import Foundation
import Observation

/// One-time pairing invite minted for this Mac (or another connected host environment).
public struct PairingInvite: Sendable, Equatable {
    public let pairingURL: String
    public let token: String
    public let expiresAt: Date
    public let origin: String
    public let environmentId: String

    public var isLoopback: Bool {
        PairingURLParser.isLoopbackOrigin(origin)
    }

    public init(
        pairingURL: String,
        token: String,
        expiresAt: Date,
        origin: String,
        environmentId: String
    ) {
        self.pairingURL = pairingURL
        self.token = token
        self.expiresAt = expiresAt
        self.origin = origin
        self.environmentId = environmentId
    }

    /// Rebuilds the invite's origin & URL when a tunnel or public HTTPS endpoint becomes active.
    public func upgraded(toPublicBaseURL publicBaseURL: String) -> PairingInvite? {
        guard let built = PairingURLParser.buildPairingInviteURL(baseURL: publicBaseURL, token: token) else {
            return nil
        }
        return PairingInvite(
            pairingURL: built.pairingURL,
            token: token,
            expiresAt: expiresAt,
            origin: built.origin,
            environmentId: environmentId
        )
    }
}

public enum EnvironmentRegistryError: Error, Sendable, Equatable, LocalizedError {
    case cannotRemoveLocal
    case environmentNotFound(String)
    case missingCredentials(String)
    case noConnectedHost
    case invalidPublicURL

    public var errorDescription: String? {
        switch self {
        case .cannotRemoveLocal:
            return "The local server on this Mac cannot be removed."
        case .environmentNotFound(let id):
            return "Environment \(id) was not found."
        case .missingCredentials(let label):
            return "Credentials for \"\(label)\" are missing from the Keychain. Re-pair to reconnect."
        case .noConnectedHost:
            return "No connected server is available to create a pairing invite."
        case .invalidPublicURL:
            return "Enter a valid http:// or https:// public URL before creating a pairing invite."
        }
    }
}

/// One managed execution environment (either this Mac's bundled server or a paired remote host),
/// owning its dedicated `ServerConnection` and `ThreadsStore`.
@MainActor
@Observable
public final class ManagedEnvironment: Identifiable {
    public nonisolated let id: String
    public nonisolated let isLocal: Bool
    public nonisolated let httpBaseURL: URL
    public nonisolated let connection: ServerConnection
    public let threadsStore: ThreadsStore

    public var customLabel: String?
    public var lastKnownLabel: String
    public var lastKnownMachine: String?
    public var lastKnownOS: String?
    public var lastKnownServerVersion: String?
    public var pairedOverHTTPS: Bool
    public var addedAt: Date
    public var lastConnectedAt: Date?
    public var hasMissingCredentials: Bool

    public init(
        id: String,
        isLocal: Bool,
        httpBaseURL: URL,
        connection: ServerConnection,
        threadsStore: ThreadsStore,
        customLabel: String? = nil,
        lastKnownLabel: String,
        lastKnownMachine: String? = nil,
        lastKnownOS: String? = nil,
        lastKnownServerVersion: String? = nil,
        pairedOverHTTPS: Bool = false,
        addedAt: Date = Date(),
        lastConnectedAt: Date? = nil,
        hasMissingCredentials: Bool = false
    ) {
        self.id = id
        self.isLocal = isLocal
        self.httpBaseURL = httpBaseURL
        self.connection = connection
        self.threadsStore = threadsStore
        self.customLabel = customLabel
        self.lastKnownLabel = lastKnownLabel
        self.lastKnownMachine = lastKnownMachine
        self.lastKnownOS = lastKnownOS
        self.lastKnownServerVersion = lastKnownServerVersion
        self.pairedOverHTTPS = pairedOverHTTPS
        self.addedAt = addedAt
        self.lastConnectedAt = lastConnectedAt
        self.hasMissingCredentials = hasMissingCredentials
    }

    public var displayLabel: String {
        let trimmed = customLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        if let live = threadsStore.environment?.label.trimmingCharacters(in: .whitespacesAndNewlines), !live.isEmpty {
            return live
        }
        return lastKnownLabel
    }

