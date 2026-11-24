import Foundation

/// Provider instances that share a driver (several Codex accounts, say) and so share one rail tab.
struct HarnessGroup: Identifiable, Hashable {
    let id: String
    let label: String
    /// Never empty.
    let harnesses: [PickerHarness]
}

/// Pure port of Studio's model picker logic: grouping, labels, search and keyboard navigation.
enum ModelPickerLogic {
    static let shortLabelMaxLength = 10

    private static let driverPrefixes: [String: [String]] = [
        "codex": ["Codex", "ChatGPT"],
        "claudeAgent": ["Claude Code", "Claude"],
        "antigravity": ["Antigravity"],
        "cursor": ["Cursor"],
        "opencode": ["OpenCode"],
        "pi": ["Pi"],
    ]

    /// Product names for drivers that brand their instances, used as the group name for several accounts.
    private static let clientLabels: [String: String] = [
        "codex": "Codex",
        "claudeAgent": "Claude",
        "antigravity": "Antigravity",
    ]

    // MARK: - Grouping

    static func driverGroup(_ harness: PickerHarness) -> String {
        if harness.driver == "acpRegistry" { return "acpRegistry:\(harness.acpAgentId ?? harness.id)" }
        return harness.driver.isEmpty ? harness.id : harness.driver
    }

    static func siblings(of harness: PickerHarness, in harnesses: [PickerHarness]) -> [PickerHarness] {
        let group = driverGroup(harness)
        return harnesses.filter { driverGroup($0) == group }
    }

    static func groups(_ harnesses: [PickerHarness]) -> [HarnessGroup] {
        var order: [String] = []
        var buckets: [String: [PickerHarness]] = [:]
        for harness in harnesses {
            let id = driverGroup(harness)
            if buckets[id] == nil { order.append(id) }
            buckets[id, default: []].append(harness)
        }
        return order.map { HarnessGroup(id: $0, label: groupLabel(buckets[$0]!), harnesses: buckets[$0]!) }
    }

    private static func groupLabel(_ harnesses: [PickerHarness]) -> String {
        let first = harnesses[0]
        if harnesses.count == 1 { return first.label }
        if first.driver != "acpRegistry", let client = clientLabels[first.driver] { return client }
        let shared = commonLeadingWords(harnesses.map(\.label))
        return shared.isEmpty ? first.label : shared.joined(separator: " ")
    }

    /// The account a group opens on: the thread's own, else the first ready one, else the first.
    static func initialHarnessID(in harnesses: [PickerHarness], current: String?) -> String? {
        if let current, harnesses.contains(where: { $0.id == current }) { return current }
        return harnesses.first(where: { $0.unavailableReason == nil && !$0.unauthenticated })?.id ?? harnesses.first?.id
    }

    // MARK: - Labels

    static func compactAccount(_ account: String?) -> String? {
        guard let trimmed = account?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else { return nil }
        let parts = trimmed.components(separatedBy: "·").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return parts.first(where: { $0.contains("@") }) ?? parts.first ?? trimmed
    }

    static func reason(of harness: PickerHarness) -> String? {
        harness.unavailableReason ?? (harness.unauthenticated ? "Not signed in" : nil)
    }

    static func accountTooltip(_ harness: PickerHarness) -> String {
        let detail = compactAccount(harness.account) ?? reason(of: harness)
        return detail.map { "\(harness.label) · \($0)" } ?? harness.label
    }

    static func groupTooltip(_ group: HarnessGroup, all: [PickerHarness]) -> String {
        if group.harnesses.count > 1 { return "\(group.label) · \(group.harnesses.count) accounts" }
        let only = group.harnesses[0]
        return detail(of: only, among: all).map { "\(only.label) · \($0)" } ?? only.label
    }

    /// A compact label telling sibling instances of one driver apart, or nil when the driver has only one.
    static func disambiguator(of harness: PickerHarness, among harnesses: [PickerHarness]) -> String? {
        let siblings = siblings(of: harness, in: harnesses)
        guard siblings.count > 1 else { return nil }
        func short(_ entry: PickerHarness) -> String {
            let stripped = stripRedundantPrefix(entry.label, driver: entry.driver)
            return stripped.isEmpty ? fullLabel(entry) : stripped
        }
        func fullLabel(_ entry: PickerHarness) -> String {
            let trimmed = entry.label.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? entry.id : trimmed
        }
        guard siblings.contains(where: { $0.id == harness.id }) else {
            let stripped = stripRedundantPrefix(harness.label, driver: harness.driver)
            return stripped.isEmpty ? harness.label : stripped
        }
        let mineShort = short(harness)
        if siblings.filter({ short($0).lowercased() == mineShort.lowercased() }).count == 1 { return mineShort }
        let mineLabel = fullLabel(harness)
        if siblings.filter({ fullLabel($0).lowercased() == mineLabel.lowercased() }).count == 1 { return mineLabel }
        if let account = compactAccount(harness.account),
           siblings.filter({ compactAccount($0.account)?.lowercased() == account.lowercased() }).count == 1
        {
            return account
        }
        return harness.id
    }

