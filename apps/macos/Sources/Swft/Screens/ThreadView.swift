import SwftDesign
import SwiftUI

struct ThreadView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let detail: ThreadDetailState
    @State private var scrollPosition = ScrollPosition()
    @State private var isAtBottom = true
    @State private var composerHeight: CGFloat = 110
    /// Rows animate in only once the transcript has content; its first population (or a snapshot arriving after a
    /// thread switch) lands in place instead of every row rising at once.
    @State private var populated = false

    var body: some View {
        let rows = detail.rows
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(rows) { row in
                    self.row(row)
                        .transition(.swftRise(reduceMotion: reduceMotion))
                }
            }
            .frame(maxWidth: SwftLayout.contentMaxWidth)
            .padding(.horizontal, 32)
            .padding(.top, SwftLayout.titlebarHeight + 24)
            // Room for the floating composer, so the latest message rests above it rather than under the glass.
            .padding(.bottom, composerHeight + 28)
            .frame(maxWidth: .infinity)
            .animation(populated ? SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion) : nil, value: rows.map(\.id))
        }
        .task(id: rows.isEmpty) { if !rows.isEmpty { populated = true } }
        .scrollPosition($scrollPosition)
        // Open at the latest message and follow growth, but keep short threads top-aligned like the reference.
        .defaultScrollAnchor(.top, for: .alignment)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.visibleRect.maxY >= geometry.contentSize.height - 48
        } action: { _, atBottom in
            isAtBottom = atBottom
        }
        .scrollEdgeSoftIfAvailable()
        // The macOS 26 toolbar reports a taller top safe area; the transcript already pads under the top bar itself.
        .ignoresSafeArea(.container, edges: .top)
        // The composer floats over the transcript; the transcript keeps scrolling underneath its glass.
        .overlay(alignment: .bottom) {
            composerBar
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { composerHeight = $0 }
        }
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
                .overlay(alignment: .top) {
                    if !isAtBottom {
                        ScrollToBottomButton {
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
        .animation(SwftMotion.resolve(SwftMotion.pop, reduceMotion: reduceMotion), value: isAtBottom)
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
