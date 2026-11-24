import AppKit
import SwftDesign
import SwiftUI

extension ProviderKind {
    /// SF Symbol for the picker; nil means "use a monogram".
    var pickerSymbol: String? { self == .other ? nil : symbol }
}

extension PickerHarness {
    var accentColor: Color? { accentHex.flatMap { Color(swftHex: $0) } }
}

extension ModelPickerContent {
    func railItems(all: [PickerHarness], currentInstanceId: String?) -> [PickerRailItem] {
        groups.map { group in
            let first = group.harnesses[0]
            return PickerRailItem(
                id: group.id,
                symbol: first.kind.pickerSymbol,
                monogram: group.label,
                tint: first.kind.tint,
                accent: group.harnesses.count == 1 ? first.accentColor : nil,
                tooltip: ModelPickerLogic.groupTooltip(group, all: all),
                inUse: group.harnesses.contains { $0.id == currentInstanceId }
            )
        }
    }
}

/// The composer's model picker: search, provider rail, models, thinking slider. Pure layout over
/// `ModelPickerContent`; every decision lives in `ModelPickerLogic`.
struct ModelPickerPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: ModelPickerSession
    let content: ModelPickerContent
    /// The trigger's frame in window coordinates, so clicking it toggles instead of counting as "outside".
    let triggerFrame: CGRect
    @FocusState private var searchFocused: Bool
    @State private var panelFrame: CGRect = .zero

    static let width: CGFloat = 340
    static let bodyHeight: CGFloat = 252

    var body: some View {
        let catalog = model.pickerCatalog
        let current = model.selectedModel
        PickerPanelSurface {
            VStack(spacing: 0) {
                PickerSearchField(text: Binding(get: { session.query }, set: { next in
                    withAnimation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion)) { model.modelPicker?.setQuery(next) }
                }), focus: $searchFocused)
                hairline
                ZStack(alignment: .topLeading) {
                    if content.isSearching {
                        searchResults(catalog: catalog)
                            .transition(.opacity)
                    } else {
                        HStack(alignment: .top, spacing: 4) {
                            PickerRail(
                                items: content.railItems(all: catalog.harnesses, currentInstanceId: current?.instanceId),
                                selectedID: content.activeGroup?.id,
                                keyboardFocused: session.focus == .rail
                            ) { id in
                                model.modelPicker?.selectGroup(id, in: content.groups)
                                model.modelPicker?.focus = .rail
                            }
                            providerPanel(catalog: catalog)
                        }
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .frame(height: Self.bodyHeight)
                .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: content.isSearching)
                hairline
                thinking(current: current)
            }
        }
        .frame(width: Self.width)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { panelFrame = $0 }
        .background(PickerEventMonitor(
            isInside: { point in panelFrame.contains(point) || triggerFrame.contains(point) },
            onKey: { key in withAnimation(SwftMotion.resolve(SwftMotion.standard, reduceMotion: reduceMotion)) { model.handleModelPickerKey(key) } },
            onOutsideClick: { closeAnimated() }
        ))
        .task { searchFocused = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Model and thinking level")
    }

    private var hairline: some View {
        Rectangle().fill(SwftColor.borderSubtle).frame(height: 1)
    }

    private func closeAnimated() {
        withAnimation(SwftMotion.resolve(SwftMotion.standard, reduceMotion: reduceMotion)) { model.closeModelPicker() }
    }

    private func pick(_ option: ModelOption) {
        withAnimation(SwftMotion.resolve(SwftMotion.standard, reduceMotion: reduceMotion)) { model.pickModel(option) }
    }

    private func rowIndex(_ option: ModelOption) -> Int? {
        content.rows.firstIndex(where: { $0.id == option.id })
    }

    // MARK: Search

    private func searchResults(catalog: PickerCatalog) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if content.searchResults.isEmpty {
                        PickerNote("No models match “\(session.query.trimmingCharacters(in: .whitespacesAndNewlines))”.")
                    }
                    ForEach(content.searchResults) { option in
                        let harness = ModelPickerLogic.harness(option.instanceId, in: catalog)
                        PickerModelRow(
                            title: option.name,
                            isCurrent: option.id == content.currentModelID,
                            isNew: option.isNew,
                            isHighlighted: session.focus == rowIndex(option).map { .row($0) },
                            leading: PickerRailItem(id: harness.id, symbol: harness.kind.pickerSymbol, monogram: harness.label, tint: harness.kind.tint, accent: harness.accentColor, tooltip: harness.label, inUse: false),
                            detail: ModelPickerLogic.locationLabel(option, in: catalog)
                        ) { pick(option) }
                        .id(option.id)
                    }
                }
            }
            .scrollIndicators(.never)
            .onChange(of: session.focus) { _, focus in scroll(proxy, to: focus) }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, to focus: ModelPickerSession.Focus) {
        guard case .row(let index) = focus, content.rows.indices.contains(index) else { return }
        withAnimation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion)) { proxy.scrollTo(content.rows[index].id) }
    }

    // MARK: Provider panel

    @ViewBuilder
    private func providerPanel(catalog: PickerCatalog) -> some View {
        let group = content.activeGroup
        VStack(alignment: .leading, spacing: 0) {
            if let group, group.harnesses.count > 1 {
                let labels = ModelPickerLogic.accountShortLabels(group.harnesses)
                PickerAccountSwitcher(
                    items: group.harnesses.map { harness in
                        PickerAccountItem(
                            id: harness.id,
                            label: labels[harness.id] ?? harness.label,
                            accent: harness.accentColor,
                            tooltip: ModelPickerLogic.accountTooltip(harness),
                            inUse: harness.id == model.selectedModel?.instanceId
                        )
                    },
                    selectedID: content.activeHarness?.id,
                    keyboardFocused: session.focus == .accounts
                ) { id in
                    model.modelPicker?.selectAccount(id, inGroup: group.id)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 6)
            }
            if content.groups.isEmpty {
                PickerNote(model.serverStatus.isConnected ? "No providers are available." : "Waiting for the local server…")
            }
            if let harness = content.activeHarness {
                harnessModels(harness, showHeader: (group?.harnesses.count ?? 1) == 1, catalog: catalog)
                    .id(harness.id)
                    .transition(.asymmetric(
                        insertion: reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 10 * CGFloat(session.groupStep == 0 ? 1 : session.groupStep))),
                        removal: .identity
                    ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .animation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion), value: content.activeHarness?.id)
    }

    @ViewBuilder
    private func harnessModels(_ harness: PickerHarness, showHeader: Bool, catalog: PickerCatalog) -> some View {
        let models = content.sections.flatMap(\.models)
        let reason = ModelPickerLogic.reason(of: harness)
        let signInOnly = harness.unauthenticated && models.isEmpty && harness.subProviders == nil
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if showHeader {
                        PickerProviderHeader(
                            title: harness.label,
                            accent: harness.accentColor,
                            detail: ModelPickerLogic.detail(of: harness, among: catalog.harnesses),
                            tooltip: harness.account
                        )
                    } else if let reason, !signInOnly {
                        PickerNote(reason)
                    }
                    if harness.unauthenticated {
                        if signInOnly {
                            PickerNote("Sign in with the \(harness.label) CLI to use models from this account, then check again.")
                        }
                        PickerActionButton("Check again", isHighlighted: session.focus == .action) {
                            model.runPickerPanelAction(harnessID: harness.id)
                        }
                    }
                    ForEach(content.sections) { section in
                        if let title = section.title {
                            PickerSectionHeader(title: title, trailing: section.unavailableReason)
                        }
                        ForEach(section.models) { option in
                            PickerModelRow(
                                title: option.name,
                                isCurrent: option.id == content.currentModelID,
                                isNew: option.isNew,
                                isHighlighted: session.focus == rowIndex(option).map { .row($0) }
                            ) { pick(option) }
                            .id(option.id)
                        }
                    }
                    if models.isEmpty && reason == nil && harness.subProviders == nil {
                        PickerNote("No models available.")
                    }
                }
            }
            .scrollIndicators(.never)
            .onChange(of: session.focus) { _, focus in scroll(proxy, to: focus) }
            .onAppear { scroll(proxy, to: content.entryRow.map { .row($0) } ?? .search) }
        }
    }

    // MARK: Thinking

    @ViewBuilder
    private func thinking(current: ModelOption?) -> some View {
        let levels = content.thinkingLevels
        if levels.count > 1 {
            ThinkingSlider(
                levels: levels.map(\.label),
                index: levels.firstIndex(where: { $0.id == model.selectedReasoningChoice?.id }) ?? 0,
                keyboardFocused: session.focus == .thinking
            ) { index in
                model.selectReasoningChoice(levels[index].id)
            }
        } else {
            PickerNote("\(current?.name ?? "This model") has no thinking levels to choose.")
                .padding(.horizontal, 6)
                .padding(.top, 4)
                .padding(.bottom, 8)
        }
    }
}

