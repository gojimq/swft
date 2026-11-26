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

    var body: some View {
        VStack(spacing: 0) {
            tabBar
                .zIndex(1)
            Rectangle().fill(SwftColor.borderSubtle).frame(height: 1)
                .zIndex(1)
            // Surfaces paint `.background(canvas)`, which extends into the toolbar's top safe area; clip it so
            // it can never wash over the tab bar sitting in that titlebar band.
            surfaceBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .background(SwftColor.canvas)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .leading) {
            if !panelState.isMaximized {
                Rectangle().fill(SwftColor.borderSubtle).frame(width: 1)
                    .allowsHitTesting(false)
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
        HStack(spacing: 6) {
            if panelState.isMaximized && !model.sidebarVisible {
                // Leave room for the traffic lights, mirroring `TopBar`.
                Color.clear.frame(width: 68, height: 1)
                IconButton("sidebar.left", help: "Show sidebar", size: 28, action: model.toggleSidebar)
            }

            tabStrip

            HStack(spacing: 0) {
                IconButton("plus", help: "Open a surface", size: 28) {
                    _ = model.rightPanel.openLauncherTab(for: threadID)
                }

                Menu {
                    ForEach(RightPanelSurfaceKind.allCases) { kind in
                        Button {
                            model.rightPanel.openSurface(kind, for: threadID)
                        } label: {
                            Label(kind.title, systemImage: kind.iconName)
                        }
                        .disabled(!surfaceAvailability(kind).available)
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(SwftColor.textTertiary)
                        .frame(width: 16, height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Open a surface in a new tab")
            }

            Rectangle()
                .fill(SwftColor.border)
                .frame(width: 1, height: 16)
                .padding(.horizontal, 2)

            HStack(spacing: 0) {
                IconButton(
                    panelState.isMaximized ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    help: panelState.isMaximized ? "Restore split view" : "Expand right panel",
                    size: 28
                ) {
                    model.rightPanel.toggleMaximized(for: threadID)
                }

                IconButton("xmark", help: "Close right panel (⌘⌥B)", size: 28) {
                    model.rightPanel.closePanel(for: threadID)
                }
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .frame(height: RightPanelMetrics.tabBarHeight)
        .background(SwftColor.canvas)
    }

    private var tabStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(panelState.tabs) { tab in
                        RightPanelTabButton(
                            icon: tab.iconName,
                            title: tab.title,
                            isActive: activeTab?.id == tab.id,
                            statusDotColor: statusDotColor(for: tab),
                            onActivate: {
                                model.rightPanel.activateTab(tab.id, for: threadID)
                            },
                            onClose: {
                                closeTab(tab)
                            }
                        )
                        .id(tab.id)
                        .contextMenu {
                            Button("Close Tab") {
                                closeTab(tab)
                            }
                            Button("Close Other Tabs") {
                                let removed = panelState.tabs.filter { $0.id != tab.id }
                                removed.forEach(releaseBrowserControllerIfNeeded)
                                model.rightPanel.closeOtherTabs(keeping: tab.id, for: threadID)
                            }
                            .disabled(panelState.tabs.count <= 1)
                            Divider()
                            Button("Close All Tabs", role: .destructive) {
                                panelState.tabs.forEach(releaseBrowserControllerIfNeeded)
                                model.rightPanel.closeAllTabs(for: threadID)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
            }
            // Soft edges so a clipped tab fades out instead of being cut against the buttons.
            .mask {
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 10)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 14)
                }
            }
            .onAppear {
                if let id = activeTab?.id { proxy.scrollTo(id) }
            }
            .onChange(of: activeTab?.id) { _, id in
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
        model.rightPanel.closeTab(tab.id, for: threadID)
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
    let threadID: String
    let replacingLauncherTabID: String?
    let availability: (RightPanelSurfaceKind) -> (available: Bool, disabledReason: String?)

    @State private var monitorToken = UUID()

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
                                model.rightPanel.openSurface(
                                    kind,
                                    for: threadID,
                                    replacingLauncherTabID: replacingLauncherTabID
                                )
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
                model.rightPanel.openSurface(
                    kind,
                    for: threadID,
                    replacingLauncherTabID: replacingLauncherTabID
                )
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
