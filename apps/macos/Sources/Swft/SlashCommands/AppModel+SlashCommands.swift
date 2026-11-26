import Foundation
import SwftKit

/// Slash command catalog, keyboard navigation, fresh-session arming, and workspace snapshot refresh for `AppModel`.
@MainActor
extension AppModel {

    // MARK: - Active Provider & Workspace Resolution

    /// Active server store backing the composer (active thread's owning environment, or Home's selected environment).
    var activeSlashCommandStore: ThreadsStore? {
        guard !isMock else { return nil }
        return resolvedActiveStore(localStore: threadsStore)
    }

    /// Active `ServerProvider` for the currently selected composer model (works for both local and remote environments).
    var activeSlashCommandProvider: ServerProvider? {
        guard let store = activeSlashCommandStore else { return nil }
        if let instanceId = selectedModel?.instanceId,
           let provider = store.provider(for: instanceId)
        {
            return provider
        }
        if let threadProviderId = activeThreadStore?.thread?.providerInstanceId,
           let provider = store.provider(for: threadProviderId)
        {
            return provider
        }
        return store.providers.first { $0.enabled && $0.installed && $0.status != .disabled }
            ?? store.providers.first
    }

    /// Active workspace directory for workspace-scoped slash commands & skills.
    var activeSlashCommandWorkspaceCwd: String? {
        if let threadID = selectedThreadID {
            if let worktree = activeThreadStore?.thread?.worktreePath, !worktree.isEmpty {
                return worktree
            }
            if let store = activeSlashCommandStore,
               let projectId = activeThreadStore?.thread?.projectId
                   ?? store.threads.first(where: { $0.id == threadID })?.projectId,
               let project = store.projectsByID[projectId],
               !project.workspaceRoot.isEmpty
            {
                return project.workspaceRoot
            }
            return threadSummary(for: threadID)?.project?.workspaceRoot
        }
        return selectedProject?.workspaceRoot
    }

    var activeSlashCommandProviderLabel: String {
        if let provider = activeSlashCommandProvider {
            return provider.label
        }
        return selectedModel?.providerDisplayName ?? "Provider"
    }

    var activeSlashCommandProviderDriver: String {
        if let provider = activeSlashCommandProvider {
            return provider.driver
        }
        return selectedModel?.provider.rawValue ?? "provider"
    }

    /// Whether `/clear` arms a fresh context on the active thread instead of resetting the Home draft.
    var supportsFreshSessionInActiveContext: Bool {
        guard selectedThreadID != nil else { return false }
        if isMock { return true }
        let store = activeSlashCommandStore
        return store?.environment?.capabilities.freshContext == true
            || store?.serverConfig?.environment.capabilities.freshContext == true
    }

    var isFreshSessionArmedForActiveThread: Bool {
        guard let threadID = selectedThreadID else { return false }
        return freshSessionThreadIDs.contains(threadID)
    }

    func armFreshSessionForActiveThread() {
        guard let threadID = selectedThreadID else { return }
        freshSessionThreadIDs.insert(threadID)
    }

    func disarmFreshSessionForActiveThread() {
        guard let threadID = selectedThreadID else { return }
        freshSessionThreadIDs.remove(threadID)
    }

    // MARK: - Trigger & Menu State

    /// Active `/` trigger at the current composer caret, or `nil` if none or dismissed for this token.
    var activeSlashCommandTrigger: SlashCommandTrigger? {
        guard modelPicker == nil, !isProjectPickerOpen else { return nil }
        guard let candidate = SlashCommandLogic.detectTrigger(in: composerText, cursorUTF16: composerCursorUTF16) else {
            return nil
        }
        if let dismissedStart = dismissedSlashTriggerStart, dismissedStart == candidate.rangeStart {
            return nil
        }
        return candidate
    }

    /// Provider slash commands currently available for the active composer environment & provider.
    var activeProviderSlashCommands: [ServerProviderSlashCommand] {
        if isMock {
            let envID = selectedThreadID.flatMap { threadSummary(for: $0)?.environmentID } ?? activeComposerEnvironmentID
            if let envID, let envOverride = mockSlashCommandsByEnvironment[envID] {
                return envOverride
            }
            if let instanceId = selectedModel?.instanceId,
               let providerOverride = mockSlashCommandsByProvider[instanceId]
            {
                return providerOverride
            }
            return MockData.slashCommands(forInstanceId: selectedModel?.instanceId)
        }
        guard let provider = activeSlashCommandProvider else { return [] }
        return provider.resolvedSlashCommands(for: activeSlashCommandWorkspaceCwd)
    }

    /// Provider skills currently available for the active composer environment & provider.
    var activeProviderSkills: [ServerProviderSkill] {
        if isMock {
            if let instanceId = selectedModel?.instanceId,
               let override = mockSkillsByProvider[instanceId]
            {
                return override
            }
            return MockData.skills(forInstanceId: selectedModel?.instanceId)
        }
        guard let provider = activeSlashCommandProvider else { return [] }
        return provider.resolvedSkills(for: activeSlashCommandWorkspaceCwd)
    }

