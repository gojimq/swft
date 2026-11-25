import AppKit
import Foundation
import SwftDesign
import SwiftUI
import Testing
@testable import Swft
@testable import SwftKit

@Suite("Disclosure reveal")
struct SwftDisclosureTests {
    @Test func revealedHeightInterpolatesAndClampsSpringOvershoot() {
        #expect(SwftDisclosureMath.revealedHeight(natural: 200, fraction: 0) == 0)
        #expect(SwftDisclosureMath.revealedHeight(natural: 200, fraction: 0.25) == 50)
        #expect(SwftDisclosureMath.revealedHeight(natural: 200, fraction: 1) == 200)
        #expect(SwftDisclosureMath.revealedHeight(natural: 200, fraction: 1.04) == 200)
        #expect(SwftDisclosureMath.revealedHeight(natural: 200, fraction: -0.03) == 0)
        #expect(SwftDisclosureMath.revealedHeight(natural: -5, fraction: 1) == 0)
    }

    @Test func opacityRampsOnlyNearClosedThenStaysCrisp() {
        #expect(SwftDisclosureMath.contentOpacity(0, reduceMotion: false) == 0)
        let mid = SwftDisclosureMath.contentOpacity(0.09, reduceMotion: false)
        #expect(abs(mid - 0.5) < 0.0001)
        #expect(SwftDisclosureMath.contentOpacity(SwftDisclosureMath.fadeRamp, reduceMotion: false) == 1)
        #expect(SwftDisclosureMath.contentOpacity(0.5, reduceMotion: false) == 1)
        #expect(SwftDisclosureMath.contentOpacity(1.1, reduceMotion: false) == 1)
    }

    @Test func reduceMotionCrossfadesAtFullHeight() {
        #expect(SwftDisclosureMath.heightFraction(0, reduceMotion: true) == 0)
        #expect(SwftDisclosureMath.heightFraction(0.3, reduceMotion: true) == 1)
        #expect(SwftDisclosureMath.revealedHeight(natural: 120, fraction: 0.3, reduceMotion: true) == 120)
        #expect(abs(SwftDisclosureMath.contentOpacity(0.3, reduceMotion: true) - 0.3) < 0.0001)
    }

    @Test func mountsWhileExpandedOrStillCollapsing() {
        #expect(SwftDisclosureMath.shouldMount(isExpanded: true, fraction: 0))
        #expect(SwftDisclosureMath.shouldMount(isExpanded: false, fraction: 0.4))
        #expect(!SwftDisclosureMath.shouldMount(isExpanded: false, fraction: 0))
    }

