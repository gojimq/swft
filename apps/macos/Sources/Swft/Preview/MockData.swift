import Foundation

/// Mock view state for SwiftUI previews and `-SwftMock`/`-SwftScreen`/`-SwftAppearance` screenshot runs.
enum MockData {
    static let now = Date()
    static func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

    static let swft = ProjectRef(id: "p-swft", name: "Swft", initials: "SW", tint: 0, workspaceRoot: "/Users/dev/swft")
    static let studio = ProjectRef(id: "p-studio", name: "Studio", initials: "ST", tint: 1, workspaceRoot: "/Users/dev/studio")
    static let api = ProjectRef(id: "p-api", name: "Ledger API", initials: "LA", tint: 2, workspaceRoot: "/Users/dev/ledger-api")
    static let site = ProjectRef(id: "p-site", name: "Marketing site", initials: "MS", tint: 3, workspaceRoot: "/Users/dev/marketing")
    static let none = ProjectRef(id: "p-none", name: "No project", initials: nil, tint: 0)

    static let projects: [ProjectRef] = [swft, studio, api, site]

    static let threads: [ThreadSummary] = [
        .init(id: "t1", title: "Build Swift desktop frontend", project: swft, location: .branch("swft/design-system"), provider: .claude, activity: .running, updatedAt: ago(2)),
        .init(id: "t2", title: "Gemini-style composer polish", project: swft, location: .host("Jim’s MacBook Pro"), provider: .codex, activity: .needsApproval, updatedAt: ago(14)),
        .init(id: "t3", title: "Improve environment switching UI", project: studio, location: .branch("main"), provider: .claude, activity: .unread, updatedAt: ago(4 * 60)),
        .init(id: "t4", title: "Studio project kickoff & roadmap", project: studio, location: .branch("studio"), provider: .cursor, activity: .idle, updatedAt: ago(14 * 60)),
        .init(id: "t5", title: "Investigate flaky ledger reconciliation test", project: api, location: .branch("fix/recon-flake"), provider: .codex, activity: .failed, updatedAt: ago(16 * 60)),
        .init(id: "t6", title: "Sketch onboarding copy", project: none, location: .host("Jim’s MacBook Pro"), provider: .opencode, activity: .idle, updatedAt: ago(26 * 60)),
        .init(id: "t7", title: "Hero section performance pass", project: site, location: .branch("perf/hero"), provider: .claude, activity: .idle, updatedAt: ago(3 * 24 * 60)),
        .init(id: "t8", title: "Migrate auth tokens to keychain", project: api, location: .branch("auth/keychain"), provider: .codex, activity: .idle, updatedAt: ago(5 * 24 * 60)),
        .init(id: "t9", title: "Dark mode token audit", project: swft, location: .branch("main"), provider: .gemini, activity: .idle, updatedAt: ago(9 * 24 * 60)),
    ]

    static let sidebar = SidebarState(threads: threads, filter: .all, account: AccountSummary(name: "Jimwell Quevedo", detail: "Local server · 3 providers"))

    static let home = HomeState(greetingName: "Jimwell", suggestions: defaultSuggestions)

    static let defaultSuggestions: [Suggestion] = [
        Suggestion(id: "s1", symbol: "magnifyingglass", text: "Explain how this repo is structured"),
        Suggestion(id: "s2", symbol: "ladybug", text: "Find and fix the failing test"),
        Suggestion(id: "s3", symbol: "arrow.triangle.branch", text: "Review my uncommitted changes"),
    ]

    static let reasoningChoices: [ReasoningChoice] = [
        .init(id: "low", label: "Low"),
        .init(id: "medium", label: "Medium"),
        .init(id: "high", label: "High"),
        .init(id: "max", label: "Max"),
    ]

    static let claudeLevels: [ReasoningChoice] = [
        .init(id: "low", label: "Low"),
        .init(id: "medium", label: "Medium"),
        .init(id: "high", label: "High"),
        .init(id: "xhigh", label: "Extra high"),
        .init(id: "max", label: "Max"),
    ]

    /// Provider instances for the picker: a lone Claude, two Codex accounts (account switcher), Cursor without thinking
    /// levels, OpenCode with sub-providers, and a signed-out Antigravity.
    static let harnesses: [PickerHarness] = [
        .init(id: "claudeAgent", driver: "claudeAgent", label: "Claude", kind: .claude, account: "Claude Max · jim@example.com"),
        .init(id: "codex", driver: "codex", label: "Codex", kind: .codex, account: "ChatGPT Pro · jim@work.dev"),
        .init(id: "codex_personal", driver: "codex", label: "Codex Personal", kind: .codex, accentHex: "#1e8e3e", account: "ChatGPT Plus · jim@example.com"),
        .init(id: "cursor", driver: "cursor", label: "Cursor", kind: .cursor),
        .init(id: "opencode", driver: "opencode", label: "OpenCode", kind: .opencode, subProviders: [
            .init(name: "OpenRouter"),
            .init(name: "Anthropic API", unavailableReason: "No API key"),
        ]),
        .init(id: "antigravity", driver: "antigravity", label: "Antigravity", kind: .gemini, unauthenticated: true, unavailableReason: "Not signed in"),
    ]

