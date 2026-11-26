import CoreGraphics
import Foundation
import Observation
import SwftDesign
import SwiftUI

/// Immutable payload emitted by `AppModel.send()` when a message is dispatched inside a thread, or when Home hands a
/// freshly launched thread over to its screen (`isHandoff`, where Home already faded the first message in while docking
/// the composer so `ThreadView` takes over in place with no flight and no double-fade).
struct ThreadSendEvent: Equatable, Sendable {
    let id: UUID
    let threadID: String
    let text: String
    /// Sent attachments; they fly with the text as one turn unit.
    let attachments: [TranscriptAttachment]
    /// The transcript row already showing this message (optimistic in-thread sends); nil for a handoff, whose first
    /// message row is bound when its screen appears.
    let optimisticItemID: String?
    let isHandoff: Bool
    let timestamp: Date

    init(
        id: UUID = UUID(),
        threadID: String,
        text: String,
        attachments: [TranscriptAttachment] = [],
        optimisticItemID: String? = nil,
        isHandoff: Bool = false,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.threadID = threadID
        self.text = text
        self.attachments = attachments
        self.optimisticItemID = optimisticItemID
        self.isHandoff = isHandoff
        self.timestamp = timestamp
    }
}

/// Snapshot of an in-progress send flight. The flight's clock lives in SwiftUI's animation system (see
/// `SendFlightOverlayLayer`), so nothing here changes per frame.
struct ActiveSendFlight: Equatable, Sendable {
    let id: UUID
    let threadID: String
    let text: String
    var attachments: [TranscriptAttachment] = []
    /// Where the bubble launches from; nil when the composer had not reported its frame yet, in which case the overlay
    /// follows the composer's live frame.
    let composerFrame: CGRect?
    var boundItemID: String?
    /// Pre-flight jump target when sending from far up a long transcript (within one viewport of the end).
    var preFlightJumpY: CGFloat? = nil
    var scrollInterrupted: Bool = false
    /// Non-nil only when deterministic snapshot/unit tests pin the flight to a specific normalized time in `[0, 1]`.
    var pinnedProgress: Double? = nil
}

/// Action returned by `SendFlightCoordinator.beginSend` / `adoptOnAppear` telling `ThreadView` how to stage the send.
enum SendFlightStartAction: Equatable, Sendable {
    case none
    case startFlight
    case handoff
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

/// Coordinates send flight, Home → new thread handoff adoption, latest-turn stream room retention, the latest turn's
/// reveal hold, display-synced scroll driving, and scroll stickiness for a single `ThreadView`. Observed properties
/// change only on discrete events (a send, a landing, a stick flip), never per scroll or animation frame, so
/// scrolling and flights do not re-render the transcript.
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
    /// Read only by the flight overlay.
    private(set) var composerFrame: CGRect = .zero
    private(set) var viewportSize: CGSize = .zero
    /// The bound bubble's measured frame (its x and size are what the flight lands on). Read only by the overlay.
    private(set) var boundBubbleFrame: CGRect?
    private(set) var showsScrollToBottom = false
    private(set) var lastHandledSendID: UUID?
    /// Bumped when a landed flight needs a gentle settle to the bottom (content grew while it flew).
    private(set) var settleToBottomToken = 0
    /// The send whose new turn is still holding its Working indicator and early rows back while the message appears.
    private(set) var latestTurnHeldForSendID: UUID?

    @ObservationIgnored let scrollDriver = SendFlightScrollDriver()
    @ObservationIgnored private(set) var stickiness = ThreadScrollStickiness()
    @ObservationIgnored private(set) var isUserInteractingWithScroll = false
    @ObservationIgnored private(set) var programmaticScrollPending = false
    @ObservationIgnored private(set) var latestMeasuredComposerHeight: CGFloat?
    @ObservationIgnored private var completionTask: Task<Void, Never>?
    @ObservationIgnored private var holdReleaseTask: Task<Void, Never>?

    init() {}

