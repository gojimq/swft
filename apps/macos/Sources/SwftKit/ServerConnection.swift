import Foundation

/// Lifecycle state of a `ServerConnection`.
public enum ConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected(ExecutionEnvironmentDescriptor)
    case reconnecting(attempt: Int, reason: String)
    case failed(String)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    public var environment: ExecutionEnvironmentDescriptor? {
        if case .connected(let descriptor) = self { return descriptor }
        return nil
    }
}

/// Exponential backoff configuration for automatic WebSocket reconnection.
public struct ReconnectPolicy: Sendable, Equatable {
    public let initialDelay: Duration
    public let maxDelay: Duration
    public let multiplier: Double
    public let jitterRatio: Double

    public static let `default` = ReconnectPolicy(
        initialDelay: .milliseconds(500),
        maxDelay: .seconds(15),
        multiplier: 2.0,
        jitterRatio: 0.2
    )

    public init(
        initialDelay: Duration = .milliseconds(500),
        maxDelay: Duration = .seconds(15),
        multiplier: Double = 2.0,
        jitterRatio: Double = 0.2
    ) {
        self.initialDelay = initialDelay
        self.maxDelay = maxDelay
        self.multiplier = multiplier
        self.jitterRatio = jitterRatio
    }

    public func delay(forAttempt attempt: Int) -> Duration {
        let exponent = max(0, attempt - 1)
        let baseSeconds = initialDelay.timeInterval * pow(multiplier, Double(exponent))
        let capped = min(baseSeconds, maxDelay.timeInterval)
        let jitter = capped * jitterRatio
        let randomized = jitter > 0
            ? max(0.05, capped + Double.random(in: -jitter...jitter))
            : capped
        return .milliseconds(Int64((randomized * 1_000).rounded()))
    }
}

private extension Duration {
    var timeInterval: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + (Double(attoseconds) / 1e18)
    }
}

