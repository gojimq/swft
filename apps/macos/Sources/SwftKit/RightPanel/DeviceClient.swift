import Foundation

// MARK: - Device RPC Method Tags (`packages/contracts/src/rpc.ts`)

public extension RPCMethod {
    static let deviceList = "device.list"
    static let deviceConfigure = "device.configure"
    static let deviceOpen = "device.open"
    static let deviceClose = "device.close"
    static let deviceShutdown = "device.shutdown"
    static let deviceDetail = "device.detail"
    static let deviceAction = "device.action"
    static let subscribeDeviceState = "subscribeDeviceState"
}

// MARK: - Device Wire Models (`packages/contracts/src/device.ts`)

public enum DevicePlatform: String, Codable, Sendable, Hashable, CaseIterable {
    case ios
    case android

    public var displayName: String {
        switch self {
        case .ios: "iOS"
        case .android: "Android"
        }
    }

    public var symbolName: String {
        switch self {
        case .ios: "iphone"
        case .android: "smartphone"
        }
    }
}

public enum DeviceHostStatus: Sendable, Hashable, Codable {
    case disabled
    case idle
    case installing
    case starting
    case ready
    case failed
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .disabled: "disabled"
        case .idle: "idle"
        case .installing: "installing"
        case .starting: "starting"
        case .ready: "ready"
        case .failed: "failed"
        case .unknown(let value): value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "disabled": self = .disabled
        case "idle": self = .idle
        case "installing": self = .installing
        case "starting": self = .starting
        case "ready": self = .ready
        case "failed": self = .failed
        default: self = .unknown(rawValue)
        }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        self.init(rawValue: try c.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

public struct DeviceSummary: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let hostId: String
    public let id: String
    public let platform: DevicePlatform
    public let name: String
    public let version: String
    public let booted: Bool
    public let physical: Bool

    public var compositeKey: String { "\(hostId)::\(id)" }

    public init(
        hostId: String = "local",
        id: String,
        platform: DevicePlatform,
        name: String,
        version: String,
        booted: Bool,
        physical: Bool = false
    ) {
        self.hostId = hostId
        self.id = id
        self.platform = platform
        self.name = name
        self.version = version
        self.booted = booted
        self.physical = physical
    }
}

public struct DevicePlatformAvailability: Codable, Sendable, Equatable, Hashable {
    public let platform: DevicePlatform
    public let available: Bool
    public let reason: String?

    public init(platform: DevicePlatform, available: Bool, reason: String? = nil) {
        self.platform = platform
        self.available = available
        self.reason = reason
    }
}

public struct DeviceHostSummary: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let kind: String
    public let platforms: [DevicePlatformAvailability]
    public let hubInstalled: Bool
    public let agentDeviceInstalled: Bool

    public init(
        id: String,
        label: String,
        kind: String = "local",
        platforms: [DevicePlatformAvailability] = [],
        hubInstalled: Bool = false,
        agentDeviceInstalled: Bool = false
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.platforms = platforms
        self.hubInstalled = hubInstalled
        self.agentDeviceInstalled = agentDeviceInstalled
    }
}

public struct DeviceHostStatusEntry: Codable, Sendable, Equatable {
    public let status: DeviceHostStatus
    public let detail: String?

    public init(status: DeviceHostStatus, detail: String? = nil) {
        self.status = status
        self.detail = detail
    }
}

public struct DeviceSession: Codable, Sendable, Equatable, Identifiable {
    public let threadId: String
    public let hostId: String
    public let deviceId: String
    public let platform: DevicePlatform
    public let openedAt: String

    public var id: String { "\(threadId):\(hostId):\(deviceId)" }

    public init(
        threadId: String,
        hostId: String = "local",
        deviceId: String,
        platform: DevicePlatform,
        openedAt: String = ""
    ) {
        self.threadId = threadId
        self.hostId = hostId
        self.deviceId = deviceId
        self.platform = platform
        self.openedAt = openedAt
    }
}

public struct BootingDeviceSummary: Codable, Sendable, Equatable, Identifiable {
    public let hostId: String
    public let id: String
    public let platform: DevicePlatform
    public let name: String
    public let version: String
    public let booted: Bool
    public let physical: Bool
    public let threadId: String

