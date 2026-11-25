import Foundation
import SwftDesign

/// Maximum number of provider usage pills shown in the sidebar footer.
let MAX_USAGE_PILLS = 3

// MARK: - Usage View-State Models

enum UsageWindowKind: String, Codable, Sendable, Equatable, Hashable {
    case session
    case weekly
    case monthly
    case other
    case unknown

    var displayOrder: Int {
        switch self {
        case .session: 0
        case .weekly: 1
        case .monthly: 2
        case .other: 3
        case .unknown: 4
        }
    }
}

struct UsageWindow: Codable, Sendable, Equatable, Hashable, Identifiable {
    let id: String
    let kind: UsageWindowKind
    let label: String
    let modelIds: [String]?
    let providerIds: [String]?
    let usedPercent: Double
    let resetsAt: Date?
    let windowDurationMins: Int?

    init(
        id: String,
        kind: UsageWindowKind,
        label: String,
        modelIds: [String]? = nil,
        providerIds: [String]? = nil,
        usedPercent: Double,
        resetsAt: Date? = nil,
        windowDurationMins: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.modelIds = modelIds
        self.providerIds = providerIds
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.windowDurationMins = windowDurationMins
    }
}

enum UsageUnavailableReason: String, Codable, Sendable, Equatable, Hashable {
    case unsupported
    case probeFailed
    case unknown
}

struct UsageUnavailable: Codable, Sendable, Equatable, Hashable {
    let reason: UsageUnavailableReason
    let message: String?

    init(reason: UsageUnavailableReason, message: String? = nil) {
        self.reason = reason
        self.message = message
    }
}

struct UsageLimitsSnapshot: Codable, Sendable, Equatable, Hashable {
    let checkedAt: Date
    let windows: [UsageWindow]
    let zeroSpendCap: Bool?
    let credentialFingerprint: String?
    let unavailable: UsageUnavailable?

    init(
        checkedAt: Date,
        windows: [UsageWindow] = [],
        zeroSpendCap: Bool? = nil,
        credentialFingerprint: String? = nil,
        unavailable: UsageUnavailable? = nil
    ) {
        self.checkedAt = checkedAt
        self.windows = windows
        self.zeroSpendCap = zeroSpendCap
        self.credentialFingerprint = credentialFingerprint
        self.unavailable = unavailable
    }
}

struct CachedUsageLimits: Codable, Sendable, Equatable, Hashable {
    let checkedAt: Date
    let windows: [UsageWindow]
}

struct UsageProviderEntry: Identifiable, Sendable, Equatable, Hashable {
    let id: String
    var driver: String
    var acpAgentId: String? = nil
    var label: String
    var kind: ProviderKind
    var accentHex: String? = nil
    var account: String? = nil
    var listed: Bool = true
    var enabled: Bool = true
    var installed: Bool = true
    var unauthenticated: Bool = false
    var unavailableReason: String? = nil
    var usageLimits: UsageLimitsSnapshot? = nil

    var asPickerHarness: PickerHarness {
        PickerHarness(
            id: id,
            driver: driver,
            acpAgentId: acpAgentId,
            label: label,
            kind: kind,
            accentHex: accentHex,
            account: account,
            unauthenticated: unauthenticated,
            unavailableReason: unavailableReason
        )
    }
}

// MARK: - Pacing & Reset Types

enum LimitPace: String, Sendable, Equatable, Hashable {
    case ahead
    case on
    case under

    var label: String {
        switch self {
        case .ahead: "Ahead of pace"
        case .on: "On pace"
        case .under: "Under pace"
        }
    }

    var pillTone: UsagePillPaceTone {
        switch self {
        case .ahead: .ahead
        case .on: .on
        case .under: .under
        }
    }
}

enum ResetCountdown: Sendable, Equatable, Hashable {
    case now
    case momentarily
    case `in`(TimeInterval)
}

// MARK: - Grouped Pill & Account Models

enum UsagePillState: Sendable, Equatable, Hashable {
    case healthy(primary: UsageWindow, secondary: UsageWindow?)
    case expired(reason: String)
    case notSignedIn(reason: String)
    case unsupported(reason: String)
    case unavailable(reason: String)

    enum Kind: Sendable, Equatable, Hashable {
        case healthy
        case expired
        case notSignedIn
        case unsupported
        case unavailable
    }

