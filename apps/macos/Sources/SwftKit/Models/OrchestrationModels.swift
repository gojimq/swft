import Foundation

// MARK: - Projects

public struct RepositoryIdentity: Codable, Sendable, Equatable {
    public let canonicalKey: String
    public let webUrl: String?
    public let rootPath: String?
    public let displayName: String?
    public let provider: String?
    public let owner: String?
    public let name: String?

    public init(
        canonicalKey: String,
        webUrl: String? = nil,
        rootPath: String? = nil,
        displayName: String? = nil,
        provider: String? = nil,
        owner: String? = nil,
        name: String? = nil
    ) {
        self.canonicalKey = canonicalKey
        self.webUrl = webUrl
        self.rootPath = rootPath
        self.displayName = displayName
        self.provider = provider
        self.owner = owner
        self.name = name
    }
}

public struct ProjectScript: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let command: String
    public let icon: String
    public let runOnWorktreeCreate: Bool

    public init(
        id: String,
        name: String,
        command: String,
        icon: String,
        runOnWorktreeCreate: Bool
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.icon = icon
        self.runOnWorktreeCreate = runOnWorktreeCreate
    }
}

public enum ProjectIconOverride: Sendable, Equatable, Codable {
    case lucide(name: String, color: String)
    case emoji(String)
    case monogram(text: String, color: String)
    case unknown(kind: String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case name
        case color
        case emoji
        case text
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "lucide":
            self = .lucide(
                name: try c.decode(String.self, forKey: .name),
                color: try c.decode(String.self, forKey: .color)
            )
        case "emoji":
            self = .emoji(try c.decode(String.self, forKey: .emoji))
        case "monogram":
            self = .monogram(
                text: try c.decode(String.self, forKey: .text),
                color: try c.decode(String.self, forKey: .color)
            )
        default:
            self = .unknown(kind: kind)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .lucide(let name, let color):
            try c.encode("lucide", forKey: .kind)
            try c.encode(name, forKey: .name)
            try c.encode(color, forKey: .color)
        case .emoji(let emoji):
            try c.encode("emoji", forKey: .kind)
            try c.encode(emoji, forKey: .emoji)
        case .monogram(let text, let color):
            try c.encode("monogram", forKey: .kind)
            try c.encode(text, forKey: .text)
            try c.encode(color, forKey: .color)
        case .unknown(let kind):
            try c.encode(kind, forKey: .kind)
        }
    }
}

public struct ProjectShell: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let hasCustomTitle: Bool?
    public let workspaceRoot: String
    public let repositoryIdentity: RepositoryIdentity?
    public let defaultModelSelection: ModelSelection?
    public let defaultThreadEnvMode: String?
    public let projectIcon: ProjectIconOverride?
    public let scripts: [ProjectScript]
    public let pinnedAt: Date?
    public let archivedAt: Date?
    public let createdAt: Date
    public let updatedAt: Date
    public let deletedAt: Date?

    public init(
        id: String,
        title: String,
        hasCustomTitle: Bool? = nil,
        workspaceRoot: String,
        repositoryIdentity: RepositoryIdentity? = nil,
        defaultModelSelection: ModelSelection? = nil,
        defaultThreadEnvMode: String? = nil,
        projectIcon: ProjectIconOverride? = nil,
        scripts: [ProjectScript] = [],
        pinnedAt: Date? = nil,
        archivedAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.hasCustomTitle = hasCustomTitle
        self.workspaceRoot = workspaceRoot
        self.repositoryIdentity = repositoryIdentity
        self.defaultModelSelection = defaultModelSelection
        self.defaultThreadEnvMode = defaultThreadEnvMode
        self.projectIcon = projectIcon
        self.scripts = scripts
        self.pinnedAt = pinnedAt
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.hasCustomTitle = try c.decodeIfPresent(Bool.self, forKey: .hasCustomTitle)
        self.workspaceRoot = try c.decode(String.self, forKey: .workspaceRoot)
        self.repositoryIdentity = try c.decodeIfPresent(RepositoryIdentity.self, forKey: .repositoryIdentity)
        self.defaultModelSelection = try c.decodeIfPresent(ModelSelection.self, forKey: .defaultModelSelection)
        self.defaultThreadEnvMode = try c.decodeIfPresent(String.self, forKey: .defaultThreadEnvMode)
        self.projectIcon = try c.decodeIfPresent(ProjectIconOverride.self, forKey: .projectIcon)
        self.scripts = try c.decodeIfPresent([ProjectScript].self, forKey: .scripts) ?? []
        self.pinnedAt = try c.decodeIfPresent(Date.self, forKey: .pinnedAt)
        self.archivedAt = try c.decodeIfPresent(Date.self, forKey: .archivedAt)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        self.deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}

public enum ProjectMutation: Encodable, Sendable, Equatable {
    case create(
        commandId: String,
        projectId: String,
        title: String,
        workspaceRoot: String,
        createWorkspaceRootIfMissing: Bool? = nil,
        defaultModelSelection: ModelSelection? = nil
    )
    case delete(commandId: String, projectId: String, force: Bool? = nil)

    private enum CodingKeys: String, CodingKey {
        case type
        case commandId
        case projectId
        case title
        case workspaceRoot
        case createWorkspaceRootIfMissing
        case defaultModelSelection
        case force
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .create(
            let commandId,
            let projectId,
            let title,
            let workspaceRoot,
            let createIfMissing,
            let defaultModelSelection
        ):
            try c.encode("project.create", forKey: .type)
            try c.encode(commandId, forKey: .commandId)
            try c.encode(projectId, forKey: .projectId)
            try c.encode(title, forKey: .title)
            try c.encode(workspaceRoot, forKey: .workspaceRoot)
            try c.encodeIfPresent(createIfMissing, forKey: .createWorkspaceRootIfMissing)
            try c.encodeIfPresent(defaultModelSelection, forKey: .defaultModelSelection)
        case .delete(let commandId, let projectId, let force):
            try c.encode("project.delete", forKey: .type)
            try c.encode(commandId, forKey: .commandId)
            try c.encode(projectId, forKey: .projectId)
            try c.encodeIfPresent(force, forKey: .force)
        }
    }
}

// MARK: - Thread Status, Lineage & Shell

