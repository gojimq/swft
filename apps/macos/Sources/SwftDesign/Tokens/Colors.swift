import AppKit
import SwiftUI

extension Color {
    /// A color that resolves per appearance (Aqua / Dark Aqua).
    static func swft(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// Semantic color tokens. Light values were sampled from the visual reference; dark values follow the same roles.
public enum SwftColor {
    // Surfaces
    public static let canvas = Color.swft(light: 0xFCFCFC, dark: 0x131314)
    public static let sidebar = Color.swft(light: 0xEFEFEF, dark: 0x1B1C1D)
    public static let surface = Color.swft(light: 0xFFFFFF, dark: 0x1E1F20)
    public static let surfaceRaised = Color.swft(light: 0xFFFFFF, dark: 0x252628)
    public static let surfaceMuted = Color.swft(light: 0xF3F4F5, dark: 0x232425)
    public static let codeBackground = Color.swft(light: 0xF6F7F8, dark: 0x1A1B1C)
    public static let userBubble = Color.swft(light: 0xE9EEF6, dark: 0x2A2C2F)

    // Interaction fills
    public static let hover = Color.swft(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.045, darkAlpha: 0.06)
    public static let selection = Color.swft(light: 0xD9D9DA, dark: 0x33363A)
    public static let pressed = Color.swft(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.09, darkAlpha: 0.1)

    // Text
    public static let textPrimary = Color.swft(light: 0x1F1F1F, dark: 0xE3E3E3)
    public static let textSecondary = Color.swft(light: 0x474747, dark: 0xC4C7C5)
    public static let textTertiary = Color.swft(light: 0x747775, dark: 0x8E918F)
    public static let placeholder = Color.swft(light: 0x8E918F, dark: 0x80868B)

    // Lines
    public static let border = Color.swft(light: 0xE1E3E1, dark: 0x3C4043)
    public static let borderSubtle = Color.swft(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.06, darkAlpha: 0.07)

    // Accent (blue)
    public static let accent = Color.swft(light: 0x0B57D0, dark: 0xA8C7FA)
    public static let accentSoft = Color.swft(light: 0xD3E3FD, dark: 0x1F3760)
    public static let sendFill = Color.swft(light: 0xB3DBFF, dark: 0x2B4A7A)
    public static let sendFillIdle = Color.swft(light: 0xE6F1FC, dark: 0x22314A)
    public static let onSend = Color.swft(light: 0x0842A0, dark: 0xD3E3FD)
    public static let glow = Color.swft(light: 0xD6EBFC, dark: 0x1A3A6E, darkAlpha: 0.38)
    public static let glowSecondary = Color.swft(light: 0xE8F1FB, dark: 0x22285A, darkAlpha: 0.35)

    // Status
    public static let success = Color.swft(light: 0x146C2E, dark: 0x6DD58C)
    public static let warning = Color.swft(light: 0xB25E00, dark: 0xFFB869)
    public static let warningSoft = Color.swft(light: 0xFEF6E8, dark: 0x262119)
    public static let warningBorder = Color.swft(light: 0xF3DDB5, dark: 0x4A3A22)
    public static let danger = Color.swft(light: 0xB3261E, dark: 0xF2B8B5)
    public static let dangerSoft = Color.swft(light: 0xFCE8E6, dark: 0x3C1F1E)

    public static let shadow = Color.swft(light: 0x1F2A44, dark: 0x000000, lightAlpha: 0.08, darkAlpha: 0.45)

    /// Project chip tints, indexed by a stable per-project number.
    public static func chip(_ index: Int) -> (fill: Color, ink: Color) {
        let palette: [(UInt32, UInt32, UInt32, UInt32)] = [
            (0xE8DEF8, 0x5B3E96, 0x3A2E55, 0xD6C6F5), // violet
            (0xD3E3FD, 0x0B57D0, 0x1F3760, 0xA8C7FA), // blue
            (0xC4EED0, 0x146C2E, 0x1F3A28, 0x8FDBA4), // green
            (0xFFDFC2, 0x8A4A00, 0x45301A, 0xFFC48A), // amber
            (0xFFD8E4, 0x9C2457, 0x46222F, 0xFFB0CB), // rose
            (0xC2E7EF, 0x00616E, 0x16363C, 0x8ED3DF), // teal
        ]
        let p = palette[((index % palette.count) + palette.count) % palette.count]
        return (Color.swft(light: p.0, dark: p.2), Color.swft(light: p.1, dark: p.3))
    }
}
