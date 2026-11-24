import CoreGraphics
import Foundation
import Observation
import SwftDesign
import SwiftUI

/// Immutable payload emitted by `AppModel.send()` when a message is dispatched inside an existing thread.
struct ThreadSendEvent: Equatable, Sendable {
    let id: UUID
    let threadID: String
    let text: String
    let optimisticItemID: String?
    let timestamp: Date

    init(
        id: UUID = UUID(),
        threadID: String,
        text: String,
        optimisticItemID: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.threadID = threadID
        self.text = text
        self.optimisticItemID = optimisticItemID
        self.timestamp = timestamp
    }
}

/// Optional integration seed for another feature (e.g. Home -> new-thread transition) to hand off
/// an already-dispatched send or raised composer frame into `ThreadView`.
struct SendFlightExternalSeed: Equatable, Sendable {
    let threadID: String
    let sentItemID: String?
    let composerFrame: CGRect?

    init(threadID: String, sentItemID: String? = nil, composerFrame: CGRect? = nil) {
        self.threadID = threadID
        self.sentItemID = sentItemID
        self.composerFrame = composerFrame
    }
}

/// Snapshot of an in-progress send flight.
struct ActiveSendFlight: Equatable, Sendable {
    let id: UUID
    let threadID: String
    let text: String
    let startedAt: Date
    let composerFrame: CGRect
    let fromScrollY: CGFloat
    var boundItemID: String?
    var scrollInterrupted: Bool = false
    /// Non-nil only when deterministic snapshot/unit tests pin the flight to a specific normalized time in `[0, 1]`.
    var pinnedProgress: Double? = nil
}

/// Resolved visual frame for the flight overlay and synchronized scroll target.
struct SendFlightFrame: Equatable, Sendable {
    let text: String
    let maxWidth: CGFloat
    let sample: SendFlightSample
    let scrollTargetY: CGFloat?
    let isComplete: Bool
}

/// Action returned by `SendFlightCoordinator.beginSend` telling `ThreadView` how to drive `ScrollPosition`.
enum SendFlightStartAction: Equatable, Sendable {
    case none
    case startFlight
    case instantAnchor
}

extension ThreadDetailState {
    var streamRoomState: StreamRoomThreadState {
        if isRunning { return .working }
        switch summary.activity {
        case .running: return .working
        case .needsApproval: return .needsYou
        case .failed: return .failed
        case .idle, .unread: return .done
        }
    }
}

/// Coordinates send flight, latest-turn stream room retention, entrance stagger, and scroll stickiness
/// for a single `ThreadView`.
@MainActor
@Observable
final class SendFlightCoordinator {
    private(set) var currentThreadID: String?
    private(set) var activeFlight: ActiveSendFlight?
    private(set) var reduceMotionFadeBubbleID: String?
    private(set) var tracker = SentAnimationTracker()
    private(set) var retainedStreamRoomTurnKey: String?
    private(set) var pendingSendStreamRoom = false
    private(set) var entrance = ConversationEntrance(initial: nil, sent: [])
    private(set) var stickiness = ThreadScrollStickiness()
    private(set) var composerFrame: CGRect = .zero
    private(set) var viewportSize: CGSize = .zero
    private(set) var measuredBubbleFrames: [String: CGRect] = [:]
    private(set) var isUserInteractingWithScroll = false
    private(set) var programmaticScrollPending = false
    private(set) var lastHandledSendID: UUID?
    private(set) var snapToBottomToken: Int = 0
    private(set) var workingDelayPendingForSendID: UUID?

    @ObservationIgnored private var completionTask: Task<Void, Never>?
    @ObservationIgnored private var workingRevealTask: Task<Void, Never>?

    init(seed: SendFlightExternalSeed? = nil) {
        if let seed {
            self.currentThreadID = seed.threadID
            if let composerFrame = seed.composerFrame {
                self.composerFrame = composerFrame
            }
            if let sentItemID = seed.sentItemID {
                self.retainedStreamRoomTurnKey = sentItemID
            }
        }
    }

    var isFlightAnimating: Bool {
        guard let activeFlight else { return false }
        return activeFlight.pinnedProgress == nil
    }

    var showsScrollToBottom: Bool {
        stickiness.showsScrollToBottom(isFlightActive: activeFlight != nil)
    }

    func sentID(for detail: ThreadDetailState, latestSend: ThreadSendEvent? = nil) -> String? {
        let lastUserID = lastUserRowID(in: detail.rows)
        if let tracked = tracker.sentID(for: detail.summary.id, lastUserID: lastUserID) {
            return tracked
        }
        if let latestSend,
           latestSend.threadID == detail.summary.id,
           let optimisticID = latestSend.optimisticItemID,
           optimisticID == lastUserID
        {
            return optimisticID
        }
        return nil
    }

