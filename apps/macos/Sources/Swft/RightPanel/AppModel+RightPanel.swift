import Foundation
import SwftDesign
import SwftKit
import SwiftUI

/// Multi-environment aware routing and data adapters for Swft's native Right Sidebar surfaces.
@MainActor
extension AppModel {
    var isRightPanelOpenForActiveThread: Bool {
        guard let threadID = selectedThreadID else { return false }
        return rightPanel.isOpen(for: threadID)
    }

    func toggleRightPanel() {
        guard let threadID = selectedThreadID else { return }
        // RootView animates open/close with `RightPanelMotion.panelLayout` honoring `effectiveReduceMotion`.
        rightPanel.togglePanel(for: threadID)
    }

    /// Opens a Side chat tab in the right panel from `/side` or `/btw`, optionally seeding its composer.
    func handleSideChatSlashCommand(prompt: String) {
        guard let threadID = selectedThreadID else { return }
        let tab = rightPanel.openSideChat(for: threadID)
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            rightPanel.pendingSideChatDrafts[tab.id] = trimmed
        }
    }

    /// Returns the `ServerConnection` owning `threadID` (supports both local and paired remote environments).
    func connection(forThreadID threadID: String) -> ServerConnection? {
        guard !isMock else { return nil }
        return owningEnvironment(forThreadID: threadID)?.connection ?? activeConnection
    }

    /// Returns the `ThreadsStore` owning `threadID` (supports both local and paired remote environments).
    func threadsStore(forThreadID threadID: String) -> ThreadsStore? {
        guard !isMock else { return nil }
        return owningEnvironment(forThreadID: threadID)?.threadsStore ?? activeThreadsStore
    }

    /// Returns the `ServerConnection` for an explicit environment ID, falling back to `fallbackThreadID`'s environment.
    func connection(forEnvironmentID environmentID: String?, fallbackThreadID: String? = nil) -> ServerConnection? {
        guard !isMock else { return nil }
        if let environmentID, let env = environmentRegistry.environment(id: environmentID) {
            return env.connection
        }
        if let fallbackThreadID {
            return connection(forThreadID: fallbackThreadID)
        }
        return activeConnection
    }

    /// Returns the `ThreadsStore` for an explicit environment ID, falling back to `fallbackThreadID`'s environment.
    func threadsStore(forEnvironmentID environmentID: String?, fallbackThreadID: String? = nil) -> ThreadsStore? {
        guard !isMock else { return nil }
        if let environmentID, let env = environmentRegistry.environment(id: environmentID) {
            return env.threadsStore
        }
        if let fallbackThreadID {
            return threadsStore(forThreadID: fallbackThreadID)
        }
        return activeThreadsStore
    }

    /// Whether the target environment (or owning environment of `fallbackThreadID`) is currently connected.
    func isEnvironmentConnected(environmentID: String?, fallbackThreadID: String? = nil) -> Bool {
        if isMock { return true }
        if let environmentID, let env = environmentRegistry.environment(id: environmentID) {
            return env.isConnected
        }
        if let fallbackThreadID, let env = owningEnvironment(forThreadID: fallbackThreadID) {
            return env.isConnected
        }
        return serverStatus.isConnected
    }

    /// Opens or activates a subagent child thread as a tab inside `parentThreadID`'s right sidebar
    /// without navigating the main chat view away from the parent thread.
    @discardableResult
    func openSubagentInRightPanel(
        _ target: SubagentNavigationTarget,
        item: SubagentItem? = nil,
        for parentThreadID: String? = nil
    ) -> RightPanelTab? {
        guard let resolvedParentID = parentThreadID ?? selectedThreadID else { return nil }
        let matchedItem = item ?? findSubagentItem(matching: target, inParentThreadID: resolvedParentID)
        let parentSummary = threadSummary(for: resolvedParentID)
        let parentEnvironmentID = parentSummary?.environmentID
            ?? owningEnvironment(forThreadID: resolvedParentID)?.id
            ?? activeThreadEnvironmentID
        let targetEnvironmentID = target.environmentID ?? parentEnvironmentID

        let resolvedTitle = [matchedItem?.title, target.title]
            .compactMap { $0?.nilIfBlank }
            .first ?? "Subagent"

        let resolvedStatus: SubagentStatus = {
            if let itemStatus = matchedItem?.status {
                return itemStatus
            }
            if isMock, let mockDetail = rightPanel.mockSubagentDetails[target.threadID] ?? detail(for: target.threadID) {
                return mockDetail.isRunning ? .running : .completed
            }
            if let existing = rightPanel.subagentTabState(
                subagentThreadId: target.threadID,
                environmentId: targetEnvironmentID,
                for: resolvedParentID
            ) {
                return existing.status
            }
            return .idle
        }()

        let childShell = threadShell(
            forThreadID: target.threadID,
            in: threadsStore(forEnvironmentID: targetEnvironmentID, fallbackThreadID: resolvedParentID)
        )
        let resolvedWorkspace = matchedItem?.workspaceLabel
            ?? childShell?.branch?.nilIfBlank
            ?? childShell?.worktreePath.flatMap { path in
                let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : (trimmed as NSString).lastPathComponent
            }

        let resolvedModel: String? = {
            if let modelName = matchedItem?.modelName?.nilIfBlank {
                return modelName
            }
            if let shell = childShell {
                let store = threadsStore(forEnvironmentID: targetEnvironmentID, fallbackThreadID: resolvedParentID)
                let provider = store?.provider(for: shell.modelSelection.instanceId)
                return SubagentDisplayLogic.resolveModelLabel(
                    reportedModel: nil,
                    executedModel: nil,
                    modelSelection: shell.modelSelection,
                    childModelSelection: nil,
                    provider: provider
                )
            }
            return nil
        }()

        let tabState = SubagentTabState(
            subagentThreadId: target.threadID,
            environmentId: targetEnvironmentID,
            title: resolvedTitle,
            status: resolvedStatus,
            modelLabel: resolvedModel,
            providerDisplayName: matchedItem?.providerDisplayName?.nilIfBlank
                ?? target.providerDisplayName?.nilIfBlank
                ?? target.provider.displayName,
            providerDriver: matchedItem?.providerDriver.nilIfBlank ?? target.providerDriver.nilIfBlank,
            providerInstanceId: matchedItem?.providerInstanceID.nilIfBlank ?? childShell?.providerInstanceId.nilIfBlank,
            providerIconUrl: matchedItem?.providerIconURL?.nilIfBlank ?? target.providerIconURL?.nilIfBlank,
            prompt: matchedItem?.prompt.nilIfBlank,
            workspaceLabel: resolvedWorkspace
        )

        return rightPanel.openSubagentTab(tabState, for: resolvedParentID)
    }

    private func findSubagentItem(
        matching target: SubagentNavigationTarget,
        inParentThreadID parentThreadID: String
    ) -> SubagentItem? {
        guard let detail = detail(for: parentThreadID) else { return nil }
        for item in detail.items {
            guard case .subagent(let subagent) = item.kind else { continue }
            if subagent.childThreadID == target.threadID || subagent.remoteThreadID == target.threadID {
                return subagent
            }
        }
        return nil
    }

    /// Resolves the workspace root directory (`worktreePath` preferred over non-scratch `project.workspaceRoot`)
    /// for the given thread on its owning environment.
    func workspaceRoot(forThreadID threadID: String) -> String? {
        if isMock {
            return threadSummary(for: threadID)?.project?.workspaceRoot?.nilIfBlank
        }

        let store = threadsStore(forThreadID: threadID)

        if let activeStore = activeThreadStore,
           activeStore.threadId == threadID,
           let thread = activeStore.thread
        {
            if let worktree = thread.worktreePath?.nilIfBlank {
                return worktree
            }
            if let project = store?.projectsByID[thread.projectId],
               store?.isScratchProject(project) != true,
               let root = project.workspaceRoot.nilIfBlank
            {
                return root
            }
        }

        if let shell = threadShell(forThreadID: threadID, in: store) {
            if let worktree = shell.worktreePath?.nilIfBlank {
                return worktree
            }
            if let project = store?.projectsByID[shell.projectId],
               store?.isScratchProject(project) != true,
               let root = project.workspaceRoot.nilIfBlank
            {
                return root
            }
        }

        return threadSummary(for: threadID)?.project?.workspaceRoot?.nilIfBlank
    }

    /// Linked pull requests for `threadID` (filters dismissed items and synthesizes fallback entries from
    /// legacy `linkedPullRequest` / `branchPullRequest` if not already in `pullRequests`).
    func linkedPullRequests(forThreadID threadID: String) -> [ThreadPullRequestLink] {
        if isMock {
            return rightPanel.mockLinkedPRsByThreadID[threadID] ?? RightPanelMockData.pullRequests
        }

        let activeThread: AppThread? = (activeThreadStore?.threadId == threadID) ? activeThreadStore?.thread : nil
        let shell = threadShell(forThreadID: threadID, in: threadsStore(forThreadID: threadID))

        let rawLinks: [ThreadPullRequestLink] = {
            if let activeThread, !activeThread.pullRequests.isEmpty {
                return activeThread.pullRequests
            }
            return shell?.pullRequests ?? []
        }()

        var visible = rawLinks.filter { !$0.isDismissed }
        var seenIDs = Set(visible.map(\.id))

        let legacyCandidates = [
            activeThread?.linkedPullRequest,
            activeThread?.branchPullRequest,
            shell?.linkedPullRequest,
            shell?.branchPullRequest,
        ].compactMap { $0 }

        for legacy in legacyCandidates {
            guard let synthesized = synthesizePullRequestLink(from: legacy) else { continue }
            if seenIDs.insert(synthesized.id).inserted {
                visible.append(synthesized)
            }
        }

        return visible
    }

    /// Linked tracker issues for `threadID`.
    func linkedIssues(forThreadID threadID: String) -> [ThreadIssueLink] {
        if isMock {
            return rightPanel.mockLinkedIssuesByThreadID[threadID] ?? RightPanelMockData.issues
        }

        if let activeThread = activeThreadStore?.thread,
           activeThread.id == threadID,
           !activeThread.issues.isEmpty
        {
            return activeThread.issues
        }
        return threadShell(forThreadID: threadID, in: threadsStore(forThreadID: threadID))?.issues ?? []
    }

    /// Related threads (parent, side chats, subagents, forks) for `threadID`, combining store shells,
    /// `orchestration.getThreadFamily` results, and projection items.
    func relatedThreads(
        forThreadID threadID: String,
        fetchedFamily: [ThreadShell]
    ) -> [LinkedThreadSummaryItem] {
        if isMock {
            return RightPanelMockData.relatedThreads(for: threadID)
        }

        let store = threadsStore(forThreadID: threadID)
        let currentShell = threadShell(forThreadID: threadID, in: store)
        let currentLineage = (activeThreadStore?.threadId == threadID ? activeThreadStore?.thread?.lineage : nil)
            ?? currentShell?.lineage
        let rootID = currentLineage?.rootThreadId ?? threadID
        let parentID = currentLineage?.parentThreadId

        var shellsByID: [String: ThreadShell] = [:]
        if let store {
            for candidate in store.threads where candidate.deletedAt == nil {
                if candidate.id == parentID
                    || candidate.lineage.parentThreadId == threadID
                    || candidate.lineage.rootThreadId == rootID
                {
                    shellsByID[candidate.id] = candidate
                }
            }
            for candidate in store.archivedThreads where candidate.deletedAt == nil {
                if candidate.id == parentID
                    || candidate.lineage.parentThreadId == threadID
                    || candidate.lineage.rootThreadId == rootID
                {
                    shellsByID[candidate.id] = shellsByID[candidate.id] ?? candidate
                }
            }
        }
        for candidate in fetchedFamily where candidate.deletedAt == nil {
            shellsByID[candidate.id] = candidate
        }
        shellsByID.removeValue(forKey: threadID)

        var itemsByID: [String: LinkedThreadSummaryItem] = [:]
        for shell in shellsByID.values {
            let relation = classifyThreadRelation(shell: shell, currentThreadID: threadID, parentThreadID: parentID)
            let status = SwftAdapters.threadActivity(from: shell, activelyViewingThreadID: selectedThreadID)
            itemsByID[shell.id] = LinkedThreadSummaryItem(
                id: shell.id,
                title: shell.title.nilIfBlank ?? "Untitled thread",
                relation: relation,
                status: status,
                updatedAt: shell.updatedAt
            )
        }

        // Supplement with projection-level subagents / forks / created threads that may not be in the shell list yet.
        if let activeStore = activeThreadStore,
           activeStore.threadId == threadID,
           let projection = activeStore.projection
        {
            for subagent in projection.subagents {
                guard let childID = subagent.childThreadId?.nilIfBlank,
                      childID != threadID,
                      itemsByID[childID] == nil
                else { continue }
                let status: ThreadActivity = switch subagent.status.lowercased() {
                case "running", "starting", "queued", "preparing": .running
                case "failed", "error": .failed
                default: .idle
                }
                itemsByID[childID] = LinkedThreadSummaryItem(
                    id: childID,
                    title: subagent.title?.nilIfBlank ?? subagent.prompt.nilIfBlank ?? "Subagent",
                    relation: .subagent,
                    status: status,
                    updatedAt: subagent.updatedAt
                )
            }

            for projected in projection.visibleTurnItems {
                let item = projected.item
                switch item.kind {
                case .fork(let targetThreadId) where targetThreadId != threadID && itemsByID[targetThreadId] == nil:
                    itemsByID[targetThreadId] = LinkedThreadSummaryItem(
                        id: targetThreadId,
                        title: item.title?.nilIfBlank ?? "Forked thread",
                        relation: .fork,
                        status: .idle,
                        updatedAt: item.updatedAt
                    )
                case .threadCreated(let targetThreadId, _, _, _) where targetThreadId != threadID && itemsByID[targetThreadId] == nil:
                    itemsByID[targetThreadId] = LinkedThreadSummaryItem(
                        id: targetThreadId,
                        title: item.title?.nilIfBlank ?? "Created thread",
                        relation: .linked,
                        status: .idle,
                        updatedAt: item.updatedAt
                    )
                default:
                    break
                }
            }
        }

        return itemsByID.values.sorted { lhs, rhs in
            if lhs.relation == .parent && rhs.relation != .parent { return true }
            if rhs.relation == .parent && lhs.relation != .parent { return false }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    /// Opens a side chat (or related thread) in the main thread canvas.
    func openSideChatInMainView(_ sideThreadID: String) {
        if isMock {
            let parentProject = selectedThreadID.flatMap { threadSummary(for: $0)?.project }
            let items = rightPanel.mockSideChatItems[sideThreadID] ?? RightPanelMockData.initialMockSideChatMessages()
            ensureMockThread(id: sideThreadID, title: "Side chat", project: parentProject, items: items)
            open(sideThreadID)
            return
        }
        open(sideThreadID)
    }

    // MARK: - Private Helpers

    private func threadShell(forThreadID threadID: String, in store: ThreadsStore?) -> ThreadShell? {
        guard let store else { return nil }
        return store.threads.first(where: { $0.id == threadID })
            ?? store.archivedThreads.first(where: { $0.id == threadID })
    }

    private func classifyThreadRelation(
        shell: ThreadShell,
        currentThreadID: String,
        parentThreadID: String?
    ) -> LinkedThreadSummaryItem.Relation {
        if shell.id == parentThreadID {
            return .parent
        }
        if shell.lineage.sideChat == true {
            return .sideChat
        }
        if shell.lineage.relationshipToParent == "subagent" {
            return .subagent
        }
        if shell.lineage.parentThreadId == currentThreadID {
            return .fork
        }
        return .linked
    }

    private func synthesizePullRequestLink(from legacy: ThreadLinkedPullRequest) -> ThreadPullRequestLink? {
        if let parsed = RightPanelLogic.parsePullRequestURL(legacy.url) {
            return ThreadPullRequestLink(
                host: parsed.host,
                repository: legacy.repository.nilIfBlank ?? parsed.repository,
                number: legacy.number,
                url: legacy.url,
                source: "branch",
                linkedAt: now
            )
        }
        guard let repo = legacy.repository.nilIfBlank else { return nil }
        let host = URL(string: legacy.url)?.host ?? "github.com"
        return ThreadPullRequestLink(
            host: host,
            repository: repo,
            number: legacy.number,
            url: legacy.url,
            source: "branch",
            linkedAt: now
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
