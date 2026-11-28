import SwiftUI

/// Swft's mark: two forward-leaning streaks. Original; deliberately unlike any vendor logo.
public struct SwftMark: View {
    var size: CGFloat
    public init(size: CGFloat = 22) { self.size = size }

    public var body: some View {
        ZStack {
            Streak().fill(LinearGradient(colors: [Color(nsColor: .init(hex: 0x4F8BFF)), Color(nsColor: .init(hex: 0x1A5CE0))], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size * 0.5, height: size)
                .offset(x: size * 0.12)
            Streak().fill(LinearGradient(colors: [Color(nsColor: .init(hex: 0x8FD3FF)), Color(nsColor: .init(hex: 0x4F8BFF))], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.5, height: size * 0.62)
                .offset(x: -size * 0.2, y: size * 0.19)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// A rounded parallelogram leaning right.
    struct Streak: Shape {
        func path(in r: CGRect) -> Path {
            let lean = r.width * 0.55
            var p = Path()
            p.move(to: CGPoint(x: r.minX + lean, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - lean, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
            return p.strokedPath(.init(lineWidth: r.width * 0.12, lineJoin: .round)).union(p)
        }
    }
}

/// A 28pt round icon button with a quiet hover fill.
public struct IconButton: View {
    let systemName: String
    let help: String
    var size: CGFloat
    var weight: Font.Weight
    var tint: Color
    let action: () -> Void

    public init(_ systemName: String, help: String, size: CGFloat = 28, weight: Font.Weight = .regular, tint: Color = SwftColor.textSecondary, action: @escaping () -> Void = {}) {
        self.systemName = systemName
        self.help = help
        self.size = size
        self.weight = weight
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        // macOS runs a Button's action inside the click's own update, which keeps the button from animating a move its
        // action causes (opening a panel slid the icon out of its pill). Acting a beat later lets it move with the rest.
        Button { Task { action() } } label: {
            Image(systemName: systemName)
                .font(.system(size: size * 0.52, weight: weight))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(HoverFillStyle(shape: Circle(), pressScale: 0.9))
        .foregroundStyle(tint)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Plain button style that paints a hover/pressed fill in the given shape. Hover and press animate with a spring;
/// the selected fill glides between rows when a `swftSelectionNamespace` is in the environment.
public struct HoverFillStyle<S: Shape>: ButtonStyle {
    let shape: S
    var selected: Bool
    var pressScale: CGFloat
    public init(shape: S, selected: Bool = false, pressScale: CGFloat = 0.97) {
        self.shape = shape
        self.selected = selected
        self.pressScale = pressScale
    }

    public func makeBody(configuration: Configuration) -> some View {
        HoverFillBody(configuration: configuration, shape: shape, selected: selected, pressScale: pressScale)
    }

    struct HoverFillBody: View {
        let configuration: Configuration
        let shape: S
        let selected: Bool
        let pressScale: CGFloat
        @State private var hovering = false
        @Environment(\.swftSelectionNamespace) private var selectionNamespace
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .background {
                    ZStack {
                        shape.fill(hoverFill)
                        if selected {
                            if let selectionNamespace {
                                shape.fill(SwftColor.selection)
                                    .matchedGeometryEffect(id: SwftSelection.pillID, in: selectionNamespace)
                            } else {
                                shape.fill(SwftColor.selection)
                            }
                        }
                    }
                }
                .scaleEffect(SwftMotion.pressScale(isPressed: configuration.isPressed, scale: pressScale, reduceMotion: reduceMotion))
                .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: hovering)
                .animation(SwftMotion.pressAnimation(isPressed: configuration.isPressed, reduceMotion: reduceMotion), value: configuration.isPressed)
                .onHover { hovering = $0 }
        }

        var hoverFill: Color {
            if selected { return .clear }
            if configuration.isPressed { return SwftColor.pressed }
            return hovering ? SwftColor.hover : .clear
        }
    }
}

/// Shared identity for the sidebar's single selection pill.
public enum SwftSelection {
    public static let pillID = "swft.selection.pill"
}

extension EnvironmentValues {
    /// When set, selected `HoverFillStyle` fills share one matched geometry so the selection pill glides between rows.
    @Entry public var swftSelectionNamespace: Namespace.ID?
}

/// Small rounded-square project badge with initials (the "ST" chip in the inbox).
public struct ProjectChip: View {
    let initials: String
    let tint: Int
    var size: CGFloat
    var dashed: Bool

    public init(initials: String, tint: Int, size: CGFloat = 16, dashed: Bool = false) {
        self.initials = initials
        self.tint = tint
        self.size = size
        self.dashed = dashed
    }

    public var body: some View {
        let colors = SwftColor.chip(tint)
        Group {
            if dashed {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(SwftColor.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            } else {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(colors.fill)
                    .overlay {
                        Text(initials)
                            .font(SwftFonts.flex(size * 0.5, weight: 700))
                            .foregroundStyle(colors.ink)
                    }
            }
        }
        .frame(width: size, height: size)
    }
}

/// A provider identity glyph resolving to the real provider mark, with a neutral fallback.
public struct ProviderGlyph: View {
    let provider: String?
    let acpAgentID: String?
    let iconURL: String?
    let symbol: String
    let tint: Color
    let name: String
    let size: CGFloat

    public init(symbol: String, tint: Color, name: String) {
        self.provider = nil
        self.acpAgentID = nil
        self.iconURL = nil
        self.symbol = symbol
        self.tint = tint
        self.name = name
        self.size = 13.5
    }

    public init(
        provider: String?,
        acpAgentID: String? = nil,
        iconURL: String? = nil,
        symbol: String = "circle.dashed",
        tint: Color = SwftColor.textSecondary,
        name: String,
        size: CGFloat = 13.5
    ) {
        self.provider = provider
        self.acpAgentID = acpAgentID
        self.iconURL = iconURL
        self.symbol = symbol
        self.tint = tint
        self.name = name
        self.size = size
    }

    public var body: some View {
        let resolved = ProviderIconKind.resolve(
            driver: provider,
            acpAgentID: acpAgentID,
            iconURL: iconURL,
            name: name,
            legacySymbol: symbol
        )
        ProviderIcon(resolved: resolved, size: size)
            .foregroundStyle(resolved == .mark(.generic) ? SwftColor.textTertiary : SwftColor.textSecondary)
            .frame(width: max(16, size), height: max(16, size))
            .help(name)
            .accessibilityLabel(name)
    }
}

/// Capsule container for top-right window toolbar controls.
public struct ToolbarPill<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        HStack(spacing: 2) { content }
            .padding(.horizontal, 4)
            .frame(height: 36)
            .background(Capsule().fill(SwftColor.surface))
            .overlay(Capsule().strokeBorder(SwftColor.borderSubtle))
            .shadow(color: SwftColor.shadow, radius: 6, y: 1)
    }
}

/// Text button for use inside a ToolbarPill.
public struct PillTextButton: View {
    let title: String
    let systemName: String?
    let action: () -> Void

    public init(_ title: String, systemName: String? = nil, action: @escaping () -> Void = {}) {
        self.title = title
        self.systemName = systemName
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemName {
                    Image(systemName: systemName).font(.system(size: 12, weight: .medium))
                }
                Text(title).font(SwftType.label)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .contentShape(Capsule())
        }
        .buttonStyle(HoverFillStyle(shape: Capsule()))
        .foregroundStyle(SwftColor.textPrimary)
    }
}

/// Soft radial blue glow painted behind the empty state. Static: no animation.
public struct GlowBackground: View {
    public init() {}
    public var body: some View {
        GeometryReader { geo in
            let side = max(geo.size.width, geo.size.height)
            ZStack {
                RadialGradient(colors: [SwftColor.glow, SwftColor.glow.opacity(0)], center: .center, startRadius: 0, endRadius: side * 0.34)
                    .scaleEffect(x: 1.25, y: 0.9)
                    .offset(y: geo.size.height * 0.08)
                RadialGradient(colors: [SwftColor.glowSecondary, SwftColor.glowSecondary.opacity(0)], center: .center, startRadius: 0, endRadius: side * 0.5)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .drawingGroup()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
