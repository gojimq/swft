import AppKit
import SwftDesign
import SwiftUI
import Testing
@testable import Swft

@Suite("Composer polish")
struct ComposerPolishTests {
    @Test func shapeAndLayoutMatchGeminiMeasurements() {
        #expect(ComposerPolish.cornerRadius == 24)
        #expect(ComposerPolish.cornerRadius < SwftRadius.composer)
        #expect(ComposerPolish.minHeight == 95)
        #expect(ComposerPolish.inputFontSize > 17)
        #expect(ComposerPolish.sendButtonSize == 28)
        #expect(ComposerPolish.controlButtonSize == 28)
    }

    @Test func sendButtonIsLightBlueFilledInLightAndDarkModes() throws {
        let lightIdle = try resolvedRGBA(ComposerPolish.sendFill(for: .idle), dark: false)
        let lightReady = try resolvedRGBA(ComposerPolish.sendFill(for: .ready), dark: false)
        let lightStop = try resolvedRGBA(ComposerPolish.sendFill(for: .stop), dark: false)
        // Light-blue circle: blue channel clearly leads red, fully opaque.
        #expect(lightIdle.alpha == 1)
        #expect(lightIdle.blue > lightIdle.red + 0.2)
        #expect(lightReady.alpha == 1)
        #expect(lightReady.blue > lightReady.red + 0.25)
        #expect(lightStop == lightReady)

        let darkIdle = try resolvedRGBA(ComposerPolish.sendFill(for: .idle), dark: true)
        let darkReady = try resolvedRGBA(ComposerPolish.sendFill(for: .ready), dark: true)
        #expect(darkIdle.alpha == 1)
        #expect(darkIdle.blue > darkIdle.red + 0.15)
        #expect(darkReady.alpha == 1)
        #expect(darkReady.blue > darkReady.red + 0.2)
    }

    @Test func glassTintRemainsTranslucentForBackgroundGlow() throws {
        let lightTint = try resolvedRGBA(ComposerPolish.glassTint, dark: false)
        let darkTint = try resolvedRGBA(ComposerPolish.glassTint, dark: true)
        #expect(lightTint.alpha > 0.1 && lightTint.alpha < 0.6)
        #expect(darkTint.alpha > 0.1 && darkTint.alpha < 0.65)
    }

    private struct RGBA: Equatable {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
    }

    private func resolvedRGBA(_ color: Color, dark: Bool) throws -> RGBA {
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolved = NSColor(color).usingColorSpace(.sRGB)
        }
        let srgb = try #require(resolved)
        return RGBA(
            red: srgb.redComponent,
            green: srgb.greenComponent,
            blue: srgb.blueComponent,
            alpha: srgb.alphaComponent
        )
    }
}

@Suite("Sidebar selection polish")
struct SidebarSelectionPolishTests {
    @Test func initialMountStartsSettledWithoutBounce() {
        let selectedInitial = SidebarSelectionMotion.initialPhase(isSelected: true)
        let unselectedInitial = SidebarSelectionMotion.initialPhase(isSelected: false)
        #expect(selectedInitial == .settled)
        #expect(unselectedInitial == .hidden)
        #expect(SidebarSelectionMotion.visualState(for: selectedInitial, reduceMotion: false) == .init(opacity: 1, scale: 1))
        #expect(SidebarSelectionMotion.visualState(for: unselectedInitial, reduceMotion: false) == .init(opacity: 0, scale: 1))
    }

