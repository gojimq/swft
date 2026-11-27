import SwftDesign
import SwiftUI

/// Renders one conversation turn inside `ThreadView`, applying stream-room height to the latest turn
/// and showing the delayed "Working" indicator when the latest turn is awaiting agent output.
///
/// Conforms to `Equatable` over plain value inputs so historical turns skip body re-evaluation during sends,
/// live server streaming updates, and work-fold toggles in other turns.
struct SendFlightTurnSection: View, Equatable {
    let threadID: String
    let turn: TranscriptTurn
    let isLatest: Bool
    let streamRoomHeight: CGFloat?
    let showWorking: Bool
    /// When a just-sent turn's "Working" row appears, so it follows the message's fade instead of racing it.
    let workingRevealAt: Date?
    /// The just-sent user message, which fades in while the transcript scrolls its turn into view.
    let fadeBubbleID: String?
    /// Work-fold IDs expanded inside this turn only.
    let expandedFoldIDs: Set<String>
    /// Subagent group and inline-detail IDs expanded inside this turn only.
    let expandedSubagentIDs: Set<String>
    let parentEnvironmentID: String?
    let knownEnvironmentIDs: Set<String>
    let reduceMotion: Bool
    let onToggleWorkFold: (String) -> Void
    let onToggleSubagentExpansion: (String) -> Void
    let onOpenSubagentThread: (SubagentNavigationTarget) -> Void
    let onResolveApproval: (String, Bool) -> Void

    init(
        threadID: String,
        turn: TranscriptTurn,
        isLatest: Bool,
        streamRoomHeight: CGFloat?,
        showWorking: Bool,
        workingRevealAt: Date? = nil,
        fadeBubbleID: String?,
        expandedFoldIDs: Set<String>,
        expandedSubagentIDs: Set<String> = [],
        parentEnvironmentID: String? = nil,
        knownEnvironmentIDs: Set<String> = [],
        reduceMotion: Bool,
        onToggleWorkFold: @escaping (String) -> Void,
        onToggleSubagentExpansion: @escaping (String) -> Void = { _ in },
        onOpenSubagentThread: @escaping (SubagentNavigationTarget) -> Void = { _ in },
        onResolveApproval: @escaping (String, Bool) -> Void
    ) {
        self.threadID = threadID
        self.turn = turn
        self.isLatest = isLatest
        self.streamRoomHeight = streamRoomHeight
        self.showWorking = showWorking
        self.workingRevealAt = workingRevealAt
        self.fadeBubbleID = fadeBubbleID
        self.expandedFoldIDs = expandedFoldIDs
        self.expandedSubagentIDs = expandedSubagentIDs
        self.parentEnvironmentID = parentEnvironmentID
        self.knownEnvironmentIDs = knownEnvironmentIDs
        self.reduceMotion = reduceMotion
        self.onToggleWorkFold = onToggleWorkFold
        self.onToggleSubagentExpansion = onToggleSubagentExpansion
        self.onOpenSubagentThread = onOpenSubagentThread
        self.onResolveApproval = onResolveApproval
    }

