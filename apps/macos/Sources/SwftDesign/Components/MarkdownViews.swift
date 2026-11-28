import AppKit
import os
import SwiftUI

// MARK: - Table Serialization

public enum MarkdownTableSerializer {
    public static func toMarkdown(_ table: MarkdownProse.TableData) -> String {
        guard !table.headers.isEmpty else { return "" }
        func escape(_ cell: String) -> String {
            cell.replacingOccurrences(of: "|", with: "\\|")
                .replacingOccurrences(of: "\n", with: " ")
        }
        let headerRow = "| " + table.headers.map(escape).joined(separator: " | ") + " |"
        let alignRow = "| " + table.alignments.map { alignment -> String in
            switch alignment {
            case .leading: "---"
            case .center: ":---:"
            case .trailing: "---:"
            }
        }.joined(separator: " | ") + " |"
        let bodyRows = table.rows.map { row in
            "| " + row.map(escape).joined(separator: " | ") + " |"
        }
        return ([headerRow, alignRow] + bodyRows).joined(separator: "\n")
    }

    public static func toCSV(_ table: MarkdownProse.TableData) -> String {
        guard !table.headers.isEmpty else { return "" }
        func csvCell(_ value: String) -> String {
            let needsQuotes = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
            guard needsQuotes else { return value }
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let allRows = [table.headers] + table.rows
        return allRows.map { $0.map(csvCell).joined(separator: ",") }.joined(separator: "\n")
    }
}

// MARK: - Diagnostics-Style GFM Table View

/// Clean horizontal-divider GFM table matching T3 Code's `MarkdownTable`: flush outer edges,
/// top-aligned wrapped cells with inline markdown, horizontal scrolling for wide tables, and a copy menu.
public struct MarkdownTableView: View, Equatable {
    let table: MarkdownProse.TableData
    @State private var copiedFormat: String?

    public init(table: MarkdownProse.TableData) {
        self.table = table
    }

    nonisolated public static func == (lhs: MarkdownTableView, rhs: MarkdownTableView) -> Bool {
        lhs.table == rhs.table
    }

    private var needsHorizontalScroll: Bool {
        table.headers.count >= 5
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if needsHorizontalScroll {
                ScrollView(.horizontal, showsIndicators: true) {
                    tableGrid(constrainColumnMax: true)
                }
            } else {
                tableGrid(constrainColumnMax: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Menu {
                    Button("Copy as Markdown") { copy(MarkdownTableSerializer.toMarkdown(table), label: "Markdown") }
                    Button("Copy as CSV") { copy(MarkdownTableSerializer.toCSV(table), label: "CSV") }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copiedFormat != nil ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10.5, weight: .medium))
                        Text(copiedFormat != nil ? "Copied" : "Copy table")
                            .font(SwftType.caption)
                    }
                    .foregroundStyle(copiedFormat != nil ? SwftColor.accent : SwftColor.textTertiary)
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .contentShape(Capsule())
                }
                .menuStyle(.button)
                .buttonStyle(HoverFillStyle(shape: Capsule()))
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func tableGrid(constrainColumnMax: Bool) -> some View {
        let columnCount = table.headers.count
        let flexibleColumns = Self.flexibleColumnFlags(for: table)
        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(0..<columnCount, id: \.self) { col in
                    let alignment = col < table.alignments.count ? table.alignments[col] : .leading
                    let text = table.headers[col]
                    tableCell(
                        text: text,
                        style: .tableHeader,
                        alignment: alignment,
                        isFirst: col == 0,
                        isLast: col == columnCount - 1,
                        isFlexible: flexibleColumns[col],
                        verticalPadding: 8,
                        constrainColumnMax: constrainColumnMax
                    )
                }
            }

