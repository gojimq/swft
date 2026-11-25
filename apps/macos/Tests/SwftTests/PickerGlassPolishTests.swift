import AppKit
import SwftDesign
import SwiftUI
import Testing
@testable import Swft

@Suite("Picker glass and touch polish")
struct PickerGlassPolishTests {
    @Test func popoverEntranceNeverOvershoots() {
        #expect(SwftMotion.popoverDamping >= 1)
        #expect(SwftMotion.popoverScale >= 0.96 && SwftMotion.popoverScale < 1)
        #expect(SwftMotion.popoverOffset <= 6)
    }

    @Test func pressScalesDownAndReduceMotionHoldsStill() {
        #expect(SwftMotion.pressScale(isPressed: true, scale: 0.92, reduceMotion: false) == 0.92)
        #expect(SwftMotion.pressScale(isPressed: false, scale: 0.92, reduceMotion: false) == 1)
        #expect(SwftMotion.pressScale(isPressed: true, scale: 0.92, reduceMotion: true) == 1)
        for scale in [PickerPolish.rowPressScale, PickerPolish.tabPressScale, PickerPolish.segmentPressScale] {
            #expect(scale < 1 && scale >= 0.9)
        }
    }

    @Test func pickerFillsStayTranslucentOverGlass() throws {
        let fills = [
            PickerPolish.frostFill, PickerPolish.divider, PickerPolish.hoverFill, PickerPolish.highlightFill,
            PickerPolish.pressedFill, PickerPolish.railSelection, PickerPolish.switcherTrack, PickerPolish.switcherThumb,
            PickerPolish.sliderTrack,
        ]
        for dark in [false, true] {
            for fill in fills {
                let alpha = try resolvedAlpha(fill, dark: dark)
                #expect(alpha > 0 && alpha < 0.9)
            }
        }
        // Interaction fills escalate hover < highlight < pressed so a press always reads.
        for dark in [false, true] {
            let hover = try resolvedAlpha(PickerPolish.hoverFill, dark: dark)
            let highlight = try resolvedAlpha(PickerPolish.highlightFill, dark: dark)
            let pressed = try resolvedAlpha(PickerPolish.pressedFill, dark: dark)
            #expect(hover < highlight && highlight < pressed)
        }
    }

    @Test func pickerGlassIsDenserThanComposerForLegibility() throws {
        for dark in [false, true] {
            #expect(try resolvedAlpha(PickerPolish.frostFill, dark: dark) > resolvedAlpha(ComposerPolish.frostFill, dark: dark))
        }
    }

    private func resolvedAlpha(_ color: Color, dark: Bool) throws -> CGFloat {
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance { resolved = NSColor(color).usingColorSpace(.sRGB) }
        return try #require(resolved).alphaComponent
    }
}

/// Optional frame capture of the picker opening, to inspect that text lands without shifting.
/// Skipped unless `SWFT_POLISH_SHOTS_DIR` is set.
@MainActor
@Suite("Picker open sequence", .enabled(if: ProcessInfo.processInfo.environment["SWFT_POLISH_SHOTS_DIR"] != nil))
struct PickerOpenSequenceSnapshots {
    static let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SWFT_POLISH_SHOTS_DIR"] ?? NSTemporaryDirectory())

    @Test func capturePickerOpenFrames() throws {
        SwftFonts.register()
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        for dark in [false, true] {
            let model = AppModel.mock()
            let size = CGSize(width: 1280, height: 860)
            let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 80, y: 120), size: size), styleMask: [.titled, .fullSizeContentView, .closable], backing: .buffered, defer: false)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let host = NSHostingView(rootView: RootView().environment(model))
            host.frame = CGRect(origin: .zero, size: size)
            window.contentView = host
            window.orderFrontRegardless()
            RunLoop.main.run(until: Date().addingTimeInterval(0.8))
            let wid = window.windowNumber
            let prefix = dark ? "picker-open-dark" : "picker-open-light"
            for (label, elapsed) in [("01", 0.03), ("02", 0.08), ("03", 0.14), ("04", 0.22), ("05", 0.5)] {
                withAnimation(SwftMotion.popover) { model.toggleModelPicker() }
                RunLoop.main.run(until: Date().addingTimeInterval(elapsed))
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                p.arguments = ["-x", "-o", "-l", "\(wid)", Self.directory.appendingPathComponent("\(prefix)-\(label).png").path]
                try p.run()
                p.waitUntilExit()
                model.closeModelPicker()
                RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            }
            window.orderOut(nil)
        }
    }
}
