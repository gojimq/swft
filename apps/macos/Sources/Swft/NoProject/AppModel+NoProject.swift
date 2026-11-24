import Foundation
import SwftDesign
import SwftKit

extension AppModel {
    /// Whether the active environment can start a thread without a project.
    var canStartWithoutProject: Bool {
        NoProjectLogic.canStartWithoutProject(
            isMock: isMock,
            isConnected: serverStatus.isConnected,
            scratchWorkspaceRoot: threadsStore?.availableScratchWorkspaceRoot
        )
    }

    /// Reason why starting without a project is unavailable, or `nil` when supported.
    var noProjectUnavailableReason: String? {
        NoProjectLogic.unavailableReason(
            isMock: isMock,
            serverStatus: serverStatus,
            environmentLabel: threadsStore?.environment?.label,
            scratchWorkspaceRoot: threadsStore?.availableScratchWorkspaceRoot
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
        return NoProjectLogic.composerChipState(
            selectedThread: activeSummary,
            contextLabel: contextLabel,
            hasProjects: !projects.isEmpty,
            canStartWithoutProject: canStartWithoutProject,
            isConnected: serverStatus.isConnected || isMock,
            isNoProjectSelected: isNoProjectSelected
        )
    }

    func resolveHomeLaunchTarget() -> HomeLaunchResolution {
        NoProjectLogic.resolveHomeLaunch(
            selectedProject: selectedProject,
            isMock: isMock,
            serverStatus: serverStatus,
            environmentLabel: threadsStore?.environment?.label,
            scratchWorkspaceRoot: threadsStore?.availableScratchWorkspaceRoot
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

    func makeMockNoProjectThread(text: String) -> ThreadDetailState {
        let id = "mock-noproject-\(UUID().uuidString)"
        let summary = ThreadSummary(
            id: id,
            title: NoProjectLogic.initialThreadTitle(from: text),
            project: nil,
            location: .host("Local"),
            provider: selectedModel?.provider ?? .claude,
            providerDisplayName: selectedModel?.providerDisplayName,
            activity: .idle,
            updatedAt: now
        )
        return ThreadDetailState(
            summary: summary,
            items: [TranscriptItem(id: UUID().uuidString, kind: .user(text), startedAt: now)],
            diffStat: nil
        )
    }
}
