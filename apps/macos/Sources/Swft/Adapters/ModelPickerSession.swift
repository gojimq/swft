import Foundation

/// Open-picker state: what is being browsed and where the keyboard highlight sits. Typing always goes to the search
/// field; arrow keys move this virtual highlight, so the field never has to give up focus.
struct ModelPickerSession: Equatable {
    enum Focus: Equatable {
        case search, rail, accounts, row(Int), action, thinking
    }

    var query = ""
    var browsingGroupID: String
    var selectedAccounts: [String: String] = [:]
    var focus: Focus = .search
    /// +1 when the last rail move went down, -1 when up; panel content slides in from that side.
    var groupStep = 0

    /// Opens on the group holding the thread's provider.
    init(catalog: PickerCatalog, currentInstanceId: String?) {
        let groups = ModelPickerLogic.groups(catalog.harnesses)
        browsingGroupID = groups.first(where: { $0.harnesses.contains { $0.id == currentInstanceId } })?.id ?? groups.first?.id ?? ""
    }

    var needle: String { query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    var isSearching: Bool { !needle.isEmpty }

    mutating func setQuery(_ next: String) {
        guard next != query else { return }
        query = next
        focus = .search
    }

    mutating func selectGroup(_ id: String, in groups: [HarnessGroup]) {
        guard id != browsingGroupID else { return }
        let from = groups.firstIndex(where: { $0.id == browsingGroupID }) ?? 0
        let to = groups.firstIndex(where: { $0.id == id }) ?? 0
        groupStep = to >= from ? 1 : -1
        browsingGroupID = id
    }

    mutating func selectAccount(_ harnessID: String, inGroup groupID: String) {
        selectedAccounts[groupID] = harnessID
    }
}

/// What the open picker shows for a session, derived purely from the catalog and the thread's selection.
struct ModelPickerContent: Equatable {
    struct Section: Equatable, Identifiable {
        var id: String { title ?? "" }
        /// nil for a provider without sub-providers.
        let title: String?
        let unavailableReason: String?
        let models: [ModelOption]
    }

    let groups: [HarnessGroup]
    let activeGroup: HarnessGroup?
    /// The account being browsed inside the active group.
    let activeHarness: PickerHarness?
    let isSearching: Bool
    let searchResults: [ModelOption]
    let sections: [Section]
    /// The rows arrow keys walk, top to bottom.
    let rows: [ModelOption]
    let hasAccountSwitcher: Bool
    /// A signed-out provider offers one panel action (sign in / check again).
    let hasPanelAction: Bool
    let currentModelID: String?
    let thinkingLevels: [ReasoningChoice]

    init(catalog: PickerCatalog, session: ModelPickerSession, currentModel: ModelOption?, currentInstanceId: String?, offersPanelAction: Bool) {
        let listed = catalog.harnesses
        groups = ModelPickerLogic.groups(listed)
        let group = groups.first(where: { $0.id == session.browsingGroupID }) ?? groups.first
        activeGroup = group
        let chosen = group.flatMap { group in session.selectedAccounts[group.id].flatMap { id in group.harnesses.first { $0.id == id } } }
        let harness = chosen ?? group.flatMap { group in
            ModelPickerLogic.initialHarnessID(in: group.harnesses, current: currentInstanceId).flatMap { id in group.harnesses.first { $0.id == id } }
        }
        activeHarness = harness
        isSearching = session.isSearching
        searchResults = session.isSearching ? catalog.models.filter { ModelPickerLogic.matches($0, needle: session.needle, in: catalog) } : []
        hasAccountSwitcher = !session.isSearching && (group?.harnesses.count ?? 0) > 1
        currentModelID = currentModel?.id
        thinkingLevels = currentModel?.reasoningChoices ?? []

        if let harness, !session.isSearching {
            let models = catalog.models.filter { $0.instanceId == harness.id }
            if let subs = harness.subProviders {
                sections = subs.map { sub in
                    Section(title: sub.name, unavailableReason: sub.unavailableReason, models: sub.unavailableReason == nil ? models.filter { $0.subProvider == sub.name } : [])
                }
            } else {
                sections = [Section(title: nil, unavailableReason: nil, models: models)]
            }
            hasPanelAction = offersPanelAction && harness.unauthenticated
        } else {
            sections = []
            hasPanelAction = false
        }
        rows = session.isSearching ? searchResults : sections.flatMap(\.models)
    }

