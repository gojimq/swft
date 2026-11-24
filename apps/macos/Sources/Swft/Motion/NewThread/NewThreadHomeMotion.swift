import SwftDesign
import SwiftUI

enum NewThreadMotion {
    /// Home's coordinate space; the composer measures its docked destination against it.
    static let homeSpace = "swft.home"
    /// Gap under a thread's docked composer (`ThreadView`'s composer bar bottom padding), so the docked Home composer
    /// lands exactly where the thread's composer sits and the hand-off is seamless.
    static let dockedBottomInset: CGFloat = 12
}

extension View {
    /// Drives Home's launch staging: `docked` springs on while a launch is in flight (and back off if it is cancelled or
    /// fails) and reports the dock settling to the launcher. Leaving Home mid-launch abandons the launch.
    func newThreadLaunchStage(docked: Binding<Bool>) -> some View {
        modifier(NewThreadLaunchStage(docked: docked))
    }

    /// While `docked`, the composer travels from its centred Home slot down to where a thread's composer sits.
    /// Under Reduce Motion it fades out in place instead, and the thread's screen crossfades in.
    func newThreadDock(_ docked: Bool) -> some View {
        modifier(NewThreadDock(docked: docked))
    }
}

private struct NewThreadLaunchStage: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var docked: Bool

    func body(content: Content) -> some View {
        content
            .coordinateSpace(.named(NewThreadMotion.homeSpace))
            .onChange(of: model.newThread.launchingToken, initial: true) { _, token in
                if let token {
                    withAnimation(SwftMotion.resolve(SwftMotion.dock, reduceMotion: reduceMotion)) {
                        docked = true
                    } completion: {
                        model.newThread.dockSettled(token: token)
                    }
                } else if docked {
                    withAnimation(SwftMotion.resolve(SwftMotion.arrival, reduceMotion: reduceMotion)) { docked = false }
                }
            }
            .onDisappear { model.newThread.abandon() }
    }
}

private struct NewThreadDock: ViewModifier {
    let docked: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var travel: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { proxy in
                // Home's bounds in the composer's own coordinates: its maxY is the distance down to Home's bottom edge.
                guard let home = proxy.bounds(of: .named(NewThreadMotion.homeSpace)) else { return 0 }
                return max(0, home.maxY - NewThreadMotion.dockedBottomInset - proxy.size.height)
            } action: { travel = $0 }
            .opacity(docked && reduceMotion ? 0 : 1)
            .offset(y: docked && !reduceMotion ? travel : 0)
    }
}
