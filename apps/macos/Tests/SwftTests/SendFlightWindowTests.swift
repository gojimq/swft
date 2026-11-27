import AppKit
import SwftDesign
import SwiftUI
import Testing
@testable import Swft

/// Drives a real offscreen `NSWindow` to verify the send choreography where it actually runs:
/// `SendFlightScrollDriver` on the transcript's `NSScrollView` and Home → Thread handoff.
@MainActor
@Suite("SendFlightWindow", .serialized)
struct SendFlightWindowTests {
    /// Regression: the scroll used to run through SwiftUI's `ScrollPosition` animation, stepping in coarse whole
    /// points with uneven cadence and velocity jitter. It must glide smoothly from where it was to the new end in one
    /// continuous display-synced motion.
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
        let samples = Self.sampleOffsets(of: scroll, for: 0.9)
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
        // ...through intermediate sub-pixel positions, always forward (no lurch back, no snap past the end).
        #expect(samples.contains { $0.offset > before + 1 && $0.offset < end - 1 })
        #expect(samples.contains { abs($0.offset - $0.offset.rounded()) > 0.01 })
        for (previous, next) in zip(samples, samples.dropFirst()) {
            #expect(next.offset >= previous.offset - 0.5)
            #expect(next.offset <= end + 0.5)
        }
    }

    /// Sending in a realistic 20-turn rich-markdown thread while live server updates stream in mid-scroll must keep
    /// gliding monotonically at sub-pixel precision and land cleanly at the bottom.
    @Test func richLongThreadWithLiveUpdatesGlidesSmoothly() throws {
        var items: [TranscriptItem] = []
        let base = MockData.now.addingTimeInterval(-3600)
        for i in 0..<20 {
            items.append(.init(id: "u-\(i)", kind: .user("Turn \(i): Explain how scroll position and LazyVStack interact on macOS during send flight."), startedAt: base.addingTimeInterval(Double(i * 60))))
            items.append(.init(id: "t-\(i)", kind: .toolCall(.init(kind: .read, title: "Read", detail: "Sources/Swft/Screens/ThreadView.swift", status: .succeeded, duration: 0.2, output: "struct ThreadView {}")), startedAt: base.addingTimeInterval(Double(i * 60 + 1)), completedAt: base.addingTimeInterval(Double(i * 60 + 2))))
            items.append(.init(id: "a-\(i)", kind: .assistant(blocks: [
                .text("## Turn \(i) summary\nHere is a **detailed** explanation of `ScrollPosition` and `NSClipView` animation.\n- First item with `inline code` and **bold text**.\n- Second item explaining `LazyVStack` measurement.\n- Third item covering `PreferenceKey` updates."),
                .code(language: "swift", source: "func scrollToBottom() {\n    // turn \(i)\n    driver.animateToBottom(duration: 0.68, curve: .send)\n}"),
            ], streaming: false), startedAt: base.addingTimeInterval(Double(i * 60 + 3)), completedAt: base.addingTimeInterval(Double(i * 60 + 10))))
        }

        let model = AppModel.mock()
        let summary = MockData.threads[0]
        let box = WindowDetailBox(ThreadDetailState(summary: summary, items: items, diffStat: "+142 −38", isRunning: false))
        let (window, host) = Self.presentCustom(WindowThreadHarness(model: model, box: box), size: CGSize(width: 1000, height: 860))
        defer { window.orderOut(nil) }

        let scroll = try #require(Self.transcriptScrollView(in: host))
        let before = scroll.contentView.bounds.origin.y

        let msgID = "u-live-new"
        box.detail.items.append(.init(id: msgID, kind: .user("Investigate laggy scroll-up during send flight.")))
        box.detail.isRunning = true
        model.latestThreadSend = ThreadSendEvent(
            threadID: summary.id,
            text: "Investigate laggy scroll-up during send flight.",
            optimisticItemID: msgID
        )

        var samples: [(time: TimeInterval, offset: CGFloat)] = []
        let start = CFAbsoluteTimeGetCurrent()
        var nextServerUpdate = 0.05
        var serverTick = 0
        while CFAbsoluteTimeGetCurrent() - start < 0.85 {
            Self.pump(0.004)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            if elapsed >= nextServerUpdate && serverTick < 8 {
                serverTick += 1
                nextServerUpdate += 0.07
                if serverTick == 1 {
                    box.detail.items.append(.init(id: "live-think", kind: .toolCall(.init(kind: .thinking, title: "Thinking", detail: "Inspecting scroll…", status: .running, output: "Step 1"))))
                } else if let idx = box.detail.items.lastIndex(where: { $0.id == "live-think" }) {
                    box.detail.items[idx].kind = .toolCall(.init(kind: .thinking, title: "Thinking", detail: "Inspecting scroll step \(serverTick)…", status: .running, output: "Step \(serverTick)"))
                }
            }
            let y = scroll.contentView.bounds.origin.y
            if samples.last.map({ abs($0.offset - y) > 0.001 }) ?? true {
                samples.append((elapsed, y))
            }
        }

        let end = try #require(samples.last?.offset)
        let maxOffset = (scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.height
        #expect(end > before + 200)
        #expect(abs(end - maxOffset) < 1.5)
        // High-cadence sub-pixel scroll: many distinct positions including fractional half-point steps.
        #expect(samples.count >= 25)
        #expect(samples.contains { abs($0.offset - $0.offset.rounded()) > 0.01 })
        for (previous, next) in zip(samples, samples.dropFirst()) {
            #expect(next.offset >= previous.offset - 0.5)
            #expect(next.offset <= end + 0.5)
        }
    }

    /// Touching the trackpad or scroll wheel mid-scroll immediately hands control back to the user without snapping back.
    @Test func userScrollInterruptsActiveSendScrollWithoutSnappingBack() throws {
        let model = AppModel.mock()
        model.destination = .thread(MockData.threadDetail.summary.id)
        let (window, host) = Self.present(model)
        defer { window.orderOut(nil) }
        let scroll = try #require(Self.transcriptScrollView(in: host))
        let before = scroll.contentView.bounds.origin.y

        model.composerText = "Start a scroll that the user interrupts"
        model.send()
        Self.pump(0.18)

        // Simulate user initiating a live scroll upward mid-flight.
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
        let interruptedTarget = max(0, before - 120)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: interruptedTarget))
        scroll.reflectScrolledClipView(scroll.contentView)

        // Wait past the 680ms send scroll; the scroll must stay where the user put it.
        Self.pump(0.75)
        #expect(abs(scroll.contentView.bounds.origin.y - interruptedTarget) < 2.0)
    }

    /// Sending while scrolled far up in a long thread jumps cleanly to the old end and smoothly glides the last viewport.
    @Test func sendFromTopOfLongThreadJumpsToOldEndThenGlidesSmoothly() throws {
        var items: [TranscriptItem] = []
        let base = MockData.now.addingTimeInterval(-3600)
        for i in 0..<14 {
            items.append(.init(id: "u-\(i)", kind: .user("Prompt \(i)"), startedAt: base.addingTimeInterval(Double(i * 60))))
            items.append(.init(id: "a-\(i)", kind: .assistant(blocks: [.text("Response \(i) with several sentences to give each turn real vertical height in the scroll view.")], streaming: false), startedAt: base.addingTimeInterval(Double(i * 60 + 2)), completedAt: base.addingTimeInterval(Double(i * 60 + 5))))
        }
        let model = AppModel.mock()
        let summary = MockData.threads[0]
        let box = WindowDetailBox(ThreadDetailState(summary: summary, items: items, diffStat: nil, isRunning: false))
        let (window, host) = Self.presentCustom(
            WindowThreadHarness(model: model, box: box),
            size: CGSize(width: 1000, height: 860)
        )
        defer { window.orderOut(nil) }
        let scroll = try #require(Self.transcriptScrollView(in: host))
        let oldEnd = (scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.height
        #expect(oldEnd > 1000)

        // Scroll all the way back to the top.
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        Self.pump(0.15)
        #expect(scroll.contentView.bounds.origin.y < 1)

        // Send a new message from the top.
        let msgID = "u-from-top"
        box.detail.items.append(.init(id: msgID, kind: .user("Jump to old end then glide smoothly")))
        box.detail.isRunning = true
        model.latestThreadSend = ThreadSendEvent(threadID: summary.id, text: "Jump to old end then glide smoothly", optimisticItemID: msgID)

        let samples = Self.sampleOffsets(of: scroll, for: 0.9)
        let finalY = try #require(samples.last?.offset)
        let newEnd = (scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.height
        #expect(abs(finalY - newEnd) < 1.5)
        // Must have intermediate animated positions between oldEnd and newEnd (not teleporting directly to newEnd).
        #expect(samples.contains { $0.offset >= oldEnd - 5 && $0.offset < newEnd - 20 })
    }

    /// The first message fades in concurrently while Home's composer slides down (no sequential wait until dock
    /// completion) and sits pixel-for-pixel at `ThreadView`'s resting `UserBubble` coordinates across the handoff.
    @Test func newThreadFirstMessageFadesInConcurrentlyWithDockAndAlignsPixelExactOnHandoff() async throws {
        let model = AppModel.mock()
        let prompt = "Simultaneous dock and fade alignment check"
        let probe = NewThreadBubbleProbe()
        nonisolated(unsafe) var handoffTimestamp: CFAbsoluteTime?
        let observer = NotificationCenter.default.addObserver(forName: .swftNewThreadDidHandOff, object: nil, queue: nil) { _ in
            handoffTimestamp = CFAbsoluteTimeGetCurrent()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let (window, _) = Self.presentCustom(
            RootView()
                .environment(model)
                .environment(\.newThreadBubbleProbe, probe),
            size: CGSize(width: 1280, height: 860)
        )
        defer { window.orderOut(nil) }

        #expect(probe.samples.isEmpty)

        model.composerText = prompt
        let sendTime = CFAbsoluteTimeGetCurrent()
        model.send()

        // Mid-dock (~0.08s): Home is STILL sliding the composer down (`destination == .home`), yet the first message
        // preview has ALREADY mounted and begun fading in (`targetOpacity` transitioning 0 → 1) concurrently!
        await Self.pumpAsync(0.08)
        #expect(model.destination == .home)
        #expect(model.newThread.launchingToken != nil)
        #expect(model.newThread.launchingMessage == NewThreadLaunchMessage(text: prompt))
        let midDockPreview = try #require(probe.samples.last(where: { $0.source == .homePreview }))
        #expect(midDockPreview.targetOpacity == 1.0)
        // Fade-in starts immediately alongside the composer slide (well before dock settles / handoff fires).
        #expect(midDockPreview.timestamp - sendTime < 0.12)

        // Complete the handoff into ThreadView.
        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline, model.destination == .home { await Self.tick() }
        await Self.pumpAsync(0.10)

        guard case .thread = model.destination else {
            Issue.record("Home did not hand off to the new thread")
            return
        }
        let handoffTime = try #require(handoffTimestamp)
        #expect(midDockPreview.timestamp < handoffTime)

        // ThreadView's real UserBubble must appear immediately at opacity 1 (no double-fade) in the EXACT same
        // window-space rect as Home's fading preview (sub-pixel alignment, zero jump on handoff).
        let threadSample = try #require(probe.samples.first(where: { $0.source == .threadBubble }))
        #expect(threadSample.targetOpacity == 1.0)
        #expect(abs(midDockPreview.frameInWindow.minX - threadSample.frameInWindow.minX) < 0.5)
        #expect(abs(midDockPreview.frameInWindow.minY - threadSample.frameInWindow.minY) < 0.5)
        #expect(abs(midDockPreview.frameInWindow.width - threadSample.frameInWindow.width) < 0.5)
        #expect(abs(midDockPreview.frameInWindow.height - threadSample.frameInWindow.height) < 0.5)
    }

    /// Cancelling or failing a launch mid-dock cleanly restores Home and fades out the launching first-message preview
    /// so no orphan bubble stays visible.
    @Test func failedOrCancelledLaunchMidDockRemovesFirstMessagePreviewCleanly() async throws {
        let model = AppModel.mock()
        let probe = NewThreadBubbleProbe()
        let (window, _) = Self.presentCustom(
            RootView()
                .environment(model)
                .environment(\.newThreadBubbleProbe, probe),
            size: CGSize(width: 1280, height: 860)
        )
        defer { window.orderOut(nil) }

        model.composerText = "This launch will fail mid-dock"
        model.send()
        await Self.pumpAsync(0.08)
        #expect(model.destination == .home)
        let token = try #require(model.newThread.launchingToken)
        let revealed = try #require(probe.samples.last(where: { $0.source == .homePreview }))
        #expect(revealed.targetOpacity == 1.0)

        // Simulate a server rejection mid-dock.
        model.newThread.fail(token: token)
        await Self.pumpAsync(0.45)
        #expect(model.destination == .home)
        #expect(model.newThread.launchingToken == nil)
        #expect(model.newThread.launchingMessage == nil)

        // The launching preview faded back down to opacity 0 and never handed off to ThreadView.
        let finalPreview = try #require(probe.samples.last(where: { $0.source == .homePreview }))
        #expect(finalPreview.targetOpacity == 0.0)
        #expect(!probe.samples.contains(where: { $0.source == .threadBubble }))
    }

    /// Under Reduce Motion, Home fades out without showing the sliding-dock message preview and hands off cleanly.
    @Test func reduceMotionLaunchSkipsHomePreviewAndCrossfadesCleanly() async throws {
        let model = AppModel.mock()
        let probe = NewThreadBubbleProbe()
        let (window, _) = Self.presentCustom(
            RootView()
                .environment(model)
                .environment(\.sendFlightForceReduceMotion, true)
                .environment(\.newThreadBubbleProbe, probe),
            size: CGSize(width: 1280, height: 860)
        )
        defer { window.orderOut(nil) }

        model.composerText = "Reduce motion launch test"
        model.send()
        let deadline = Date().addingTimeInterval(0.8)
        while Date() < deadline, model.destination == .home { await Self.tick() }
        await Self.pumpAsync(0.20)

        guard case .thread = model.destination else {
            Issue.record("Reduce Motion Home did not hand off to the new thread")
            return
        }
        // Under Reduce Motion, Home never mounts the sliding preview; ThreadView crossfades in whole with the real bubble.
        #expect(!probe.samples.contains(where: { $0.source == .homePreview }))
        let threadSample = try #require(probe.samples.first(where: { $0.source == .threadBubble }))
        #expect(threadSample.targetOpacity == 1.0)
    }

    /// The first message of a brand-new thread fades in cleanly at the top and fills one screen without overflow.
    @Test func newThreadFirstTurnFillsTheViewportWithoutOverflow() async throws {
        let model = AppModel.mock()
        model.composerText = "Plan the onboarding flow"
        let (window, host) = Self.present(model)
        defer { window.orderOut(nil) }
        model.send()
        // Wait for Home's dock handoff and the first message's fade-in.
        let start = Date()
        while Date().timeIntervalSince(start) < 1.3 { await Self.tick() }

        guard case .thread = model.destination else {
            Issue.record("Home did not hand off to the new thread")
            return
        }
        let scroll = try #require(Self.transcriptScrollView(in: host))
        let documentHeight = scroll.documentView?.frame.height ?? 0
        #expect(documentHeight <= scroll.contentView.bounds.height + 0.5)
        #expect(scroll.contentView.bounds.origin.y < 0.5)

        // A subsequent message sent inside this new thread scrolls down to its own turn.
        let beforeSecond = scroll.contentView.bounds.origin.y
        model.composerText = "Follow up inside the existing thread"
        model.send()
        let secondSamples = Self.sampleOffsets(of: scroll, for: 0.9)
        let afterSecond = try #require(secondSamples.last?.offset)
        #expect(afterSecond > beforeSecond + 40)
    }

    /// A send from anywhere glides down to the new turn's stream room, and when the streamed reply finishes nothing
    /// above it folds away and nothing moves: the transcript stays exactly where the user was reading.
    @Test func finishedReplyStaysPutAfterStreamingIntoItsRoom() throws {
        var items: [TranscriptItem] = []
        let base = MockData.now.addingTimeInterval(-3600)
        for i in 0..<8 {
            items.append(.init(id: "u-\(i)", kind: .user("Prompt \(i)"), startedAt: base.addingTimeInterval(Double(i * 60))))
            items.append(.init(id: "a-\(i)", kind: .assistant(blocks: [.text("Response \(i) with several sentences to give each turn real vertical height in the scroll view, wrapping across lines.")], streaming: false), startedAt: base.addingTimeInterval(Double(i * 60 + 2)), completedAt: base.addingTimeInterval(Double(i * 60 + 5))))
        }
        let model = AppModel.mock()
        let summary = MockData.threads[0]
        let box = WindowDetailBox(ThreadDetailState(summary: summary, items: items, diffStat: nil, isRunning: false))
        let (window, host) = Self.presentCustom(WindowThreadHarness(model: model, box: box), size: CGSize(width: 1000, height: 760))
        defer { window.orderOut(nil) }
        let scroll = try #require(Self.transcriptScrollView(in: host))

        // Send from the middle of the history.
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 300))
        scroll.reflectScrolledClipView(scroll.contentView)
        Self.pump(0.2)
        box.detail.items.append(.init(id: "u-new", kind: .user("Tighten the send animation"), startedAt: Date()))
        box.detail.isRunning = true
        model.latestThreadSend = ThreadSendEvent(threadID: summary.id, text: "Tighten the send animation", optimisticItemID: "u-new")
        func maxOffset() -> CGFloat { (scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.height }
        // One continuous forward glide to the new end, even though the new turn's real height is only learned as it
        // scrolls into view (the glide used to stop at the old end, then glide again).
        let glide = Self.sampleOffsets(of: scroll, for: 0.9)
        for (previous, next) in zip(glide, glide.dropFirst()) {
            #expect(next.offset >= previous.offset - 0.5)
        }
        // Until it is nearly there it never pauses for more than a few frames.
        let glideStart = glide.first?.offset ?? 0
        let glideEnd = glide.last?.offset ?? 0
        let travel = glide.filter { $0.offset < glideStart + (glideEnd - glideStart) * 0.95 }.map(\.time)
        for (previous, next) in zip(travel, travel.dropFirst()) {
            #expect(next - previous < 0.05)
        }
        #expect(abs(scroll.contentView.bounds.origin.y - maxOffset()) < 1.5)

        // Stream a turn with work, an interim message and a long answer, following the bottom as it grows.
        let now = Date()
        box.detail.items.append(.init(id: "t-1", kind: .toolCall(.init(kind: .read, title: "Read", detail: "ThreadView.swift", status: .succeeded, duration: 0.3)), startedAt: now, completedAt: now))
        Self.pump(0.1)
        box.detail.items.append(.init(id: "c-1", kind: .assistant(blocks: [.text("I'll look at the scroll driver next.")], streaming: false), startedAt: now))
        Self.pump(0.1)
        box.detail.items.append(.init(id: "t-2", kind: .toolCall(.init(kind: .read, title: "Read", detail: "SendFlightScrollDriver.swift", status: .succeeded, duration: 0.2)), startedAt: now, completedAt: now))
        Self.pump(0.1)
        let paragraphs = (1...14).map { "Paragraph \($0) of the answer, long enough to wrap across the reading column so the turn outgrows the viewport." }
        box.detail.items.append(.init(id: "answer", kind: .assistant(blocks: [.text(paragraphs.prefix(1).joined(separator: "\n\n"))], streaming: true), startedAt: now))
        for count in 2...paragraphs.count {
            Self.pump(0.05)
            box.detail.items[box.detail.items.count - 1].kind = .assistant(blocks: [.text(paragraphs.prefix(count).joined(separator: "\n\n"))], streaming: true)
        }
        Self.pump(0.6)
        let liveOffset = scroll.contentView.bounds.origin.y
        let liveHeight = scroll.documentView?.frame.height ?? 0
        #expect(abs(liveOffset - maxOffset()) < 1.5)

        // The reply finishes.
        box.detail.items[box.detail.items.count - 1].kind = .assistant(blocks: [.text(paragraphs.joined(separator: "\n\n"))], streaming: false)
        box.detail.items[box.detail.items.count - 1].completedAt = Date()
        box.detail.isRunning = false
        var offsets: [CGFloat] = []
        var heights: [CGFloat] = []
        let start = Date()
        while Date().timeIntervalSince(start) < 0.8 {
            Self.pump(1.0 / 120.0)
            offsets.append(scroll.contentView.bounds.origin.y)
            heights.append(scroll.documentView?.frame.height ?? 0)
        }
        for offset in offsets { #expect(abs(offset - liveOffset) < 0.5) }
        for height in heights { #expect(abs(height - liveHeight) < 0.5) }
    }

    /// One display frame of run loop, then a yield so main-actor tasks (the launch's hand-off) get to run.
    private static func tick() async {
        pump(1.0 / 60.0)
        await Task.yield()
    }

    private static func pumpAsync(_ seconds: TimeInterval) async {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            pump(min(1.0 / 60.0, max(0.002, end.timeIntervalSinceNow)))
            await Task.yield()
        }
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
        presentCustom(RootView().environment(model), size: CGSize(width: 1280, height: 860))
    }

    private static func presentCustom<V: View>(
        _ view: V,
        size: CGSize,
        appearance: NSAppearance.Name? = nil
    ) -> (NSWindow, NSView) {
        SwftFonts.register()
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -4000, y: -4000), size: size),
            styleMask: [.titled, .fullSizeContentView, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        if let appearance {
            window.appearance = NSAppearance(named: appearance)
        }
        let host = NSHostingView(rootView: view)
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

@MainActor
@Observable
private final class WindowDetailBox {
    var detail: ThreadDetailState
    init(_ detail: ThreadDetailState) { self.detail = detail }
}

private struct WindowThreadHarness: View {
    let model: AppModel
    let box: WindowDetailBox

    var body: some View {
        ThreadView(detail: box.detail)
            .environment(model)
    }
}
