import Foundation
import SwftDesign
import SwftKit
import SwiftUI

// MARK: - Surface Kinds (Strictly the 5 included surfaces — Terminal, Diff, Pull request are excluded)

enum RightPanelSurfaceKind: String, CaseIterable, Hashable, Sendable, Identifiable {
    case browser
    case files
    case linkedItems
    case device
    case sideChat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .browser: "Browser"
        case .files: "Files"
        case .linkedItems: "Linked items"
        case .device: "Device"
        case .sideChat: "Side chat"
        }
    }

    var subtitle: String {
        switch self {
        case .browser: "Preview dev servers and web pages"
        case .files: "Browse and read workspace files"
        case .linkedItems: "Pull requests, issues, and related threads"
        case .device: "Stream an iOS Simulator or Android Emulator"
        case .sideChat: "Ask aside without interrupting this thread"
        }
    }

    var shortcutKey: String {
        switch self {
        case .browser: "B"
        case .files: "F"
        case .linkedItems: "L"
        case .device: "M"
        case .sideChat: "S"
        }
    }

    var iconName: String {
        switch self {
        case .browser: "globe"
        case .files: "folder"
        case .linkedItems: "link"
        case .device: "iphone"
        case .sideChat: "bubble.left.and.bubble.right"
        }
    }
}

// MARK: - Tab Payloads & Per-Thread State

struct BrowserTabState: Equatable, Hashable, Sendable {
    var urlString: String
    var pageTitle: String?
    var serverPreviewTabId: String?

    init(urlString: String = "", pageTitle: String? = nil, serverPreviewTabId: String? = nil) {
        self.urlString = urlString
        self.pageTitle = pageTitle
        self.serverPreviewTabId = serverPreviewTabId
    }
}

struct FilesTabState: Equatable, Hashable, Sendable {
    var selectedFilePath: String?
    var openFilePaths: [String]
    var folderPath: String

    init(selectedFilePath: String? = nil, openFilePaths: [String] = [], folderPath: String = "") {
        self.selectedFilePath = selectedFilePath
        self.openFilePaths = openFilePaths
        self.folderPath = folderPath
    }
}

struct DeviceTabState: Equatable, Hashable, Sendable {
    var hostId: String?
    var deviceId: String?
    var platform: DevicePlatform?
    var deviceName: String?

    init(
        hostId: String? = nil,
        deviceId: String? = nil,
        platform: DevicePlatform? = nil,
        deviceName: String? = nil
    ) {
        self.hostId = hostId
        self.deviceId = deviceId
        self.platform = platform
        self.deviceName = deviceName
    }
}

struct SideChatTabState: Equatable, Hashable, Sendable {
    var sideThreadId: String?
    var title: String?
    var isCreating: Bool

    init(sideThreadId: String? = nil, title: String? = nil, isCreating: Bool = false) {
        self.sideThreadId = sideThreadId
        self.title = title
        self.isCreating = isCreating
    }
}

struct SubagentTabState: Equatable, Hashable, Sendable {
    var subagentThreadId: String
    var environmentId: String?
    var title: String
    var status: SubagentStatus
    var modelLabel: String?
    var providerDisplayName: String?
    var providerDriver: String?
    var providerInstanceId: String?
    var providerIconUrl: String?
    var prompt: String?
    var workspaceLabel: String?

    init(
        subagentThreadId: String,
        environmentId: String? = nil,
        title: String = "",
        status: SubagentStatus = .idle,
        modelLabel: String? = nil,
        providerDisplayName: String? = nil,
        providerDriver: String? = nil,
        providerInstanceId: String? = nil,
        providerIconUrl: String? = nil,
        prompt: String? = nil,
        workspaceLabel: String? = nil
    ) {
        self.subagentThreadId = subagentThreadId
        self.environmentId = environmentId
        self.title = title
        self.status = status
        self.modelLabel = modelLabel
        self.providerDisplayName = providerDisplayName
        self.providerDriver = providerDriver
        self.providerInstanceId = providerInstanceId
        self.providerIconUrl = providerIconUrl
        self.prompt = prompt
        self.workspaceLabel = workspaceLabel
    }
}

