import AppKit
import SwftDesign
import SwftKit
import SwiftUI

struct RightPanelContainerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let threadID: String
    let availableWindowWidth: CGFloat

    private var panelState: ThreadRightPanelState {
        model.rightPanel.state(for: threadID)
    }

    private var activeTab: RightPanelTab? {
        panelState.activeTab
    }

    @State private var dragStartWidth: CGFloat?
    @State private var hoveredTabID: String?
    @State private var scrollEdges = TabStripScrollEdges()

    private struct TabStripScrollEdges: Equatable {
        var canScrollLeading = false
        var canScrollTrailing = false
    }

    private var tabLifecycleAnimation: Animation {
        SwftMotion.resolve(RightPanelMotion.tabLifecycle, reduceMotion: reduceMotion)
    }

    private var tabSwitchAnimation: Animation {
        SwftMotion.resolve(RightPanelMotion.tabSwitch, reduceMotion: reduceMotion)
    }

    private var panelLayoutAnimation: Animation {
        SwftMotion.resolve(RightPanelMotion.panelLayout, reduceMotion: reduceMotion)
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
                .zIndex(2)
            // Surfaces paint `.background(canvas)`, which extends into the toolbar's top safe area; clip it so
            // it can never wash over the tab bar sitting in that titlebar band.
            ZStack {
                surfaceBody
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .animation(
                SwftMotion.resolve(SwftMotion.screenSwitch, reduceMotion: reduceMotion),
                value: activeTab?.id
            )
        }
        .background(SwftColor.canvas)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .leading) {
            // Separate overlay so the 1pt edge sits strictly at x = 0 instead of centering inside the 8pt resize handle.
            let showLeadingEdge = !panelState.isMaximized || model.sidebarVisible
            Rectangle()
                .fill(SwftColor.borderSubtle)
                .frame(width: 1)
                .opacity(showLeadingEdge ? 1 : 0)
                .allowsHitTesting(false)
                .animation(panelLayoutAnimation, value: showLeadingEdge)
        }
        .overlay(alignment: .leading) {
            if !panelState.isMaximized {
                // Straddles the split edge without taking layout width, so no gutter shows between columns.
                RightPanelResizeHandle { travel in
                    let start = dragStartWidth
                        ?? RightPanelLogic.clampedWidth(model.rightPanel.panelWidth, availableWindowWidth: availableWindowWidth)
                    dragStartWidth = start
                    model.rightPanel.setWidth(start + travel, availableWindowWidth: availableWindowWidth)
                } onDragEnded: {
                    dragStartWidth = nil
                }
                .offset(x: -RightPanelMetrics.resizeHandleHitWidth / 2)
            }
        }
    }

    // MARK: - Top Tab Bar

    private var tabBar: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if panelState.isMaximized && !model.sidebarVisible {
                HStack(spacing: 4) {
                    // Leave room for the traffic lights, mirroring `TopBar`.
                    Color.clear.frame(width: 74, height: 1)
                    IconButton("sidebar.left", help: "Show sidebar", size: 28, action: model.toggleSidebar)
                }
                .padding(.trailing, 4)
                .padding(.bottom, 11)
                .transition(.swftPop(reduceMotion: reduceMotion, scale: 0.8))
            }

            DiaTabBarAccessoryLayout(spacing: 2, emptyLeadingInset: 4) {
                tabStrip
                addTabControl
                    .padding(.bottom, 11)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(tabLifecycleAnimation, value: panelState.tabs.map(\.id))

            HStack(spacing: 2) {
                Rectangle()
                    .fill(RightPanelColor.tabDivider)
                    .frame(width: 1, height: 16)
                    .padding(.horizontal, 4)

                IconButton(
                    panelState.isMaximized ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    help: panelState.isMaximized ? "Restore split view" : "Expand right panel",
                    size: 28
                ) {
                    withAnimation(panelLayoutAnimation) {
                        model.rightPanel.toggleMaximized(for: threadID)
                    }
                }

                IconButton("xmark", help: "Close right panel (⌘⌥B)", size: 28) {
                    withAnimation(panelLayoutAnimation) {
                        model.rightPanel.closePanel(for: threadID)
                    }
                }
            }
            .padding(.bottom, 11)
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .frame(height: RightPanelMetrics.tabBarHeight)
        .background {
            RightPanelColor.tabStripBackground
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(RightPanelColor.tabBorder)
                        .frame(height: 1)
                }
        }
        .animation(panelLayoutAnimation, value: panelState.isMaximized && !model.sidebarVisible)
    }

    private var addTabControl: some View {
        HStack(spacing: 0) {
            IconButton("plus", help: "Open a surface", size: 28, weight: .medium) {
                withAnimation(tabLifecycleAnimation) {
                    _ = model.rightPanel.openLauncherTab(for: threadID)
                }
            }

            Menu {
                ForEach(RightPanelSurfaceKind.allCases) { kind in
                    Button {
                        withAnimation(tabLifecycleAnimation) {
                            _ = model.rightPanel.openSurface(kind, for: threadID)
                        }
                    } label: {
                        Label(kind.title, systemImage: kind.iconName)
                    }
                    .disabled(!surfaceAvailability(kind).available)
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(SwftColor.textTertiary)
                    .frame(width: 16, height: 24)
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .menuStyle(.button)
            .buttonStyle(HoverFillStyle(shape: RoundedRectangle(cornerRadius: 6, style: .continuous), pressScale: 0.92))
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Open a surface in a new tab")
        }
    }

    private var tabStrip: some View {
        let tabs = panelState.tabs
        let tabIDs = tabs.map(\.id)
        let activeID = activeTab?.id
        let shoulder = RightPanelMetrics.tabShoulderRadius

        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                        let isActive = activeID == tab.id
                        let showDivider = DiaTabStripLayout.showsTrailingDivider(
                            at: index,
                            tabIDs: tabIDs,
                            activeTabID: activeID,
                            hoveredTabID: hoveredTabID
                        )

                        RightPanelTabButton(
                            icon: tab.iconName,
                            title: tab.title,
                            isActive: isActive,
                            statusDotColor: statusDotColor(for: tab),
                            showTrailingDivider: showDivider,
                            onHoverChanged: { isHovering in
                                if isHovering {
                                    hoveredTabID = tab.id
                                } else if hoveredTabID == tab.id {
                                    hoveredTabID = nil
                                }
                            },
                            onActivate: {
                                withAnimation(tabSwitchAnimation) {
                                    model.rightPanel.activateTab(tab.id, for: threadID)
                                }
                            },
                            onClose: {
                                closeTab(tab)
                            }
                        )
                        // Include outer concave shoulder clearance inside `.id(tab.id)` so `scrollTo` brings
                        // the first/last active tab's full curved shoulder cleanly onscreen without edge fading.
                        .padding(.leading, index == 0 ? shoulder : 0)
                        .padding(.trailing, index == tabs.count - 1 ? shoulder : 0)
                        .id(tab.id)
                        .zIndex(isActive ? 2 : (hoveredTabID == tab.id ? 1 : 0))
                        .transition(.diaTabTransition(reduceMotion: reduceMotion))
                        .contextMenu {
                            Button("Close Tab") {
                                closeTab(tab)
                            }
                            Button("Close Other Tabs") {
                                let removed = panelState.tabs.filter { $0.id != tab.id }
                                removed.forEach(releaseBrowserControllerIfNeeded)
                                withAnimation(tabLifecycleAnimation) {
                                    model.rightPanel.closeOtherTabs(keeping: tab.id, for: threadID)
                                }
                            }
                            .disabled(panelState.tabs.count <= 1)
                            Divider()
                            Button("Close All Tabs", role: .destructive) {
                                panelState.tabs.forEach(releaseBrowserControllerIfNeeded)
                                withAnimation(tabLifecycleAnimation) {
                                    model.rightPanel.closeAllTabs(for: threadID)
                                }
                            }
                        }
                    }
                }
                .padding(.top, RightPanelMetrics.tabTopInset)
                .frame(height: RightPanelMetrics.tabBarHeight, alignment: .bottom)
                .animation(tabLifecycleAnimation, value: tabIDs)
            }
            .defaultScrollAnchor(.leading)
            .frame(height: RightPanelMetrics.tabBarHeight)
            .onScrollGeometryChange(for: TabStripScrollEdges.self) { geo in
                TabStripScrollEdges(
                    canScrollLeading: geo.contentOffset.x > 2,
                    canScrollTrailing: geo.contentSize.width - geo.containerSize.width - geo.contentOffset.x > 2
                )
            } action: { _, next in
                scrollEdges = next
            }
            // Only fade edges when tabs actually overflow offscreen so first/last active tab shoulders stay crisp.
            .mask {
                HStack(spacing: 0) {
                    if scrollEdges.canScrollLeading {
                        LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 12)
                    }
                    Color.black
                    if scrollEdges.canScrollTrailing {
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 16)
                    }
                }
            }
            .onAppear {
                if let id = activeID { proxy.scrollTo(id) }
            }
            .onChange(of: activeID) { _, id in
                guard let id else { return }
                withAnimation(SwftMotion.resolve(SwftMotion.standard, reduceMotion: reduceMotion)) {
                    proxy.scrollTo(id)
                }
            }
        }
    }

    // MARK: - Surface Content Router

    @ViewBuilder
    private var surfaceBody: some View {
        if let tab = activeTab {
            switch tab.payload {
            case .launcher:
                RightPanelLauncherView(
                    threadID: threadID,
                    replacingLauncherTabID: tab.id,
                    availability: surfaceAvailability
                )
            case .browser(let browserState):
                BrowserSurfaceView(threadID: threadID, tabID: tab.id, browserState: browserState)
                    .id(tab.id)
            case .files(let filesState):
                FilesSurfaceView(threadID: threadID, tabID: tab.id, filesState: filesState)
                    .id(tab.id)
            case .linkedItems:
                LinkedItemsSurfaceView(threadID: threadID)
                    .id(tab.id)
            case .device(let deviceState):
                DeviceSurfaceView(threadID: threadID, tabID: tab.id, deviceState: deviceState)
                    .id(tab.id)
            case .sideChat(let sideChatState):
                SideChatSurfaceView(threadID: threadID, tabID: tab.id, sideChatState: sideChatState)
                    .id(tab.id)
            case .subagent(let subagentState):
                SubagentSurfaceView(threadID: threadID, tabID: tab.id, subagentState: subagentState)
                    .id(tab.id)
            }
        } else {
            RightPanelLauncherView(
                threadID: threadID,
                replacingLauncherTabID: nil,
                availability: surfaceAvailability
            )
        }
    }

    private func surfaceAvailability(_ kind: RightPanelSurfaceKind) -> (available: Bool, disabledReason: String?) {
        switch kind {
        case .browser, .linkedItems, .device:
            return (true, nil)
        case .files:
            if model.workspaceRoot(forThreadID: threadID) != nil {
                return (true, nil)
            }
            return (false, "Attach a project to browse its files")
        case .sideChat:
            // Side chats fork from the thread's latest stable point, so they need a first message to fork from.
            let hasMessage = model.detail(for: threadID)?.items.contains {
                if case .user = $0.kind { return true }
                return false
            } ?? false
            return hasMessage ? (true, nil) : (false, "Send a first message to fork a side chat")
        }
    }

    private func statusDotColor(for tab: RightPanelTab) -> Color? {
        switch tab.payload {
        case .sideChat(let state):
            if let sideID = state.sideThreadId,
               let store = model.rightPanel.sideChatStores[sideID]
            {
                if !store.pendingApprovals.isEmpty { return SwftColor.warning }
                if store.isRunning { return SwftColor.accent }
            }
            return nil
        case .subagent(let state):
            let store = model.rightPanel.subagentStores[state.subagentThreadId]
            let hasPendingApprovals = store.map { !$0.pendingApprovals.isEmpty || !$0.pendingUserInputs.isEmpty } ?? false
            let isLiveRunning = store?.isRunning == true
            return RightPanelLogic.subagentStatusDotTone(
                status: state.status,
                hasPendingApprovals: hasPendingApprovals,
                isLiveRunning: isLiveRunning
            ).map(RightPanelLogic.statusDotColor(for:))
        default:
            return nil
        }
    }

    private func closeTab(_ tab: RightPanelTab) {
        releaseBrowserControllerIfNeeded(tab)
        if hoveredTabID == tab.id { hoveredTabID = nil }
        withAnimation(tabLifecycleAnimation) {
            model.rightPanel.closeTab(tab.id, for: threadID)
        }
    }

    private func releaseBrowserControllerIfNeeded(_ tab: RightPanelTab) {
        if case .browser = tab.payload {
            BrowserControllerPool.shared.remove(tabID: tab.id)
        }
    }
}

