import AppKit
import QuartzCore
import SwftDesign
import SwiftUI

/// Drives smooth display-synced scrolling on `ThreadView`'s underlying macOS `NSScrollView`.
///
/// SwiftUI's animated `ScrollPosition.scrollTo(edge: .bottom)` on macOS `HostingScrollView` steps `bounds.origin.y`
/// in whole-point integers at uneven frame cadence with velocity jitter. Driving `NSClipView` directly from a
/// `CADisplayLink` synced to the display's native refresh rate (60/120Hz ProMotion) with `CubicBezierCurve.send`
/// keeps the transcript scroll locked in phase with `SendFlightOverlayBubble` at physical-pixel precision, while
/// canceling immediately the instant the user touches the trackpad, mouse wheel, or scrollbar.
@MainActor
final class SendFlightScrollDriver {
    private struct ActiveScrollAnimation {
        let startY: CGFloat
        var targetY: CGFloat
        let startTime: CFTimeInterval
        let duration: TimeInterval
        let curve: CubicBezierCurve
        var targetLocked: Bool
        let onComplete: (() -> Void)?
    }

    private weak var scrollView: NSScrollView?
    private var proxy: ScrollDriverProxy?
    private var displayLink: CADisplayLink?
    private var fallbackTimer: Timer?
    private var animation: ActiveScrollAnimation?

    /// Called immediately when the user initiates scrolling while a programmatic scroll animation is running.
    var onUserScrollInterrupt: (() -> Void)?

    var isAnimating: Bool { animation != nil }
    var isAttached: Bool { scrollView != nil }

    func attach(_ scrollView: NSScrollView) {
        if self.scrollView === scrollView { return }
        detach()
        self.scrollView = scrollView
        let proxy = ScrollDriverProxy(driver: self)
        self.proxy = proxy
        NotificationCenter.default.addObserver(
            proxy,
            selector: #selector(ScrollDriverProxy.handleWillStartLiveScroll(_:)),
            name: NSScrollView.willStartLiveScrollNotification,
            object: scrollView
        )
    }

    func detach() {
        cancelAnimation()
        if let proxy {
            NotificationCenter.default.removeObserver(proxy)
        }
        proxy = nil
        scrollView = nil
    }

    func maxScrollY(of scrollView: NSScrollView) -> CGFloat {
        let clipView = scrollView.contentView
        let insets = clipView.contentInsets
        let minY = -insets.top
        guard let documentView = scrollView.documentView else { return minY }
        let rawMax = max(minY, documentView.frame.maxY - clipView.bounds.height + insets.bottom)
        let constrained = clipView.constrainBoundsRect(
            NSRect(origin: NSPoint(x: clipView.bounds.origin.x, y: rawMax), size: clipView.bounds.size)
        ).origin.y
        return max(minY, constrained)
    }

    @discardableResult
    func scrollImmediately(toY y: CGFloat) -> Bool {
        guard let scrollView else { return false }
        cancelAnimation()
        applyOffset(y, to: scrollView)
        return true
    }

    @discardableResult
    func scrollToBottomImmediately() -> Bool {
        guard let scrollView else { return false }
        cancelAnimation()
        scrollView.layoutSubtreeIfNeeded()
        applyOffset(maxScrollY(of: scrollView), to: scrollView)
        return true
    }

    /// Animates the attached `NSScrollView` to its bottom using `curve` over `duration`.
    /// Returns `false` when no scroll view is attached so the caller can fall back to SwiftUI's `ScrollPosition`.
    @discardableResult
    func animateToBottom(
        duration: TimeInterval,
        curve: CubicBezierCurve,
        preJumpY: CGFloat? = nil,
        onComplete: (() -> Void)? = nil
    ) -> Bool {
        guard let scrollView else { return false }
        cancelAnimation()
        scrollView.layoutSubtreeIfNeeded()
        if let preJumpY {
            applyOffset(preJumpY, to: scrollView)
        }
        let startY = scrollView.contentView.bounds.origin.y
        let targetY = maxScrollY(of: scrollView)

        if duration <= 0 {
            applyOffset(targetY, to: scrollView)
            onComplete?()
            return true
        }

        let now = CACurrentMediaTime()
        animation = ActiveScrollAnimation(
            startY: startY,
            targetY: targetY,
            startTime: now,
            duration: duration,
            curve: curve,
            targetLocked: false,
            onComplete: onComplete
        )
        startFramePacing(for: scrollView)
        return true
    }

    /// Distance remaining to the bottom of the attached `NSScrollView`, or `nil` when detached.
    func distanceFromBottom() -> CGFloat? {
        guard let scrollView else { return nil }
        let maxY = maxScrollY(of: scrollView)
        return max(0, maxY - scrollView.contentView.bounds.origin.y)
    }

