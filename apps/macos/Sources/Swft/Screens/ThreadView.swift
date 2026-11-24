import SwftDesign
import SwiftUI

struct ThreadView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let detail: ThreadDetailState
    @State private var scrollPosition = ScrollPosition()
    @State private var composerHeight: CGFloat = 110
    @State private var sendFlight = SendFlightCoordinator()
    /// Rows animate in only once the transcript has content; its first population (or a snapshot arriving after a
    /// thread switch) lands in place instead of every row rising at once.
    @State private var populated = false

    var body: some View {
        let rows = detail.rows
        let turns = SendFlightLogic.turns(from: rows)
        let topInset = SwftLayout.titlebarHeight + 24
        let streamRoomTopAnchor = SwftLayout.titlebarHeight + 16
        let bottomInset = composerHeight + 28
        let hasStreamRoom = sendFlight.hasStreamRoom(for: detail, isBusy: model.composer.isBusy)
        let streamRoom = hasStreamRoom
            ? SendFlightLogic.streamRoomHeight(viewportHeight: sendFlight.viewportSize.height, topInset: streamRoomTopAnchor, bottomInset: bottomInset)
            : nil
        let showWorking = sendFlight.shouldShowWorking(
            for: detail,
            isBusy: model.composer.isBusy,
            latestTurnRows: turns.last?.rows ?? [],
            latestSend: model.latestThreadSend,
            reduceMotion: reduceMotion
        )
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                ForEach(Array(turns.enumerated()), id: \.element.id) { index, turn in
                    SendFlightTurnSection(
                        detail: detail,
                        turn: turn,
                        isLatest: index == turns.count - 1,
                        streamRoomHeight: streamRoom,
                        showWorking: showWorking,
                        coordinator: sendFlight,
                        reduceMotion: reduceMotion
                    ) { row in
                        self.row(row)
                    }
                }
            }
            .frame(maxWidth: SwftLayout.contentMaxWidth)
            .padding(.horizontal, 32)
            .padding(.top, topInset)
            // Room for the floating composer, so the latest message rests above it rather than under the glass.
            .padding(.bottom, bottomInset)
            .frame(maxWidth: .infinity)
            .animation(populated && sendFlight.activeFlight == nil ? SwftMotion.resolve(SwftMotion.settle, reduceMotion: reduceMotion) : nil, value: rows.map(\.id))
        }
        .task(id: rows.isEmpty) { if !rows.isEmpty { populated = true } }
        .scrollPosition($scrollPosition)
        // Open at the latest message and follow growth via stickiness, keeping short threads top-aligned.
        .defaultScrollAnchor(.top, for: .alignment)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.top, for: .sizeChanges)
        .threadSendFlightScrollTracking(coordinator: sendFlight, scrollPosition: $scrollPosition)
        .scrollEdgeSoftIfAvailable()
        // The macOS 26 toolbar reports a taller top safe area; the transcript already pads under the top bar itself.
        .ignoresSafeArea(.container, edges: .top)
        // The composer floats over the transcript; the transcript keeps scrolling underneath its glass.
        .overlay(alignment: .bottom) {
            composerBar
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { composerHeight = $0 }
        }
        .threadSendFlightHost(
            detail: detail,
            isBusy: model.composer.isBusy,
            latestThreadSend: model.latestThreadSend,
            failedThreadSendID: model.failedThreadSendID,
            topInset: streamRoomTopAnchor,
            reduceMotion: reduceMotion,
            coordinator: sendFlight,
            scrollPosition: $scrollPosition
        )
    }

    private var composerBar: some View {
        VStack(spacing: 8) {
            if let actionError = model.actionError {
                ActionErrorBanner(message: actionError) {
                    model.actionError = nil
                }
                .frame(maxWidth: SwftLayout.composerMaxWidth)
                .transition(.swftRise(reduceMotion: reduceMotion))
            }

            ComposerView(placeholder: "Reply to \(detail.summary.providerLabel)…")
                .frame(maxWidth: SwftLayout.composerMaxWidth)
                .sendFlightComposerAnchor()
                .overlay(alignment: .top) {
                    if sendFlight.showsScrollToBottom {
                        ScrollToBottomButton {
                            sendFlight.armScrollToBottom()
                            withAnimation(SwftMotion.resolve(SwftMotion.screen, reduceMotion: reduceMotion)) {
                                scrollPosition.scrollTo(edge: .bottom)
                            }
                        }
                        .offset(y: -50)
                        .transition(.swftPop(reduceMotion: reduceMotion, scale: 0.6))
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
        .animation(SwftMotion.resolve(SwftMotion.pop, reduceMotion: reduceMotion), value: sendFlight.showsScrollToBottom)
        .animation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion), value: model.actionError)
    }

    @ViewBuilder private func row(_ row: TranscriptRow) -> some View {
        switch row {
        case .user(_, let text):
            UserBubble(text).padding(.vertical, 4)
        case .assistant(_, let blocks, let streaming):
            AssistantMessage {
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    switch block {
                    case .text(let text):
                        MessageText(text, streaming: streaming && index == blocks.count - 1)
                    case .code(let language, let source):
                        CodeBlock(source, language: language)
                    }
                }
            }
        case .work(let fold):
            WorkFoldView(fold: fold, isExpanded: model.expandedWorkFolds.contains(fold.id)) {
                sendFlight.handleWorkFoldToggle()
                withAnimation(SwftMotion.resolve(SwftMotion.disclosure, reduceMotion: reduceMotion)) {
                    model.toggleWorkFold(fold.id)
                }
            }
        case .approval(let id, let approval):
            ApprovalCard(
                title: approval.title,
                message: approval.message,
                command: approval.command,
                status: approval.status.cardStatus,
                onApprove: { model.resolveApproval(itemID: id, in: detail.summary.id, approved: true) },
                onDeny: { model.resolveApproval(itemID: id, in: detail.summary.id, approved: false) }
            )
        case .note(_, let title, let message, let isError):
            QuietNote(title: title, message: message, isError: isError)
        }
    }
}
