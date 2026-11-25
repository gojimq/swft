import Foundation
import SwftKit
import Testing
@testable import Swft

/// A live send shows its row on the send's own frame and keeps that row (same id) once the server echoes it, so the
/// flight's landing geometry exists from the first frame and nothing swaps out mid-flight.
@Suite("OptimisticSend")
struct OptimisticSendTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let summary = ThreadSummary(id: "thr-1", title: "T", project: nil, location: nil, provider: .claude, activity: .idle, updatedAt: Date(timeIntervalSince1970: 1_800_000_000))

    private func projection(_ items: [TurnItem]) -> ThreadProjection {
        let thread = AppThread(
            id: "thr-1",
            projectId: "proj-1",
            title: "T",
            providerInstanceId: "claudeAgent",
            modelSelection: ModelSelection(instanceId: "claudeAgent", model: "haiku"),
            branch: "main",
            createdAt: t0,
            updatedAt: t0
        )
        let projected = items.enumerated().map { index, item in
            ProjectedTurnItem(position: index, visibility: .local, sourceThreadId: "thr-1", sourceItemId: item.id, item: item)
        }
        return ThreadProjection(thread: thread, runtimeRequests: [], visibleTurnItems: projected, updatedAt: t0)
    }

    private func user(_ itemID: String, messageID: String, _ text: String) -> TurnItem {
        TurnItem(
            id: itemID,
            threadId: "thr-1",
            ordinal: 1,
            status: "completed",
            updatedAt: t0,
            kind: .userMessage(messageId: messageID, text: text, inputIntent: "turn_start", attachments: [], createdBy: "user", creationSource: "web")
        )
    }

    private func reply(_ itemID: String) -> TurnItem {
        TurnItem(
            id: itemID,
            threadId: "thr-1",
            ordinal: 2,
            status: "running",
            updatedAt: t0,
            kind: .assistantMessage(messageId: "m-\(itemID)", text: "On it", streaming: true, phase: nil, delivery: nil, attachments: [])
        )
    }

    @Test func pendingMessageShowsBeforeTheEchoAndKeepsItsRowAfter() {
        let pending = [PendingUserMessage(messageID: "msg-new", text: "Fix the hitch")]
        let history = [user("i1", messageID: "m1", "Hi"), reply("i2")]

        // Before the echo: the row is there at once, as the latest turn.
        let before = SwftAdapters.threadDetail(from: projection(history), summary: summary, pendingUserMessages: pending)
        #expect(before.rows.last?.id == "msg-new")
        #expect(SendFlightLogic.turns(from: before.rows).last?.id == "msg-new")

        // After the echo: exactly one row for the message, under the same id (not the server's item id).
        let echoed = history + [user("i3", messageID: "msg-new", "Fix the hitch"), reply("i4")]
        let after = SwftAdapters.threadDetail(from: projection(echoed), summary: summary, pendingUserMessages: pending)
        let userRows = after.rows.filter { if case .user = $0 { true } else { false } }
        #expect(userRows.map(\.id) == ["i1", "msg-new"])
        #expect(!after.rows.contains { $0.id == "i3" })
        // The reply lands inside the same turn, below the prompt.
        #expect(SendFlightLogic.turns(from: after.rows).last?.rows.count == 2)

        // Other users' (or earlier) messages keep their own item ids.
        #expect(after.rows.first?.id == "i1")
    }

    @Test func aFailedSendLeavesNoRowBehind() {
        let history = [user("i1", messageID: "m1", "Hi")]
        // `AppModel` drops the pending message when the dispatch throws; with nothing pending there is no row.
        let rolledBack = SwftAdapters.threadDetail(from: projection(history), summary: summary, pendingUserMessages: [])
        #expect(rolledBack.rows.map(\.id) == ["i1"])
    }

    @MainActor
    @Test func aFailedSendCancelsItsFlightAndHold() {
        let coordinator = SendFlightCoordinator()
        var detail = MockData.threadDetail
        detail.items.append(TranscriptItem(id: "msg-new", kind: .user("Fix the hitch")))
        let event = ThreadSendEvent(threadID: detail.summary.id, text: "Fix the hitch", optimisticItemID: "msg-new")
        coordinator.syncThread(detail: detail, isBusy: true)
        _ = coordinator.beginSend(event, detail: detail, reduceMotion: false)
        #expect(coordinator.activeFlight?.boundItemID == "msg-new")
        coordinator.failSend(event.id)
        #expect(coordinator.activeFlight == nil)
        #expect(coordinator.latestTurnHeldForSendID == nil)
    }
}
