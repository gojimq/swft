import AppKit
import Foundation
import SwftDesign

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
        .init(id: "t8", title: "Migrate auth tokens to keychain", project: api, location: .branch("auth/keychain"), provider: .codex, activity: .idle, updatedAt: ago(5 * 24 * 60), isSettled: true, settledAt: ago(4 * 24 * 60)),
        .init(id: "t9", title: "Dark mode token audit", project: swft, location: .branch("main"), provider: .gemini, activity: .idle, updatedAt: ago(9 * 24 * 60), isSettled: true, settledAt: ago(8 * 24 * 60)),
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

    private static func inMinutes(_ minutes: Double) -> Date { now.addingTimeInterval(minutes * 60) }

    /// Realistic usage limits for mock mode: Claude (2 accounts, 5h/weekly & pace), Codex (healthy on pace),
    /// Antigravity (9% low quota ahead of pace), plus Cursor (4th candidate for Settings toggle testing).
    static let usageProviders: [UsageProviderEntry] = [
        UsageProviderEntry(
            id: "claudeAgent",
            driver: "claudeAgent",
            label: "Claude Work",
            kind: .claude,
            accentHex: "#d97757",
            account: "Claude Max · jim@work.dev",
            usageLimits: UsageLimitsSnapshot(
                checkedAt: ago(1),
                windows: [
                    UsageWindow(
                        id: "claude-work-5h",
                        kind: .session,
                        label: "5-hour",
                        usedPercent: 36,
                        resetsAt: inMinutes(134),
                        windowDurationMins: 300
                    ),
                    UsageWindow(
                        id: "claude-work-weekly",
                        kind: .weekly,
                        label: "Weekly",
                        usedPercent: 28,
                        resetsAt: inMinutes(3 * 24 * 60 + 18 * 60),
                        windowDurationMins: 7 * 24 * 60
                    ),
                ]
            )
        ),
        UsageProviderEntry(
            id: "claudeAgent_personal",
            driver: "claudeAgent",
            label: "Claude Personal",
            kind: .claude,
            accentHex: "#7c5cfa",
            account: "Claude Pro · jim@example.com",
            usageLimits: UsageLimitsSnapshot(
                checkedAt: ago(1),
                windows: [
                    UsageWindow(
                        id: "claude-personal-5h",
                        kind: .session,
                        label: "5-hour",
                        usedPercent: 18,
                        resetsAt: inMinutes(245),
                        windowDurationMins: 300
                    ),
                    UsageWindow(
                        id: "claude-personal-weekly",
                        kind: .weekly,
                        label: "Weekly",
                        usedPercent: 9,
                        resetsAt: inMinutes(5 * 24 * 60 + 12 * 60),
                        windowDurationMins: 7 * 24 * 60
                    ),
                ]
            )
        ),
        UsageProviderEntry(
            id: "codex",
            driver: "codex",
            label: "Codex",
            kind: .codex,
            account: "ChatGPT Pro · jim@work.dev",
            usageLimits: UsageLimitsSnapshot(
                checkedAt: ago(2),
                windows: [
                    UsageWindow(
                        id: "codex-5h",
                        kind: .session,
                        label: "5-hour",
                        usedPercent: 22,
                        resetsAt: inMinutes(228),
                        windowDurationMins: 300
                    ),
                    UsageWindow(
                        id: "codex-weekly",
                        kind: .weekly,
                        label: "Weekly",
                        usedPercent: 14,
                        resetsAt: inMinutes(4 * 24 * 60 + 6 * 60),
                        windowDurationMins: 7 * 24 * 60
                    ),
                ]
            )
        ),
        UsageProviderEntry(
            id: "antigravity",
            driver: "antigravity",
            label: "Antigravity",
            kind: .gemini,
            account: "AI Ultra · jim@example.com",
            usageLimits: UsageLimitsSnapshot(
                checkedAt: ago(1),
                windows: [
                    UsageWindow(
                        id: "antigravity-5h",
                        kind: .session,
                        label: "5-hour",
                        usedPercent: 91,
                        resetsAt: inMinutes(72),
                        windowDurationMins: 300
                    ),
                    UsageWindow(
                        id: "antigravity-weekly",
                        kind: .weekly,
                        label: "Weekly",
                        usedPercent: 66,
                        resetsAt: inMinutes(2 * 24 * 60 + 11 * 60),
                        windowDurationMins: 7 * 24 * 60
                    ),
                ]
            )
        ),
        UsageProviderEntry(
            id: "cursor",
            driver: "cursor",
            label: "Cursor",
            kind: .cursor,
            account: "Cursor Pro · jim@work.dev",
            usageLimits: UsageLimitsSnapshot(
                checkedAt: ago(3),
                windows: [
                    UsageWindow(
                        id: "cursor-monthly",
                        kind: .monthly,
                        label: "Monthly",
                        usedPercent: 16,
                        resetsAt: inMinutes(14 * 24 * 60 + 6 * 60),
                        windowDurationMins: 30 * 24 * 60
                    ),
                ]
            )
        ),
    ]

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

    /// A settled turn with attachments both ways: a screenshot and a log from the user, an inline markdown image and an
    /// attached chart from the agent. Their pixels are generated locally (`seedImageCache`), nothing is fetched.
    @MainActor
    static var attachmentsDetail: ThreadDetailState {
        ThreadDetailState(
            summary: threads[2],
            items: [
                .init(id: "m1", kind: .user("The environment picker clips on narrow windows — here’s what I see.", attachments: [
                    TranscriptAttachment(id: "mock-shot", kind: .image, name: "Screenshot 2026-11-25 at 10.41.png", mimeType: "image/png", sizeBytes: 482_113),
                    TranscriptAttachment(id: "mock-log", kind: .file, name: "environment-switch.log", mimeType: "text/plain", sizeBytes: 18_204),
                ]), startedAt: at(0)),
                .init(id: "m2", kind: .toolCall(.init(kind: .read, title: "Viewed", detail: "Screenshot 2026-11-25 at 10.41.png", status: .succeeded, duration: 0.2, output: nil)), startedAt: at(1), completedAt: at(1.2)),
                .init(id: "m3", kind: .assistant(blocks: [
                    .text("The chip’s label isn’t allowed to truncate, so it pushes the picker past the composer’s edge. Here’s the clipped state reproduced:"),
                    .image(alt: "Clipped environment picker", source: mockImageDataURI),
                    .text("I’ve attached a width sweep showing where it starts to clip."),
                    .attachments([TranscriptAttachment(id: "mock-chart", kind: .image, name: "width-sweep.png", mimeType: "image/png", sizeBytes: 96_400)]),
                ], streaming: false), startedAt: at(3), completedAt: at(6)),
            ],
            diffStat: nil
        )
    }

    /// Generated stand-ins for the attachment fixtures above, pinned so they never need a server.
    @MainActor
    static func seedImageCache() {
        let cache = SwftImageCache.shared
        if let shot = gradientImage(width: 1440, height: 900, from: (0.82, 0.89, 0.99), to: (0.55, 0.68, 0.95)) {
            cache.store(shot, for: SwftImageReference.attachmentKey("mock-shot"), pinned: true)
        }
        if let chart = gradientImage(width: 1200, height: 1200, from: (0.98, 0.9, 0.78), to: (0.93, 0.6, 0.45)) {
            cache.store(chart, for: SwftImageReference.attachmentKey("mock-chart"), pinned: true)
        }
    }

    static let mockImageDataURI: String = {
        guard let image = gradientImage(width: 640, height: 280, from: (0.86, 0.95, 0.88), to: (0.45, 0.75, 0.6)) else { return "" }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return "" }
        return "data:image/png;base64,\(png.base64EncodedString())"
    }()

    private static func gradientImage(width: Int, height: Int, from: (CGFloat, CGFloat, CGFloat), to: (CGFloat, CGFloat, CGFloat)) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: space, colors: [
                  CGColor(srgbRed: from.0, green: from.1, blue: from.2, alpha: 1),
                  CGColor(srgbRed: to.0, green: to.1, blue: to.2, alpha: 1),
              ] as CFArray, locations: [0, 1])
        else { return nil }
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        context.setFillColor(CGColor(gray: 1, alpha: 0.55))
        let inset = CGFloat(min(width, height)) * 0.12
        context.fill(CGRect(x: inset, y: inset, width: CGFloat(width) - inset * 2, height: CGFloat(height) * 0.22))
        return context.makeImage()
    }

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

    /// Realistic subagent showcase: a completed single delegated subagent, a parallel 3-subagent fan-out group
    /// (running, completed, failed), a waiting subagent, and a native expandable subagent without a child thread.
    static let subagentsDetail = ThreadDetailState(
        summary: threads[3],
        items: [
            .init(id: "sa-u1", kind: .user("Audit our WebSocket reconnect path and propose a concrete refactor plan."), startedAt: at(0)),
            .init(id: "sa-t1", kind: .toolCall(.init(kind: .read, title: "Read", detail: "Sources/SwftKit/ServerConnection.swift", status: .succeeded, duration: 0.2, output: nil)), startedAt: at(1), completedAt: at(1.2)),
            .init(
                id: "sa-single-1",
                kind: .subagent(
                    SubagentItem(
                        id: "sa-single-1",
                        subagentID: "node-sa-1",
                        runID: "run-sa-1",
                        providerTurnID: "turn-sa-1",
                        origin: "app_owned",
                        title: "Codebase Researcher",
                        provider: .claude,
                        providerDriver: "claudeAgent",
                        providerInstanceID: "claudeAgent",
                        providerDisplayName: "Claude",
                        modelName: "Opus 5.5",
                        status: .completed,
                        prompt: "Trace WebSocket reconnect backoff, resume sequences, and subscription replay across ServerConnection and ThreadStore.",
                        progress: "Mapped reconnect state transitions",
                        result: "Found 2 stale sequence edge cases in ServerConnection and verified ThreadStore deduplication.",
                        childThreadID: "t4-sub-research",
                        worktreeBranch: "swft/reconnect-audit",
                        startedAt: at(2),
                        completedAt: at(44)
                    )
                ),
                startedAt: at(2),
                completedAt: at(44)
            ),
            .init(
                id: "sa-a1",
                kind: .assistant(blocks: [
                    .text("The researcher traced both reconnect edge cases — `ServerConnection` can drop a pending completion marker when a ticket expires mid-handshake. I'll fan out the fix, test coverage, and migration check in parallel."),
                ], streaming: false),
                startedAt: at(45),
                completedAt: at(48)
            ),
            .init(id: "sa-u2", kind: .user("Go ahead and run the parallel implementation passes now."), startedAt: at(60)),
            .init(
                id: "sa-group-1",
                kind: .subagent(
                    SubagentItem(
                        id: "sa-group-1",
                        subagentID: "node-sa-2",
                        runID: "run-sa-2",
                        providerTurnID: "turn-sa-2",
                        origin: "app_owned",
                        title: "Reconnect Fixer",
                        provider: .codex,
                        providerDriver: "codex",
                        providerInstanceID: "codex",
                        providerDisplayName: "Codex",
                        modelName: "GPT-6.1",
                        status: .running,
                        prompt: "Guard ticket expiry during WebSocket handshake and reset resume sequence safely.",
                        progress: "Editing Sources/SwftKit/ServerConnection.swift",
                        result: nil,
                        childThreadID: "t4-sub-ui",
                        worktreeBranch: "fix/ws-handshake",
                        startedAt: at(62),
                        completedAt: nil
                    )
                ),
                startedAt: at(62)
            ),
            .init(
                id: "sa-group-2",
                kind: .subagent(
                    SubagentItem(
                        id: "sa-group-2",
                        subagentID: "node-sa-3",
                        runID: "run-sa-2",
                        providerTurnID: "turn-sa-2",
                        origin: "app_owned",
                        title: "Store Replay Tests",
                        provider: .claude,
                        providerDriver: "claudeAgent",
                        providerInstanceID: "claudeAgent",
                        providerDisplayName: "Claude",
                        modelName: "Haiku 5.5",
                        status: .completed,
                        prompt: "Add deterministic ThreadStore replay and sequence deduplication tests.",
                        progress: nil,
                        result: "Added 6 unit tests covering out-of-order replay and snapshot recovery.",
                        childThreadID: "t4-sub-tests",
                        startedAt: at(62),
                        completedAt: at(88)
                    )
                ),
                startedAt: at(62),
                completedAt: at(88)
            ),
            .init(
                id: "sa-group-3",
                kind: .subagent(
                    SubagentItem(
                        id: "sa-group-3",
                        subagentID: "node-sa-4",
                        runID: "run-sa-2",
                        providerTurnID: "turn-sa-2",
                        origin: "app_owned",
                        title: "Contract Compatibility Check",
                        provider: .gemini,
                        providerDriver: "antigravity",
                        providerInstanceID: "antigravity",
                        providerDisplayName: "Antigravity",
                        modelName: "Gemini 3 Pro",
                        status: .failed,
                        prompt: "Verify backwards compatibility against protocol v2 fixtures.",
                        progress: nil,
                        result: "Fixture mismatch on `snapshot-required` envelope in legacy server v0.1.9.",
                        childThreadID: nil,
                        startedAt: at(63),
                        completedAt: at(76)
                    )
                ),
                startedAt: at(63),
                completedAt: at(76)
            ),
            .init(
                id: "sa-native-1",
                kind: .subagent(
                    SubagentItem(
                        id: "sa-native-1",
                        subagentID: "node-sa-5",
                        runID: "run-sa-2",
                        providerTurnID: "turn-sa-3",
                        origin: "provider_native",
                        title: "Native Doc Verifier",
                        provider: .cursor,
                        providerDriver: "cursor",
                        providerInstanceID: "cursor",
                        providerDisplayName: "Cursor",
                        modelName: "Composer 2",
                        status: .waiting,
                        prompt: "Check whether `docs/internals/09_connection-runtime.md` documents the new reconnect sequence.",
                        progress: "Waiting on file lock before reading connection runtime docs",
                        result: nil,
                        childThreadID: nil,
                        worktreeBranch: "studio",
                        startedAt: at(70),
                        completedAt: nil
                    )
                ),
                startedAt: at(70)
            ),
        ],
        diffStat: "+84 −19",
        isRunning: true
    )

    static let subagentChildDetails: [ThreadDetailState] = [
        ThreadDetailState(
            summary: ThreadSummary(
                id: "t4-sub-research",
                title: "Codebase Researcher",
                project: studio,
                location: .branch("swft/reconnect-audit"),
                provider: .claude,
                providerDisplayName: "Claude",
                activity: .idle,
                updatedAt: ago(28),
                providerDriver: "claudeAgent"
            ),
            items: [
                .init(id: "sub-r-u1", kind: .user("Trace WebSocket reconnect backoff, resume sequences, and subscription replay across ServerConnection and ThreadStore."), startedAt: at(2)),
                .init(id: "sub-r-t1", kind: .toolCall(.init(kind: .search, title: "Searched", detail: "lastSequence", status: .succeeded, duration: 0.3, output: nil)), startedAt: at(4), completedAt: at(4.3)),
                .init(id: "sub-r-t2", kind: .toolCall(.init(kind: .read, title: "Read", detail: "Sources/SwftKit/Stores/ThreadStore.swift", status: .succeeded, duration: 0.2, output: nil)), startedAt: at(5), completedAt: at(5.2)),
                .init(id: "sub-r-a1", kind: .assistant(blocks: [
                    .text("Found 2 stale sequence edge cases in `ServerConnection`:\n- Expired bootstrap tickets retry without clearing `resumeSequence`.\n- `ThreadStore` already deduplicates strictly via `sequence <= lastSequence`."),
                ], streaming: false), startedAt: at(40), completedAt: at(44)),
            ],
            diffStat: nil,
            isRunning: false,
            parentLink: SubagentParentLink(threadID: threads[3].id, title: threads[3].title, environmentID: nil)
        ),
        ThreadDetailState(
            summary: ThreadSummary(
                id: "t4-sub-ui",
                title: "Reconnect Fixer",
                project: studio,
                location: .branch("fix/ws-handshake"),
                provider: .codex,
                providerDisplayName: "Codex",
                activity: .running,
                updatedAt: ago(1),
                providerDriver: "codex"
            ),
            items: [
                .init(id: "sub-u-u1", kind: .user("Guard ticket expiry during WebSocket handshake and reset resume sequence safely."), startedAt: at(62)),
                .init(id: "sub-u-t1", kind: .toolCall(.init(kind: .edit, title: "Editing", detail: "Sources/SwftKit/ServerConnection.swift", status: .running, duration: nil, output: nil)), startedAt: at(65)),
            ],
            diffStat: "+24 −8",
            isRunning: true,
            parentLink: SubagentParentLink(threadID: threads[3].id, title: threads[3].title, environmentID: nil)
        ),
        ThreadDetailState(
            summary: ThreadSummary(
                id: "t4-sub-tests",
                title: "Store Replay Tests",
                project: studio,
                location: .branch("studio"),
                provider: .claude,
                providerDisplayName: "Claude",
                activity: .idle,
                updatedAt: ago(2),
                providerDriver: "claudeAgent"
            ),
            items: [
                .init(id: "sub-t-u1", kind: .user("Add deterministic ThreadStore replay and sequence deduplication tests."), startedAt: at(62)),
                .init(id: "sub-t-a1", kind: .assistant(blocks: [
                    .text("Added 6 unit tests covering out-of-order replay and snapshot recovery in `StoreTests.swift`. All passing."),
                ], streaming: false), startedAt: at(84), completedAt: at(88)),
            ],
            diffStat: "+60 −11",
            isRunning: false,
            parentLink: SubagentParentLink(threadID: threads[3].id, title: threads[3].title, environmentID: nil)
        ),
    ]
}
