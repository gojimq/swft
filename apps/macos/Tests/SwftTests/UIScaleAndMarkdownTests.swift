import AppKit
import Foundation
import SwftDesign
import SwiftUI
import Testing
@testable import Swft

@Suite("UI Scale & Preference")
struct UIScaleTests {
    @Test func zoomSteppingClampingAndLabels() {
        #expect(SwftUIScale.clamp(0.1) == SwftUIScale.minScale)
        #expect(SwftUIScale.clamp(3.0) == SwftUIScale.maxScale)
        #expect(SwftUIScale.clamp(.nan) == SwftUIScale.defaultScale)
        #expect(SwftUIScale.isDefault(1.0))
        #expect(!SwftUIScale.isDefault(0.85))

        #expect(SwftUIScale.steppedOut(from: 1.00) == 0.95)
        #expect(SwftUIScale.steppedOut(from: 0.95) == 0.90)
        #expect(SwftUIScale.steppedOut(from: 0.90) == 0.85)
        #expect(SwftUIScale.steppedOut(from: 0.75) == 0.75)
        #expect(!SwftUIScale.canZoomOut(from: 0.75))

        #expect(SwftUIScale.steppedIn(from: 0.85) == 0.90)
        #expect(SwftUIScale.steppedIn(from: 1.00) == 1.10)
        #expect(SwftUIScale.steppedIn(from: 1.50) == 1.50)
        #expect(!SwftUIScale.canZoomIn(from: 1.50))

        #expect(SwftUIScale.percentLabel(for: 0.85) == "85%")
        #expect(SwftUIScale.percentLabel(for: 1.00) == "100%")
        #expect(SwftUIScale.percentLabel(for: 1.20) == "120%")
    }

    @Test func trafficLightClearancePreservesRealWindowPointsWhenZoomedOut() {
        // At 0.75x scale, 76pt horizontal clearance needs 101.33 logical pt so 101.33 * 0.75 = 76pt on screen.
        let clearance75 = SwftUIScale.trafficLightHorizontalClearance(base: 76, scale: 0.75)
        #expect(abs(clearance75 * 0.75 - 76) < 0.01)

        // At 1.2x scale, keep at least the base clearance so chrome stays balanced.
        let clearance120 = SwftUIScale.trafficLightHorizontalClearance(base: 76, scale: 1.20)
        #expect(clearance120 == 76)

        // Top bar keeps at least 44pt physical height even at 75% scale.
        let bar75 = SwftUIScale.trafficLightTopBarHeight(base: 52, minimumPhysicalHeight: 44, scale: 0.75)
        #expect(bar75 * 0.75 >= 43.99)
        #expect(SwftUIScale.trafficLightTopBarHeight(base: 52, minimumPhysicalHeight: 44, scale: 1.0) == 52)
    }

    @Test func unscaledRectDividesOriginAndSizeByScale() {
        let rect = CGRect(x: 85, y: 170, width: 632.4, height: 80.75)
        let logical = SwftUIScale.unscaledRect(rect, scale: 0.85)
        #expect(abs(logical.origin.x - 100) < 0.01)
        #expect(abs(logical.origin.y - 200) < 0.01)
        #expect(abs(logical.size.width - 744) < 0.01)
        #expect(abs(logical.size.height - 95) < 0.01)
    }

    @MainActor
    @Test func preferenceAndSettingsControllerPersistScale() {
        let suiteName = "swft.test.uiscale.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(UIScalePreference.load(from: defaults) == 1.0)

        let controller = SettingsController(defaults: defaults)
        #expect(controller.uiScale == 1.0)
        controller.zoomOut(showHUD: true)
        #expect(controller.uiScale == 0.95)
        #expect(controller.zoomHUDVisible)
        #expect(abs(UIScalePreference.load(from: defaults) - 0.95) < 0.001)

        controller.setUIScale(0.85, showHUD: false)
        #expect(abs(UIScalePreference.load(from: defaults) - 0.85) < 0.001)

        controller.resetUIScale(showHUD: false)
        #expect(controller.uiScale == 1.0)
        #expect(defaults.object(forKey: UIScalePreference.defaultsKey) == nil)
    }
}

@Suite("Rich GFM Markdown & Code Highlighting")
struct RichMarkdownTests {
    @Test func parsesEmptyLeadingHeaderTableAndNormalizesRows() {
        let md = """
        **Trade-offs: Three.js vs. Godot**
        || Three.js (WebGL2) | Godot 4.7 |
        |---|---|---|
        | **Distribution** | Instant URL — works in any browser | Requires exporting/signing native builds |
        | **Physics** | `rapier3d` WASM | Built-in `CharacterBody3D` |
        """
        let blocks = MarkdownProse.blocks(md)
        #expect(blocks.count == 2)
        guard case .paragraph(let lead) = blocks[0] else {
            Issue.record("Expected leading paragraph")
            return
        }
        #expect(lead == "**Trade-offs: Three.js vs. Godot**")

        guard case .table(let table) = blocks[1] else {
            Issue.record("Expected parsed GFM table")
            return
        }
        #expect(table.headers == ["", "Three.js (WebGL2)", "Godot 4.7"])
        #expect(table.alignments == [.leading, .leading, .leading])
        #expect(table.rows.count == 2)
        #expect(table.rows[0][0] == "**Distribution**")
        #expect(table.rows[1][2] == "Built-in `CharacterBody3D`")
    }

