import Foundation
import SwftDesign
import SwftKit

extension AppModel {
    /// Whether the active environment can start a thread without a project.
    var canStartWithoutProject: Bool {
        let store = resolvedComposerStore(localStore: threadsStore)
        return NoProjectLogic.canStartWithoutProject(
            isMock: isMock,
            isConnected: isTargetEnvironmentConnected(localConnected: serverStatus.isConnected),
            scratchWorkspaceRoot: store?.availableScratchWorkspaceRoot
        )
    }

    /// Reason why starting without a project is unavailable, or `nil` when supported.
    var noProjectUnavailableReason: String? {
        let store = resolvedComposerStore(localStore: threadsStore)
        return NoProjectLogic.unavailableReason(
            isMock: isMock,
            serverStatus: serverStatus,
            environmentLabel: activeComposerEnvironment?.label ?? store?.environment?.label,
            scratchWorkspaceRoot: store?.availableScratchWorkspaceRoot
        )
    }

    /// Active server projects indexed by ID, excluding the hidden managed scratch project.
    var nonScratchProjectsByID: [String: ProjectShell] {
        guard let threadsStore else { return [:] }
        return NoProjectLogic.nonScratchProjectsByID(
            projects: threadsStore.projects,
            scratchWorkspaceRoot: threadsStore.serverConfig?.scratchWorkspaceRoot
        )
    }

    /// Clears the Home project selection so the next thread starts without a project.
    func clearProject() {
        guard canStartWithoutProject else {
            if let reason = noProjectUnavailableReason {
                actionError = reason
            }
            return
        }
        isNoProjectSelected = true
        selectedProjectID = nil
        isProjectPickerOpen = false
        actionError = nil
    }

    /// Context label for `ComposerState.contextLabel` (returns `nil` when project-less).
    func resolvedComposerContextLabel(mockDefaultContextLabel: String?) -> String? {
        let activeSummary = selectedThreadID.flatMap(threadSummary(for:))
        return NoProjectLogic.composerContextLabel(
            selectedThread: activeSummary,
            selectedProject: selectedProject,
            isMock: isMock,
            mockDefaultProjectID: isMock ? MockData.swft.id : nil,
            mockDefaultContextLabel: mockDefaultContextLabel
        )
    }

    /// Chip state rendered by `ComposerProjectSlot` on Home and inside active threads.
    func composerProjectChipState(contextLabel: String?) -> ComposerProjectChipState {
        let activeSummary = selectedThreadID.flatMap(threadSummary(for:))
        let hasValidProjects = projects.contains { !$0.isWorkspaceMissing }
        return NoProjectLogic.composerChipState(
            selectedThread: activeSummary,
            contextLabel: contextLabel,
            hasProjects: hasValidProjects,
            canStartWithoutProject: canStartWithoutProject,
            isConnected: isTargetEnvironmentConnected(localConnected: serverStatus.isConnected) || isMock,
            isNoProjectSelected: isNoProjectSelected
        )
    }

    func resolveHomeLaunchTarget() -> HomeLaunchResolution {
        let store = resolvedComposerStore(localStore: threadsStore)
        return NoProjectLogic.resolveHomeLaunch(
            selectedProject: selectedProject,
            isMock: isMock,
            serverStatus: serverStatus,
            environmentLabel: store?.environment?.label,
            scratchWorkspaceRoot: store?.availableScratchWorkspaceRoot
        )
    }

    func resolveLaunchProjectID(
        for target: HomeLaunchTarget,
        using store: ThreadsStore
    ) async throws -> String {
        try await NoProjectLogic.resolveLaunchProjectID(for: target) {
            try await store.ensureScratchProject().projectId
        }
    }

    func makeMockNoProjectThread(text: String, attachments: [TranscriptAttachment] = []) -> ThreadDetailState {
        let id = "mock-noproject-\(UUID().uuidString)"
        let summary = ThreadSummary(
            id: id,
            title: NoProjectLogic.initialThreadTitle(from: text.isEmpty ? (attachments.first?.name ?? "Attachment") : text),
            project: nil,
            location: .host("Local"),
            provider: selectedModel?.provider ?? .claude,
            providerDisplayName: selectedModel?.providerDisplayName,
            activity: .idle,
            updatedAt: now
        )
        return ThreadDetailState(
            summary: summary,
            items: [TranscriptItem(id: UUID().uuidString, kind: .user(text, attachments: attachments), startedAt: now)],
            diffStat: nil
        )
    }
}
