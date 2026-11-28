import AppKit
import SwiftUI

/// Layout metrics for the native Right Sidebar panel.
public enum RightPanelMetrics {
    public static let minWidth: CGFloat = 340
    public static let defaultWidth: CGFloat = 480
    public static let maxWidth: CGFloat = 960
    public static let minChatColumnWidth: CGFloat = 360
    /// Matches the chat column's `TopBar` so both headers share one baseline across the window.
    public static let tabBarHeight: CGFloat = SwftLayout.titlebarHeight
    /// Breathing room above the active Dia folder tab so its top aligns with `TopBar`'s pills.
    public static let tabTopInset: CGFloat = 8
    /// Active curved folder tab height, flush to the bottom of `tabBarHeight` (`8 + 44 = 52`).
    public static let tabHeight: CGFloat = tabBarHeight - tabTopInset
    /// Generous top corner radius on the active folder tab.
    public static let tabCornerRadius: CGFloat = 10
    /// Concave inverted-fillet flare radius where the active tab fuses into the canvas below.
    public static let tabShoulderRadius: CGFloat = 10
    /// Minimum horizontal body width of a tab before shoulders flare outward.
    public static let tabMinWidth: CGFloat = 86
    public static let subHeaderHeight: CGFloat = 38
    /// Invisible grab area straddling the 1pt split edge; it takes no layout width.
    public static let resizeHandleHitWidth: CGFloat = 8
    public static let tabMaxTitleWidth: CGFloat = 132
    public static let launcherWidth: CGFloat = 372
}

/// Panel-specific colors that have no general-purpose `SwftColor` equivalent.
public enum RightPanelColor {
    /// GitHub-style "merged" violet, tuned per appearance for legible ink on its soft fill.
    public static let merged = Color.swft(light: 0x8250DF, dark: 0xC9A7FF)
    public static let successSoft = Color.swft(light: 0xE6F4EA, dark: 0x1C2B21)
    /// Hardware bezel around a streamed device screen.
    public static let deviceBezel = Color.swft(light: 0x1C1D1F, dark: 0x050505)
    /// Softly recessed well behind the Dia-style tab strip, distinct from `SwftColor.canvas` in both modes.
    public static let tabStripBackground = Color.swft(light: 0xEFEFEF, dark: 0x1F2022)
    /// Opaque hairline tracing the active tab silhouette and tab-strip bottom divider without alpha doubling at the join.
    public static let tabBorder = Color.swft(light: 0xDBDDDF, dark: 0x333539)
    /// Subtle vertical hairline between adjacent inactive tabs in the recessed well.
    public static let tabDivider = Color.swft(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.10, darkAlpha: 0.11)
}

/// One-shot springs tuned for right-panel tabs and split/fullscreen transitions.
public enum RightPanelMotion {
    /// Tab insertion and removal in the Dia strip.
    public static let tabLifecycle = Animation.spring(response: 0.30, dampingFraction: 0.85)
    /// Active tab switching and curved silhouette lift.
    public static let tabSwitch = Animation.spring(response: 0.24, dampingFraction: 0.90)
    /// Right sidebar open/close and split ↔ fullscreen expand/restore.
    public static let panelLayout = SwftMotion.screen
}

extension AnyTransition {
    /// Tactile Dia-like entrance and exit for a tab rising out of or settling back into the tab well.
    public static func diaTabTransition(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.92, anchor: .bottomLeading))
                .combined(with: .offset(y: 6)),
            removal: .opacity
                .combined(with: .scale(scale: 0.90, anchor: .bottomLeading))
                .combined(with: .offset(y: 4))
        )
    }
}

/// Single-pass layout keeping the horizontal tab strip flush to the leading edge while the trailing `+`
/// accessory hugs the last tab (and pins beside the strip once tabs overflow), avoiding two-pass jump frames.
public struct DiaTabBarAccessoryLayout: Layout {
    public var spacing: CGFloat
    public var emptyLeadingInset: CGFloat

    public init(spacing: CGFloat = 2, emptyLeadingInset: CGFloat = 4) {
        self.spacing = spacing
        self.emptyLeadingInset = emptyLeadingInset
    }