    public var machineKind: EnvironmentMachineKind {
        if let platform = threadsStore.environment?.platform {
            return EnvironmentMachineKind(platform: platform)
        }
        return EnvironmentMachineKind(rawMachine: lastKnownMachine, os: lastKnownOS)
    }

    public var connectionState: ConnectionState {
        if hasMissingCredentials {
            return .failed("Credentials missing — re-pair to connect.")
        }
        return threadsStore.connectionState
    }

    public var isConnected: Bool {
        !hasMissingCredentials && threadsStore.connectionState.isConnected
    }

    public var serverVersion: String? {
        threadsStore.environment?.serverVersion ?? lastKnownServerVersion
    }

    public var canRemove: Bool { !isLocal }
    public var canRename: Bool { !isLocal }

    public var canReconnect: Bool {
        !hasMissingCredentials && !isConnected
    }

    public func toSavedRecord() -> SavedEnvironmentRecord {
        SavedEnvironmentRecord(
            id: id,
            customLabel: customLabel,
            lastKnownLabel: threadsStore.environment?.label ?? lastKnownLabel,
            httpBaseURL: httpBaseURL,
            machine: threadsStore.environment?.platform.machine ?? lastKnownMachine,
            os: threadsStore.environment?.platform.os ?? lastKnownOS,
            serverVersion: serverVersion,
            pairedOverHTTPS: pairedOverHTTPS,
            addedAt: addedAt,
            lastConnectedAt: lastConnectedAt
        )
    }
}

/// Multi-environment registry coordinating the local bundled server alongside any number of
/// saved remote environments, with Keychain-backed credentials and thread/project routing.
@MainActor
@Observable
public final class EnvironmentRegistry {
    public typealias RemotePairHandler = @Sendable (
        _ target: ParsedPairingTarget,
        _ expectedEnvironmentId: String?,
        _ clientLabel: String
    ) async throws -> PairedRemoteSession

    public private(set) var entries: [ManagedEnvironment] = []
    public private(set) var isLoaded: Bool = false

    private let credentialStore: any CredentialStore
    private let recordStore: any EnvironmentRecordStore
    private let session: URLSession
    private let pairingClient: PairingClient
    private let clientLabel: String
    private let pairHandler: RemotePairHandler
    @ObservationIgnored private var connectTasks: [String: Task<Void, Never>] = [:]

    public init(
        credentialStore: any CredentialStore = KeychainCredentialStore(),
        recordStore: any EnvironmentRecordStore = FileEnvironmentRecordStore(),
        session: URLSession = .shared,
        clientLabel: String = "Swft",
        pairHandler: RemotePairHandler? = nil
    ) {
        self.credentialStore = credentialStore
        self.recordStore = recordStore
        self.session = session
        let client = PairingClient(session: session)
        self.pairingClient = client
        self.clientLabel = clientLabel
        self.pairHandler = pairHandler ?? { target, expectedId, label in
            try await client.pairRemote(
                target: target,
                expectedEnvironmentId: expectedId,
                clientLabel: label
            )
        }
    }

    // MARK: - Queries & Routing

    public var localEnvironment: ManagedEnvironment? {
        entries.first(where: \.isLocal)
    }

    public var remoteEnvironments: [ManagedEnvironment] {
        entries.filter { !$0.isLocal }
    }

    public var connectedEnvironments: [ManagedEnvironment] {
        entries.filter(\.isConnected)
    }

    public func environment(id: String) -> ManagedEnvironment? {
        entries.first { $0.id == id }
    }

    /// Finds the environment that owns a given thread ID (checking active and archived threads).
    public func environment(owningThreadID threadID: String, preferredEnvironmentID: String? = nil) -> ManagedEnvironment? {
        if let preferredEnvironmentID,
           let preferred = environment(id: preferredEnvironmentID),
           preferred.threadsStore.threads.contains(where: { $0.id == threadID })
           || preferred.threadsStore.archivedThreads.contains(where: { $0.id == threadID })
        {
            return preferred
        }
        for entry in entries {
            if entry.threadsStore.threads.contains(where: { $0.id == threadID })
                || entry.threadsStore.archivedThreads.contains(where: { $0.id == threadID })
            {
                return entry
            }
        }
        return nil
    }

