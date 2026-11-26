import AppKit
import CoreGraphics
import SwftDesign
import SwiftUI
import Testing
@testable import Swft

@Suite("Dia Tabs Geometry, Divider Rules & Split Layout")
struct DiaTabsLayoutTests {

    // MARK: - DiaTabGeometry & Shapes

    @Test func resolvesStandardDiaTabGeometryWithCrispHalfPointStrokeAlignment() {
        let rect = CGRect(x: 0, y: 0, width: 140, height: RightPanelMetrics.tabHeight)
        let geometry = DiaTabGeometry.resolve(in: rect)

        #expect(!geometry.isEmpty)
        #expect(geometry.topY == 0.5)
        #expect(geometry.baseY == RightPanelMetrics.tabHeight - 0.5)
        #expect(geometry.shoulderRadius == RightPanelMetrics.tabShoulderRadius)
        #expect(geometry.topCornerRadius == RightPanelMetrics.tabCornerRadius)
        #expect(geometry.bodyLeft == 0.5 + RightPanelMetrics.tabShoulderRadius)
        #expect(geometry.bodyRight == 140 - 0.5 - RightPanelMetrics.tabShoulderRadius)
        #expect(geometry.bodyLeft < geometry.bodyRight)
    }

    @Test func clampsDiaTabRadiiSafelyForNarrowShortAndEmptyRects() {
        let narrow = DiaTabGeometry.resolve(in: CGRect(x: 0, y: 0, width: 20, height: 44))
        #expect(narrow.shoulderRadius <= 5)
        #expect(narrow.bodyLeft <= narrow.bodyRight)
        #expect(narrow.topCornerRadius <= (narrow.bodyRight - narrow.bodyLeft) * 0.5 + 0.001)

        let short = DiaTabGeometry.resolve(in: CGRect(x: 0, y: 0, width: 120, height: 12))
        #expect(short.shoulderRadius <= 6)
        #expect(short.topCornerRadius + short.shoulderRadius <= short.baseY - short.topY + 0.001)

        let zero = DiaTabGeometry.resolve(in: .zero)
        #expect(zero.isEmpty)
        #expect(DiaTabShape().path(in: .zero).isEmpty)
        #expect(DiaTabOutlineShape().path(in: .zero).isEmpty)
    }

    @Test func producesSymmetricFillAndOpenOutlinePathsMeetingTheBottomHairline() {
        let rect = CGRect(x: 0, y: 0, width: 150, height: 44)
        let fillPath = DiaTabShape().path(in: rect)
        let outlinePath = DiaTabOutlineShape().path(in: rect)

        #expect(!fillPath.isEmpty)
        #expect(!outlinePath.isEmpty)

        // Fill covers from topY (0.5) flush to rect.maxY (44.0) across the full flared width.
        let fillBounds = fillPath.boundingRect
        #expect(abs(fillBounds.minX - 0) < 0.01)
        #expect(abs(fillBounds.maxX - 150) < 0.01)
        #expect(abs(fillBounds.minY - 0.5) < 0.01)
        #expect(abs(fillBounds.maxY - 44.0) < 0.01)

        // Outline stops at baseY (43.5) so its 1pt stroke spans [43.0, 44.0], matching the tab bar's bottom divider.
        let outlineBounds = outlinePath.boundingRect
        #expect(abs(outlineBounds.minX - 0) < 0.01)
        #expect(abs(outlineBounds.maxX - 150) < 0.01)
        #expect(abs(outlineBounds.minY - 0.5) < 0.01)
        #expect(abs(outlineBounds.maxY - 43.5) < 0.01)

        // Center of the tab body is inside the fill; outside upper corners above the shoulders are not.
        #expect(fillPath.contains(CGPoint(x: 75, y: 22)))
        #expect(fillPath.contains(CGPoint(x: 75, y: 43.5)))
        #expect(!fillPath.contains(CGPoint(x: 2, y: 10)))
        #expect(!fillPath.contains(CGPoint(x: 148, y: 10)))
    }

    // MARK: - DiaTabStripLayout Dividers

    @Test func hidesInactiveDividersNextToActiveAndHoveredTabs() {
        let ids = ["a", "b", "c", "d"]

        // Active tab is "b" (index 1): hides divider after "a" (0) and after "b" (1), keeps divider between "c" and "d" (2).
        #expect(!DiaTabStripLayout.showsTrailingDivider(at: 0, tabIDs: ids, activeTabID: "b", hoveredTabID: nil))
        #expect(!DiaTabStripLayout.showsTrailingDivider(at: 1, tabIDs: ids, activeTabID: "b", hoveredTabID: nil))
        #expect(DiaTabStripLayout.showsTrailingDivider(at: 2, tabIDs: ids, activeTabID: "b", hoveredTabID: nil))
        #expect(!DiaTabStripLayout.showsTrailingDivider(at: 3, tabIDs: ids, activeTabID: "b", hoveredTabID: nil))

        // Hovering "c" hides the divider between "c" and "d" as well.
        #expect(!DiaTabStripLayout.showsTrailingDivider(at: 2, tabIDs: ids, activeTabID: "b", hoveredTabID: "c"))
        // Hovering "d" also hides the divider between "c" and "d".
        #expect(!DiaTabStripLayout.showsTrailingDivider(at: 2, tabIDs: ids, activeTabID: "b", hoveredTabID: "d"))

        // Active tab is first ("a"): dividers appear between b|c and c|d.
        #expect(!DiaTabStripLayout.showsTrailingDivider(at: 0, tabIDs: ids, activeTabID: "a", hoveredTabID: nil))
        #expect(DiaTabStripLayout.showsTrailingDivider(at: 1, tabIDs: ids, activeTabID: "a", hoveredTabID: nil))
        #expect(DiaTabStripLayout.showsTrailingDivider(at: 2, tabIDs: ids, activeTabID: "a", hoveredTabID: nil))

        // Single tab and out-of-range indices never show a trailing divider.
        #expect(!DiaTabStripLayout.showsTrailingDivider(at: 0, tabIDs: ["only"], activeTabID: "only", hoveredTabID: nil))
        #expect(!DiaTabStripLayout.showsTrailingDivider(at: -1, tabIDs: ids, activeTabID: nil, hoveredTabID: nil))
        #expect(!DiaTabStripLayout.showsTrailingDivider(at: 4, tabIDs: ids, activeTabID: nil, hoveredTabID: nil))
    }