    /// Text beside a provider's name: why it is unavailable, else the account of a same-named sibling, else nil.
    static func detail(of harness: PickerHarness, among harnesses: [PickerHarness]) -> String? {
        if let reason = reason(of: harness) { return reason }
        let label = harness.label.trimmingCharacters(in: .whitespaces).lowercased()
        let collides = siblings(of: harness, in: harnesses).contains {
            $0.id != harness.id && $0.label.trimmingCharacters(in: .whitespaces).lowercased() == label
        }
        return collides ? disambiguator(of: harness, among: harnesses) : nil
    }

    /// Short, unique switcher labels for the accounts of one group: strip redundant prefixes, keep names up to
    /// 10 characters, otherwise fall back to 2 letters or digits and expand on collisions.
    static func accountShortLabels(_ harnesses: [PickerHarness]) -> [String: String] {
        guard !harnesses.isEmpty else { return [:] }
        let groupPrefix = harnesses.count > 1 ? groupLabel(harnesses) : nil
        let rawLabels = harnesses.map { entry -> String in
            let trimmed = entry.label.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? entry.id : trimmed
        }
        let stripped = harnesses.indices.map { index -> String in
            let value = stripRedundantPrefix(rawLabels[index], driver: harnesses[index].driver, extra: groupPrefix.map { [$0] } ?? [])
            return value.isEmpty ? rawLabels[index] : value
        }
        let rawCounts = countKeys(rawLabels)
        let strippedCounts = countKeys(stripped)
        var bases = stripped.indices.map { index -> String in
            if strippedCounts[stripped[index].lowercased(), default: 0] > 1, rawCounts[rawLabels[index].lowercased()] == 1 {
                return rawLabels[index]
            }
            return stripped[index]
        }
        resolveAccountCollisions(harnesses, &bases)

        if bases.contains(where: { $0.count > shortLabelMaxLength }) {
            let shared = commonLeadingWords(bases)
            if !shared.isEmpty {
                let reduced = bases.map { stripLeadingWords($0, shared) }
                if allUnique(reduced) { bases = reduced }
            }
        }

        var chars = bases.map(alnumChars)
        var shortened = bases.map { $0.count > shortLabelMaxLength }
        var prefixLens = bases.indices.map { shortened[$0] ? min(2, chars[$0].count) : chars[$0].count }
        var labels = bases.indices.map { shortened[$0] ? String(chars[$0].prefix(prefixLens[$0])) : bases[$0] }

        let maxSteps = chars.reduce(0) { $0 + $1.count } + harnesses.count * 2 + 4
        for _ in 0..<maxSteps {
            var order: [String] = []
            var buckets: [String: [Int]] = [:]
            for index in labels.indices {
                let key = labels[index].lowercased()
                if buckets[key] == nil { order.append(key) }
                buckets[key, default: []].append(index)
            }
            var changed = false
            for key in order {
                let indices = buckets[key]!
                guard indices.count > 1 else { continue }

                let shared = commonLeadingWords(indices.map { bases[$0] })
                if !shared.isEmpty {
                    let reduced = indices.map { stripLeadingWords(bases[$0], shared) }
                    if zip(reduced, indices).contains(where: { $0 != bases[$1] }) {
                        for (position, index) in indices.enumerated() {
                            let next = reduced[position]
                            bases[index] = next
                            chars[index] = alnumChars(next)
                            shortened[index] = next.count > shortLabelMaxLength
                            prefixLens[index] = shortened[index] ? min(2, chars[index].count) : chars[index].count
                            labels[index] = shortened[index] ? String(chars[index].prefix(prefixLens[index])) : next
                        }
                        changed = true
                        continue
                    }
                }

                var expanded = false
                for index in indices where shortened[index] && prefixLens[index] < chars[index].count {
                    prefixLens[index] += 1
                    labels[index] = String(chars[index].prefix(prefixLens[index]))
                    expanded = true
                    changed = true
                }
                if expanded { continue }

                var restored = false
                for index in indices where labels[index] != bases[index] {
                    labels[index] = bases[index]
                    shortened[index] = false
                    restored = true
                    changed = true
                }
                if restored { continue }

                for index in indices where labels[index] != harnesses[index].id {
                    labels[index] = harnesses[index].id
                    changed = true
                }
            }
            if !changed { break }
        }
        return Dictionary(uniqueKeysWithValues: harnesses.indices.map { (harnesses[$0].id, labels[$0]) })
    }

