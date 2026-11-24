import CoreGraphics
import Foundation
import SwftDesign
import SwiftUI
import Testing
@testable import Swft

@Suite("Send flight & scroll logic")
struct SendFlightLogicTests {

    // MARK: - Constants & Cubic-Bezier Curve

    @Test func constantsMatchStudioReference() {
        #expect(SendFlightTiming.stickThreshold == 80)
        #expect(SendFlightTiming.settleDuration == 0.42)
        #expect(SendFlightTiming.sendDuration == 0.68)
        #expect(SendFlightTiming.handoffDuration == 0.22)
        #expect(SendFlightTiming.workingDelay == 0.34)
        #expect(SendFlightTiming.staggerStep == 0.03)
        #expect(SendFlightTiming.maxStaggerIndex == 12)
        #expect(SendFlightTiming.sendTopTuck == 8)
        #expect(SendFlightTiming.sendBottomInset == 6)
    }

    @Test func sendAndSettleCurvesAreMonotonicWithExpectedProfile() {
        for curve in [CubicBezierCurve.send, CubicBezierCurve.settle] {
            #expect(curve.value(at: -0.5) == 0)
            #expect(curve.value(at: 0) == 0)
            #expect(curve.value(at: 1) == 1)
            #expect(curve.value(at: 1.5) == 1)

            var prev = -1.0
            for step in 0...100 {
                let t = Double(step) / 100.0
                let y = curve.value(at: t)
                #expect(y >= prev)
                prev = y
            }
        }

        // Studio's cubic-bezier(0.3, 0.2, 0, 1): gentle ease-in, strong mid sweep, calm settle.
        #expect(CubicBezierCurve.send.value(at: 0.1) < 0.18)
        #expect(CubicBezierCurve.send.value(at: 0.5) > 0.72)
        #expect(CubicBezierCurve.send.value(at: 0.8) > 0.94)
    }

    // MARK: - computeSendLift (mirrors Studio threadView.logic.test.ts)

