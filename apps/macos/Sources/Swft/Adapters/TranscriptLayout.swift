import Foundation
import SwftKit

/// Folds each turn's intermediate work (thoughts, tool calls, interim commentary, resolved approvals, quiet notices)
/// into one `WorkFold` row, leaving the user's message, the final answer, errors and pending approvals visible.
enum TranscriptLayout {
    static func rows(for items: [TranscriptItem], isRunning: Bool) -> [TranscriptRow] {
        let turns = splitTurns(items)
        var rows: [TranscriptRow] = []
        for (index, turn) in turns.enumerated() {
            let isLast = index == turns.count - 1
            let live = isLast && (isRunning || turn.contains(where: isInFlight))
            rows += fold(turn, live: live)
        }
        return rows
    }

    // MARK: - Turns

    private static func splitTurns(_ items: [TranscriptItem]) -> [[TranscriptItem]] {
        var turns: [[TranscriptItem]] = []
        for item in items {
            if case .user = item.kind {
                turns.append([item])
            } else if turns.isEmpty {
                turns.append([item])
            } else {
                turns[turns.count - 1].append(item)
            }
        }
        return turns
    }

    private static func isInFlight(_ item: TranscriptItem) -> Bool {
        switch item.kind {
        case .assistant(_, let streaming): streaming
        case .toolCall(let call): call.status == .running
        case .subagent(let subagent): subagent.status.isActive
        case .approval(let approval): approval.status == .pending
        default: false
        }
    }

    private static func fold(_ turn: [TranscriptItem], live: Bool) -> [TranscriptRow] {
        guard let first = turn.first else { return [] }
        let settledAnswerIndex = live ? nil : turn.indices.last {
            if case .assistant = turn[$0].kind { true } else { false }
        }
        let hasSubagents = turn.contains { if case .subagent = $0.kind { true } else { false } }

        var rows: [TranscriptRow] = []
        var steps: [WorkStep] = []
        var segmentItems: [TranscriptItem] = []
        var foldPosition: Int?
        var flushedFoldCount = 0

        func addStep(_ step: WorkStep, item: TranscriptItem) {
            if foldPosition == nil { foldPosition = rows.count }
            steps.append(step)
            segmentItems.append(item)
        }

        func flushWorkSegment(isTail: Bool) {
            guard let position = foldPosition, !steps.isEmpty else {
                steps.removeAll()
                segmentItems.removeAll()
                foldPosition = nil
                return
            }
            defer {
                steps.removeAll()
                segmentItems.removeAll()
                foldPosition = nil
            }

            let segmentLive: Bool
            if isTail {
                let hasBlockingApproval = rows[position...].contains {
                    if case .approval = $0 { true } else { false }
                }
                let hasTrailingAnswer = rows[position...].contains {
                    if case .assistant = $0 { true } else { false }
                }
                segmentLive = live && !hasBlockingApproval && !hasTrailingAnswer
            } else {
                segmentLive = false
            }

            // A turn whose only "work" is a single notice reads better as that notice's quiet line;
            // multiple notices stay folded into one collapsed row.
            let notes = steps.compactMap { step -> TranscriptRow? in
                guard case .note(let title, let message) = step.kind else { return nil }
                return .note(id: step.id, title: title, message: message, isError: false)
            }
            if !segmentLive, notes.count == steps.count, notes.count == 1 {
                rows.insert(contentsOf: notes, at: position)
                return
            }

            let foldID = flushedFoldCount == 0
                ? "work:\(first.id)"
                : "work:\(first.id):\(steps[0].id)"
            flushedFoldCount += 1

            let fold = makeFold(
                id: foldID,
                steps: steps,
                timingItems: (hasSubagents || live) ? segmentItems : turn,
                turn: turn,
                answerIndex: isTail ? settledAnswerIndex : nil,
                live: segmentLive
            )
            rows.insert(.work(fold), at: position)
        }

        for (index, item) in turn.enumerated() {
            switch item.kind {
            case .user(let text, let attachments):
                rows.append(.user(id: item.id, text: text, attachments: attachments))
            case .assistant(let blocks, let streaming):
                // Match T3 Code: while a turn is live, assistant messages stay visible inline in chronological
                // order between work groups; once settled, interim messages fold into one "Worked for …" row.
                if live {
                    flushWorkSegment(isTail: false)
                    rows.append(.assistant(id: item.id, blocks: blocks, streaming: streaming))
                } else if index == settledAnswerIndex {
                    rows.append(.assistant(id: item.id, blocks: blocks, streaming: streaming))
                } else {
                    addStep(WorkStep(id: item.id, kind: .commentary(blocks)), item: item)
                }
            case .toolCall(let call):
                if call.kind == .thinking {
                    addStep(WorkStep(id: item.id, kind: .thought(call.output ?? call.detail)), item: item)
                } else {
                    addStep(WorkStep(id: item.id, kind: .tool(call)), item: item)
                }
            case .subagent(let subagent):
                flushWorkSegment(isTail: false)
                if let last = rows.last {
                    switch last {
                    case .subagent(let previous) where SubagentDisplayLogic.canGroupConsecutive(previous, subagent):
                        rows[rows.count - 1] = .subagentGroup(
                            SubagentGroup(id: "subagent-group:\(previous.id)", members: [previous, subagent])
                        )
                        continue
                    case .subagentGroup(var group) where group.members.last.map({ SubagentDisplayLogic.canGroupConsecutive($0, subagent) }) == true:
                        group.members.append(subagent)
                        rows[rows.count - 1] = .subagentGroup(group)
                        continue
                    default:
                        break
                    }
                }
                rows.append(.subagent(subagent))
            case .approval(let approval):
                if approval.status == .pending {
                    rows.append(.approval(id: item.id, approval))
                } else {
                    addStep(WorkStep(id: item.id, kind: .approval(approval)), item: item)
                }
            case .notice(let title, let message, let isError):
                if isError {
                    rows.append(.note(id: item.id, title: title, message: message, isError: true))
                } else {
                    addStep(WorkStep(id: item.id, kind: .note(title: title, message: message)), item: item)
                }
            }
        }

        flushWorkSegment(isTail: true)
        return rows
    }

