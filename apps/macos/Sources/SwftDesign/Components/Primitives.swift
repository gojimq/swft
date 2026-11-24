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
    let action: () -> Void

    public init(_ systemName: String, help: String, size: CGFloat = 28, weight: Font.Weight = .regular, action: @escaping () -> Void = {}) {
        self.systemName = systemName
        self.help = help
        self.size = size
        self.weight = weight
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.52, weight: weight))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(HoverFillStyle(shape: Circle()))
        .foregroundStyle(SwftColor.textSecondary)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Plain button style that paints a hover/pressed fill in the given shape.
public struct HoverFillStyle<S: Shape>: ButtonStyle {
    let shape: S
    var selected: Bool
    public init(shape: S, selected: Bool = false) {
        self.shape = shape
        self.selected = selected
    }

    public func makeBody(configuration: Configuration) -> some View {
        HoverFillBody(configuration: configuration, shape: shape, selected: selected)
    }

    struct HoverFillBody: View {
        let configuration: Configuration
        let shape: S
        let selected: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background {
                    shape.fill(fill)
                }
                .onHover { hovering = $0 }
        }

        var fill: Color {
            if selected { return SwftColor.selection }
            if configuration.isPressed { return SwftColor.pressed }
            return hovering ? SwftColor.hover : .clear
        }
    }
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

/// A provider identity glyph: neutral SF Symbol in a tint, never a vendor logo.
public struct ProviderGlyph: View {
    let symbol: String
    let tint: Color
    let name: String

    public init(symbol: String, tint: Color, name: String) {
        self.symbol = symbol
        self.tint = tint
        self.name = name
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 16, height: 16)
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
