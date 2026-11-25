import AppKit
import Foundation
import Observation
import SwftKit

/// Everything the coordinator touches outside itself, so the whole update can run against deterministic fakes.
struct UpdateServices {
    var fetchLatestRelease: @Sendable () async throws -> SwftReleaseInfo
    var environments: @MainActor () -> [UpdateEnvironmentSnapshot]
    var localAppVersion: @MainActor () -> String
    var localAppEligibility: @MainActor () -> LocalAppUpdateEligibility
    var updateRemote: @MainActor (
        _ environmentID: String,
        _ targetVersion: String,
        _ onProgress: @escaping @Sendable (ServerSelfUpdateProgressStage) -> Void
    ) async throws -> ServerSelfUpdateResult
    /// Fetches SHA256SUMS and stages the verified Swft.app.
    var stageLocalApp: @MainActor (
        _ release: SwftReleaseInfo,
        _ onStage: @escaping @Sendable (LocalAppUpdateStage) -> Void
    ) async throws -> StagedAppUpdate
    /// Hands the staged app to the swap helper and quits. Returns false when nothing terminated (demo).
    var installAndRelaunch: @MainActor (_ staged: StagedAppUpdate) async throws -> Bool
    var sleep: @Sendable (Duration) async throws -> Void
    var hasSavedToken: @MainActor () -> Bool
    var saveToken: @MainActor (String) throws -> Void
    var deleteToken: @MainActor () throws -> Void
    /// Persists the dismissed version; nil keeps it in memory only.
    var defaults: UserDefaults?
    var reconnectTimeout: Duration = .seconds(90)
    var reconnectPollInterval: Duration = .milliseconds(500)
    var completionHold: Duration = .milliseconds(1400)
    var backgroundInterval: Duration = .seconds(4 * 60 * 60)
    /// Upper bound on waiting for an environment to connect before the first background check.
    var initialConnectWait: Duration = .seconds(30)
}

@MainActor
@Observable
final class UpdateCoordinator {
    enum CheckStatus: Equatable {
        case idle
        case checking
        case upToDate
        case available
        case noReleases
        case failed(String)
    }

    static let dismissedVersionKey = "SwftUpdateDismissedVersion"

    private(set) var release: SwftReleaseInfo?
    private(set) var plan: UpdatePlan?
    private(set) var phase: UpdatePillPhase = .hidden
    private(set) var checkStatus: CheckStatus = .idle
    private(set) var lastCheckedAt: Date?
    private(set) var targets: [UpdateTargetEntry] = []
    private(set) var isRunning = false
    private(set) var dismissedVersion: String?
    private(set) var completedVersion: String?
    private(set) var hasSavedToken = false
    private(set) var tokenError: String?

    @ObservationIgnored let services: UpdateServices
    @ObservationIgnored private var backgroundTask: Task<Void, Never>?
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var collapseTask: Task<Void, Never>?
    @ObservationIgnored private var isObservingEnvironments = false
    @ObservationIgnored private var isStopped = false

    init(services: UpdateServices) {
        self.services = services
        self.dismissedVersion = services.defaults?.string(forKey: Self.dismissedVersionKey)
        self.hasSavedToken = services.hasSavedToken()
    }

    var environmentSnapshots: [UpdateEnvironmentSnapshot] { services.environments() }
    var localAppVersion: String { services.localAppVersion() }

    var updateHeadline: String? {
        guard let plan, plan.hasActionableUpdate else { return nil }
        return UpdateLogic.actionHeadline(version: plan.release.version, targetCount: plan.targetCount)
    }

    // MARK: Lifecycle

    /// Checks once something has connected, then every few hours; also re-plans as environments come and go.
    func start() {
        guard backgroundTask == nil, !isStopped else { return }
        observeEnvironments()
        backgroundTask = Task { [weak self] in
            guard let self else { return }
            await self.waitForFirstConnection()
            while !Task.isCancelled {
                await self.checkForUpdates(userInitiated: false)
                do { try await self.services.sleep(self.services.backgroundInterval) } catch { return }
            }
        }
    }

    func stop() {
        isStopped = true
        backgroundTask?.cancel()
        backgroundTask = nil
        collapseTask?.cancel()
        collapseTask = nil
        runTask?.cancel()
        runTask = nil
    }

    private func waitForFirstConnection() async {
        var waited: Duration = .zero
        let step: Duration = .seconds(1)
        while waited < services.initialConnectWait, !Task.isCancelled {
            if services.environments().contains(where: \.isConnected) { return }
            do { try await services.sleep(step) } catch { return }
            waited += step
        }
    }

