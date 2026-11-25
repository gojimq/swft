import AppKit
import SwftDesign
import SwiftUI
import Testing
@testable import Swft

@MainActor
@Observable
private final class RapidScrubHarnessState {
    var levels = ["Low", "Medium", "High", "Extra high", "Max"]
    var levelIndex = 2
    var modelName = "Haiku 5.5"
}

private struct RapidScrubHarnessView: View {
    var state: RapidScrubHarnessState
    private let mark = PickerRailItem(
        id: "claudeAgent",
        provider: "claudeAgent",
        symbol: "sparkles",
        monogram: "Claude",
        tint: .orange,
        accent: nil,
        tooltip: "Claude",
        inUse: true
    )

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            ThinkingSlider(levels: state.levels, index: state.levelIndex, keyboardFocused: false) { next in
                state.levelIndex = next
            }
            .frame(width: 300)
            ModelPickerTrigger(
                mark: mark,
                disambiguator: nil,
                model: state.modelName,
                effort: state.levels[state.levelIndex],
                isOpen: true,
                action: {}
            )
        }
        .padding(16)
        .frame(width: 360, height: 140)
        .background(Color.white)
    }
}

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

    @Test func swapMotionRespectsReduceMotionAndSettlesCleanly() {
        #expect(SwapVisualState.settled == SwapVisualState(opacity: 1, offsetY: 0))

        let normalStart = SwapMotion.startState(reduceMotion: false)
        #expect(normalStart.opacity == 0)
        #expect(normalStart.offsetY == SwapMotion.riseOffset)
        #expect(normalStart.offsetY > 0)

        let reducedStart = SwapMotion.startState(reduceMotion: true)
        #expect(reducedStart.opacity == 0)
        #expect(reducedStart.offsetY == 0)

        #expect(SwapMotion.duration(reduceMotion: false) > 0)
        #expect(SwapMotion.duration(reduceMotion: true) > 0)
    }

    @Test func modelPickerTriggerKeepsModelSteadyWhenOnlyEffortChanges() {
        let modelKeyHigh = ModelPickerTrigger.modelSwapKey(markID: "claudeAgent", disambiguator: nil, model: "Haiku 5.5")
        let modelKeyExtraHigh = ModelPickerTrigger.modelSwapKey(markID: "claudeAgent", disambiguator: nil, model: "Haiku 5.5")
        #expect(modelKeyHigh == modelKeyExtraHigh)

        let swapKeyHigh = ModelPickerTrigger.swapKey(markID: "claudeAgent", disambiguator: nil, model: "Haiku 5.5", effort: "High")
        let swapKeyExtraHigh = ModelPickerTrigger.swapKey(markID: "claudeAgent", disambiguator: nil, model: "Haiku 5.5", effort: "Extra high")
        #expect(swapKeyHigh != swapKeyExtraHigh)

        let otherModelKey = ModelPickerTrigger.modelSwapKey(markID: "claudeAgent", disambiguator: nil, model: "Opus 5.5")
        #expect(modelKeyHigh != otherModelKey)
    }

    @MainActor
    @Test func rapidThinkingScrubSettlesWithZeroStackedOrGhostedText() throws {
        SwftFonts.register()
        let size = CGSize(width: 360, height: 140)
        let state = RapidScrubHarnessState()
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -4000, y: -4000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        let host = NSHostingView(rootView: RapidScrubHarnessView(state: state))
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        window.orderBack(nil)
        defer { window.orderOut(nil) }

        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        let baseline = try captureRGBA(host)

        // Rapidly scrub back and forth across thinking levels (revisiting earlier keys mid-flight),
        // alternating animated and un-animated updates faster than the swap animation duration.
        let scrubSequence = [3, 4, 3, 2, 1, 0, 1, 2, 3, 4, 2, 0, 3, 1, 4, 2, 3, 2, 1, 3, 4, 1, 3, 2]
        for (step, nextIndex) in scrubSequence.enumerated() {
            if step.isMultiple(of: 2) {
                withAnimation(SwftMotion.standard) { state.levelIndex = nextIndex }
            } else {
                state.levelIndex = nextIndex
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.015))
        }

        // Also rapidly swap models back and forth before returning to the initial model + level.
        for name in ["Opus 5.5", "Sonnet 5.5", "Haiku 5.5", "Opus 5.5", "Haiku 5.5"] {
            withAnimation(SwftMotion.spring) { state.modelName = name }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }

        // Wait for the final swap animation to finish settling.
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let afterScrub = try captureRGBA(host)

        #expect(state.levelIndex == 2)
        #expect(state.modelName == "Haiku 5.5")
        let mismatched = mismatchedPixelCount(baseline, afterScrub)
        #expect(mismatched == 0, "Expected identical settled render after rapid scrub, but \(mismatched) pixels differed")
    }

    @MainActor
    private func captureRGBA(_ view: NSView) throws -> [UInt8] {
        view.layoutSubtreeIfNeeded()
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let cgImage = try #require(rep.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    private func mismatchedPixelCount(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        guard lhs.count == rhs.count else { return max(lhs.count, rhs.count) }
        var diff = 0
        var i = 0
        while i + 3 < lhs.count {
            let dr = abs(Int(lhs[i]) - Int(rhs[i]))
            let dg = abs(Int(lhs[i + 1]) - Int(rhs[i + 1]))
            let db = abs(Int(lhs[i + 2]) - Int(rhs[i + 2]))
            let da = abs(Int(lhs[i + 3]) - Int(rhs[i + 3]))
            if max(max(dr, dg), max(db, da)) > 2 {
                diff += 1
            }
            i += 4
        }
        return diff
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

    @Test func captureRapidThinkingScrub() throws {
        SwftFonts.register()
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        for dark in [false, true] {
            let model = AppModel.mock()
            model.destination = .thread(MockData.threadDetail.summary.id)
            model.selectReasoningChoice("high")
            model.toggleModelPicker()
            let size = CGSize(width: 1280, height: 860)
            let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 80, y: 120), size: size), styleMask: [.titled, .fullSizeContentView, .closable], backing: .buffered, defer: false)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let host = NSHostingView(rootView: RootView().environment(model))
            host.frame = CGRect(origin: .zero, size: size)
            window.contentView = host
            window.orderFrontRegardless()
            RunLoop.main.run(until: Date().addingTimeInterval(0.7))

            let sequence = ["xhigh", "max", "high", "medium", "low", "high", "xhigh", "low", "max", "medium", "high", "xhigh", "high", "medium", "xhigh", "low", "high"]
            for choice in sequence {
                withAnimation(SwftMotion.standard) { model.selectReasoningChoice(choice) }
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }

            let wid = window.windowNumber
            let prefix = dark ? "rapid-scrub-dark" : "rapid-scrub-light"
            // Capture right after scrubbing (mid-rise) and after settling.
            for (label, wait) in [("mid", 0.03), ("settled", 0.45)] {
                RunLoop.main.run(until: Date().addingTimeInterval(wait))
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                p.arguments = ["-x", "-o", "-l", "\(wid)", Self.directory.appendingPathComponent("\(prefix)-\(label).png").path]
                try p.run()
                p.waitUntilExit()
            }
            window.orderOut(nil)
        }
    }
}
