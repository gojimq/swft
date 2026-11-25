import CoreGraphics
import Foundation

struct ProjectThreadCounts: Equatable, Sendable {
    var listed: Int
    var archived: Int

    var total: Int { listed + archived }
}

struct ProjectDeletionConfirmation: Equatable, Sendable {
    let title: String
    let message: String
    let confirmLabel: String
}

struct ProjectPostDeleteSelection: Equatable, Sendable {
    let selectedProjectID: String?
    let isNoProjectSelected: Bool
}

/// Pure helpers for local workspace availability, project removal confirmation copy, and post-delete selection recovery.
enum ProjectDeletionLogic {
    static func localDirectoryExists(at path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    /// Checks workspace folder existence only for local environments; remote paths are never probed on this Mac.
    static func isWorkspaceMissing(
        workspaceRoot: String?,
        isLocalEnvironment: Bool,
        directoryExists: (String) -> Bool = localDirectoryExists
    ) -> Bool {
        guard isLocalEnvironment else { return false }
        guard let trimmed = workspaceRoot?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return false }
        return !directoryExists(trimmed)
    }

    static func nextSelectionAfterDeleting(
        deletedProjectID: String,
        wasSelected: Bool,
        wasNoProjectSelected: Bool,
        currentSelectedProjectID: String?,
        remainingProjects: [ProjectRef]
    ) -> ProjectPostDeleteSelection {
        if wasNoProjectSelected {
            return ProjectPostDeleteSelection(selectedProjectID: nil, isNoProjectSelected: true)
        }
        if !wasSelected,
           let currentSelectedProjectID,
           currentSelectedProjectID != deletedProjectID,
           remainingProjects.contains(where: { $0.id == currentSelectedProjectID && !$0.isWorkspaceMissing })
        {
            return ProjectPostDeleteSelection(selectedProjectID: currentSelectedProjectID, isNoProjectSelected: false)
        }
        let nextValid = remainingProjects.first(where: { !$0.isWorkspaceMissing })
        return ProjectPostDeleteSelection(selectedProjectID: nextValid?.id, isNoProjectSelected: false)
    }

    static func confirmation(
        for project: ProjectRef,
        threadCounts: ProjectThreadCounts
    ) -> ProjectDeletionConfirmation {
        let title = "Remove “\(project.name)”?"
        let impact: String
        switch (threadCounts.listed > 0, threadCounts.archived > 0) {
        case (true, true):
            impact = "This removes the project and deletes \(pluralized(threadCounts.listed, singular: "thread")) and \(pluralized(threadCounts.archived, singular: "archived thread")) from Swft."
        case (true, false):
            impact = "This removes the project and deletes \(pluralized(threadCounts.listed, singular: "thread")) from Swft."
        case (false, true):
            impact = "This removes the project and deletes \(pluralized(threadCounts.archived, singular: "archived thread")) from Swft."
        case (false, false):
            if project.isWorkspaceMissing {
                impact = "This folder no longer exists on disk. Removing it clears the project entry from Swft."
            } else {
                impact = "This removes the project entry from Swft."
            }
        }

        let diskNote = project.isWorkspaceMissing
            ? "No files on disk will be deleted."
            : "Your files on disk will not be deleted."

        return ProjectDeletionConfirmation(
            title: title,
            message: "\(impact) \(diskNote)",
            confirmLabel: "Remove"
        )
    }

    static func displayPath(
        _ path: String,
        homeDirectory: String = NSHomeDirectory(),
        isLocal: Bool
    ) -> String {
        guard isLocal else { return path }
        let normalizedHome = trimTrailingSlashes(homeDirectory)
        guard !normalizedHome.isEmpty, normalizedHome != "/" else { return path }
        if path == normalizedHome {
            return "~"
        }
        if path.hasPrefix("\(normalizedHome)/") {
            return "~\(path.dropFirst(normalizedHome.count))"
        }
        return path
    }

    static func panelLeadingOffset(
        triggerFrame: CGRect,
        composerFrame: CGRect,
        panelWidth: CGFloat
    ) -> CGFloat {
        guard composerFrame.width > 0, triggerFrame.width > 0 else { return 0 }
        let raw = triggerFrame.minX - composerFrame.minX
        let maxOffset = max(0, composerFrame.width - panelWidth)
        return min(max(0, raw), maxOffset)
    }

    private static func pluralized(_ count: Int, singular: String) -> String {
        "\(count) \(count == 1 ? singular : "\(singular)s")"
    }

    private static func trimTrailingSlashes(_ value: String) -> String {
        var result = value
        while result.count > 1 && result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}
