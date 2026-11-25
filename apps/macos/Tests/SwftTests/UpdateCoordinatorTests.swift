import AppKit
import Foundation
import SwftDesign
import SwiftUI
import Testing
@testable import Swft
@testable import SwftKit

// MARK: - Fixtures

private func release(_ version: String) -> SwftReleaseInfo {
    let semver = SwftSemver(version)!
    return SwftReleaseInfo(
        version: semver.raw,
        semver: semver,
        tagName: "v\(semver.raw)",
        name: "Swft v\(semver.raw)",
        notes: "",
        htmlURL: URL(string: "https://github.com/gojimq/swft/releases/tag/v\(semver.raw)")!,
        publishedAt: nil,
        macosAppAsset: nil,
        serverAssets: [:],
        checksumsAsset: nil
    )
}

private func env(
    _ id: String,
    local: Bool = false,
    connected: Bool = true,
    version: String? = "0.1.0",
    capability: ServerSelfUpdateCapability? = .bootService,
    desktopAppUpdate: Bool = false
) -> UpdateEnvironmentSnapshot {
    UpdateEnvironmentSnapshot(
        id: id,
        label: local ? UpdateLogic.localLabel : id,
        isLocal: local,
        isConnected: connected,
        serverVersion: version,
        selfUpdateCapability: capability,
        desktopAppUpdate: desktopAppUpdate,
        machineSymbol: local ? "laptopcomputer" : "server.rack"
    )
}

private struct FakeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Deterministic stand-in for GitHub, the remotes, and this Mac's app bundle.
@MainActor
private final class FakeUpdateWorld {
    static let completionHold: Duration = .seconds(1400)

    var log: [String] = []
    var latest: SwftReleaseInfo
    var localVersion = "0.1.0"
    var environments: [UpdateEnvironmentSnapshot]
    var eligibility: LocalAppUpdateEligibility = .eligible(appURL: URL(fileURLWithPath: "/Applications/Swft.app"))
    var remoteErrors: [String: String] = [:]
    /// Connection states each remote walks through after handing off its update, one per poll.
    var afterHandoff: [String: [(connected: Bool, version: String?)]] = [:]
    var pendingReconnect: [String: [(connected: Bool, version: String?)]] = [:]
    var holdCompletion = false
    private var completionGate: CheckedContinuation<Void, Never>?
    weak var coordinator: UpdateCoordinator?
    let defaults: UserDefaults

