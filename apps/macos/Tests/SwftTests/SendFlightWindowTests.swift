import AppKit
import SwftDesign
import SwiftUI
import Testing
@testable import Swft

/// Drives a real offscreen `NSWindow` to check the send choreography where it actually runs: SwiftUI's animated
/// `ScrollPosition` on the transcript's `NSScrollView`.
@MainActor
@Suite("SendFlightWindow", .serialized)
struct SendFlightWindowTests {
    /// Regression: the scroll used to be re-targeted from a 120Hz `TimelineView`, stalled until the server echo, then
    /// lurched and snapped at the end. It must glide from where it was to the new end in one continuous motion.
    @Test func sendInALongThreadGlidesToTheNewTurnInOneMotion() throws {
        let model = AppModel.mock()
        model.destination = .thread(MockData.threadDetail.summary.id)
        let (window, host) = Self.present(model)
        defer { window.orderOut(nil) }
        let scroll = try #require(Self.transcriptScrollView(in: host))
        let before = scroll.contentView.bounds.origin.y

        model.composerText = "Ship the smoother send flight"
        model.send()
        // Sampled without yielding the main actor, so parallel suites cannot starve the run loop mid-glide.
        let samples = Self.sampleOffsets(of: scroll, for: 1.0)
        let end = try #require(samples.last?.offset)
        let documentHeight = scroll.documentView?.frame.height ?? 0
        let maxOffset = documentHeight - scroll.contentView.bounds.height

        // It reaches the new end (the sent prompt resting at the top over its stream room)...
        #expect(end > before + 40)
        #expect(abs(end - maxOffset) < 1.5)
        // ...without teleporting: early on it has covered well under half the way (the curve eases in)...
        if let early = samples.first(where: { $0.time < 0.1 }) {
            #expect(early.offset - before < (end - before) * 0.5)
        }
        // ...through intermediate positions, always forward (no lurch back, no snap past the end).
        #expect(samples.contains { $0.offset > before + 1 && $0.offset < end - 1 })
        for (previous, next) in zip(samples, samples.dropFirst()) {
            #expect(next.offset >= previous.offset - 0.5)
            #expect(next.offset <= end + 0.5)
        }
    }

    /// The first message of a brand-new thread fits on one screen: nothing scrolls, so it cannot hitch at the top.
    @Test func newThreadFirstTurnFillsTheViewportWithoutOverflow() async throws {
        let model = AppModel.mock()
        model.composerText = "Plan the onboarding flow"
        let (window, host) = Self.present(model)
        defer { window.orderOut(nil) }
        model.send()
        // Home's own dock animation reports settling; wait for it plus the first message's flight.
        let start = Date()
        while Date().timeIntervalSince(start) < 1.6 { await Self.tick() }

        guard case .thread = model.destination else {
            Issue.record("Home did not hand off to the new thread")
            return
        }
        let scroll = try #require(Self.transcriptScrollView(in: host))
        let documentHeight = scroll.documentView?.frame.height ?? 0
        #expect(documentHeight <= scroll.contentView.bounds.height + 0.5)
        #expect(scroll.contentView.bounds.origin.y < 0.5)
    }

    /// One display frame of run loop, then a yield so main-actor tasks (the launch's hand-off) get to run.
    private static func tick() async {
        pump(1.0 / 60.0)
        await Task.yield()
    }

    private static func sampleOffsets(of scroll: NSScrollView, for duration: TimeInterval) -> [(time: TimeInterval, offset: CGFloat)] {
        var samples: [(time: TimeInterval, offset: CGFloat)] = []
        let start = Date()
        while Date().timeIntervalSince(start) < duration {
            pump(1.0 / 120.0)
            samples.append((Date().timeIntervalSince(start), scroll.contentView.bounds.origin.y))
        }
        return samples
    }

    private static func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private static func present(_ model: AppModel) -> (NSWindow, NSView) {
        SwftFonts.register()
        let size = CGSize(width: 1280, height: 860)
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -4000, y: -4000), size: size),
            styleMask: [.titled, .fullSizeContentView, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        let host = NSHostingView(rootView: RootView().environment(model))
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        window.orderBack(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        return (window, host)
    }

    /// The transcript is the widest scroll view in the window (the sidebar's is narrower).
    private static func transcriptScrollView(in view: NSView) -> NSScrollView? {
        func all(_ view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? [] + view.subviews.flatMap(all)
        }
        return all(view).max { $0.frame.width < $1.frame.width }
    }
}
