import SwiftUI

/// Secondary hover action displayed in the top-right slot of a thread inbox row.
@MainActor
public struct ThreadRowHoverAction {
    public let systemName: String
    public let label: String
    public let perform: () -> Void

    public init(systemName: String, label: String, perform: @escaping () -> Void) {
        self.systemName = systemName
        self.label = label
        self.perform = perform
    }

    public static func settle(_ perform: @escaping () -> Void) -> Self {
        Self(systemName: "checkmark", label: "Settle thread", perform: perform)
    }

    public static func unsettle(_ perform: @escaping () -> Void) -> Self {
        Self(systemName: "arrow.uturn.backward", label: "Un-settle thread", perform: perform)
    }
}

/// Quiet circular icon button that crossfades over the timestamp slot when a thread row is hovered.
public struct ThreadHoverActionButton: View {
    let action: ThreadRowHoverAction
    let onTrigger: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(action: ThreadRowHoverAction, onTrigger: (() -> Void)? = nil) {
        self.action = action
        self.onTrigger = onTrigger ?? action.perform
    }

    public var body: some View {
        Button(action: onTrigger) {
            Image(systemName: action.systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isHovered ? SwftColor.textPrimary : SwftColor.textTertiary)
                .frame(width: 20, height: 20)
                .contentShape(Circle())
        }
        .buttonStyle(ActionCircleButtonStyle(isHovered: isHovered))
        .onHover { isHovered = $0 }
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: isHovered)
        .help(action.label)
        .accessibilityLabel(action.label)
    }
}

private struct ActionCircleButtonStyle: ButtonStyle {
    let isHovered: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Circle().fill(fill(isPressed: configuration.isPressed))
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
            .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: isHovered)
            .animation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion), value: configuration.isPressed)
    }

    private func fill(isPressed: Bool) -> Color {
        if isPressed { return SwftColor.pressed }
        if isHovered { return SwftColor.hover }
        return .clear
    }
}

/// Button style matching `HoverFillStyle` whose hover state is supplied by an enclosing container,
/// preventing background flicker when moving the pointer onto a sibling overlay button.
public struct ExternalHoverFillStyle<S: Shape>: ButtonStyle {
    let shape: S
    var selected: Bool
    var isHovering: Bool
    var pressScale: CGFloat

    public init(shape: S, selected: Bool = false, isHovering: Bool = false, pressScale: CGFloat = 0.97) {
        self.shape = shape
        self.selected = selected
        self.isHovering = isHovering
        self.pressScale = pressScale
    }

    public func makeBody(configuration: Configuration) -> some View {
        BodyView(
            configuration: configuration,
            shape: shape,
            selected: selected,
            isHovering: isHovering,
            pressScale: pressScale
        )
    }

    private struct BodyView: View {
        let configuration: Configuration
        let shape: S
        let selected: Bool
        let isHovering: Bool
        let pressScale: CGFloat
        @Environment(\.swftSelectionNamespace) private var selectionNamespace
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .background {
                    ZStack {
                        shape.fill(hoverFill)
                        if selected {
                            if let selectionNamespace {
                                shape.fill(SwftColor.selection)
                                    .matchedGeometryEffect(id: SwftSelection.pillID, in: selectionNamespace)
                            } else {
                                shape.fill(SwftColor.selection)
                            }
                        }
                    }
                }
                .scaleEffect(configuration.isPressed && !reduceMotion ? pressScale : 1)
                .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: isHovering)
                .animation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion), value: configuration.isPressed)
        }

        private var hoverFill: Color {
            if selected { return .clear }
            if configuration.isPressed { return SwftColor.pressed }
            return isHovering ? SwftColor.hover : .clear
        }
    }
}

/// Quiet collapsible header for the Settled threads shelf inside the sidebar list.
public struct SettledSectionHeader: View {
    let title: String
    let count: Int
    let isExpanded: Bool
    let opensUpward: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        _ title: String = "Settled",
        count: Int,
        isExpanded: Bool,
        opensUpward: Bool = false,
        action: @escaping () -> Void = {}
    ) {
        self.title = title
        self.count = count
        self.isExpanded = isExpanded
        self.opensUpward = opensUpward
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: opensUpward ? "chevron.up" : "chevron.right")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(SwftColor.textTertiary)
                    .rotationEffect(.degrees(isExpanded ? (opensUpward ? 180 : 90) : 0))
                    .frame(width: 11, height: 11)
                    .animation(SwftMotion.resolve(SwftMotion.disclosure, reduceMotion: reduceMotion), value: isExpanded)
                Text(title)
                    .font(SwftType.sectionHeader)
                    .foregroundStyle(SwftColor.textTertiary)
                Spacer(minLength: 0)
                Text("\(count)")
                    .font(SwftType.caption)
                    .monospacedDigit()
                    .foregroundStyle(SwftColor.textTertiary)
            }
            .padding(.leading, 9)
            .padding(.trailing, 10)
            .frame(height: 28)
            .contentShape(RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous))
        }
        .buttonStyle(HoverFillStyle(shape: RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous), pressScale: 0.99))
        .accessibilityLabel("\(title), \(count) \(count == 1 ? "thread" : "threads")")
        .accessibilityHint(isExpanded ? "Collapse settled threads" : "Expand settled threads")
        .accessibilityAddTraits(.isHeader)
    }
}

/// Minimal unobtrusive retry pill shown in the sidebar footer only when the local server is offline.
public struct OfflineRetryPill: View {
    let title: String
    let dotColor: Color
    let action: () -> Void

    public init(title: String, dotColor: Color, action: @escaping () -> Void = {}) {
        self.title = title
        self.dotColor = dotColor
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Retry")
                        .font(SwftType.captionStrong)
                }
                .foregroundStyle(SwftColor.textPrimary)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Capsule().fill(SwftColor.surfaceMuted))
            .overlay(Capsule().strokeBorder(SwftColor.borderSubtle))
            .contentShape(Capsule())
        }
        .buttonStyle(HoverFillStyle(shape: Capsule(), pressScale: 0.985))
        .help("Reconnect to local server")
        .accessibilityLabel("\(title). Retry connection")
    }
}

extension View {
    @ViewBuilder
    public func optionalAccessibilityAction(_ hoverAction: ThreadRowHoverAction?) -> some View {
        if let hoverAction {
            self.accessibilityAction(named: Text(hoverAction.label)) {
                hoverAction.perform()
            }
        } else {
            self
        }
    }
}
