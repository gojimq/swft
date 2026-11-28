import AppKit
import os
import SwiftUI

/// Right-aligned user message: its attachments above a plain soft-grey bubble with a large radius, like the reference.
public struct UserBubble: View, Equatable {
    let text: String
    let attachments: [TranscriptAttachment]

    public init(_ text: String, attachments: [TranscriptAttachment] = []) {
        self.text = text
        self.attachments = attachments
    }

    nonisolated public static func == (lhs: UserBubble, rhs: UserBubble) -> Bool {
        lhs.text == rhs.text && lhs.attachments == rhs.attachments
    }

    public var body: some View {
        HStack {
            Spacer(minLength: UserBubbleMetrics.leadingSpacerMinLength)
            UserTurnContent(text: text, attachments: attachments)
                .textSelection(.enabled)
        }
    }
}

/// Assistant message: free-flowing content in the reading column, no avatar and no bubble.
public struct AssistantMessage<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Markdown prose: headings, paragraphs, nested bullet/ordered/task lists, GFM tables, blockquotes/alerts,
/// and thematic breaks, with inline code pills, links, and bold styled cleanly like T3 Code.
/// `streaming` appends a static caret (no blink, by design) and lets the text grow smoothly.
public struct MessageText: View, Equatable {
    let markdown: String
    var streaming: Bool
    /// The size it last had while streaming. Dropping the caret can unwrap a line, so a finished message keeps that
    /// height at the same width and the transcript under the reader does not jump.
    @State private var streamedSize: CGSize?

    public init(_ markdown: String, streaming: Bool = false) {
        self.markdown = markdown
        self.streaming = streaming
    }

    nonisolated public static func == (lhs: MessageText, rhs: MessageText) -> Bool {
        lhs.markdown == rhs.markdown && lhs.streaming == rhs.streaming
    }

    public var body: some View {
        let blocks = MarkdownProse.blocks(markdown)
        blockListView(blocks, appendCaret: streaming)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: streaming ? nil : streamedSize?.height, alignment: .top)
            .onGeometryChange(for: CGSize.self, of: \.size) { size in
                if streaming {
                    streamedSize = size
                } else if let streamedSize, abs(streamedSize.width - size.width) > 0.5 {
                    self.streamedSize = nil
                }
            }
            .animation(streaming ? .easeOut(duration: 0.22) : nil, value: markdown)
    }

    private func blockListView(_ blocks: [MarkdownProse.Block], appendCaret: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                let caret = appendCaret && index == blocks.count - 1
                blockView(block, caret: caret)
                    .padding(.top, index == 0 ? 0 : block.spacingBefore(after: blocks[index - 1]))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func blockView(_ block: MarkdownProse.Block, caret: Bool) -> AnyView {
        switch block {
        case .heading(let level, let text):
            let style = MarkdownProse.Style.headingStyle(for: level)
            return AnyView(
                styledText(
                    text,
                    base: style,
                    caret: caret,
                    foreground: level >= 6 ? SwftColor.textSecondary : SwftColor.textPrimary
                )
            )
        case .paragraph(let text):
            return AnyView(styledText(text, base: .body, caret: caret))
        case .listItem(let marker, let depth, let text):
            return AnyView(
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    listMarkerView(marker: marker, depth: depth)
                    styledText(text, base: .body, caret: caret)
                }
                .padding(.leading, 2 + CGFloat(depth) * 18)
            )
        case .table(let table):
            return AnyView(MarkdownTableView(table: table).equatable())
        case .blockquote(let alert, let innerBlocks):
            return AnyView(
                MarkdownBlockquoteView(alert: alert) {
                    blockListView(innerBlocks, appendCaret: caret)
                }
            )
        case .thematicBreak:
            return AnyView(
                Rectangle()
                    .fill(SwftColor.tableDivider)
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
            )
        }
    }

    @ViewBuilder private func listMarkerView(marker: MarkdownProse.Marker, depth: Int) -> some View {
        switch marker {
        case .bullet:
            let bulletFont: Font = switch depth {
            case 0: SwftFonts.flex(15, weight: 600)
            case 1: SwftFonts.flex(14, weight: 500)
            default: SwftFonts.flex(11)
            }
            Text(marker.display(depth: depth))
                .font(bulletFont)
                .foregroundStyle(SwftColor.textTertiary)
                .frame(width: 18, alignment: .center)
                .padding(.trailing, 4)
        case .ordered(let number):
            Text("\(number).")
                .font(SwftType.body.monospacedDigit())
                .foregroundStyle(SwftColor.textTertiary)
                .frame(minWidth: 20, alignment: .trailing)
                .padding(.trailing, 7)
        case .task(let checked):
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(checked ? SwftColor.accent : SwftColor.textTertiary)
                .frame(width: 18, alignment: .center)
                .padding(.trailing, 6)
        }
    }

    private func styledText(
        _ source: String,
        base: MarkdownProse.Style,
        caret: Bool,
        foreground: Color = SwftColor.textPrimary
    ) -> some View {
        var attributed = MarkdownProse.inline(source, style: base)
        if caret {
            var mark = AttributedString(" \u{258D}")
            mark.foregroundColor = SwftColor.accent
            attributed.append(mark)
        }
        return Text(attributed)
            .font(base.font)
            .foregroundStyle(foreground)
            .lineSpacing(base == .body ? SwftType.bodyLineSpacing : 3.5)
            .contentTransition(.interpolate)
    }
}

