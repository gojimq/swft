import AppKit
import Foundation
import SwftDesign
import SwiftUI
import Testing
@testable import Swft
@testable import SwftKit

@Suite("Remote UI Logic, Multi-Environment Routing & Snapshots")
struct RemoteViewTests {

    @Test func sortsAndResolvesEnvironmentsMatchingStudioBehavior() {
        let local = RemoteEnvironmentItem(
            id: "local",
            label: "MacBook Pro",
            serverLabel: "MacBook Pro",
            url: "http://127.0.0.1:3773",
            isLocal: true,
            machine: .laptop,
            phase: .connected,
            serverVersion: "0.1.11",
            errorDetail: nil,
            providerCount: 3,
            hasMissingCredentials: false
        )
        let studio = RemoteEnvironmentItem(
            id: "studio",
            label: "Mac Studio",
            serverLabel: "Mac Studio",
            url: "https://studio.example.com",
            isLocal: false,
            machine: .desktop,
            phase: .connected,
            serverVersion: "0.1.11",
            errorDetail: nil,
            providerCount: 2,
            hasMissingCredentials: false
        )
        let build = RemoteEnvironmentItem(
            id: "build",
            label: "Build Server",
            serverLabel: "Build Server",
            url: "https://build.example.com",
            isLocal: false,
            machine: .server,
            phase: .offline,
            serverVersion: nil,
            errorDetail: "Offline",
            providerCount: 0,
            hasMissingCredentials: false
        )

        let sorted = RemoteLogic.sortEnvironments([studio, build, local])
        #expect(sorted.map(\.id) == ["local", "build", "studio"])

        // Composer environment chip visibility
        #expect(!RemoteLogic.shouldShowComposerEnvironmentControl(environments: [local], activeEnvironmentID: "local"))
        #expect(RemoteLogic.shouldShowComposerEnvironmentControl(environments: [local, studio], activeEnvironmentID: "local"))
        #expect(RemoteLogic.shouldShowComposerEnvironmentControl(environments: [studio], activeEnvironmentID: "studio"))
        #expect(RemoteLogic.shouldShowComposerEnvironmentControl(environments: [local], activeEnvironmentID: "local", threadIsRemote: true))

        // Selection precedence: thread > user selection > first connected > first
        #expect(RemoteLogic.resolveSelectedEnvironmentID(environments: sorted, threadEnvironmentID: "studio", selectedEnvironmentID: "local") == "studio")
        #expect(RemoteLogic.resolveSelectedEnvironmentID(environments: sorted, threadEnvironmentID: nil, selectedEnvironmentID: "studio") == "studio")
        #expect(RemoteLogic.resolveSelectedEnvironmentID(environments: [build, studio], threadEnvironmentID: nil, selectedEnvironmentID: nil) == "studio")
    }

    @Test func findsBestMatchingProjectWhenSwitchingEnvironments() {
        let projects = [
            ProjectRef(id: "p1", name: "Alpha", initials: "AL", tint: 0, environmentID: "studio"),
            ProjectRef(id: "p2", name: "Swft", initials: "SW", tint: 1, environmentID: "studio"),
        ]
        #expect(RemoteLogic.findProjectForEnvironment(projects: projects, preferredName: "swft")?.id == "p2")
        #expect(RemoteLogic.findProjectForEnvironment(projects: projects, preferredName: "missing")?.id == "p1")
        #expect(RemoteLogic.findProjectForEnvironment(projects: [], preferredName: "swft") == nil)
    }

    @Test func inboxModelShowsMachineSubtitleForMultiEnvironmentThreads() {
        let now = MockData.now

        // Single-environment thread preserves plain branch subtitle
        let singleEnv = ThreadSummary(
            id: "t1",
            title: "Single env",
            project: MockData.swft,
            location: .branch("main"),
            provider: .claude,
            activity: .idle,
            updatedAt: now
        )
        let singleModel = singleEnv.inboxModel(now: now)
        #expect(singleModel.location == "main")
        #expect(singleModel.locationSymbol == "arrow.triangle.branch")

        // Remote multi-environment thread with branch displays host + branch and machine glyph
        let remoteBranch = ThreadSummary(
            id: "t2",
            title: "Remote branch",
            project: MockData.swft,
            location: .branch("feat/gpu"),
            provider: .codex,
            activity: .running,
            updatedAt: now,
            environmentID: "studio",
            environmentLabel: "Mac Studio",
            isRemoteEnvironment: true,
            environmentMachineSymbol: "desktopcomputer"
        )
        let remoteBranchModel = remoteBranch.inboxModel(now: now)
        #expect(remoteBranchModel.location == "Mac Studio · feat/gpu")
        #expect(remoteBranchModel.locationSymbol == "desktopcomputer")

        // Remote thread without branch displays host name and machine glyph
        let remoteHost = ThreadSummary(
            id: "t3",
            title: "Remote host only",
            project: MockData.swft,
            location: .host("Build Box"),
            provider: .codex,
            activity: .idle,
            updatedAt: now,
            environmentID: "build",
            environmentLabel: "Build Box",
            isRemoteEnvironment: true,
            environmentMachineSymbol: "server.rack"
        )
        let remoteHostModel = remoteHost.inboxModel(now: now)
        #expect(remoteHostModel.location == "Build Box")
        #expect(remoteHostModel.locationSymbol == "server.rack")
    }