/// Multiplexed Effect RPC WebSocket client for a single T3-derived server environment.
public actor ServerConnection {
    public let httpBaseURL: URL
    public let clientLabel: String
    public let clientIdentity: ClientIdentity

    private let credential: AuthCredential
    private let authClient: AuthClient
    let session: URLSession
    private let reconnectPolicy: ReconnectPolicy
    private let pingInterval: Duration
    private let livenessTimeout: Duration

    private var cachedAccessToken: String?
    private var environmentDescriptor: ExecutionEnvironmentDescriptor?
    private var currentState: ConnectionState = .disconnected
    private var stateObservers: [UUID: AsyncStream<ConnectionState>.Continuation] = [:]

    private var shouldStayConnected = false
    private var connectionGeneration: UInt64 = 0
    private var socketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var lastInboundActivity: ContinuousClock.Instant = .now
    private var reassembler = SocketFrameReassembler()

    private var nextRequestId: Int = 1
    private var pendingUnary: [String: PendingUnaryHandler] = [:]
    private var activeStreams: [String: ActiveStreamHandler] = [:]

    private struct PendingUnaryHandler: Sendable {
        let tag: String
        let handleExit: @Sendable (Data) -> Void
        let fail: @Sendable (any Error) -> Void
    }

    private struct ActiveStreamHandler: Sendable {
        let tag: String
        let handleChunk: @Sendable (Data) -> Void
        let handleExit: @Sendable (Data) -> Void
        let fail: @Sendable (any Error) -> Void
    }

    public init(
        httpBaseURL: URL,
        credential: AuthCredential,
        clientLabel: String = "Swft",
        clientIdentity: ClientIdentity = .current,
        reconnectPolicy: ReconnectPolicy = .default,
        pingInterval: Duration = .seconds(5),
        livenessTimeout: Duration = .seconds(15),
        session: URLSession = .shared
    ) {
        self.httpBaseURL = httpBaseURL
        self.credential = credential
        self.clientLabel = clientLabel
        self.clientIdentity = clientIdentity
        self.reconnectPolicy = reconnectPolicy
        self.pingInterval = pingInterval
        self.livenessTimeout = livenessTimeout
        self.session = session
        self.authClient = AuthClient(session: session)
    }

    public var state: ConnectionState { currentState }
    public var environment: ExecutionEnvironmentDescriptor? { environmentDescriptor }

    /// Returns the active bearer access token for HTTP endpoints (e.g. minting pairing invites),
    /// reusing the session's cached token so desktop-bootstrap sessions are never replaced mid-flight.
    public func currentAccessToken() async throws -> String {
        if let existing = cachedAccessToken {
            return existing
        }
        let token = try await authClient.resolveAccessToken(
            baseURL: httpBaseURL,
            credential: credential,
            clientLabel: clientLabel,
            clientIdentity: clientIdentity
        )
        cachedAccessToken = token
        return token
    }

    /// Mints a short-lived ticket for media routes such as `/api/device-hub/...`.
    public func mintMediaTicket() async throws -> AuthWebSocketTicketResult {
        if let existingToken = cachedAccessToken {
            do {
                return try await authClient.mintMediaTicket(
                    baseURL: httpBaseURL,
                    accessToken: existingToken
                )
            } catch RPCError.authenticationFailed {
                if case .bearerToken = credential {
                    throw RPCError.authenticationFailed("Bearer access token rejected")
                }
                cachedAccessToken = nil
            }
        }
        let token = try await authClient.resolveAccessToken(
            baseURL: httpBaseURL,
            credential: credential,
            clientLabel: clientLabel
        )
        cachedAccessToken = token
        return try await authClient.mintMediaTicket(baseURL: httpBaseURL, accessToken: token)
    }

    /// Stream of connection state updates; yields the current state immediately on subscribe.
    public func stateUpdates() -> AsyncStream<ConnectionState> {
        let id = UUID()
        let initial = currentState
        return AsyncStream { continuation in
            self.stateObservers[id] = continuation
            continuation.yield(initial)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeStateObserver(id) }
            }
        }
    }

    /// Discovers the environment, authenticates, and opens the WebSocket connection.
    @discardableResult
    public func connect() async throws -> ExecutionEnvironmentDescriptor {
        if case .connected(let descriptor) = currentState, socketTask != nil {
            return descriptor
        }
        shouldStayConnected = true
        reconnectTask?.cancel()
        reconnectTask = nil
        transition(to: .connecting)

        do {
            let descriptor = try await openAuthenticatedSocket()
            return descriptor
        } catch {
            transition(to: .failed(error.localizedDescription))
            throw error
        }
    }

    /// Gracefully closes the WebSocket and disables automatic reconnection.
    public func disconnect() async {
        shouldStayConnected = false
        reconnectTask?.cancel()
        reconnectTask = nil
        if let socket = socketTask {
            try? await sendControlMessage(.eof, on: socket)
            socket.cancel(with: .normalClosure, reason: nil)
        }
        teardownActiveSocket(failWith: RPCError.disconnected)
        transition(to: .disconnected)
    }

    /// Suspends the socket and reconnect timers when the host app enters the background.
    public func suspend() async {
        await disconnect()
    }

    /// Resumes a suspended or disconnected session, immediately attempting a connection and
    /// falling back to exponential backoff on transient errors (such as Wi-Fi or VPN waking up).
    public func resume() async {
        if case .connected = currentState, socketTask != nil {
            return
        }
        if case .connecting = currentState {
            return
        }
        shouldStayConnected = true
        reconnectTask?.cancel()
        reconnectTask = nil
        transition(to: .connecting)

        do {
            _ = try await openAuthenticatedSocket()
        } catch {
            if case RPCError.authenticationFailed = error {
                transition(to: .failed(error.localizedDescription))
                return
            }
            if case RPCError.incompatibleProtocol = error {
                transition(to: .failed(error.localizedDescription))
                return
            }
            if shouldStayConnected {
                startReconnectLoop(initialReason: error.localizedDescription)
            }
        }
    }

    /// Cancels any backoff delay and attempts an immediate reconnect when network reachability changes.
    public func reconnectNow() async {
        guard shouldStayConnected else { return }
        if case .connected = currentState, socketTask != nil {
            return
        }
        await resume()
    }

    /// Executes a unary Effect RPC call and decodes its `Exit.Success.value`.
    public func call<Payload: Encodable & Sendable, Response: Decodable & Sendable>(
        tag: String,
        payload: Payload
    ) async throws -> Response {
        guard let socket = socketTask, currentState.isConnected else {
            throw RPCError.disconnected
        }
        if Task.isCancelled {
            throw RPCError.cancelled
        }

        let requestId = allocateRequestID()
        let encodedData = try SwftJSON.makeEncoder().encode(
            RPCRequestEnvelope(id: requestId, tag: tag, payload: payload)
        )
        guard let text = String(data: encodedData, encoding: .utf8) else {
            throw RPCError.protocolError("Failed to encode RPC request as UTF-8")
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Response, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: RPCError.cancelled)
                    return
                }
                pendingUnary[requestId] = PendingUnaryHandler(
                    tag: tag,
                    handleExit: { data in
                        do {
                            let envelope = try SwftJSON.makeDecoder().decode(
                                RPCExitEnvelope<Response>.self,
                                from: data
                            )
                            switch envelope.exit {
                            case .success(let value):
                                continuation.resume(returning: value)
                            case .failure(let causes):
                                continuation.resume(
                                    throwing: RPCError.remoteFailure(tag: tag, causes: causes)
                                )
                            }
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    },
                    fail: { error in
                        continuation.resume(throwing: error)
                    }
                )

                Task {
                    do {
                        try await socket.send(.string(text))
                    } catch {
                        self.failUnary(id: requestId, error: error)
                    }
                }
            }
        } onCancel: {
            Task { await self.cancelUnary(id: requestId) }
        }
    }

    /// Executes a unary Effect RPC call whose `Exit.Success` carries no value.
    public func callVoid<Payload: Encodable & Sendable>(
        tag: String,
        payload: Payload
    ) async throws {
        let _: VoidResponse = try await call(tag: tag, payload: payload)
    }

    /// Opens a streaming Effect RPC subscription with automatic per-chunk `Ack` flow control
    /// and `Interrupt` on consumer cancellation.
    public nonisolated func subscribe<Payload: Encodable & Sendable, Item: Decodable & Sendable>(
        tag: String,
        payload: Payload
    ) -> AsyncThrowingStream<Item, any Error> {
        AsyncThrowingStream { continuation in
            let setupTask = Task {
                await self.startStream(tag: tag, payload: payload, continuation: continuation)
            }
            continuation.onTermination = { _ in
                setupTask.cancel()
            }
        }
    }

    // MARK: - Internal Stream & Request Handling

    private func startStream<Payload: Encodable & Sendable, Item: Decodable & Sendable>(
        tag: String,
        payload: Payload,
        continuation: AsyncThrowingStream<Item, any Error>.Continuation
    ) {
        if Task.isCancelled {
            continuation.finish()
            return
        }
        guard let socket = socketTask, currentState.isConnected else {
            continuation.finish(throwing: RPCError.disconnected)
            return
        }

        let requestId = allocateRequestID()
        let text: String
        do {
            let data = try SwftJSON.makeEncoder().encode(
                RPCRequestEnvelope(id: requestId, tag: tag, payload: payload)
            )
            guard let encoded = String(data: data, encoding: .utf8) else {
                continuation.finish(throwing: RPCError.protocolError("Failed to encode stream request"))
                return
            }
            text = encoded
        } catch {
            continuation.finish(throwing: error)
            return
        }

        activeStreams[requestId] = ActiveStreamHandler(
            tag: tag,
            handleChunk: { data in
                do {
                    let envelope = try SwftJSON.makeDecoder().decode(
                        RPCChunkEnvelope<Item>.self,
                        from: data
                    )
                    for item in envelope.values {
                        continuation.yield(item)
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            },
            handleExit: { data in
                do {
                    let envelope = try SwftJSON.makeDecoder().decode(
                        RPCExitEnvelope<VoidResponse>.self,
                        from: data
                    )
                    switch envelope.exit {
                    case .success:
                        continuation.finish()
                    case .failure(let causes):
                        continuation.finish(throwing: RPCError.remoteFailure(tag: tag, causes: causes))
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            },
            fail: { error in
                continuation.finish(throwing: error)
            }
        )

        continuation.onTermination = { [weak self] _ in
            Task { await self?.cancelStream(id: requestId) }
        }

        Task {
            do {
                try await socket.send(.string(text))
            } catch {
                self.failStream(id: requestId, error: error)
            }
        }
    }

    private func openAuthenticatedSocket() async throws -> ExecutionEnvironmentDescriptor {
        let descriptor = try await authClient.discoverEnvironment(baseURL: httpBaseURL)
        environmentDescriptor = descriptor

        let ticket = try await mintWebSocketTicketWithRefresh()
        let wsURL = try authClient.webSocketURL(
            httpBaseURL: httpBaseURL,
            ticket: ticket.ticket,
            clientIdentity: clientIdentity
        )

        teardownActiveSocket(failWith: RPCError.disconnected)

        connectionGeneration &+= 1
        let generation = connectionGeneration
        let socket = session.webSocketTask(with: wsURL)
        socket.maximumMessageSize = 64 * 1024 * 1024
        socket.resume()

        // Confirm the HTTP 101 WebSocket upgrade succeeded before reporting connected.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            socket.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        socketTask = socket
        reassembler.reset()
        lastInboundActivity = .now
        transition(to: .connected(descriptor))

        receiveTask = Task { [weak self] in
            await self?.runReceiveLoop(socket: socket, generation: generation)
        }
        heartbeatTask = Task { [weak self] in
            await self?.runHeartbeatLoop(socket: socket, generation: generation)
        }
        return descriptor
    }

    private func mintWebSocketTicketWithRefresh() async throws -> AuthWebSocketTicketResult {
        if let existingToken = cachedAccessToken {
            do {
                return try await authClient.mintWebSocketTicket(
                    baseURL: httpBaseURL,
                    accessToken: existingToken
                )
            } catch RPCError.authenticationFailed {
                if case .bearerToken = credential {
                    throw RPCError.authenticationFailed("Bearer access token rejected")
                }
                cachedAccessToken = nil
            }
        }

        let token = try await authClient.resolveAccessToken(
            baseURL: httpBaseURL,
            credential: credential,
            clientLabel: clientLabel,
            clientIdentity: clientIdentity
        )
        cachedAccessToken = token
        return try await authClient.mintWebSocketTicket(baseURL: httpBaseURL, accessToken: token)
    }

    private func runReceiveLoop(socket: URLSessionWebSocketTask, generation: UInt64) async {
        while !Task.isCancelled && connectionGeneration == generation {
            do {
                let message = try await socket.receive()
                guard connectionGeneration == generation else { return }
                lastInboundActivity = .now

                let text: String
                switch message {
                case .string(let string):
                    text = string
                case .data(let data):
                    guard let decoded = String(data: data, encoding: .utf8) else { continue }
                    text = decoded
                @unknown default:
                    continue
                }

                guard let completeFrame = reassembler.feed(text) else {
                    continue
                }
                await handleInboundFrame(completeFrame, socket: socket)
            } catch {
                guard connectionGeneration == generation else { return }
                handleSocketDropped(reason: error.localizedDescription, generation: generation)
                return
            }
        }
    }

    private func handleInboundFrame(_ frame: String, socket: URLSessionWebSocketTask) async {
        guard let data = frame.data(using: .utf8) else { return }
        guard let header = try? SwftJSON.makeDecoder().decode(RPCServerFrameHeader.self, from: data) else {
            return
        }

        switch header._tag {
        case "Pong":
            // Unsolicited server heartbeats and Ping replies both refresh lastInboundActivity.
            return

        case "Chunk":
            guard let requestId = header.requestId?.rawValue,
                  let stream = activeStreams[requestId]
            else { return }
            stream.handleChunk(data)
            // Server blocks on a backpressure Latch until Ack arrives for this requestId.
            try? await sendControlMessage(.ack(requestId: requestId), on: socket)

        case "Exit":
            guard let requestId = header.requestId?.rawValue else { return }
            if let unary = pendingUnary.removeValue(forKey: requestId) {
                unary.handleExit(data)
            } else if let stream = activeStreams.removeValue(forKey: requestId) {
                stream.handleExit(data)
            }

        case "Defect":
            let message = try? SwftJSON.makeDecoder().decode(RPCServerMessage.self, from: data)
            let defect: JSONValue
            if case .defect(let value) = message {
                defect = value
            } else {
                defect = .string("Server protocol defect")
            }
            handleSocketDropped(
                reason: RPCError.remoteDefect(defect).localizedDescription,
                generation: connectionGeneration
            )

        default:
            return
        }
    }

    private func runHeartbeatLoop(socket: URLSessionWebSocketTask, generation: UInt64) async {
        while !Task.isCancelled && connectionGeneration == generation {
            do {
                try await Task.sleep(for: pingInterval)
            } catch {
                return
            }
            guard connectionGeneration == generation else { return }

            if ContinuousClock.now - lastInboundActivity > livenessTimeout {
                socket.cancel(with: .goingAway, reason: nil)
                handleSocketDropped(reason: "Heartbeat liveness timeout", generation: generation)
                return
            }

            do {
                try await sendControlMessage(.ping, on: socket)
            } catch {
                guard connectionGeneration == generation else { return }
                handleSocketDropped(reason: error.localizedDescription, generation: generation)
                return
            }
        }
    }

    private func handleSocketDropped(reason: String, generation: UInt64) {
        guard connectionGeneration == generation else { return }
        teardownActiveSocket(failWith: RPCError.disconnected)
        guard shouldStayConnected else {
            transition(to: .disconnected)
            return
        }
        startReconnectLoop(initialReason: reason)
    }

    private func startReconnectLoop(initialReason: String) {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            var attempt = 1
            var reason = initialReason
            while !Task.isCancelled {
                guard await self.shouldStayConnected else { return }
                await self.transition(to: .reconnecting(attempt: attempt, reason: reason))
                let delay = self.reconnectPolicy.delay(forAttempt: attempt)
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
                guard await self.shouldStayConnected else { return }
                do {
                    _ = try await self.openAuthenticatedSocket()
                    return
                } catch {
                    if case RPCError.authenticationFailed = error {
                        await self.transition(to: .failed(error.localizedDescription))
                        return
                    }
                    if case RPCError.incompatibleProtocol = error {
                        await self.transition(to: .failed(error.localizedDescription))
                        return
                    }
                    reason = error.localizedDescription
                    attempt += 1
                }
            }
        }
    }

    private func teardownActiveSocket(failWith error: any Error) {
        connectionGeneration &+= 1
        receiveTask?.cancel()
        receiveTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        socketTask?.cancel(with: .goingAway, reason: nil)
        socketTask = nil
        reassembler.reset()

        let unary = pendingUnary
        pendingUnary.removeAll()
        for handler in unary.values {
            handler.fail(error)
        }

        let streams = activeStreams
        activeStreams.removeAll()
        for handler in streams.values {
            handler.fail(error)
        }
    }

    private func sendControlMessage(
        _ message: RPCClientMessage,
        on socket: URLSessionWebSocketTask
    ) async throws {
        let data = try SwftJSON.makeEncoder().encode(message)
        guard let text = String(data: data, encoding: .utf8) else { return }
        try await socket.send(.string(text))
    }

    private func allocateRequestID() -> String {
        let id = String(nextRequestId)
        nextRequestId += 1
        return id
    }

    private func failUnary(id: String, error: any Error) {
        if let handler = pendingUnary.removeValue(forKey: id) {
            handler.fail(error)
        }
    }

    private func cancelUnary(id: String) {
        if let handler = pendingUnary.removeValue(forKey: id) {
            handler.fail(RPCError.cancelled)
            if let socket = socketTask {
                Task { try? await self.sendControlMessage(.interrupt(requestId: id), on: socket) }
            }
        }
    }

    private func failStream(id: String, error: any Error) {
        if let handler = activeStreams.removeValue(forKey: id) {
            handler.fail(error)
        }
    }

    private func cancelStream(id: String) {
        guard activeStreams.removeValue(forKey: id) != nil else { return }
        if let socket = socketTask {
            Task { try? await self.sendControlMessage(.interrupt(requestId: id), on: socket) }
        }
    }

    private func transition(to newState: ConnectionState) {
        guard currentState != newState else { return }
        currentState = newState
        for continuation in stateObservers.values {
            continuation.yield(newState)
        }
    }

    private func removeStateObserver(_ id: UUID) {
        stateObservers.removeValue(forKey: id)
    }
}
