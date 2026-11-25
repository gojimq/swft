import AppKit
import Foundation
import Observation
import SwftKit
import UserNotifications

/// Coordinates Settings screen navigation, local preferences, server settings RPCs,
/// and per-provider auth/install subscriptions.
@MainActor
@Observable
final class SettingsController {
    var section: SettingsSection = .general
    var expandedProviderID: String?
    var settingsError: String?
    var isRefreshingProviders = false
    var isLoadingSettings = false

    // MARK: - Local Preferences (UserDefaults)

    var appearance: AppearancePreference {
        didSet {
            guard oldValue != appearance else { return }
            defaults.set(appearance.rawValue, forKey: AppearancePreference.defaultsKey)
            applyAppearance()
        }
    }

    var notificationMode: NotificationModePreference {
        didSet {
            guard oldValue != notificationMode else { return }
            defaults.set(notificationMode.rawValue, forKey: NotificationModePreference.defaultsKey)
        }
    }

    var notifyOnComplete: Bool {
        didSet {
            guard oldValue != notifyOnComplete else { return }
            defaults.set(notifyOnComplete, forKey: NotificationModePreference.notifyOnCompleteKey)
        }
    }

    var notifyOnAttention: Bool {
        didSet {
            guard oldValue != notifyOnAttention else { return }
            defaults.set(notifyOnAttention, forKey: NotificationModePreference.notifyOnAttentionKey)
        }
    }

    var inAppNotificationsEnabled: Bool {
        didSet {
            guard oldValue != inAppNotificationsEnabled else { return }
            defaults.set(inAppNotificationsEnabled, forKey: NotificationModePreference.inAppBannerKey)
        }
    }

    var notificationPermission: NotificationPermissionState = .unknown
    var notificationStatusNote: String?

    // MARK: - Provider Setup Stream State

    private(set) var authStates: [String: ProviderAuthState] = [:]
    private(set) var authErrors: [String: String] = [:]
    private(set) var installStates: [String: ProviderInstallState] = [:]
    private(set) var installErrors: [String: String] = [:]
    private(set) var setupPendingIDs: Set<String> = []
    private(set) var setupActionErrors: [String: String] = [:]

    // MARK: - Mock Backing

    private var mockServerSettings: ServerSettings = SettingsMockData.serverSettings
    private var mockProviders: [ServerProvider] = SettingsMockData.providers

    // MARK: - Private