    public init(
        hostId: String = "local",
        id: String,
        platform: DevicePlatform,
        name: String,
        version: String,
        booted: Bool = false,
        physical: Bool = false,
        threadId: String
    ) {
        self.hostId = hostId
        self.id = id
        self.platform = platform
        self.name = name
        self.version = version
        self.booted = booted
        self.physical = physical
        self.threadId = threadId
    }
}

public struct DeviceServiceState: Codable, Sendable, Equatable {
    public let hostStatus: DeviceHostStatus
    public let hostStatusDetail: String?
    public let hostStatuses: [String: DeviceHostStatusEntry]
    public let hosts: [DeviceHostSummary]
    public let devices: [DeviceSummary]
    public let sessions: [DeviceSession]
    public let bootingDevices: [BootingDeviceSummary]
    public let onboardingCompleted: Bool
    public let agentAccessEnabled: Bool
    public let hubBasePath: String
    public let revision: Int

    private enum CodingKeys: String, CodingKey {
        case hostStatus, hostStatusDetail, hostStatuses, hosts, easHosts, simlockHosts
        case devices, sessions, bootingDevices, onboardingCompleted, agentAccessEnabled
        case hubBasePath, revision
    }

    public init(
        hostStatus: DeviceHostStatus = .idle,
        hostStatusDetail: String? = nil,
        hostStatuses: [String: DeviceHostStatusEntry] = [:],
        hosts: [DeviceHostSummary] = [],
        devices: [DeviceSummary] = [],
        sessions: [DeviceSession] = [],
        bootingDevices: [BootingDeviceSummary] = [],
        onboardingCompleted: Bool = true,
        agentAccessEnabled: Bool = true,
        hubBasePath: String = "/api/device-hub",
        revision: Int = 0
    ) {
        self.hostStatus = hostStatus
        self.hostStatusDetail = hostStatusDetail
        self.hostStatuses = hostStatuses
        self.hosts = hosts
        self.devices = devices
        self.sessions = sessions
        self.bootingDevices = bootingDevices
        self.onboardingCompleted = onboardingCompleted
        self.agentAccessEnabled = agentAccessEnabled
        self.hubBasePath = hubBasePath
        self.revision = revision
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.hostStatus = try c.decode(DeviceHostStatus.self, forKey: .hostStatus)
        self.hostStatusDetail = try c.decodeIfPresent(String.self, forKey: .hostStatusDetail)
        self.hostStatuses = try c.decodeIfPresent([String: DeviceHostStatusEntry].self, forKey: .hostStatuses) ?? [:]
        let baseHosts = try c.decodeIfPresent([DeviceHostSummary].self, forKey: .hosts) ?? []
        let easHosts = try c.decodeIfPresent([DeviceHostSummary].self, forKey: .easHosts) ?? []
        let simlockHosts = try c.decodeIfPresent([DeviceHostSummary].self, forKey: .simlockHosts) ?? []
        self.hosts = baseHosts + easHosts + simlockHosts
        self.devices = try c.decodeIfPresent([DeviceSummary].self, forKey: .devices) ?? []
        self.sessions = try c.decodeIfPresent([DeviceSession].self, forKey: .sessions) ?? []
        self.bootingDevices = try c.decodeIfPresent([BootingDeviceSummary].self, forKey: .bootingDevices) ?? []
        self.onboardingCompleted = try c.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        self.agentAccessEnabled = try c.decodeIfPresent(Bool.self, forKey: .agentAccessEnabled) ?? false
        self.hubBasePath = try c.decodeIfPresent(String.self, forKey: .hubBasePath) ?? "/api/device-hub"
        self.revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 0
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(hostStatus, forKey: .hostStatus)
        try c.encodeIfPresent(hostStatusDetail, forKey: .hostStatusDetail)
        try c.encode(hostStatuses, forKey: .hostStatuses)
        try c.encode(hosts.filter { $0.kind == "local" || $0.kind == "ssh" }, forKey: .hosts)
        let eas = hosts.filter { $0.kind == "eas" }
        if !eas.isEmpty { try c.encode(eas, forKey: .easHosts) }
        let simlock = hosts.filter { $0.kind == "simlock" }
        if !simlock.isEmpty { try c.encode(simlock, forKey: .simlockHosts) }
        try c.encode(devices, forKey: .devices)
        try c.encode(sessions, forKey: .sessions)
        try c.encode(bootingDevices, forKey: .bootingDevices)
        try c.encode(onboardingCompleted, forKey: .onboardingCompleted)
        try c.encode(agentAccessEnabled, forKey: .agentAccessEnabled)
        try c.encode(hubBasePath, forKey: .hubBasePath)
        try c.encode(revision, forKey: .revision)
    }
}