    public func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let height = proposal.height ?? RightPanelMetrics.tabBarHeight
        if let proposedWidth = proposal.width {
            return CGSize(width: max(0, proposedWidth), height: height)
        }
        let intrinsic = subviews.reduce(CGFloat(0)) { $0 + $1.sizeThatFits(.unspecified).width }
        return CGSize(width: intrinsic + spacing, height: height)
    }

    public func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard subviews.count >= 2 else {
            for subview in subviews {
                subview.place(
                    at: CGPoint(x: bounds.minX, y: bounds.maxY),
                    anchor: .bottomLeading,
                    proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
                )
            }
            return
        }

        let scrollSubview = subviews[0]
        let accessorySubview = subviews[1]

        let accessorySize = accessorySubview.sizeThatFits(.unspecified)
        let idealScrollWidth = max(0, scrollSubview.sizeThatFits(.unspecified).width)
        let hasTabs = idealScrollWidth > 0.5
        let gap = hasTabs ? spacing : emptyLeadingInset
        let maxScrollWidth = max(0, bounds.width - accessorySize.width - gap)
        let resolvedScrollWidth = hasTabs ? min(idealScrollWidth, maxScrollWidth) : 0

        scrollSubview.place(
            at: CGPoint(x: bounds.minX, y: bounds.maxY),
            anchor: .bottomLeading,
            proposal: ProposedViewSize(width: resolvedScrollWidth, height: bounds.height)
        )

        let accessoryX = bounds.minX + resolvedScrollWidth + gap
        accessorySubview.place(
            at: CGPoint(x: accessoryX, y: bounds.maxY),
            anchor: .bottomLeading,
            proposal: ProposedViewSize(accessorySize)
        )
    }
}

/// Pure resolved geometry for Dia-style curved folder tabs (convex top corners + concave bottom inverted fillets).
public struct DiaTabGeometry: Equatable, Sendable {
    /// Exact cubic Bezier control-point factor for a quarter-circle arc: `4 * (sqrt(2) - 1) / 3`.
    public static let quarterCircleKappa: CGFloat = 0.5522847498307936

    public let rect: CGRect
    public let strokeInset: CGFloat
    public let topY: CGFloat
    public let baseY: CGFloat
    public let bodyLeft: CGFloat
    public let bodyRight: CGFloat
    public let topCornerRadius: CGFloat
    public let shoulderRadius: CGFloat

    public var isEmpty: Bool {
        rect.width <= 0 || rect.height <= 0
    }

    public static func resolve(
        in rect: CGRect,
        topCornerRadius: CGFloat = RightPanelMetrics.tabCornerRadius,
        shoulderRadius: CGFloat = RightPanelMetrics.tabShoulderRadius,
        strokeInset: CGFloat = 0.5
    ) -> DiaTabGeometry {
        let inset = max(0, min(strokeInset, rect.width * 0.5, rect.height * 0.5))
        let topY = rect.minY + inset
        let baseY = rect.maxY - inset
        let leftEdge = rect.minX + inset
        let rightEdge = rect.maxX - inset
        let availW = max(0, rightEdge - leftEdge)
        let availH = max(0, baseY - topY)

        let s = max(0, min(shoulderRadius, availW * 0.25, availH * 0.5))
        let bodyLeft = leftEdge + s
        let bodyRight = rightEdge - s
        let bodyWidth = max(0, bodyRight - bodyLeft)
        let r = max(0, min(topCornerRadius, bodyWidth * 0.5, availH - s))

        return DiaTabGeometry(
            rect: rect,
            strokeInset: inset,
            topY: topY,
            baseY: baseY,
            bodyLeft: bodyLeft,
            bodyRight: bodyRight,
            topCornerRadius: r,
            shoulderRadius: s
        )
    }