/// Bounded thread-safe cache avoiding repeated `AttributedString(markdown:)` parses during scroll and live updates.
private final class MarkdownProseCache: Sendable {
    struct InlineKey: Hashable, Sendable {
        let style: MarkdownProse.Style
        let source: String
    }

    private struct Storage {
        var blocks: [String: [MarkdownProse.Block]] = [:]
        var inline: [InlineKey: AttributedString] = [:]
    }

    static let shared = MarkdownProseCache()
    private static let maxEntries = 512
    private let lock = OSAllocatedUnfairLock(initialState: Storage())

    func blocks(for markdown: String, compute: () -> [MarkdownProse.Block]) -> [MarkdownProse.Block] {
        guard markdown.utf8.count <= 16_384 else { return compute() }
        if let cached = lock.withLock({ $0.blocks[markdown] }) {
            return cached
        }
        let result = compute()
        lock.withLock { storage in
            if storage.blocks.count >= Self.maxEntries { storage.blocks.removeAll(keepingCapacity: true) }
            storage.blocks[markdown] = result
        }
        return result
    }

    func inline(for source: String, style: MarkdownProse.Style, compute: () -> AttributedString) -> AttributedString {
        guard source.utf8.count <= 8_192 else { return compute() }
        let key = InlineKey(style: style, source: source)
        if let cached = lock.withLock({ $0.inline[key] }) {
            return cached
        }
        let result = compute()
        lock.withLock { storage in
            if storage.inline.count >= Self.maxEntries { storage.inline.removeAll(keepingCapacity: true) }
            storage.inline[key] = result
        }
        return result
    }
}

/// GFM block-level markdown splitter for assistant prose (fenced code is split out earlier, upstream).
public enum MarkdownProse {
    public enum Style: Hashable, Sendable {
        case body, h1, heading, subheading, minorHeading, tableHeader, tableCell

        static func headingStyle(for level: Int) -> Style {
            switch level {
            case 1: .h1
            case 2: .heading
            case 3: .subheading
            default: .minorHeading
            }
        }

        var font: Font {
            switch self {
            case .body: SwftType.body
            case .h1: SwftType.h1
            case .heading: SwftType.heading
            case .subheading: SwftType.subheading
            case .minorHeading: SwftType.minorHeading
            case .tableHeader: SwftType.tableHeader
            case .tableCell: SwftType.tableCell
            }
        }

