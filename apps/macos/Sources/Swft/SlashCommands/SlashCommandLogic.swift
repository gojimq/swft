import Foundation
import SwftKit

/// A detected `/` token in the composer at or before the caret.
struct SlashCommandTrigger: Equatable, Sendable {
    let query: String
    /// UTF-16 offset of the leading `/`.
    let rangeStart: Int
    /// UTF-16 offset of the caret at detection time.
    let rangeEnd: Int
    /// True when only whitespace precedes the `/` token.
    let isAtPromptStart: Bool
}

enum BuiltInSlashCommand: String, Equatable, Hashable, Sendable {
    case model
    case clear
    case plan
    case defaultMode = "default"
    case side
    case btw

    var commandName: String { rawValue }
}

enum SkillSourceKind: String, Equatable, Hashable, Sendable {
    case app
    case repo
    case project
    case personal
    case system
    case other

    var badgeLabel: String {
        switch self {
        case .app: "App"
        case .repo: "Repo"
        case .project: "Project"
        case .personal: "Personal"
        case .system: "System"
        case .other: "Provider"
        }
    }

    var systemImage: String {
        switch self {
        case .app: "square.grid.2x2"
        case .repo, .project: "folder"
        case .personal: "person"
        case .system: "gearshape"
        case .other: "shippingbox"
        }
    }
}

enum SlashCommandGroup: Int, Equatable, Hashable, Sendable {
    case builtIn = 0
    case provider = 1
    case skill = 2
}

enum SlashCommandSource: Equatable, Hashable, Sendable {
    case builtIn
    case provider(label: String, driver: String)
    case skill(SkillSourceKind)

    var badgeLabel: String {
        switch self {
        case .builtIn: "Built-in"
        case .provider(let label, _): label
        case .skill(let kind): kind.badgeLabel
        }
    }
}

enum SlashCommandItemKind: Equatable, Hashable, Sendable {
    case builtIn(BuiltInSlashCommand)
    case providerCommand(ServerProviderSlashCommand)
    case skill(ServerProviderSkill)
}

struct SlashCommandItem: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let kind: SlashCommandItemKind
    /// Canonical command label shown in the menu (e.g. `/model`, `/learn`, `/skill:test-t3-app`).
    let label: String
    /// Primary searchable name without leading `/`.
    let name: String
    /// Optional argument hint reported by the provider (e.g. `<topic>`).
    let inputHint: String?
    let description: String
    let source: SlashCommandSource
    let group: SlashCommandGroup
}

struct SlashCommandSection: Identifiable, Equatable, Sendable {
    let id: String
    let title: String?
    let items: [SlashCommandItem]
}

enum SlashCommandKey: Equatable, Sendable {
    case up
    case down
    case tab
    case enter
    case escape
}

enum SlashCommandAction: Equatable, Sendable {
    case openModelPicker(updatedPrompt: String, cursorUTF16: Int)
    case armFreshSession(updatedPrompt: String, cursorUTF16: Int)
    case clearDraftOrStartNewThread(updatedPrompt: String, cursorUTF16: Int)
    case setInteractionMode(ProviderInteractionMode, updatedPrompt: String, cursorUTF16: Int)
    case replacePrompt(text: String, cursorUTF16: Int)
}

enum SlashCommandLogic {
    static let workspaceSnapshotTTL: TimeInterval = 5 * 60
    static let workspaceSnapshotRetryCooldown: TimeInterval = 10

    // MARK: - Trigger Detection

    /// Detects a `/` slash-command trigger at `cursorUTF16` (defaults to end of `text`).
    /// Mirrors `detectComposerTrigger` and `isPathWord` in `packages/shared/src/composerTrigger.ts`.
    static func detectTrigger(in text: String, cursorUTF16: Int? = nil) -> SlashCommandTrigger? {
        let utf16 = Array(text.utf16)
        let cursor = max(0, min(utf16.count, cursorUTF16 ?? utf16.count))
        guard cursor > 0 else { return nil }

        var tokenIdx = cursor - 1
        while tokenIdx >= 0 && !isWhitespace(utf16[tokenIdx]) {
            tokenIdx -= 1
        }
        let tokenStart = tokenIdx + 1
        guard tokenStart < cursor, utf16[tokenStart] == 0x2F else { // '/'
            return nil
        }

        if isPathWord(in: utf16, tokenStart: tokenStart, cursor: cursor) {
            return nil
        }

        let queryUnits = Array(utf16[(tokenStart + 1)..<cursor])
        let query = String(decoding: queryUnits, as: UTF16.self)
        let isAtPromptStart = utf16[0..<tokenStart].allSatisfy(isWhitespace)

        return SlashCommandTrigger(
            query: query,
            rangeStart: tokenStart,
            rangeEnd: cursor,
            isAtPromptStart: isAtPromptStart
        )
    }

