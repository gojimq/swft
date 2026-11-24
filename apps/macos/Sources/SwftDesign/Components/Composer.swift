import SwiftUI

/// The pill composer: multi-line field above a row of controls (+, accessories … picker, mic, send).
public struct PillComposer<Leading: View, Trailing: View>: View {
    @Binding var text: String
    let placeholder: String
    var isBusy: Bool
    let onSend: () -> Void
    let onStop: (() -> Void)?
    let leading: Leading
    let trailing: Trailing
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(text: Binding<String>, placeholder: String, isBusy: Bool = false, onSend: @escaping () -> Void, onStop: (() -> Void)? = nil, @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self._text = text
        self.placeholder = placeholder
        self.isBusy = isBusy
        self.onSend = onSend
        self.onStop = onStop
        self.leading = leading()
        self.trailing = trailing()
    }

    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    public var body: some View {
        VStack(alignment: .leading, spacing: ComposerPolish.verticalSpacing) {
            TextField(
                "",
                text: $text,
                prompt: Text(placeholder)
                    .font(ComposerPolish.placeholderFont)
                    .foregroundStyle(ComposerPolish.placeholderColor),
                axis: .vertical
            )
                .textFieldStyle(.plain)
                .font(ComposerPolish.inputFont)
                .foregroundStyle(SwftColor.textPrimary)
                .lineLimit(1...10)
                .focused($focused)
                .onSubmit { if canSend { onSend() } }
                .padding(.horizontal, ComposerPolish.textHorizontalInset)
                .padding(.top, ComposerPolish.textTopInset)

            HStack(spacing: ComposerPolish.controlsSpacing) {
                IconButton("plus", help: "Attach files", size: ComposerPolish.controlButtonSize, tint: SwftColor.textPrimary)
                leading
                Spacer(minLength: 8)
                trailing
                IconButton("mic", help: "Dictate", size: ComposerPolish.controlButtonSize, tint: SwftColor.textPrimary)
                SendButton(state: isBusy ? .stop : (canSend ? .ready : .idle), action: isBusy ? (onStop ?? onSend) : onSend)
            }
        }
        .padding(.leading, ComposerPolish.contentLeadingPadding)
        .padding(.trailing, ComposerPolish.contentTrailingPadding)
        .padding(.top, ComposerPolish.contentTopPadding)
        .padding(.bottom, ComposerPolish.contentBottomPadding)
        .frame(minHeight: ComposerPolish.minHeight, alignment: .top)
        .swftComposerGlass(in: shape)
        .contentShape(shape)
        .onTapGesture { focused = true }
        // Grows/shrinks smoothly as lines are added or removed.
        .animation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion), value: text.filter(\.isNewline).count)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ComposerPolish.cornerRadius, style: .continuous)
    }
}

extension PillComposer where Leading == EmptyView {
    public init(text: Binding<String>, placeholder: String, isBusy: Bool = false, onSend: @escaping () -> Void, onStop: (() -> Void)? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.init(text: text, placeholder: placeholder, isBusy: isBusy, onSend: onSend, onStop: onStop, leading: { EmptyView() }, trailing: trailing)
    }
}

/// Circular send / stop button.
public struct SendButton: View {
    public enum State { case idle, ready, stop }
    let state: State
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(state: State, action: @escaping () -> Void) {
        self.state = state
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: state == .stop ? "stop.fill" : "arrow.up")
                .font(.system(size: state == .stop ? 10.5 : 13, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(ComposerPolish.sendIconColor(for: state))
                .frame(width: ComposerPolish.sendButtonSize, height: ComposerPolish.sendButtonSize)
                .background(Circle().fill(ComposerPolish.sendFill(for: state)))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(state == .idle)
        .animation(SwftMotion.resolve(SwftMotion.pop, reduceMotion: reduceMotion), value: state)
        .help(state == .stop ? "Stop" : "Send")
        .keyboardShortcut(.return, modifiers: .command)
    }
}

/// Plain style that springs down a little while pressed.
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(SwftMotion.spring, value: configuration.isPressed)
    }
}

/// Small capsule chip for composer context (project / branch).
public struct ComposerChip: View {
    let title: String
    let systemName: String
    let action: () -> Void

    public init(_ title: String, systemName: String, action: @escaping () -> Void = {}) {
        self.title = title
        self.systemName = systemName
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemName).font(.system(size: 12, weight: .medium))
                Text(title).font(SwftType.label)
            }
            .foregroundStyle(SwftColor.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .contentShape(Capsule())
        }
        .buttonStyle(HoverFillStyle(shape: Capsule()))
    }
}

/// Two-or-more segment capsule toggle (Chat / Task).
public struct SegmentedToggle<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    @Namespace private var ns

    public init(selection: Binding<Value>, options: [(value: Value, title: String)]) {
        self._selection = selection
        self.options = options
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    withAnimation(SwftMotion.glide) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(selected ? SwftType.labelStrong : SwftType.label)
                        .foregroundStyle(selected ? SwftColor.textPrimary : SwftColor.textTertiary)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background {
                            if selected {
                                Capsule().fill(SwftColor.surfaceMuted).matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(SwftColor.surface))
        .overlay(Capsule().strokeBorder(SwftColor.borderSubtle))
        .shadow(color: SwftColor.shadow, radius: 8, y: 1)
    }
}

/// Starter prompt row under the empty-state composer.
public struct SuggestionRow: View {
    let title: String
    let systemName: String
    let action: () -> Void

    public init(_ title: String, systemName: String, action: @escaping () -> Void = {}) {
        self.title = title
        self.systemName = systemName
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(SwftColor.textSecondary)
                    .frame(width: 18)
                Text(title)
                    .font(SwftType.suggestion)
                    .foregroundStyle(SwftColor.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .contentShape(Capsule())
        }
        .buttonStyle(HoverFillStyle(shape: Capsule()))
    }
}