public struct DeviceListInput: Encodable, Sendable, Equatable {
    public let inspectOnly: Bool?
    public let retryHostId: String?

    public init(inspectOnly: Bool? = nil, retryHostId: String? = nil) {
        self.inspectOnly = inspectOnly
        self.retryHostId = retryHostId
    }
}

public struct DeviceConfigureInput: Encodable, Sendable, Equatable {
    public let enabled: Bool?
    public let agentAccessEnabled: Bool?
    public let onboardingCompleted: Bool?

    public init(
        enabled: Bool? = nil,
        agentAccessEnabled: Bool? = nil,
        onboardingCompleted: Bool? = nil
    ) {
        self.enabled = enabled
        self.agentAccessEnabled = agentAccessEnabled
        self.onboardingCompleted = onboardingCompleted
    }
}

public struct DeviceOpenInput: Encodable, Sendable, Equatable {
    public let threadId: String
    public let hostId: String?
    public let deviceId: String
    public let platform: DevicePlatform
    public let boot: Bool?

    public init(
        threadId: String,
        hostId: String? = nil,
        deviceId: String,
        platform: DevicePlatform,
        boot: Bool? = true
    ) {
        self.threadId = threadId
        self.hostId = hostId
        self.deviceId = deviceId
        self.platform = platform
        self.boot = boot
    }
}

public struct DeviceCloseInput: Encodable, Sendable, Equatable {
    public let hostId: String?
    public let threadId: String
    public let deviceId: String?
    public let shutdown: Bool?

    public init(
        threadId: String,
        hostId: String? = nil,
        deviceId: String? = nil,
        shutdown: Bool? = false
    ) {
        self.hostId = hostId
        self.threadId = threadId
        self.deviceId = deviceId
        self.shutdown = shutdown
    }
}

public struct DeviceShutdownInput: Encodable, Sendable, Equatable {
    public let hostId: String?
    public let deviceId: String
    public let platform: DevicePlatform

    public init(hostId: String? = nil, deviceId: String, platform: DevicePlatform) {
        self.hostId = hostId
        self.deviceId = deviceId
        self.platform = platform
    }
}

public struct DeviceDetailInput: Encodable, Sendable, Equatable {
    public let hostId: String?
    public let deviceId: String

    public init(hostId: String? = nil, deviceId: String) {
        self.hostId = hostId
        self.deviceId = deviceId
    }
}

public struct DeviceForegroundApp: Codable, Sendable, Equatable {
    public let id: String
    public let name: String?
    public let version: String?

    public init(id: String, name: String? = nil, version: String? = nil) {
        self.id = id
        self.name = name
        self.version = version
    }
}

public struct DeviceSettings: Codable, Sendable, Equatable {
    public let appearance: String?
    public let textSize: String?
    public let reduceMotion: Bool?
    public let increaseContrast: Bool?
    public let reduceTransparency: Bool?
    public let showBorders: Bool?
    public let voiceOver: Bool?
    public let networkEnabled: Bool?

    public init(
        appearance: String? = nil,
        textSize: String? = nil,
        reduceMotion: Bool? = nil,
        increaseContrast: Bool? = nil,
        reduceTransparency: Bool? = nil,
        showBorders: Bool? = nil,
        voiceOver: Bool? = nil,
        networkEnabled: Bool? = nil
    ) {
        self.appearance = appearance
        self.textSize = textSize
        self.reduceMotion = reduceMotion
        self.increaseContrast = increaseContrast
        self.reduceTransparency = reduceTransparency
        self.showBorders = showBorders
        self.voiceOver = voiceOver
        self.networkEnabled = networkEnabled
    }
}