public enum RunStatus: Sendable, Hashable, Codable {
    case preparing
    case queued
    case starting
    case running
    case waiting
    case completed
    case interrupted
    case failed
    case cancelled
    case rolledBack
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .preparing: return "preparing"
        case .queued: return "queued"
        case .starting: return "starting"
        case .running: return "running"
        case .waiting: return "waiting"
        case .completed: return "completed"
        case .interrupted: return "interrupted"
        case .failed: return "failed"
        case .cancelled: return "cancelled"
        case .rolledBack: return "rolled_back"
        case .unknown(let value): return value
        }
    }

    public var isActive: Bool {
        switch self {
        case .preparing, .queued, .starting, .running, .waiting:
            return true
        default:
            return false
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "preparing": self = .preparing
        case "queued": self = .queued
        case "starting": self = .starting
        case "running": self = .running
        case "waiting": self = .waiting
        case "completed": self = .completed
        case "interrupted": self = .interrupted
        case "failed": self = .failed
        case "cancelled": self = .cancelled
        case "rolled_back": self = .rolledBack
        default: self = .unknown(rawValue)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum ShellThreadStatus: Sendable, Hashable, Codable {
    case idle
    case run(RunStatus)

    public var rawValue: String {
        switch self {
        case .idle: return "idle"
        case .run(let status): return status.rawValue
        }
    }

    public var isActive: Bool {
        if case .run(let status) = self { return status.isActive }
        return false
    }

    public init(rawValue: String) {
        if rawValue == "idle" {
            self = .idle
        } else {
            self = .run(RunStatus(rawValue: rawValue))
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ThreadLineage: Codable, Sendable, Equatable {
    public let parentThreadId: String?
    public let relationshipToParent: String?
    public let rootThreadId: String
    public let sideChat: Bool?
    public let workflowStep: Bool?

    /// Mirrors server `isListedThreadLineage`: excludes subagents, side chats, and workflow steps.
    public var isListed: Bool {
        relationshipToParent != "subagent" && sideChat != true && workflowStep != true
    }

    public init(
        parentThreadId: String? = nil,
        relationshipToParent: String? = nil,
        rootThreadId: String,
        sideChat: Bool? = nil,
        workflowStep: Bool? = nil
    ) {
        self.parentThreadId = parentThreadId
        self.relationshipToParent = relationshipToParent
        self.rootThreadId = rootThreadId
        self.sideChat = sideChat
        self.workflowStep = workflowStep
    }
}

public struct PendingRuntimeRequestSummary: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: String
    public let createdAt: Date
    public let blocking: Bool?
    public let userOnly: Bool?

    public var isApproval: Bool {
        kind != "user_input" && kind != "auth_refresh"
    }

    public var isUserInput: Bool {
        kind == "user_input"
    }

    public init(
        id: String,
        kind: String,
        createdAt: Date,
        blocking: Bool? = nil,
        userOnly: Bool? = nil
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.blocking = blocking
        self.userOnly = userOnly
    }
}

public struct LatestVisibleMessageSummary: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let role: String
    public let text: String
    public let updatedAt: Date

    public init(id: String, role: String, text: String, updatedAt: Date) {
        self.id = id
        self.role = role
        self.text = text
        self.updatedAt = updatedAt
    }
}

public struct PendingBackgroundTask: Codable, Sendable, Equatable {
    public let kind: String
    public let taskId: String
    public let description: String?
    public let command: String?
    public let itemId: String?
    public let awaited: Bool?

    public init(
        kind: String,
        taskId: String,
        description: String? = nil,
        command: String? = nil,
        itemId: String? = nil,
        awaited: Bool? = nil
    ) {
        self.kind = kind
        self.taskId = taskId
        self.description = description
        self.command = command
        self.itemId = itemId
        self.awaited = awaited
    }
}

public struct ThreadShell: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let projectId: String
    public let title: String
    public let providerInstanceId: String
    public let modelSelection: ModelSelection
    public let runtimeMode: RuntimeMode
    public let interactionMode: ProviderInteractionMode
    public let branch: String?
    public let worktreePath: String?
    public let linkedPullRequest: ThreadLinkedPullRequest?
    public let branchPullRequest: ThreadLinkedPullRequest?
    public let pullRequests: [ThreadPullRequestLink]
    public let issues: [ThreadIssueLink]
    public let lineage: ThreadLineage
    public let activeProviderThreadId: String?
    public let latestRunId: String?
    public let latestRunRequestedAt: Date?
    public let latestRunStartedAt: Date?
    public let latestRunCompletedAt: Date?
    public let latestRunStopRequested: Bool?
    public let activeRunId: String?
    public let activityRunStartedAt: Date?
    public let activityRunStatus: String?
    public let blockedOnThreadWait: Bool?
    public let status: ShellThreadStatus
    public let lastError: String?
    public let lastErrorClass: String?
    public let lastErrorCode: String?
    public let usageLimitResetAt: String?
    public let pendingRuntimeRequest: PendingRuntimeRequestSummary?
    public let pendingGuestMessageCount: Int?
    public let latestVisibleMessage: LatestVisibleMessageSummary?
    public let latestUserMessageAt: Date?
    public let hasActionableProposedPlan: Bool
    public let pendingBackgroundTasks: [PendingBackgroundTask]
    public let itemCount: Int
    public let visibleItemCount: Int
    public let createdAt: Date
    public let updatedAt: Date
    public let archivedAt: Date?
    public let settledOverride: String?
    public let settledAt: Date?
    public let unsettledAt: Date?
    public let snoozedUntil: Date?
    public let pinnedAt: Date?
    public let lastVisitedAt: Date?
    public let deletedAt: Date?

    public var isListed: Bool {
        lineage.isListed && deletedAt == nil && archivedAt == nil
    }

    public var needsApproval: Bool {
        pendingRuntimeRequest?.isApproval == true
    }

    public var needsUserInput: Bool {
        pendingRuntimeRequest?.isUserInput == true
    }

    public var isRunning: Bool {
        if needsApproval || needsUserInput { return false }
        if activityRunStatus != nil { return true }
        return status.isActive
    }

    /// Mirrors `Sidebar.logic.ts:hasUnseenCompletion`.
    public var isUnread: Bool {
        guard let completedAt = latestRunCompletedAt else { return false }
        if status == .run(.interrupted) || status == .run(.cancelled) { return false }
        guard let lastVisitedAt else { return false }
        return completedAt > lastVisitedAt
    }

    public var isPinned: Bool { pinnedAt != nil }
    public var isSettled: Bool {
        settledOverride == "settled" || (settledAt != nil && settledOverride != "active")
    }
    public var isArchived: Bool { archivedAt != nil }

    public func isSnoozed(asOf now: Date = Date()) -> Bool {
        guard let snoozedUntil else { return false }
        return snoozedUntil > now
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.projectId = try c.decode(String.self, forKey: .projectId)
        self.title = try c.decode(String.self, forKey: .title)
        self.providerInstanceId = try c.decode(String.self, forKey: .providerInstanceId)
        self.modelSelection = try c.decode(ModelSelection.self, forKey: .modelSelection)
        self.runtimeMode = try c.decode(RuntimeMode.self, forKey: .runtimeMode)
        self.interactionMode = try c.decode(ProviderInteractionMode.self, forKey: .interactionMode)
        self.branch = try c.decodeIfPresent(String.self, forKey: .branch)
        self.worktreePath = try c.decodeIfPresent(String.self, forKey: .worktreePath)
        self.linkedPullRequest = try c.decodeIfPresent(ThreadLinkedPullRequest.self, forKey: .linkedPullRequest)
        self.branchPullRequest = try c.decodeIfPresent(ThreadLinkedPullRequest.self, forKey: .branchPullRequest)
        self.pullRequests = try c.decodeIfPresent([ThreadPullRequestLink].self, forKey: .pullRequests) ?? []
        self.issues = try c.decodeIfPresent([ThreadIssueLink].self, forKey: .issues) ?? []
        self.lineage = try c.decode(ThreadLineage.self, forKey: .lineage)
        self.activeProviderThreadId = try c.decodeIfPresent(String.self, forKey: .activeProviderThreadId)
        self.latestRunId = try c.decodeIfPresent(String.self, forKey: .latestRunId)
        self.latestRunRequestedAt = try c.decodeIfPresent(Date.self, forKey: .latestRunRequestedAt)
        self.latestRunStartedAt = try c.decodeIfPresent(Date.self, forKey: .latestRunStartedAt)
        self.latestRunCompletedAt = try c.decodeIfPresent(Date.self, forKey: .latestRunCompletedAt)
        self.latestRunStopRequested = try c.decodeIfPresent(Bool.self, forKey: .latestRunStopRequested)
        self.activeRunId = try c.decodeIfPresent(String.self, forKey: .activeRunId)
        self.activityRunStartedAt = try c.decodeIfPresent(Date.self, forKey: .activityRunStartedAt)
        self.activityRunStatus = try c.decodeIfPresent(String.self, forKey: .activityRunStatus)
        self.blockedOnThreadWait = try c.decodeIfPresent(Bool.self, forKey: .blockedOnThreadWait)
        self.status = try c.decode(ShellThreadStatus.self, forKey: .status)
        self.lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
        self.lastErrorClass = try c.decodeIfPresent(String.self, forKey: .lastErrorClass)
        self.lastErrorCode = try c.decodeIfPresent(String.self, forKey: .lastErrorCode)
        self.usageLimitResetAt = try c.decodeIfPresent(String.self, forKey: .usageLimitResetAt)
        self.pendingRuntimeRequest = try c.decodeIfPresent(PendingRuntimeRequestSummary.self, forKey: .pendingRuntimeRequest)
        self.pendingGuestMessageCount = try c.decodeIfPresent(Int.self, forKey: .pendingGuestMessageCount)
        self.latestVisibleMessage = try c.decodeIfPresent(LatestVisibleMessageSummary.self, forKey: .latestVisibleMessage)
        self.latestUserMessageAt = try c.decodeIfPresent(Date.self, forKey: .latestUserMessageAt)
        self.hasActionableProposedPlan = try c.decodeIfPresent(Bool.self, forKey: .hasActionableProposedPlan) ?? false
        self.pendingBackgroundTasks = try c.decodeIfPresent([PendingBackgroundTask].self, forKey: .pendingBackgroundTasks) ?? []
        self.itemCount = try c.decodeIfPresent(Int.self, forKey: .itemCount) ?? 0
        self.visibleItemCount = try c.decodeIfPresent(Int.self, forKey: .visibleItemCount) ?? 0
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        self.archivedAt = try c.decodeIfPresent(Date.self, forKey: .archivedAt)
        self.settledOverride = try c.decodeIfPresent(String.self, forKey: .settledOverride)
        self.settledAt = try c.decodeIfPresent(Date.self, forKey: .settledAt)
        self.unsettledAt = try c.decodeIfPresent(Date.self, forKey: .unsettledAt)
        self.snoozedUntil = try c.decodeIfPresent(Date.self, forKey: .snoozedUntil)
        self.pinnedAt = try c.decodeIfPresent(Date.self, forKey: .pinnedAt)
        self.lastVisitedAt = try c.decodeIfPresent(Date.self, forKey: .lastVisitedAt)
        self.deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    public init(
        id: String,
        projectId: String,
        title: String,
        providerInstanceId: String,
        modelSelection: ModelSelection,
        runtimeMode: RuntimeMode = .fullAccess,
        interactionMode: ProviderInteractionMode = .default,
        branch: String? = nil,
        worktreePath: String? = nil,
        linkedPullRequest: ThreadLinkedPullRequest? = nil,
        branchPullRequest: ThreadLinkedPullRequest? = nil,
        pullRequests: [ThreadPullRequestLink] = [],
        issues: [ThreadIssueLink] = [],
        lineage: ThreadLineage? = nil,
        activeProviderThreadId: String? = nil,
        latestRunId: String? = nil,
        latestRunRequestedAt: Date? = nil,
        latestRunStartedAt: Date? = nil,
        latestRunCompletedAt: Date? = nil,
        latestRunStopRequested: Bool? = nil,
        activeRunId: String? = nil,
        activityRunStartedAt: Date? = nil,
        activityRunStatus: String? = nil,
        blockedOnThreadWait: Bool? = nil,
        status: ShellThreadStatus = .idle,
        lastError: String? = nil,
        lastErrorClass: String? = nil,
        lastErrorCode: String? = nil,
        usageLimitResetAt: String? = nil,
        pendingRuntimeRequest: PendingRuntimeRequestSummary? = nil,
        pendingGuestMessageCount: Int? = nil,
        latestVisibleMessage: LatestVisibleMessageSummary? = nil,
        latestUserMessageAt: Date? = nil,
        hasActionableProposedPlan: Bool = false,
        pendingBackgroundTasks: [PendingBackgroundTask] = [],
        itemCount: Int = 0,
        visibleItemCount: Int = 0,
        createdAt: Date,
        updatedAt: Date,
        archivedAt: Date? = nil,
        settledOverride: String? = nil,
        settledAt: Date? = nil,
        unsettledAt: Date? = nil,
        snoozedUntil: Date? = nil,
        pinnedAt: Date? = nil,
        lastVisitedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.providerInstanceId = providerInstanceId
        self.modelSelection = modelSelection
        self.runtimeMode = runtimeMode
        self.interactionMode = interactionMode
        self.branch = branch
        self.worktreePath = worktreePath
        self.linkedPullRequest = linkedPullRequest
        self.branchPullRequest = branchPullRequest
        self.pullRequests = pullRequests
        self.issues = issues
        self.lineage = lineage ?? ThreadLineage(rootThreadId: id)
        self.activeProviderThreadId = activeProviderThreadId
        self.latestRunId = latestRunId
        self.latestRunRequestedAt = latestRunRequestedAt
        self.latestRunStartedAt = latestRunStartedAt
        self.latestRunCompletedAt = latestRunCompletedAt
        self.latestRunStopRequested = latestRunStopRequested
        self.activeRunId = activeRunId
        self.activityRunStartedAt = activityRunStartedAt
        self.activityRunStatus = activityRunStatus
        self.blockedOnThreadWait = blockedOnThreadWait
        self.status = status
        self.lastError = lastError
        self.lastErrorClass = lastErrorClass
        self.lastErrorCode = lastErrorCode
        self.usageLimitResetAt = usageLimitResetAt
        self.pendingRuntimeRequest = pendingRuntimeRequest
        self.pendingGuestMessageCount = pendingGuestMessageCount
        self.latestVisibleMessage = latestVisibleMessage
        self.latestUserMessageAt = latestUserMessageAt
        self.hasActionableProposedPlan = hasActionableProposedPlan
        self.pendingBackgroundTasks = pendingBackgroundTasks
        self.itemCount = itemCount
        self.visibleItemCount = visibleItemCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
        self.settledOverride = settledOverride
        self.settledAt = settledAt
        self.unsettledAt = unsettledAt
        self.snoozedUntil = snoozedUntil
        self.pinnedAt = pinnedAt
        self.lastVisitedAt = lastVisitedAt
        self.deletedAt = deletedAt
    }
}

public struct ShellSnapshot: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let snapshotSequence: Int
    public let projects: [ProjectShell]
    public let threads: [ThreadShell]
    public let archivedThreads: [ThreadShell]

    public init(
        schemaVersion: Int = 2,
        snapshotSequence: Int,
        projects: [ProjectShell],
        threads: [ThreadShell],
        archivedThreads: [ThreadShell] = []
    ) {
        self.schemaVersion = schemaVersion
        self.snapshotSequence = snapshotSequence
        self.projects = projects
        self.threads = threads
        self.archivedThreads = archivedThreads
    }
}

public enum ShellThreadLocation: String, Codable, Sendable, Hashable {
    case active
    case archive
}

public struct SubscribeShellInput: Encodable, Sendable {
    public let afterSequence: Int?
    public let requestCompletionMarker: Bool?
    public let omitIdleSubagents: Bool?
    public let omitOlderSettled: Bool?

    public init(
        afterSequence: Int? = nil,
        requestCompletionMarker: Bool? = true,
        omitIdleSubagents: Bool? = nil,
        omitOlderSettled: Bool? = nil
    ) {
        self.afterSequence = afterSequence
        self.requestCompletionMarker = requestCompletionMarker
        self.omitIdleSubagents = omitIdleSubagents
        self.omitOlderSettled = omitOlderSettled
    }
}

public enum ShellStreamItem: Sendable, Equatable {
    case snapshot(ShellSnapshot, resolvedRepositoryIdentityRoots: [String]?)
    case synchronized
    case snapshotRequired
    case projectUpdated(sequence: Int, project: ProjectShell)
    case projectRemoved(sequence: Int, projectId: String)
    case threadUpdated(sequence: Int, location: ShellThreadLocation, thread: ThreadShell)
    case threadRemoved(sequence: Int, location: ShellThreadLocation, threadId: String)
    case unknown(kind: String)
}

extension ShellStreamItem: Decodable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case snapshot
        case resolvedRepositoryIdentityRoots
        case sequence
        case project
        case projectId
        case location
        case thread
        case threadId
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "snapshot":
            let snapshot = try c.decode(ShellSnapshot.self, forKey: .snapshot)
            let roots = try c.decodeIfPresent([String].self, forKey: .resolvedRepositoryIdentityRoots)
            self = .snapshot(snapshot, resolvedRepositoryIdentityRoots: roots)
        case "synchronized":
            self = .synchronized
        case "snapshot-required":
            self = .snapshotRequired
        case "project.updated":
            self = .projectUpdated(
                sequence: try c.decode(Int.self, forKey: .sequence),
                project: try c.decode(ProjectShell.self, forKey: .project)
            )
        case "project.removed":
            self = .projectRemoved(
                sequence: try c.decode(Int.self, forKey: .sequence),
                projectId: try c.decode(String.self, forKey: .projectId)
            )
        case "thread.updated":
            self = .threadUpdated(
                sequence: try c.decode(Int.self, forKey: .sequence),
                location: try c.decode(ShellThreadLocation.self, forKey: .location),
                thread: try c.decode(ThreadShell.self, forKey: .thread)
            )
        case "thread.removed":
            self = .threadRemoved(
                sequence: try c.decode(Int.self, forKey: .sequence),
                location: try c.decode(ShellThreadLocation.self, forKey: .location),
                threadId: try c.decode(String.self, forKey: .threadId)
            )
        default:
            self = .unknown(kind: kind)
        }
    }
}