    /// Finds the environment that owns a given project ID.
    public func environment(owningProjectID projectID: String, preferredEnvironmentID: String? = nil) -> ManagedEnvironment? {
        if let preferredEnvironmentID,
           let preferred = environment(id: preferredEnvironmentID),
           preferred.threadsStore.projects.contains(where: { $0.id == projectID })
        {
            return preferred
        }
        return entries.first { $0.threadsStore.projects.contains(where: { $0.id == projectID }) }
    }

    /// Aggregated listed threads across all environments, sorted newest-updated first.
    public var allListedThreads: [(environment: ManagedEnvironment, thread: ThreadShell)] {
        entries
            .flatMap { entry in
                entry.threadsStore.listedThreads.map { (environment: entry, thread: $0) }
            }
            .sorted { $0.thread.updatedAt > $1.thread.updatedAt }
    }

    // MARK: - Local Registration

    /// Registers (or replaces) the local bundled server environment in the registry.
    @discardableResult
    public func registerLocal(
        endpoint: ServerEndpoint,
        connection: ServerConnection,
        threadsStore: ThreadsStore
    ) -> ManagedEnvironment {
        entries.removeAll { $0.isLocal || $0.id == endpoint.environment.environmentId }
        let entry = ManagedEnvironment(
            id: endpoint.environment.environmentId,
            isLocal: true,
            httpBaseURL: endpoint.httpBaseURL,
            connection: connection,
            threadsStore: threadsStore,
            customLabel: nil,
            lastKnownLabel: endpoint.environment.label,
            lastKnownMachine: endpoint.environment.platform.machine,
            lastKnownOS: endpoint.environment.platform.os,
            lastKnownServerVersion: endpoint.environment.serverVersion,
            pairedOverHTTPS: false,
            lastConnectedAt: Date()
        )
        entries.append(entry)
        sortEntries()
        return entry
    }

    public func unregisterLocal() async {
        guard let local = localEnvironment else { return }
        connectTasks.removeValue(forKey: local.id)?.cancel()
        entries.removeAll { $0.id == local.id }
    }

    internal func insertEnvironmentForTesting(_ entry: ManagedEnvironment) {
        entries.removeAll { $0.id == entry.id }
        entries.append(entry)
        sortEntries()
    }

    // MARK: - Persistence & Saved Remotes

    /// Loads saved remote environments from disk + Keychain and optionally opens their connections.
    public func loadSavedRemotes(autoConnect: Bool = true) async {
        let records: [SavedEnvironmentRecord]
        do {
            records = try recordStore.load()
        } catch {
            records = []
        }

        for record in records {
            if entries.contains(where: { $0.id == record.id }) {
                continue
            }
            let storedToken = try? credentialStore.read(account: record.id)
            let credential: AuthCredential = storedToken.map { .bearerToken($0) } ?? .bearerToken("")
            let connection = ServerConnection(
                httpBaseURL: record.httpBaseURL,
                credential: credential,
                clientLabel: clientLabel,
                session: session
            )
            let store = ThreadsStore(connection: connection)
            let entry = ManagedEnvironment(
                id: record.id,
                isLocal: false,
                httpBaseURL: record.httpBaseURL,
                connection: connection,
                threadsStore: store,
                customLabel: record.customLabel,
                lastKnownLabel: record.lastKnownLabel,
                lastKnownMachine: record.machine,
                lastKnownOS: record.os,
                lastKnownServerVersion: record.serverVersion,
                pairedOverHTTPS: record.pairedOverHTTPS,
                addedAt: record.addedAt,
                lastConnectedAt: record.lastConnectedAt,
                hasMissingCredentials: storedToken == nil || storedToken?.isEmpty == true
            )
            entries.append(entry)
            if autoConnect && !entry.hasMissingCredentials {
                startConnection(for: entry)
            }
        }
        sortEntries()
        isLoaded = true
    }

