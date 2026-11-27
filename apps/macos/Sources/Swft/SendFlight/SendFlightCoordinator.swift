import CoreGraphics
import Foundation
import Observation
import SwftDesign
import SwiftUI

/// Immutable payload emitted by `AppModel.send()` when a message is dispatched inside a thread, or when Home hands a
/// freshly launched thread over to its screen (`isHandoff`, where Home already faded the first message in while docking
/// the composer, so `ThreadView` takes over in place).
struct ThreadSendEvent: Equatable, Sendable {
    let id: UUID
    let threadID: String
    let text: String
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

/// What `ThreadView` does with a send it has just handled.
enum ThreadSendAction: Equatable, Sendable {
    case none
    /// Scroll the new turn (and its stream room) into view, jumping to `preJumpY` first when sent from far up.
    case scrollToNewTurn(preJumpY: CGFloat?)
    /// Home → new thread: the first message is already in place; nothing scrolls.
    case handoff
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

/// Coordinates a send inside one `ThreadView`: the scroll down to the new turn's stream room, the sent message's fade-in,
/// stream-room retention, keeping watched turns laid out as they streamed, and scroll stickiness. Observed properties
/// change only on discrete events (a send, a stick flip), never per scroll frame, so scrolling does not re-render the
/// transcript.
@MainActor
@Observable
final class SendFlightCoordinator {
    private(set) var currentThreadID: String?
    /// The sent message row fading in; it keeps its fade modifier until the thread changes.
    private(set) var fadeBubbleID: String?
    private(set) var retainedStreamRoomTurnKey: String?
    /// A handoff whose first message row has not arrived yet still reserves stream room.
    private(set) var pendingSendStreamRoom = false
    /// Turns seen live on this screen; they keep their streamed layout after settling (see `TranscriptLayout.rows`).
    private(set) var inlineTurnIDs: Set<String> = []
    private(set) var viewportSize: CGSize = .zero
    private(set) var showsScrollToBottom = false
    private(set) var lastHandledSendID: UUID?

    @ObservationIgnored let scrollDriver = SendFlightScrollDriver()
    @ObservationIgnored private(set) var stickiness = ThreadScrollStickiness()
    @ObservationIgnored private(set) var isUserInteractingWithScroll = false
    @ObservationIgnored private(set) var programmaticScrollPending = false

    init() {}

    /// True on the frame a send's row lands in the transcript, before `beginSend` / `adoptOnAppear` has handled it.
    func isSendPending(_ latestSend: ThreadSendEvent?, in detail: ThreadDetailState) -> Bool {
        guard let latestSend, latestSend.threadID == detail.summary.id else { return false }
        return latestSend.id != lastHandledSendID
    }

    /// The user row fading in. A pending in-thread send's row fades from its very first frame, before `beginSend` runs.
    func fadingBubbleID(latestSend: ThreadSendEvent?, in detail: ThreadDetailState) -> String? {
        if let latestSend, !latestSend.isHandoff, isSendPending(latestSend, in: detail) {
            return latestSend.optimisticItemID
        }
        return fadeBubbleID
    }

    /// Pass `latestSend` so the new turn has its room on the send's very first frame.
    func hasStreamRoom(
        for detail: ThreadDetailState,
        rows: [TranscriptRow],
        isBusy: Bool,
        latestSend: ThreadSendEvent? = nil
    ) -> Bool {
        if isSendPending(latestSend, in: detail) { return true }
        if pendingSendStreamRoom && currentThreadID == detail.summary.id { return true }
        return SendFlightLogic.latestTurnHasStreamRoom(
            state: detail.streamRoomState,
            isBusy: isBusy,
            items: SendFlightLogic.streamRoomItems(from: rows),
            retainedTurnKey: retainedStreamRoomTurnKey
        )
    }

    /// Synchronizes thread-scoped state whenever the open thread, rows, or busy state changes.
    func syncThread(detail: ThreadDetailState, rows: [TranscriptRow], isBusy: Bool) {
        let threadID = detail.summary.id
        if currentThreadID != threadID {
            scrollDriver.cancelAnimation()
            fadeBubbleID = nil
            retainedStreamRoomTurnKey = nil
            pendingSendStreamRoom = false
            inlineTurnIDs = []
            stickiness.resetForThread()
            isUserInteractingWithScroll = false
            programmaticScrollPending = false
            currentThreadID = threadID
            refreshScrollToBottom()
        }

        if let liveTurnID = TranscriptLayout.liveTurnID(in: detail.items, isRunning: detail.isRunning),
           !inlineTurnIDs.contains(liveTurnID)
        {
            inlineTurnIDs.insert(liveTurnID)
        }

        let items = SendFlightLogic.streamRoomItems(from: rows)
        if pendingSendStreamRoom, let latestUser = items.last(where: \.isUser) {
            retainedStreamRoomTurnKey = latestUser.id
            pendingSendStreamRoom = false
        }
        let retained = SendFlightLogic.resolveStreamRoomTurnKey(
            state: detail.streamRoomState,
            isBusy: isBusy,
            items: items,
            retainedTurnKey: retainedStreamRoomTurnKey
        )
        if retained != retainedStreamRoomTurnKey { retainedStreamRoomTurnKey = retained }
    }

