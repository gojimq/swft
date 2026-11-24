import AppKit
import SwiftUI

/// Visual tokens and Liquid Glass surface styling for the Gemini-matched composer.
public enum ComposerPolish {
    // Shape & dimensions measured from the Gemini macOS composer (744×95pt at 1x).
    public static let cornerRadius: CGFloat = 24
    public static let minHeight: CGFloat = 95
    public static let verticalSpacing: CGFloat = 13
    public static let contentLeadingPadding: CGFloat = 10
    public static let contentTrailingPadding: CGFloat = 12
    public static let contentTopPadding: CGFloat = 15
    public static let contentBottomPadding: CGFloat = 12
    public static let textHorizontalInset: CGFloat = 8
    public static let textTopInset: CGFloat = 2
    public static let controlsSpacing: CGFloat = 8
    public static let controlButtonSize: CGFloat = 28
    public static let sendButtonSize: CGFloat = 28

    // Typography: slightly larger composer text with a lighter placeholder weight.
    public static let inputFontSize: CGFloat = 18.5
    public static let inputFont: Font = SwftFonts.flex(inputFontSize, weight: 400)
    public static let placeholderFont: Font = SwftFonts.flex(inputFontSize, weight: 340)

    // Colors
    public static let placeholderColor: Color = dynamic(light: 0x8A8E93, dark: 0x8E939A, lightAlpha: 0.88, darkAlpha: 0.84)
    /// Gentle frosted neutral wash layered inside Liquid Glass so the composer reads as a translucent
    /// light-grey slab over both the home blue glow and the white thread canvas (and charcoal glass in dark mode).
    public static let frostFill: Color = dynamic(light: 0xF1F2F4, dark: 0x222428, lightAlpha: 0.46, darkAlpha: 0.26)
    /// Tint passed to macOS 26 `Glass.clear.tint(_:)`: pure translucent white in light mode keeps the
    /// Liquid Glass specular rim bright with no dark outline; cool charcoal tint grounds dark mode.
    public static let glassTint: Color = dynamic(light: 0xFFFFFF, dark: 0x3D4047, lightAlpha: 0.28, darkAlpha: 0.26)
    /// macOS 15 material fallback tint and soft luminous edge (no hard dark outline).
    public static let fallbackTint: Color = dynamic(light: 0xF2F3F5, dark: 0x222428, lightAlpha: 0.62, darkAlpha: 0.58)
    public static let fallbackHighlight: Color = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.78, darkAlpha: 0.11)

    // Send button: light-blue filled circle (Gemini #9DD2FF in light mode, matched soft blue in dark mode).
    public static let sendFillReady: Color = dynamic(light: 0x94CEFF, dark: 0x457EC7)
    public static let sendFillIdle: Color = dynamic(light: 0xA8D6FF, dark: 0x335D94)
    public static let sendIconReady: Color = dynamic(light: 0x051E3E, dark: 0xF0F6FF)
    public static let sendIconIdle: Color = dynamic(light: 0x051E3E, dark: 0xDCEBFF, lightAlpha: 0.76, darkAlpha: 0.82)

    public static func sendFill(for state: SendButton.State) -> Color {
        state == .idle ? sendFillIdle : sendFillReady
    }

    public static func sendIconColor(for state: SendButton.State) -> Color {
        state == .idle ? sendIconIdle : sendIconReady
    }

    /// Appearance-resolved tint for `Glass.clear.tint(_:)` so macOS 26 receives a literal `Color.white`
    /// in light mode (preserving the luminous rim without darkening the bezel).
    public static func resolvedGlassTint(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(white: 0.24, opacity: 0.26)
            : Color.white.opacity(0.28)
    }

    static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: isDark ? darkAlpha : lightAlpha
            )
        })
    }
}

private struct ComposerGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            GlassEffectContainer {
                content
                    .background(shape.fill(ComposerPolish.frostFill))
                    .glassEffect(.clear.tint(ComposerPolish.resolvedGlassTint(for: colorScheme)), in: shape)
            }
        } else {
            content
                .background(.thinMaterial, in: shape)
                .background(shape.fill(ComposerPolish.fallbackTint))
                .overlay(shape.strokeBorder(ComposerPolish.fallbackHighlight, lineWidth: 1))
        }
    }
}

extension View {
    /// Frosted translucent Liquid Glass slab on macOS 26+ (no hard border or drop shadow), with a soft
    /// translucent material fallback on macOS 15.
    @MainActor
    public func swftComposerGlass<S: InsettableShape>(in shape: S) -> some View {
        modifier(ComposerGlassModifier(shape: shape))
    }
}