    var isFlightAnimating: Bool {
        guard let activeFlight else { return false }
        return activeFlight.pinnedProgress == nil
    }

    func recordMeasuredComposerHeight(_ height: CGFloat) {
        latestMeasuredComposerHeight = height
    }

    func sentID(for detail: ThreadDetailState, rows: [TranscriptRow]? = nil, latestSend: ThreadSendEvent? = nil) -> String? {
        let lastUserID = lastUserRowID(in: rows ?? detail.rows)
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

    /// True on the frame a send's row lands in the transcript, before `beginSend` / `adoptOnAppear` has handled it.
    func isSendPending(_ latestSend: ThreadSendEvent?, in detail: ThreadDetailState) -> Bool {
        guard let latestSend, latestSend.threadID == detail.summary.id else { return false }
        return latestSend.id != lastHandledSendID
    }

    /// The row a pending in-thread send is about to fly onto, hidden on that first frame so it never flashes in place
    /// before the flight overlay takes over. Handoffs arrive already visible in place without a flight overlay.
    func pendingFlightRowID(latestSend: ThreadSendEvent?, in detail: ThreadDetailState, rows: [TranscriptRow]? = nil, reduceMotion: Bool) -> String? {
        guard !reduceMotion, let latestSend, !latestSend.isHandoff, isSendPending(latestSend, in: detail) else { return nil }
        return latestSend.optimisticItemID
    }

    /// Resolves which user bubble (if any) is currently hidden behind an active or pending send-flight overlay.
    func activeHiddenFlightBubbleID(
        in detail: ThreadDetailState,
        rows: [TranscriptRow]? = nil,
        pendingRowID: String? = nil
    ) -> String? {
        if let pendingRowID { return pendingRowID }
        guard let flight = activeFlight, flight.threadID == detail.summary.id else { return nil }
        return flight.boundItemID ?? sentID(for: detail, rows: rows)
    }

    /// Whether the latest turn's Working indicator and non-user rows wait (hidden) while the sent message flies up
    /// (in-thread send) or on the initial mount frame of a Home → new thread handoff before `adoptOnAppear` releases it.
    func holdsLatestTurn(
        for detail: ThreadDetailState,
        latestSend: ThreadSendEvent?,
        isHandoffScreen: Bool = true,
        reduceMotion: Bool
    ) -> Bool {
        if reduceMotion { return false }
        if let flight = activeFlight, flight.threadID == detail.summary.id, let pinned = flight.pinnedProgress {
            return pinned < SendFlightTiming.workingDelay / SendFlightTiming.sendDuration
        }
        if isSendPending(latestSend, in: detail) {
            if latestSend?.isHandoff == true && !isHandoffScreen { return false }
            return true
        }
        return latestTurnHeldForSendID != nil
    }

    func shouldShowWorking(
        for detail: ThreadDetailState,
        isBusy: Bool,
        latestTurnRows: [TranscriptRow],
        latestSend: ThreadSendEvent?,
        isHandoffScreen: Bool = true,
        reduceMotion: Bool
    ) -> Bool {
        guard SendFlightLogic.shouldShowWorkingIndicator(
            isRunning: detail.isRunning,
            isBusy: isBusy,
            latestTurnRows: latestTurnRows
        ) else {
            return false
        }
        return !holdsLatestTurn(for: detail, latestSend: latestSend, isHandoffScreen: isHandoffScreen, reduceMotion: reduceMotion)
    }

    /// Pass `latestSend` so the new turn has its room on the send's very first frame (an idle thread would otherwise
    /// gain it a frame later, shifting the transcript under the starting flight).
    func hasStreamRoom(
        for detail: ThreadDetailState,
        rows: [TranscriptRow]? = nil,
        isBusy: Bool,
        latestSend: ThreadSendEvent? = nil
    ) -> Bool {
        if isSendPending(latestSend, in: detail) { return true }
        if pendingSendStreamRoom && (activeFlight?.threadID == detail.summary.id || currentThreadID == detail.summary.id) {
            return true
        }
        let items = SendFlightLogic.streamRoomItems(from: rows ?? detail.rows)
        return SendFlightLogic.latestTurnHasStreamRoom(
            state: detail.streamRoomState,
            isBusy: isBusy,
            items: items,
            retainedTurnKey: retainedStreamRoomTurnKey
        )
    }

    /// Synchronizes thread-scoped state whenever the open thread, rows, or busy state changes.
    func syncThread(detail: ThreadDetailState, rows providedRows: [TranscriptRow]? = nil, isBusy: Bool) {
        let threadID = detail.summary.id
        if currentThreadID != threadID {
            cancelFlight(clearPendingStreamRoom: true)
            reduceMotionFadeBubbleID = nil
            tracker.resetForThreadIfNeeded(threadID)
            retainedStreamRoomTurnKey = nil
            entrance = ConversationEntrance(initial: nil, sent: [])
            stickiness.resetForThread()
            refreshScrollToBottom()
            isUserInteractingWithScroll = false
            programmaticScrollPending = false
            currentThreadID = threadID
        }

        let rows = providedRows ?? detail.rows
        let lastUserID = lastUserRowID(in: rows)
        let currentSentID = tracker.sentID(for: threadID, lastUserID: lastUserID)

        if var flight = activeFlight, flight.threadID == threadID {
            if flight.boundItemID == nil, let currentSentID {
                flight.boundItemID = currentSentID
                activeFlight = flight
                pendingSendStreamRoom = false
            } else if let bound = flight.boundItemID, pendingSendStreamRoom, rows.contains(where: { $0.id == bound }) {
                pendingSendStreamRoom = false
            }
        } else if pendingSendStreamRoom, currentSentID != nil {
            pendingSendStreamRoom = false
        }

        if let fadeID = reduceMotionFadeBubbleID, fadeID.isEmpty, let currentSentID {
            reduceMotionFadeBubbleID = currentSentID
        }

        let resolvedSentID = currentSentID ?? activeFlight?.boundItemID

        let streamItems = SendFlightLogic.streamRoomItems(from: rows)
        let retained = SendFlightLogic.resolveStreamRoomTurnKey(
            state: detail.streamRoomState,
            isBusy: isBusy,
            items: streamItems,
            sentID: resolvedSentID,
            retainedTurnKey: retainedStreamRoomTurnKey
        )
        if retained != retainedStreamRoomTurnKey { retainedStreamRoomTurnKey = retained }

        let entries = SendFlightLogic.entranceEntries(from: rows)
        let advanced = SendFlightLogic.advanceConversationEntrance(
            entrance,
            items: entries,
            sentID: resolvedSentID
        )
        if advanced != entrance { entrance = advanced }
    }

    /// Handles the latest send as a screen appears. A Home handoff adopts stream room and stickiness in place (no
    /// J-curve flight and no double-fade, since Home already faded the first message in while docking); anything else
    /// (a send made before the user left and came back) is only marked handled so it never replays.
    @discardableResult
    func adoptOnAppear(
        _ event: ThreadSendEvent?,
        detail: ThreadDetailState,
        rows: [TranscriptRow]? = nil,
        isHandoffScreen: Bool,
        reduceMotion: Bool,
        now: Date = Date()
    ) -> SendFlightStartAction {
        guard let event, event.threadID == detail.summary.id, lastHandledSendID != event.id else { return .none }
        guard event.isHandoff, isHandoffScreen else {
            lastHandledSendID = event.id
            return .none
        }
        return beginSend(event, detail: detail, rows: rows, reduceMotion: reduceMotion, now: now)
    }

    /// Begins a send flight (in-thread), adopts a Home handoff in place, or runs an instant Reduce Motion anchor.
    @discardableResult
    func beginSend(
        _ event: ThreadSendEvent,
        detail: ThreadDetailState,
        rows providedRows: [TranscriptRow]? = nil,
        reduceMotion: Bool,
        now: Date = Date()
    ) -> SendFlightStartAction {
        guard event.threadID == detail.summary.id else { return .none }
        guard lastHandledSendID != event.id else { return .none }
        lastHandledSendID = event.id

        // Under Reduce Motion a handoff screen crossfades in whole; no separate bubble fade or flight.
        if event.isHandoff && reduceMotion { return .none }

        let rows = providedRows ?? detail.rows
        let preFlightJump = event.isHandoff ? nil : preFlightJumpOffset()

        // Rapid consecutive send: finish/supersede any earlier flight cleanly so its real bubble appears immediately.
        cancelFlight(clearPendingStreamRoom: false)

        let boundID = event.optimisticItemID ?? (event.isHandoff ? lastUserRowID(in: rows) : nil)
        let lastUserIDBeforeSend = lastUserRowID(in: rows, excluding: boundID)
        tracker.armSend(threadID: event.threadID, lastUserID: lastUserIDBeforeSend)
        stickiness.armStick()
        if let boundID {
            retainedStreamRoomTurnKey = boundID
        }

        // Home → new thread handoff: Home already faded the first message in while docking the composer, so keep the
        // real bubble at opacity 1 with no flight and release Working immediately to rise smoothly below it.
        if event.isHandoff {
            reduceMotionFadeBubbleID = nil
            pendingSendStreamRoom = (boundID == nil)
            releaseHold()
            refreshScrollToBottom()
            return .handoff
        }

        if reduceMotion {
            releaseHold()
            reduceMotionFadeBubbleID = event.optimisticItemID ?? ""
            pendingSendStreamRoom = false
            programmaticScrollPending = true
            return .instantAnchor
        }

        reduceMotionFadeBubbleID = nil
        pendingSendStreamRoom = true
        boundBubbleFrame = nil
        activeFlight = ActiveSendFlight(
            id: event.id,
            threadID: event.threadID,
            text: event.text,
            attachments: event.attachments,
            composerFrame: composerFrame.width > 0 && composerFrame.height > 0 ? composerFrame : nil,
            boundItemID: boundID,
            preFlightJumpY: preFlightJump
        )
        programmaticScrollPending = true
        refreshScrollToBottom()
        scheduleHoldRelease(for: event.id, delay: SendFlightTiming.workingDelay)
        scheduleCompletionSafetyNet(for: event.id)
        return .startFlight
    }

    /// Cancels an active flight or handoff hold if its live network dispatch threw an error.
    func failSend(_ eventID: UUID) {
        guard activeFlight?.id == eventID || latestTurnHeldForSendID == eventID else { return }
        cancelFlight(clearPendingStreamRoom: true)
    }

    /// Unconditionally clears any active flight and stops any in-progress programmatic scroll animation.
    func cancelFlight(clearPendingStreamRoom: Bool = false) {
        completionTask?.cancel()
        completionTask = nil
        scrollDriver.cancelAnimation()
        if activeFlight != nil { activeFlight = nil }
        boundBubbleFrame = nil
        programmaticScrollPending = false
        if clearPendingStreamRoom {
            pendingSendStreamRoom = false
            releaseHold()
        }
        refreshScrollToBottom()
    }

    /// Lands the active flight if its ID still matches. Returns `true` when the transcript should settle to the bottom
    /// (content grew under the flight); that also bumps `settleToBottomToken`.
    @discardableResult
    func finishFlightIfMatching(_ id: UUID) -> Bool {
        guard let flight = activeFlight, flight.id == id else { return false }
        if !flight.scrollInterrupted && scrollDriver.isAnimating {
            scrollDriver.finishAnimationAtTarget()
        }
        let remainingDistance = scrollDriver.distanceFromBottom() ?? stickiness.lastMetrics.distanceFromBottom
        let needsSettle = !flight.scrollInterrupted
            && stickiness.isSticking
            && remainingDistance > 1
        cancelFlight(clearPendingStreamRoom: true)
        if needsSettle {
            programmaticScrollPending = true
            settleToBottomToken += 1
        }
        return needsSettle
    }

    /// True while the real `UserBubble` for `rowID` is represented by the active flight overlay (or is about to be:
    /// `pendingRowID` from `pendingFlightRowID`).
    func isBubbleHiddenForFlight(rowID: String, in detail: ThreadDetailState, pendingRowID: String? = nil) -> Bool {
        activeHiddenFlightBubbleID(in: detail, pendingRowID: pendingRowID) == rowID
    }

    /// Pins the active flight to an exact normalized progress `[0, 1]` for deterministic snapshot verification.
    func pinActiveFlightProgress(_ progress: Double) {
        guard var flight = activeFlight else { return }
        completionTask?.cancel()
        completionTask = nil
        scrollDriver.cancelAnimation()
        flight.pinnedProgress = min(1.0, max(0.0, progress))
        activeFlight = flight
    }

    func updateComposerFrame(_ frame: CGRect) {
        guard frame.width > 0, frame.height > 0, !frame.isNearlyEqual(to: composerFrame) else { return }
        composerFrame = frame
    }

    func updateViewportSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0, size != viewportSize else { return }
        viewportSize = size
    }

