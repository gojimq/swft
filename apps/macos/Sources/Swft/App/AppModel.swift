import AppKit
import Foundation
import Observation
import SwftDesign
import SwftKit
import SwiftUI

/// UI state and SwftKit orchestration coordinator for the main window.
@MainActor
@Observable
final class AppModel {
    // MARK: - Navigation & UI Controls

    var destination: SidebarDestination = .home {
        didSet {
            guard oldValue != destination else { return }
            modelPicker = nil
            isProjectPickerOpen = false
            // A send belongs to the screen it was made on; a screen opened later must never replay it.
            latestThreadSend = nil
        }
    }
    /// The open model picker, or nil when it is closed.
    var modelPicker: ModelPickerSession?
    /// Whether the Home composer's floating project picker is open.
    var isProjectPickerOpen = false
    /// Project IDs currently awaiting a `project.delete` RPC response.
    var deletingProjectIDs: Set<String> = []
    var sidebarVisible = true
    var filter: ThreadFilter = .all
    var isSettledExpanded: Bool = false {
        didSet {
            defaults?.set(isSettledExpanded, forKey: SettledThreadsLogic.expandedDefaultsKey)
        }
    }
    var composerText = ""
    /// Files and images staged in the composer; each uploads to the composer's environment as soon as it is attached.
    let composerAttachments = ComposerAttachments()
    var composerMode: ComposerMode = .chat
    var selectedProjectID: String? {
        didSet { if selectedProjectID != nil { isNoProjectSelected = false } }
    }
    var isNoProjectSelected = false
    var selectedModelID: String?
    var selectedReasoningChoiceId: String?
    var now: Date
    var actionError: String?
    /// Work folds the reader has opened, by fold id (ids are unique per turn, so this spans threads).
    var expandedWorkFolds: Set<String> = []
    /// Subagent group cards and inline native-subagent detail drawers opened by the reader.
    var expandedSubagentRows: Set<String> = []
    /// Settings screen coordinator (preferences, server settings RPCs, provider setup streams).
    let settings = SettingsController()
    /// Hook invoked when the model picker's signed-out action deep-links to provider settings.
    var openProviderSettingsAction: ((String) -> Void)?
    /// Home → new thread staging (composer docking, hand-off); see `Motion/NewThread`.
    let newThread = NewThreadLauncher()
    /// Release checks and the remote-first, this-Mac-last update run behind Home's update pill.
    let updates: UpdateCoordinator
    /// Most recent send dispatched inside an existing thread, observed by `ThreadView` to launch send flight.
    var latestThreadSend: ThreadSendEvent?
    /// Send event ID whose live dispatch failed, so `ThreadView` can cancel its flight overlay immediately.
    var failedThreadSendID: UUID?

    // MARK: - Usage Pills

    /// Driver group IDs pinned in the sidebar usage footer (`nil` = automatic first 3 healthy/expired).
    var selectedUsagePillIDs: [String]?
    /// Last-good usage limits keyed by `"\(environmentID):\(instanceId)"`.
    var lastGoodUsageLimits: [String: CachedUsageLimits] = [:]
    /// Cache keys currently undergoing an explicit provider refresh from a usage pill.
    var renewingUsageProviderKeys: Set<String> = []
    /// Renewal errors keyed by `"\(environmentID):\(instanceId)"`.
    var usageRenewalErrors: [String: String] = [:]
    /// Provider instance ID requested via pill click, for deep-linking Settings → Providers.
    var requestedSettingsProviderID: String?
    /// Optional hook for Settings integration to deep-link straight to a specific provider row.
    @ObservationIgnored var onOpenProviderSettings: ((String) -> Void)?
    /// Optional preview-only override to pin a usage breakdown popover open for screenshots/tests.
    var previewUsagePopoverGroupID: String?

    // MARK: - Remote Environments

    var selectedEnvironmentID: String?
    var activeThreadEnvironmentID: String?
    let environmentRegistry: EnvironmentRegistry
    let tunnelController: CloudflareTunnelController
    var mockEnvironments: [RemoteEnvironmentItem]?
    var mockProjectsByEnvironment: [String: [ProjectRef]] = [:]
    var mockModelsByEnvironment: [String: [ModelOption]] = [:]
    var mockThreadsOverride: [ThreadSummary]?

    // MARK: - Mode & Live SwftKit Backing

    let isMock: Bool

    private var serverProcess: ServerProcess?
    private var connection: ServerConnection?
    private(set) var threadsStore: ThreadsStore?
    private(set) var activeThreadStore: ThreadStore?
    private var serverPort: Int?
    private var launchPhase: LaunchPhase = .idle
    private var isSubmitting = false
    private var optimisticApprovals: [String: ApprovalItem.Status] = [:]
    /// Navigation breadcrumbs & instant placeholders for opened subagent child threads.
    private var subagentNavigationContexts: [ThreadSummary.ID: SubagentNavigationContext] = [:]

    private struct SubagentNavigationContext: Equatable {
        let parentLink: SubagentParentLink
        let placeholderSummary: ThreadSummary
    }
    /// Messages sent into the open thread, shown at once and kept under the same row id after the server echoes them.
    private var pendingUserMessages: [ThreadSummary.ID: [PendingUserMessage]] = [:]
    private var optimisticSettlements: [ThreadSummary.ID: OptimisticSettlement] = [:]
    private var workspaceAvailabilityRevision = 0
    @ObservationIgnored var localWorkspaceDirectoryExists: (String) -> Bool = ProjectDeletionLogic.localDirectoryExists
    @ObservationIgnored private var localWorkspaceAvailabilityCache: [String: Bool] = [:]
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var recentProjections = RecentProjections()
    @ObservationIgnored private var imageLoaders: [String: SwftImageLoader] = [:]
    @ObservationIgnored private var cachedLiveDetail: CachedLiveThreadDetail?

    private struct CachedLiveThreadDetail {
        let storeID: ObjectIdentifier
        let projectionVersion: UInt64
        let summary: ThreadSummary
        let providers: [ServerProvider]
        let parentLink: SubagentParentLink?
        let pending: [PendingUserMessage]
        let approvals: [String: ApprovalItem.Status]
        let detail: ThreadDetailState
    }

    private enum LaunchPhase: Equatable {
        case idle
        case starting
        case running
        case failed(String)
    }

    @ObservationIgnored private var startupTask: Task<Void, Never>?
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private var visitTimerTask: Task<Void, Never>?
    @ObservationIgnored private var visitPolicy = ThreadVisitPolicy()
    @ObservationIgnored private var isShuttingDown = false
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var isObservingVisits = false

    // MARK: - Mock Backing (Previews & Screenshot Flags Only)

    private struct MockBacking {
        var projects: [ProjectRef]
        var threads: [ThreadSummary]
        var account: AccountSummary
        var home: HomeState
        var models: [ModelOption]
        var harnesses: [PickerHarness]
        var usageProviders: [UsageProviderEntry]
        var details: [ThreadSummary.ID: ThreadDetailState]
        var defaultContextLabel: String?
    }

    private var mockBacking: MockBacking?

    // MARK: - Initializers & Factories

    private init(
        isMock: Bool,
        now: Date,
        mockBacking: MockBacking? = nil,
        defaults: UserDefaults? = nil,
        updateServices: UpdateServices? = nil,
        useInMemoryRegistry: Bool? = nil
    ) {
        self.isMock = isMock
        self.now = now
        self.mockBacking = mockBacking
        self.defaults = defaults
        self.isSettledExpanded = defaults?.bool(forKey: SettledThreadsLogic.expandedDefaultsKey) ?? false
        let baseDir = Self.resolveBaseDirectory()
        let ephemeralRegistry = useInMemoryRegistry ?? isMock
        if ephemeralRegistry {
            self.environmentRegistry = EnvironmentRegistry(
                credentialStore: InMemoryCredentialStore(),
                recordStore: InMemoryEnvironmentRecordStore()
            )
            self.tunnelController = CloudflareTunnelController(
                baseDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("swft-mock-tunnel", isDirectory: true),
                localPort: 3773,
                resolveBinary: { nil }
            )
        } else {
            self.environmentRegistry = EnvironmentRegistry(
                credentialStore: KeychainCredentialStore(
                    service: KeychainCredentialStore.serviceName(forBaseDirectory: baseDir)
                ),
                recordStore: FileEnvironmentRecordStore(baseDirectory: baseDir)
            )
            self.tunnelController = CloudflareTunnelController(baseDirectory: baseDir)
        }
        self.updates = UpdateCoordinator(
            services: updateServices ?? Self.makeUpdateServices(isMock: isMock, registry: environmentRegistry)
        )
        self.settings.attach(to: self)
        self.composerAttachments.onError = { [weak self] message in
            self?.actionError = message
        }
        self.openProviderSettingsAction = { [weak self] harnessID in
            self?.openSettings(section: .providers, providerID: harnessID)
        }
        self.onOpenProviderSettings = { [weak self] instanceID in
            self?.openSettings(section: .providers, providerID: instanceID)
        }
        self.settings.applyAppearance()
        if !ephemeralRegistry {
            self.selectedUsagePillIDs = UsagePillsStore.loadSelection()
            self.lastGoodUsageLimits = UsagePillsStore.loadLastGoodLimits()
        }
    }

    static func makeForLaunch() -> AppModel {
        if shouldUseMockMode() {
            return .mock()
        }
        return .live()
    }

    static func live() -> AppModel {
        AppModel(isMock: false, now: Date(), defaults: .standard)
    }

    /// Ephemeral live-mode `AppModel` for unit tests (never touches Keychain, UserDefaults, or `~/.t3/userdata`).
    static func testingLive(localStore: ThreadsStore? = nil) -> AppModel {
        let model = AppModel(
            isMock: false,
            now: Date(),
            defaults: nil,
            updateServices: .inert,
            useInMemoryRegistry: true
        )
        model.threadsStore = localStore
        if localStore != nil {
            model.launchPhase = .running
        }
        return model
    }

