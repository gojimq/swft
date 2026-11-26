import Foundation
import SwftDesign

// Plain value types the screens render. The engineering track backs these with SwftKit data;
// screens never see wire models directly.

enum ServerStatus: Equatable {
    case starting
    case connecting
    case connected(label: String, providerCount: Int, port: Int?)
    case reconnecting(attempt: Int, message: String)
    case failed(message: String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var errorMessage: String? {
        switch self {
        case .failed(let message): return message
        case .reconnecting(_, let message): return message
        default: return nil
        }
    }
}

struct ProjectRef: Identifiable, Hashable {
    let id: String
    var name: String
    /// Two-letter badge; nil renders the dashed "No project" chip.
    var initials: String?
    /// Stable index into the chip palette.
    var tint: Int
    var workspaceRoot: String?
    var environmentID: String?
    /// True only when a local environment project's folder no longer exists on disk.
    var isWorkspaceMissing: Bool

    init(
        id: String,
        name: String,
        initials: String?,
        tint: Int,
        workspaceRoot: String? = nil,
        environmentID: String? = nil,
        isWorkspaceMissing: Bool = false
    ) {
        self.id = id
        self.name = name
        self.initials = initials
        self.tint = tint
        self.workspaceRoot = workspaceRoot
        self.environmentID = environmentID
        self.isWorkspaceMissing = isWorkspaceMissing
    }
}

enum ProviderKind: String, Hashable, CaseIterable {
    case claude, codex, cursor, opencode, gemini, other

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .opencode: "OpenCode"
        case .gemini: "Gemini"
        case .other: "Agent"
        }
    }
}

enum ThreadActivity: Hashable {
    case idle
    case running
    case needsApproval
    case unread
    case failed
}

enum ThreadLocation: Hashable {
    case branch(String)
    case host(String)
}

struct ThreadSummary: Identifiable, Hashable {
    let id: String
    var title: String
    var project: ProjectRef?
    var location: ThreadLocation?
    var provider: ProviderKind
    var providerDisplayName: String?
    var providerDriver: String?
    var providerIconUrl: String?
    var activity: ThreadActivity
    var updatedAt: Date
    var environmentID: String?
    var environmentLabel: String?
    var isRemoteEnvironment: Bool
    var environmentMachineSymbol: String?
    var isSettled: Bool = false
    var settledAt: Date? = nil

    var providerLabel: String { providerDisplayName ?? provider.displayName }

    init(
        id: String,
        title: String,
        project: ProjectRef?,
        location: ThreadLocation?,
        provider: ProviderKind,
        providerDisplayName: String? = nil,
        activity: ThreadActivity,
        updatedAt: Date,
        providerDriver: String? = nil,
        providerIconUrl: String? = nil,
        environmentID: String? = nil,
        environmentLabel: String? = nil,
        isRemoteEnvironment: Bool = false,
        environmentMachineSymbol: String? = nil,
        isSettled: Bool = false,
        settledAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.project = project
        self.location = location
        self.provider = provider
        self.providerDisplayName = providerDisplayName
        self.providerDriver = providerDriver
        self.providerIconUrl = providerIconUrl
        self.activity = activity
        self.updatedAt = updatedAt
        self.environmentID = environmentID
        self.environmentLabel = environmentLabel
        self.isRemoteEnvironment = isRemoteEnvironment
        self.environmentMachineSymbol = environmentMachineSymbol
        self.isSettled = isSettled
        self.settledAt = settledAt
    }
}

enum ThreadFilter: String, CaseIterable, Hashable {
    case all = "All"
    case active = "Active"
    case needsAttention = "Needs attention"
}

enum SidebarDestination: Hashable {
    case home
    case projects
    case scheduled
    case settings
    case thread(ThreadSummary.ID)
}

struct AccountSummary: Hashable {
    var name: String
    var detail: String
}

struct SidebarState {
    var threads: [ThreadSummary]
    var filter: ThreadFilter
    var account: AccountSummary
}

struct Suggestion: Identifiable, Hashable {
    let id: String
    var symbol: String
    var text: String
}

struct HomeState {
    var greetingName: String
    var suggestions: [Suggestion]
}

enum ComposerMode: String, CaseIterable, Hashable {
    case chat = "Chat"
    case task = "Task"
}

struct ReasoningChoice: Identifiable, Hashable {
    let id: String
    var label: String
}

struct ModelOption: Identifiable, Hashable {
    let id: String
    var instanceId: String
    var slug: String
    var name: String
    var provider: ProviderKind
    var providerDisplayName: String
    var reasoningOptionId: String?
    var reasoningOptionLabel: String?
    var reasoningChoices: [ReasoningChoice]
    var defaultReasoningChoiceId: String?
    var isDefault: Bool
    /// Section the model sits under inside its provider (e.g. OpenRouter inside OpenCode).
    var subProvider: String?
    var isNew: Bool