    func shouldShowWorking(
        for detail: ThreadDetailState,
        isBusy: Bool,
        latestTurnRows: [TranscriptRow],
        latestSend: ThreadSendEvent?,
        reduceMotion: Bool
    ) -> Bool {
        guard SendFlightLogic.shouldShowWorkingIndicator(
            isRunning: detail.isRunning,
            isBusy: isBusy,
            latestTurnRows: latestTurnRows
        ) else {
            return false
        }
        if let flight = activeFlight, flight.threadID == detail.summary.id, let pinned = flight.pinnedProgress {
            let threshold = SendFlightTiming.workingDelay / SendFlightTiming.sendDuration
            return pinned >= threshold
        }
        if reduceMotion {
            return true
        }
        // Suppress on Frame 0 before `.onChange(of: latestThreadSend)` invokes `beginSend`.
        if let latestSend, latestSend.threadID == detail.summary.id, lastHandledSendID != latestSend.id {
            return false
        }
        return workingDelayPendingForSendID == nil
    }

    func hasStreamRoom(for detail: ThreadDetailState, isBusy: Bool) -> Bool {
        if pendingSendStreamRoom && activeFlight?.threadID == detail.summary.id {
            return true
        }
        let items = SendFlightLogic.streamRoomItems(from: detail.rows)
        return SendFlightLogic.latestTurnHasStreamRoom(
            state: detail.streamRoomState,
            isBusy: isBusy,
            items: items,
            retainedTurnKey: retainedStreamRoomTurnKey
        )
    }

    /// Synchronizes thread-scoped state whenever the open thread, rows, or busy state changes.
    func syncThread(detail: ThreadDetailState, isBusy: Bool) {
        let threadID = detail.summary.id
        if currentThreadID != threadID {
            cancelFlight(clearPendingStreamRoom: true)
            reduceMotionFadeBubbleID = nil
            tracker.resetForThreadIfNeeded(threadID)
            retainedStreamRoomTurnKey = nil
            entrance = ConversationEntrance(initial: nil, sent: [])
            stickiness.resetForThread()
            measuredBubbleFrames = [:]
            isUserInteractingWithScroll = false
            programmaticScrollPending = false
            currentThreadID = threadID
        }

        let rows = detail.rows
        let lastUserID = lastUserRowID(in: rows)
        let currentSentID = tracker.sentID(for: threadID, lastUserID: lastUserID)

        if var flight = activeFlight, flight.threadID == threadID {
            if flight.boundItemID == nil, let currentSentID {
                flight.boundItemID = currentSentID
                activeFlight = flight
                pendingSendStreamRoom = false
            } else if let bound = flight.boundItemID, rows.contains(where: { $0.id == bound }) {
                pendingSendStreamRoom = false
            }
        }

        if let fadeID = reduceMotionFadeBubbleID, fadeID.isEmpty, let currentSentID {
            reduceMotionFadeBubbleID = currentSentID
        }

        let streamItems = SendFlightLogic.streamRoomItems(from: rows)
        retainedStreamRoomTurnKey = SendFlightLogic.resolveStreamRoomTurnKey(
            state: detail.streamRoomState,
            isBusy: isBusy,
            items: streamItems,
            sentID: currentSentID ?? activeFlight?.boundItemID,
            retainedTurnKey: retainedStreamRoomTurnKey
        )

        let entries = SendFlightLogic.entranceEntries(from: rows)
        entrance = SendFlightLogic.advanceConversationEntrance(
            entrance,
            items: entries,
            sentID: currentSentID ?? activeFlight?.boundItemID
        )
    }

    /// Begins a send flight (or instant Reduce Motion anchor) for a message sent inside the current thread.
    @discardableResult
    func beginSend(
        _ event: ThreadSendEvent,
        detail: ThreadDetailState,
        reduceMotion: Bool,
        now: Date = Date()
    ) -> SendFlightStartAction {
        guard event.threadID == detail.summary.id else { return .none }
        guard lastHandledSendID != event.id else { return .none }
        lastHandledSendID = event.id

        // Rapid consecutive send: finish/supersede any earlier flight cleanly so its real bubble appears immediately.
        cancelFlight(clearPendingStreamRoom: false)

        let lastUserIDBeforeSend = lastUserRowID(in: detail.rows, excluding: event.optimisticItemID)
        tracker.armSend(threadID: event.threadID, lastUserID: lastUserIDBeforeSend)
        stickiness.armStick()
        pendingSendStreamRoom = true
        if let optimisticID = event.optimisticItemID {
            retainedStreamRoomTurnKey = optimisticID
        }

        if reduceMotion {
            workingRevealTask?.cancel()
            workingRevealTask = nil
            workingDelayPendingForSendID = nil
            reduceMotionFadeBubbleID = event.optimisticItemID ?? ""
            pendingSendStreamRoom = false
            programmaticScrollPending = true
            return .instantAnchor
        }

        reduceMotionFadeBubbleID = nil
        let startComposerFrame = resolvedComposerFrame()
        let flight = ActiveSendFlight(
            id: event.id,
            threadID: event.threadID,
            text: event.text,
            startedAt: now,
            composerFrame: startComposerFrame,
            fromScrollY: stickiness.lastMetrics.offsetY,
            boundItemID: event.optimisticItemID
        )
        activeFlight = flight
        programmaticScrollPending = true
        scheduleWorkingReveal(for: event.id)
        scheduleCompletionSafetyNet(for: flight.id)
        return .startFlight
    }