    static func mock(defaults: UserDefaults? = nil, updateServices: UpdateServices? = nil) -> AppModel {
        var mockDetails: [ThreadSummary.ID: ThreadDetailState] = [
            MockData.threadDetail.summary.id: MockData.threadDetail,
            MockData.approvalDetail.summary.id: MockData.approvalDetail,
            MockData.attachmentsDetail.summary.id: MockData.attachmentsDetail,
            MockData.subagentsDetail.summary.id: MockData.subagentsDetail,
        ]
        for childDetail in MockData.subagentChildDetails {
            mockDetails[childDetail.summary.id] = childDetail
        }
        let backing = MockBacking(
            projects: MockData.projects,
            threads: MockData.threads,
            account: MockData.sidebar.account,
            home: MockData.home,
            models: MockData.models,
            harnesses: MockData.harnesses,
            usageProviders: MockData.usageProviders,
            details: mockDetails,
            defaultContextLabel: "Swft · main"
        )
        MockData.seedImageCache()
        let model = AppModel(isMock: true, now: MockData.now, mockBacking: backing, defaults: defaults, updateServices: updateServices)
        model.selectedProjectID = MockData.swft.id
        model.selectedModelID = MockData.models.first?.id
        model.selectedReasoningChoiceId = MockData.models.first?.defaultReasoningChoiceId
        // `-SwftScreen thread` opens straight into the mock thread (used for screenshots).
        if UserDefaults.standard.string(forKey: "SwftScreen") == "thread" {
            model.destination = .thread(MockData.threadDetail.summary.id)
        }
        if UserDefaults.standard.string(forKey: "SwftScreen") == "settings" {
            model.destination = .settings
        }
        // `-SwftSettled expanded` opens the Settled shelf in mock mode (used for screenshots).
        if defaults == nil, UserDefaults.standard.string(forKey: "SwftSettled") == "expanded" {
            model.isSettledExpanded = true
        }
        // `-SwftPicker open|<query>` opens the model picker (optionally searching), for screenshots.
        if let picker = UserDefaults.standard.string(forKey: "SwftPicker") {
            model.toggleModelPicker()
            if picker != "open" { model.modelPicker?.setQuery(picker) }
        }
        // `-SwftUsagePopover <driverGroupID>` opens a usage pill breakdown card for screenshots.
        if let popover = UserDefaults.standard.string(forKey: "SwftUsagePopover"), !popover.isEmpty {
            model.previewUsagePopoverGroupID = popover
        }
        return model
    }

    /// Mock mode is active only for SwiftUI previews and explicit screenshot flags
    /// (`-SwftMock`, `-SwftScreen`, `-SwftAppearance`). Passing `-SwftMock NO` forces live mode.
    static func shouldUseMockMode(
        arguments: [String] = CommandLine.arguments,
        defaults: UserDefaults = .standard
    ) -> Bool {
        if let mockIndex = arguments.firstIndex(of: "-SwftMock") {
            let nextIndex = arguments.index(after: mockIndex)
            if nextIndex < arguments.endIndex {
                let next = arguments[nextIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if next == "no" || next == "0" || next == "false" {
                    return false
                }
            }
            return true
        }
        if defaults.bool(forKey: "SwftMock") {
            return true
        }
        if defaults.string(forKey: "SwftScreen") != nil || defaults.string(forKey: "SwftAppearance") != nil {
            return true
        }
        return false
    }

    // MARK: - Server Lifecycle

    func startIfNeeded() {
        guard !isMock, !hasStarted else { return }
        hasStarted = true
        startClockTick()
        startVisitObservation()
        connectToLocalServer()
        startRemoteConnections()
        updates.start()
    }

    /// Opens Settings → About so a menu-bar check always shows its result, then checks.
    func checkForUpdates(userInitiated: Bool) {
        if userInitiated { openSettings(section: .about) }
        Task { await updates.checkForUpdates(userInitiated: userInitiated) }
    }

    private static func makeUpdateServices(isMock: Bool, registry: EnvironmentRegistry) -> UpdateServices {
        let appVersion = SettingsController.bundleAppVersion
        if let demo = DemoUpdateWorld.fromEnvironment(localVersion: appVersion) {
            return demo.services
        }
        if isMock { return .inert }
        return .live(registry: registry, appVersion: { appVersion })
    }

    func retryConnection() {
        guard !isMock else { return }
        actionError = nil
        startupTask?.cancel()
        startupTask = Task { [weak self] in
            await self?.restartServerAndConnect()
        }
    }

    func refreshProviders() {
        guard !isMock, let store = resolvedActiveStore(localStore: threadsStore) else { return }
        Task {
            do {
                _ = try await store.refreshProviders(fresh: true)
            } catch {
                self.actionError = error.localizedDescription
            }
        }
    }

    func shutdown() async {
        isShuttingDown = true
        updates.stop()
        settings.stopProviderSubscriptions()
        startupTask?.cancel()
        startupTask = nil
        clockTask?.cancel()
        clockTask = nil
        visitTimerTask?.cancel()
        visitTimerTask = nil

        activeThreadStore?.stop()
        activeThreadStore = nil
        threadsStore?.stop()
        threadsStore = nil

        await shutdownRemoteConnections()

        if let connection {
            await connection.disconnect()
        }
        self.connection = nil

        if let serverProcess {
            await serverProcess.stop()
        }
        self.serverProcess = nil
    }

    func terminateServerImmediately() {
        tunnelController.terminateImmediately()
        serverProcess?.terminateImmediately()
    }

    private func connectToLocalServer() {
        startupTask?.cancel()
        startupTask = Task { [weak self] in
            await self?.bootAndConnect()
        }
    }

    private func restartServerAndConnect() async {
        activeThreadStore?.stop()
        activeThreadStore = nil
        threadsStore?.stop()
        threadsStore = nil
        await unregisterLocalEnvironment()
        if let connection {
            await connection.disconnect()
        }
        self.connection = nil
        if let serverProcess {
            await serverProcess.stop()
        }
        self.serverProcess = nil
        self.serverPort = nil
        await bootAndConnect()
    }

    private func bootAndConnect() async {
        guard !isShuttingDown else { return }
        launchPhase = .starting
        actionError = nil

        let baseDir = Self.resolveBaseDirectory()
        let process = ServerProcess(
            configuration: ServerLaunchConfiguration(
                baseDirectory: baseDir,
                readinessTimeout: .seconds(25)
            )
        )
        self.serverProcess = process

        let endpoint: ServerEndpoint
        do {
            endpoint = try await process.start()
        } catch is CancellationError {
            await process.stop()
            return
        } catch {
            self.serverProcess = nil
            self.launchPhase = .failed(error.localizedDescription)
            return
        }

        guard !Task.isCancelled, !isShuttingDown else {
            await process.stop()
            return
        }

        self.serverPort = endpoint.port
        let conn = ServerConnection(
            httpBaseURL: endpoint.httpBaseURL,
            credential: .bootstrapToken(endpoint.bootstrapToken),
            clientLabel: "Swft"
        )
        let store = ThreadsStore(connection: conn)
        self.connection = conn
        self.threadsStore = store
        self.launchPhase = .running
        registerLocalEnvironment(endpoint: endpoint, connection: conn, store: store)

        store.start()
        do {
            _ = try await conn.connect()
        } catch is CancellationError {
            return
        } catch {
            // `ServerConnection` transitions to `.failed` on error, which `serverStatus` surfaces.
        }

        // If the user already navigated to a thread before connect finished, attach its store now.
        if case .thread(let id) = destination, activeThreadStore?.threadId != id {
            let ownerConn = owningEnvironment(forThreadID: id)?.connection ?? conn
            attachThreadStore(for: id, on: ownerConn, initialProjection: nil)
        }
    }

    private static func resolveBaseDirectory() -> URL {
        if let customHome = ProcessInfo.processInfo.environment["SWFT_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !customHome.isEmpty
        {
            return URL(fileURLWithPath: (customHome as NSString).expandingTildeInPath, isDirectory: true)
        }
        return ServerLaunchConfiguration.defaultBaseDirectory
    }

    private func startClockTick() {
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                self?.now = Date()
            }
        }
    }

    // MARK: - Derived View State

    var activeConnection: ServerConnection? { connection }
    var activeThreadsStore: ThreadsStore? { threadsStore }
    var resolvedDataDirectory: URL { Self.resolveBaseDirectory() }

    var serverStatus: ServerStatus {
        if isMock {
            return .connected(label: "Local server", providerCount: 3, port: nil)
        }
        switch launchPhase {
        case .idle, .starting:
            return .starting
        case .failed(let message):
            return .failed(message: message)
        case .running:
            guard let threadsStore else { return .connecting }
            switch threadsStore.connectionState {
            case .disconnected, .connecting:
                return .connecting
            case .connected(let descriptor):
                let readyCount = threadsStore.providers.filter { $0.enabled && $0.installed && $0.status != .disabled }.count
                return .connected(label: descriptor.label, providerCount: readyCount, port: serverPort)
            case .reconnecting(let attempt, let reason):
                return .reconnecting(attempt: attempt, message: reason)
            case .failed(let reason):
                return .failed(message: reason)
            }
        }
    }

    var projects: [ProjectRef] {
        _ = workspaceAvailabilityRevision
        if let mockBacking {
            return resolvedMockProjects(defaultProjects: mockBacking.projects)
        }
        guard let store = resolvedComposerStore(localStore: threadsStore) else { return [] }
        let envID = activeComposerEnvironmentID ?? store.environment?.environmentId
        let isLocalEnv = activeComposerEnvironment?.isLocal ?? true
        return store.projects
            .filter { $0.archivedAt == nil && $0.deletedAt == nil && !store.isScratchProject($0) }
            .map { project in
                var ref = envID.map { SwftAdapters.projectRef(from: project, environmentID: $0) }
                    ?? SwftAdapters.projectRef(from: project)
                if isLocalEnv {
                    ref.isWorkspaceMissing = ProjectDeletionLogic.isWorkspaceMissing(
                        workspaceRoot: project.workspaceRoot,
                        isLocalEnvironment: true,
                        directoryExists: cachedLocalWorkspaceExists
                    )
                }
                return ref
            }
    }