/// Window-level key and click handling while the picker is open: arrow keys, Return and Escape go to the picker
/// before the search field sees them, and a click anywhere outside the panel and its trigger closes it.
private struct PickerEventMonitor: NSViewRepresentable {
    let isInside: (CGPoint) -> Bool
    let onKey: (ModelPickerKey) -> Bool
    let onOutsideClick: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.parent = self
        context.coordinator.install(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator {
        var parent: PickerEventMonitor?
        private var monitors: [Any] = []
        private weak var view: NSView?

        func install(for view: NSView) {
            self.view = view
            monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let window = event.window.map(ObjectIdentifier.init)
                let keyCode = event.keyCode
                let plain = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
                let handled = MainActor.assumeIsolated { self?.handleKey(keyCode, plain: plain, window: window) ?? false }
                return handled ? nil : event
            } as Any)
            monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                let window = event.window.map(ObjectIdentifier.init)
                let height = event.window?.contentView?.bounds.height ?? 0
                let point = CGPoint(x: event.locationInWindow.x, y: height - event.locationInWindow.y)
                MainActor.assumeIsolated { self?.handleClick(at: point, window: window) }
                return event
            } as Any)
        }

        func uninstall() {
            monitors.forEach(NSEvent.removeMonitor)
            monitors.removeAll()
        }

        private var windowID: ObjectIdentifier? { view?.window.map(ObjectIdentifier.init) }

        private func handleKey(_ keyCode: UInt16, plain: Bool, window: ObjectIdentifier?) -> Bool {
            guard plain, window != nil, window == windowID else { return false }
            let key: ModelPickerKey? = switch keyCode {
            case 126: .up
            case 125: .down
            case 123: .left
            case 124: .right
            case 36, 76: .enter
            case 53: .escape
            default: nil
            }
            guard let key, let parent else { return false }
            return parent.onKey(key)
        }

        private func handleClick(at point: CGPoint, window: ObjectIdentifier?) {
            guard let parent else { return }
            if window != windowID || !parent.isInside(point) { parent.onOutsideClick() }
        }
    }
}