    /// Cancels an active flight if its live network dispatch threw an error.
    func failSend(_ eventID: UUID) {
        guard activeFlight?.id == eventID else { return }
        cancelFlight(clearPendingStreamRoom: true)
    }

    /// Unconditionally clears any active flight so a ghost overlay can never persist.
    func cancelFlight(clearPendingStreamRoom: Bool = false) {
        completionTask?.cancel()
        completionTask = nil
        activeFlight = nil
        programmaticScrollPending = false
        if clearPendingStreamRoom {
            pendingSendStreamRoom = false
            workingRevealTask?.cancel()
            workingRevealTask = nil
            workingDelayPendingForSendID = nil
        }
    }

    /// Marks the active flight complete if its ID still matches. Returns `true` if a final bottom snap is needed.
    @discardableResult
    func finishFlightIfMatching(_ id: UUID, emitSnapToken: Bool = false) -> Bool {
        guard let flight = activeFlight, flight.id == id else { return false }
        let shouldSnapToBottom = !flight.scrollInterrupted && stickiness.isSticking
        cancelFlight(clearPendingStreamRoom: true)
        if shouldSnapToBottom {
            programmaticScrollPending = true
            if emitSnapToken {
                snapToBottomToken += 1
            }
        }
        return shouldSnapToBottom
    }

    /// True while the real `UserBubble` for `rowID` is represented by the active flight overlay.
    func isBubbleHiddenForFlight(rowID: String, in detail: ThreadDetailState) -> Bool {
        guard let flight = activeFlight, flight.threadID == detail.summary.id else { return false }
        if let boundID = flight.boundItemID {
            return boundID == rowID
        }
        return sentID(for: detail) == rowID
    }

    /// Pins the active flight to an exact normalized progress `[0, 1]` for deterministic snapshot verification.
    func pinActiveFlightProgress(_ progress: Double) {
        guard var flight = activeFlight else { return }
        completionTask?.cancel()
        completionTask = nil
        flight.pinnedProgress = min(1.0, max(0.0, progress))
        activeFlight = flight
    }

    func updateComposerFrame(_ frame: CGRect) {
        guard frame.width > 0, frame.height > 0 else { return }
        composerFrame = frame
    }