    @Test func scrollFadeOnlyOnEdgesHidingContent() {
        #expect(ScrollOverflowEdges.from(offsetY: 0, contentHeight: 180, containerHeight: 180) == .none)
        #expect(ScrollOverflowEdges.from(offsetY: 0, contentHeight: 180.5, containerHeight: 180) == .none)
        #expect(ScrollOverflowEdges.from(offsetY: 0, contentHeight: 400, containerHeight: 240)
            == ScrollOverflowEdges(above: false, below: true))
        #expect(ScrollOverflowEdges.from(offsetY: 80, contentHeight: 400, containerHeight: 240)
            == ScrollOverflowEdges(above: true, below: true))
        #expect(ScrollOverflowEdges.from(offsetY: 160, contentHeight: 400, containerHeight: 240)
            == ScrollOverflowEdges(above: true, below: false))
    }

    @Test func settledShelfHeightCapsAndEstimatesBeforeMeasuring() {
        #expect(SettledShelfLayout.shelfHeight(listHeight: 0, rowCount: 2) == 2 * SettledShelfLayout.estimatedRowHeight + 4)
        #expect(SettledShelfLayout.shelfHeight(listHeight: 152, rowCount: 2) == 152)
        #expect(SettledShelfLayout.shelfHeight(listHeight: 900, rowCount: 16) == SettledShelfLayout.maxHeight)
        #expect(SettledShelfLayout.shelfHeight(listHeight: 0, rowCount: 20) == SettledShelfLayout.maxHeight)
    }

    @Test func pinnedRowOnlyWhenCollapsedOnASelectedSettledThread() {
        let settled = [Self.thread("a"), Self.thread("b")]
        #expect(SettledShelfLayout.pinnedThread(settled: settled, isExpanded: false, selectedThreadID: "b")?.id == "b")
        #expect(SettledShelfLayout.pinnedThread(settled: settled, isExpanded: true, selectedThreadID: "b") == nil)
        #expect(SettledShelfLayout.pinnedThread(settled: settled, isExpanded: false, selectedThreadID: "zz") == nil)
        #expect(SettledShelfLayout.pinnedThread(settled: settled, isExpanded: false, selectedThreadID: nil) == nil)
    }

    @Test @MainActor func overlayScrollbarsModifierSetsEnclosingScrollViewToOverlay() {
        struct ProbeView: View {
            var tall: Bool
            var onMeasure: (CGFloat) -> Void

            var body: some View {
                ScrollView {
                    VStack {
                        Color.clear
                            .frame(maxWidth: 400)
                            .frame(height: tall ? 1200 : 100)
                            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: { onMeasure($0) }
                    }
                    .frame(maxWidth: .infinity)
                    .swftOverlayScrollbars()
                }
                .scrollIndicators(.automatic)
                .frame(width: 600, height: 400)
            }
        }

        var measuredX: [CGFloat] = []
        let hosting = NSHostingView(rootView: ProbeView(tall: false) { measuredX.append($0) })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        func findScrollViews(in view: NSView) -> [NSScrollView] {
            var result: [NSScrollView] = []
            if let sv = view as? NSScrollView { result.append(sv) }
            for sub in view.subviews { result.append(contentsOf: findScrollViews(in: sub)) }
            return result
        }

        let scrollViews = findScrollViews(in: hosting)
        #expect(!scrollViews.isEmpty)
        for sv in scrollViews {
            #expect(sv.scrollerStyle == .overlay)
        }

        let shortX = measuredX.last
        hosting.rootView = ProbeView(tall: true) { measuredX.append($0) }
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        for sv in findScrollViews(in: hosting) {
            #expect(sv.scrollerStyle == .overlay)
        }
        let tallX = measuredX.last
        #expect(shortX != nil)
        #expect(shortX == tallX)
    }

    @Test @MainActor func settledScrollViewInsideDisclosureStartsAtTopWithoutLegacyGutter() {
        struct SettledProbe: View {
            var onOffset: (CGFloat) -> Void

            var body: some View {
                SwftDisclosure(isExpanded: true) {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(0..<6, id: \.self) { idx in
                                Text("Row \(idx)")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .frame(height: 72)
                            }
                        }
                        .swftOverlayScrollbars()
                    }
                    .defaultScrollAnchor(.top)
                    .scrollIndicators(.automatic)
                    .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, next in
                        onOffset(next)
                    }
                    .frame(height: 240)
                }
                .frame(width: 264)
            }
        }

        var latestOffset: CGFloat = -1
        let hosting = NSHostingView(rootView: SettledProbe { latestOffset = $0 })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))

        func findScrollViews(in view: NSView) -> [NSScrollView] {
            var result: [NSScrollView] = []
            if let sv = view as? NSScrollView { result.append(sv) }
            for sub in view.subviews { result.append(contentsOf: findScrollViews(in: sub)) }
            return result
        }

        let scrollViews = findScrollViews(in: hosting)
        #expect(!scrollViews.isEmpty)
        for sv in scrollViews {
            #expect(sv.scrollerStyle == .overlay)
        }
        #expect(abs(latestOffset) <= 1)
    }

    private static func thread(_ id: String) -> ThreadSummary {
        ThreadSummary(
            id: id,
            title: "Thread \(id)",
            project: MockData.swft,
            location: .branch("main"),
            provider: .claude,
            activity: .idle,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            isSettled: true,
            settledAt: nil
        )
    }
}
