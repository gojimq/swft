import AppKit
import SwftDesign
import SwiftUI
import Testing
@testable import Swft

@Suite("SwftEntranceLogic")
struct SwftEntranceLogicTests {
    @Test func startsHiddenBelowRestingPositionAndSettles() {
        let initial = SwftEntranceLogic.visualState(
            shown: false,
            screenHandoff: false,
            reduceMotion: false,
            distance: SwftMotion.threadSwitchOffset
        )
        #expect(initial == SwftEntranceVisualState(opacity: 0, offsetY: SwftMotion.threadSwitchOffset))
        #expect(SwftEntranceLogic.revealAnimation(base: SwftMotion.threadSwitch, screenHandoff: false, reduceMotion: false) != nil)

        let settled = SwftEntranceLogic.visualState(
            shown: true,
            screenHandoff: false,
            reduceMotion: false,
            distance: SwftMotion.threadSwitchOffset
        )
        #expect(settled == SwftEntranceVisualState(opacity: 1, offsetY: 0))
    }

    @Test func reduceMotionCrossfadesWithoutVerticalOffset() {
        let initial = SwftEntranceLogic.visualState(
            shown: false,
            screenHandoff: false,
            reduceMotion: true,
            distance: SwftMotion.threadSwitchOffset
        )
        #expect(initial == SwftEntranceVisualState(opacity: 0, offsetY: 0))
        #expect(SwftEntranceLogic.revealAnimation(base: SwftMotion.threadSwitch, screenHandoff: false, reduceMotion: true) != nil)

        // Under Reduce Motion, screen handoffs still crossfade cleanly instead of bypassing.
        let handoffReduceMotion = SwftEntranceLogic.visualState(
            shown: false,
            screenHandoff: true,
            reduceMotion: true,
            distance: SwftMotion.threadSwitchOffset
        )
        #expect(handoffReduceMotion == SwftEntranceVisualState(opacity: 0, offsetY: 0))
        #expect(!SwftEntranceLogic.bypassesEntrance(screenHandoff: true, reduceMotion: true))
    }

    @Test func screenHandoffBypassesEntranceWhenMotionIsEnabled() {
        #expect(SwftEntranceLogic.bypassesEntrance(screenHandoff: true, reduceMotion: false))
        let state = SwftEntranceLogic.visualState(
            shown: false,
            screenHandoff: true,
            reduceMotion: false,
            distance: SwftMotion.threadSwitchOffset
        )
        #expect(state == SwftEntranceVisualState(opacity: 1, offsetY: 0))
        #expect(SwftEntranceLogic.revealAnimation(base: SwftMotion.threadSwitch, screenHandoff: true, reduceMotion: false) == nil)
    }

    @Test func explicitBypassAlwaysSettlesImmediatelyIncludingReduceMotion() {
        for reduceMotion in [false, true] {
            #expect(SwftEntranceLogic.bypassesEntrance(bypass: true, screenHandoff: false, reduceMotion: reduceMotion))
            let state = SwftEntranceLogic.visualState(
                shown: false,
                bypass: true,
                screenHandoff: false,
                reduceMotion: reduceMotion,
                distance: SwftMotion.threadSwitchOffset
            )
            #expect(state == SwftEntranceVisualState(opacity: 1, offsetY: 0))
            #expect(
                SwftEntranceLogic.revealAnimation(
                    base: SwftMotion.threadSwitch,
                    bypass: true,
                    screenHandoff: false,
                    reduceMotion: reduceMotion
                ) == nil
            )
        }
    }
}

@MainActor
@Suite("ThreadSwitchDestinationTracking")
struct ThreadSwitchDestinationTrackingTests {
    @Test func tracksDirectThreadToThreadSwitchesOnly() {
        let model = AppModel.mock()
        #expect(model.previousDestination == nil)
        #expect(!model.isSwitchingBetweenThreads)

        // Home -> thread is not a thread-to-thread switch (composer enters with the thread).
        model.open("t1")
        #expect(model.previousDestination == .home)
        #expect(!model.isSwitchingBetweenThreads)

        // Thread -> another thread keeps shared chrome anchored.
        model.open("t2")
        #expect(model.previousDestination == .thread("t1"))
        #expect(model.isSwitchingBetweenThreads)

        // Re-selecting the same thread is a no-op and preserves previousDestination.
        model.open("t2")
        #expect(model.previousDestination == .thread("t1"))
        #expect(model.isSwitchingBetweenThreads)

        // Thread -> Home clears thread-to-thread state.
        model.goHome()
        #expect(model.previousDestination == .thread("t2"))
        #expect(!model.isSwitchingBetweenThreads)

        // Settings -> thread is not a thread-to-thread switch.
        model.destination = .settings
        model.open("t1")
        #expect(model.previousDestination == .settings)
        #expect(!model.isSwitchingBetweenThreads)
    }
}

/// Optional frame capture to visually verify thread-switch fade & settle timing in a real `NSWindow`.
/// Run with: `SWFT_THREAD_SWITCH_FRAMES_DIR=/tmp/swft-thread-switch swift test --filter ThreadSwitchMotionFrames`
@MainActor
@Suite(
    "ThreadSwitchMotionFrames",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SWFT_THREAD_SWITCH_FRAMES_DIR"] != nil)
)
struct ThreadSwitchMotionFrames {
    static let directory = URL(
        fileURLWithPath: ProcessInfo.processInfo.environment["SWFT_THREAD_SWITCH_FRAMES_DIR"] ?? NSTemporaryDirectory()
    )

    @Test func captureThreadToThreadSequence() throws {
        SwftFonts.register()
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)

        let model = AppModel.mock()
        model.destination = .thread("t1")
        let size = CGSize(width: 1280, height: 860)
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: 80, y: 120), size: size),
            styleMask: [.titled, .fullSizeContentView, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .aqua)
        let host = NSHostingView(rootView: RootView().environment(model))
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        let wid = window.windowNumber
        func grab(_ name: String) throws {
            host.layoutSubtreeIfNeeded()
            let out = Self.directory.appendingPathComponent("\(name).png").path
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-o", "-l", "\(wid)", out]
            try process.run()
            process.waitUntilExit()
        }

        try grab("00-before-t1")

        let samples: [(String, TimeInterval)] = [
            ("01-t2-010ms", 0.010),
            ("02-t2-045ms", 0.045),
            ("03-t2-090ms", 0.090),
            ("04-t2-150ms", 0.150),
            ("05-t2-280ms", 0.280),
        ]
        for (label, elapsed) in samples {
            model.open("t1")
            RunLoop.main.run(until: Date().addingTimeInterval(0.32))
            model.open("t2")
            RunLoop.main.run(until: Date().addingTimeInterval(elapsed))
            try grab(label)
        }
    }
}