    /// Pairs a new remote server (or re-pairs an existing one), persists its credentials in Keychain,
    /// saves metadata to disk, and starts its live WebSocket + `ThreadsStore` subscriptions.
    @discardableResult
    public func pairRemote(
        address: String,
        token: String? = nil,
        expectedEnvironmentId: String? = nil,
        connectImmediately: Bool = true
    ) async throws -> ManagedEnvironment {
        let target = try PairingURLParser.parse(address: address, token: token)

        if let expectedId = expectedEnvironmentId,
           let existing = environment(id: expectedId),
           existing.pairedOverHTTPS && !target.isHTTPS
        {
            throw PairingError.httpsDowngradeNotAllowed(label: existing.displayLabel)
        }

        let paired = try await pairHandler(target, expectedEnvironmentId, clientLabel)
        let envId = paired.descriptor.environmentId

        if let existing = environment(id: envId), existing.pairedOverHTTPS && !target.isHTTPS {
            throw PairingError.httpsDowngradeNotAllowed(label: existing.displayLabel)
        }

        // Preserve any user-assigned custom label on re-pair.
        let preservedCustomLabel = environment(id: envId)?.customLabel ?? paired.suggestedLabel
        let preservedAddedAt = environment(id: envId)?.addedAt ?? Date()

        if let existing = environment(id: envId), !existing.isLocal {
            connectTasks.removeValue(forKey: envId)?.cancel()
            existing.threadsStore.stop()
            await existing.connection.disconnect()
            entries.removeAll { $0.id == envId }
        }

        try credentialStore.write(paired.accessToken, account: envId)

        let connection = ServerConnection(
            httpBaseURL: paired.httpBaseURL,
            credential: .bearerToken(paired.accessToken),
            clientLabel: clientLabel,
            session: session
        )
        let store = ThreadsStore(connection: connection)
        let entry = ManagedEnvironment(
            id: envId,
            isLocal: false,
            httpBaseURL: paired.httpBaseURL,
            connection: connection,
            threadsStore: store,
            customLabel: preservedCustomLabel,
            lastKnownLabel: paired.descriptor.label,
            lastKnownMachine: paired.descriptor.platform.machine,
            lastKnownOS: paired.descriptor.platform.os,
            lastKnownServerVersion: paired.descriptor.serverVersion,
            pairedOverHTTPS: target.isHTTPS,
            addedAt: preservedAddedAt,
            lastConnectedAt: Date(),
            hasMissingCredentials: false
        )

        // If the user paired their own local server, don't duplicate the local entry.
        if let existingLocal = environment(id: envId), existingLocal.isLocal {
            return existingLocal
        }

        entries.append(entry)
        sortEntries()
        try persistRemoteRecords()

        if connectImmediately {
            store.start()
            do {
                let descriptor = try await connection.connect()
                updateMetadata(for: entry, descriptor: descriptor)
            } catch {
                // Keep the saved entry so the user can retry from Settings -> Connections.
            }
        }
        return entry
    }

    /// Renames a saved remote environment (passing nil or whitespace resets to the server's own label).
    public func renameRemote(id: String, customLabel: String?) throws {
        guard let entry = environment(id: id) else {
            throw EnvironmentRegistryError.environmentNotFound(id)
        }
        let cleaned = customLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.customLabel = cleaned?.isEmpty == false ? cleaned : nil
        sortEntries()
        try persistRemoteRecords()
    }

    /// Disconnects and removes a saved remote environment, purging its Keychain credential and metadata.
    public func removeRemote(id: String) async throws {
        guard let entry = environment(id: id) else {
            throw EnvironmentRegistryError.environmentNotFound(id)
        }
        guard !entry.isLocal else {
            throw EnvironmentRegistryError.cannotRemoveLocal
        }
        connectTasks.removeValue(forKey: id)?.cancel()
        entry.threadsStore.stop()
        await entry.connection.disconnect()
        entries.removeAll { $0.id == id }
        try? credentialStore.delete(account: id)
        try persistRemoteRecords()
    }