// MARK: - Thread Detail Projection & Turn Items

public struct AppThread: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let projectId: String
    public let title: String
    public let providerInstanceId: String
    public let modelSelection: ModelSelection
    public let runtimeMode: RuntimeMode
    public let interactionMode: ProviderInteractionMode
    public let branch: String?
    public let worktreePath: String?
    public let linkedPullRequest: ThreadLinkedPullRequest?
    public let branchPullRequest: ThreadLinkedPullRequest?
    public let pullRequests: [ThreadPullRequestLink]
    public let issues: [ThreadIssueLink]
    public var activeProviderThreadId: String?
    public let lineage: ThreadLineage
    public let createdAt: Date
    public let updatedAt: Date
    public let archivedAt: Date?
    public let settledOverride: String?
    public let settledAt: Date?
    public let snoozedUntil: Date?
    public let pinnedAt: Date?
    public var lastVisitedAt: Date?
    public let deletedAt: Date?

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.projectId = try c.decode(String.self, forKey: .projectId)
        self.title = try c.decode(String.self, forKey: .title)
        self.providerInstanceId = try c.decode(String.self, forKey: .providerInstanceId)
        self.modelSelection = try c.decode(ModelSelection.self, forKey: .modelSelection)
        self.runtimeMode = try c.decode(RuntimeMode.self, forKey: .runtimeMode)
        self.interactionMode = try c.decode(ProviderInteractionMode.self, forKey: .interactionMode)
        self.branch = try c.decodeIfPresent(String.self, forKey: .branch)
        self.worktreePath = try c.decodeIfPresent(String.self, forKey: .worktreePath)
        self.linkedPullRequest = try c.decodeIfPresent(ThreadLinkedPullRequest.self, forKey: .linkedPullRequest)
        self.branchPullRequest = try c.decodeIfPresent(ThreadLinkedPullRequest.self, forKey: .branchPullRequest)
        self.pullRequests = try c.decodeIfPresent([ThreadPullRequestLink].self, forKey: .pullRequests) ?? []
        self.issues = try c.decodeIfPresent([ThreadIssueLink].self, forKey: .issues) ?? []
        self.activeProviderThreadId = try c.decodeIfPresent(String.self, forKey: .activeProviderThreadId)
        self.lineage = try c.decode(ThreadLineage.self, forKey: .lineage)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        self.archivedAt = try c.decodeIfPresent(Date.self, forKey: .archivedAt)
        self.settledOverride = try c.decodeIfPresent(String.self, forKey: .settledOverride)
        self.settledAt = try c.decodeIfPresent(Date.self, forKey: .settledAt)
        self.snoozedUntil = try c.decodeIfPresent(Date.self, forKey: .snoozedUntil)
        self.pinnedAt = try c.decodeIfPresent(Date.self, forKey: .pinnedAt)
        self.lastVisitedAt = try c.decodeIfPresent(Date.self, forKey: .lastVisitedAt)
        self.deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    public init(
        id: String,
        projectId: String,
        title: String,
        providerInstanceId: String,
        modelSelection: ModelSelection,
        runtimeMode: RuntimeMode = .fullAccess,
        interactionMode: ProviderInteractionMode = .default,
        branch: String? = nil,
        worktreePath: String? = nil,
        linkedPullRequest: ThreadLinkedPullRequest? = nil,
        branchPullRequest: ThreadLinkedPullRequest? = nil,
        pullRequests: [ThreadPullRequestLink] = [],
        issues: [ThreadIssueLink] = [],
        activeProviderThreadId: String? = nil,
        lineage: ThreadLineage? = nil,
        createdAt: Date,
        updatedAt: Date,
        archivedAt: Date? = nil,
        settledOverride: String? = nil,
        settledAt: Date? = nil,
        snoozedUntil: Date? = nil,
        pinnedAt: Date? = nil,
        lastVisitedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.providerInstanceId = providerInstanceId
        self.modelSelection = modelSelection
        self.runtimeMode = runtimeMode
        self.interactionMode = interactionMode
        self.branch = branch
        self.worktreePath = worktreePath
        self.linkedPullRequest = linkedPullRequest
        self.branchPullRequest = branchPullRequest
        self.pullRequests = pullRequests
        self.issues = issues
        self.activeProviderThreadId = activeProviderThreadId
        self.lineage = lineage ?? ThreadLineage(rootThreadId: id)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
        self.settledOverride = settledOverride
        self.settledAt = settledAt
        self.snoozedUntil = snoozedUntil
        self.pinnedAt = pinnedAt
        self.lastVisitedAt = lastVisitedAt
        self.deletedAt = deletedAt
    }
}

public struct ThreadVisit: Codable, Sendable, Equatable {
    public let lastVisitedAt: Date?
}

public struct RunOutput: Codable, Sendable, Equatable {
    public let value: JSONValue
    public let submittedAt: String
}

public struct Run: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let threadId: String
    public let ordinal: Int
    public let providerInstanceId: String
    public let modelSelection: ModelSelection
    public let providerThreadId: String?
    public let userMessageId: String
    public let rootNodeId: String?
    public let activeAttemptId: String?
    public let status: RunStatus
    public let queuePosition: Int?
    public let queueHeld: Bool?
    public let requestedAt: Date
    public let startedAt: Date?
    public let completedAt: Date?
    public let workStartedAt: Date?
    public var output: RunOutput?

    public init(
        id: String,
        threadId: String,
        ordinal: Int,
        providerInstanceId: String,
        modelSelection: ModelSelection,
        providerThreadId: String? = nil,
        userMessageId: String,
        rootNodeId: String? = nil,
        activeAttemptId: String? = nil,
        status: RunStatus,
        queuePosition: Int? = nil,
        queueHeld: Bool? = nil,
        requestedAt: Date,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        workStartedAt: Date? = nil,
        output: RunOutput? = nil
    ) {
        self.id = id
        self.threadId = threadId
        self.ordinal = ordinal
        self.providerInstanceId = providerInstanceId
        self.modelSelection = modelSelection
        self.providerThreadId = providerThreadId
        self.userMessageId = userMessageId
        self.rootNodeId = rootNodeId
        self.activeAttemptId = activeAttemptId
        self.status = status
        self.queuePosition = queuePosition
        self.queueHeld = queueHeld
        self.requestedAt = requestedAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.workStartedAt = workStartedAt
        self.output = output
    }
}