    nonisolated static func == (lhs: SendFlightTurnSection, rhs: SendFlightTurnSection) -> Bool {
        lhs.threadID == rhs.threadID
            && lhs.turn == rhs.turn
            && lhs.isLatest == rhs.isLatest
            && lhs.streamRoomHeight == rhs.streamRoomHeight
            && lhs.showWorking == rhs.showWorking
            && lhs.workingRevealAt == rhs.workingRevealAt
            && lhs.fadeBubbleID == rhs.fadeBubbleID
            && lhs.expandedFoldIDs == rhs.expandedFoldIDs
            && lhs.expandedSubagentIDs == rhs.expandedSubagentIDs
            && lhs.parentEnvironmentID == rhs.parentEnvironmentID
            && lhs.knownEnvironmentIDs == rhs.knownEnvironmentIDs
            && lhs.reduceMotion == rhs.reduceMotion
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(turn.rows) { row in
                rowView(row)
            }
            if isLatest && showWorking {
                WorkingIndicatorRow(revealAt: workingRevealAt, reduceMotion: reduceMotion)
                    .id("working:\(turn.id)")
                    .transition(.swftRise(reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: isLatest ? streamRoomHeight : nil, alignment: .top)
        .animation(SwftMotion.resolve(SwftMotion.settle, reduceMotion: reduceMotion), value: showWorking)
    }

    @ViewBuilder private func rowView(_ row: TranscriptRow) -> some View {
        switch row {
        case .user(let id, let text, let attachments):
            let fading = fadeBubbleID == id
            UserBubble(text, attachments: attachments)
                .equatable()
                .padding(.vertical, SendFlightLogic.userRowVerticalPadding)
                .modifier(SentMessageFade(isFading: fading, reduceMotion: reduceMotion))
                .newThreadBubbleProbe(.threadBubble, opacity: fading ? 0 : 1)
        case .assistant(_, let blocks, let streaming):
            AssistantMessage {
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    switch block {
                    case .text(let text):
                        MessageText(text, streaming: streaming && index == blocks.count - 1)
                            .equatable()
                    case .code(let language, let source):
                        CodeBlock(source, language: language)
                            .equatable()
                    case .image(let alt, let source):
                        MessageImage(source: source, alt: alt)
                    case .attachments(let attachments):
                        AttachmentStrip(attachments, trailing: false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .transition(.swftRise(reduceMotion: reduceMotion))
        case .work(let fold):
            WorkFoldView(fold: fold, isExpanded: expandedFoldIDs.contains(fold.id)) {
                onToggleWorkFold(fold.id)
            }
            .transition(.swftRise(reduceMotion: reduceMotion))
        case .subagent(let subagent):
            SubagentSingleRowView(
                item: subagent,
                parentEnvironmentID: parentEnvironmentID,
                knownEnvironmentIDs: knownEnvironmentIDs,
                isExpanded: expandedSubagentIDs.contains(subagent.id),
                onToggleExpansion: onToggleSubagentExpansion,
                onOpenThread: onOpenSubagentThread
            )
            .equatable()
            .transition(.swftRise(reduceMotion: reduceMotion))
        case .subagentGroup(let group):
            SubagentGroupRowView(
                group: group,
                parentEnvironmentID: parentEnvironmentID,
                knownEnvironmentIDs: knownEnvironmentIDs,
                expandedIDs: expandedSubagentIDs,
                onToggleExpansion: onToggleSubagentExpansion,
                onOpenThread: onOpenSubagentThread
            )
            .equatable()
            .transition(.swftRise(reduceMotion: reduceMotion))
        case .approval(let id, let approval):
            ApprovalCard(
                title: approval.title,
                message: approval.message,
                command: approval.command,
                status: approval.status.cardStatus,
                onApprove: { onResolveApproval(id, true) },
                onDeny: { onResolveApproval(id, false) }
            )
            .transition(.swftRise(reduceMotion: reduceMotion))
        case .note(_, let title, let message, let isError):
            QuietNote(title: title, message: message, isError: isError)
                .transition(.swftRise(reduceMotion: reduceMotion))
        }
    }
}

/// Fades a just-sent message in, starting a beat into the scroll that brings its turn into view so it appears as the
/// transcript settles rather than before it moves. The fade belongs to the row, so a scroll the user interrupts never
/// cuts it short.
private struct SentMessageFade: ViewModifier {
    let isFading: Bool
    let reduceMotion: Bool
    @State private var revealed: Bool

    init(isFading: Bool, reduceMotion: Bool) {
        self.isFading = isFading
        self.reduceMotion = reduceMotion
        self._revealed = State(initialValue: !isFading)
    }

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .onAppear {
                guard !revealed else { return }
                withAnimation(reduceMotion ? SwftMotion.reduceMotionFade : SwftMotion.sentMessageFade) {
                    revealed = true
                }
            }
    }
}

/// Test-only sample reported for the first user bubble across Home's launching preview and `ThreadView`'s real row.
struct NewThreadBubbleProbeSample: Equatable {
    enum Source: Equatable {
        case homePreview
        case threadBubble
    }

    let source: Source
    let frameInWindow: CGRect
    let targetOpacity: Double
    let timestamp: CFAbsoluteTime
}

/// Test-only recorder collecting window-space geometry and opacity samples across Home → `ThreadView` handoff.
@MainActor
final class NewThreadBubbleProbe {
    private(set) var samples: [NewThreadBubbleProbeSample] = []

    func record(_ sample: NewThreadBubbleProbeSample) {
        samples.append(sample)
    }
}

private struct NewThreadBubbleProbeModifier: ViewModifier {
    let source: NewThreadBubbleProbeSample.Source
    let opacity: Double
    @Environment(\.newThreadBubbleProbe) private var probe
    @State private var measuredFrame: CGRect = .zero

    func body(content: Content) -> some View {
        if let probe {
            content
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
                    measuredFrame = frame
                    guard frame.width > 0, frame.height > 0 else { return }
                    probe.record(NewThreadBubbleProbeSample(
                        source: source,
                        frameInWindow: frame,
                        targetOpacity: opacity,
                        timestamp: CFAbsoluteTimeGetCurrent()
                    ))
                }
                .onChange(of: opacity) { _, newOpacity in
                    guard measuredFrame.width > 0, measuredFrame.height > 0 else { return }
                    probe.record(NewThreadBubbleProbeSample(
                        source: source,
                        frameInWindow: measuredFrame,
                        targetOpacity: newOpacity,
                        timestamp: CFAbsoluteTimeGetCurrent()
                    ))
                }
        } else {
            content
        }
    }
}

extension View {
    func newThreadBubbleProbe(_ source: NewThreadBubbleProbeSample.Source, opacity: Double) -> some View {
        modifier(NewThreadBubbleProbeModifier(source: source, opacity: opacity))
    }
}

extension EnvironmentValues {
    /// Test-only hook allowing offscreen snapshot tests to force Reduce Motion independently of system Accessibility.
    @Entry var sendFlightForceReduceMotion: Bool = false
    /// Test-only hook observing real window-space bubble geometry and opacity across Home → ThreadView handoff.
    @Entry var newThreadBubbleProbe: NewThreadBubbleProbe? = nil
}

/// Wires geometry, the send scroll, stickiness and thread syncing onto `ThreadView`.
struct ThreadSendFlightHostModifier: ViewModifier {
    let detail: ThreadDetailState
    let rows: [TranscriptRow]
    let isBusy: Bool
    let latestThreadSend: ThreadSendEvent?
    let failedThreadSendID: UUID?
    let reduceMotion: Bool
    let coordinator: SendFlightCoordinator
    @Binding var scrollPosition: ScrollPosition
    @Environment(\.swftScreenHandoff) private var isHandoffScreen

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self, of: \.size) { _, newSize in
                coordinator.updateViewportSize(newSize)
            }
            .onAppear {
                coordinator.scrollDriver.onUserScrollInterrupt = {
                    coordinator.handleUserScrollInterrupt()
                }
                coordinator.syncThread(detail: detail, rows: rows, isBusy: isBusy)
                let action = coordinator.adoptOnAppear(
                    latestThreadSend,
                    detail: detail,
                    rows: rows,
                    isHandoffScreen: isHandoffScreen
                )
                perform(action)
            }
            .onChange(of: detail.summary.id) { _, _ in
                coordinator.syncThread(detail: detail, rows: rows, isBusy: isBusy)
                if !coordinator.scrollDriver.scrollToBottomImmediately() {
                    scrollPosition.scrollTo(edge: .bottom)
                }
            }
            .onChange(of: rows.map(\.id)) { _, _ in
                coordinator.syncThread(detail: detail, rows: rows, isBusy: isBusy)
            }
            .onChange(of: detail.isRunning) { _, _ in
                coordinator.syncThread(detail: detail, rows: rows, isBusy: isBusy)
            }
            .onChange(of: isBusy) { _, _ in
                coordinator.syncThread(detail: detail, rows: rows, isBusy: isBusy)
            }
            .onChange(of: latestThreadSend) { _, event in
                guard let event else { return }
                let action = coordinator.beginSend(event, detail: detail, rows: rows)
                coordinator.syncThread(detail: detail, rows: rows, isBusy: isBusy)
                perform(action)
            }
            .onChange(of: failedThreadSendID) { _, failedID in
                guard let failedID else { return }
                coordinator.failSend(failedID)
            }
            .onDisappear {
                coordinator.scrollDriver.detach()
            }
    }

    /// Scrolls down to the new turn's stream room. The display-synced driver keeps the glide smooth; SwiftUI's
    /// `ScrollPosition` is only the fallback before the `NSScrollView` is attached.
    private func perform(_ action: ThreadSendAction) {
        guard case .scrollToNewTurn(let preJumpY) = action else { return }
        let driver = coordinator.scrollDriver
        if reduceMotion {
            if !driver.scrollToBottomImmediately() {
                scrollPosition.scrollTo(edge: .bottom)
            }
            return
        }
        let started = driver.animateToBottom(duration: SendFlightTiming.sendDuration, preJumpY: preJumpY) {
            if coordinator.finishSendScroll() {
                driver.animateToBottom(duration: SendFlightTiming.settleDuration)
            }
        }
        if !started {
            if let preJumpY { scrollPosition.scrollTo(y: preJumpY) }
            withAnimation(SwftMotion.send) { scrollPosition.scrollTo(edge: .bottom) }
        }
    }
}

extension View {
    func threadSendFlightHost(
        detail: ThreadDetailState,
        rows: [TranscriptRow],
        isBusy: Bool,
        latestThreadSend: ThreadSendEvent?,
        failedThreadSendID: UUID?,
        reduceMotion: Bool,
        coordinator: SendFlightCoordinator,
        scrollPosition: Binding<ScrollPosition>
    ) -> some View {
        modifier(ThreadSendFlightHostModifier(
            detail: detail,
            rows: rows,
            isBusy: isBusy,
            latestThreadSend: latestThreadSend,
            failedThreadSendID: failedThreadSendID,
            reduceMotion: reduceMotion,
            coordinator: coordinator,
            scrollPosition: scrollPosition
        ))
    }

    /// Attaches Studio-style scroll geometry and user-scroll-phase tracking to the thread `ScrollView`.
    func threadSendFlightScrollTracking(
        coordinator: SendFlightCoordinator,
        isSendPending: Bool,
        scrollPosition: Binding<ScrollPosition>
    ) -> some View {
        self
            .onScrollPhaseChange { _, newPhase in
                coordinator.handleScrollPhaseChange(to: newPhase)
            }
            .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
                ScrollMetrics(
                    offsetY: max(0, geometry.visibleRect.minY),
                    contentHeight: geometry.contentSize.height,
                    viewportHeight: geometry.visibleRect.height
                )
            } action: { _, metrics in
                // SwiftUI reports growth before AppKit resizes the document view, so pin through SwiftUI; the
                // driver would scroll to the stale end and miss the last chunk of a reply.
                if coordinator.handleScrollGeometryChange(metrics, isSendPending: isSendPending) {
                    scrollPosition.wrappedValue.scrollTo(edge: .bottom)
                }
            }
    }
}
