import SwftDesign
import SwiftUI

/// Renders the J-shaped send flight overlay. The flight and the transcript's scroll start in one transaction and run on
/// SwiftUI's own animation clock: the bubble interpolates `progress` (only it re-renders per frame) while
/// `ScrollPosition` animates to the new end with the same 680ms send curve. Nothing mutates state per frame.
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
            withAnimation(SwftMotion.send) {
                scrollPosition.scrollTo(edge: .bottom)
            }
        }
    }
}

/// Renders one conversation turn inside `ThreadView`, applying stream-room height to the latest turn
/// and showing the delayed "Working" indicator when the latest turn is awaiting agent output.
struct SendFlightTurnSection<RowContent: View>: View {
    let detail: ThreadDetailState
    let turn: TranscriptTurn
    let isLatest: Bool
    let streamRoomHeight: CGFloat?
    let showWorking: Bool
    /// The latest turn's non-user rows wait, hidden, while its prompt flies up; they fade and rise in together.
    let holdsRows: Bool
    /// A just-sent row whose flight starts next frame; hidden now so it never flashes in place.
    let pendingFlightRowID: String?
    let coordinator: SendFlightCoordinator
    let reduceMotion: Bool
    @ViewBuilder let rowContent: (TranscriptRow) -> RowContent

    var body: some View {
        let held = isLatest && holdsRows
        VStack(alignment: .leading, spacing: 16) {
            ForEach(turn.rows) { row in
                rowView(row, held: held)
            }
            if isLatest && showWorking {
                WorkingIndicatorRow(delay: 0, reduceMotion: effectiveReduceMotion)
                    .id("working:\(turn.id)")
                    .transition(.swftRise(reduceMotion: effectiveReduceMotion))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: isLatest ? streamRoomHeight : nil, alignment: .top)
        .animation(SwftMotion.resolve(SwftMotion.settle, reduceMotion: effectiveReduceMotion), value: showWorking)
        .animation(SwftMotion.resolve(SwftMotion.settle, reduceMotion: effectiveReduceMotion), value: held)
    }

    @Environment(\.sendFlightForceReduceMotion) private var forceReduceMotion
    private var effectiveReduceMotion: Bool { reduceMotion || forceReduceMotion }

    @ViewBuilder private func rowView(_ row: TranscriptRow, held: Bool) -> some View {
        if case .user(let id, _) = row {
            let hidden = coordinator.isBubbleHiddenForFlight(rowID: id, in: detail, pendingRowID: pendingFlightRowID)
            rowContent(row)
                .sendFlightBubbleTarget(id: hidden ? id : nil)
                .opacity(hidden ? 0 : 1)
                .modifier(ReduceMotionSendFadeModifier(
                    active: reduceMotion && coordinator.reduceMotionFadeBubbleID == id
                ))
        } else {
            rowContent(row)
                .opacity(held ? 0 : 1)
                .offset(y: held ? 8 : 0)
                .transition(.swftRise(reduceMotion: reduceMotion))
        }
    }
}

private struct ReduceMotionSendFadeModifier: ViewModifier {
    let active: Bool
    @State private var revealed: Bool

    init(active: Bool) {
        self.active = active
        self._revealed = State(initialValue: !active)
    }

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .onAppear {
                guard active, !revealed else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    revealed = true
                }
            }
    }
}

extension EnvironmentValues {
    /// Test-only hook allowing offscreen snapshot tests to pin an active send flight to an exact normalized time.
    @Entry var sendFlightPinnedProgress: Double? = nil
    /// Test-only hook allowing offscreen snapshot tests to force Reduce Motion independently of system Accessibility.
    @Entry var sendFlightForceReduceMotion: Bool = false
}

/// Wires send-flight coordinate space, geometry observers, scroll phase/stickiness, and flight overlay onto `ThreadView`.
struct ThreadSendFlightHostModifier: ViewModifier {
    let detail: ThreadDetailState
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
                coordinator.syncThread(detail: detail, isBusy: isBusy)
                // Home → new thread: the first message flies out of the docked composer this screen took over.
                let action = coordinator.adoptOnAppear(
                    latestThreadSend,
                    detail: detail,
                    isHandoffScreen: isHandoffScreen,
                    reduceMotion: effectiveReduceMotion
                )
                if action == .startFlight, let pinnedProgress {
                    coordinator.pinActiveFlightProgress(pinnedProgress)
                }
            }
            .onChange(of: detail.summary.id) { _, _ in
                coordinator.syncThread(detail: detail, isBusy: isBusy)
                scrollPosition.scrollTo(edge: .bottom)
            }
            .onChange(of: coordinator.settleToBottomToken) { _, _ in
                withAnimation(SwftMotion.resolve(SwftMotion.settle, reduceMotion: effectiveReduceMotion)) {
                    scrollPosition.scrollTo(edge: .bottom)
                }
            }
            .onChange(of: detail.rows.map(\.id)) { _, _ in
                coordinator.syncThread(detail: detail, isBusy: isBusy)
            }
            .onChange(of: detail.isRunning) { _, _ in
                coordinator.syncThread(detail: detail, isBusy: isBusy)
            }
            .onChange(of: isBusy) { _, _ in
                coordinator.syncThread(detail: detail, isBusy: isBusy)
            }
            .onChange(of: latestThreadSend) { _, event in
                guard let event else { return }
                let jump = coordinator.preFlightJumpOffset()
                let action = coordinator.beginSend(event, detail: detail, reduceMotion: effectiveReduceMotion)
                coordinator.syncThread(detail: detail, isBusy: isBusy)
                switch action {
                case .startFlight:
                    if let pinnedProgress {
                        coordinator.pinActiveFlightProgress(pinnedProgress)
                    } else if let jump {
                        scrollPosition.scrollTo(y: jump)
                    }
                case .instantAnchor:
                    scrollPosition.scrollTo(edge: .bottom)
                case .none:
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
            }
    }
}

extension View {
    func threadSendFlightHost(
        detail: ThreadDetailState,
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
                if coordinator.handleScrollGeometryChange(metrics) {
                    scrollPosition.wrappedValue.scrollTo(edge: .bottom)
                }
            }
    }
}
