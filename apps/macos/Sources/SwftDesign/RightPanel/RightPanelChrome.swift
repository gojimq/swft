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
    public static let subHeaderHeight: CGFloat = 38
    /// Invisible grab area straddling the 1pt split edge; it takes no layout width.
    public static let resizeHandleHitWidth: CGFloat = 8
    public static let tabMaxTitleWidth: CGFloat = 128
    public static let launcherWidth: CGFloat = 372
}

/// Panel-specific colors that have no general-purpose `SwftColor` equivalent.
public enum RightPanelColor {
    /// GitHub-style "merged" violet, tuned per appearance for legible ink on its soft fill.
    public static let merged = Color.swft(light: 0x8250DF, dark: 0xC9A7FF)
    public static let successSoft = Color.swft(light: 0xE6F4EA, dark: 0x1C2B21)
    /// Hardware bezel around a streamed device screen.
    public static let deviceBezel = Color.swft(light: 0x1C1D1F, dark: 0x050505)
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

/// Clickable tab pill for the right sidebar tab bar, with hover-revealed close button and middle-click close.
public struct RightPanelTabButton: View {
    let icon: String
    let title: String
    let isActive: Bool
    let statusDotColor: Color?
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
        onActivate: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.isActive = isActive
        self.statusDotColor = statusDotColor
        self.onActivate = onActivate
        self.onClose = onClose
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isActive ? SwftColor.textPrimary : SwftColor.textTertiary)
                .frame(width: 14, height: 14)
                .overlay(alignment: .topTrailing) {
                    if let statusDotColor {
                        Circle()
                            .fill(statusDotColor)
                            .frame(width: 6, height: 6)
                            .overlay(Circle().strokeBorder(SwftColor.canvas, lineWidth: 1))
                            .offset(x: 3, y: -2)
                    }
                }

            Text(title)
                .font(isActive ? SwftType.captionStrong : SwftType.caption)
                .foregroundStyle(isActive ? SwftColor.textPrimary : SwftColor.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: RightPanelMetrics.tabMaxTitleWidth, alignment: .leading)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(closeHovering ? SwftColor.textPrimary : SwftColor.textTertiary)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(closeHovering ? SwftColor.pressed : .clear))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(hovering || isActive ? 1 : 0)
            .allowsHitTesting(hovering || isActive)
            .onHover { closeHovering = $0 }
            .help("Close tab")
            .accessibilityLabel("Close \(title)")
        }
        .padding(.leading, 10)
        .padding(.trailing, 5)
        .frame(height: 28)
        .background {
            if isActive {
                shape
                    .fill(SwftColor.surface)
                    .shadow(color: SwftColor.shadow, radius: 1.5, y: 0.5)
            } else if hovering {
                shape.fill(SwftColor.hover)
            }
        }
        .overlay(shape.strokeBorder(isActive ? SwftColor.border : .clear, lineWidth: 1))
        .contentShape(shape)
        .onTapGesture(perform: onActivate)
        .overlay {
            MiddleClickCatcher(onMiddleClick: onClose)
        }
        .onHover { hovering = $0 }
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: hovering)
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: isActive)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(title)
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
                        // Dragging left (negative x) widens the right sidebar.
                        onDragChanged(-value.translation.width)
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