    init(latest: SwftReleaseInfo, environments: [UpdateEnvironmentSnapshot]) {
        self.latest = latest
        self.environments = environments
        let suite = "swft.update-tests.\(UUID().uuidString)"
        self.defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    func replace(_ id: String, connected: Bool, version: String?) {
        guard let index = environments.firstIndex(where: { $0.id == id }) else { return }
        let old = environments[index]
        environments[index] = UpdateEnvironmentSnapshot(
            id: old.id, label: old.label, isLocal: old.isLocal, isConnected: connected, serverVersion: version,
            selfUpdateCapability: old.selfUpdateCapability, desktopAppUpdate: old.desktopAppUpdate,
            machineSymbol: old.machineSymbol
        )
    }

    func sleep(_ duration: Duration) async {
        if duration == Self.completionHold, holdCompletion {
            await withCheckedContinuation { completionGate = $0 }
            return
        }
        for (id, steps) in pendingReconnect where !steps.isEmpty {
            let step = steps[0]
            pendingReconnect[id] = Array(steps.dropFirst())
            replace(id, connected: step.connected, version: step.version)
        }
        await Task.yield()
    }

    func releaseCompletion() {
        holdCompletion = false
        completionGate?.resume()
        completionGate = nil
    }

    var services: UpdateServices {
        UpdateServices(
            fetchLatestRelease: { await self.latest },
            environments: { self.environments },
            localAppVersion: { self.localVersion },
            localAppEligibility: { self.eligibility },
            updateRemote: { id, version, onProgress in
                self.log.append("remote:\(id):start")
                onProgress(.downloading)
                await Task.yield()
                onProgress(.installing)
                if let message = self.remoteErrors[id] {
                    self.log.append("remote:\(id):error")
                    throw FakeError(message: message)
                }
                self.log.append("remote:\(id):handoff")
                self.pendingReconnect[id] = self.afterHandoff[id] ?? [(false, nil), (true, version)]
                return ServerSelfUpdateResult(targetVersion: version, method: .bootService, updateId: "u-\(id)")
            },
            stageLocalApp: { release, onStage in
                let remoteStates = self.coordinator?.targets.filter { !$0.isLocal }.map(\.status) ?? []
                self.log.append("local:stage remotes=\(remoteStates.map { UpdateLogic.statusDetail($0) })")
                onStage(.downloading(fraction: 0.5))
                onStage(.verifying)
                onStage(.ready)
                let dir = URL(fileURLWithPath: "/tmp/swft-fake")
                return StagedAppUpdate(version: release.version, stagingDirectory: dir, appURL: dir, sha256: "")
            },
            installAndRelaunch: { _ in
                self.log.append("local:relaunch")
                return true
            },
            sleep: { await self.sleep($0) },
            hasSavedToken: { false },
            saveToken: { _ in },
            deleteToken: {},
            defaults: defaults,
            reconnectTimeout: .seconds(10),
            reconnectPollInterval: .seconds(1),
            completionHold: Self.completionHold
        )
    }

    func makeCoordinator() -> UpdateCoordinator {
        let coordinator = UpdateCoordinator(services: services)
        self.coordinator = coordinator
        return coordinator
    }
}

// MARK: - Planning

@Suite("Update planning")
struct UpdatePlanningTests {
    @Test func remotesFirstWithActionableSkipsAndCurrentOmitted() {
        let plan = UpdateLogic.makePlan(
            release: release("0.2.0"),
            localAppVersion: "0.1.0",
            localAppEligible: true,
            environments: [
                env("local", local: true),
                env("mini"),
                env("respawn", capability: .respawn),
                env("manual", capability: nil),
                env("away", connected: false),
                env("current", version: "0.2.0", capability: nil),
                env("away-current", connected: false, version: "0.2.0"),
                env("desk-managed", capability: .desktopManaged, desktopAppUpdate: false),
                env("desk-updatable", capability: .desktopManaged, desktopAppUpdate: true),
            ]
        )
        #expect(plan.remoteTargets.map(\.id) == ["mini", "respawn", "desk-updatable"])
        #expect(plan.remoteTargets.allSatisfy { $0.status == .queued && $0.targetVersion == "0.2.0" })
        let skipped = Dictionary(uniqueKeysWithValues: plan.skippedRemotes.map { ($0.id, $0.status) })
        #expect(skipped == [
            "manual": .skipped(reason: "Install Swft server service to enable remote updates"),
            "away": .skipped(reason: "Offline"),
            "desk-managed": .skipped(reason: UpdateLogic.desktopManagedReason),
        ])
        #expect(plan.needsLocalAppUpdate)
        #expect(plan.hasActionableUpdate)
        #expect(plan.targetCount == 4)
        #expect(plan.orderedTargets.last?.isLocal == true)
        #expect(plan.orderedTargets.dropLast().allSatisfy { !$0.isLocal })
    }

    @Test func localOnlyRemoteOnlyAndNothingToDo() {
        let localOnly = UpdateLogic.makePlan(
            release: release("0.2.0"), localAppVersion: "0.1.0", localAppEligible: true,
            environments: [env("local", local: true), env("mini", version: "0.2.0")]
        )
        #expect(localOnly.remoteTargets.isEmpty && localOnly.needsLocalAppUpdate)

        let remoteOnly = UpdateLogic.makePlan(
            release: release("0.2.0"), localAppVersion: "0.2.0", localAppEligible: true,
            environments: [env("local", local: true, version: "0.2.0"), env("mini")]
        )
        #expect(remoteOnly.remoteTargets.map(\.id) == ["mini"] && !remoteOnly.needsLocalAppUpdate)

        let none = UpdateLogic.makePlan(
            release: release("0.2.0"), localAppVersion: "0.2.0", localAppEligible: true,
            environments: [env("local", local: true, version: "0.2.0"), env("mini", version: "0.3.0")]
        )
        #expect(!none.hasActionableUpdate)
    }

    @Test func staleBundledServerOnlyCountsWhenTheAppCanUpdate() {
        let environments = [env("local", local: true, version: "0.1.0")]
        let eligible = UpdateLogic.makePlan(release: release("0.2.0"), localAppVersion: "0.2.0", localAppEligible: true, environments: environments)
        let ineligible = UpdateLogic.makePlan(release: release("0.2.0"), localAppVersion: "0.2.0", localAppEligible: false, environments: environments)
        #expect(eligible.needsLocalAppUpdate)
        #expect(!ineligible.needsLocalAppUpdate)
    }

    @Test func semverComparisonIsStrict() {
        let target = SwftSemver("0.2.0")!
        #expect(UpdateLogic.isBehind("0.2.0-beta.1", target: target))
        #expect(!UpdateLogic.isBehind("0.2.0", target: target))
        #expect(!UpdateLogic.isBehind("v0.10.0", target: target))
        #expect(!UpdateLogic.isBehind(nil, target: target))
        #expect(!UpdateLogic.isBehind("garbage", target: target))
    }

    @Test func headlinesAndLabelsScaleWithEnvironmentCount() {
        #expect(UpdateLogic.actionHeadline(version: "0.2.0", targetCount: 1) == "Update to v0.2.0")
        #expect(UpdateLogic.actionHeadline(version: "0.2.0", targetCount: 2) == "Update 2 environments to v0.2.0")
        #expect(UpdateLogic.actionTitle(targetCount: 1) == "Update")
        #expect(UpdateLogic.actionTitle(targetCount: 3) == "Update all")
        #expect(UpdateLogic.availableMessage(version: "0.2.0", targetCount: 1) == "Swft v0.2.0 is available")
        #expect(UpdateLogic.statusDetail(.downloading(fraction: 0.644)) == "Downloading 64%…")
        #expect(UpdateLogic.statusDetail(.downloading(fraction: nil)) == "Downloading…")

        let mini = UpdateTargetEntry(id: "mini", label: "Mac Mini", machineSymbol: "macmini", isLocal: false, currentVersion: "0.1.0", targetVersion: "0.2.0", status: .installing)
        var local = UpdateTargetEntry(id: UpdateTargetEntry.localID, label: "This Mac", machineSymbol: "laptopcomputer", isLocal: true, currentVersion: "0.1.0", targetVersion: "0.2.0", status: .queued)
        #expect(UpdateLogic.updatingPhase(targets: [mini, local]) == .updating(headline: "Updating Mac Mini", detail: "Installing…", progress: nil, targets: [mini, local]))
        local.status = .downloading(fraction: 0.5)
        var doneMini = mini
        doneMini.status = .succeeded
        #expect(UpdateLogic.updatingPhase(targets: [doneMini, local]) == .updating(headline: "Updating Swft", detail: "Downloading 50%…", progress: 0.5, targets: [doneMini, local]))
        #expect(UpdateLogic.completionMessage(targets: [doneMini, local]) == "All environments updated")
        #expect(UpdateLogic.completionMessage(targets: [doneMini]) == "Mac Mini is up to date")
        var failedMini = mini
        failedMini.status = .failed("x")
        #expect(UpdateLogic.partialFailureSummary(targets: [failedMini, local]) == "Mac Mini couldn't update")
        #expect(UpdateLogic.pillRows([doneMini]).isEmpty)
        #expect(UpdateLogic.pillRows([doneMini, local]).map(\.tone) == [.success, .active])
    }

    @Test func reconnectNeedsADisconnectBeforeCallingRollback() {
        let target = SwftSemver("0.2.0")!
        #expect(UpdateLogic.reconnectVerdict(isConnected: true, serverVersion: "0.1.0", target: target, sawDisconnect: false) == .waiting)
        #expect(UpdateLogic.reconnectVerdict(isConnected: false, serverVersion: nil, target: target, sawDisconnect: false) == .waiting)
        #expect(UpdateLogic.reconnectVerdict(isConnected: true, serverVersion: "0.2.0", target: target, sawDisconnect: false) == .updated)
        #expect(UpdateLogic.reconnectVerdict(isConnected: true, serverVersion: "0.1.0", target: target, sawDisconnect: true) == .rolledBack("0.1.0"))
    }

    @Test func settingsReadinessBadges() {
        let r = release("0.2.0")
        #expect(UpdateLogic.readiness(of: env("l", local: true), localAppVersion: "0.1.0", release: r) == .updateAvailable)
        #expect(UpdateLogic.readiness(of: env("l", local: true), localAppVersion: "0.2.0", release: r) == .upToDate)
        #expect(UpdateLogic.readiness(of: env("l", local: true), localAppVersion: "0.2.0", release: nil) == nil)
        #expect(UpdateLogic.readiness(of: env("m", connected: false), localAppVersion: "0.2.0", release: r) == .offline)
        #expect(UpdateLogic.readiness(of: env("m", capability: nil), localAppVersion: "0.2.0", release: r) == .needsServiceInstall)
        #expect(UpdateLogic.readiness(of: env("m"), localAppVersion: "0.2.0", release: nil) == .readyForRemoteUpdates)
        #expect(UpdateLogic.readiness(of: env("m", version: "0.2.0"), localAppVersion: "0.2.0", release: r) == .upToDate)
    }
}