    var kind: Kind {
        switch self {
        case .healthy: .healthy
        case .expired: .expired
        case .notSignedIn: .notSignedIn
        case .unsupported: .unsupported
        case .unavailable: .unavailable
        }
    }

    var isHealthy: Bool { kind == .healthy }
    var isExpired: Bool { kind == .expired }

    var reason: String? {
        switch self {
        case .healthy: nil
        case .expired(let reason),
             .notSignedIn(let reason),
             .unsupported(let reason),
             .unavailable(let reason):
            reason
        }
    }
}

struct UsagePillAccount: Identifiable, Sendable, Equatable, Hashable {
    var id: String { entry.id }
    let entry: UsageProviderEntry
    let state: UsagePillState
}

struct UsagePillGroup: Identifiable, Sendable, Equatable, Hashable {
    /// Driver group id persisted in UserDefaults.
    let id: String
    /// Shared provider title (e.g. "Claude") or the lone account's own label.
    let label: String
    /// Representative provider entry for the pill's icon and tint.
    let primary: UsageProviderEntry
    /// Signed-in accounts shown in the breakdown popover (or signed-out accounts when none are signed in).
    let accounts: [UsagePillAccount]
    /// Every candidate account under this driver, including signed-out siblings.
    let allAccounts: [UsagePillAccount]
    /// Aggregate pill state.
    let state: UsagePillState
    /// Accounts whose Antigravity OAuth sign-in expired and can be refreshed on click.
    let expiredAccounts: [UsagePillAccount]
    /// Instance id to highlight when opening Settings → Providers.
    let openTargetId: String
}

struct UsageSplitWindowRow: Identifiable, Sendable, Equatable, Hashable {
    var id: String { window.id }
    let window: UsageWindow
    let label: String
}

struct UsageSplitWindowGroup: Sendable, Equatable, Hashable {
    let family: String?
    let rows: [UsageSplitWindowRow]
}

struct UsageCardHeader: Sendable, Equatable, Hashable {
    let title: String
    let detail: String?
}

// MARK: - Pure Pacing, Grouping & Selection Logic

enum UsagePillsLogic {
    static let maxPills = MAX_USAGE_PILLS

    private static let minuteSeconds: TimeInterval = 60
    private static let hourSeconds: TimeInterval = 3_600
    private static let daySeconds: TimeInterval = 86_400

    // MARK: Pacing Math (mirrors `packages/shared/src/usageLimits.ts`)

    static func remainingPercent(_ window: UsageWindow) -> Int {
        guard window.usedPercent.isFinite else { return 0 }
        let clamped = min(max(window.usedPercent, 0), 100)
        return Int((100.0 - clamped).rounded())
    }

    static func elapsedShare(_ window: UsageWindow, now: Date) -> Double? {
        guard let resetsAt = window.resetsAt,
              let durationMins = window.windowDurationMins,
              durationMins > 0
        else { return nil }
        let length = Double(durationMins) * minuteSeconds
        guard length > 0 else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        let share = (length - remaining) / length
        return min(max(share, 0), 1)
    }

    /// Where even-pace sits on a remaining-quota bar (`round((1 - elapsed) * 100)`).
    static func paceRemainingPercent(_ window: UsageWindow, now: Date) -> Int? {
        guard let elapsed = elapsedShare(window, now: now) else { return nil }
        return Int(((1.0 - elapsed) * 100.0).rounded())
    }

    static func paceOf(_ window: UsageWindow, now: Date) -> LimitPace? {
        guard window.usedPercent.isFinite, let elapsed = elapsedShare(window, now: now) else { return nil }
        let gap = window.usedPercent - elapsed * 100.0
        if gap > 5.0 { return .ahead }
        if gap < -5.0 { return .under }
        return .on
    }

    static func resetCountdown(_ window: UsageWindow, now: Date) -> ResetCountdown? {
        guard let resetsAt = window.resetsAt else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        if remaining <= 0 { return .now }
        if remaining < minuteSeconds { return .momentarily }
        return .in(remaining)
    }