    // MARK: - Labels

    private static func makeFold(
        id: String,
        steps: [WorkStep],
        timingItems: [TranscriptItem],
        turn: [TranscriptItem],
        answerIndex: Int?,
        live: Bool
    ) -> WorkFold {
        let failed = steps.filter { step in
            if case .tool(let call) = step.kind { call.status == .failed } else { false }
        }.count
        if live {
            return WorkFold(
                id: id,
                steps: steps,
                isLive: true,
                title: currentStep(steps),
                subtitle: summaryLabel(isCurrent(steps.last) ? Array(steps.dropLast()) : steps),
                liveThought: latestThoughtPreview(in: steps),
                failedCount: failed
            )
        }

        let summary = summaryLabel(steps)
        let onlyNotes = !steps.isEmpty && steps.allSatisfy {
            if case .note = $0.kind { true } else { false }
        }
        let title: String
        if onlyNotes {
            title = summary ?? "\(steps.count) notices"
        } else if let answerIndex, case .assistant(_, false) = turn[answerIndex].kind, let seconds = workedSeconds(timingItems), seconds >= 1 {
            title = "Worked for \(formatDuration(seconds))"
        } else {
            title = summary ?? "Worked"
        }
        return WorkFold(
            id: id,
            steps: steps,
            isLive: false,
            title: title,
            subtitle: nil,
            liveThought: nil,
            failedCount: failed
        )
    }

    /// Returns the latest non-empty reasoning thought in `steps` for T3 Code's `work-live` thought preview.
    static func latestThoughtPreview(in steps: [WorkStep]) -> WorkThoughtPreview? {
        for step in steps.reversed() {
            guard case .thought(let raw) = step.kind,
                  let line = liveThoughtLine(from: raw)
            else { continue }
            return WorkThoughtPreview(id: step.id, text: line)
        }
        return nil
    }