    @ObservationIgnored private weak var appModel: AppModel?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var authSubscriptionTask: Task<Void, Never>?
    @ObservationIgnored private var installSubscriptionTask: Task<Void, Never>?
    @ObservationIgnored private var subscribedProviderID: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.appearance = AppearancePreference.load(from: defaults)
        self.notificationMode = NotificationModePreference.load(from: defaults)
        if defaults.object(forKey: NotificationModePreference.notifyOnCompleteKey) != nil {
            self.notifyOnComplete = defaults.bool(forKey: NotificationModePreference.notifyOnCompleteKey)
        } else {
            self.notifyOnComplete = true
        }
        if defaults.object(forKey: NotificationModePreference.notifyOnAttentionKey) != nil {
            self.notifyOnAttention = defaults.bool(forKey: NotificationModePreference.notifyOnAttentionKey)
        } else {
            self.notifyOnAttention = true
        }
        self.inAppNotificationsEnabled = defaults.bool(forKey: NotificationModePreference.inAppBannerKey)
    }

    func attach(to appModel: AppModel) {
        self.appModel = appModel
        if let tab = SettingsSection.fromLaunchArgument(defaults.string(forKey: "SwftSettingsTab")) {
            section = tab
        }
        if let expand = defaults.string(forKey: "SwftSettingsProvider") {
            expandedProviderID = expand
        }
    }

    // MARK: - Appearance

    func applyAppearance() {
        // Respect explicit screenshot/launch flag (`-SwftAppearance light|dark`) when active.
        if defaults.string(forKey: "SwftAppearance") != nil { return }
        guard let app = NSApp else { return }
        if let name = appearance.nsAppearanceName {
            app.appearance = NSAppearance(named: name)
        } else {
            app.appearance = nil
        }
    }

    // MARK: - Server Data Accessors

    var isMock: Bool { appModel?.isMock ?? true }

    var isServerConnected: Bool {
        if isMock { return true }
        return appModel?.serverStatus.isConnected == true && appModel?.activeConnection != nil
    }

    var serverSettings: ServerSettings? {
        if isMock { return mockServerSettings }
        return appModel?.activeThreadsStore?.serverSettings ?? appModel?.activeThreadsStore?.serverConfig?.settings
    }

    var rawProviders: [ServerProvider] {
        if isMock { return mockProviders }
        return appModel?.activeThreadsStore?.providers ?? []
    }

    var providerEntries: [ProviderEntry] {
        ProviderSettingsLogic.sortedProviderEntries(providers: rawProviders, settings: serverSettings)
    }

    var environmentDescriptor: ExecutionEnvironmentDescriptor? {
        if isMock { return SettingsMockData.environment }
        return appModel?.activeThreadsStore?.environment ?? appModel?.activeThreadsStore?.serverConfig?.environment
    }

    var serverWorkingDirectory: String? {
        if isMock { return "/Users/dev/swft" }
        return appModel?.activeThreadsStore?.serverConfig?.cwd
    }

    var dataDirectoryURL: URL {
        appModel?.resolvedDataDirectory ?? ServerLaunchConfiguration.defaultBaseDirectory
    }

    var appVersion: String { Self.bundleAppVersion }

    static var bundleAppVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return short?.isEmpty == false ? short! : "0.1.0"
    }

    var readOnlyReason: String? {
        isServerConnected ? nil : "Connect to the local server to change server settings."
    }

    // MARK: - Lifecycle

    func onSettingsAppear() {
        refreshNotificationPermission()
        ensureServerSettingsLoaded()
        if let expandedProviderID {
            syncProviderSubscriptions(for: expandedProviderID)
        }
    }

    func onSettingsDisappear() {
        stopProviderSubscriptions()
    }

    func ensureServerSettingsLoaded() {
        guard !isMock,
              let connection = appModel?.activeConnection,
              let store = appModel?.activeThreadsStore,
              appModel?.serverStatus.isConnected == true,
              store.serverSettings == nil,
              !isLoadingSettings
        else { return }

        isLoadingSettings = true
        Task {
            do {
                let fetched = try await connection.getSettings()
                store.updateServerSettings(fetched)
            } catch {
                self.settingsError = error.localizedDescription
            }
            self.isLoadingSettings = false
        }
    }

    // MARK: - Server Settings Writes

    func updateServerSettings(_ patch: ServerSettingsPatch) {
        settingsError = nil
        if isMock {
            applyMockPatch(patch)
            return
        }
        guard let connection = appModel?.activeConnection,
              let store = appModel?.activeThreadsStore,
              isServerConnected
        else {
            settingsError = "Connect to the local server before saving settings."
            return
        }
        Task {
            do {
                let updated = try await connection.updateSettings(ServerUpdateSettingsInput(patch: patch))
                store.updateServerSettings(updated)
            } catch {
                self.settingsError = error.localizedDescription
            }
        }
    }

    func setDefaultModelSelection(_ selection: ModelSelection?) {
        updateServerSettings(ServerSettingsPatch(defaultModelSelection: .set(selection)))
    }

    func setDefaultRuntimeMode(_ mode: RuntimeMode) {
        updateServerSettings(ServerSettingsPatch(defaultRuntimeMode: mode))
    }

    func setDefaultThreadEnvMode(_ mode: ThreadEnvMode?) {
        updateServerSettings(ServerSettingsPatch(defaultThreadEnvMode: .set(mode)))
    }

    func setResponseStreamingMode(_ mode: ResponseStreamingMode) {
        updateServerSettings(ServerSettingsPatch(responseStreamingMode: mode))
    }

    func setKeepAwake(_ enabled: Bool) {
        updateServerSettings(ServerSettingsPatch(keepAwakeWhileAgentsWork: enabled))
    }

    func setContinueAfterRestart(_ enabled: Bool) {
        updateServerSettings(ServerSettingsPatch(continueThreadsAfterServerUpdate: enabled))
    }

    func setAutoSettleOnMerge(_ enabled: Bool) {
        updateServerSettings(ServerSettingsPatch(sidebarAutoSettleOnMerge: enabled))
    }

    func setIdleCompaction(_ mode: IdleCompactionMode) {
        let current = serverSettings ?? ServerSettings()
        updateServerSettings(SettingsValuePresentation.idleCompactionPatch(current: current, next: mode))
    }

    // MARK: - Provider Instance Management

    func toggleExpandedProvider(_ id: String) {
        if expandedProviderID == id {
            expandedProviderID = nil
            stopProviderSubscriptions()
        } else {
            expandedProviderID = id
            syncProviderSubscriptions(for: id)
        }
    }

    func openProviders(expanding providerID: String?) {
        section = .providers
        if let providerID {
            let resolved = ProviderSettingsLogic.resolveProviderExpandID(
                entries: providerEntries,
                requestedID: providerID
            ) ?? providerID
            expandedProviderID = resolved
            syncProviderSubscriptions(for: resolved)
        }
    }

    func refreshProviders() {
        guard !isRefreshingProviders else { return }
        settingsError = nil
        if isMock {
            isRefreshingProviders = true
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                self.isRefreshingProviders = false
            }
            return
        }
        guard let store = appModel?.activeThreadsStore, isServerConnected else {
            settingsError = "Connect to the local server before refreshing providers."
            return
        }
        isRefreshingProviders = true
        Task {
            do {
                _ = try await store.refreshProvidersCatalog(reloadSecrets: true)
            } catch {
                self.settingsError = error.localizedDescription
            }
            self.isRefreshingProviders = false
        }
    }

    func setProviderEnabled(_ id: String, enabled: Bool) {
        guard let previous = currentInstanceConfig(for: id) else { return }
        let next = ProviderSettingsLogic.buildEnabledInstanceConfig(previous: previous, enabled: enabled)
        Task { _ = await mutateProvider(.upsert(instanceId: id, instance: next)) }
    }

    func updateProviderDisplayName(_ id: String, displayName: String) {
        guard let previous = currentInstanceConfig(for: id) else { return }
        let next = ProviderSettingsLogic.buildDisplayNameInstanceConfig(previous: previous, displayName: displayName)
        Task { _ = await mutateProvider(.upsert(instanceId: id, instance: next)) }
    }

    func updateProviderAccentColor(_ id: String, accentColor: String?) {
        guard let previous = currentInstanceConfig(for: id) else { return }
        let next = ProviderSettingsLogic.buildAccentColorInstanceConfig(previous: previous, accentColor: accentColor)
        Task { _ = await mutateProvider(.upsert(instanceId: id, instance: next)) }
    }

    func updateProviderConfig(_ id: String, config: [String: JSONValue]?) {
        guard let previous = currentInstanceConfig(for: id) else { return }
        let next = ProviderSettingsLogic.buildConfigInstanceConfig(previous: previous, config: config)
        Task { _ = await mutateProvider(.upsert(instanceId: id, instance: next)) }
    }

    func updateProviderEnvironment(_ id: String, environment: [ProviderInstanceEnvironmentVariable]) {
        guard let previous = currentInstanceConfig(for: id) else { return }
        let next = ProviderSettingsLogic.buildEnvironmentInstanceConfig(previous: previous, environment: environment)
        Task { _ = await mutateProvider(.upsert(instanceId: id, instance: next)) }
    }

    func addCustomModel(to id: String, slug: String) {
        guard let previous = currentInstanceConfig(for: id) else { return }
        let existing = ProviderSettingsLogic.readCustomModelSlugs(driver: previous.driver, config: previous.configObject)
        guard !existing.contains(slug) else { return }
        let nextConfig = ProviderSettingsLogic.nextConfigWithCustomModels(from: previous.configObject, slugs: existing + [slug])
        let next = ProviderSettingsLogic.buildConfigInstanceConfig(previous: previous, config: nextConfig)
        Task { _ = await mutateProvider(.upsert(instanceId: id, instance: next)) }
    }

    func removeCustomModel(from id: String, slug: String) {
        guard let previous = currentInstanceConfig(for: id) else { return }
        let existing = ProviderSettingsLogic.readCustomModelSlugs(driver: previous.driver, config: previous.configObject)
        let nextConfig = ProviderSettingsLogic.nextConfigWithCustomModels(from: previous.configObject, slugs: existing.filter { $0 != slug })
        let next = ProviderSettingsLogic.buildConfigInstanceConfig(previous: previous, config: nextConfig)
        Task { _ = await mutateProvider(.upsert(instanceId: id, instance: next)) }
    }

    func createProviderAccount(draft: CreateAccountDraft) async -> Result<String, SettingsValidationError> {
        let result = await mutateProvider(.create(instanceId: draft.instanceId, instance: draft.instance))
        switch result {
        case .success:
            expandedProviderID = draft.instanceId
            syncProviderSubscriptions(for: draft.instanceId)
            return .success(draft.instanceId)
        case .failure(let error):
            return .failure(.message(error.localizedDescription))
        }
    }

    func removeProviderAccount(_ id: String) {
        if expandedProviderID == id {
            expandedProviderID = nil
            stopProviderSubscriptions()
        }
        Task { _ = await mutateProvider(.remove(instanceId: id)) }
    }

    private func currentInstanceConfig(for id: String) -> ProviderInstanceConfig? {
        if let explicit = serverSettings?.providerInstances[id] {
            return explicit
        }
        guard let snapshot = rawProviders.first(where: { $0.instanceId == id }) else { return nil }
        return ProviderSettingsLogic.baseInstanceConfig(explicit: nil, driver: snapshot.driver)
    }

    private func mutateProvider(
        _ mutation: ProviderInstanceMutation,
        patch: ServerSettingsPatch = ServerSettingsPatch()
    ) async -> Result<Void, Error> {
        settingsError = nil
        if isMock {
            applyMockProviderMutation(mutation)
            return .success(())
        }
        guard let connection = appModel?.activeConnection,
              let store = appModel?.activeThreadsStore,
              isServerConnected
        else {
            let err = SettingsValidationError.message("Connect to the local server before saving provider settings.")
            settingsError = err.localizedDescription
            return .failure(err)
        }
        do {
            let updated = try await connection.updateSettings(
                ServerUpdateSettingsInput(patch: patch, providerInstanceMutation: mutation)
            )
            store.updateServerSettings(updated)
            return .success(())
        } catch {
            settingsError = error.localizedDescription
            return .failure(error)
        }
    }

    // MARK: - Provider Auth & Install Setup Subscriptions + Actions

    func syncProviderSubscriptions(for id: String) {
        if subscribedProviderID == id { return }
        stopProviderSubscriptions()
        subscribedProviderID = id

        guard let entry = providerEntries.first(where: { $0.id == id }) else { return }

        if isMock {
            if entry.supportsAuth {
                authStates[id] = ProviderAuthState(
                    instanceId: id,
                    phase: entry.auth.status == .authenticated ? .succeeded : .idle
                )
            }
            if entry.supportsInstall {
                installStates[id] = ProviderInstallState(
                    driver: entry.driver,
                    phase: .idle,
                    version: entry.version,
                    installedVersion: entry.installed ? entry.version : nil,
                    source: entry.installed ? "local" : nil,
                    canRemove: false
                )
            }
            return
        }

        guard let connection = appModel?.activeConnection, isServerConnected else { return }

        if entry.supportsAuth {
            authErrors.removeValue(forKey: id)
            authSubscriptionTask = Task { [weak self] in
                var lastPhase: ProviderAuthPhase?
                let stream = connection.subscribeProviderAuth(instanceId: id)
                do {
                    for try await state in stream {
                        guard !Task.isCancelled, let self else { break }
                        let prev = lastPhase
                        lastPhase = state.phase
                        self.authStates[id] = state
                        self.authErrors.removeValue(forKey: id)
                        if prev != nil && prev != .succeeded && state.phase == .succeeded {
                            await self.refreshSingleProvider(id)
                        }
                    }
                } catch {
                    if !Task.isCancelled {
                        self?.authErrors[id] = error.localizedDescription
                    }
                }
            }
        }

        if entry.supportsInstall {
            installErrors.removeValue(forKey: id)
            installSubscriptionTask = Task { [weak self] in
                var lastPhase: ProviderInstallPhase?
                let stream = connection.subscribeProviderInstall(instanceId: id)
                do {
                    for try await state in stream {
                        guard !Task.isCancelled, let self else { break }
                        let prev = lastPhase
                        lastPhase = state.phase
                        self.installStates[id] = state
                        self.installErrors.removeValue(forKey: id)
                        if prev != nil && prev != .succeeded && state.phase == .succeeded {
                            await self.refreshSingleProvider(id)
                        }
                    }
                } catch {
                    if !Task.isCancelled {
                        self?.installErrors[id] = error.localizedDescription
                    }
                }
            }
        }
    }

    func stopProviderSubscriptions() {
        authSubscriptionTask?.cancel()
        authSubscriptionTask = nil
        installSubscriptionTask?.cancel()
        installSubscriptionTask = nil
        subscribedProviderID = nil
    }

    private func refreshSingleProvider(_ id: String) async {
        guard !isMock, let store = appModel?.activeThreadsStore else { return }
        _ = try? await store.refreshProvidersCatalog(instanceId: id, reloadSecrets: false)
    }

    func startProviderAuth(for id: String, methodID: String?) {
        runProviderSetupAction(for: id) { connection in
            let state = try await connection.startProviderAuth(
                ProviderAuthStartInput(instanceId: id, methodId: methodID, callbackMode: "server")
            )
            self.authStates[id] = state
        }
    }

    func respondProviderAuth(
        for id: String,
        flowID: String,
        interactionID: String,
        response: ProviderAuthResponse
    ) {
        runProviderSetupAction(for: id) { connection in
            let state = try await connection.respondProviderAuth(
                ProviderAuthRespondInput(
                    instanceId: id,
                    flowId: flowID,
                    interactionId: interactionID,
                    response: response
                )
            )
            self.authStates[id] = state
        }
    }

    func openProviderSignInURL(
        for id: String,
        url rawURL: String,
        requiresConsent: Bool,
        flowID: String?,
        interactionID: String?
    ) {
        guard ProviderSettingsLogic.isWebURL(rawURL), let url = URL(string: rawURL) else {
            setupActionErrors[id] = "This sign-in link is not a valid web address."
            return
        }
        setupActionErrors.removeValue(forKey: id)
        if requiresConsent, let flowID, let interactionID {
            runProviderSetupAction(for: id) { connection in
                let state = try await connection.respondProviderAuth(
                    ProviderAuthRespondInput(
                        instanceId: id,
                        flowId: flowID,
                        interactionId: interactionID,
                        response: .browser(action: "accept")
                    )
                )
                self.authStates[id] = state
                NSWorkspace.shared.open(url)
            }
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func completeProviderAuth(for id: String, flowID: String, callbackURL: String) {
        let trimmed = callbackURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        runProviderSetupAction(for: id) { connection in
            let state = try await connection.completeProviderAuth(
                ProviderAuthCompleteInput(instanceId: id, flowId: flowID, callbackUrl: trimmed)
            )
            self.authStates[id] = state
            await self.refreshSingleProvider(id)
        }
    }

    func cancelProviderAuth(for id: String, flowID: String) {
        runProviderSetupAction(for: id) { connection in
            let state = try await connection.cancelProviderAuth(
                ProviderAuthCancelInput(instanceId: id, flowId: flowID)
            )
            self.authStates[id] = state
        }
    }

    func logoutProviderAuth(for id: String) {
        if isMock {
            if let index = mockProviders.firstIndex(where: { $0.instanceId == id }) {
                let old = mockProviders[index]
                mockProviders[index] = ServerProvider(
                    instanceId: old.instanceId,
                    driver: old.driver,
                    displayName: old.displayName,
                    accentColor: old.accentColor,
                    enabled: old.enabled,
                    installed: old.installed,
                    version: old.version,
                    status: .warning,
                    auth: ServerProviderAuth(status: .unauthenticated, type: old.auth.type, label: old.auth.label),
                    checkedAt: Date(),
                    models: [],
                    setup: old.setup
                )
                authStates[id] = ProviderAuthState(instanceId: id, phase: .idle)
            }
            return
        }
        runProviderSetupAction(for: id) { connection in
            let state = try await connection.logoutProviderAuth(instanceId: id)
            self.authStates[id] = state
            await self.refreshSingleProvider(id)
        }
    }

    func startProviderInstall(for id: String) {
        runProviderSetupAction(for: id) { connection in
            let state = try await connection.startProviderInstall(instanceId: id)
            self.installStates[id] = state
        }
    }

    func cancelProviderInstall(for id: String, operationID: String) {
        runProviderSetupAction(for: id) { connection in
            let state = try await connection.cancelProviderInstall(
                ProviderInstallCancelInput(instanceId: id, operationId: operationID)
            )
            self.installStates[id] = state
        }
    }

    func removeProviderInstallation(for id: String) {
        runProviderSetupAction(for: id) { connection in
            let state = try await connection.removeProviderInstallation(instanceId: id)
            self.installStates[id] = state
            await self.refreshSingleProvider(id)
        }
    }

    private func runProviderSetupAction(
        for id: String,
        operation: @escaping @MainActor (ServerConnection) async throws -> Void
    ) {
        guard !setupPendingIDs.contains(id) else { return }
        setupActionErrors.removeValue(forKey: id)
        if isMock {
            setupActionErrors[id] = "Live server connection required to complete sign-in or installation."
            return
        }
        guard let connection = appModel?.activeConnection, isServerConnected else {
            setupActionErrors[id] = "Connect to the local server first."
            return
        }
        setupPendingIDs.insert(id)
        Task {
            do {
                try await operation(connection)
            } catch {
                self.setupActionErrors[id] = error.localizedDescription
            }
            self.setupPendingIDs.remove(id)
        }
    }

    // MARK: - Notifications Permission & Sound

    func refreshNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else {
            notificationPermission = .unavailable
            return
        }
        Task { @MainActor in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.notificationPermission = .authorized
            case .denied:
                self.notificationPermission = .denied
            case .notDetermined:
                self.notificationPermission = .notDetermined
            @unknown default:
                self.notificationPermission = .unknown
            }
        }
    }

    func selectNotificationMode(_ mode: NotificationModePreference) {
        notificationStatusNote = nil
        if mode.includesSystemNotification {
            guard Bundle.main.bundleIdentifier != nil else {
                notificationMode = mode
                notificationPermission = .unavailable
                return
            }
            Task { @MainActor in
                let center = UNUserNotificationCenter.current()
                let settings = await center.notificationSettings()
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    self.notificationPermission = .authorized
                    self.notificationMode = mode
                case .denied:
                    self.notificationPermission = .denied
                    self.notificationStatusNote = "Allow notifications for Swft in macOS System Settings, or choose Sound only."
                case .notDetermined:
                    do {
                        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                        self.notificationPermission = granted ? .authorized : .denied
                        if granted {
                            self.notificationMode = mode
                        } else {
                            self.notificationStatusNote = "Notifications were not allowed. You can still use Sound only."
                        }
                    } catch {
                        self.notificationStatusNote = "Could not request notification permission."
                    }
                @unknown default:
                    self.notificationMode = mode
                }
            }
        } else {
            notificationMode = mode
        }
    }

    func playTestNotificationSound() {
        NSSound(named: "Glass")?.play()
    }

    func openSystemNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - About Actions

    func revealDataFolderInFinder() {
        let url = dataDirectoryURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    // MARK: - Mock Mutations (Previews & Snapshots)

    private func applyMockPatch(_ patch: ServerSettingsPatch) {
        if case .set(let model) = patch.defaultModelSelection {
            mockServerSettings.defaultModelSelection = model
        }
        if let runtime = patch.defaultRuntimeMode {
            mockServerSettings.defaultRuntimeMode = runtime
        }
        if case .set(let envMode) = patch.defaultThreadEnvMode {
            mockServerSettings.defaultThreadEnvMode = envMode
        }
        if let streaming = patch.responseStreamingMode {
            mockServerSettings.responseStreamingMode = streaming
        }
        if let keepAwake = patch.keepAwakeWhileAgentsWork {
            mockServerSettings.keepAwakeWhileAgentsWork = keepAwake
        }
        if let cont = patch.continueThreadsAfterServerUpdate {
            mockServerSettings.continueThreadsAfterServerUpdate = cont
        }
        if let settle = patch.sidebarAutoSettleOnMerge {
            mockServerSettings.sidebarAutoSettleOnMerge = settle
        }
        if let idle = patch.idleCompaction {
            mockServerSettings.idleCompaction = idle
        }
    }

    private func applyMockProviderMutation(_ mutation: ProviderInstanceMutation) {
        switch mutation {
        case .create(let id, let config):
            mockServerSettings.providerInstances[id] = config
            mockProviders.append(
                ServerProvider(
                    instanceId: id,
                    driver: config.driver,
                    displayName: config.displayName,
                    accentColor: config.accentColor,
                    enabled: config.enabled ?? true,
                    installed: true,
                    status: .warning,
                    auth: ServerProviderAuth(status: .unauthenticated),
                    checkedAt: Date(),
                    models: [],
                    setup: ServerProviderSetup(canAuthenticate: config.driver != "claudeAgent", canInstall: false)
                )
            )
        case .upsert(let id, let config):
            mockServerSettings.providerInstances[id] = config
            if let index = mockProviders.firstIndex(where: { $0.instanceId == id }) {
                let old = mockProviders[index]
                let enabled = ProviderSettingsLogic.resolveInstanceEnabled(config)
                mockProviders[index] = ServerProvider(
                    instanceId: old.instanceId,
                    driver: old.driver,
                    displayName: config.displayName ?? old.displayName,
                    accentColor: config.accentColor,
                    enabled: enabled,
                    installed: old.installed,
                    version: old.version,
                    status: enabled ? (old.status == .disabled ? .ready : old.status) : .disabled,
                    auth: old.auth,
                    checkedAt: old.checkedAt,
                    message: old.message,
                    models: old.models,
                    subProviders: old.subProviders,
                    setup: old.setup
                )
            }
        case .remove(let id):
            mockServerSettings.providerInstances.removeValue(forKey: id)
            mockProviders.removeAll { $0.instanceId == id }
        }
    }
}

// MARK: - AppModel Settings Navigation Extension

extension AppModel {
    /// Opens the in-window Settings screen, optionally deep-linking to a specific section or provider row.
    func openSettings(section: SettingsSection = .general, providerID: String? = nil) {
        if let providerID {
            settings.openProviders(expanding: providerID)
        } else {
            settings.section = section
        }
        destination = .settings
    }
}
