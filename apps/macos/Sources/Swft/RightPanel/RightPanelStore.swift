import Foundation
import Observation
import SwftDesign
import SwftKit

/// Per-thread state manager for Swft's native Right Sidebar tab system and live side-chat stores.
@MainActor
@Observable
final class RightPanelStore {
    private(set) var byThreadID: [String: ThreadRightPanelState] = [:]
    var panelWidth: CGFloat = RightPanelMetrics.defaultWidth

    /// Live `ThreadStore` instances for active side-chat tabs (keyed by side thread ID).
    private(set) var sideChatStores: [String: ThreadStore] = [:]
    /// Optimistic user messages sent in a side chat before server echo.
    var pendingSideChatMessages: [String: [PendingUserMessage]] = [:]
    /// Pending draft prompt seeded into a side-chat tab (e.g. from `/side <prompt>`).
    var pendingSideChatDrafts: [String: String] = [:]

    func takePendingSideChatDraft(forTabID tabID: String) -> String? {
        pendingSideChatDrafts.removeValue(forKey: tabID)
    }
    /// Mock-mode transcripts keyed by side-chat tab/thread ID.
    var mockSideChatItems: [String: [TranscriptItem]] = [:]
    /// Mock-mode linked PR/issue overrides keyed by thread ID so unlinking/linking updates immediately in mock mode.
    var mockLinkedPRsByThreadID: [String: [ThreadPullRequestLink]] = [:]
    var mockLinkedIssuesByThreadID: [String: [ThreadIssueLink]] = [:]

    // MARK: - Queries

    func state(for threadID: String) -> ThreadRightPanelState {
        byThreadID[threadID] ?? ThreadRightPanelState()
    }

    func isOpen(for threadID: String) -> Bool {
        byThreadID[threadID]?.isOpen == true
    }

    func isMaximized(for threadID: String) -> Bool {
        byThreadID[threadID]?.isMaximized == true
    }

    func tabs(for threadID: String) -> [RightPanelTab] {
        byThreadID[threadID]?.tabs ?? []
    }

    func activeTab(for threadID: String) -> RightPanelTab? {
        byThreadID[threadID]?.activeTab
    }

    // MARK: - Panel Visibility & Geometry

    func togglePanel(for threadID: String) {
        var current = state(for: threadID)
        current.isOpen.toggle()
        if !current.isOpen {
            current.isMaximized = false
        }
        byThreadID[threadID] = current
    }

    func openPanel(for threadID: String) {
        var current = state(for: threadID)
        current.isOpen = true
        byThreadID[threadID] = current
    }

    func closePanel(for threadID: String) {
        var current = state(for: threadID)
        current.isOpen = false
        current.isMaximized = false
        byThreadID[threadID] = current
    }

    func toggleMaximized(for threadID: String) {
        var current = state(for: threadID)
        guard current.isOpen else { return }
        current.isMaximized.toggle()
        byThreadID[threadID] = current
    }

    func setMaximized(_ maximized: Bool, for threadID: String) {
        var current = state(for: threadID)
        current.isMaximized = maximized && current.isOpen
        byThreadID[threadID] = current
    }

    func adjustWidth(by delta: CGFloat, availableWindowWidth: CGFloat? = nil) {
        panelWidth = RightPanelLogic.clampedWidth(
            panelWidth + delta,
            availableWindowWidth: availableWindowWidth
        )
    }

    func setWidth(_ width: CGFloat, availableWindowWidth: CGFloat? = nil) {
        panelWidth = RightPanelLogic.clampedWidth(width, availableWindowWidth: availableWindowWidth)
    }

    // MARK: - Tab Lifecycle

    @discardableResult
    func openLauncherTab(for threadID: String) -> RightPanelTab {
        var current = state(for: threadID)
        current.isOpen = true
        if let existing = current.tabs.first(where: { $0.payload == .launcher }) {
            current.activeTabID = existing.id
            byThreadID[threadID] = current
            return existing
        }
        let tab = RightPanelTab(id: "launcher:\(UUID().uuidString)", payload: .launcher)
        current.tabs.append(tab)
        current.activeTabID = tab.id
        byThreadID[threadID] = current
        return tab
    }

    @discardableResult
    func openSurface(
        _ kind: RightPanelSurfaceKind,
        for threadID: String,
        replacingLauncherTabID: String? = nil
    ) -> RightPanelTab {
        switch kind {
        case .browser:
            return openBrowser(for: threadID, replacingLauncherTabID: replacingLauncherTabID)
        case .files:
            return openFiles(for: threadID, replacingLauncherTabID: replacingLauncherTabID)
        case .linkedItems:
            return openLinkedItems(for: threadID, replacingLauncherTabID: replacingLauncherTabID)
        case .device:
            return openDevice(for: threadID, replacingLauncherTabID: replacingLauncherTabID)
        case .sideChat:
            return openSideChat(for: threadID, replacingLauncherTabID: replacingLauncherTabID)
        }
    }