    /// Reconnects one environment immediately (canceling any backoff delay).
    public func reconnect(id: String) async {
        guard let entry = environment(id: id), !entry.hasMissingCredentials else { return }
        connectTasks.removeValue(forKey: id)?.cancel()
        if entry.isConnected {
            await entry.connection.disconnect()
        }
        entry.threadsStore.start()
        do {
            let descriptor = try await entry.connection.connect()
            updateMetadata(for: entry, descriptor: descriptor)
        } catch {
            // ConnectionState reflects `.failed`, surfaced by the UI.
        }
    }

    /// Reconnects every disconnected or failed environment in parallel.
    public func reconnectAll() async {
        let targetIDs = entries.filter { !$0.isConnected && !$0.hasMissingCredentials }.map(\.id)
        let tasks = targetIDs.map { id in
            Task { @MainActor [weak self] in
                await self?.reconnect(id: id)
            }
        }
        for task in tasks {
            await task.value
        }
    }

    /// Mints a one-time pairing invite on the local host (or specified connected environment).
    public func createPairingInvite(
        environmentId: String? = nil,
        publicBaseURL: String? = nil,
        label: String? = "Swft"
    ) async throws -> PairingInvite {
        let target: ManagedEnvironment?
        if let environmentId {
            target = environment(id: environmentId)
        } else if let local = localEnvironment, local.isConnected {
            target = local
        } else {
            target = connectedEnvironments.first
        }

        guard let host = target, host.isConnected else {
            throw EnvironmentRegistryError.noConnectedHost
        }

        let accessToken = try await host.connection.currentAccessToken()
        let issued = try await pairingClient.createPairingCredential(
            baseURL: host.httpBaseURL,
            accessToken: accessToken,
            label: label
        )

        let baseURLString = publicBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBase = (baseURLString?.isEmpty == false ? baseURLString : nil) ?? host.httpBaseURL.absoluteString
        guard let built = PairingURLParser.buildPairingInviteURL(baseURL: resolvedBase, token: issued.credential) else {
            throw EnvironmentRegistryError.invalidPublicURL
        }

        return PairingInvite(
            pairingURL: built.pairingURL,
            token: issued.credential,
            expiresAt: issued.expiresAt,
            origin: built.origin,
            environmentId: host.id
        )
    }

    /// Cleanly disconnects all remote environments (and clears active connect tasks).
    public func disconnectAll() async {
        for task in connectTasks.values {
            task.cancel()
        }
        connectTasks.removeAll()
        for entry in entries where !entry.isLocal {
            entry.threadsStore.stop()
            await entry.connection.disconnect()
        }
    }

    // MARK: - Internal Helpers

    private func startConnection(for entry: ManagedEnvironment) {
        connectTasks[entry.id]?.cancel()
        entry.threadsStore.start()
        connectTasks[entry.id] = Task { @MainActor [weak self, weak entry] in
            guard let self, let entry else { return }
            do {
                let descriptor = try await entry.connection.connect()
                guard !Task.isCancelled else { return }
                self.updateMetadata(for: entry, descriptor: descriptor)
            } catch {
                // `ServerConnection` sets `.failed`; user can retry from Settings -> Connections.
            }
        }
    }

    private func updateMetadata(for entry: ManagedEnvironment, descriptor: ExecutionEnvironmentDescriptor) {
        entry.lastKnownLabel = descriptor.label
        entry.lastKnownMachine = descriptor.platform.machine
        entry.lastKnownOS = descriptor.platform.os
        entry.lastKnownServerVersion = descriptor.serverVersion
        entry.lastConnectedAt = Date()
        if !entry.isLocal {
            try? persistRemoteRecords()
        }
    }

    private func persistRemoteRecords() throws {
        let records = remoteEnvironments.map { $0.toSavedRecord() }
        try recordStore.save(records)
    }

    private func sortEntries() {
        entries.sort { lhs, rhs in
            if lhs.isLocal != rhs.isLocal {
                return lhs.isLocal
            }
            let cmp = lhs.displayLabel.localizedCaseInsensitiveCompare(rhs.displayLabel)
            if cmp != .orderedSame {
                return cmp == .orderedAscending
            }
            return lhs.id < rhs.id
        }
    }
}
