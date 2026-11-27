import CoreGraphics
import Foundation
import SwftDesign

// Pure stream-room, turn and scroll-stickiness logic for `ThreadView` (ported from Studio's `threadView.logic.ts`).

/// Coarse thread activity state matching Studio's `ThreadState` for stream-room decisions.
enum StreamRoomThreadState: Equatable, Sendable {
    case idle
    case working
    case needsYou
    case done
    case failed
}

/// Minimal item descriptor used by stream-room calculations.
struct StreamRoomItem: Equatable, Sendable {
    let id: String
    let isUser: Bool
    let isTurnFold: Bool

    init(id: String, isUser: Bool = false, isTurnFold: Bool = false) {
        self.id = id
        self.isUser = isUser
        self.isTurnFold = isTurnFold
    }
}

/// One Swft transcript turn (from a user message through all responses/work before the next user message).
struct TranscriptTurn: Identifiable, Equatable {
    let id: String
    let rows: [TranscriptRow]
}

/// Snapshot of a scroll view's vertical geometry.
struct ScrollMetrics: Equatable, Sendable {
    var offsetY: CGFloat
    var contentHeight: CGFloat
    var viewportHeight: CGFloat

    var endOffsetY: CGFloat { max(0, contentHeight - viewportHeight) }
    var distanceFromBottom: CGFloat { max(0, endOffsetY - offsetY) }
    var isScrollable: Bool { contentHeight > viewportHeight + 1 }
}

/// Pure stick-to-bottom state machine mirroring Studio's `STICK_PX` / `handleScroll` behavior.
struct ThreadScrollStickiness: Equatable, Sendable {
    private(set) var isSticking: Bool = true
    private(set) var lastOffsetY: CGFloat = 0
    private(set) var lastMetrics = ScrollMetrics(offsetY: 0, contentHeight: 0, viewportHeight: 0)

    mutating func resetForThread() {
        isSticking = true
        lastOffsetY = 0
        lastMetrics = ScrollMetrics(offsetY: 0, contentHeight: 0, viewportHeight: 0)
    }

    mutating func armStick() {
        isSticking = true
    }

    mutating func releaseStick() {
        isSticking = false
    }

    /// Updates tracked geometry during a programmatic scroll without treating it as a user scroll-up.
    mutating func recordProgrammaticMetrics(_ metrics: ScrollMetrics) {
        lastMetrics = metrics
        lastOffsetY = metrics.offsetY
    }

    /// Processes a scroll event: scrolling up releases stick immediately; content shrinking underneath does not;
    /// scrolling back within `SendFlightTiming.stickThreshold` (80pt) of the bottom re-arms stick.
    mutating func handleScroll(_ metrics: ScrollMetrics) {
        let fromEnd = metrics.distanceFromBottom
        let scrolledUp = metrics.offsetY < lastOffsetY - 0.5 && fromEnd > 1
        lastOffsetY = metrics.offsetY
        lastMetrics = metrics
        if !metrics.isScrollable {
            isSticking = true
        } else {
            isSticking = fromEnd < SendFlightTiming.stickThreshold && !scrolledUp
        }
    }

    /// Whether the floating scroll-to-bottom button should be visible.
    func showsScrollToBottom(isScrolling: Bool) -> Bool {
        guard !isScrolling, lastMetrics.isScrollable else { return false }
        return !isSticking && lastMetrics.distanceFromBottom >= SendFlightTiming.stickThreshold
    }
}

enum SendFlightLogic {
    /// Minimum height reserved for the latest turn so the sent prompt sits at the top with empty stream room below.
    static func streamRoomHeight(viewportHeight: CGFloat, topInset: CGFloat, bottomInset: CGFloat) -> CGFloat {
        max(0, viewportHeight - topInset - bottomInset)
    }

    /// Vertical padding around a user bubble row in the transcript; Home's first-message preview matches it so the
    /// handoff lands in place.
    static let userRowVerticalPadding: CGFloat = 4

    /// Key of the latest turn in a thread (the last user message's ID, else the first item's ID, else nil).
    static func latestTurnKeyOf(_ items: [StreamRoomItem]) -> String? {
        if let user = items.last(where: \.isUser) {
            return user.id
        }
        return items.first?.id
    }

    /// Whether the latest turn has settled into a fold.
    static func latestTurnHasSettledFold(_ items: [StreamRoomItem]) -> Bool {
        let turnStart = items.lastIndex(where: \.isUser) ?? -1
        return items.indices.contains { $0 > turnStart && items[$0].isTurnFold }
    }

    /// Whether the latest turn reserves viewport height below its content for incoming output.
    static func latestTurnHasStreamRoom(
        state: StreamRoomThreadState,
        isBusy: Bool,
        items: [StreamRoomItem],
        retainedTurnKey: String? = nil
    ) -> Bool {
        if items.isEmpty { return false }
        if let latestKey = latestTurnKeyOf(items), retainedTurnKey == latestKey { return true }
        if latestTurnHasSettledFold(items) { return false }
        return state == .working || state == .needsYou || isBusy
    }

    /// Latches the latest turn key for stream-room retention while this thread stays open, so a turn that had room
    /// keeps it after it settles instead of the transcript shrinking under the reader.
    static func resolveStreamRoomTurnKey(
        state: StreamRoomThreadState,
        isBusy: Bool,
        items: [StreamRoomItem],
        retainedTurnKey: String?
    ) -> String? {
        guard let latestKey = latestTurnKeyOf(items) else { return nil }
        if retainedTurnKey == latestKey { return latestKey }
        return latestTurnHasStreamRoom(state: state, isBusy: isBusy, items: items) ? latestKey : nil
    }

    /// Splits Swft's `[TranscriptRow]` into turns so the latest turn can reserve stream room cleanly.
    static func turns(from rows: [TranscriptRow]) -> [TranscriptTurn] {
        var groups: [(id: String, rows: [TranscriptRow])] = []
        for row in rows {
            if case .user(let id, _, _) = row {
                groups.append((id: id, rows: [row]))
            } else if groups.isEmpty {
                groups.append((id: row.id, rows: [row]))
            } else {
                groups[groups.count - 1].rows.append(row)
            }
        }
        return groups.map { TranscriptTurn(id: $0.id, rows: $0.rows) }
    }

    static func streamRoomItems(from rows: [TranscriptRow]) -> [StreamRoomItem] {
        rows.map { row in
            switch row {
            case .user(let id, _, _):
                StreamRoomItem(id: id, isUser: true)
            case .work(let fold):
                StreamRoomItem(id: fold.id, isTurnFold: !fold.isLive)
            default:
                StreamRoomItem(id: row.id)
            }
        }
    }

    /// Shows the quiet "Working" indicator when a turn is active before any live work fold, streaming reply,
    /// pending approval, or settled fold/answer appears in the latest turn.
    static func shouldShowWorkingIndicator(
        isRunning: Bool,
        isBusy: Bool,
        latestTurnRows: [TranscriptRow]
    ) -> Bool {
        guard isRunning || isBusy, !latestTurnRows.isEmpty else { return false }
        for row in latestTurnRows {
            switch row {
            case .user:
                continue
            case .work:
                return false
            case .assistant(_, _, _):
                return false
            case .approval(_, let approval) where approval.status == .pending:
                return false
            case .subagent(let subagent) where subagent.status.isActive:
                return false
            case .subagentGroup(let group) where group.hasActive:
                return false
            case .approval, .note, .subagent, .subagentGroup:
                continue
            }
        }
        return true
    }
}
