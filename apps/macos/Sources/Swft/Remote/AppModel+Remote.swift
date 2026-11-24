import AppKit
import Foundation
import SwftDesign
import SwftKit

/// Multi-environment state, routing, pairing, and tunnel extensions on `AppModel`.
@MainActor
extension AppModel {

    // MARK: - Environment Lists & Selection

    /// All environments (local Mac first, then saved remotes sorted alphabetically).
    var remoteEnvironments: [RemoteEnvironmentItem] {
        if isMock {
            if let mockEnvironments {
                return RemoteLogic.sortEnvironments(mockEnvironments)
            }
            return [
                RemoteEnvironmentItem(
                    id: "mock-local",
                    label: "Local server",
                    serverLabel: "Local server",
                    url: "http://127.0.0.1:3773",
                    isLocal: true,
                    machine: .laptop,
                    phase: .connected,
                    serverVersion: "0.1.11",
                    errorDetail: nil,
                    providerCount: 3,
                    hasMissingCredentials: false
                ),
            ]
        }

        var items = environmentRegistry.entries.map(RemoteLogic.environmentItem(from:))
        if !items.contains(where: \.isLocal) {
            items.insert(syntheticLocalEnvironmentItem(), at: 0)
        }
        return RemoteLogic.sortEnvironments(items)
    }

    var isMultiEnvironment: Bool {
        remoteEnvironments.count > 1
    }

    var activeComposerEnvironmentID: String? {
        RemoteLogic.resolveSelectedEnvironmentID(
            environments: remoteEnvironments,
            threadEnvironmentID: nil,
            selectedEnvironmentID: selectedEnvironmentID
        )
    }

    var activeComposerEnvironment: RemoteEnvironmentItem? {
        guard let id = activeComposerEnvironmentID else { return nil }
        return remoteEnvironments.first { $0.id == id }
    }

    var shouldShowComposerEnvironmentPicker: Bool {
        RemoteLogic.shouldShowComposerEnvironmentControl(
            environments: remoteEnvironments,
            activeEnvironmentID: activeComposerEnvironmentID,
            threadIsRemote: false
        )
    }

    var composerEnvironmentChipItems: [EnvironmentChipItem] {
        remoteEnvironments.map(\.chipItem)
    }

    var localServerEndpointPort: Int? {
        if isMock { return 3773 }
        return tunnelController.status.localPort
    }

    var canCreatePairingInvite: Bool {
        if isMock { return true }
        return environmentRegistry.connectedEnvironments.isEmpty == false
    }

    // MARK: - Active Store Routing (used by AppModel hooks)

    /// Returns the `ThreadsStore` that backs the Home composer (selected environment, falling back to local).
    func resolvedComposerStore(localStore: ThreadsStore?) -> ThreadsStore? {
        if let id = activeComposerEnvironmentID,
           let env = environmentRegistry.environment(id: id)
        {
            return env.threadsStore
        }
        return environmentRegistry.localEnvironment?.threadsStore ?? localStore
    }

    /// Returns the `ThreadsStore` that owns the active thread (or Home composer when on Home).
    func resolvedActiveStore(localStore: ThreadsStore?) -> ThreadsStore? {
        if let threadID = selectedThreadID {
            return owningEnvironment(forThreadID: threadID)?.threadsStore ?? localStore
        }
        return resolvedComposerStore(localStore: localStore)
    }

    /// Finds the managed environment owning `threadID`, preferring `activeThreadEnvironmentID` on tie.
    func owningEnvironment(forThreadID threadID: String) -> ManagedEnvironment? {
        if let owner = environmentRegistry.environment(
            owningThreadID: threadID,
            preferredEnvironmentID: activeThreadEnvironmentID
        ) {
            return owner
        }
        if let activeID = activeThreadEnvironmentID,
           let env = environmentRegistry.environment(id: activeID)
        {
            return env
        }
        return environmentRegistry.localEnvironment
    }