    /// Records the bound bubble's measured frame. Only its x and size matter (scrolling moves y every frame), so
    /// scrolling during the flight never invalidates anything.
    func updateBubbleFrames(_ frames: [String: CGRect]) {
        guard let boundID = activeFlight?.boundItemID, let frame = frames[boundID], frame.width > 0, frame.height > 0 else { return }
        if let current = boundBubbleFrame,
           abs(current.minX - frame.minX) < 0.5,
           abs(current.width - frame.width) < 0.5,
           abs(current.height - frame.height) < 0.5
        {
            return
        }
        boundBubbleFrame = frame
    }

    /// Where the flight lands, in `SendFlightCoordinateSpace`: the new prompt's resting spot once the transcript has
    /// scrolled to its end, using the real bubble's measured size as soon as it is known.
    func landingFrame(for flight: ActiveSendFlight, topInset: CGFloat, bottomInset: CGFloat) -> CGRect {
        let viewport = resolvedViewportSize(for: flight)
        let maxWidth = SendFlightLogic.maxUserBubbleWidth(viewportWidth: viewport.width)
        let size = boundBubbleFrame?.size ?? SendFlightLogic.estimatedTurnSize(text: flight.text, attachments: flight.attachments, maxWidth: maxWidth)
        return SendFlightLogic.landingFrame(
            viewportSize: viewport,
            topInset: topInset,
            bottomInset: bottomInset,
            bubbleSize: size,
            measuredMinX: boundBubbleFrame?.minX
        )
    }

