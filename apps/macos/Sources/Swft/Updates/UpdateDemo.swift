import Foundation
import Observation
import SwftKit

/// `SWFT_DEMO_UPDATE_VERSION=0.9.0` swaps the real updater for a timed simulation (a remote "Mac Mini" plus this Mac),
/// so every frame of the Home pill choreography can be inspected without replacing the running binary.
@MainActor
@Observable
final class DemoUpdateWorld {
    static let environmentKey = "SWFT_DEMO_UPDATE_VERSION"
    static let remoteID = "demo-mac-mini"

    let release: SwftReleaseInfo
    let localVersion: String
    private(set) var remoteVersion: String
    private(set) var remoteConnected = true

    init?(version: String, localVersion: String) {
        guard let semver = SwftSemver(version) else { return nil }
        let base = URL(string: "https://github.com/gojimq/swft/releases/tag/v\(semver.raw)")!
        self.release = SwftReleaseInfo(
            version: semver.raw,
            semver: semver,
            tagName: "v\(semver.raw)",
            name: "Swft v\(semver.raw)",
            notes: "",
            htmlURL: base,
            publishedAt: nil,
            macosAppAsset: nil,
            serverAssets: [:],
            checksumsAsset: nil
        )
        self.localVersion = localVersion
        self.remoteVersion = localVersion
    }

    static func fromEnvironment(localVersion: String) -> DemoUpdateWorld? {
        guard let raw = ProcessInfo.processInfo.environment[environmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return DemoUpdateWorld(version: raw, localVersion: localVersion)
    }

    var environments: [UpdateEnvironmentSnapshot] {
        [
            UpdateEnvironmentSnapshot(
                id: "demo-local", label: UpdateLogic.localLabel, isLocal: true, isConnected: true,
                serverVersion: localVersion, selfUpdateCapability: .desktopManaged, desktopAppUpdate: true,
                machineSymbol: "laptopcomputer"
            ),
            UpdateEnvironmentSnapshot(
                id: Self.remoteID, label: "Mac Mini", isLocal: false, isConnected: remoteConnected,
                serverVersion: remoteVersion, selfUpdateCapability: .bootService, desktopAppUpdate: false,
                machineSymbol: "macmini"
            ),
        ]
    }

    private func pause(_ seconds: Double) async throws {
        try await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }

    func updateRemote(onProgress: @escaping @Sendable (ServerSelfUpdateProgressStage) -> Void) async throws -> ServerSelfUpdateResult {
        onProgress(.downloading)
        try await pause(1.6)
        onProgress(.installing)
        try await pause(1.2)
        // The service launcher takes over: the server drops off, then returns on the new version.
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await self.pause(0.4)
            self.remoteConnected = false
            try? await self.pause(1.6)
            self.remoteVersion = self.release.version
            self.remoteConnected = true
        }
        return ServerSelfUpdateResult(targetVersion: release.version, method: .bootService, updateId: "demo")
    }

    func stageLocalApp(onStage: @escaping @Sendable (LocalAppUpdateStage) -> Void) async throws -> StagedAppUpdate {
        for step in 0...20 {
            onStage(.downloading(fraction: Double(step) / 20))
            try await pause(0.09)
        }
        onStage(.verifying)
        try await pause(0.9)
        onStage(.extracting)
        try await pause(0.9)
        onStage(.ready)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swft-demo-update", isDirectory: true)
        return StagedAppUpdate(version: release.version, stagingDirectory: dir, appURL: dir.appendingPathComponent("Swft.app"), sha256: "")
    }

    var services: UpdateServices {
        UpdateServices(
            fetchLatestRelease: { [release] in release },
            // Strong captures: the coordinator owns these services, and the world must outlive the demo.
            environments: { self.environments },
            localAppVersion: { [localVersion] in localVersion },
            localAppEligibility: { .eligible(appURL: URL(fileURLWithPath: "/Applications/Swft.app")) },
            updateRemote: { _, _, onProgress in try await self.updateRemote(onProgress: onProgress) },
            stageLocalApp: { _, onStage in try await self.stageLocalApp(onStage: onStage) },
            installAndRelaunch: { _ in
                try await Task.sleep(for: .milliseconds(900))
                return false
            },
            sleep: { try await Task.sleep(for: $0) },
            hasSavedToken: { false },
            saveToken: { _ in },
            deleteToken: {},
            defaults: nil,
            backgroundInterval: .seconds(4 * 60 * 60),
            initialConnectWait: .zero
        )
    }
}