    /// Extracts one clean summary line from reasoning markdown, mirroring T3 Code's `liveThoughtLine`:
    /// uses a leading `**Bold heading**` when present; otherwise strips markdown and takes the first sentence.
    static func liveThoughtLine(from markdown: String) -> String? {
        let heading = leadingBoldHeading(in: markdown)
        var text = heading ?? markdown
        // Strip markdown links/images down to their label.
        text = text.replacingOccurrences(of: #"!?\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        // Strip line-leading heading / list / blockquote markers.
        text = text.replacingOccurrences(of: #"(?m)^[ \t]*(?:#{1,6}|[-*+]|\d+\.|>)[ \t]+"#, with: "", options: .regularExpression)
        // Strip inline code, bold, strikethrough, and emphasis markers.
        text = text.replacingOccurrences(of: #"`+|\*\*|~~"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(^|[^\w*])[*_]([^*_\n]+)[*_](?![\w*])"#, with: "$1$2", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty, text != "…", text != "..." else { return nil }
        if heading != nil { return text }

        if let range = text.range(of: #"[.?!]["'”’)]?(?=\s)|[。！？]["'”’）」』]?"#, options: .regularExpression) {
            return String(text[..<range.upperBound])
        }
        return text
    }

    private static func leadingBoldHeading(in markdown: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"^\s*\*\*([^*\r\n]+)\*\*[ \t]*\r?(?:\n|$)"#),
              let match = regex.firstMatch(in: markdown, range: NSRange(markdown.startIndex..., in: markdown)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: markdown)
        else { return nil }
        return String(markdown[range])
    }

    /// The step the live row is narrating, which the running summary leaves out.
    private static func isCurrent(_ step: WorkStep?) -> Bool {
        switch step?.kind {
        case .tool(let call): call.status == .running
        case .thought: true
        default: false
        }
    }

    private static func currentStep(_ steps: [WorkStep]) -> String {
        guard let last = steps.last else { return "Thinking…" }
        if case .tool(let call) = last.kind, call.status == .running {
            let subject = call.kind == .command ? call.detail : shortPath(call.detail)
            return "\(call.title) \(subject)"
        }
        return "Thinking…"
    }

    /// "Read 2 files, ran swift build" — clauses in the order the work first happened.
    static func summaryLabel(_ steps: [WorkStep]) -> String? {
        var order: [ToolCallItem.Kind] = []
        var calls: [ToolCallItem.Kind: [ToolCallItem]] = [:]
        var thoughts = 0
        var notes = 0
        for step in steps {
            switch step.kind {
            case .tool(let call):
                if calls[call.kind] == nil { order.append(call.kind) }
                calls[call.kind, default: []].append(call)
            case .thought:
                thoughts += 1
            case .note:
                notes += 1
            default:
                break
            }
        }
        var clauses: [String] = order.compactMap { kind in
            guard let group = calls[kind] else { return nil }
            let n = group.count
            switch kind {
            case .read: return "read \(plural(n, "file"))"
            case .edit: return "edited \(plural(n, "file"))"
            case .command:
                if n == 1, group[0].detail.count <= 28 { return "ran \(group[0].detail)" }
                return "ran \(plural(n, "command"))"
            case .search:
                if n == 1 { return "searched for \(group[0].detail)" }
                return "searched \(n) times"
            case .thinking: return nil
            }
        }
        if clauses.isEmpty, thoughts > 0 { clauses = ["thought"] }
        if clauses.isEmpty, notes > 0 { clauses = [plural(notes, "notice")] }
        guard let first = clauses.first else { return nil }
        clauses[0] = first.prefix(1).uppercased() + first.dropFirst()
        return clauses.joined(separator: ", ")
    }

    private static func workedSeconds(_ turn: [TranscriptItem]) -> TimeInterval? {
        guard let start = turn.compactMap(\.startedAt).min() else { return nil }
        let ends = turn.compactMap { $0.completedAt ?? $0.startedAt }
        guard let end = ends.max() else { return nil }
        return end.timeIntervalSince(start)
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s)s" }
        if s < 3600 { return s % 60 == 0 ? "\(s / 60)m" : "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }

    private static func plural(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }

    private static func shortPath(_ path: String) -> String {
        guard path.contains("/"), !path.contains(" ") else { return path }
        return (path as NSString).lastPathComponent
    }
}

/// The last projections of recently left threads, most recent first, so switching back renders immediately.
/// Only ever answers for the thread asked about.
struct RecentProjections {
    private(set) var entries: [ThreadProjection] = []
    var limit = 8

    mutating func remember(_ projection: ThreadProjection?) {
        guard let projection else { return }
        entries.removeAll { $0.thread.id == projection.thread.id }
        entries.insert(projection, at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
    }

    func projection(for threadID: String) -> ThreadProjection? {
        entries.first { $0.thread.id == threadID }
    }
}