public struct RunAttempt: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let runId: String
    public let attemptOrdinal: Int
    public let rootNodeId: String
    public let providerInstanceId: String
    public let providerThreadId: String
    public let providerTurnId: String?
    public let reason: String
    public let status: String
    public let startedAt: Date?
    public let completedAt: Date?

    public init(
        id: String,
        runId: String,
        attemptOrdinal: Int,
        rootNodeId: String,
        providerInstanceId: String,
        providerThreadId: String,
        providerTurnId: String? = nil,
        reason: String,
        status: String,
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.runId = runId
        self.attemptOrdinal = attemptOrdinal
        self.rootNodeId = rootNodeId
        self.providerInstanceId = providerInstanceId
        self.providerThreadId = providerThreadId
        self.providerTurnId = providerTurnId
        self.reason = reason
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

public struct ChatAttachment: Codable, Sendable, Equatable, Identifiable {
    public let type: String
    public let id: String
    public let name: String
    public let mimeType: String
    public let sizeBytes: Int

    public init(type: String, id: String, name: String, mimeType: String, sizeBytes: Int) {
        self.type = type
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
    }
}

public struct ConversationMessage: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let threadId: String
    public let runId: String?
    public let nodeId: String?
    public let role: String
    public let text: String
    public let attachments: [ChatAttachment]
    public let streaming: Bool
    public let createdAt: Date
    public let updatedAt: Date

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.threadId = try c.decode(String.self, forKey: .threadId)
        self.runId = try c.decodeIfPresent(String.self, forKey: .runId)
        self.nodeId = try c.decodeIfPresent(String.self, forKey: .nodeId)
        self.role = try c.decode(String.self, forKey: .role)
        self.text = try c.decode(String.self, forKey: .text)
        self.attachments = try c.decodeIfPresent([ChatAttachment].self, forKey: .attachments) ?? []
        self.streaming = try c.decode(Bool.self, forKey: .streaming)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }

    public init(
        id: String,
        threadId: String,
        runId: String? = nil,
        nodeId: String? = nil,
        role: String,
        text: String,
        attachments: [ChatAttachment] = [],
        streaming: Bool = false,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.threadId = threadId
        self.runId = runId
        self.nodeId = nodeId
        self.role = role
        self.text = text
        self.attachments = attachments
        self.streaming = streaming
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum ProviderApprovalDecision: String, Codable, Sendable, CaseIterable, Hashable {
    case accept
    case acceptForSession
    case acceptAlways
    case decline
    case cancel
}

public struct ProviderApprovalOption: Codable, Sendable, Equatable {
    public let decision: ProviderApprovalDecision
    public let label: String
    public let warning: String?

    public init(decision: ProviderApprovalDecision, label: String, warning: String? = nil) {
        self.decision = decision
        self.label = label
        self.warning = warning
    }
}

public enum RuntimeRequestResponseCapability: Sendable, Equatable, Codable {
    case live(providerSessionId: String, supportsFeedback: Bool?)
    case message
    case notResumable(reason: String)
    case unknown(type: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case providerSessionId
        case supportsFeedback
        case reason
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "live":
            self = .live(
                providerSessionId: try c.decode(String.self, forKey: .providerSessionId),
                supportsFeedback: try c.decodeIfPresent(Bool.self, forKey: .supportsFeedback)
            )
        case "message":
            self = .message
        case "not_resumable":
            self = .notResumable(reason: try c.decode(String.self, forKey: .reason))
        default:
            self = .unknown(type: type)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .live(let sessionId, let supportsFeedback):
            try c.encode("live", forKey: .type)
            try c.encode(sessionId, forKey: .providerSessionId)
            try c.encodeIfPresent(supportsFeedback, forKey: .supportsFeedback)
        case .message:
            try c.encode("message", forKey: .type)
        case .notResumable(let reason):
            try c.encode("not_resumable", forKey: .type)
            try c.encode(reason, forKey: .reason)
        case .unknown(let type):
            try c.encode(type, forKey: .type)
        }
    }
}

public struct RuntimeRequest: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let nodeId: String
    public let providerTurnId: String?
    public let kind: String
    public let status: String
    public let responseCapability: RuntimeRequestResponseCapability
    public let createdAt: Date
    public let resolvedAt: Date?
    public let decision: ProviderApprovalDecision?
    public let feedback: String?
    public let answers: [String: JSONValue]?

    public var isPending: Bool { status == "pending" }
    public var isApproval: Bool { kind != "user_input" && kind != "auth_refresh" }
    public var isUserInput: Bool { kind == "user_input" }

    public init(
        id: String,
        nodeId: String,
        providerTurnId: String? = nil,
        kind: String,
        status: String,
        responseCapability: RuntimeRequestResponseCapability,
        createdAt: Date,
        resolvedAt: Date? = nil,
        decision: ProviderApprovalDecision? = nil,
        feedback: String? = nil,
        answers: [String: JSONValue]? = nil
    ) {
        self.id = id
        self.nodeId = nodeId
        self.providerTurnId = providerTurnId
        self.kind = kind
        self.status = status
        self.responseCapability = responseCapability
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
        self.decision = decision
        self.feedback = feedback
        self.answers = answers
    }
}

public struct PlanStep: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let text: String
    public let status: String
    public let durationMs: Int?

    public init(id: String, text: String, status: String, durationMs: Int? = nil) {
        self.id = id
        self.text = text
        self.status = status
        self.durationMs = durationMs
    }
}

public struct PlanArtifact: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let threadId: String
    public let runId: String?
    public let nodeId: String
    public let status: String
    public let kind: String
    public let markdown: String?
    public let steps: [PlanStep]?
    public let explanation: String?

    public init(
        id: String,
        threadId: String,
        runId: String? = nil,
        nodeId: String,
        status: String,
        kind: String,
        markdown: String? = nil,
        steps: [PlanStep]? = nil,
        explanation: String? = nil
    ) {
        self.id = id
        self.threadId = threadId
        self.runId = runId
        self.nodeId = nodeId
        self.status = status
        self.kind = kind
        self.markdown = markdown
        self.steps = steps
        self.explanation = explanation
    }
}

public struct UserInputQuestionOption: Codable, Sendable, Equatable {
    public let label: String
    public let description: String
    public let value: String?
    public let preview: String?

    public init(label: String, description: String, value: String? = nil, preview: String? = nil) {
        self.label = label
        self.description = description
        self.value = value
        self.preview = preview
    }
}

public struct UserInputQuestion: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let header: String
    public let question: String
    public let options: [UserInputQuestionOption]
    public let multiSelect: Bool?
    public let allowCustomAnswer: Bool?
    public let initialAnswer: String?
    public let required: Bool?

    public init(
        id: String,
        header: String,
        question: String,
        options: [UserInputQuestionOption],
        multiSelect: Bool? = nil,
        allowCustomAnswer: Bool? = nil,
        initialAnswer: String? = nil,
        required: Bool? = nil
    ) {
        self.id = id
        self.header = header
        self.question = question
        self.options = options
        self.multiSelect = multiSelect
        self.allowCustomAnswer = allowCustomAnswer
        self.initialAnswer = initialAnswer
        self.required = required
    }
}

public struct FileChangeDetail: Codable, Sendable, Equatable {
    public let operation: String
    public let path: String
    public let oldPath: String?
    public let fileType: String?
    public let mimeType: String?
}

public struct FileSearchResult: Codable, Sendable, Equatable {
    public let fileName: String
    public let line: Int?
    public let column: Int?
    public let preview: String?
}

public struct WebSearchResult: Codable, Sendable, Equatable {
    public let title: String?
    public let url: String?
    public let snippet: String?
}

public struct CheckpointFileSummary: Codable, Sendable, Equatable {
    public let path: String
    public let kind: String
    public let additions: Int
    public let deletions: Int
}

public struct ProviderFailure: Codable, Sendable, Equatable {
    public let failureClass: String
    public let message: String
    public let code: String?
    public let retryable: Bool?
    public let resetAt: String?

    private enum CodingKeys: String, CodingKey {
        case failureClass = "class"
        case message
        case code
        case retryable
        case resetAt
    }

    public init(
        failureClass: String,
        message: String,
        code: String? = nil,
        retryable: Bool? = nil,
        resetAt: String? = nil
    ) {
        self.failureClass = failureClass
        self.message = message
        self.code = code
        self.retryable = retryable
        self.resetAt = resetAt
    }
}

public struct ProviderThreadSummary: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let driver: String
    public let providerInstanceId: String
    public let providerSessionId: String?
    public let appThreadId: String?
    public let status: String
    public let firstRunOrdinal: Int?
    public let lastRunOrdinal: Int?
    public let nativeThreadRef: JSONValue?

    public var isQueuedPlaceholder: Bool {
        status == "not_loaded"
            && firstRunOrdinal == nil
            && (nativeThreadRef == nil || nativeThreadRef == .null)
            && providerSessionId == nil
    }
}

public struct SubagentSummary: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let threadId: String
    public let runId: String?
    public let origin: String
    public let driver: String
    public let providerInstanceId: String
    public let childThreadId: String?
    public let prompt: String
    public let title: String?
    public let model: String?
    public let status: String
    public let progress: String?
    public let result: String?
    public let startedAt: Date?
    public let completedAt: Date?
    public let updatedAt: Date
}

// MARK: - TurnItem

public enum TurnItemKind: Sendable, Equatable {
    case userMessage(
        messageId: String,
        text: String,
        inputIntent: String,
        attachments: [ChatAttachment],
        createdBy: String,
        creationSource: String
    )
    case assistantMessage(
        messageId: String,
        text: String,
        streaming: Bool,
        phase: String?,
        delivery: String?,
        attachments: [ChatAttachment]
    )
    case reasoning(text: String, streaming: Bool)
    case proposedPlan(planId: String, markdown: String, streaming: Bool)
    case todoList(planId: String, steps: [PlanStep], explanation: String?)
    case commandExecution(
        input: String,
        output: String?,
        outputOmitted: Bool,
        outputIndicatesFailure: Bool?,
        exitCode: Int?,
        monitor: Bool?
    )
    case fileChange(
        fileName: String,
        additions: Int?,
        deletions: Int?,
        diffStr: String?,
        oldStr: String?,
        newStr: String?,
        changes: [FileChangeDetail]?
    )
    case fileSearch(pattern: String?, results: [FileSearchResult]?)
    case webSearch(patterns: [String]?, results: [WebSearchResult]?)
    case dynamicTool(
        toolName: String?,
        viewedImagePath: String?,
        input: JSONValue?,
        output: JSONValue?,
        outputOmitted: Bool
    )
    case approvalRequest(
        requestId: String,
        requestKind: String,
        prompt: String?,
        reason: String?,
        fullAccessOverride: String?,
        appName: String?,
        options: [ProviderApprovalOption]?
    )
    case userInputRequest(
        requestId: String,
        questions: [UserInputQuestion],
        responseMode: String?
    )
    case subagent(
        subagentId: String,
        origin: String,
        driver: String,
        providerInstanceId: String,
        childThreadId: String?,
        prompt: String,
        progress: String?,
        result: String?
    )
    case checkpoint(checkpointId: String, scopeId: String, files: [CheckpointFileSummary])
    case notification(outcome: String, summary: String, detail: String?)
    case runInterruptRequest(message: String, unresponsiveAt: Date?)
    case runInterruptResult(message: String)
    case systemNotice(message: String, level: String?)
    case error(failure: ProviderFailure)
    case compaction(driver: String?, summary: String?, beforeTokenCount: Int?, afterTokenCount: Int?)
    case handoff(
        contextHandoffId: String,
        toProviderInstanceId: String,
        toModel: String?,
        strategy: String,
        summary: String?
    )
    case fork(targetThreadId: String)
    case threadCreated(
        targetThreadId: String,
        targetRunId: String?,
        targetProviderInstanceId: String,
        targetModel: String
    )
    case secretRequest(label: String, reason: String, url: String?, secretStatus: String)
    case linkRequest(url: String?, reason: String, hint: String?, linkStatus: String)
    case unknown(type: String, raw: JSONValue)