enum RightPanelTabPayload: Equatable, Hashable, Sendable {
    case launcher
    case browser(BrowserTabState)
    case files(FilesTabState)
    case linkedItems
    case device(DeviceTabState)
    case sideChat(SideChatTabState)
    case subagent(SubagentTabState)

    var surfaceKind: RightPanelSurfaceKind? {
        switch self {
        case .launcher: nil
        case .browser: .browser
        case .files: .files
        case .linkedItems: .linkedItems
        case .device: .device
        case .sideChat: .sideChat
        case .subagent: nil
        }
    }
}

struct RightPanelTab: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    var payload: RightPanelTabPayload

    var surfaceKind: RightPanelSurfaceKind? { payload.surfaceKind }

    var title: String {
        switch payload {
        case .launcher:
            return "New tab"
        case .browser(let state):
            return RightPanelLogic.displayBrowserTitle(title: state.pageTitle, urlString: state.urlString)
        case .files(let state):
            if let selected = state.selectedFilePath, !selected.isEmpty {
                return RightPanelLogic.fileName(from: selected)
            }
            return "Files"
        case .linkedItems:
            return "Linked items"
        case .device(let state):
            if let name = state.deviceName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return name
            }
            return "Device"
        case .sideChat(let state):
            if let title = state.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return title
            }
            return "Side chat"
        case .subagent(let state):
            let trimmed = state.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Subagent" : trimmed
        }
    }

    var iconName: String {
        switch payload {
        case .launcher:
            return "plus.square"
        case .browser:
            return "globe"
        case .files(let state):
            return state.selectedFilePath == nil ? "folder" : "doc.text"
        case .linkedItems:
            return "link"
        case .device(let state):
            return state.platform?.symbolName ?? "iphone"
        case .sideChat:
            return "bubble.left.and.bubble.right"
        case .subagent:
            return "cpu"
        }
    }
}

struct ThreadRightPanelState: Equatable, Sendable {
    var isOpen: Bool = false
    var tabs: [RightPanelTab] = []
    var activeTabID: String?
    var isMaximized: Bool = false

    var activeTab: RightPanelTab? {
        guard let activeTabID else { return tabs.first }
        return tabs.first(where: { $0.id == activeTabID }) ?? tabs.first
    }
}

// MARK: - File Tree & Preview Classification Models

struct FileTreeRow: Identifiable, Equatable, Hashable, Sendable {
    let path: String
    let name: String
    let kind: ProjectEntryKind
    let depth: Int
    let isExpanded: Bool
    let ignored: Bool

    var id: String { path }
}

enum WorkspaceFilePreviewKind: Equatable, Hashable, Sendable {
    case markdown
    case image
    case code(language: String?)
    case binary
}

struct ParsedPullRequestURL: Equatable, Sendable {
    let host: String
    let repository: String
    let number: Int
    let url: String
}

// MARK: - Pure Testable Logic

enum RightPanelLogic {

    // MARK: Shortcuts

    /// Maps a single-character launcher shortcut (`B`, `F`, `L`, `M`, `S`) to its surface kind.
    /// Deliberately excludes `T` (Terminal), `D` (Diff), and `P` (Pull request).
    static func surfaceKind(
        forKey key: String,
        hasCommandOrControlOrOption: Bool = false
    ) -> RightPanelSurfaceKind? {
        guard !hasCommandOrControlOrOption else { return nil }
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.count == 1 else { return nil }
        return RightPanelSurfaceKind.allCases.first { $0.shortcutKey == normalized }
    }

    // MARK: Panel Width Clamping

    static func clampedWidth(
        _ proposed: CGFloat,
        availableWindowWidth: CGFloat? = nil
    ) -> CGFloat {
        let hardMax: CGFloat
        if let availableWindowWidth, availableWindowWidth > 0 {
            hardMax = max(
                RightPanelMetrics.minWidth,
                min(RightPanelMetrics.maxWidth, availableWindowWidth - RightPanelMetrics.minChatColumnWidth)
            )
        } else {
            hardMax = RightPanelMetrics.maxWidth
        }
        return min(hardMax, max(RightPanelMetrics.minWidth, proposed))
    }

