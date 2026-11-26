import AppKit
import SwftDesign
import SwiftUI
import Testing
@testable import Swft

/// Offscreen snapshots of the right panel: the "Open a surface" launcher and every surface tab, light & dark.
/// Run with: `SWFT_SNAPSHOT_DIR=/tmp/swft-right-panel-review swift test --filter RightPanelSnapshots`
///
/// Renders the real `TopBar` over the canvas beside the real `RightPanelContainerView` rather than the whole
/// `RootView`: the unified toolbar's scroll-edge backdrop blanks titlebar-region content in offscreen captures.
@MainActor
@Suite("RightPanelSnapshots", .enabled(if: ProcessInfo.processInfo.environment["SWFT_SNAPSHOT_DIR"] != nil))
struct RightPanelSnapshots {
    static let threadID = MockData.threadDetail.summary.id

    @Test(arguments: ["light", "dark"])
    func launcher(appearance: String) throws {
        let model = Self.threadModel()
        model.rightPanel.openPanel(for: Self.threadID)
        try Self.capture(model, appearance: appearance, name: "rp-launcher-\(appearance)")
    }

    @Test(arguments: ["light", "dark"])
    func launcherWithTabs(appearance: String) throws {
        let model = Self.modelWithAllTabs()
        _ = model.rightPanel.openLauncherTab(for: Self.threadID)
        try Self.capture(model, appearance: appearance, name: "rp-launcher-tabs-\(appearance)")
    }

    @Test(arguments: [
        "browser-light", "browser-dark",
        "files-light", "files-dark",
        "linked-light", "linked-dark",
        "device-light", "device-dark",
        "sidechat-light", "sidechat-dark",
    ])
    func surface(variant: String) throws {
        let parts = variant.split(separator: "-").map(String.init)
        let surface = parts[0]
        let appearance = parts[1]
        let model = Self.modelWithAllTabs()
        let target = model.rightPanel.tabs(for: Self.threadID).first { tab in
            switch (surface, tab.payload) {
            case ("browser", .browser), ("files", .files), ("linked", .linkedItems),
                 ("device", .device), ("sidechat", .sideChat): true
            default: false
            }
        }
        if let target { model.rightPanel.activateTab(target.id, for: Self.threadID) }
        try Self.capture(model, appearance: appearance, name: "rp-\(surface)-\(appearance)")
    }

    /// A project-less thread: Files is disabled in the launcher and its tab shows the no-project state.
    @Test(arguments: ["light", "dark"])
    func noProject(appearance: String) throws {
        let model = AppModel.mock()
        model.destination = .thread("t6")
        model.rightPanel.openPanel(for: "t6")
        try Self.capture(model, appearance: appearance, name: "rp-noproject-launcher-\(appearance)", threadID: "t6")
        model.rightPanel.openFiles(for: "t6")
        try Self.capture(model, appearance: appearance, name: "rp-noproject-files-\(appearance)", threadID: "t6")
    }

    /// Single active Dia curved tab with `+` hugging its right shoulder.
    @Test(arguments: ["light", "dark"])
    func diaSingleTab(appearance: String) throws {
        let model = Self.threadModel()
        _ = model.rightPanel.openLauncherTab(for: Self.threadID)
        try Self.capture(model, appearance: appearance, name: "dia-single-tab-\(appearance)")
    }

    /// Multi-tab strip testing active tab in first, middle, and last slots so both shoulders and inactive dividers are verified.
    @Test(arguments: [
        "first-light", "first-dark",
        "middle-light", "middle-dark",
        "last-light", "last-dark",
    ])
    func diaMultiTabPositions(variant: String) throws {
        let parts = variant.split(separator: "-").map(String.init)
        let position = parts[0]
        let appearance = parts[1]
        let model = Self.modelWithThreeTabs()
        let tabs = model.rightPanel.tabs(for: Self.threadID)
        switch position {
        case "first":
            if let first = tabs.first { model.rightPanel.activateTab(first.id, for: Self.threadID) }
        case "middle":
            if tabs.count > 1 { model.rightPanel.activateTab(tabs[1].id, for: Self.threadID) }
        case "last":
            if let last = tabs.last { model.rightPanel.activateTab(last.id, for: Self.threadID) }
        default:
            break
        }
        try Self.capture(model, appearance: appearance, name: "dia-multi-\(position)-\(appearance)")
    }

