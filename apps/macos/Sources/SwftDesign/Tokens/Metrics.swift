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
    public static let quick = Animation.snappy(duration: 0.16)
    public static let standard = Animation.snappy(duration: 0.24)
    /// Default UI spring: hover/press, toggles, cards expanding.
    public static let spring = Animation.spring(response: 0.34, dampingFraction: 0.86)
    /// Slightly lively spring for things that pop in (send button, scroll-to-bottom, approval card).
    public static let pop = Animation.spring(response: 0.3, dampingFraction: 0.72)
    /// Screen and sidebar changes.
    public static let screen = Animation.spring(response: 0.42, dampingFraction: 0.9)
    /// Selection pill gliding between rows.
    public static let glide = Animation.spring(response: 0.36, dampingFraction: 0.82)

    public static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : animation
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

    /// Screen swap: incoming screen settles from a hair below and slightly scaled; outgoing fades.
    public static func swftScreen(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.985)).combined(with: .offset(y: 8)),
            removal: .opacity
        )
    }
}
