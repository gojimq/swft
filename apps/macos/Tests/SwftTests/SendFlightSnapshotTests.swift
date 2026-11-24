import AppKit
import SwftDesign
import SwiftUI
import Testing
@testable import Swft

/// Offscreen screenshots verifying the send flight J-curve, stream room anchor, working indicator,
/// scroll-to-bottom button, and Reduce Motion path.
/// Run with: `SWFT_SNAPSHOT_DIR=/tmp/send-flight-shots swift test --filter SendFlightSnapshots`
@MainActor
@Suite("SendFlightSnapshots", .enabled(if: ProcessInfo.processInfo.environment["SWFT_SNAPSHOT_DIR"] != nil))
struct SendFlightSnapshots {
    static let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SWFT_SNAPSHOT_DIR"] ?? NSTemporaryDirectory())

    @Test(arguments: ["light", "dark"])
    func midFlightJCurve(appearance: String) throws {
        for (label, progress) in [("launch", 0.08), ("start", 0.18), ("mid", 0.45), ("near-land", 0.78)] {
            let model = AppModel.mock()
            model.destination = .thread(MockData.threadDetail.summary.id)
            try Self.capture(
                model,
                appearance: appearance,
                name: "send-flight-\(label)-\(appearance)",
                pinnedProgress: progress
            ) {
                model.composerText = "Port the J-shaped send flight and stream room"
                model.send()
                RunLoop.main.run(until: Date().addingTimeInterval(0.25))
            }
        }
    }

    @Test(arguments: ["light", "dark"])
    func landedWithStreamRoomAndWorking(appearance: String) throws {
        let model = AppModel.mock()
        model.destination = .thread(MockData.threadDetail.summary.id)
        try Self.capture(
            model,
            appearance: appearance,
            name: "send-flight-landed-\(appearance)"
        ) {
            model.composerText = "Port the J-shaped send flight and stream room"
            model.send()
            // Wait past SEND_MS (680ms) + WORKING_DELAY_MS (340ms) so the bubble lands and Working appears.
            RunLoop.main.run(until: Date().addingTimeInterval(1.15))
        }
    }

    @Test func reduceMotionInstantAnchor() throws {
        let model = AppModel.mock()
        model.destination = .thread(MockData.threadDetail.summary.id)
        try Self.capture(
            model,
            appearance: "light",
            name: "send-flight-reduce-motion-light",
            forceReduceMotion: true
        ) {
            model.composerText = "Instant anchor under Reduce Motion"
            model.send()
            RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        }
    }

    @Test func scrolledUpShowsScrollToBottomButton() throws {
        let model = AppModel.mock()
        model.destination = .thread(MockData.threadDetail.summary.id)
        try Self.capture(
            model,
            appearance: "light",
            name: "send-flight-scrolled-up-light"
        ) { host in
            // Scroll the transcript NSScrollView (right-most scroll view) up to the top.
            if let transcriptScroll = Self.findScrollViews(in: host).max(by: { $0.frame.width < $1.frame.width }) {
                transcriptScroll.contentView.scroll(to: .zero)
                transcriptScroll.reflectScrolledClipView(transcriptScroll.contentView)
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        }
    }

    private static func findScrollViews(in view: NSView) -> [NSScrollView] {
        var result: [NSScrollView] = []
        if let sv = view as? NSScrollView { result.append(sv) }
        for child in view.subviews { result.append(contentsOf: findScrollViews(in: child)) }
        return result
    }

    static func capture(
        _ model: AppModel,
        appearance: String,
        name: String,
        size: CGSize = CGSize(width: 1280, height: 860),
        pinnedProgress: Double? = nil,
        forceReduceMotion: Bool = false,
        then interact: () -> Void = {}
    ) throws {
        try capture(
            model,
            appearance: appearance,
            name: name,
            size: size,
            pinnedProgress: pinnedProgress,
            forceReduceMotion: forceReduceMotion,
            withHost: { _ in interact() }
        )
    }

    static func capture(
        _ model: AppModel,
        appearance: String,
        name: String,
        size: CGSize = CGSize(width: 1280, height: 860),
        pinnedProgress: Double? = nil,
        forceReduceMotion: Bool = false,
        withHost interact: (NSView) -> Void
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
            .environment(\.sendFlightPinnedProgress, pinnedProgress)
            .environment(\.sendFlightForceReduceMotion, forceReduceMotion)
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        window.orderBack(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        interact(host)
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent("\(name).png"))
        window.orderOut(nil)
    }
}