    /// A second `/` or `\` anywhere in the whitespace-delimited token makes it a file path, not a command.
    static func isPathWord(in utf16: [UInt16], tokenStart: Int, cursor: Int) -> Bool {
        var wordEnd = cursor
        while wordEnd < utf16.count && !isWhitespace(utf16[wordEnd]) {
            wordEnd += 1
        }
        guard tokenStart + 1 < wordEnd else { return false }
        for idx in (tokenStart + 1)..<wordEnd {
            let unit = utf16[idx]
            if unit == 0x2F || unit == 0x5C { // '/' or '\'
                return true
            }
        }
        return false
    }

    /// Replaces `[rangeStart..<rangeEnd]` (UTF-16 offsets) with `replacement`, optionally swallowing
    /// one trailing space so inserting `/command ` before existing text doesn't leave double spaces.
    static func replaceRange(
        in text: String,
        rangeStart: Int,
        rangeEnd: Int,
        replacement: String,
        swallowTrailingSpace: Bool = true
    ) -> (text: String, cursorUTF16: Int) {
        let utf16 = Array(text.utf16)
        let safeStart = max(0, min(utf16.count, rangeStart))
        var safeEnd = max(safeStart, min(utf16.count, rangeEnd))

        if swallowTrailingSpace,
           replacement.hasSuffix(" "),
           safeEnd < utf16.count,
           utf16[safeEnd] == 0x20
        {
            safeEnd += 1
        }

        let replacementUnits = Array(replacement.utf16)
        var resultUnits: [UInt16] = []
        resultUnits.reserveCapacity(utf16.count - (safeEnd - safeStart) + replacementUnits.count)
        resultUnits.append(contentsOf: utf16[0..<safeStart])
        resultUnits.append(contentsOf: replacementUnits)
        resultUnits.append(contentsOf: utf16[safeEnd..<utf16.count])

        let nextText = String(decoding: resultUnits, as: UTF16.self)
        return (nextText, safeStart + replacementUnits.count)
    }

    // MARK: - Verbatim Command Parsing

    static func isClearCommand(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.caseInsensitiveCompare("/clear") == .orderedSame
    }

    static func isModelCommand(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.caseInsensitiveCompare("/model") == .orderedSame
    }

    static func parseSideChatCommand(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let prefix: String
        if lower == "/side" || lower.hasPrefix("/side ") || lower.hasPrefix("/side\n") || lower.hasPrefix("/side\t") {
            prefix = "/side"
        } else if lower == "/btw" || lower.hasPrefix("/btw ") || lower.hasPrefix("/btw\n") || lower.hasPrefix("/btw\t") {
            prefix = "/btw"
        } else {
            return nil
        }
        let remainder = trimmed.dropFirst(prefix.count)
        return remainder.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parseInteractionModeCommand(_ text: String) -> ProviderInteractionMode? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("/plan") == .orderedSame { return .plan }
        if trimmed.caseInsensitiveCompare("/default") == .orderedSame { return .default }
        return nil
    }

    // MARK: - Catalog Construction

    static func resolveSkillSourceKind(path: String, scope: String?) -> SkillSourceKind {
        let normalizedPath = path.replacingOccurrences(of: "\\", with: "/")
        if normalizedPath.contains("/.codex/plugins/") || normalizedPath.contains("/.agents/plugins/") {
            return .app
        }
        let normalizedScope = scope?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        switch normalizedScope {
        case "repo", "repository": return .repo
        case "project", "workspace", "local": return .project
        case "user", "personal": return .personal
        case "system": return .system
        default: return .other
        }
    }

