import Foundation
import Observation

/// Sidebar-ready projection of a thread combining thread shell, project, environment, and provider data.
public struct SidebarThreadItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let projectId: String
    public let projectTitle: String
    public let title: String
    public let updatedAt: Date
    public let branch: String?
    public let worktreePath: String?
    public let host: String
    public let providerInstanceId: String
    public let providerDisplayName: String
    public let modelSlug: String
    public let modelDisplayName: String
    public let status: ShellThreadStatus
    public let isRunning: Bool
    public let isUnread: Bool
    public let needsApproval: Bool
    public let needsUserInput: Bool
    public let isPinned: Bool
    public let isSettled: Bool
    public let settledAt: Date?
    public let isSnoozed: Bool
    public let lastError: String?

    public init(
        id: String,
        projectId: String,
        projectTitle: String,
        title: String,
        updatedAt: Date,
        branch: String?,
        worktreePath: String?,
        host: String,
        providerInstanceId: String,
        providerDisplayName: String,
        modelSlug: String,
        modelDisplayName: String,
        status: ShellThreadStatus,
        isRunning: Bool,
        isUnread: Bool,
        needsApproval: Bool,
        needsUserInput: Bool,
        isPinned: Bool,
        isSettled: Bool,
        settledAt: Date? = nil,
        isSnoozed: Bool,
        lastError: String?
    ) {
        self.id = id
        self.projectId = projectId
        self.projectTitle = projectTitle
        self.title = title
        self.updatedAt = updatedAt
        self.branch = branch
        self.worktreePath = worktreePath
        self.host = host
        self.providerInstanceId = providerInstanceId
        self.providerDisplayName = providerDisplayName
        self.modelSlug = modelSlug
        self.modelDisplayName = modelDisplayName
        self.status = status
        self.isRunning = isRunning
        self.isUnread = isUnread
        self.needsApproval = needsApproval
        self.needsUserInput = needsUserInput
        self.isPinned = isPinned
        self.isSettled = isSettled
        self.settledAt = settledAt
        self.isSnoozed = isSnoozed
        self.lastError = lastError
    }
}

/// Observable store for a server environment's providers, projects, and thread list.
@MainActor
@Observable
public final class ThreadsStore {
    public let connection: ServerConnection

    public private(set) var connectionState: ConnectionState = .disconnected
    public private(set) var environment: ExecutionEnvironmentDescriptor?
    public private(set) var serverConfig: ServerConfig?
    public private(set) var serverSettings: ServerSettings?
    public private(set) var hostname: String?
    public private(set) var providers: [ServerProvider] = []
    public private(set) var projects: [ProjectShell] = []
    public private(set) var threads: [ThreadShell] = []
    public private(set) var archivedThreads: [ThreadShell] = []
    public private(set) var isSynchronized: Bool = false
    public private(set) var lastSequence: Int?
    public private(set) var lastError: String?

    private var stateMonitorTask: Task<Void, Never>?
    private var configSubscriptionTask: Task<Void, Never>?
    private var shellSubscriptionTask: Task<Void, Never>?

    public init(connection: ServerConnection) {
        self.connection = connection
    }

    // MARK: - Derived Sidebar Views

    public var projectsByID: [String: ProjectShell] {
        Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
    }