public struct DeviceDetail: Codable, Sendable, Equatable {
    public let hostId: String
    public let deviceId: String
    public let settings: DeviceSettings
    public let foregroundApp: DeviceForegroundApp?
    public let readAt: String

    public init(
        hostId: String,
        deviceId: String,
        settings: DeviceSettings = DeviceSettings(),
        foregroundApp: DeviceForegroundApp? = nil,
        readAt: String = ""
    ) {
        self.hostId = hostId
        self.deviceId = deviceId
        self.settings = settings
        self.foregroundApp = foregroundApp
        self.readAt = readAt
    }
}

public enum DeviceActionInput: Encodable, Sendable, Equatable {
    case setAppearance(hostId: String? = nil, deviceId: String, value: String)
    case setOrientation(hostId: String? = nil, deviceId: String, value: String)
    case openUrl(hostId: String? = nil, deviceId: String, url: String)
    case launchApp(hostId: String? = nil, deviceId: String, appId: String)
    case terminateApp(hostId: String? = nil, deviceId: String, appId: String)
    case shake(hostId: String? = nil, deviceId: String)

    private enum CodingKeys: String, CodingKey {
        case hostId, deviceId, type, value, url, appId
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .setAppearance(let hostId, let deviceId, let value):
            try c.encodeIfPresent(hostId, forKey: .hostId)
            try c.encode(deviceId, forKey: .deviceId)
            try c.encode("setAppearance", forKey: .type)
            try c.encode(value, forKey: .value)
        case .setOrientation(let hostId, let deviceId, let value):
            try c.encodeIfPresent(hostId, forKey: .hostId)
            try c.encode(deviceId, forKey: .deviceId)
            try c.encode("setOrientation", forKey: .type)
            try c.encode(value, forKey: .value)
        case .openUrl(let hostId, let deviceId, let url):
            try c.encodeIfPresent(hostId, forKey: .hostId)
            try c.encode(deviceId, forKey: .deviceId)
            try c.encode("openUrl", forKey: .type)
            try c.encode(url, forKey: .url)
        case .launchApp(let hostId, let deviceId, let appId):
            try c.encodeIfPresent(hostId, forKey: .hostId)
            try c.encode(deviceId, forKey: .deviceId)
            try c.encode("launchApp", forKey: .type)
            try c.encode(appId, forKey: .appId)
        case .terminateApp(let hostId, let deviceId, let appId):
            try c.encodeIfPresent(hostId, forKey: .hostId)
            try c.encode(deviceId, forKey: .deviceId)
            try c.encode("terminateApp", forKey: .type)
            try c.encode(appId, forKey: .appId)
        case .shake(let hostId, let deviceId):
            try c.encodeIfPresent(hostId, forKey: .hostId)
            try c.encode(deviceId, forKey: .deviceId)
            try c.encode("shake", forKey: .type)
        }
    }
}

public enum DeviceHardwareButton: String, Sendable, Equatable, CaseIterable {
    case home
    case back
    case recents
    case power
}

// MARK: - Device Hub URL & Input Frame Helpers

public enum DeviceHubURLBuilder {
    public static func screenshotURL(
        baseURL: URL,
        hubBasePath: String = "/api/device-hub",
        hostId: String,
        deviceId: String,
        platform: DevicePlatform
    ) -> URL? {
        let vendor = platform == .ios ? "serve-sim" : "serve-emu"
        let trimmedBase = hubBasePath.hasSuffix("/") ? String(hubBasePath.dropLast()) : hubBasePath
        let path = "\(trimmedBase)/vendor/\(vendor)/api/screenshot"
        guard let resolved = AssetURLResolver.resolve(path, against: baseURL),
              var components = URLComponents(url: resolved, resolvingAgainstBaseURL: false)
        else { return nil }
        components.queryItems = [
            URLQueryItem(name: "device", value: deviceId),
            URLQueryItem(name: "hostId", value: hostId),
        ]
        return components.url
    }

