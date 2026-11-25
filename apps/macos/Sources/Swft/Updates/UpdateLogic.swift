import Foundation
import SwftDesign
import SwftKit

/// What the updater needs to know about one environment (this Mac's bundled server or a paired remote).
struct UpdateEnvironmentSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let isLocal: Bool
    let isConnected: Bool
    let serverVersion: String?
    let selfUpdateCapability: ServerSelfUpdateCapability?
    let desktopAppUpdate: Bool
    let machineSymbol: String
}

enum UpdateTargetStatus: Equatable, Sendable {
    case queued
    case downloading(fraction: Double?)
    case verifying
    case installing
    case restarting
    case succeeded
    case failed(String)
    case skipped(reason: String)

    var isActive: Bool {
        switch self {
        case .downloading, .verifying, .installing, .restarting: true
        default: false
        }
    }

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }

    /// Server progress events may land after the coordinator has moved on; only these states accept them.
    var acceptsServerProgress: Bool {
        switch self {
        case .queued, .downloading, .installing: true
        default: false
        }
    }
}

struct UpdateTargetEntry: Identifiable, Equatable, Sendable {
    static let localID = "swft.local-app"

    let id: String
    let label: String
    let machineSymbol: String
    let isLocal: Bool
    let currentVersion: String?
    let targetVersion: String
    var status: UpdateTargetStatus
}

struct UpdatePlan: Equatable, Sendable {
    let release: SwftReleaseInfo
    let remoteTargets: [UpdateTargetEntry]
    let skippedRemotes: [UpdateTargetEntry]
    let needsLocalAppUpdate: Bool
    let localTarget: UpdateTargetEntry

    var hasActionableUpdate: Bool { !remoteTargets.isEmpty || needsLocalAppUpdate }
    var targetCount: Int { remoteTargets.count + (needsLocalAppUpdate ? 1 : 0) }

    /// Remotes first, this Mac last: the order the update runs in.
    var orderedTargets: [UpdateTargetEntry] {
        remoteTargets + (needsLocalAppUpdate ? [localTarget] : [])
    }
}

enum UpdatePillPhase: Equatable, Sendable {
    case hidden
    case available(version: String, targetCount: Int, remoteCount: Int, includesLocalApp: Bool)
    case updating(headline: String, detail: String?, progress: Double?, targets: [UpdateTargetEntry])
    case partialFailure(summary: String, targets: [UpdateTargetEntry], canContinueLocal: Bool)
    /// Brief confirmation beat before the pill collapses.
    case completed(message: String)
    case failed(message: String)

    var isVisible: Bool { self != .hidden }
}

/// Outcome of watching a remote come back after it handed its update to the service launcher.
enum UpdateReconnectVerdict: Equatable, Sendable {
    case waiting
    case updated
    case rolledBack(String)
}

/// Per-environment badge in Settings → About → Updates.
enum EnvironmentUpdateReadiness: Equatable, Sendable {
    case upToDate
    case updateAvailable
    case readyForRemoteUpdates
    case needsServiceInstall
    case offline

    var title: String {
        switch self {
        case .upToDate: "Up to date"
        case .updateAvailable: "Update available"
        case .readyForRemoteUpdates: "Ready for remote updates"
        case .needsServiceInstall: "Needs service install"
        case .offline: "Offline"
        }
    }
}

enum UpdateLogic {
    static let localLabel = "This Mac"
    static let serviceInstallReason = "Install Swft server service to enable remote updates"
    static let offlineReason = "Offline"
    static let desktopManagedReason = "Update Swft on that Mac to update its server"

    // MARK: Versions

    /// Unknown or unparseable versions never trigger an update: we only replace what we can compare.
    static func isBehind(_ version: String?, target: SwftSemver) -> Bool {
        guard let version, let current = SwftSemver(version) else { return false }
        return current < target
    }

    static func isAtLeast(_ version: String?, target: SwftSemver) -> Bool {
        guard let version, let current = SwftSemver(version) else { return false }
        return current >= target
    }