// MARK: - Coordinator

@Suite("Update coordinator")
@MainActor
struct UpdateCoordinatorTests {
    @Test func remotesFinishAndReconnectBeforeThisMacIsTouched() async {
        let world = FakeUpdateWorld(latest: release("0.2.0"), environments: [env("local", local: true), env("mini"), env("studio")])
        let coordinator = world.makeCoordinator()
        await coordinator.checkForUpdates(userInitiated: false)
        #expect(coordinator.phase == .available(version: "0.2.0", targetCount: 3, remoteCount: 2, includesLocalApp: true))

        coordinator.startUpdate()
        await coordinator.waitForRun()

        let stageIndex = world.log.firstIndex { $0.hasPrefix("local:stage") }
        #expect(stageIndex != nil)
        for id in ["mini", "studio"] {
            let handoff = world.log.firstIndex(of: "remote:\(id):handoff")
            #expect(handoff != nil && handoff! < stageIndex!)
        }
        // Both remotes had reconnected on the new version by the time this Mac started downloading.
        #expect(world.log[stageIndex!] == "local:stage remotes=[\"Updated\", \"Updated\"]")
        #expect(world.log.last == "local:relaunch")
        #expect(coordinator.targets.first(where: \.isLocal)?.status == .restarting)
    }

    @Test func rollbackAfterRestartIsAFailureAndHoldsTheLocalRelaunch() async {
        let world = FakeUpdateWorld(latest: release("0.2.0"), environments: [env("local", local: true), env("mini")])
        world.afterHandoff["mini"] = [(false, nil), (true, "0.1.0")]
        let coordinator = world.makeCoordinator()
        await coordinator.checkForUpdates(userInitiated: false)
        coordinator.startUpdate()
        await coordinator.waitForRun()

        let mini = coordinator.targets.first { $0.id == "mini" }
        #expect(mini?.status == .failed("Rolled back to v0.1.0"))
        guard case .partialFailure(let summary, _, let canContinueLocal) = coordinator.phase else {
            Issue.record("expected partial failure, got \(coordinator.phase)")
            return
        }
        #expect(summary == "mini couldn't update")
        #expect(canContinueLocal)
        #expect(!world.log.contains { $0.hasPrefix("local:") })

        coordinator.continueLocalUpdate()
        await coordinator.waitForRun()
        #expect(world.log.last == "local:relaunch")
        #expect(world.log.filter { $0 == "remote:mini:start" }.count == 1)
    }

