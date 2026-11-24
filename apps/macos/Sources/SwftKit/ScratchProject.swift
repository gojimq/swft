import Foundation

public extension RPCMethod {
    static let projectsEnsureScratch = "projects.ensureScratch"
}

/// Result of `projects.ensureScratch` (`ProjectEnsureScratchResult` in `packages/contracts/src/project.ts`).
public struct ProjectEnsureScratchResult: Codable, Sendable, Equatable {
    public let projectId: String

    public init(projectId: String) {
        self.projectId = projectId
    }
}

/// Path normalization and scratch-project matching mirroring `packages/shared/src/path.ts`
/// (`normalizeProjectPathForComparison`) and `packages/client-runtime/src/state/projects.ts` (`isScratchProject`).
public enum ScratchProjectMatcher {
    public static func normalizePathForComparison(_ value: String) -> String {
        let normalized = normalizePathForDispatch(value)
        if isWindowsDrivePath(normalized) || isUncPath(normalized) {
            return normalized.replacingOccurrences(of: "/", with: "\\").lowercased()
        }
        return normalized
    }

    public static func isScratchProject(
        workspaceRoot: String,
        scratchWorkspaceRoot: String?
    ) -> Bool {
        guard let scratchWorkspaceRoot else { return false }
        let normalizedRoot = normalizePathForComparison(scratchWorkspaceRoot)
        guard !normalizedRoot.isEmpty else { return false }
        return normalizePathForComparison(workspaceRoot) == normalizedRoot
    }

    private static func normalizePathForDispatch(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRootPath(trimmed) else { return trimmed }

        let stripped: String
        if trimmed.hasPrefix("/") {
            stripped = trimTrailing(trimmed, matching: { $0 == "/" })
        } else {
            stripped = trimTrailing(trimmed, matching: { $0 == "/" || $0 == "\\" })
        }
        if stripped.isEmpty { return trimmed }
        if isBareWindowsDrive(stripped) {
            return "\(stripped)\\"
        }
        return stripped
    }

    private static func trimTrailing(_ value: String, matching predicate: (Character) -> Bool) -> String {
        var end = value.endIndex
        while end > value.startIndex {
            let prev = value.index(before: end)
            if predicate(value[prev]) {
                end = prev
            } else {
                break
            }
        }
        return String(value[..<end])
    }

    private static func isRootPath(_ value: String) -> Bool {
        if value == "/" || value == "\\" { return true }
        let chars = Array(value)
        return chars.count == 3
            && chars[0].isASCII && chars[0].isLetter
            && chars[1] == ":"
            && (chars[2] == "/" || chars[2] == "\\")
    }

    private static func isBareWindowsDrive(_ value: String) -> Bool {
        let chars = Array(value)
        return chars.count == 2 && chars[0].isASCII && chars[0].isLetter && chars[1] == ":"
    }

    private static func isWindowsDrivePath(_ value: String) -> Bool {
        let chars = Array(value)
        guard chars.count >= 2, chars[0].isASCII, chars[0].isLetter, chars[1] == ":" else {
            return false
        }
        return chars.count == 2 || chars[2] == "/" || chars[2] == "\\"
    }

    private static func isUncPath(_ value: String) -> Bool {
        value.hasPrefix("\\\\")
    }
}

public extension ProjectShell {
    func isScratch(in scratchWorkspaceRoot: String?) -> Bool {
        ScratchProjectMatcher.isScratchProject(
            workspaceRoot: workspaceRoot,
            scratchWorkspaceRoot: scratchWorkspaceRoot
        )
    }
}

public extension ThreadsStore {
    /// Non-empty scratch workspace root advertised by the connected server, or nil when unavailable.
    var availableScratchWorkspaceRoot: String? {
        guard connectionState.isConnected else { return nil }
        guard let root = serverConfig?.scratchWorkspaceRoot?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !root.isEmpty
        else { return nil }
        return root
    }

    /// The server's managed scratch ("No project") project if present in the shell snapshot.
    var scratchProject: ProjectShell? {
        guard let root = serverConfig?.scratchWorkspaceRoot else { return nil }
        return projects.first { $0.isScratch(in: root) }
    }

    /// Whether `project` is the server's managed scratch project rather than a user project.
    func isScratchProject(_ project: ProjectShell) -> Bool {
        project.isScratch(in: serverConfig?.scratchWorkspaceRoot)
    }

    /// Ensures the server's managed scratch project exists and returns its project ID.
    @discardableResult
    func ensureScratchProject() async throws -> ProjectEnsureScratchResult {
        try await connection.call(
            tag: RPCMethod.projectsEnsureScratch,
            payload: EmptyPayload()
        )
    }
}