            Rectangle()
                .fill(SwftColor.tableDivider)
                .frame(height: 1)
                .gridCellUnsizedAxes(.horizontal)

            ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                GridRow {
                    ForEach(0..<columnCount, id: \.self) { col in
                        let alignment = col < table.alignments.count ? table.alignments[col] : .leading
                        let text = col < row.count ? row[col] : ""
                        tableCell(
                            text: text,
                            style: .tableCell,
                            alignment: alignment,
                            isFirst: col == 0,
                            isLast: col == columnCount - 1,
                            isFlexible: flexibleColumns[col],
                            verticalPadding: 7,
                            constrainColumnMax: constrainColumnMax
                        )
                    }
                }
                if rowIndex < table.rows.count - 1 {
                    Rectangle()
                        .fill(SwftColor.borderSubtle)
                        .frame(height: 1)
                        .gridCellUnsizedAxes(.horizontal)
                }
            }

            Rectangle()
                .fill(SwftColor.tableDivider)
                .frame(height: 1)
                .gridCellUnsizedAxes(.horizontal)
        }
        .textSelection(.enabled)
    }

    /// Gives short label columns their natural width when paired with wider prose columns so prose wraps less.
    private static func flexibleColumnFlags(for table: MarkdownProse.TableData) -> [Bool] {
        let count = table.headers.count
        guard count > 1 else { return Array(repeating: true, count: count) }
        var maxLengths = table.headers.map(\.count)
        for row in table.rows {
            for col in 0..<min(count, row.count) {
                maxLengths[col] = max(maxLengths[col], row[col].count)
            }
        }
        let hasProseColumn = maxLengths.contains { $0 > 28 }
        guard hasProseColumn else { return Array(repeating: true, count: count) }
        return maxLengths.map { $0 > 28 }
    }

    private func tableCell(
        text: String,
        style: MarkdownProse.Style,
        alignment: MarkdownProse.ColumnAlignment,
        isFirst: Bool,
        isLast: Bool,
        isFlexible: Bool,
        verticalPadding: CGFloat,
        constrainColumnMax: Bool
    ) -> some View {
        let horizontalAlignment: Alignment = switch alignment {
        case .leading: .topLeading
        case .center: .top
        case .trailing: .topTrailing
        }
        let textAlignment: TextAlignment = switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
        let maxColumnWidth: CGFloat? = constrainColumnMax ? 280 : (isFlexible ? .infinity : nil)
        return Text(MarkdownProse.inline(text, style: style))
            .font(style.font)
            .foregroundStyle(SwftColor.textPrimary)
            .lineSpacing(3)
            .multilineTextAlignment(textAlignment)
            .fixedSize(horizontal: !isFlexible && !constrainColumnMax, vertical: true)
            .frame(
                minWidth: constrainColumnMax ? 100 : nil,
                maxWidth: maxColumnWidth,
                alignment: horizontalAlignment
            )
            .padding(.leading, isFirst ? 0 : 14)
            .padding(.trailing, isLast ? 0 : 14)
            .padding(.vertical, verticalPadding)
            .gridColumnAlignment(gridAlignment(for: alignment))
    }

    private func gridAlignment(for alignment: MarkdownProse.ColumnAlignment) -> HorizontalAlignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private func copy(_ value: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copiedFormat = label
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            if copiedFormat == label { copiedFormat = nil }
        }
    }
}

// MARK: - Blockquote & GitHub Callout Alert

public struct MarkdownBlockquoteView<Content: View>: View {
    let alert: MarkdownProse.AlertKind?
    let content: Content