    private func observeEnvironments() {
        guard !isObservingEnvironments else { return }
        isObservingEnvironments = true
        withObservationTracking {
            _ = services.environments()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.isStopped else { return }
                self.isObservingEnvironments = false
                self.recomputePlan()
                self.observeEnvironments()
            }
        }
    }

    // MARK: Checking

    func checkForUpdates(userInitiated: Bool) async {
        guard checkStatus != .checking else { return }
        if userInitiated {
            // An explicit check always answers, even for a version dismissed or just completed.
            setDismissedVersion(nil)
            completedVersion = nil
        }
        checkStatus = .checking
        do {
            let release = try await services.fetchLatestRelease()
            self.release = release
            lastCheckedAt = Date()
            recomputePlan()
            checkStatus = plan?.hasActionableUpdate == true ? .available : .upToDate
        } catch GitHubReleaseClientError.noReleasesPublished {
            lastCheckedAt = Date()
            checkStatus = .noReleases
        } catch {
            checkStatus = .failed(error.localizedDescription)
        }
    }

    func recomputePlan() {
        guard let release, !isRunning else { return }
        let eligible: Bool = if case .eligible = services.localAppEligibility() { true } else { false }
        let plan = UpdateLogic.makePlan(
            release: release,
            localAppVersion: services.localAppVersion(),
            localAppEligible: eligible,
            environments: services.environments()
        )
        self.plan = plan
        switch phase {
        case .hidden, .available:
            let suppressed = dismissedVersion == release.version || completedVersion == release.version
            phase = plan.hasActionableUpdate && !suppressed ? UpdateLogic.availablePhase(for: plan) : .hidden
        default:
            break
        }
        if checkStatus == .available || checkStatus == .upToDate {
            checkStatus = plan.hasActionableUpdate ? .available : .upToDate
        }
    }

    // MARK: Actions

    func startUpdate() {
        guard !isRunning, let plan, plan.hasActionableUpdate else { return }
        collapseTask?.cancel()
        targets = plan.orderedTargets
        run(release: plan.release, remoteIDs: plan.remoteTargets.map(\.id), includeLocal: plan.needsLocalAppUpdate)
    }

    func retryFailed() {
        guard !isRunning, let release else { return }
        let failedRemotes = targets.filter { !$0.isLocal && $0.status.isFailure }.map(\.id)
        let local = targets.first(where: \.isLocal)
        let includeLocal = local.map { $0.status.isFailure || $0.status == .queued } ?? false
        guard !failedRemotes.isEmpty || includeLocal else { return }
        for id in failedRemotes + (includeLocal ? [UpdateTargetEntry.localID] : []) {
            setStatus(id, .queued)
        }
        run(release: release, remoteIDs: failedRemotes, includeLocal: includeLocal)
    }

    /// "Update this Mac anyway": the user has seen which remotes failed and chooses to restart regardless.
    func continueLocalUpdate() {
        guard !isRunning, let release, targets.contains(where: \.isLocal) else { return }
        setStatus(UpdateTargetEntry.localID, .queued)
        run(release: release, remoteIDs: [], includeLocal: true, acknowledgedRemoteFailures: true)
    }

    func dismiss() {
        guard !isRunning else { return }
        collapseTask?.cancel()
        if let release { setDismissedVersion(release.version) }
        phase = .hidden
        targets = []
    }

    // MARK: Token

    func saveToken(_ token: String) {
        do {
            try services.saveToken(token)
            tokenError = nil
        } catch {
            tokenError = error.localizedDescription
        }
        hasSavedToken = services.hasSavedToken()
    }

    func removeToken() {
        do {
            try services.deleteToken()
            tokenError = nil
        } catch {
            tokenError = error.localizedDescription
        }
        hasSavedToken = services.hasSavedToken()
    }

    /// Awaits the in-flight update run, so tests drain it instead of sleeping.
    func waitForRun() async {
        await runTask?.value
    }

    /// Awaits the completion beat that collapses the pill.
    func waitForCollapse() async {
        await collapseTask?.value
    }

    // MARK: Running

    private func run(release: SwftReleaseInfo, remoteIDs: [String], includeLocal: Bool, acknowledgedRemoteFailures: Bool = false) {
        isRunning = true
        refreshRunningPhase()
        runTask = Task { [weak self] in
            await self?.perform(
                release: release,
                remoteIDs: remoteIDs,
                includeLocal: includeLocal,
                acknowledgedRemoteFailures: acknowledgedRemoteFailures
            )
        }
    }

    private func perform(release: SwftReleaseInfo, remoteIDs: [String], includeLocal: Bool, acknowledgedRemoteFailures: Bool) async {
        // Remotes first, in parallel: this Mac only restarts once every other machine has had its turn.
        await withTaskGroup(of: Void.self) { group in
            for id in remoteIDs {
                group.addTask { await self.updateRemote(id: id, release: release) }
            }
        }
        guard !Task.isCancelled else { return }

        let remoteFailed = targets.contains { !$0.isLocal && $0.status.isFailure }
        if includeLocal {
            if remoteFailed && !acknowledgedRemoteFailures {
                finishWithFailures(canContinueLocal: true)
                return
            }
            await updateLocalApp(release: release)
            return
        }
        if remoteFailed {
            finishWithFailures(canContinueLocal: false)
        } else {
            complete(release: release)
        }
    }

    private func updateRemote(id: String, release: SwftReleaseInfo) async {
        let previous = services.environments().first { $0.id == id }
        setStatus(id, .downloading(fraction: nil))
        do {
            _ = try await services.updateRemote(id, release.version) { [weak self] stage in
                Task { @MainActor in
                    guard let self, let entry = self.targets.first(where: { $0.id == id }),
                          entry.status.acceptsServerProgress else { return }
                    self.setStatus(id, stage == .downloading ? .downloading(fraction: nil) : .installing)
                }
            }
        } catch {
            setStatus(id, .failed(error.localizedDescription))
            return
        }
        setStatus(id, .restarting)
        await waitForReconnect(id: id, label: previous?.label ?? "Server", target: release.semver)
    }

    private func waitForReconnect(id: String, label: String, target: SwftSemver) async {
        var sawDisconnect = false
        var waited: Duration = .zero
        var last: UpdateEnvironmentSnapshot?
        while waited < services.reconnectTimeout {
            do { try await services.sleep(services.reconnectPollInterval) } catch { return }
            waited += services.reconnectPollInterval
            guard let snapshot = services.environments().first(where: { $0.id == id }) else { continue }
            last = snapshot
            switch UpdateLogic.reconnectVerdict(
                isConnected: snapshot.isConnected,
                serverVersion: snapshot.serverVersion,
                target: target,
                sawDisconnect: sawDisconnect
            ) {
            case .updated:
                setStatus(id, .succeeded)
                return
            case .rolledBack(let version):
                setStatus(id, .failed("Rolled back to v\(version)"))
                return
            case .waiting:
                if !snapshot.isConnected { sawDisconnect = true }
            }
        }
        setStatus(id, .failed(UpdateLogic.reconnectTimeoutMessage(
            label: label,
            isConnected: last?.isConnected ?? false,
            serverVersion: last?.serverVersion
        )))
    }

    private func updateLocalApp(release: SwftReleaseInfo) async {
        let id = UpdateTargetEntry.localID
        if case .ineligible(let reason) = services.localAppEligibility() {
            setStatus(id, .skipped(reason: reason))
            isRunning = false
            phase = .failed(message: reason)
            return
        }
        setStatus(id, .downloading(fraction: nil))
        do {
            let staged = try await services.stageLocalApp(release) { [weak self] stage in
                Task { @MainActor in
                    self?.applyLocalStage(stage)
                }
            }
            setStatus(id, .restarting)
            if try await services.installAndRelaunch(staged) {
                // The app is quitting; the helper swaps the bundle and relaunches the new version.
                return
            }
            setStatus(id, .succeeded)
            complete(release: release)
        } catch {
            setStatus(id, .failed(error.localizedDescription))
            finishWithFailures(canContinueLocal: false)
        }
    }

    private func applyLocalStage(_ stage: LocalAppUpdateStage) {
        let id = UpdateTargetEntry.localID
        guard let entry = targets.first(where: { $0.id == id }) else { return }
        switch entry.status {
        case .downloading, .verifying, .installing: break
        default: return
        }
        switch stage {
        case .downloading(let fraction): setStatus(id, .downloading(fraction: fraction))
        case .verifying: setStatus(id, .verifying)
        case .extracting, .ready: setStatus(id, .installing)
        }
    }

    private func finishWithFailures(canContinueLocal: Bool) {
        isRunning = false
        phase = .partialFailure(
            summary: UpdateLogic.partialFailureSummary(targets: targets),
            targets: targets,
            canContinueLocal: canContinueLocal
        )
    }

    private func complete(release: SwftReleaseInfo) {
        isRunning = false
        completedVersion = release.version
        phase = .completed(message: UpdateLogic.completionMessage(targets: targets))
        collapseTask = Task { [weak self] in
            guard let self else { return }
            do { try await self.services.sleep(self.services.completionHold) } catch { return }
            guard case .completed = self.phase else { return }
            self.phase = .hidden
            self.targets = []
            self.recomputePlan()
        }
    }

    private func setStatus(_ id: String, _ status: UpdateTargetStatus) {
        guard let index = targets.firstIndex(where: { $0.id == id }) else { return }
        targets[index].status = status
        refreshRunningPhase()
    }

    private func refreshRunningPhase() {
        guard isRunning else { return }
        phase = UpdateLogic.updatingPhase(targets: targets)
    }

    private func setDismissedVersion(_ version: String?) {
        dismissedVersion = version
        if let version {
            services.defaults?.set(version, forKey: Self.dismissedVersionKey)
        } else {
            services.defaults?.removeObject(forKey: Self.dismissedVersionKey)
        }
    }
}

