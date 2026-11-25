import CoreGraphics
import Foundation
import SwftDesign

// Pure thread-view send-flight, stream-room, entrance, turn-block, and scroll-stickiness logic
// ported from Studio (`threadView.logic.ts` and `threadView.shared.tsx`).

/// Geometry inputs for Studio's `computeSendLift`.
struct SendLiftInput: Equatable, Sendable {
    var anchorTop: CGFloat
    var anchorBottom: CGFloat
    var bubbleTop: CGFloat
    var bubbleBottom: CGFloat
    var slide: CGFloat
}

/// Entrance metadata for one visible transcript row.
struct EntranceEntry: Equatable, Sendable {
    let id: String
    let foldedBy: String?
    let isTurnFold: Bool

    init(id: String, foldedBy: String? = nil, isTurnFold: Bool = false) {
        self.id = id
        self.foldedBy = foldedBy
        self.isTurnFold = isTurnFold
    }
}

/// Snapshot of initial stagger delays and locally-sent item IDs for an open thread.
struct ConversationEntrance: Equatable, Sendable {
    /// `nil` until the thread's first non-empty visible batch arrives (live threads mount empty).
    var initial: [String: TimeInterval]?
    var sent: Set<String>
}

/// Resolved entrance behavior for a single row.
struct ItemEntrance: Equatable, Sendable {
    let still: Bool
    let delay: TimeInterval
}

/// Coarse thread activity state matching Studio's `ThreadState` for stream-room decisions.
enum StreamRoomThreadState: Equatable, Sendable {
    case idle
    case working
    case needsYou
    case done
    case failed
}

/// Minimal item descriptor used by stream-room and latest-turn-fold calculations.
struct StreamRoomItem: Equatable, Sendable {
    let id: String
    let isUser: Bool
    let isTurnFold: Bool
    let foldedBy: String?

    init(id: String, isUser: Bool = false, isTurnFold: Bool = false, foldedBy: String? = nil) {
        self.id = id
        self.isUser = isUser
        self.isTurnFold = isTurnFold
        self.foldedBy = foldedBy
    }
}

/// Anchor row kept stationary when a live turn settles into a fold.
struct LatestTurnFoldResult: Equatable, Sendable {
    let anchorID: String?
}

/// Turn-block item kinds matching Studio's `partitionTurnBlocks`.
enum TurnBlockItemKind: Equatable, Sendable {
    case user
    case assistant
    case thought
    case command
    case edit
    case read
    case search
    case web
    case tool
    case subagent
    case turnFold
    case decision
    case question
    case plan
    case changes
    case handoff
    case error
    case notice
    case todo
    case compaction
    case threadLink
    case divider
    case worked
}

/// Minimal item input for `SendFlightLogic.partitionTurnBlocks`.
struct TurnBlockItem: Equatable, Sendable {
    let id: String
    let kind: TurnBlockItemKind
    let foldedBy: String?

    init(id: String, kind: TurnBlockItemKind, foldedBy: String? = nil) {
        self.id = id
        self.kind = kind
        self.foldedBy = foldedBy
    }
}

/// One visible or sliced row inside a partitioned turn.
enum TurnRow: Equatable, Sendable {
    case item(TurnBlockItem, visibleIndex: Int)
    case work(key: String, items: [TurnBlockItem], visibleIndex: Int, active: Bool)
    case subagents(key: String, items: [TurnBlockItem], visibleIndex: Int)

    var head: TurnBlockItem {
        switch self {
        case .item(let item, _): item
        case .work(_, let items, _, _): items[0]
        case .subagents(_, let items, _): items[0]
        }
    }
}

/// A top-level block in a partitioned turn: either a visible row or a contiguous folded slice.
enum TurnBlock: Equatable, Sendable {
    case row(TurnRow)
    case foldedSlice(key: String, foldID: String, rows: [TurnRow])
}

/// One Swft transcript turn (from a user message through all responses/work before the next user message).
struct TranscriptTurn: Identifiable, Equatable {
    let id: String
    let rows: [TranscriptRow]
}

/// Tracks the composer-sent user bubble ID for one open thread without replaying on thread switch.
struct SentAnimationTracker: Equatable, Sendable {
    private(set) var armedThreadID: String?
    private(set) var armedPreviousUserID: String?

    mutating func resetForThreadIfNeeded(_ threadID: String) {
        if armedThreadID != nil && armedThreadID != threadID {
            armedThreadID = nil
            armedPreviousUserID = nil
        }
    }