    public var typeName: String {
        switch self {
        case .userMessage: return "user_message"
        case .assistantMessage: return "assistant_message"
        case .reasoning: return "reasoning"
        case .proposedPlan: return "proposed_plan"
        case .todoList: return "todo_list"
        case .commandExecution: return "command_execution"
        case .fileChange: return "file_change"
        case .fileSearch: return "file_search"
        case .webSearch: return "web_search"
        case .dynamicTool: return "dynamic_tool"
        case .approvalRequest: return "approval_request"
        case .userInputRequest: return "user_input_request"
        case .subagent: return "subagent"
        case .checkpoint: return "checkpoint"
        case .notification: return "notification"
        case .runInterruptRequest: return "run_interrupt_request"
        case .runInterruptResult: return "run_interrupt_result"
        case .systemNotice: return "system_notice"
        case .error: return "error"
        case .compaction: return "compaction"
        case .handoff: return "handoff"
        case .fork: return "fork"
        case .threadCreated: return "thread_created"
        case .secretRequest: return "secret_request"
        case .linkRequest: return "link_request"
        case .unknown(let type, _): return type
        }
    }
}

public struct TurnItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let threadId: String
    public let runId: String?
    public let nodeId: String?
    public let providerThreadId: String?
    public let providerTurnId: String?
    public let parentItemId: String?
    public let ordinal: Int
    public let status: String
    public let title: String?
    public let startedAt: Date?
    public let completedAt: Date?
    public let updatedAt: Date
    public let kind: TurnItemKind

    public init(
        id: String,
        threadId: String,
        runId: String? = nil,
        nodeId: String? = nil,
        providerThreadId: String? = nil,
        providerTurnId: String? = nil,
        parentItemId: String? = nil,
        ordinal: Int,
        status: String,
        title: String? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        updatedAt: Date,
        kind: TurnItemKind
    ) {
        self.id = id
        self.threadId = threadId
        self.runId = runId
        self.nodeId = nodeId
        self.providerThreadId = providerThreadId
        self.providerTurnId = providerTurnId
        self.parentItemId = parentItemId
        self.ordinal = ordinal
        self.status = status
        self.title = title
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.updatedAt = updatedAt
        self.kind = kind
    }
}

extension TurnItem: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, threadId, runId, nodeId, providerThreadId, providerTurnId, parentItemId
        case ordinal, status, title, startedAt, completedAt, updatedAt, type
        case messageId, text, inputIntent, attachments, createdBy, creationSource
        case streaming, phase, delivery
        case planId, markdown, steps, explanation
        case input, output, outputOmitted, outputIndicatesFailure, exitCode, monitor
        case fileName, additions, deletions, diffStr, oldStr, newStr, changes
        case pattern, patterns, results
        case toolName, viewedImagePath
        case requestId, requestKind, prompt, reason, fullAccessOverride, appName, options
        case questions, responseMode
        case subagentId, origin, driver, providerInstanceId, childThreadId, progress, result
        case checkpointId, scopeId, files
        case outcome, summary, detail
        case message, unresponsiveAt, level, failure
        case beforeTokenCount, afterTokenCount
        case contextHandoffId, toProviderInstanceId, toModel, strategy
        case targetThreadId, targetRunId, targetProviderInstanceId, targetModel
        case label, url, secretStatus, hint, linkStatus
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.threadId = try c.decode(String.self, forKey: .threadId)
        self.runId = try c.decodeIfPresent(String.self, forKey: .runId)
        self.nodeId = try c.decodeIfPresent(String.self, forKey: .nodeId)
        self.providerThreadId = try c.decodeIfPresent(String.self, forKey: .providerThreadId)
        self.providerTurnId = try c.decodeIfPresent(String.self, forKey: .providerTurnId)
        self.parentItemId = try c.decodeIfPresent(String.self, forKey: .parentItemId)
        self.ordinal = try c.decode(Int.self, forKey: .ordinal)
        self.status = try c.decode(String.self, forKey: .status)
        self.title = try c.decodeIfPresent(String.self, forKey: .title)
        self.startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        self.completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        self.updatedAt = try c.decode(Date.self, forKey: .updatedAt)

        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "user_message":
            self.kind = .userMessage(
                messageId: try c.decode(String.self, forKey: .messageId),
                text: try c.decode(String.self, forKey: .text),
                inputIntent: try c.decode(String.self, forKey: .inputIntent),
                attachments: try c.decodeIfPresent([ChatAttachment].self, forKey: .attachments) ?? [],
                createdBy: try c.decodeIfPresent(String.self, forKey: .createdBy) ?? "user",
                creationSource: try c.decodeIfPresent(String.self, forKey: .creationSource) ?? "web"
            )
        case "assistant_message":
            self.kind = .assistantMessage(
                messageId: try c.decode(String.self, forKey: .messageId),
                text: try c.decode(String.self, forKey: .text),
                streaming: try c.decode(Bool.self, forKey: .streaming),
                phase: try c.decodeIfPresent(String.self, forKey: .phase),
                delivery: try c.decodeIfPresent(String.self, forKey: .delivery),
                attachments: try c.decodeIfPresent([ChatAttachment].self, forKey: .attachments) ?? []
            )
        case "reasoning":
            self.kind = .reasoning(
                text: try c.decode(String.self, forKey: .text),
                streaming: try c.decode(Bool.self, forKey: .streaming)
            )
        case "proposed_plan":
            self.kind = .proposedPlan(
                planId: try c.decode(String.self, forKey: .planId),
                markdown: try c.decode(String.self, forKey: .markdown),
                streaming: try c.decode(Bool.self, forKey: .streaming)
            )
        case "todo_list":
            self.kind = .todoList(
                planId: try c.decode(String.self, forKey: .planId),
                steps: try c.decode([PlanStep].self, forKey: .steps),
                explanation: try c.decodeIfPresent(String.self, forKey: .explanation)
            )
        case "command_execution":
            self.kind = .commandExecution(
                input: try c.decode(String.self, forKey: .input),
                output: try c.decodeIfPresent(String.self, forKey: .output),
                outputOmitted: try c.decodeIfPresent(Bool.self, forKey: .outputOmitted) ?? false,
                outputIndicatesFailure: try c.decodeIfPresent(Bool.self, forKey: .outputIndicatesFailure),
                exitCode: try c.decodeIfPresent(Int.self, forKey: .exitCode),
                monitor: try c.decodeIfPresent(Bool.self, forKey: .monitor)
            )
        case "file_change":
            self.kind = .fileChange(
                fileName: try c.decode(String.self, forKey: .fileName),
                additions: try c.decodeIfPresent(Int.self, forKey: .additions),
                deletions: try c.decodeIfPresent(Int.self, forKey: .deletions),
                diffStr: try c.decodeIfPresent(String.self, forKey: .diffStr),
                oldStr: try c.decodeIfPresent(String.self, forKey: .oldStr),
                newStr: try c.decodeIfPresent(String.self, forKey: .newStr),
                changes: try c.decodeIfPresent([FileChangeDetail].self, forKey: .changes)
            )
        case "file_search":
            self.kind = .fileSearch(
                pattern: try c.decodeIfPresent(String.self, forKey: .pattern),
                results: try c.decodeIfPresent([FileSearchResult].self, forKey: .results)
            )
        case "web_search":
            self.kind = .webSearch(
                patterns: try c.decodeIfPresent([String].self, forKey: .patterns),
                results: try c.decodeIfPresent([WebSearchResult].self, forKey: .results)
            )
        case "dynamic_tool":
            self.kind = .dynamicTool(
                toolName: try c.decodeIfPresent(String.self, forKey: .toolName),
                viewedImagePath: try c.decodeIfPresent(String.self, forKey: .viewedImagePath),
                input: try c.decodeIfPresent(JSONValue.self, forKey: .input),
                output: try c.decodeIfPresent(JSONValue.self, forKey: .output),
                outputOmitted: try c.decodeIfPresent(Bool.self, forKey: .outputOmitted) ?? false
            )
        case "approval_request":
            self.kind = .approvalRequest(
                requestId: try c.decode(String.self, forKey: .requestId),
                requestKind: try c.decode(String.self, forKey: .requestKind),
                prompt: try c.decodeIfPresent(String.self, forKey: .prompt),
                reason: try c.decodeIfPresent(String.self, forKey: .reason),
                fullAccessOverride: try c.decodeIfPresent(String.self, forKey: .fullAccessOverride),
                appName: try c.decodeIfPresent(String.self, forKey: .appName),
                options: try c.decodeIfPresent([ProviderApprovalOption].self, forKey: .options)
            )
        case "user_input_request":
            self.kind = .userInputRequest(
                requestId: try c.decode(String.self, forKey: .requestId),
                questions: try c.decode([UserInputQuestion].self, forKey: .questions),
                responseMode: try c.decodeIfPresent(String.self, forKey: .responseMode)
            )
        case "subagent":
            self.kind = .subagent(
                subagentId: try c.decode(String.self, forKey: .subagentId),
                origin: try c.decode(String.self, forKey: .origin),
                driver: try c.decode(String.self, forKey: .driver),
                providerInstanceId: try c.decode(String.self, forKey: .providerInstanceId),
                childThreadId: try c.decodeIfPresent(String.self, forKey: .childThreadId),
                prompt: try c.decode(String.self, forKey: .prompt),
                progress: try c.decodeIfPresent(String.self, forKey: .progress),
                result: try c.decodeIfPresent(String.self, forKey: .result)
            )
        case "checkpoint":
            self.kind = .checkpoint(
                checkpointId: try c.decode(String.self, forKey: .checkpointId),
                scopeId: try c.decode(String.self, forKey: .scopeId),
                files: try c.decodeIfPresent([CheckpointFileSummary].self, forKey: .files) ?? []
            )
        case "notification":
            self.kind = .notification(
                outcome: try c.decode(String.self, forKey: .outcome),
                summary: try c.decode(String.self, forKey: .summary),
                detail: try c.decodeIfPresent(String.self, forKey: .detail)
            )
        case "run_interrupt_request":
            self.kind = .runInterruptRequest(
                message: try c.decode(String.self, forKey: .message),
                unresponsiveAt: try c.decodeIfPresent(Date.self, forKey: .unresponsiveAt)
            )
        case "run_interrupt_result":
            self.kind = .runInterruptResult(message: try c.decode(String.self, forKey: .message))
        case "system_notice":
            self.kind = .systemNotice(
                message: try c.decode(String.self, forKey: .message),
                level: try c.decodeIfPresent(String.self, forKey: .level)
            )
        case "error":
            self.kind = .error(failure: try c.decode(ProviderFailure.self, forKey: .failure))
        case "compaction":
            self.kind = .compaction(
                driver: try c.decodeIfPresent(String.self, forKey: .driver),
                summary: try c.decodeIfPresent(String.self, forKey: .summary),
                beforeTokenCount: try c.decodeIfPresent(Int.self, forKey: .beforeTokenCount),
                afterTokenCount: try c.decodeIfPresent(Int.self, forKey: .afterTokenCount)
            )
        case "handoff":
            self.kind = .handoff(
                contextHandoffId: try c.decode(String.self, forKey: .contextHandoffId),
                toProviderInstanceId: try c.decode(String.self, forKey: .toProviderInstanceId),
                toModel: try c.decodeIfPresent(String.self, forKey: .toModel),
                strategy: try c.decode(String.self, forKey: .strategy),
                summary: try c.decodeIfPresent(String.self, forKey: .summary)
            )
        case "fork":
            self.kind = .fork(targetThreadId: try c.decode(String.self, forKey: .targetThreadId))
        case "thread_created":
            self.kind = .threadCreated(
                targetThreadId: try c.decode(String.self, forKey: .targetThreadId),
                targetRunId: try c.decodeIfPresent(String.self, forKey: .targetRunId),
                targetProviderInstanceId: try c.decode(String.self, forKey: .targetProviderInstanceId),
                targetModel: try c.decode(String.self, forKey: .targetModel)
            )
        case "secret_request":
            self.kind = .secretRequest(
                label: try c.decode(String.self, forKey: .label),
                reason: try c.decode(String.self, forKey: .reason),
                url: try c.decodeIfPresent(String.self, forKey: .url),
                secretStatus: try c.decode(String.self, forKey: .secretStatus)
            )
        case "link_request":
            self.kind = .linkRequest(
                url: try c.decodeIfPresent(String.self, forKey: .url),
                reason: try c.decode(String.self, forKey: .reason),
                hint: try c.decodeIfPresent(String.self, forKey: .hint),
                linkStatus: try c.decode(String.self, forKey: .linkStatus)
            )
        default:
            let raw = try JSONValue(from: decoder)
            self.kind = .unknown(type: type, raw: raw)
        }
    }
}

