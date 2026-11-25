import SwiftUI

/// Pure math behind `SwftDisclosure`, kept separate so the reveal curve is unit-testable.
public enum SwftDisclosureMath {
    /// Fraction of travel over which content fades from 0 to full opacity; past it content stays crisp.
    public static let fadeRamp: CGFloat = 0.18

    public static func clamped(_ fraction: CGFloat) -> CGFloat {
        min(max(fraction, 0), 1)
    }

    /// Share of the natural height shown. Reduce Motion skips the roll: full height while any content is shown.
    public static func heightFraction(_ fraction: CGFloat, reduceMotion: Bool) -> CGFloat {
        if reduceMotion { return fraction > 0.0001 ? 1 : 0 }
        return clamped(fraction)
    }

    public static func revealedHeight(natural: CGFloat, fraction: CGFloat, reduceMotion: Bool = false) -> CGFloat {
        max(0, natural) * heightFraction(fraction, reduceMotion: reduceMotion)
    }

    /// Softens only the leading sliver of travel; Reduce Motion crossfades across the whole animation instead.
    public static func contentOpacity(_ fraction: CGFloat, reduceMotion: Bool) -> Double {
        let value = clamped(fraction)
        if reduceMotion { return Double(value) }
        return Double(min(1, value / fadeRamp))
    }

    /// Content stays mounted while expanded or while a collapse is still rolling up.
    public static func shouldMount(isExpanded: Bool, fraction: CGFloat) -> Bool {
        isExpanded || fraction > 0
    }
}

/// Height-reveal disclosure: the clip edge unrolls over content laid out at its full natural height,
/// so text never re-wraps mid-animation and parents resize frame by frame with it.
/// Content mounts on open and unmounts once a collapse finishes.
public struct SwftDisclosure<Content: View>: View {
    private let isExpanded: Bool
    private let animation: Animation
    private let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fraction: CGFloat
    @State private var isMounted: Bool

    public init(
        isExpanded: Bool,
        animation: Animation = SwftMotion.disclosure,
        @ViewBuilder content: () -> Content
    ) {
        self.isExpanded = isExpanded
        self.animation = animation
        self.content = content()
        _fraction = State(initialValue: isExpanded ? 1 : 0)
        _isMounted = State(initialValue: isExpanded)
    }

    public var body: some View {
        // The layout stays in the tree while content mounts inside it, so the very first open animates 0 → 1.
        VerticalRevealLayout(fraction: fraction, reduceMotion: reduceMotion) {
            if isMounted {
                VStack(alignment: .leading, spacing: 0) { content }
                    .transition(.identity)
            }
        }
        .modifier(RevealOpacity(fraction: fraction, reduceMotion: reduceMotion))
        .clipped()
        .allowsHitTesting(isExpanded)
        .accessibilityHidden(!isExpanded)
        .onChange(of: isExpanded) { _, expanded in
            if expanded { isMounted = true }
            withAnimation(SwftMotion.resolve(animation, reduceMotion: reduceMotion)) {
                fraction = expanded ? 1 : 0
            } completion: {
                // `isExpanded` and `fraction` hold the latest target, so a reopen mid-collapse keeps content mounted.
                if !SwftDisclosureMath.shouldMount(isExpanded: isExpanded, fraction: fraction) {
                    isMounted = false
                }
            }
        }
    }
}

private struct VerticalRevealLayout: Layout {
    var fraction: CGFloat
    let reduceMotion: Bool

    var animatableData: CGFloat {
        get { fraction }
        set { fraction = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return CGSize(width: proposal.width ?? 0, height: 0) }
        let natural = child.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(
            width: proposal.width ?? natural.width,
            height: SwftDisclosureMath.revealedHeight(natural: natural.height, fraction: fraction, reduceMotion: reduceMotion)
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        let natural = child.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        child.place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: natural.height)
        )
    }
}

private struct RevealOpacity: ViewModifier, Animatable {
    var fraction: CGFloat
    let reduceMotion: Bool

    nonisolated var animatableData: CGFloat {
        get { fraction }
        set { fraction = newValue }
    }

    func body(content: Content) -> some View {
        content.opacity(SwftDisclosureMath.contentOpacity(fraction, reduceMotion: reduceMotion))
    }
}
