import Foundation
import SwftDesign
import SwftKit

/// Connection phase surfaced in Connections settings and composer pickers.
enum RemoteEnvironmentPhase: Equatable, Hashable, Sendable {
    case connected
    case connecting
    case reconnecting(attempt: Int)
    case offline
    case failed(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var chipStatus: EnvironmentChipStatus {
        switch self {
        case .connected: .connected
        case .connecting, .reconnecting: .connecting
        case .offline, .failed: .offline
        }
    }
}

/// View-state snapshot of one execution environment (local Mac or paired remote server).
struct RemoteEnvironmentItem: Identifiable, Hashable, Sendable {
    let id: String
    var label: String
    var serverLabel: String
    var url: String?
    var isLocal: Bool
    var machine: EnvironmentMachineKind
    var phase: RemoteEnvironmentPhase
    var serverVersion: String?
    var errorDetail: String?
    var providerCount: Int
    var hasMissingCredentials: Bool

    var canRemove: Bool { !isLocal }
    var canRename: Bool { !isLocal }
    var canReconnect: Bool { !hasMissingCredentials && !phase.isConnected }

    var machineSymbol: String {
        RemoteLogic.machineSymbol(for: machine)
    }

    var statusSummary: String {
        switch phase {
        case .connected:
            if let serverVersion, !serverVersion.isEmpty {
                return "Connected · v\(serverVersion)"
            }
            return "Connected"
        case .connecting:
            return "Connecting…"
        case .reconnecting(let attempt):
            return attempt > 1 ? "Reconnecting (\(attempt))…" : "Reconnecting…"
        case .offline:
            return "Offline"
        case .failed:
            return hasMissingCredentials ? "Re-pair required" : "Offline"
        }
    }

    var chipItem: EnvironmentChipItem {
        EnvironmentChipItem(
            id: id,
            label: label,
            machineSymbol: machineSymbol,
            status: phase.chipStatus,
            isLocal: isLocal,
            detail: url
        )
    }
}

/// Pure multi-environment presentation and selection helpers mirroring Studio's `environment.logic.ts`.
enum RemoteLogic {
    static func machineSymbol(for kind: EnvironmentMachineKind) -> String {
        switch kind {
        case .laptop: "laptopcomputer"
        case .desktop: "desktopcomputer"
        case .server: "server.rack"
        case .unknown: "desktopcomputer"
        }
    }

    /// Primary (local) environment first, then remote environments sorted alphabetically by label.
    static func sortEnvironments(_ environments: [RemoteEnvironmentItem]) -> [RemoteEnvironmentItem] {
        environments.sorted { lhs, rhs in
            if lhs.isLocal != rhs.isLocal {
                return lhs.isLocal
            }
            let cmp = lhs.label.localizedCaseInsensitiveCompare(rhs.label)
            if cmp != .orderedSame {
                return cmp == .orderedAscending
            }
            return lhs.id < rhs.id
        }
    }

    /// Whether to surface machine labels on sidebar rows and headers to disambiguate hosts.
    static func shouldShowEnvironmentDisambiguation(environmentCount: Int, isRemote: Bool) -> Bool {
        environmentCount > 1 || isRemote
    }

    /// Matches Studio's `shouldShowComposerEnvironmentControl`:
    /// shown when more than one environment exists or when the active environment is remote.
    static func shouldShowComposerEnvironmentControl(
        environments: [RemoteEnvironmentItem],
        activeEnvironmentID: String?,
        threadIsRemote: Bool = false
    ) -> Bool {
        if environments.count > 1 { return true }
        if threadIsRemote { return true }
        if let activeID = activeEnvironmentID,
           let active = environments.first(where: { $0.id == activeID }),
           !active.isLocal
        {
            return true
        }
        return false
    }

    /// Picks the active environment ID: thread's own environment when known, else user-selected
    /// environment, else first connected environment, else first environment.
    static func resolveSelectedEnvironmentID(
        environments: [RemoteEnvironmentItem],
        threadEnvironmentID: String? = nil,
        selectedEnvironmentID: String? = nil
    ) -> String? {
        guard !environments.isEmpty else { return nil }
        if let threadEnvironmentID, environments.contains(where: { $0.id == threadEnvironmentID }) {
            return threadEnvironmentID
        }
        if let selectedEnvironmentID, environments.contains(where: { $0.id == selectedEnvironmentID }) {
            return selectedEnvironmentID
        }
        return environments.first(where: { $0.phase.isConnected })?.id ?? environments.first?.id
    }