    @discardableResult
    func openBrowser(
        urlString: String = "",
        pageTitle: String? = nil,
        serverPreviewTabId: String? = nil,
        for threadID: String,
        replacingLauncherTabID: String? = nil
    ) -> RightPanelTab {
        var current = state(for: threadID)
        current.isOpen = true

        if let serverPreviewTabId,
           let existing = current.tabs.first(where: {
               if case .browser(let state) = $0.payload {
                   return state.serverPreviewTabId == serverPreviewTabId
               }
               return false
           })
        {
            current.activeTabID = existing.id
            byThreadID[threadID] = current
            return existing
        }

        let tab = RightPanelTab(
            id: "browser:\(UUID().uuidString)",
            payload: .browser(BrowserTabState(
                urlString: urlString,
                pageTitle: pageTitle,
                serverPreviewTabId: serverPreviewTabId
            ))
        )
        insertOrReplaceLauncher(&current, with: tab, replacingLauncherTabID: replacingLauncherTabID)
        byThreadID[threadID] = current
        return tab
    }

    @discardableResult
    func openFiles(
        selectedFilePath: String? = nil,
        for threadID: String,
        replacingLauncherTabID: String? = nil
    ) -> RightPanelTab {
        var current = state(for: threadID)
        current.isOpen = true

        if let existingIndex = current.tabs.firstIndex(where: {
            if case .files = $0.payload { return true }
            return false
        }) {
            if let selectedFilePath {
                if case .files(var filesState) = current.tabs[existingIndex].payload {
                    filesState.selectedFilePath = selectedFilePath
                    if !filesState.openFilePaths.contains(selectedFilePath) {
                        filesState.openFilePaths.append(selectedFilePath)
                    }
                    filesState.folderPath = RightPanelLogic.parentDirectory(of: selectedFilePath)
                    current.tabs[existingIndex].payload = .files(filesState)
                }
            }
            if let launcherID = replacingLauncherTabID {
                current.tabs.removeAll { $0.id == launcherID && $0.payload == .launcher }
            }
            current.activeTabID = current.tabs[existingIndex].id
            byThreadID[threadID] = current
            return current.tabs[existingIndex]
        }

        let initialOpen = selectedFilePath.map { [$0] } ?? []
        let initialFolder = selectedFilePath.map(RightPanelLogic.parentDirectory(of:)) ?? ""
        let tab = RightPanelTab(
            id: "files:\(UUID().uuidString)",
            payload: .files(FilesTabState(
                selectedFilePath: selectedFilePath,
                openFilePaths: initialOpen,
                folderPath: initialFolder
            ))
        )
        insertOrReplaceLauncher(&current, with: tab, replacingLauncherTabID: replacingLauncherTabID)
        byThreadID[threadID] = current
        return tab
    }

    @discardableResult
    func openLinkedItems(
        for threadID: String,
        replacingLauncherTabID: String? = nil
    ) -> RightPanelTab {
        var current = state(for: threadID)
        current.isOpen = true

        if let existing = current.tabs.first(where: { $0.payload == .linkedItems }) {
            if let launcherID = replacingLauncherTabID {
                current.tabs.removeAll { $0.id == launcherID && $0.payload == .launcher }
            }
            current.activeTabID = existing.id
            byThreadID[threadID] = current
            return existing
        }

        let tab = RightPanelTab(id: "linked-items", payload: .linkedItems)
        insertOrReplaceLauncher(&current, with: tab, replacingLauncherTabID: replacingLauncherTabID)
        byThreadID[threadID] = current
        return tab
    }

