import CoreGraphics
import Foundation
import SwiftUI

/// Timing, threshold, and inset constants ported from Studio's thread view (`threadView.shared.tsx` / `threadView.logic.ts`).
public enum SendFlightTiming {
    /// Distance from the bottom edge (pt) within which streaming keeps the viewport pinned (`STICK_PX`).
    public static let stickThreshold: CGFloat = 80
    /// Duration (s) for a settling run's rows to glide into place (`SETTLE_MS = 420`).
    public static let settleDuration: TimeInterval = 0.42
    /// Shared clock duration (s) for a sent bubble's flight and the conversation scroll (`SEND_MS = 680`).
    public static let sendDuration: TimeInterval = 0.68
    /// Composer attachment-tray handoff duration (s) (`HANDOFF_MS = 220`).
    public static let handoffDuration: TimeInterval = 0.22
    /// Delay (s) before showing the "Working" indicator after a composer send (`WORKING_DELAY_MS = 340`).
    public static let workingDelay: TimeInterval = 0.34
    /// Entrance stagger step per initial visible row (s) (`STAGGER_MS = 30`).
    public static let staggerStep: TimeInterval = 0.03
    /// Maximum initial stagger step index (`MAX_STAGGER_INDEX = 12`).
    public static let maxStaggerIndex: Int = 12
    /// Top inset (pt) tucking a rising sent bubble inside the composer's top edge (`SEND_TOP_TUCK_PX = 8`).
    public static let sendTopTuck: CGFloat = 8
    /// Bottom inset (pt) keeping tall sent bubbles inside the composer's bottom edge (`SEND_BOTTOM_INSET_PX = 6`).
    public static let sendBottomInset: CGFloat = 6
}

/// Pure cubic Bézier timing function matching CSS `cubic-bezier(x1, y1, x2, y2)`.
public struct CubicBezierCurve: Equatable, Sendable {
    public let x1: Double
    public let y1: Double
    public let x2: Double
    public let y2: Double

    /// Studio's send curve (`SEND_EASE = cubic-bezier(0.3, 0.2, 0, 1)`): eases in briefly so the screen
    /// does not lurch, then decelerates calmly into its resting anchor.
    public static let send = CubicBezierCurve(x1: 0.3, y1: 0.2, x2: 0.0, y2: 1.0)

    /// Studio's settle curve (`SETTLE_EASE = cubic-bezier(0.2, 0.8, 0.2, 1)`).
    public static let settle = CubicBezierCurve(x1: 0.2, y1: 0.8, x2: 0.2, y2: 1.0)

    public init(x1: Double, y1: Double, x2: Double, y2: Double) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
    }

    public var unitCurve: UnitCurve {
        .bezier(startControlPoint: UnitPoint(x: x1, y: y1), endControlPoint: UnitPoint(x: x2, y: y2))
    }

    public func animation(duration: TimeInterval) -> Animation {
        .timingCurve(x1, y1, x2, y2, duration: duration)
    }

    /// Evaluates the eased output `y` for a normalized linear time `t` in `[0, 1]`.
    public func value(at t: Double) -> Double {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        let u = solveParameter(forX: t)
        return sampleY(u)
    }

    private func sampleX(_ u: Double) -> Double {
        let ax = 1.0 - 3.0 * x2 + 3.0 * x1
        let bx = 3.0 * x2 - 6.0 * x1
        let cx = 3.0 * x1
        return ((ax * u + bx) * u + cx) * u
    }

    private func sampleDerivativeX(_ u: Double) -> Double {
        let ax = 1.0 - 3.0 * x2 + 3.0 * x1
        let bx = 3.0 * x2 - 6.0 * x1
        let cx = 3.0 * x1
        return (3.0 * ax * u + 2.0 * bx) * u + cx
    }

    private func sampleY(_ u: Double) -> Double {
        let ay = 1.0 - 3.0 * y2 + 3.0 * y1
        let by = 3.0 * y2 - 6.0 * y1
        let cy = 3.0 * y1
        return ((ay * u + by) * u + cy) * u
    }

    private func solveParameter(forX targetX: Double) -> Double {
        var u = targetX
        for _ in 0..<8 {
            let error = sampleX(u) - targetX
            if abs(error) < 1e-7 { return u }
            let derivative = sampleDerivativeX(u)
            if abs(derivative) < 1e-6 { break }
            let next = u - error / derivative
            if next < 0 || next > 1 { break }
            u = next
        }
        var lo = 0.0
        var hi = 1.0
        u = targetX
        for _ in 0..<24 {
            let x = sampleX(u)
            if abs(x - targetX) < 1e-7 { return u }
            if x < targetX { lo = u } else { hi = u }
            u = 0.5 * (lo + hi)
        }
        return u
    }
}

public extension SwftMotion {
    /// One-shot send flight and conversation scroll clock (`680ms`, `cubic-bezier(0.3, 0.2, 0, 1)`).
    static let send = CubicBezierCurve.send.animation(duration: SendFlightTiming.sendDuration)
    /// Settling turn layout and fold transition (`420ms`, `cubic-bezier(0.2, 0.8, 0.2, 1)`).
    static let settle = CubicBezierCurve.settle.animation(duration: SendFlightTiming.settleDuration)
    /// Composer handoff transition (`220ms`, `cubic-bezier(0.2, 0.8, 0.2, 1)`).
    static let handoff = CubicBezierCurve.settle.animation(duration: SendFlightTiming.handoffDuration)
}