    public var listedThreads: [ThreadShell] {
        threads
            .filter(\.isListed)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public var sidebarItems: [SidebarThreadItem] {
        let projectMap = projectsByID
        let providerMap = Dictionary(uniqueKeysWithValues: providers.map { ($0.instanceId, $0) })
        let hostName = hostname ?? environment?.label ?? connection.httpBaseURL.host() ?? "localhost"
        let now = Date()

        return listedThreads.map { thread in
            let project = projectMap[thread.projectId]
            let provider = providerMap[thread.providerInstanceId]
            let model = provider?.models.first { $0.slug == thread.modelSelection.model }
            return SidebarThreadItem(
                id: thread.id,
                projectId: thread.projectId,
                projectTitle: project?.title ?? thread.projectId,
                title: thread.title,
                updatedAt: thread.updatedAt,
                branch: thread.branch,
                worktreePath: thread.worktreePath,
                host: hostName,
                providerInstanceId: thread.providerInstanceId,
                providerDisplayName: provider?.label ?? thread.providerInstanceId,
                modelSlug: thread.modelSelection.model,
                modelDisplayName: model?.displayName ?? thread.modelSelection.model,
                status: thread.status,
                isRunning: thread.isRunning,
                isUnread: thread.isUnread,
                needsApproval: thread.needsApproval,
                needsUserInput: thread.needsUserInput,
                isPinned: thread.isPinned,
                isSettled: thread.isSettled,
                settledAt: thread.settledAt,
                isSnoozed: thread.isSnoozed(asOf: now),
                lastError: thread.lastError
            )
        }
    }

    public func project(for thread: ThreadShell) -> ProjectShell? {
        projects.first { $0.id == thread.projectId }
    }

    public func provider(for instanceId: String) -> ServerProvider? {
        providers.first { $0.instanceId == instanceId }
    }

    public func model(for selection: ModelSelection) -> ServerProviderModel? {
        provider(for: selection.instanceId)?.models.first { $0.slug == selection.model }
    }

    // MARK: - Lifecycle

    /// Begins observing connection state and subscribing to config + shell updates across reconnects.
    public func start() {
        guard stateMonitorTask == nil else { return }
        stateMonitorTask = Task { [weak self] in
            guard let self else { return }
            let updates = await connection.stateUpdates()
            for await state in updates {
                guard !Task.isCancelled else { break }
                self.connectionState = state
                switch state {
                case .connected(let descriptor):
                    self.environment = descriptor
                    self.lastError = nil
                    self.startSubscriptions()
                case .disconnected:
                    self.stopSubscriptions()
                    self.isSynchronized = false
                case .reconnecting(_, let reason):
                    self.stopSubscriptions()
                    self.isSynchronized = false
                    self.lastError = reason
                case .failed(let reason):
                    self.stopSubscriptions()
                    self.isSynchronized = false
                    self.lastError = reason
                case .connecting:
                    break
                }
            }
        }
    }

    public func stop() {
        stateMonitorTask?.cancel()
        stateMonitorTask = nil
        stopSubscriptions()
    }

    private func startSubscriptions() {
        stopSubscriptions()

        configSubscriptionTask = Task { [weak self] in
            guard let self else { return }
            let stream: AsyncThrowingStream<ServerConfigStreamEvent, any Error> =
                connection.subscribe(
                    tag: RPCMethod.subscribeServerConfig,
                    payload: SubscribeServerConfigInput()
                )
            do {
                for try await event in stream {
                    guard !Task.isCancelled else { break }
                    self.apply(event)
                }
            } catch {
                if !Task.isCancelled {
                    self.lastError = error.localizedDescription
                }
            }
        }

        let resumeSequence = lastSequence
        shellSubscriptionTask = Task { [weak self] in
            guard let self else { return }
            let stream: AsyncThrowingStream<ShellStreamItem, any Error> =
                connection.subscribe(
                    tag: RPCMethod.orchestrationSubscribeShell,
                    payload: SubscribeShellInput(
                        afterSequence: resumeSequence,
                        requestCompletionMarker: true
                    )
                )
            do {
                for try await item in stream {
                    guard !Task.isCancelled else { break }
                    self.apply(item)
                }
            } catch {
                if !Task.isCancelled {
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    private func stopSubscriptions() {
        configSubscriptionTask?.cancel()
        configSubscriptionTask = nil
        shellSubscriptionTask?.cancel()
        shellSubscriptionTask = nil
    }

    // MARK: - Reducers

    internal func apply(_ event: ServerConfigStreamEvent) {
        switch event {
        case .snapshot(let config):
            serverConfig = config
            if let settings = config.settings {
                serverSettings = settings
            }
            environment = config.environment
            hostname = config.hostname
            providers = config.providers
        case .providerStatuses(let updatedProviders):
            providers = updatedProviders
        case .settingsUpdated(let settings):
            serverSettings = settings
        case .unknown:
            break
        }
    }

    public func updateServerSettings(_ settings: ServerSettings) {
        serverSettings = settings
    }

    internal func applyRefreshedProviders(_ updated: [ServerProvider]) {
        providers = updated
    }

    internal func apply(_ item: ShellStreamItem) {
        switch item {
        case .snapshot(let snapshot, let resolvedRoots):
            // Enrichment snapshots refresh project repositoryIdentity only and deliberately carry
            // empty threads/archivedThreads arrays — never overwrite threads from them.
            if resolvedRoots != nil {
                mergeEnrichedProjects(snapshot.projects)
                return
            }
            projects = snapshot.projects
            threads = snapshot.threads
            archivedThreads = snapshot.archivedThreads
            lastSequence = snapshot.snapshotSequence

        case .synchronized:
            isSynchronized = true

        case .snapshotRequired:
            lastSequence = nil
            isSynchronized = false

        case .projectUpdated(let sequence, let project):
            guard shouldApply(sequence: sequence) else { return }
            upsert(project, into: &projects)
            lastSequence = sequence

        case .projectRemoved(let sequence, let projectId):
            guard shouldApply(sequence: sequence) else { return }
            projects.removeAll { $0.id == projectId }
            lastSequence = sequence

        case .threadUpdated(let sequence, let location, let thread):
            guard shouldApply(sequence: sequence) else { return }
            switch location {
            case .active:
                upsert(thread, into: &threads)
                archivedThreads.removeAll { $0.id == thread.id }
            case .archive:
                upsert(thread, into: &archivedThreads)
                threads.removeAll { $0.id == thread.id }
            }
            lastSequence = sequence

        case .threadRemoved(let sequence, let location, let threadId):
            guard shouldApply(sequence: sequence) else { return }
            switch location {
            case .active:
                threads.removeAll { $0.id == threadId }
            case .archive:
                archivedThreads.removeAll { $0.id == threadId }
            }
            lastSequence = sequence

        case .unknown:
            break
        }
    }

    private func shouldApply(sequence: Int) -> Bool {
        guard let lastSequence else { return true }
        return sequence > lastSequence
    }

    private func mergeEnrichedProjects(_ enriched: [ProjectShell]) {
        for project in enriched {
            upsert(project, into: &projects)
        }
    }

    private func upsert<T: Identifiable>(_ item: T, into array: inout [T]) {
        if let index = array.firstIndex(where: { $0.id == item.id }) {
            array[index] = item
        } else {
            array.append(item)
        }
    }

    // MARK: - Actions

    @discardableResult
    public func createProject(
        title: String,
        workspaceRoot: String,
        createIfMissing: Bool = false,
        defaultModelSelection: ModelSelection? = nil
    ) async throws -> ProjectShell {
        let mutation = ProjectMutation.create(
            commandId: UUID().uuidString,
            projectId: UUID().uuidString,
            title: title,
            workspaceRoot: workspaceRoot,
            createWorkspaceRootIfMissing: createIfMissing,
            defaultModelSelection: defaultModelSelection
        )
        let project: ProjectShell = try await connection.call(tag: RPCMethod.projectsMutate, payload: mutation)
        upsert(project, into: &projects)
        return project
    }

    @discardableResult
    public func createThread(
        projectId: String,
        title: String = "New thread",
        modelSelection: ModelSelection,
        runtimeMode: RuntimeMode = .fullAccess,
        interactionMode: ProviderInteractionMode = .default,
        branch: String? = nil,
        worktreePath: String? = nil
    ) async throws -> String {
        let threadId = UUID().uuidString
        let command = OrchestrationCommand.createThread(
            commandId: UUID().uuidString,
            threadId: threadId,
            projectId: projectId,
            title: title,
            modelSelection: modelSelection,
            runtimeMode: runtimeMode,
            interactionMode: interactionMode,
            branch: branch,
            worktreePath: worktreePath
        )
        let _: DispatchCommandResult = try await connection.call(
            tag: RPCMethod.orchestrationDispatchCommand,
            payload: command
        )
        return threadId
    }

    @discardableResult
    public func launchThread(_ input: LaunchThreadInput) async throws -> LaunchThreadResult {
        try await connection.call(tag: RPCMethod.orchestrationLaunchThread, payload: input)
    }

    public func markVisited(threadId: String, visitedAt: Date? = nil, opened: Bool = true) async throws {
        let resolvedVisitedAt = visitedAt ?? threads.first(where: { $0.id == threadId })?.updatedAt ?? Date()
        let _: DispatchCommandResult = try await connection.call(
            tag: RPCMethod.orchestrationDispatchCommand,
            payload: OrchestrationCommand.visitThread(
                threadId: threadId,
                visitedAt: resolvedVisitedAt,
                opened: opened
            )
        )
    }

    public func markUnread(threadId: String) async throws {
        let _: DispatchCommandResult = try await connection.call(
            tag: RPCMethod.orchestrationDispatchCommand,
            payload: OrchestrationCommand.markThreadUnread(threadId: threadId)
        )
    }

    public func archiveThread(threadId: String) async throws {
        let _: DispatchCommandResult = try await connection.call(
            tag: RPCMethod.orchestrationDispatchCommand,
            payload: OrchestrationCommand.archiveThread(threadId: threadId)
        )
    }

    public func deleteThread(threadId: String) async throws {
        let _: DispatchCommandResult = try await connection.call(
            tag: RPCMethod.orchestrationDispatchCommand,
            payload: OrchestrationCommand.deleteThread(threadId: threadId)
        )
    }

    public func settleThread(threadId: String) async throws {
        let _: DispatchCommandResult = try await connection.call(
            tag: RPCMethod.orchestrationDispatchCommand,
            payload: OrchestrationCommand.settleThread(threadId: threadId)
        )
    }

    public func unsettleThread(threadId: String) async throws {
        let _: DispatchCommandResult = try await connection.call(
            tag: RPCMethod.orchestrationDispatchCommand,
            payload: OrchestrationCommand.unsettleThread(threadId: threadId)
        )
    }

    @discardableResult
    public func refreshProviders(
        instanceId: String? = nil,
        cwd: String? = nil,
        fresh: Bool? = true,
        refreshModels: Bool? = nil
    ) async throws -> [ServerProvider] {
        let result: ServerRefreshProvidersResult = try await connection.call(
            tag: RPCMethod.serverRefreshProviders,
            payload: ServerRefreshProvidersInput(
                instanceId: instanceId,
                cwd: cwd,
                fresh: fresh,
                refreshModels: refreshModels
            )
        )
        providers = result.providers
        return result.providers
    }

    @discardableResult
    public func updateServerWithProgress(
        targetVersion: String,
        targetDatabaseMigration: Int? = nil,
        stageOnly: Bool = false,
        onProgress: @escaping @Sendable (ServerSelfUpdateProgressStage) -> Void
    ) async throws -> ServerSelfUpdateResult {
        let input = ServerSelfUpdateInput(
            targetVersion: targetVersion,
            targetDatabaseMigration: targetDatabaseMigration,
            stageOnly: stageOnly ? true : nil
        )
        let supportsProgress =
            environment?.capabilities.serverSelfUpdateProgress == true
            || serverConfig?.environment.capabilities.serverSelfUpdateProgress == true

        if supportsProgress {
            let stream: AsyncThrowingStream<ServerSelfUpdateProgressEvent, any Error> =
                connection.subscribe(
                    tag: RPCMethod.serverUpdateServerWithProgress,
                    payload: input
                )
            var finalResult: ServerSelfUpdateResult?
            for try await event in stream {
                switch event {
                case .progress(let stage):
                    onProgress(stage)
                case .complete(let result):
                    finalResult = result
                }
            }
            guard let finalResult else {
                throw RPCError.protocolError(
                    "Server update stream completed without a final result."
                )
            }
            return finalResult
        }

        return try await connection.call(
            tag: RPCMethod.serverUpdateServer,
            payload: input
        )
    }
}
