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

            if let actionError = model.actionError {
                ActionErrorBanner(message: actionError) {
                    model.actionError = nil
                }
                .frame(maxWidth: SwftLayout.composerMaxWidth)
                .padding(.horizontal, 32)
                .padding(.bottom, 8)
            }

            ComposerView(placeholder: "Reply to \(detail.summary.providerLabel)…")
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