    @discardableResult
    func openDevice(
        hostId: String? = nil,
        deviceId: String? = nil,
        platform: DevicePlatform? = nil,
        deviceName: String? = nil,
        for threadID: String,
        replacingLauncherTabID: String? = nil
    ) -> RightPanelTab {
        var current = state(for: threadID)
        current.isOpen = true

        if let deviceId,
           let existing = current.tabs.first(where: {
               if case .device(let state) = $0.payload {
                   return state.deviceId == deviceId && (hostId == nil || state.hostId == hostId)
               }
               return false
           })
        {
            if let launcherID = replacingLauncherTabID {
                current.tabs.removeAll { $0.id == launcherID && $0.payload == .launcher }
            }
            current.activeTabID = existing.id
            byThreadID[threadID] = current
            return existing
        }

        // Reuse an unassigned Device tab when clicking Device without a specific target.
        if deviceId == nil,
           let existing = current.tabs.first(where: {
               if case .device = $0.payload { return true }
               return false
           })
        {
            if let launcherID = replacingLauncherTabID {
                current.tabs.removeAll { $0.id == launcherID && $0.payload == .launcher }
            }
            current.activeTabID = existing.id
            byThreadID[threadID] = current
            return existing
        }

        let tab = RightPanelTab(
            id: "device:\(UUID().uuidString)",
            payload: .device(DeviceTabState(
                hostId: hostId,
                deviceId: deviceId,
                platform: platform,
                deviceName: deviceName
            ))
        )
        insertOrReplaceLauncher(&current, with: tab, replacingLauncherTabID: replacingLauncherTabID)
        byThreadID[threadID] = current
        return tab
    }

    @discardableResult
    func openSideChat(
        sideThreadId: String? = nil,
        title: String? = nil,
        for threadID: String,
        replacingLauncherTabID: String? = nil
    ) -> RightPanelTab {
        var current = state(for: threadID)
        current.isOpen = true

        if let sideThreadId,
           let existing = current.tabs.first(where: {
               if case .sideChat(let state) = $0.payload {
                   return state.sideThreadId == sideThreadId
               }
               return false
           })
        {
            if let launcherID = replacingLauncherTabID {
                current.tabs.removeAll { $0.id == launcherID && $0.payload == .launcher }
            }
            current.activeTabID = existing.id
            byThreadID[threadID] = current
            return existing
        }

        let tab = RightPanelTab(
            id: "side-chat:\(sideThreadId ?? UUID().uuidString)",
            payload: .sideChat(SideChatTabState(sideThreadId: sideThreadId, title: title, isCreating: false))
        )
        insertOrReplaceLauncher(&current, with: tab, replacingLauncherTabID: replacingLauncherTabID)
        byThreadID[threadID] = current
        return tab
    }

    func activateTab(_ tabID: String, for threadID: String) {
        var current = state(for: threadID)
        guard current.tabs.contains(where: { $0.id == tabID }) else { return }
        current.isOpen = true
        current.activeTabID = tabID
        byThreadID[threadID] = current
    }

    func closeTab(_ tabID: String, for threadID: String) {
        var current = state(for: threadID)
        guard let index = current.tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let removed = current.tabs.remove(at: index)
        cleanupResources(for: [removed], remainingTabs: allTabsExcluding(threadID: threadID, extra: current.tabs))

        if current.activeTabID == tabID {
            if current.tabs.isEmpty {
                current.activeTabID = nil
            } else {
                let nextIndex = min(index, current.tabs.count - 1)
                current.activeTabID = current.tabs[nextIndex].id
            }
        }
        byThreadID[threadID] = current
    }

    func closeOtherTabs(keeping tabID: String, for threadID: String) {
        var current = state(for: threadID)
        guard let kept = current.tabs.first(where: { $0.id == tabID }) else { return }
        let removed = current.tabs.filter { $0.id != tabID }
        current.tabs = [kept]
        current.activeTabID = kept.id
        byThreadID[threadID] = current
        cleanupResources(for: removed, remainingTabs: allTabsExcluding(threadID: threadID, extra: current.tabs))
    }

    func closeAllTabs(for threadID: String) {
        var current = state(for: threadID)
        let removed = current.tabs
        current.tabs.removeAll()
        current.activeTabID = nil
        byThreadID[threadID] = current
        cleanupResources(for: removed, remainingTabs: allTabsExcluding(threadID: threadID, extra: []))
    }

    // MARK: - Per-Tab Payload Updates

    func updateBrowserTab(
        tabID: String,
        urlString: String? = nil,
        pageTitle: String? = nil,
        serverPreviewTabId: String? = nil,
        for threadID: String
    ) {
        mutateTab(tabID: tabID, for: threadID) { tab in
            guard case .browser(var browser) = tab.payload else { return }
            if let urlString { browser.urlString = urlString }
            if let pageTitle { browser.pageTitle = pageTitle }
            if let serverPreviewTabId { browser.serverPreviewTabId = serverPreviewTabId }
            tab.payload = .browser(browser)
        }
    }