    /// Traces the open top-and-shoulders contour from `(rect.minX, baseY)` to `(rect.maxX, baseY)`.
    public func traceOutline(into path: inout Path) {
        guard !isEmpty else { return }
        let k = Self.quarterCircleKappa
        let s = shoulderRadius
        let r = topCornerRadius

        path.move(to: CGPoint(x: rect.minX, y: baseY))
        if bodyLeft - s > rect.minX {
            path.addLine(to: CGPoint(x: bodyLeft - s, y: baseY))
        }

        // Bottom-left concave inverted fillet curving smoothly from horizontal right to vertical up.
        if s > 0 {
            path.addCurve(
                to: CGPoint(x: bodyLeft, y: baseY - s),
                control1: CGPoint(x: bodyLeft - (1 - k) * s, y: baseY),
                control2: CGPoint(x: bodyLeft, y: baseY - (1 - k) * s)
            )
        }

        // Left vertical edge.
        path.addLine(to: CGPoint(x: bodyLeft, y: topY + r))

        // Top-left convex corner.
        if r > 0 {
            path.addCurve(
                to: CGPoint(x: bodyLeft + r, y: topY),
                control1: CGPoint(x: bodyLeft, y: topY + (1 - k) * r),
                control2: CGPoint(x: bodyLeft + (1 - k) * r, y: topY)
            )
        }

        // Top horizontal edge.
        path.addLine(to: CGPoint(x: bodyRight - r, y: topY))

        // Top-right convex corner.
        if r > 0 {
            path.addCurve(
                to: CGPoint(x: bodyRight, y: topY + r),
                control1: CGPoint(x: bodyRight - (1 - k) * r, y: topY),
                control2: CGPoint(x: bodyRight, y: topY + (1 - k) * r)
            )
        }

        // Right vertical edge.
        path.addLine(to: CGPoint(x: bodyRight, y: baseY - s))

        // Bottom-right concave inverted fillet curving smoothly from vertical down to horizontal right.
        if s > 0 {
            path.addCurve(
                to: CGPoint(x: bodyRight + s, y: baseY),
                control1: CGPoint(x: bodyRight, y: baseY - (1 - k) * s),
                control2: CGPoint(x: bodyRight + (1 - k) * s, y: baseY)
            )
        }

        if rect.maxX > bodyRight + s {
            path.addLine(to: CGPoint(x: rect.maxX, y: baseY))
        }
    }
}

/// Closed Dia folder-tab fill shape. Extends flush to `rect.maxY + bottomExtension` so it cleanly covers
/// the tab bar's 1pt bottom hairline beneath the active tab and fuses into `SwftColor.canvas`.
public struct DiaTabShape: Shape, Sendable {
    public var topCornerRadius: CGFloat
    public var shoulderRadius: CGFloat
    public var strokeInset: CGFloat
    public var bottomExtension: CGFloat

    public init(
        topCornerRadius: CGFloat = RightPanelMetrics.tabCornerRadius,
        shoulderRadius: CGFloat = RightPanelMetrics.tabShoulderRadius,
        strokeInset: CGFloat = 0.5,
        bottomExtension: CGFloat = 0
    ) {
        self.topCornerRadius = topCornerRadius
        self.shoulderRadius = shoulderRadius
        self.strokeInset = strokeInset
        self.bottomExtension = bottomExtension
    }

    public func path(in rect: CGRect) -> Path {
        let geometry = DiaTabGeometry.resolve(
            in: rect,
            topCornerRadius: topCornerRadius,
            shoulderRadius: shoulderRadius,
            strokeInset: strokeInset
        )
        var path = Path()
        guard !geometry.isEmpty else { return path }
        geometry.traceOutline(into: &path)
        let bottomY = rect.maxY + max(0, bottomExtension)
        path.addLine(to: CGPoint(x: rect.maxX, y: bottomY))
        path.addLine(to: CGPoint(x: rect.minX, y: bottomY))
        path.closeSubpath()
        return path
    }
}

/// Open-bottom hairline contour tracing the active Dia tab's concave shoulders, sides, and rounded top corners,
/// meeting the tab bar's bottom 1pt divider tangentially with zero gap or overlap bump.
public struct DiaTabOutlineShape: Shape, Sendable {
    public var topCornerRadius: CGFloat
    public var shoulderRadius: CGFloat
    public var strokeInset: CGFloat

    public init(
        topCornerRadius: CGFloat = RightPanelMetrics.tabCornerRadius,
        shoulderRadius: CGFloat = RightPanelMetrics.tabShoulderRadius,
        strokeInset: CGFloat = 0.5
    ) {
        self.topCornerRadius = topCornerRadius
        self.shoulderRadius = shoulderRadius
        self.strokeInset = strokeInset
    }

    public func path(in rect: CGRect) -> Path {
        let geometry = DiaTabGeometry.resolve(
            in: rect,
            topCornerRadius: topCornerRadius,
            shoulderRadius: shoulderRadius,
            strokeInset: strokeInset
        )
        var path = Path()
        geometry.traceOutline(into: &path)
        return path
    }
}

