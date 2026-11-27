import AppKit
import SwftDesign
import SwiftUI
import Testing
@testable import Swft

@MainActor
@Suite("RightPanelToggleFrames", .serialized, .enabled(if: ProcessInfo.processInfo.environment["SWFT_FRAMES_DIR"] != nil))
struct RightPanelToggleFrames {
    @Test func toggle() async throws {
        let model = AppModel.mock()
        model.open(MockData.threadDetail.summary.id)
        try await NewThreadMotionFrames.record(model, name: "right-toggle", frames: 20, interval: 0.025) {
            model.toggleRightPanel()
        }
    }

    @Test func close() async throws {
        let model = AppModel.mock()
        model.open(MockData.threadDetail.summary.id)
        model.toggleRightPanel()
        try await NewThreadMotionFrames.record(model, name: "right-close", frames: 20, interval: 0.025) {
            model.toggleRightPanel()
        }
    }

    /// A real click: mouse down and up on the toggle, so the press release lands in the same update as the toggle.
    @Test func click() async throws {
        let model = AppModel.mock()
        model.open(MockData.threadDetail.summary.id)
        try await NewThreadMotionFrames.record(model, name: "right-click", frames: 20, interval: 0.025) { window in
            let point = NSPoint(x: 1250, y: window.contentView!.bounds.height - 26)
            for kind in [NSEvent.EventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
                if let event = NSEvent.mouseEvent(with: kind, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: kind == .leftMouseUp ? 0 : 1) {
                    window.sendEvent(event)
                }
                await NewThreadMotionFrames.pump(0.06)
            }
        }
    }
}