    func updateFilesTab(
        tabID: String,
        selectedFilePath: String?,
        folderPath: String? = nil,
        for threadID: String
    ) {
        mutateTab(tabID: tabID, for: threadID) { tab in
            guard case .files(var files) = tab.payload else { return }
            files.selectedFilePath = selectedFilePath
            if let selectedFilePath, !selectedFilePath.isEmpty, !files.openFilePaths.contains(selectedFilePath) {
                files.openFilePaths.append(selectedFilePath)
            }
            if let folderPath {
                files.folderPath = folderPath
            }
            tab.payload = .files(files)
        }
    }

    func closeOpenFile(_ path: String, inTabID tabID: String, for threadID: String) {
        mutateTab(tabID: tabID, for: threadID) { tab in
            guard case .files(var files) = tab.payload else { return }
            guard let idx = files.openFilePaths.firstIndex(of: path) else { return }
            files.openFilePaths.remove(at: idx)
            if files.selectedFilePath == path {
                files.selectedFilePath = files.openFilePaths.isEmpty
                    ? nil
                    : files.openFilePaths[min(idx, files.openFilePaths.count - 1)]
            }
            tab.payload = .files(files)
        }
    }

    func updateDeviceTab(
        tabID: String,
        hostId: String?,
        deviceId: String?,
        platform: DevicePlatform?,
        deviceName: String?,
        for threadID: String
    ) {
        mutateTab(tabID: tabID, for: threadID) { tab in
            guard case .device(var device) = tab.payload else { return }
            device.hostId = hostId
            device.deviceId = deviceId
            device.platform = platform
            device.deviceName = deviceName
            tab.payload = .device(device)
        }
    }

    func updateSideChatTab(
        tabID: String,
        sideThreadId: String? = nil,
        title: String? = nil,
        isCreating: Bool? = nil,
        for threadID: String
    ) {
        mutateTab(tabID: tabID, for: threadID) { tab in
            guard case .sideChat(var sideChat) = tab.payload else { return }
            if let sideThreadId { sideChat.sideThreadId = sideThreadId }
            if let title { sideChat.title = title }
            if let isCreating { sideChat.isCreating = isCreating }
            tab.payload = .sideChat(sideChat)
        }
    }

    // MARK: - Side Chat ThreadStore Lifecycle

    func ensureSideChatStore(
        sideThreadId: String,
        connection: ServerConnection
    ) -> ThreadStore {
        if let existing = sideChatStores[sideThreadId], existing.connection === connection {
            return existing
        }
        sideChatStores[sideThreadId]?.stop()
        let store = ThreadStore(connection: connection, threadId: sideThreadId)
        sideChatStores[sideThreadId] = store
        store.start()
        return store
    }

    func stopSideChatStore(sideThreadId: String) {
        sideChatStores.removeValue(forKey: sideThreadId)?.stop()
        pendingSideChatMessages.removeValue(forKey: sideThreadId)
    }

    func shutdown() {
        for store in sideChatStores.values {
            store.stop()
        }
        sideChatStores.removeAll()
        pendingSideChatMessages.removeAll()
    }

    // MARK: - Private Helpers

    private func insertOrReplaceLauncher(
        _ current: inout ThreadRightPanelState,
        with tab: RightPanelTab,
        replacingLauncherTabID: String?
    ) {
        if let launcherID = replacingLauncherTabID,
           let idx = current.tabs.firstIndex(where: { $0.id == launcherID && $0.payload == .launcher })
        {
            current.tabs[idx] = tab
        } else {
            current.tabs.append(tab)
        }
        current.activeTabID = tab.id
    }

    private func mutateTab(tabID: String, for threadID: String, update: (inout RightPanelTab) -> Void) {
        var current = state(for: threadID)
        guard let index = current.tabs.firstIndex(where: { $0.id == tabID }) else { return }
        update(&current.tabs[index])
        byThreadID[threadID] = current
    }

    private func allTabsExcluding(threadID: String, extra: [RightPanelTab]) -> [RightPanelTab] {
        var result = extra
        for (id, panelState) in byThreadID where id != threadID {
            result.append(contentsOf: panelState.tabs)
        }
        return result
    }

    private func cleanupResources(for removed: [RightPanelTab], remainingTabs: [RightPanelTab]) {
        let remainingSideChatIDs: Set<String> = Set(remainingTabs.compactMap { tab in
            if case .sideChat(let state) = tab.payload { return state.sideThreadId }
            return nil
        })
        for tab in removed {
            if case .sideChat(let state) = tab.payload,
               let sideThreadId = state.sideThreadId,
               !remainingSideChatIDs.contains(sideThreadId)
            {
                stopSideChatStore(sideThreadId: sideThreadId)
            }
        }
    }
}
