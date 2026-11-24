import Foundation
import Testing
@testable import Swft
@testable import SwftKit

@Suite("Swft Adapters, Markdown & Visit Throttling")
struct AdapterTests {
    @Test func parsesMarkdownProseAndFencedCodeBlocksIncludingStreaming() {
        let complete = """
        Here is a summary:

        ```swift
        let x = 1
        print(x)
        ```

        And `inline` backticks stay in prose.
        """
        let blocks = MarkdownBlockParser.parse(complete)
        #expect(blocks == [
            .text("Here is a summary:"),
            .code(language: "swift", source: "let x = 1\nprint(x)"),
            .text("And `inline` backticks stay in prose."),
        ])

        // Mid-stream unclosed fence should still render as a code block rather than raw backticks.
        let streaming = "Starting:\n```ts\nconst a = 42"
        #expect(MarkdownBlockParser.parse(streaming) == [
            .text("Starting:"),
            .code(language: "ts", source: "const a = 42"),
        ])

        // Tilde fence without language.
        let tilde = "~~~\nhello\n~~~"
        #expect(MarkdownBlockParser.parse(tilde) == [
            .code(language: nil, source: "hello"),
        ])
    }

    @Test func adaptsProvidersModelsAndThinkingOptions() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let codex = ServerProvider(
            instanceId: "codex-work",
            driver: "codex",
            displayName: "Codex Work",
            enabled: true,
            installed: true,
            status: .ready,
            auth: ServerProviderAuth(status: .authenticated),
            checkedAt: now,
            models: [
                ServerProviderModel(
                    slug: "gpt-6-mini",
                    name: "GPT-6 Mini",
                    shortName: "Mini",
                    isDefault: true,
                    capabilities: ModelCapabilities(optionDescriptors: [
                        .select(.init(
                            id: "reasoningEffort",
                            label: "Reasoning",
                            options: [
                                .init(id: "low", label: "Low"),
                                .init(id: "high", label: "High", isDefault: true),
                            ],
                            currentValue: "high",
                            role: "reasoning"
                        ))
                    ])
                ),
                ServerProviderModel(
                    slug: "old-model",
                    name: "Legacy Model",
                    isLegacy: true
                ),
            ]
        )
        let disabled = ServerProvider(
            instanceId: "disabled-one",
            driver: "cursor",
            enabled: false,
            installed: false,
            status: .disabled,
            auth: ServerProviderAuth(status: .unauthenticated),
            checkedAt: now,
            models: [ServerProviderModel(slug: "c1", name: "Composer")]
        )

        let options = SwftAdapters.modelOptions(from: [disabled, codex])
        #expect(options.count == 1)
        #expect(options[0].instanceId == "codex-work")
        #expect(options[0].slug == "gpt-6-mini")
        #expect(options[0].name == "Mini")
        #expect(options[0].provider == .codex)
        #expect(options[0].providerDisplayName == "Codex Work")
        #expect(options[0].reasoningOptionId == "reasoningEffort")
        #expect(options[0].reasoningChoices.map(\.id) == ["low", "high"])
        #expect(options[0].defaultReasoningChoiceId == "high")

        let wireSelection = SwftAdapters.modelSelection(from: options[0], reasoningChoiceId: "low")
        #expect(wireSelection.instanceId == "codex-work")
        #expect(wireSelection.model == "gpt-6-mini")
        #expect(wireSelection.options == [.string("reasoningEffort", "low")])
    }

    @Test func mapsSidebarThreadSummaryStatusesAndMetadata() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let project = ProjectShell(
            id: "proj-1",
            title: "Scratch Repo",
            workspaceRoot: "/tmp/scratch-repo",
            createdAt: now,
            updatedAt: now
        )
        let provider = ServerProvider(
            instanceId: "claudeAgent",
            driver: "claudeAgent",
            displayName: "Claude",
            enabled: true,
            installed: true,
            status: .ready,
            auth: ServerProviderAuth(status: .authenticated),
            checkedAt: now,
            models: []
        )

        let approvalShell = ThreadShell(
            id: "t-approval",
            projectId: "proj-1",
            title: "Needs approval",
            providerInstanceId: "claudeAgent",
            modelSelection: ModelSelection(instanceId: "claudeAgent", model: "haiku"),
            branch: "feat/test",
            status: .run(.waiting),
            pendingRuntimeRequest: PendingRuntimeRequestSummary(id: "r1", kind: "command", createdAt: now),
            createdAt: now,
            updatedAt: now
        )
        let unreadShell = ThreadShell(
            id: "t-unread",
            projectId: "proj-1",
            title: "Unread done",
            providerInstanceId: "claudeAgent",
            modelSelection: ModelSelection(instanceId: "claudeAgent", model: "haiku"),
            latestRunCompletedAt: now,
            status: .run(.completed),
            createdAt: now.addingTimeInterval(-60),
            updatedAt: now,
            lastVisitedAt: now.addingTimeInterval(-30)
        )
        let failedShell = ThreadShell(
            id: "t-failed",
            projectId: "proj-1",
            title: "Errored run",
            providerInstanceId: "claudeAgent",
            modelSelection: ModelSelection(instanceId: "claudeAgent", model: "haiku"),
            status: .run(.failed),
            lastError: "Rate limited",
            createdAt: now,
            updatedAt: now
        )

        let approvalRow = SwftAdapters.threadSummary(
            from: approvalShell,
            projectsByID: [project.id: project],
            providersByID: [provider.instanceId: provider],
            hostName: "MacBook Pro",
            activelyViewingThreadID: nil
        )
        #expect(approvalRow.project?.initials == "SR")
        #expect(approvalRow.location == .branch("feat/test"))
        #expect(approvalRow.activity == .needsApproval)
        #expect(approvalRow.provider == .claude)

        let unreadRow = SwftAdapters.threadSummary(
            from: unreadShell,
            projectsByID: [project.id: project],
            providersByID: [provider.instanceId: provider],
            hostName: "MacBook Pro",
            activelyViewingThreadID: nil
        )
        #expect(unreadRow.location == .host("MacBook Pro"))
        #expect(unreadRow.activity == .unread)

        // When actively viewing the thread, unread badge is suppressed.
        let viewingRow = SwftAdapters.threadSummary(
            from: unreadShell,
            projectsByID: [project.id: project],
            providersByID: [provider.instanceId: provider],
            hostName: "MacBook Pro",
            activelyViewingThreadID: "t-unread"
        )
        #expect(viewingRow.activity == .idle)

        let failedRow = SwftAdapters.threadSummary(
            from: failedShell,
            projectsByID: [project.id: project],
            providersByID: [provider.instanceId: provider],
            hostName: "MacBook Pro",
            activelyViewingThreadID: nil
        )
        #expect(failedRow.activity == .failed)
    }

    @Test func mapsThreadProjectionTranscriptWithStreamingToolsApprovalsAndErrors() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let thread = AppThread(
            id: "thr-1",
            projectId: "proj-1",
            title: "Live Thread",
            providerInstanceId: "claudeAgent",
            modelSelection: ModelSelection(instanceId: "claudeAgent", model: "haiku"),
            branch: "main",
            createdAt: t0,
            updatedAt: t0
        )
        let items: [ProjectedTurnItem] = [
            ProjectedTurnItem(
                position: 0,
                visibility: .local,
                sourceThreadId: "thr-1",
                sourceItemId: "i1",
                item: TurnItem(
                    id: "i1",
                    threadId: "thr-1",
                    ordinal: 1,
                    status: "completed",
                    updatedAt: t0,
                    kind: .userMessage(messageId: "m1", text: "Hello", inputIntent: "turn_start", attachments: [], createdBy: "user", creationSource: "web")
                )
            ),
            ProjectedTurnItem(
                position: 1,
                visibility: .local,
                sourceThreadId: "thr-1",
                sourceItemId: "i2",
                item: TurnItem(
                    id: "i2",
                    threadId: "thr-1",
                    ordinal: 2,
                    status: "completed",
                    startedAt: t0,
                    completedAt: t0.addingTimeInterval(0.5),
                    updatedAt: t0,
                    kind: .reasoning(text: "Checking repo structure first.", streaming: false)
                )
            ),
            ProjectedTurnItem(
                position: 2,
                visibility: .local,
                sourceThreadId: "thr-1",
                sourceItemId: "i3",
                item: TurnItem(
                    id: "i3",
                    threadId: "thr-1",
                    ordinal: 3,
                    status: "completed",
                    startedAt: t0,
                    completedAt: t0.addingTimeInterval(1.2),
                    updatedAt: t0,
                    kind: .commandExecution(input: "git status", output: "clean", outputOmitted: false, outputIndicatesFailure: false, exitCode: 0, monitor: nil)
                )
            ),
            ProjectedTurnItem(
                position: 3,
                visibility: .local,
                sourceThreadId: "thr-1",
                sourceItemId: "i4",
                item: TurnItem(
                    id: "i4",
                    threadId: "thr-1",
                    ordinal: 4,
                    status: "waiting",
                    title: "Run rm?",
                    updatedAt: t0,
                    kind: .approvalRequest(requestId: "req-42", requestKind: "command", prompt: "rm -rf build", reason: "Clean build", fullAccessOverride: nil, appName: nil, options: nil)
                )
            ),
            ProjectedTurnItem(
                position: 4,
                visibility: .local,
                sourceThreadId: "thr-1",
                sourceItemId: "i5",
                item: TurnItem(
                    id: "i5",
                    threadId: "thr-1",
                    ordinal: 5,
                    status: "running",
                    updatedAt: t0,
                    kind: .assistantMessage(messageId: "m2", text: "Done:\n```swift\nlet ok = true\n```", streaming: true, phase: nil, delivery: nil, attachments: [])
                )
            ),
        ]

        let projection = ThreadProjection(
            thread: thread,
            runtimeRequests: [
                RuntimeRequest(
                    id: "req-42",
                    nodeId: "n1",
                    kind: "command",
                    status: "pending",
                    responseCapability: .live(providerSessionId: "s1", supportsFeedback: true),
                    createdAt: t0
                )
            ],
            visibleTurnItems: items,
            updatedAt: t0
        )

        let summary = ThreadSummary(
            id: "thr-1",
            title: "Old",
            project: nil,
            location: nil,
            provider: .claude,
            activity: .running,
            updatedAt: t0
        )
        let detail = SwftAdapters.threadDetail(from: projection, summary: summary)
        #expect(detail.summary.title == "Live Thread")
        #expect(detail.summary.location == .branch("main"))
        #expect(detail.items.count == 5)

        #expect(detail.items[0].kind == .user("Hello"))
        if case .toolCall(let thought) = detail.items[1].kind {
            #expect(thought.kind == .thinking)
            #expect(thought.title == "Thought")
            #expect(thought.output == "Checking repo structure first.")
        } else {
            Issue.record("Expected reasoning tool card")
        }
        if case .toolCall(let cmd) = detail.items[2].kind {
            #expect(cmd.kind == .command)
            #expect(cmd.detail == "git status")
            #expect(cmd.status == .succeeded)
        } else {
            Issue.record("Expected command tool card")
        }
        if case .approval(let approval) = detail.items[3].kind {
            #expect(approval.requestId == "req-42")
            #expect(approval.command == "rm -rf build")
            #expect(approval.status == .pending)
        } else {
            Issue.record("Expected approval card")
        }
        if case .assistant(let blocks, let streaming) = detail.items[4].kind {
            #expect(streaming)
            #expect(blocks == [.text("Done:"), .code(language: "swift", source: "let ok = true")])
        } else {
            Issue.record("Expected assistant message with code block")
        }
    }

    @Test func throttlesThreadVisitsWhileStreamingAndFlushesOnCompletion() {
        var policy = ThreadVisitPolicy()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)

        policy.selectThread("thr-1")
        // Initial open dispatches immediately with opened: true.
        let openAction = policy.evaluate(
            threadId: "thr-1",
            updatedAt: t0,
            lastVisitedAt: nil,
            latestRunCompletedAt: nil,
            now: t0
        )
        #expect(openAction == .dispatchNow(visitedAt: t0, opened: true))

        // Streaming tick 2s later is deferred by 8s.
        let streamAction = policy.evaluate(
            threadId: "thr-1",
            updatedAt: t0.addingTimeInterval(2),
            lastVisitedAt: t0,
            latestRunCompletedAt: nil,
            now: t0.addingTimeInterval(2)
        )
        #expect(streamAction == .deferBy(8, visitedAt: t0.addingTimeInterval(2)))

        // Run completion flushes immediately without waiting for throttle window.
        let completedAction = policy.evaluate(
            threadId: "thr-1",
            updatedAt: t0.addingTimeInterval(4),
            lastVisitedAt: t0,
            latestRunCompletedAt: t0.addingTimeInterval(4),
            now: t0.addingTimeInterval(4)
        )
        #expect(completedAction == .dispatchNow(visitedAt: t0.addingTimeInterval(4), opened: false))
    }

    @Test @MainActor func launchFlagMockModeDetection() {
        let suiteName = "swft-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(!AppModel.shouldUseMockMode(arguments: ["Swft"], defaults: defaults))
        #expect(AppModel.shouldUseMockMode(arguments: ["Swft", "-SwftMock"], defaults: defaults))
        #expect(AppModel.shouldUseMockMode(arguments: ["Swft", "-SwftMock", "YES"], defaults: defaults))
        #expect(!AppModel.shouldUseMockMode(arguments: ["Swft", "-SwftMock", "NO"], defaults: defaults))

        defaults.set("thread", forKey: "SwftScreen")
        #expect(AppModel.shouldUseMockMode(arguments: ["Swft"], defaults: defaults))
        #expect(!AppModel.shouldUseMockMode(arguments: ["Swft", "-SwftMock", "NO"], defaults: defaults))
    }
}