    public init(alert: MarkdownProse.AlertKind?, @ViewBuilder content: () -> Content) {
        self.alert = alert
        self.content = content()
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(barColor)
                .frame(width: 2.5)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 6) {
                if let alert {
                    HStack(spacing: 6) {
                        Image(systemName: alert.systemName)
                            .font(.system(size: 12.5, weight: .semibold))
                        Text(alert.title)
                            .font(SwftType.labelStrong)
                    }
                    .foregroundStyle(barColor)
                }
                content
                    .foregroundStyle(alert == nil ? SwftColor.textSecondary : SwftColor.textPrimary)
            }
            .padding(.leading, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var barColor: Color {
        switch alert {
        case nil: SwftColor.blockquoteBorder
        case .note: SwftColor.accent
        case .tip: SwftColor.success
        case .important: SwftColor.syntaxKeyword
        case .warning: SwftColor.warning
        case .caution: SwftColor.danger
        }
    }
}

// MARK: - Lightweight Syntax Highlighting for CodeBlock

/// Fast, zero-dependency syntax tokenizer for fenced code blocks with bounded caching.
/// Plain-text fences stay uncolored to match T3 Code.
public enum SwftCodeHighlight {
    private static let plainLanguages: Set<String> = ["", "text", "txt", "plain", "plaintext"]

    private static let keywordsByFamily: [String: Set<String>] = [
        "swift": [
            "actor", "as", "async", "await", "break", "case", "catch", "class", "continue", "default",
            "defer", "do", "else", "enum", "extension", "fallthrough", "false", "fileprivate", "final",
            "for", "func", "guard", "if", "import", "in", "init", "inout", "internal", "is", "let",
            "mutating", "nil", "nonisolated", "open", "operator", "override", "private", "protocol",
            "public", "repeat", "rethrows", "return", "self", "Self", "some", "any", "static", "struct",
            "subscript", "super", "switch", "throw", "throws", "true", "try", "typealias", "var",
            "weak", "where", "while",
        ],
        "js": [
            "as", "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger",
            "default", "delete", "do", "else", "enum", "export", "extends", "false", "finally", "for",
            "from", "function", "if", "implements", "import", "in", "instanceof", "interface", "let",
            "new", "null", "of", "package", "private", "protected", "public", "readonly", "return",
            "satisfies", "static", "super", "switch", "this", "throw", "true", "try", "type", "typeof",
            "undefined", "var", "void", "while", "with", "yield",
        ],
        "python": [
            "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif",
            "else", "except", "False", "finally", "for", "from", "global", "if", "import", "in", "is",
            "lambda", "match", "case", "None", "nonlocal", "not", "or", "pass", "raise", "return",
            "True", "try", "while", "with", "yield",
        ],
        "rust": [
            "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum",
            "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move",
            "mut", "pub", "ref", "return", "self", "Self", "static", "struct", "super", "trait", "true",
            "type", "unsafe", "use", "where", "while",
        ],
        "c": [
            "auto", "bool", "break", "case", "char", "class", "const", "constexpr", "continue",
            "default", "do", "double", "else", "enum", "extern", "false", "float", "for", "goto", "if",
            "in", "inline", "inout", "int", "layout", "long", "namespace", "new", "nullptr", "out",
            "override", "private", "protected", "public", "return", "shader_type", "short", "signed",
            "sizeof", "static", "struct", "switch", "template", "this", "true", "typedef", "typename",
            "uint", "uniform", "unsigned", "using", "varying", "vec2", "vec3", "vec4", "mat3", "mat4",
            "virtual", "void", "volatile", "while",
        ],
        "go": [
            "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough",
            "false", "for", "func", "go", "goto", "if", "import", "interface", "map", "nil", "package",
            "range", "return", "select", "struct", "switch", "true", "type", "var",
        ],
        "shell": [
            "case", "do", "done", "elif", "else", "esac", "export", "fi", "for", "function", "if", "in",
            "local", "readonly", "return", "set", "then", "trap", "unset", "until", "while",
        ],
        "sql": [
            "SELECT", "FROM", "WHERE", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "ON", "AS", "AND",
            "OR", "NOT", "IN", "IS", "NULL", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE",
            "CREATE", "TABLE", "INDEX", "DROP", "ALTER", "ORDER", "BY", "GROUP", "HAVING", "LIMIT",
            "DISTINCT", "UNION", "CASE", "WHEN", "THEN", "ELSE", "END", "TRUE", "FALSE",
        ],
        "json": ["true", "false", "null"],
    ]