    @Test func computeSendLiftMatchesStudioCases() {
        // Short text-only bubble fits inside the composer: tucked 8px below composer top.
        #expect(
            SendFlightLogic.computeSendLift(
                SendLiftInput(anchorTop: 652, anchorBottom: 734, bubbleTop: 84, bubbleBottom: 120, slide: 154)
            ) == 422
        )
        // Tall text + image unit clamps so its bottom stays 6px above the composer bottom (728).
        #expect(
            SendFlightLogic.computeSendLift(
                SendLiftInput(anchorTop: 600, anchorBottom: 734, bubbleTop: 84, bubbleBottom: 287, slide: 154)
            ) == 287
        )
        // Image-only unit clamps identically without poking beneath the composer bar.
        #expect(
            SendFlightLogic.computeSendLift(
                SendLiftInput(anchorTop: 600, anchorBottom: 734, bubbleTop: 84, bubbleBottom: 244, slide: 154)
            ) == 330
        )
        // Tall image + text on a scrollable thread uses negative lift so bottom stays 6px inside composer.
        #expect(
            SendFlightLogic.computeSendLift(
                SendLiftInput(anchorTop: 640, anchorBottom: 774, bubbleTop: 84, bubbleBottom: 287, slide: 558)
            ) == -77
        )
        // Scrolled-up text-only send uses negative lift so top starts 8px inside composer top.
        #expect(
            SendFlightLogic.computeSendLift(
                SendLiftInput(anchorTop: 692, anchorBottom: 774, bubbleTop: 84, bubbleBottom: 120, slide: 800)
            ) == -184
        )
        // Oversized multi-image bubble taller than the viewport clamps to -slide (slide + lift === 0).
        #expect(
            SendFlightLogic.computeSendLift(
                SendLiftInput(anchorTop: 600, anchorBottom: 734, bubbleTop: 84, bubbleBottom: 800, slide: 154)
            ) == -154
        )
    }

    @Test func clampedSlideAndStreamRoomAndLandingProjection() {
        #expect(SendFlightLogic.clampedSlide(from: 200, to: 500, viewportHeight: 700) == 300)
        #expect(SendFlightLogic.clampedSlide(from: 0, to: 2000, viewportHeight: 700) == 700)
        #expect(SendFlightLogic.clampedSlide(from: 2000, to: 100, viewportHeight: 700) == -700)

        #expect(SendFlightLogic.streamRoomHeight(viewportHeight: 860, topInset: 76, bottomInset: 138) == 646)
        #expect(SendFlightLogic.streamRoomHeight(viewportHeight: 150, topInset: 76, bottomInset: 138) == 0)

        // Live frame at currentScrollY=0 with endScrollY=540 projects to final landed minY=80.
        let projected = SendFlightLogic.landedBubbleFrame(
            measuredFrame: CGRect(x: 520, y: 620, width: 240, height: 44),
            currentScrollY: 0,
            endScrollY: 540
        )
        #expect(projected == CGRect(x: 520, y: 80, width: 240, height: 44))
    }

    // MARK: - J-Shaped Flight Path Geometry

    @Test func sendFlightPathTravelsRightThenUpAlongJCurve() {
        let composer = CGRect(x: 128, y: 738, width: 744, height: 110)
        let target = CGRect(x: 680, y: 80, width: 200, height: 44)
        let path = SendFlightPath.make(composerFrame: composer, targetFrame: target)

        let s0 = path.sample(normalizedTime: 0)
        let sEarly = path.sample(normalizedTime: 0.2)
        let sMid = path.sample(normalizedTime: 0.5)
        let sEnd = path.sample(normalizedTime: 1.0)

        // Starts near composer left, tucked 8pt below composer top.
        #expect(abs(s0.center.x - (composer.minX + 18 + target.width / 2)) < 0.01)
        #expect(abs(s0.center.y - (composer.minY + SendFlightTiming.sendTopTuck + target.height / 2)) < 0.01)
        #expect(s0.scale == 0.84)
        #expect(s0.opacity == 0)

        // Opacity reaches 1.0 by t=0.2 matching Studio's keyframe offset.
        #expect(abs(sEarly.opacity - 1.0) < 0.001)

        // J-curve property: early-to-mid flight covers a greater share of horizontal travel than vertical travel.
        let totalDX = sEnd.center.x - s0.center.x
        let totalDY = s0.center.y - sEnd.center.y
        let earlyXFraction = (sEarly.center.x - s0.center.x) / totalDX
        let earlyYFraction = (s0.center.y - sEarly.center.y) / totalDY
        #expect(earlyXFraction > earlyYFraction)
        #expect(sMid.center.x > sEarly.center.x)
        #expect(sMid.center.y < sEarly.center.y)

        // Lands pixel-exact on target bubble at scale 1.0, opacity 1.0.
        #expect(abs(sEnd.center.x - target.midX) < 0.01)
        #expect(abs(sEnd.center.y - target.midY) < 0.01)
        #expect(abs(sEnd.scale - 1.0) < 0.001)
        #expect(abs(sEnd.opacity - 1.0) < 0.001)
        #expect(abs(sEnd.pillOpacity - 1.0) < 0.001)
    }

    @Test func sendFlightPathHandlesTallAndWideBubblesWithoutOverflow() {
        let composer = CGRect(x: 128, y: 738, width: 744, height: 110)
        // Tall bubble clamps bottom to composer.maxY - 6 instead of poking below the composer.
        let tallTarget = CGRect(x: 200, y: 80, width: 680, height: 220)
        let tallPath = SendFlightPath.make(composerFrame: composer, targetFrame: tallTarget)
        let tallStartBottom = tallPath.startCenter.y + tallTarget.height / 2
        #expect(abs(tallStartBottom - (composer.maxY - SendFlightTiming.sendBottomInset)) < 0.01)

        // Full-width bubble with zero horizontal travel rises vertically without horizontal drift.
        let alignedTarget = CGRect(x: composer.minX + 18, y: 80, width: 400, height: 44)
        let straightPath = SendFlightPath.make(composerFrame: composer, targetFrame: alignedTarget)
        let mid = straightPath.sample(normalizedTime: 0.5)
        #expect(abs(mid.center.x - alignedTarget.midX) < 0.01)
        #expect(mid.center.y < straightPath.startCenter.y && mid.center.y > alignedTarget.midY)
    }

    // MARK: - Conversation Entrance Stagger (mirrors Studio threadView.logic.test.ts)

    private func entries(_ ids: String...) -> [EntranceEntry] {
        ids.map { EntranceEntry(id: $0) }
    }

    private func resolveAll(_ entrance: ConversationEntrance, _ items: [EntranceEntry]) -> [(id: String, still: Bool, delay: TimeInterval)] {
        let cutoff = SendFlightLogic.prependedCutoffIndex(entrance, items: items)
        return items.enumerated().map { index, item in
            let r = SendFlightLogic.itemEntrance(entrance, itemID: item.id, index: index, cutoffIndex: cutoff, isTurnFold: item.isTurnFold)
            return (item.id, r.still, r.delay)
        }
    }

    @Test func entranceStaggersInitialItemsAndCapsAtTwelveSteps() {
        let items = entries("u1", "read1", "a1", "u2", "a2")
        let entrance = SendFlightLogic.createConversationEntrance(items, sentID: nil)
        let resolved = resolveAll(entrance, items)
        #expect(resolved.map(\.still) == [false, false, false, false, false])
        #expect(resolved.map(\.delay) == [0, 0.03, 0.06, 0.09, 0.12])
        #expect(abs(SendFlightLogic.tailEntranceDelay(entrance) - 0.15) < 1e-9)

        let fifteen = (0..<15).map { EntranceEntry(id: "i\($0)") }
        let capped = SendFlightLogic.createConversationEntrance(fifteen, sentID: nil)
        let cappedResolved = resolveAll(capped, fifteen)
        #expect(abs(cappedResolved[11].delay - 11 * SendFlightTiming.staggerStep) < 1e-9)
        #expect(abs(cappedResolved[12].delay - 12 * SendFlightTiming.staggerStep) < 1e-9)
        #expect(abs(cappedResolved[14].delay - 12 * SendFlightTiming.staggerStep) < 1e-9)
        #expect(abs(SendFlightLogic.tailEntranceDelay(capped) - 12 * SendFlightTiming.staggerStep) < 1e-9)
    }

    @Test func entranceCapturesFirstNonEmptyBatchAfterMountAndSkipsSentAndPrependedAndFolds() {
        let atMount = SendFlightLogic.createConversationEntrance([], sentID: nil)
        #expect(atMount.initial == nil)
        #expect(SendFlightLogic.tailEntranceDelay(atMount) == 0)

        let loaded = entries("u1", "a1")
        let afterLoad = SendFlightLogic.advanceConversationEntrance(atMount, items: loaded, sentID: nil)
        #expect(resolveAll(afterLoad, loaded).map(\.delay) == [0, 0.03])

        // Sent message skips rise; later assistant reply rises with 0 delay; second send also skips rise.
        let afterSend1Items = entries("u1", "a1", "u2")
        let afterSend1 = SendFlightLogic.advanceConversationEntrance(afterLoad, items: afterSend1Items, sentID: "u2")
        #expect(resolveAll(afterSend1, afterSend1Items)[2].still == true)

        let afterReplyItems = entries("u1", "a1", "u2", "a2")
        let afterReply = SendFlightLogic.advanceConversationEntrance(afterSend1, items: afterReplyItems, sentID: "u2")
        #expect(resolveAll(afterReply, afterReplyItems)[3].still == false)
        #expect(resolveAll(afterReply, afterReplyItems)[3].delay == 0)

        // Prepended earlier history stays still without shifting initial delays.
        let withEarlier = entries("u0", "a0", "u1", "a1", "u2", "a2")
        let resolvedEarlier = resolveAll(afterReply, withEarlier)
        #expect(resolvedEarlier[0].still == true)
        #expect(resolvedEarlier[1].still == true)
        #expect(resolvedEarlier[2].still == false && resolvedEarlier[2].delay == 0)
        #expect(resolvedEarlier[3].still == false && resolvedEarlier[3].delay == 0.03)

        // A live turn settling into a turn-fold keeps the new turn-fold still.
        let withFold = [
            EntranceEntry(id: "u1"),
            EntranceEntry(id: "a1"),
            EntranceEntry(id: "u2"),
            EntranceEntry(id: "turn-fold:r2", isTurnFold: true),
            EntranceEntry(id: "cmd2", foldedBy: "r2"),
            EntranceEntry(id: "a2"),
        ]
        let visible = SendFlightLogic.visibleItemsOf(withFold)
        #expect(visible.map(\.id) == ["u1", "a1", "u2", "turn-fold:r2", "a2"])
        let cutoff = SendFlightLogic.prependedCutoffIndex(afterReply, items: withFold)
        let foldEntry = SendFlightLogic.itemEntrance(afterReply, itemID: "turn-fold:r2", index: 3, cutoffIndex: cutoff, isTurnFold: true)
        #expect(foldEntry == ItemEntrance(still: true, delay: 0))
    }

    // MARK: - Stream Room & Latest Turn Fold (mirrors Studio threadView.logic.test.ts)

    @Test func latestTurnFoldAndStreamRoomRetentionMatchStudio() {
        let runningItems: [StreamRoomItem] = [
            .init(id: "u1", isUser: true),
            .init(id: "turn-fold:u1", isTurnFold: true),
            .init(id: "c1", foldedBy: "u1"),
            .init(id: "a1"),
            .init(id: "u2", isUser: true),
            .init(id: "c2"),
        ]
        let settledFoldedItems: [StreamRoomItem] = [
            .init(id: "u1", isUser: true),
            .init(id: "turn-fold:u1", isTurnFold: true),
            .init(id: "c1", foldedBy: "u1"),
            .init(id: "a1"),
            .init(id: "u2", isUser: true),
            .init(id: "turn-fold:u2", isTurnFold: true),
            .init(id: "c2", foldedBy: "u2"),
            .init(id: "a2"),
        ]
        let settledPlainItems: [StreamRoomItem] = [
            .init(id: "u1", isUser: true),
            .init(id: "a1"),
        ]

        #expect(SendFlightLogic.latestTurnFold(runningItems) == nil)
        #expect(SendFlightLogic.latestTurnFold(settledFoldedItems) == LatestTurnFoldResult(anchorID: "a2"))

        #expect(SendFlightLogic.latestTurnKeyOf([]) == nil)
        #expect(SendFlightLogic.latestTurnKeyOf(runningItems) == "u2")
        #expect(SendFlightLogic.latestTurnKeyOf(settledFoldedItems) == "u2")
        #expect(SendFlightLogic.latestTurnKeyOf([.init(id: "a0")]) == "a0")

        // Active states get room.
        #expect(SendFlightLogic.latestTurnHasStreamRoom(state: .working, isBusy: true, items: runningItems))
        #expect(SendFlightLogic.latestTurnHasStreamRoom(state: .working, isBusy: false, items: runningItems))
        #expect(SendFlightLogic.latestTurnHasStreamRoom(state: .needsYou, isBusy: false, items: runningItems))
        // Optimistic send awaiting server before state flips to working.
        #expect(SendFlightLogic.latestTurnHasStreamRoom(state: .done, isBusy: true, items: [.init(id: "u1", isUser: true)]))

        // Reopened settled threads open at the bottom without blank stream room.
        #expect(!SendFlightLogic.latestTurnHasStreamRoom(state: .done, isBusy: false, items: settledFoldedItems))
        #expect(!SendFlightLogic.latestTurnHasStreamRoom(state: .done, isBusy: false, items: settledPlainItems))
        #expect(!SendFlightLogic.latestTurnHasStreamRoom(state: .failed, isBusy: false, items: settledPlainItems))
        #expect(!SendFlightLogic.latestTurnHasStreamRoom(state: .idle, isBusy: false, items: settledPlainItems))
        // A turn-fold on a reopened thread clears room even if summary state lags.
        #expect(!SendFlightLogic.latestTurnHasStreamRoom(state: .working, isBusy: true, items: settledFoldedItems))

        // Retained latest turn keeps room across settle, fold, fail, or idle; stale key does not.
        #expect(SendFlightLogic.latestTurnHasStreamRoom(state: .done, isBusy: false, items: settledPlainItems, retainedTurnKey: "u1"))
        #expect(SendFlightLogic.latestTurnHasStreamRoom(state: .done, isBusy: false, items: settledFoldedItems, retainedTurnKey: "u2"))
        #expect(!SendFlightLogic.latestTurnHasStreamRoom(state: .done, isBusy: false, items: settledFoldedItems, retainedTurnKey: "u1"))
        #expect(!SendFlightLogic.latestTurnHasStreamRoom(state: .working, isBusy: true, items: [], retainedTurnKey: "u1"))
        #expect(!SendFlightLogic.latestTurnHasStreamRoom(state: .working, isBusy: false, items: runningItems, compact: true, retainedTurnKey: "u2"))

        // resolveStreamRoomTurnKey full lifecycle: send -> settle -> next send -> reopen.
        let sentKey = SendFlightLogic.resolveStreamRoomTurnKey(
            state: .done, isBusy: false, items: [.init(id: "u1", isUser: true)], sentID: "u1", retainedTurnKey: nil
        )
        #expect(sentKey == "u1")
        let afterSettle = SendFlightLogic.resolveStreamRoomTurnKey(
            state: .done, isBusy: false, items: settledPlainItems, sentID: nil, retainedTurnKey: sentKey
        )
        #expect(afterSettle == "u1")
        let latchedMidTurn = SendFlightLogic.resolveStreamRoomTurnKey(
            state: .working, isBusy: true, items: runningItems, sentID: nil, retainedTurnKey: nil
        )
        #expect(latchedMidTurn == "u2")
        #expect(SendFlightLogic.resolveStreamRoomTurnKey(
            state: .done, isBusy: false, items: settledFoldedItems, sentID: nil, retainedTurnKey: latchedMidTurn
        ) == "u2")
        #expect(SendFlightLogic.resolveStreamRoomTurnKey(
            state: .done, isBusy: false, items: settledPlainItems + [.init(id: "u2", isUser: true)], sentID: "u2", retainedTurnKey: "u1"
        ) == "u2")
        #expect(SendFlightLogic.resolveStreamRoomTurnKey(
            state: .done, isBusy: false, items: settledFoldedItems, sentID: nil, retainedTurnKey: nil
        ) == nil)
        #expect(SendFlightLogic.resolveStreamRoomTurnKey(
            state: .working, isBusy: true, items: runningItems, sentID: "u2", retainedTurnKey: "u2", compact: true
        ) == nil)
    }

    // MARK: - partitionTurnBlocks & rowHeads (mirrors Studio threadView.logic.test.ts)

    @Test func partitionTurnBlocksGroupsWorkSubagentsAndFoldedSlices() {
        let foldedItems: [TurnBlockItem] = [
            .init(id: "u1", kind: .user),
            .init(id: "turn-fold:r1", kind: .turnFold),
            .init(id: "r1", kind: .read, foldedBy: "r1"),
            .init(id: "c1", kind: .command, foldedBy: "r1"),
            .init(id: "q1", kind: .question),
            .init(id: "e1", kind: .edit, foldedBy: "r1"),
            .init(id: "a1", kind: .assistant),
        ]
        let blocks = SendFlightLogic.partitionTurnBlocks(foldedItems, startVisibleIndex: 10)
        #expect(blocks.count == 6)
        #expect(SendFlightLogic.rowHeads(blocks).map(\.id) == ["u1", "turn-fold:r1", "q1", "a1"])
        guard case .foldedSlice(_, "r1", let firstSliceRows) = blocks[2],
              case .work(_, let mergedWork, _, false) = firstSliceRows[0]
        else {
            Issue.record("expected merged work row in first folded slice")
            return
        }
        #expect(mergedWork.map(\.id) == ["r1", "c1"])

        // Running turn marks only the tail work group active.
        let runningItems: [TurnBlockItem] = [
            .init(id: "u1", kind: .user),
            .init(id: "t1", kind: .thought),
            .init(id: "c1", kind: .command),
            .init(id: "a1", kind: .assistant),
            .init(id: "t2", kind: .thought),
            .init(id: "c2", kind: .command),
        ]
        let liveBlocks = SendFlightLogic.partitionTurnBlocks(runningItems, running: true)
        #expect(liveBlocks.count == 4)
        if case .row(.work(_, _, _, let active1)) = liveBlocks[1],
           case .row(.work(_, _, _, let active2)) = liveBlocks[3]
        {
            #expect(!active1)
            #expect(active2)
        } else {
            Issue.record("expected two work groups")
        }

        // Consecutive subagents group together while lone subagent stays standalone.
        let subagentItems: [TurnBlockItem] = [
            .init(id: "u1", kind: .user),
            .init(id: "sa1", kind: .subagent),
            .init(id: "sa2", kind: .subagent),
            .init(id: "a1", kind: .assistant),
            .init(id: "sa3", kind: .subagent),
        ]
        let subBlocks = SendFlightLogic.partitionTurnBlocks(subagentItems)
        #expect(subBlocks.count == 4)
        if case .row(.subagents(_, let grouped, _)) = subBlocks[1] {
            #expect(grouped.map(\.id) == ["sa1", "sa2"])
        } else {
            Issue.record("expected subagents group")
        }
        #expect(SendFlightLogic.rowHeads(subBlocks).map(\.id) == ["u1", "sa1", "a1", "sa3"])
    }

    // MARK: - SentAnimationTracker & Working Indicator

    @Test func sentTrackerTracksConsecutiveSendsAndResetsOnThreadSwitch() {
        var tracker = SentAnimationTracker()
        #expect(tracker.sentID(for: "t1", lastUserID: "u1") == nil)

        tracker.armSend(threadID: "t1", lastUserID: "u1")
        #expect(tracker.sentID(for: "t1", lastUserID: "u1") == nil)
        #expect(tracker.sentID(for: "t1", lastUserID: "u2") == "u2")

        // Second send after u2 landed clears stale u2 and arms for u3.
        tracker.armSend(threadID: "t1", lastUserID: "u2")
        #expect(tracker.sentID(for: "t1", lastUserID: "u2") == nil)
        #expect(tracker.sentID(for: "t1", lastUserID: "u3") == "u3")

        // Switching threads never replays an earlier send.
        tracker.resetForThreadIfNeeded("t2")
        #expect(tracker.sentID(for: "t2", lastUserID: "u3") == nil)
    }

    @Test func workingIndicatorVisibilityAndDelay() {
        let justSent: [TranscriptRow] = [.user(id: "u2", text: "Check tests")]
        #expect(SendFlightLogic.shouldShowWorkingIndicator(isRunning: true, isBusy: false, latestTurnRows: justSent))
        #expect(SendFlightLogic.shouldShowWorkingIndicator(isRunning: false, isBusy: true, latestTurnRows: justSent))
        #expect(!SendFlightLogic.shouldShowWorkingIndicator(isRunning: false, isBusy: false, latestTurnRows: justSent))

        // Live work fold or streaming reply or pending approval already shows state -> hide Working.
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

        // Delay is WORKING_DELAY_MS (340ms) only for a newly sent message when Reduce Motion is off.
        #expect(SendFlightLogic.workingIndicatorDelay(latestRowID: "u2", sentID: "u2", reduceMotion: false) == SendFlightTiming.workingDelay)
        #expect(SendFlightLogic.workingIndicatorDelay(latestRowID: "u2", sentID: "u2", reduceMotion: true) == 0)
        #expect(SendFlightLogic.workingIndicatorDelay(latestRowID: "u2", sentID: nil, reduceMotion: false) == 0)
    }

    // MARK: - Stick-to-Bottom & Scroll-to-Bottom Logic

    @Test func scrollStickinessFollowsStudioStickRules() {
        var stick = ThreadScrollStickiness()
        #expect(stick.isSticking)

        // Initial resting at bottom of a 2000pt transcript in an 800pt viewport (endOffsetY = 1200).
        stick.handleScroll(ScrollMetrics(offsetY: 1200, contentHeight: 2000, viewportHeight: 800))
        #expect(stick.isSticking)
        #expect(!stick.showsScrollToBottom(isFlightActive: false))

        // Scrolling UP even 10pt (still < 80pt) releases stick immediately so streaming won't yank the user.
        stick.handleScroll(ScrollMetrics(offsetY: 1190, contentHeight: 2000, viewportHeight: 800))
        #expect(!stick.isSticking)
        // Still within 80pt so scroll-to-bottom button does not flicker on tiny nudges.
        #expect(!stick.showsScrollToBottom(isFlightActive: false))

        // Scrolling further up past STICK_PX (80pt) shows the scroll-to-bottom button.
        stick.handleScroll(ScrollMetrics(offsetY: 1050, contentHeight: 2000, viewportHeight: 800))
        #expect(!stick.isSticking)
        #expect(stick.showsScrollToBottom(isFlightActive: false))
        // Hidden while a send flight is actively running.
        #expect(!stick.showsScrollToBottom(isFlightActive: true))

        // Scrolling back down within 80pt re-arms stick and hides the button.
        stick.handleScroll(ScrollMetrics(offsetY: 1140, contentHeight: 2000, viewportHeight: 800))
        #expect(stick.isSticking)
        #expect(!stick.showsScrollToBottom(isFlightActive: false))

        // Content shrinking at the bottom (e.g. a turn folding) does NOT release stick.
        stick.handleScroll(ScrollMetrics(offsetY: 1000, contentHeight: 1800, viewportHeight: 800))
        #expect(stick.isSticking)

        // Expanding a fold releases stick so the opened fold stays put.
        stick.releaseStick()
        #expect(!stick.isSticking)

        // Sending re-arms stick.
        stick.armStick()
        #expect(stick.isSticking)

        // Short non-scrollable thread never shows scroll-to-bottom button.
        stick.releaseStick()
        stick.handleScroll(ScrollMetrics(offsetY: 0, contentHeight: 400, viewportHeight: 800))
        #expect(stick.isSticking)
        #expect(!stick.showsScrollToBottom(isFlightActive: false))
    }

    // MARK: - SendFlightCoordinator End-to-End Lifecycle

    @MainActor
    @Test func coordinatorHandlesFullFlightRapidSendsThreadSwitchInterruptAndReduceMotion() {
        let baseDetail = MockData.threadDetail
        let coordinator = SendFlightCoordinator()
        coordinator.updateViewportSize(CGSize(width: 1000, height: 860))
        coordinator.updateComposerFrame(CGRect(x: 128, y: 738, width: 744, height: 110))
        coordinator.syncThread(detail: baseDetail, isBusy: false)
        _ = coordinator.handleScrollGeometryChange(ScrollMetrics(offsetY: 400, contentHeight: 1260, viewportHeight: 860))

        // 1. Live-mode send: flight starts immediately before server echoes the user item.
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let send1 = ThreadSendEvent(threadID: baseDetail.summary.id, text: "First send", optimisticItemID: nil, timestamp: t0)
        let action1 = coordinator.beginSend(send1, detail: baseDetail, reduceMotion: false, now: t0)
        #expect(action1 == .startFlight)
        #expect(coordinator.activeFlight?.id == send1.id)
        #expect(coordinator.hasStreamRoom(for: baseDetail, isBusy: false))

        // Server echoes u-new-1 mid-flight: bubble is hidden immediately before syncThread binds it (zero 1-frame flash).
        var withSend1 = baseDetail
        withSend1.items.append(TranscriptItem(id: "u-new-1", kind: .user("First send")))
        #expect(coordinator.isBubbleHiddenForFlight(rowID: "u-new-1", in: withSend1))
        coordinator.syncThread(detail: withSend1, isBusy: true)
        #expect(coordinator.activeFlight?.boundItemID == "u-new-1")

        // Mid-flight evaluation moves scroll forward and positions bubble along the J-curve.
        _ = coordinator.handleScrollGeometryChange(ScrollMetrics(offsetY: 400, contentHeight: 1850, viewportHeight: 860))
        let midFrame = coordinator.evaluateFlightFrame(at: t0.addingTimeInterval(0.34), topInset: 76)
        #expect(midFrame != nil)
        #expect(midFrame?.isComplete == false)
        #expect((midFrame?.scrollTargetY ?? 0) > 400)

        // Completion clears flight overlay and reveals the real bubble (never leaves a ghost).
        let endFrame = coordinator.evaluateFlightFrame(at: t0.addingTimeInterval(0.70), topInset: 76)
        #expect(endFrame?.isComplete == true)
        let shouldSnap = coordinator.finishFlightIfMatching(send1.id)
        #expect(shouldSnap)
        #expect(coordinator.activeFlight == nil)
        #expect(!coordinator.isBubbleHiddenForFlight(rowID: "u-new-1", in: withSend1))

        // Even after the turn settles, stream room stays retained while this thread stays open.
        var settledDetail = withSend1
        settledDetail.isRunning = false
        settledDetail.summary.activity = .idle
        settledDetail.items.append(TranscriptItem(id: "a-new-1", kind: .assistant(blocks: [.text("Done.")], streaming: false)))
        coordinator.syncThread(detail: settledDetail, isBusy: false)
        #expect(coordinator.hasStreamRoom(for: settledDetail, isBusy: false))

        // 2. Rapid consecutive sends: second send supersedes first flight cleanly.
        var withSend2 = settledDetail
        withSend2.items.append(TranscriptItem(id: "u-new-2", kind: .user("Second")))
        let send2 = ThreadSendEvent(threadID: settledDetail.summary.id, text: "Second", optimisticItemID: "u-new-2", timestamp: t0)
        _ = coordinator.beginSend(send2, detail: withSend2, reduceMotion: false, now: t0)
        #expect(coordinator.isBubbleHiddenForFlight(rowID: "u-new-2", in: withSend2))

        var withSend3 = withSend2
        withSend3.items.append(TranscriptItem(id: "u-new-3", kind: .user("Third")))
        let send3 = ThreadSendEvent(threadID: settledDetail.summary.id, text: "Third", optimisticItemID: "u-new-3", timestamp: t0.addingTimeInterval(0.1))
        _ = coordinator.beginSend(send3, detail: withSend3, reduceMotion: false, now: t0.addingTimeInterval(0.1))
        #expect(coordinator.activeFlight?.id == send3.id)
        // First interrupted bubble is immediately visible (no hidden bubble left behind).
        #expect(!coordinator.isBubbleHiddenForFlight(rowID: "u-new-2", in: withSend3))
        #expect(coordinator.isBubbleHiddenForFlight(rowID: "u-new-3", in: withSend3))

        // 3. User scroll interruption cancels flight immediately so scroll isn't fought.
        coordinator.handleScrollPhaseChange(from: .idle, to: .interacting)
        #expect(coordinator.activeFlight == nil)
        #expect(!coordinator.isBubbleHiddenForFlight(rowID: "u-new-3", in: withSend3))

        // 4. Thread switch mid-flight cancels flight, resets stickiness, and clears retained stream room.
        let send4 = ThreadSendEvent(threadID: withSend3.summary.id, text: "Fourth", optimisticItemID: nil, timestamp: t0)
        _ = coordinator.beginSend(send4, detail: withSend3, reduceMotion: false, now: t0)
        #expect(coordinator.activeFlight != nil)

        var settledOtherThread = MockData.approvalDetail
        settledOtherThread.isRunning = false
        settledOtherThread.summary.activity = .idle
        settledOtherThread.items = [
            TranscriptItem(id: "o1", kind: .user("Hi")),
            TranscriptItem(id: "o2", kind: .assistant(blocks: [.text("Hello")], streaming: false)),
        ]
        coordinator.syncThread(detail: settledOtherThread, isBusy: false)
        #expect(coordinator.activeFlight == nil)
        #expect(coordinator.stickiness.isSticking)
        #expect(!coordinator.hasStreamRoom(for: settledOtherThread, isBusy: false))

        // 5. Failed send cancels active flight immediately.
        let send5 = ThreadSendEvent(threadID: settledOtherThread.summary.id, text: "Will fail", optimisticItemID: nil, timestamp: t0)
        _ = coordinator.beginSend(send5, detail: settledOtherThread, reduceMotion: false, now: t0)
        #expect(coordinator.activeFlight != nil)
        coordinator.failSend(send5.id)
        #expect(coordinator.activeFlight == nil)

        // 6. Reduce Motion skips flight overlay and returns instant anchor.
        var withReduceSend = settledOtherThread
        withReduceSend.items.append(TranscriptItem(id: "u-rm", kind: .user("Quiet send")))
        let sendRM = ThreadSendEvent(threadID: settledOtherThread.summary.id, text: "Quiet send", optimisticItemID: "u-rm", timestamp: t0)
        let rmAction = coordinator.beginSend(sendRM, detail: withReduceSend, reduceMotion: true, now: t0)
        #expect(rmAction == .instantAnchor)
        #expect(coordinator.activeFlight == nil)
        #expect(coordinator.reduceMotionFadeBubbleID == "u-rm")
        #expect(!coordinator.isBubbleHiddenForFlight(rowID: "u-rm", in: withReduceSend))

        // 7. Working indicator respects WORKING_DELAY_MS on Frame 0 before beginSend runs and under pinned flight progress.
        let freshCoord = SendFlightCoordinator()
        var mockSendDetail = baseDetail
        mockSendDetail.items.append(TranscriptItem(id: "u-frame0", kind: .user("Frame 0")))
        let frame0Event = ThreadSendEvent(threadID: mockSendDetail.summary.id, text: "Frame 0", optimisticItemID: "u-frame0", timestamp: t0)
        // Hidden on Frame 0 before beginSend arms the delay timer (zero flash).
        #expect(!freshCoord.shouldShowWorking(
            for: mockSendDetail,
            isBusy: false,
            latestTurnRows: [.user(id: "u-frame0", text: "Frame 0")],
            latestSend: frame0Event,
            reduceMotion: false
        ))

        _ = freshCoord.beginSend(frame0Event, detail: mockSendDetail, reduceMotion: false, now: t0)
        // Still hidden immediately after beginSend while workingDelayPendingForSendID is active.
        #expect(freshCoord.workingDelayPendingForSendID == frame0Event.id)
        #expect(!freshCoord.shouldShowWorking(
            for: mockSendDetail, isBusy: false, latestTurnRows: [.user(id: "u-frame0", text: "Frame 0")],
            latestSend: frame0Event, reduceMotion: false
        ))
        // Under Reduce Motion, Working shows immediately without waiting.
        #expect(freshCoord.shouldShowWorking(
            for: mockSendDetail, isBusy: false, latestTurnRows: [.user(id: "u-frame0", text: "Frame 0")],
            latestSend: frame0Event, reduceMotion: true
        ))
        // Pinned progress switches cleanly at WORKING_DELAY_MS / SEND_MS (0.5).
        freshCoord.pinActiveFlightProgress(0.2)
        #expect(!freshCoord.shouldShowWorking(
            for: mockSendDetail, isBusy: false, latestTurnRows: [.user(id: "u-frame0", text: "Frame 0")],
            latestSend: frame0Event, reduceMotion: false
        ))
        freshCoord.pinActiveFlightProgress(0.6)
        #expect(freshCoord.shouldShowWorking(
            for: mockSendDetail, isBusy: false, latestTurnRows: [.user(id: "u-frame0", text: "Frame 0")],
            latestSend: frame0Event, reduceMotion: false
        ))
    }
}
