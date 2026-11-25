import Foundation
import Testing
@testable import Swft
@testable import SwftKit

@Suite("Settled Threads")
struct SettledThreadsTests {
    private static let base = Date(timeIntervalSince1970: 1_800_000_000)

    private static func thread(
        id: String,
        activity: ThreadActivity = .idle,
        updatedMinutesAgo: Double,
        isSettled: Bool = false,
        settledMinutesAgo: Double? = nil
    ) -> ThreadSummary {
        ThreadSummary(
            id: id,
            title: "Thread \(id)",
            project: MockData.swft,
            location: .branch("main"),
            provider: .claude,
            activity: activity,
            updatedAt: base.addingTimeInterval(-updatedMinutesAgo * 60),
            isSettled: isSettled,
            settledAt: settledMinutesAgo.map { base.addingTimeInterval(-$0 * 60) }
        )
    }

    @Test func partitionsAndSortsSettledBySettledAtFallingBackToUpdatedAt() {
        let threads = [
            Self.thread(id: "a1", activity: .running, updatedMinutesAgo: 2),
            Self.thread(id: "a2", activity: .idle, updatedMinutesAgo: 10),
            Self.thread(id: "s-old", updatedMinutesAgo: 5, isSettled: true, settledMinutesAgo: 120),
            Self.thread(id: "s-recent", updatedMinutesAgo: 300, isSettled: true, settledMinutesAgo: 15),
            Self.thread(id: "s-fallback", updatedMinutesAgo: 45, isSettled: true, settledMinutesAgo: nil),
            // Tie on timestamp breaks deterministically by ascending thread ID.
            Self.thread(id: "s-tie-b", updatedMinutesAgo: 45, isSettled: true, settledMinutesAgo: 60),
            Self.thread(id: "s-tie-a", updatedMinutesAgo: 1, isSettled: true, settledMinutesAgo: 60),
        ]

        let collapsed = SettledThreadsLogic.partition(
            threads: threads,
            filter: .all,
            isSettledExpanded: false,
            selectedThreadID: nil
        )
        #expect(collapsed.active.map(\.id) == ["a1", "a2"])
        #expect(collapsed.settled.map(\.id) == ["s-recent", "s-fallback", "s-tie-a", "s-tie-b", "s-old"])
        #expect(collapsed.visibleSettled.isEmpty)

        let expanded = SettledThreadsLogic.partition(
            threads: threads,
            filter: .all,
            isSettledExpanded: true,
            selectedThreadID: nil
        )
        #expect(expanded.visibleSettled.map(\.id) == ["s-recent", "s-fallback", "s-tie-a", "s-tie-b", "s-old"])
    }

    @Test func filterAppliesOnlyToActiveThreadsAndKeepsSelectedSettledVisibleWhenCollapsed() {
        let threads = [
            Self.thread(id: "a-run", activity: .running, updatedMinutesAgo: 1),
            Self.thread(id: "a-approval", activity: .needsApproval, updatedMinutesAgo: 2),
            Self.thread(id: "a-unread", activity: .unread, updatedMinutesAgo: 3),
            Self.thread(id: "a-failed", activity: .failed, updatedMinutesAgo: 4),
            Self.thread(id: "a-idle", activity: .idle, updatedMinutesAgo: 5),
            Self.thread(id: "s-1", activity: .idle, updatedMinutesAgo: 60, isSettled: true, settledMinutesAgo: 20),
            Self.thread(id: "s-2", activity: .idle, updatedMinutesAgo: 90, isSettled: true, settledMinutesAgo: 40),
        ]

        let activeOnly = SettledThreadsLogic.partition(
            threads: threads,
            filter: .active,
            isSettledExpanded: false,
            selectedThreadID: "s-2"
        )
        #expect(activeOnly.active.map(\.id) == ["a-run", "a-approval"])
        #expect(activeOnly.settled.map(\.id) == ["s-1", "s-2"])
        // Selected settled thread stays visible even while Settled shelf is collapsed.
        #expect(activeOnly.visibleSettled.map(\.id) == ["s-2"])

        let attentionOnly = SettledThreadsLogic.partition(
            threads: threads,
            filter: .needsAttention,
            isSettledExpanded: false,
            selectedThreadID: "a-run"
        )
        #expect(attentionOnly.active.map(\.id) == ["a-approval", "a-unread", "a-failed"])
        #expect(attentionOnly.settled.map(\.id) == ["s-1", "s-2"])
        #expect(attentionOnly.visibleSettled.isEmpty)
    }

