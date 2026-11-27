import CoreGraphics
import Foundation
import SwftDesign
import SwiftUI
import Testing
@testable import Swft

@Suite("Send & scroll logic")
struct SendFlightLogicTests {

    // MARK: - Timing

    @Test func sentMessageFadesInBeforeWorkingRises() {
        #expect(SendFlightTiming.stickThreshold == 80)
        #expect(SendFlightTiming.sendDuration == 0.68)
        #expect(SendFlightTiming.sentMessageFadeDelay < SendFlightTiming.sendDuration)
        #expect(SendFlightTiming.workingDelay == SendFlightTiming.sentMessageFadeDelay + SendFlightTiming.handoffFadeDuration)
    }

    // MARK: - Stream Room

    @Test func streamRoomHeight() {
        #expect(SendFlightLogic.streamRoomHeight(viewportHeight: 860, topInset: 76, bottomInset: 140) == 644)
        #expect(SendFlightLogic.streamRoomHeight(viewportHeight: 100, topInset: 76, bottomInset: 140) == 0)
    }

    @Test func streamRoomIsRetainedForTheTurnThatHadIt() {
        let runningItems: [StreamRoomItem] = [
            .init(id: "u1", isUser: true),
            .init(id: "work:u1", isTurnFold: true),
            .init(id: "a1"),
            .init(id: "u2", isUser: true),
            .init(id: "c2"),
        ]
        let settledFoldedItems: [StreamRoomItem] = [
            .init(id: "u1", isUser: true),
            .init(id: "work:u1", isTurnFold: true),
            .init(id: "a1"),
            .init(id: "u2", isUser: true),
            .init(id: "work:u2", isTurnFold: true),
            .init(id: "a2"),
        ]
        let settledPlainItems: [StreamRoomItem] = [.init(id: "u1", isUser: true), .init(id: "a1")]

        #expect(!SendFlightLogic.latestTurnHasSettledFold(runningItems))
        #expect(SendFlightLogic.latestTurnHasSettledFold(settledFoldedItems))
        #expect(SendFlightLogic.latestTurnKeyOf([]) == nil)
        #expect(SendFlightLogic.latestTurnKeyOf(runningItems) == "u2")
        #expect(SendFlightLogic.latestTurnKeyOf([.init(id: "a0")]) == "a0")

        // Active states get room, including an optimistic send before the state flips to working.
        #expect(SendFlightLogic.latestTurnHasStreamRoom(state: .working, isBusy: false, items: runningItems))
        #expect(SendFlightLogic.latestTurnHasStreamRoom(state: .needsYou, isBusy: false, items: runningItems))
        #expect(SendFlightLogic.latestTurnHasStreamRoom(state: .done, isBusy: true, items: [.init(id: "u1", isUser: true)]))

        // Reopened settled threads open at the bottom without blank stream room.
        #expect(!SendFlightLogic.latestTurnHasStreamRoom(state: .done, isBusy: false, items: settledFoldedItems))
        #expect(!SendFlightLogic.latestTurnHasStreamRoom(state: .done, isBusy: false, items: settledPlainItems))
        #expect(!SendFlightLogic.latestTurnHasStreamRoom(state: .working, isBusy: true, items: settledFoldedItems))

        // The retained latest turn keeps its room after it settles, so the transcript never shrinks under the reader.
        #expect(SendFlightLogic.latestTurnHasStreamRoom(state: .done, isBusy: false, items: settledPlainItems, retainedTurnKey: "u1"))
        #expect(SendFlightLogic.latestTurnHasStreamRoom(state: .done, isBusy: false, items: settledFoldedItems, retainedTurnKey: "u2"))
        #expect(!SendFlightLogic.latestTurnHasStreamRoom(state: .done, isBusy: false, items: settledFoldedItems, retainedTurnKey: "u1"))

        let latched = SendFlightLogic.resolveStreamRoomTurnKey(state: .working, isBusy: true, items: runningItems, retainedTurnKey: nil)
        #expect(latched == "u2")
        #expect(SendFlightLogic.resolveStreamRoomTurnKey(state: .done, isBusy: false, items: settledFoldedItems, retainedTurnKey: latched) == "u2")
        #expect(SendFlightLogic.resolveStreamRoomTurnKey(state: .done, isBusy: false, items: settledFoldedItems, retainedTurnKey: nil) == nil)
    }

