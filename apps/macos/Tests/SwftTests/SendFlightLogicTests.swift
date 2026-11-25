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

    @Test func streamRoomHeight() {
        #expect(SendFlightLogic.streamRoomHeight(viewportHeight: 860, topInset: 76, bottomInset: 138) == 646)
        #expect(SendFlightLogic.streamRoomHeight(viewportHeight: 150, topInset: 76, bottomInset: 138) == 0)
    }

    /// Regression: the stream room and the landing were computed from a 68pt anchor while the transcript is padded
    /// 76pt, so a first turn overflowed the viewport by 8pt and the flight landed 8pt above the real bubble.
    @Test func landingMatchesTheTranscriptPixelForPixel() {
        let viewport = CGSize(width: 1000, height: 860)
        let topInset = ThreadView.topInset
        let bottomInset: CGFloat = 138
        let bubble = CGSize(width: 240, height: 44)
        let room = SendFlightLogic.streamRoomHeight(viewportHeight: viewport.height, topInset: topInset, bottomInset: bottomInset)

        // A brand-new thread's only turn fills the viewport exactly: nothing to scroll, nothing to hitch.
        #expect(topInset + room + bottomInset == viewport.height)

        // The landing sits on the real pill: transcript top padding, then the user row's own padding.
        let landing = SendFlightLogic.landingFrame(viewportSize: viewport, topInset: topInset, bottomInset: bottomInset, bubbleSize: bubble)
        #expect(landing.minY == topInset + SendFlightLogic.userRowVerticalPadding)
        #expect(landing.minY == 80)
        #expect(landing.size == bubble)
        // Right-aligned to the reading column.
        let column = min(viewport.width - 64, SwftLayout.contentMaxWidth)
        #expect(landing.maxX == (viewport.width + column) / 2)

        // A long thread scrolled to its end puts the latest turn's top at the same inset, so the landing is the same.
        let previousTurns: CGFloat = 2400
        let turnTop = topInset + previousTurns + 32
        let contentHeight = turnTop + room + bottomInset
        let endOffset = contentHeight - viewport.height
        #expect(turnTop - endOffset + SendFlightLogic.userRowVerticalPadding == landing.minY)

        // The real bubble's measured x wins over the estimate.
        let measured = SendFlightLogic.landingFrame(viewportSize: viewport, topInset: topInset, bottomInset: bottomInset, bubbleSize: bubble, measuredMinX: 612)
        #expect(measured.minX == 612)
        #expect(measured.minY == landing.minY)

        // A prompt taller than the stream room rests above the composer instead of below the window.
        let tall = CGSize(width: 600, height: 900)
        let tallLanding = SendFlightLogic.landingFrame(viewportSize: viewport, topInset: topInset, bottomInset: bottomInset, bubbleSize: tall)
        #expect(tallLanding.maxY + SendFlightLogic.userRowVerticalPadding == viewport.height - bottomInset)
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
    @Test func coordinatorHandlesFullFlightRapidSendsThreadSwitchInterruptAndReduceMotion() throws {
        let baseDetail = MockData.threadDetail
        let coordinator = SendFlightCoordinator()
        coordinator.updateViewportSize(CGSize(width: 1000, height: 860))
        coordinator.updateComposerFrame(CGRect(x: 128, y: 738, width: 744, height: 110))
        coordinator.syncThread(detail: baseDetail, isBusy: false)
        _ = coordinator.handleScrollGeometryChange(ScrollMetrics(offsetY: 400, contentHeight: 1260, viewportHeight: 860))

        // 1. Optimistic send: the row is in the transcript on the send's frame, and the flight binds to it at once.
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        var withSend1 = baseDetail
        withSend1.items.append(TranscriptItem(id: "u-new-1", kind: .user("First send")))
        let send1 = ThreadSendEvent(threadID: baseDetail.summary.id, text: "First send", optimisticItemID: "u-new-1", timestamp: t0)
        #expect(coordinator.isSendPending(send1, in: withSend1))
        let action1 = coordinator.beginSend(send1, detail: withSend1, reduceMotion: false, now: t0)
        #expect(action1 == .startFlight)
        #expect(!coordinator.isSendPending(send1, in: withSend1))
        #expect(coordinator.activeFlight?.id == send1.id)
        #expect(coordinator.activeFlight?.boundItemID == "u-new-1")
        #expect(coordinator.activeFlight?.composerFrame == CGRect(x: 128, y: 738, width: 744, height: 110))
        #expect(coordinator.hasStreamRoom(for: withSend1, isBusy: true))
        #expect(coordinator.isBubbleHiddenForFlight(rowID: "u-new-1", in: withSend1))
        coordinator.syncThread(detail: withSend1, isBusy: true)

        // Scrolling during the flight only records metrics: no observed state, no follow-pin fighting the animation.
        #expect(!coordinator.handleScrollGeometryChange(ScrollMetrics(offsetY: 600, contentHeight: 1850, viewportHeight: 860)))
        #expect(!coordinator.showsScrollToBottom)

        // The landing uses the measured bubble (only the bound one is recorded) and the real 76pt transcript inset.
        coordinator.updateBubbleFrames(["u-other": CGRect(x: 1, y: 2, width: 3, height: 4)])
        #expect(coordinator.boundBubbleFrame == nil)
        coordinator.updateBubbleFrames(["u-new-1": CGRect(x: 610, y: 700, width: 262, height: 44)])
        let flight1 = try #require(coordinator.activeFlight)
        let landing = coordinator.landingFrame(for: flight1, topInset: ThreadView.topInset, bottomInset: 138)
        #expect(landing == CGRect(x: 610, y: 80, width: 262, height: 44))
        // Scrolling moves the measured y every frame; that must not count as a change.
        coordinator.updateBubbleFrames(["u-new-1": CGRect(x: 610, y: 420, width: 262, height: 44)])
        #expect(coordinator.boundBubbleFrame?.minY == 700)

        // Landing at the bottom needs no settle; the real bubble shows and the overlay is gone.
        _ = coordinator.handleScrollGeometryChange(ScrollMetrics(offsetY: 990, contentHeight: 1850, viewportHeight: 860))
        #expect(!coordinator.finishFlightIfMatching(send1.id))
        #expect(coordinator.activeFlight == nil)
        #expect(coordinator.settleToBottomToken == 0)
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
        // A late landing from the superseded flight is ignored.
        #expect(!coordinator.finishFlightIfMatching(send2.id))
        #expect(coordinator.activeFlight?.id == send3.id)
        #expect(!coordinator.isBubbleHiddenForFlight(rowID: "u-new-2", in: withSend3))
        #expect(coordinator.isBubbleHiddenForFlight(rowID: "u-new-3", in: withSend3))

        // 3. User scroll interruption cancels flight immediately so scroll isn't fought.
        #expect(coordinator.handleScrollPhaseChange(from: .idle, to: .interacting))
        #expect(coordinator.activeFlight == nil)
        #expect(!coordinator.isBubbleHiddenForFlight(rowID: "u-new-3", in: withSend3))
        coordinator.handleScrollPhaseChange(from: .interacting, to: .idle)

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

        // 5. Failed send cancels active flight and its hold immediately.
        let send5 = ThreadSendEvent(threadID: settledOtherThread.summary.id, text: "Will fail", optimisticItemID: nil, timestamp: t0)
        _ = coordinator.beginSend(send5, detail: settledOtherThread, reduceMotion: false, now: t0)
        #expect(coordinator.activeFlight != nil)
        coordinator.failSend(send5.id)
        #expect(coordinator.activeFlight == nil)
        #expect(coordinator.latestTurnHeldForSendID == nil)

        // 6. Reduce Motion skips flight overlay and returns instant anchor.
        var withReduceSend = settledOtherThread
        withReduceSend.items.append(TranscriptItem(id: "u-rm", kind: .user("Quiet send")))
        let sendRM = ThreadSendEvent(threadID: settledOtherThread.summary.id, text: "Quiet send", optimisticItemID: "u-rm", timestamp: t0)
        let rmAction = coordinator.beginSend(sendRM, detail: withReduceSend, reduceMotion: true, now: t0)
        #expect(rmAction == .instantAnchor)
        #expect(coordinator.activeFlight == nil)
        #expect(coordinator.reduceMotionFadeBubbleID == "u-rm")
        #expect(!coordinator.isBubbleHiddenForFlight(rowID: "u-rm", in: withReduceSend))
        #expect(!coordinator.holdsLatestTurn(for: withReduceSend, latestSend: sendRM, reduceMotion: true))
    }

    @MainActor
    @Test func workingAndEarlyRowsWaitForTheFlight() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let coordinator = SendFlightCoordinator()
        var detail = MockData.threadDetail
        detail.items.append(TranscriptItem(id: "u-frame0", kind: .user("Frame 0")))
        let event = ThreadSendEvent(threadID: detail.summary.id, text: "Frame 0", optimisticItemID: "u-frame0", timestamp: t0)
        let latestTurn: [TranscriptRow] = [.user(id: "u-frame0", text: "Frame 0")]

        // Frame 0, before beginSend: held, so nothing pops in under the bubble that is about to fly.
        #expect(coordinator.holdsLatestTurn(for: detail, latestSend: event, reduceMotion: false))
        #expect(!coordinator.shouldShowWorking(for: detail, isBusy: true, latestTurnRows: latestTurn, latestSend: event, reduceMotion: false))
        // Reduce Motion never holds.
        #expect(coordinator.shouldShowWorking(for: detail, isBusy: true, latestTurnRows: latestTurn, latestSend: event, reduceMotion: true))

        _ = coordinator.beginSend(event, detail: detail, reduceMotion: false, now: t0)
        #expect(coordinator.latestTurnHeldForSendID == event.id)
        #expect(coordinator.holdsLatestTurn(for: detail, latestSend: event, reduceMotion: false))

        // Pinned progress releases the hold at WORKING_DELAY_MS / SEND_MS (0.5).
        coordinator.pinActiveFlightProgress(0.2)
        #expect(coordinator.holdsLatestTurn(for: detail, latestSend: event, reduceMotion: false))
        coordinator.pinActiveFlightProgress(0.6)
        #expect(!coordinator.holdsLatestTurn(for: detail, latestSend: event, reduceMotion: false))
        #expect(coordinator.shouldShowWorking(for: detail, isBusy: true, latestTurnRows: latestTurn, latestSend: event, reduceMotion: false))
    }

    @MainActor
    @Test func holdReleasesOnItsOwnAfterTheWorkingDelay() async throws {
        let coordinator = SendFlightCoordinator()
        var detail = MockData.threadDetail
        detail.items.append(TranscriptItem(id: "u1", kind: .user("Hi")))
        let event = ThreadSendEvent(threadID: detail.summary.id, text: "Hi", optimisticItemID: "u1")
        _ = coordinator.beginSend(event, detail: detail, reduceMotion: false)
        #expect(coordinator.latestTurnHeldForSendID == event.id)
        try await Task.sleep(for: .seconds(SendFlightTiming.workingDelay))
        // Bounded: a busy main actor (parallel window tests) can resume the release a little late.
        for _ in 0..<100 where coordinator.latestTurnHeldForSendID != nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(coordinator.latestTurnHeldForSendID == nil)
        #expect(!coordinator.holdsLatestTurn(for: detail, latestSend: event, reduceMotion: false))
    }

    // MARK: - Home → New Thread Handoff

    @MainActor
    @Test func handoffFadesTheFirstMessageWithoutFlightOnlyOnTheHandoffScreen() async throws {
        var detail = MockData.threadDetail
        detail.items = [TranscriptItem(id: "first", kind: .user("Plan the launch"))]
        detail.isRunning = true
        let handoff = ThreadSendEvent(threadID: detail.summary.id, text: "Plan the launch", isHandoff: true)

        // The screen that took over from Home fades the first row in directly — NO J-curve flight overlay.
        let coordinator = SendFlightCoordinator()
        coordinator.syncThread(detail: detail, isBusy: true)
        #expect(coordinator.pendingFlightRowID(latestSend: handoff, in: detail, reduceMotion: false) == nil)
        #expect(coordinator.pendingHandoffFadeRowID(latestSend: handoff, in: detail, isHandoffScreen: true, reduceMotion: false) == "first")
        #expect(coordinator.holdsLatestTurn(for: detail, latestSend: handoff, isHandoffScreen: true, reduceMotion: false))
        let action = coordinator.adoptOnAppear(handoff, detail: detail, isHandoffScreen: true, reduceMotion: false)
        #expect(action == .handoffFade)
        #expect(coordinator.activeFlight == nil)
        #expect(coordinator.handoffFadeBubbleID == "first")
        #expect(!coordinator.isBubbleHiddenForFlight(rowID: "first", in: detail))
        #expect(coordinator.hasStreamRoom(for: detail, isBusy: true))
        // Working (and any early live rows) wait briefly while the first message fades in.
        #expect(!coordinator.shouldShowWorking(for: detail, isBusy: true, latestTurnRows: detail.rows, latestSend: handoff, isHandoffScreen: true, reduceMotion: false))
        #expect(coordinator.holdsLatestTurn(for: detail, latestSend: handoff, isHandoffScreen: true, reduceMotion: false))

        // Hold releases cleanly after the handoff beat so Working appears gracefully.
        try await Task.sleep(for: .seconds(SendFlightTiming.handoffDuration))
        for _ in 0..<100 where coordinator.latestTurnHeldForSendID != nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(coordinator.latestTurnHeldForSendID == nil)
        #expect(coordinator.shouldShowWorking(for: detail, isBusy: true, latestTurnRows: detail.rows, latestSend: handoff, isHandoffScreen: true, reduceMotion: false))

        // Every subsequent send inside this thread STILL runs the full J-curve flight.
        var followUpDetail = detail
        followUpDetail.items.append(TranscriptItem(id: "second", kind: .user("Now add tests")))
        let followUp = ThreadSendEvent(threadID: detail.summary.id, text: "Now add tests", optimisticItemID: "second", isHandoff: false)
        #expect(coordinator.pendingFlightRowID(latestSend: followUp, in: followUpDetail, reduceMotion: false) == "second")
        let followUpAction = coordinator.beginSend(followUp, detail: followUpDetail, reduceMotion: false)
        #expect(followUpAction == .startFlight)
        #expect(coordinator.activeFlight?.boundItemID == "second")
        #expect(coordinator.handoffFadeBubbleID == nil)
        #expect(coordinator.isBubbleHiddenForFlight(rowID: "second", in: followUpDetail))
        coordinator.cancelFlight(clearPendingStreamRoom: true)

        // Coming back to the thread later (not a handoff screen) never replays, never fades, and never leaves Working hidden.
        let revisit = SendFlightCoordinator()
        #expect(revisit.pendingHandoffFadeRowID(latestSend: handoff, in: detail, isHandoffScreen: false, reduceMotion: false) == nil)
        #expect(!revisit.holdsLatestTurn(for: detail, latestSend: handoff, isHandoffScreen: false, reduceMotion: false))
        #expect(revisit.adoptOnAppear(handoff, detail: detail, isHandoffScreen: false, reduceMotion: false) == .none)
        #expect(revisit.activeFlight == nil)
        #expect(revisit.handoffFadeBubbleID == nil)
        #expect(revisit.shouldShowWorking(for: detail, isBusy: true, latestTurnRows: detail.rows, latestSend: handoff, isHandoffScreen: false, reduceMotion: false))

        // Reduce Motion: the screen crossfades in whole, nothing flies, nothing fades separately, and nothing is held.
        let quiet = SendFlightCoordinator()
        #expect(quiet.pendingHandoffFadeRowID(latestSend: handoff, in: detail, isHandoffScreen: true, reduceMotion: true) == nil)
        #expect(quiet.adoptOnAppear(handoff, detail: detail, isHandoffScreen: true, reduceMotion: true) == .none)
        #expect(quiet.activeFlight == nil)
        #expect(quiet.handoffFadeBubbleID == nil)
        #expect(!quiet.holdsLatestTurn(for: detail, latestSend: handoff, isHandoffScreen: true, reduceMotion: true))

        // Async projection arrival: handoff armed before first user row arrives still resolves on the row's first frame.
        var emptyDetail = detail
        emptyDetail.items = []
        let asyncHandoff = SendFlightCoordinator()
        asyncHandoff.syncThread(detail: emptyDetail, isBusy: true)
        #expect(asyncHandoff.adoptOnAppear(handoff, detail: emptyDetail, isHandoffScreen: true, reduceMotion: false) == .handoffFade)
        #expect(asyncHandoff.handoffFadeBubbleID == "")
        #expect(asyncHandoff.activeFlight == nil)
        #expect(asyncHandoff.activeHandoffFadeBubbleID(in: detail, latestSend: handoff, isHandoffScreen: true, reduceMotion: false) == "first")
        asyncHandoff.syncThread(detail: detail, isBusy: true)
        #expect(asyncHandoff.handoffFadeBubbleID == "first")
    }

    @MainActor
    @Test func pendingSendSuppressesAutoFollowSnapAndPreservesPreFlightJump() {
        let coordinator = SendFlightCoordinator()
        coordinator.syncThread(detail: MockData.threadDetail, isBusy: false)
        // User scrolled to the top of a 2000pt transcript (old endOffsetY = 1200).
        _ = coordinator.handleScrollGeometryChange(ScrollMetrics(offsetY: 0, contentHeight: 2000, viewportHeight: 800))

        // Frame 0: stream room expands content height before beginSend runs; must NOT snap or overwrite pre-send end.
        let shouldSnap = coordinator.handleScrollGeometryChange(
            ScrollMetrics(offsetY: 0, contentHeight: 2650, viewportHeight: 800),
            isSendPending: true
        )
        #expect(!shouldSnap)
        #expect(coordinator.preFlightJumpOffset() == 1200)
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

    // MARK: - Scroll Lifecycle

    @MainActor
    @Test func scrollFollowsStreamingOnlyWhileStuckAndNeverFightsTheUser() {
        let coordinator = SendFlightCoordinator()
        coordinator.syncThread(detail: MockData.threadDetail, isBusy: false)

        // Opening a thread: the first snapshot grows the content and pins to the end.
        #expect(coordinator.handleScrollGeometryChange(ScrollMetrics(offsetY: 0, contentHeight: 2000, viewportHeight: 800)))
        _ = coordinator.handleScrollGeometryChange(ScrollMetrics(offsetY: 1200, contentHeight: 2000, viewportHeight: 800))

        // Streaming growth while at the end keeps following.
        #expect(coordinator.handleScrollGeometryChange(ScrollMetrics(offsetY: 1200, contentHeight: 2040, viewportHeight: 800)))
        _ = coordinator.handleScrollGeometryChange(ScrollMetrics(offsetY: 1240, contentHeight: 2040, viewportHeight: 800))

        // The user scrolls up (trackpad, then momentum): stick releases and growth no longer moves them.
        coordinator.handleScrollPhaseChange(from: .idle, to: .interacting)
        _ = coordinator.handleScrollGeometryChange(ScrollMetrics(offsetY: 1100, contentHeight: 2040, viewportHeight: 800))
        coordinator.handleScrollPhaseChange(from: .interacting, to: .decelerating)
        _ = coordinator.handleScrollGeometryChange(ScrollMetrics(offsetY: 900, contentHeight: 2040, viewportHeight: 800))
        coordinator.handleScrollPhaseChange(from: .decelerating, to: .idle)
        #expect(!coordinator.stickiness.isSticking)
        #expect(coordinator.showsScrollToBottom)
        #expect(!coordinator.handleScrollGeometryChange(ScrollMetrics(offsetY: 900, contentHeight: 2100, viewportHeight: 800)))
        #expect(coordinator.showsScrollToBottom)

        // A send from far up jumps to the old end first so the animated part stays within about one viewport.
        _ = coordinator.handleScrollGeometryChange(ScrollMetrics(offsetY: 100, contentHeight: 2100, viewportHeight: 800))
        #expect(coordinator.preFlightJumpOffset() == 1300)
        _ = coordinator.handleScrollGeometryChange(ScrollMetrics(offsetY: 900, contentHeight: 2100, viewportHeight: 800))
        #expect(coordinator.preFlightJumpOffset() == nil)

        // The scroll-to-bottom button re-arms stick and hides once the end is reached.
        coordinator.armScrollToBottom()
        _ = coordinator.handleScrollGeometryChange(ScrollMetrics(offsetY: 1300, contentHeight: 2100, viewportHeight: 800))
        #expect(coordinator.stickiness.isSticking)
        #expect(!coordinator.showsScrollToBottom)

        // Content that grew under a flight gets one gentle settle when it lands.
        var detail = MockData.threadDetail
        detail.items.append(TranscriptItem(id: "u9", kind: .user("Go")))
        let event = ThreadSendEvent(threadID: detail.summary.id, text: "Go", optimisticItemID: "u9")
        _ = coordinator.beginSend(event, detail: detail, reduceMotion: false)
        _ = coordinator.handleScrollGeometryChange(ScrollMetrics(offsetY: 1300, contentHeight: 2400, viewportHeight: 800))
        #expect(coordinator.finishFlightIfMatching(event.id))
        #expect(coordinator.settleToBottomToken == 1)
    }
}