    @Test func optimisticOverridesApplyUntilServerMatches() {
        let settledTime = Self.base.addingTimeInterval(-30)
        let threads = [
            Self.thread(id: "t1", updatedMinutesAgo: 10, isSettled: false),
            Self.thread(id: "t2", updatedMinutesAgo: 20, isSettled: true, settledMinutesAgo: 5),
        ]
        let overrides: [String: OptimisticSettlement] = [
            "t1": OptimisticSettlement(isSettled: true, settledAt: settledTime),
            // Matches server state already, so canonical server timestamp is preserved.
            "t2": OptimisticSettlement(isSettled: true, settledAt: Self.base),
        ]

        let applied = SettledThreadsLogic.applyOptimisticSettlements(to: threads, overrides: overrides)
        #expect(applied[0].isSettled)
        #expect(applied[0].settledAt == settledTime)
        #expect(applied[1].isSettled)
        #expect(applied[1].settledAt == threads[1].settledAt)
    }

    @Test func picksNextActiveThreadAfterSettlingSelectedThread() {
        let active = [
            Self.thread(id: "t1", updatedMinutesAgo: 1),
            Self.thread(id: "t2", updatedMinutesAgo: 2),
            Self.thread(id: "t3", updatedMinutesAgo: 3),
        ]
        #expect(SettledThreadsLogic.nextActiveThreadID(afterSettling: "t1", activeThreads: active) == "t2")
        #expect(SettledThreadsLogic.nextActiveThreadID(afterSettling: "t2", activeThreads: active) == "t3")
        #expect(SettledThreadsLogic.nextActiveThreadID(afterSettling: "t3", activeThreads: active) == "t1")
        #expect(SettledThreadsLogic.nextActiveThreadID(afterSettling: "t1", activeThreads: [active[0]]) == nil)
    }

    @Test func mapsSettledFieldsThroughAdaptersAndInboxModel() {
        let now = Self.base
        let settledAt = now.addingTimeInterval(-3 * 3600)
        let project = ProjectShell(
            id: "proj-1",
            title: "Swft",
            workspaceRoot: "/tmp/swft",
            createdAt: now,
            updatedAt: now
        )
        let shell = ThreadShell(
            id: "thr-settled",
            projectId: "proj-1",
            title: "Completed migration",
            providerInstanceId: "codex",
            modelSelection: ModelSelection(instanceId: "codex", model: "gpt-6-astra"),
            createdAt: now.addingTimeInterval(-86_400),
            updatedAt: now.addingTimeInterval(-2 * 86_400),
            settledOverride: "settled",
            settledAt: settledAt
        )

        let summary = SwftAdapters.threadSummary(
            from: shell,
            projectsByID: [project.id: project],
            providersByID: [:],
            hostName: "Mac",
            activelyViewingThreadID: nil
        )
        #expect(summary.isSettled)
        #expect(summary.settledAt == settledAt)

        let rowModel = summary.inboxModel(now: now)
        #expect(rowModel.isSettled)
        #expect(rowModel.time == "3h")
    }

    @Test @MainActor func appModelMockSettleUnsettleRoundTripAndPersistence() {
        let suiteName = "swft-settled-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = AppModel.mock(defaults: defaults)

        // MockData starts with 2 settled threads and collapsed shelf.
        #expect(!model.isSettledExpanded)
        #expect(model.settledThreads.count == 2)
        #expect(model.visibleSettledThreads.isEmpty)
        let initialActiveCount = model.visibleThreads.count
        #expect(initialActiveCount >= 2)

        // Toggling Settled persists across launches.
        model.toggleSettledSection()
        #expect(model.isSettledExpanded)
        #expect(model.visibleSettledThreads.count == 2)
        #expect(defaults.bool(forKey: SettledThreadsLogic.expandedDefaultsKey))

        let reloaded = AppModel.mock(defaults: defaults)
        #expect(reloaded.isSettledExpanded)

        // Collapse again and open a settled thread -> stays visible while collapsed.
        model.toggleSettledSection()
        #expect(!model.isSettledExpanded)
        let firstSettledID = model.settledThreads[0].id
        model.open(firstSettledID)
        #expect(model.visibleSettledThreads.map(\.id) == [firstSettledID])

        // Un-settling moves it back into active threads cleanly.
        model.unsettleThread(firstSettledID)
        #expect(model.settledThreads.count == 1)
        #expect(model.visibleThreads.contains(where: { $0.id == firstSettledID }))
        #expect(model.selectedThreadID == firstSettledID)

        // Settling the currently selected active thread moves it to Settled and advances selection cleanly.
        let activeFirst = model.visibleThreads[0].id
        let activeSecond = model.visibleThreads[1].id
        model.open(activeFirst)
        model.settleThread(activeFirst)
        #expect(!model.visibleThreads.contains(where: { $0.id == activeFirst }))
        #expect(model.settledThreads.first?.id == activeFirst)
        #expect(model.selectedThreadID == activeSecond)

        // Settling every remaining active thread returns gracefully to home.
        while let current = model.visibleThreads.first {
            model.open(current.id)
            model.settleThread(current.id)
        }
        #expect(model.visibleThreads.isEmpty)
        #expect(model.destination == .home)
    }
}
