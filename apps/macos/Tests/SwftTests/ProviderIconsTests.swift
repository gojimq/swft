import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Swft
@testable import SwftDesign
@testable import SwftKit

@Suite("Provider icon mapping and fallback")
struct ProviderIconsTests {
    @Test func mapsEveryKnownServerDriverToItsMark() {
        #expect(ProviderIconKind.resolve(driver: "claudeAgent") == .mark(.claude))
        #expect(ProviderIconKind.resolve(driver: "codex") == .mark(.openai))
        #expect(ProviderIconKind.resolve(driver: "cursor") == .mark(.cursor))
        #expect(ProviderIconKind.resolve(driver: "grok") == .mark(.grok))
        #expect(ProviderIconKind.resolve(driver: "opencode") == .mark(.opencode))
        #expect(ProviderIconKind.resolve(driver: "antigravity") == .mark(.antigravity))
        #expect(ProviderIconKind.resolve(driver: "kiro") == .mark(.kiro))
        #expect(ProviderIconKind.resolve(driver: "pi") == .mark(.pi))
        #expect(ProviderIconKind.resolve(driver: "muse") == .mark(.muse))
        #expect(ProviderIconKind.resolve(driver: "fx") == .mark(.fx))
        #expect(ProviderIconKind.resolve(driver: "openai") == .mark(.openai))
        #expect(ProviderIconKind.resolve(driver: "anthropic") == .mark(.anthropic))
        #expect(ProviderIconKind.resolve(driver: "openrouter") == .mark(.openrouter))
        #expect(ProviderIconKind.resolve(driver: "ollama") == .mark(.ollama))
    }

    @Test func normalizesCaseWhitespaceAndAliases() {
        #expect(ProviderIconKind.resolve(driver: " ClaudeAgent ") == .mark(.claude))
        #expect(ProviderIconKind.resolve(driver: "GROK") == .mark(.grok))
        #expect(ProviderIconKind.resolve(driver: "xAI") == .mark(.grok))
        #expect(ProviderIconKind.resolve(driver: "Gemini") == .mark(.antigravity))
        #expect(ProviderIconKind.resolve(driver: "Muse Code") == .mark(.muse))
        #expect(ProviderIconKind.resolve(driver: "OpenCode Zen") == .mark(.opencode))
    }