    /// The whole window with the panel maximized over the chat column (both with sidebar visible and hidden for traffic-light clearance).
    @Test(arguments: ["light", "dark"])
    func maximized(appearance: String) throws {
        let model = Self.modelWithAllTabs()
        if let files = model.rightPanel.tabs(for: Self.threadID).first(where: { $0.surfaceKind == .files }) {
            model.rightPanel.activateTab(files.id, for: Self.threadID)
        }
        model.rightPanel.setMaximized(true, for: Self.threadID)
        try Self.captureMaximized(model, appearance: appearance, name: "dia-maximized-sidebar-open-\(appearance)")

        model.sidebarVisible = false
        try Self.captureMaximized(model, appearance: appearance, name: "dia-maximized-sidebar-hidden-\(appearance)")
    }

    private static func threadModel() -> AppModel {
        let model = AppModel.mock()
        model.destination = .thread(threadID)
        return model
    }

    private static func modelWithThreeTabs() -> AppModel {
        let model = threadModel()
        let panel = model.rightPanel
        panel.openBrowser(urlString: "http://localhost:5173", pageTitle: "Swft App", for: threadID)
        panel.openFiles(selectedFilePath: "Package.swift", for: threadID)
        panel.openLinkedItems(for: threadID)
        return model
    }

    private static func modelWithAllTabs() -> AppModel {
        let model = threadModel()
        let panel = model.rightPanel
        panel.openBrowser(for: threadID)
        panel.openFiles(selectedFilePath: "Package.swift", for: threadID)
        panel.openLinkedItems(for: threadID)
        panel.openDevice(for: threadID)
        panel.openSideChat(sideThreadId: "mock-side-review", title: "URL edge cases", for: threadID)
        return model
    }

    private static func captureMaximized(_ model: AppModel, appearance: String, name: String, threadID: String = threadID) throws {
        let size = CGSize(width: 1120, height: 780)
        let root = HStack(spacing: 0) {
            if model.sidebarVisible {
                SidebarView()
                    .frame(width: SwftLayout.sidebarWidth)
            }
            RightPanelContainerView(threadID: threadID, availableWindowWidth: size.width)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: size.width, height: size.height)
        .background(SwftColor.sidebar)
        .environment(model)
        try Self.renderSnapshot(root: root, size: size, appearance: appearance, name: name)
    }

    private static func capture(_ model: AppModel, appearance: String, name: String, threadID: String = threadID) throws {
        let chatWidth: CGFloat = 420
        let panelWidth = RightPanelMetrics.defaultWidth
        let size = CGSize(width: chatWidth + panelWidth, height: 820)
        let root = HStack(spacing: 0) {
            ZStack(alignment: .top) {
                SwftColor.canvas
                TopBar()
            }
            .frame(width: chatWidth)
            RightPanelContainerView(threadID: threadID, availableWindowWidth: 1280)
                .frame(width: panelWidth)
        }
        .frame(width: size.width, height: size.height)
        .environment(model)
        try Self.renderSnapshot(root: root, size: size, appearance: appearance, name: name)
    }

    private static func renderSnapshot<V: View>(root: V, size: CGSize, appearance: String, name: String) throws {
        SwftFonts.register()
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -4000, y: -4000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        window.orderBack(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(1.6))
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: Snapshots.directory, withIntermediateDirectories: true)
        try png.write(to: Snapshots.directory.appendingPathComponent("\(name).png"))
        window.orderOut(nil)
    }
}
