import Foundation

// MARK: - Files & Filesystem RPC Method Tags (`packages/contracts/src/rpc.ts`)

public extension RPCMethod {
    static let projectsListEntries = "projects.listEntries"
    static let projectsSearchEntries = "projects.searchEntries"
    static let projectsReadFile = "projects.readFile"
    static let filesystemBrowse = "filesystem.browse"
    static let filesystemGetMetadata = "filesystem.getMetadata"
}

// MARK: - Project Entries & File Reading (`packages/contracts/src/project.ts`)

public enum ProjectEntryKind: String, Codable, Sendable, Hashable {
    case file
    case directory
}

public struct ProjectEntry: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let path: String
    public let kind: ProjectEntryKind
    public let ignored: Bool?

    public var id: String { path }

    public var name: String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        if let slash = trimmed.lastIndex(of: "/") {
            return String(trimmed[trimmed.index(after: slash)...])
        }
        return trimmed
    }

    public init(path: String, kind: ProjectEntryKind, ignored: Bool? = nil) {
        self.path = path
        self.kind = kind
        self.ignored = ignored
    }
}

public struct ProjectListEntriesInput: Encodable, Sendable, Equatable {
    public let cwd: String
    public let directoryPath: String?

    public init(cwd: String, directoryPath: String? = nil) {
        self.cwd = cwd
        self.directoryPath = directoryPath
    }
}

public struct ProjectListEntriesResult: Codable, Sendable, Equatable {
    public let entries: [ProjectEntry]
    public let truncated: Bool

    public init(entries: [ProjectEntry], truncated: Bool = false) {
        self.entries = entries
        self.truncated = truncated
    }
}

public struct ProjectSearchEntriesInput: Encodable, Sendable, Equatable {
    public let cwd: String
    public let query: String
    public let limit: Int
    public let kind: ProjectEntryKind?
    public let imageOnly: Bool?

    public init(
        cwd: String,
        query: String,
        limit: Int = 100,
        kind: ProjectEntryKind? = nil,
        imageOnly: Bool? = nil
    ) {
        self.cwd = cwd
        self.query = query
        self.limit = max(1, min(200, limit))
        self.kind = kind
        self.imageOnly = imageOnly
    }
}

public struct ProjectSearchEntriesResult: Codable, Sendable, Equatable {
    public let entries: [ProjectEntry]
    public let truncated: Bool

    public init(entries: [ProjectEntry], truncated: Bool = false) {
        self.entries = entries
        self.truncated = truncated
    }
}

public struct ProjectReadFileInput: Encodable, Sendable, Equatable {
    public let cwd: String
    public let relativePath: String
    public let allowMissing: Bool?

    public init(cwd: String, relativePath: String, allowMissing: Bool? = nil) {
        self.cwd = cwd
        self.relativePath = relativePath
        self.allowMissing = allowMissing
    }
}

public struct ProjectReadFileResult: Codable, Sendable, Equatable {
    public let relativePath: String
    public let contents: String
    public let byteLength: Int
    public let truncated: Bool
    public let exists: Bool?

    public init(
        relativePath: String,
        contents: String,
        byteLength: Int,
        truncated: Bool = false,
        exists: Bool? = nil
    ) {
        self.relativePath = relativePath
        self.contents = contents
        self.byteLength = byteLength
        self.truncated = truncated
        self.exists = exists
    }
}

// MARK: - Filesystem Browse & Metadata (`packages/contracts/src/filesystem.ts`)

public struct FilesystemBrowseInput: Encodable, Sendable, Equatable {
    public let partialPath: String
    public let cwd: String?

    public init(partialPath: String, cwd: String? = nil) {
        self.partialPath = partialPath
        self.cwd = cwd
    }
}

public struct FilesystemBrowseEntry: Codable, Sendable, Equatable, Identifiable {
    public let name: String
    public let fullPath: String

    public var id: String { fullPath }

    public init(name: String, fullPath: String) {
        self.name = name
        self.fullPath = fullPath
    }
}

public struct FilesystemBrowseResult: Codable, Sendable, Equatable {
    public let parentPath: String
    public let entries: [FilesystemBrowseEntry]

    public init(parentPath: String, entries: [FilesystemBrowseEntry]) {
        self.parentPath = parentPath
        self.entries = entries
    }
}

public struct FilesystemGetMetadataInput: Encodable, Sendable, Equatable {
    public let paths: [String]

    public init(paths: [String]) {
        self.paths = paths
    }
}

public struct FilesystemEntryMetadata: Codable, Sendable, Equatable {
    public let kind: String
    public let byteLength: Int?
    public let mimeType: String?

    public init(kind: String, byteLength: Int? = nil, mimeType: String? = nil) {
        self.kind = kind
        self.byteLength = byteLength
        self.mimeType = mimeType
    }
}

public struct FilesystemGetMetadataResult: Codable, Sendable, Equatable {
    public let entries: [FilesystemEntryMetadata?]

    public init(entries: [FilesystemEntryMetadata?]) {
        self.entries = entries
    }
}

// MARK: - ServerConnection Files RPCs

public extension ServerConnection {
    func listProjectEntries(
        cwd: String,
        directoryPath: String? = nil
    ) async throws -> ProjectListEntriesResult {
        try await call(
            tag: RPCMethod.projectsListEntries,
            payload: ProjectListEntriesInput(cwd: cwd, directoryPath: directoryPath)
        )
    }

    func searchProjectEntries(
        cwd: String,
        query: String,
        limit: Int = 100,
        kind: ProjectEntryKind? = nil,
        imageOnly: Bool? = nil
    ) async throws -> ProjectSearchEntriesResult {
        try await call(
            tag: RPCMethod.projectsSearchEntries,
            payload: ProjectSearchEntriesInput(
                cwd: cwd,
                query: query,
                limit: limit,
                kind: kind,
                imageOnly: imageOnly
            )
        )
    }

    func readProjectFile(
        cwd: String,
        relativePath: String,
        allowMissing: Bool? = nil
    ) async throws -> ProjectReadFileResult {
        try await call(
            tag: RPCMethod.projectsReadFile,
            payload: ProjectReadFileInput(
                cwd: cwd,
                relativePath: relativePath,
                allowMissing: allowMissing
            )
        )
    }

    func browseFilesystem(
        partialPath: String,
        cwd: String? = nil
    ) async throws -> FilesystemBrowseResult {
        try await call(
            tag: RPCMethod.filesystemBrowse,
            payload: FilesystemBrowseInput(partialPath: partialPath, cwd: cwd)
        )
    }

    func getFilesystemMetadata(paths: [String]) async throws -> FilesystemGetMetadataResult {
        try await call(
            tag: RPCMethod.filesystemGetMetadata,
            payload: FilesystemGetMetadataInput(paths: paths)
        )
    }
}