    /// Finds the best matching project on a newly selected environment, preferring one with the
    /// same name as the previous project before falling back to the first project on that host.
    static func findProjectForEnvironment(
        projects: [ProjectRef],
        preferredName: String?
    ) -> ProjectRef? {
        guard !projects.isEmpty else { return nil }
        if let preferred = preferredName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !preferred.isEmpty,
           let exact = projects.first(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == preferred })
        {
            return exact
        }
        return projects.first
    }

    static func phase(from state: ConnectionState, hasMissingCredentials: Bool = false) -> RemoteEnvironmentPhase {
        if hasMissingCredentials {
            return .failed("Credentials missing — re-pair to reconnect.")
        }
        switch state {
        case .connected:
            return .connected
        case .connecting:
            return .connecting
        case .reconnecting(let attempt, _):
            return .reconnecting(attempt: attempt)
        case .disconnected:
            return .offline
        case .failed(let reason):
            return .failed(reason)
        }
    }

    static func errorDetail(from state: ConnectionState, hasMissingCredentials: Bool = false) -> String? {
        if hasMissingCredentials {
            return "Credentials missing from Keychain — re-pair to reconnect."
        }
        switch state {
        case .reconnecting(_, let reason): return reason
        case .failed(let reason): return reason
        default: return nil
        }
    }

    static func formatInviteExpiry(_ expiresAt: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "Expires at \(formatter.string(from: expiresAt))"
    }

    @MainActor
    static func environmentItem(from managed: ManagedEnvironment) -> RemoteEnvironmentItem {
        let readyCount = managed.threadsStore.providers.filter {
            $0.enabled && $0.installed && $0.status != .disabled
        }.count
        let state = managed.connectionState
        return RemoteEnvironmentItem(
            id: managed.id,
            label: managed.displayLabel,
            serverLabel: managed.threadsStore.environment?.label ?? managed.lastKnownLabel,
            url: managed.httpBaseURL.absoluteString,
            isLocal: managed.isLocal,
            machine: managed.machineKind,
            phase: phase(from: state, hasMissingCredentials: managed.hasMissingCredentials),
            serverVersion: managed.serverVersion,
            errorDetail: errorDetail(from: state, hasMissingCredentials: managed.hasMissingCredentials),
            providerCount: readyCount,
            hasMissingCredentials: managed.hasMissingCredentials
        )
    }
}

// MARK: - Additive SwftAdapters Extensions (keeps SwftKitAdapters.swift untouched)

extension SwftAdapters {
    @MainActor
    static func remoteThreadSummary(
        from shell: ThreadShell,
        environment: ManagedEnvironment,
        showEnvironmentLabel: Bool,
        activelyViewingThreadID: String?
    ) -> ThreadSummary {
        let store = environment.threadsStore
        let providersByID = Dictionary(
            uniqueKeysWithValues: store.providers.map { ($0.instanceId, $0) }
        )
        let hostLabel = environment.displayLabel
        var summary = threadSummary(
            from: shell,
            projectsByID: NoProjectLogic.nonScratchProjectsByID(
                projects: store.projects,
                scratchWorkspaceRoot: store.serverConfig?.scratchWorkspaceRoot
            ),
            providersByID: providersByID,
            hostName: hostLabel,
            activelyViewingThreadID: activelyViewingThreadID
        )
        summary.environmentID = environment.id
        summary.isRemoteEnvironment = !environment.isLocal
        summary.environmentMachineSymbol = RemoteLogic.machineSymbol(for: environment.machineKind)
        if showEnvironmentLabel {
            summary.environmentLabel = hostLabel
        }
        if var project = summary.project {
            project.environmentID = environment.id
            summary.project = project
        }
        return summary
    }

    static func projectRef(from project: ProjectShell, environmentID: String) -> ProjectRef {
        var ref = projectRef(from: project)
        ref.environmentID = environmentID
        return ref
    }
}
