import AppKit
import SwiftUI

/// Right-aligned user message: a plain soft-grey bubble with a large radius, like the reference. Nothing attached.
public struct UserBubble: View {
    let text: String
    public init(_ text: String) { self.text = text }

    /// The reference bubble is 61pt tall for one line; derive padding from this font's natural line height.
    private static let verticalPadding = max(10, (61 - SwftFonts.lineHeight(SwftType.bodySize)) / 2)

    public var body: some View {
        HStack {
            Spacer(minLength: 80)
            Text(text)
                .font(SwftType.body)
                .foregroundStyle(SwftColor.textPrimary)
                .lineSpacing(SwftType.bodyLineSpacing)
                .textSelection(.enabled)
                .padding(.horizontal, 20)
                .padding(.vertical, Self.verticalPadding)
                .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(SwftColor.userBubble))
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
            VStack(alignment: .leading, spacing: 14) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Markdown prose: paragraphs, `#` headings and `-`/`1.` lists, with bold and inline code styled explicitly so they
/// stay in Google Sans Flex / mono instead of falling back to the system font.
/// `streaming` appends a static caret (no blink, by design) and lets the text grow smoothly.
public struct MessageText: View {
    let markdown: String
    var streaming: Bool

    public init(_ markdown: String, streaming: Bool = false) {
        self.markdown = markdown
        self.streaming = streaming
    }

    public var body: some View {
        let blocks = MarkdownProse.blocks(markdown)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                let caret = streaming && index == blocks.count - 1
                blockView(block, caret: caret)
                    .padding(.top, index == 0 ? 0 : block.spacingBefore(after: blocks[index - 1]))
            }
        }
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .animation(streaming ? .easeOut(duration: 0.22) : nil, value: markdown)
    }

    @ViewBuilder private func blockView(_ block: MarkdownProse.Block, caret: Bool) -> some View {
        switch block {
        case .heading(let level, let text):
            styledText(text, base: level <= 2 ? .heading : .subheading, caret: caret)
        case .paragraph(let text):
            styledText(text, base: .body, caret: caret)
        case .listItem(let marker, let depth, let text):
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(marker.display(depth: depth))
                    .font(marker.isOrdered ? SwftType.body : SwftFonts.flex(13))
                    .foregroundStyle(SwftColor.textPrimary)
                    .frame(width: 22, alignment: marker.isOrdered ? .trailing : .center)
                    .padding(.trailing, marker.isOrdered ? 8 : 6)
                styledText(text, base: .body, caret: caret)
            }
            .padding(.leading, 6 + CGFloat(depth) * 22)
        }
    }

    private func styledText(_ source: String, base: MarkdownProse.Style, caret: Bool) -> some View {
        var attributed = MarkdownProse.inline(source, style: base)
        if caret {
            var mark = AttributedString(" \u{258D}")
            mark.foregroundColor = SwftColor.accent
            attributed.append(mark)
        }
        return Text(attributed)
            .font(base.font)
            .foregroundStyle(SwftColor.textPrimary)
            .lineSpacing(base == .body ? SwftType.bodyLineSpacing : 4)
            .contentTransition(.interpolate)
    }
}

/// Small block-level markdown splitter for assistant prose (fenced code is split out earlier, upstream).
public enum MarkdownProse {
    public enum Style: Equatable {
        case body, heading, subheading

        var font: Font {
            switch self {
            case .body: SwftType.body
            case .heading: SwftType.heading
            case .subheading: SwftType.subheading
            }
        }

        var strongFont: Font {
            switch self {
            case .body: SwftType.bodyStrong
            case .heading: SwftFonts.flex(20, weight: 620)
            case .subheading: SwftFonts.flex(17, weight: 700)
            }
        }
    }

    public enum Marker: Equatable {
        case bullet
        case ordered(String)

        var isOrdered: Bool { if case .ordered = self { true } else { false } }

        func display(depth: Int) -> String {
            switch self {
            case .bullet: depth == 0 ? "\u{25E6}" : "\u{25AA}"
            case .ordered(let n): "\(n)."
            }
        }
    }

    public enum Block: Equatable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case listItem(marker: Marker, depth: Int, text: String)

        func spacingBefore(after previous: Block) -> CGFloat {
            switch (previous, self) {
            case (_, .heading): 26
            case (.heading, _): 10
            case (.listItem, .listItem): 8
            default: 14
            }
        }
    }

    public static func blocks(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []

        func flush() {
            let text = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { blocks.append(.paragraph(text)) }
            paragraph.removeAll()
        }

        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flush()
                continue
            }
            if let heading = heading(trimmed) {
                flush()
                blocks.append(heading)
                continue
            }
            if let item = listItem(line) {
                flush()
                blocks.append(item)
                continue
            }
            if case .listItem(let marker, let depth, let text) = blocks.last, paragraph.isEmpty, line.first == " " {
                // Indented continuation of the previous list item.
                blocks[blocks.count - 1] = .listItem(marker: marker, depth: depth, text: text + "\n" + trimmed)
                continue
            }
            paragraph.append(line)
        }
        flush()
        return blocks
    }

    private static func heading(_ trimmed: String) -> Block? {
        let hashes = trimmed.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return nil }
        let rest = trimmed.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        return .heading(level: hashes, text: rest.trimmingCharacters(in: .whitespaces))
    }

    private static func listItem(_ line: String) -> Block? {
        let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let body = line.drop(while: { $0 == " " || $0 == "\t" })
        let depth = min(indent / 2, 3)
        if let first = body.first, "-*+".contains(first), body.dropFirst().first == " " {
            return .listItem(marker: .bullet, depth: depth, text: body.dropFirst(2).trimmingCharacters(in: .whitespaces))
        }
        let digits = body.prefix(while: \.isNumber)
        if !digits.isEmpty, digits.count <= 3 {
            let rest = body.dropFirst(digits.count)
            if let sep = rest.first, sep == "." || sep == ")", rest.dropFirst().first == " " {
                return .listItem(marker: .ordered(String(digits)), depth: depth, text: rest.dropFirst(2).trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }

    /// Inline markdown with explicit fonts on strong and code runs.
    public static func inline(_ source: String, style: Style) -> AttributedString {
        var attributed = (try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(source)
        for run in attributed.runs {
            guard let intent = run.inlinePresentationIntent else { continue }
            if intent.contains(.code) {
                attributed[run.range].font = SwftType.inlineCode
            } else if intent.contains(.stronglyEmphasized) {
                attributed[run.range].font = style.strongFont
            }
        }
        return attributed
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                withAnimation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion)) { expanded.toggle() }
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
                        .id(status)
                        .transition(.swftPop(reduceMotion: reduceMotion, scale: 0.5))
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
                VStack(spacing: 0) {
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
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(SwftColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous))
        .animation(SwftMotion.resolve(SwftMotion.pop, reduceMotion: reduceMotion), value: status)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                        .transition(.swftPop(reduceMotion: reduceMotion, scale: 0.7))
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
                    .buttonStyle(PressScaleStyle())
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
            }
        }
        .animation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion), value: status)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: SwftRadius.l, style: .continuous).fill(SwftColor.warningSoft))
        .overlay(RoundedRectangle(cornerRadius: SwftRadius.l, style: .continuous).strokeBorder(SwftColor.warningBorder))
    }
}