    /// Arms tracking before dispatching a send so the next newly-arrived user message is recognized as locally sent.
    mutating func armSend(threadID: String, lastUserID: String?) {
        if armedThreadID != threadID {
            armedThreadID = threadID
            armedPreviousUserID = lastUserID
        } else if lastUserID != armedPreviousUserID {
            armedPreviousUserID = lastUserID
        }
    }

    func sentID(for threadID: String, lastUserID: String?) -> String? {
        guard armedThreadID == threadID, let lastUserID, lastUserID != armedPreviousUserID else {
            return nil
        }
        return lastUserID
    }
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

    /// Updates tracked geometry during programmatic scroll/flight without falsely treating it as a user scroll-up.
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
    func showsScrollToBottom(isFlightActive: Bool) -> Bool {
        guard !isFlightActive, lastMetrics.isScrollable else { return false }
        return !isSticking && lastMetrics.distanceFromBottom >= SendFlightTiming.stickThreshold
    }
}

enum SendFlightLogic {
    // MARK: - Lift & Scroll Geometry

    /// Starting vertical lift for a sent user bubble unit inside a sliding conversation wrapper.
    /// Clamping at `-slide` keeps `slide + lift >= 0` while tucking tall/attachment bubbles inside the composer bottom.
    static func computeSendLift(_ input: SendLiftInput) -> CGFloat {
        let fromTop = input.anchorTop + SendFlightTiming.sendTopTuck - input.bubbleTop - input.slide
        let fromBottom = input.anchorBottom - SendFlightTiming.sendBottomInset - input.bubbleBottom - input.slide
        return max(-input.slide, min(fromTop, fromBottom))
    }

    /// Minimum height reserved for the latest turn so the sent prompt sits at the top with empty stream room below.
    static func streamRoomHeight(viewportHeight: CGFloat, topInset: CGFloat, bottomInset: CGFloat) -> CGFloat {
        max(0, viewportHeight - topInset - bottomInset)
    }

    /// Vertical padding around a user bubble row in the transcript (`ThreadView`), so its pill sits this far below
    /// the top of its turn. Landing math and the transcript share it so the flight lands on the pill exactly.
    static let userRowVerticalPadding: CGFloat = 4

    /// Analytical top-right landing frame in `SendFlightCoordinateSpace` before the real bubble reports geometry.
    /// `topInset` is the transcript's own top padding (the latest turn's top once scrolled to its end).
    static func predictedLandingFrame(
        viewportWidth: CGFloat,
        topInset: CGFloat,
        bubbleSize: CGSize
    ) -> CGRect {
        let horizontalPadding: CGFloat = 32
        let columnWidth = min(max(0, viewportWidth - horizontalPadding * 2), SwftLayout.contentMaxWidth)
        let columnTrailingX = (viewportWidth + columnWidth) / 2
        let minX = max(horizontalPadding, columnTrailingX - bubbleSize.width)
        let minY = topInset + userRowVerticalPadding
        return CGRect(x: minX, y: minY, width: bubbleSize.width, height: bubbleSize.height)
    }

    /// Where a sent bubble rests once the transcript has scrolled to its end. The latest turn is at least
    /// `streamRoomHeight` tall, so its top sits exactly at `topInset`; a prompt taller than the stream room instead
    /// ends `bottomInset` above the viewport's bottom. `measuredMinX` (the real bubble's x) wins over the estimate.
    static func landingFrame(
        viewportSize: CGSize,
        topInset: CGFloat,
        bottomInset: CGFloat,
        bubbleSize: CGSize,
        measuredMinX: CGFloat? = nil
    ) -> CGRect {
        var frame = predictedLandingFrame(viewportWidth: viewportSize.width, topInset: topInset, bubbleSize: bubbleSize)
        let turnHeight = bubbleSize.height + userRowVerticalPadding * 2
        let room = streamRoomHeight(viewportHeight: viewportSize.height, topInset: topInset, bottomInset: bottomInset)
        if turnHeight > room {
            frame.origin.y = viewportSize.height - bottomInset - turnHeight + userRowVerticalPadding
        }
        if let measuredMinX { frame.origin.x = measuredMinX }
        return frame
    }

    /// Maximum horizontal width allowed for a `UserBubble` pill given the viewport width.
    static func maxUserBubbleWidth(viewportWidth: CGFloat) -> CGFloat {
        let columnWidth = min(max(0, viewportWidth - 64), SwftLayout.contentMaxWidth)
        return max(44, columnWidth - UserBubbleMetrics.leadingSpacerMinLength)
    }

    // MARK: - Conversation Entrance Stagger

    static func visibleItemsOf(_ items: [EntranceEntry]) -> [EntranceEntry] {
        items.filter { $0.foldedBy == nil }
    }

