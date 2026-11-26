import Foundation
import SwftDesign
import SwftKit

/// Normalized lifecycle status for an inline subagent item.
enum SubagentStatus: Hashable, Sendable {
    case pending
    case running
    case waiting
    case idle
    case completed
    case failed
    case cancelled
    case interrupted
    case unknown(String)

    init(rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "pending", "queued", "preparing", "starting":
            self = .pending
        case "running", "working", "in_progress":
            self = .running
        case "waiting":
            self = .waiting
        case "idle":
            self = .idle
        case "completed", "done", "succeeded":
            self = .completed
        case "failed", "error":
            self = .failed
        case "cancelled", "canceled":
            self = .cancelled
        case "interrupted", "stopped":
            self = .interrupted
        default:
            self = .unknown(rawValue)
        }
    }

    var isActive: Bool {
        switch self {
        case .pending, .running, .waiting: true
        default: false
        }
    }

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled, .interrupted: true
        default: false
        }
    }

    var isFailed: Bool { self == .failed }
    var isWaiting: Bool { self == .waiting }
    var showsSpinner: Bool { self == .pending || self == .running }

    var displayLabel: String {
        switch self {
        case .pending: return "Queued"
        case .running: return "Running"
        case .waiting: return "Waiting"
        case .idle: return "Idle · resumable"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        case .interrupted: return "Stopped"
        case .unknown(let raw):
            let cleaned = raw.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let first = cleaned.first else { return "Unknown" }
            return first.uppercased() + cleaned.dropFirst()
        }
    }

    var badgeStatus: SubagentBadgeStatus {
        switch self {
        case .pending: .pending
        case .running: .running
        case .waiting: .waiting
        case .idle: .idle
        case .completed: .completed
        case .failed: .failed
        case .cancelled: .cancelled
        case .interrupted: .interrupted
        case .unknown: .idle
        }
    }
}

/// Destination resolved when clicking a delegated subagent row.
struct SubagentNavigationTarget: Equatable, Hashable, Sendable {
    let threadID: String
    let environmentID: String?
    let title: String
    let provider: ProviderKind
    let providerDriver: String
    let providerDisplayName: String?
    let providerIconURL: String?
    let isRemoteLinked: Bool
}

/// Back-to-parent breadcrumb data shown in `TopBar` while viewing a child subagent thread.
struct SubagentParentLink: Equatable, Hashable, Sendable {
    let threadID: String
    let title: String
    let environmentID: String?
}

/// Aggregate timing and status summary for a group of consecutive parallel subagents.
struct SubagentGroupTiming: Equatable, Hashable, Sendable {
    let isActive: Bool
    let hasSpinnerActivity: Bool
    let hasWaiting: Bool
    let hasFailed: Bool
    let startedAt: Date?
    let completedAt: Date?
}

/// Pure formatting, grouping, timing, and navigation logic for inline subagent transcript indicators.
/// Mirrors T3 Code's `subagentDisplay.ts`, `TimelineV2EventRow.logic.ts`, `V2LifecycleRow.tsx`, and `AgentElapsed.tsx`.
enum SubagentDisplayLogic {

    // MARK: - Title & Detail Formatting

