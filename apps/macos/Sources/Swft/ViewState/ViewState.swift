import Foundation

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

    init(id: String, name: String, initials: String?, tint: Int, workspaceRoot: String? = nil) {
        self.id = id
        self.name = name
        self.initials = initials
        self.tint = tint
        self.workspaceRoot = workspaceRoot
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
    var activity: ThreadActivity
    var updatedAt: Date

    var providerLabel: String { providerDisplayName ?? provider.displayName }

    init(
        id: String,
        title: String,
        project: ProjectRef?,
        location: ThreadLocation?,
        provider: ProviderKind,
        providerDisplayName: String? = nil,
        activity: ThreadActivity,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.project = project
        self.location = location
        self.provider = provider
        self.providerDisplayName = providerDisplayName
        self.activity = activity
        self.updatedAt = updatedAt
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
        isDefault: Bool = false
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
    }
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

struct TranscriptItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case user(String)
        case assistant(blocks: [MessageBlock], streaming: Bool)
        case toolCall(ToolCallItem)
        case approval(ApprovalItem)
        case notice(title: String, message: String, isError: Bool)
    }
    let id: String
    var kind: Kind
}

struct ThreadDetailState {
    var summary: ThreadSummary
    var items: [TranscriptItem]
    /// e.g. "+142 −38"; nil hides the diff pill.
    var diffStat: String?
}
