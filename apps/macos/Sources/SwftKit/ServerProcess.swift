import Darwin
import Foundation
import os
import Security

/// Connection details reported once a locally spawned server passes its readiness probe.
public struct ServerEndpoint: Sendable, Equatable {
    public let httpBaseURL: URL
    public let wsBaseURL: URL
    public let port: Int
    public let bootstrapToken: String
    public let pid: Int32
    public let baseDirectory: URL
    public let environment: ExecutionEnvironmentDescriptor

    public init(
        httpBaseURL: URL,
        wsBaseURL: URL,
        port: Int,
        bootstrapToken: String,
        pid: Int32,
        baseDirectory: URL,
        environment: ExecutionEnvironmentDescriptor
    ) {
        self.httpBaseURL = httpBaseURL
        self.wsBaseURL = wsBaseURL
        self.port = port
        self.bootstrapToken = bootstrapToken
        self.pid = pid
        self.baseDirectory = baseDirectory
        self.environment = environment
    }
}

/// Configuration for launching a local child server process.
public struct ServerLaunchConfiguration: Sendable {
    public let baseDirectory: URL
    public let nodeExecutable: URL?
    public let serverEntrypoint: URL?
    public let workingDirectory: URL?
    public let port: Int?
    public let readinessTimeout: Duration
    public let extraEnvironment: [String: String]

    /// Dedicated Swft application data directory (`~/Library/Application Support/Swft`).
    /// Never points at `~/.t3` or `~/.t3/userdata`.
    public static var defaultBaseDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport.appendingPathComponent("Swft", isDirectory: true)
    }

    public init(
        baseDirectory: URL = ServerLaunchConfiguration.defaultBaseDirectory,
        nodeExecutable: URL? = nil,
        serverEntrypoint: URL? = nil,
        workingDirectory: URL? = nil,
        port: Int? = nil,
        readinessTimeout: Duration = .seconds(20),
        extraEnvironment: [String: String] = [:]
    ) {
        self.baseDirectory = baseDirectory
        self.nodeExecutable = nodeExecutable
        self.serverEntrypoint = serverEntrypoint
        self.workingDirectory = workingDirectory
        self.port = port
        self.readinessTimeout = readinessTimeout
        self.extraEnvironment = extraEnvironment
    }
}

public enum ServerProcessError: Error, Sendable, LocalizedError {
    case forbiddenBaseDirectory(String)
    case nodeNotFound
    case entrypointNotFound
    case portAllocationFailed(Int32)
    case randomTokenGenerationFailed
    case alreadyRunning
    case exitedEarly(status: Int32, output: String)
    case readinessTimedOut(url: URL, output: String)

    public var errorDescription: String? {
        switch self {
        case .forbiddenBaseDirectory(let path):
            return "Refusing to launch server against live T3 userdata directory: \(path)"
        case .nodeNotFound:
            return "Could not locate a Node.js executable."
        case .entrypointNotFound:
            return "Could not locate server entrypoint (dist/bin.mjs or src/bin.ts)."
        case .portAllocationFailed(let code):
            return "Failed to allocate a free loopback TCP port (errno \(code))."
        case .randomTokenGenerationFailed:
            return "Failed to generate cryptographically random bootstrap token."
        case .alreadyRunning:
            return "Server process is already running."
        case .exitedEarly(let status, let output):
            return "Server exited early with status \(status).\n\(output)"
        case .readinessTimedOut(let url, let output):
            return "Timed out waiting for server readiness at \(url.absoluteString).\n\(output)"
        }
    }
}