    static func createConversationEntrance(
        _ items: [EntranceEntry],
        sentID: String?
    ) -> ConversationEntrance {
        advanceConversationEntrance(ConversationEntrance(initial: nil, sent: []), items: items, sentID: sentID)
    }

    static func advanceConversationEntrance(
        _ current: ConversationEntrance,
        items: [EntranceEntry],
        sentID: String?
    ) -> ConversationEntrance {
        let visible = visibleItemsOf(items)
        var initial = current.initial
        var sent = current.sent

        if let sentID, !sent.contains(sentID) {
            sent.insert(sentID)
        }

        if initial == nil && !visible.isEmpty {
            var delays: [String: TimeInterval] = [:]
            for (index, item) in visible.enumerated() where !sent.contains(item.id) {
                delays[item.id] = Double(min(index, SendFlightTiming.maxStaggerIndex)) * SendFlightTiming.staggerStep
            }
            initial = delays
        }

        return ConversationEntrance(initial: initial, sent: sent)
    }

    static func prependedCutoffIndex(
        _ entrance: ConversationEntrance,
        items: [EntranceEntry]
    ) -> Int {
        let visible = visibleItemsOf(items)
        if let initial = entrance.initial, !initial.isEmpty {
            return visible.firstIndex(where: { initial[$0.id] != nil }) ?? -1
        }
        if !entrance.sent.isEmpty {
            return visible.firstIndex(where: { entrance.sent.contains($0.id) }) ?? -1
        }
        return -1
    }

    static func itemEntrance(
        _ entrance: ConversationEntrance,
        itemID: String,
        index: Int,
        cutoffIndex: Int,
        isTurnFold: Bool = false
    ) -> ItemEntrance {
        if entrance.sent.contains(itemID) {
            return ItemEntrance(still: true, delay: 0)
        }
        if let initialDelay = entrance.initial?[itemID] {
            return ItemEntrance(still: false, delay: initialDelay)
        }
        if cutoffIndex != -1 && index < cutoffIndex {
            return ItemEntrance(still: true, delay: 0)
        }
        if isTurnFold {
            return ItemEntrance(still: true, delay: 0)
        }
        return ItemEntrance(still: false, delay: 0)
    }

    static func tailEntranceDelay(_ entrance: ConversationEntrance) -> TimeInterval {
        Double(min(entrance.initial?.count ?? 0, SendFlightTiming.maxStaggerIndex)) * SendFlightTiming.staggerStep
    }

    // MARK: - Turn Partitioning & Stream Room

    static func isWorkStep(_ kind: TurnBlockItemKind) -> Bool {
        switch kind {
        case .thought, .command, .edit, .read, .search, .web, .tool:
            true
        default:
            false
        }
    }

    /// Splits one turn's items into visible rows and contiguous folded slices in chronological order.
    static func partitionTurnBlocks(
        _ items: [TurnBlockItem],
        startVisibleIndex: Int = 0,
        running: Bool = false
    ) -> [TurnBlock] {
        var blocks: [TurnBlock] = []
        var visibleIndex = startVisibleIndex

        func appendRow(into rows: inout [TurnRow], item: TurnBlockItem, visibleIndex: Int) -> Bool {
            if let last = rows.last {
                if isWorkStep(item.kind), case .work(let key, var existing, let idx, let active) = last {
                    existing.append(item)
                    rows[rows.count - 1] = .work(key: key, items: existing, visibleIndex: idx, active: active)
                    return false
                }
                if isWorkStep(item.kind), case .item(let prev, let idx) = last, isWorkStep(prev.kind) {
                    rows[rows.count - 1] = .work(key: prev.id, items: [prev, item], visibleIndex: idx, active: false)
                    return false
                }
                if item.kind == .subagent, case .subagents(let key, var existing, let idx) = last {
                    existing.append(item)
                    rows[rows.count - 1] = .subagents(key: key, items: existing, visibleIndex: idx)
                    return false
                }
                if item.kind == .subagent, case .item(let prev, let idx) = last, prev.kind == .subagent {
                    rows[rows.count - 1] = .subagents(key: prev.id, items: [prev, item], visibleIndex: idx)
                    return false
                }
            }
            rows.append(.item(item, visibleIndex: visibleIndex))
            return true
        }

        func appendTopLevelRow(_ item: TurnBlockItem) -> Bool {
            if let last = blocks.last, case .row(let prevRow) = last {
                var scratch = [prevRow]
                let createdNew = appendRow(into: &scratch, item: item, visibleIndex: visibleIndex)
                if !createdNew {
                    blocks[blocks.count - 1] = .row(scratch[0])
                    return false
                }
            }
            blocks.append(.row(.item(item, visibleIndex: visibleIndex)))
            return true
        }

        for item in items {
            guard let foldID = item.foldedBy else {
                if appendTopLevelRow(item) {
                    visibleIndex += 1
                }
                continue
            }
            if let last = blocks.last, case .foldedSlice(let key, let existingFoldID, var sliceRows) = last, existingFoldID == foldID {
                _ = appendRow(into: &sliceRows, item: item, visibleIndex: -1)
                blocks[blocks.count - 1] = .foldedSlice(key: key, foldID: existingFoldID, rows: sliceRows)
            } else {
                blocks.append(
                    .foldedSlice(
                        key: "slice:\(foldID):\(item.id)",
                        foldID: foldID,
                        rows: [.item(item, visibleIndex: -1)]
                    )
                )
            }
        }

        if running, let last = blocks.last, case .row(.work(let key, let workItems, let idx, _)) = last {
            blocks[blocks.count - 1] = .row(.work(key: key, items: workItems, visibleIndex: idx, active: true))
        }
        return blocks
    }