    /// Projects for the currently targeted Home environment (or mock per-environment projects).
    func resolvedMockProjects(defaultProjects: [ProjectRef]) -> [ProjectRef] {
        if let id = activeComposerEnvironmentID, let scoped = mockProjectsByEnvironment[id] {
            return scoped
        }
        return defaultProjects
    }

    /// Models for the currently targeted environment in mock mode.
    func resolvedMockModels(defaultModels: [ModelOption]) -> [ModelOption] {
        let envID = selectedThreadID
            .flatMap { threadSummary(for: $0)?.environmentID }
            ?? activeComposerEnvironmentID
        if let envID, let scoped = mockModelsByEnvironment[envID] {
            return scoped
        }
        return defaultModels
    }

    /// Aggregates sidebar threads across all registered environments, sorted newest first.
    func aggregatedSidebarThreads(fallbackLocalStore: ThreadsStore?) -> [ThreadSummary] {
        let entries = environmentRegistry.entries
        if entries.isEmpty {
            guard let store = fallbackLocalStore else { return [] }
            let hostName = store.environment?.label ?? store.hostname
            let providersByID = Dictionary(
                uniqueKeysWithValues: store.providers.map { ($0.instanceId, $0) }
            )
            return store.listedThreads.map { shell in
                SwftAdapters.threadSummary(
                    from: shell,
                    projectsByID: store.projectsByID,
                    providersByID: providersByID,
                    hostName: hostName,
                    activelyViewingThreadID: selectedThreadID
                )
            }
        }

        let envCount = entries.count
        return environmentRegistry.allListedThreads.map { pair in
            let showEnv = RemoteLogic.shouldShowEnvironmentDisambiguation(
                environmentCount: envCount,
                isRemote: !pair.environment.isLocal
            )
            return SwftAdapters.remoteThreadSummary(
                from: pair.thread,
                environment: pair.environment,
                showEnvironmentLabel: showEnv,
                activelyViewingThreadID: selectedThreadID
            )
        }
    }

    /// Whether the target environment for the current action (active thread or Home composer) is connected.
    func isTargetEnvironmentConnected(localConnected: Bool) -> Bool {
        if let threadID = selectedThreadID {
            return owningEnvironment(forThreadID: threadID)?.isConnected ?? localConnected
        }
        if let id = activeComposerEnvironmentID,
           let env = environmentRegistry.environment(id: id)
        {
            return env.isConnected
        }
        return localConnected
    }

    /// Multi-environment aware subtitle for the sidebar footer account row.
    func remoteAwareAccountDetail(defaultDetail: String) -> String {
        let remotes = environmentRegistry.remoteEnvironments
        guard !remotes.isEmpty else { return defaultDetail }
        let connectedCount = environmentRegistry.connectedEnvironments.count
        let totalCount = max(environmentRegistry.entries.count, remotes.count + 1)
        let totalProviders = environmentRegistry.connectedEnvironments.reduce(0) { sum, env in
            sum + env.threadsStore.providers.filter { $0.enabled && $0.installed && $0.status != .disabled }.count
        }
        let serverWord = totalCount == 1 ? "server" : "servers"
        let providerWord = totalProviders == 1 ? "provider" : "providers"
        if connectedCount == totalCount {
            return "\(connectedCount) \(serverWord) · \(totalProviders) \(providerWord)"
        }
        return "\(connectedCount)/\(totalCount) \(serverWord) online"
    }

    // MARK: - Lifecycle Hooks

    func startRemoteConnections() {
        guard !isMock else { return }
        Task { @MainActor [weak self] in
            await self?.environmentRegistry.loadSavedRemotes(autoConnect: true)
        }
    }

    func registerLocalEnvironment(
        endpoint: ServerEndpoint,
        connection: ServerConnection,
        store: ThreadsStore
    ) {
        environmentRegistry.registerLocal(endpoint: endpoint, connection: connection, threadsStore: store)
        tunnelController.updateLocalPort(endpoint.port)
    }

    func unregisterLocalEnvironment() async {
        await environmentRegistry.unregisterLocal()
        tunnelController.updateLocalPort(nil)
    }

    func shutdownRemoteConnections() async {
        await tunnelController.stop()
        await environmentRegistry.disconnectAll()
    }

