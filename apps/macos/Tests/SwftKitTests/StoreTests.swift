import Foundation
import Testing
@testable import SwftKit

@Suite("Stores & Process Safety")
struct StoreTests {
    private static func makeDummyConnection() -> ServerConnection {
        ServerConnection(
            httpBaseURL: URL(string: "http://127.0.0.1:1")!,
            credential: .bootstrapToken("test")
        )
    }

    @Test @MainActor func threadsStorePreservesThreadsOnEnrichmentSnapshotAndComputesSidebarState() {
        let store = ThreadsStore(connection: Self.makeDummyConnection())
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let project = ProjectShell(
            id: "proj-1",
            title: "Swft",
            workspaceRoot: "/Users/dev/swft",
            createdAt: now,
            updatedAt: now
        )
        let unreadThread = ThreadShell(
            id: "thr-1",
            projectId: "proj-1",
            title: "Build SwftKit",
            providerInstanceId: "codex",
            modelSelection: ModelSelection(instanceId: "codex", model: "gpt-6-astra"),
            branch: "swft/main",
            worktreePath: "/tmp/wt-1",
            latestRunCompletedAt: now,
            status: .run(.completed),
            createdAt: now.addingTimeInterval(-300),
            updatedAt: now,
            lastVisitedAt: now.addingTimeInterval(-60)
        )
        let approvalThread = ThreadShell(
            id: "thr-2",
            projectId: "proj-1",
            title: "Waiting approval",
            providerInstanceId: "codex",
            modelSelection: ModelSelection(instanceId: "codex", model: "gpt-6-astra"),
            status: .run(.waiting),
            pendingRuntimeRequest: PendingRuntimeRequestSummary(
                id: "req-1",
                kind: "command",
                createdAt: now
            ),
            createdAt: now.addingTimeInterval(-400),
            updatedAt: now.addingTimeInterval(-10)
        )
        let hiddenSubagent = ThreadShell(
            id: "thr-sub",
            projectId: "proj-1",
            title: "Subagent child",
            providerInstanceId: "codex",
            modelSelection: ModelSelection(instanceId: "codex", model: "gpt-6-astra"),
            lineage: ThreadLineage(
                parentThreadId: "thr-1",
                relationshipToParent: "subagent",
                rootThreadId: "thr-1"
            ),
            createdAt: now,
            updatedAt: now
        )

        store.apply(.snapshot(
            ShellSnapshot(
                snapshotSequence: 10,
                projects: [project],
                threads: [unreadThread, approvalThread, hiddenSubagent]
            ),
            resolvedRepositoryIdentityRoots: nil
        ))
        store.apply(.synchronized)

        #expect(store.isSynchronized)
        #expect(store.listedThreads.map(\.id) == ["thr-1", "thr-2"])

        // Enrichment snapshot with empty threads array MUST NOT wipe threads!
        let enrichedProject = ProjectShell(
            id: "proj-1",
            title: "Swft",
            workspaceRoot: "/Users/dev/swft",
            repositoryIdentity: RepositoryIdentity(
                canonicalKey: "github.com/gojimq/swft",
                displayName: "gojimq/swft"
            ),
            createdAt: now,
            updatedAt: now
        )
        store.apply(.snapshot(
            ShellSnapshot(snapshotSequence: 10, projects: [enrichedProject], threads: []),
            resolvedRepositoryIdentityRoots: ["/Users/dev/swft"]
        ))

        #expect(store.threads.count == 3)
        #expect(store.projects.first?.repositoryIdentity?.displayName == "gojimq/swft")

        // Stale sequence delta (<= 10) is ignored.
        store.apply(.threadRemoved(sequence: 10, location: .active, threadId: "thr-1"))
        #expect(store.threads.count == 3)

        let rows = store.sidebarItems
        #expect(rows.count == 2)
        #expect(rows[0].id == "thr-1")
        #expect(rows[0].isUnread)
        #expect(!rows[0].isRunning)
        #expect(rows[0].projectTitle == "Swft")
        #expect(rows[0].branch == "swft/main")

        #expect(rows[1].id == "thr-2")
        #expect(rows[1].needsApproval)
        #expect(!rows[1].isRunning)
    }

    @Test @MainActor func threadStoreReducesStreamingTurnItemsApprovalsAndRollbacks() {
        let store = ThreadStore(connection: Self.makeDummyConnection(), threadId: "thr-1")
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)

        let thread = AppThread(
            id: "thr-1",
            projectId: "proj-1",
            title: "Streaming test",
            providerInstanceId: "codex",
            modelSelection: ModelSelection(instanceId: "codex", model: "gpt-6-astra"),
            createdAt: t0,
            updatedAt: t0
        )
        let run1 = Run(
            id: "run-1",
            threadId: "thr-1",
            ordinal: 1,
            providerInstanceId: "codex",
            modelSelection: thread.modelSelection,
            userMessageId: "msg-u1",
            status: .running,
            requestedAt: t0,
            startedAt: t0
        )
        store.apply(.snapshot(
            snapshotSequence: 1,
            projection: ThreadProjection(thread: thread, runs: [run1], updatedAt: t0)
        ))
        #expect(store.isRunning)