    static func rowHeads(_ blocks: [TurnBlock]) -> [TurnBlockItem] {
        blocks.compactMap { block in
            switch block {
            case .row(let row): row.head
            case .foldedSlice: nil
            }
        }
    }

    static func rowHeads(_ rows: [TurnRow]) -> [TurnBlockItem] {
        rows.map(\.head)
    }

    /// Key of the latest turn in a thread (the last user message's ID, else the first item's ID, else nil).
    static func latestTurnKeyOf(_ items: [StreamRoomItem]) -> String? {
        if let user = items.last(where: \.isUser) {
            return user.id
        }
        return items.first?.id
    }

    /// Finds the latest turn's settled fold and the anchor row directly below it.
    static func latestTurnFold(_ items: [StreamRoomItem]) -> LatestTurnFoldResult? {
        let turnStart = items.lastIndex(where: \.isUser) ?? -1
        guard let foldIndex = items.indices.first(where: { $0 > turnStart && items[$0].isTurnFold }) else {
            return nil
        }
        let anchor = items[(foldIndex + 1)...].first { $0.foldedBy == nil && !$0.isTurnFold }
        return LatestTurnFoldResult(anchorID: anchor?.id)
    }

    /// Whether the latest turn reserves viewport height below its content for incoming output.
    static func latestTurnHasStreamRoom(
        state: StreamRoomThreadState,
        isBusy: Bool,
        items: [StreamRoomItem],
        compact: Bool = false,
        retainedTurnKey: String? = nil
    ) -> Bool {
        if compact || items.isEmpty { return false }
        let latestKey = latestTurnKeyOf(items)
        if let latestKey, retainedTurnKey == latestKey { return true }
        if latestTurnFold(items) != nil { return false }
        return state == .working || state == .needsYou || isBusy
    }

    /// Latches the latest turn key for stream-room retention while this thread stays open.
    static func resolveStreamRoomTurnKey(
        state: StreamRoomThreadState,
        isBusy: Bool,
        items: [StreamRoomItem],
        sentID: String?,
        retainedTurnKey: String?,
        compact: Bool = false
    ) -> String? {
        if compact { return nil }
        guard let latestKey = latestTurnKeyOf(items) else { return nil }
        if let sentID, sentID == latestKey { return latestKey }
        if retainedTurnKey == latestKey { return latestKey }
        return latestTurnHasStreamRoom(state: state, isBusy: isBusy, items: items) ? latestKey : nil
    }

    // MARK: - Swft Transcript Adaptation

    /// Splits Swft's `[TranscriptRow]` into turns so the latest turn can reserve stream room cleanly.
    static func turns(from rows: [TranscriptRow]) -> [TranscriptTurn] {
        var groups: [(id: String, rows: [TranscriptRow])] = []
        for row in rows {
            if case .user(let id, _) = row {
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
            case .user(let id, _):
                StreamRoomItem(id: id, isUser: true)
            case .work(let fold):
                StreamRoomItem(id: fold.id, isTurnFold: !fold.isLive)
            default:
                StreamRoomItem(id: row.id)
            }
        }
    }

    static func entranceEntries(from rows: [TranscriptRow]) -> [EntranceEntry] {
        rows.map { row in
            switch row {
            case .work(let fold):
                EntranceEntry(id: fold.id, isTurnFold: !fold.isLive)
            default:
                EntranceEntry(id: row.id)
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
            case .approval, .note:
                continue
            }
        }
        return true
    }

}