    @Test func resolvesAcpRegistryIconsAndRejectsUntrustedOverrides() {
        #expect(
            ProviderIconKind.resolve(driver: "acpRegistry", acpAgentID: "devin")
                == .acpRegistry(iconURL: URL(string: "https://cdn.agentclientprotocol.com/registry/v1/latest/devin.svg"))
        )
        #expect(
            ProviderIconKind.resolve(
                driver: "acpRegistry",
                acpAgentID: "gemini",
                iconURL: "https://cdn.agentclientprotocol.com/registry/icons/gemini.svg"
            ) == .acpRegistry(iconURL: URL(string: "https://cdn.agentclientprotocol.com/registry/icons/gemini.svg"))
        )
        #expect(
            ProviderIconKind.resolve(
                driver: "acpRegistry",
                acpAgentID: "factory-droid",
                iconURL: "https://evil.example.com/droid.svg"
            ) == .acpRegistry(iconURL: URL(string: "https://cdn.agentclientprotocol.com/registry/v1/latest/factory-droid.svg"))
        )
        #expect(
            ProviderIconKind.resolve(
                driver: "acpRegistry",
                iconURL: "http://cdn.agentclientprotocol.com/registry/v1/latest/devin.svg"
            ) == .acpRegistry(iconURL: nil)
        )
        #expect(
            ProviderIconKind.resolve(
                driver: "acpRegistry",
                iconURL: "https://user:pass@cdn.agentclientprotocol.com/registry/v1/latest/devin.svg"
            ) == .acpRegistry(iconURL: nil)
        )
        #expect(ProviderIconKind.resolve(driver: "acpRegistry") == .acpRegistry(iconURL: nil))
        #expect(
            ProviderIconKind.resolve(driver: "acpRegistry", instanceID: "acp_devin")
                == .acpRegistry(iconURL: URL(string: "https://cdn.agentclientprotocol.com/registry/v1/latest/devin.svg"))
        )
    }

    @Test func fallsBackToGenericWithoutFalsePositives() {
        #expect(ProviderIconKind.resolve() == .mark(.generic))
        #expect(ProviderIconKind.resolve(driver: "futureDriver") == .mark(.generic))
        #expect(ProviderIconKind.resolve(driver: "openaiCompatible") == .mark(.generic))
        // Short tokens like "pi" and "fx" must not match inside unrelated words.
        #expect(ProviderIconKind.resolve(name: "Custom API") == .mark(.generic))
        #expect(ProviderIconKind.resolve(name: "Prefix Agent") == .mark(.generic))
        #expect(ProviderIconKind.resolve(name: "Copilot") == .mark(.generic))
        #expect(ProviderIconKind.resolve(instanceID: "pi_personal") == .mark(.pi))
        #expect(ProviderIconKind.resolve(instanceID: "fx-work") == .mark(.fx))
    }

    @Test func resolvesLegacyProviderGlyphCallSitesFromNameOrSymbol() {
        #expect(ProviderIconKind.resolve(name: "Claude") == .mark(.claude))
        #expect(ProviderIconKind.resolve(name: "Codex Personal") == .mark(.openai))
        #expect(ProviderIconKind.resolve(name: "Cursor") == .mark(.cursor))
        #expect(ProviderIconKind.resolve(name: "OpenCode") == .mark(.opencode))
        #expect(ProviderIconKind.resolve(name: "Antigravity") == .mark(.antigravity))
        #expect(ProviderIconKind.resolve(name: "Kiro") == .mark(.kiro))
        #expect(ProviderIconKind.resolve(name: "Muse Code") == .mark(.muse))
        // Custom display name with Swft's earlier SF Symbol placeholder still upgrades cleanly.
        #expect(ProviderIconKind.resolve(name: "Work Account", legacySymbol: "hexagon") == .mark(.openai))
        #expect(ProviderIconKind.resolve(name: "Work Account", legacySymbol: "asterisk") == .mark(.claude))
        #expect(ProviderIconKind.resolve(name: "Work Account", legacySymbol: "circle.dashed") == .mark(.generic))
    }

    @Test func resolvesSubProviderNamesMatchingStudio() {
        #expect(ProviderIconKind.resolveSubProvider("Anthropic") == .anthropic)
        #expect(ProviderIconKind.resolveSubProvider("Anthropic API") == .anthropic)
        #expect(ProviderIconKind.resolveSubProvider("OpenAI") == .openai)
        #expect(ProviderIconKind.resolveSubProvider("OpenRouter") == .openrouter)
        #expect(ProviderIconKind.resolveSubProvider("Ollama") == .ollama)
        #expect(ProviderIconKind.resolveSubProvider("OpenCode") == .opencode)
        #expect(ProviderIconKind.resolveSubProvider("OpenCode Zen") == .opencode)
        #expect(ProviderIconKind.resolveSubProvider("xAI") == .grok)
        #expect(ProviderIconKind.resolveSubProvider("Grok") == .grok)
        #expect(ProviderIconKind.resolveSubProvider("Cursor") == .cursor)
        #expect(ProviderIconKind.resolveSubProvider("Antigravity") == .antigravity)
        #expect(ProviderIconKind.resolveSubProvider("Kiro") == .kiro)
        #expect(ProviderIconKind.resolveSubProvider("Muse") == .muse)
        #expect(ProviderIconKind.resolveSubProvider("Muse Code") == .muse)
        #expect(ProviderIconKind.resolveSubProvider("Xiaomi token plan") == nil)
        #expect(ProviderIconKind.resolveSubProvider("GitHub Copilot") == nil)
    }

    @Test func distinguishesBrandColoredFromMonochromeMarks() {
        #expect(ProviderIconKind.claude.hasBrandColor)
        #expect(ProviderIconKind.antigravity.hasBrandColor)
        #expect(ProviderIconKind.kiro.hasBrandColor)
        #expect(ProviderIconKind.muse.hasBrandColor)
        for mono: ProviderIconKind in [.openai, .cursor, .grok, .opencode, .pi, .fx, .acpRegistry, .anthropic, .openrouter, .ollama, .generic] {
            #expect(!mono.hasBrandColor)
        }
    }

    @Test @MainActor func everyBundledVectorSpecParsesToNonEmptyPathsAndLoadsAntigravity() {
        for kind in ProviderIconKind.allCases where kind != .antigravity && kind != .generic {
            let spec = ProviderIconArtwork.vectorSpec(for: kind)
            #expect(spec != nil, "Missing vector spec for \(kind.rawValue)")
            if let spec {
                #expect(spec.viewBox.width > 0 && spec.viewBox.height > 0)
                #expect(!spec.layers.isEmpty)
                for layer in spec.layers {
                    #expect(!layer.path.isEmpty, "Empty path in \(kind.rawValue)")
                    let box = layer.path.boundingRect
                    #expect(box.width > 0 && box.height > 0, "Degenerate bounds in \(kind.rawValue)")
                    #expect(box.minX.isFinite && box.maxX.isFinite && box.minY.isFinite && box.maxY.isFinite)
                }
            }
        }
        #expect(ProviderIconArtwork.antigravityImage != nil)
    }

    @Test func svgPathParserHandlesArcsCompressedFlagsAndDocuments() {
        // Compressed flags `01` followed immediately by endpoint `10 10`, plus decimal-delimited numbers.
        let arc = SVGPathParser.parsePath("M0 0a5 5 0 0110 10l-1.5.5z")
        #expect(!arc.isEmpty)
        let box = arc.boundingRect
        #expect(box.width > 8 && box.height > 8)

        let svg = """
        <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
          <defs><clipPath id="c"><rect width="24" height="24"/></clipPath></defs>
          <path d="M2 12L12 2L22 12Z" fill-rule="evenodd"/>
          <circle cx="12" cy="18" r="2"/>
        </svg>
        """
        let parsed = SVGPathParser.parseSVGDocument(Data(svg.utf8))
        #expect(parsed != nil)
        #expect(parsed?.viewBox == CGRect(x: 0, y: 0, width: 24, height: 24))
        #expect(parsed?.paths.count == 2)
        #expect(parsed?.paths.first?.evenOdd == true)
    }

    @Test func adaptersPreserveServerDriverAndIconURLForPickerAndSidebar() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let devinURL = "https://cdn.agentclientprotocol.com/registry/v1/latest/devin.svg"
        let devin = ServerProvider(
            instanceId: "acp_devin",
            driver: "acpRegistry",
            displayName: "Devin",
            iconUrl: devinURL,
            enabled: true,
            installed: true,
            status: .ready,
            auth: ServerProviderAuth(status: .authenticated),
            checkedAt: now,
            models: [ServerProviderModel(slug: "default", name: "Devin")]
        )
        let grok = ServerProvider(
            instanceId: "grok-main",
            driver: "grok",
            displayName: "Grok",
            enabled: true,
            installed: true,
            status: .ready,
            auth: ServerProviderAuth(status: .authenticated),
            checkedAt: now,
            models: [ServerProviderModel(slug: "grok-4", name: "Grok 4")]
        )

        let devinHarness = SwftAdapters.pickerHarness(from: devin)
        #expect(devinHarness.driver == "acpRegistry")
        #expect(devinHarness.iconUrl == devinURL)
        #expect(SwftAdapters.resolvedProviderIcon(for: devinHarness) == .acpRegistry(iconURL: URL(string: devinURL)))

        let grokShell = ThreadShell(
            id: "t-grok",
            projectId: "p1",
            title: "Audit latency",
            providerInstanceId: "grok-main",
            modelSelection: ModelSelection(instanceId: "grok-main", model: "grok-4"),
            status: .idle,
            createdAt: now,
            updatedAt: now
        )
        let summary = SwftAdapters.threadSummary(
            from: grokShell,
            projectsByID: [:],
            providersByID: ["grok-main": grok],
            hostName: "Mac",
            activelyViewingThreadID: nil
        )
        #expect(summary.providerDriver == "grok")
        #expect(SwftAdapters.resolvedProviderIcon(for: summary) == .mark(.grok))
        let inbox = summary.inboxModel(now: now)
        #expect(inbox.providerDriver == "grok")
    }

    @Test @MainActor func preservesExistingPublicSwftDesignSignatures() {
        // Legacy initializers must remain source-compatible for parallel branches.
        let glyph = ProviderGlyph(symbol: "hexagon", tint: SwftColor.textSecondary, name: "Codex")
        let mark = ProviderMark(symbol: "asterisk", monogram: "Claude", size: 14)
        let railItem = PickerRailItem(
            id: "claudeAgent",
            symbol: "asterisk",
            monogram: "Claude",
            tint: SwftColor.textSecondary,
            accent: nil,
            tooltip: "Claude",
            inUse: true
        )
        let inboxModel = ThreadInboxRow.Model(
            projectName: "Swft",
            projectInitials: "SW",
            projectTint: 0,
            time: "now",
            title: "Verify API seam",
            location: "main",
            locationSymbol: "arrow.triangle.branch",
            status: .none,
            providerSymbol: "hexagon",
            providerTint: SwftColor.textSecondary,
            providerName: "Codex"
        )
        let icon = ProviderIcon(provider: "claudeAgent", size: 16)
        let subIcon = SubProviderIcon(name: "OpenRouter", size: 12)

        _ = (glyph, mark, railItem, inboxModel, icon, subIcon)
        #expect(railItem.provider == nil)
        #expect(inboxModel.providerDriver == nil)
    }
}

