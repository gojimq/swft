import AppKit
import SwiftUI

/// Gives the window an empty unified toolbar so the traffic lights sit centred in a 52pt band
/// (matching the sidebar's top row), while the titlebar stays transparent and content runs underneath.
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
        }
    }
}