    /// Formats a subagent's display title, matching `formatSubagentDisplayTitle` + `promptTitle`.
    static func formatDisplayTitle(_ rawTitle: String?, fallbackPrompt: String = "") -> String {
        if let raw = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            let stripped = stripSubagentPrefix(raw)
            if !stripped.isEmpty {
                if let formattedPath = formatRootPathTitle(stripped) {
                    return formattedPath
                }
                return stripped
            }
        }
        let promptLine = firstCollapsedLine(fallbackPrompt)
        if !promptLine.isEmpty {
            return truncatePromptTitle(promptLine, limit: 80)
        }
        return "Subagent"
    }

    /// Cleans a subagent progress/result snippet for compact single-line card display (`subagentCardDetail`).
    static func cleanCardDetail(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.range(of: #"^Child task ended with status\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return nil
        }

        // Replace markdown links/images `![label](url)` / `[label](url)` with `label`.
        var text = trimmed.replacingOccurrences(
            of: #"!?\[([^\]]+)\]\((?:\\.|[^\\()]|\((?:\\.|[^\\()])*\))*\)"#,
            with: "$1",
            options: .regularExpression
        )
        // Strip backticks and leading list markers.
        text = text.replacingOccurrences(of: "`", with: "")
        text = text.replacingOccurrences(
            of: #"(?m)^[ \t]*[-*][ \t]+"#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Picks the best concise preview snippet for a subagent based on whether it has settled.
    static func detailPreview(
        status: SubagentStatus,
        progress: String?,
        result: String?
    ) -> String? {
        let settled = status.isTerminal || status == .idle
        let preferred = settled ? result : progress
        let fallback = settled ? progress : result
        return cleanCardDetail(preferred) ?? cleanCardDetail(fallback)
    }

    /// Resolves the body section shown when a native/non-navigable subagent card is expanded inline.
    static func inlineExpandedBody(for item: SubagentItem) -> (label: String, text: String)? {
        if item.status == .failed {
            if let text = nonEmpty(item.result) ?? nonEmpty(item.progress) {
                return ("Error", text)
            }
            return nil
        }
        if item.status.isTerminal || item.status == .idle {
            if let text = nonEmpty(item.result) {
                return ("Summary", text)
            }
            if let text = nonEmpty(item.progress) {
                return ("Last progress", text)
            }
            return nil
        }
        if let text = nonEmpty(item.progress) {
            return ("Progress", text)
        }
        if let text = nonEmpty(item.result) {
            return ("Summary", text)
        }
        return nil
    }

    // MARK: - Elapsed Timing

    /// Formats a subagent's elapsed time (`14s`, `1m 22s`, `1h 04m`), or nil when timestamps are unavailable.
    static func formatElapsed(
        startedAt: Date?,
        completedAt: Date?,
        status: SubagentStatus,
        now: Date
    ) -> String? {
        SubagentElapsedFormatter.format(
            startedAt: startedAt,
            completedAt: completedAt,
            isActive: status.isActive,
            now: now
        )
    }

    static func formatElapsedSeconds(_ totalSeconds: Int) -> String {
        SubagentElapsedFormatter.formatSeconds(totalSeconds)
    }

    /// Compact status + elapsed summary string (e.g. `"Running · 14s"`, `"Completed · 1m 22s"`).
    static func statusAndElapsedText(for item: SubagentItem, now: Date) -> String {
        if let elapsed = formatElapsed(
            startedAt: item.startedAt,
            completedAt: item.completedAt,
            status: item.status,
            now: now
        ) {
            return "\(item.status.displayLabel) · \(elapsed)"
        }
        return item.status.displayLabel
    }

    // MARK: - Model Resolution

    /// Resolves a concise human-readable model badge for a subagent.
    static func resolveModelLabel(
        reportedModel: String?,
        executedModel: String?,
        modelSelection: ModelSelection?,
        childModelSelection: ModelSelection?,
        provider: ServerProvider?
    ) -> String? {
        let raw = nonEmpty(executedModel)
            ?? nonEmpty(reportedModel)
            ?? nonEmpty(modelSelection?.model)
            ?? nonEmpty(childModelSelection?.model)
        guard let raw else { return nil }
        if let catalogModel = provider?.models.first(where: { $0.slug == raw || $0.slug.caseInsensitiveCompare(raw) == .orderedSame }) {
            let label = catalogModel.displayName
            if let qualifier = nonEmpty(catalogModel.subProvider) {
                return stripLeadingQualifier(qualifier, from: label)
            }
            return label
        }
        return formatModelSlugName(raw)
    }

    /// Formats a raw model slug (e.g. `"claude-sonnet-4-5"`, `"gpt-5.4-mini"`) into a clean display name.
    static func formatModelSlugName(_ slug: String) -> String {
        let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return slug }
        let leaf = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
        if leaf.contains(" ") { return leaf }

        let parts = leaf.split(separator: "-").map(String.init)
        guard parts.count > 1 else { return leaf }

        var output: [String] = []
        var index = 0
        while index < parts.count {
            let part = parts[index]
            let lower = part.lowercased()
            // Merge adjacent numeric version components (`4`, `5` -> `4.5`).
            if part.allSatisfy(\.isNumber),
               index + 1 < parts.count,
               parts[index + 1].allSatisfy(\.isNumber),
               parts[index + 1].count <= 2,
               part.count <= 2
            {
                output.append("\(part).\(parts[index + 1])")
                index += 2
                continue
            }
            // Drop trailing 8-digit release date suffix (`20250929`).
            if part.count == 8 && part.allSatisfy(\.isNumber) && index == parts.count - 1 {
                index += 1
                continue
            }
            switch lower {
            case "gpt":
                if index + 1 < parts.count, let next = parts[index + 1].first, next.isNumber {
                    output.append("GPT-\(parts[index + 1])")
                    index += 2
                    continue
                }
                output.append("GPT")
            case "claude":
                output.append("Claude")
            case "gemini":
                output.append("Gemini")
            case "codex":
                output.append("Codex")
            case "opus", "sonnet", "haiku", "flash", "pro", "mini", "nano", "lite", "max", "fast", "spark", "luna", "astra", "fable", "neon":
                output.append(lower.prefix(1).uppercased() + lower.dropFirst())
            default:
                if part.first?.isNumber == true {
                    output.append(part)
                } else {
                    output.append(part.prefix(1).uppercased() + part.dropFirst())
                }
            }
            index += 1
        }
        return output.joined(separator: " ")
    }

    // MARK: - Consecutive Grouping & Aggregate Status

    /// Two consecutive subagent rows group together when spawned in the same run and provider turn.
    static func canGroupConsecutive(_ lhs: SubagentItem, _ rhs: SubagentItem) -> Bool {
        lhs.runID == rhs.runID && lhs.providerTurnID == rhs.providerTurnID
    }

    static func groupHeaderTitle(count: Int) -> String {
        count == 1 ? "1 subagent" : "\(count) subagents"
    }

    /// Concise status breakdown for a parallel subagent group (e.g. `"2 running · 1 done"`).
    static func summarizeGroupStatuses(_ statuses: [SubagentStatus]) -> String {
        var running = 0
        var waiting = 0
        var done = 0
        var failed = 0
        var stopped = 0
        var idle = 0

        for status in statuses {
            switch status {
            case .pending, .running: running += 1
            case .waiting: waiting += 1
            case .completed: done += 1
            case .failed: failed += 1
            case .cancelled, .interrupted: stopped += 1
            case .idle, .unknown: idle += 1
            }
        }

        var parts: [String] = []
        if running > 0 { parts.append("\(running) running") }
        if waiting > 0 { parts.append("\(waiting) waiting") }
        if done > 0 { parts.append("\(done) done") }
        if failed > 0 { parts.append("\(failed) failed") }
        if stopped > 0 { parts.append("\(stopped) stopped") }
        if idle > 0 { parts.append("\(idle) idle") }
        return parts.joined(separator: " · ")
    }

    /// Computes aggregate start/end timing and activity flags across a parallel subagent group.
    static func groupTiming(for members: [SubagentItem]) -> SubagentGroupTiming {
        var earliestStart: Date?
        var latestEnd: Date?
        var endUnknown = false
        var anyActive = false
        var anySpinner = false
        var anyWaiting = false
        var anyFailed = false

        for member in members {
            if let start = member.startedAt {
                earliestStart = earliestStart.map { min($0, start) } ?? start
            }
            if let end = member.completedAt {
                latestEnd = latestEnd.map { max($0, end) } ?? end
            } else {
                endUnknown = true
            }
            if member.status.isActive { anyActive = true }
            if member.status.showsSpinner { anySpinner = true }
            if member.status.isWaiting { anyWaiting = true }
            if member.status.isFailed { anyFailed = true }
        }

        return SubagentGroupTiming(
            isActive: anyActive,
            hasSpinnerActivity: anySpinner,
            hasWaiting: anyWaiting,
            hasFailed: anyFailed,
            startedAt: earliestStart,
            completedAt: (anyActive || endUnknown) ? nil : latestEnd
        )
    }

    // MARK: - Navigation Resolution

    /// Resolves whether clicking a subagent row navigates to a child thread (and in which environment),
    /// or returns `nil` for native/read-only subagents that expand inline instead.
    static func navigationTarget(
        for item: SubagentItem,
        parentEnvironmentID: String?,
        knownEnvironmentIDs: Set<String> = []
    ) -> SubagentNavigationTarget? {
        if let childID = nonEmpty(item.childThreadID) {
            return SubagentNavigationTarget(
                threadID: childID,
                environmentID: parentEnvironmentID,
                title: item.title,
                provider: item.provider,
                providerDriver: item.providerDriver,
                providerDisplayName: item.providerDisplayName,
                providerIconURL: item.providerIconURL,
                isRemoteLinked: false
            )
        }
        if let remoteThreadID = nonEmpty(item.remoteThreadID),
           let remoteEnvID = nonEmpty(item.remoteEnvironmentID),
           knownEnvironmentIDs.contains(remoteEnvID)
        {
            return SubagentNavigationTarget(
                threadID: remoteThreadID,
                environmentID: remoteEnvID,
                title: item.title,
                provider: item.provider,
                providerDriver: item.providerDriver,
                providerDisplayName: item.providerDisplayName,
                providerIconURL: item.providerIconURL,
                isRemoteLinked: true
            )
        }
        return nil
    }

    // MARK: - Private Helpers

    private static func stripSubagentPrefix(_ title: String) -> String {
        title.replacingOccurrences(
            of: #"^Subagent:\s*"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func formatRootPathTitle(_ title: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"^/root/(?:[^/]+/)*([^/]+)/?$"#) else {
            return nil
        }
        let nsRange = NSRange(title.startIndex..<title.endIndex, in: title)
        guard let match = regex.firstMatch(in: title, range: nsRange),
              match.numberOfRanges >= 2,
              let segmentRange = Range(match.range(at: 1), in: title)
        else {
            return nil
        }
        let segment = String(title[segmentRange])
            .replacingOccurrences(of: #"[_\s]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !segment.isEmpty else { return title }
        return segment
            .split(separator: " ")
            .map { word in
                guard let first = word.first else { return "" }
                return first.uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    private static func firstCollapsedLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty }) ?? ""
    }

    private static func truncatePromptTitle(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let prefix = String(text.prefix(max(1, limit - 3))).trimmingCharacters(in: .whitespaces)
        return prefix + "…"
    }

    private static func stripLeadingQualifier(_ qualifier: String, from label: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: qualifier)
        let stripped = label.replacingOccurrences(
            of: #"^\#(escaped)(?:\s*[.:/-]\s*|\s+)"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? label : stripped
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