    func maxBubbleWidth(for flight: ActiveSendFlight) -> CGFloat {
        SendFlightLogic.maxUserBubbleWidth(viewportWidth: resolvedViewportSize(for: flight).width)
    }

    /// The composer frame a flight launches from.
    func launchFrame(for flight: ActiveSendFlight) -> CGRect {
        if let frame = flight.composerFrame { return frame }
        if composerFrame.width > 0 && composerFrame.height > 0 { return composerFrame }
        let viewport = resolvedViewportSize(for: flight)
        let width = min(max(200, viewport.width - 64), SwftLayout.composerMaxWidth)
        let height: CGFloat = 110
        return CGRect(x: max(32, (viewport.width - width) / 2), y: max(0, viewport.height - height - 12), width: width, height: height)
    }

    /// A send from far up the transcript first jumps to the old end, so the animated part covers at most about one
    /// viewport instead of streaking through the whole history (Studio's one-viewport `reach`).
    func preFlightJumpOffset() -> CGFloat? {
        let metrics = stickiness.lastMetrics
        guard metrics.viewportHeight > 0, metrics.distanceFromBottom > metrics.viewportHeight else { return nil }
        return metrics.endOffsetY
    }

    func handleWorkFoldToggle() {
        scrollDriver.cancelAnimation()
        stickiness.releaseStick()
        refreshScrollToBottom()
    }