// MARK: - "Open a surface" Launcher with Single-Key Shortcuts (B, F, L, M, S)

struct RightPanelLauncherView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let threadID: String
    let replacingLauncherTabID: String?
    let availability: (RightPanelSurfaceKind) -> (available: Bool, disabledReason: String?)

    @State private var monitorToken = UUID()

    private var tabLifecycleAnimation: Animation {
        SwftMotion.resolve(RightPanelMotion.tabLifecycle, reduceMotion: reduceMotion)
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 4) {
                        Text("Open a surface")
                            .font(SwftType.headline)
                            .foregroundStyle(SwftColor.textPrimary)
                        Text("Pick one below or press its key")
                            .font(SwftType.caption)
                            .foregroundStyle(SwftColor.textTertiary)
                    }

                    VStack(spacing: 2) {
                        ForEach(RightPanelSurfaceKind.allCases) { kind in
                            let status = availability(kind)
                            RightPanelSurfaceLauncherRow(
                                icon: kind.iconName,
                                title: kind.title,
                                subtitle: kind.subtitle,
                                shortcut: kind.shortcutKey,
                                isAvailable: status.available,
                                disabledReason: status.disabledReason
                            ) {
                                withAnimation(tabLifecycleAnimation) {
                                    _ = model.rightPanel.openSurface(
                                        kind,
                                        for: threadID,
                                        replacingLauncherTabID: replacingLauncherTabID
                                    )
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: RightPanelMetrics.launcherWidth)
                .padding(.horizontal, 20)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
                // Sit slightly above center: optical center reads calmer than geometric center.
                .frame(minHeight: geo.size.height * 0.86)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear {
            RightPanelShortcutRouter.activate(token: monitorToken) { key, hasModifiers in
                guard let kind = RightPanelLogic.surfaceKind(
                    forKey: key,
                    hasCommandOrControlOrOption: hasModifiers
                ) else { return false }
                guard availability(kind).available else { return false }
                withAnimation(tabLifecycleAnimation) {
                    _ = model.rightPanel.openSurface(
                        kind,
                        for: threadID,
                        replacingLauncherTabID: replacingLauncherTabID
                    )
                }
                return true
            }
        }
        .onDisappear {
            RightPanelShortcutRouter.deactivate(token: monitorToken)
        }
    }
}

/// Handles single-key launcher shortcuts (`B`, `F`, `L`, `M`, `S`) while the "Open a surface" view is active,
/// never intercepting typing inside text fields/editors or when a sheet/popover is open.
@MainActor
enum RightPanelShortcutRouter {
    private static var activeToken: UUID?
    private static var monitor: Any?
    private static var handler: ((String, Bool) -> Bool)?

    static func activate(token: UUID, handler newHandler: @escaping (String, Bool) -> Bool) {
        activeToken = token
        handler = newHandler
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            nonisolated(unsafe) let keyEvent = event
            let handled = MainActor.assumeIsolated { handle(keyEvent) }
            return handled ? nil : event
        }
    }

    static func deactivate(token: UUID) {
        guard activeToken == token else { return }
        activeToken = nil
        handler = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static func handle(_ event: NSEvent) -> Bool {
        guard let handler,
              event.window?.isKeyWindow == true,
              event.window?.attachedSheet == nil
        else { return false }

        // Never intercept single-key shortcuts while the user is typing in a text field, composer, or WebView.
        if let firstResponder = event.window?.firstResponder {
            if firstResponder is NSTextView || firstResponder is NSTextField {
                return false
            }
            let responderName = String(describing: type(of: firstResponder))
            if responderName.contains("WK") || responderName.contains("Text") || responderName.contains("Field") {
                return false
            }
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasModifiers = flags.contains(.command) || flags.contains(.control) || flags.contains(.option)
        guard let chars = event.charactersIgnoringModifiers, !chars.isEmpty else { return false }
        return handler(chars, hasModifiers)
    }
}