    static func canSelfUpdate(_ environment: UpdateEnvironmentSnapshot) -> Bool {
        switch environment.selfUpdateCapability {
        case .bootService, .respawn: true
        case .desktopManaged: environment.desktopAppUpdate
        case nil: false
        }
    }

    // MARK: Planning

    static func makePlan(
        release: SwftReleaseInfo,
        localAppVersion: String,
        localAppEligible: Bool,
        environments: [UpdateEnvironmentSnapshot]
    ) -> UpdatePlan {
        let target = release.semver
        var remoteTargets: [UpdateTargetEntry] = []
        var skipped: [UpdateTargetEntry] = []

        for env in environments where !env.isLocal {
            let entry = { (status: UpdateTargetStatus) in
                UpdateTargetEntry(
                    id: env.id,
                    label: env.label,
                    machineSymbol: env.machineSymbol,
                    isLocal: false,
                    currentVersion: env.serverVersion,
                    targetVersion: release.version,
                    status: status
                )
            }
            if !env.isConnected {
                // A remote last seen on the release is fine; anything else we can't vouch for.
                if !isAtLeast(env.serverVersion, target: target) {
                    skipped.append(entry(.skipped(reason: offlineReason)))
                }
                continue
            }
            guard isBehind(env.serverVersion, target: target) else { continue }
            if canSelfUpdate(env) {
                remoteTargets.append(entry(.queued))
            } else {
                let reason = env.selfUpdateCapability == .desktopManaged ? desktopManagedReason : serviceInstallReason
                skipped.append(entry(.skipped(reason: reason)))
            }
        }

        let local = environments.first(where: \.isLocal)
        let appBehind = isBehind(localAppVersion, target: target)
        let localServerBehind = localAppEligible && isBehind(local?.serverVersion, target: target)
        let localTarget = UpdateTargetEntry(
            id: UpdateTargetEntry.localID,
            label: localLabel,
            machineSymbol: local?.machineSymbol ?? "laptopcomputer",
            isLocal: true,
            currentVersion: localAppVersion,
            targetVersion: release.version,
            status: .queued
        )
        return UpdatePlan(
            release: release,
            remoteTargets: remoteTargets,
            skippedRemotes: skipped,
            needsLocalAppUpdate: appBehind || localServerBehind,
            localTarget: localTarget
        )
    }

    static func availablePhase(for plan: UpdatePlan) -> UpdatePillPhase {
        .available(
            version: plan.release.version,
            targetCount: plan.targetCount,
            remoteCount: plan.remoteTargets.count,
            includesLocalApp: plan.needsLocalAppUpdate
        )
    }

    // MARK: Reconnect

    /// Right after the hand-off the old server is often still answering, so an old version only means a rollback
    /// once we have seen it go away and come back.
    static func reconnectVerdict(
        isConnected: Bool,
        serverVersion: String?,
        target: SwftSemver,
        sawDisconnect: Bool
    ) -> UpdateReconnectVerdict {
        guard isConnected else { return .waiting }
        if isAtLeast(serverVersion, target: target) { return .updated }
        if sawDisconnect, let serverVersion { return .rolledBack(serverVersion) }
        return .waiting
    }

    static func reconnectTimeoutMessage(label: String, isConnected: Bool, serverVersion: String?) -> String {
        if isConnected, let serverVersion {
            return "Still on v\(serverVersion) after restart"
        }
        return "\(label) didn't come back online"
    }

    // MARK: Copy

    static func actionHeadline(version: String, targetCount: Int) -> String {
        targetCount > 1 ? "Update \(targetCount) environments to v\(version)" : "Update to v\(version)"
    }

    static func actionTitle(targetCount: Int) -> String {
        targetCount > 1 ? "Update all" : "Update"
    }

    static func availableMessage(version: String, targetCount: Int) -> String {
        targetCount > 1 ? "Swft v\(version) is available for \(targetCount) environments" : "Swft v\(version) is available"
    }

    static func statusDetail(_ status: UpdateTargetStatus) -> String {
        switch status {
        case .queued: "Waiting…"
        case .downloading(let fraction):
            fraction.map { "Downloading \(percent($0))%…" } ?? "Downloading…"
        case .verifying: "Verifying…"
        case .installing: "Installing…"
        case .restarting: "Restarting…"
        case .succeeded: "Updated"
        case .failed(let message): message
        case .skipped(let reason): reason
        }
    }