    // MARK: - RightPanelSplitLayout

    @Test func computesExactZeroGapSplitClosedAndMaximizedWidthsWhilePreservingChatContentWidth() {
        // Closed: chat occupies full content area, panel width is 0.
        let closed = RightPanelSplitLayout.compute(
            availableContentWidth: 1000,
            isPanelOpen: false,
            isPanelMaximized: false,
            clampedPanelWidth: 480
        )
        #expect(closed.chatContainerWidth == 1000)
        #expect(closed.chatContentWidth == 1000)
        #expect(closed.panelWidth == 0)

        // Split: exact partition summing to availableContentWidth.
        let split = RightPanelSplitLayout.compute(
            availableContentWidth: 1000,
            isPanelOpen: true,
            isPanelMaximized: false,
            clampedPanelWidth: 480
        )
        #expect(split.chatContainerWidth == 520)
        #expect(split.chatContentWidth == 520)
        #expect(split.panelWidth == 480)
        #expect(split.chatContainerWidth + split.panelWidth == 1000)

        // Maximized: chat container collapses to 0, panel fills 1000, while chatContentWidth stays 520 (no reflow thrash!).
        let maximized = RightPanelSplitLayout.compute(
            availableContentWidth: 1000,
            isPanelOpen: true,
            isPanelMaximized: true,
            clampedPanelWidth: 480
        )
        #expect(maximized.chatContainerWidth == 0)
        #expect(maximized.chatContentWidth == split.chatContentWidth)
        #expect(maximized.panelWidth == 1000)
        #expect(maximized.chatContainerWidth + maximized.panelWidth == 1000)

        // Narrow window or negative/zero transient geometry never produces negative widths.
        let narrow = RightPanelSplitLayout.compute(
            availableContentWidth: 300,
            isPanelOpen: true,
            isPanelMaximized: false,
            clampedPanelWidth: 480
        )
        #expect(narrow.panelWidth == 300)
        #expect(narrow.chatContainerWidth == 0)

        let zero = RightPanelSplitLayout.compute(
            availableContentWidth: -20,
            isPanelOpen: true,
            isPanelMaximized: true,
            clampedPanelWidth: 480
        )
        #expect(zero.chatContainerWidth == 0)
        #expect(zero.chatContentWidth == 0)
        #expect(zero.panelWidth == 0)
    }

    // MARK: - Single-Pass DiaTabBarAccessoryLayout

    @Test @MainActor func placesFirstTabLeadingAlignedAndHugsAddControlInSinglePass() {
        let layout = DiaTabBarAccessoryLayout(spacing: 2, emptyLeadingInset: 4)
        var measuredScrollFrame: CGRect = .zero
        var measuredAddFrame: CGRect = .zero

        func render(tabCount: Int, barWidth: CGFloat = 420) {
            let root = layout {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(0..<tabCount, id: \.self) { index in
                            Color.clear
                                .frame(width: 110, height: RightPanelMetrics.tabHeight)
                                .padding(.leading, index == 0 ? 10 : 0)
                                .padding(.trailing, index == tabCount - 1 ? 10 : 0)
                        }
                    }
                    .frame(height: RightPanelMetrics.tabBarHeight, alignment: .bottom)
                }
                .defaultScrollAnchor(.leading)
                .background(GeometryReader { g in
                    Color.clear.onAppear { measuredScrollFrame = g.frame(in: .named("bar")) }
                })

                Color.clear
                    .frame(width: 44, height: 28)
                    .background(GeometryReader { g in
                        Color.clear.onAppear { measuredAddFrame = g.frame(in: .named("bar")) }
                    })
            }
            .frame(width: barWidth, height: RightPanelMetrics.tabBarHeight)
            .coordinateSpace(name: "bar")

            let host = NSHostingView(rootView: root)
            host.frame = CGRect(x: 0, y: 0, width: barWidth, height: RightPanelMetrics.tabBarHeight)
            host.layoutSubtreeIfNeeded()
        }

        // 0 tabs: scroll strip is 0pt wide and `+` sits at the leading inset.
        render(tabCount: 0)
        #expect(measuredScrollFrame.minX == 0)
        #expect(measuredScrollFrame.width == 0)
        #expect(abs(measuredAddFrame.minX - 4) < 0.5)

        // 1 tab (110 + 10 + 10 = 130pt): sits flush at leading x = 0, NEVER centered in the 420pt bar!
        render(tabCount: 1)
        #expect(abs(measuredScrollFrame.minX) < 0.5)
        #expect(abs(measuredScrollFrame.width - 130) < 0.5)
        #expect(abs(measuredAddFrame.minX - 132) < 0.5)

        // 6 overflowing tabs: strip clamps to barWidth - addWidth - spacing (420 - 44 - 2 = 374pt) and `+` pins beside it.
        render(tabCount: 6)
        #expect(abs(measuredScrollFrame.minX) < 0.5)
        #expect(abs(measuredScrollFrame.width - 374) < 0.5)
        #expect(abs(measuredAddFrame.minX - 376) < 0.5)
    }
}