    private struct CacheKey: Hashable, Sendable {
        let language: String
        let code: String
    }

    private final class HighlightCache: Sendable {
        static let shared = HighlightCache()
        private let lock = OSAllocatedUnfairLock(initialState: [CacheKey: AttributedString]())

        func getOrCompute(key: CacheKey, compute: () -> AttributedString) -> AttributedString {
            guard key.code.utf8.count <= 24_576 else { return compute() }
            if let hit = lock.withLock({ $0[key] }) { return hit }
            let value = compute()
            lock.withLock { storage in
                if storage.count >= 256 { storage.removeAll(keepingCapacity: true) }
                storage[key] = value
            }
            return value
        }
    }

    public static func attributed(_ code: String, language: String?) -> AttributedString {
        let normalized = (language ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !plainLanguages.contains(normalized), !code.isEmpty else {
            return AttributedString(code)
        }
        return HighlightCache.shared.getOrCompute(key: CacheKey(language: normalized, code: code)) {
            tokenize(code, language: normalized)
        }
    }

    private static func family(for language: String) -> String {
        switch language {
        case "swift": "swift"
        case "ts", "tsx", "typescript", "js", "jsx", "javascript", "mjs", "cjs": "js"
        case "py", "python": "python"
        case "rs", "rust": "rust"
        case "go", "golang": "go"
        case "sh", "bash", "zsh", "shell": "shell"
        case "sql", "sqlite", "postgres", "postgresql": "sql"
        case "json", "jsonc": "json"
        case "c", "h", "cpp", "cc", "cxx", "hpp", "objc", "glsl", "gdshader", "metal", "wgsl", "hlsl": "c"
        default: "generic"
        }
    }

    private static func tokenize(_ code: String, language: String) -> AttributedString {
        let fam = family(for: language)
        let keywords = keywordsByFamily[fam] ?? keywordsByFamily["js"]!
        let supportsHashComment = fam == "python" || fam == "shell" || language == "yaml" || language == "yml" || language == "toml"
        let supportsSlashComment = fam != "python" && fam != "shell" && language != "yaml" && language != "yml"
        let supportsDashComment = fam == "sql"
        let isSQL = fam == "sql"
        let isJSON = fam == "json"

        var result = AttributedString(code)
        let scalars = Array(code.unicodeScalars)
        let count = scalars.count
        var i = 0

        func apply(_ color: Color, scalarStart: Int, scalarEnd: Int) {
            guard scalarStart < scalarEnd else { return }
            let startIdx = code.unicodeScalars.index(code.unicodeScalars.startIndex, offsetBy: scalarStart)
            let endIdx = code.unicodeScalars.index(code.unicodeScalars.startIndex, offsetBy: scalarEnd)
            guard let attrStart = AttributedString.Index(startIdx, within: result),
                  let attrEnd = AttributedString.Index(endIdx, within: result)
            else { return }
            result[attrStart..<attrEnd].foregroundColor = color
        }

        while i < count {
            let ch = scalars[i]

            // Line comments: //, #, --
            if supportsSlashComment, ch == "/", i + 1 < count, scalars[i + 1] == "/" {
                let start = i
                i += 2
                while i < count && scalars[i] != "\n" { i += 1 }
                apply(SwftColor.syntaxComment, scalarStart: start, scalarEnd: i)
                continue
            }
            if supportsSlashComment, ch == "/", i + 1 < count, scalars[i + 1] == "*" {
                let start = i
                i += 2
                while i + 1 < count && !(scalars[i] == "*" && scalars[i + 1] == "/") { i += 1 }
                i = min(count, i + 2)
                apply(SwftColor.syntaxComment, scalarStart: start, scalarEnd: i)
                continue
            }
            if supportsHashComment, ch == "#" {
                let start = i
                while i < count && scalars[i] != "\n" { i += 1 }
                apply(SwftColor.syntaxComment, scalarStart: start, scalarEnd: i)
                continue
            }
            if supportsDashComment, ch == "-", i + 1 < count, scalars[i + 1] == "-" {
                let start = i
                while i < count && scalars[i] != "\n" { i += 1 }
                apply(SwftColor.syntaxComment, scalarStart: start, scalarEnd: i)
                continue
            }

            // Strings: "...", '...', `...`
            if ch == "\"" || ch == "'" || ch == "`" {
                let quote = ch
                let start = i
                i += 1
                while i < count {
                    if scalars[i] == "\\" && i + 1 < count {
                        i += 2
                        continue
                    }
                    if scalars[i] == quote {
                        i += 1
                        break
                    }
                    if quote != "`" && scalars[i] == "\n" {
                        break
                    }
                    i += 1
                }
                if isJSON {
                    // Distinguish JSON object keys ("key":) from string values.
                    var probe = i
                    while probe < count && (scalars[probe] == " " || scalars[probe] == "\t") { probe += 1 }
                    let color = (probe < count && scalars[probe] == ":") ? SwftColor.syntaxType : SwftColor.syntaxString
                    apply(color, scalarStart: start, scalarEnd: i)
                } else {
                    apply(SwftColor.syntaxString, scalarStart: start, scalarEnd: i)
                }
                continue
            }

            // Attributes / preprocessor directives (@MainActor, #include, #if)
            if (ch == "@" || (ch == "#" && (fam == "c" || fam == "swift"))),
               i + 1 < count, isIdentStart(scalars[i + 1])
            {
                let start = i
                i += 1
                while i < count && isIdentContinue(scalars[i]) { i += 1 }
                apply(SwftColor.syntaxKeyword, scalarStart: start, scalarEnd: i)
                continue
            }

            // Numbers
            if isDigit(ch) && (i == 0 || !isIdentContinue(scalars[i - 1])) {
                let start = i
                i += 1
                while i < count && (isHexOrNumChar(scalars[i]) || (scalars[i] == "." && i + 1 < count && isDigit(scalars[i + 1]))) {
                    i += 1
                }
                apply(SwftColor.syntaxNumber, scalarStart: start, scalarEnd: i)
                continue
            }

            // Identifiers, keywords, and PascalCase types
            if isIdentStart(ch) {
                let start = i
                i += 1
                while i < count && isIdentContinue(scalars[i]) { i += 1 }
                let word = String(String.UnicodeScalarView(scalars[start..<i]))
                if keywords.contains(isSQL ? word.uppercased() : word) {
                    apply(SwftColor.syntaxKeyword, scalarStart: start, scalarEnd: i)
                } else if !isJSON, isPascalType(word) {
                    apply(SwftColor.syntaxType, scalarStart: start, scalarEnd: i)
                }
                continue
            }

            i += 1
        }

        return result
    }

    private static func isIdentStart(_ s: UnicodeScalar) -> Bool {
        (s >= "a" && s <= "z") || (s >= "A" && s <= "Z") || s == "_"
    }

    private static func isIdentContinue(_ s: UnicodeScalar) -> Bool {
        isIdentStart(s) || isDigit(s)
    }

    private static func isDigit(_ s: UnicodeScalar) -> Bool {
        s >= "0" && s <= "9"
    }

    private static func isHexOrNumChar(_ s: UnicodeScalar) -> Bool {
        isDigit(s) || (s >= "a" && s <= "f") || (s >= "A" && s <= "F") || s == "x" || s == "X" || s == "_"
    }

    private static func isPascalType(_ word: String) -> Bool {
        guard word.count >= 2, let first = word.unicodeScalars.first, first >= "A" && first <= "Z" else { return false }
        return word.unicodeScalars.contains { $0 >= "a" && $0 <= "z" }
    }
}
