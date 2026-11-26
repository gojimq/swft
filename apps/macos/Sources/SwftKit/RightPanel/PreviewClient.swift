import Foundation

// MARK: - Preview RPC Method Tags (`packages/contracts/src/rpc.ts`)

public extension RPCMethod {
    static let previewList = "preview.list"
    static let previewOpen = "preview.open"
    static let previewClose = "preview.close"
    static let previewReportStatus = "preview.reportStatus"
    static let subscribePreviewEvents = "subscribePreviewEvents"
    static let subscribeDiscoveredLocalServers = "subscribeDiscoveredLocalServers"
}

// MARK: - Preview Wire Models (`packages/contracts/src/preview.ts`)

public enum PreviewRuntime: String, Codable, Sendable, Hashable {
    case desktop
    case server
}

public enum PreviewNavStatus: Sendable, Equatable, Hashable {
    case idle
    case loading(url: String, title: String)
    case success(url: String, title: String)
    case loadFailed(url: String, title: String, code: Int, description: String)
    case unknown(tag: String)

    public var url: String? {
        switch self {
        case .idle, .unknown:
            return nil
        case .loading(let url, _), .success(let url, _), .loadFailed(let url, _, _, _):
            return url
        }
    }

    public var title: String? {
        switch self {
        case .idle, .unknown:
            return nil
        case .loading(_, let title), .success(_, let title), .loadFailed(_, let title, _, _):
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

extension PreviewNavStatus: Codable {
    private enum CodingKeys: String, CodingKey {
        case _tag
        case url
        case title
        case code
        case description
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try c.decode(String.self, forKey: ._tag)
        switch tag {
        case "Idle":
            self = .idle
        case "Loading":
            self = .loading(
                url: try c.decode(String.self, forKey: .url),
                title: try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            )
        case "Success":
            self = .success(
                url: try c.decode(String.self, forKey: .url),
                title: try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            )
        case "LoadFailed":
            self = .loadFailed(
                url: try c.decode(String.self, forKey: .url),
                title: try c.decodeIfPresent(String.self, forKey: .title) ?? "",
                code: try c.decodeIfPresent(Int.self, forKey: .code) ?? 0,
                description: try c.decodeIfPresent(String.self, forKey: .description) ?? ""
            )
        default:
            self = .unknown(tag: tag)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .idle:
            try c.encode("Idle", forKey: ._tag)
        case .loading(let url, let title):
            try c.encode("Loading", forKey: ._tag)
            try c.encode(url, forKey: .url)
            try c.encode(title, forKey: .title)
        case .success(let url, let title):
            try c.encode("Success", forKey: ._tag)
            try c.encode(url, forKey: .url)
            try c.encode(title, forKey: .title)
        case .loadFailed(let url, let title, let code, let description):
            try c.encode("LoadFailed", forKey: ._tag)
            try c.encode(url, forKey: .url)
            try c.encode(title, forKey: .title)
            try c.encode(code, forKey: .code)
            try c.encode(description, forKey: .description)
        case .unknown(let tag):
            try c.encode(tag, forKey: ._tag)
        }
    }
}

public struct PreviewSessionSnapshot: Codable, Sendable, Equatable, Identifiable {
    public let threadId: String
    public let tabId: String
    public let navStatus: PreviewNavStatus
    public let canGoBack: Bool
    public let canGoForward: Bool
    public let runtime: PreviewRuntime?
    public let headless: Bool?
    public let automationOwner: String?
    public let reveal: Bool?
    public let updatedAt: String

    public var id: String { tabId }

    public init(
        threadId: String,
        tabId: String,
        navStatus: PreviewNavStatus,
        canGoBack: Bool = false,
        canGoForward: Bool = false,
        runtime: PreviewRuntime? = nil,
        headless: Bool? = nil,
        automationOwner: String? = nil,
        reveal: Bool? = nil,
        updatedAt: String = ""
    ) {
        self.threadId = threadId
        self.tabId = tabId
        self.navStatus = navStatus
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.runtime = runtime
        self.headless = headless
        self.automationOwner = automationOwner
        self.reveal = reveal
        self.updatedAt = updatedAt
    }
}

public struct PreviewListInput: Encodable, Sendable, Equatable {
    public let threadId: String

    public init(threadId: String) {
        self.threadId = threadId
    }
}

public struct PreviewListResult: Codable, Sendable, Equatable {
    public let sessions: [PreviewSessionSnapshot]
    public let serverEpoch: String
    public let revision: Int

    public init(sessions: [PreviewSessionSnapshot], serverEpoch: String, revision: Int) {
        self.sessions = sessions
        self.serverEpoch = serverEpoch
        self.revision = revision
    }
}

public struct PreviewOpenInput: Encodable, Sendable, Equatable {
    public let threadId: String
    public let url: String?
    public let runtime: PreviewRuntime?
    public let reveal: Bool?

    public init(
        threadId: String,
        url: String? = nil,
        runtime: PreviewRuntime? = nil,
        reveal: Bool? = nil
    ) {
        self.threadId = threadId
        self.url = url
        self.runtime = runtime
        self.reveal = reveal
    }
}

public struct PreviewCloseInput: Encodable, Sendable, Equatable {
    public let threadId: String
    public let tabId: String?

    public init(threadId: String, tabId: String? = nil) {
        self.threadId = threadId
        self.tabId = tabId
    }
}

public enum PreviewEvent: Sendable, Equatable {
    case opened(threadId: String, tabId: String, revision: Int, snapshot: PreviewSessionSnapshot)
    case navigated(threadId: String, tabId: String, revision: Int, snapshot: PreviewSessionSnapshot)
    case resized(threadId: String, tabId: String, revision: Int, snapshot: PreviewSessionSnapshot)
    case failed(threadId: String, tabId: String, revision: Int, url: String, description: String)
    case closed(threadId: String, tabId: String, revision: Int)
    case unknown(type: String)
}

extension PreviewEvent: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type, threadId, tabId, revision, snapshot, url, description
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "opened":
            self = .opened(
                threadId: try c.decode(String.self, forKey: .threadId),
                tabId: try c.decode(String.self, forKey: .tabId),
                revision: try c.decode(Int.self, forKey: .revision),
                snapshot: try c.decode(PreviewSessionSnapshot.self, forKey: .snapshot)
            )
        case "navigated":
            self = .navigated(
                threadId: try c.decode(String.self, forKey: .threadId),
                tabId: try c.decode(String.self, forKey: .tabId),
                revision: try c.decode(Int.self, forKey: .revision),
                snapshot: try c.decode(PreviewSessionSnapshot.self, forKey: .snapshot)
            )
        case "resized":
            self = .resized(
                threadId: try c.decode(String.self, forKey: .threadId),
                tabId: try c.decode(String.self, forKey: .tabId),
                revision: try c.decode(Int.self, forKey: .revision),
                snapshot: try c.decode(PreviewSessionSnapshot.self, forKey: .snapshot)
            )
        case "failed":
            self = .failed(
                threadId: try c.decode(String.self, forKey: .threadId),
                tabId: try c.decode(String.self, forKey: .tabId),
                revision: try c.decode(Int.self, forKey: .revision),
                url: try c.decode(String.self, forKey: .url),
                description: try c.decodeIfPresent(String.self, forKey: .description) ?? ""
            )
        case "closed":
            self = .closed(
                threadId: try c.decode(String.self, forKey: .threadId),
                tabId: try c.decode(String.self, forKey: .tabId),
                revision: try c.decode(Int.self, forKey: .revision)
            )
        default:
            self = .unknown(type: type)
        }
    }
}

