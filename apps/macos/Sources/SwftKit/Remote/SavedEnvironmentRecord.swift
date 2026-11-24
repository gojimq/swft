import Foundation
import os

/// Hardware form factor for choosing a machine glyph in environment pickers and inbox subtitles.
public enum EnvironmentMachineKind: String, Codable, Sendable, Hashable {
    case laptop
    case desktop
    case server
    case unknown

    public init(platform: ExecutionEnvironmentPlatform?) {
        self.init(rawMachine: platform?.machine, os: platform?.os)
    }

    public init(rawMachine: String?, os: String?) {
        switch rawMachine?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "laptop":
            self = .laptop
        case "desktop":
            self = .desktop
        case "server", "vm", "container":
            self = .server
        default:
            switch os?.lowercased() {
            case "linux":
                self = .server
            case "darwin":
                self = .laptop
            case "win32", "windows":
                self = .desktop
            default:
                self = .unknown
            }
        }
    }
}

/// Non-secret metadata persisted for each saved remote environment.
/// Access tokens are NEVER stored here; they live exclusively in `CredentialStore` (Keychain).
public struct SavedEnvironmentRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var customLabel: String?
    public var lastKnownLabel: String
    public var httpBaseURL: URL
    public var machine: String?
    public var os: String?
    public var serverVersion: String?
    public var pairedOverHTTPS: Bool
    public var addedAt: Date
    public var lastConnectedAt: Date?

    public init(
        id: String,
        customLabel: String? = nil,
        lastKnownLabel: String,
        httpBaseURL: URL,
        machine: String? = nil,
        os: String? = nil,
        serverVersion: String? = nil,
        pairedOverHTTPS: Bool = false,
        addedAt: Date = Date(),
        lastConnectedAt: Date? = nil
    ) {
        self.id = id
        self.customLabel = customLabel
        self.lastKnownLabel = lastKnownLabel
        self.httpBaseURL = httpBaseURL
        self.machine = machine
        self.os = os
        self.serverVersion = serverVersion
        self.pairedOverHTTPS = pairedOverHTTPS
        self.addedAt = addedAt
        self.lastConnectedAt = lastConnectedAt
    }

    public var effectiveLabel: String {
        let trimmed = customLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        return lastKnownLabel
    }
}

/// Persistence abstraction for saved remote environment metadata.
public protocol EnvironmentRecordStore: Sendable {
    func load() throws -> [SavedEnvironmentRecord]
    func save(_ records: [SavedEnvironmentRecord]) throws
}

/// Atomically stores saved remote environment metadata in `<baseDirectory>/environments.json`.
public final class FileEnvironmentRecordStore: EnvironmentRecordStore {
    public static let filename = "environments.json"

    public let fileURL: URL

    public init(baseDirectory: URL = ServerLaunchConfiguration.defaultBaseDirectory) {
        self.fileURL = baseDirectory.appendingPathComponent(Self.filename, isDirectory: false)
    }

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> [SavedEnvironmentRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        return try SwftJSON.makeDecoder().decode([SavedEnvironmentRecord].self, from: data)
    }

    public func save(_ records: [SavedEnvironmentRecord]) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = SwftJSON.makeEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(records)
        data.append(0x0A)

        let tempURL = dir.appendingPathComponent(".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: tempURL, options: .atomic)
        do {
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }
}

/// In-memory record store for unit tests and mock mode.
public final class InMemoryEnvironmentRecordStore: EnvironmentRecordStore {
    private let storage = OSAllocatedUnfairLock<[SavedEnvironmentRecord]>(initialState: [])

    public init(initial: [SavedEnvironmentRecord] = []) {
        storage.withLock { $0 = initial }
    }

    public func load() throws -> [SavedEnvironmentRecord] {
        storage.withLock { $0 }
    }

    public func save(_ records: [SavedEnvironmentRecord]) throws {
        storage.withLock { $0 = records }
    }
}