public enum ProjectedTurnItemVisibility: String, Codable, Sendable, Hashable {
    case local
    case inherited
    case synthetic
}

public struct ProjectedTurnItem: Decodable, Sendable, Equatable, Identifiable {
    public var position: Int
    public let visibility: ProjectedTurnItemVisibility
    public let sourceThreadId: String
    public let sourceItemId: String
    public let item: TurnItem

    public var id: String { sourceItemId }

    public init(
        position: Int,
        visibility: ProjectedTurnItemVisibility,
        sourceThreadId: String,
        sourceItemId: String,
        item: TurnItem
    ) {
        self.position = position
        self.visibility = visibility
        self.sourceThreadId = sourceThreadId
        self.sourceItemId = sourceItemId
        self.item = item
    }
}

public struct ThreadProjection: Decodable, Sendable, Equatable {
    public var thread: AppThread
    public var runs: [Run]
    public var attempts: [RunAttempt]
    public var subagents: [SubagentSummary]
    public var providerThreads: [ProviderThreadSummary]
    public var runtimeRequests: [RuntimeRequest]
    public var messages: [ConversationMessage]
    public var plans: [PlanArtifact]
    public var turnItems: [TurnItem]
    public var visibleTurnItems: [ProjectedTurnItem]
    public var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case thread, runs, attempts, subagents, providerThreads
        case runtimeRequests, messages, plans, turnItems, visibleTurnItems, updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.thread = try c.decode(AppThread.self, forKey: .thread)
        self.runs = try c.decodeIfPresent([Run].self, forKey: .runs) ?? []
        self.attempts = try c.decodeIfPresent([RunAttempt].self, forKey: .attempts) ?? []
        self.subagents = try c.decodeIfPresent([SubagentSummary].self, forKey: .subagents) ?? []
        self.providerThreads = try c.decodeIfPresent([ProviderThreadSummary].self, forKey: .providerThreads) ?? []
        self.runtimeRequests = try c.decodeIfPresent([RuntimeRequest].self, forKey: .runtimeRequests) ?? []
        self.messages = try c.decodeIfPresent([ConversationMessage].self, forKey: .messages) ?? []
        self.plans = try c.decodeIfPresent([PlanArtifact].self, forKey: .plans) ?? []
        self.turnItems = try c.decodeIfPresent([TurnItem].self, forKey: .turnItems) ?? []
        self.visibleTurnItems = try c.decodeIfPresent([ProjectedTurnItem].self, forKey: .visibleTurnItems) ?? []
        self.updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }

    public init(
        thread: AppThread,
        runs: [Run] = [],
        attempts: [RunAttempt] = [],
        subagents: [SubagentSummary] = [],
        providerThreads: [ProviderThreadSummary] = [],
        runtimeRequests: [RuntimeRequest] = [],
        messages: [ConversationMessage] = [],
        plans: [PlanArtifact] = [],
        turnItems: [TurnItem] = [],
        visibleTurnItems: [ProjectedTurnItem] = [],
        updatedAt: Date
    ) {
        self.thread = thread
        self.runs = runs
        self.attempts = attempts
        self.subagents = subagents
        self.providerThreads = providerThreads
        self.runtimeRequests = runtimeRequests
        self.messages = messages
        self.plans = plans
        self.turnItems = turnItems
        self.visibleTurnItems = visibleTurnItems
        self.updatedAt = updatedAt
    }
}

// MARK: - Thread Stream & Domain Events

public struct SubscribeThreadInput: Encodable, Sendable {
    public let threadId: String
    public let afterSequence: Int?
    public let requestCompletionMarker: Bool?

    public init(
        threadId: String,
        afterSequence: Int? = nil,
        requestCompletionMarker: Bool? = true
    ) {
        self.threadId = threadId
        self.afterSequence = afterSequence
        self.requestCompletionMarker = requestCompletionMarker
    }
}

public enum DomainEventKind: Sendable, Equatable {
    case threadUpdated(AppThread, updatesActivityTimestamp: Bool)
    case threadVisitRecorded(ThreadVisit)
    case runUpserted(Run)
    case runOutputSubmitted(runId: String, output: RunOutput)
    case runAttemptUpserted(RunAttempt)
    case subagentUpdated(SubagentSummary)
    case providerThreadUpdated(ProviderThreadSummary)
    case runtimeRequestUpdated(RuntimeRequest)
    case messageUpdated(ConversationMessage)
    case turnItemUpdated(TurnItem)
    case planUpdated(PlanArtifact)
    case ignored(type: String)
}

public struct DomainEvent: Decodable, Sendable, Equatable {
    public let id: String
    public let threadId: String
    public let runId: String?
    public let nodeId: String?
    public let occurredAt: Date
    public let type: String
    public let kind: DomainEventKind

    private enum CodingKeys: String, CodingKey {
        case id, threadId, runId, nodeId, occurredAt, type, payload
    }

    private struct RunOutputSubmittedPayload: Decodable {
        let runId: String
        let output: RunOutput
    }

    private static let nonActivityThreadEvents: Set<String> = [
        "thread.visited",
        "thread.tags-updated",
        "thread.marked-unread",
    ]

    private static let activityThreadEvents: Set<String> = [
        "thread.created",
        "thread.archived",
        "thread.unarchived",
        "thread.deleted",
        "thread.settled",
        "thread.unsettled",
        "thread.snoozed",
        "thread.unsnoozed",
        "thread.auto-settle-set",
        "thread.pinned",
        "thread.unpinned",
        "thread.pin-reordered",
        "thread.active-reordered",
        "thread.metadata-updated",
        "thread.pull-request-synced",
        "thread.issue-synced",
        "thread.runtime-mode-updated",
        "thread.interaction-mode-updated",
        "thread.model-selection-updated",
        "thread.provider-switched",
        "thread.guest-share-updated",
    ]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.threadId = try c.decode(String.self, forKey: .threadId)
        self.runId = try c.decodeIfPresent(String.self, forKey: .runId)
        self.nodeId = try c.decodeIfPresent(String.self, forKey: .nodeId)
        self.occurredAt = try c.decode(Date.self, forKey: .occurredAt)
        let type = try c.decode(String.self, forKey: .type)
        self.type = type