/// Pure rules for tab-strip divider visibility between adjacent inactive tabs.
public enum DiaTabStripLayout {
    /// Shows a vertical hairline after `index` only when both this tab and the next tab are inactive and unhovered.
    public static func showsTrailingDivider(
        at index: Int,
        tabIDs: [String],
        activeTabID: String?,
        hoveredTabID: String?
    ) -> Bool {
        guard index >= 0, index + 1 < tabIDs.count else { return false }
        let current = tabIDs[index]
        let next = tabIDs[index + 1]
        return current != activeTabID
            && next != activeTabID
            && current != hoveredTabID
            && next != hoveredTabID
    }
}

/// Pure width allocation for the main chat column and right panel across closed, split, and maximized states.
/// Keeps `chatContainerWidth + panelWidth == availableContentWidth` and preserves `chatContentWidth` across
/// split ↔ maximized transitions so the mounted chat view collapses cleanly without markdown reflow thrash.
public struct RightPanelSplitLayout: Equatable, Sendable {
    public let chatContainerWidth: CGFloat
    public let chatContentWidth: CGFloat
    public let panelWidth: CGFloat

    public init(chatContainerWidth: CGFloat, chatContentWidth: CGFloat, panelWidth: CGFloat) {
        self.chatContainerWidth = chatContainerWidth
        self.chatContentWidth = chatContentWidth
        self.panelWidth = panelWidth
    }

    public static func compute(
        availableContentWidth: CGFloat,
        isPanelOpen: Bool,
        isPanelMaximized: Bool,
        clampedPanelWidth: CGFloat
    ) -> RightPanelSplitLayout {
        let total = max(0, availableContentWidth)
        guard isPanelOpen else {
            return RightPanelSplitLayout(
                chatContainerWidth: total,
                chatContentWidth: total,
                panelWidth: 0
            )
        }

        let effectiveSplitPanelWidth = min(total, max(0, clampedPanelWidth))
        let splitChatWidth = max(0, total - effectiveSplitPanelWidth)

        if isPanelMaximized {
            let preservedChatWidth = max(
                splitChatWidth,
                min(total, RightPanelMetrics.minChatColumnWidth)
            )
            return RightPanelSplitLayout(
                chatContainerWidth: 0,
                chatContentWidth: preservedChatWidth,
                panelWidth: total
            )
        }

        return RightPanelSplitLayout(
            chatContainerWidth: splitChatWidth,
            chatContentWidth: splitChatWidth,
            panelWidth: effectiveSplitPanelWidth
        )
    }
}

/// Crisp keyboard shortcut badge matching T3 Code's `<Kbd>` pill inside the surface launcher.
public struct RightPanelKeyCap: View {
    let label: String

    public init(_ label: String) {
        self.label = label
    }

    public var body: some View {
        Text(label)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(SwftColor.textSecondary)
            .frame(minWidth: 20, minHeight: 20)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(SwftColor.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(SwftColor.border, lineWidth: 1)
            )
            // A hairline "key travel" lip, so the cap reads as a key rather than a tag.
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(SwftColor.border)
                    .frame(height: 1.5)
                    .padding(.horizontal, 1.5)
                    .offset(y: 0.5)
                    .mask(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .accessibilityHidden(true)
    }
}

/// One row inside the "Open a surface" launcher.
public struct RightPanelSurfaceLauncherRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let shortcut: String
    let isAvailable: Bool
    let disabledReason: String?
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        icon: String,
        title: String,
        subtitle: String,
        shortcut: String,
        isAvailable: Bool = true,
        disabledReason: String? = nil,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.shortcut = shortcut
        self.isAvailable = isAvailable
        self.disabledReason = disabledReason
        self.action = action
    }

    public var body: some View {
        Button {
            guard isAvailable else { return }
            action()
        } label: {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isAvailable ? SwftColor.textPrimary : SwftColor.textTertiary)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(hovering && isAvailable ? SwftColor.surface : SwftColor.surfaceMuted)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(SwftColor.borderSubtle, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(SwftType.labelStrong)
                        .foregroundStyle(isAvailable ? SwftColor.textPrimary : SwftColor.textTertiary)
                        .lineLimit(1)
                    Text(isAvailable ? subtitle : (disabledReason ?? subtitle))
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                RightPanelKeyCap(shortcut)
                    .opacity(isAvailable ? 1 : 0.5)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous)
                    .fill(hovering && isAvailable ? SwftColor.hover : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(isAvailable ? 1 : 0.85)
        .disabled(!isAvailable)
        .onHover { hovering = $0 }
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: hovering)
        .help(isAvailable ? "\(title) (\(shortcut))" : (disabledReason ?? title))
        .accessibilityHint(isAvailable ? subtitle : (disabledReason ?? ""))
    }
}

