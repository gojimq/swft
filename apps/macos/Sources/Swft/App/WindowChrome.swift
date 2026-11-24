import AppKit
import SwiftUI

/// Gives the window an empty unified toolbar so the traffic lights get the macOS 26 inset placement (14pt lights,
/// centred 26pt from the top-left corner, like the reference), while the titlebar stays transparent and content runs
/// underneath. This needs the binary to be stamped with the current SDK; see scripts/bundle.sh.
struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ChromeView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class ChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
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
        }
    }
}