    @Test func workingIndicatorShowsOnlyBeforeTheTurnHasVisibleState() {
        let justSent: [TranscriptRow] = [.user(id: "u2", text: "Check tests")]
        #expect(SendFlightLogic.shouldShowWorkingIndicator(isRunning: true, isBusy: false, latestTurnRows: justSent))
        #expect(SendFlightLogic.shouldShowWorkingIndicator(isRunning: false, isBusy: true, latestTurnRows: justSent))
        #expect(!SendFlightLogic.shouldShowWorkingIndicator(isRunning: false, isBusy: false, latestTurnRows: justSent))

        let withLiveFold: [TranscriptRow] = [
            .user(id: "u2", text: "Check"),
            .work(WorkFold(id: "work:u2", steps: [], isLive: true, title: "Running…", subtitle: nil, failedCount: 0)),
        ]
        #expect(!SendFlightLogic.shouldShowWorkingIndicator(isRunning: true, isBusy: true, latestTurnRows: withLiveFold))

        let withStreamingAnswer: [TranscriptRow] = [
            .user(id: "u2", text: "Check"),
            .assistant(id: "a2", blocks: [.text("Sure")], streaming: true),
        ]
        #expect(!SendFlightLogic.shouldShowWorkingIndicator(isRunning: true, isBusy: true, latestTurnRows: withStreamingAnswer))

        let withPendingApproval: [TranscriptRow] = [
            .user(id: "u2", text: "Check"),
            .approval(id: "ap1", ApprovalItem(title: "Run?", message: "Allow", command: "ls", status: .pending)),
        ]
        #expect(!SendFlightLogic.shouldShowWorkingIndicator(isRunning: true, isBusy: true, latestTurnRows: withPendingApproval))
    }

    // MARK: - Stick-to-Bottom

    @Test func contentGrowingInPlaceNeverReArmsAReleasedStick() {
        var stick = ThreadScrollStickiness()
        stick.handleScroll(ScrollMetrics(offsetY: 0, contentHeight: 700, viewportHeight: 800))
        stick.releaseStick()
        // A work log opening in a thread that fit the window: still unscrollable, then just past the edge.
        stick.handleScroll(ScrollMetrics(offsetY: 0, contentHeight: 790, viewportHeight: 800))
        #expect(!stick.isSticking)
        stick.handleScroll(ScrollMetrics(offsetY: 0, contentHeight: 840, viewportHeight: 800))
        #expect(!stick.isSticking)
        // Scrolling down to the end is what re-arms it.
        stick.handleScroll(ScrollMetrics(offsetY: 40, contentHeight: 840, viewportHeight: 800))
        #expect(stick.isSticking)
    }

