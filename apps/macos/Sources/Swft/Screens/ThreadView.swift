import SwftDesign
import SwiftUI

struct ThreadView: View {
    @Environment(AppModel.self) private var model
    let detail: ThreadDetailState

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(detail.items) { item in
                        row(item)
                    }
                }
                .frame(maxWidth: SwftLayout.contentMaxWidth)
                .padding(.horizontal, 32)
                .padding(.top, SwftLayout.titlebarHeight + 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)

            ComposerView(placeholder: "Reply to \(detail.summary.provider.displayName)…")
                .frame(maxWidth: SwftLayout.composerMaxWidth)
                .padding(.horizontal, 32)
                .padding(.bottom, 20)
                .background(alignment: .top) {
                    LinearGradient(colors: [SwftColor.canvas.opacity(0), SwftColor.canvas], startPoint: .top, endPoint: .bottom)
                        .frame(height: 24)
                        .offset(y: -24)
                        .allowsHitTesting(false)
                }
        }
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
        }
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
