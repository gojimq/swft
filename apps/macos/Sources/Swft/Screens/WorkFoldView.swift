import SwftDesign
import SwiftUI

/// A turn's folded work: one quiet line ("Worked for 12s ›"), or while the turn runs, the current step over a muted
/// running summary. Opening it lists each step as plain text.
struct WorkFoldView: View {
    let fold: WorkFold
    let isExpanded: Bool
    let onToggle: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) { header }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
                .accessibilityLabel(fold.title)
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(fold.steps) { WorkStepRow(step: $0) }
                }
                .padding(.leading, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .overlay(alignment: .leading) {
                    Rectangle().fill(SwftColor.borderSubtle).frame(width: 1).padding(.vertical, 8)
                }
                .padding(.leading, 2)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -4)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: hovering)
    }

    @ViewBuilder private var header: some View {
        if fold.isLive {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ProgressView().controlSize(.mini).frame(width: 12, height: 12).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(fold.title)
                            .font(SwftType.label)
                            .foregroundStyle(SwftColor.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .contentTransition(.interpolate)
                        chevron
                    }
                    if let subtitle = fold.subtitle {
                        summaryLine(subtitle)
                    }
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        } else {
            HStack(spacing: 5) {
                Text(fold.title)
                    .font(SwftType.label)
                    .foregroundStyle(hovering || isExpanded ? SwftColor.textSecondary : SwftColor.textTertiary)
                    .lineLimit(1)
                if fold.failedCount > 0 {
                    Text("· \(fold.failedCount) failed").font(SwftType.label).foregroundStyle(SwftColor.danger.opacity(0.85))
                }
                chevron
            }
            .frame(height: 24)
            .contentShape(Rectangle())
        }
    }

    private func summaryLine(_ text: String) -> some View {
        HStack(spacing: 5) {
            Text(text).lineLimit(1).truncationMode(.tail)
            if fold.failedCount > 0 {
                Text("· \(fold.failedCount) failed").foregroundStyle(SwftColor.danger.opacity(0.85))
            }
        }
        .font(SwftType.caption)
        .foregroundStyle(SwftColor.textTertiary)
        .contentTransition(.interpolate)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(SwftColor.textTertiary)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .opacity(fold.isLive && !hovering && !isExpanded ? 0 : 1)
    }
}

/// One plain-text line inside an open fold. Tool calls with output reveal it on click.
private struct WorkStepRow: View {
    let step: WorkStep
    @State private var showsOutput = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch step.kind {
        case .tool(let call):
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    guard call.output != nil else { return }
                    withAnimation(SwftMotion.resolve(SwftMotion.disclosure, reduceMotion: reduceMotion)) { showsOutput.toggle() }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(call.title).font(SwftType.label).foregroundStyle(SwftColor.textSecondary)
                        Text(call.detail)
                            .font(call.kind == .command ? SwftType.monoSmall : SwftType.label)
                            .foregroundStyle(SwftColor.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if call.status == .failed {
                            Text("failed").font(SwftType.caption).foregroundStyle(SwftColor.danger.opacity(0.85))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(call.output == nil ? "" : (showsOutput ? "Hide output" : "Show output"))

                if showsOutput, let output = call.output {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(output)
                            .font(SwftType.monoSmall)
                            .foregroundStyle(SwftColor.textSecondary)
                            .lineSpacing(2)
                            .lineLimit(24)
                            .textSelection(.enabled)
                            .fixedSize()
                            .padding(10)
                    }
                    .background(RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous).fill(SwftColor.codeBackground))
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -4)))
                }
            }
        case .thought(let text):
            Text(text)
                .font(SwftType.label)
                .foregroundStyle(SwftColor.textTertiary)
                .lineSpacing(2)
                .lineLimit(4)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .commentary(let blocks):
            let prose = blocks.compactMap { if case .text(let text) = $0 { text } else { nil } }.joined(separator: "\n")
            Text(MarkdownProse.inline(prose, style: .body))
                .font(SwftType.label)
                .foregroundStyle(SwftColor.textSecondary)
                .lineSpacing(2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .approval(let approval):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(approval.status == .approved ? "Approved" : "Denied").font(SwftType.label).foregroundStyle(SwftColor.textSecondary)
                Text(approval.command ?? approval.title)
                    .font(approval.command == nil ? SwftType.label : SwftType.monoSmall)
                    .foregroundStyle(SwftColor.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        case .note(let title, let message):
            QuietNote(title: title, message: message, isError: false)
        }
    }
}

/// A notice reduced to one muted line; errors keep a soft red tint.
struct QuietNote: View {
    let title: String
    let message: String
    let isError: Bool

    var body: some View {
        Text(line)
            .font(SwftType.label)
            .foregroundStyle(isError ? SwftColor.danger.opacity(0.85) : SwftColor.textTertiary)
            .lineLimit(isError ? 4 : 1)
            .truncationMode(.tail)
            .textSelection(.enabled)
            .help(message)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var line: String {
        // Notices usually restate their title in the message; show whichever says more, once.
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return title }
        if isError { return "\(title): \(trimmed)" }
        return trimmed.count > title.count ? trimmed : title
    }
}
