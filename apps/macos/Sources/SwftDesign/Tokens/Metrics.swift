import CoreGraphics

public enum SwftSpace {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    public static let xxxl: CGFloat = 48
}

public enum SwftRadius {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 20
    public static let composer: CGFloat = 28
    /// Floating menus and popovers (model picker).
    public static let menu: CGFloat = 22
}

public enum SwftLayout {
    public static let sidebarWidth: CGFloat = 280
    public static let sidebarRowHeight: CGFloat = 32
    public static let contentMaxWidth: CGFloat = 760
    public static let composerMaxWidth: CGFloat = 744
    public static let titlebarHeight: CGFloat = 52
}

import SwiftUI

/// One-shot springs and transitions. Nothing in Swft repaints continuously (no repeating animations);
/// every animation here settles and stops. Views pass `reduceMotion` so Reduce Motion falls back to crossfades.
public enum SwftMotion {
    /// Tightest swap/step motion: text swaps and stepped slider stops.
    public static let snap = Animation.snappy(duration: 0.11)
    public static let quick = Animation.snappy(duration: 0.16)
    public static let standard = Animation.snappy(duration: 0.24)
    /// Default UI spring: hover/press, toggles, cards expanding.
    public static let spring = Animation.spring(response: 0.34, dampingFraction: 0.86)
    /// Slightly lively spring for things that pop in (send button, scroll-to-bottom, approval card).
    public static let pop = Animation.spring(response: 0.3, dampingFraction: 0.72)
    /// Sidebar collapse and long scrolls.
    public static let screen = Animation.spring(response: 0.42, dampingFraction: 0.9)
    /// Switching screens or threads: short and critically damped, so a new click retargets instead of queueing.
    public static let screenSwitch = Animation.snappy(duration: 0.18)
    /// Work folds opening and closing.
    public static let disclosure = Animation.spring(response: 0.28, dampingFraction: 0.92)
    /// Selection pill gliding between rows.
    public static let glide = Animation.spring(response: 0.36, dampingFraction: 0.82)

    /// Popover entrance and exit: critically damped (no overshoot) so text lands once and never wobbles.
    public static let popoverDamping: Double = 1
    public static let popover = Animation.spring(response: 0.24, dampingFraction: popoverDamping)
    /// Scale a popover grows from; kept close to 1 so glyphs barely resize while it fades in.
    public static let popoverScale: CGFloat = 0.97
    public static let popoverOffset: CGFloat = 4

    public static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : animation
    }

    // Tactile press: down is instant-feeling, release springs back.
    public static func pressAnimation(isPressed: Bool, reduceMotion: Bool) -> Animation {
        if reduceMotion { return .easeOut(duration: 0.1) }
        return isPressed ? snap : spring
    }

    /// Scale while pressed; Reduce Motion keeps controls still and relies on the pressed fill alone.
    public static func pressScale(isPressed: Bool, scale: CGFloat, reduceMotion: Bool) -> CGFloat {
        isPressed && !reduceMotion ? scale : 1
    }
}

extension AnyTransition {
    /// New content fades in while rising slightly; crossfade only under Reduce Motion.
    public static func swftRise(reduceMotion: Bool, distance: CGFloat = 10) -> AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(y: distance)), removal: .opacity)
    }

    /// Pops in from slightly smaller; crossfade only under Reduce Motion.
    public static func swftPop(reduceMotion: Bool, scale: CGFloat = 0.9) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: scale))
    }

    /// A floating panel growing out of its trigger's corner; `opensBelow` panels drop down, others rise up.
    public static func swftPopover(reduceMotion: Bool, opensBelow: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        let anchor: UnitPoint = opensBelow ? .topTrailing : .bottomTrailing
        return .opacity
            .combined(with: .scale(scale: SwftMotion.popoverScale, anchor: anchor))
            .combined(with: .offset(y: opensBelow ? -SwftMotion.popoverOffset : SwftMotion.popoverOffset))
    }
}

extension View {
    /// One-shot entrance for a freshly inserted screen: it settles from a hair below while fading in.
    /// Screens swap without a transition (the old one leaves at once), so rapid switching never stacks two screens,
    /// and a click mid-entrance simply starts the next screen's entrance.
    public func swftEntrance(reduceMotion: Bool) -> some View {
        modifier(SwftEntrance(reduceMotion: reduceMotion))
    }
}

private struct SwftEntrance: ViewModifier {
    let reduceMotion: Bool
    @State private var shown = false
    @Environment(\.swftScreenHandoff) private var screenHandoff

    func body(content: Content) -> some View {
        let handoff = screenHandoff && !reduceMotion
        content
            .opacity(shown || handoff ? 1 : 0)
            .offset(y: shown || reduceMotion || handoff ? 0 : 6)
            .onAppear {
                withAnimation(SwftMotion.resolve(SwftMotion.screenSwitch, reduceMotion: reduceMotion)) { shown = true }
            }
    }
}
