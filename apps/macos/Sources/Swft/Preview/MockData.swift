import Foundation

/// Mock view state for building and screenshotting the UI before SwftKit is wired in.
enum MockData {
    static let now = Date()
    static func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

    static let swft = ProjectRef(id: "p-swft", name: "Swft", initials: "SW", tint: 0)
    static let studio = ProjectRef(id: "p-studio", name: "Studio", initials: "ST", tint: 1)
    static let api = ProjectRef(id: "p-api", name: "Ledger API", initials: "LA", tint: 2)
    static let site = ProjectRef(id: "p-site", name: "Marketing site", initials: "MS", tint: 3)
    static let none = ProjectRef(id: "p-none", name: "No project", initials: nil, tint: 0)

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

    static let home = HomeState(greetingName: "Jimwell", suggestions: [
        Suggestion(id: "s1", symbol: "magnifyingglass", text: "Explain how this repo is structured"),
        Suggestion(id: "s2", symbol: "ladybug", text: "Find and fix the failing test"),
        Suggestion(id: "s3", symbol: "arrow.triangle.branch", text: "Review my uncommitted changes"),
    ])

    static let models: [ModelOption] = [
        .init(id: "opus", name: "Opus 5.5", provider: .claude),
        .init(id: "sonnet", name: "Sonnet 5.5", provider: .claude),
        .init(id: "gpt", name: "GPT-6.1", provider: .codex),
        .init(id: "composer", name: "Composer 2", provider: .cursor),
    ]

    static func composer(context: String? = "Swft · main") -> ComposerState {
        ComposerState(model: models[0], effort: .high, availableModels: models, contextLabel: context)
    }

    static let threadDetail = ThreadDetailState(
        summary: threads[0],
        items: [
            .init(id: "i1", kind: .user("Add a pill-shaped composer to the home screen with a model picker and a circular send button. Keep it quiet — no heavy shadows.")),
            .init(id: "i2", kind: .assistant(blocks: [
                .text("I’ll start by looking at how the design tokens are organised, then add a `PillComposer` component to **SwftDesign** so both the home and thread screens can share it."),
            ], streaming: false)),
            .init(id: "i3", kind: .toolCall(.init(kind: .search, title: "Searched", detail: "\"RoundedRectangle\" in Sources/SwftDesign", status: .succeeded, duration: 0.4, output: nil))),
            .init(id: "i4", kind: .toolCall(.init(kind: .read, title: "Read", detail: "Sources/SwftDesign/Tokens/Metrics.swift", status: .succeeded, duration: 0.1, output: "public enum SwftRadius {\n    public static let s: CGFloat = 8\n    public static let m: CGFloat = 12\n    public static let composer: CGFloat = 28\n}"))),
            .init(id: "i5", kind: .toolCall(.init(kind: .command, title: "Ran", detail: "swift build", status: .succeeded, duration: 7.4, output: "Building for debugging...\n[12/12] Compiling SwftDesign Composer.swift\nBuild complete! (7.41s)"))),
            .init(id: "i6", kind: .assistant(blocks: [
                .text("The composer is in place. It stacks a multi-line field above a control row, and the send button only lights up once there’s text:"),
                .code(language: "swift", source: "PillComposer(text: $draft, placeholder: \"Ask Swft\", onSend: send) {\n    ModelPicker(model: \"Opus 5.5\", effort: \"High\") { modelMenu }\n}"),
                .text("Next I want to clear the stale build products so the bundle picks up the new font resources."),
            ], streaming: false)),
            .init(id: "i7", kind: .approval(.init(title: "Run command?", message: "Claude wants to delete the build directory before re-bundling the app.", command: "rm -rf apps/macos/build && scripts/bundle.sh", status: .pending))),
            .init(id: "i8", kind: .assistant(blocks: [
                .text("While that’s pending, I’m checking the dark-mode contrast of the composer border against the canvas"),
            ], streaming: true)),
        ],
        diffStat: "+142 −38"
    )
}
