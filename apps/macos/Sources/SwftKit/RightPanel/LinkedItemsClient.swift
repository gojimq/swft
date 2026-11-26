import Foundation

// MARK: - Linked Pull Request, Issue & Thread Family Models (`threadPullRequest.ts`, `issue.ts`, `orchestrationV2.ts`)

public struct ThreadLinkedPullRequest: Codable, Sendable, Equatable, Hashable {
    public let projectId: String
    public let repository: String
    public let number: Int
    public let url: String

    public init(projectId: String, repository: String, number: Int, url: String) {
        self.projectId = projectId
        self.repository = repository
        self.number = number
        self.url = url
    }
}

public struct ThreadPullRequestActor: Codable, Sendable, Equatable, Hashable {
    public let isBot: Bool?
    public let login: String
    public let name: String?
    public let avatarUrl: String?

    public init(isBot: Bool? = nil, login: String, name: String? = nil, avatarUrl: String? = nil) {
        self.isBot = isBot
        self.login = login
        self.name = name
        self.avatarUrl = avatarUrl
    }
}

public struct ThreadPullRequestSnapshot: Codable, Sendable, Equatable, Hashable {
    public let state: String
    public let title: String
    public let headBranch: String
    public let baseBranch: String
    public let isDraft: Bool
    public let updatedAt: Date?
    public let syncedAt: Date
    public let closedAt: String?
    public let mergedAt: String?
    public let author: ThreadPullRequestActor?
    public let additions: Int?
    public let deletions: Int?
    public let changedFiles: Int?
    public let reviewDecision: String?
    public let checksState: String?
    public let mergeability: String?
    public let rebaseRequired: Bool?

    public init(
        state: String,
        title: String,
        headBranch: String,
        baseBranch: String,
        isDraft: Bool,
        updatedAt: Date? = nil,
        syncedAt: Date,
        closedAt: String? = nil,
        mergedAt: String? = nil,
        author: ThreadPullRequestActor? = nil,
        additions: Int? = nil,
        deletions: Int? = nil,
        changedFiles: Int? = nil,
        reviewDecision: String? = nil,
        checksState: String? = nil,
        mergeability: String? = nil,
        rebaseRequired: Bool? = nil
    ) {
        self.state = state
        self.title = title
        self.headBranch = headBranch
        self.baseBranch = baseBranch
        self.isDraft = isDraft
        self.updatedAt = updatedAt
        self.syncedAt = syncedAt
        self.closedAt = closedAt
        self.mergedAt = mergedAt
        self.author = author
        self.additions = additions
        self.deletions = deletions
        self.changedFiles = changedFiles
        self.reviewDecision = reviewDecision
        self.checksState = checksState
        self.mergeability = mergeability
        self.rebaseRequired = rebaseRequired
    }
}

public struct ThreadPullRequestStackLayer: Codable, Sendable, Equatable, Hashable {
    public let number: Int
    public let headBranch: String
    public let state: String

    public init(number: Int, headBranch: String, state: String) {
        self.number = number
        self.headBranch = headBranch
        self.state = state
    }
}

public struct ThreadPullRequestStack: Codable, Sendable, Equatable, Hashable {
    public let kind: String
    public let id: String
    public let number: Int
    public let url: String
    public let base: String
    public let layers: [ThreadPullRequestStackLayer]

    public init(
        kind: String = "native",
        id: String,
        number: Int,
        url: String,
        base: String,
        layers: [ThreadPullRequestStackLayer]
    ) {
        self.kind = kind
        self.id = id
        self.number = number
        self.url = url
        self.base = base
        self.layers = layers
    }
}

public struct ThreadPullRequestWatch: Codable, Sendable, Equatable, Hashable {
    public let startedAt: Date
    public let passed: Bool
    public let conflicting: Bool
    public let checksPending: Bool?
    public let until: String?

    public init(
        startedAt: Date,
        passed: Bool,
        conflicting: Bool,
        checksPending: Bool? = nil,
        until: String? = nil
    ) {
        self.startedAt = startedAt
        self.passed = passed
        self.conflicting = conflicting
        self.checksPending = checksPending
        self.until = until
    }
}

