import Foundation
import SwftDesign
import SwftKit

/// Launch target resolved from Home composer state before creating a new thread.
enum HomeLaunchTarget: Equatable, Sendable {
    case project(id: String)
    case noProject
}

/// Whether Home can launch a new thread now, or why it cannot.
enum HomeLaunchResolution: Equatable, Sendable {
    case ready(HomeLaunchTarget)
    case unavailable(reason: String)
}

/// Pure selection, display, and launch logic for project-less ("No project") threads.
enum NoProjectLogic {
    static let noProjectLabel = "No project"
    static let noProjectMenuTag = "__swft_no_project__"

    /// Resolves which real project is selected on Home.
    /// Returns `nil` when the user explicitly cleared the project or no valid local/remote projects exist.
    static func resolveSelectedProject(
        projects: [ProjectRef],
        selectedProjectID: String?,
        isNoProjectSelected: Bool
    ) -> ProjectRef? {
        if isNoProjectSelected { return nil }
        if let selectedProjectID,
           let match = projects.first(where: { $0.id == selectedProjectID }),
           !match.isWorkspaceMissing
        {
            return match
        }
        return projects.first(where: { !$0.isWorkspaceMissing })
    }

    /// Whether a thread has no real project attached (live scratch thread or mock no-project placeholder).
    static func isProjectless(_ summary: ThreadSummary) -> Bool {
        guard let project = summary.project else { return true }
        return project.initials == nil
    }

    /// Whether the current environment can create threads without a project.
    static func canStartWithoutProject(
        isMock: Bool,
        isConnected: Bool,
        scratchWorkspaceRoot: String?
    ) -> Bool {
        if isMock { return true }
        guard isConnected else { return false }
        guard let root = scratchWorkspaceRoot?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !root.isEmpty
    }

    /// Human-readable explanation when starting without a project is unavailable, or `nil` when available.
    static func unavailableReason(
        isMock: Bool,
        serverStatus: ServerStatus,
        environmentLabel: String?,
        scratchWorkspaceRoot: String?
    ) -> String? {
        if canStartWithoutProject(
            isMock: isMock,
            isConnected: serverStatus.isConnected,
            scratchWorkspaceRoot: scratchWorkspaceRoot
        ) {
            return nil
        }
        let label = environmentLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = (label?.isEmpty == false) ? label! : "the local server"
        switch serverStatus {
        case .starting, .connecting, .reconnecting:
            return "Wait for \(host) to connect to start without a project."
        case .failed:
            return "Connect to \(host) to start without a project."
        case .connected:
            return "\(host) does not support starting without a project."
        }
    }

    /// Decides whether Home `send()` launches inside a real project, in the server's scratch project, or fails.
    static func resolveHomeLaunch(
        selectedProject: ProjectRef?,
        isMock: Bool,
        serverStatus: ServerStatus,
        environmentLabel: String?,
        scratchWorkspaceRoot: String?
    ) -> HomeLaunchResolution {
        if let selectedProject {
            return .ready(.project(id: selectedProject.id))
        }
        if canStartWithoutProject(
            isMock: isMock,
            isConnected: serverStatus.isConnected,
            scratchWorkspaceRoot: scratchWorkspaceRoot
        ) {
            return .ready(.noProject)
        }
        let reason = unavailableReason(
            isMock: isMock,
            serverStatus: serverStatus,
            environmentLabel: environmentLabel,
            scratchWorkspaceRoot: scratchWorkspaceRoot
        ) ?? "Select or add a project first to start a thread."
        return .unavailable(reason: reason)
    }

    /// Resolves the wire `projectId` for `orchestration.launchThread`, ensuring the scratch project only when needed.
    static func resolveLaunchProjectID(
        for target: HomeLaunchTarget,
        isolation: isolated (any Actor)? = #isolation,
        ensureScratch: () async throws -> String
    ) async throws -> String {
        switch target {
        case .project(let id):
            return id
        case .noProject:
            return try await ensureScratch()
        }
    }

    /// Context label for `ComposerState.contextLabel` (`nil` when project-less).
    static func composerContextLabel(
        selectedThread: ThreadSummary?,
        selectedProject: ProjectRef?,
        isMock: Bool,
        mockDefaultProjectID: String? = nil,
        mockDefaultContextLabel: String? = nil
    ) -> String? {
        if let selectedThread {
            guard !isProjectless(selectedThread), let projectName = selectedThread.project?.name else {
                return nil
            }
            if case .branch(let branch) = selectedThread.location {
                return "\(projectName) · \(branch)"
            }
            return projectName
        }

        guard let selectedProject else { return nil }
        if isMock,
           let mockDefaultContextLabel,
           mockDefaultProjectID == nil || selectedProject.id == mockDefaultProjectID
        {
            return mockDefaultContextLabel
        }
        return selectedProject.name
    }

    /// Visual state for `ComposerProjectChip` on Home or inside a thread.
    static func composerChipState(
        selectedThread: ThreadSummary?,
        contextLabel: String?,
        hasProjects: Bool,
        canStartWithoutProject: Bool,
        isConnected: Bool,
        isNoProjectSelected: Bool
    ) -> ComposerProjectChipState {
        if let contextLabel {
            return .project(contextLabel)
        }
        if selectedThread != nil {
            return .noProject(noProjectLabel)
        }
        if !canStartWithoutProject && !isNoProjectSelected && isConnected && !hasProjects {
            return .noProject("Add project")
        }
        return .noProject(noProjectLabel)
    }

    /// Filters the server's managed scratch project out of a projects dictionary so threads referencing it render as project-less.
    static func nonScratchProjectsByID(
        projects: [ProjectShell],
        scratchWorkspaceRoot: String?
    ) -> [String: ProjectShell] {
        Dictionary(
            uniqueKeysWithValues: projects
                .filter { !$0.isScratch(in: scratchWorkspaceRoot) }
                .map { ($0.id, $0) }
        )
    }

    static func initialThreadTitle(from text: String) -> String {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty }) ?? "New thread"
        if firstLine.count <= 60 { return firstLine }
        return String(firstLine.prefix(57)) + "…"
    }
}
