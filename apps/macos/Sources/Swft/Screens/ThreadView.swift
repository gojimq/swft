import SwftDesign
import SwiftUI

struct ThreadView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sendFlightForceReduceMotion) private var forceReduceMotion
    @Environment(\.swftScreenHandoff) private var isHandoffScreen
    let detail: ThreadDetailState
    /// Keeps the floating bottom composer rooted when switching directly from another thread so only the
    /// transcript transitions instead of blinking the shared input capsule.
    let anchorsComposer: Bool
    @State private var scrollPosition = ScrollPosition()
    @State private var composerHeight: CGFloat = 110
    @State private var sendFlight = SendFlightCoordinator()
    /// Rows animate in only once the transcript has content; its first population (or a snapshot arriving after a
    /// thread switch) lands in place instead of every row rising at once.
    @State private var populated = false
    /// The image open in the lightbox, if any.
    @State private var imagePreview: SwftImagePreview?

    init(
        detail: ThreadDetailState,
        anchorsComposer: Bool = false,
        initialImagePreview: SwftImagePreview? = nil
    ) {
        self.detail = detail
        self.anchorsComposer = anchorsComposer
        _imagePreview = State(initialValue: initialImagePreview)
    }

    nonisolated static let topInset = SwftLayout.titlebarHeight + 24

    private var effectiveReduceMotion: Bool { reduceMotion || forceReduceMotion }

    var body: some View {
        let rows = detail.rows
        let turns = SendFlightLogic.turns(from: rows)
        // One inset drives the transcript's padding, the stream room and the flight's landing, so a sent prompt
        // lands exactly where its real bubble rests.
        let topInset = Self.topInset
        let bottomInset = composerHeight + 28
        let isBusy = model.isComposerBusy
        let latestSend = model.latestThreadSend
        let isSendPending = sendFlight.isSendPending(latestSend, in: detail)
        let hasStreamRoom = sendFlight.hasStreamRoom(for: detail, rows: rows, isBusy: isBusy, latestSend: latestSend)
        let streamRoom = hasStreamRoom
            ? SendFlightLogic.streamRoomHeight(viewportHeight: sendFlight.viewportSize.height, topInset: topInset, bottomInset: bottomInset)
            : nil
        let showWorking = sendFlight.shouldShowWorking(
            for: detail,
            isBusy: isBusy,
            latestTurnRows: turns.last?.rows ?? [],
            latestSend: latestSend,
            isHandoffScreen: isHandoffScreen,
            reduceMotion: effectiveReduceMotion
        )
        let holdsLatestTurn = sendFlight.holdsLatestTurn(
            for: detail,
            latestSend: latestSend,
            isHandoffScreen: isHandoffScreen,
            reduceMotion: effectiveReduceMotion
        )
        let pendingFlightRowID = sendFlight.pendingFlightRowID(
            latestSend: latestSend,
            in: detail,
            rows: rows,
            reduceMotion: effectiveReduceMotion
        )
        let hiddenBubbleID = sendFlight.activeHiddenFlightBubbleID(
            in: detail,
            rows: rows,
            pendingRowID: pendingFlightRowID
        )
        let (fadeBubbleID, fadeStyle): (String?, SendBubbleFadeStyle) = {
            if effectiveReduceMotion, let rmID = sendFlight.reduceMotionFadeBubbleID, !rmID.isEmpty {
                return (rmID, .reduceMotion)
            }
            return (nil, .none)
        }()
        // The send's own row insertion and active scroll flight land without a LazyVStack layout animation:
        // the flight and display-synced scroll carry that motion cleanly without fighting layout.
        let animatesRows = populated && !isSendPending && !sendFlight.isFlightAnimating
        let expandedWorkFolds = model.expandedWorkFolds
        let expandedSubagentRows = model.expandedSubagentRows
        let knownEnvironmentIDs = model.knownEnvironmentIDs
        let threadID = detail.summary.id
        let parentEnvironmentID = detail.summary.environmentID ?? model.activeThreadEnvironmentID
        let subagentItems: [SubagentItem] = detail.items.compactMap {
            if case .subagent(let item) = $0.kind { item } else { nil }
        }

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                ForEach(Array(turns.enumerated()), id: \.element.id) { index, turn in
                    let isLatest = index == turns.count - 1
                    SendFlightTurnSection(
                        threadID: threadID,
                        turn: turn,
                        isLatest: isLatest,
                        streamRoomHeight: isLatest ? streamRoom : nil,
                        showWorking: isLatest && showWorking,
                        holdsRows: isLatest && holdsLatestTurn,
                        hiddenBubbleID: isLatest ? hiddenBubbleID : nil,
                        fadeBubbleID: isLatest ? fadeBubbleID : nil,
                        fadeStyle: isLatest ? fadeStyle : .none,
                        expandedFoldIDs: Self.expandedFoldIDs(for: turn, in: expandedWorkFolds),
                        expandedSubagentIDs: Self.expandedSubagentIDs(for: turn, in: expandedSubagentRows),
                        parentEnvironmentID: parentEnvironmentID,
                        knownEnvironmentIDs: knownEnvironmentIDs,
                        reduceMotion: effectiveReduceMotion,
                        onToggleWorkFold: { foldID in
                            sendFlight.handleWorkFoldToggle()
                            withAnimation(SwftMotion.resolve(SwftMotion.disclosure, reduceMotion: effectiveReduceMotion)) {
                                model.toggleWorkFold(foldID)
                            }
                        },
                        onToggleSubagentExpansion: { subagentRowID in
                            sendFlight.handleWorkFoldToggle()
                            withAnimation(SwftMotion.resolve(SwftMotion.disclosure, reduceMotion: effectiveReduceMotion)) {
                                model.toggleSubagentRow(subagentRowID)
                            }
                        },
                        onOpenSubagentThread: { target in
                            let matchedItem = subagentItems.first {
                                $0.childThreadID == target.threadID || $0.remoteThreadID == target.threadID
                            }
                            withAnimation(SwftMotion.resolve(SwftMotion.screen, reduceMotion: effectiveReduceMotion)) {
                                _ = model.openSubagentInRightPanel(target, item: matchedItem, for: threadID)
                            }
                        },
                        onResolveApproval: { itemID, approved in
                            model.resolveApproval(itemID: itemID, in: threadID, approved: approved)
                        }
                    )
                    .equatable()
                }
            }
            .frame(maxWidth: SwftLayout.contentMaxWidth)
            .padding(.horizontal, 32)
            .padding(.top, topInset)
            // Room for the floating composer, so the latest message rests above it rather than under the glass.
            .padding(.bottom, bottomInset)
            .frame(maxWidth: .infinity)
            .swftEntrance(
                reduceMotion: effectiveReduceMotion,
                distance: SwftMotion.threadSwitchOffset,
                animation: SwftMotion.threadSwitch,
                ready: !rows.isEmpty,
                bypass: isSendPending || sendFlight.isFlightAnimating
            )
            .swftOverlayScrollbars()
            .background(SendFlightScrollAnchor(driver: sendFlight.scrollDriver).frame(width: 0, height: 0))
            .animation(animatesRows ? SwftMotion.resolve(SwftMotion.settle, reduceMotion: effectiveReduceMotion) : nil, value: rows.map(\.id))
        }
        .task(id: rows.isEmpty) { if !rows.isEmpty { populated = true } }
        .scrollPosition($scrollPosition)
        // Open at the latest message and follow growth via stickiness, keeping short threads top-aligned.
        .defaultScrollAnchor(.top, for: .alignment)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.top, for: .sizeChanges)
        .threadSendFlightScrollTracking(coordinator: sendFlight, isSendPending: isSendPending, scrollPosition: $scrollPosition)
        .scrollEdgeSoftIfAvailable()
        // The macOS 26 toolbar reports a taller top safe area; the transcript already pads under the top bar itself.
        .ignoresSafeArea(.container, edges: .top)
        // The composer floats over the transcript; the transcript keeps scrolling underneath its glass.
        .overlay(alignment: .bottom) {
            composerBar
                .swftEntrance(
                    reduceMotion: effectiveReduceMotion,
                    distance: SwftMotion.threadSwitchOffset,
                    animation: SwftMotion.threadSwitch,
                    bypass: anchorsComposer
                )
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                    let quantized = (height * 2).rounded() / 2
                    sendFlight.recordMeasuredComposerHeight(quantized)
                    // Avoid re-rendering the transcript every frame while a multi-line composer or attachment tray
                    // collapses during a send flight; the settled height flushes when the flight finishes.
                    if !sendFlight.isFlightAnimating, abs(quantized - composerHeight) >= 0.5 {
                        composerHeight = quantized
                    }
                }
        }
        .onChange(of: sendFlight.isFlightAnimating) { _, animating in
            if !animating, let measured = sendFlight.latestMeasuredComposerHeight, abs(measured - composerHeight) >= 0.5 {
                composerHeight = measured
            }
        }
        .threadSendFlightHost(
            detail: detail,
            rows: rows,
            isBusy: isBusy,
            latestThreadSend: latestSend,
            failedThreadSendID: model.failedThreadSendID,
            topInset: topInset,
            bottomInset: bottomInset,
            reduceMotion: effectiveReduceMotion,
            coordinator: sendFlight,
            scrollPosition: $scrollPosition
        )
        .environment(\.swftImagePreviewAction, SwftImagePreviewAction { [binding = $imagePreview] preview in
            binding.wrappedValue = preview
        })
        .overlay {
            if let imagePreview {
                SwftImageLightbox(preview: imagePreview) { self.imagePreview = nil }
                    .id(imagePreview.id)
            }
        }
        // Transcript, flight overlay and lightbox all resolve images through this thread's own environment.
        .environment(\.swftImageLoader, model.imageLoader(forThreadID: detail.summary.id))
        .onChange(of: subagentItems) { _, updated in
            model.rightPanel.syncSubagentTabs(
                from: updated,
                parentEnvironmentID: parentEnvironmentID,
                for: threadID
            )
        }
    }

    private static func expandedFoldIDs(for turn: TranscriptTurn, in expanded: Set<String>) -> Set<String> {
        guard !expanded.isEmpty else { return [] }
        var matched: Set<String> = []
        for row in turn.rows {
            if let foldID = row.workFoldID, expanded.contains(foldID) {
                matched.insert(foldID)
            }
        }
        return matched
    }

    private static func expandedSubagentIDs(for turn: TranscriptTurn, in expanded: Set<String>) -> Set<String> {
        guard !expanded.isEmpty else { return [] }
        var matched: Set<String> = []
        for row in turn.rows {
            for id in row.subagentDisclosureIDs where expanded.contains(id) {
                matched.insert(id)
            }
        }
        return matched
    }

    private var composerBar: some View {
        VStack(spacing: 8) {
            if let actionError = model.actionError {
                ActionErrorBanner(message: actionError) {
                    model.actionError = nil
                }
                .frame(maxWidth: SwftLayout.composerMaxWidth)
                .transition(.swftRise(reduceMotion: effectiveReduceMotion))
            }

            ComposerView(placeholder: "Reply to \(detail.summary.providerLabel)…")
                .frame(maxWidth: SwftLayout.composerMaxWidth)
                .sendFlightComposerAnchor()
                .overlay(alignment: .top) {
                    if sendFlight.showsScrollToBottom {
                        ScrollToBottomButton {
                            sendFlight.armScrollToBottom()
                            if effectiveReduceMotion {
                                if !sendFlight.scrollDriver.scrollToBottomImmediately() {
                                    scrollPosition.scrollTo(edge: .bottom)
                                }
                            } else if !sendFlight.scrollDriver.animateToBottom(
                                duration: SendFlightTiming.settleDuration,
                                curve: .settle
                            ) {
                                withAnimation(SwftMotion.screen) {
                                    scrollPosition.scrollTo(edge: .bottom)
                                }
                            }
                        }
                        .offset(y: -50)
                        .transition(.swftPop(reduceMotion: effectiveReduceMotion, scale: 0.6))
                    }
                }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) {
            // Soft fade so text sinking under the composer dissolves instead of meeting a hard edge.
            LinearGradient(
                stops: [.init(color: SwftColor.canvas.opacity(0), location: 0), .init(color: SwftColor.canvas.opacity(0.92), location: 0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 64)
            .allowsHitTesting(false)
        }
        .animation(SwftMotion.resolve(SwftMotion.pop, reduceMotion: effectiveReduceMotion), value: sendFlight.showsScrollToBottom)
        .animation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: effectiveReduceMotion), value: model.actionError)
    }
}
