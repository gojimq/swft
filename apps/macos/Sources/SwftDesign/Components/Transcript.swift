import AppKit
import SwiftUI

/// Right-aligned user message bubble.
public struct UserBubble: View {
    let text: String
    public init(_ text: String) { self.text = text }

    public var body: some View {
        HStack {
            Spacer(minLength: 80)
            Text(text)
                .font(SwftType.body)
                .foregroundStyle(SwftColor.textPrimary)
                .lineSpacing(3)
                .textSelection(.enabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 22, bottomTrailingRadius: 22, topTrailingRadius: 6, style: .continuous)
                        .fill(SwftColor.userBubble)
                )
        }
    }
}

/// Assistant message: a small avatar column with free-flowing content (no bubble), like the reference.
public struct AssistantMessage<Content: View>: View {
    let avatar: AnyView
    let content: Content

    public init(@ViewBuilder avatar: () -> some View, @ViewBuilder content: () -> Content) {
        self.avatar = AnyView(avatar())
        self.content = content()
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 14) {
            avatar.frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 12) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Inline-markdown prose paragraph. `streaming` appends a static caret (no blink, by design).
public struct MessageText: View {
    let markdown: String
    var streaming: Bool

    public init(_ markdown: String, streaming: Bool = false) {
        self.markdown = markdown
        self.streaming = streaming
    }

    public var body: some View {
        let attributed = (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(markdown)
        (Text(attributed) + (streaming ? Text(" \u{258D}").foregroundColor(SwftColor.accent) : Text("")))
            .font(SwftType.body)
            .foregroundStyle(SwftColor.textPrimary)
            .lineSpacing(4)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Fenced code block with a language label and copy button.
public struct CodeBlock: View {
    let code: String
    let language: String?
    @State private var copied = false

    public init(_ code: String, language: String? = nil) {
        self.code = code
        self.language = language
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "code").font(SwftType.caption).foregroundStyle(SwftColor.textTertiary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(SwftType.caption)
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .contentShape(Capsule())
                }
                .buttonStyle(HoverFillStyle(shape: Capsule()))
                .foregroundStyle(SwftColor.textSecondary)
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .padding(.vertical, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(SwftType.mono)
                    .foregroundStyle(SwftColor.textPrimary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize()
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .padding(.top, 2)
            }
        }
        .background(RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous).fill(SwftColor.codeBackground))
        .overlay(RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous).strokeBorder(SwftColor.borderSubtle))
    }
}

/// Outcome of a tool call.
public enum ToolCallStatus: Sendable {
    case running, succeeded, failed
}

/// Collapsible tool-call card: one quiet line when collapsed, monospace output when expanded.
public struct ToolCallCard: View {
    let title: String
    let detail: String
    let systemName: String
    let status: ToolCallStatus
    let duration: String?
    let output: String?
    @State private var expanded: Bool

    public init(title: String, detail: String, systemName: String, status: ToolCallStatus, duration: String? = nil, output: String? = nil, expanded: Bool = false) {
        self.title = title
        self.detail = detail
        self.systemName = systemName
        self.status = status
        self.duration = duration
        self.output = output
        self._expanded = State(initialValue: expanded)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                guard output != nil else { return }
                withAnimation(SwftMotion.quick) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: systemName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SwftColor.textSecondary)
                        .frame(width: 16)
                    Text(title).font(SwftType.labelStrong).foregroundStyle(SwftColor.textPrimary)
                    Text(detail)
                        .font(SwftType.monoSmall)
                        .foregroundStyle(SwftColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    if let duration {
                        Text(duration).font(SwftType.caption).monospacedDigit().foregroundStyle(SwftColor.textTertiary)
                    }
                    statusIcon
                    if output != nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(SwftColor.textTertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded, let output {
                Divider().overlay(SwftColor.borderSubtle)
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(output)
                        .font(SwftType.monoSmall)
                        .foregroundStyle(SwftColor.textSecondary)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .fixedSize()
                        .padding(12)
                }
                .background(SwftColor.codeBackground)
            }
        }
        .background(SwftColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous).strokeBorder(SwftColor.border))
    }

    @ViewBuilder private var statusIcon: some View {
        switch status {
        case .running:
            ProgressView().controlSize(.mini).frame(width: 14, height: 14)
        case .succeeded:
            Image(systemName: "checkmark").font(.system(size: 10.5, weight: .bold)).foregroundStyle(SwftColor.success)
        case .failed:
            Image(systemName: "xmark").font(.system(size: 10.5, weight: .bold)).foregroundStyle(SwftColor.danger)
        }
    }
}

/// Resolution state of an approval request.
public enum ApprovalStatus: Sendable {
    case pending, approved, denied
}

/// Approval request card with Deny / Approve.
public struct ApprovalCard: View {
    let title: String
    let message: String
    let command: String?
    let status: ApprovalStatus
    let onApprove: () -> Void
    let onDeny: () -> Void

    public init(title: String, message: String, command: String?, status: ApprovalStatus, onApprove: @escaping () -> Void = {}, onDeny: @escaping () -> Void = {}) {
        self.title = title
        self.message = message
        self.command = command
        self.status = status
        self.onApprove = onApprove
        self.onDeny = onDeny
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(SwftColor.warning)
                Text(title).font(SwftType.labelStrong).foregroundStyle(SwftColor.textPrimary)
                Spacer()
                if status != .pending {
                    Label(status == .approved ? "Approved" : "Denied", systemImage: status == .approved ? "checkmark" : "xmark")
                        .font(SwftType.caption)
                        .foregroundStyle(status == .approved ? SwftColor.success : SwftColor.danger)
                }
            }
            Text(message).font(SwftType.label).foregroundStyle(SwftColor.textSecondary).fixedSize(horizontal: false, vertical: true)
            if let command {
                Text(command)
                    .font(SwftType.mono)
                    .foregroundStyle(SwftColor.textPrimary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous).fill(SwftColor.surface))
            }
            if status == .pending {
                HStack(spacing: 8) {
                    Spacer()
                    Button(action: onDeny) {
                        Text("Deny").font(SwftType.labelStrong).padding(.horizontal, 16).frame(height: 32).contentShape(Capsule())
                    }
                    .buttonStyle(HoverFillStyle(shape: Capsule()))
                    .overlay(Capsule().strokeBorder(SwftColor.border))
                    .foregroundStyle(SwftColor.textPrimary)
                    .keyboardShortcut(.escape, modifiers: [])

                    Button(action: onApprove) {
                        Text("Approve").font(SwftType.labelStrong).padding(.horizontal, 16).frame(height: 32)
                            .background(Capsule().fill(SwftColor.accent))
                            .foregroundStyle(SwftColor.canvas)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: SwftRadius.l, style: .continuous).fill(SwftColor.warningSoft))
        .overlay(RoundedRectangle(cornerRadius: SwftRadius.l, style: .continuous).strokeBorder(SwftColor.warningBorder))
    }
}