    @Test func remoteThatReconnectsOnTheTargetSucceeds() async {
        let world = FakeUpdateWorld(latest: release("0.2.0"), environments: [env("local", local: true, version: "0.2.0"), env("mini")])
        world.localVersion = "0.2.0"
        world.afterHandoff["mini"] = [(true, "0.1.0"), (false, nil), (false, nil), (true, "0.2.0")]
        let coordinator = world.makeCoordinator()
        await coordinator.checkForUpdates(userInitiated: false)
        coordinator.startUpdate()
        await coordinator.waitForRun()
        #expect(coordinator.targets.first?.status == .succeeded)
    }

    @Test func partialFailureWaitsForRetryBeforeRelaunching() async {
        let world = FakeUpdateWorld(latest: release("0.2.0"), environments: [env("local", local: true), env("mini"), env("studio")])
        world.remoteErrors["studio"] = "Disk full"
        let coordinator = world.makeCoordinator()
        await coordinator.checkForUpdates(userInitiated: false)
        coordinator.startUpdate()
        await coordinator.waitForRun()

        #expect(coordinator.targets.first { $0.id == "studio" }?.status == .failed("Disk full"))
        #expect(coordinator.targets.first { $0.id == "mini" }?.status == .succeeded)
        #expect(!coordinator.isRunning)
        #expect(!world.log.contains("local:relaunch"))
        guard case .partialFailure = coordinator.phase else {
            Issue.record("expected partial failure, got \(coordinator.phase)")
            return
        }

        world.remoteErrors["studio"] = nil
        coordinator.retryFailed()
        await coordinator.waitForRun()
        // Only the failed remote reruns; the healthy one is left alone.
        #expect(world.log.filter { $0 == "remote:mini:start" }.count == 1)
        #expect(world.log.filter { $0 == "remote:studio:start" }.count == 2)
        #expect(world.log.last == "local:relaunch")
    }