    static func dedupeSkills(_ skills: [ServerProviderSkill]) -> [ServerProviderSkill] {
        var seen: Set<String> = []
        var result: [ServerProviderSkill] = []
        for skill in skills where skill.isUserInvocable {
            let key = skill.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            result.append(skill)
        }
        return result
    }

    /// Builds the full slash-command catalog for the current composer context, applying prompt-position
    /// filtering and deduplication between built-ins, provider slash commands, and provider skills.
    static func catalog(
        providerCommands: [ServerProviderSlashCommand],
        providerSkills: [ServerProviderSkill],
        providerLabel: String,
        providerDriver: String,
        isAtPromptStart: Bool,
        supportsFreshSession: Bool,
        supportsSideChat: Bool,
        supportsPlanModeToggle: Bool,
        currentInteractionMode: ProviderInteractionMode = .default,
        showSkills: Bool = true
    ) -> [SlashCommandItem] {
        let visibleSkills = showSkills ? dedupeSkills(providerSkills) : []
        let skillNameSet = Set(visibleSkills.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })

        // Deduplicate provider commands against visible skills and Swft's built-in `/clear`.
        let filteredProviderCommands: [ServerProviderSlashCommand] = {
            var seen: Set<String> = []
            return providerCommands.filter { command in
                let normalized = command.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !normalized.isEmpty else { return false }
                guard normalized != "clear" else { return false }
                guard !skillNameSet.contains(normalized) else { return false }
                return seen.insert(normalized).inserted
            }
        }()

        let providerHasPlanCommand = filteredProviderCommands.contains {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "plan"
        }

        var items: [SlashCommandItem] = []

        // Built-in commands
        items.append(
            SlashCommandItem(
                id: "slash:model",
                kind: .builtIn(.model),
                label: "/model",
                name: "model",
                inputHint: nil,
                description: "Switch response model",
                source: .builtIn,
                group: .builtIn
            )
        )

        if isAtPromptStart {
            items.append(
                SlashCommandItem(
                    id: "slash:clear",
                    kind: .builtIn(.clear),
                    label: "/clear",
                    name: "clear",
                    inputHint: nil,
                    description: supportsFreshSession
                        ? "Start a fresh session; earlier messages stay visible"
                        : "Start a fresh thread",
                    source: .builtIn,
                    group: .builtIn
                )
            )

            if supportsPlanModeToggle && !providerHasPlanCommand {
                if currentInteractionMode == .plan {
                    items.append(
                        SlashCommandItem(
                            id: "slash:default",
                            kind: .builtIn(.defaultMode),
                            label: "/default",
                            name: "default",
                            inputHint: nil,
                            description: "Return to default interaction mode",
                            source: .builtIn,
                            group: .builtIn
                        )
                    )
                } else {
                    items.append(
                        SlashCommandItem(
                            id: "slash:plan",
                            kind: .builtIn(.plan),
                            label: "/plan",
                            name: "plan",
                            inputHint: nil,
                            description: "Switch to plan mode before execution",
                            source: .builtIn,
                            group: .builtIn
                        )
                    )
                }
            }

            if supportsSideChat {
                items.append(
                    SlashCommandItem(
                        id: "slash:side",
                        kind: .builtIn(.side),
                        label: "/side",
                        name: "side",
                        inputHint: "question",
                        description: "Ask a side question in a new side chat",
                        source: .builtIn,
                        group: .builtIn
                    )
                )
                items.append(
                    SlashCommandItem(
                        id: "slash:btw",
                        kind: .builtIn(.btw),
                        label: "/btw",
                        name: "btw",
                        inputHint: "question",
                        description: "Same as /side",
                        source: .builtIn,
                        group: .builtIn
                    )
                )
            }

            // Provider slash commands (only at prompt start, matching web's `slashCommandItemsForPromptPosition`)
            for command in filteredProviderCommands {
                let hint = nonEmpty(command.input?.hint)
                let description = nonEmpty(command.description) ?? hint ?? "Run provider command"
                items.append(
                    SlashCommandItem(
                        id: "provider:\(providerDriver):\(command.name)",
                        kind: .providerCommand(command),
                        label: "/\(command.name)",
                        name: command.name,
                        inputHint: hint,
                        description: description,
                        source: .provider(label: providerLabel, driver: providerDriver),
                        group: .provider
                    )
                )
            }
        }