    static let models: [ModelOption] = [
        .init(id: "claudeAgent::opus", instanceId: "claudeAgent", slug: "opus", name: "Opus 5.5", provider: .claude, providerDisplayName: "Claude", reasoningOptionId: "effort", reasoningOptionLabel: "Thinking", reasoningChoices: claudeLevels, defaultReasoningChoiceId: "high", isDefault: true),
        .init(id: "claudeAgent::sonnet", instanceId: "claudeAgent", slug: "sonnet", name: "Sonnet 5.5", provider: .claude, providerDisplayName: "Claude", reasoningOptionId: "effort", reasoningOptionLabel: "Thinking", reasoningChoices: claudeLevels, defaultReasoningChoiceId: "medium"),
        .init(id: "claudeAgent::haiku", instanceId: "claudeAgent", slug: "haiku", name: "Haiku 5.5", provider: .claude, providerDisplayName: "Claude", reasoningOptionId: "effort", reasoningOptionLabel: "Thinking", reasoningChoices: Array(claudeLevels.prefix(3)), defaultReasoningChoiceId: "medium"),
        .init(id: "claudeAgent::fable", instanceId: "claudeAgent", slug: "fable", name: "Fable 5.2", provider: .claude, providerDisplayName: "Claude", reasoningOptionId: "effort", reasoningOptionLabel: "Thinking", reasoningChoices: claudeLevels, defaultReasoningChoiceId: "high", isNew: true),
        .init(id: "codex::gpt", instanceId: "codex", slug: "gpt-6.1", name: "GPT-6.1", provider: .codex, providerDisplayName: "Codex", reasoningOptionId: "reasoningEffort", reasoningOptionLabel: "Thinking", reasoningChoices: reasoningChoices, defaultReasoningChoiceId: "high", isNew: true),
        .init(id: "codex::luna", instanceId: "codex", slug: "gpt-6-luna", name: "GPT-6 Luna", provider: .codex, providerDisplayName: "Codex", reasoningOptionId: "reasoningEffort", reasoningOptionLabel: "Thinking", reasoningChoices: reasoningChoices, defaultReasoningChoiceId: "medium"),
        .init(id: "codex_personal::gpt", instanceId: "codex_personal", slug: "gpt-6.1", name: "GPT-6.1", provider: .codex, providerDisplayName: "Codex Personal", reasoningOptionId: "reasoningEffort", reasoningOptionLabel: "Thinking", reasoningChoices: reasoningChoices, defaultReasoningChoiceId: "high"),
        .init(id: "codex_personal::astra", instanceId: "codex_personal", slug: "gpt-6-astra", name: "GPT-6 Astra", provider: .codex, providerDisplayName: "Codex Personal", reasoningOptionId: "reasoningEffort", reasoningOptionLabel: "Thinking", reasoningChoices: reasoningChoices, defaultReasoningChoiceId: "medium"),
        .init(id: "cursor::composer", instanceId: "cursor", slug: "composer", name: "Composer 2", provider: .cursor, providerDisplayName: "Cursor"),
        .init(id: "opencode::deepseek", instanceId: "opencode", slug: "openrouter/deepseek-v4", name: "DeepSeek V4", provider: .opencode, providerDisplayName: "OpenCode", subProvider: "OpenRouter"),
        .init(id: "opencode::kimi", instanceId: "opencode", slug: "openrouter/kimi-k3", name: "Kimi K3", provider: .opencode, providerDisplayName: "OpenCode", reasoningOptionId: "reasoning", reasoningOptionLabel: "Thinking", reasoningChoices: Array(reasoningChoices.prefix(3)), defaultReasoningChoiceId: "medium", subProvider: "OpenRouter", isNew: true),
    ]

    static let pickerCatalog = PickerCatalog(harnesses: harnesses, models: models)

    static func composer(context: String? = "Swft · main") -> ComposerState {
        ComposerState(model: models[0], selectedReasoningChoiceId: "high", availableModels: models, contextLabel: context)
    }

    private static func at(_ seconds: Double) -> Date { ago(30).addingTimeInterval(seconds) }

