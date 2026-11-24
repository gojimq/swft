import AppKit
import Foundation
import Observation
import SwftKit
import SwiftUI

/// UI state and SwftKit orchestration coordinator for the main window.
@MainActor
@Observable
final class AppModel {
    // MARK: - Navigation & UI Controls

    var destination: SidebarDestination = .home {
        didSet { if oldValue != destination { modelPicker = nil } }
    }
    /// The open model picker, or nil when it is closed.
    var modelPicker: ModelPickerSession?
    var sidebarVisible = true
    var filter: ThreadFilter = .all
    var composerText = ""
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
    /// Settings screen coordinator (preferences, server settings RPCs, provider setup streams).
    let settings = SettingsController()
    /// Hook invoked when the model picker's signed-out action deep-links to provider settings.
    var openProviderSettingsAction: ((String) -> Void)?
    /// Home → new thread staging (composer docking, hand-off); see `Motion/NewThread`.
    let newThread = NewThreadLauncher()

    // MARK: - Mode & Live SwftKit Backing

    let isMock: Bool

    private var serverProcess: ServerProcess?
    private var connection: ServerConnection?
    private(set) var threadsStore: ThreadsStore?
    private var activeThreadStore: ThreadStore?
    private var serverPort: Int?
    private var launchPhase: LaunchPhase = .idle
    private var isSubmitting = false
    private var optimisticApprovals: [String: ApprovalItem.Status] = [:]
    @ObservationIgnored private var recentProjections = RecentProjections()

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
        var details: [ThreadSummary.ID: ThreadDetailState]
        var defaultContextLabel: String?
    }

    private var mockBacking: MockBacking?

    // MARK: - Initializers & Factories

    private init(isMock: Bool, now: Date, mockBacking: MockBacking? = nil) {
        self.isMock = isMock
        self.now = now
        self.mockBacking = mockBacking
        self.settings.attach(to: self)
        self.openProviderSettingsAction = { [weak self] harnessID in
            self?.openSettings(section: .providers, providerID: harnessID)
        }
        self.settings.applyAppearance()
    }

    static func makeForLaunch() -> AppModel {
        if shouldUseMockMode() {
            return .mock()
        }
        return .live()
    }

    static func live() -> AppModel {
        AppModel(isMock: false, now: Date())
    }

    static func mock() -> AppModel {
        let backing = MockBacking(
            projects: MockData.projects,
            threads: MockData.threads,
            account: MockData.sidebar.account,
            home: MockData.home,
            models: MockData.models,
            harnesses: MockData.harnesses,
            details: [MockData.threadDetail.summary.id: MockData.threadDetail, MockData.approvalDetail.summary.id: MockData.approvalDetail],
            defaultContextLabel: "Swft · main"
        )
        let model = AppModel(isMock: true, now: MockData.now, mockBacking: backing)
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
        // `-SwftPicker open|<query>` opens the model picker (optionally searching), for screenshots.
        if let picker = UserDefaults.standard.string(forKey: "SwftPicker") {
            model.toggleModelPicker()
            if picker != "open" { model.modelPicker?.setQuery(picker) }
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
        guard !isMock, let threadsStore else { return }
        Task {
            do {
                _ = try await threadsStore.refreshProviders(fresh: true)
            } catch {
                self.actionError = error.localizedDescription
            }
        }
    }

    func shutdown() async {
        isShuttingDown = true
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
            attachThreadStore(for: id, initialProjection: nil)
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
        if let mockBacking {
            return mockBacking.projects
        }
        guard let threadsStore else { return [] }
        return threadsStore.projects
            .filter { $0.archivedAt == nil && !threadsStore.isScratchProject($0) }
            .map(SwftAdapters.projectRef(from:))
    }

    var selectedProject: ProjectRef? {
        NoProjectLogic.resolveSelectedProject(
            projects: projects,
            selectedProjectID: selectedProjectID,
            isNoProjectSelected: isNoProjectSelected
        )
    }

    var availableModels: [ModelOption] {
        if let mockBacking {
            return mockBacking.models
        }
        guard let threadsStore else { return [] }
        return SwftAdapters.modelOptions(from: threadsStore.providers)
    }

    var pickerCatalog: PickerCatalog {
        if let mockBacking {
            return PickerCatalog(harnesses: mockBacking.harnesses, models: mockBacking.models)
        }
        guard let threadsStore else { return .empty }
        return SwftAdapters.pickerCatalog(from: threadsStore.providers)
    }

    var selectedModel: ModelOption? {
        let options = availableModels
        if let selectedModelID, let match = options.first(where: { $0.id == selectedModelID }) {
            return match
        }
        if !isMock,
           let thread = activeThreadStore?.thread,
           let threadsStore
        {
            let providersByID = Dictionary(uniqueKeysWithValues: threadsStore.providers.map { ($0.instanceId, $0) })
            return options.first(where: {
                $0.instanceId == thread.modelSelection.instanceId && $0.slug == thread.modelSelection.model
            }) ?? SwftAdapters.fallbackModelOption(for: thread.modelSelection, providersByID: providersByID)
        }
        let projectDefault: ModelSelection?
        if let projectID = selectedProject?.id {
            projectDefault = threadsStore?.projectsByID[projectID]?.defaultModelSelection
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
            return SidebarState(threads: mockBacking.threads, filter: filter, account: mockBacking.account)
        }
        let hostName = threadsStore?.environment?.label ?? threadsStore?.hostname
        let projectsByID = nonScratchProjectsByID
        let providersByID = Dictionary(
            uniqueKeysWithValues: (threadsStore?.providers ?? []).map { ($0.instanceId, $0) }
        )
        let threads = (threadsStore?.listedThreads ?? []).map { shell in
            SwftAdapters.threadSummary(
                from: shell,
                projectsByID: projectsByID,
                providersByID: providersByID,
                hostName: hostName,
                activelyViewingThreadID: selectedThreadID
            )
        }
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

    var composer: ComposerState {
        let contextLabel = resolvedComposerContextLabel(mockDefaultContextLabel: mockBacking?.defaultContextLabel)

        let isBusy: Bool
        if isMock {
            isBusy = false
        } else if selectedThreadID != nil {
            isBusy = isSubmitting || (activeThreadStore?.isRunning == true)
        } else {
            isBusy = isSubmitting
        }

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

    var visibleThreads: [ThreadSummary] {
        let all = sidebar.threads
        switch filter {
        case .all:
            return all
        case .active:
            return all.filter { $0.activity == .running || $0.activity == .needsApproval }
        case .needsAttention:
            return all.filter { $0.activity == .needsApproval || $0.activity == .failed || $0.activity == .unread }
        }
    }

    var selectedThreadID: ThreadSummary.ID? {
        if case .thread(let id) = destination { id } else { nil }
    }

    var readyProviderNames: [String] {
        if isMock { return ["Claude", "Codex", "Cursor"] }
        return (threadsStore?.providers ?? [])
            .filter { $0.enabled && $0.installed && $0.status != .disabled }
            .map(\.label)
    }

    func threadSummary(for id: ThreadSummary.ID) -> ThreadSummary? {
        if let match = sidebar.threads.first(where: { $0.id == id }) {
            return match
        }
        if !isMock,
           let activeThreadStore,
           activeThreadStore.threadId == id,
           let thread = activeThreadStore.thread
        {
            let project = nonScratchProjectsByID[thread.projectId].map(SwftAdapters.projectRef(from:))
            let provider = threadsStore?.provider(for: thread.providerInstanceId)
            let location: ThreadLocation? = thread.branch.flatMap { $0.isEmpty ? nil : .branch($0) }
                ?? (threadsStore?.environment?.label ?? threadsStore?.hostname).map { .host($0) }
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
                providerIconUrl: provider?.iconUrl
            )
        }
        return nil
    }

    func detail(for id: ThreadSummary.ID) -> ThreadDetailState? {
        if let mockBacking {
            if let detail = mockBacking.details[id] { return detail }
            guard let summary = mockBacking.threads.first(where: { $0.id == id }) else { return nil }
            var sample = MockData.threadDetail
            sample.summary = summary
            return sample
        }

        guard let summary = threadSummary(for: id) else { return nil }
        if let activeThreadStore,
           activeThreadStore.threadId == id,
           let projection = activeThreadStore.projection
        {
            return SwftAdapters.threadDetail(
                from: projection,
                summary: summary,
                optimisticApprovals: optimisticApprovals
            )
        }
        return ThreadDetailState(summary: summary, items: [], diffStat: nil)
    }

    func threadCount(forProjectID projectID: String) -> Int {
        sidebar.threads.filter { $0.project?.id == projectID }.count
    }

    // MARK: - Actions

    func goHome() {
        newThread.cancel()
        destination = .home
        detachActiveThread()
    }

    func open(_ id: ThreadSummary.ID) {
        newThread.cancel()
        destination = .thread(id)
        actionError = nil

        if isMock {
            if let index = mockBacking?.threads.firstIndex(where: { $0.id == id }),
               mockBacking?.threads[index].activity == .unread
            {
                mockBacking?.threads[index].activity = .idle
            }
            return
        }

        if let shell = threadsStore?.threads.first(where: { $0.id == id }) {
            syncComposerModel(to: shell.modelSelection)
        }
        attachThreadStore(for: id, initialProjection: nil)
        visitPolicy.selectThread(id)
        visitTimerTask?.cancel()
        visitTimerTask = nil
        evaluateActiveThreadVisit()
    }

    func toggleWorkFold(_ id: String) {
        if expandedWorkFolds.remove(id) == nil { expandedWorkFolds.insert(id) }
    }

    func toggleSidebar() {
        withAnimation(.snappy(duration: 0.22)) { sidebarVisible.toggle() }
    }

    func selectProject(_ id: String) {
        selectedProjectID = id
        actionError = nil
        if !isMock,
           let projectDefault = threadsStore?.projectsByID[id]?.defaultModelSelection
        {
            syncComposerModel(to: projectDefault)
        }
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
                workspaceRoot: url.path
            )
            mockBacking?.projects.append(ref)
            selectedProjectID = ref.id
            return
        }

        guard let threadsStore, serverStatus.isConnected else {
            actionError = "Connect to the local server before adding a project."
            return
        }
        do {
            let created = try await threadsStore.createProject(title: title, workspaceRoot: url.path)
            selectedProjectID = created.id
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
    }

    func send() {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if isMock {
            if selectedThreadID == nil {
                launchMockThread(text: text)
                return
            }
            composerText = ""
            let id = selectedThreadID ?? MockData.threadDetail.summary.id
            var existing = detail(for: id) ?? MockData.threadDetail
            existing.items.append(TranscriptItem(id: UUID().uuidString, kind: .user(text)))
            mockBacking?.details[id] = existing
            destination = .thread(id)
            return
        }

        guard serverStatus.isConnected, let threadsStore else {
            actionError = "Local server is not connected yet."
            return
        }

        if let threadID = selectedThreadID,
           let threadStore = activeThreadStore,
           threadStore.threadId == threadID
        {
            let selection = selectedModel.map {
                SwftAdapters.modelSelection(from: $0, reasoningChoiceId: selectedReasoningChoice?.id)
            }
            composerText = ""
            actionError = nil
            isSubmitting = true
            Task {
                do {
                    _ = try await threadStore.sendMessage(text: text, modelSelection: selection)
                } catch {
                    if self.composerText.isEmpty { self.composerText = text }
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

        let modelSelection = SwftAdapters.modelSelection(
            from: modelOption,
            reasoningChoiceId: selectedReasoningChoice?.id
        )
        let provider = threadsStore.provider(for: modelOption.instanceId)
        let runtimeMode = Self.resolveRuntimeMode(for: provider, preferred: settings.serverSettings?.defaultRuntimeMode)
        let initialTitle = Self.initialThreadTitle(from: text)

        composerText = ""
        actionError = nil
        isSubmitting = true
        let launchToken = newThread.begin(text: text)

        Task {
            do {
                let projectId = try await resolveLaunchProjectID(for: launchTarget, using: threadsStore)
                let input = LaunchThreadInput(
                    projectId: projectId,
                    title: initialTitle,
                    generateTitle: true,
                    modelSelection: modelSelection,
                    runtimeMode: runtimeMode,
                    interactionMode: .default,
                    workspaceStrategy: .root(),
                    initialMessage: LaunchThreadInitialMessage(text: text)
                )
                let result = try await threadsStore.launchThread(input)
                // Wait for Home's composer to dock; if the user moved on meanwhile, leave them where they are.
                guard await self.newThread.awaitHandoff(token: launchToken, threadID: result.threadId) else {
                    self.isSubmitting = false
                    return
                }
                self.destination = .thread(result.threadId)
                self.attachThreadStore(for: result.threadId, initialProjection: result.projection)
                self.visitPolicy.selectThread(result.threadId)
                self.visitTimerTask?.cancel()
                self.visitTimerTask = nil
                self.evaluateActiveThreadVisit()
            } catch {
                self.newThread.fail(token: launchToken)
                if self.composerText.isEmpty { self.composerText = text }
                self.actionError = error.localizedDescription
            }
            self.isSubmitting = false
        }
    }

    /// Mock Home send: a new thread row lands in the inbox, Home hands off once the composer docks, and a "generated"
    /// title replaces the first-message title a moment later (as the server's title generation would).
    private func launchMockThread(text: String) {
        guard mockBacking != nil else { return }
        composerText = ""
        let created: ThreadDetailState
        if selectedProject == nil {
            created = makeMockNoProjectThread(text: text)
        } else {
            let summary = ThreadSummary(
                id: "mock-\(UUID().uuidString.prefix(8))",
                title: Self.initialThreadTitle(from: text),
                project: selectedProject,
                location: .branch("main"),
                provider: selectedModel?.provider ?? .claude,
                providerDisplayName: selectedModel?.providerDisplayName,
                activity: .idle,
                updatedAt: now
            )
            created = ThreadDetailState(summary: summary, items: [TranscriptItem(id: UUID().uuidString, kind: .user(text))], diffStat: nil)
        }
        let id = created.summary.id
        mockBacking?.threads.insert(created.summary, at: 0)
        mockBacking?.details[id] = created
        let token = newThread.begin(text: text)
        Task {
            guard await self.newThread.awaitHandoff(token: token, threadID: id) else { return }
            self.destination = .thread(id)
        }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            self.renameMockThread(id, to: MockData.generatedTitle(for: text))
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
        let canForceStop = threadsStore?.environment?.capabilities.threadForceStop == true

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
        return AccountSummary(name: Self.localUserFullName(), detail: detail)
    }

    private func attachThreadStore(for threadID: String, initialProjection: ThreadProjection?) {
        if activeThreadStore?.threadId == threadID {
            return
        }
        if let previous = activeThreadStore {
            previous.stop()
            recentProjections.remember(previous.projection)
        }
        optimisticApprovals.removeAll()
        guard let connection else {
            activeThreadStore = nil
            return
        }
        // Start from the last projection seen for this thread so a revisit shows its transcript at once; the
        // subscription's snapshot replaces it moments later.
        let store = ThreadStore(
            connection: connection,
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
        visitPolicy.selectThread(nil)
        visitTimerTask?.cancel()
        visitTimerTask = nil
    }

    private func syncComposerModel(to selection: ModelSelection) {
        let targetID = SwftAdapters.modelOptionID(instanceId: selection.instanceId, slug: selection.model)
        if let option = availableModels.first(where: { $0.id == targetID }) {
            selectedModelID = option.id
            selectedReasoningChoiceId = SwftAdapters.reasoningChoiceId(from: selection, for: option)
        } else if let threadsStore {
            let providersByID = Dictionary(uniqueKeysWithValues: threadsStore.providers.map { ($0.instanceId, $0) })
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
              let threadsStore,
              threadsStore.connectionState.isConnected,
              let shell = threadsStore.threads.first(where: { $0.id == threadID })
        else { return }

        if threadsStore.environment?.capabilities.threadVisitedTracking == false {
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
                try? await threadsStore.markVisited(
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
                      let store = self.threadsStore,
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