    init(
        id: String,
        instanceId: String? = nil,
        slug: String? = nil,
        name: String,
        provider: ProviderKind,
        providerDisplayName: String? = nil,
        reasoningOptionId: String? = nil,
        reasoningOptionLabel: String? = nil,
        reasoningChoices: [ReasoningChoice] = [],
        defaultReasoningChoiceId: String? = nil,
        isDefault: Bool = false,
        subProvider: String? = nil,
        isNew: Bool = false
    ) {
        self.id = id
        self.instanceId = instanceId ?? provider.rawValue
        self.slug = slug ?? id
        self.name = name
        self.provider = provider
        self.providerDisplayName = providerDisplayName ?? provider.displayName
        self.reasoningOptionId = reasoningOptionId
        self.reasoningOptionLabel = reasoningOptionLabel
        self.reasoningChoices = reasoningChoices
        self.defaultReasoningChoiceId = defaultReasoningChoiceId
        self.isDefault = isDefault
        self.subProvider = subProvider
        self.isNew = isNew
    }
}

/// One provider instance as the model picker shows it (Studio's "harness").
struct PickerHarness: Identifiable, Hashable {
    let id: String
    var driver: String
    /// Groups clones of the same ACP registry agent; the server does not send it yet, so it is usually nil.
    var acpAgentId: String? = nil
    var iconUrl: String? = nil
    var label: String
    var kind: ProviderKind
    /// Normalised `#rrggbb`.
    var accentHex: String? = nil
    /// "Auth label · email" when signed in.
    var account: String? = nil
    var unauthenticated = false
    var unavailableReason: String? = nil
    var subProviders: [PickerSubProvider]? = nil
}

struct PickerSubProvider: Hashable {
    var name: String
    var unavailableReason: String? = nil
}

/// Everything the model picker lists: provider instances in server order, and the models usable right now.
struct PickerCatalog: Hashable {
    var harnesses: [PickerHarness]
    var models: [ModelOption]

    static let empty = PickerCatalog(harnesses: [], models: [])
}

struct ComposerState {
    var text: String = ""
    var mode: ComposerMode = .chat
    var model: ModelOption?
    var selectedReasoningChoiceId: String? = nil
    var availableModels: [ModelOption] = []
    /// Short context label, e.g. "Swft · main"; nil hides the chip.
    var contextLabel: String? = nil
    var isBusy: Bool = false

    var selectedReasoningChoice: ReasoningChoice? {
        guard let model, !model.reasoningChoices.isEmpty else { return nil }
        if let id = selectedReasoningChoiceId,
           let match = model.reasoningChoices.first(where: { $0.id == id })
        {
            return match
        }
        if let def = model.defaultReasoningChoiceId,
           let match = model.reasoningChoices.first(where: { $0.id == def })
        {
            return match
        }
        return model.reasoningChoices.first
    }
}

enum MessageBlock: Hashable {
    case text(String)
    case code(language: String?, source: String)
    /// A markdown image (`![alt](source)`) on its own block.
    case image(alt: String, source: String)
    /// Files and images the agent attached to its message.
    case attachments([TranscriptAttachment])
}

struct ToolCallItem: Hashable {
    enum Kind: Hashable { case command, read, edit, search, thinking }
    enum Status: Hashable { case running, succeeded, failed }
    var kind: Kind
    var title: String
    var detail: String
    var status: Status
    var duration: TimeInterval?
    var output: String?
    /// An image the tool looked at (e.g. a viewed screenshot), shown with its output.
    var imagePath: String? = nil
}

struct ApprovalItem: Hashable {
    enum Status: Hashable { case pending, approved, denied }
    var requestId: String
    var title: String
    var message: String
    var command: String?
    var status: Status

    init(
        requestId: String = "",
        title: String,
        message: String,
        command: String?,
        status: Status
    ) {
        self.requestId = requestId
        self.title = title
        self.message = message
        self.command = command
        self.status = status
    }
}

/// A message sent from this client that is shown in the transcript before (and keeps its row identity after) the
/// server echoes it. `messageID` is the id sent with the dispatch, and doubles as the transcript row's id.
struct PendingUserMessage: Equatable, Sendable {
    let messageID: String
    let text: String
    var attachments: [TranscriptAttachment] = []
}

struct SubagentItem: Identifiable, Hashable, Sendable {
    let id: String
    let subagentID: String
    var runID: String?
    var providerTurnID: String?
    var origin: String
    var title: String
    var provider: ProviderKind
    var providerDriver: String
    var providerInstanceID: String
    var providerDisplayName: String?
    var providerIconURL: String?
    var modelName: String?
    var status: SubagentStatus
    var prompt: String
    var progress: String?
    var result: String?
    var childThreadID: String?
    var remoteEnvironmentID: String?
    var remoteEnvironmentLabel: String?
    var remoteThreadID: String?
    var worktreeBranch: String?
    var worktreePath: String?
    var startedAt: Date?
    var completedAt: Date?

