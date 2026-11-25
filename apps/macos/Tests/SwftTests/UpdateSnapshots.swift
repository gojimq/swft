import AppKit
import SwftDesign
import SwiftUI
import Testing
@testable import Swft

/// Offscreen screenshots of the Home update pill and Settings → About → Updates.
/// Skipped unless `SWFT_SNAPSHOT_DIR` is set:
///
///     SWFT_SNAPSHOT_DIR=<scratch>/shots swift test --filter UpdateSnapshots
@MainActor
@Suite("UpdateSnapshots", .enabled(if: ProcessInfo.processInfo.environment["SWFT_SNAPSHOT_DIR"] != nil))
struct UpdateSnapshots {
    private static func demoModel() -> AppModel {
        let world = DemoUpdateWorld(version: "0.9.0", localVersion: "0.1.0")!
        return AppModel.mock(updateServices: world.services)
    }

    @Test(arguments: ["light", "dark"])
    func homeAvailable(appearance: String) async throws {
        let model = Self.demoModel()
        await model.updates.checkForUpdates(userInitiated: false)
        try Snapshots.capture(model, appearance: appearance, name: "home-update-available-\(appearance)")
    }

    @Test(arguments: ["light", "dark"])
    func homeUpdating(appearance: String) async throws {
        let model = Self.demoModel()
        await model.updates.checkForUpdates(userInitiated: false)
        model.updates.startUpdate()
        try Snapshots.capture(model, appearance: appearance, name: "home-update-progress-\(appearance)")
    }

    @Test(arguments: ["light", "dark"])
    func settingsAbout(appearance: String) async throws {
        let model = Self.demoModel()
        await model.updates.checkForUpdates(userInitiated: false)
        model.openSettings(section: .about)
        try Snapshots.capture(model, appearance: appearance, name: "settings-about-updates-\(appearance)")
    }

    @Test(arguments: ["light", "dark"])
    func pillGallery(appearance: String) throws {
        let rows = [
            HomeUpdatePillRow(id: "mini", label: "Mac Mini", symbol: "macmini", detail: "Updated", tone: .success),
            HomeUpdatePillRow(id: "local", label: "This Mac", symbol: "laptopcomputer", detail: "Downloading 64%…", tone: .active),
        ]
        let failedRows = [
            HomeUpdatePillRow(id: "mini", label: "Mac Mini", symbol: "macmini", detail: "Rolled back to v0.1.0", tone: .failure),
            HomeUpdatePillRow(id: "local", label: "This Mac", symbol: "laptopcomputer", detail: "Waiting…", tone: .pending),
        ]
        let states: [HomeUpdatePillState] = [
            .available(message: "Swft v0.9.0 is available for 2 environments", actionTitle: "Update all", actionHelp: ""),
            .progress(headline: "Updating Mac Mini", detail: "Installing…", fraction: nil, rows: []),
            .progress(headline: "Updating Swft", detail: "Downloading 64%…", fraction: 0.64, rows: rows),
            .attention(summary: "Mac Mini couldn't update", rows: failedRows, canContinueLocal: true),
            .done(message: "All environments updated"),
            .failed(message: "Automatic app updates require running from a packaged Swft.app bundle."),
        ]
        let gallery = VStack(spacing: 24) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                HomeUpdatePill(state: state, actions: HomeUpdatePillActions())
            }
        }
        .padding(40)
        .frame(width: 900, height: 760)
        .background(GlowBackground())
        .background(SwftColor.canvas)
        try Self.capture(gallery, appearance: appearance, name: "update-pill-gallery-\(appearance)", size: CGSize(width: 900, height: 760))
    }

    private static func capture(_ view: some View, appearance: String, name: String, size: CGSize) throws {
        SwftFonts.register()
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -4000, y: -4000), size: size),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        window.orderBack(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: Snapshots.directory, withIntermediateDirectories: true)
        try png.write(to: Snapshots.directory.appendingPathComponent("\(name).png"))
        window.orderOut(nil)
    }
}
