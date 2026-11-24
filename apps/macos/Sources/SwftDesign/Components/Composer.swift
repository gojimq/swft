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
        VStack(alignment: .leading, spacing: 8) {
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(SwftColor.placeholder), axis: .vertical)
                .textFieldStyle(.plain)
                .font(SwftType.composer)
                .foregroundStyle(SwftColor.textPrimary)
                .lineLimit(1...10)
                .focused($focused)
                .onSubmit { if canSend { onSend() } }
                .padding(.horizontal, 6)
                .padding(.top, 2)

            HStack(spacing: 6) {
                IconButton("plus", help: "Attach files", size: 30)
                leading
                Spacer(minLength: 8)
                trailing
                IconButton("mic", help: "Dictate", size: 30)
                SendButton(state: isBusy ? .stop : (canSend ? .ready : .idle), action: isBusy ? (onStop ?? onSend) : onSend)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.top, 14)
        .padding(.bottom, 9)
        .background {
            RoundedRectangle(cornerRadius: SwftRadius.composer, style: .continuous)
                .fill(SwftColor.surface)
                .shadow(color: SwftColor.shadow, radius: 14, y: 3)
        }
        .overlay {
            RoundedRectangle(cornerRadius: SwftRadius.composer, style: .continuous)
                .strokeBorder(focused ? SwftColor.border : SwftColor.borderSubtle)
        }
        .contentShape(RoundedRectangle(cornerRadius: SwftRadius.composer, style: .continuous))
        .onTapGesture { focused = true }
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

    public init(state: State, action: @escaping () -> Void) {
        self.state = state
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: state == .stop ? "stop.fill" : "arrow.up")
                .font(.system(size: state == .stop ? 11 : 14, weight: .semibold))
                .foregroundStyle(state == .idle ? SwftColor.onSend.opacity(0.55) : SwftColor.onSend)
                .frame(width: 32, height: 32)
                .background(Circle().fill(state == .idle ? SwftColor.sendFillIdle : SwftColor.sendFill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(state == .idle)
        .animation(SwftMotion.quick, value: state)
        .help(state == .stop ? "Stop" : "Send")
        .keyboardShortcut(.return, modifiers: .command)
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

/// "Model  Effort" picker label (model in primary ink, effort in tertiary) that opens a menu.
public struct ModelPicker<MenuContent: View>: View {
    let model: String
    let effort: String?
    let menu: MenuContent

    public init(model: String, effort: String?, @ViewBuilder menu: () -> MenuContent) {
        self.model = model
        self.effort = effort
        self.menu = menu()
    }

    public var body: some View {
        Menu {
            menu
        } label: {
            HStack(spacing: 5) {
                Text(model).foregroundStyle(SwftColor.textPrimary)
                if let effort {
                    Text(effort).foregroundStyle(SwftColor.textTertiary)
                }
            }
            .font(SwftType.label)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(HoverFillStyle(shape: Capsule()))
        .menuIndicator(.hidden)
        .fixedSize()
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
                    withAnimation(SwftMotion.quick) { selection = option.value }
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
                    .font(SwftType.body)
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