        // Stream assistant message item (ordinal 2) then earlier user message (ordinal 1)
        let assistantPartial = TurnItem(
            id: "item-a1",
            threadId: "thr-1",
            runId: "run-1",
            ordinal: 2,
            status: "running",
            updatedAt: t0.addingTimeInterval(1),
            kind: .assistantMessage(
                messageId: "msg-a1",
                text: "Hello",
                streaming: true,
                phase: nil,
                delivery: nil,
                attachments: []
            )
        )
        store.apply(.event(
            sequence: 2,
            event: DomainEvent(
                id: "ev-2",
                threadId: "thr-1",
                occurredAt: t0.addingTimeInterval(1),
                type: "turn-item.updated",
                kind: .turnItemUpdated(assistantPartial)
            )
        ))

        let userItem = TurnItem(
            id: "item-u1",
            threadId: "thr-1",
            runId: "run-1",
            ordinal: 1,
            status: "completed",
            updatedAt: t0,
            kind: .userMessage(
                messageId: "msg-u1",
                text: "Hi",
                inputIntent: "turn_start",
                attachments: [],
                createdBy: "user",
                creationSource: "web"
            )
        )
        store.apply(.event(
            sequence: 3,
            event: DomainEvent(
                id: "ev-3",
                threadId: "thr-1",
                occurredAt: t0.addingTimeInterval(2),
                type: "turn-item.updated",
                kind: .turnItemUpdated(userItem)
            )
        ))

        // Sorted by ordinal: user (1) before assistant (2)
        #expect(store.visibleItems.map(\.sourceItemId) == ["item-u1", "item-a1"])
        #expect(store.visibleItems.map(\.position) == [0, 1])

        // Replacement text update on assistant message keeps position 1
        let assistantFinal = TurnItem(
            id: "item-a1",
            threadId: "thr-1",
            runId: "run-1",
            ordinal: 2,
            status: "completed",
            updatedAt: t0.addingTimeInterval(3),
            kind: .assistantMessage(
                messageId: "msg-a1",
                text: "Hello, world!",
                streaming: false,
                phase: "final_answer",
                delivery: nil,
                attachments: []
            )
        )
        store.apply(.event(
            sequence: 4,
            event: DomainEvent(
                id: "ev-4",
                threadId: "thr-1",
                occurredAt: t0.addingTimeInterval(3),
                type: "turn-item.updated",
                kind: .turnItemUpdated(assistantFinal)
            )
        ))
        if case .assistantMessage(_, let text, let streaming, _, _, _) = store.visibleItems[1].item.kind {
            #expect(text == "Hello, world!")
            #expect(!streaming)
        } else {
            Issue.record("Expected updated assistant message")
        }

        // Unknown event advances lastSequence without breaking state
        store.apply(.unknownEvent(sequence: 5, eventType: "future.event"))
        #expect(store.lastSequence == 5)

        // Run output preserved across subsequent run.updated without output
        let output = RunOutput(value: .object(["ok": .bool(true)]), submittedAt: "2026-11-24T19:00:05.000Z")
        store.apply(.event(
            sequence: 6,
            event: DomainEvent(
                id: "ev-6",
                threadId: "thr-1",
                occurredAt: t0.addingTimeInterval(4),
                type: "run.output-submitted",
                kind: .runOutputSubmitted(runId: "run-1", output: output)
            )
        ))
        let completedRun = Run(
            id: "run-1",
            threadId: "thr-1",
            ordinal: 1,
            providerInstanceId: "codex",
            modelSelection: thread.modelSelection,
            userMessageId: "msg-u1",
            status: .completed,
            requestedAt: t0,
            startedAt: t0,
            completedAt: t0.addingTimeInterval(5)
        )
        store.apply(.event(
            sequence: 7,
            event: DomainEvent(
                id: "ev-7",
                threadId: "thr-1",
                occurredAt: t0.addingTimeInterval(5),
                type: "run.updated",
                kind: .runUpserted(completedRun)
            )
        ))
        #expect(!store.isRunning)
        #expect(store.runs.first?.output == output)

        // Rolling back run-1 hides its turn items
        let rolledBackRun = Run(
            id: "run-1",
            threadId: "thr-1",
            ordinal: 1,
            providerInstanceId: "codex",
            modelSelection: thread.modelSelection,
            userMessageId: "msg-u1",
            status: .rolledBack,
            requestedAt: t0,
            startedAt: t0,
            completedAt: t0.addingTimeInterval(6)
        )
        store.apply(.event(
            sequence: 8,
            event: DomainEvent(
                id: "ev-8",
                threadId: "thr-1",
                occurredAt: t0.addingTimeInterval(6),
                type: "run.updated",
                kind: .runUpserted(rolledBackRun)
            )
        ))
        #expect(store.visibleItems.isEmpty)
    }

    @Test func serverProcessRejectsLiveT3UserdataDirectory() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let forbiddenRoot = home.appendingPathComponent(".t3", isDirectory: true)
        let forbiddenUserdata = forbiddenRoot.appendingPathComponent("userdata", isDirectory: true)

        #expect(throws: ServerProcessError.self) {
            try ServerProcess.validateBaseDirectory(forbiddenRoot)
        }
        #expect(throws: ServerProcessError.self) {
            try ServerProcess.validateBaseDirectory(forbiddenUserdata)
        }

        // Default Swft directory and temp dirs are permitted.
        try ServerProcess.validateBaseDirectory(ServerLaunchConfiguration.defaultBaseDirectory)
        try ServerProcess.validateBaseDirectory(
            FileManager.default.temporaryDirectory.appendingPathComponent("swft-test-dir", isDirectory: true)
        )
    }
}