    @Test func remoteOnlyUpdateCompletesThenCollapses() async {
        let world = FakeUpdateWorld(latest: release("0.2.0"), environments: [env("local", local: true, version: "0.2.0"), env("mini")])
        world.localVersion = "0.2.0"
        world.holdCompletion = true
        let coordinator = world.makeCoordinator()
        await coordinator.checkForUpdates(userInitiated: false)
        #expect(coordinator.phase == .available(version: "0.2.0", targetCount: 1, remoteCount: 1, includesLocalApp: false))

        coordinator.startUpdate()
        await coordinator.waitForRun()
        #expect(coordinator.phase == .completed(message: "mini is up to date"))
        #expect(!world.log.contains { $0.hasPrefix("local:") })

        world.releaseCompletion()
        await coordinator.waitForCollapse()
        #expect(coordinator.phase == .hidden)
        #expect(coordinator.completedVersion == "0.2.0")
        #expect(coordinator.plan?.hasActionableUpdate == false)
    }

    @Test func dismissHidesUntilANewerReleaseOrAManualCheck() async {
        let world = FakeUpdateWorld(latest: release("0.2.0"), environments: [env("local", local: true)])
        let coordinator = world.makeCoordinator()
        await coordinator.checkForUpdates(userInitiated: false)
        #expect(coordinator.phase.isVisible)

        coordinator.dismiss()
        #expect(coordinator.phase == .hidden)
        #expect(world.defaults.string(forKey: UpdateCoordinator.dismissedVersionKey) == "0.2.0")

        await coordinator.checkForUpdates(userInitiated: false)
        #expect(coordinator.phase == .hidden)
        #expect(coordinator.checkStatus == .available)

        // A fresh coordinator (next launch) remembers the dismissal.
        let relaunched = UpdateCoordinator(services: world.services)
        await relaunched.checkForUpdates(userInitiated: false)
        #expect(relaunched.phase == .hidden)

        world.latest = release("0.3.0")
        await coordinator.checkForUpdates(userInitiated: false)
        #expect(coordinator.phase == .available(version: "0.3.0", targetCount: 1, remoteCount: 0, includesLocalApp: true))

        coordinator.dismiss()
        await coordinator.checkForUpdates(userInitiated: true)
        #expect(coordinator.phase.isVisible)
    }

    @Test func ineligibleBuildReportsInsteadOfRelaunching() async {
        let world = FakeUpdateWorld(latest: release("0.2.0"), environments: [env("local", local: true)])
        world.eligibility = .ineligible(reason: "Automatic app updates require running from a packaged Swft.app bundle.")
        let coordinator = world.makeCoordinator()
        await coordinator.checkForUpdates(userInitiated: false)
        coordinator.startUpdate()
        await coordinator.waitForRun()
        #expect(coordinator.phase == .failed(message: "Automatic app updates require running from a packaged Swft.app bundle."))
        #expect(!world.log.contains { $0.hasPrefix("local:") })
    }

