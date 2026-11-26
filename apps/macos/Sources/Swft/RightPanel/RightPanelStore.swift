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
    /// Live `ThreadStore` instances for active subagent tabs (keyed by subagent thread ID).
    private(set) var subagentStores: [String: ThreadStore] = [:]
    /// Optimistic user messages sent in a side chat before server echo.
    var pendingSideChatMessages: [String: [PendingUserMessage]] = [:]
    /// Optimistic user messages sent to a subagent tab before server echo.
    var pendingSubagentMessages: [String: [PendingUserMessage]] = [:]
    /// Optimistic approval resolutions inside a subagent tab before server echo.
    var optimisticSubagentApprovals: [String: [String: ApprovalItem.Status]] = [:]
    /// Pending draft prompt seeded into a side-chat tab (e.g. from `/side <prompt>`).
    var pendingSideChatDrafts: [String: String] = [:]

    func takePendingSideChatDraft(forTabID tabID: String) -> String? {
        pendingSideChatDrafts.removeValue(forKey: tabID)
    }
    /// Mock-mode transcripts keyed by side-chat tab/thread ID.
    var mockSideChatItems: [String: [TranscriptItem]] = [:]
    /// Mock-mode detail overrides keyed by subagent thread ID (for interactive follow-ups and approvals).
    var mockSubagentDetails: [String: ThreadDetailState] = [:]
    /// Mock-mode linked PR/issue overrides keyed by thread ID so unlinking/linking updates immediately in mock mode.
    var mockLinkedPRsByThreadID: [String: [ThreadPullRequestLink]] = [:]
    var mockLinkedIssuesByThreadID: [String: [ThreadIssueLink]] = [:]

    /// Mounted `SubagentSurfaceView` tab IDs holding an active subscription per subagent thread ID.
    @ObservationIgnored private var activeSubagentHolders: [String: Set<String>] = [:]
    /// Recently detached/closed subagent projections so switching tabs back renders immediately.
    @ObservationIgnored private var recentSubagentProjections = RecentProjections()

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

    @discardableResult
    func openSubagentTab(
        _ state: SubagentTabState,
        for parentThreadID: String
    ) -> RightPanelTab {
        var current = self.state(for: parentThreadID)
        current.isOpen = true

        if let existingIndex = current.tabs.firstIndex(where: { tab in
            if case .subagent(let existing) = tab.payload {
                return existing.subagentThreadId == state.subagentThreadId
                    && existing.environmentId == state.environmentId
            }
            return false
        }) {
            if case .subagent(let existing) = current.tabs[existingIndex].payload {
                let merged = Self.mergedSubagentState(existing: existing, incoming: state)
                current.tabs[existingIndex].payload = .subagent(merged)
            }
            current.activeTabID = current.tabs[existingIndex].id
            byThreadID[parentThreadID] = current
            return current.tabs[existingIndex]
        }

        let envKey = state.environmentId ?? "local"
        let tab = RightPanelTab(
            id: "subagent:\(envKey):\(state.subagentThreadId)",
            payload: .subagent(state)
        )
        if current.tabs.count == 1 && current.tabs[0].payload == .launcher {
            current.tabs[0] = tab
        } else {
            current.tabs.append(tab)
        }
        current.activeTabID = tab.id
        byThreadID[parentThreadID] = current
        return tab
    }

    func subagentTabState(
        subagentThreadId: String,
        environmentId: String?,
        for parentThreadID: String
    ) -> SubagentTabState? {
        for tab in tabs(for: parentThreadID) {
            if case .subagent(let state) = tab.payload,
               state.subagentThreadId == subagentThreadId,
               state.environmentId == environmentId
            {
                return state
            }
        }
        return nil
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

    func updateSubagentTab(
        tabID: String,
        title: String? = nil,
        status: SubagentStatus? = nil,
        modelLabel: String? = nil,
        workspaceLabel: String? = nil,
        for parentThreadID: String
    ) {
        guard var current = byThreadID[parentThreadID],
              let index = current.tabs.firstIndex(where: { $0.id == tabID }),
              case .subagent(var subagent) = current.tabs[index].payload
        else { return }

        let previous = subagent
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            subagent.title = title
        }
        if let status {
            subagent.status = status
        }
        if let modelLabel = modelLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !modelLabel.isEmpty {
            subagent.modelLabel = modelLabel
        }
        if let workspaceLabel = workspaceLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !workspaceLabel.isEmpty {
            subagent.workspaceLabel = workspaceLabel
        }

        guard subagent != previous else { return }
        current.tabs[index].payload = .subagent(subagent)
        byThreadID[parentThreadID] = current
    }

    /// Refreshes open `.subagent` tabs on `parentThreadID` whenever the parent thread's inline subagents update.
    func syncSubagentTabs(
        from subagents: [SubagentItem],
        parentEnvironmentID: String?,
        for parentThreadID: String
    ) {
        guard var current = byThreadID[parentThreadID], !subagents.isEmpty else { return }
        let hasSubagentTab = current.tabs.contains {
            if case .subagent = $0.payload { return true }
            return false
        }
        guard hasSubagentTab else { return }

        struct Key: Hashable {
            let threadID: String
            let environmentID: String?
        }

        var itemsByKey: [Key: SubagentItem] = [:]
        var itemsByThreadID: [String: SubagentItem] = [:]
        for item in subagents {
            if let childID = item.childThreadID?.trimmingCharacters(in: .whitespacesAndNewlines), !childID.isEmpty {
                itemsByKey[Key(threadID: childID, environmentID: parentEnvironmentID)] = item
                itemsByThreadID[childID] = item
            }
            if let remoteID = item.remoteThreadID?.trimmingCharacters(in: .whitespacesAndNewlines), !remoteID.isEmpty {
                let remoteEnv = item.remoteEnvironmentID?.trimmingCharacters(in: .whitespacesAndNewlines)
                itemsByKey[Key(threadID: remoteID, environmentID: remoteEnv)] = item
                itemsByThreadID[remoteID] = itemsByThreadID[remoteID] ?? item
            }
        }

        var changed = false
        for index in current.tabs.indices {
            guard case .subagent(var tabState) = current.tabs[index].payload else { continue }
            let matched = itemsByKey[Key(threadID: tabState.subagentThreadId, environmentID: tabState.environmentId)]
                ?? itemsByThreadID[tabState.subagentThreadId]
            guard let item = matched else { continue }

            let previous = tabState
            let trimmedTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTitle.isEmpty {
                tabState.title = trimmedTitle
            }
            if subagentStores[tabState.subagentThreadId]?.isRunning != true {
                tabState.status = item.status
            }
            if let modelName = item.modelName, !modelName.isEmpty {
                tabState.modelLabel = modelName
            }
            if let providerName = item.providerDisplayName, !providerName.isEmpty {
                tabState.providerDisplayName = providerName
            }
            if !item.providerDriver.isEmpty {
                tabState.providerDriver = item.providerDriver
            }
            if !item.providerInstanceID.isEmpty {
                tabState.providerInstanceId = item.providerInstanceID
            }
            if let iconURL = item.providerIconURL, !iconURL.isEmpty {
                tabState.providerIconUrl = iconURL
            }
            let trimmedPrompt = item.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedPrompt.isEmpty {
                tabState.prompt = trimmedPrompt
            }
            if let workspace = item.workspaceLabel, !workspace.isEmpty {
                tabState.workspaceLabel = workspace
            }

            if tabState != previous {
                current.tabs[index].payload = .subagent(tabState)
                changed = true
            }
        }

        if changed {
            byThreadID[parentThreadID] = current
        }
    }

    // MARK: - Side Chat & Subagent ThreadStore Lifecycle

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

    func cachedSubagentProjection(for subagentThreadId: String) -> ThreadProjection? {
        subagentStores[subagentThreadId]?.projection
            ?? recentSubagentProjections.projection(for: subagentThreadId)
    }

    @discardableResult
    func ensureSubagentStore(
        subagentThreadId: String,
        connection: ServerConnection,
        initialProjection: ThreadProjection? = nil,
        holderTabID: String? = nil
    ) -> ThreadStore {
        if let holderTabID {
            activeSubagentHolders[subagentThreadId, default: []].insert(holderTabID)
        }
        if let existing = subagentStores[subagentThreadId], existing.connection === connection {
            return existing
        }
        if let previous = subagentStores[subagentThreadId] {
            recentSubagentProjections.remember(previous.projection)
            previous.stop()
        }
        let seed = initialProjection ?? recentSubagentProjections.projection(for: subagentThreadId)
        let store = ThreadStore(
            connection: connection,
            threadId: subagentThreadId,
            initialProjection: seed
        )
        subagentStores[subagentThreadId] = store
        store.start()
        return store
    }

    /// Detaches a mounted `SubagentSurfaceView` holder when switching tabs or hiding the panel,
    /// stopping the underlying `ThreadStore` subscription once no active view holds it while caching its projection.
    func releaseSubagentStore(subagentThreadId: String, holderTabID: String) {
        activeSubagentHolders[subagentThreadId]?.remove(holderTabID)
        if activeSubagentHolders[subagentThreadId]?.isEmpty != false {
            activeSubagentHolders.removeValue(forKey: subagentThreadId)
            if let store = subagentStores.removeValue(forKey: subagentThreadId) {
                recentSubagentProjections.remember(store.projection)
                store.stop()
            }
        }
    }

    func stopSubagentStore(subagentThreadId: String) {
        activeSubagentHolders.removeValue(forKey: subagentThreadId)
        if let store = subagentStores.removeValue(forKey: subagentThreadId) {
            recentSubagentProjections.remember(store.projection)
            store.stop()
        }
        pendingSubagentMessages.removeValue(forKey: subagentThreadId)
        optimisticSubagentApprovals.removeValue(forKey: subagentThreadId)
    }

    func shutdown() {
        for store in sideChatStores.values {
            store.stop()
        }
        sideChatStores.removeAll()
        pendingSideChatMessages.removeAll()

        for store in subagentStores.values {
            store.stop()
        }
        subagentStores.removeAll()
        activeSubagentHolders.removeAll()
        pendingSubagentMessages.removeAll()
        optimisticSubagentApprovals.removeAll()
        recentSubagentProjections = RecentProjections()
    }

    // MARK: - Private Helpers

    private static func mergedSubagentState(
        existing: SubagentTabState,
        incoming: SubagentTabState
    ) -> SubagentTabState {
        let trimmedTitle = incoming.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return SubagentTabState(
            subagentThreadId: existing.subagentThreadId,
            environmentId: existing.environmentId,
            title: trimmedTitle.isEmpty ? existing.title : trimmedTitle,
            status: incoming.status,
            modelLabel: incoming.modelLabel ?? existing.modelLabel,
            providerDisplayName: incoming.providerDisplayName ?? existing.providerDisplayName,
            providerDriver: incoming.providerDriver ?? existing.providerDriver,
            providerInstanceId: incoming.providerInstanceId ?? existing.providerInstanceId,
            providerIconUrl: incoming.providerIconUrl ?? existing.providerIconUrl,
            prompt: incoming.prompt ?? existing.prompt,
            workspaceLabel: incoming.workspaceLabel ?? existing.workspaceLabel
        )
    }

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
        let remainingSubagentIDs: Set<String> = Set(remainingTabs.compactMap { tab in
            if case .subagent(let state) = tab.payload { return state.subagentThreadId }
            return nil
        })
        for tab in removed {
            switch tab.payload {
            case .sideChat(let state):
                if let sideThreadId = state.sideThreadId,
                   !remainingSideChatIDs.contains(sideThreadId)
                {
                    stopSideChatStore(sideThreadId: sideThreadId)
                }
            case .subagent(let state):
                activeSubagentHolders[state.subagentThreadId]?.remove(tab.id)
                if !remainingSubagentIDs.contains(state.subagentThreadId) {
                    stopSubagentStore(subagentThreadId: state.subagentThreadId)
                }
            default:
                break
            }
        }
    }
}