    static func percent(_ fraction: Double) -> Int {
        Int((min(max(fraction, 0), 1) * 100).rounded(.down))
    }

    private static func subject(_ entry: UpdateTargetEntry) -> String {
        entry.isLocal ? "Swft" : entry.label
    }

    static func updatingPhase(targets: [UpdateTargetEntry]) -> UpdatePillPhase {
        let active = targets.filter(\.status.isActive)
        if active.count == 1, let entry = active.first {
            var fraction: Double?
            if case .downloading(let value) = entry.status { fraction = value.map { min(max($0, 0), 1) } }
            return .updating(
                headline: "Updating \(subject(entry))",
                detail: statusDetail(entry.status),
                progress: fraction,
                targets: targets
            )
        }
        if active.count > 1 {
            let details = Set(active.map { statusDetail($0.status) })
            return .updating(
                headline: "Updating \(active.count) environments",
                detail: details.count == 1 ? details.first : nil,
                progress: nil,
                targets: targets
            )
        }
        return .updating(headline: "Preparing update…", detail: nil, progress: nil, targets: targets)
    }

    static func partialFailureSummary(targets: [UpdateTargetEntry]) -> String {
        let failed = targets.filter(\.status.isFailure)
        if failed.count == 1, let entry = failed.first {
            return entry.isLocal ? "Swft couldn't update on this Mac" : "\(entry.label) couldn't update"
        }
        return "\(failed.count) environments couldn't update"
    }

    static func completionMessage(targets: [UpdateTargetEntry]) -> String {
        if targets.count == 1, let entry = targets.first {
            return entry.isLocal ? "Swft is up to date" : "\(entry.label) is up to date"
        }
        return "All environments updated"
    }

    // MARK: Settings

    static func readiness(
        of environment: UpdateEnvironmentSnapshot,
        localAppVersion: String,
        release: SwftReleaseInfo?
    ) -> EnvironmentUpdateReadiness? {
        if environment.isLocal {
            guard let release else { return nil }
            return isBehind(localAppVersion, target: release.semver) ? .updateAvailable : .upToDate
        }
        guard environment.isConnected else { return .offline }
        guard canSelfUpdate(environment) else { return .needsServiceInstall }
        guard let release else { return .readyForRemoteUpdates }
        return isBehind(environment.serverVersion, target: release.semver) ? .updateAvailable : .upToDate
    }

    // MARK: Pill presentation

    static func pillState(for phase: UpdatePillPhase) -> HomeUpdatePillState? {
        switch phase {
        case .hidden:
            return nil
        case .available(let version, let targetCount, _, _):
            return .available(
                message: availableMessage(version: version, targetCount: targetCount),
                actionTitle: actionTitle(targetCount: targetCount),
                actionHelp: actionHeadline(version: version, targetCount: targetCount)
            )
        case .updating(let headline, let detail, let progress, let targets):
            return .progress(headline: headline, detail: detail, fraction: progress, rows: pillRows(targets))
        case .partialFailure(let summary, let targets, let canContinueLocal):
            return .attention(summary: summary, rows: pillRows(targets), canContinueLocal: canContinueLocal)
        case .completed(let message):
            return .done(message: message)
        case .failed(let message):
            return .failed(message: message)
        }
    }

    /// Per-machine rows only earn their space when more than one machine is involved.
    static func pillRows(_ targets: [UpdateTargetEntry]) -> [HomeUpdatePillRow] {
        guard targets.count > 1 else { return [] }
        return targets.map { entry in
            HomeUpdatePillRow(
                id: entry.id,
                label: entry.label,
                symbol: entry.machineSymbol,
                detail: statusDetail(entry.status),
                tone: tone(entry.status)
            )
        }
    }

    private static func tone(_ status: UpdateTargetStatus) -> HomeUpdatePillRow.Tone {
        switch status {
        case .queued, .skipped: .pending
        case .downloading, .verifying, .installing, .restarting: .active
        case .succeeded: .success
        case .failed: .failure
        }
    }
}
