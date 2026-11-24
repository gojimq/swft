import SwiftUI

/// Discrete visual phases of an in-place sidebar selection pill.
public enum SidebarSelectionPhase: Equatable, Sendable {
    case hidden
    case pressingIn
    case settled
    case fadingOut
}

/// Target transform and opacity for a sidebar selection pill at a given phase.
public struct SidebarSelectionVisualState: Equatable, Sendable {
    public let opacity: Double
    public let scale: CGFloat

    public init(opacity: Double, scale: CGFloat) {
        self.opacity = opacity
        self.scale = scale
    }
}

/// Pure motion parameters and state resolution for in-place sidebar selection.
public enum SidebarSelectionMotion {
    public static let pillPressScale: CGFloat = 0.965
    public static let rowPressScale: CGFloat = 0.985
    public static let pressInDuration: TimeInterval = 0.075
    public static let fadeOutDuration: TimeInterval = 0.14
    public static let reduceMotionDuration: TimeInterval = 0.14
    public static let releaseSpringResponse: Double = 0.22
    public static let releaseSpringDamping: Double = 0.78

    /// Resolves the target pill opacity and scale for a phase, disabling scale under Reduce Motion.
    public static func visualState(for phase: SidebarSelectionPhase, reduceMotion: Bool) -> SidebarSelectionVisualState {
        switch phase {
        case .hidden, .fadingOut:
            SidebarSelectionVisualState(opacity: 0, scale: 1)
        case .pressingIn:
            SidebarSelectionVisualState(opacity: 1, scale: reduceMotion ? 1 : pillPressScale)
        case .settled:
            SidebarSelectionVisualState(opacity: 1, scale: 1)
        }
    }

    /// Initial phase when a row mounts (already-selected rows start settled with no entrance bounce).
    public static func initialPhase(isSelected: Bool) -> SidebarSelectionPhase {
        isSelected ? .settled : .hidden
    }

    /// Next phase when `isSelected` changes on an existing row.
    public static func transitionPhase(isSelected: Bool, reduceMotion: Bool) -> SidebarSelectionPhase {
        if isSelected {
            return reduceMotion ? .settled : .pressingIn
        }
        return .fadingOut
    }

    /// Returns whether a pending press-release completion should settle the pill to scale 1.
    public static func shouldRelease(capturedGeneration: Int, currentGeneration: Int, isSelected: Bool) -> Bool {
        capturedGeneration == currentGeneration && isSelected
    }
}

/// Sidebar row button style with hover/press feedback and an in-place selection pill.
/// Clicking a new row fades the pill in with a subtle press-down/up pulse while the previous row fades out
/// strictly in place (no matched-geometry sliding).
public struct SidebarSelectionButtonStyle<S: Shape>: ButtonStyle {
    let shape: S
    let selected: Bool
    let pressScale: CGFloat

    public init(shape: S, selected: Bool = false, pressScale: CGFloat = SidebarSelectionMotion.rowPressScale) {
        self.shape = shape
        self.selected = selected
        self.pressScale = pressScale
    }

    public func makeBody(configuration: Configuration) -> some View {
        SidebarSelectionRowBody(
            configuration: configuration,
            shape: shape,
            selected: selected,
            pressScale: pressScale
        )
    }

    private struct SidebarSelectionRowBody: View {
        let configuration: Configuration
        let shape: S
        let selected: Bool
        let pressScale: CGFloat
        @State private var hovering = false
        @State private var pillOpacity: Double
        @State private var pillScale: CGFloat = 1
        @State private var pulseGeneration = 0
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        init(configuration: Configuration, shape: S, selected: Bool, pressScale: CGFloat) {
            self.configuration = configuration
            self.shape = shape
            self.selected = selected
            self.pressScale = pressScale
            let initial = SidebarSelectionMotion.visualState(
                for: SidebarSelectionMotion.initialPhase(isSelected: selected),
                reduceMotion: false
            )
            _pillOpacity = State(initialValue: initial.opacity)
            _pillScale = State(initialValue: initial.scale)
        }

        var body: some View {
            configuration.label
                .background {
                    ZStack {
                        shape.fill(hoverFill)
                        shape.fill(SwftColor.selection)
                            .opacity(pillOpacity)
                            .scaleEffect(pillScale)
                    }
                }
                .scaleEffect(configuration.isPressed && !reduceMotion ? pressScale : 1)
                .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: hovering)
                .animation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion), value: configuration.isPressed)
                .onHover { hovering = $0 }
                .onChange(of: selected) { _, isNowSelected in
                    animateSelection(isNowSelected)
                }
        }

        private var hoverFill: Color {
            if selected { return .clear }
            if configuration.isPressed { return SwftColor.pressed }
            return hovering ? SwftColor.hover : .clear
        }

        private func animateSelection(_ isNowSelected: Bool) {
            pulseGeneration &+= 1
            let generation = pulseGeneration
            let phase = SidebarSelectionMotion.transitionPhase(isSelected: isNowSelected, reduceMotion: reduceMotion)
            let target = SidebarSelectionMotion.visualState(for: phase, reduceMotion: reduceMotion)

            if phase == .pressingIn {
                withAnimation(.easeOut(duration: SidebarSelectionMotion.pressInDuration)) {
                    pillOpacity = target.opacity
                    pillScale = target.scale
                } completion: {
                    guard SidebarSelectionMotion.shouldRelease(
                        capturedGeneration: generation,
                        currentGeneration: pulseGeneration,
                        isSelected: selected
                    ) else { return }
                    let settled = SidebarSelectionMotion.visualState(for: .settled, reduceMotion: reduceMotion)
                    withAnimation(.spring(
                        response: SidebarSelectionMotion.releaseSpringResponse,
                        dampingFraction: SidebarSelectionMotion.releaseSpringDamping
                    )) {
                        pillOpacity = settled.opacity
                        pillScale = settled.scale
                    }
                }
            } else {
                let duration = reduceMotion
                    ? SidebarSelectionMotion.reduceMotionDuration
                    : SidebarSelectionMotion.fadeOutDuration
                withAnimation(.easeOut(duration: duration)) {
                    pillOpacity = target.opacity
                    pillScale = target.scale
                }
            }
        }
    }
}
