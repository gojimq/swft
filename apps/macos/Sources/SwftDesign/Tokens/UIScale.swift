import CoreGraphics
import SwiftUI

/// Whole-app UI zoom scale steps and pure coordinate helpers (mirroring T3 Code desktop zoom).
public enum SwftUIScale {
    /// Discrete zoom stops; 85%–90% matches T3 Code's dense workstation feel while 100% stays the native baseline.
    public static let steps: [CGFloat] = [
        0.75, 0.80, 0.85, 0.90, 0.95,
        1.00,
        1.10, 1.20, 1.30, 1.40, 1.50,
    ]
    public static let defaultScale: CGFloat = 1.00
    public static let minScale: CGFloat = 0.75
    public static let maxScale: CGFloat = 1.50
    private static let epsilon: CGFloat = 0.001

    public static func clamp(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return defaultScale }
        return min(maxScale, max(minScale, value))
    }

    public static func isDefault(_ value: CGFloat) -> Bool {
        abs(clamp(value) - defaultScale) < epsilon
    }

    public static func canZoomIn(from current: CGFloat) -> Bool {
        clamp(current) < maxScale - epsilon
    }

    public static func canZoomOut(from current: CGFloat) -> Bool {
        clamp(current) > minScale + epsilon
    }

    public static func steppedIn(from current: CGFloat) -> CGFloat {
        let clamped = clamp(current)
        return steps.first(where: { $0 > clamped + epsilon }) ?? maxScale
    }

    public static func steppedOut(from current: CGFloat) -> CGFloat {
        let clamped = clamp(current)
        return steps.last(where: { $0 < clamped - epsilon }) ?? minScale
    }

    public static func percentLabel(for scale: CGFloat) -> String {
        "\(Int((clamp(scale) * 100).rounded()))%"
    }

    /// Logical horizontal clearance needed so unscaled macOS traffic lights never collide with chrome when zoomed out.
    public static func trafficLightHorizontalClearance(base: CGFloat, scale: CGFloat) -> CGFloat {
        let safeScale = clamp(scale)
        return max(base, base / safeScale)
    }

    /// Logical top-bar height keeping at least `minimumPhysicalHeight` real window points around the traffic lights.
    public static func trafficLightTopBarHeight(
        base: CGFloat,
        minimumPhysicalHeight: CGFloat = 44,
        scale: CGFloat
    ) -> CGFloat {
        let safeScale = clamp(scale)
        return max(base, minimumPhysicalHeight / safeScale)
    }

    /// Converts a window-space rect (`.global`) back to pre-scale logical coordinates inside the scaled root.
    public static func unscaledRect(_ rect: CGRect, scale: CGFloat) -> CGRect {
        let safeScale = clamp(scale)
        return CGRect(
            x: rect.origin.x / safeScale,
            y: rect.origin.y / safeScale,
            width: rect.size.width / safeScale,
            height: rect.size.height / safeScale
        )
    }
}

extension EnvironmentValues {
    @Entry public var swftUIScale: CGFloat = SwftUIScale.defaultScale
}