    var slashCommandItems: [SlashCommandItem] {
        guard let trigger = activeSlashCommandTrigger else { return [] }
        let supportsPlanToggle = isMock ? false : (activeSlashCommandProvider?.showInteractionModeToggle == true)
        let catalog = SlashCommandLogic.catalog(
            providerCommands: activeProviderSlashCommands,
            providerSkills: activeProviderSkills,
            providerLabel: activeSlashCommandProviderLabel,
            providerDriver: activeSlashCommandProviderDriver,
            isAtPromptStart: trigger.isAtPromptStart,
            supportsFreshSession: supportsFreshSessionInActiveContext,
            supportsSideChat: selectedThreadID != nil && onSideChatCommand != nil,
            supportsPlanModeToggle: supportsPlanToggle,
            currentInteractionMode: activeInteractionMode
        )
        return SlashCommandLogic.filterAndRank(catalog, query: trigger.query)
    }

    var slashCommandSections: [SlashCommandSection] {
        guard let trigger = activeSlashCommandTrigger else { return [] }
        return SlashCommandLogic.sections(
            for: slashCommandItems,
            query: trigger.query,
            providerLabel: activeSlashCommandProviderLabel
        )
    }

    /// True when the floating slash-command menu should be displayed.
    var isSlashCommandMenuOpen: Bool {
        guard let trigger = activeSlashCommandTrigger else { return false }
        // At prompt start, stay open even with 0 matches so the user sees "No matching command."
        // Mid-prompt, hide when nothing matches so prose slashes never pop up an empty box.
        return trigger.isAtPromptStart || !slashCommandItems.isEmpty
    }

    var highlightedSlashCommandID: String? {
        SlashCommandLogic.resolveHighlightedID(current: slashCommandHighlightedID, in: slashCommandItems)
    }

    var activeInteractionMode: ProviderInteractionMode {
        if !isMock, let threadMode = activeThreadStore?.thread?.interactionMode {
            return threadMode
        }
        return composerInteractionMode
    }

    // MARK: - Composer Cursor & Dismissal Sync

    func updateComposerCursor(utf16Offset: Int) {
        let clamped = max(0, min(composerText.utf16.count, utf16Offset))
        if composerCursorUTF16 != clamped {
            composerCursorUTF16 = clamped
        }
        syncSlashTriggerDismissal()
    }

    func syncSlashTriggerDismissal() {
        let candidate = SlashCommandLogic.detectTrigger(in: composerText, cursorUTF16: composerCursorUTF16)
        if let dismissedStart = dismissedSlashTriggerStart {
            if candidate == nil || candidate?.rangeStart != dismissedStart {
                dismissedSlashTriggerStart = nil
            }
        }
        if candidate != nil && dismissedSlashTriggerStart == nil && modelPicker == nil && !isProjectPickerOpen {
            refreshActiveWorkspaceSnapshotIfNeeded()
        }
    }

    func dismissSlashCommandMenu() {
        if let candidate = SlashCommandLogic.detectTrigger(in: composerText, cursorUTF16: composerCursorUTF16) {
            dismissedSlashTriggerStart = candidate.rangeStart
        }
        slashCommandHighlightedID = nil
    }

    func resetSlashCommandMenuState() {
        dismissedSlashTriggerStart = nil
        slashCommandHighlightedID = nil
    }

    // MARK: - Keyboard Handling & Execution

    /// Routes a key press to the open slash-command menu. Returns `true` when consumed.
    @discardableResult
    func handleSlashCommandKey(_ key: SlashCommandKey) -> Bool {
        guard isSlashCommandMenuOpen else { return false }
        let items = slashCommandItems

        switch key {
        case .escape:
            dismissSlashCommandMenu()
            return true

        case .up:
            guard !items.isEmpty else { return false }
            slashCommandHighlightedID = SlashCommandLogic.stepHighlight(
                current: highlightedSlashCommandID,
                direction: -1,
                in: items
            )
            return true

        case .down:
            guard !items.isEmpty else { return false }
            slashCommandHighlightedID = SlashCommandLogic.stepHighlight(
                current: highlightedSlashCommandID,
                direction: 1,
                in: items
            )
            return true

        case .tab:
            guard let targetID = highlightedSlashCommandID,
                  let item = items.first(where: { $0.id == targetID })
            else { return false }
            selectSlashCommand(item)
            return true

        case .enter:
            guard let targetID = highlightedSlashCommandID,
                  let item = items.first(where: { $0.id == targetID })
            else { return false }
            selectSlashCommand(item)
            return true
        }
    }