// MARK: - Service factories

extension UpdateServices {
    /// Does nothing and never touches the network or Keychain: previews, screenshots, and mock mode.
    static var inert: UpdateServices {
        UpdateServices(
            fetchLatestRelease: { throw GitHubReleaseClientError.noReleasesPublished },
            environments: { [] },
            localAppVersion: { "0.0.0" },
            localAppEligibility: { .ineligible(reason: "Updates are unavailable in preview mode.") },
            updateRemote: { _, _, _ in throw CancellationError() },
            stageLocalApp: { _, _ in throw CancellationError() },
            installAndRelaunch: { _ in false },
            sleep: { try await Task.sleep(for: $0) },
            hasSavedToken: { false },
            saveToken: { _ in },
            deleteToken: {},
            defaults: nil
        )
    }

    static func live(
        registry: EnvironmentRegistry,
        appVersion: @escaping @MainActor () -> String,
        releaseClient: GitHubReleaseClient = GitHubReleaseClient(),
        localUpdater: LocalAppUpdater = LocalAppUpdater(),
        tokenStore: UpdateTokenStore = UpdateTokenStore(),
        defaults: UserDefaults = .standard
    ) -> UpdateServices {
        UpdateServices(
            fetchLatestRelease: { try await releaseClient.fetchLatestRelease() },
            environments: { registry.entries.map(UpdateServices.snapshot(of:)) },
            localAppVersion: appVersion,
            localAppEligibility: { localUpdater.canUpdateCurrentApp() },
            updateRemote: { environmentID, version, onProgress in
                guard let env = registry.environment(id: environmentID) else {
                    throw EnvironmentRegistryError.environmentNotFound(environmentID)
                }
                return try await env.threadsStore.updateServerWithProgress(targetVersion: version, onProgress: onProgress)
            },
            stageLocalApp: { release, onStage in
                let sums = try await releaseClient.fetchChecksums(for: release)
                let expected = release.macosAppAsset.flatMap { sums[$0.name] }
                return try await localUpdater.stageUpdate(
                    release: release,
                    expectedSHA256: expected,
                    releaseClient: releaseClient,
                    onProgress: onStage
                )
            },
            installAndRelaunch: { staged in
                guard case .eligible(let appURL) = localUpdater.canUpdateCurrentApp() else {
                    throw LocalAppUpdaterError.ineligible("Swft.app can no longer be replaced in place.")
                }
                try localUpdater.installAndRelaunch(staged: staged, targetAppURL: appURL)
                // `AppDelegate` runs `AppModel.shutdown()` before the process exits; the helper waits for that exit.
                NSApplication.shared.terminate(nil)
                return true
            },
            sleep: { try await Task.sleep(for: $0) },
            hasSavedToken: { ((try? tokenStore.readToken()) ?? nil) != nil },
            saveToken: { try tokenStore.saveToken($0) },
            deleteToken: { try tokenStore.deleteToken() },
            defaults: defaults
        )
    }

    @MainActor
    static func snapshot(of env: ManagedEnvironment) -> UpdateEnvironmentSnapshot {
        let capabilities = env.threadsStore.environment?.capabilities
        return UpdateEnvironmentSnapshot(
            id: env.id,
            label: env.isLocal ? UpdateLogic.localLabel : env.displayLabel,
            isLocal: env.isLocal,
            isConnected: env.isConnected,
            serverVersion: env.serverVersion,
            selfUpdateCapability: capabilities?.serverSelfUpdate,
            desktopAppUpdate: capabilities?.desktopAppUpdate ?? false,
            machineSymbol: RemoteLogic.machineSymbol(for: env.machineKind)
        )
    }
}
