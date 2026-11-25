import SwiftUI

/// Attachment wiring for `PillComposer`; `.none` hides the tray and leaves `+` inert.
public struct ComposerAttachmentHandlers {
    public var items: [ComposerAttachmentItem]
    public var onAdd: (() -> Void)?
    public var onRemove: (String) -> Void
    /// Handles files or images dropped on the composer; returns whether the drop was accepted.
    public var onDrop: (([NSItemProvider]) -> Bool)?

    public init(
        items: [ComposerAttachmentItem],
        onAdd: (() -> Void)? = nil,
        onRemove: @escaping (String) -> Void = { _ in },
        onDrop: (([NSItemProvider]) -> Bool)? = nil
    ) {
        self.items = items
        self.onAdd = onAdd
        self.onRemove = onRemove
        self.onDrop = onDrop
    }

    public static var none: ComposerAttachmentHandlers { ComposerAttachmentHandlers(items: []) }

    /// Sendable with text or at least one uploaded attachment, and never while an upload is still in flight.
    public static func canSend(text: String, items: [ComposerAttachmentItem]) -> Bool {
        if items.contains(where: { $0.status == .uploading }) { return false }
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText || items.contains { $0.status == .ready }
    }
}

/// The pill composer: staged attachments, a multi-line field, then a row of controls (+, accessories … picker, mic, send).
public struct PillComposer<Leading: View, Trailing: View>: View {
    @Binding var text: String
    let placeholder: String
    var isBusy: Bool
    let attachments: ComposerAttachmentHandlers
    let onSend: () -> Void
    let onStop: (() -> Void)?
    let leading: Leading
    let trailing: Trailing
    @FocusState private var focused: Bool
    @State private var isDropTargeted = false
    /// The tray keeps showing its last items while it rolls closed (they fade out at once on send).
    @State private var trayItems: [ComposerAttachmentItem]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        text: Binding<String>,
        placeholder: String,
        isBusy: Bool = false,
        attachments: ComposerAttachmentHandlers = .none,
        onSend: @escaping () -> Void,
        onStop: (() -> Void)? = nil,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self._text = text
        self.placeholder = placeholder
        self.isBusy = isBusy
        self.attachments = attachments
        self.onSend = onSend
        self.onStop = onStop
        self.leading = leading()
        self.trailing = trailing()
        self._trayItems = State(initialValue: attachments.items)
    }

    private var canSend: Bool { ComposerAttachmentHandlers.canSend(text: text, items: attachments.items) }
    private var hasAttachments: Bool { !attachments.items.isEmpty }

    public var body: some View {
        // No stack spacing: a collapsed tray is zero-height, so each gap lives with the view below it.
        VStack(alignment: .leading, spacing: 0) {
            // Rolls open above the field when something is attached and back up once the tray empties.
            SwftDisclosure(isExpanded: hasAttachments) {
                ComposerAttachmentTray(items: hasAttachments ? attachments.items : trayItems, onRemove: attachments.onRemove)
                    .opacity(hasAttachments ? 1 : 0)
                    .padding(.horizontal, ComposerPolish.textHorizontalInset)
                    .padding(.top, ComposerPolish.textTopInset)
                    .padding(.bottom, 10)
            }

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
                IconButton("plus", help: "Attach files", size: ComposerPolish.controlButtonSize, tint: SwftColor.textPrimary) {
                    attachments.onAdd?()
                }
                leading
                Spacer(minLength: 8)
                trailing
                IconButton("mic", help: "Dictate", size: ComposerPolish.controlButtonSize, tint: SwftColor.textPrimary)
                SendButton(state: isBusy ? .stop : (canSend ? .ready : .idle), action: isBusy ? (onStop ?? onSend) : onSend)
            }
            .padding(.top, ComposerPolish.verticalSpacing)
        }
        .padding(.leading, ComposerPolish.contentLeadingPadding)
        .padding(.trailing, ComposerPolish.contentTrailingPadding)
        .padding(.top, ComposerPolish.contentTopPadding)
        .padding(.bottom, ComposerPolish.contentBottomPadding)
        .frame(minHeight: ComposerPolish.minHeight, alignment: .top)
        .swftComposerGlass(in: shape)
        .overlay {
            // Quiet drop target: an accent ring and the faintest wash while files hover over the composer.
            shape.strokeBorder(SwftColor.accent.opacity(isDropTargeted ? 0.75 : 0), lineWidth: 1.5)
                .background(shape.fill(SwftColor.accent.opacity(isDropTargeted ? 0.04 : 0)))
                .allowsHitTesting(false)
        }
        .contentShape(shape)
        .onTapGesture { focused = true }
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
            guard let onDrop = attachments.onDrop else { return false }
            focused = true
            return onDrop(providers)
        }
        .onChange(of: attachments.items) { _, items in
            if !items.isEmpty { trayItems = items }
        }
        // Grows/shrinks smoothly as lines are added or removed.
        .animation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion), value: text.filter(\.isNewline).count)
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: isDropTargeted)
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: hasAttachments)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ComposerPolish.cornerRadius, style: .continuous)
    }
}

extension PillComposer where Leading == EmptyView {
    public init(text: Binding<String>, placeholder: String, isBusy: Bool = false, attachments: ComposerAttachmentHandlers = .none, onSend: @escaping () -> Void, onStop: (() -> Void)? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.init(text: text, placeholder: placeholder, isBusy: isBusy, attachments: attachments, onSend: onSend, onStop: onStop, leading: { EmptyView() }, trailing: trailing)
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

/// Plain style that presses down a little and springs back on release.
struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.9

    func makeBody(configuration: Configuration) -> some View {
        PressScaleBody(configuration: configuration, scale: scale)
    }

    private struct PressScaleBody: View {
        let configuration: Configuration
        let scale: CGFloat
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let pressed = configuration.isPressed
            configuration.label
                .scaleEffect(SwftMotion.pressScale(isPressed: pressed, scale: scale, reduceMotion: reduceMotion))
                .opacity(pressed && reduceMotion ? 0.75 : 1)
                .animation(SwftMotion.pressAnimation(isPressed: pressed, reduceMotion: reduceMotion), value: pressed)
        }
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