        if Self.activityThreadEvents.contains(type) {
            self.kind = .threadUpdated(
                try c.decode(AppThread.self, forKey: .payload),
                updatesActivityTimestamp: true
            )
        } else if Self.nonActivityThreadEvents.contains(type) {
            self.kind = .threadUpdated(
                try c.decode(AppThread.self, forKey: .payload),
                updatesActivityTimestamp: false
            )
        } else {
            switch type {
            case "thread.visit-recorded":
                self.kind = .threadVisitRecorded(try c.decode(ThreadVisit.self, forKey: .payload))
            case "run.created", "run.updated":
                self.kind = .runUpserted(try c.decode(Run.self, forKey: .payload))
            case "run.output-submitted":
                let payload = try c.decode(RunOutputSubmittedPayload.self, forKey: .payload)
                self.kind = .runOutputSubmitted(runId: payload.runId, output: payload.output)
            case "run-attempt.created", "run-attempt.updated":
                self.kind = .runAttemptUpserted(try c.decode(RunAttempt.self, forKey: .payload))
            case "subagent.updated":
                self.kind = .subagentUpdated(try c.decode(SubagentSummary.self, forKey: .payload))
            case "provider-thread.updated":
                self.kind = .providerThreadUpdated(try c.decode(ProviderThreadSummary.self, forKey: .payload))
            case "runtime-request.updated":
                self.kind = .runtimeRequestUpdated(try c.decode(RuntimeRequest.self, forKey: .payload))
            case "message.updated":
                self.kind = .messageUpdated(try c.decode(ConversationMessage.self, forKey: .payload))
            case "turn-item.updated":
                self.kind = .turnItemUpdated(try c.decode(TurnItem.self, forKey: .payload))
            case "plan.updated":
                self.kind = .planUpdated(try c.decode(PlanArtifact.self, forKey: .payload))
            default:
                self.kind = .ignored(type: type)
            }
        }
    }

    public init(
        id: String,
        threadId: String,
        runId: String? = nil,
        nodeId: String? = nil,
        occurredAt: Date,
        type: String,
        kind: DomainEventKind
    ) {
        self.id = id
        self.threadId = threadId
        self.runId = runId
        self.nodeId = nodeId
        self.occurredAt = occurredAt
        self.type = type
        self.kind = kind
    }
}

public enum ThreadStreamItem: Sendable, Equatable {
    case snapshot(snapshotSequence: Int, projection: ThreadProjection)
    case synchronized
    case event(sequence: Int, event: DomainEvent)
    case unknownEvent(sequence: Int, eventType: String)
    case unknown(kind: String)
}

extension ThreadStreamItem: Decodable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case snapshotSequence
        case projection
        case sequence
        case event
    }

    private struct UnknownEventHeader: Decodable {
        let type: String
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "snapshot":
            self = .snapshot(
                snapshotSequence: try c.decode(Int.self, forKey: .snapshotSequence),
                projection: try c.decode(ThreadProjection.self, forKey: .projection)
            )
        case "synchronized":
            self = .synchronized
        case "event":
            let sequence = try c.decode(Int.self, forKey: .sequence)
            do {
                let event = try c.decode(DomainEvent.self, forKey: .event)
                self = .event(sequence: sequence, event: event)
            } catch {
                // Unknown future event payloads must still advance the resume sequence.
                let header = try? c.decode(UnknownEventHeader.self, forKey: .event)
                self = .unknownEvent(sequence: sequence, eventType: header?.type ?? "unknown")
            }
        default:
            self = .unknown(kind: kind)
        }
    }
}

// MARK: - Commands & Launch Thread

public enum MessageDispatchMode: Encodable, Sendable, Equatable {
    case startImmediately
    case queueAfterActive
    case steerActive(targetRunId: String)
    case restartActive(targetRunId: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case targetRunId
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .startImmediately:
            try c.encode("start_immediately", forKey: .type)
        case .queueAfterActive:
            try c.encode("queue_after_active", forKey: .type)
        case .steerActive(let targetRunId):
            try c.encode("steer_active", forKey: .type)
            try c.encode(targetRunId, forKey: .targetRunId)
        case .restartActive(let targetRunId):
            try c.encode("restart_active", forKey: .type)
            try c.encode(targetRunId, forKey: .targetRunId)
        }
    }
}

public enum MessageDeliveryIntent: String, Encodable, Sendable {
    case auto
    case steer
    case restart
}

/// Wire commands for `orchestration.dispatchCommand`.
public enum OrchestrationCommand: Encodable, Sendable {
    case createThread(
        commandId: String = UUID().uuidString,
        threadId: String = UUID().uuidString,
        projectId: String,
        title: String,
        titleRenamed: Bool? = nil,
        modelSelection: ModelSelection,
        runtimeMode: RuntimeMode = .fullAccess,
        interactionMode: ProviderInteractionMode = .default,
        branch: String? = nil,
        worktreePath: String? = nil
    )
    case dispatchMessage(
        commandId: String = UUID().uuidString,
        threadId: String,
        messageId: String = UUID().uuidString,
        text: String,
        attachments: [ChatAttachment] = [],
        modelSelection: ModelSelection? = nil,
        deliveryIntent: MessageDeliveryIntent? = nil,
        dispatchMode: MessageDispatchMode = .startImmediately,
        freshContext: Bool? = nil
    )
    case setRuntimeMode(
        commandId: String = UUID().uuidString,
        threadId: String,
        runtimeMode: RuntimeMode
    )
    case setInteractionMode(
        commandId: String = UUID().uuidString,
        threadId: String,
        interactionMode: ProviderInteractionMode
    )
    case setModelSelection(
        commandId: String = UUID().uuidString,
        threadId: String,
        modelSelection: ModelSelection
    )
    case stopThread(
        commandId: String = UUID().uuidString,
        threadId: String,
        reason: String? = nil
    )
    case interruptRun(
        commandId: String = UUID().uuidString,
        threadId: String,
        runId: String,
        reason: String? = nil,
        holdQueue: Bool? = true
    )
    case respondToRuntimeRequest(
        commandId: String = UUID().uuidString,
        threadId: String,
        requestId: String,
        decision: ProviderApprovalDecision? = nil,
        feedback: String? = nil,
        answers: [String: JSONValue]? = nil
    )
    case visitThread(
        commandId: String = UUID().uuidString,
        threadId: String,
        visitedAt: Date = Date(),
        opened: Bool? = nil
    )
    case markThreadUnread(
        commandId: String = UUID().uuidString,
        threadId: String
    )
    case archiveThread(commandId: String = UUID().uuidString, threadId: String)
    case unarchiveThread(commandId: String = UUID().uuidString, threadId: String)
    case deleteThread(commandId: String = UUID().uuidString, threadId: String, onlyIfUnused: Bool? = nil)
    case settleThread(commandId: String = UUID().uuidString, threadId: String)
    case unsettleThread(commandId: String = UUID().uuidString, threadId: String)
    case pinThread(commandId: String = UUID().uuidString, threadId: String)
    case unpinThread(commandId: String = UUID().uuidString, threadId: String)
    case updateThreadMetadata(
        commandId: String = UUID().uuidString,
        threadId: String,
        title: String? = nil,
        regenerateTitle: Bool? = nil
    )
    case forkThread(
        commandId: String = UUID().uuidString,
        sourceThreadId: String,
        targetThreadId: String = UUID().uuidString,
        sourcePoint: ThreadForkSourcePoint = .latestStable,
        title: String? = nil,
        sideChat: Bool? = nil
    )
    case linkPullRequest(
        commandId: String = UUID().uuidString,
        threadId: String,
        host: String,
        repository: String,
        number: Int,
        url: String,
        source: String = "manual"
    )
    case unlinkPullRequest(
        commandId: String = UUID().uuidString,
        threadId: String,
        host: String,
        repository: String,
        number: Int
    )
    case unlinkIssue(
        commandId: String = UUID().uuidString,
        threadId: String,
        tracker: String,
        host: String,
        scope: String,
        key: String
    )

    private enum CodingKeys: String, CodingKey {
        case type, commandId, createdBy, creationSource
        case threadId, projectId, title, titleRenamed, regenerateTitle
        case modelSelection, runtimeMode, interactionMode, branch, worktreePath
        case messageId, text, attachments, deliveryIntent, dispatchMode, freshContext
        case runId, reason, holdQueue
        case requestId, decision, feedback, answers
        case visitedAt, opened, onlyIfUnused
        case sourceThreadId, targetThreadId, sourcePoint, sideChat
        case host, repository, number, url, source, tracker, scope, key
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .createThread(
            let commandId,
            let threadId,
            let projectId,
            let title,
            let titleRenamed,
            let modelSelection,
            let runtimeMode,
            let interactionMode,
            let branch,
            let worktreePath
        ):
            try c.encode("thread.create", forKey: .type)
            try c.encode(commandId, forKey: .commandId)
            try c.encode("user", forKey: .createdBy)
            try c.encode("web", forKey: .creationSource)
            try c.encode(threadId, forKey: .threadId)
            try c.encode(projectId, forKey: .projectId)
            try c.encode(title, forKey: .title)
            try c.encodeIfPresent(titleRenamed, forKey: .titleRenamed)
            try c.encode(modelSelection, forKey: .modelSelection)
            try c.encode(runtimeMode, forKey: .runtimeMode)
            try c.encode(interactionMode, forKey: .interactionMode)
            // Required nullable keys (`Schema.NullOr`) must encode explicit `null` when nil.
            try c.encode(branch, forKey: .branch)
            try c.encode(worktreePath, forKey: .worktreePath)

        case .dispatchMessage(
            let commandId,
            let threadId,
            let messageId,
            let text,
            let attachments,
            let modelSelection,
            let deliveryIntent,
            let dispatchMode,
            let freshContext
        ):
            try c.encode("message.dispatch", forKey: .type)
            try c.encode(commandId, forKey: .commandId)
            try c.encode("user", forKey: .createdBy)
            try c.encode("web", forKey: .creationSource)
            try c.encode(threadId, forKey: .threadId)
            try c.encode(messageId, forKey: .messageId)
            try c.encode(text, forKey: .text)
            try c.encode(attachments, forKey: .attachments)
            try c.encodeIfPresent(modelSelection, forKey: .modelSelection)
            try c.encodeIfPresent(deliveryIntent, forKey: .deliveryIntent)
            try c.encode(dispatchMode, forKey: .dispatchMode)
            try c.encodeIfPresent(freshContext, forKey: .freshContext)

        case .setRuntimeMode(let commandId, let threadId, let runtimeMode):
            try c.encode("thread.runtime-mode.set", forKey: .type)
            try c.encode(commandId, forKey: .commandId)
            try c.encode(threadId, forKey: .threadId)
            try c.encode(runtimeMode, forKey: .runtimeMode)

        case .setInteractionMode(let commandId, let threadId, let interactionMode):
            try c.encode("thread.interaction-mode.set", forKey: .type)
            try c.encode(commandId, forKey: .commandId)
            try c.encode(threadId, forKey: .threadId)
            try c.encode(interactionMode, forKey: .interactionMode)

        case .setModelSelection(let commandId, let threadId, let modelSelection):
            try c.encode("thread.model-selection.set", forKey: .type)
            try c.encode(commandId, forKey: .commandId)
            try c.encode(threadId, forKey: .threadId)
            try c.encode(modelSelection, forKey: .modelSelection)

