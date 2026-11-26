import AppKit
import SwftDesign
import SwftKit
import SwiftUI

struct RightPanelContainerView: View {
    @Environment(AppModel.self) private var model
    let threadID: String
    let availableWindowWidth: CGFloat

    private var panelState: ThreadRightPanelState {
        model.rightPanel.state(for: threadID)
    }

    private var activeTab: RightPanelTab? {
        panelState.activeTab
    }

    var body: some View {
        HStack(spacing: 0) {
            if !panelState.isMaximized {
                RightPanelResizeHandle { delta in
                    model.rightPanel.adjustWidth(by: delta, availableWindowWidth: availableWindowWidth)
                }
            }

            VStack(spacing: 0) {
                tabBar
                Divider().overlay(SwftColor.borderSubtle)
                surfaceBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(SwftColor.canvas)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Top Tab Bar

    private var tabBar: some View {
        HStack(spacing: 4) {
            if panelState.isMaximized && !model.sidebarVisible {
                Color.clear.frame(width: 76, height: 1)
                IconButton("sidebar.left", help: "Show sidebar", size: 26, action: model.toggleSidebar)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
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
                        .contextMenu {
                            Button("Close") {
                                closeTab(tab)
                            }
                            Button("Close Others") {
                                let removed = panelState.tabs.filter { $0.id != tab.id }
                                removed.forEach(releaseBrowserControllerIfNeeded)
                                model.rightPanel.closeOtherTabs(keeping: tab.id, for: threadID)
                            }
                            .disabled(panelState.tabs.count <= 1)
                            Divider()
                            Button("Close All", role: .destructive) {
                                panelState.tabs.forEach(releaseBrowserControllerIfNeeded)
                                model.rightPanel.closeAllTabs(for: threadID)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            HStack(spacing: 2) {
                IconButton("plus", help: "Open a surface", size: 26) {
                    model.rightPanel.openLauncherTab(for: threadID)
                }

                Menu {
                    ForEach(RightPanelSurfaceKind.allCases) { kind in
                        let availability = surfaceAvailability(kind)
                        Button {
                            model.rightPanel.openSurface(kind, for: threadID)
                        } label: {
                            Label("\(kind.title)  (\(kind.shortcutKey))", systemImage: kind.iconName)
                        }
                        .disabled(!availability.available)
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(SwftColor.textTertiary)
                        .frame(width: 18, height: 26)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Quick open a surface")
            }

            Spacer(minLength: 4)

            HStack(spacing: 2) {
                IconButton(
                    panelState.isMaximized ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    help: panelState.isMaximized ? "Restore split width" : "Expand right panel",
                    size: 26
                ) {
                    model.rightPanel.toggleMaximized(for: threadID)
                }

                IconButton("xmark", help: "Close right panel (⌘⌥B)", size: 26) {
                    model.rightPanel.closePanel(for: threadID)
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: RightPanelMetrics.tabBarHeight)
        .background(SwftColor.sidebar.opacity(0.65))
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
        case .browser, .linkedItems, .device, .sideChat:
            return (true, nil)
        case .files:
            if model.workspaceRoot(forThreadID: threadID) != nil {
                return (true, nil)
            }
            return (false, "Available when a project is attached to this thread.")
        }
    }

    private func statusDotColor(for tab: RightPanelTab) -> Color? {
        if case .sideChat(let state) = tab.payload,
           let sideID = state.sideThreadId,
           let store = model.rightPanel.sideChatStores[sideID]
        {
            if !store.pendingApprovals.isEmpty { return SwftColor.warning }
            if store.isRunning { return SwftColor.accent }
        }
        return nil
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
        ScrollView {
            VStack(spacing: 12) {
                Text("Open a surface")
                    .font(SwftType.labelStrong)
                    .foregroundStyle(SwftColor.textPrimary)
                    .padding(.bottom, 2)

                VStack(spacing: 3) {
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
            .frame(maxWidth: 310)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