    func selectSlashCommand(_ item: SlashCommandItem) {
        guard let trigger = activeSlashCommandTrigger
            ?? SlashCommandLogic.detectTrigger(in: composerText, cursorUTF16: composerCursorUTF16)
        else { return }

        let action = SlashCommandLogic.selectionAction(
            for: item,
            trigger: trigger,
            prompt: composerText,
            supportsFreshSession: supportsFreshSessionInActiveContext
        )

        slashCommandHighlightedID = nil
        dismissedSlashTriggerStart = nil

        switch action {
        case .openModelPicker(let updatedPrompt, let cursorUTF16):
            applyComposerReplacement(text: updatedPrompt, cursorUTF16: cursorUTF16)
            if modelPicker == nil {
                toggleModelPicker()
            }

        case .armFreshSession(let updatedPrompt, let cursorUTF16):
            applyComposerReplacement(text: updatedPrompt, cursorUTF16: cursorUTF16)
            armFreshSessionForActiveThread()

        case .clearDraftOrStartNewThread(let updatedPrompt, let cursorUTF16):
            applyComposerReplacement(text: updatedPrompt, cursorUTF16: cursorUTF16)
            if selectedThreadID != nil {
                goHome()
            } else {
                composerText = ""
                composerCursorUTF16 = 0
                composerAttachments.clear()
            }

        case .setInteractionMode(let mode, let updatedPrompt, let cursorUTF16):
            applyComposerReplacement(text: updatedPrompt, cursorUTF16: cursorUTF16)
            setComposerInteractionMode(mode)

        case .replacePrompt(let text, let cursorUTF16):
            applyComposerReplacement(text: text, cursorUTF16: cursorUTF16)
        }
    }

    /// Handles verbatim built-in commands submitted directly (e.g. clicking Send or Cmd+Return on `/clear` or `/model`).
    /// Returns `true` if the command was handled locally and should not be sent as a chat message.
    func interceptBuiltInSlashSubmission(trimmedText: String) -> Bool {
        guard composerAttachments.ready.isEmpty else { return false }

        if SlashCommandLogic.isModelCommand(trimmedText) {
            applyComposerReplacement(text: "", cursorUTF16: 0)
            if modelPicker == nil {
                toggleModelPicker()
            }
            return true
        }

        if SlashCommandLogic.isClearCommand(trimmedText) {
            applyComposerReplacement(text: "", cursorUTF16: 0)
            if supportsFreshSessionInActiveContext {
                armFreshSessionForActiveThread()
            } else if selectedThreadID != nil {
                goHome()
            } else {
                composerAttachments.clear()
            }
            return true
        }

        if let sideChatPrompt = SlashCommandLogic.parseSideChatCommand(trimmedText),
           let handler = onSideChatCommand
        {
            applyComposerReplacement(text: "", cursorUTF16: 0)
            handler(sideChatPrompt)
            return true
        }

        let providerHasPlan = activeProviderSlashCommands.contains {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "plan"
        }
        if !providerHasPlan,
           activeSlashCommandProvider?.showInteractionModeToggle == true,
           let mode = SlashCommandLogic.parseInteractionModeCommand(trimmedText)
        {
            applyComposerReplacement(text: "", cursorUTF16: 0)
            setComposerInteractionMode(mode)
            return true
        }

        return false
    }

    func setComposerInteractionMode(_ mode: ProviderInteractionMode) {
        composerInteractionMode = mode
        guard !isMock, let threadStore = activeThreadStore else { return }
        Task {
            do {
                try await threadStore.setInteractionMode(mode)
            } catch {
                self.actionError = error.localizedDescription
            }
        }
    }

    private func applyComposerReplacement(text: String, cursorUTF16: Int) {
        let clamped = max(0, min(text.utf16.count, cursorUTF16))
        isApplyingProgrammaticComposerEdit = true
        composerText = text
        composerCursorUTF16 = clamped
        isApplyingProgrammaticComposerEdit = false
        pendingComposerCursorUTF16 = clamped
        composerCursorRequestID &+= 1
        syncSlashTriggerDismissal()
    }

    // MARK: - Live Workspace Snapshot Refresh

    func refreshActiveWorkspaceSnapshotIfNeeded() {
        guard !isMock,
              let store = activeSlashCommandStore,
              store.connectionState.isConnected,
              let provider = activeSlashCommandProvider,
              let cwd = activeSlashCommandWorkspaceCwd,
              !cwd.isEmpty
        else { return }

        let envID = store.environment?.environmentId ?? "local"
        let key = "\(envID)::\(provider.instanceId)::\(cwd)"
        let currentNow = Date()
        guard SlashCommandLogic.shouldRefreshWorkspaceSnapshot(
            provider: provider,
            cwd: cwd,
            lastRequestedAt: workspaceSnapshotRequests[key],
            now: currentNow
        ) else { return }

        workspaceSnapshotRequests[key] = currentNow
        let instanceId = provider.instanceId
        Task { [weak store] in
            _ = try? await store?.refreshWorkspaceSnapshot(instanceId: instanceId, cwd: cwd, fresh: false)
        }
    }
}