    /// Compact countdown label: `"Now"`, `"<1m"`, `"42m"`, `"2h 14m"`, `"3d 18h"`.
    static func formatResetCountdown(_ window: UsageWindow, now: Date) -> String? {
        guard let countdown = resetCountdown(window, now: now) else { return nil }
        switch countdown {
        case .now:
            return "Now"
        case .momentarily:
            return "<1m"
        case .in(let seconds):
            return formatCompactDuration(seconds)
        }
    }

    /// Sentence fragment for footer status: `"resets now"`, `"resets momentarily"`, `"resets in 42m"`.
    static func formatResetsInPhrase(_ window: UsageWindow, now: Date) -> String? {
        guard let countdown = resetCountdown(window, now: now) else { return nil }
        switch countdown {
        case .now:
            return "resets now"
        case .momentarily:
            return "resets momentarily"
        case .in(let seconds):
            return "resets in \(formatCompactDuration(seconds))"
        }
    }

    static func formatCompactDuration(_ seconds: TimeInterval) -> String {
        let clamped = max(0, Int(seconds))
        let days = clamped / Int(daySeconds)
        let hours = (clamped % Int(daySeconds)) / Int(hourSeconds)
        let minutes = (clamped % Int(hourSeconds)) / Int(minuteSeconds)
        if days > 0 {
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        }
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }

    static func formatAsOfTime(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        if calendar.isDate(date, inSameDayAs: now) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
        } else {
            formatter.setLocalizedDateFormatFromTemplate("MMM d, j:mm")
        }
        return formatter.string(from: date)
    }

    // MARK: Window Family Splitting (mirrors `usageLimitBars.logic.ts`)

    private static let kindMatchers: [UsageWindowKind: (label: String, pattern: String)] = [
        .session: ("Session", #"^(?:session|5-hour|5h|five-hour)$"#),
        .weekly: ("Weekly", #"^(?:weekly|7-day|week)$"#),
        .monthly: ("Monthly", #"^monthly$"#),
    ]

    static func usageWindowGroups(_ windows: [UsageWindow]) -> [UsageSplitWindowGroup] {
        var order: [String?] = [nil]
        var buckets: [String?: [UsageSplitWindowRow]] = [nil: []]

        for window in windows {
            let (family, label) = splitWindow(window)
            if buckets[family] == nil {
                order.append(family)
                buckets[family] = []
            }
            buckets[family]?.append(UsageSplitWindowRow(window: window, label: label))
        }

        return order.compactMap { family in
            guard let rows = buckets[family], !rows.isEmpty else { return nil }
            return UsageSplitWindowGroup(family: family, rows: rows)
        }
    }

    private static func splitWindow(_ window: UsageWindow) -> (family: String?, label: String) {
        let parts = window.label
            .components(separatedBy: " · ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard parts.count >= 2 else { return (nil, window.label) }
        if let matcher = kindMatchers[window.kind],
           let regex = try? NSRegularExpression(pattern: matcher.pattern, options: [.caseInsensitive]),
           let index = parts.firstIndex(where: { part in
               let range = NSRange(part.startIndex..., in: part)
               return regex.firstMatch(in: part, range: range) != nil
           })
        {
            let familyParts = parts.enumerated().compactMap { $0.offset == index ? nil : $0.element }
            return (familyParts.joined(separator: " · "), matcher.label)
        }
        return (parts[0], parts.dropFirst().joined(separator: " · "))
    }

    // MARK: Driver Grouping & Classification (mirrors `usageRings.logic.ts`)

    static func driverGroupID(of entry: UsageProviderEntry) -> String {
        if entry.driver == "acpRegistry" {
            return "acpRegistry:\(entry.acpAgentId ?? entry.id)"
        }
        return entry.driver.isEmpty ? entry.id : entry.driver
    }

    static func hasUsageWindows(_ limits: UsageLimitsSnapshot?) -> Bool {
        guard let limits else { return false }
        return limits.unavailable == nil && !limits.windows.isEmpty
    }

    static func isExpiredAntigravityUsageLimits(_ limits: UsageLimitsSnapshot?, driver: String? = nil) -> Bool {
        guard driver == nil || driver == "antigravity" else { return false }
        guard limits?.unavailable?.reason == .probeFailed,
              let message = limits?.unavailable?.message
        else { return false }
        return message.range(of: "saved sign-in has expired", options: .caseInsensitive) != nil
    }

    static func classify(_ entry: UsageProviderEntry) -> UsagePillState? {
        guard entry.listed, entry.enabled, entry.installed else { return nil }
        if entry.unavailableReason == nil,
           let limits = entry.usageLimits,
           hasUsageWindows(limits),
           let picked = pillWindows(from: limits)
        {
            return .healthy(primary: picked.primary, secondary: picked.secondary)
        }
        if isExpiredAntigravityUsageLimits(entry.usageLimits, driver: entry.driver) {
            return .expired(reason: "Sign-in expired")
        }
        let unsupportedSignIn = entry.usageLimits?.unavailable?.reason == .unsupported
            && (entry.usageLimits?.unavailable?.message?.range(of: "sign in", options: .caseInsensitive) != nil)
        if entry.unauthenticated || unsupportedSignIn {
            return .notSignedIn(reason: "Not signed in")
        }
        if entry.usageLimits?.unavailable?.reason == .unsupported {
            return .unsupported(reason: entry.usageLimits?.unavailable?.message ?? "Usage limits not available")
        }
        if entry.usageLimits?.unavailable?.reason == .probeFailed {
            return .unavailable(reason: entry.usageLimits?.unavailable?.message ?? "Could not read limits")
        }
        return nil
    }

    static func tightestWindow(_ windows: [UsageWindow]) -> UsageWindow? {
        var best: UsageWindow?
        for window in windows {
            if let current = best {
                if remainingPercent(window) < remainingPercent(current) {
                    best = window
                }
            } else {
                best = window
            }
        }
        return best
    }

    private static func accountWindow(_ windows: [UsageWindow], kind: UsageWindowKind) -> UsageWindow? {
        let ofKind = windows.filter { $0.kind == kind }
        let unscoped = ofKind.filter { ($0.modelIds?.isEmpty ?? true) && ($0.providerIds?.isEmpty ?? true) }
        return tightestWindow(unscoped.isEmpty ? ofKind : unscoped)
    }

    /// Selects the pill's primary window (tightest `session` / 5-hour window, or tightest overall)
    /// and optional secondary `weekly` window for the subtle 2pt bottom bar.
    static func pillWindows(from limits: UsageLimitsSnapshot) -> (primary: UsageWindow, secondary: UsageWindow?)? {
        guard hasUsageWindows(limits) else { return nil }
        let session = accountWindow(limits.windows, kind: .session)
        let weekly = accountWindow(limits.windows, kind: .weekly)
        if let session {
            return (primary: session, secondary: weekly)
        }
        if let weekly {
            return (primary: weekly, secondary: nil)
        }
        guard let tightest = tightestWindow(limits.windows) else { return nil }
        return (primary: tightest, secondary: nil)
    }

    private static func groupPillWindows(
        healthyAccounts: [UsagePillAccount]
    ) -> (primary: UsageWindow, secondary: UsageWindow?, tightestAccountID: String?)? {
        struct Entry {
            let accountID: String
            let window: UsageWindow
        }

        var allWindows: [Entry] = []
        for account in healthyAccounts {
            if case .healthy(let primary, let secondary) = account.state {
                allWindows.append(Entry(accountID: account.id, window: primary))
                if let secondary {
                    allWindows.append(Entry(accountID: account.id, window: secondary))
                }
            }
        }

        func tightestOf(_ list: [Entry]) -> Entry? {
            var best: Entry?
            for item in list {
                if let current = best {
                    if remainingPercent(item.window) < remainingPercent(current.window) {
                        best = item
                    }
                } else {
                    best = item
                }
            }
            return best
        }

        let session = tightestOf(allWindows.filter { $0.window.kind == .session })
        let weekly = tightestOf(allWindows.filter { $0.window.kind == .weekly })

        let primaryEntry: Entry
        let secondaryEntry: Entry?
        if let session {
            primaryEntry = session
            secondaryEntry = weekly
        } else if let weekly {
            primaryEntry = weekly
            secondaryEntry = nil
        } else if let fallback = tightestOf(allWindows) {
            primaryEntry = fallback
            secondaryEntry = nil
        } else {
            return nil
        }

        let chosen = [primaryEntry, secondaryEntry].compactMap { $0 }
        let tightestOverall = tightestOf(chosen)
        return (
            primary: primaryEntry.window,
            secondary: secondaryEntry?.window,
            tightestAccountID: tightestOverall?.accountID
        )
    }

    /// Candidate usage pill groups folded by provider driver, preserving catalog order.
    static func candidateGroups(from entries: [UsageProviderEntry]) -> [UsagePillGroup] {
        var order: [String] = []
        var buckets: [String: [UsagePillAccount]] = [:]

        for entry in entries {
            guard let state = classify(entry) else { continue }
            let groupID = driverGroupID(of: entry)
            let account = UsagePillAccount(entry: entry, state: state)
            if buckets[groupID] == nil {
                order.append(groupID)
            }
            buckets[groupID, default: []].append(account)
        }

        return order.compactMap { groupID -> UsagePillGroup? in
            guard let allAccounts = buckets[groupID], !allAccounts.isEmpty else { return nil }
            let signedIn = allAccounts.filter { $0.state.kind != .notSignedIn }
            let visible = signedIn.isEmpty ? allAccounts : signedIn
            let healthy = visible.filter { $0.state.isHealthy }
            let expiredAccounts = visible.filter { $0.state.isExpired }
            let unavailable = visible.first { $0.state.kind == .unavailable }
            let unsupported = visible.first { $0.state.kind == .unsupported }

            let state: UsagePillState
            let openTargetId: String

            if let aggregated = groupPillWindows(healthyAccounts: healthy) {
                state = .healthy(primary: aggregated.primary, secondary: aggregated.secondary)
                let windows = [aggregated.primary, aggregated.secondary].compactMap { $0 }
                let tightest = tightestWindow(windows)
                if let tightest, remainingPercent(tightest) <= 10, let tightestAccountID = aggregated.tightestAccountID {
                    openTargetId = tightestAccountID
                } else {
                    openTargetId = visible[0].id
                }
            } else if let firstExpired = expiredAccounts.first {
                state = firstExpired.state
                openTargetId = firstExpired.id
            } else if let unavailable {
                state = unavailable.state
                openTargetId = unavailable.id
            } else if let unsupported {
                state = unsupported.state
                openTargetId = unsupported.id
            } else {
                state = visible[0].state
                openTargetId = visible[0].id
            }

            let label: String
            if visible.count == 1 {
                label = visible[0].entry.label
            } else {
                label = ModelPickerLogic.groups(visible.map(\.entry.asPickerHarness)).first?.label ?? visible[0].entry.label
            }

            return UsagePillGroup(
                id: groupID,
                label: label,
                primary: visible[0].entry,
                accounts: visible,
                allAccounts: allAccounts,
                state: state,
                expiredAccounts: expiredAccounts,
                openTargetId: openTargetId
            )
        }
    }

    /// Maps legacy instance ids in a persisted selection to deduplicated driver group ids,
    /// keeping unknown ids intact so temporarily absent providers are never lost.
    static func migrateSelection(
        _ selected: [String]?,
        entries: [UsageProviderEntry]
    ) -> [String]? {
        guard let selected else { return nil }
        var groupByID: [String: String] = [:]
        for entry in entries {
            let groupID = driverGroupID(of: entry)
            groupByID[groupID] = groupID
            groupByID[entry.id] = groupID
        }
        var seen = Set<String>()
        var migrated: [String] = []
        for item in selected {
            let mapped = groupByID[item] ?? item
            if seen.insert(mapped).inserted {
                migrated.append(mapped)
            }
        }
        return migrated
    }

    /// Up to `MAX_USAGE_PILLS` (3) provider groups shown in the sidebar footer.
    static func visibleGroups(
        from entries: [UsageProviderEntry],
        selected: [String]?,
        cachedInstanceIDs: Set<String> = []
    ) -> [UsagePillGroup] {
        let candidates = candidateGroups(from: entries)
        let migrated = migrateSelection(selected, entries: entries)
        let picked: [UsagePillGroup]
        if let migrated {
            let selectedSet = Set(migrated)
            picked = candidates.filter { selectedSet.contains($0.id) }
        } else {
            picked = candidates.filter { group in
                group.state.isHealthy
                    || group.state.isExpired
                    || group.allAccounts.contains { cachedInstanceIDs.contains($0.id) }
            }
        }
        return Array(picked.prefix(maxPills))
    }

    /// Next persisted selection after toggling one provider group in Settings.
    /// Turning a provider on when already at `MAX_USAGE_PILLS` changes nothing.
    static func toggleSelection(
        entries: [UsageProviderEntry],
        selected: [String]?,
        groupID: String,
        isOn: Bool,
        cachedInstanceIDs: Set<String> = []
    ) -> [String] {
        let targetID = migrateSelection([groupID], entries: entries)?.first ?? groupID
        let shown = visibleGroups(from: entries, selected: selected, cachedInstanceIDs: cachedInstanceIDs).map(\.id)
        if !isOn {
            return shown.filter { $0 != targetID }
        }
        if shown.contains(targetID) || shown.count >= maxPills {
            return shown
        }
        return shown + [targetID]
    }

    // MARK: Plan & Account Section Labels (mirrors `usageRings.logic.ts`)

    private static let planNoiseRegex = try? NSRegularExpression(
        pattern: #"\b(?:chatgpt|openai|claude|anthropic|google|gemini|codex|antigravity|cursor|subscription|plan|account|tier)\b"#,
        options: [.caseInsensitive]
    )

    static func shortPlanLabel(_ plan: String?) -> String? {
        guard let plan, !plan.isEmpty else { return nil }
        var cleaned = plan
        if let regex = planNoiseRegex {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: " ")
        }
        let trimChars = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-·:"))
        cleaned = cleaned.trimmingCharacters(in: trimChars)
        cleaned = cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func accountParts(_ account: String?) -> (plan: String, email: String?) {
        let parts = (account ?? "")
            .components(separatedBy: "·")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let plan = parts.filter { !$0.contains("@") }.joined(separator: " ")
        let email = parts.first { $0.contains("@") }
        return (plan, email)
    }

    private static func emailLocalPart(_ email: String) -> String {
        guard let at = email.firstIndex(of: "@") else { return email }
        return String(email[..<at])
    }

    private static func compactSiblingEmail(_ email: String, siblings: [UsageProviderEntry]) -> String {
        let targetLocal = emailLocalPart(email).lowercased()
        let matches = siblings.compactMap { accountParts($0.account).email }.filter {
            emailLocalPart($0).lowercased() == targetLocal
        }
        return matches.count > 1 ? email : emailLocalPart(email)
    }

    static func cardHeader(for entry: UsageProviderEntry, in entries: [UsageProviderEntry]) -> UsageCardHeader {
        let parts = accountParts(entry.account)
        let signedIn = entries.filter { $0.listed && $0.unavailableReason == nil }
        let harnesses = signedIn.map(\.asPickerHarness)
        let siblings = signedIn.filter { driverGroupID(of: $0) == driverGroupID(of: entry) }
        if siblings.count <= 1 {
            return UsageCardHeader(title: entry.label, detail: shortPlanLabel(parts.plan))
        }
        let siblingHarnesses = siblings.map(\.asPickerHarness)
        let title = ModelPickerLogic.groups(siblingHarnesses).first?.label ?? entry.label
        let name = ModelPickerLogic.disambiguator(of: entry.asPickerHarness, among: harnesses)
        if let name, name.contains("@") {
            return UsageCardHeader(title: title, detail: compactSiblingEmail(name, siblings: siblings))
        }
        if let name, name.lowercased() != title.lowercased(), name != entry.id {
            return UsageCardHeader(title: title, detail: name)
        }
        let detail = parts.email.map { compactSiblingEmail($0, siblings: siblings) } ?? shortPlanLabel(parts.plan)
        return UsageCardHeader(title: title, detail: detail)
    }

    static func accountSectionHeader(
        for entry: UsageProviderEntry,
        siblings: [UsageProviderEntry]
    ) -> UsageCardHeader {
        let parts = accountParts(entry.account)
        let shortPlan = shortPlanLabel(parts.plan)
        if siblings.count <= 1 {
            return UsageCardHeader(title: entry.label, detail: shortPlan)
        }
        let siblingHarnesses = siblings.map(\.asPickerHarness)
        let groupTitle = ModelPickerLogic.groups(siblingHarnesses).first?.label ?? entry.label
        let name = ModelPickerLogic.disambiguator(of: entry.asPickerHarness, among: siblingHarnesses)

        if let name, name.contains("@") {
            let emailLabel = compactSiblingEmail(name, siblings: siblings)
            let trimmedLabel = entry.label.trimmingCharacters(in: .whitespaces)
            if !trimmedLabel.isEmpty && trimmedLabel.lowercased() != groupTitle.lowercased() {
                let detail = [emailLabel, shortPlan].compactMap { $0 }.joined(separator: " · ")
                return UsageCardHeader(title: trimmedLabel, detail: detail.isEmpty ? nil : detail)
            }
            return UsageCardHeader(title: emailLabel, detail: shortPlan)
        }

        if let name, name.lowercased() != groupTitle.lowercased(), name != entry.id {
            let detail = shortPlan.flatMap { $0.lowercased() == name.lowercased() ? nil : $0 }
            return UsageCardHeader(title: name, detail: detail)
        }

        if let email = parts.email {
            return UsageCardHeader(title: compactSiblingEmail(email, siblings: siblings), detail: shortPlan)
        }

        if let shortPlan {
            return UsageCardHeader(title: shortPlan, detail: nil)
        }

        let trimmed = entry.label.trimmingCharacters(in: .whitespaces)
        let fallback = trimmed.isEmpty ? entry.id : trimmed
        return UsageCardHeader(
            title: fallback,
            detail: fallback.lowercased() == groupTitle.lowercased() ? entry.id : nil
        )
    }
}

// MARK: - UserDefaults Persistence & Last-Good Cache

enum UsagePillsStore {
    static let selectedPillsKey = "swft.usagePills.selected"
    static let lastGoodLimitsKey = "swft.usagePills.lastGood"
    static let maxCachedLimits = 64

    static func cacheKey(environmentID: String, instanceID: String) -> String {
        "\(environmentID):\(instanceID)"
    }

    static func cachedInstanceIDs(
        in entries: [String: CachedUsageLimits],
        environmentID: String
    ) -> Set<String> {
        let prefix = "\(environmentID):"
        var ids = Set<String>()
        for key in entries.keys where key.hasPrefix(prefix) {
            ids.insert(String(key.dropFirst(prefix.count)))
        }
        return ids
    }

    static func loadSelection(from defaults: UserDefaults = .standard) -> [String]? {
        guard defaults.object(forKey: selectedPillsKey) != nil else { return nil }
        return defaults.stringArray(forKey: selectedPillsKey)
    }

    static func saveSelection(_ selected: [String]?, to defaults: UserDefaults = .standard) {
        if let selected {
            defaults.set(selected, forKey: selectedPillsKey)
        } else {
            defaults.removeObject(forKey: selectedPillsKey)
        }
    }

    static func loadLastGoodLimits(from defaults: UserDefaults = .standard) -> [String: CachedUsageLimits] {
        guard let data = defaults.data(forKey: lastGoodLimitsKey),
              let decoded = try? JSONDecoder().decode([String: CachedUsageLimits].self, from: data)
        else { return [:] }
        return decoded.filter { !$0.value.windows.isEmpty }
    }

    static func saveLastGoodLimits(_ entries: [String: CachedUsageLimits], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: lastGoodLimitsKey)
    }

    /// Merges any newly observed healthy usage limits into the last-good cache.
    /// Returns nil when nothing changed to avoid redundant persistence writes.
    static func mergedLastGoodLimits(
        _ current: [String: CachedUsageLimits],
        environmentID: String,
        entries: [UsageProviderEntry]
    ) -> [String: CachedUsageLimits]? {
        guard !environmentID.isEmpty else { return nil }
        var next: [String: CachedUsageLimits]?
        for entry in entries {
            guard let limits = entry.usageLimits, UsagePillsLogic.hasUsageWindows(limits) else { continue }
            let key = cacheKey(environmentID: environmentID, instanceID: entry.id)
            let candidate = CachedUsageLimits(checkedAt: limits.checkedAt, windows: limits.windows)
            if (next ?? current)[key] == candidate { continue }
            if next == nil { next = current }
            next?[key] = candidate
        }
        guard var updated = next else { return nil }
        if updated.count > maxCachedLimits {
            let keptKeys = updated
                .sorted { $0.value.checkedAt > $1.value.checkedAt }
                .prefix(maxCachedLimits)
                .map(\.key)
            updated = Dictionary(uniqueKeysWithValues: keptKeys.compactMap { key in
                updated[key].map { (key, $0) }
            })
        }
        return updated
    }
}
