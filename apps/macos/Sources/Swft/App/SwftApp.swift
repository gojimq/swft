import AppKit
import SwftDesign
import SwiftUI

@main
struct SwftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel

    init() {
        SwftFonts.register()
        _model = State(initialValue: AppModel.makeForLaunch())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    appDelegate.onTerminate = { await model.shutdown() }
                    appDelegate.onWillTerminateSync = { model.terminateServerImmediately() }
                    model.startIfNeeded()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1360, height: 860)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { model.checkForUpdates(userInitiated: true) }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.openSettings() }
                    .keyboardShortcut(",")
            }
            CommandGroup(replacing: .newItem) {
                Button("New Thread") { model.goHome() }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") { model.toggleSidebar() }
                    .keyboardShortcut("s", modifiers: [.command, .control])
                Button("Toggle Right Panel") { model.toggleRightPanel() }
                    .keyboardShortcut("b", modifiers: [.command, .option])
                Divider()
                Button("Actual Size") { model.resetUIScale() }
                    .keyboardShortcut("0", modifiers: .command)
                    .disabled(SwftUIScale.isDefault(model.settings.uiScale))
                Button("Zoom In") { model.zoomIn() }
                    .keyboardShortcut("=", modifiers: .command)
                    .disabled(!model.settings.canZoomIn)
                Button("Zoom Out") { model.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(!model.settings.canZoomOut)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var onTerminate: (@MainActor () async -> Void)?
    var onWillTerminateSync: (@MainActor () -> Void)?
    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `swift run` launches a bare executable; make it a regular foreground app.
        NSApp.setActivationPolicy(.regular)
        // `-SwftAppearance light|dark` pins the appearance (used for screenshots).
        switch UserDefaults.standard.string(forKey: "SwftAppearance") {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default:
            if let name = AppearancePreference.load().nsAppearanceName {
                NSApp.appearance = NSAppearance(named: name)
            }
        }
        NSApp.activate()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating, let onTerminate else { return .terminateNow }
        isTerminating = true
        Task { @MainActor in
            await onTerminate()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        onWillTerminateSync?()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
