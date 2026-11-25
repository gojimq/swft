import SwiftUI

/// Tonal color tokens and Liquid Glass styling for the sidebar usage pills and hover breakdown card.
public enum SwftUsageColor {
    // Pill base tracks sitting over the sidebar surface.
    public static let pillTrack = Color.swft(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.62, darkAlpha: 0.055)
    public static let pillTrackDepleted = Color.swft(light: 0xFCE8E6, dark: 0x3C1F1E, lightAlpha: 0.56, darkAlpha: 0.44)
    public static let pillTrackMuted = Color.swft(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.36, darkAlpha: 0.032)

    // Primary left-to-right tonal fuel wash inside the pill.
    public static let fuelFill = Color.swft(light: 0xC8DDFD, dark: 0x2B4A7A, lightAlpha: 0.85, darkAlpha: 0.68)
    public static let fuelFillHover = Color.swft(light: 0xB8D4FC, dark: 0x33588F, lightAlpha: 0.94, darkAlpha: 0.82)
    public static let fuelFillDepleted = Color.swft(light: 0xF3B6B0, dark: 0x8F302D, lightAlpha: 0.92, darkAlpha: 0.78)
    public static let fuelFillDepletedHover = Color.swft(light: 0xEDA39B, dark: 0xA63935, lightAlpha: 0.98, darkAlpha: 0.88)

    // Pace reference tick on the pill (crisp top notch + whisper-soft guide) and inside the breakdown meter.
    public static let paceTick = Color.swft(light: 0x0B57D0, dark: 0xA8C7FA, lightAlpha: 0.62, darkAlpha: 0.72)
    public static let paceTickAhead = Color.swft(light: 0xB25E00, dark: 0xFFB869, lightAlpha: 0.82, darkAlpha: 0.88)
    public static let paceTickDepleted = Color.swft(light: 0xB3261E, dark: 0xF2B8B5, lightAlpha: 0.82, darkAlpha: 0.88)
    public static let paceGuide = Color.swft(light: 0x0B57D0, dark: 0xA8C7FA, lightAlpha: 0.16, darkAlpha: 0.2)
    public static let paceGuideDepleted = Color.swft(light: 0xB3261E, dark: 0xF2B8B5, lightAlpha: 0.22, darkAlpha: 0.26)

    // Secondary 2pt bottom accent bar inside the pill.
    public static let secondaryTrack = Color.swft(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.1)
    public static let secondaryFill = Color.swft(light: 0x0B57D0, dark: 0xA8C7FA, lightAlpha: 0.62, darkAlpha: 0.72)

    // Pill borders & hover lift.
    public static let pillBorder = Color.swft(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.09)
    public static let pillBorderHover = Color.swft(light: 0x0B57D0, dark: 0xA8C7FA, lightAlpha: 0.44, darkAlpha: 0.48)
    public static let pillBorderDepleted = Color.swft(light: 0xB3261E, dark: 0xF2B8B5, lightAlpha: 0.3, darkAlpha: 0.36)
    public static let pillBorderDepletedHover = Color.swft(light: 0xB3261E, dark: 0xF2B8B5, lightAlpha: 0.56, darkAlpha: 0.62)
    public static let pillBorderDashed = Color.swft(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.22, darkAlpha: 0.22)
    public static let pillBorderDashedHover = Color.swft(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.38, darkAlpha: 0.38)

    // Multi-account compact badge inside the pill.
    public static let countBadgeFill = Color.swft(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.085, darkAlpha: 0.14)

    // Linear meter bar inside the breakdown card.
    public static let meterTrack = Color.swft(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.09, darkAlpha: 0.12)
    public static let meterFill = Color.swft(light: 0x0B57D0, dark: 0xA8C7FA, lightAlpha: 0.88, darkAlpha: 0.9)
    public static let meterTick = Color.swft(light: 0x1F1F1F, dark: 0xE3E3E3, lightAlpha: 0.58, darkAlpha: 0.66)

    // Liquid Glass popover tint (clear glass with soft frosted wash for crisp text contrast).
    public static let popoverGlassTint = Color.swft(light: 0xFFFFFF, dark: 0x1E1F21, lightAlpha: 0.72, darkAlpha: 0.68)
    public static let popoverBorder = Color.swft(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.62, darkAlpha: 0.12)
}

extension View {
    /// Floating Liquid Glass card surface matching the model picker popover on macOS 26+ (exterior-only
    /// elevation shadow, never inside a shared GlassEffectContainer), with a translucent regularMaterial
    /// fallback on macOS 15.
    @MainActor
    public func swftUsagePopoverGlass(cornerRadius: CGFloat = 18) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .clipShape(shape)
            .swftPickerGlass(in: shape)
    }
}