/// Dia-style curved folder tab for the right sidebar tab bar, with hover-revealed close button and middle-click close.
public struct RightPanelTabButton: View {
    let icon: String
    let title: String
    let isActive: Bool
    let statusDotColor: Color?
    let showTrailingDivider: Bool
    let onHoverChanged: ((Bool) -> Void)?
    let onActivate: () -> Void
    let onClose: () -> Void

    @State private var hovering = false
    @State private var closeHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        icon: String,
        title: String,
        isActive: Bool,
        statusDotColor: Color? = nil,
        showTrailingDivider: Bool = false,
        onHoverChanged: ((Bool) -> Void)? = nil,
        onActivate: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.isActive = isActive
        self.statusDotColor = statusDotColor
        self.showTrailingDivider = showTrailingDivider
        self.onHoverChanged = onHoverChanged
        self.onActivate = onActivate
        self.onClose = onClose
    }

    public var body: some View {
        let hoverPillShape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let shoulder = RightPanelMetrics.tabShoulderRadius
        let corner = RightPanelMetrics.tabCornerRadius

        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11.5, weight: isActive ? .medium : .regular))
                .foregroundStyle(isActive ? SwftColor.textPrimary : (hovering ? SwftColor.textSecondary : SwftColor.textTertiary))
                .frame(width: 15, height: 15)
                .overlay(alignment: .topTrailing) {
                    if let statusDotColor {
                        Circle()
                            .fill(statusDotColor)
                            .frame(width: 6, height: 6)
                            .overlay(
                                Circle().strokeBorder(
                                    isActive ? SwftColor.canvas : RightPanelColor.tabStripBackground,
                                    lineWidth: 1
                                )
                            )
                            .offset(x: 3, y: -2)
                    }
                }

            Text(title)
                .font(isActive ? SwftType.captionStrong : SwftType.caption)
                .foregroundStyle(isActive ? SwftColor.textPrimary : (hovering ? SwftColor.textPrimary : SwftColor.textSecondary))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: RightPanelMetrics.tabMaxTitleWidth, alignment: .leading)
                .mask {
                    if !isActive && hovering {
                        HStack(spacing: 0) {
                            Color.black
                            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 18)
                        }
                    } else {
                        Color.black
                    }
                }

            if isActive {
                closeButton
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, isActive ? 8 : 12)
        // Lift optical center into the upper tab body (`y = 27pt`) so icons & labels align cleanly with `+`, `⤢`, `×`, and traffic lights.
        .padding(.bottom, 6)
        .frame(minWidth: RightPanelMetrics.tabMinWidth)
        .frame(height: RightPanelMetrics.tabHeight)
        .background {
            ZStack {
                // Recessed hover pill sits neatly inside the upper label band, well clear of a neighbor's bottom flare.
                hoverPillShape
                    .fill(SwftColor.hover)
                    .padding(.horizontal, 3)
                    .padding(.top, 4)
                    .padding(.bottom, 10)
                    .opacity(!isActive && hovering ? 1 : 0)

                // Active Dia folder-tab silhouette: concave shoulders extend outward without shifting sibling tabs.
                ZStack {
                    DiaTabShape(topCornerRadius: corner, shoulderRadius: shoulder)
                        .fill(SwftColor.canvas)
                    DiaTabOutlineShape(topCornerRadius: corner, shoulderRadius: shoulder)
                        .stroke(
                            RightPanelColor.tabBorder,
                            style: StrokeStyle(lineWidth: 1, lineCap: .butt, lineJoin: .round)
                        )
                }
                .padding(.horizontal, -shoulder)
                .opacity(isActive ? 1 : 0)
                .scaleEffect(y: isActive || reduceMotion ? 1 : 0.92, anchor: .bottom)
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(RightPanelColor.tabDivider)
                .frame(width: 1, height: 15)
                .padding(.bottom, 6)
                .opacity(showTrailingDivider ? 1 : 0)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
        .overlay(alignment: .trailing) {
            if !isActive {
                closeButton
                    .padding(.trailing, 7)
                    .padding(.bottom, 6)
                    .opacity(hovering ? 1 : 0)
                    .allowsHitTesting(hovering)
            }
        }
        .overlay {
            MiddleClickCatcher(onMiddleClick: onClose)
        }
        .onHover { isHovering in
            hovering = isHovering
            onHoverChanged?(isHovering)
        }
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: hovering)
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: showTrailingDivider)
        .animation(SwftMotion.resolve(RightPanelMotion.tabSwitch, reduceMotion: reduceMotion), value: isActive)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(title)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(closeHovering ? SwftColor.textPrimary : SwftColor.textTertiary)
                .frame(width: 17, height: 17)
                .background(Circle().fill(closeHovering ? SwftColor.pressed : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { closeHovering = $0 }
        .help("Close tab")
        .accessibilityLabel("Close \(title)")
    }
}

