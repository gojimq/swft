import CoreGraphics
import SwiftUI

/// Shared coordinate space spanning the transcript scroll view and the floating composer bar.
public enum SendFlightCoordinateSpace {
    public static let name = "swft.thread.sendFlight"
}

private struct SendFlightBubbleFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct SendFlightComposerFrameKey: PreferenceKey {
    static let defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        if let next = nextValue() {
            value = next
        }
    }
}

extension EnvironmentValues {
    /// Set by `sendFlightBubbleTarget(id:)` so `UserBubble` reports its pill rect only when tracked.
    @Entry public var sendFlightBubbleTargetID: String? = nil
}

private struct SendFlightBubbleAnchorModifier: ViewModifier {
    @Environment(\.sendFlightBubbleTargetID) private var targetID

    func body(content: Content) -> some View {
        content.background {
            if let targetID {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: SendFlightBubbleFramesKey.self,
                        value: [targetID: geo.frame(in: .named(SendFlightCoordinateSpace.name))]
                    )
                }
            }
        }
    }
}

public extension View {
    /// Marks a view (such as the pill inside `UserBubble`) as the measurable landing surface for send flight.
    func sendFlightBubbleAnchor() -> some View {
        modifier(SendFlightBubbleAnchorModifier())
    }

    /// Associates a transcript user-bubble row with its item ID so its pill rect reports to the flight overlay. Pass
    /// an ID only for the bubble a flight is landing on: every reporting bubble re-reports on each scroll frame.
    func sendFlightBubbleTarget(id: String?) -> some View {
        environment(\.sendFlightBubbleTargetID, id)
    }

    /// Measures the composer container in the shared send-flight coordinate space without altering its layout.
    func sendFlightComposerAnchor() -> some View {
        background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: SendFlightComposerFrameKey.self,
                    value: geo.frame(in: .named(SendFlightCoordinateSpace.name))
                )
            }
        }
    }

    /// Observes measured user-bubble landing rects in the shared send-flight coordinate space.
    func onSendFlightBubbleFramesChange(_ action: @escaping ([String: CGRect]) -> Void) -> some View {
        onPreferenceChange(SendFlightBubbleFramesKey.self, perform: action)
    }

    /// Observes the composer container rect in the shared send-flight coordinate space.
    func onSendFlightComposerFrameChange(_ action: @escaping (CGRect) -> Void) -> some View {
        onPreferenceChange(SendFlightComposerFrameKey.self) { rect in
            if let rect, rect.width > 0, rect.height > 0 {
                action(rect)
            }
        }
    }
}

/// Instantaneous visual sample of a flying user bubble along its J-shaped path.
public struct SendFlightSample: Equatable, Sendable {
    public let center: CGPoint
    public let scale: CGFloat
    public let opacity: Double
    public let pillOpacity: Double
    public let easedProgress: Double

    public init(center: CGPoint, scale: CGFloat, opacity: Double, pillOpacity: Double, easedProgress: Double) {
        self.center = center
        self.scale = scale
        self.opacity = opacity
        self.pillOpacity = pillOpacity
        self.easedProgress = easedProgress
    }
}

/// Pure quadratic Bézier flight path from the left of the composer along a J-shaped curve
/// (travelling right first, then sweeping up) into the top-right user bubble landing spot.
public struct SendFlightPath: Equatable, Sendable {
    public let startCenter: CGPoint
    public let controlPoint: CGPoint
    public let endCenter: CGPoint
    public let startScale: CGFloat
    public let opacityFadeEnd: Double

    public init(
        startCenter: CGPoint,
        controlPoint: CGPoint,
        endCenter: CGPoint,
        startScale: CGFloat = 0.84,
        opacityFadeEnd: Double = 0.2
    ) {
        self.startCenter = startCenter
        self.controlPoint = controlPoint
        self.endCenter = endCenter
        self.startScale = startScale
        self.opacityFadeEnd = opacityFadeEnd
    }

    /// Builds the J-shaped trajectory in the shared thread coordinate space.
    public static func make(
        composerFrame: CGRect,
        targetFrame: CGRect,
        composerLeadingInset: CGFloat = 18
    ) -> SendFlightPath {
        let bubbleWidth = targetFrame.width
        let bubbleHeight = targetFrame.height

        let idealStartMinX = composerFrame.minX + composerLeadingInset
        let maxStartMinX = max(composerFrame.minX, composerFrame.maxX - bubbleWidth - 12)
        let startMinX = min(idealStartMinX, maxStartMinX)
        let startCenterX = startMinX + bubbleWidth / 2

        let fromTop = composerFrame.minY + SendFlightTiming.sendTopTuck
        let fromBottom = composerFrame.maxY - SendFlightTiming.sendBottomInset - bubbleHeight
        let startMinY = max(targetFrame.minY, min(fromTop, fromBottom))
        let startCenterY = startMinY + bubbleHeight / 2

        let start = CGPoint(x: startCenterX, y: startCenterY)
        let end = CGPoint(x: targetFrame.midX, y: targetFrame.midY)

        let dx = end.x - start.x
        let dy = start.y - end.y
        // Full rightward sweep produces a J hook (horizontal exit, vertical arrival); full-width messages rise straight up.
        let horizontalBlend = min(1.0, max(0.0, abs(dx) / 140.0))
        let controlX = end.x
        let controlY = start.y - dy * (0.5 - 0.36 * horizontalBlend)

        return SendFlightPath(
            startCenter: start,
            controlPoint: CGPoint(x: controlX, y: controlY),
            endCenter: end
        )
    }

    /// Evaluates the bubble's transform at linear progress `t` in `[0, 1]` using the send timing curve.
    public func sample(normalizedTime t: Double, curve: CubicBezierCurve = .send) -> SendFlightSample {
        let clamped = min(1.0, max(0.0, t))
        let s = curve.value(at: clamped)
        let inv = 1.0 - s
        let x = inv * inv * startCenter.x + 2.0 * inv * s * controlPoint.x + s * s * endCenter.x
        let y = inv * inv * startCenter.y + 2.0 * inv * s * controlPoint.y + s * s * endCenter.y
        let scale = startScale + (1.0 - startScale) * CGFloat(s)
        let opacity = opacityFadeEnd > 0 ? min(1.0, clamped / opacityFadeEnd) : 1.0
        let pillOpacity = min(1.0, 0.35 + 0.65 * min(1.0, s / 0.55))
        return SendFlightSample(
            center: CGPoint(x: x, y: y),
            scale: scale,
            opacity: opacity,
            pillOpacity: pillOpacity,
            easedProgress: s
        )
    }
}
