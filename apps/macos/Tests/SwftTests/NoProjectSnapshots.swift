import AppKit
import SwftDesign
import SwiftUI
import Testing
@testable import Swft

/// Offscreen snapshots for the No-Project feature states (light & dark).
/// Run with: `SWFT_SNAPSHOT_DIR=<scratch>/shots swift test --filter NoProjectSnapshots`
@MainActor
@Suite("NoProjectSnapshots", .enabled(if: ProcessInfo.processInfo.environment["SWFT_SNAPSHOT_DIR"] != nil))
struct NoProjectSnapshots {
    static let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SWFT_SNAPSHOT_DIR"] ?? NSTemporaryDirectory())

    @Test(arguments: ["light", "dark"])
    func homeProjectHoverClear(appearance: String) throws {
        let model = AppModel.mock()
        try Self.capture(
            model,
            appearance: appearance,
            name: "noproject-home-hover-\(appearance)",
            forceHoverClear: true
        )
    }

    @Test(arguments: ["light", "dark"])
    func homeNoProject(appearance: String) throws {
        let model = AppModel.mock()
        model.clearProject()
        try Self.capture(
            model,
            appearance: appearance,
            name: "noproject-home-cleared-\(appearance)"
        )
    }

    @Test(arguments: ["light", "dark"])
    func projectlessThread(appearance: String) throws {
        let model = AppModel.mock()
        model.clearProject()
        model.composerText = "Draft a short announcement for Swft's project-less threads"
        model.send()
        try Self.capture(
            model,
            appearance: appearance,
            name: "noproject-thread-\(appearance)"
        )
    }

    private static func capture(
        _ model: AppModel,
        appearance: String,
        name: String,
        size: CGSize = CGSize(width: 1280, height: 860),
        forceHoverClear: Bool = false
    ) throws {
        SwftFonts.register()
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -4000, y: -4000), size: size),
            styleMask: [.titled, .fullSizeContentView, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        let root = RootView()
            .environment(model)
            .environment(\.swftForceProjectChipClearVisible, forceHoverClear)
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        window.orderBack(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent("\(name).png"))
        window.orderOut(nil)
    }
}
