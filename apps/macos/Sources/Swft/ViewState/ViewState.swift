import Foundation

// Plain value types the screens render. The engineering track backs these with SwftKit data;
// screens never see wire models directly.

struct ProjectRef: Identifiable, Hashable {
    let id: String
    var name: String
    /// Two-letter badge; nil renders the dashed "No project" chip.
    var initials: String?
    /// Stable index into the chip palette.
    var tint: Int
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
    var activity: ThreadActivity
    var updatedAt: Date
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

enum ReasoningEffort: String, CaseIterable, Hashable {
    case low = "Low", medium = "Medium", high = "High", max = "Max"
}

struct ModelOption: Identifiable, Hashable {
    let id: String
    var name: String
    var provider: ProviderKind
}

struct ComposerState {
    var text: String = ""
    var mode: ComposerMode = .chat
    var model: ModelOption
    var effort: ReasoningEffort
    var availableModels: [ModelOption]
    /// Short context label, e.g. "swft · main"; nil hides the chip.
    var contextLabel: String?
    var isBusy: Bool = false
}

enum MessageBlock: Hashable {
    case text(String)
    case code(language: String?, source: String)
}

struct ToolCallItem: Hashable {
    enum Kind: Hashable { case command, read, edit, search }
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
    var title: String
    var message: String
    var command: String?
    var status: Status
}

struct TranscriptItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case user(String)
        case assistant(blocks: [MessageBlock], streaming: Bool)
        case toolCall(ToolCallItem)
        case approval(ApprovalItem)
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