    public static func inputWebSocketURL(
        baseURL: URL,
        hubBasePath: String = "/api/device-hub",
        hostId: String,
        deviceId: String,
        platform: DevicePlatform,
        wsTicket: String
    ) -> URL? {
        let vendorPath = platform == .ios ? "/vendor/serve-sim/helper/ws" : "/vendor/serve-emu/ws"
        let trimmedBase = hubBasePath.hasSuffix("/") ? String(hubBasePath.dropLast()) : hubBasePath
        guard let resolved = AssetURLResolver.resolve("\(trimmedBase)\(vendorPath)", against: baseURL),
              var components = URLComponents(url: resolved, resolvingAgainstBaseURL: false)
        else { return nil }
        switch components.scheme?.lowercased() {
        case "https", "wss": components.scheme = "wss"
        case "http", "ws": components.scheme = "ws"
        default: return nil
        }
        components.queryItems = [
            URLQueryItem(name: "device", value: deviceId),
            URLQueryItem(name: "hostId", value: hostId),
            URLQueryItem(name: "wsTicket", value: wsTicket),
        ]
        return components.url
    }

    /// Encodes a tagged JSON binary frame for serve-sim (iOS) input WebSocket.
    public static func iosTaggedFrame(tag: UInt8, payload: [String: JSONValue]) throws -> Data {
        let jsonData = try SwftJSON.makeEncoder().encode(payload)
        var frame = Data(capacity: 1 + jsonData.count)
        frame.append(tag)
        frame.append(jsonData)
        return frame
    }
}

private struct EmptyDevicePayload: Encodable, Sendable {}

// MARK: - ServerConnection Device RPCs & Screenshot/Input Helpers

public extension ServerConnection {
    func listDevices(_ input: DeviceListInput = DeviceListInput()) async throws -> DeviceServiceState {
        try await call(tag: RPCMethod.deviceList, payload: input)
    }

    func configureDevices(_ input: DeviceConfigureInput) async throws -> DeviceServiceState {
        try await call(tag: RPCMethod.deviceConfigure, payload: input)
    }

    @discardableResult
    func openDevice(_ input: DeviceOpenInput) async throws -> DeviceSession {
        try await call(tag: RPCMethod.deviceOpen, payload: input)
    }

    func closeDevice(_ input: DeviceCloseInput) async throws {
        try await callVoid(tag: RPCMethod.deviceClose, payload: input)
    }

    func shutdownDevice(_ input: DeviceShutdownInput) async throws {
        try await callVoid(tag: RPCMethod.deviceShutdown, payload: input)
    }

    func getDeviceDetail(hostId: String? = nil, deviceId: String) async throws -> DeviceDetail {
        try await call(
            tag: RPCMethod.deviceDetail,
            payload: DeviceDetailInput(hostId: hostId, deviceId: deviceId)
        )
    }

    @discardableResult
    func performDeviceAction(_ input: DeviceActionInput) async throws -> DeviceDetail {
        try await call(tag: RPCMethod.deviceAction, payload: input)
    }

    nonisolated func subscribeDeviceState() -> AsyncThrowingStream<DeviceServiceState, any Error> {
        subscribe(tag: RPCMethod.subscribeDeviceState, payload: EmptyDevicePayload())
    }