        var strongFont: Font {
            switch self {
            case .body: SwftType.bodyStrong
            case .h1: SwftType.h1Strong
            case .heading: SwftType.headingStrong
            case .subheading: SwftType.subheadingStrong
            case .minorHeading: SwftType.minorHeadingStrong
            case .tableHeader: SwftType.tableHeader
            case .tableCell: SwftType.tableCellStrong
            }
        }

        var inlineCodeFont: Font {
            switch self {
            case .tableHeader, .tableCell: SwftType.tableInlineCode
            default: SwftType.inlineCode
            }
        }
    }

    public enum ColumnAlignment: Hashable, Sendable {
        case leading, center, trailing
    }

    public struct TableData: Hashable, Sendable {
        public let headers: [String]
        public let alignments: [ColumnAlignment]
        public let rows: [[String]]

        public init(headers: [String], alignments: [ColumnAlignment], rows: [[String]]) {
            self.headers = headers
            self.alignments = alignments
            self.rows = rows
        }
    }

    public enum AlertKind: String, Hashable, Sendable {
        case note = "NOTE"
        case tip = "TIP"
        case important = "IMPORTANT"
        case warning = "WARNING"
        case caution = "CAUTION"

        var title: String {
            switch self {
            case .note: "Note"
            case .tip: "Tip"
            case .important: "Important"
            case .warning: "Warning"
            case .caution: "Caution"
            }
        }

        var systemName: String {
            switch self {
            case .note: "info.circle"
            case .tip: "lightbulb"
            case .important: "exclamationmark.bubble"
            case .warning: "exclamationmark.triangle"
            case .caution: "exclamationmark.octagon"
            }
        }
    }

    public enum Marker: Hashable, Sendable {
        case bullet
        case ordered(String)
        case task(checked: Bool)

        var isOrdered: Bool { if case .ordered = self { true } else { false } }

        func display(depth: Int) -> String {
            switch self {
            case .bullet:
                switch depth {
                case 0: "\u{2022}"
                case 1: "\u{25E6}"
                default: "\u{25AA}"
                }
            case .ordered(let n): "\(n)."
            case .task(let checked): checked ? "[x]" : "[ ]"
            }
        }
    }

    public enum Block: Hashable, Sendable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case listItem(marker: Marker, depth: Int, text: String)
        case table(TableData)
        case blockquote(AlertKind?, [Block])
        case thematicBreak