    @Test func scrollStickinessFollowsStudioStickRules() {
        var stick = ThreadScrollStickiness()
        #expect(stick.isSticking)

        stick.handleScroll(ScrollMetrics(offsetY: 1200, contentHeight: 2000, viewportHeight: 800))
        #expect(stick.isSticking)
        #expect(!stick.showsScrollToBottom(isScrolling: false))

        // Scrolling up even 10pt releases stick so streaming won't yank the user, without flashing the button.
        stick.handleScroll(ScrollMetrics(offsetY: 1190, contentHeight: 2000, viewportHeight: 800))
        #expect(!stick.isSticking)
        #expect(!stick.showsScrollToBottom(isScrolling: false))

        stick.handleScroll(ScrollMetrics(offsetY: 1050, contentHeight: 2000, viewportHeight: 800))
        #expect(stick.showsScrollToBottom(isScrolling: false))
        #expect(!stick.showsScrollToBottom(isScrolling: true))

        // Scrolling back down within 80pt re-arms stick and hides the button.
        stick.handleScroll(ScrollMetrics(offsetY: 1140, contentHeight: 2000, viewportHeight: 800))
        #expect(stick.isSticking)

        // Content shrinking at the bottom does not release stick.
        stick.handleScroll(ScrollMetrics(offsetY: 1000, contentHeight: 1800, viewportHeight: 800))
        #expect(stick.isSticking)

        stick.releaseStick()
        #expect(!stick.isSticking)
        stick.armStick()
        #expect(stick.isSticking)

        // A short, non-scrollable thread never shows the button.
        stick.releaseStick()
        stick.handleScroll(ScrollMetrics(offsetY: 0, contentHeight: 400, viewportHeight: 800))
        #expect(stick.isSticking)
        #expect(!stick.showsScrollToBottom(isScrolling: false))
    }

    // MARK: - Coordinator

    @MainActor
    @Test func inThreadSendScrollsToTheNewTurnAndFadesItsMessageIn() {
        let coordinator = SendFlightCoordinator()
        var detail = MockData.threadDetail
        coordinator.syncThread(detail: detail, rows: detail.rows, isBusy: false)

        detail.items.append(TranscriptItem(id: "u-new", kind: .user("Ship it")))
        let event = ThreadSendEvent(threadID: detail.summary.id, text: "Ship it", optimisticItemID: "u-new")

        // The row's first frame: it already fades and already has stream room, before `beginSend` runs.
        #expect(coordinator.isSendPending(event, in: detail))
        #expect(coordinator.fadingBubbleID(latestSend: event, in: detail) == "u-new")
        #expect(coordinator.hasStreamRoom(for: detail, rows: detail.rows, isBusy: true, latestSend: event))

        #expect(coordinator.beginSend(event, detail: detail, rows: detail.rows) == .scrollToNewTurn(preJumpY: nil))
        coordinator.syncThread(detail: detail, rows: detail.rows, isBusy: true)
        #expect(!coordinator.isSendPending(event, in: detail))
        #expect(coordinator.fadingBubbleID(latestSend: event, in: detail) == "u-new")
        #expect(coordinator.retainedStreamRoomTurnKey == "u-new")
        #expect(coordinator.stickiness.isSticking)

        // Never replays.
        #expect(coordinator.beginSend(event, detail: detail, rows: detail.rows) == .none)

        // The turn finishes: its room stays, so nothing below the answer collapses.
        detail.isRunning = false
        coordinator.syncThread(detail: detail, rows: detail.rows, isBusy: false)
        #expect(coordinator.hasStreamRoom(for: detail, rows: detail.rows, isBusy: false))

        // Switching threads forgets the fade and the room.
        let other = MockData.approvalDetail
        coordinator.syncThread(detail: other, rows: other.rows, isBusy: false)
        #expect(coordinator.fadeBubbleID == nil)
        #expect(coordinator.retainedStreamRoomTurnKey != "u-new")
        #expect(!coordinator.inlineTurnIDs.contains("u-new"))
    }

    @MainActor
    @Test func handoffAdoptsTheFirstMessageInPlaceWithoutFadingItAgain() {
        let coordinator = SendFlightCoordinator()
        var detail = MockData.threadDetail
        detail.items = [TranscriptItem(id: "u-first", kind: .user("Hello"))]
        detail.isRunning = true
        coordinator.syncThread(detail: detail, rows: detail.rows, isBusy: true)

        let handoff = ThreadSendEvent(threadID: detail.summary.id, text: "Hello", isHandoff: true)
        #expect(coordinator.fadingBubbleID(latestSend: handoff, in: detail) == nil)
        #expect(coordinator.adoptOnAppear(handoff, detail: detail, rows: detail.rows, isHandoffScreen: true) == .handoff)
        #expect(coordinator.fadeBubbleID == nil)
        #expect(coordinator.retainedStreamRoomTurnKey == "u-first")

        // Coming back to a thread later never replays an old send.
        let fresh = SendFlightCoordinator()
        let old = ThreadSendEvent(threadID: detail.summary.id, text: "Hello", optimisticItemID: "u-first")
        #expect(fresh.adoptOnAppear(old, detail: detail, rows: detail.rows, isHandoffScreen: false) == .none)
        #expect(fresh.fadingBubbleID(latestSend: old, in: detail) == nil)
    }

