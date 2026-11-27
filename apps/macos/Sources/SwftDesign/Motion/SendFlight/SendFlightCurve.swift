import CoreGraphics
import Foundation
import SwiftUI

/// Timing and threshold constants for a send in `ThreadView` (ported from Studio's thread view).
public enum SendFlightTiming {
    /// Distance from the bottom edge (pt) within which streaming keeps the viewport pinned (`STICK_PX`).
    public static let stickThreshold: CGFloat = 80
    /// Duration (s) for a settling scroll to glide into place (`SETTLE_MS = 420`).
    public static let settleDuration: TimeInterval = 0.42
    /// Duration (s) of the scroll that brings a sent message's turn and its stream room into view (`SEND_MS = 680`).
    public static let sendDuration: TimeInterval = 0.68
    /// Delay (s) into the send scroll before the sent message starts fading in.
    public static let sentMessageFadeDelay: TimeInterval = 0.2
    /// Fade-in duration (s) for a sent message, matching the first message's fade on a new thread.
    public static let handoffFadeDuration: TimeInterval = 0.30
    /// Delay (s) from a send until its "Working" indicator rises, once the message has faded in.
    public static let workingDelay: TimeInterval = sentMessageFadeDelay + handoffFadeDuration
}

public extension SwftMotion {
    /// The send scroll's fallback clock when no `NSScrollView` is attached (`680ms`, `cubic-bezier(0.3, 0.2, 0, 1)`).
    static let send = Animation.timingCurve(0.3, 0.2, 0, 1, duration: SendFlightTiming.sendDuration)
    /// Settling turn layout and fold transition (`420ms`, `cubic-bezier(0.2, 0.8, 0.2, 1)`).
    static let settle = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: SendFlightTiming.settleDuration)
    /// First-message fade-in as a new thread takes over from Home (`300ms`, `cubic-bezier(0.2, 0.8, 0.2, 1)`).
    static let handoffFade = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: SendFlightTiming.handoffFadeDuration)
    /// A sent message fading in as the transcript scrolls its turn into view: the same fade, a beat in.
    static let sentMessageFade = handoffFade.delay(SendFlightTiming.sentMessageFadeDelay)
    /// A sent message appearing under Reduce Motion, where nothing scrolls.
    static let reduceMotionFade = Animation.easeInOut(duration: 0.18)
}
