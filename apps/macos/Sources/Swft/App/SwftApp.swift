import AppKit
import SwftDesign
import SwiftUI

@main
struct SwftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.mock()

    init() {
        SwftFonts.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1360, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Thread") { model.destination = .home }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") { model.toggleSidebar() }
                    .keyboardShortcut("s", modifiers: [.command, .control])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // `swift run` launches a bare executable; make it a regular foreground app.
        NSApp.setActivationPolicy(.regular)
        // `-SwftAppearance light|dark` pins the appearance (used for screenshots).
        switch UserDefaults.standard.string(forKey: "SwftAppearance") {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
