import AppKit
import SwiftUI

/// Gives the window an empty unified toolbar so the traffic lights get the macOS 26 inset placement (14pt lights,
/// centred 26pt from the top-left corner, like the reference), while the titlebar stays transparent and content runs
/// underneath. This needs the binary to be stamped with the current SDK; see scripts/bundle.sh.
struct WindowChrome: NSViewRepresentable {
    var onZoomIn: (@MainActor () -> Void)?
    var onZoomOut: (@MainActor () -> Void)?
    var onResetZoom: (@MainActor () -> Void)?

    func makeNSView(context: Context) -> ChromeView {
        let view = ChromeView()
        view.onZoomIn = onZoomIn
        view.onZoomOut = onZoomOut
        view.onResetZoom = onResetZoom
        return view
    }

    func updateNSView(_ nsView: ChromeView, context: Context) {
        nsView.onZoomIn = onZoomIn
        nsView.onZoomOut = onZoomOut
        nsView.onResetZoom = onResetZoom
    }

    static func dismantleNSView(_ nsView: ChromeView, coordinator: ()) {
        nsView.removeKeyMonitor()
    }

    final class ChromeView: NSView {
        var onZoomIn: (@MainActor () -> Void)?
        var onZoomOut: (@MainActor () -> Void)?
        var onResetZoom: (@MainActor () -> Void)?
        private var keyMonitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else {
                removeKeyMonitor()
                return
            }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarSeparatorStyle = .none
            if window.toolbar == nil {
                window.toolbar = NSToolbar(identifier: "swft.main")
            }
            window.toolbarStyle = .unified
            window.isMovableByWindowBackground = false
            // `-SwftWindowSize 1924x1052` pins the window size for screenshot comparisons.
            if let size = UserDefaults.standard.string(forKey: "SwftWindowSize")?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 {
                window.setFrame(NSRect(x: 40, y: 40, width: size[0], height: size[1]), display: true)
            }
            installKeyMonitor()
        }

        private func installKeyMonitor() {
            guard keyMonitor == nil else { return }
            // Complement the View menu shortcuts (`⌘=`, `⌘-`, `⌘0`) so `⌘+` (Shift+=) and numpad `+`/`-`/`0` also work.
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
                guard flags.contains(.command), !flags.contains(.control), !flags.contains(.option) else { return event }
                let chars = event.charactersIgnoringModifiers ?? ""
                if (flags.contains(.shift) && (chars == "+" || chars == "=")) || event.keyCode == 69 {
                    MainActor.assumeIsolated { self.onZoomIn?() }
                    return nil
                }
                if event.keyCode == 78 {
                    MainActor.assumeIsolated { self.onZoomOut?() }
                    return nil
                }
                if event.keyCode == 82 {
                    MainActor.assumeIsolated { self.onResetZoom?() }
                    return nil
                }
                return event
            }
        }

        func removeKeyMonitor() {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
        }
    }
}
