import AppKit
import SwftDesign
import SwiftUI
import Testing
@testable import Swft

/// Offscreen screenshots of mock screens, for reviewing design changes without launching the app.
/// Skipped unless `SWFT_SNAPSHOT_DIR` is set:
///
///     SWFT_SNAPSHOT_DIR=/tmp/shots swift test --filter Snapshots
@MainActor
@Suite("Snapshots", .enabled(if: ProcessInfo.processInfo.environment["SWFT_SNAPSHOT_DIR"] != nil))
struct Snapshots {
    static let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SWFT_SNAPSHOT_DIR"] ?? NSTemporaryDirectory())

    @Test(arguments: ["light", "dark"])
    func thread(appearance: String) throws {
        let model = AppModel.mock()
        model.destination = .thread(MockData.threadDetail.summary.id)
        try Self.capture(model, appearance: appearance, name: "thread-\(appearance)")
    }

    @Test(arguments: ["light", "dark"])
    func threadExpandedFolds(appearance: String) throws {
        let model = AppModel.mock()
        model.destination = .thread(MockData.threadDetail.summary.id)
        model.expandedWorkFolds = Set(MockData.threadDetail.rows.compactMap(\.workFoldID))
        try Self.capture(model, appearance: appearance, name: "thread-folds-open-\(appearance)")
    }

    @Test(arguments: ["light", "dark"])
    func approval(appearance: String) throws {
        let model = AppModel.mock()
        model.destination = .thread(MockData.approvalDetail.summary.id)
        try Self.capture(model, appearance: appearance, name: "approval-\(appearance)")
    }

    @Test(arguments: ["light", "dark"])
    func home(appearance: String) throws {
        try Self.capture(AppModel.mock(), appearance: appearance, name: "home-\(appearance)")
    }

    @Test(arguments: ["light", "dark"])
    func pickerRail(appearance: String) throws {
        let model = AppModel.mock()
        model.destination = .thread(MockData.threadDetail.summary.id)
        model.toggleModelPicker()
        try Self.capture(model, appearance: appearance, name: "picker-rail-\(appearance)")
    }

    @Test(arguments: ["light", "dark"])
    func pickerSearch(appearance: String) throws {
        let model = AppModel.mock()
        model.destination = .thread(MockData.threadDetail.summary.id)
        model.toggleModelPicker()
        model.modelPicker?.setQuery("gpt")
        model.handleModelPickerKey(.down)
        try Self.capture(model, appearance: appearance, name: "picker-search-\(appearance)")
    }

    /// Browsing the two Codex accounts with the keyboard on the thinking slider.
    @Test(arguments: ["light", "dark"])
    func pickerThinking(appearance: String) throws {
        let model = AppModel.mock()
        model.destination = .thread(MockData.threadDetail.summary.id)
        model.selectReasoningChoice("xhigh")
        model.toggleModelPicker()
        model.modelPicker?.focus = .rail
        model.handleModelPickerKey(.down)
        model.modelPicker?.focus = .thinking
        try Self.capture(model, appearance: appearance, name: "picker-thinking-\(appearance)")
    }

    @Test func pickerHome() throws {
        let model = AppModel.mock()
        model.toggleModelPicker()
        model.modelPicker?.selectGroup("opencode", in: ModelPickerLogic.groups(model.pickerCatalog.harnesses))
        try Self.capture(model, appearance: "light", name: "picker-home-light")
    }

    /// The trigger swapping models mid-animation: one label, never two overlapping.
    @Test func triggerSwap() throws {
        let model = AppModel.mock()
        model.destination = .thread(MockData.threadDetail.summary.id)
        try Self.capture(model, appearance: "light", name: "trigger-swap") {
            if let luna = MockData.models.first(where: { $0.id == "codex::luna" }) {
                withAnimation(SwftMotion.spring) { model.selectModel(luna) }
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    /// Mid-switch frame after clicking through threads faster than the screen animation: one transcript, one title.
    @Test func rapidThreadSwitch() throws {
        let model = AppModel.mock()
        model.destination = .thread("t1")
        try Self.capture(model, appearance: "light", name: "rapid-switch") {
            for id in ["t2", "t3", "t5", "t2"] {
                model.open(id)
                RunLoop.main.run(until: Date().addingTimeInterval(0.06))
            }
        }
    }

    static func capture(
        _ model: AppModel,
        appearance: String,
        name: String,
        size: CGSize = CGSize(width: 1280, height: 860),
        then interact: () -> Void = {}
    ) throws {
        SwftFonts.register()
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -4000, y: -4000), size: size),
            styleMask: [.titled, .fullSizeContentView, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: RootView().environment(model))
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        window.orderBack(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        interact()
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent("\(name).png"))
        window.orderOut(nil)
    }
}
