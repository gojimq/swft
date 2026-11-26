import SwiftUI

extension SwftMotion {
    /// Gentle rise used by staggered arrivals: a touch slower than `spring`, with no overshoot.
    public static let arrival = Animation.spring(response: 0.5, dampingFraction: 0.9)
    /// Gap between consecutive elements of a staggered arrival.
    public static let arrivalStagger: Double = 0.045
    /// Content stepping aside for something else (Home's greeting leaving as a thread launches).
    public static let departure = Animation.easeOut(duration: 0.22)
    /// A docked element travelling from where it was to where it lives (the composer settling to the bottom).
    public static let dock = Animation.spring(response: 0.5, dampingFraction: 0.88)
    /// Text replacing text in place (a generated thread title arriving).
    public static let titleSwap = Animation.easeInOut(duration: 0.34)
    /// Simple blur-fade swap for live thinking and activity updates replacing earlier text in place.
    public static let blurSwapIn = Animation.easeInOut(duration: 0.26)
    public static let blurSwapOut = Animation.easeOut(duration: 0.14)
    public static let blurSwapDelay: Double = 0.05
    public static let blurSwapRadius: CGFloat = 3.5
    /// A soft background glow blooming in.
    public static let bloom = Animation.easeOut(duration: 0.8)
}

/// Pure motion helpers for `swftBlurSwap`, kept separate for unit testing.
public enum SwftBlurSwapLogic {
    /// Blur radius applied during swap transitions (always 0 under Reduce Motion).
    public static func activeBlurRadius(_ radius: CGFloat, reduceMotion: Bool) -> CGFloat {
        reduceMotion ? 0 : max(0, radius)
    }

    /// Delay before incoming text starts fading in over the outgoing text (always 0 under Reduce Motion).
    public static func insertionDelay(reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : SwftMotion.blurSwapDelay
    }
}

/// Where a staged element goes when it departs.
public enum SwftDepartureDirection: Sendable {
    case up
    case down
    /// Fades in place.
    case none
}

extension EnvironmentValues {
    /// True while a screen is being handed off from a screen that already showed its content in place (Home's docked
    /// composer becoming the new thread's composer). `swftEntrance` then shows the incoming screen at once instead of
    /// fading it in, so the hand-off is seamless. Ignored under Reduce Motion, where the screen crossfades as usual.
    @Entry public var swftScreenHandoff = false
}

extension AnyTransition {
    /// A row landing at the top of a list: the rows below make room first, then it fades down into the gap, so the
    /// new row never draws over the one it is displacing. Crossfade only under Reduce Motion.
    public static func swftListInsert(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: -8)).combined(with: .scale(scale: 0.98, anchor: .top))
                .animation(SwftMotion.arrival.delay(0.1)),
            removal: .opacity.animation(SwftMotion.quick)
        )
    }
}

extension View {
    /// One-shot staggered arrival: fades in while rising from a few points below, `order` steps after its siblings.
    /// While `departing` is true it fades out toward `departure`, and comes back if `departing` returns to false.
    /// Under Reduce Motion it only crossfades.
    public func swftArrival(
        order: Int,
        distance: CGFloat = 10,
        blur: CGFloat = 2,
        departing: Bool = false,
        departure: SwftDepartureDirection = .none
    ) -> some View {
        modifier(SwftArrival(order: order, distance: distance, blur: blur, departing: departing, departure: departure))
    }

    /// Crossfades text in place when `value` changes (the old one fades out with a soft blur while the new one fades
    /// in). When `identity` changes the swap is instant: that is a different thing, not this thing renamed.
    public func swftTitleSwap<Value: Hashable, Identity: Hashable>(_ value: Value, identity: Identity) -> some View {
        modifier(SwftTitleSwap(value: value)).id(identity)
    }

    /// Crossfades text in place when `value` changes.
    public func swftTitleSwap<Value: Hashable>(_ value: Value) -> some View {
        modifier(SwftTitleSwap(value: value))
    }