        func spacingBefore(after previous: Block) -> CGFloat {
            switch (previous, self) {
            case (_, .heading(let level, _)):
                level <= 2 ? 22 : 18
            case (.heading, _):
                8
            case (_, .table), (.table, _):
                14
            case (_, .blockquote), (.blockquote, _):
                14
            case (_, .thematicBreak), (.thematicBreak, _):
                14
            case (.listItem(_, let prevDepth, _), .listItem(_, let curDepth, _)):
                (curDepth == 0 && prevDepth > 0) ? 8 : 5
            case (_, .listItem):
                10
            case (.listItem, _):
                12
            default:
                12
            }
        }
    }

    public static func blocks(_ markdown: String) -> [Block] {
        MarkdownProseCache.shared.blocks(for: markdown) {
            parseBlocks(markdown)
        }
    }

    private static func parseBlocks(_ markdown: String) -> [Block] {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [Block] = []
        var paragraph: [String] = []
        var index = 0

        func flush() {
            let text = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { blocks.append(.paragraph(text)) }
            paragraph.removeAll()
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flush()
                index += 1
                continue
            }
            if isThematicBreak(trimmed) {
                flush()
                blocks.append(.thematicBreak)
                index += 1
                continue
            }
            if let heading = heading(trimmed) {
                flush()
                blocks.append(heading)
                index += 1
                continue
            }
            if isBlockquoteLine(trimmed) {
                flush()
                var quotedLines: [String] = []
                while index < lines.count {
                    let qTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
                    guard isBlockquoteLine(qTrimmed) else { break }
                    quotedLines.append(stripBlockquotePrefix(qTrimmed))
                    index += 1
                }
                let (alert, bodyLines) = extractAlert(from: quotedLines)
                let inner = parseBlocks(bodyLines.joined(separator: "\n"))
                if !inner.isEmpty || alert != nil {
                    blocks.append(.blockquote(alert, inner))
                }
                continue
            }
            if index + 1 < lines.count,
               let parsed = parseTable(lines: lines, start: index)
            {
                flush()
                blocks.append(.table(parsed.table))
                index = parsed.nextIndex
                continue
            }
            if let item = listItem(line) {
                flush()
                blocks.append(item)
                index += 1
                continue
            }
            if case .listItem(let marker, let depth, let text) = blocks.last,
               paragraph.isEmpty,
               (line.first == " " || line.first == "\t")
            {
                blocks[blocks.count - 1] = .listItem(marker: marker, depth: depth, text: text + "\n" + trimmed)
                index += 1
                continue
            }
            paragraph.append(line)
            index += 1
        }
        flush()
        return blocks
    }

    private static func isThematicBreak(_ trimmed: String) -> Bool {
        guard let first = trimmed.first, first == "-" || first == "*" || first == "_" else { return false }
        var count = 0
        for ch in trimmed {
            if ch == first {
                count += 1
            } else if ch != " " && ch != "\t" {
                return false
            }
        }
        return count >= 3
    }

    private static func isBlockquoteLine(_ trimmed: String) -> Bool {
        trimmed.hasPrefix(">")
    }

    private static func stripBlockquotePrefix(_ trimmed: String) -> String {
        guard trimmed.hasPrefix(">") else { return trimmed }
        let rest = trimmed.dropFirst()
        if rest.first == " " {
            return String(rest.dropFirst())
        }
        return String(rest)
    }

    private static func extractAlert(from lines: [String]) -> (AlertKind?, [String]) {
        guard let first = lines.first?.trimmingCharacters(in: .whitespaces),
              first.hasPrefix("[!"),
              let closing = first.firstIndex(of: "]")
        else { return (nil, lines) }
        let tagStart = first.index(first.startIndex, offsetBy: 2)
        let tag = String(first[tagStart..<closing]).uppercased()
        guard let kind = AlertKind(rawValue: tag) else { return (nil, lines) }
        let remainder = first[first.index(after: closing)...].trimmingCharacters(in: .whitespaces)
        var body = Array(lines.dropFirst())
        if !remainder.isEmpty {
            body.insert(remainder, at: 0)
        }
        return (kind, body)
    }

    private static func parseTable(lines: [String], start: Int) -> (table: TableData, nextIndex: Int)? {
        let headerLine = lines[start].trimmingCharacters(in: .whitespaces)
        let delimiterLine = lines[start + 1].trimmingCharacters(in: .whitespaces)
        guard headerLine.contains("|"),
              let alignments = parseTableDelimiter(delimiterLine)
        else { return nil }
        let headers = splitTableRow(headerLine)
        guard !headers.isEmpty, headers.count == alignments.count else { return nil }

        let colCount = headers.count
        var rows: [[String]] = []
        var cursor = start + 2
        while cursor < lines.count {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || isThematicBreak(trimmed) || isBlockquoteLine(trimmed) || heading(trimmed) != nil {
                break
            }
            guard trimmed.contains("|") else { break }
            var cells = splitTableRow(trimmed)
            if cells.count < colCount {
                cells.append(contentsOf: repeatElement("", count: colCount - cells.count))
            } else if cells.count > colCount {
                cells = Array(cells.prefix(colCount))
            }
            rows.append(cells)
            cursor += 1
        }
        return (TableData(headers: headers, alignments: alignments, rows: rows), cursor)
    }

    private static func parseTableDelimiter(_ trimmed: String) -> [ColumnAlignment]? {
        guard trimmed.contains("|") || trimmed.contains("-") else { return nil }
        let cells = splitTableRow(trimmed)
        guard !cells.isEmpty else { return nil }
        var alignments: [ColumnAlignment] = []
        alignments.reserveCapacity(cells.count)
        for cell in cells {
            guard !cell.isEmpty else { return nil }
            let leadingColon = cell.hasPrefix(":")
            let trailingColon = cell.hasSuffix(":")
            let coreStart = leadingColon ? cell.index(after: cell.startIndex) : cell.startIndex
            let coreEnd = trailingColon && cell.count > (leadingColon ? 1 : 0) ? cell.index(before: cell.endIndex) : cell.endIndex
            let core = cell[coreStart..<coreEnd]
            guard !core.isEmpty, core.allSatisfy({ $0 == "-" }) else { return nil }
            if leadingColon && trailingColon {
                alignments.append(.center)
            } else if trailingColon {
                alignments.append(.trailing)
            } else {
                alignments.append(.leading)
            }
        }
        return alignments
    }

    /// Splits one GFM pipe-table row into trimmed cells, preserving `\|` escapes and pipes inside `` `code` `` spans.
    private static func splitTableRow(_ trimmed: String) -> [String] {
        var slice = trimmed[...]
        if slice.first == "|" {
            slice = slice.dropFirst()
        }
        if slice.last == "|" {
            // Keep an escaped trailing `\|` inside the last cell.
            let beforeLast = slice.index(before: slice.endIndex)
            let isEscaped = beforeLast > slice.startIndex && slice[slice.index(before: beforeLast)] == "\\"
            if !isEscaped {
                slice = slice.dropLast()
            }
        }
        var cells: [String] = []
        var current = ""
        var inCode = false
        var escaped = false
        for ch in slice {
            if escaped {
                if ch == "|" {
                    current.append("|")
                } else {
                    current.append("\\")
                    current.append(ch)
                }
                escaped = false
                continue
            }
            if ch == "\\" {
                escaped = true
                continue
            }
            if ch == "`" {
                inCode.toggle()
                current.append(ch)
                continue
            }
            if ch == "|" && !inCode {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current.removeAll(keepingCapacity: true)
                continue
            }
            current.append(ch)
        }
        if escaped { current.append("\\") }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
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
            let content = body.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if content.hasPrefix("[ ] ") {
                return .listItem(marker: .task(checked: false), depth: depth, text: String(content.dropFirst(4)).trimmingCharacters(in: .whitespaces))
            }
            if content.hasPrefix("[x] ") || content.hasPrefix("[X] ") {
                return .listItem(marker: .task(checked: true), depth: depth, text: String(content.dropFirst(4)).trimmingCharacters(in: .whitespaces))
            }
            return .listItem(marker: .bullet, depth: depth, text: content)
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

    /// Inline markdown with tinted inline code pills, crisp strong weight, strikethrough, and T3 Code-style links.
    public static func inline(_ source: String, style: Style) -> AttributedString {
        MarkdownProseCache.shared.inline(for: source, style: style) {
            var attributed = (try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                ?? AttributedString(source)
            var fileLinkSuffixes: [(Range<AttributedString.Index>, String, URL)] = []

            for run in attributed.runs {
                if let intent = run.inlinePresentationIntent {
                    if intent.contains(.code) {
                        attributed[run.range].font = style.inlineCodeFont
                        attributed[run.range].backgroundColor = SwftColor.inlineCodeBackground
                    } else if intent.contains(.stronglyEmphasized) {
                        attributed[run.range].font = style.strongFont
                    }
                    if intent.contains(.strikethrough) {
                        attributed[run.range].strikethroughStyle = .single
                        attributed[run.range].foregroundColor = SwftColor.textTertiary
                    }
                }
                if let url = run.link {
                    attributed[run.range].foregroundColor = SwftColor.accent
                    if url.isFileURL {
                        let label = String(attributed[run.range].characters)
                        if let suffix = fileLinkLineSuffix(for: url, label: label) {
                            fileLinkSuffixes.append((run.range, suffix, url))
                        }
                    }
                }
            }

            // Append quiet ` · L12–34` line ranges to `file://` links whose label omits line numbers (matching T3 Code).
            for (range, suffix, url) in fileLinkSuffixes.reversed() {
                var tail = AttributedString(suffix)
                tail.link = url
                tail.foregroundColor = SwftColor.accent.opacity(0.75)
                tail.font = style.font.monospacedDigit()
                attributed.insert(tail, at: range.upperBound)
            }

            return attributed
        }
    }

    /// Extracts a T3 Code-style ` · L123` / ` · L123–145` suffix from `file://...#L123-L145` when absent from `label`.
    static func fileLinkLineSuffix(for url: URL, label: String) -> String? {
        guard let fragment = url.fragment, !fragment.isEmpty else { return nil }
        let upper = fragment.uppercased()
        guard upper.hasPrefix("L") else { return nil }
        let parts = upper.split(separator: "-")
        guard let startDigits = parts.first?.dropFirst(), !startDigits.isEmpty, startDigits.allSatisfy(\.isNumber) else {
            return nil
        }
        // Skip if the label already includes line numbers (e.g. `Foo.swift:12` or `Foo.swift L12`).
        if label.contains(":\(startDigits)") || label.contains("L\(startDigits)") {
            return nil
        }
        if parts.count >= 2 {
            let rawEnd = parts[1].hasPrefix("L") ? parts[1].dropFirst() : parts[1][...]
            if !rawEnd.isEmpty, rawEnd.allSatisfy(\.isNumber), rawEnd != startDigits {
                return " \u{00B7} L\(startDigits)\u{2013}\(rawEnd)"
            }
        }
        return " \u{00B7} L\(startDigits)"
    }
}

/// Fenced code block with language header, wrap toggle, auto-resetting copy button, and syntax highlighting.
public struct CodeBlock: View, Equatable {
    let code: String
    let language: String?
    @State private var copied = false
    @State private var wrapsLines = false

    nonisolated public static func == (lhs: CodeBlock, rhs: CodeBlock) -> Bool {
        lhs.code == rhs.code && lhs.language == rhs.language
    }

    public init(_ code: String, language: String? = nil) {
        self.code = code
        self.language = language
    }

    public var body: some View {
        let highlighted = SwftCodeHighlight.attributed(code, language: language)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(language?.isEmpty == false ? language! : "code")
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.textTertiary)
                Spacer()
                Button {
                    wrapsLines.toggle()
                } label: {
                    Image(systemName: wrapsLines ? "text.alignleft" : "arrow.right.to.line")
                        .font(.system(size: 10.5, weight: .medium))
                        .frame(width: 24, height: 24)
                        .contentShape(Capsule())
                }
                .buttonStyle(HoverFillStyle(shape: Capsule(), selected: wrapsLines))
                .foregroundStyle(wrapsLines ? SwftColor.textPrimary : SwftColor.textTertiary)
                .help(wrapsLines ? "Disable line wrapping" : "Wrap long lines")

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(SwftType.caption)
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .contentShape(Capsule())
                }
                .buttonStyle(HoverFillStyle(shape: Capsule()))
                .foregroundStyle(copied ? SwftColor.accent : SwftColor.textSecondary)
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .frame(height: 32)

            Rectangle()
                .fill(SwftColor.borderSubtle)
                .frame(height: 1)

            if wrapsLines {
                Text(highlighted)
                    .font(SwftType.mono)
                    .foregroundStyle(SwftColor.textPrimary)
                    .lineSpacing(3.5)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(highlighted)
                        .font(SwftType.mono)
                        .foregroundStyle(SwftColor.textPrimary)
                        .lineSpacing(3.5)
                        .textSelection(.enabled)
                        .fixedSize()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous).fill(SwftColor.codeBackground))
        .overlay(RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous).strokeBorder(SwftColor.borderSubtle))
    }
}