    var selectedProject: ProjectRef? {
        NoProjectLogic.resolveSelectedProject(
            projects: projects,
            selectedProjectID: selectedProjectID,
            isNoProjectSelected: isNoProjectSelected
        )
    }

    /// Re-checks local project workspace folders on disk and notifies views if availability changed.
    func refreshLocalProjectAvailability() {
        guard !isMock else { return }
        guard let localStore = environmentRegistry.localEnvironment?.threadsStore ?? threadsStore else { return }
        var nextCache: [String: Bool] = [:]
        for project in localStore.projects where project.archivedAt == nil && project.deletedAt == nil {
            let trimmed = project.workspaceRoot.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            nextCache[trimmed] = localWorkspaceDirectoryExists(trimmed)
        }
        let changed = nextCache != localWorkspaceAvailabilityCache
        localWorkspaceAvailabilityCache = nextCache
        if changed {
            workspaceAvailabilityRevision &+= 1
        }
    }

    private func cachedLocalWorkspaceExists(_ path: String) -> Bool {
        if let cached = localWorkspaceAvailabilityCache[path] {
            return cached
        }
        let exists = localWorkspaceDirectoryExists(path)
        localWorkspaceAvailabilityCache[path] = exists
        return exists
    }

    var availableModels: [ModelOption] {
        if let mockBacking {
            return resolvedMockModels(defaultModels: mockBacking.models)
        }
        guard let store = resolvedActiveStore(localStore: threadsStore) else { return [] }
        return SwftAdapters.modelOptions(from: store.providers)
    }

    var pickerCatalog: PickerCatalog {
        if let mockBacking {
            return PickerCatalog(
                harnesses: mockBacking.harnesses,
                models: resolvedMockModels(defaultModels: mockBacking.models)
            )
        }
        guard let store = resolvedActiveStore(localStore: threadsStore) else { return .empty }
        return SwftAdapters.pickerCatalog(from: store.providers)
    }

    // MARK: - Usage Pills

    var usageEnvironmentID: String {
        if isMock { return "mock" }
        let activeStore = resolvedActiveStore(localStore: threadsStore) ?? threadsStore
        return activeStore?.environment?.environmentId ?? "default"
    }

    var usageProviders: [UsageProviderEntry] {
        if let mockBacking {
            return mockBacking.usageProviders
        }
        guard let activeStore = resolvedActiveStore(localStore: threadsStore) ?? threadsStore else { return [] }
        return SwftAdapters.usageProviders(from: activeStore.providers)
    }

    var usageCachedInstanceIDs: Set<String> {
        UsagePillsStore.cachedInstanceIDs(in: lastGoodUsageLimits, environmentID: usageEnvironmentID)
    }

    var usagePillCandidateGroups: [UsagePillGroup] {
        UsagePillsLogic.candidateGroups(from: usageProviders)
    }

    var visibleUsagePillGroups: [UsagePillGroup] {
        UsagePillsLogic.visibleGroups(
            from: usageProviders,
            selected: selectedUsagePillIDs,
            cachedInstanceIDs: usageCachedInstanceIDs
        )
    }

    func cachedUsageLimits(for instanceId: String) -> CachedUsageLimits? {
        let key = UsagePillsStore.cacheKey(environmentID: usageEnvironmentID, instanceID: instanceId)
        return lastGoodUsageLimits[key]
    }

    func isRenewingUsageProvider(_ instanceId: String) -> Bool {
        let key = UsagePillsStore.cacheKey(environmentID: usageEnvironmentID, instanceID: instanceId)
        return renewingUsageProviderKeys.contains(key)
    }

    func usageRenewalError(for instanceId: String) -> String? {
        let key = UsagePillsStore.cacheKey(environmentID: usageEnvironmentID, instanceID: instanceId)
        return usageRenewalErrors[key]
    }

    func toggleUsagePill(groupID: String, isOn: Bool) {
        let next = UsagePillsLogic.toggleSelection(
            entries: usageProviders,
            selected: selectedUsagePillIDs,
            groupID: groupID,
            isOn: isOn,
            cachedInstanceIDs: usageCachedInstanceIDs
        )
        selectedUsagePillIDs = next
        if !isMock {
            UsagePillsStore.saveSelection(next)
        }
    }

    func recordHealthyUsageLimitsIfNeeded() {
        let entries = usageProviders
        if !isMock, let selected = selectedUsagePillIDs, !entries.isEmpty,
           let migrated = UsagePillsLogic.migrateSelection(selected, entries: entries),
           migrated != selected
        {
            selectedUsagePillIDs = migrated
            UsagePillsStore.saveSelection(migrated)
        }
        if let updated = UsagePillsStore.mergedLastGoodLimits(
            lastGoodUsageLimits,
            environmentID: usageEnvironmentID,
            entries: entries
        ) {
            lastGoodUsageLimits = updated
            if !isMock {
                UsagePillsStore.saveLastGoodLimits(updated)
            }
        }
    }

    func openProviderSettings(instanceId: String) {
        requestedSettingsProviderID = instanceId
        destination = .settings
        onOpenProviderSettings?(instanceId)
    }

    func refreshUsageProviders(instanceIds: [String]) {
        let envID = usageEnvironmentID
        for instanceId in instanceIds {
            let key = UsagePillsStore.cacheKey(environmentID: envID, instanceID: instanceId)
            guard !renewingUsageProviderKeys.contains(key) else { continue }
            renewingUsageProviderKeys.insert(key)
            usageRenewalErrors.removeValue(forKey: key)

            if isMock {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(350))
                    self?.renewingUsageProviderKeys.remove(key)
                }
                continue
            }

