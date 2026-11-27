import AppKit
import SwftDesign
import SwiftUI
import Testing
@testable import Swft

/// Offscreen screenshots verifying inline subagent rows, parallel subagent groups, native inline detail expansion,
/// and child-thread TopBar back navigation in light and dark appearance.
/// Run with: `SWFT_SNAPSHOT_DIR=/tmp/subagent-shots swift test --filter SubagentSnapshots`
@MainActor
@Suite("SubagentSnapshots", .enabled(if: ProcessInfo.processInfo.environment["SWFT_SNAPSHOT_DIR"] != nil))
struct SubagentSnapshots {
    static let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SWFT_SNAPSHOT_DIR"] ?? NSTemporaryDirectory())

    @Test(arguments: ["light", "dark"])
    func inlineSubagentsCollapsed(appearance: String) throws {
        let model = AppModel.mock()
        model.destination = .thread(MockData.subagentsDetail.summary.id)
        try Self.capture(model, appearance: appearance, name: "subagents-collapsed-\(appearance)")
    }

    @Test(arguments: ["light", "dark"])
    func inlineSubagentsExpanded(appearance: String) throws {
        let model = AppModel.mock()
        model.destination = .thread(MockData.subagentsDetail.summary.id)
        model.expandedSubagentRows = ["subagent-group:sa-group-1", "sa-native-1"]
        try Self.capture(model, appearance: appearance, name: "subagents-expanded-\(appearance)")
    }

    @Test(arguments: ["light", "dark"])
    func subagentChildThreadWithBreadcrumb(appearance: String) throws {
        let model = AppModel.mock()
        model.destination = .thread("t4-sub-research")
        try Self.capture(model, appearance: appearance, name: "subagents-child-\(appearance)")
    }

    @Test(arguments: ["light", "dark"])
    func subagentInRightSidebarTabs(appearance: String) throws {
        let model = AppModel.mock()
        let parentID = MockData.subagentsDetail.summary.id
        model.destination = .thread(parentID)
        model.expandedSubagentRows = ["subagent-group:sa-group-1"]
        _ = model.openSubagentInRightPanel(
            SubagentNavigationTarget(
                threadID: "t4-sub-ui",
                environmentID: nil,
                title: "Reconnect Fixer",
                provider: .codex,
                providerDriver: "codex",
                providerDisplayName: "Codex",
                providerIconURL: nil,
                isRemoteLinked: false
            ),
            for: parentID
        )
        _ = model.openSubagentInRightPanel(
            SubagentNavigationTarget(
                threadID: "t4-sub-research",
                environmentID: nil,
                title: "Codebase Researcher",
                provider: .claude,
                providerDriver: "claudeAgent",
                providerDisplayName: "Claude",
                providerIconURL: nil,
                isRemoteLinked: false
            ),
            for: parentID
        )
        try Self.capture(model, appearance: appearance, name: "subagents-right-sidebar-\(appearance)")
    }

    @Test(arguments: ["light", "dark"])
    func subagentTranscriptCards(appearance: String) throws {
        let turns = SendFlightLogic.turns(from: MockData.subagentsDetail.rows)
        let pinnedClock = MockData.ago(30).addingTimeInterval(95)

        for (label, expanded) in [("collapsed", Set<String>()), ("expanded", Set(["subagent-group:sa-group-1", "sa-native-1"]))] {
            let view = VStack(alignment: .leading, spacing: 24) {
                ForEach(Array(turns.enumerated()), id: \.element.id) { index, turn in
                    SendFlightTurnSection(
                        threadID: MockData.subagentsDetail.summary.id,
                        turn: turn,
                        isLatest: index == turns.count - 1,
                        streamRoomHeight: nil,
                        showWorking: false,
                        fadeBubbleID: nil,
                        expandedFoldIDs: [],
                        expandedSubagentIDs: expanded,
                        parentEnvironmentID: "mock-local",
                        knownEnvironmentIDs: ["mock-local"],
                        reduceMotion: true,
                        onToggleWorkFold: { _ in },
                        onToggleSubagentExpansion: { _ in },
                        onOpenSubagentThread: { _ in },
                        onResolveApproval: { _, _ in }
                    )
                }
            }
            .padding(28)
            .frame(width: 780, alignment: .leading)
            .background(SwftColor.canvas)
            .environment(\.subagentClockNow, pinnedClock)

            try Self.captureView(
                view,
                appearance: appearance,
                name: "subagents-cards-\(label)-\(appearance)",
                size: CGSize(width: 780, height: label == "expanded" ? 960 : 620)
            )
        }
    }

    private static func captureView<V: View>(
        _ view: V,
        appearance: String,
        name: String,
        size: CGSize
    ) throws {
        SwftFonts.register()
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -4000, y: -4000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        window.orderBack(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent("\(name).png"))
        window.orderOut(nil)
    }

    private static func capture(
        _ model: AppModel,
        appearance: String,
        name: String,
        size: CGSize = CGSize(width: 1280, height: 860)
    ) throws {
        SwftFonts.register()
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -4000, y: -4000), size: size),
            styleMask: [.titled, .fullSizeContentView, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        let pinnedClock = MockData.ago(30).addingTimeInterval(95)
        let root = RootView()
            .environment(model)
            .environment(\.subagentClockNow, pinnedClock)
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        window.orderBack(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent("\(name).png"))
        window.orderOut(nil)
    }
}