/// Captures middle-mouse clicks on a tab without blocking normal left clicks or context menus.
private struct MiddleClickCatcher: NSViewRepresentable {
    let onMiddleClick: () -> Void

    func makeNSView(context: Context) -> MiddleClickView {
        let view = MiddleClickView()
        view.onMiddleClick = onMiddleClick
        return view
    }

    func updateNSView(_ nsView: MiddleClickView, context: Context) {
        nsView.onMiddleClick = onMiddleClick
    }

    final class MiddleClickView: NSView {
        var onMiddleClick: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard NSApp.currentEvent?.type == .otherMouseDown else {
                return nil
            }
            return super.hitTest(point)
        }

        override func otherMouseDown(with event: NSEvent) {
            if event.buttonNumber == 2 {
                onMiddleClick?()
            } else {
                super.otherMouseDown(with: event)
            }
        }
    }
}

/// Invisible grab strip over the panel's leading hairline. Reports the drag's total horizontal travel
/// (positive = wider panel) so the caller can size from the width captured at drag start; clamping then never
/// lets the edge drift away from the cursor.
public struct RightPanelResizeHandle: View {
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: () -> Void

    @State private var hovering = false
    @State private var dragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.swftUIScale) private var uiScale

    public init(
        onDragChanged: @escaping (CGFloat) -> Void,
        onDragEnded: @escaping () -> Void = {}
    ) {
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
    }

    public var body: some View {
        Color.clear
            .frame(width: RightPanelMetrics.resizeHandleHitWidth)
            .frame(maxHeight: .infinity)
            .overlay {
                Rectangle()
                    .fill(dragging ? SwftColor.accent : SwftColor.border)
                    .frame(width: 2)
                    .opacity(dragging || hovering ? 1 : 0)
            }
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .onHover { hovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        dragging = true
                        // Dragging left (negative x) widens the right sidebar; convert global pts back to scaled layout space.
                        onDragChanged(-value.translation.width / SwftUIScale.clamp(uiScale))
                    }
                    .onEnded { _ in
                        dragging = false
                        onDragEnded()
                    }
            )
            .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: hovering)
            .accessibilityLabel("Resize right panel")
    }
}

/// Compact pill status badge for PRs, issues, devices, and checks.
public struct RightPanelStatusBadge: View {
    public enum Tone: Sendable, Hashable {
        case neutral
        case accent
        case success
        case warning
        case danger
        case merged
    }

    let text: String
    let icon: String?
    let tone: Tone

    public init(_ text: String, icon: String? = nil, tone: Tone = .neutral) {
        self.text = text
        self.icon = icon
        self.tone = tone
    }

    public var body: some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 8.5, weight: .bold))
            }
            Text(text)
                .font(SwftType.micro)
                .lineLimit(1)
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 6)
        .frame(height: 17)
        .background(Capsule().fill(backgroundColor))
        .fixedSize()
    }

    private var foregroundColor: Color {
        switch tone {
        case .neutral: SwftColor.textSecondary
        case .accent: SwftColor.accent
        case .success: SwftColor.success
        case .warning: SwftColor.warning
        case .danger: SwftColor.danger
        case .merged: RightPanelColor.merged
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .neutral: SwftColor.surfaceMuted
        case .accent: SwftColor.accentSoft.opacity(0.7)
        case .success: RightPanelColor.successSoft
        case .warning: SwftColor.warningSoft
        case .danger: SwftColor.dangerSoft
        case .merged: RightPanelColor.merged.opacity(0.14)
        }
    }
}