    /// A settled turn (its work folds to "Worked for 14s") followed by a live one.
    static let threadDetail = ThreadDetailState(
        summary: threads[0],
        items: [
            .init(id: "i1", kind: .user("Add a pill-shaped composer to the home screen with a model picker and a circular send button. Keep it quiet — no heavy shadows."), startedAt: at(0)),
            .init(id: "i2", kind: .toolCall(.init(kind: .thinking, title: "Thought", detail: "The composer should live in SwftDesign so home and thread share it.", status: .succeeded, duration: 1.8, output: "The composer should live in SwftDesign so home and thread share it. Check the radius tokens first.")), startedAt: at(1), completedAt: at(2.8)),
            .init(id: "i3", kind: .assistant(blocks: [
                .text("I’ll start by looking at how the design tokens are organised, then add a `PillComposer` component to **SwftDesign**."),
            ], streaming: false), startedAt: at(3), completedAt: at(3.5)),
            .init(id: "i4", kind: .toolCall(.init(kind: .search, title: "Searched", detail: "RoundedRectangle", status: .succeeded, duration: 0.4, output: nil)), startedAt: at(4), completedAt: at(4.4)),
            .init(id: "i5", kind: .toolCall(.init(kind: .read, title: "Read", detail: "Sources/SwftDesign/Tokens/Metrics.swift", status: .succeeded, duration: 0.1, output: "public enum SwftRadius {\n    public static let s: CGFloat = 8\n    public static let m: CGFloat = 12\n    public static let composer: CGFloat = 28\n}")), startedAt: at(4.5), completedAt: at(4.6)),
            .init(id: "i6", kind: .toolCall(.init(kind: .read, title: "Read", detail: "Sources/SwftDesign/Components/Primitives.swift", status: .succeeded, duration: 0.1, output: nil)), startedAt: at(4.7), completedAt: at(4.8)),
            .init(id: "i7", kind: .toolCall(.init(kind: .command, title: "Ran", detail: "swift build", status: .succeeded, duration: 7.4, output: "Building for debugging...\n[12/12] Compiling SwftDesign Composer.swift\nBuild complete! (7.41s)")), startedAt: at(5), completedAt: at(12.4)),
            .init(id: "i8", kind: .notice(title: "MCP server plugin:finance:slack needs a sign-in", message: "The plugin:finance:slack MCP server needs a sign-in before Claude can use it.", isError: false), startedAt: at(12.5)),
            .init(id: "i9", kind: .assistant(blocks: [
                .text("The composer is in place. It stacks a multi-line field above a control row, and the send button only lights up once there’s text:"),
                .code(language: "swift", source: "PillComposer(text: $draft, placeholder: \"Ask Swft\", onSend: send) {\n    ModelPickerTrigger(model: \"Opus 5.5\", effort: \"High\") { openPicker() }\n}"),
                .text("## What changed\n- `PillComposer` lives in **SwftDesign**, shared by home and thread screens.\n- The send button stays quiet until there’s text, then springs to life."),
            ], streaming: false), startedAt: at(12.6), completedAt: at(14.2)),
            .init(id: "j1", kind: .user("Now check the dark-mode contrast of the composer border."), startedAt: at(60)),
            .init(id: "j2", kind: .toolCall(.init(kind: .thinking, title: "Thought", detail: "Compare the border token against the dark canvas.", status: .succeeded, duration: 1.1, output: "Compare the border token against the dark canvas.")), startedAt: at(61), completedAt: at(62)),
            .init(id: "j3", kind: .toolCall(.init(kind: .read, title: "Read", detail: "Sources/SwftDesign/Tokens/Colors.swift", status: .succeeded, duration: 0.1, output: nil)), startedAt: at(62), completedAt: at(62.1)),
            .init(id: "j4", kind: .toolCall(.init(kind: .command, title: "Running", detail: "swift test --filter Contrast", status: .running, duration: nil, output: nil)), startedAt: at(63)),
        ],
        diffStat: "+142 −38",
        isRunning: true
    )

    /// A live turn paused on an approval.
    static let approvalDetail = ThreadDetailState(
        summary: threads[1],
        items: [
            .init(id: "k1", kind: .user("Clear the stale build products and re-bundle the app."), startedAt: at(0)),
            .init(id: "k2", kind: .toolCall(.init(kind: .read, title: "Read", detail: "scripts/bundle.sh", status: .succeeded, duration: 0.1, output: nil)), startedAt: at(1), completedAt: at(1.1)),
            .init(id: "k3", kind: .approval(.init(requestId: "mock-req-1", title: "Run command?", message: "Delete the build directory before re-bundling the app.", command: "rm -rf apps/macos/build && scripts/bundle.sh", status: .pending)), startedAt: at(2)),
        ],
        diffStat: nil,
        isRunning: true
    )
}