    var hasThinkingSlider: Bool { thinkingLevels.count > 1 }

    /// The row a move into the panel lands on: the current model when listed, else the first.
    var entryRow: Int? {
        guard !rows.isEmpty else { return nil }
        return rows.firstIndex(where: { $0.id == currentModelID }) ?? 0
    }
}

/// Keys the picker handles itself.
enum ModelPickerKey {
    case up, down, left, right, enter, escape
}

enum ModelPickerCommand: Equatable {
    case pick(ModelOption)
    case selectLevel(String)
    case panelAction(harnessID: String)
    case close
}

extension ModelPickerLogic {
    /// Panel stops top to bottom, as laid out: account switcher, sign-in action, model rows, thinking slider.
    static func stops(_ content: ModelPickerContent) -> [ModelPickerSession.Focus] {
        var stops: [ModelPickerSession.Focus] = []
        if content.hasAccountSwitcher { stops.append(.accounts) }
        if content.hasPanelAction { stops.append(.action) }
        stops += content.rows.indices.map { .row($0) }
        if content.hasThinkingSlider { stops.append(.thinking) }
        return stops
    }

    /// Handles one key. Returns nil when the key is not the picker's (so the search field gets it, e.g. caret moves);
    /// otherwise the key is consumed, `session` is updated in place, and the inner value is a command for the app.
    static func handle(
        _ key: ModelPickerKey,
        session: inout ModelPickerSession,
        content: ModelPickerContent,
        currentLevelID: String?
    ) -> ModelPickerCommand?? {
        if key == .escape { return .some(.close) }
        let stops = stops(content)
        let consumed: ModelPickerCommand?? = .some(nil)

        func go(_ focus: ModelPickerSession.Focus?) -> ModelPickerCommand?? {
            if let focus { session.focus = focus }
            return consumed
        }
        /// Where a move into the panel lands: the current model's row when listed, else the first stop.
        var entry: ModelPickerSession.Focus? {
            content.entryRow.map { .row($0) } ?? stops.first
        }

        switch session.focus {
        case .search:
            switch key {
            case .down: return go(content.isSearching ? stops.first : entry)
            case .enter:
                guard content.isSearching else { return nil }
                return .some(content.searchResults.first.map { .pick($0) })
            default: return nil
            }

        case .rail:
            switch key {
            case .up, .down:
                let groups = content.groups
                guard let index = groups.firstIndex(where: { $0.id == content.activeGroup?.id }) else { return consumed }
                if key == .up && index == 0 { return go(.search) }
                let next = min(max(index + (key == .down ? 1 : -1), 0), groups.count - 1)
                session.selectGroup(groups[next].id, in: groups)
                return consumed
            case .right, .enter: return go(stops.first == .accounts ? .accounts : entry)
            default: return consumed
            }

        case let focus:
            let position = stops.firstIndex(of: focus)
            switch key {
            case .up:
                guard let position, position > 0 else { return go(.search) }
                return go(stops[position - 1])
            case .down:
                guard let position, position + 1 < stops.count else { return consumed }
                return go(stops[position + 1])
            case .left where focus == .accounts, .right where focus == .accounts:
                guard let group = content.activeGroup,
                      let index = group.harnesses.firstIndex(where: { $0.id == content.activeHarness?.id })
                else { return consumed }
                let next = min(max(index + (key == .right ? 1 : -1), 0), group.harnesses.count - 1)
                session.selectAccount(group.harnesses[next].id, inGroup: group.id)
                return consumed
            case .left where focus == .thinking, .right where focus == .thinking:
                let levels = content.thinkingLevels
                let index = levels.firstIndex(where: { $0.id == currentLevelID }) ?? 0
                let next = min(max(index + (key == .right ? 1 : -1), 0), levels.count - 1)
                return .some(next == index ? nil : .selectLevel(levels[next].id))
            case .left:
                return content.isSearching ? consumed : go(.rail)
            case .right:
                return consumed
            case .enter:
                switch focus {
                case .row(let index) where content.rows.indices.contains(index): return .some(.pick(content.rows[index]))
                case .action: return .some(content.activeHarness.map { .panelAction(harnessID: $0.id) })
                case .accounts: return go(position.map { $0 + 1 < stops.count ? stops[$0 + 1] : focus })
                default: return consumed
                }
            case .escape:
                return .some(.close)
            }
        }
    }
}