    // MARK: Browser URL Normalization

    /// Normalizes user-typed browser input into a loadable http(s) URL.
    /// Uses `http://` for loopback (`localhost`, `127.0.0.1`, `[::1]`), private LAN IPs, `.local`, and bare ports (`:3000`);
    /// uses `https://` for everything else. Rejects non-HTTP(S) schemes such as `javascript:` or `file:`.
    static func normalizeBrowserURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Bare port shorthand like ":3000" or ":5173/dashboard"
        if trimmed.hasPrefix(":") {
            return URL(string: "http://localhost\(trimmed)")
        }

        // Check for an explicit scheme (`scheme://` or `scheme:`).
        if let colonIndex = trimmed.firstIndex(of: ":") {
            let prefix = String(trimmed[..<colonIndex])
            let afterColon = trimmed[trimmed.index(after: colonIndex)...]
            let looksLikeScheme = !prefix.isEmpty
                && prefix.allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }
                && (afterColon.hasPrefix("//") || !isPortPrefix(afterColon))
            if looksLikeScheme {
                let lowerScheme = prefix.lowercased()
                guard lowerScheme == "http" || lowerScheme == "https" else {
                    return nil
                }
                guard let url = URL(string: trimmed),
                      let host = url.host(), !host.isEmpty
                else { return nil }
                return url
            }
        }

        let scheme = shouldDefaultToHTTP(trimmed) ? "http" : "https"
        guard let url = URL(string: "\(scheme)://\(trimmed)"),
              let host = url.host(), !host.isEmpty
        else { return nil }
        return url
    }

    private static func isPortPrefix(_ remainder: Substring) -> Bool {
        let digits = remainder.prefix(while: \.isNumber)
        guard !digits.isEmpty else { return false }
        let afterDigits = remainder.dropFirst(digits.count)
        return afterDigits.isEmpty || afterDigits.first == "/" || afterDigits.first == "?" || afterDigits.first == "#"
    }

    static func shouldDefaultToHTTP(_ hostAndPath: String) -> Bool {
        let authority: String
        if let slash = hostAndPath.firstIndex(of: "/") {
            authority = String(hostAndPath[..<slash])
        } else if let query = hostAndPath.firstIndex(of: "?") {
            authority = String(hostAndPath[..<query])
        } else {
            authority = hostAndPath
        }

        let host: String
        if authority.hasPrefix("["), let closeBracket = authority.firstIndex(of: "]") {
            host = String(authority[authority.index(after: authority.startIndex)..<closeBracket]).lowercased()
        } else if let colon = authority.lastIndex(of: ":") {
            host = String(authority[..<colon]).lowercased()
        } else {
            host = authority.lowercased()
        }

        if host == "localhost"
            || host.hasSuffix(".localhost")
            || host.hasSuffix(".local")
            || host == "::1"
            || host == "0.0.0.0"
        {
            return true
        }
        return isLocalOrPrivateIPv4(host)
    }

    private static func isLocalOrPrivateIPv4(_ host: String) -> Bool {
        let octets = host.split(separator: ".", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }
        if octets[0] == 127 || octets[0] == 10 { return true }
        if octets[0] == 192 && octets[1] == 168 { return true }
        if octets[0] == 172 && (16...31).contains(octets[1]) { return true }
        if octets[0] == 169 && octets[1] == 254 { return true }
        if octets[0] == 100 && (64...127).contains(octets[1]) { return true } // Tailscale CGNAT
        return false
    }

    static func displayBrowserTitle(title: String?, urlString: String) -> String {
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        if let url = URL(string: urlString), let host = url.host(), !host.isEmpty {
            if let port = url.port {
                return "\(host):\(port)"
            }
            return host
        }
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Browser" : trimmed
    }

    // MARK: Files Tree & Classification

    /// Brand-cased issue tracker names ("github" → "GitHub"); unknown trackers fall back to capitalized.
    static func trackerDisplayName(_ tracker: String) -> String {
        switch tracker.lowercased() {
        case "github": "GitHub"
        case "gitlab": "GitLab"
        case "linear": "Linear"
        case "jira": "Jira"
        default: tracker.capitalized
        }
    }

    static func fileName(from path: String) -> String {
        let cleaned = path.hasSuffix("/") ? String(path.dropLast()) : path
        if let slash = cleaned.lastIndex(of: "/") {
            return String(cleaned[cleaned.index(after: slash)...])
        }
        return cleaned
    }

    static func parentDirectory(of path: String) -> String {
        let cleaned = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard let slash = cleaned.lastIndex(of: "/") else { return "" }
        return String(cleaned[..<slash])
    }

    static func breadcrumbSegments(for path: String) -> [(name: String, path: String)] {
        let parts = path.split(separator: "/").map(String.init)
        var result: [(name: String, path: String)] = []
        var current = ""
        for part in parts {
            current = current.isEmpty ? part : "\(current)/\(part)"
            result.append((name: part, path: current))
        }
        return result
    }

    /// Builds a deterministic, sorted tree list from loaded directory slices (directories first, then files).
    static func buildFileTreeRows(
        entriesByDirectory: [String: [ProjectEntry]],
        expandedDirectories: Set<String>
    ) -> [FileTreeRow] {
        var rows: [FileTreeRow] = []
        var visited = Set<String>()

        func appendChildren(of directory: String, depth: Int) {
            guard visited.insert(directory).inserted else { return }
            let entries = sortEntries(entriesByDirectory[directory] ?? [])
            for entry in entries {
                let isExpanded = entry.kind == .directory && expandedDirectories.contains(entry.path)
                rows.append(
                    FileTreeRow(
                        path: entry.path,
                        name: entry.name,
                        kind: entry.kind,
                        depth: depth,
                        isExpanded: isExpanded,
                        ignored: entry.ignored == true
                    )
                )
                if isExpanded {
                    appendChildren(of: entry.path, depth: depth + 1)
                }
            }
        }

        appendChildren(of: "", depth: 0)
        return rows
    }

    static func sortEntries(_ entries: [ProjectEntry]) -> [ProjectEntry] {
        entries.sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind == .directory
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func classifyFilePreview(path: String) -> WorkspaceFilePreviewKind {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "md", "markdown", "mdx":
            return .markdown
        case "png", "jpg", "jpeg", "gif", "webp", "bmp", "ico", "heic", "tiff", "tif":
            return .image
        case "pdf", "zip", "tar", "gz", "tgz", "7z", "rar", "dmg", "pkg", "exe", "bin", "dylib",
             "so", "a", "o", "wasm", "ttf", "otf", "woff", "woff2", "mp3", "wav", "m4a", "mp4",
             "mov", "avi", "mkv", "sqlite", "db":
            return .binary
        default:
            return .code(language: languageName(forExtension: ext, fileName: fileName(from: path)))
        }
    }

    static func languageName(forExtension ext: String, fileName: String) -> String? {
        switch ext {
        case "swift": return "Swift"
        case "ts", "mts", "cts": return "TypeScript"
        case "tsx": return "TSX"
        case "js", "mjs", "cjs": return "JavaScript"
        case "jsx": return "JSX"
        case "json", "jsonc": return "JSON"
        case "yaml", "yml": return "YAML"
        case "toml": return "TOML"
        case "html", "htm": return "HTML"
        case "css", "scss", "less": return "CSS"
        case "py": return "Python"
        case "rs": return "Rust"
        case "go": return "Go"
        case "rb": return "Ruby"
        case "sh", "bash", "zsh": return "Shell"
        case "sql": return "SQL"
        case "xml", "plist", "svg": return "XML"
        case "c", "h": return "C"
        case "cpp", "cc", "cxx", "hpp": return "C++"
        case "java": return "Java"
        case "kt", "kts": return "Kotlin"
        default:
            let lower = fileName.lowercased()
            if lower == "dockerfile" { return "Dockerfile" }
            if lower == "makefile" { return "Makefile" }
            return nil
        }
    }

    static func fileSymbol(for path: String, kind: ProjectEntryKind, isExpanded: Bool = false) -> String {
        if kind == .directory {
            return isExpanded ? "folder.fill" : "folder"
        }
        switch classifyFilePreview(path: path) {
        case .image: return "photo"
        case .markdown: return "doc.richtext"
        case .binary: return "doc.zipper"
        case .code(let lang):
            if lang == "JSON" || lang == "YAML" || lang == "TOML" { return "curlybraces" }
            if lang != nil { return "chevron.left.forwardslash.chevron.right" }
            return "doc.text"
        }
    }

    static func formatByteCount(_ bytes: Int) -> String {
        if bytes < 1_024 { return "\(bytes) B" }
        if bytes < 1_024 * 1_024 {
            return String(format: "%.1f KB", Double(bytes) / 1_024)
        }
        return String(format: "%.1f MB", Double(bytes) / (1_024 * 1_024))
    }

    // MARK: Pull Request URL Parsing

    /// Parses a GitHub or GitLab PR/MR URL into host, repository (`owner/name`), and number.
    static func parsePullRequestURL(_ raw: String) -> ParsedPullRequestURL? {
        guard let url = normalizeBrowserURL(raw),
              let host = url.host()?.lowercased(),
              !host.isEmpty
        else { return nil }

        let parts = url.pathComponents.filter { $0 != "/" }
        // GitHub: /{owner}/{repo}/pull/{number}
        if parts.count >= 4, parts[2] == "pull", let number = Int(parts[3]), number > 0 {
            let repo = "\(parts[0])/\(parts[1])"
            return ParsedPullRequestURL(host: host, repository: repo, number: number, url: url.absoluteString)
        }
        // GitLab: /{group...}/{project}/-/merge_requests/{number}
        if let dashIdx = parts.firstIndex(of: "-"),
           dashIdx >= 2,
           dashIdx + 2 < parts.count,
           parts[dashIdx + 1] == "merge_requests",
           let number = Int(parts[dashIdx + 2]),
           number > 0
        {
            let repo = parts[..<dashIdx].joined(separator: "/")
            return ParsedPullRequestURL(host: host, repository: repo, number: number, url: url.absoluteString)
        }
        return nil
    }

    // MARK: Subagent Tab Presentation

    /// Resolves the live tab status dot tone for a `.subagent` tab from its live `ThreadStore` state and status.
    static func subagentStatusDotTone(
        status: SubagentStatus,
        hasPendingApprovals: Bool = false,
        isLiveRunning: Bool = false
    ) -> RightPanelStatusBadge.Tone? {
        if hasPendingApprovals { return .warning }
        if isLiveRunning { return .accent }
        switch status {
        case .pending, .running:
            return .accent
        case .waiting:
            return .warning
        case .completed:
            return .success
        case .failed:
            return .danger
        case .idle, .cancelled, .interrupted, .unknown:
            return nil
        }
    }

    static func statusDotColor(for tone: RightPanelStatusBadge.Tone) -> Color {
        switch tone {
        case .accent: SwftColor.accent
        case .warning: SwftColor.warning
        case .success: SwftColor.success
        case .danger: SwftColor.danger
        case .merged: RightPanelColor.merged
        case .neutral: SwftColor.textTertiary
        }
    }

    static func subagentStatus(from runStatus: RunStatus) -> SubagentStatus {
        switch runStatus {
        case .preparing, .queued, .starting: .pending
        case .running: .running
        case .waiting: .waiting
        case .completed: .completed
        case .failed: .failed
        case .cancelled: .cancelled
        case .interrupted: .interrupted
        case .rolledBack: .idle
        case .unknown(let raw): SubagentStatus(rawValue: raw)
        }
    }
}