            guard let activeStore = resolvedActiveStore(localStore: threadsStore) ?? threadsStore else {
                renewingUsageProviderKeys.remove(key)
                continue
            }
            Task { @MainActor [weak self] in
                do {
                    _ = try await activeStore.refreshProviders(
                        instanceId: instanceId,
                        fresh: true,
                        refreshModels: true
                    )
                    self?.usageRenewalErrors.removeValue(forKey: key)
                } catch {
                    self?.usageRenewalErrors[key] = error.localizedDescription
                }
                self?.renewingUsageProviderKeys.remove(key)
            }
        }
    }

    var selectedModel: ModelOption? {
        let options = availableModels
        if let selectedModelID, let match = options.first(where: { $0.id == selectedModelID }) {
            return match
        }
        let activeStore = resolvedActiveStore(localStore: threadsStore)
        if !isMock,
           let thread = activeThreadStore?.thread,
           let activeStore
        {
            let providersByID = Dictionary(uniqueKeysWithValues: activeStore.providers.map { ($0.instanceId, $0) })
            return options.first(where: {
                $0.instanceId == thread.modelSelection.instanceId && $0.slug == thread.modelSelection.model
            }) ?? SwftAdapters.fallbackModelOption(for: thread.modelSelection, providersByID: providersByID)
        }
        let projectDefault: ModelSelection?
        if let projectID = selectedProject?.id {
            projectDefault = resolvedComposerStore(localStore: threadsStore)?.projectsByID[projectID]?.defaultModelSelection
        } else {
            projectDefault = nil
        }
        return SwftAdapters.preferredDefaultModel(
            from: options,
            projectDefault: projectDefault ?? settings.serverSettings?.defaultModelSelection
        )
    }

    var selectedReasoningChoice: ReasoningChoice? {
        guard let model = selectedModel, !model.reasoningChoices.isEmpty else { return nil }
        if let id = selectedReasoningChoiceId,
           let match = model.reasoningChoices.first(where: { $0.id == id })
        {
            return match
        }
        if selectedModelID == nil,
           let serverDefault = settings.serverSettings?.defaultModelSelection,
           serverDefault.instanceId == model.instanceId,
           serverDefault.model == model.slug,
           let configured = SwftAdapters.reasoningChoiceId(from: serverDefault, for: model),
           let match = model.reasoningChoices.first(where: { $0.id == configured })
        {
            return match
        }
        if let def = model.defaultReasoningChoiceId,
           let match = model.reasoningChoices.first(where: { $0.id == def })
        {
            return match
        }
        return model.reasoningChoices.first
    }

    var sidebar: SidebarState {
        if let mockBacking {
            let threads = mockThreadsOverride ?? mockBacking.threads
            return SidebarState(threads: threads, filter: filter, account: mockBacking.account)
        }
        let threads = SettledThreadsLogic.applyOptimisticSettlements(
            to: aggregatedSidebarThreads(fallbackLocalStore: threadsStore),
            overrides: optimisticSettlements
        )
        return SidebarState(threads: threads, filter: filter, account: liveAccountSummary)
    }

    var home: HomeState {
        if let mockBacking {
            return mockBacking.home
        }
        return HomeState(
            greetingName: Self.localUserFirstName(),
            suggestions: MockData.defaultSuggestions
        )
    }

    /// The composer's busy state alone, for views that must not re-render on every keystroke via `composer`.
    var isComposerBusy: Bool {
        if isMock { return false }
        if selectedThreadID != nil { return isSubmitting || (activeThreadStore?.isRunning == true) }
        return isSubmitting
    }

    var composer: ComposerState {
        let contextLabel = resolvedComposerContextLabel(mockDefaultContextLabel: mockBacking?.defaultContextLabel)
        let isBusy = isComposerBusy

        return ComposerState(
            text: composerText,
            mode: composerMode,
            model: selectedModel,
            selectedReasoningChoiceId: selectedReasoningChoice?.id,
            availableModels: availableModels,
            contextLabel: contextLabel,
            isBusy: isBusy
        )
    }

    private var settledPartition: SettledPartition {
        SettledThreadsLogic.partition(
            threads: sidebar.threads,
            filter: filter,
            isSettledExpanded: isSettledExpanded,
            selectedThreadID: selectedThreadID
        )
    }

    var visibleThreads: [ThreadSummary] {
        settledPartition.active
    }

    var settledThreads: [ThreadSummary] {
        settledPartition.settled
    }

    var visibleSettledThreads: [ThreadSummary] {
        settledPartition.visibleSettled
    }

    var selectedThreadID: ThreadSummary.ID? {
        if case .thread(let id) = destination { id } else { nil }
    }

    var readyProviderNames: [String] {
        if isMock { return ["Claude", "Codex", "Cursor"] }
        return (resolvedActiveStore(localStore: threadsStore)?.providers ?? [])
            .filter { $0.enabled && $0.installed && $0.status != .disabled }
            .map(\.label)
    }

    var knownEnvironmentIDs: Set<String> {
        if isMock {
            return Set(remoteEnvironments.map(\.id))
        }
        return Set(environmentRegistry.entries.map(\.id))
    }

    func parentThreadLink(for id: ThreadSummary.ID) -> SubagentParentLink? {
        if let recorded = subagentNavigationContexts[id]?.parentLink {
            return recorded
        }
        if let mockDetail = mockBacking?.details[id], let parentLink = mockDetail.parentLink {
            return parentLink
        }
        if !isMock {
            if let activeThreadStore,
               activeThreadStore.threadId == id,
               let thread = activeThreadStore.thread,
               thread.lineage.relationshipToParent == "subagent",
               let parentID = thread.lineage.parentThreadId
            {
                let envID = activeThreadEnvironmentID ?? owningEnvironment(forThreadID: id)?.id
                let title = resolveThreadTitle(for: parentID, preferredEnvironmentID: envID) ?? "Parent thread"
                return SubagentParentLink(threadID: parentID, title: title, environmentID: envID)
            }
            let owner = owningEnvironment(forThreadID: id)
            let store = owner?.threadsStore ?? threadsStore
            if let shell = store?.threads.first(where: { $0.id == id }) ?? store?.archivedThreads.first(where: { $0.id == id }),
               shell.lineage.relationshipToParent == "subagent",
               let parentID = shell.lineage.parentThreadId
            {
                let envID = owner?.id ?? activeThreadEnvironmentID
                let title = resolveThreadTitle(for: parentID, preferredEnvironmentID: envID) ?? "Parent thread"
                return SubagentParentLink(threadID: parentID, title: title, environmentID: envID)
            }
        }
        return nil
    }

    private func resolveThreadTitle(for id: ThreadSummary.ID, preferredEnvironmentID: String?) -> String? {
        if let match = sidebar.threads.first(where: { $0.id == id }) {
            return match.title
        }
        if let mockDetail = mockBacking?.details[id] {
            return mockDetail.summary.title
        }
        if let preferredEnvironmentID,
           let env = environmentRegistry.environment(id: preferredEnvironmentID),
           let shell = env.threadsStore.threads.first(where: { $0.id == id }) ?? env.threadsStore.archivedThreads.first(where: { $0.id == id })
        {
            return shell.title
        }
        if let shell = threadsStore?.threads.first(where: { $0.id == id }) ?? threadsStore?.archivedThreads.first(where: { $0.id == id }) {
            return shell.title
        }
        if let cached = recentProjections.projection(for: id) {
            return cached.thread.title
        }
        return subagentNavigationContexts[id]?.placeholderSummary.title
    }

    func threadSummary(for id: ThreadSummary.ID) -> ThreadSummary? {
        if let match = sidebar.threads.first(where: { $0.id == id }) {
            return match
        }
        if let mockDetail = mockBacking?.details[id] {
            return mockDetail.summary
        }
        if !isMock,
           let activeThreadStore,
           activeThreadStore.threadId == id,
           let thread = activeThreadStore.thread
        {
            let owner = owningEnvironment(forThreadID: id)
            let store = owner?.threadsStore ?? threadsStore
            let project = store?.projectsByID[thread.projectId]
                .flatMap { store?.isScratchProject($0) == true ? nil : $0 }
                .map(SwftAdapters.projectRef(from:))
            let provider = store?.provider(for: thread.providerInstanceId)
            let hostLabel = owner?.displayLabel ?? store?.environment?.label ?? store?.hostname
            let location: ThreadLocation? = thread.branch.flatMap { $0.isEmpty ? nil : .branch($0) }
                ?? hostLabel.map { .host($0) }
            let showEnv = owner.map {
                RemoteLogic.shouldShowEnvironmentDisambiguation(
                    environmentCount: environmentRegistry.entries.count,
                    isRemote: !$0.isLocal
                )
            } ?? false
            let isSettled = thread.settledOverride == "settled"
                || (thread.settledAt != nil && thread.settledOverride != "active")
            return ThreadSummary(
                id: thread.id,
                title: thread.title,
                project: project,
                location: location,
                provider: SwftAdapters.providerKind(
                    driver: provider?.driver ?? thread.providerInstanceId,
                    instanceId: thread.providerInstanceId
                ),
                providerDisplayName: provider?.label,
                activity: activeThreadStore.isRunning ? .running : .idle,
                updatedAt: thread.updatedAt,
                providerDriver: SwftAdapters.providerDriverIdentifier(driver: provider?.driver, instanceId: thread.providerInstanceId),
                providerIconUrl: provider?.iconUrl,
                environmentID: owner?.id,
                environmentLabel: showEnv ? hostLabel : nil,
                isRemoteEnvironment: owner.map { !$0.isLocal } ?? false,
                environmentMachineSymbol: owner.map { RemoteLogic.machineSymbol(for: $0.machineKind) },
                isSettled: isSettled,
                settledAt: thread.settledAt
            )
        }
        if !isMock {
            let owner = owningEnvironment(forThreadID: id)
            let store = owner?.threadsStore ?? threadsStore
            if let store,
               let shell = store.threads.first(where: { $0.id == id }) ?? store.archivedThreads.first(where: { $0.id == id })
            {
                if let owner {
                    let showEnv = RemoteLogic.shouldShowEnvironmentDisambiguation(
                        environmentCount: environmentRegistry.entries.count,
                        isRemote: !owner.isLocal
                    )
                    return SwftAdapters.remoteThreadSummary(
                        from: shell,
                        environment: owner,
                        showEnvironmentLabel: showEnv,
                        activelyViewingThreadID: selectedThreadID
                    )
                }
                let providersByID = Dictionary(uniqueKeysWithValues: store.providers.map { ($0.instanceId, $0) })
                return SwftAdapters.threadSummary(
                    from: shell,
                    projectsByID: NoProjectLogic.nonScratchProjectsByID(
                        projects: store.projects,
                        scratchWorkspaceRoot: store.serverConfig?.scratchWorkspaceRoot
                    ),
                    providersByID: providersByID,
                    hostName: store.environment?.label ?? store.hostname,
                    activelyViewingThreadID: selectedThreadID
                )
            }
        }
        return subagentNavigationContexts[id]?.placeholderSummary
    }

    func detail(for id: ThreadSummary.ID) -> ThreadDetailState? {
        if let mockBacking {
            let liveSummary = mockBacking.threads.first(where: { $0.id == id })
            if var detail = mockBacking.details[id] {
                if let liveSummary { detail.summary = liveSummary }
                if detail.parentLink == nil { detail.parentLink = parentThreadLink(for: id) }
                return detail
            }
            if let summary = liveSummary ?? subagentNavigationContexts[id]?.placeholderSummary {
                var sample = MockData.threadDetail
                sample.summary = summary
                sample.parentLink = parentThreadLink(for: id)
                return sample
            }
            return nil
        }

        guard let summary = threadSummary(for: id) else { return nil }
        let parentLink = parentThreadLink(for: id)
        if let activeThreadStore,
           activeThreadStore.threadId == id,
           let projection = activeThreadStore.projection
        {
            let owner = owningEnvironment(forThreadID: id)
            let ownerStore = owner?.threadsStore ?? threadsStore
            let providers = ownerStore?.providers ?? []
            let pending = pendingUserMessages[id] ?? []
            let storeID = ObjectIdentifier(activeThreadStore)
            let version = activeThreadStore.projectionVersion
            if let cached = cachedLiveDetail,
               cached.storeID == storeID,
               cached.projectionVersion == version,
               cached.summary == summary,
               cached.providers == providers,
               cached.parentLink == parentLink,
               cached.pending == pending,
               cached.approvals == optimisticApprovals
            {
                return cached.detail
            }
            if !pending.isEmpty {
                Self.aliasPromotedAttachmentPreviews(in: projection, matching: pending)
            }
            let providersByID = Dictionary(uniqueKeysWithValues: providers.map { ($0.instanceId, $0) })
            let threadsByID = Dictionary(
                (ownerStore?.threads ?? []).map { ($0.id, $0) },
                uniquingKeysWith: { _, latest in latest }
            )
            let detail = SwftAdapters.threadDetail(
                from: projection,
                summary: summary,
                providersByID: providersByID,
                threadsByID: threadsByID,
                optimisticApprovals: optimisticApprovals,
                pendingUserMessages: pending,
                parentLink: parentLink
            )
            cachedLiveDetail = CachedLiveThreadDetail(
                storeID: storeID,
                projectionVersion: version,
                summary: summary,
                providers: providers,
                parentLink: parentLink,
                pending: pending,
                approvals: optimisticApprovals,
                detail: detail
            )
            return detail
        }
        let pending = (pendingUserMessages[id] ?? []).map { TranscriptItem(id: $0.messageID, kind: .user($0.text, attachments: $0.attachments)) }
        return ThreadDetailState(summary: summary, items: pending, diffStat: nil, parentLink: parentLink)
    }

    func threadCount(forProjectID projectID: String) -> Int {
        if let match = projects.first(where: { $0.id == projectID }) {
            return projectThreadCounts(for: match).listed
        }
        return sidebar.threads.filter { $0.project?.id == projectID }.count
    }

    func projectThreadCounts(for project: ProjectRef) -> ProjectThreadCounts {
        if isMock {
            let listed = sidebar.threads.filter { thread in
                thread.project?.id == project.id
                    && (project.environmentID == nil || thread.environmentID == nil || thread.environmentID == project.environmentID)
            }.count
            return ProjectThreadCounts(listed: listed, archived: 0)
        }
        guard let store = owningStore(forProject: project)?.store else {
            return ProjectThreadCounts(listed: 0, archived: 0)
        }
        let listed = store.listedThreads.filter { $0.projectId == project.id }.count
        let archived = store.archivedThreads.filter {
            $0.projectId == project.id && $0.lineage.isListed && $0.deletedAt == nil
        }.count
        return ProjectThreadCounts(listed: listed, archived: archived)
    }

    // MARK: - Actions

    func goHome() {
        newThread.cancel()
        destination = .home
        activeThreadEnvironmentID = nil
        subagentNavigationContexts.removeAll()
        detachActiveThread()
    }

    func open(_ id: ThreadSummary.ID) {
        open(id, inEnvironmentID: nil, preserveSubagentTrail: false)
    }

    func open(
        _ id: ThreadSummary.ID,
        inEnvironmentID explicitEnvironmentID: String?,
        preserveSubagentTrail: Bool = false
    ) {
        newThread.cancel()
        if !preserveSubagentTrail && subagentNavigationContexts[id] == nil {
            subagentNavigationContexts.removeAll()
        }
        destination = .thread(id)
        actionError = nil

        if isMock {
            if let explicitEnvironmentID {
                activeThreadEnvironmentID = explicitEnvironmentID
            } else {
                activeThreadEnvironmentID = threadSummary(for: id)?.environmentID
            }
            if let index = mockThreadsOverride?.firstIndex(where: { $0.id == id }),
               mockThreadsOverride?[index].activity == .unread
            {
                mockThreadsOverride?[index].activity = .idle
            }
            if let index = mockBacking?.threads.firstIndex(where: { $0.id == id }),
               mockBacking?.threads[index].activity == .unread
            {
                mockBacking?.threads[index].activity = .idle
            }
            return
        }

        let owner: ManagedEnvironment? = if let explicitEnvironmentID {
            environmentRegistry.environment(id: explicitEnvironmentID) ?? owningEnvironment(forThreadID: id)
        } else {
            owningEnvironment(forThreadID: id)
        }
        activeThreadEnvironmentID = explicitEnvironmentID ?? owner?.id
        let ownerStore = owner?.threadsStore ?? threadsStore
        if let shell = ownerStore?.threads.first(where: { $0.id == id }) {
            syncComposerModel(to: shell.modelSelection, in: ownerStore)
        }
        attachThreadStore(for: id, on: owner?.connection ?? connection, initialProjection: nil)
        visitPolicy.selectThread(id)
        visitTimerTask?.cancel()
        visitTimerTask = nil
        evaluateActiveThreadVisit()
    }

    /// Opens a delegated subagent child thread in its owning environment and records a back-to-parent breadcrumb.
    func openSubagentThread(_ target: SubagentNavigationTarget, fromThreadID parentThreadID: ThreadSummary.ID) {
        let parentSummary = threadSummary(for: parentThreadID)
        let parentEnvironmentID = activeThreadEnvironmentID
            ?? parentSummary?.environmentID
            ?? owningEnvironment(forThreadID: parentThreadID)?.id
        let targetEnvironmentID = target.environmentID ?? parentEnvironmentID
        let parentLink = SubagentParentLink(
            threadID: parentThreadID,
            title: parentSummary?.title ?? "Parent thread",
            environmentID: parentEnvironmentID
        )
        let placeholderSummary = ThreadSummary(
            id: target.threadID,
            title: target.title,
            project: parentSummary?.project,
            location: parentSummary?.location,
            provider: target.provider,
            providerDisplayName: target.providerDisplayName,
            activity: .idle,
            updatedAt: now,
            providerDriver: target.providerDriver,
            providerIconUrl: target.providerIconURL,
            environmentID: targetEnvironmentID,
            environmentLabel: parentSummary?.environmentLabel,
            isRemoteEnvironment: parentSummary?.isRemoteEnvironment ?? false,
            environmentMachineSymbol: parentSummary?.environmentMachineSymbol
        )
        subagentNavigationContexts[target.threadID] = SubagentNavigationContext(
            parentLink: parentLink,
            placeholderSummary: placeholderSummary
        )
        open(target.threadID, inEnvironmentID: targetEnvironmentID, preserveSubagentTrail: true)
    }

    /// Navigates back from a child subagent thread to its parent thread in the parent's owning environment.
    func openParentThread(_ link: SubagentParentLink) {
        if let currentID = selectedThreadID {
            subagentNavigationContexts.removeValue(forKey: currentID)
        }
        open(link.threadID, inEnvironmentID: link.environmentID, preserveSubagentTrail: true)
    }

    func toggleWorkFold(_ id: String) {
        if expandedWorkFolds.remove(id) == nil { expandedWorkFolds.insert(id) }
    }

    func toggleSubagentRow(_ id: String) {
        if expandedSubagentRows.remove(id) == nil { expandedSubagentRows.insert(id) }
    }

    func toggleSidebar() {
        withAnimation(.snappy(duration: 0.22)) { sidebarVisible.toggle() }
    }

    func toggleSettledSection() {
        isSettledExpanded.toggle()
    }

    func settleThread(_ id: ThreadSummary.ID) {
        actionError = nil
        let wasSelected = selectedThreadID == id
        let nextThreadID: ThreadSummary.ID? = wasSelected
            ? SettledThreadsLogic.nextActiveThreadID(afterSettling: id, activeThreads: visibleThreads)
            : nil

        if isMock {
            guard let index = mockBacking?.threads.firstIndex(where: { $0.id == id }),
                  mockBacking?.threads[index].isSettled == false
            else { return }
            mockBacking?.threads[index].isSettled = true
            mockBacking?.threads[index].settledAt = now
            if wasSelected {
                advanceAfterSettlingSelectedThread(nextThreadID: nextThreadID)
            }
            return
        }

        let ownerStore = owningEnvironment(forThreadID: id)?.threadsStore ?? threadsStore
        guard let targetStore = ownerStore, targetStore.connectionState.isConnected || serverStatus.isConnected else {
            actionError = "Server is not connected yet."
            return
        }
        if let current = sidebar.threads.first(where: { $0.id == id }), current.isSettled {
            return
        }

        let token = UUID()
        optimisticSettlements[id] = OptimisticSettlement(isSettled: true, settledAt: now, token: token)
        if wasSelected {
            advanceAfterSettlingSelectedThread(nextThreadID: nextThreadID)
        }

        Task {
            do {
                try await targetStore.settleThread(threadId: id)
                await self.reconcileOptimisticSettlement(id: id, in: targetStore, expectedSettled: true, token: token)
            } catch {
                if self.optimisticSettlements[id]?.token == token {
                    self.optimisticSettlements.removeValue(forKey: id)
                }
                self.actionError = error.localizedDescription
            }
        }
    }

    func unsettleThread(_ id: ThreadSummary.ID) {
        actionError = nil

        if isMock {
            guard let index = mockBacking?.threads.firstIndex(where: { $0.id == id }),
                  mockBacking?.threads[index].isSettled == true
            else { return }
            mockBacking?.threads[index].isSettled = false
            mockBacking?.threads[index].settledAt = nil
            return
        }

        let ownerStore = owningEnvironment(forThreadID: id)?.threadsStore ?? threadsStore
        guard let targetStore = ownerStore, targetStore.connectionState.isConnected || serverStatus.isConnected else {
            actionError = "Server is not connected yet."
            return
        }
        if let current = sidebar.threads.first(where: { $0.id == id }), !current.isSettled {
            return
        }

        let token = UUID()
        optimisticSettlements[id] = OptimisticSettlement(isSettled: false, settledAt: nil, token: token)

        Task {
            do {
                try await targetStore.unsettleThread(threadId: id)
                await self.reconcileOptimisticSettlement(id: id, in: targetStore, expectedSettled: false, token: token)
            } catch {
                if self.optimisticSettlements[id]?.token == token {
                    self.optimisticSettlements.removeValue(forKey: id)
                }
                self.actionError = error.localizedDescription
            }
        }
    }

    private func advanceAfterSettlingSelectedThread(nextThreadID: ThreadSummary.ID?) {
        if let nextThreadID {
            open(nextThreadID)
        } else {
            goHome()
        }
    }

    private func reconcileOptimisticSettlement(
        id: ThreadSummary.ID,
        in store: ThreadsStore,
        expectedSettled: Bool,
        token: UUID
    ) async {
        if store.threads.first(where: { $0.id == id })?.isSettled == expectedSettled {
            if optimisticSettlements[id]?.token == token {
                optimisticSettlements.removeValue(forKey: id)
            }
            return
        }
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, optimisticSettlements[id]?.token == token else { return }
            if store.threads.first(where: { $0.id == id })?.isSettled == expectedSettled {
                optimisticSettlements.removeValue(forKey: id)
                return
            }
        }
        if optimisticSettlements[id]?.token == token {
            optimisticSettlements.removeValue(forKey: id)
        }
    }

    @discardableResult
    func selectProject(_ id: String) -> Bool {
        if let target = projects.first(where: { $0.id == id }), target.isWorkspaceMissing {
            actionError = "The folder for “\(target.name)” no longer exists on disk. Remove it or restore the folder."
            return false
        }
        selectedProjectID = id
        isProjectPickerOpen = false
        actionError = nil
        if !isMock,
           let projectDefault = resolvedComposerStore(localStore: threadsStore)?.projectsByID[id]?.defaultModelSelection
        {
            syncComposerModel(to: projectDefault, in: resolvedComposerStore(localStore: threadsStore))
        }
        return true
    }

    func toggleProjectPicker() {
        if isProjectPickerOpen {
            isProjectPickerOpen = false
        } else {
            modelPicker = nil
            refreshLocalProjectAvailability()
            isProjectPickerOpen = true
        }
    }

    func closeProjectPicker() {
        isProjectPickerOpen = false
    }

    /// Removes a project entry (and its threads on the server; never deletes files on disk).
    /// Returns an error message on failure, or `nil` on success.
    @discardableResult
    func deleteProject(_ project: ProjectRef) async -> String? {
        guard !deletingProjectIDs.contains(project.id) else { return nil }
        let wasSelected = selectedProject?.id == project.id
        let wasNoProjectSelected = isNoProjectSelected
        let currentSelectedID = selectedProjectID

        if isMock {
            removeMockProject(project)
            applyPostDeleteSelection(
                deletedProjectID: project.id,
                wasSelected: wasSelected,
                wasNoProjectSelected: wasNoProjectSelected,
                currentSelectedID: currentSelectedID
            )
            actionError = nil
            return nil
        }

        guard let target = owningStore(forProject: project) else {
            let message = "Connect to the server before removing a project."
            actionError = message
            return message
        }
        guard target.isConnected else {
            let message = "Connect to \(target.label) before removing a project."
            actionError = message
            return message
        }

        let activeThreadBelongsToDeleted: Bool = {
            guard let openThreadID = selectedThreadID else { return false }
            if let activeThread = activeThreadStore?.thread,
               activeThread.id == openThreadID,
               activeThread.projectId == project.id,
               target.environmentID == nil || activeThreadEnvironmentID == nil || activeThreadEnvironmentID == target.environmentID
            {
                return true
            }
            return target.store.threads.contains(where: { $0.id == openThreadID && $0.projectId == project.id })
                || target.store.archivedThreads.contains(where: { $0.id == openThreadID && $0.projectId == project.id })
        }()

        deletingProjectIDs.insert(project.id)
        defer { deletingProjectIDs.remove(project.id) }

        do {
            _ = try await target.store.deleteProject(projectId: project.id, force: true)
            if let root = project.workspaceRoot?.trimmingCharacters(in: .whitespacesAndNewlines), !root.isEmpty {
                localWorkspaceAvailabilityCache.removeValue(forKey: root)
            }
            if activeThreadBelongsToDeleted {
                goHome()
            }
            if target.environmentID == nil || target.environmentID == activeComposerEnvironmentID {
                applyPostDeleteSelection(
                    deletedProjectID: project.id,
                    wasSelected: wasSelected,
                    wasNoProjectSelected: wasNoProjectSelected,
                    currentSelectedID: currentSelectedID
                )
            }
            actionError = nil
            return nil
        } catch {
            let message = error.localizedDescription
            actionError = message
            return message
        }
    }

    private func applyPostDeleteSelection(
        deletedProjectID: String,
        wasSelected: Bool,
        wasNoProjectSelected: Bool,
        currentSelectedID: String?
    ) {
        let next = ProjectDeletionLogic.nextSelectionAfterDeleting(
            deletedProjectID: deletedProjectID,
            wasSelected: wasSelected,
            wasNoProjectSelected: wasNoProjectSelected,
            currentSelectedProjectID: currentSelectedID,
            remainingProjects: projects
        )
        selectedProjectID = next.selectedProjectID
        isNoProjectSelected = next.isNoProjectSelected
    }

    private func removeMockProject(_ project: ProjectRef) {
        if let envID = project.environmentID ?? activeComposerEnvironmentID,
           mockProjectsByEnvironment[envID] != nil
        {
            mockProjectsByEnvironment[envID]?.removeAll { $0.id == project.id }
        }
        mockBacking?.projects.removeAll { $0.id == project.id }

        let matchesDeletedThread: (ThreadSummary) -> Bool = { thread in
            thread.project?.id == project.id
                && (project.environmentID == nil || thread.environmentID == nil || thread.environmentID == project.environmentID)
        }
        var removedThreadIDs = Set<String>()
        if let backingThreads = mockBacking?.threads {
            for thread in backingThreads where matchesDeletedThread(thread) {
                removedThreadIDs.insert(thread.id)
            }
            mockBacking?.threads.removeAll(where: matchesDeletedThread)
        }
        if let overrideThreads = mockThreadsOverride {
            for thread in overrideThreads where matchesDeletedThread(thread) {
                removedThreadIDs.insert(thread.id)
            }
            mockThreadsOverride?.removeAll(where: matchesDeletedThread)
        }
        for threadID in removedThreadIDs {
            mockBacking?.details.removeValue(forKey: threadID)
        }
        if let openID = selectedThreadID, removedThreadIDs.contains(openID) {
            goHome()
        }
    }

    private func owningStore(
        forProject project: ProjectRef
    ) -> (store: ThreadsStore, environmentID: String?, label: String, isConnected: Bool)? {
        if let envID = project.environmentID,
           let env = environmentRegistry.environment(id: envID)
        {
            return (env.threadsStore, env.id, env.displayLabel, env.isConnected)
        }
        if let env = environmentRegistry.environment(
            owningProjectID: project.id,
            preferredEnvironmentID: activeComposerEnvironmentID
        ) {
            return (env.threadsStore, env.id, env.displayLabel, env.isConnected)
        }
        if let store = resolvedComposerStore(localStore: threadsStore) {
            let label = activeComposerEnvironment?.label ?? store.environment?.label ?? "the server"
            let connected = store.connectionState.isConnected || isTargetEnvironmentConnected(localConnected: serverStatus.isConnected)
            return (store, activeComposerEnvironmentID, label, connected)
        }
        return nil
    }

    func selectModel(_ option: ModelOption) {
        let previousReasoning = selectedReasoningChoiceId
        selectedModelID = option.id
        if let previousReasoning, option.reasoningChoices.contains(where: { $0.id == previousReasoning }) {
            selectedReasoningChoiceId = previousReasoning
        } else {
            selectedReasoningChoiceId = option.defaultReasoningChoiceId ?? option.reasoningChoices.first?.id
        }
        syncSelectionToActiveThread()
    }

    // MARK: Model picker

    var modelPickerContent: ModelPickerContent? {
        guard let modelPicker else { return nil }
        let current = selectedModel
        return ModelPickerContent(
            catalog: pickerCatalog,
            session: modelPicker,
            currentModel: current,
            currentInstanceId: current?.instanceId,
            offersPanelAction: true
        )
    }

    func toggleModelPicker() {
        if modelPicker == nil {
            isProjectPickerOpen = false
            modelPicker = ModelPickerSession(catalog: pickerCatalog, currentInstanceId: selectedModel?.instanceId)
        } else {
            modelPicker = nil
        }
    }

    func closeModelPicker() {
        modelPicker = nil
    }

    func pickModel(_ option: ModelOption) {
        selectModel(option)
        modelPicker = nil
    }

    /// Deep-links to provider settings when configured, falling back to re-checking providers.
    func runPickerPanelAction(harnessID: String) {
        if let openProviderSettingsAction {
            openProviderSettingsAction(harnessID)
            return
        }
        refreshProviders()
    }

    /// Routes one key to the open picker. Returns false when the key isn't the picker's.
    @discardableResult
    func handleModelPickerKey(_ key: ModelPickerKey) -> Bool {
        guard var session = modelPicker, let content = modelPickerContent else { return false }
        guard let outcome = ModelPickerLogic.handle(key, session: &session, content: content, currentLevelID: selectedReasoningChoice?.id) else {
            return false
        }
        modelPicker = session
        switch outcome {
        case .pick(let option): pickModel(option)
        case .selectLevel(let id): selectReasoningChoice(id)
        case .panelAction(let id): runPickerPanelAction(harnessID: id)
        case .close: closeModelPicker()
        case nil: break
        }
        return true
    }

    func selectReasoningChoice(_ choiceId: String) {
        selectedReasoningChoiceId = choiceId
        syncSelectionToActiveThread()
    }

    func pickAndAddProject() {
        if pickAndAddProjectForActiveEnvironment() {
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Add Project"
        panel.prompt = "Add Project"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await addProject(at: url)
        }
    }

    func addProject(at url: URL) async {
        let title = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        if isMock {
            let ref = ProjectRef(
                id: "mock-\(UUID().uuidString)",
                name: title,
                initials: SwftAdapters.deriveInitials(from: title),
                tint: SwftAdapters.stableTintIndex(for: url.path),
                workspaceRoot: url.path,
                environmentID: activeComposerEnvironmentID
            )
            if let envID = activeComposerEnvironmentID, mockProjectsByEnvironment[envID] != nil {
                mockProjectsByEnvironment[envID]?.append(ref)
            } else {
                mockBacking?.projects.append(ref)
            }
            selectedProjectID = ref.id
            return
        }

        guard let targetStore = resolvedComposerStore(localStore: threadsStore),
              isTargetEnvironmentConnected(localConnected: serverStatus.isConnected)
        else {
            actionError = "Connect to the target server before adding a project."
            return
        }
        do {
            let created = try await targetStore.createProject(title: title, workspaceRoot: url.path)
            localWorkspaceAvailabilityCache[created.workspaceRoot] = true
            selectedProjectID = created.id
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: - Composer Attachments

    /// The connection composer attachments upload to: the open thread's environment, else Home's target environment.
    /// Nil in mock mode (attachments stay local).
    var composerConnection: ServerConnection? {
        if isMock { return nil }
        if let threadID = selectedThreadID {
            return owningEnvironment(forThreadID: threadID)?.connection ?? connection
        }
        if let id = activeComposerEnvironmentID, let environment = environmentRegistry.environment(id: id) {
            return environment.connection
        }
        return environmentRegistry.localEnvironment?.connection ?? connection
    }

    /// One loader per thread and environment, reused across renders so the environment value stays stable.
    func imageLoader(forThreadID id: String) -> SwftImageLoader {
        if isMock {
            return ThreadImageLoading.loader(threadID: id, environmentID: "mock", connection: nil)
        }
        let owner = owningEnvironment(forThreadID: id)
        let key = "\(owner?.id ?? "local"):\(id)"
        if let cached = imageLoaders[key] { return cached }
        let loader = ThreadImageLoading.loader(threadID: id, environmentID: owner?.id, connection: owner?.connection ?? connection)
        imageLoaders[key] = loader
        return loader
    }

    func attach(_ sources: [AttachmentSource]) {
        guard !sources.isEmpty else { return }
        actionError = nil
        composerAttachments.add(sources, connection: composerConnection)
    }

    func removeComposerAttachment(_ id: String) {
        composerAttachments.remove(id)
    }

    /// When the server promotes `pending-<uuid>` uploads to `<thread>-<uuid>` on send/launch, alias the local preview
    /// into `SwftImageCache` under the promoted id so the flight and transcript never flash a loading spinner.
    static func aliasAttachmentPreviews(from pending: [TranscriptAttachment], to promoted: [ChatAttachment]) {
        guard !pending.isEmpty, pending.count == promoted.count else { return }
        for (local, server) in zip(pending, promoted) where local.id != server.id {
            let sourceKey = SwftImageReference.attachmentKey(local.id)
            let targetKey = SwftImageReference.attachmentKey(server.id)
            if SwftImageCache.shared.image(for: targetKey) == nil,
               let cached = SwftImageCache.shared.image(for: sourceKey)
            {
                SwftImageCache.shared.store(cached, for: targetKey)
            }
        }
    }

    static func aliasPromotedAttachmentPreviews(in projection: ThreadProjection, matching pending: [PendingUserMessage]) {
        let pendingByID = Dictionary(uniqueKeysWithValues: pending.map { ($0.messageID, $0) })
        for projected in projection.visibleTurnItems {
            if case .userMessage(let messageID, _, _, let serverAttachments, _, _) = projected.item.kind,
               let match = pendingByID[messageID]
            {
                aliasAttachmentPreviews(from: match.attachments, to: serverAttachments)
            }
        }
    }

    static func aliasLaunchedAttachmentPreviews(
        pending: [TranscriptAttachment],
        projection: ThreadProjection?
    ) -> [TranscriptAttachment] {
        guard !pending.isEmpty, let projection else { return pending }
        for projected in projection.visibleTurnItems {
            if case .userMessage(_, _, _, let serverAttachments, _, _) = projected.item.kind, !serverAttachments.isEmpty {
                aliasAttachmentPreviews(from: pending, to: serverAttachments)
                return serverAttachments.map(SwftAdapters.transcriptAttachment)
            }
        }
        return pending
    }

    /// `+` in the composer: the system open panel, any files or images, several at once.
    func pickAttachments() {
        let panel = NSOpenPanel()
        panel.title = "Attach Files"
        panel.prompt = "Attach"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        guard panel.runModal() == .OK else { return }
        attach(panel.urls.map(AttachmentSource.file))
    }

    func send() {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Never dispatch an attachment whose bytes are still on their way up.
        guard !composerAttachments.isUploading else { return }
        guard !text.isEmpty || !composerAttachments.ready.isEmpty else { return }
        isProjectPickerOpen = false
        modelPicker = nil

        if isMock {
            let attachments = composerAttachments.takeReady(keepPinned: true)
            if selectedThreadID == nil {
                launchMockThread(text: text, attachments: attachments)
                return
            }
            composerText = ""
            let id = selectedThreadID ?? MockData.threadDetail.summary.id
            var existing = detail(for: id) ?? MockData.threadDetail
            let itemID = UUID().uuidString
            existing.items.append(TranscriptItem(id: itemID, kind: .user(text, attachments: attachments)))
            mockBacking?.details[id] = existing
            if selectedThreadID != nil {
                latestThreadSend = ThreadSendEvent(threadID: id, text: text, attachments: attachments, optimisticItemID: itemID)
            }
            destination = .thread(id)
            return
        }

        guard isTargetEnvironmentConnected(localConnected: serverStatus.isConnected),
              let targetStore = resolvedActiveStore(localStore: threadsStore)
        else {
            let targetName = activeComposerEnvironment?.label ?? "Server"
            actionError = "\(targetName) is not connected yet."
            return
        }

        let attachmentConnection = composerConnection
        guard composerAttachments.readyAttachments(for: attachmentConnection) != nil else {
            actionError = "These attachments were uploaded to another environment. Remove them and attach again."
            return
        }

        if let threadID = selectedThreadID,
           let threadStore = activeThreadStore,
           threadStore.threadId == threadID
        {
            let selection = selectedModel.map {
                SwftAdapters.modelSelection(from: $0, reasoningChoiceId: selectedReasoningChoice?.id)
            }
            let attachments = composerAttachments.takeReady(keepPinned: false)
            // The row appears on this frame (not after the server's echo), so the send flight and the scroll have
            // their real landing geometry from the start.
            let messageID = UUID().uuidString
            pendingUserMessages[threadID, default: []].append(PendingUserMessage(messageID: messageID, text: text, attachments: attachments))
            let sendEvent = ThreadSendEvent(threadID: threadID, text: text, attachments: attachments, optimisticItemID: messageID)
            latestThreadSend = sendEvent
            composerText = ""
            actionError = nil
            isSubmitting = true
            Task {
                do {
                    _ = try await threadStore.sendMessage(
                        text: text,
                        messageId: messageID,
                        modelSelection: selection,
                        attachments: attachments.map(SwftAdapters.chatAttachment)
                    )
                } catch {
                    self.pendingUserMessages[threadID]?.removeAll { $0.messageID == messageID }
                    self.failedThreadSendID = sendEvent.id
                    if self.composerText.isEmpty { self.composerText = text }
                    self.composerAttachments.restore(attachments, connection: attachmentConnection)
                    self.actionError = error.localizedDescription
                }
                self.isSubmitting = false
            }
            return
        }

        // Home composer: create a new thread in the selected project (or scratch when no project is chosen).
        let launchResolution = resolveHomeLaunchTarget()
        guard case .ready(let launchTarget) = launchResolution else {
            if case .unavailable(let reason) = launchResolution { actionError = reason }
            return
        }
        guard let modelOption = selectedModel else {
            actionError = "No models available from the server yet."
            return
        }

        let targetEnv = activeComposerEnvironmentID.flatMap { environmentRegistry.environment(id: $0) }
        let launchStore = targetEnv?.threadsStore ?? targetStore
        let launchConnection = targetEnv?.connection ?? connection

        let modelSelection = SwftAdapters.modelSelection(
            from: modelOption,
            reasoningChoiceId: selectedReasoningChoice?.id
        )
        let provider = launchStore.provider(for: modelOption.instanceId)
        let runtimeMode = Self.resolveRuntimeMode(for: provider, preferred: settings.serverSettings?.defaultRuntimeMode)
        let attachments = composerAttachments.takeReady(keepPinned: false)
        let initialTitle = Self.initialThreadTitle(from: text.isEmpty ? (attachments.first?.name ?? "Attachment") : text)

        composerText = ""
        actionError = nil
        isSubmitting = true
        let launchToken = newThread.begin(text: text)

        Task {
            do {
                let projectId = try await resolveLaunchProjectID(for: launchTarget, using: launchStore)
                let input = LaunchThreadInput(
                    projectId: projectId,
                    title: initialTitle,
                    generateTitle: true,
                    modelSelection: modelSelection,
                    runtimeMode: runtimeMode,
                    interactionMode: .default,
                    workspaceStrategy: .root(),
                    initialMessage: LaunchThreadInitialMessage(text: text, attachments: attachments.map(SwftAdapters.chatAttachment))
                )
                let result = try await launchStore.launchThread(input)
                // The server promotes `pending-<uuid>` uploads to `<thread>-<uuid>` on launch; carry the cached local
                // preview across so the flight and landing never flash a spinner.
                let handoffAttachments = Self.aliasLaunchedAttachmentPreviews(
                    pending: attachments,
                    projection: result.projection
                )
                // Wait for Home's composer to dock; if the user moved on meanwhile, leave them where they are.
                guard await self.newThread.awaitHandoff(token: launchToken, threadID: result.threadId) else {
                    self.isSubmitting = false
                    return
                }
                self.activeThreadEnvironmentID = targetEnv?.id
                self.destination = .thread(result.threadId)
                self.attachThreadStore(
                    for: result.threadId,
                    on: launchConnection,
                    initialProjection: result.projection
                )
                self.latestThreadSend = ThreadSendEvent(threadID: result.threadId, text: text, attachments: handoffAttachments, isHandoff: true)
                self.visitPolicy.selectThread(result.threadId)
                self.visitTimerTask?.cancel()
                self.visitTimerTask = nil
                self.evaluateActiveThreadVisit()
            } catch {
                self.newThread.fail(token: launchToken)
                if self.composerText.isEmpty { self.composerText = text }
                self.composerAttachments.restore(attachments, connection: attachmentConnection)
                self.actionError = error.localizedDescription
            }
            self.isSubmitting = false
        }
    }

    /// Mock Home send: a new thread row lands in the inbox, Home hands off once the composer docks, and a "generated"
    /// title replaces the first-message title a moment later (as the server's title generation would).
    private func launchMockThread(text: String, attachments: [TranscriptAttachment] = []) {
        guard mockBacking != nil else { return }
        composerText = ""
        let titleSource = text.isEmpty ? (attachments.first?.name ?? "Attachment") : text
        let created: ThreadDetailState
        if selectedProject == nil {
            created = makeMockNoProjectThread(text: text, attachments: attachments)
        } else {
            let summary = ThreadSummary(
                id: "mock-\(UUID().uuidString.prefix(8))",
                title: Self.initialThreadTitle(from: titleSource),
                project: selectedProject,
                location: .branch("main"),
                provider: selectedModel?.provider ?? .claude,
                providerDisplayName: selectedModel?.providerDisplayName,
                activity: .idle,
                updatedAt: now
            )
            created = ThreadDetailState(summary: summary, items: [TranscriptItem(id: UUID().uuidString, kind: .user(text, attachments: attachments))], diffStat: nil)
        }
        let id = created.summary.id
        mockBacking?.threads.insert(created.summary, at: 0)
        mockBacking?.details[id] = created
        let token = newThread.begin(text: text)
        Task {
            guard await self.newThread.awaitHandoff(token: token, threadID: id) else { return }
            self.destination = .thread(id)
            self.latestThreadSend = ThreadSendEvent(threadID: id, text: text, attachments: attachments, isHandoff: true)
        }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            self.renameMockThread(id, to: MockData.generatedTitle(for: titleSource))
        }
    }

    /// Mock stand-in for a server-generated title arriving.
    func renameMockThread(_ id: ThreadSummary.ID, to title: String) {
        guard let index = mockBacking?.threads.firstIndex(where: { $0.id == id }) else { return }
        mockBacking?.threads[index].title = title
        mockBacking?.details[id]?.summary.title = title
    }

    func stopActiveRun() {
        if isMock {
            if let id = selectedThreadID,
               let index = mockBacking?.threads.firstIndex(where: { $0.id == id }),
               mockBacking?.threads[index].activity == .running
            {
                mockBacking?.threads[index].activity = .idle
            }
            return
        }

        guard let threadStore = activeThreadStore else { return }
        let activeRunID = threadStore.activeRun?.id
        let isUnresponsive = threadStore.visibleItems.contains { projected in
            guard projected.item.runId == activeRunID || activeRunID == nil else { return false }
            if case .runInterruptRequest(_, let unresponsiveAt) = projected.item.kind {
                return unresponsiveAt != nil
            }
            return false
        }
        let ownerStore = owningEnvironment(forThreadID: threadStore.threadId)?.threadsStore ?? threadsStore
        let canForceStop = ownerStore?.environment?.capabilities.threadForceStop == true

        Task {
            do {
                if isUnresponsive && canForceStop {
                    _ = try await threadStore.forceStop()
                } else {
                    try await threadStore.interrupt(reason: "User stopped")
                }
            } catch {
                self.actionError = error.localizedDescription
            }
        }
    }

    func resolveApproval(itemID: TranscriptItem.ID, in threadID: ThreadSummary.ID, approved: Bool) {
        if isMock {
            guard var current = detail(for: threadID),
                  let index = current.items.firstIndex(where: { $0.id == itemID }),
                  case .approval(var approval) = current.items[index].kind
            else { return }
            approval.status = approved ? .approved : .denied
            current.items[index].kind = .approval(approval)
            mockBacking?.details[threadID] = current
            if let t = mockBacking?.threads.firstIndex(where: { $0.id == threadID }),
               mockBacking?.threads[t].activity == .needsApproval
            {
                mockBacking?.threads[t].activity = .running
            }
            return
        }

        guard let current = detail(for: threadID),
              let item = current.items.first(where: { $0.id == itemID }),
              case .approval(let approval) = item.kind,
              !approval.requestId.isEmpty,
              let threadStore = activeThreadStore,
              threadStore.threadId == threadID
        else { return }

        let requestId = approval.requestId
        optimisticApprovals[requestId] = approved ? .approved : .denied

        Task {
            do {
                try await threadStore.respondToApproval(
                    requestId: requestId,
                    decision: approved ? .accept : .decline
                )
            } catch {
                self.optimisticApprovals.removeValue(forKey: requestId)
                self.actionError = error.localizedDescription
            }
        }
    }

    // MARK: - Private Helpers

    private var liveAccountSummary: AccountSummary {
        let detail: String
        switch serverStatus {
        case .starting:
            detail = "Starting local server…"
        case .connecting:
            detail = "Connecting to server…"
        case .connected(_, let providerCount, _):
            let unit = providerCount == 1 ? "provider" : "providers"
            detail = "Local server · \(providerCount) \(unit)"
        case .reconnecting(let attempt, _):
            detail = "Reconnecting (attempt \(attempt))…"
        case .failed:
            detail = "Server offline · Click to retry"
        }
        return AccountSummary(
            name: Self.localUserFullName(),
            detail: remoteAwareAccountDetail(defaultDetail: detail)
        )
    }

    private func attachThreadStore(
        for threadID: String,
        on targetConnection: ServerConnection? = nil,
        initialProjection: ThreadProjection?
    ) {
        let resolvedConnection = targetConnection ?? connection
        if activeThreadStore?.threadId == threadID,
           let resolvedConnection,
           activeThreadStore?.connection === resolvedConnection
        {
            return
        }
        if let previous = activeThreadStore {
            previous.stop()
            recentProjections.remember(previous.projection)
        }
        optimisticApprovals.removeAll()
        pendingUserMessages.removeAll()
        guard let resolvedConnection else {
            activeThreadStore = nil
            return
        }
        // Start from the last projection seen for this thread so a revisit shows its transcript at once; the
        // subscription's snapshot replaces it moments later.
        let store = ThreadStore(
            connection: resolvedConnection,
            threadId: threadID,
            initialProjection: initialProjection ?? recentProjections.projection(for: threadID)
        )
        activeThreadStore = store
        store.start()
    }

    private func detachActiveThread() {
        activeThreadStore?.stop()
        recentProjections.remember(activeThreadStore?.projection)
        activeThreadStore = nil
        optimisticApprovals.removeAll()
        pendingUserMessages.removeAll()
        visitPolicy.selectThread(nil)
        visitTimerTask?.cancel()
        visitTimerTask = nil
    }

    private func syncComposerModel(to selection: ModelSelection, in storeOverride: ThreadsStore? = nil) {
        let targetID = SwftAdapters.modelOptionID(instanceId: selection.instanceId, slug: selection.model)
        if let option = availableModels.first(where: { $0.id == targetID }) {
            selectedModelID = option.id
            selectedReasoningChoiceId = SwftAdapters.reasoningChoiceId(from: selection, for: option)
        } else if let store = storeOverride ?? resolvedActiveStore(localStore: threadsStore) {
            let providersByID = Dictionary(uniqueKeysWithValues: store.providers.map { ($0.instanceId, $0) })
            let fallback = SwftAdapters.fallbackModelOption(for: selection, providersByID: providersByID)
            selectedModelID = fallback.id
            selectedReasoningChoiceId = SwftAdapters.reasoningChoiceId(from: selection, for: fallback)
        }
    }

    private func syncSelectionToActiveThread() {
        guard !isMock,
              let threadStore = activeThreadStore,
              let model = selectedModel
        else { return }
        let selection = SwftAdapters.modelSelection(
            from: model,
            reasoningChoiceId: selectedReasoningChoice?.id
        )
        Task {
            try? await threadStore.setModelSelection(selection)
        }
    }

    private func startVisitObservation() {
        guard !isObservingVisits else { return }
        isObservingVisits = true
        observeVisitsTick()
    }

    private func observeVisitsTick() {
        guard !isMock, !isShuttingDown else { return }
        withObservationTracking {
            self.evaluateActiveThreadVisit()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeVisitsTick()
            }
        }
    }

    private func evaluateActiveThreadVisit() {
        guard let threadID = selectedThreadID,
              let ownerStore = owningEnvironment(forThreadID: threadID)?.threadsStore ?? threadsStore,
              ownerStore.connectionState.isConnected,
              let shell = ownerStore.threads.first(where: { $0.id == threadID })
        else { return }

        if ownerStore.environment?.capabilities.threadVisitedTracking == false {
            return
        }

        let action = visitPolicy.evaluate(
            threadId: threadID,
            updatedAt: shell.updatedAt,
            lastVisitedAt: shell.lastVisitedAt,
            latestRunCompletedAt: shell.latestRunCompletedAt
        )

        switch action {
        case .none:
            break
        case .dispatchNow(let visitedAt, let opened):
            visitTimerTask?.cancel()
            visitTimerTask = nil
            Task {
                try? await ownerStore.markVisited(
                    threadId: threadID,
                    visitedAt: visitedAt,
                    opened: opened
                )
            }
        case .deferBy(let delay, _):
            guard visitTimerTask == nil else { return }
            visitTimerTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                self.visitTimerTask = nil
                guard self.selectedThreadID == threadID,
                      let store = self.owningEnvironment(forThreadID: threadID)?.threadsStore ?? self.threadsStore,
                      store.connectionState.isConnected,
                      let latestShell = store.threads.first(where: { $0.id == threadID })
                else { return }
                let visitedAt = latestShell.updatedAt
                self.visitPolicy.markDeferredDispatched(visitedAt: visitedAt)
                try? await store.markVisited(
                    threadId: threadID,
                    visitedAt: visitedAt,
                    opened: false
                )
            }
        }
    }

    private static func resolveRuntimeMode(for provider: ServerProvider?, preferred: RuntimeMode? = nil) -> RuntimeMode {
        guard let supported = provider?.supportedRuntimeModes, !supported.isEmpty else {
            return preferred ?? .fullAccess
        }
        if let preferred, supported.contains(preferred) { return preferred }
        if supported.contains(.fullAccess) { return .fullAccess }
        return supported.first ?? .fullAccess
    }

    private static func initialThreadTitle(from text: String) -> String {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty }) ?? "New thread"
        if firstLine.count <= 60 { return firstLine }
        return String(firstLine.prefix(57)) + "…"
    }

    private static func localUserFullName() -> String {
        let full = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        if !full.isEmpty { return full }
        let user = NSUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        return user.isEmpty ? "Local user" : user
    }

    private static func localUserFirstName() -> String {
        let full = localUserFullName()
        return full.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? full
    }
}
