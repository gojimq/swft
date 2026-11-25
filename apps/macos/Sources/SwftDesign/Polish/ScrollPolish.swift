import AppKit
import SwiftUI

/// Which edges of a scroll view hide more content.
public struct ScrollOverflowEdges: Equatable, Sendable {
    public var above: Bool
    public var below: Bool

    public init(above: Bool, below: Bool) {
        self.above = above
        self.below = below
    }

    public static let none = ScrollOverflowEdges(above: false, below: false)

    /// Sub-point slack so rounding never fades a list that fits exactly.
    public static func from(
        offsetY: CGFloat,
        contentHeight: CGFloat,
        containerHeight: CGFloat,
        tolerance: CGFloat = 1
    ) -> ScrollOverflowEdges {
        guard contentHeight > containerHeight + tolerance else { return .none }
        return ScrollOverflowEdges(
            above: offsetY > tolerance,
            below: offsetY + containerHeight < contentHeight - tolerance
        )
    }
}

public extension View {
    /// Dissolves only the edges that actually hide scrolled content; a list that fits gets no fade.
    func swftScrollEdgeFade(length: CGFloat = 22) -> some View {
        modifier(ScrollEdgeFade(length: length))
    }

    /// Keeps the enclosing `NSScrollView` on overlay scrollers so a legacy scrollbar never steals width.
    /// Apply to the scroll view's content, not the `ScrollView` itself.
    func swftOverlayScrollbars() -> some View {
        background(OverlayScrollersAnchor().frame(width: 0, height: 0))
    }
}

private struct ScrollEdgeFade: ViewModifier {
    let length: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var edges = ScrollOverflowEdges.none

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: ScrollOverflowEdges.self) { geometry in
                ScrollOverflowEdges.from(
                    offsetY: geometry.contentOffset.y + geometry.contentInsets.top,
                    contentHeight: geometry.contentSize.height,
                    containerHeight: geometry.containerSize.height
                )
            } action: { _, next in
                withAnimation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion)) {
                    edges = next
                }
            }
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.black.opacity(edges.above ? 0 : 1), .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: length)
                    Color.black
                    LinearGradient(
                        colors: [.black, .black.opacity(edges.below ? 0 : 1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: length)
                }
            }
    }
}

private struct OverlayScrollersAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> OverlayScrollersView { OverlayScrollersView() }
    func updateNSView(_ nsView: OverlayScrollersView, context: Context) { nsView.applyOverlayStyle() }
}

final class OverlayScrollersView: NSView {
    private weak var observedScrollView: NSScrollView?
    private var scrollerStyleObservation: NSKeyValueObservation?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferredStyleChanged),
            name: NSScroller.preferredScrollerStyleDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyOverlayStyle()
    }

    @objc func applyOverlayStyle() {
        guard let scrollView = enclosingScrollView else { return }
        if observedScrollView !== scrollView {
            observedScrollView = scrollView
            scrollerStyleObservation = scrollView.observe(\.scrollerStyle, options: [.new]) { scrollView, _ in
                MainActor.assumeIsolated {
                    if scrollView.scrollerStyle != .overlay {
                        scrollView.scrollerStyle = .overlay
                    }
                }
            }
        }
        if scrollView.scrollerStyle != .overlay {
            scrollView.scrollerStyle = .overlay
        }
    }

    // AppKit resets every scroll view to the new preferred style on this notification; reapply after it does.
    @objc private func preferredStyleChanged() {
        perform(#selector(applyOverlayStyle), with: nil, afterDelay: 0)
    }
}
