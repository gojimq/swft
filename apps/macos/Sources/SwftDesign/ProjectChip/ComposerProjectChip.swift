import SwiftUI

/// Visual state rendered by `ComposerProjectChip`.
public enum ComposerProjectChipState: Equatable, Hashable, Sendable {
    /// A real project is attached (e.g. "Swft" or "Swft · main").
    case project(String)
    /// No project is attached — renders as a dashed neutral chip.
    case noProject(String = "No project")

    public var title: String {
        switch self {
        case .project(let title), .noProject(let title):
            return title
        }
    }

    public var isNoProject: Bool {
        if case .noProject = self { return true }
        return false
    }
}

extension EnvironmentValues {
    /// Forces the hover clear affordance visible for offscreen snapshots and previews.
    @Entry public var swftForceProjectChipClearVisible = false
}

/// Composer project context chip with hover-to-clear (`×`) and a dashed "No project" state.
/// Interactive instances wrap a `Menu` picker; display-only instances render the same pill without chrome.
public struct ComposerProjectChip<MenuContent: View>: View {
    let state: ComposerProjectChipState
    let interactive: Bool
    let onClear: (() -> Void)?
    let clearHelp: String
    let chipHelp: String?
    let menuContent: (() -> MenuContent)?

    @State private var isHovering = false
    @State private var isHoveringClear = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.swftForceProjectChipClearVisible) private var forceClearVisible

    public init(
        state: ComposerProjectChipState,
        onClear: (() -> Void)? = nil,
        clearHelp: String = "Clear project",
        chipHelp: String? = nil,
        @ViewBuilder menu: @escaping () -> MenuContent
    ) {
        self.state = state
        self.interactive = true
        self.onClear = onClear
        self.clearHelp = clearHelp
        self.chipHelp = chipHelp
        self.menuContent = menu
    }

    fileprivate init(
        readOnly state: ComposerProjectChipState,
        chipHelp: String?
    ) where MenuContent == EmptyView {
        self.state = state
        self.interactive = false
        self.onClear = nil
        self.clearHelp = "Clear project"
        self.chipHelp = chipHelp
        self.menuContent = nil
    }

    private var showsClear: Bool {
        interactive && !state.isNoProject && onClear != nil && (isHovering || forceClearVisible)
    }

    private var showHoveredChrome: Bool {
        interactive && (isHovering || forceClearVisible)
    }

    private var backgroundFill: Color {
        if state.isNoProject {
            return showHoveredChrome ? SwftColor.hover : SwftColor.surfaceMuted.opacity(0.55)
        }
        return showHoveredChrome ? SwftColor.hover : .clear
    }

    private var iconColor: Color {
        if state.isNoProject {
            return showHoveredChrome ? SwftColor.textSecondary : SwftColor.textTertiary
        }
        return SwftColor.textPrimary
    }

    private var labelColor: Color {
        if state.isNoProject {
            return showHoveredChrome ? SwftColor.textPrimary : SwftColor.textSecondary
        }
        return SwftColor.textPrimary
    }

    private var dashedBorderOpacity: Double {
        showHoveredChrome ? 0.52 : 0.36
    }

    public var body: some View {
        HStack(spacing: 0) {
            if interactive, let menuContent {
                Menu {
                    menuContent()
                } label: {
                    chipLabel
                }
                .menuStyle(.button)
                .buttonStyle(ChipTriggerStyle(reduceMotion: reduceMotion))
                .menuIndicator(.hidden)
                .fixedSize()
                .help(chipHelp ?? "")
            } else {
                chipLabel
                    .fixedSize()
                    .help(chipHelp ?? "")
            }

            if showsClear, let onClear {
                Button {
                    isHoveringClear = false
                    withAnimation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion)) {
                        onClear()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(isHoveringClear ? SwftColor.textPrimary : SwftColor.textTertiary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(isHoveringClear ? SwftColor.pressed : .clear))
                        .contentShape(Circle())
                }
                .buttonStyle(ChipClearButtonStyle(reduceMotion: reduceMotion))
                .onHover { isHoveringClear = $0 }
                .padding(.trailing, 5)
                .help(clearHelp)
                .accessibilityLabel(clearHelp)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .scale(scale: 0.72))
                )
            }
        }
        .frame(height: 30)
        .background(Capsule().fill(backgroundFill))
        .overlay {
            Capsule()
                .strokeBorder(
                    SwftColor.textTertiary.opacity(dashedBorderOpacity),
                    style: StrokeStyle(lineWidth: 1, dash: [3.5, 3])
                )
                .opacity(state.isNoProject ? 1 : 0)
                .allowsHitTesting(false)
        }
        .contentShape(Capsule())
        .onHover { hovering in
            guard interactive else { return }
            isHovering = hovering
            if !hovering { isHoveringClear = false }
        }
        .onChange(of: state) { _, _ in
            isHovering = false
            isHoveringClear = false
        }
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: isHovering)
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: isHoveringClear)
        .animation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion), value: showsClear)
        .animation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion), value: state)
    }

    private var chipLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: state.isNoProject ? "square.dashed" : "folder")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 14, height: 14)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            SwapText(state.title)
                .font(SwftType.label)
                .foregroundStyle(labelColor)
                .frame(maxWidth: 240, alignment: .leading)
        }
        .padding(.leading, 10)
        .padding(.trailing, showsClear ? 4 : 10)
        .frame(height: 30)
        .contentShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(state.isNoProject ? "No project" : "Project: \(state.title)")
    }
}

extension ComposerProjectChip where MenuContent == EmptyView {
    /// Read-only chip for an active thread whose project is already fixed.
    public init(state: ComposerProjectChipState, chipHelp: String? = nil) {
        self.init(readOnly: state, chipHelp: chipHelp)
    }
}

private struct ChipTriggerStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Capsule().fill(configuration.isPressed ? SwftColor.hover : .clear))
            .scaleEffect(SwftMotion.pressScale(isPressed: configuration.isPressed, scale: 0.97, reduceMotion: reduceMotion))
            .animation(SwftMotion.pressAnimation(isPressed: configuration.isPressed, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

private struct ChipClearButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(SwftMotion.pressScale(isPressed: configuration.isPressed, scale: 0.88, reduceMotion: reduceMotion))
            .animation(SwftMotion.pressAnimation(isPressed: configuration.isPressed, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}