/// Manages a local child Node server process using `--bootstrap-fd 0` (`DesktopBackendBootstrap`).
/// Terminates only the exact PID it spawned; never kills processes by name or pattern.
public actor ServerProcess {
    private struct DesktopBootstrapPayload: Encodable {
        let mode: String = "desktop"
        let noBrowser: Bool = true
        let port: Int
        let t3Home: String
        let host: String = "127.0.0.1"
        let desktopBootstrapToken: String
        let tailscaleServeEnabled: Bool = false
        let tailscaleServePort: Int = 443
    }

    private final class OutputRingBuffer: Sendable {
        private let maxBytes: Int
        private let state = OSAllocatedUnfairLock<Data>(initialState: Data())

        init(maxBytes: Int = 65_536) {
            self.maxBytes = maxBytes
        }

        func append(_ chunk: Data) {
            guard !chunk.isEmpty else { return }
            state.withLock { buffer in
                buffer.append(chunk)
                if buffer.count > maxBytes {
                    buffer.removeFirst(buffer.count - maxBytes)
                }
            }
        }

        func snapshotString() -> String {
            state.withLock { buffer in
                String(data: buffer, encoding: .utf8) ?? ""
            }
        }
    }

    private let configuration: ServerLaunchConfiguration
    private let session: URLSession
    private let trackedPID = OSAllocatedUnfairLock<Int32?>(initialState: nil)
    private var process: Process?
    private var spawnedPID: Int32?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var outputBuffer: OutputRingBuffer?
    private var activeEndpoint: ServerEndpoint?

    public init(
        configuration: ServerLaunchConfiguration = ServerLaunchConfiguration(),
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
    }

    deinit {
        if let pid = trackedPID.withLock({ $0 }), pid > 0 {
            _ = Darwin.kill(pid, SIGTERM)
        }
    }

    public var endpoint: ServerEndpoint? { activeEndpoint }
    public var pid: Int32? { spawnedPID }
    public var isRunning: Bool { process?.isRunning == true }

    public var recentOutput: String {
        outputBuffer?.snapshotString() ?? ""
    }

    /// Launches the child server, feeds its bootstrap payload on stdin, and waits for readiness.
    public func start() async throws -> ServerEndpoint {
        guard process == nil else {
            throw ServerProcessError.alreadyRunning
        }

        try Self.validateBaseDirectory(configuration.baseDirectory)
        try FileManager.default.createDirectory(
            at: configuration.baseDirectory,
            withIntermediateDirectories: true
        )

        let nodeURL = try resolveNodeExecutable()
        let entrypointURL = try resolveServerEntrypoint()
        let port = try configuration.port ?? Self.allocateLoopbackPort()
        let bootstrapToken = try Self.generateRandomHexToken(byteCount: 32)

        let child = Process()
        child.executableURL = nodeURL
        child.arguments = [entrypointURL.path, "--bootstrap-fd", "0"]
        if let workingDirectory = configuration.workingDirectory {
            child.currentDirectoryURL = workingDirectory
        } else {
            child.currentDirectoryURL = entrypointURL.deletingLastPathComponent()
        }

        // Strip ambient T3CODE_* env vars so a developer's live T3 Code session never overrides bootstrap.
        var env = ProcessInfo.processInfo.environment.filter { key, _ in
            !key.hasPrefix("T3CODE_") && key != "VITE_DEV_SERVER_URL"
        }
        for (key, value) in configuration.extraEnvironment {
            env[key] = value
        }
        child.environment = env

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        let ring = OutputRingBuffer()

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                ring.append(data)
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                ring.append(data)
            }
        }

        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = stderr

        try child.run()
        let pid = child.processIdentifier

        self.process = child
        self.spawnedPID = pid
        self.trackedPID.withLock { $0 = pid }
        self.stdoutPipe = stdout
        self.stderrPipe = stderr
        self.outputBuffer = ring

        do {
            let payload = DesktopBootstrapPayload(
                port: port,
                t3Home: configuration.baseDirectory.path,
                desktopBootstrapToken: bootstrapToken
            )
            var payloadData = try SwftJSON.makeEncoder().encode(payload)
            payloadData.append(0x0A) // '\n' required by readline bootstrap reader
            try stdin.fileHandleForWriting.write(contentsOf: payloadData)
            try stdin.fileHandleForWriting.close()
        } catch {
            await stop()
            throw error
        }

        guard let httpBaseURL = URL(string: "http://127.0.0.1:\(port)"),
              let wsBaseURL = URL(string: "ws://127.0.0.1:\(port)")
        else {
            await stop()
            throw RPCError.protocolError("Failed to form loopback server URLs for port \(port)")
        }

        do {
            let descriptor = try await waitForReadiness(
                httpBaseURL: httpBaseURL,
                child: child,
                ring: ring
            )
            let endpoint = ServerEndpoint(
                httpBaseURL: httpBaseURL,
                wsBaseURL: wsBaseURL,
                port: port,
                bootstrapToken: bootstrapToken,
                pid: pid,
                baseDirectory: configuration.baseDirectory,
                environment: descriptor
            )
            self.activeEndpoint = endpoint
            return endpoint
        } catch {
            await stop()
            throw error
        }
    }

    /// Terminates ONLY the exact PID spawned by this `ServerProcess` instance.
    public func stop(gracePeriod: Duration = .seconds(5)) async {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        if let child = process, let pid = spawnedPID, pid > 0, child.isRunning {
            _ = Darwin.kill(pid, SIGTERM)
            let deadline = ContinuousClock.now + gracePeriod
            while child.isRunning && ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
            if child.isRunning {
                _ = Darwin.kill(pid, SIGKILL)
                let killDeadline = ContinuousClock.now + .seconds(2)
                while child.isRunning && ContinuousClock.now < killDeadline {
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        }

        stdoutPipe = nil
        stderrPipe = nil
        process = nil
        spawnedPID = nil
        trackedPID.withLock { $0 = nil }
        activeEndpoint = nil
    }

    // MARK: - Validation & Discovery

    /// Guardrail preventing accidental launch against the user's live `~/.t3` / `~/.t3/userdata`.
    public static func validateBaseDirectory(_ url: URL) throws {
        let candidate = url.standardizedFileURL.resolvingSymlinksInPath().path
        let home = FileManager.default.homeDirectoryForCurrentUser
            .standardizedFileURL.resolvingSymlinksInPath().path
        let forbiddenRoot = (home as NSString).appendingPathComponent(".t3")
        if candidate == forbiddenRoot || candidate.hasPrefix(forbiddenRoot + "/") {
            throw ServerProcessError.forbiddenBaseDirectory(candidate)
        }
    }

    private func waitForReadiness(
        httpBaseURL: URL,
        child: Process,
        ring: OutputRingBuffer
    ) async throws -> ExecutionEnvironmentDescriptor {
        let authClient = AuthClient(session: session)
        let readinessURL = httpBaseURL.appendingPathComponent(".well-known/t3/environment")
        let deadline = ContinuousClock.now + configuration.readinessTimeout

        while ContinuousClock.now < deadline {
            if !child.isRunning {
                throw ServerProcessError.exitedEarly(
                    status: child.terminationStatus,
                    output: ring.snapshotString()
                )
            }
            if let descriptor = try? await authClient.discoverEnvironment(baseURL: httpBaseURL) {
                return descriptor
            }
            try await Task.sleep(for: .milliseconds(150))
        }

        throw ServerProcessError.readinessTimedOut(
            url: readinessURL,
            output: ring.snapshotString()
        )
    }

    private func resolveNodeExecutable() throws -> URL {
        let fm = FileManager.default
        if let explicit = configuration.nodeExecutable, fm.isExecutableFile(atPath: explicit.path) {
            return explicit
        }
        if let envPath = ProcessInfo.processInfo.environment["SWFT_NODE_PATH"],
           fm.isExecutableFile(atPath: envPath)
        {
            return URL(fileURLWithPath: envPath)
        }

        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        for dir in pathEntries {
            let candidate = (dir as NSString).appendingPathComponent("node")
            if fm.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }

        let fallbacks = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
        ]
        for path in fallbacks where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        // Check vite-plus managed node installations under ~/.local/node/*/bin/node.
        let localNodeRoot = fm.homeDirectoryForCurrentUser.appendingPathComponent(".local/node", isDirectory: true)
        if let entries = try? fm.contentsOfDirectory(at: localNodeRoot, includingPropertiesForKeys: nil) {
            for entry in entries.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                let candidate = entry.appendingPathComponent("bin/node")
                if fm.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        throw ServerProcessError.nodeNotFound
    }

    private func resolveServerEntrypoint() throws -> URL {
        let fm = FileManager.default
        if let explicit = configuration.serverEntrypoint, fm.fileExists(atPath: explicit.path) {
            return explicit
        }
        if let envEntry = ProcessInfo.processInfo.environment["SWFT_SERVER_ENTRY"],
           fm.fileExists(atPath: envEntry)
        {
            return URL(fileURLWithPath: envEntry)
        }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("server/bin.mjs"),
           fm.fileExists(atPath: bundled.path)
        {
            return bundled
        }

        var searchRoots: [URL] = []
        if let cwd = configuration.workingDirectory {
            searchRoots.append(cwd)
        }
        searchRoots.append(URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true))

        for start in searchRoots {
            var current = start.standardizedFileURL
            for _ in 0..<8 {
                let distEntry = current.appendingPathComponent("apps/server/dist/bin.mjs")
                if fm.fileExists(atPath: distEntry.path) {
                    return distEntry
                }
                let srcEntry = current.appendingPathComponent("apps/server/src/bin.ts")
                if fm.fileExists(atPath: srcEntry.path) {
                    return srcEntry
                }
                let parent = current.deletingLastPathComponent()
                if parent.path == current.path { break }
                current = parent
            }
        }

        throw ServerProcessError.entrypointNotFound
    }

    private static func allocateLoopbackPort() throws -> Int {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw ServerProcessError.portAllocationFailed(errno)
        }
        defer { _ = Darwin.close(fd) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw ServerProcessError.portAllocationFailed(errno)
        }

        var boundAddr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.getsockname(fd, sockPtr, &len)
            }
        }
        guard nameResult == 0 else {
            throw ServerProcessError.portAllocationFailed(errno)
        }
        return Int(UInt16(bigEndian: boundAddr.sin_port))
    }

    private static func generateRandomHexToken(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        guard status == errSecSuccess else {
            throw ServerProcessError.randomTokenGenerationFailed
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