/// Offscreen visual gallery of every provider and sub-provider icon at 12pt, 16pt, and 20pt in light & dark mode.
/// Run with: `SWFT_SNAPSHOT_DIR=/tmp/shots swift test --filter ProviderIconGallerySnapshots`
@MainActor
@Suite("ProviderIconGallerySnapshots", .enabled(if: ProcessInfo.processInfo.environment["SWFT_SNAPSHOT_DIR"] != nil))
struct ProviderIconGallerySnapshots {
    @Test(arguments: ["light", "dark"])
    func gallery(appearance: String) throws {
        SwftFonts.register()
        let size = CGSize(width: 740, height: 620)
        let view = ProviderIconGalleryView()
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -4000, y: -4000), size: size),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        window.orderBack(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SWFT_SNAPSHOT_DIR"] ?? NSTemporaryDirectory())
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try png.write(to: dir.appendingPathComponent("provider-icons-gallery-\(appearance).png"))
        window.orderOut(nil)
    }
}

private struct ProviderIconGalleryView: View {
    private let rows: [(String, ProviderIconKind)] = [
        ("Claude", .claude),
        ("Codex / OpenAI", .openai),
        ("Cursor", .cursor),
        ("Grok / xAI", .grok),
        ("OpenCode", .opencode),
        ("Antigravity", .antigravity),
        ("Kiro", .kiro),
        ("Pi", .pi),
        ("Muse Code", .muse),
        ("fx", .fx),
        ("ACP Registry", .acpRegistry),
        ("Anthropic", .anthropic),
        ("OpenRouter", .openrouter),
        ("Ollama", .ollama),
        ("Fallback", .generic),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Text("Provider").frame(width: 150, alignment: .leading)
                Text("12pt").frame(width: 44)
                Text("16pt").frame(width: 44)
                Text("20pt").frame(width: 44)
                Text("Mono 16pt").frame(width: 72)
                Text("Accent 16pt").frame(width: 80)
                Text("Glyph").frame(width: 48)
            }
            .font(SwftType.captionStrong)
            .foregroundStyle(SwftColor.textTertiary)

            Divider()

            ForEach(rows, id: \.0) { label, kind in
                HStack(spacing: 16) {
                    Text(label)
                        .font(SwftType.label)
                        .foregroundStyle(SwftColor.textPrimary)
                        .frame(width: 150, alignment: .leading)
                    ProviderIcon(kind: kind, size: 12)
                        .foregroundStyle(SwftColor.textPrimary)
                        .frame(width: 44)
                    ProviderIcon(kind: kind, size: 16)
                        .foregroundStyle(SwftColor.textPrimary)
                        .frame(width: 44)
                    ProviderIcon(kind: kind, size: 20)
                        .foregroundStyle(SwftColor.textPrimary)
                        .frame(width: 44)
                    ProviderIcon(kind: kind, size: 16, renderingMode: .monochrome)
                        .foregroundStyle(SwftColor.textSecondary)
                        .frame(width: 72)
                    ProviderIcon(kind: kind, size: 16, renderingMode: .monochrome)
                        .foregroundStyle(SwftColor.accent)
                        .frame(width: 80)
                    ProviderGlyph(provider: kind.rawValue, name: label)
                        .frame(width: 48)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SwftColor.canvas)
    }
}
