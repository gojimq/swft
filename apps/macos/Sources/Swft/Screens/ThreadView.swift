import SwftDesign
import SwiftUI

struct ThreadView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let detail: ThreadDetailState
    @State private var scrollPosition = ScrollPosition()
    @State private var isAtBottom = true
    @State private var composerHeight: CGFloat = 110

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(detail.items) { item in
                    row(item)
                        .transition(.swftRise(reduceMotion: reduceMotion))
                }
            }
            .frame(maxWidth: SwftLayout.contentMaxWidth)
            .padding(.horizontal, 32)
            .padding(.top, SwftLayout.titlebarHeight + 24)
            // Room for the floating composer, so the latest message rests above it rather than under the glass.
            .padding(.bottom, composerHeight + 28)
            .frame(maxWidth: .infinity)
            .animation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion), value: detail.items.map(\.id))
        }
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

    @ViewBuilder private func row(_ item: TranscriptItem) -> some View {
        switch item.kind {
        case .user(let text):
            UserBubble(text).padding(.vertical, 6)
        case .assistant(let blocks, let streaming):
            AssistantMessage {
                ProviderAvatar(provider: detail.summary.provider)
            } content: {
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    switch block {
                    case .text(let text):
                        MessageText(text, streaming: streaming && index == blocks.count - 1)
                    case .code(let language, let source):
                        CodeBlock(source, language: language)
                    }
                }
            }
        case .toolCall(let call):
            ToolCallCard(
                title: call.title,
                detail: call.detail,
                systemName: call.symbol,
                status: call.status.cardStatus,
                duration: call.durationText,
                output: call.output
            )
            .padding(.leading, 38)
        case .approval(let approval):
            ApprovalCard(
                title: approval.title,
                message: approval.message,
                command: approval.command,
                status: approval.status.cardStatus,
                onApprove: { model.resolveApproval(itemID: item.id, in: detail.summary.id, approved: true) },
                onDeny: { model.resolveApproval(itemID: item.id, in: detail.summary.id, approved: false) }
            )
            .padding(.leading, 38)
        case .notice(let title, let message, let isError):
            TranscriptNoticeCard(title: title, message: message, isError: isError)
                .padding(.leading, 38)
        }
    }
}

struct TranscriptNoticeCard: View {
    let title: String
    let message: String
    let isError: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isError ? "exclamationmark.circle.fill" : "info.circle")
                .font(.system(size: 12.5))
                .foregroundStyle(isError ? SwftColor.danger : SwftColor.textSecondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SwftType.labelStrong)
                    .foregroundStyle(SwftColor.textPrimary)
                Text(message)
                    .font(SwftType.label)
                    .foregroundStyle(SwftColor.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous)
                .fill(isError ? SwftColor.dangerSoft : SwftColor.surfaceMuted)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous)
                .strokeBorder(isError ? SwftColor.danger.opacity(0.28) : SwftColor.borderSubtle)
        )
    }
}

struct ProviderAvatar: View {
    let provider: ProviderKind
    var body: some View {
        Circle()
            .fill(SwftColor.surfaceMuted)
            .overlay(Image(systemName: provider.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(provider.tint))
            .overlay(Circle().strokeBorder(SwftColor.borderSubtle))
            .frame(width: 24, height: 24)
            .padding(.top, 1)
    }
}