    @Test func selectingRowPressesInPlaceAndDeselectingFadesOutInPlace() {
        let selectPhase = SidebarSelectionMotion.transitionPhase(isSelected: true, reduceMotion: false)
        #expect(selectPhase == .pressingIn)
        let pressed = SidebarSelectionMotion.visualState(for: selectPhase, reduceMotion: false)
        #expect(pressed.opacity == 1)
        #expect(pressed.scale == SidebarSelectionMotion.pillPressScale)
        #expect(pressed.scale < 1 && pressed.scale > 0.9)

        let settled = SidebarSelectionMotion.visualState(for: .settled, reduceMotion: false)
        #expect(settled == .init(opacity: 1, scale: 1))

        let deselectPhase = SidebarSelectionMotion.transitionPhase(isSelected: false, reduceMotion: false)
        #expect(deselectPhase == .fadingOut)
        let faded = SidebarSelectionMotion.visualState(for: deselectPhase, reduceMotion: false)
        // Old highlight fades out strictly in place at scale 1 (no shrink or travel).
        #expect(faded == .init(opacity: 0, scale: 1))
    }

    @Test func reduceMotionCrossfadesWithoutScaling() {
        let phase = SidebarSelectionMotion.transitionPhase(isSelected: true, reduceMotion: true)
        #expect(phase == .settled)
        #expect(SidebarSelectionMotion.visualState(for: .pressingIn, reduceMotion: true) == .init(opacity: 1, scale: 1))
        #expect(SidebarSelectionMotion.visualState(for: .fadingOut, reduceMotion: true) == .init(opacity: 0, scale: 1))
    }

    @Test func generationGuardCancelsStaleReleaseOnRapidClicks() {
        #expect(SidebarSelectionMotion.shouldRelease(capturedGeneration: 1, currentGeneration: 1, isSelected: true))
        #expect(!SidebarSelectionMotion.shouldRelease(capturedGeneration: 1, currentGeneration: 2, isSelected: true))
        #expect(!SidebarSelectionMotion.shouldRelease(capturedGeneration: 1, currentGeneration: 1, isSelected: false))
    }
}

/// Optional frame-sequence capture for visual verification of in-place sidebar selection.
/// Skipped unless `SWFT_POLISH_SHOTS_DIR` is set.
@MainActor
@Suite("Sidebar selection sequence", .enabled(if: ProcessInfo.processInfo.environment["SWFT_POLISH_SHOTS_DIR"] != nil))
struct SidebarSelectionSequenceSnapshots {
    static let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SWFT_POLISH_SHOTS_DIR"] ?? NSTemporaryDirectory())

    @Test func captureThreadAndNavSelectionSequences() throws {
        SwftFonts.register()
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)

        // 1. Thread-to-thread selection jump (t1 -> t4, skipping t2 and t3 to prove zero vertical travel).
        try captureSequence(
            prefix: "seq-thread",
            initialDestination: .thread("t1"),
            nextDestination: .thread("t4")
        )

        // 2. Nav-to-nav selection jump (home -> settings, skipping projects and scheduled).
        try captureSequence(
            prefix: "seq-nav",
            initialDestination: .home,
            nextDestination: .settings
        )
    }

    private func captureSequence(
        prefix: String,
        initialDestination: SidebarDestination,
        nextDestination: SidebarDestination
    ) throws {
        let model = AppModel.mock()
        model.destination = initialDestination
        let size = CGSize(width: 1280, height: 860)
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: 80, y: 120), size: size),
            styleMask: [.titled, .fullSizeContentView, .closable],
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
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        let wid = window.windowNumber
        func grab(_ suffix: String) throws {
            let out = Self.directory.appendingPathComponent("\(prefix)-\(suffix).png").path
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-x", "-o", "-l", "\(wid)", out]
            try p.run()
            p.waitUntilExit()
        }

        // Frame 0: settled initial state
        try grab("00-before")

        // Reset before each timestamp so screencapture latency never skews subsequent frames.
        let samples: [(String, Double)] = [
            ("01-press-in", 0.005),
            ("02-pressed", 0.035),
            ("03-release", 0.085),
            ("04-settling", 0.145),
            ("05-settled", 0.300),
        ]
        for (label, elapsed) in samples {
            model.destination = initialDestination
            RunLoop.main.run(until: Date().addingTimeInterval(0.38))
            model.destination = nextDestination
            RunLoop.main.run(until: Date().addingTimeInterval(elapsed))
            try grab(label)
        }

        window.orderOut(nil)
    }
}
