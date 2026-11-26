import AppKit
import SwiftUI

/// Layout metrics for the native Right Sidebar panel.
public enum RightPanelMetrics {
    public static let minWidth: CGFloat = 340
    public static let defaultWidth: CGFloat = 480
    public static let maxWidth: CGFloat = 960
    public static let minChatColumnWidth: CGFloat = 360
    public static let tabBarHeight: CGFloat = SwftLayout.titlebarHeight
    public static let subHeaderHeight: CGFloat = 36
    public static let resizeHandleHitWidth: CGFloat = 7
}

/// Crisp keyboard shortcut badge matching T3 Code's `<Kbd>` pill inside the surface launcher.
public struct RightPanelKeyCap: View {
    let label: String

    public init(_ label: String) {
        self.label = label
    }

    public var body: some View {
        Text(label)
            .font(SwftType.monoSmall)
            .fontWeight(.medium)
            .foregroundStyle(SwftColor.textTertiary)
            .frame(minWidth: 20, minHeight: 20)
            .padding(.horizontal, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(SwftColor.surfaceMuted)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(SwftColor.borderSubtle, lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

/// One row inside the "Open a surface" launcher card.
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
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(isAvailable ? SwftColor.textSecondary : SwftColor.textTertiary)
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(SwftType.labelStrong)
                        .foregroundStyle(isAvailable ? SwftColor.textPrimary : SwftColor.textTertiary)
                        .lineLimit(1)
                    Text(isAvailable ? subtitle : (disabledReason ?? subtitle))
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                RightPanelKeyCap(shortcut)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous)
                    .fill(hovering && isAvailable ? SwftColor.hover : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(isAvailable ? 1 : 0.55)
        .disabled(!isAvailable)
        .onHover { hovering = $0 }
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: hovering)
        .help(isAvailable ? "\(title) (\(shortcut))" : (disabledReason ?? title))
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
        HStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(isActive ? SwftColor.textPrimary : SwftColor.textTertiary)
                    .frame(width: 14, height: 14)

                if let statusDotColor {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 5.5, height: 5.5)
                        .offset(x: 2, y: -2)
                }
            }

            Text(title)
                .font(isActive ? SwftType.captionStrong : SwftType.caption)
                .foregroundStyle(isActive ? SwftColor.textPrimary : SwftColor.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 140, alignment: .leading)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(closeHovering ? SwftColor.textPrimary : SwftColor.textTertiary)
                    .frame(width: 16, height: 16)
                    .background(
                        Circle()
                            .fill(closeHovering ? SwftColor.pressed : .clear)
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(hovering || isActive ? 1 : 0)
            .onHover { closeHovering = $0 }
            .help("Close tab")
            .accessibilityLabel("Close \(title)")
        }
        .padding(.leading, 9)
        .padding(.trailing, 5)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous)
                .fill(isActive ? SwftColor.surface : (hovering ? SwftColor.hover : .clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous)
                .strokeBorder(isActive ? SwftColor.borderSubtle : .clear, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous))
        .onTapGesture(perform: onActivate)
        .overlay {
            MiddleClickCatcher(onMiddleClick: onClose)
        }
        .onHover { hovering = $0 }
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: hovering)
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: isActive)
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

/// Draggable left-edge resize handle for the right sidebar with native left-right resize cursor.
public struct RightPanelResizeHandle: View {
    let onDragDelta: (CGFloat) -> Void
    let onDragEnded: () -> Void

    @State private var hovering = false
    @State private var dragging = false
    @State private var lastTranslationX: CGFloat = 0

    public init(
        onDragDelta: @escaping (CGFloat) -> Void,
        onDragEnded: @escaping () -> Void = {}
    ) {
        self.onDragDelta = onDragDelta
        self.onDragEnded = onDragEnded
    }

    public var body: some View {
        ZStack {
            Rectangle()
                .fill(SwftColor.borderSubtle)
                .frame(width: 1)
            Rectangle()
                .fill(dragging ? SwftColor.accent : (hovering ? SwftColor.border : .clear))
                .frame(width: dragging || hovering ? 2 : 1)
        }
        .frame(width: RightPanelMetrics.resizeHandleHitWidth)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { isHovering in
            hovering = isHovering
            if isHovering {
                NSCursor.resizeLeftRight.push()
            } else if !dragging {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if !dragging {
                        dragging = true
                        lastTranslationX = 0
                    }
                    let step = value.translation.width - lastTranslationX
                    lastTranslationX = value.translation.width
                    // Dragging left (negative x) widens the right sidebar.
                    onDragDelta(-step)
                }
                .onEnded { _ in
                    dragging = false
                    lastTranslationX = 0
                    if !hovering {
                        NSCursor.pop()
                    }
                    onDragEnded()
                }
        )
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
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .semibold))
            }
            Text(text)
                .font(SwftType.micro)
                .lineLimit(1)
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(
            Capsule()
                .fill(backgroundColor)
        )
    }

    private var foregroundColor: Color {
        switch tone {
        case .neutral: SwftColor.textSecondary
        case .accent: SwftColor.accent
        case .success: SwftColor.success
        case .warning: SwftColor.warning
        case .danger: SwftColor.danger
        case .merged: Color(red: 0.56, green: 0.36, blue: 0.88)
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .neutral: SwftColor.surfaceMuted
        case .accent: SwftColor.accentSoft.opacity(0.65)
        case .success: SwftColor.success.opacity(0.14)
        case .warning: SwftColor.warningSoft
        case .danger: SwftColor.dangerSoft
        case .merged: Color(red: 0.56, green: 0.36, blue: 0.88).opacity(0.15)
        }
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
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(SwftColor.textTertiary)
                .padding(.bottom, 2)

            Text(title)
                .font(SwftType.labelStrong)
                .foregroundStyle(SwftColor.textPrimary)
                .multilineTextAlignment(.center)

            Text(message)
                .font(SwftType.caption)
                .foregroundStyle(SwftColor.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)

            actions
                .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