    @Test @MainActor func appModelSwitchesProjectsModelsAndManagesRemotesInMultiEnvMode() async throws {
        let model = AppModel.mockMultiEnvironment()
        #expect(model.isMultiEnvironment)
        #expect(model.shouldShowComposerEnvironmentPicker)
        #expect(model.remoteEnvironments.count == 3)
        #expect(model.activeComposerEnvironment?.isLocal == true)
        #expect(model.projects.contains(where: { $0.name == "Swft" }))

        // Switch Home composer target to remote Mac Studio -> projects & models switch!
        model.selectEnvironment("env-remote-studio")
        #expect(model.activeComposerEnvironmentID == "env-remote-studio")
        #expect(model.projects.map(\.name) == ["ML Runner", "Cluster Infra"])
        #expect(model.selectedProject?.name == "ML Runner")
        #expect(model.availableModels.count == 5)

        // Pair a new remote, rename it, and remove it
        let added = try await model.pairRemoteEnvironment(
            address: "https://lab-gpu.example.com/pair#token=TEST-PAIR"
        )
        #expect(model.remoteEnvironments.contains(where: { $0.id == added.id }))

        try model.renameRemoteEnvironment(id: added.id, customLabel: "GPU Box")
        #expect(model.remoteEnvironments.first(where: { $0.id == added.id })?.label == "GPU Box")

        try await model.removeRemoteEnvironment(id: added.id)
        #expect(!model.remoteEnvironments.contains(where: { $0.id == added.id }))
    }

    @Test func generatesScannableQRCodeImage() {
        let image = QRCodeView.makeCGImage(from: "https://amber-river.trycloudflare.com/pair#token=ABC123")
        #expect(image != nil)
        #expect((image?.width ?? 0) >= 21)
        #expect((image?.height ?? 0) >= 21)
        #expect(QRCodeView.makeCGImage(from: "   ") == nil)
    }
}

/// Offscreen screenshots of the remote connections & multi-environment UI (written only when `SWFT_SNAPSHOT_DIR` is set).
@MainActor
@Suite("RemoteSnapshots", .enabled(if: ProcessInfo.processInfo.environment["SWFT_SNAPSHOT_DIR"] != nil))
struct RemoteSnapshots {
    @Test(arguments: ["light", "dark"])
    func connectionsSettings(appearance: String) throws {
        let model = AppModel.mockMultiEnvironment()
        model.destination = .settings
        try Snapshots.capture(model, appearance: appearance, name: "connections-settings-\(appearance)")
    }

    @Test(arguments: ["light", "dark"])
    func homeMultiEnvironment(appearance: String) throws {
        let model = AppModel.mockMultiEnvironment()
        model.selectEnvironment("env-remote-studio")
        try Snapshots.capture(model, appearance: appearance, name: "home-multi-env-\(appearance)")
    }

    @Test(arguments: ["light", "dark"])
    func connectionsWithPairingQR(appearance: String) throws {
        SwftFonts.register()
        let model = AppModel.mockMultiEnvironment()
        let invite = PairingInvite(
            pairingURL: "https://amber-river-4821.trycloudflare.com/pair#token=SWFT-PAIR-7F9K-3M2Q",
            token: "SWFT-PAIR-7F9K-3M2Q",
            expiresAt: MockData.now.addingTimeInterval(300),
            origin: "https://amber-river-4821.trycloudflare.com",
            environmentId: "env-local-macbook"
        )
        let size = CGSize(width: 960, height: 960)
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -4000, y: -4000), size: size),
            styleMask: [.titled, .fullSizeContentView, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        let host = NSHostingView(
            rootView: ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Connections")
                        .font(SwftType.title)
                        .foregroundStyle(SwftColor.textPrimary)
                    ConnectionsSettingsView(previewInvite: invite)
                }
                .frame(maxWidth: SwftLayout.contentMaxWidth, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
            }
            .background(SwftColor.canvas)
            .environment(model)
        )
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        window.orderBack(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: Snapshots.directory, withIntermediateDirectories: true)
        try png.write(to: Snapshots.directory.appendingPathComponent("connections-qr-\(appearance).png"))
        window.orderOut(nil)
    }
}