        // Provider skills (available at prompt start and mid-prompt)
        for skill in visibleSkills {
            let sourceKind = resolveSkillSourceKind(path: skill.path, scope: skill.scope)
            let description = nonEmpty(skill.shortDescription)
                ?? nonEmpty(skill.description)
                ?? (nonEmpty(skill.scope).map { "\($0) skill" } ?? "Run provider skill")
            items.append(
                SlashCommandItem(
                    id: "skill:\(providerDriver):\(skill.name)",
                    kind: .skill(skill),
                    label: "/skill:\(skill.resolvedDisplayName)",
                    name: skill.name,
                    inputHint: nil,
                    description: description,
                    source: .skill(sourceKind),
                    group: .skill
                )
            )
        }

        return items
    }

    // MARK: - Search & Ranking

    /// Filters and ranks slash commands matching `query` (mirrors `composerSlashCommandSearch.ts` + `searchRanking.ts`).
    static func filterAndRank(_ items: [SlashCommandItem], query: String) -> [SlashCommandItem] {
        let normalizedQuery = normalizeQuery(query)
        guard !normalizedQuery.isEmpty else { return items }

        var ranked: [(item: SlashCommandItem, score: Int, tieBreaker: String)] = []
        ranked.reserveCapacity(items.count)

        for item in items {
            guard let score = scoreItem(item, query: normalizedQuery) else { continue }
            let tieBreaker = "\(item.group.rawValue)\u{0000}\(item.name.lowercased())\u{0000}\(item.id)"
            ranked.append((item, score, tieBreaker))
        }

        ranked.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            return lhs.tieBreaker < rhs.tieBreaker
        }
        return ranked.map(\.item)
    }

    /// Groups items into titled sections when browsing (`query` empty), or a single ranked flat list while searching.
    static func sections(
        for items: [SlashCommandItem],
        query: String,
        providerLabel: String
    ) -> [SlashCommandSection] {
        guard !items.isEmpty else { return [] }
        if !normalizeQuery(query).isEmpty {
            return [SlashCommandSection(id: "search", title: nil, items: items)]
        }

        var result: [SlashCommandSection] = []
        let builtIns = items.filter { $0.group == .builtIn }
        let providerItems = items.filter { $0.group == .provider }
        let skillItems = items.filter { $0.group == .skill }

        if !builtIns.isEmpty {
            result.append(SlashCommandSection(id: "builtIn", title: "Built-in", items: builtIns))
        }
        if !providerItems.isEmpty {
            result.append(SlashCommandSection(id: "provider", title: providerLabel, items: providerItems))
        }
        if !skillItems.isEmpty {
            result.append(SlashCommandSection(id: "skills", title: "Skills", items: skillItems))
        }
        return result
    }

    // MARK: - Keyboard Highlight Navigation

    static func resolveHighlightedID(current: String?, in items: [SlashCommandItem]) -> String? {
        guard !items.isEmpty else { return nil }
        if let current, items.contains(where: { $0.id == current }) {
            return current
        }
        return items.first?.id
    }

    static func stepHighlight(current: String?, direction: Int, in items: [SlashCommandItem]) -> String? {
        guard !items.isEmpty else { return nil }
        guard let current, let index = items.firstIndex(where: { $0.id == current }) else {
            return direction >= 0 ? items.first?.id : items.last?.id
        }
        let nextIndex = (index + direction + items.count) % items.count
        return items[nextIndex].id
    }

    // MARK: - Selection Execution Plan

    static func selectionAction(
        for item: SlashCommandItem,
        trigger: SlashCommandTrigger,
        prompt: String,
        supportsFreshSession: Bool
    ) -> SlashCommandAction {
        switch item.kind {
        case .builtIn(let command):
            switch command {
            case .model:
                let replaced = replaceRange(
                    in: prompt,
                    rangeStart: trigger.rangeStart,
                    rangeEnd: trigger.rangeEnd,
                    replacement: "",
                    swallowTrailingSpace: false
                )
                return .openModelPicker(updatedPrompt: replaced.text, cursorUTF16: replaced.cursorUTF16)

            case .clear:
                let replaced = replaceRange(
                    in: prompt,
                    rangeStart: trigger.rangeStart,
                    rangeEnd: trigger.rangeEnd,
                    replacement: "",
                    swallowTrailingSpace: false
                )
                if supportsFreshSession {
                    return .armFreshSession(updatedPrompt: replaced.text, cursorUTF16: replaced.cursorUTF16)
                }
                return .clearDraftOrStartNewThread(updatedPrompt: replaced.text, cursorUTF16: replaced.cursorUTF16)

            case .plan:
                let replaced = replaceRange(
                    in: prompt,
                    rangeStart: trigger.rangeStart,
                    rangeEnd: trigger.rangeEnd,
                    replacement: "",
                    swallowTrailingSpace: false
                )
                return .setInteractionMode(.plan, updatedPrompt: replaced.text, cursorUTF16: replaced.cursorUTF16)

            case .defaultMode:
                let replaced = replaceRange(
                    in: prompt,
                    rangeStart: trigger.rangeStart,
                    rangeEnd: trigger.rangeEnd,
                    replacement: "",
                    swallowTrailingSpace: false
                )
                return .setInteractionMode(.default, updatedPrompt: replaced.text, cursorUTF16: replaced.cursorUTF16)

            case .side, .btw:
                let replaced = replaceRange(
                    in: prompt,
                    rangeStart: trigger.rangeStart,
                    rangeEnd: trigger.rangeEnd,
                    replacement: "/\(command.commandName) ",
                    swallowTrailingSpace: true
                )
                return .replacePrompt(text: replaced.text, cursorUTF16: replaced.cursorUTF16)
            }

        case .providerCommand(let command):
            let replaced = replaceRange(
                in: prompt,
                rangeStart: trigger.rangeStart,
                rangeEnd: trigger.rangeEnd,
                replacement: "/\(command.name) ",
                swallowTrailingSpace: true
            )
            return .replacePrompt(text: replaced.text, cursorUTF16: replaced.cursorUTF16)

        case .skill(let skill):
            let replaced = replaceRange(
                in: prompt,
                rangeStart: trigger.rangeStart,
                rangeEnd: trigger.rangeEnd,
                replacement: "$\(skill.name) ",
                swallowTrailingSpace: true
            )
            return .replacePrompt(text: replaced.text, cursorUTF16: replaced.cursorUTF16)
        }
    }

    // MARK: - Workspace Snapshot Freshness

    static func shouldRefreshWorkspaceSnapshot(
        provider: ServerProvider,
        cwd: String?,
        lastRequestedAt: Date?,
        now: Date
    ) -> Bool {
        guard let cwd = nonEmpty(cwd) else { return false }
        if let snapshot = provider.workspaceSnapshot(for: cwd),
           !snapshot.isPending,
           now.timeIntervalSince(snapshot.checkedAt) < workspaceSnapshotTTL
        {
            return false
        }
        if let lastRequestedAt, now.timeIntervalSince(lastRequestedAt) < workspaceSnapshotRetryCooldown {
            return false
        }
        return true
    }

    // MARK: - Private Scoring Helpers

    private static func isWhitespace(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x0A || unit == 0x09 || unit == 0x0D
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func normalizeQuery(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasPrefix("/") {
            trimmed.removeFirst()
        }
        return trimmed.lowercased()
    }

    private static func scoreItem(_ item: SlashCommandItem, query: String) -> Int? {
        if case .skill(let skill) = item.kind {
            if query == "skill" { return 0 }
            let skillQuery = query.hasPrefix("skill:") ? String(query.dropFirst("skill:".count)) : query
            if skillQuery.isEmpty { return 0 }
            if let score = scoreSkill(skill, query: skillQuery) {
                return score
            }
            return "skill".hasPrefix(query) ? Int.max / 2 : nil
        }

        let primaryValue = item.name.lowercased()
        let description = item.description.lowercased()
        let scores = [
            scoreQueryMatch(
                value: primaryValue,
                query: query,
                exactBase: 0,
                prefixBase: 2,
                boundaryBase: 4,
                includesBase: 6,
                fuzzyBase: 100,
                boundaryMarkers: ["-", "_", "/"]
            ),
            scoreQueryMatch(
                value: description,
                query: query,
                exactBase: 20,
                prefixBase: 22,
                boundaryBase: 24,
                includesBase: 26,
                fuzzyBase: nil,
                boundaryMarkers: [" ", "-", "_", "/"]
            ),
        ].compactMap { $0 }

        return scores.min()
    }

    private static func scoreSkill(_ skill: ServerProviderSkill, query: String) -> Int? {
        let name = skill.name.lowercased()
        let label = skill.resolvedDisplayName.lowercased()
        let shortDesc = (skill.shortDescription ?? "").lowercased()
        let desc = (skill.description ?? "").lowercased()
        let scope = (skill.scope ?? "").lowercased()

        let scores = [
            scoreQueryMatch(
                value: name,
                query: query,
                exactBase: 0,
                prefixBase: 2,
                boundaryBase: 4,
                includesBase: 6,
                fuzzyBase: 100,
                boundaryMarkers: ["-", "_", "/"]
            ),
            scoreQueryMatch(
                value: label,
                query: query,
                exactBase: 1,
                prefixBase: 3,
                boundaryBase: 5,
                includesBase: 7,
                fuzzyBase: 110,
                boundaryMarkers: [" ", "-", "_", "/"]
            ),
            scoreQueryMatch(
                value: shortDesc,
                query: query,
                exactBase: 20,
                prefixBase: 22,
                boundaryBase: 24,
                includesBase: 26,
                fuzzyBase: nil,
                boundaryMarkers: [" ", "-", "_", "/"]
            ),
            scoreQueryMatch(
                value: desc,
                query: query,
                exactBase: 30,
                prefixBase: 32,
                boundaryBase: 34,
                includesBase: 36,
                fuzzyBase: nil,
                boundaryMarkers: [" ", "-", "_", "/"]
            ),
            scoreQueryMatch(
                value: scope,
                query: query,
                exactBase: 40,
                prefixBase: 42,
                boundaryBase: nil,
                includesBase: 44,
                fuzzyBase: nil,
                boundaryMarkers: []
            ),
        ].compactMap { $0 }

        return scores.min()
    }

    private static func scoreQueryMatch(
        value: String,
        query: String,
        exactBase: Int,
        prefixBase: Int?,
        boundaryBase: Int?,
        includesBase: Int?,
        fuzzyBase: Int?,
        boundaryMarkers: [String]
    ) -> Int? {
        guard !value.isEmpty, !query.isEmpty else { return nil }
        let penalty = min(64, max(0, value.count - query.count))

        if value == query { return exactBase }

        if let prefixBase, value.hasPrefix(query) {
            return prefixBase + penalty
        }

        if let boundaryBase, let boundaryIndex = findBoundaryMatchIndex(value: value, query: query, markers: boundaryMarkers) {
            return boundaryBase + boundaryIndex * 2 + penalty
        }

        if let includesBase, let range = value.range(of: query) {
            let offset = value.distance(from: value.startIndex, to: range.lowerBound)
            return includesBase + offset * 2 + penalty
        }

        if let fuzzyBase, let fuzzyScore = scoreSubsequenceMatch(value: value, query: query) {
            return fuzzyBase + fuzzyScore
        }

        return nil
    }

    private static func findBoundaryMatchIndex(value: String, query: String, markers: [String]) -> Int? {
        var best: Int?
        for marker in markers {
            guard let range = value.range(of: marker + query) else { continue }
            let matchOffset = value.distance(from: value.startIndex, to: range.lowerBound) + marker.count
            if best == nil || matchOffset < best! {
                best = matchOffset
            }
        }
        return best
    }

    private static func scoreSubsequenceMatch(value: String, query: String) -> Int? {
        let valueChars = Array(value)
        let queryChars = Array(query)
        guard !queryChars.isEmpty else { return 0 }

        var queryIdx = 0
        var firstMatch = -1
        var previousMatch = -1
        var gapPenalty = 0

        for valueIdx in valueChars.indices {
            if valueChars[valueIdx] != queryChars[queryIdx] { continue }
            if firstMatch == -1 { firstMatch = valueIdx }
            if previousMatch != -1 { gapPenalty += valueIdx - previousMatch - 1 }
            previousMatch = valueIdx
            queryIdx += 1
            if queryIdx == queryChars.count {
                let spanPenalty = valueIdx - firstMatch + 1 - queryChars.count
                let lengthPenalty = min(64, max(0, valueChars.count - queryChars.count))
                return firstMatch * 2 + gapPenalty * 3 + spanPenalty + lengthPenalty
            }
        }
        return nil
    }
}
