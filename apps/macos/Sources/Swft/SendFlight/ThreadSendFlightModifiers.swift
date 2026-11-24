import SwftDesign
import SwiftUI

/// Renders the J-shaped send flight overlay and keeps `ScrollPosition` locked to the same 680ms cubic-bezier clock.
struct SendFlightOverlayLayer: View {
    let coordinator: SendFlightCoordinator
    let topInset: CGFloat
    @Binding var scrollPosition: ScrollPosition

    var body: some View {
        if coordinator.activeFlight != nil {
            TimelineView(.animation(paused: !coordinator.isFlightAnimating)) { context in
                SendFlightOverlayFrameView(
                    coordinator: coordinator,
                    now: context.date,
                    topInset: topInset,
                    scrollPosition: $scrollPosition
                )
            }
            .allowsHitTesting(false)
        }
    }
}

private struct SendFlightOverlayFrameView: View {
    let coordinator: SendFlightCoordinator
    let now: Date
    let topInset: CGFloat
    @Binding var scrollPosition: ScrollPosition

    var body: some View {
        let frame = coordinator.evaluateFlightFrame(at: now, topInset: topInset)
        ZStack(alignment: .topLeading) {
            Color.clear
            if let frame {
                SendFlightOverlayBubble(
                    text: frame.text,
                    maxWidth: frame.maxWidth,
                    sample: frame.sample
                )
            }
        }
        .onChange(of: now) { _, tick in
            driveFlightTick(at: tick)
        }
        .onChange(of: coordinator.activeFlight?.pinnedProgress) { _, _ in
            driveFlightTick(at: now)
        }
        .onChange(of: coordinator.stickiness.lastMetrics.contentHeight) { _, _ in
            if coordinator.activeFlight?.pinnedProgress != nil {
                driveFlightTick(at: now)
            }
        }
        .onAppear {
            driveFlightTick(at: now)
        }
    }

    private func driveFlightTick(at tick: Date) {
        guard let flightID = coordinator.activeFlight?.id,
              let frame = coordinator.evaluateFlightFrame(at: tick, topInset: topInset)
        else { return }

        if let scrollY = frame.scrollTargetY {
            scrollPosition.scrollTo(y: scrollY)
        }
        if frame.isComplete {
            if coordinator.finishFlightIfMatching(flightID) {
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
    let coordinator: SendFlightCoordinator
    let reduceMotion: Bool
    @ViewBuilder let rowContent: (TranscriptRow) -> RowContent

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(turn.rows) { row in
                rowView(row)
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
    }

    @Environment(\.sendFlightForceReduceMotion) private var forceReduceMotion
    private var effectiveReduceMotion: Bool { reduceMotion || forceReduceMotion }

    @ViewBuilder private func rowView(_ row: TranscriptRow) -> some View {
        if case .user(let id, _) = row {
            rowContent(row)
                .sendFlightBubbleTarget(id: id)
                .opacity(coordinator.isBubbleHiddenForFlight(rowID: id, in: detail) ? 0 : 1)
                .modifier(ReduceMotionSendFadeModifier(
                    active: reduceMotion && coordinator.reduceMotionFadeBubbleID == id
                ))
        } else {
            rowContent(row)
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
    let reduceMotion: Bool
    let coordinator: SendFlightCoordinator
    @Binding var scrollPosition: ScrollPosition
    @Environment(\.sendFlightPinnedProgress) private var pinnedProgress
    @Environment(\.sendFlightForceReduceMotion) private var forceReduceMotion

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
                    scrollPosition: $scrollPosition
                )
            }
            .onAppear {
                coordinator.syncThread(detail: detail, isBusy: isBusy)
            }
            .onChange(of: detail.summary.id) { _, _ in
                coordinator.syncThread(detail: detail, isBusy: isBusy)
                scrollPosition.scrollTo(edge: .bottom)
            }
            .onChange(of: coordinator.snapToBottomToken) { _, _ in
                scrollPosition.scrollTo(edge: .bottom)
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
                let action = coordinator.beginSend(event, detail: detail, reduceMotion: effectiveReduceMotion)
                coordinator.syncThread(detail: detail, isBusy: isBusy)
                if action == .startFlight, let pinnedProgress {
                    coordinator.pinActiveFlightProgress(pinnedProgress)
                }
                if action == .instantAnchor {
                    scrollPosition.scrollTo(edge: .bottom)
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
                coordinator.handleScrollPhaseChange(from: oldPhase, to: newPhase)
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