    init(
        id: String,
        subagentID: String? = nil,
        runID: String? = nil,
        providerTurnID: String? = nil,
        origin: String = "app_owned",
        title: String,
        provider: ProviderKind,
        providerDriver: String? = nil,
        providerInstanceID: String? = nil,
        providerDisplayName: String? = nil,
        providerIconURL: String? = nil,
        modelName: String? = nil,
        status: SubagentStatus,
        prompt: String = "",
        progress: String? = nil,
        result: String? = nil,
        childThreadID: String? = nil,
        remoteEnvironmentID: String? = nil,
        remoteEnvironmentLabel: String? = nil,
        remoteThreadID: String? = nil,
        worktreeBranch: String? = nil,
        worktreePath: String? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.subagentID = subagentID ?? id
        self.runID = runID
        self.providerTurnID = providerTurnID
        self.origin = origin
        self.title = title
        self.provider = provider
        self.providerDriver = providerDriver ?? provider.driverIdentifier
        self.providerInstanceID = providerInstanceID ?? provider.rawValue
        self.providerDisplayName = providerDisplayName
        self.providerIconURL = providerIconURL
        self.modelName = modelName
        self.status = status
        self.prompt = prompt
        self.progress = progress
        self.result = result
        self.childThreadID = childThreadID
        self.remoteEnvironmentID = remoteEnvironmentID
        self.remoteEnvironmentLabel = remoteEnvironmentLabel
        self.remoteThreadID = remoteThreadID
        self.worktreeBranch = worktreeBranch
        self.worktreePath = worktreePath
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    var workspaceLabel: String? {
        if let branch = worktreeBranch?.trimmingCharacters(in: .whitespacesAndNewlines), !branch.isEmpty {
            return branch
        }
        if let path = worktreePath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            return (path as NSString).lastPathComponent
        }
        return nil
    }
}

struct SubagentGroup: Identifiable, Hashable, Sendable {
    let id: String
    var members: [SubagentItem]

    var hasActive: Bool { members.contains { $0.status.isActive } }
}

struct TranscriptItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case user(String, attachments: [TranscriptAttachment] = [])
        case assistant(blocks: [MessageBlock], streaming: Bool)
        case toolCall(ToolCallItem)
        case subagent(SubagentItem)
        case approval(ApprovalItem)
        case notice(title: String, message: String, isError: Bool)
    }
    let id: String
    var kind: Kind
    var startedAt: Date?
    var completedAt: Date?

    init(id: String, kind: Kind, startedAt: Date? = nil, completedAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

struct ThreadDetailState: Equatable {
    var summary: ThreadSummary
    var items: [TranscriptItem]
    /// e.g. "+142 −38"; nil hides the diff pill.
    var diffStat: String?
    /// The thread has an active run, so its latest turn renders as live work.
    var isRunning: Bool = false
    /// When this thread is a delegated subagent child, links back to its parent thread.
    var parentLink: SubagentParentLink? = nil

    var rows: [TranscriptRow] { TranscriptLayout.rows(for: items, isRunning: isRunning) }
}

/// One step inside a work fold: a tool call, a thought, interim commentary, a resolved approval or a quiet notice.
struct WorkStep: Identifiable, Hashable {
    enum Kind: Hashable {
        case tool(ToolCallItem)
        case thought(String)
        case commentary([MessageBlock])
        case approval(ApprovalItem)
        case note(title: String, message: String)
    }
    let id: String
    var kind: Kind
}

/// Latest live reasoning thought summary displayed above the active tool row (matching T3 Code's `work-live`).
struct WorkThoughtPreview: Hashable, Sendable {
    /// Thought step identity; blur-fade transitions key on `id` so token streaming updates smoothly in place
    /// while a new thought step blur-fades cleanly over the old one.
    let id: String
    let text: String
}

/// A turn's intermediate work folded into one quiet row.
struct WorkFold: Identifiable, Hashable {
    let id: String
    var steps: [WorkStep]
    /// The turn is still working: `title` is the current step and `subtitle` the running summary.
    var isLive: Bool
    var title: String
    var subtitle: String?
    /// Latest live reasoning thought surfaced above the active tool row while collapsed.
    var liveThought: WorkThoughtPreview? = nil
    var failedCount: Int
}

/// What the thread screen renders, after folding each turn's work.
enum TranscriptRow: Identifiable, Hashable {
    case user(id: String, text: String, attachments: [TranscriptAttachment] = [])
    case assistant(id: String, blocks: [MessageBlock], streaming: Bool)
    case work(WorkFold)
    case subagent(SubagentItem)
    case subagentGroup(SubagentGroup)
    case approval(id: String, ApprovalItem)
    case note(id: String, title: String, message: String, isError: Bool)

    var id: String {
        switch self {
        case .user(let id, _, _), .assistant(let id, _, _), .approval(let id, _), .note(let id, _, _, _): id
        case .work(let fold): fold.id
        case .subagent(let item): item.id
        case .subagentGroup(let group): group.id
        }
    }

    var workFoldID: String? {
        if case .work(let fold) = self { fold.id } else { nil }
    }

    var subagentDisclosureIDs: [String] {
        switch self {
        case .subagent(let item): [item.id]
        case .subagentGroup(let group): [group.id] + group.members.map(\.id)
        default: []
        }
    }
}