public struct DiscoveredLocalServer: Codable, Sendable, Equatable, Identifiable {
    public let host: String
    public let port: Int
    public let url: String
    public let processName: String?
    public let pid: Int?

    public var id: String { "\(host):\(port)" }

    public init(host: String, port: Int, url: String, processName: String? = nil, pid: Int? = nil) {
        self.host = host
        self.port = port
        self.url = url
        self.processName = processName
        self.pid = pid
    }
}

public struct DiscoveredLocalServerList: Codable, Sendable, Equatable {
    public let servers: [DiscoveredLocalServer]
    public let scannedAt: String

    public init(servers: [DiscoveredLocalServer], scannedAt: String) {
        self.servers = servers
        self.scannedAt = scannedAt
    }
}

private struct EmptyPreviewPayload: Encodable, Sendable {}

// MARK: - ServerConnection Preview RPCs

public extension ServerConnection {
    func listPreviewSessions(threadId: String) async throws -> PreviewListResult {
        try await call(tag: RPCMethod.previewList, payload: PreviewListInput(threadId: threadId))
    }

    @discardableResult
    func openPreviewSession(_ input: PreviewOpenInput) async throws -> PreviewSessionSnapshot {
        try await call(tag: RPCMethod.previewOpen, payload: input)
    }

    func closePreviewSession(threadId: String, tabId: String? = nil) async throws {
        try await callVoid(
            tag: RPCMethod.previewClose,
            payload: PreviewCloseInput(threadId: threadId, tabId: tabId)
        )
    }

    nonisolated func subscribePreviewEvents() -> AsyncThrowingStream<PreviewEvent, any Error> {
        subscribe(tag: RPCMethod.subscribePreviewEvents, payload: EmptyPreviewPayload())
    }

    nonisolated func subscribeDiscoveredLocalServers() -> AsyncThrowingStream<DiscoveredLocalServerList, any Error> {
        subscribe(tag: RPCMethod.subscribeDiscoveredLocalServers, payload: EmptyPreviewPayload())
    }
}