    /// Fetches a fresh PNG screenshot from the server's device hub proxy (works for local and remote environments).
    func fetchDeviceScreenshot(
        hubBasePath: String = "/api/device-hub",
        hostId: String,
        deviceId: String,
        platform: DevicePlatform
    ) async throws -> Data {
        guard let url = DeviceHubURLBuilder.screenshotURL(
            baseURL: httpBaseURL,
            hubBasePath: hubBasePath,
            hostId: hostId,
            deviceId: deviceId,
            platform: platform
        ) else {
            throw AssetTransferError.invalidURL("\(hubBasePath)/screenshot")
        }
        let token = try await currentAccessToken()
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let detail = String(data: data.prefix(240), encoding: .utf8) ?? ""
            throw RPCError.httpError(statusCode: http.statusCode, body: detail)
        }
        return data
    }

    /// Sends a normalized tap `(x, y)` (0...1) over the device hub input WebSocket.
    func sendDeviceTap(
        hubBasePath: String = "/api/device-hub",
        hostId: String,
        deviceId: String,
        platform: DevicePlatform,
        x: Double,
        y: Double
    ) async throws {
        let clampedX = min(1, max(0, x))
        let clampedY = min(1, max(0, y))
        try await withDeviceInputSocket(
            hubBasePath: hubBasePath,
            hostId: hostId,
            deviceId: deviceId,
            platform: platform
        ) { socket in
            if platform == .ios {
                let down = try DeviceHubURLBuilder.iosTaggedFrame(tag: 0x03, payload: [
                    "type": .string("begin"),
                    "x": .double(clampedX),
                    "y": .double(clampedY),
                ])
                let up = try DeviceHubURLBuilder.iosTaggedFrame(tag: 0x03, payload: [
                    "type": .string("end"),
                    "x": .double(clampedX),
                    "y": .double(clampedY),
                ])
                try await socket.send(.data(down))
                try? await Task.sleep(for: .milliseconds(40))
                try await socket.send(.data(up))
            } else {
                let down = try SwftJSON.makeEncoder().encode([
                    "type": JSONValue.string("touch"),
                    "action": .string("down"),
                    "x": .double(clampedX),
                    "y": .double(clampedY),
                ])
                let up = try SwftJSON.makeEncoder().encode([
                    "type": JSONValue.string("touch"),
                    "action": .string("up"),
                    "x": .double(clampedX),
                    "y": .double(clampedY),
                ])
                if let downStr = String(data: down, encoding: .utf8) {
                    try await socket.send(.string(downStr))
                }
                try? await Task.sleep(for: .milliseconds(40))
                if let upStr = String(data: up, encoding: .utf8) {
                    try await socket.send(.string(upStr))
                }
            }
        }
    }

    /// Sends a hardware button press (home, back, recents, power) over the device hub input WebSocket.
    func sendDeviceHardwareButton(
        hubBasePath: String = "/api/device-hub",
        hostId: String,
        deviceId: String,
        platform: DevicePlatform,
        button: DeviceHardwareButton
    ) async throws {
        try await withDeviceInputSocket(
            hubBasePath: hubBasePath,
            hostId: hostId,
            deviceId: deviceId,
            platform: platform
        ) { socket in
            if platform == .ios {
                let name: String = switch button {
                case .home: "home"
                case .recents: "app_switcher"
                case .power: "lock"
                case .back: "home"
                }
                let frame = try DeviceHubURLBuilder.iosTaggedFrame(tag: 0x04, payload: [
                    "button": .string(name),
                ])
                try await socket.send(.data(frame))
            } else {
                let payload = try SwftJSON.makeEncoder().encode(["type": button.rawValue])
                if let text = String(data: payload, encoding: .utf8) {
                    try await socket.send(.string(text))
                }
            }
        }
    }

    /// Sends text input to an Android emulator over the device hub input WebSocket.
    func sendDeviceText(
        hubBasePath: String = "/api/device-hub",
        hostId: String,
        deviceId: String,
        platform: DevicePlatform,
        text: String
    ) async throws {
        guard !text.isEmpty, platform == .android else { return }
        try await withDeviceInputSocket(
            hubBasePath: hubBasePath,
            hostId: hostId,
            deviceId: deviceId,
            platform: platform
        ) { socket in
            let payload = try SwftJSON.makeEncoder().encode([
                "type": JSONValue.string("text"),
                "text": .string(text),
            ])
            if let encoded = String(data: payload, encoding: .utf8) {
                try await socket.send(.string(encoded))
            }
        }
    }

    private func withDeviceInputSocket(
        hubBasePath: String,
        hostId: String,
        deviceId: String,
        platform: DevicePlatform,
        operation: (URLSessionWebSocketTask) async throws -> Void
    ) async throws {
        let ticket = try await mintMediaTicket()
        guard let url = DeviceHubURLBuilder.inputWebSocketURL(
            baseURL: httpBaseURL,
            hubBasePath: hubBasePath,
            hostId: hostId,
            deviceId: deviceId,
            platform: platform,
            wsTicket: ticket.ticket
        ) else {
            throw AssetTransferError.invalidURL("\(hubBasePath)/ws")
        }
        let socket = session.webSocketTask(with: url)
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }
        try await operation(socket)
        try? await Task.sleep(for: .milliseconds(60))
    }
}