    private static func resolveAccountCollisions(_ harnesses: [PickerHarness], _ bases: inout [String]) {
        var order: [String] = []
        var buckets: [String: [Int]] = [:]
        for index in bases.indices {
            let key = bases[index].lowercased()
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(index)
        }
        func applyIfUnique(_ indices: [Int], _ next: [String]) -> Bool {
            let inside = Set(indices)
            let outside = Set(bases.indices.filter { !inside.contains($0) }.map { bases[$0].lowercased() })
            var seen = Set<String>()
            for candidate in next {
                let key = candidate.lowercased()
                if outside.contains(key) || seen.contains(key) { return false }
                seen.insert(key)
            }
            for (position, index) in indices.enumerated() { bases[index] = next[position] }
            return true
        }
        for key in order {
            let indices = buckets[key]!
            guard indices.count > 1 else { continue }
            let accounts = indices.map { compactAccount(harnesses[$0].account) }
            let locals = zip(accounts, indices).map { account, index -> String in
                guard let account else { return bases[index] }
                if let at = account.firstIndex(of: "@"), at > account.startIndex { return String(account[..<at]) }
                return account
            }
            if applyIfUnique(indices, locals) { continue }
            let domains = zip(accounts, indices).map { account, index -> String in
                guard let account else { return bases[index] }
                if let at = account.firstIndex(of: "@"), at > account.startIndex { return String(account[account.index(after: at)...]) }
                return account
            }
            if applyIfUnique(indices, domains) { continue }
            if applyIfUnique(indices, zip(accounts, indices).map { $0 ?? bases[$1] }) { continue }
            for index in indices { bases[index] = harnesses[index].id }
        }
    }

    // MARK: - Search

    static func harness(_ id: String, in catalog: PickerCatalog) -> PickerHarness {
        catalog.harnesses.first(where: { $0.id == id })
            ?? PickerHarness(id: id, driver: id, label: id, kind: SwftAdapters.providerKind(driver: id, instanceId: id))
    }

    static func locationLabel(_ option: ModelOption, in catalog: PickerCatalog) -> String {
        let label = harness(option.instanceId, in: catalog).label
        return option.subProvider.map { "\(label) via \($0)" } ?? label
    }

    static func matches(_ option: ModelOption, needle: String, in catalog: PickerCatalog) -> Bool {
        let account = harness(option.instanceId, in: catalog).account ?? ""
        let haystack = "\(option.name) \(locationLabel(option, in: catalog)) \(account)".lowercased()
        return needle.split(whereSeparator: \.isWhitespace).allSatisfy { haystack.contains($0) }
    }

    // MARK: - Word helpers

    private static let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-·:_/"))
    private static let separatorClass = #"[\s\-·:_/]"#

    private static func splitWords(_ value: String) -> [String] {
        value.trimmingCharacters(in: .whitespaces).components(separatedBy: separators).filter { !$0.isEmpty }
    }

    private static func commonLeadingWords(_ values: [String]) -> [String] {
        guard values.count >= 2 else { return [] }
        let lists = values.map(splitWords)
        let first = lists[0]
        var count = 0
        while count < first.count {
            let word = first[count].lowercased()
            if lists.contains(where: { count >= $0.count || $0[count].lowercased() != word }) { break }
            count += 1
        }
        return Array(first.prefix(count))
    }

    private static func stripLeadingWords(_ value: String, _ words: [String]) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else { return trimmed }
        let pattern = "^" + words.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "\(separatorClass)+") + "\(separatorClass)+(.+)$"
        let rest = firstCapture(pattern, in: trimmed)?.trimmingCharacters(in: .whitespaces)
        return rest.flatMap { $0.isEmpty ? nil : $0 } ?? trimmed
    }

    private static func stripRedundantPrefix(_ label: String, driver: String, extra: [String] = []) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        var prefixes = driverPrefixes[driver] ?? []
        if driver != "acpRegistry", let client = clientLabels[driver] { prefixes.append(client) }
        prefixes += extra.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var seen = Set<String>()
        let ordered = prefixes.filter { seen.insert($0).inserted }.sorted { $0.count > $1.count }
        for prefix in ordered {
            let pattern = "^\(NSRegularExpression.escapedPattern(for: prefix))(?:\\s*[-·:_]\\s*|\\s+)(.+)$"
            if let rest = firstCapture(pattern, in: trimmed)?.trimmingCharacters(in: .whitespaces), !rest.isEmpty { return rest }
        }
        return trimmed
    }

    private static func firstCapture(_ pattern: String, in value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value)
        else { return nil }
        return String(value[range])
    }

    private static func alnumChars(_ value: String) -> [Character] {
        let matched = value.filter { $0.isLetter || $0.isNumber }
        return matched.isEmpty ? Array(value.trimmingCharacters(in: .whitespaces)) : Array(matched)
    }

    private static func countKeys(_ values: [String]) -> [String: Int] {
        values.reduce(into: [:]) { $0[$1.lowercased(), default: 0] += 1 }
    }

    private static func allUnique(_ values: [String]) -> Bool {
        countKeys(values).count == values.count
    }
}