    /// Handles the latest send as a screen appears: a Home handoff is adopted in place; anything else (a send made
    /// before the user left and came back) is only marked handled so it never replays.
    @discardableResult
    func adoptOnAppear(
        _ event: ThreadSendEvent?,
        detail: ThreadDetailState,
        rows: [TranscriptRow],
        isHandoffScreen: Bool
    ) -> ThreadSendAction {
        guard let event, event.threadID == detail.summary.id, lastHandledSendID != event.id else { return .none }
        guard event.isHandoff, isHandoffScreen else {
            lastHandledSendID = event.id
            return .none
        }
        return beginSend(event, detail: detail, rows: rows)
    }

    @discardableResult
    func beginSend(_ event: ThreadSendEvent, detail: ThreadDetailState, rows: [TranscriptRow]) -> ThreadSendAction {
        guard event.threadID == detail.summary.id, lastHandledSendID != event.id else { return .none }
        lastHandledSendID = event.id
        stickiness.armStick()

        let turnKey = event.optimisticItemID ?? (event.isHandoff ? SendFlightLogic.streamRoomItems(from: rows).last(where: \.isUser)?.id : nil)
        if let turnKey {
            retainedStreamRoomTurnKey = turnKey
            pendingSendStreamRoom = false
        } else {
            pendingSendStreamRoom = true
        }

        if event.isHandoff {
            refreshScrollToBottom()
            return .handoff
        }

        fadeBubbleID = event.optimisticItemID
        programmaticScrollPending = true
        let preJump = preSendJumpOffset()
        refreshScrollToBottom()
        return .scrollToNewTurn(preJumpY: preJump)
    }

    /// The send's network dispatch threw; its optimistic row is gone, so stop scrolling toward it.
    func failSend(_ eventID: UUID) {
        guard lastHandledSendID == eventID else { return }
        scrollDriver.cancelAnimation()
        programmaticScrollPending = false
        refreshScrollToBottom()
    }

    func updateViewportSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0, size != viewportSize else { return }
        viewportSize = size
    }

    /// A send from far up the transcript first jumps to the old end, so the animated part covers at most about one
    /// viewport instead of streaking through the whole history.
    func preSendJumpOffset() -> CGFloat? {
        let metrics = stickiness.lastMetrics
        guard metrics.viewportHeight > 0, metrics.distanceFromBottom > metrics.viewportHeight else { return nil }
        return metrics.endOffsetY
    }

    /// The send scroll landed. Returns `true` when streaming outgrew it meanwhile and it should settle to the new end.
    func finishSendScroll() -> Bool {
        let remaining = scrollDriver.distanceFromBottom() ?? stickiness.lastMetrics.distanceFromBottom
        guard stickiness.isSticking, !isUserInteractingWithScroll, remaining > 1 else { return false }
        programmaticScrollPending = true
        return true
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

    /// Hands scroll control straight back to the user when they scroll during a programmatic scroll.
    func handleUserScrollInterrupt() {
        isUserInteractingWithScroll = true
        programmaticScrollPending = false
        scrollDriver.cancelAnimation()
        refreshScrollToBottom()
    }

    func handleScrollPhaseChange(to newPhase: ScrollPhase) {
        switch newPhase {
        case .interacting:
            handleUserScrollInterrupt()
        case .idle:
            isUserInteractingWithScroll = false
            programmaticScrollPending = false
        case .decelerating, .tracking, .animating:
            break
        }
    }

    /// Updates scroll stickiness from SwiftUI's `onScrollGeometryChange`.
    /// Returns `true` when the view should pin to the bottom to follow live streaming growth.
    @discardableResult
    func handleScrollGeometryChange(_ metrics: ScrollMetrics, isSendPending: Bool = false) -> Bool {
        defer { refreshScrollToBottom() }
        // Keep the pre-send metrics on the send's first frame so `preSendJumpOffset()` targets the old end.
        if isSendPending { return false }

        if scrollDriver.isAnimating {
            stickiness.recordProgrammaticMetrics(metrics)
            return false
        }

        let contentGrew = metrics.contentHeight > stickiness.lastMetrics.contentHeight + 0.5
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

    private func refreshScrollToBottom() {
        let shows = stickiness.showsScrollToBottom(isScrolling: scrollDriver.isAnimating)
        if shows != showsScrollToBottom { showsScrollToBottom = shows }
    }
}