/// Small uppercase section label with an optional count, shared by every surface's lists.
public struct RightPanelSectionHeader: View {
    let title: String
    let count: Int?

    public init(_ title: String, count: Int? = nil) {
        self.title = title
        self.count = count
    }

    public var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(SwftType.micro)
                .tracking(0.4)
                .foregroundStyle(SwftColor.textTertiary)
            if let count {
                Text(String(count))
                    .font(SwftType.micro)
                    .monospacedDigit()
                    .foregroundStyle(SwftColor.textTertiary)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 16, minHeight: 15)
                    .background(Capsule().fill(SwftColor.surfaceMuted))
            }
        }
        .padding(.leading, 2)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Bordered card used for list rows (PRs, issues, threads, devices, sessions); hover lifts the border.
private struct RightPanelCardModifier: ViewModifier {
    let interactive: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous)
        content
            .background(shape.fill(SwftColor.surface))
            .overlay(shape.strokeBorder(hovering && interactive ? SwftColor.border : SwftColor.borderSubtle, lineWidth: 1))
            .contentShape(shape)
            .onHover { if interactive { hovering = $0 } }
            .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: hovering)
    }
}

extension View {
    /// Wraps a list row in the panel's surface card.
    public func rightPanelCard(interactive: Bool = true) -> some View {
        modifier(RightPanelCardModifier(interactive: interactive))
    }

    /// Standard surface sub-header strip under the tab bar.
    public func rightPanelSubHeader() -> some View {
        padding(.horizontal, 10)
            .frame(height: RightPanelMetrics.subHeaderHeight)
            .frame(maxWidth: .infinity)
            .background(SwftColor.canvas)
    }
}

/// Borderless "•••" overflow menu trigger with a circular hover fill and no disclosure chevron.
public struct RightPanelOverflowMenu<Items: View>: View {
    let help: String
    let items: Items

    public init(help: String = "More actions", @ViewBuilder items: () -> Items) {
        self.help = help
        self.items = items()
    }

    public var body: some View {
        Menu {
            items
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SwftColor.textTertiary)
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(HoverFillStyle(shape: Circle(), pressScale: 0.9))
        .menuIndicator(.hidden)
        .fixedSize()
        // AppKit-backed menus report a loose max width; pin it so neighbors keep the row's free space.
        .frame(width: 24, height: 24)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Calm centered empty/unavailable state shared across right-panel surfaces.
public struct RightPanelEmptyState<Actions: View>: View {
    let icon: String
    let title: String
    let message: String
    let actions: Actions

    public init(
        icon: String,
        title: String,
        message: String,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actions = actions()
    }

    public var body: some View {
        VStack(spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(SwftColor.textSecondary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(SwftColor.surfaceMuted))
                .overlay(Circle().strokeBorder(SwftColor.borderSubtle, lineWidth: 1))
                .padding(.bottom, 14)

            Text(title)
                .font(SwftType.labelStrong)
                .foregroundStyle(SwftColor.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 4)

            Text(message)
                .font(SwftType.caption)
                .foregroundStyle(SwftColor.textTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 270)

            actions
                .padding(.top, 14)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Compact capsule action ("Open", "Copy", "Link PR") sized for 38pt sub-headers and list cards.
public struct RightPanelPillButton: View {
    let title: String
    let systemName: String?
    let prominent: Bool
    let tint: Color?
    let action: () -> Void

    public init(_ title: String, systemName: String? = nil, prominent: Bool = false, tint: Color? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemName = systemName
        self.prominent = prominent
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(title)
                    .font(SwftType.captionStrong)
                    .lineLimit(1)
            }
            .foregroundStyle(tint ?? (prominent ? SwftColor.onSend : SwftColor.textSecondary))
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(prominent ? SwftColor.sendFill : SwftColor.surfaceMuted))
            .overlay(Capsule().strokeBorder(SwftColor.borderSubtle, lineWidth: prominent ? 0 : 1))
            .contentShape(Capsule())
        }
        .buttonStyle(HoverFillStyle(shape: Capsule()))
        .fixedSize()
    }
}