        case .stopThread(let commandId, let threadId, let reason):
            try c.encode("thread.stop", forKey: .type)
            try c.encode(commandId, forKey: .commandId)
            try c.encode(threadId, forKey: .threadId)
            try c.encodeIfPresent(reason, forKey: .reason)

        case .interruptRun(let commandId, let threadId, let runId, let reason, let holdQueue):
            try c.encode("run.interrupt", forKey: .type)
            try c.encode(commandId, forKey: .commandId)
            try c.encode(threadId, forKey: .threadId)
            try c.encode(runId, forKey: .runId)
            try c.encodeIfPresent(reason, forKey: .reason)
            try c.encodeIfPresent(holdQueue, forKey: .holdQueue)

        case .respondToRuntimeRequest(
            let commandId,
            let threadId,
            let requestId,
            let decision,
            let feedback,
            let answers
        ):
            try c.encode("runtime-request.respond", forKey: .type)
            try c.encode(commandId, forKey: .commandId)
            try c.encode(threadId, forKey: .threadId)
            try c.encode(requestId, forKey: .requestId)
            try c.encodeIfPresent(decision, forKey: .decision)
            try c.encodeIfPresent(feedback, forKey: .feedback)
            try c.encodeIfPresent(answers, forKey: .answers)

        case .visitThread(let commandId, let threadId, let visitedAt, let opened):
            try c.encode("thread.visit", forKey: .type)
            try c.encode(commandId, forKey: .commandId)
            try c.encode(threadId, forKey: .threadId)
            try c.encode(SwftJSON.formatISO8601(visitedAt), forKey: .visitedAt)
            try c.encodeIfPresent(opened, forKey: .opened)

        case .markThreadUnread(let commandId, let threadId):
            try c.encode("thread.mark-unread", forKey: .type)
            try c.encode(commandId, forKey: .commandId)
            try c.encode(threadId, forKey: .threadId)

        case .archiveThread(let commandId, let threadId):
            try c.encode("thread.archive", forKey: .type)
            try c.encode(commandId, forKey: .commandId)
            try c.encode(threadId, forKey: .threadId)

        case .unarchiveThread(let commandId, let threadId):
            try c.encode("thread.unarchive", forKey: .type)
            try c.encode(commandId, forKey: .commandId)
            try c.encode(threadId, forKey: .threadId)

        case .deleteThread(let commandId, let threadId, let onlyIfUnused):
            try c.encode("thread.delete", forKey: .type)
            try c.encode(commandId, forKey: .commandId)
            try c.encode(threadId, forKey: .threadId)
            try c.encodeIfPresent(onlyIfUnused, forKey: .onlyIfUnused)

        case .settleThread(let commandId, let threadId):
            try c.encode("thread.settle", forKey: .type)
            try c.encode(commandId, forKey: .commandId)
            try c.encode(threadId, forKey: .threadId)

        case .unsettleThread(let commandId, let threadId):
            try c.encode("thread.unsettle", forKey: .type)
            try c.encode(commandId, forKey: .commandId)
            try c.encode(threadId, forKey: .threadId)
            try c.encode("user", forKey: .reason)

        case .pinThread(let commandId, let threadId):
            try c.encode("thread.pin", forKey: .type)
            try c.encode(commandId, forKey: .commandId)
            try c.encode(threadId, forKey: .threadId)

        case .unpinThread(let commandId, let threadId):
            try c.encode("thread.unpin", forKey: .type)
            try c.encode(commandId, forKey: .commandId)
            try c.encode(threadId, forKey: .threadId)

        case .updateThreadMetadata(let commandId, let threadId, let title, let regenerateTitle):
            try c.encode("thread.metadata.update", forKey: .type)
            try c.encode(commandId, forKey: .commandId)
            try c.encode(threadId, forKey: .threadId)
            try c.encodeIfPresent(title, forKey: .title)
            try c.encodeIfPresent(regenerateTitle, forKey: .regenerateTitle)

        case .forkThread(let commandId, let sourceThreadId, let targetThreadId, let sourcePoint, let title, let sideChat):
            try c.encode("thread.fork", forKey: .type)
            try c.encode(commandId, forKey: .commandId)
            try c.encode("user", forKey: .createdBy)
            try c.encode("web", forKey: .creationSource)
            try c.encode(sourceThreadId, forKey: .sourceThreadId)
            try c.encode(targetThreadId, forKey: .targetThreadId)
            try c.encode(sourcePoint, forKey: .sourcePoint)
            try c.encodeIfPresent(title, forKey: .title)
            try c.encodeIfPresent(sideChat, forKey: .sideChat)

        case .linkPullRequest(let commandId, let threadId, let host, let repository, let number, let url, let source):
            try c.encode("thread.pull-request.link", forKey: .type)
            try c.encode(commandId, forKey: .commandId)
            try c.encode(threadId, forKey: .threadId)
            try c.encode(host, forKey: .host)
            try c.encode(repository, forKey: .repository)
            try c.encode(number, forKey: .number)
            try c.encode(url, forKey: .url)
            try c.encode(source, forKey: .source)

        case .unlinkPullRequest(let commandId, let threadId, let host, let repository, let number):
            try c.encode("thread.pull-request.unlink", forKey: .type)
            try c.encode(commandId, forKey: .commandId)
            try c.encode(threadId, forKey: .threadId)
            try c.encode(host, forKey: .host)
            try c.encode(repository, forKey: .repository)
            try c.encode(number, forKey: .number)

        case .unlinkIssue(let commandId, let threadId, let tracker, let host, let scope, let key):
            try c.encode("thread.issue.unlink", forKey: .type)
            try c.encode(commandId, forKey: .commandId)
            try c.encode(threadId, forKey: .threadId)
            try c.encode(tracker, forKey: .tracker)
            try c.encode(host, forKey: .host)
            try c.encode(scope, forKey: .scope)
            try c.encode(key, forKey: .key)
        }
    }
}

public struct DispatchCommandResult: Codable, Sendable, Equatable {
    public let sequence: Int
}

public struct ForceStopThreadInput: Encodable, Sendable {
    public let threadId: String
    public let runId: String?

    public init(threadId: String, runId: String? = nil) {
        self.threadId = threadId
        self.runId = runId
    }
}

public struct ForceStopThreadResult: Codable, Sendable, Equatable {
    public let outcome: String
    public let sharedWithThreadIds: [String]
}

public enum LaunchThreadWorkspaceStrategy: Encodable, Sendable, Equatable {
    case root(branch: String? = nil)
    case existingWorktree(worktreePath: String, branch: String? = nil)
    case worktree(baseRef: String, branch: String? = nil, startFromOrigin: Bool? = nil)

    private enum CodingKeys: String, CodingKey {
        case type, branch, worktreePath, baseRef, startFromOrigin
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .root(let branch):
            try c.encode("root", forKey: .type)
            try c.encodeIfPresent(branch, forKey: .branch)
        case .existingWorktree(let worktreePath, let branch):
            try c.encode("existing_worktree", forKey: .type)
            try c.encode(worktreePath, forKey: .worktreePath)
            try c.encodeIfPresent(branch, forKey: .branch)
        case .worktree(let baseRef, let branch, let startFromOrigin):
            try c.encode("worktree", forKey: .type)
            try c.encode(baseRef, forKey: .baseRef)
            try c.encodeIfPresent(branch, forKey: .branch)
            try c.encodeIfPresent(startFromOrigin, forKey: .startFromOrigin)
        }
    }
}

public struct LaunchThreadInitialMessage: Encodable, Sendable, Equatable {
    public let messageId: String?
    public let text: String
    public let attachments: [ChatAttachment]

    public init(
        messageId: String? = UUID().uuidString,
        text: String,
        attachments: [ChatAttachment] = []
    ) {
        self.messageId = messageId
        self.text = text
        self.attachments = attachments
    }
}

public struct LaunchThreadInput: Encodable, Sendable {
    public let commandId: String
    public let creationSource: String
    public let threadId: String?
    public let projectId: String
    public let title: String
    public let generateTitle: Bool?
    public let modelSelection: ModelSelection
    public let runtimeMode: RuntimeMode
    public let interactionMode: ProviderInteractionMode
    public let workspaceStrategy: LaunchThreadWorkspaceStrategy
    public let initialMessage: LaunchThreadInitialMessage?

    public init(
        commandId: String = UUID().uuidString,
        threadId: String? = nil,
        projectId: String,
        title: String,
        generateTitle: Bool? = nil,
        modelSelection: ModelSelection,
        runtimeMode: RuntimeMode = .fullAccess,
        interactionMode: ProviderInteractionMode = .default,
        workspaceStrategy: LaunchThreadWorkspaceStrategy = .root(),
        initialMessage: LaunchThreadInitialMessage? = nil
    ) {
        self.commandId = commandId
        self.creationSource = "web"
        self.threadId = threadId
        self.projectId = projectId
        self.title = title
        self.generateTitle = generateTitle
        self.modelSelection = modelSelection
        self.runtimeMode = runtimeMode
        self.interactionMode = interactionMode
        self.workspaceStrategy = workspaceStrategy
        self.initialMessage = initialMessage
    }
}

public struct LaunchThreadResult: Decodable, Sendable, Equatable {
    public let threadId: String
    public let projection: ThreadProjection
    public let resumed: Bool
    public let sequence: Int?
}

/// RPC method tag constants matching `WS_METHODS` and `ORCHESTRATION_V2_WS_METHODS`.
public enum RPCMethod {
    public static let serverProbe = "server.probe"
    public static let serverGetConfig = "server.getConfig"
    public static let serverRefreshProviders = "server.refreshProviders"
    public static let serverUpdateServer = "server.updateServer"
    public static let serverUpdateServerWithProgress = "server.updateServerWithProgress"
    public static let serverCommitDesktopUpdate = "server.commitDesktopUpdate"
    public static let subscribeServerConfig = "subscribeServerConfig"

    public static let projectsMutate = "projects.mutate"

    public static let orchestrationDispatchCommand = "orchestration.dispatchCommand"
    public static let orchestrationLaunchThread = "orchestration.launchThread"
    public static let orchestrationForceStopThread = "orchestration.forceStopThread"
    public static let orchestrationGetThreadProjection = "orchestration.getThreadProjection"
    public static let orchestrationGetThreadFamily = "orchestration.getThreadFamily"
    public static let orchestrationSubscribeShell = "orchestration.subscribeShell"
    public static let orchestrationSubscribeThread = "orchestration.subscribeThread"
}