/// Resolution state of an approval request.
public enum ApprovalStatus: Sendable {
    case pending, approved, denied
}

/// Approval request: the one thing in a turn that needs the reader, so it keeps a soft surface and a clear action,
/// without warning colors or icons.
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(SwftType.labelStrong).foregroundStyle(SwftColor.textPrimary)
                Spacer()
                if status != .pending {
                    Text(status == .approved ? "Approved" : "Denied")
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textTertiary)
                        .transition(.swftPop(reduceMotion: reduceMotion, scale: 0.8))
                }
            }
            Text(message).font(SwftType.label).foregroundStyle(SwftColor.textSecondary).fixedSize(horizontal: false, vertical: true)
            if let command {
                Text(command)
                    .font(SwftType.monoSmall)
                    .foregroundStyle(SwftColor.textPrimary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous).fill(SwftColor.canvas.opacity(0.7)))
            }
            if status == .pending {
                HStack(spacing: 8) {
                    Spacer()
                    Button(action: onDeny) {
                        Text("Deny").font(SwftType.label).padding(.horizontal, 14).frame(height: 28).contentShape(Capsule())
                    }
                    .buttonStyle(HoverFillStyle(shape: Capsule()))
                    .foregroundStyle(SwftColor.textSecondary)
                    .keyboardShortcut(.escape, modifiers: [])

                    Button(action: onApprove) {
                        Text("Approve").font(SwftType.labelStrong).padding(.horizontal, 14).frame(height: 28)
                            .background(Capsule().fill(SwftColor.textPrimary))
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
        .background(RoundedRectangle(cornerRadius: SwftRadius.l, style: .continuous).fill(SwftColor.surfaceMuted))
    }
}

/// Layout metrics shared by `UserBubble` and the attachment strip above it.
public enum UserBubbleMetrics {
    public static let horizontalPadding: CGFloat = 18
    public static let verticalPadding: CGFloat = max(8, (44 - SwftFonts.lineHeight(SwftType.bodySize)) / 2)
    public static let cornerRadius: CGFloat = 22
    public static let leadingSpacerMinLength: CGFloat = 80

    /// Attachment-only messages render no text pill.
    public static func hasText(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Quiet "Working" tail row shown while a turn is running before work steps or streaming text arrive.
/// Waits `delay` (or until `revealAt`, typically `send.timestamp + SendFlightTiming.workingDelay`) so a just-sent
/// message has faded in first.
public struct WorkingIndicatorRow: View {
    let delay: TimeInterval
    let revealAt: Date?
    let reduceMotionOverride: Bool?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var shown: Bool

    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    public init(delay: TimeInterval = 0, revealAt: Date? = nil, reduceMotion: Bool? = nil) {
        self.delay = delay
        self.revealAt = revealAt
        self.reduceMotionOverride = reduceMotion
        let initialRemaining: TimeInterval
        if reduceMotion == true {
            initialRemaining = 0
        } else if let revealAt {
            initialRemaining = max(0, revealAt.timeIntervalSinceNow)
        } else {
            initialRemaining = max(0, delay)
        }
        self._shown = State(initialValue: initialRemaining <= 0)
    }

    public var body: some View {
        HStack(spacing: 8) {
            if reduceMotion {
                Circle()
                    .fill(SwftColor.textTertiary)
                    .frame(width: 6, height: 6)
                    .frame(width: 12, height: 12)
            } else {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 12, height: 12)
            }
            Text("Working")
                .font(SwftType.label)
                .foregroundStyle(SwftColor.textSecondary)
        }
        .frame(height: 24, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(shown ? 1 : 0)
        .offset(y: shown || reduceMotion ? 0 : 8)
        .task(id: revealAt?.timeIntervalSinceReferenceDate ?? delay) {
            if shown { return }
            let remaining: TimeInterval
            if reduceMotion {
                remaining = 0
            } else if let revealAt {
                remaining = max(0, revealAt.timeIntervalSinceNow)
            } else {
                remaining = max(0, delay)
            }
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
                guard !Task.isCancelled else { return }
            }
            withAnimation(SwftMotion.resolve(SwftMotion.settle, reduceMotion: reduceMotion)) {
                shown = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Working")
    }
}