    @MainActor
    @Test func handoffBeforeItsRowArrivesStillReservesRoom() {
        let coordinator = SendFlightCoordinator()
        var detail = MockData.threadDetail
        detail.items = []
        coordinator.syncThread(detail: detail, rows: detail.rows, isBusy: true)
        let handoff = ThreadSendEvent(threadID: detail.summary.id, text: "Hello", isHandoff: true)
        #expect(coordinator.beginSend(handoff, detail: detail, rows: detail.rows) == .handoff)
        #expect(coordinator.pendingSendStreamRoom)

        detail.items = [TranscriptItem(id: "u-first", kind: .user("Hello"))]
        coordinator.syncThread(detail: detail, rows: detail.rows, isBusy: true)
        #expect(!coordinator.pendingSendStreamRoom)
        #expect(coordinator.retainedStreamRoomTurnKey == "u-first")
    }

    @MainActor
    @Test func aTurnSeenLiveKeepsItsStreamedLayoutAfterItSettles() {
        let coordinator = SendFlightCoordinator()
        var detail = MockData.threadDetail
        detail.items = [
            TranscriptItem(id: "u1", kind: .user("Go")),
            TranscriptItem(id: "t1", kind: .toolCall(.init(kind: .read, title: "Read", detail: "a.swift", status: .succeeded))),
            TranscriptItem(id: "c1", kind: .assistant(blocks: [.text("Looking at the scroll driver next.")], streaming: false)),
            TranscriptItem(id: "t2", kind: .toolCall(.init(kind: .read, title: "Read", detail: "b.swift", status: .succeeded))),
            TranscriptItem(id: "a1", kind: .assistant(blocks: [.text("Done.")], streaming: true)),
        ]
        detail.isRunning = true
        coordinator.syncThread(detail: detail, rows: detail.rows, isBusy: true)
        #expect(coordinator.inlineTurnIDs == ["u1"])
        let live = TranscriptLayout.rows(for: detail.items, isRunning: true, inlineTurnIDs: coordinator.inlineTurnIDs)

        detail.items[4].kind = .assistant(blocks: [.text("Done.")], streaming: false)
        detail.isRunning = false
        let settled = TranscriptLayout.rows(for: detail.items, isRunning: false, inlineTurnIDs: coordinator.inlineTurnIDs)
        // Same rows in the same places; only the answer stops streaming.
        #expect(settled.map(\.id) == live.map(\.id))
        #expect(settled.contains { $0.id == "c1" })

        // Reopened, the same turn folds its interim message away.
        let reopened = TranscriptLayout.rows(for: detail.items, isRunning: false)
        #expect(!reopened.contains { $0.id == "c1" })
    }

    @MainActor
    @Test func pendingSendKeepsThePreSendEndForTheJump() {
        let coordinator = SendFlightCoordinator()
        coordinator.syncThread(detail: MockData.threadDetail, rows: MockData.threadDetail.rows, isBusy: false)
        _ = coordinator.handleScrollGeometryChange(ScrollMetrics(offsetY: 0, contentHeight: 2000, viewportHeight: 800))

        // The send's first frame grows the content (stream room) before `beginSend` runs; it must not snap or
        // overwrite the old end the jump targets.
        let shouldSnap = coordinator.handleScrollGeometryChange(
            ScrollMetrics(offsetY: 0, contentHeight: 2650, viewportHeight: 800),
            isSendPending: true
        )
        #expect(!shouldSnap)
        #expect(coordinator.preSendJumpOffset() == 1200)
    }

