import SwftDesign
import SwiftUI

/// Renders the J-shaped send flight overlay for in-thread sends. The overlay bubble interpolates `progress` on
/// SwiftUI's animation clock while `SendFlightScrollDriver` drives the underlying `NSScrollView` in lockstep over the
/// same 680ms `CubicBezierCurve.send` curve at native display refresh rate (60/120Hz). Nothing mutates observed state
/// per frame.
struct SendFlightOverlayLayer: View {
    let coordinator: SendFlightCoordinator
    let topInset: CGFloat
    let bottomInset: CGFloat
    @Binding var scrollPosition: ScrollPosition

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if let flight = coordinator.activeFlight {
                SendFlightFlyer(
                    flight: flight,
                    coordinator: coordinator,
                    topInset: topInset,
                    bottomInset: bottomInset,
                    scrollPosition: $scrollPosition
                )
                .id(flight.id)
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct SendFlightFlyer: View {
    let flight: ActiveSendFlight
    let coordinator: SendFlightCoordinator
    let topInset: CGFloat
    let bottomInset: CGFloat
    @Binding var scrollPosition: ScrollPosition
    @State private var progress: Double = 0

    var body: some View {
        let target = coordinator.landingFrame(for: flight, topInset: topInset, bottomInset: bottomInset)
        let path = SendFlightPath.make(composerFrame: coordinator.launchFrame(for: flight), targetFrame: target)
        SendFlightOverlayBubble(
            text: flight.text,
            attachments: flight.attachments,
            maxWidth: coordinator.maxBubbleWidth(for: flight),
            path: path,
            progress: flight.pinnedProgress ?? progress
        )
        .onAppear {
            guard flight.pinnedProgress == nil else { return }
            let id = flight.id
            withAnimation(.linear(duration: SendFlightTiming.sendDuration)) {
                progress = 1
            } completion: {
                coordinator.finishFlightIfMatching(id)
            }
            if !coordinator.scrollDriver.animateToBottom(
                duration: SendFlightTiming.sendDuration,
                curve: .send,
                preJumpY: flight.preFlightJumpY
            ) {
                if let jump = flight.preFlightJumpY {
                    scrollPosition.scrollTo(y: jump)
                }
                withAnimation(SwftMotion.send) {
                    scrollPosition.scrollTo(edge: .bottom)
                }
            }
        }
    }
}

/// Fade-in cadence for a user bubble appearing directly in place (no J-curve flight).
enum SendBubbleFadeStyle: Equatable, Sendable {
    case none
    /// In-thread send under Reduce Motion.
    case reduceMotion

    var animation: Animation {
        switch self {
        case .none: .linear(duration: 0)
        case .reduceMotion: .easeInOut(duration: 0.18)
        }
    }
}

/// Renders one conversation turn inside `ThreadView`, applying stream-room height to the latest turn
/// and showing the delayed "Working" indicator when the latest turn is awaiting agent output.
///
/// Conforms to `Equatable` over plain value inputs so historical turns skip body re-evaluation during send flights,
/// live server streaming updates, and work-fold toggles in other turns.
struct SendFlightTurnSection: View, Equatable {
    let threadID: String
    let turn: TranscriptTurn
    let isLatest: Bool
    let streamRoomHeight: CGFloat?
    let showWorking: Bool
    /// The latest turn's non-user rows wait, hidden, while its prompt flies up or fades in; they fade and rise in together.
    let holdsRows: Bool
    /// The user bubble currently represented by an active/pending send flight overlay.
    let hiddenBubbleID: String?
    /// The user bubble fading cleanly in place (Home handoff or Reduce Motion in-thread send).
    let fadeBubbleID: String?
    let fadeStyle: SendBubbleFadeStyle
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
        holdsRows: Bool,
        hiddenBubbleID: String?,
        fadeBubbleID: String?,
        fadeStyle: SendBubbleFadeStyle,
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
        self.holdsRows = holdsRows
        self.hiddenBubbleID = hiddenBubbleID
        self.fadeBubbleID = fadeBubbleID
        self.fadeStyle = fadeStyle
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
            && lhs.holdsRows == rhs.holdsRows
            && lhs.hiddenBubbleID == rhs.hiddenBubbleID
            && lhs.fadeBubbleID == rhs.fadeBubbleID
            && lhs.fadeStyle == rhs.fadeStyle
            && lhs.expandedFoldIDs == rhs.expandedFoldIDs
            && lhs.expandedSubagentIDs == rhs.expandedSubagentIDs
            && lhs.parentEnvironmentID == rhs.parentEnvironmentID
            && lhs.knownEnvironmentIDs == rhs.knownEnvironmentIDs
            && lhs.reduceMotion == rhs.reduceMotion
    }

    var body: some View {
        let held = isLatest && holdsRows
        VStack(alignment: .leading, spacing: 16) {
            ForEach(turn.rows) { row in
                rowView(row, held: held)
            }
            if isLatest && showWorking {
                WorkingIndicatorRow(delay: 0, reduceMotion: reduceMotion)
                    .id("working:\(turn.id)")
                    .transition(.swftRise(reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: isLatest ? streamRoomHeight : nil, alignment: .top)
        .animation(SwftMotion.resolve(SwftMotion.settle, reduceMotion: reduceMotion), value: showWorking)
        .animation(SwftMotion.resolve(SwftMotion.settle, reduceMotion: reduceMotion), value: held)
    }

    @ViewBuilder private func rowView(_ row: TranscriptRow, held: Bool) -> some View {
        switch row {
        case .user(let id, let text, let attachments):
            let hidden = hiddenBubbleID == id
            let rowFadeStyle: SendBubbleFadeStyle = (fadeBubbleID == id) ? fadeStyle : .none
            UserBubble(text, attachments: attachments)
                .equatable()
                .padding(.vertical, SendFlightLogic.userRowVerticalPadding)
                .sendFlightBubbleTarget(id: hidden ? id : nil)
                .opacity(hidden ? 0 : 1)
                .modifier(SendBubbleFadeModifier(style: rowFadeStyle))
                .newThreadBubbleProbe(
                    .threadBubble,
                    opacity: hidden ? 0 : (rowFadeStyle == .none ? 1 : 0)
                )
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
            .opacity(held ? 0 : 1)
            .offset(y: held ? 8 : 0)
            .transition(.swftRise(reduceMotion: reduceMotion))
        case .work(let fold):
            WorkFoldView(fold: fold, isExpanded: expandedFoldIDs.contains(fold.id)) {
                onToggleWorkFold(fold.id)
            }
            .opacity(held ? 0 : 1)
            .offset(y: held ? 8 : 0)
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
            .opacity(held ? 0 : 1)
            .offset(y: held ? 8 : 0)
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
            .opacity(held ? 0 : 1)
            .offset(y: held ? 8 : 0)
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
            .opacity(held ? 0 : 1)
            .offset(y: held ? 8 : 0)
            .transition(.swftRise(reduceMotion: reduceMotion))
        case .note(_, let title, let message, let isError):
            QuietNote(title: title, message: message, isError: isError)
                .opacity(held ? 0 : 1)
                .offset(y: held ? 8 : 0)
                .transition(.swftRise(reduceMotion: reduceMotion))
        }
    }
}

private struct SendBubbleFadeModifier: ViewModifier {
    let style: SendBubbleFadeStyle
    @State private var revealed: Bool

    init(style: SendBubbleFadeStyle) {
        self.style = style
        self._revealed = State(initialValue: style == .none)
    }

    func body(content: Content) -> some View {
        content
            .opacity(style == .none || revealed ? 1 : 0)
            .onAppear {
                guard style != .none, !revealed else { return }
                withAnimation(style.animation) {
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
    /// Test-only hook allowing offscreen snapshot tests to pin an active send flight to an exact normalized time.
    @Entry var sendFlightPinnedProgress: Double? = nil
    /// Test-only hook allowing offscreen snapshot tests to force Reduce Motion independently of system Accessibility.
    @Entry var sendFlightForceReduceMotion: Bool = false
    /// Test-only hook observing real window-space bubble geometry and opacity across Home → ThreadView handoff.
    @Entry var newThreadBubbleProbe: NewThreadBubbleProbe? = nil
}

/// Wires send-flight coordinate space, geometry observers, scroll phase/stickiness, and flight overlay onto `ThreadView`.
struct ThreadSendFlightHostModifier: ViewModifier {
    let detail: ThreadDetailState
    let rows: [TranscriptRow]
    let isBusy: Bool
    let latestThreadSend: ThreadSendEvent?
    let failedThreadSendID: UUID?
    let topInset: CGFloat
    let bottomInset: CGFloat
    let reduceMotion: Bool
    let coordinator: SendFlightCoordinator
    @Binding var scrollPosition: ScrollPosition
    @Environment(\.sendFlightPinnedProgress) private var pinnedProgress
    @Environment(\.sendFlightForceReduceMotion) private var forceReduceMotion
    @Environment(\.swftScreenHandoff) private var isHandoffScreen

    private var effectiveReduceMotion: Bool { reduceMotion || forceReduceMotion }

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: SendFlightCoordinateSpace.name)
            .onGeometryChange(for: CGSize.self, of: \.size) { _, newSize in
                coordinator.updateViewportSize(newSize)
            }
            .onSendFlightComposerFrameChange { frame in
                coordinator.updateComposerFrame(frame)
            }
            .onSendFlightBubbleFramesChange { frames in
                coordinator.updateBubbleFrames(frames)
            }
            .overlay {
                SendFlightOverlayLayer(
                    coordinator: coordinator,
                    topInset: topInset,
                    bottomInset: bottomInset,
                    scrollPosition: $scrollPosition
                )
            }
            .onAppear {
                coordinator.scrollDriver.onUserScrollInterrupt = {
                    if coordinator.isFlightAnimating {
                        withAnimation(.easeOut(duration: 0.16)) {
                            _ = coordinator.handleUserScrollInterrupt()
                        }
                    } else {
                        _ = coordinator.handleUserScrollInterrupt()
                    }
                }
                coordinator.syncThread(detail: detail, rows: rows, isBusy: isBusy)
                // Home → new thread: Home already faded the first message in while docking; adopt stream room in place.
                let action = coordinator.adoptOnAppear(
                    latestThreadSend,
                    detail: detail,
                    rows: rows,
                    isHandoffScreen: isHandoffScreen,
                    reduceMotion: effectiveReduceMotion
                )
                if action == .startFlight, let pinnedProgress {
                    coordinator.pinActiveFlightProgress(pinnedProgress)
                }
            }
            .onChange(of: detail.summary.id) { _, _ in
                coordinator.syncThread(detail: detail, rows: rows, isBusy: isBusy)
                if !coordinator.scrollDriver.scrollToBottomImmediately() {
                    scrollPosition.scrollTo(edge: .bottom)
                }
            }
            .onChange(of: coordinator.settleToBottomToken) { _, _ in
                if effectiveReduceMotion {
                    if !coordinator.scrollDriver.scrollToBottomImmediately() {
                        scrollPosition.scrollTo(edge: .bottom)
                    }
                } else if !coordinator.scrollDriver.animateToBottom(
                    duration: SendFlightTiming.settleDuration,
                    curve: .settle
                ) {
                    withAnimation(SwftMotion.settle) {
                        scrollPosition.scrollTo(edge: .bottom)
                    }
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
                let action = coordinator.beginSend(event, detail: detail, rows: rows, reduceMotion: effectiveReduceMotion)
                coordinator.syncThread(detail: detail, rows: rows, isBusy: isBusy)
                switch action {
                case .startFlight:
                    if let pinnedProgress {
                        coordinator.pinActiveFlightProgress(pinnedProgress)
                    }
                case .instantAnchor:
                    if !coordinator.scrollDriver.scrollToBottomImmediately() {
                        scrollPosition.scrollTo(edge: .bottom)
                    }
                case .handoff, .none:
                    break
                }
            }
            .onChange(of: pinnedProgress) { _, newProgress in
                if let newProgress {
                    coordinator.pinActiveFlightProgress(newProgress)
                }
            }
            .onChange(of: failedThreadSendID) { _, failedID in
                guard let failedID else { return }
                coordinator.failSend(failedID)
            }
            .onDisappear {
                coordinator.cancelFlight(clearPendingStreamRoom: true)
                coordinator.scrollDriver.detach()
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
        topInset: CGFloat,
        bottomInset: CGFloat,
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
            topInset: topInset,
            bottomInset: bottomInset,
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
            .onScrollPhaseChange { oldPhase, newPhase in
                // A gesture mid-flight hands the scroll back to the user; the real bubble fades in where it is.
                if coordinator.isFlightAnimating {
                    withAnimation(.easeOut(duration: 0.16)) {
                        _ = coordinator.handleScrollPhaseChange(from: oldPhase, to: newPhase)
                    }
                } else {
                    coordinator.handleScrollPhaseChange(from: oldPhase, to: newPhase)
                }
            }
            .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
                ScrollMetrics(
                    offsetY: max(0, geometry.visibleRect.minY),
                    contentHeight: geometry.contentSize.height,
                    viewportHeight: geometry.visibleRect.height
                )
            } action: { _, metrics in
                if coordinator.handleScrollGeometryChange(metrics, isSendPending: isSendPending) {
                    if !coordinator.scrollDriver.scrollToBottomImmediately() {
                        scrollPosition.wrappedValue.scrollTo(edge: .bottom)
                    }
                }
            }
    }
}