    /// Finishes an active scroll cleanly at its target (used when the paired flight lands right before the final tick).
    func finishAnimationAtTarget() {
        guard let anim = animation, let scrollView else {
            cancelAnimation()
            return
        }
        let finalY = anim.targetLocked ? anim.targetY : maxScrollY(of: scrollView)
        applyOffset(finalY, to: scrollView)
        let completion = anim.onComplete
        cancelAnimation()
        completion?()
    }

    func cancelAnimation() {
        animation = nil
        displayLink?.invalidate()
        displayLink = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    // MARK: - Frame Pacing

    private func startFramePacing(for scrollView: NSScrollView) {
        let proxy = self.proxy ?? {
            let created = ScrollDriverProxy(driver: self)
            self.proxy = created
            return created
        }()

        let link: CADisplayLink?
        if scrollView.window?.screen != nil {
            link = scrollView.displayLink(target: proxy, selector: #selector(ScrollDriverProxy.stepDisplayLink(_:)))
        } else if let screen = NSScreen.main {
            link = screen.displayLink(target: proxy, selector: #selector(ScrollDriverProxy.stepDisplayLink(_:)))
        } else {
            link = nil
        }

        if let link {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            displayLink = link
            return
        }

        // Headless fallback when no display is attached.
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.step(at: CACurrentMediaTime())
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        fallbackTimer = timer
    }

    fileprivate func handleDisplayLinkTick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let sampleTime: CFTimeInterval
        if abs(link.timestamp - now) < 0.5, link.targetTimestamp >= now {
            sampleTime = link.targetTimestamp
        } else {
            sampleTime = now
        }
        step(at: sampleTime)
    }

    fileprivate func handleUserLiveScroll() {
        let wasAnimating = animation != nil
        cancelAnimation()
        if wasAnimating {
            onUserScrollInterrupt?()
        }
    }

    private func step(at now: CFTimeInterval) {
        guard var anim = animation, let scrollView else {
            cancelAnimation()
            return
        }
        let clipView = scrollView.contentView
        let elapsed = max(0, now - anim.startTime)

        // Allow LazyVStack to settle the newly added turn's height during the first 80ms (while eased < ~0.12),
        // then lock the target so mid-flight streaming overflow never causes a sudden velocity jump.
        if !anim.targetLocked {
            let liveMax = maxScrollY(of: scrollView)
            if liveMax > anim.startY + 0.5 {
                anim.targetY = liveMax
            }
            if elapsed >= 0.08 && anim.targetY > anim.startY + 0.5 {
                anim.targetLocked = true
            }
        }

        let progress = min(1.0, elapsed / anim.duration)

        if progress >= 1.0 {
            let finalY = anim.targetLocked ? anim.targetY : maxScrollY(of: scrollView)
            applyOffset(finalY, to: scrollView)
            let completion = anim.onComplete
            cancelAnimation()
            completion?()
            return
        }

        let eased = anim.curve.value(at: progress)
        let scale = max(2, scrollView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        let interpolated = anim.startY + (anim.targetY - anim.startY) * CGFloat(eased)
        let nextY = (interpolated * scale).rounded() / scale

        if abs(nextY - clipView.bounds.origin.y) >= 0.01 {
            applyOffset(nextY, to: scrollView)
        }
        animation = anim
    }

    private func applyOffset(_ y: CGFloat, to scrollView: NSScrollView) {
        let clipView = scrollView.contentView
        let proposed = NSRect(origin: NSPoint(x: clipView.bounds.origin.x, y: y), size: clipView.bounds.size)
        let constrained = clipView.constrainBoundsRect(proposed).origin
        clipView.scroll(to: constrained)
        scrollView.reflectScrolledClipView(clipView)
    }
}

@MainActor
private final class ScrollDriverProxy: NSObject {
    weak var driver: SendFlightScrollDriver?

    init(driver: SendFlightScrollDriver) {
        self.driver = driver
    }

    @objc func stepDisplayLink(_ link: CADisplayLink) {
        driver?.handleDisplayLinkTick(link)
    }

    @objc func handleWillStartLiveScroll(_ notification: Notification) {
        driver?.handleUserLiveScroll()
    }
}

/// Zero-size AppKit anchor placed inside `ThreadView`'s `ScrollView` content to bind `SendFlightScrollDriver`
/// to the enclosing `NSScrollView`.
struct SendFlightScrollAnchor: NSViewRepresentable {
    let driver: SendFlightScrollDriver

    func makeNSView(context: Context) -> SendFlightScrollAnchorView {
        SendFlightScrollAnchorView(driver: driver)
    }

    func updateNSView(_ nsView: SendFlightScrollAnchorView, context: Context) {
        nsView.driver = driver
        nsView.attachIfPossible()
    }
}

final class SendFlightScrollAnchorView: NSView {
    weak var driver: SendFlightScrollDriver?

    init(driver: SendFlightScrollDriver) {
        self.driver = driver
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            driver?.detach()
        } else {
            attachIfPossible()
        }
    }

    func attachIfPossible() {
        guard let scrollView = enclosingScrollView else { return }
        driver?.attach(scrollView)
    }
}