    // MARK: - User Actions

    func selectEnvironment(_ environmentID: String) {
        guard activeComposerEnvironmentID != environmentID else { return }
        let previousProjectName = selectedProject?.name
        selectedEnvironmentID = environmentID
        modelPicker = nil
        actionError = nil

        let targetProjects = projects
        if let match = RemoteLogic.findProjectForEnvironment(
            projects: targetProjects,
            preferredName: previousProjectName
        ) {
            selectedProjectID = match.id
        } else {
            selectedProjectID = nil
        }

        // If the currently chosen model doesn't exist on the target environment, let selectedModel resolve its default.
        let targetModels = availableModels
        if let currentModelID = selectedModelID,
           !targetModels.contains(where: { $0.id == currentModelID })
        {
            selectedModelID = nil
            selectedReasoningChoiceId = nil
        }
    }

    func openConnectionsSettings() {
        destination = .settings
    }

    /// Prompts for a folder path when targeting a remote environment (native NSOpenPanel only browses this Mac).
    func pickAndAddProjectForActiveEnvironment() -> Bool {
        guard let activeEnv = activeComposerEnvironment, !activeEnv.isLocal else {
            return false
        }
        let alert = NSAlert()
        alert.messageText = "Add Project on \(activeEnv.label)"
        alert.informativeText = "Enter the folder path on \(activeEnv.label) to register as a project."
        alert.addButton(withTitle: "Add Project")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        input.placeholderString = "/path/to/your/project"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        if alert.runModal() == .alertFirstButtonReturn {
            let trimmed = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                Task {
                    await addRemoteProject(path: trimmed, onEnvironmentID: activeEnv.id)
                }
            }
        }
        return true
    }

    func addRemoteProject(path: String, onEnvironmentID envID: String) async {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let title = URL(fileURLWithPath: trimmed).lastPathComponent.nilIfBlank ?? trimmed

        if isMock {
            let ref = ProjectRef(
                id: "mock-\(UUID().uuidString)",
                name: title,
                initials: SwftAdapters.deriveInitials(from: title),
                tint: SwftAdapters.stableTintIndex(for: trimmed),
                workspaceRoot: trimmed,
                environmentID: envID
            )
            mockProjectsByEnvironment[envID, default: []].append(ref)
            selectedProjectID = ref.id
            return
        }

        guard let env = environmentRegistry.environment(id: envID), env.isConnected else {
            actionError = "Connect to that server before adding a project."
            return
        }
        do {
            let created = try await env.threadsStore.createProject(title: title, workspaceRoot: trimmed)
            selectedProjectID = created.id
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
    }

    @discardableResult
    func pairRemoteEnvironment(
        address: String,
        token: String? = nil,
        expectedEnvironmentId: String? = nil
    ) async throws -> RemoteEnvironmentItem {
        if isMock {
            let target = try PairingURLParser.parse(address: address, token: token)
            let envID = expectedEnvironmentId ?? "mock-remote-\(UUID().uuidString.prefix(6))"
            let hostName = target.suggestedLabel ?? target.httpBaseURL.host() ?? "Remote server"
            let item = RemoteEnvironmentItem(
                id: envID,
                label: hostName,
                serverLabel: hostName,
                url: target.httpBaseURL.absoluteString,
                isLocal: false,
                machine: .server,
                phase: .connected,
                serverVersion: "0.1.11",
                errorDetail: nil,
                providerCount: 2,
                hasMissingCredentials: false
            )
            var current = mockEnvironments ?? remoteEnvironments
            current.removeAll { $0.id == envID }
            current.append(item)
            mockEnvironments = current
            return item
        }

        let entry = try await environmentRegistry.pairRemote(
            address: address,
            token: token,
            expectedEnvironmentId: expectedEnvironmentId,
            connectImmediately: true
        )
        return RemoteLogic.environmentItem(from: entry)
    }

    func renameRemoteEnvironment(id: String, customLabel: String?) throws {
        if isMock {
            var current = mockEnvironments ?? remoteEnvironments
            guard let index = current.firstIndex(where: { $0.id == id }) else { return }
            let trimmed = customLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
            current[index].label = trimmed?.isEmpty == false ? trimmed! : current[index].serverLabel
            mockEnvironments = current
            return
        }
        try environmentRegistry.renameRemote(id: id, customLabel: customLabel)
    }

    func removeRemoteEnvironment(id: String) async throws {
        if isMock {
            var current = mockEnvironments ?? remoteEnvironments
            current.removeAll { $0.id == id && !$0.isLocal }
            mockEnvironments = current
            if selectedEnvironmentID == id {
                selectedEnvironmentID = nil
            }
            return
        }

        let shouldReturnHome = activeThreadEnvironmentID == id
        try await environmentRegistry.removeRemote(id: id)
        if selectedEnvironmentID == id {
            selectedEnvironmentID = nil
            selectedProjectID = nil
        }
        if shouldReturnHome {
            activeThreadEnvironmentID = nil
            goHome()
        }
    }

    func reconnectEnvironment(id: String) async {
        if isMock {
            var current = mockEnvironments ?? remoteEnvironments
            if let index = current.firstIndex(where: { $0.id == id }) {
                current[index].phase = .connected
                current[index].errorDetail = nil
                mockEnvironments = current
            }
            return
        }
        if let env = environmentRegistry.environment(id: id), env.isLocal {
            retryConnection()
            return
        }
        if environmentRegistry.environment(id: id) == nil {
            retryConnection()
            return
        }
        await environmentRegistry.reconnect(id: id)
    }

    func createHostPairingInvite(publicBaseURL: String? = nil) async throws -> PairingInvite {
        if isMock {
            let base = publicBaseURL?.nilIfBlank
                ?? tunnelController.status.activePublicUrl
                ?? "http://127.0.0.1:3773"
            let token = "SWFT-DEMO-PAIR-8429"
            let built = PairingURLParser.buildPairingInviteURL(baseURL: base, token: token)
                ?? (origin: base, pairingURL: "\(base)/pair#token=\(token)")
            return PairingInvite(
                pairingURL: built.pairingURL,
                token: token,
                expiresAt: now.addingTimeInterval(300),
                origin: built.origin,
                environmentId: "mock-local"
            )
        }

        let effectiveBase = publicBaseURL?.nilIfBlank ?? tunnelController.status.activePublicUrl
        return try await environmentRegistry.createPairingInvite(
            environmentId: environmentRegistry.localEnvironment?.id,
            publicBaseURL: effectiveBase,
            label: "Swft"
        )
    }

    // MARK: - Multi-Environment Mock Factory (Previews, Tests & Screenshots)

    static func mockMultiEnvironment() -> AppModel {
        let model = AppModel.mock()
        let localID = "env-local-macbook"
        let studioID = "env-remote-studio"
        let buildID = "env-remote-linux"

        model.mockEnvironments = [
            RemoteEnvironmentItem(
                id: localID,
                label: "Jim’s MacBook Pro",
                serverLabel: "Jim’s MacBook Pro",
                url: "http://127.0.0.1:3773",
                isLocal: true,
                machine: .laptop,
                phase: .connected,
                serverVersion: "0.1.11",
                errorDetail: nil,
                providerCount: 3,
                hasMissingCredentials: false
            ),
            RemoteEnvironmentItem(
                id: studioID,
                label: "Mac Studio",
                serverLabel: "Mac Studio",
                url: "https://studio-mac.trycloudflare.com",
                isLocal: false,
                machine: .desktop,
                phase: .connected,
                serverVersion: "0.1.11",
                errorDetail: nil,
                providerCount: 2,
                hasMissingCredentials: false
            ),
            RemoteEnvironmentItem(
                id: buildID,
                label: "Build Box",
                serverLabel: "build-box-01",
                url: "https://build.example.ts.net",
                isLocal: false,
                machine: .server,
                phase: .offline,
                serverVersion: "0.1.10",
                errorDetail: "Connection timed out",
                providerCount: 0,
                hasMissingCredentials: false
            ),
        ]

        let studioProject = ProjectRef(
            id: "p-ml-runner",
            name: "ML Runner",
            initials: "MR",
            tint: 5,
            workspaceRoot: "/Users/jim/code/ml-runner",
            environmentID: studioID
        )
        let studioInfra = ProjectRef(
            id: "p-infra",
            name: "Cluster Infra",
            initials: "CI",
            tint: 3,
            workspaceRoot: "/Users/jim/code/infra",
            environmentID: studioID
        )
        model.mockProjectsByEnvironment = [
            localID: MockData.projects.map { p in
                ProjectRef(id: p.id, name: p.name, initials: p.initials, tint: p.tint, workspaceRoot: p.workspaceRoot, environmentID: localID)
            },
            studioID: [studioProject, studioInfra],
            buildID: [],
        ]
        model.mockModelsByEnvironment = [
            localID: MockData.models,
            studioID: Array(MockData.models.prefix(5)),
        ]
        model.mockThreadsOverride = [
            ThreadSummary(
                id: "t-remote-1",
                title: "Benchmark batched inference kernels on M4 Max",
                project: studioProject,
                location: .branch("perf/flash-attn"),
                provider: .claude,
                activity: .running,
                updatedAt: MockData.ago(1),
                environmentID: studioID,
                environmentLabel: "Mac Studio",
                isRemoteEnvironment: true,
                environmentMachineSymbol: "desktopcomputer"
            ),
            ThreadSummary(
                id: "t-local-1",
                title: "Build Swift desktop frontend",
                project: MockData.swft,
                location: .branch("swft/feat-remote"),
                provider: .claude,
                activity: .needsApproval,
                updatedAt: MockData.ago(8),
                environmentID: localID,
                environmentLabel: "Jim’s MacBook Pro",
                isRemoteEnvironment: false,
                environmentMachineSymbol: "laptopcomputer"
            ),
            ThreadSummary(
                id: "t-remote-2",
                title: "Rotate staging tunnel certificates",
                project: studioInfra,
                location: .host("Mac Studio"),
                provider: .codex,
                activity: .unread,
                updatedAt: MockData.ago(35),
                environmentID: studioID,
                environmentLabel: "Mac Studio",
                isRemoteEnvironment: true,
                environmentMachineSymbol: "desktopcomputer"
            ),
            ThreadSummary(
                id: "t-local-2",
                title: "Improve environment switching UI",
                project: MockData.studio,
                location: .branch("main"),
                provider: .gemini,
                activity: .idle,
                updatedAt: MockData.ago(140),
                environmentID: localID,
                environmentLabel: "Jim’s MacBook Pro",
                isRemoteEnvironment: false,
                environmentMachineSymbol: "laptopcomputer"
            ),
        ]
        model.selectedEnvironmentID = localID
        return model
    }

    // MARK: - Helpers

    private func syntheticLocalEnvironmentItem() -> RemoteEnvironmentItem {
        let phase: RemoteEnvironmentPhase
        let error: String?
        let label: String
        let providers: Int
        let portString: String?

        switch serverStatus {
        case .starting, .connecting:
            phase = .connecting
            error = nil
            label = Host.current().localizedName ?? "This Mac"
            providers = 0
            portString = nil
        case .connected(let serverLabel, let count, let port):
            phase = .connected
            error = nil
            label = serverLabel
            providers = count
            portString = port.map { "http://127.0.0.1:\($0)" }
        case .reconnecting(let attempt, let message):
            phase = .reconnecting(attempt: attempt)
            error = message
            label = Host.current().localizedName ?? "This Mac"
            providers = 0
            portString = nil
        case .failed(let message):
            phase = .failed(message)
            error = message
            label = Host.current().localizedName ?? "This Mac"
            providers = 0
            portString = nil
        }

        return RemoteEnvironmentItem(
            id: "local-pending",
            label: label,
            serverLabel: label,
            url: portString,
            isLocal: true,
            machine: .laptop,
            phase: phase,
            serverVersion: nil,
            errorDetail: error,
            providerCount: providers,
            hasMissingCredentials: false
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