    /// Blur-fades new content cleanly over previous content whenever `value` changes.
    /// Under Reduce Motion it falls back to a crisp opacity crossfade with zero blur.
    public func swftBlurSwap<Value: Hashable>(
        _ value: Value,
        alignment: Alignment = .topLeading,
        blurRadius: CGFloat = SwftMotion.blurSwapRadius
    ) -> some View {
        modifier(SwftBlurSwap(value: value, alignment: alignment, blurRadius: blurRadius))
    }

    /// One-shot bloom for a soft background glow: it swells in from slightly smaller on appear, and fades away while
    /// `fading` is true.
    public func swftBloom(fading: Bool = false) -> some View {
        modifier(SwftBloom(fading: fading))
    }
}

private struct SwftArrival: ViewModifier {
    let order: Int
    let distance: CGFloat
    let blur: CGFloat
    let departing: Bool
    let departure: SwftDepartureDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    func body(content: Content) -> some View {
        let visible = arrived && !departing
        content
            .opacity(visible ? 1 : 0)
            .blur(radius: visible || reduceMotion ? 0 : blur)
            .offset(y: reduceMotion ? 0 : offset)
            .allowsHitTesting(!departing)
            .animation(SwftMotion.resolve(departing ? SwftMotion.departure : SwftMotion.arrival, reduceMotion: reduceMotion), value: departing)
            .onAppear {
                guard !arrived else { return }
                let delay = reduceMotion ? 0 : Double(order) * SwftMotion.arrivalStagger
                withAnimation(SwftMotion.resolve(SwftMotion.arrival, reduceMotion: reduceMotion).delay(delay)) { arrived = true }
            }
    }

    private var offset: CGFloat {
        if !arrived { return distance }
        guard departing else { return 0 }
        switch departure {
        case .up: return -distance
        case .down: return distance
        case .none: return 0
        }
    }
}

private struct SwftTitleSwap<Value: Hashable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // The old text clears quickly and the new one follows a beat later, so two titles never read as one jumble.
        let fade: AnyTransition = reduceMotion ? .opacity : .opacity.combined(with: .modifier(active: SoftBlur(radius: 3), identity: SoftBlur(radius: 0)))
        ZStack(alignment: .leading) {
            content
                .id(value)
                .transition(.asymmetric(
                    insertion: fade.animation(SwftMotion.resolve(SwftMotion.titleSwap, reduceMotion: reduceMotion).delay(reduceMotion ? 0 : 0.1)),
                    removal: fade.animation(.easeOut(duration: 0.14))
                ))
        }
        .animation(SwftMotion.resolve(SwftMotion.titleSwap, reduceMotion: reduceMotion), value: value)
    }
}

private struct SoftBlur: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

private struct SwftBlurSwap<Value: Hashable>: ViewModifier {
    let value: Value
    let alignment: Alignment
    let blurRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let radius = SwftBlurSwapLogic.activeBlurRadius(blurRadius, reduceMotion: reduceMotion)
        let transition: AnyTransition = radius > 0
            ? .opacity.combined(with: .modifier(active: SoftBlur(radius: radius), identity: SoftBlur(radius: 0)))
            : .opacity
        let inAnimation = SwftMotion.resolve(SwftMotion.blurSwapIn, reduceMotion: reduceMotion)
            .delay(SwftBlurSwapLogic.insertionDelay(reduceMotion: reduceMotion))
        let outAnimation = SwftMotion.resolve(SwftMotion.blurSwapOut, reduceMotion: reduceMotion)

        ZStack(alignment: alignment) {
            content
                .id(value)
                .transition(.asymmetric(
                    insertion: transition.animation(inAnimation),
                    removal: transition.animation(outAnimation)
                ))
        }
        .animation(SwftMotion.resolve(SwftMotion.blurSwapIn, reduceMotion: reduceMotion), value: value)
    }
}

private struct SwftBloom: ViewModifier {
    let fading: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bloomed = false

    func body(content: Content) -> some View {
        let shown = bloomed && !fading
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(reduceMotion || bloomed ? 1 : 0.92)
            .animation(SwftMotion.resolve(fading ? SwftMotion.departure : SwftMotion.bloom, reduceMotion: reduceMotion), value: fading)
            .onAppear {
                guard !bloomed else { return }
                withAnimation(SwftMotion.resolve(SwftMotion.bloom, reduceMotion: reduceMotion)) { bloomed = true }
            }
    }
}