    @Test func parsesTableAlignmentsEscapedPipesAndInlineCodePipes() {
        let md = """
        | Key | Expression | Score |
        | :--- | :---: | ---: |
        | bitwise | `a | b` | 10 |
        | escaped | foo \\| bar | 20 |
        | short | only two |
        """
        let blocks = MarkdownProse.blocks(md)
        guard case .table(let table) = blocks.first else {
            Issue.record("Expected table")
            return
        }
        #expect(table.alignments == [.leading, .center, .trailing])
        #expect(table.rows[0] == ["bitwise", "`a | b`", "10"])
        #expect(table.rows[1] == ["escaped", "foo | bar", "20"])
        #expect(table.rows[2] == ["short", "only two", ""])

        let serializedMD = MarkdownTableSerializer.toMarkdown(table)
        #expect(serializedMD.contains("| --- | :---: | ---: |"))
        #expect(serializedMD.contains("foo \\| bar"))

        let csv = MarkdownTableSerializer.toCSV(
            MarkdownProse.TableData(
                headers: ["Name", "Notes"],
                alignments: [.leading, .leading],
                rows: [["A, B", #"Said "hi""#]]
            )
        )
        #expect(csv == "Name,Notes\n\"A, B\",\"Said \"\"hi\"\"\"")
    }

    @Test func parsesBlockquotesAlertsRulesAndTaskLists() {
        let md = """
        > Standard quote line
        > with a second line.

        ---

        > [!TIP]
        > Prefer `SwftUIScale` helpers for traffic-light clearance.

        - [x] Done task
        - [ ] Open task
          - Nested bullet
        """
        let blocks = MarkdownProse.blocks(md)
        #expect(blocks.count == 6)

        guard case .blockquote(nil, let standardBody) = blocks[0] else {
            Issue.record("Expected standard blockquote")
            return
        }
        #expect(standardBody.count == 1)

        #expect(blocks[1] == .thematicBreak)

        guard case .blockquote(.tip, let tipBody) = blocks[2] else {
            Issue.record("Expected TIP alert blockquote")
            return
        }
        #expect(tipBody.count == 1)

        #expect(blocks[3] == .listItem(marker: .task(checked: true), depth: 0, text: "Done task"))
        #expect(blocks[4] == .listItem(marker: .task(checked: false), depth: 0, text: "Open task"))
        #expect(blocks[5] == .listItem(marker: .bullet, depth: 1, text: "Nested bullet"))
    }

    @Test func inlineCodeHasTintedPillBackgroundAndFileLinksShowLineNumbers() {
        let inline = MarkdownProse.inline(
            "Updated [ServerProcess.swift](file:///tmp/ServerProcess.swift#L377-L384) to call `confstr()`.",
            style: .body
        )
        let plain = String(inline.characters)
        #expect(plain.contains("ServerProcess.swift \u{00B7} L377\u{2013}384"))

        let codeRun = inline.runs.first { String(inline[$0.range].characters) == "confstr()" }
        #expect(codeRun?.backgroundColor != nil)
        #expect(codeRun?.font == SwftType.inlineCode)

        // Do not duplicate line numbers if the label already includes them.
        let alreadyLabeled = MarkdownProse.inline(
            "See [ServerProcess.swift:377](file:///tmp/ServerProcess.swift#L377-L384).",
            style: .body
        )
        #expect(!String(alreadyLabeled.characters).contains("\u{00B7} L377"))
    }

    @Test func syntaxHighlighterColorsCodeAndLeavesPlainTextUncolored() {
        let swiftAttr = SwftCodeHighlight.attributed("let count = 42 // answer\nlet name = \"Swft\"", language: "swift")
        let coloredRuns = swiftAttr.runs.filter { $0.foregroundColor != nil }
        #expect(coloredRuns.count >= 4)

        let plainAttr = SwftCodeHighlight.attributed("let count = 42", language: "plaintext")
        #expect(plainAttr.runs.allSatisfy { $0.foregroundColor == nil })
    }
}

@MainActor
@Suite("UIScaleAndMarkdownSnapshots", .serialized, .enabled(if: ProcessInfo.processInfo.environment["SWFT_SNAPSHOT_DIR"] != nil))
struct UIScaleAndMarkdownSnapshots {
    private static let richReplySample = """
    ## Rendering Architecture & Trade-offs

    1. **Per-material opt-in outlines** ([pixel_outline.gdshader](file:///tmp/pixel_outline.gdshader#L14-L52)):
       - Godot Forward+ gives you `hint_depth_texture` and `hint_normal_roughness_texture` for free.
       - Three.js uses `WebGLRenderTarget` with `count: 2` + `DepthTexture` to keep opt-in masking clean:
         - Output color to attachment `0` and `(viewNormal, outlineMask)` to attachment `1`.
         - Note: depth reconstruction changes from Godot's reversed-Z to WebGL `[0..1]`.
    2. **Custom lighting + canopy shadows** ([tree_foliage.gdshader](file:///tmp/tree_foliage.gdshader#L88)):
       - Compute shadow lookup from pre-billboard vertex positions for crisp `4096px` shadows.

    ### Trade-offs: Three.js vs. Godot

    || Three.js (WebGL2) | Godot 4.7 |
    |---|---|---|
    | **Distribution** | Instant URL — works in any browser (desktop/mobile), zero install | Requires exporting/signing native builds (or heavier WebAssembly export) |
    | **Visual parity** | Same look once custom MRT outline + shadow cel-shader base is set up | Built-in G-buffer + `light()` + `LIGHT_VERTEX` out of the box |
    | **Physics / collisions** | Need lightweight custom height/collider logic or `rapier3d` WASM | Built-in `CharacterBody3D`, `move_and_slide()`, `Area3D` |
    | **Scene tooling** | Code-first (matches how `JTgame` & `StarfallLanterns` were built!) | Full visual editor & inspector |

    > [!TIP]
    > A small **Three.js + Vite** vertical slice proves all 4 core pieces side-by-side before porting the rest.

    - [x] Verify `WebGLRenderTarget` MRT outline pass
    - [ ] Prototype pre-billboard foliage shadow shader

    ---

    **Recommendation:** Start with the vertical slice and compare frame times on both desktop and mobile.
    """

    private static let codeSample = """
    // MRT outline pass setup
    export function createOutlineTarget(width: number, height: number) {
      return new THREE.WebGLRenderTarget(width, height, {
        count: 2,
        samples: 0,
      });
    }
    """

    @Test func renderRichMarkdownAndScaledWindowSnapshots() async throws {
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SWFT_SNAPSHOT_DIR"]!)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // 1. Rich markdown card in Dark & Light mode.
        let card = VStack(alignment: .leading, spacing: 14) {
            MessageText(Self.richReplySample)
            CodeBlock(Self.codeSample, language: "typescript")
        }
        .padding(24)
        .frame(width: 760, alignment: .leading)
        .background(SwftColor.canvas)

        try await capture(card, size: CGSize(width: 760, height: 920), appearance: .darkAqua, to: dir.appendingPathComponent("rich-markdown-dark.png"))
        try await capture(card, size: CGSize(width: 760, height: 920), appearance: .aqua, to: dir.appendingPathComponent("rich-markdown-light.png"))

        // 2. Full RootView comparison at 100% vs 85% UI scale (Dark mode, 1440x900).
        let model100 = makeRichThreadModel(scale: 1.00)
        try await capture(RootView().environment(model100), size: CGSize(width: 1440, height: 900), appearance: .darkAqua, to: dir.appendingPathComponent("root-scale-100.png"))

        let model85 = makeRichThreadModel(scale: 0.85)
        try await capture(RootView().environment(model85), size: CGSize(width: 1440, height: 900), appearance: .darkAqua, to: dir.appendingPathComponent("root-scale-85.png"))

        let settingsModel = AppModel.mock()
        settingsModel.settings.setUIScale(0.85, showHUD: false)
        settingsModel.openSettings(section: .general)
        try await capture(RootView().environment(settingsModel), size: CGSize(width: 1280, height: 820), appearance: .darkAqua, to: dir.appendingPathComponent("settings-scale-85.png"))
    }

    private func makeRichThreadModel(scale: CGFloat) -> AppModel {
        let model = AppModel.mock()
        model.settings.setUIScale(scale, showHUD: false)
        let id = MockData.threadDetail.summary.id
        var detail = MockData.threadDetail
        detail.items = [
            TranscriptItem(id: "u1", kind: .user("Compare Three.js WebGL2 vs Godot 4.7 for our isometric cel-shaded game.", attachments: [])),
            TranscriptItem(id: "a1", kind: .assistant(blocks: [
                .text(Self.richReplySample),
                .code(language: "typescript", source: Self.codeSample),
            ], streaming: false)),
        ]
        model.setMockDetail(detail, for: id)
        model.open(id)
        return model
    }

    private func capture<V: View>(
        _ view: V,
        size: CGSize,
        appearance: NSAppearance.Name,
        to url: URL
    ) async throws {
        SwftFonts.register()
        let window = NSWindow(
            contentRect: NSRect(x: 60, y: 60, width: size.width, height: size.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar = NSToolbar(identifier: "snapshot.\(UUID().uuidString)")
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.appearance = window.appearance
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        for _ in 0..<6 {
            try await Task.sleep(for: .milliseconds(50))
            await Task.yield()
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        proc.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
        try proc.run()
        proc.waitUntilExit()
        #expect(proc.terminationStatus == 0)
    }
}
