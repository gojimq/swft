import SwftDesign
import SwiftUI

enum NewThreadMotion {
    /// Home's coordinate space; the composer measures its docked destination against it.
    static let homeSpace = "swft.home"
    /// Gap under a thread's docked composer (`ThreadView`'s composer bar bottom padding), so the docked Home composer
    /// lands exactly where the thread's composer sits and the hand-off is seamless.
    static let dockedBottomInset: CGFloat = 12
}

/// Token-scoped first-message preview held by `HomeView` so a cancelled or failed launch can fade the preview back out
/// cleanly before removing it.
struct NewThreadLaunchPreview: Equatable {
    let token: Int
    let message: NewThreadLaunchMessage
}

extension View {
    /// Drives Home's launch staging: `docked` springs on while a launch is in flight (and back off if it is cancelled or
    /// fails), populates `launchPreview` so the first message fades in concurrently with the dock, and reports the dock
    /// settling to the launcher. Leaving Home mid-launch abandons the launch.
    func newThreadLaunchStage(
        docked: Binding<Bool>,
        launchPreview: Binding<NewThreadLaunchPreview?>
    ) -> some View {
        modifier(NewThreadLaunchStage(docked: docked, launchPreview: launchPreview))
    }

    /// While `docked`, the composer travels from its centred Home slot down to where a thread's composer sits.
    /// Under Reduce Motion it fades out in place instead, and the thread's screen crossfades in.
    func newThreadDock(_ docked: Bool) -> some View {
        modifier(NewThreadDock(docked: docked))
    }
}

/// Fades the launching first message into the exact top-of-transcript coordinates `ThreadView` uses for `UserBubble`,
/// simultaneously with the composer sliding down. When `ThreadView` takes over on handoff, its real `UserBubble` is
/// already at opacity 1 in the exact same pixels (zero double-fade, zero jump).
struct NewThreadFirstMessagePreview: View {
    let message: NewThreadLaunchMessage
    let visible: Bool
    let onHidden: () -> Void
    @State private var opacity: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            UserBubble(message.text, attachments: message.attachments)
                .equatable()
                .padding(.vertical, SendFlightLogic.userRowVerticalPadding)
                .newThreadBubbleProbe(.homePreview, opacity: opacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxWidth: SwftLayout.contentMaxWidth)
        .padding(.horizontal, 32)
        .padding(.top, ThreadView.topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.container, edges: .top)
        .opacity(opacity)
        .allowsHitTesting(false)
        .onAppear {
            guard visible else { return }
            withAnimation(SwftMotion.handoffFade) {
                opacity = 1
            }
        }
        .onChange(of: visible) { _, isVisible in
            if isVisible {
                withAnimation(SwftMotion.handoffFade) {
                    opacity = 1
                }
            } else {
                withAnimation(SwftMotion.departure, completionCriteria: .logicallyComplete) {
                    opacity = 0
                } completion: {
                    onHidden()
                }
            }
        }
    }
}

private struct NewThreadLaunchStage: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sendFlightForceReduceMotion) private var forceReduceMotion
    @Binding var docked: Bool
    @Binding var launchPreview: NewThreadLaunchPreview?

    private var effectiveReduceMotion: Bool { reduceMotion || forceReduceMotion }

    func body(content: Content) -> some View {
        content
            .coordinateSpace(.named(NewThreadMotion.homeSpace))
            .onChange(of: model.newThread.launchingToken, initial: true) { _, token in
                if let token {
                    if !effectiveReduceMotion, let message = model.newThread.launchingMessage {
                        launchPreview = NewThreadLaunchPreview(token: token, message: message)
                    } else {
                        launchPreview = nil
                    }
                    // Hand off when the dock lands visually (the spring's duration, within ~1pt), not after its
                    // invisible tail; the first message has already faded into place concurrently during the slide.
                    withAnimation(SwftMotion.resolve(SwftMotion.dock, reduceMotion: effectiveReduceMotion), completionCriteria: .logicallyComplete) {
                        docked = true
                    } completion: {
                        model.newThread.dockSettled(token: token)
                    }
                } else if docked {
                    withAnimation(SwftMotion.resolve(SwftMotion.arrival, reduceMotion: effectiveReduceMotion)) { docked = false }
                } else {
                    launchPreview = nil
                }
            }
            .onDisappear { model.newThread.abandon() }
    }
}

private struct NewThreadDock: ViewModifier {
    let docked: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sendFlightForceReduceMotion) private var forceReduceMotion
    @State private var travel: CGFloat = 0

    private var effectiveReduceMotion: Bool { reduceMotion || forceReduceMotion }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { proxy in
                // Home's bounds in the composer's own coordinates: its maxY is the distance down to Home's bottom edge.
                guard let home = proxy.bounds(of: .named(NewThreadMotion.homeSpace)) else { return 0 }
                return max(0, home.maxY - NewThreadMotion.dockedBottomInset - proxy.size.height)
            } action: { travel = $0 }
            .opacity(docked && effectiveReduceMotion ? 0 : 1)
            .offset(y: docked && !effectiveReduceMotion ? travel : 0)
    }
}
