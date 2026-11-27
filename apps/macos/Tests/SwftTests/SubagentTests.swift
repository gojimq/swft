import Foundation
import SwftDesign
import Testing
@testable import Swft
@testable import SwftKit

@Suite("Inline Subagent Display, Layout & Navigation")
struct SubagentTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    private func subagentItem(
        id: String,
        title: String = "Researcher",
        status: SubagentStatus = .completed,
        runID: String? = "run-1",
        providerTurnID: String? = "turn-1",
        childThreadID: String? = nil,
        remoteEnvID: String? = nil,
        remoteThreadID: String? = nil,
        start: Double? = 1,
        end: Double? = 15
    ) -> TranscriptItem {
        TranscriptItem(
            id: id,
            kind: .subagent(
                SubagentItem(
                    id: id,
                    subagentID: "node-\(id)",
                    runID: runID,
                    providerTurnID: providerTurnID,
                    title: title,
                    provider: .claude,
                    modelName: "Opus 5.5",
                    status: status,
                    prompt: "Prompt for \(id)",
                    childThreadID: childThreadID,
                    remoteEnvironmentID: remoteEnvID,
                    remoteThreadID: remoteThreadID,
                    startedAt: start.map(at),
                    completedAt: end.map(at)
                )
            ),
            startedAt: start.map(at),
            completedAt: end.map(at)
        )
    }

    // MARK: - SubagentDisplayLogic

    @Test func formatsDisplayTitlesMatchingWebRules() {
        #expect(SubagentDisplayLogic.formatDisplayTitle("Subagent: Codebase Researcher") == "Codebase Researcher")
        #expect(SubagentDisplayLogic.formatDisplayTitle("subagent:   API Auditor") == "API Auditor")
        #expect(SubagentDisplayLogic.formatDisplayTitle("/root/agents/security_reviewer/") == "Security Reviewer")
        #expect(SubagentDisplayLogic.formatDisplayTitle("/root/db_migrator") == "Db Migrator")
        #expect(SubagentDisplayLogic.formatDisplayTitle(nil, fallbackPrompt: "  Trace the reconnect loop\nSecond line") == "Trace the reconnect loop")
        let longPrompt = String(repeating: "a", count: 100)
        let truncated = SubagentDisplayLogic.formatDisplayTitle("", fallbackPrompt: longPrompt)
        #expect(truncated.hasSuffix("…"))
        #expect(truncated.count <= 80)
        #expect(SubagentDisplayLogic.formatDisplayTitle(nil, fallbackPrompt: "   ") == "Subagent")
    }

    @Test func cleansCardDetailAndPicksActiveVsSettledSnippet() {
        #expect(SubagentDisplayLogic.cleanCardDetail("Child task ended with status completed") == nil)
        #expect(
            SubagentDisplayLogic.cleanCardDetail("- Checked [`ServerConnection.swift`](file:///a) and `ThreadStore`")
                == "Checked ServerConnection.swift and ThreadStore"
        )
        #expect(
            SubagentDisplayLogic.detailPreview(status: .running, progress: "Scanning files", result: "Old result")
                == "Scanning files"
        )
        #expect(
            SubagentDisplayLogic.detailPreview(status: .completed, progress: "Scanning files", result: "All 12 tests passed")
                == "All 12 tests passed"
        )
        #expect(
            SubagentDisplayLogic.detailPreview(status: .failed, progress: "Running build", result: nil)
                == "Running build"
        )
    }

    @Test func formatsElapsedTimesForActiveAndSettledSubagents() {
        #expect(SubagentDisplayLogic.formatElapsedSeconds(0) == "0s")
        #expect(SubagentDisplayLogic.formatElapsedSeconds(14) == "14s")
        #expect(SubagentDisplayLogic.formatElapsedSeconds(65) == "1m 05s")
        #expect(SubagentDisplayLogic.formatElapsedSeconds(82) == "1m 22s")
        #expect(SubagentDisplayLogic.formatElapsedSeconds(3840) == "1h 04m")

        // Active subagent measures against `now`.
        #expect(
            SubagentDisplayLogic.formatElapsed(
                startedAt: at(10),
                completedAt: nil,
                status: .running,
                now: at(24.9)
            ) == "14s"
        )
        // Settled subagent freezes at `completedAt`, ignoring `now`.
        #expect(
            SubagentDisplayLogic.formatElapsed(
                startedAt: at(10),
                completedAt: at(92),
                status: .completed,
                now: at(500)
            ) == "1m 22s"
        )
        // Missing start or settled without end returns nil.
        #expect(SubagentDisplayLogic.formatElapsed(startedAt: nil, completedAt: at(10), status: .completed, now: at(20)) == nil)
        #expect(SubagentDisplayLogic.formatElapsed(startedAt: at(10), completedAt: nil, status: .completed, now: at(20)) == nil)
    }

    @Test func summarizesParallelGroupStatusesAndAggregateTiming() {
        #expect(SubagentDisplayLogic.groupHeaderTitle(count: 1) == "1 subagent")
        #expect(SubagentDisplayLogic.groupHeaderTitle(count: 3) == "3 subagents")

        #expect(
            SubagentDisplayLogic.summarizeGroupStatuses([.running, .pending, .completed])
                == "2 running · 1 done"
        )
        #expect(
            SubagentDisplayLogic.summarizeGroupStatuses([.waiting, .completed, .failed, .cancelled])
                == "1 waiting · 1 done · 1 failed · 1 stopped"
        )

        let runningMembers = [
            SubagentItem(id: "a", title: "A", provider: .claude, status: .running, startedAt: at(10), completedAt: nil),
            SubagentItem(id: "b", title: "B", provider: .codex, status: .completed, startedAt: at(12), completedAt: at(25)),
        ]
        let activeTiming = SubagentDisplayLogic.groupTiming(for: runningMembers)
        #expect(activeTiming.isActive)
        #expect(activeTiming.hasSpinnerActivity)
        #expect(activeTiming.startedAt == at(10))
        #expect(activeTiming.completedAt == nil)

        let settledMembers = [
            SubagentItem(id: "a", title: "A", provider: .claude, status: .completed, startedAt: at(10), completedAt: at(42)),
            SubagentItem(id: "b", title: "B", provider: .codex, status: .failed, startedAt: at(12), completedAt: at(30)),
        ]
        let settledTiming = SubagentDisplayLogic.groupTiming(for: settledMembers)
        #expect(!settledTiming.isActive)
        #expect(settledTiming.hasFailed)
        #expect(settledTiming.startedAt == at(10))
        #expect(settledTiming.completedAt == at(42))
    }

    @Test func resolvesModelLabelsAndStatusNormalization() {
        #expect(SubagentStatus(rawValue: "queued") == .pending)
        #expect(SubagentStatus(rawValue: "starting") == .pending)
        #expect(SubagentStatus(rawValue: "working") == .running)
        #expect(SubagentStatus(rawValue: "waiting").isWaiting)
        #expect(SubagentStatus(rawValue: "cancelled").displayLabel == "Cancelled")
        #expect(SubagentStatus(rawValue: "interrupted").displayLabel == "Stopped")

        #expect(SubagentDisplayLogic.formatModelSlugName("claude-sonnet-4-5-20250929") == "Claude Sonnet 4.5")
        #expect(SubagentDisplayLogic.formatModelSlugName("gpt-5.4-mini") == "GPT-5.4 Mini")
        #expect(SubagentDisplayLogic.formatModelSlugName("openrouter/deepseek-v4") == "Deepseek V4")
    }

    // MARK: - Adapter Merging

    @Test func adapterMergesLiveProjectionSubagentsOntoTurnItems() {
        let provider = ServerProvider(
            instanceId: "codex",
            driver: "codex",
            displayName: "Codex",
            enabled: true,
            installed: true,
            status: .ready,
            auth: ServerProviderAuth(status: .authenticated),
            checkedAt: t0,
            models: [
                ServerProviderModel(slug: "gpt-6.1", name: "GPT-6.1", shortName: "GPT-6.1"),
            ]
        )
        let childShell = ThreadShell(
            id: "thr-child-1",
            projectId: "proj-1",
            title: "Lock Auditor",
            providerInstanceId: "codex",
            modelSelection: ModelSelection(instanceId: "codex", model: "gpt-6.1"),
            branch: "fix/locks",
            worktreePath: "/tmp/wt-locks",
            lineage: ThreadLineage(parentThreadId: "thr-1", relationshipToParent: "subagent", rootThreadId: "thr-1"),
            createdAt: t0,
            updatedAt: t0
        )
        let parentThread = AppThread(
            id: "thr-1",
            projectId: "proj-1",
            title: "Parent",
            providerInstanceId: "claudeAgent",
            modelSelection: ModelSelection(instanceId: "claudeAgent", model: "opus"),
            createdAt: t0,
            updatedAt: t0
        )
        // TurnItem still has stale "running" status while projection.subagents has live "completed" + result + model.
        let staleItem = TurnItem(
            id: "item-sub-1",
            threadId: "thr-1",
            runId: "run-1",
            providerTurnId: "turn-1",
            ordinal: 1,
            status: "running",
            title: "Subagent: Lock Auditor",
            startedAt: at(10),
            completedAt: nil,
            updatedAt: at(10),
            kind: .subagent(
                subagentId: "node-1",
                origin: "app_owned",
                driver: "codex",
                providerInstanceId: "codex",
                childThreadId: "thr-child-1",
                remoteChild: nil,
                prompt: "Audit locks",
                progress: "Reading...",
                result: nil
            )
        )
        let liveSubagent = SubagentSummary(
            id: "node-1",
            threadId: "thr-1",
            runId: "run-1",
            origin: "app_owned",
            driver: "codex",
            providerInstanceId: "codex",
            childThreadId: "thr-child-1",
            prompt: "Audit locks",
            title: "Subagent: Lock Auditor",
            model: "gpt-6.1",
            status: "completed",
            progress: "Finished",
            result: "No race conditions found.",
            startedAt: at(10),
            completedAt: at(52),
            updatedAt: at(52)
        )
        let projection = ThreadProjection(
            thread: parentThread,
            subagents: [liveSubagent],
            visibleTurnItems: [
                ProjectedTurnItem(position: 0, visibility: .local, sourceThreadId: "thr-1", sourceItemId: "item-sub-1", item: staleItem)
            ],
            updatedAt: at(52)
        )
        let summary = ThreadSummary(id: "thr-1", title: "Parent", project: nil, location: nil, provider: .claude, activity: .idle, updatedAt: t0)
        let detail = SwftAdapters.threadDetail(
            from: projection,
            summary: summary,
            providersByID: ["codex": provider],
            threadsByID: ["thr-child-1": childShell]
        )

        #expect(detail.items.count == 1)
        guard case .subagent(let mapped) = detail.items[0].kind else {
            Issue.record("Expected inline .subagent TranscriptItem, not toolCall")
            return
        }
        #expect(mapped.title == "Lock Auditor")
        #expect(mapped.status == .completed)
        #expect(mapped.modelName == "GPT-6.1")
        #expect(mapped.result == "No race conditions found.")
        #expect(mapped.childThreadID == "thr-child-1")
        #expect(mapped.worktreeBranch == "fix/locks")
        #expect(mapped.startedAt == at(10))
        #expect(mapped.completedAt == at(52))
    }

    // MARK: - TranscriptLayout Grouping & Positioning

    @Test func keepsSingleSubagentInlineAtExactChronologicalPosition() {
        let items: [TranscriptItem] = [
            TranscriptItem(id: "u1", kind: .user("Check architecture"), startedAt: at(0)),
            TranscriptItem(
                id: "t1",
                kind: .toolCall(ToolCallItem(kind: .read, title: "Read", detail: "App.swift", status: .succeeded, duration: 0.2, output: nil)),
                startedAt: at(1),
                completedAt: at(1.2)
            ),
            subagentItem(id: "sa1", title: "Researcher", status: .completed, childThreadID: "child-1", start: 2, end: 18),
            TranscriptItem(
                id: "t2",
                kind: .toolCall(ToolCallItem(kind: .command, title: "Ran", detail: "swift test", status: .succeeded, duration: 3, output: nil)),
                startedAt: at(19),
                completedAt: at(22)
            ),
            TranscriptItem(id: "a1", kind: .assistant(blocks: [.text("All clear.")], streaming: false), startedAt: at(23), completedAt: at(24)),
        ]

        let rows = TranscriptLayout.rows(for: items, isRunning: false)
        #expect(rows.map(\.id) == ["u1", "work:u1", "sa1", "work:u1:t2", "a1"])
        if case .subagent(let sa) = rows[2] {
            #expect(sa.title == "Researcher")
            #expect(sa.childThreadID == "child-1")
        } else {
            Issue.record("Expected standalone inline .subagent row at index 2")
        }
    }

    @Test func groupsConsecutiveParallelSubagentsAndSeparatesDistinctTurns() {
        let items: [TranscriptItem] = [
            TranscriptItem(id: "u1", kind: .user("Fan out"), startedAt: at(0)),
            subagentItem(id: "sa1", title: "Agent 1", status: .running, runID: "r1", providerTurnID: "pt1", start: 1, end: nil),
            subagentItem(id: "sa2", title: "Agent 2", status: .completed, runID: "r1", providerTurnID: "pt1", start: 1, end: 8),
            subagentItem(id: "sa3", title: "Agent 3", status: .failed, runID: "r1", providerTurnID: "pt1", start: 2, end: 6),
            // Different providerTurnID: sequential spawn, stays standalone.
            subagentItem(id: "sa4", title: "Follow-up", status: .completed, runID: "r1", providerTurnID: "pt2", start: 10, end: 14),
            TranscriptItem(id: "a1", kind: .assistant(blocks: [.text("Summary")], streaming: false), startedAt: at(15), completedAt: at(16)),
        ]

        let rows = TranscriptLayout.rows(for: items, isRunning: true)
        #expect(rows.map(\.id) == ["u1", "subagent-group:sa1", "sa4", "a1"])
        guard case .subagentGroup(let group) = rows[1] else {
            Issue.record("Expected grouped parallel subagents")
            return
        }
        #expect(group.members.map(\.id) == ["sa1", "sa2", "sa3"])
        #expect(group.hasActive)

        // Adding a 4th parallel subagent to the same group keeps the exact same group ID.
        var expandedItems = items
        expandedItems.insert(
            subagentItem(id: "sa3b", title: "Agent 3b", status: .running, runID: "r1", providerTurnID: "pt1", start: 3, end: nil),
            at: 4
        )
        let expandedRows = TranscriptLayout.rows(for: expandedItems, isRunning: true)
        #expect(expandedRows[1].id == "subagent-group:sa1")
    }

    @Test func workingIndicatorSuppressesDuplicateSpinnerWhileSubagentRuns() {
        let activeSub = SubagentItem(id: "s1", title: "Worker", provider: .codex, status: .running, startedAt: at(1))
        let doneSub = SubagentItem(id: "s1", title: "Worker", provider: .codex, status: .completed, startedAt: at(1), completedAt: at(5))

        let runningRows: [TranscriptRow] = [.user(id: "u1", text: "Go"), .subagent(activeSub)]
        #expect(!SendFlightLogic.shouldShowWorkingIndicator(isRunning: true, isBusy: true, latestTurnRows: runningRows))

        let settledRows: [TranscriptRow] = [.user(id: "u1", text: "Go"), .subagent(doneSub)]
        #expect(SendFlightLogic.shouldShowWorkingIndicator(isRunning: true, isBusy: true, latestTurnRows: settledRows))
    }

    // MARK: - AppModel Navigation (Local, Remote & Mock)

    @Test @MainActor func clickingSubagentOpensChildInSameRemoteEnvironmentWithParentBreadcrumb() {
        let localConn = ServerConnection(httpBaseURL: URL(string: "http://127.0.0.1:3773")!, credential: .bootstrapToken("local"))
        let remoteConn = ServerConnection(httpBaseURL: URL(string: "https://studio.example.ts.net")!, credential: .bearerToken("remote"))
        let localStore = ThreadsStore(connection: localConn)
        let remoteStore = ThreadsStore(connection: remoteConn)

        let remoteProject = ProjectShell(id: "proj-remote", title: "ML Runner", workspaceRoot: "/code/ml", createdAt: t0, updatedAt: t0)
        let parentShell = ThreadShell(
            id: "thr-remote-parent",
            projectId: "proj-remote",
            title: "Optimize kernels",
            providerInstanceId: "claudeAgent",
            modelSelection: ModelSelection(instanceId: "claudeAgent", model: "opus"),
            createdAt: t0,
            updatedAt: t0
        )
        remoteStore.apply(.snapshot(
            ShellSnapshot(snapshotSequence: 1, projects: [remoteProject], threads: [parentShell]),
            resolvedRepositoryIdentityRoots: nil
        ))

        let model = AppModel.testingLive(localStore: localStore)
        let localEnv = ManagedEnvironment(
            id: "env-local",
            isLocal: true,
            httpBaseURL: URL(string: "http://127.0.0.1:3773")!,
            connection: localConn,
            threadsStore: localStore,
            lastKnownLabel: "This Mac"
        )
        let remoteEnv = ManagedEnvironment(
            id: "env-studio",
            isLocal: false,
            httpBaseURL: URL(string: "https://studio.example.ts.net")!,
            connection: remoteConn,
            threadsStore: remoteStore,
            lastKnownLabel: "Mac Studio"
        )
        model.environmentRegistry.insertEnvironmentForTesting(localEnv)
        model.environmentRegistry.insertEnvironmentForTesting(remoteEnv)

        // Open remote parent thread first.
        model.open("thr-remote-parent")
        #expect(model.activeThreadEnvironmentID == "env-studio")
        #expect(model.activeThreadStore?.connection === remoteConn)

        // Click delegated subagent whose childThreadId is NOT yet in remoteStore.threads (e.g. unlisted/omitted).
        let subagent = SubagentItem(
            id: "item-sub-9",
            title: "Kernel Profiler",
            provider: .codex,
            providerDriver: "codex",
            providerDisplayName: "Codex",
            status: .running,
            childThreadID: "thr-remote-child-9"
        )
        let target = SubagentDisplayLogic.navigationTarget(
            for: subagent,
            parentEnvironmentID: model.activeThreadEnvironmentID,
            knownEnvironmentIDs: model.knownEnvironmentIDs
        )
        #expect(target?.threadID == "thr-remote-child-9")
        #expect(target?.environmentID == "env-studio")

        model.openSubagentThread(target!, fromThreadID: "thr-remote-parent")

        // Must stay on the remote environment's ServerConnection and render immediately without flashing Home.
        #expect(model.destination == .thread("thr-remote-child-9"))
        #expect(model.activeThreadEnvironmentID == "env-studio")
        #expect(model.activeThreadStore?.threadId == "thr-remote-child-9")
        #expect(model.activeThreadStore?.connection === remoteConn)
        #expect(model.threadSummary(for: "thr-remote-child-9")?.title == "Kernel Profiler")
        #expect(model.detail(for: "thr-remote-child-9") != nil)

        // Back-to-parent breadcrumb resolves cleanly and navigates back on the same remote environment.
        let backLink = model.parentThreadLink(for: "thr-remote-child-9")
        #expect(backLink == SubagentParentLink(threadID: "thr-remote-parent", title: "Optimize kernels", environmentID: "env-studio"))

        model.openParentThread(backLink!)
        #expect(model.destination == .thread("thr-remote-parent"))
        #expect(model.activeThreadEnvironmentID == "env-studio")
        #expect(model.activeThreadStore?.connection === remoteConn)
        #expect(model.parentThreadLink(for: "thr-remote-parent") == nil)
    }

    @Test @MainActor func mockModeNavigatesIntoSubagentChildThreadAndBack() {
        let model = AppModel.mock()
        let parentID = MockData.subagentsDetail.summary.id
        model.open(parentID)

        let childTarget = SubagentNavigationTarget(
            threadID: "t4-sub-research",
            environmentID: nil,
            title: "Codebase Researcher",
            provider: .claude,
            providerDriver: "claudeAgent",
            providerDisplayName: "Claude",
            providerIconURL: nil,
            isRemoteLinked: false
        )
        model.openSubagentThread(childTarget, fromThreadID: parentID)
        #expect(model.destination == .thread("t4-sub-research"))
        #expect(model.threadSummary(for: "t4-sub-research")?.title == "Codebase Researcher")
        #expect(model.detail(for: "t4-sub-research")?.items.isEmpty == false)

        let parentLink = model.parentThreadLink(for: "t4-sub-research")
        #expect(parentLink?.threadID == parentID)
        #expect(parentLink?.title == MockData.subagentsDetail.summary.title)

        model.openParentThread(parentLink!)
        #expect(model.destination == .thread(parentID))
    }

    @Test @MainActor func openingSubagentInRightPanelKeepsParentDestinationAndReusesTabs() {
        let model = AppModel.mock()
        let parentID = MockData.subagentsDetail.summary.id
        model.open(parentID)
        #expect(!model.rightPanel.isOpen(for: parentID))

        let firstTarget = SubagentNavigationTarget(
            threadID: "t4-sub-research",
            environmentID: nil,
            title: "Codebase Researcher",
            provider: .claude,
            providerDriver: "claudeAgent",
            providerDisplayName: "Claude",
            providerIconURL: nil,
            isRemoteLinked: false
        )
        let firstTab = model.openSubagentInRightPanel(firstTarget, for: parentID)
        #expect(firstTab != nil)
        // Main chat view stays on the parent thread while the right panel opens.
        #expect(model.destination == .thread(parentID))
        #expect(model.rightPanel.isOpen(for: parentID))
        #expect(model.rightPanel.tabs(for: parentID).count == 1)
        #expect(model.rightPanel.activeTab(for: parentID)?.id == firstTab?.id)
        if case .subagent(let state) = model.rightPanel.activeTab(for: parentID)?.payload {
            #expect(state.subagentThreadId == "t4-sub-research")
            #expect(state.title == "Codebase Researcher")
            #expect(state.status == .completed)
            #expect(state.modelLabel == "Opus 5.5")
            #expect(state.workspaceLabel == "swft/reconnect-audit")
        } else {
            Issue.record("Expected .subagent payload enriched from parent detail")
        }

        // Opening a second subagent adds a second tab alongside the first.
        let secondTarget = SubagentNavigationTarget(
            threadID: "t4-sub-ui",
            environmentID: nil,
            title: "Reconnect Fixer",
            provider: .codex,
            providerDriver: "codex",
            providerDisplayName: "Codex",
            providerIconURL: nil,
            isRemoteLinked: false
        )
        let secondTab = model.openSubagentInRightPanel(secondTarget, for: parentID)
        #expect(model.destination == .thread(parentID))
        #expect(model.rightPanel.tabs(for: parentID).count == 2)
        #expect(model.rightPanel.activeTab(for: parentID)?.id == secondTab?.id)

        // Re-clicking the first subagent activates its existing tab instead of creating a duplicate.
        let reactivated = model.openSubagentInRightPanel(firstTarget, for: parentID)
        #expect(reactivated?.id == firstTab?.id)
        #expect(model.rightPanel.tabs(for: parentID).count == 2)
        #expect(model.rightPanel.activeTab(for: parentID)?.id == firstTab?.id)

        // Closing one tab preserves the other.
        model.rightPanel.closeTab(firstTab!.id, for: parentID)
        #expect(model.rightPanel.tabs(for: parentID).map(\.id) == [secondTab!.id])
        #expect(model.rightPanel.activeTab(for: parentID)?.id == secondTab?.id)

        // Inline row help text reflects opening in the right sidebar.
        let rowItem = SubagentItem(
            id: "sa-help",
            title: "Codebase Researcher",
            provider: .claude,
            status: .completed,
            childThreadID: "t4-sub-research"
        )
        let rowModel = SubagentSingleRowView.makeRowModel(for: rowItem, target: firstTarget)
        #expect(rowModel.helpText.contains("Click to open subagent in right sidebar"))
    }

    @Test @MainActor func openingRemoteSubagentInRightPanelPreservesRemoteEnvironmentRouting() {
        let localConn = ServerConnection(httpBaseURL: URL(string: "http://127.0.0.1:3773")!, credential: .bootstrapToken("local"))
        let remoteConn = ServerConnection(httpBaseURL: URL(string: "https://studio.example.ts.net")!, credential: .bearerToken("remote"))
        let localStore = ThreadsStore(connection: localConn)
        let remoteStore = ThreadsStore(connection: remoteConn)

        let remoteProject = ProjectShell(id: "proj-remote", title: "ML Runner", workspaceRoot: "/code/ml", createdAt: t0, updatedAt: t0)
        let parentShell = ThreadShell(
            id: "thr-remote-parent",
            projectId: "proj-remote",
            title: "Optimize kernels",
            providerInstanceId: "claudeAgent",
            modelSelection: ModelSelection(instanceId: "claudeAgent", model: "opus"),
            createdAt: t0,
            updatedAt: t0
        )
        remoteStore.apply(.snapshot(
            ShellSnapshot(snapshotSequence: 1, projects: [remoteProject], threads: [parentShell]),
            resolvedRepositoryIdentityRoots: nil
        ))

        let model = AppModel.testingLive(localStore: localStore)
        let localEnv = ManagedEnvironment(
            id: "env-local",
            isLocal: true,
            httpBaseURL: URL(string: "http://127.0.0.1:3773")!,
            connection: localConn,
            threadsStore: localStore,
            lastKnownLabel: "This Mac"
        )
        let remoteEnv = ManagedEnvironment(
            id: "env-studio",
            isLocal: false,
            httpBaseURL: URL(string: "https://studio.example.ts.net")!,
            connection: remoteConn,
            threadsStore: remoteStore,
            lastKnownLabel: "Mac Studio"
        )
        model.environmentRegistry.insertEnvironmentForTesting(localEnv)
        model.environmentRegistry.insertEnvironmentForTesting(remoteEnv)

        model.open("thr-remote-parent")
        #expect(model.destination == .thread("thr-remote-parent"))

        let subagent = SubagentItem(
            id: "item-sub-remote",
            title: "Kernel Profiler",
            provider: .codex,
            providerDriver: "codex",
            providerDisplayName: "Codex",
            modelName: "GPT-6.1",
            status: .running,
            childThreadID: "thr-remote-child-99",
            worktreeBranch: "perf/kernels"
        )
        let target = SubagentDisplayLogic.navigationTarget(
            for: subagent,
            parentEnvironmentID: model.activeThreadEnvironmentID,
            knownEnvironmentIDs: model.knownEnvironmentIDs
        )!

        let openedTab = model.openSubagentInRightPanel(target, item: subagent, for: "thr-remote-parent")
        #expect(openedTab != nil)
        #expect(model.destination == .thread("thr-remote-parent"))
        #expect(model.rightPanel.isOpen(for: "thr-remote-parent"))
        if case .subagent(let tabState) = openedTab?.payload {
            #expect(tabState.subagentThreadId == "thr-remote-child-99")
            #expect(tabState.environmentId == "env-studio")
            #expect(tabState.status == .running)
            #expect(tabState.workspaceLabel == "perf/kernels")
            #expect(model.connection(forEnvironmentID: tabState.environmentId, fallbackThreadID: "thr-remote-parent") === remoteConn)
            #expect(model.threadsStore(forEnvironmentID: tabState.environmentId, fallbackThreadID: "thr-remote-parent") === remoteStore)
        } else {
            Issue.record("Expected remote .subagent tab payload")
        }
    }

    // MARK: - SendFlightTurnSection Equatable Stability

    @Test @MainActor func sendFlightTurnSectionEquatablePreservesStabilityWithSubagents() {
        let group = SubagentGroup(
            id: "subagent-group:sa1",
            members: [
                SubagentItem(id: "sa1", title: "A", provider: .claude, status: .completed, startedAt: at(1), completedAt: at(5)),
                SubagentItem(id: "sa2", title: "B", provider: .codex, status: .completed, startedAt: at(1), completedAt: at(7)),
            ]
        )
        let turn = TranscriptTurn(id: "u1", rows: [.user(id: "u1", text: "Run"), .subagentGroup(group)])

        let a = SendFlightTurnSection(
            threadID: "t1",
            turn: turn,
            isLatest: false,
            streamRoomHeight: nil,
            showWorking: false,
            fadeBubbleID: nil,
            expandedFoldIDs: [],
            expandedSubagentIDs: [],
            parentEnvironmentID: "env-local",
            knownEnvironmentIDs: ["env-local"],
            reduceMotion: false,
            onToggleWorkFold: { _ in },
            onToggleSubagentExpansion: { _ in },
            onOpenSubagentThread: { _ in },
            onResolveApproval: { _, _ in }
        )
        let b = SendFlightTurnSection(
            threadID: "t1",
            turn: turn,
            isLatest: false,
            streamRoomHeight: nil,
            showWorking: false,
            fadeBubbleID: nil,
            expandedFoldIDs: [],
            expandedSubagentIDs: [],
            parentEnvironmentID: "env-local",
            knownEnvironmentIDs: ["env-local"],
            reduceMotion: false,
            onToggleWorkFold: { _ in },
            onToggleSubagentExpansion: { _ in },
            onOpenSubagentThread: { _ in },
            onResolveApproval: { _, _ in }
        )
        let expanded = SendFlightTurnSection(
            threadID: "t1",
            turn: turn,
            isLatest: false,
            streamRoomHeight: nil,
            showWorking: false,
            fadeBubbleID: nil,
            expandedFoldIDs: [],
            expandedSubagentIDs: ["subagent-group:sa1"],
            parentEnvironmentID: "env-local",
            knownEnvironmentIDs: ["env-local"],
            reduceMotion: false,
            onToggleWorkFold: { _ in },
            onToggleSubagentExpansion: { _ in },
            onOpenSubagentThread: { _ in },
            onResolveApproval: { _, _ in }
        )

        #expect(a == b)
        #expect(a != expanded)
    }
}