    @Test func noPublishedReleasesIsNotAnError() async {
        var services = FakeUpdateWorld(latest: release("0.2.0"), environments: []).services
        services.fetchLatestRelease = { throw GitHubReleaseClientError.noReleasesPublished }
        let coordinator = UpdateCoordinator(services: services)
        await coordinator.checkForUpdates(userInitiated: true)
        #expect(coordinator.checkStatus == .noReleases)
        #expect(coordinator.phase == .hidden)
    }
}

// MARK: - Home layout

@Suite("Home update pill layout")
@MainActor
struct HomeUpdatePillLayoutTests {
    private struct HomeProbe: View {
        let state: HomeUpdatePillState?
        let onGreeting: (CGRect) -> Void
        let onComposer: (CGRect) -> Void

        var body: some View {
            VStack(spacing: 0) {
                Spacer(minLength: SwftLayout.titlebarHeight)
                Text("Hi Jim, what are we building?")
                    .font(SwftType.greeting)
                    .hidden()
                    .frame(maxWidth: SwftLayout.composerMaxWidth)
                    .padding(.bottom, HomeUpdatePillMetrics.restingGap)
                    .overlay(alignment: .bottom) {
                        VStack(spacing: 0) {
                            Text("Hi Jim, what are we building?")
                                .font(SwftType.greeting)
                                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onGreeting($0) }
                                .padding(.bottom, HomeUpdatePillMetrics.greetingPadding)
                            HomeUpdatePillSlot(state: state, actions: HomeUpdatePillActions())
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                RoundedRectangle(cornerRadius: SwftRadius.composer)
                    .frame(width: 600, height: 120)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onComposer($0) }
                Spacer(minLength: 40)
            }
            .frame(width: 900, height: 700)
        }
    }

    @Test func greetingRisesForThePillAndGlidesBackDownWhenItCollapses() {
        var greeting = CGRect.zero
        var composer = CGRect.zero
        func probe(_ state: HomeUpdatePillState?) -> HomeProbe {
            HomeProbe(state: state, onGreeting: { greeting = $0 }, onComposer: { composer = $0 })
        }
        func settle() {
            for _ in 0..<12 {
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            }
        }

        let hosting = NSHostingView(rootView: probe(nil))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        window.layoutIfNeeded()
        settle()

        let resting = greeting.minY
        let restingComposer = composer.minY
        #expect(abs(composer.minY - greeting.maxY - HomeUpdatePillMetrics.restingGap) < 0.5)

        let available = HomeUpdatePillState.available(message: "Swft v0.2.0 is available", actionTitle: "Update", actionHelp: "Update to v0.2.0")
        hosting.rootView = probe(available)
        settle()
        let raised = greeting.minY
        #expect(raised < resting - 10, "greeting should move up to make room for the pill")
        #expect(abs(composer.minY - restingComposer) < 0.5, "composer should stay pinned while the pill appears")
        let pillHeight = composer.minY - greeting.maxY - HomeUpdatePillMetrics.gapBelowGreeting - HomeUpdatePillMetrics.gapAboveComposer
        #expect(pillHeight >= 40)

        hosting.rootView = probe(.done(message: "All environments updated"))
        settle()
        #expect(abs(greeting.minY - raised) < 0.5, "morphing phases keeps the pill's slot in place")
        #expect(abs(composer.minY - restingComposer) < 0.5)

        hosting.rootView = probe(nil)
        settle()
        #expect(greeting.minY > raised + 10, "greeting glides back down once the pill collapses")
        #expect(abs(greeting.minY - resting) < 0.5)
        #expect(abs(composer.minY - restingComposer) < 0.5, "composer stays pinned when the pill collapses")
        #expect(abs(composer.minY - greeting.maxY - HomeUpdatePillMetrics.restingGap) < 0.5)
    }
}