    func updateViewportSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        viewportSize = size
    }

    func updateBubbleFrames(_ frames: [String: CGRect]) {
        measuredBubbleFrames = frames
    }

    func handleWorkFoldToggle() {
        stickiness.releaseStick()
    }

    func armScrollToBottom() {
        stickiness.armStick()
        programmaticScrollPending = true
    }

    func handleScrollPhaseChange(from oldPhase: ScrollPhase, to newPhase: ScrollPhase) {
        switch newPhase {
        case .interacting:
            isUserInteractingWithScroll = true
            programmaticScrollPending = false
            if var flight = activeFlight {
                flight.scrollInterrupted = true
                activeFlight = flight
                cancelFlight(clearPendingStreamRoom: false)
            }
        case .idle:
            isUserInteractingWithScroll = false
            programmaticScrollPending = false
        case .decelerating, .tracking, .animating:
            break
        }
    }

    /// Updates scroll stickiness from SwiftUI's `onScrollGeometryChange`.
    /// Returns `true` when the view should pin to the bottom to follow live streaming / hydration growth.
    @discardableResult
    func handleScrollGeometryChange(_ metrics: ScrollMetrics) -> Bool {
        let previousContentHeight = stickiness.lastMetrics.contentHeight
        let contentGrew = metrics.contentHeight > previousContentHeight + 0.5

        if activeFlight != nil {
            stickiness.recordProgrammaticMetrics(metrics)
            return false
        }

        if contentGrew && stickiness.isSticking && !isUserInteractingWithScroll {
            stickiness.recordProgrammaticMetrics(metrics)
            programmaticScrollPending = true
            return true
        }

        if programmaticScrollPending && !isUserInteractingWithScroll {
            stickiness.recordProgrammaticMetrics(metrics)
            if metrics.distanceFromBottom < 2 {
                programmaticScrollPending = false
            }
            return false
        }

        stickiness.handleScroll(metrics)
        return false
    }

    /// Evaluates the flying overlay bubble transform and synchronized scroll offset for the current frame.
    func evaluateFlightFrame(at now: Date, topInset: CGFloat) -> SendFlightFrame? {
        guard let flight = activeFlight else { return nil }
        let rawProgress: Double = if let pinned = flight.pinnedProgress {
            pinned
        } else {
            now.timeIntervalSince(flight.startedAt) / SendFlightTiming.sendDuration
        }
        let clampedProgress = min(1.0, max(0.0, rawProgress))
        let maxBubbleWidth = SendFlightLogic.maxUserBubbleWidth(
            viewportWidth: viewportSize.width > 0 ? viewportSize.width : max(flight.composerFrame.width + 64, 600)
        )
        let targetFrame = resolvedTargetFrame(
            for: flight,
            topInset: topInset,
            maxBubbleWidth: maxBubbleWidth
        )
        let path = SendFlightPath.make(
            composerFrame: flight.composerFrame,
            targetFrame: targetFrame
        )
        let sample = path.sample(normalizedTime: clampedProgress, curve: .send)

        let scrollTargetY: CGFloat?
        if flight.scrollInterrupted {
            scrollTargetY = nil
        } else {
            let metrics = stickiness.lastMetrics
            let endY = metrics.endOffsetY
            let viewportHeight = metrics.viewportHeight > 0 ? metrics.viewportHeight : viewportSize.height
            let slide = SendFlightLogic.clampedSlide(
                from: flight.fromScrollY,
                to: endY,
                viewportHeight: max(1, viewportHeight)
            )
            let effectiveStart = endY - slide
            scrollTargetY = max(0, effectiveStart + slide * CGFloat(sample.easedProgress))
        }

        return SendFlightFrame(
            text: flight.text,
            maxWidth: maxBubbleWidth,
            sample: sample,
            scrollTargetY: scrollTargetY,
            isComplete: flight.pinnedProgress == nil && rawProgress >= 1.0
        )
    }

    // MARK: - Private Helpers

    private func scheduleWorkingReveal(for sendID: UUID) {
        workingRevealTask?.cancel()
        workingDelayPendingForSendID = sendID
        workingRevealTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(SendFlightTiming.workingDelay))
            guard !Task.isCancelled else { return }
            if self?.workingDelayPendingForSendID == sendID {
                self?.workingDelayPendingForSendID = nil
            }
        }
    }

    private func scheduleCompletionSafetyNet(for flightID: UUID) {
        completionTask?.cancel()
        completionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(SendFlightTiming.sendDuration + 0.08))
            guard !Task.isCancelled else { return }
            _ = self?.finishFlightIfMatching(flightID, emitSnapToken: true)
        }
    }

    private func resolvedComposerFrame() -> CGRect {
        if composerFrame.width > 0 && composerFrame.height > 0 {
            return composerFrame
        }
        let width = min(max(0, viewportSize.width - 64), SwftLayout.composerMaxWidth)
        let x = max(32, (viewportSize.width - width) / 2)
        let height: CGFloat = 110
        let y = max(0, viewportSize.height - height - 12)
        return CGRect(x: x, y: y, width: max(200, width), height: height)
    }

    private func resolvedTargetFrame(
        for flight: ActiveSendFlight,
        topInset: CGFloat,
        maxBubbleWidth: CGFloat
    ) -> CGRect {
        if let boundID = flight.boundItemID,
           let measured = measuredBubbleFrames[boundID],
           measured.width > 0,
           measured.height > 0
        {
            let landed = SendFlightLogic.landedBubbleFrame(
                measuredFrame: measured,
                currentScrollY: stickiness.lastMetrics.offsetY,
                endScrollY: stickiness.lastMetrics.endOffsetY
            )
            if landed.minY >= 0 && landed.minY.isFinite {
                return landed
            }
        }
        let estimated = UserBubbleMetrics.estimatedSize(for: flight.text, maxWidth: maxBubbleWidth)
        let effectiveViewportWidth = viewportSize.width > 0
            ? viewportSize.width
            : max(flight.composerFrame.maxX + 32, SwftLayout.contentMaxWidth + 64)
        return SendFlightLogic.predictedLandingFrame(
            viewportWidth: effectiveViewportWidth,
            topInset: topInset,
            bubbleSize: estimated
        )
    }

    private func lastUserRowID(in rows: [TranscriptRow], excluding excludedID: String? = nil) -> String? {
        for row in rows.reversed() {
            if case .user(let id, _) = row, id != excludedID {
                return id
            }
        }
        return nil
    }
}
