import SwiftUI

/// Liquid Glass tokens for the floating model picker. It shares the composer's recipe (frosted neutral wash under
/// `Glass.clear.tint`) but with a denser wash, since a menu floats over busy transcript text and must stay legible.
/// Every fill inside the panel is a translucent overlay so nothing reads as an opaque block pasted onto glass.
public enum PickerPolish {
    public static let frostFill: Color = ComposerPolish.dynamic(light: 0xF6F7F9, dark: 0x1C1D20, lightAlpha: 0.64, darkAlpha: 0.5)
    /// macOS 15 material fallback.
    public static let fallbackTint: Color = ComposerPolish.dynamic(light: 0xF5F6F8, dark: 0x1F2023, lightAlpha: 0.78, darkAlpha: 0.72)
    public static let fallbackHighlight: Color = ComposerPolish.fallbackHighlight
    /// Soft elevation under the panel, cast only outside its shape so it never greys the glass.
    public static let elevationShadow: Color = ComposerPolish.dynamic(light: 0x1F2A44, dark: 0x000000, lightAlpha: 0.12, darkAlpha: 0.38)

    public static let divider: Color = ComposerPolish.dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.06, darkAlpha: 0.08)
    public static let hoverFill: Color = ComposerPolish.dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.045, darkAlpha: 0.07)
    public static let highlightFill: Color = ComposerPolish.dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.07, darkAlpha: 0.1)
    public static let pressedFill: Color = ComposerPolish.dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.1, darkAlpha: 0.14)
    /// Provider rail selection: a translucent accent wash instead of the opaque `accentSoft` tile.
    public static let railSelection: Color = ComposerPolish.dynamic(light: 0x0B57D0, dark: 0xA8C7FA, lightAlpha: 0.12, darkAlpha: 0.17)
    public static let switcherTrack: Color = ComposerPolish.dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.05, darkAlpha: 0.06)
    public static let switcherThumb: Color = ComposerPolish.dynamic(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.86, darkAlpha: 0.13)
    public static let sliderTrack: Color = ComposerPolish.dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.12)

    public static let rowPressScale: CGFloat = 0.985
    public static let tabPressScale: CGFloat = 0.92
    public static let segmentPressScale: CGFloat = 0.96

    /// Appearance-resolved `Glass.clear.tint(_:)`: brighter than the composer so the menu separates from it.
    public static func resolvedGlassTint(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(white: 0.2, opacity: 0.34) : Color.white.opacity(0.42)
    }
}

private struct PickerGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            // No GlassEffectContainer: the panel must never merge with the composer's glass it floats beside.
            content
                .background(shape.fill(PickerPolish.frostFill))
                .glassEffect(.clear.tint(PickerPolish.resolvedGlassTint(for: colorScheme)), in: shape)
                .background(elevation)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .background(shape.fill(PickerPolish.fallbackTint))
                .overlay(shape.strokeBorder(PickerPolish.fallbackHighlight, lineWidth: 1))
                .background(elevation)
        }
    }

    // A shadow from an opaque copy of the shape, with the interior punched out so the glass keeps sampling the
    // backdrop and text never picks up a shadow.
    private var elevation: some View {
        shape.fill(Color.black)
            .shadow(color: PickerPolish.elevationShadow, radius: 20, y: 8)
            .shadow(color: PickerPolish.elevationShadow.opacity(0.5), radius: 1.5, y: 0.5)
            .overlay(shape.fill(Color.black).blendMode(.destinationOut))
            .compositingGroup()
            .allowsHitTesting(false)
    }
}

extension View {
    /// Frosted Liquid Glass for floating picker panels (macOS 26+), material fallback on macOS 15.
    @MainActor
    public func swftPickerGlass<S: InsettableShape>(in shape: S) -> some View {
        modifier(PickerGlassModifier(shape: shape))
    }
}

/// Tactile press feedback for plain controls: a translucent pressed fill in `shape` plus a quick press-down scale
/// that springs back on release. Reduce Motion keeps the fill and drops the scale.
public struct TactilePressStyle<S: Shape>: ButtonStyle {
    let shape: S
    var pressScale: CGFloat
    var pressedFill: Color

    public init(shape: S, pressScale: CGFloat = PickerPolish.rowPressScale, pressedFill: Color = PickerPolish.pressedFill) {
        self.shape = shape
        self.pressScale = pressScale
        self.pressedFill = pressedFill
    }

    public func makeBody(configuration: Configuration) -> some View {
        TactileBody(configuration: configuration, shape: shape, pressScale: pressScale, pressedFill: pressedFill)
    }

    private struct TactileBody: View {
        let configuration: Configuration
        let shape: S
        let pressScale: CGFloat
        let pressedFill: Color
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let pressed = configuration.isPressed
            configuration.label
                .background(shape.fill(pressed ? pressedFill : .clear))
                .scaleEffect(SwftMotion.pressScale(isPressed: pressed, scale: pressScale, reduceMotion: reduceMotion))
                .animation(SwftMotion.pressAnimation(isPressed: pressed, reduceMotion: reduceMotion), value: pressed)
        }
    }
}