    @Test func markdownProseCachePreservesExactParsedOutput() {
        let sample = "## Heading\nA paragraph with **bold** and `inlineCode`.\n- First item\n- Second item"
        let firstBlocks = MarkdownProse.blocks(sample)
        let secondBlocks = MarkdownProse.blocks(sample)
        #expect(firstBlocks == secondBlocks)
        #expect(firstBlocks.count == 4)

        let firstInline = MarkdownProse.inline("Use **bold** and `code`", style: .body)
        let secondInline = MarkdownProse.inline("Use **bold** and `code`", style: .body)
        #expect(firstInline == secondInline)
    }

    @MainActor
    @Test func scrollFollowsStreamingOnlyWhileStuckAndNeverFightsTheUser() {
        let coordinator = SendFlightCoordinator()
        coordinator.syncThread(detail: MockData.threadDetail, rows: MockData.threadDetail.rows, isBusy: false)

        // Opening a thread: the first snapshot grows the content and pins to the end.
        #expect(coordinator.handleScrollGeometryChange(ScrollMetrics(offsetY: 0, contentHeight: 2000, viewportHeight: 800)))
        _ = coordinator.handleScrollGeometryChange(ScrollMetrics(offsetY: 1200, contentHeight: 2000, viewportHeight: 800))

        // Streaming growth while at the end keeps following.
        #expect(coordinator.handleScrollGeometryChange(ScrollMetrics(offsetY: 1200, contentHeight: 2040, viewportHeight: 800)))
        _ = coordinator.handleScrollGeometryChange(ScrollMetrics(offsetY: 1240, contentHeight: 2040, viewportHeight: 800))

        // The user scrolls up (trackpad, then momentum): stick releases and growth no longer moves them.
        coordinator.handleScrollPhaseChange(to: .interacting)
        _ = coordinator.handleScrollGeometryChange(ScrollMetrics(offsetY: 1100, contentHeight: 2040, viewportHeight: 800))
        coordinator.handleScrollPhaseChange(to: .decelerating)
        _ = coordinator.handleScrollGeometryChange(ScrollMetrics(offsetY: 900, contentHeight: 2040, viewportHeight: 800))
        coordinator.handleScrollPhaseChange(to: .idle)
        #expect(!coordinator.stickiness.isSticking)
        #expect(coordinator.showsScrollToBottom)
        #expect(!coordinator.handleScrollGeometryChange(ScrollMetrics(offsetY: 900, contentHeight: 2100, viewportHeight: 800)))

        // A send from far up jumps to the old end first so the animated part stays within about one viewport.
        _ = coordinator.handleScrollGeometryChange(ScrollMetrics(offsetY: 100, contentHeight: 2100, viewportHeight: 800))
        #expect(coordinator.preSendJumpOffset() == 1300)
        _ = coordinator.handleScrollGeometryChange(ScrollMetrics(offsetY: 900, contentHeight: 2100, viewportHeight: 800))
        #expect(coordinator.preSendJumpOffset() == nil)

        // The scroll-to-bottom button re-arms stick and hides once the end is reached.
        coordinator.armScrollToBottom()
        _ = coordinator.handleScrollGeometryChange(ScrollMetrics(offsetY: 1300, contentHeight: 2100, viewportHeight: 800))
        #expect(coordinator.stickiness.isSticking)
        #expect(!coordinator.showsScrollToBottom)

        // Content that outgrew the send scroll gets one gentle settle when it lands.
        var detail = MockData.threadDetail
        detail.items.append(TranscriptItem(id: "u9", kind: .user("Go")))
        let event = ThreadSendEvent(threadID: detail.summary.id, text: "Go", optimisticItemID: "u9")
        _ = coordinator.beginSend(event, detail: detail, rows: detail.rows)
        _ = coordinator.handleScrollGeometryChange(ScrollMetrics(offsetY: 1300, contentHeight: 2400, viewportHeight: 800))
        #expect(coordinator.finishSendScroll())
    }
}