    func armScrollToBottom() {
        stickiness.armStick()
        programmaticScrollPending = true
        refreshScrollToBottom()
    }

    /// Immediately hands scroll control back to the user if they start scrolling while a flight or programmatic scroll
    /// is running. Returns `true` when an active flight was cut short.
    @discardableResult
    func handleUserScrollInterrupt() -> Bool {
        isUserInteractingWithScroll = true
        programmaticScrollPending = false
        scrollDriver.cancelAnimation()
        if activeFlight != nil {
            cancelFlight(clearPendingStreamRoom: false)
            return true
        }
        return false
    }

    /// Returns `true` when a user gesture cut an active flight short (the caller fades the real bubble in).
    @discardableResult
    func handleScrollPhaseChange(from oldPhase: ScrollPhase, to newPhase: ScrollPhase) -> Bool {
        switch newPhase {
        case .interacting:
            return handleUserScrollInterrupt()
        case .idle:
            isUserInteractingWithScroll = false
            programmaticScrollPending = false
        case .decelerating, .tracking, .animating:
            break
        }
        return false
    }

    /// Updates scroll stickiness from SwiftUI's `onScrollGeometryChange`.
    /// Returns `true` when the view should pin to the bottom to follow live streaming / hydration growth.
    @discardableResult
    func handleScrollGeometryChange(_ metrics: ScrollMetrics, isSendPending: Bool = false) -> Bool {
        defer { refreshScrollToBottom() }
        let previousContentHeight = stickiness.lastMetrics.contentHeight
        let contentGrew = metrics.contentHeight > previousContentHeight + 0.5

        if isSendPending && activeFlight == nil {
            // Preserve pre-send scroll metrics on Frame 0 so `preFlightJumpOffset()` targets the old end.
            return false
        }

        if activeFlight != nil || scrollDriver.isAnimating {
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

    // MARK: - Private Helpers

    private func refreshScrollToBottom() {
        let shows = stickiness.showsScrollToBottom(isFlightActive: activeFlight != nil)
        if shows != showsScrollToBottom { showsScrollToBottom = shows }
    }

    private func releaseHold() {
        holdReleaseTask?.cancel()
        holdReleaseTask = nil
        if latestTurnHeldForSendID != nil { latestTurnHeldForSendID = nil }
    }

    private func scheduleHoldRelease(for sendID: UUID, delay: TimeInterval) {
        holdReleaseTask?.cancel()
        latestTurnHeldForSendID = sendID
        holdReleaseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.latestTurnHeldForSendID == sendID else { return }
            self.latestTurnHeldForSendID = nil
        }
    }

    /// The overlay's animation completion lands the flight; this only guarantees a ghost can never outlive it.
    private func scheduleCompletionSafetyNet(for flightID: UUID) {
        completionTask?.cancel()
        completionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(SendFlightTiming.sendDuration + 0.25))
            guard !Task.isCancelled else { return }
            _ = self?.finishFlightIfMatching(flightID)
        }
    }

    private func resolvedViewportSize(for flight: ActiveSendFlight) -> CGSize {
        if viewportSize.width > 0 && viewportSize.height > 0 { return viewportSize }
        let width = max((flight.composerFrame?.maxX ?? 0) + 32, SwftLayout.contentMaxWidth + 64)
        return CGSize(width: width, height: 860)
    }

    private func lastUserRowID(in rows: [TranscriptRow], excluding excludedID: String? = nil) -> String? {
        for row in rows.reversed() {
            if case .user(let id, _, _) = row, id != excludedID {
                return id
            }
        }
        return nil
    }
}

private extension CGRect {
    func isNearlyEqual(to other: CGRect) -> Bool {
        abs(minX - other.minX) < 0.5 && abs(minY - other.minY) < 0.5 && abs(width - other.width) < 0.5 && abs(height - other.height) < 0.5
    }
}