public struct ThreadPullRequestLink: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let host: String
    public let repository: String
    public let number: Int
    public let url: String
    public let repositoryWebUrl: String?
    public let source: String
    public let linkedAt: Date
    public let snapshot: ThreadPullRequestSnapshot?
    public let stack: ThreadPullRequestStack?
    public let watch: ThreadPullRequestWatch?

    public var id: String {
        "\(host.lowercased())/\(repository.lowercased())#\(number)"
    }

    public var isDismissed: Bool {
        source == "stack-dismissed"
    }

    public var isWatching: Bool {
        watch != nil
    }

    public init(
        host: String,
        repository: String,
        number: Int,
        url: String,
        repositoryWebUrl: String? = nil,
        source: String = "manual",
        linkedAt: Date = Date(),
        snapshot: ThreadPullRequestSnapshot? = nil,
        stack: ThreadPullRequestStack? = nil,
        watch: ThreadPullRequestWatch? = nil
    ) {
        self.host = host
        self.repository = repository
        self.number = number
        self.url = url
        self.repositoryWebUrl = repositoryWebUrl
        self.source = source
        self.linkedAt = linkedAt
        self.snapshot = snapshot
        self.stack = stack
        self.watch = watch
    }
}

public struct ThreadIssueLink: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let tracker: String
    public let host: String
    public let scope: String
    public let key: String
    public let projectId: String
    public let url: String
    public let source: String
    public let linkedAt: Date
    public let displayKey: String
    public let title: String

    public var id: String {
        "\(tracker):\(host.lowercased()):\(scope.lowercased()):\(key)"
    }

    public init(
        tracker: String,
        host: String,
        scope: String,
        key: String,
        projectId: String,
        url: String,
        source: String = "manual",
        linkedAt: Date = Date(),
        displayKey: String,
        title: String
    ) {
        self.tracker = tracker
        self.host = host
        self.scope = scope
        self.key = key
        self.projectId = projectId
        self.url = url
        self.source = source
        self.linkedAt = linkedAt
        self.displayKey = displayKey
        self.title = title
    }
}

public struct GetThreadFamilyInput: Encodable, Sendable, Equatable {
    public let threadId: String

    public init(threadId: String) {
        self.threadId = threadId
    }
}

public struct ThreadFamilyResult: Decodable, Sendable, Equatable {
    public let snapshotSequence: Int
    public let threads: [ThreadShell]

    public init(snapshotSequence: Int, threads: [ThreadShell]) {
        self.snapshotSequence = snapshotSequence
        self.threads = threads
    }
}

// MARK: - ServerConnection Linked Items RPCs

public extension ServerConnection {
    func getThreadFamily(threadId: String) async throws -> ThreadFamilyResult {
        try await call(
            tag: RPCMethod.orchestrationGetThreadFamily,
            payload: GetThreadFamilyInput(threadId: threadId)
        )
    }

    @discardableResult
    func linkPullRequest(
        threadId: String,
        host: String,
        repository: String,
        number: Int,
        url: String,
        source: String = "manual"
    ) async throws -> DispatchCommandResult {
        try await call(
            tag: RPCMethod.orchestrationDispatchCommand,
            payload: OrchestrationCommand.linkPullRequest(
                threadId: threadId,
                host: host,
                repository: repository,
                number: number,
                url: url,
                source: source
            )
        )
    }

    @discardableResult
    func unlinkPullRequest(
        threadId: String,
        host: String,
        repository: String,
        number: Int
    ) async throws -> DispatchCommandResult {
        try await call(
            tag: RPCMethod.orchestrationDispatchCommand,
            payload: OrchestrationCommand.unlinkPullRequest(
                threadId: threadId,
                host: host,
                repository: repository,
                number: number
            )
        )
    }

    @discardableResult
    func unlinkIssue(
        threadId: String,
        tracker: String,
        host: String,
        scope: String,
        key: String
    ) async throws -> DispatchCommandResult {
        try await call(
            tag: RPCMethod.orchestrationDispatchCommand,
            payload: OrchestrationCommand.unlinkIssue(
                threadId: threadId,
                tracker: tracker,
                host: host,
                scope: scope,
                key: key
            )
        )
    }
}
