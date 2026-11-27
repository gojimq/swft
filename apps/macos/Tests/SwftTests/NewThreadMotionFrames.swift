import AppKit
import SwftDesign
import SwiftUI
import Testing
@testable import Swft

/// Frame sequences of the new-thread motion, for reviewing timing without launching the app. Skipped unless
/// `SWFT_FRAMES_DIR` is set:
///
///     SWFT_FRAMES_DIR=/tmp/frames swift test --filter NewThreadMotionFrames
@MainActor
@Suite("NewThreadMotionFrames", .serialized, .enabled(if: ProcessInfo.processInfo.environment["SWFT_FRAMES_DIR"] != nil))
struct NewThreadMotionFrames {
    static let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SWFT_FRAMES_DIR"] ?? NSTemporaryDirectory())

    /// (a) "New thread" from an open thread: Home's greeting, composer, toggle and suggestions rise in, the glow blooms.
    @Test(arguments: ["light", "dark"])
    func homeArrival(appearance: String) async throws {
        let model = AppModel.mock()
        model.destination = .thread("t1")
        try await Self.record(model, name: "a-home-arrival-\(appearance)", appearance: appearance, frames: 16, interval: 0.04) {
            model.goHome()
        }
    }

    /// (b) Sending the first message from Home: content steps aside, the composer docks, the thread takes over and its
    /// row lands at the top of the inbox.
    @Test(arguments: ["light", "dark"])
    func launch(appearance: String) async throws {
        let model = AppModel.mock()
        try await Self.record(model, name: "b-launch-\(appearance)", appearance: appearance, frames: 28, interval: 0.04) {
            model.composerText = "Find and fix the failing test"
            model.send()
        }
    }

    /// (c) The generated title arriving: it crossfades in place in the sidebar row and the top bar.
    @Test(arguments: ["light", "dark"])
    func titleArrival(appearance: String) async throws {
        let model = AppModel.mock()
        model.open("t4")
        try await Self.record(model, name: "c-title-\(appearance)", appearance: appearance, frames: 12, interval: 0.04) {
            model.renameMockThread("t4", to: "Studio Roadmap Kickoff")
        }
    }

    /// Hammering "New thread" and a thread mid-launch: never two screens, and Home's content comes back.
    @Test func rapidClicksMidLaunch() async throws {
        let model = AppModel.mock()
        try await Self.record(model, name: "rapid-mid-launch", frames: 14, interval: 0.04) {
            model.composerText = "Explain how this repo is structured"
            model.send()
            await Self.pump(0.12)
            model.goHome()
            await Self.pump(0.05)
            model.open("t2")
            await Self.pump(0.05)
            model.goHome()
        }
    }

    static func record(
        _ model: AppModel,
        name: String,
        appearance: String = "light",
        frames: Int,
        interval: TimeInterval,
        size: CGSize = CGSize(width: 1280, height: 820),
        action: () async -> Void
    ) async throws {
        try await record(model, name: name, appearance: appearance, frames: frames, interval: interval, size: size) { _ in await action() }
    }

    static func record(
        _ model: AppModel,
        name: String,
        appearance: String = "light",
        frames: Int,
        interval: TimeInterval,
        size: CGSize = CGSize(width: 1280, height: 820),
        action: (NSWindow) async -> Void
    ) async throws {
        SwftFonts.register()
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -4000, y: -4000), size: size),
            styleMask: [.titled, .fullSizeContentView, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: RootView().environment(model))
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        window.orderBack(nil)
        await Self.pump(1.2)
        let folder = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        await action(window)
        let start = Date()
        for index in 0..<frames {
            await pump(until: start.addingTimeInterval(interval * Double(index)))
            host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: folder.appendingPathComponent(String(format: "%@-%03d.png", name, index)))
        }
        window.orderOut(nil)
    }

    /// Spins the run loop (SwiftUI's updates and animations) in short slices, yielding between them so main-actor
    /// tasks the app schedules (the launch hand-off) get to run too.
    static func pump(until date: Date) async {
        repeat {
            spin(until: min(date, Date().addingTimeInterval(0.005)))
            await Task.yield()
        } while Date() < date
    }

    private static func spin(until date: Date) {
        RunLoop.main.run(until: date)
    }

    static func pump(_ seconds: TimeInterval) async {
        await pump(until: Date().addingTimeInterval(seconds))
    }
}
