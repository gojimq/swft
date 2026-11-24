import AppKit
import SwiftUI

// Reusable Gemini-styled Settings building blocks: quiet headers, soft grey grouped cards with large radii,
// Google-blue controls, and one-shot springs that respect Reduce Motion.

// MARK: - Navigation Tab Strip

public struct SettingsTabItem<ID: Hashable>: Identifiable {
    public let id: ID
    public let title: String
    public let systemName: String

    public init(id: ID, title: String, systemName: String) {
        self.id = id
        self.title = title
        self.systemName = systemName
    }
}

/// Horizontal pill navigation bar for switching settings sections; the active capsule glides between tabs.
public struct SettingsTabStrip<ID: Hashable>: View {
    let items: [SettingsTabItem<ID>]
    @Binding var selection: ID
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(items: [SettingsTabItem<ID>], selection: Binding<ID>) {
        self.items = items
        self._selection = selection
    }

    public var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 3) {
                ForEach(items) { item in
                    let isSelected = item.id == selection
                    SettingsTabButton(
                        title: item.title,
                        systemName: item.systemName,
                        isSelected: isSelected,
                        namespace: ns
                    ) {
                        guard selection != item.id else { return }
                        withAnimation(SwftMotion.resolve(SwftMotion.glide, reduceMotion: reduceMotion)) {
                            selection = item.id
                        }
                    }
                }
            }
            .padding(4)
            .background(Capsule().fill(SwftColor.surfaceMuted))
            .overlay(Capsule().strokeBorder(SwftColor.borderSubtle))
        }
        .scrollIndicators(.never)
        .fixedSize(horizontal: false, vertical: true)
        .animation(SwftMotion.resolve(SwftMotion.glide, reduceMotion: reduceMotion), value: selection)
    }

    private struct SettingsTabButton: View {
        let title: String
        let systemName: String
        let isSelected: Bool
        let namespace: Namespace.ID
        let action: () -> Void
        @State private var hovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: systemName)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? SwftColor.accent : (hovering ? SwftColor.textPrimary : SwftColor.textTertiary))
                    Text(title)
                        .font(isSelected ? SwftType.labelStrong : SwftType.label)
                        .foregroundStyle(isSelected ? SwftColor.textPrimary : (hovering ? SwftColor.textPrimary : SwftColor.textSecondary))
                        .lineLimit(1)
                }
                .padding(.horizontal, 13)
                .frame(height: 30)
                .background {
                    ZStack {
                        if hovering && !isSelected {
                            Capsule().fill(SwftColor.hover)
                        }
                        if isSelected {
                            Capsule()
                                .fill(SwftColor.surfaceRaised)
                                .overlay(Capsule().strokeBorder(SwftColor.borderSubtle))
                                .shadow(color: SwftColor.shadow.opacity(0.9), radius: 4, y: 1)
                                .matchedGeometryEffect(id: "settings.tab.pill", in: namespace)
                        }
                    }
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: hovering)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        }
    }
}

// MARK: - Section Card & Dividers

/// Soft grey grouped card with a quiet header above and an optional footer note below.
public struct SettingsSectionCard<HeaderAccessory: View, Content: View>: View {
    let title: String?
    let footer: String?
    let headerAccessory: HeaderAccessory
    let content: Content

    public init(
        _ title: String? = nil,
        footer: String? = nil,
        @ViewBuilder headerAccessory: () -> HeaderAccessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.headerAccessory = headerAccessory()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if title != nil || HeaderAccessory.self != EmptyView.self {
                HStack(alignment: .center, spacing: 8) {
                    if let title {
                        Text(title)
                            .font(SwftFonts.flex(12.5, weight: 540))
                            .foregroundStyle(SwftColor.textTertiary)
                    }
                    Spacer(minLength: 8)
                    headerAccessory
                }
                .padding(.horizontal, 6)
            }

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: SwftRadius.xl, style: .continuous).fill(SwftColor.surfaceMuted))
            .overlay(RoundedRectangle(cornerRadius: SwftRadius.xl, style: .continuous).strokeBorder(SwftColor.borderSubtle))

            if let footer, !footer.isEmpty {
                Text(footer)
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
            }
        }
    }
}

extension SettingsSectionCard where HeaderAccessory == EmptyView {
    public init(
        _ title: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title, footer: footer, headerAccessory: { EmptyView() }, content: content)
    }
}

/// Subtle inset hairline separating rows inside a `SettingsSectionCard`.
public struct SettingsRowDivider: View {
    let inset: CGFloat

    public init(inset: CGFloat = 18) {
        self.inset = inset
    }

    public var body: some View {
        Rectangle()
            .fill(SwftColor.borderSubtle)
            .frame(height: 1)
            .padding(.horizontal, inset)
    }
}

// MARK: - Rows

/// Standard two-column (or stacked) setting row with label, optional description, status note, and reset action.
public struct SettingsRow<Control: View>: View {
    let title: String
    let description: String?
    let statusNote: String?
    let statusIsError: Bool
    let isModified: Bool
    let onReset: (() -> Void)?
    let stacked: Bool
    let control: Control

    public init(
        _ title: String,
        description: String? = nil,
        statusNote: String? = nil,
        statusIsError: Bool = false,
        isModified: Bool = false,
        onReset: (() -> Void)? = nil,
        stacked: Bool = false,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.description = description
        self.statusNote = statusNote
        self.statusIsError = statusIsError
        self.isModified = isModified
        self.onReset = onReset
        self.stacked = stacked
        self.control = control()
    }

    public var body: some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        labelStack
                        if isModified, let onReset {
                            resetButton(onReset)
                        }
                    }
                    control
                }
            } else {
                HStack(alignment: .center, spacing: 16) {
                    labelStack
                    Spacer(minLength: 8)
                    HStack(spacing: 8) {
                        if isModified, let onReset {
                            resetButton(onReset)
                        }
                        control
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }

    private func resetButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Reset")
                .font(SwftFonts.flex(11.5, weight: 520))
                .foregroundStyle(SwftColor.textTertiary)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .contentShape(Capsule())
        }
        .buttonStyle(HoverFillStyle(shape: Capsule()))
        .help("Reset \(title) to default")
    }

    private var labelStack: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(SwftType.labelStrong)
                .foregroundStyle(SwftColor.textPrimary)
            if let description, !description.isEmpty {
                Text(description)
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let statusNote, !statusNote.isEmpty {
                Text(statusNote)
                    .font(SwftType.caption)
                    .foregroundStyle(statusIsError ? SwftColor.danger : SwftColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Key-value read-only info row (for About versions, paths, statuses).
public struct SettingsValueRow<Trailing: View>: View {
    let title: String
    let value: String
    let monospaced: Bool
    let trailing: Trailing

    public init(
        _ title: String,
        value: String,
        monospaced: Bool = false,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.value = value
        self.monospaced = monospaced
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(SwftType.labelStrong)
                .foregroundStyle(SwftColor.textPrimary)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 12)
            Text(value)
                .font(monospaced ? SwftType.monoSmall : SwftType.label)
                .foregroundStyle(SwftColor.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            trailing
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }
}

extension SettingsValueRow where Trailing == EmptyView {
    public init(_ title: String, value: String, monospaced: Bool = false) {
        self.init(title, value: value, monospaced: monospaced, trailing: { EmptyView() })
    }
}

// MARK: - Controls

/// Google-blue pill switch with a crisp one-shot spring thumb.
public struct SettingsToggle: View {
    @Binding var isOn: Bool
    let label: String
    var disabled: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(isOn: Binding<Bool>, label: String, disabled: Bool = false) {
        self._isOn = isOn
        self.label = label
        self.disabled = disabled
    }

    public var body: some View {
        Button {
            guard !disabled else { return }
            withAnimation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion)) {
                isOn.toggle()
            }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(trackFill)
                    .frame(width: 40, height: 22)
                    .overlay(
                        Capsule().strokeBorder(isOn ? Color.clear : SwftColor.border, lineWidth: 1)
                    )
                Circle()
                    .fill(thumbFill)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
                    .padding(3)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .onHover { hovering = $0 }
        .animation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion), value: isOn)
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: hovering)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
    }

    private var trackFill: Color {
        if isOn { return SwftColor.accent }
        return hovering ? SwftColor.pressed : SwftColor.surface
    }

    private var thumbFill: Color {
        if isOn {
            return Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return isDark ? NSColor(srgbRed: 0.04, green: 0.14, blue: 0.30, alpha: 1) : .white
            })
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? NSColor(srgbRed: 0.56, green: 0.58, blue: 0.60, alpha: 1) : .white
        })
    }
}

/// Convenience settings row with a trailing `SettingsToggle`.
public struct SettingsToggleRow: View {
    let title: String
    let description: String?
    @Binding var isOn: Bool
    var disabled: Bool
    var isModified: Bool
    var onReset: (() -> Void)?

    public init(
        _ title: String,
        description: String? = nil,
        isOn: Binding<Bool>,
        disabled: Bool = false,
        isModified: Bool = false,
        onReset: (() -> Void)? = nil
    ) {
        self.title = title
        self.description = description
        self._isOn = isOn
        self.disabled = disabled
        self.isModified = isModified
        self.onReset = onReset
    }

    public var body: some View {
        SettingsRow(
            title,
            description: description,
            isModified: isModified,
            onReset: onReset
        ) {
            SettingsToggle(isOn: $isOn, label: title, disabled: disabled)
        }
    }
}

public struct SettingsChoiceOption<Value: Hashable>: Identifiable {
    public let value: Value
    public let label: String
    public let detail: String?

    public var id: Value { value }

    public init(value: Value, label: String, detail: String? = nil) {
        self.value = value
        self.label = label
        self.detail = detail
    }
}

/// Capsule segmented control tailored for settings cards, with a gliding Google-blue active pill.
public struct SettingsSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [SettingsChoiceOption<Value>]
    var disabled: Bool
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        selection: Binding<Value>,
        options: [SettingsChoiceOption<Value>],
        disabled: Bool = false
    ) {
        self._selection = selection
        self.options = options
        self.disabled = disabled
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let selected = option.value == selection
                Button {
                    guard !disabled, selection != option.value else { return }
                    withAnimation(SwftMotion.resolve(SwftMotion.glide, reduceMotion: reduceMotion)) {
                        selection = option.value
                    }
                } label: {
                    Text(option.label)
                        .font(selected ? SwftType.captionStrong : SwftType.caption)
                        .foregroundStyle(selected ? SwftColor.onSend : SwftColor.textSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(SwftColor.accentSoft)
                                    .matchedGeometryEffect(id: "settings.seg", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(SwftColor.surface))
        .overlay(Capsule().strokeBorder(SwftColor.borderSubtle))
        .opacity(disabled ? 0.5 : 1)
        .animation(SwftMotion.resolve(SwftMotion.glide, reduceMotion: reduceMotion), value: selection)
    }
}

/// Styled dropdown trigger pill for native macOS `Menu` pickers inside settings cards.
public struct SettingsMenuTrigger: View {
    let title: String
    var leadingSystemName: String?
    var disabled: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ title: String, systemName: String? = nil, disabled: Bool = false) {
        self.title = title
        self.leadingSystemName = systemName
        self.disabled = disabled
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let leadingSystemName {
                Image(systemName: leadingSystemName)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(SwftColor.textSecondary)
            }
            Text(title)
                .font(SwftType.label)
                .foregroundStyle(SwftColor.textPrimary)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(SwftColor.textTertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hovering && !disabled ? SwftColor.surfaceRaised : SwftColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(hovering && !disabled ? SwftColor.border : SwftColor.borderSubtle)
        )
        .opacity(disabled ? 0.5 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering = $0 }
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: hovering)
    }
}

/// Convenience settings row wrapping a native `Menu` picker styled with `SettingsMenuTrigger`.
public struct SettingsPickerRow<Value: Hashable>: View {
    let title: String
    let description: String?
    let statusNote: String?
    let statusIsError: Bool
    let selection: Value
    let options: [SettingsChoiceOption<Value>]
    var disabled: Bool
    var isModified: Bool
    var onReset: (() -> Void)?
    let onSelect: (Value) -> Void

    public init(
        _ title: String,
        description: String? = nil,
        statusNote: String? = nil,
        statusIsError: Bool = false,
        selection: Value,
        options: [SettingsChoiceOption<Value>],
        disabled: Bool = false,
        isModified: Bool = false,
        onReset: (() -> Void)? = nil,
        onSelect: @escaping (Value) -> Void
    ) {
        self.title = title
        self.description = description
        self.statusNote = statusNote
        self.statusIsError = statusIsError
        self.selection = selection
        self.options = options
        self.disabled = disabled
        self.isModified = isModified
        self.onReset = onReset
        self.onSelect = onSelect
    }

    private var selectedLabel: String {
        options.first(where: { $0.value == selection })?.label ?? ""
    }

    public var body: some View {
        SettingsRow(
            title,
            description: description,
            statusNote: statusNote,
            statusIsError: statusIsError,
            isModified: isModified,
            onReset: onReset
        ) {
            Menu {
                ForEach(options) { option in
                    Button {
                        onSelect(option.value)
                    } label: {
                        if let detail = option.detail {
                            Text("\(option.label) — \(detail)")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                SettingsMenuTrigger(selectedLabel, disabled: disabled)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .disabled(disabled)
            .fixedSize()
        }
    }
}

/// Calm single-line input field for settings cards; commits when pressing Return or losing focus.
public struct SettingsCommitField: View {
    let savedValue: String
    let placeholder: String
    let monospaced: Bool
    let secret: Bool
    let disabled: Bool
    let onCommit: (String) -> Void

    @State private var draft: String
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        value: String,
        placeholder: String = "",
        monospaced: Bool = false,
        secret: Bool = false,
        disabled: Bool = false,
        onCommit: @escaping (String) -> Void
    ) {
        self.savedValue = value
        self.placeholder = placeholder
        self.monospaced = monospaced
        self.secret = secret
        self.disabled = disabled
        self.onCommit = onCommit
        self._draft = State(initialValue: value)
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Group {
            if secret {
                SecureField("", text: $draft, prompt: Text(placeholder).foregroundStyle(SwftColor.placeholder))
            } else {
                TextField("", text: $draft, prompt: Text(placeholder).foregroundStyle(SwftColor.placeholder))
            }
        }
        .textFieldStyle(.plain)
        .font(monospaced ? SwftType.monoSmall : SwftType.label)
        .foregroundStyle(SwftColor.textPrimary)
        .disabled(disabled)
        .focused($focused)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(shape.fill(SwftColor.surface))
        .overlay(shape.strokeBorder(focused ? SwftColor.accent : SwftColor.borderSubtle, lineWidth: focused ? 1.5 : 1))
        .opacity(disabled ? 0.5 : 1)
        .onSubmit { commit() }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
        .onChange(of: savedValue) { _, newValue in
            if !focused { draft = newValue }
        }
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: focused)
    }

    private func commit() {
        if secret {
            guard !draft.isEmpty else { return }
            let value = draft
            draft = ""
            onCommit(value)
        } else if draft != savedValue {
            onCommit(draft)
        }
    }
}

/// Pill action button with four calm styles tailored for Settings.
public struct SettingsPillButton: View {
    public enum Variant {
        case primary
        case secondary
        case quiet
        case destructive
    }

    let title: String
    let systemName: String?
    let variant: Variant
    let isLoading: Bool
    let disabled: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        _ title: String,
        systemName: String? = nil,
        variant: Variant = .secondary,
        isLoading: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemName = systemName
        self.variant = variant
        self.isLoading = isLoading
        self.disabled = disabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 12, height: 12)
                } else if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(variant == .primary ? SwftType.captionStrong : SwftType.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, variant == .quiet ? 10 : 12)
            .frame(height: 28)
            .background(Capsule().fill(background))
            .overlay(Capsule().strokeBorder(borderColor, lineWidth: borderWidth))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled || isLoading)
        .opacity((disabled || isLoading) ? 0.5 : 1)
        .onHover { hovering = $0 }
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: hovering)
    }

    private var foreground: Color {
        switch variant {
        case .primary: SwftColor.onSend
        case .secondary: SwftColor.textPrimary
        case .quiet: hovering ? SwftColor.textPrimary : SwftColor.textSecondary
        case .destructive: SwftColor.danger
        }
    }

    private var background: Color {
        switch variant {
        case .primary: hovering ? SwftColor.sendFill.opacity(0.88) : SwftColor.sendFill
        case .secondary: hovering ? SwftColor.surfaceRaised : SwftColor.surface
        case .quiet: hovering ? SwftColor.hover : .clear
        case .destructive: hovering ? SwftColor.dangerSoft.opacity(0.9) : SwftColor.dangerSoft
        }
    }

    private var borderColor: Color {
        switch variant {
        case .primary, .quiet: .clear
        case .secondary: hovering ? SwftColor.border : SwftColor.borderSubtle
        case .destructive: SwftColor.danger.opacity(0.24)
        }
    }

    private var borderWidth: CGFloat {
        switch variant {
        case .primary, .quiet: 0
        case .secondary, .destructive: 1
        }
    }
}

/// Compact semantic status dot + caption text.
public struct SettingsStatusBadge: View {
    public enum Tone {
        case ready
        case warning
        case error
        case neutral
    }

    let text: String
    let tone: Tone

    public init(_ text: String, tone: Tone = .neutral) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
            Text(text)
                .font(SwftType.caption)
                .foregroundStyle(SwftColor.textSecondary)
                .lineLimit(1)
        }
    }

    private var dotColor: Color {
        switch tone {
        case .ready: SwftColor.success
        case .warning: SwftColor.warning
        case .error: SwftColor.danger
        case .neutral: SwftColor.textTertiary.opacity(0.6)
        }
    }
}

/// Determinate Google-blue progress bar for managed provider runtime downloads.
public struct SettingsProgressBar: View {
    let fraction: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(fraction: Double) {
        self.fraction = min(max(fraction, 0), 1)
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(SwftColor.borderSubtle)
                Capsule()
                    .fill(SwftColor.accent)
                    .frame(width: max(4, geo.size.width * fraction))
            }
        }
        .frame(height: 5)
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: fraction)
    }
}

/// Monospaced command or path box with a one-click Copy button.
public struct SettingsCopyableCode: View {
    let text: String
    let copyLabel: String
    @State private var copied = false

    public init(_ text: String, copyLabel: String = "Copy") {
        self.text = text
        self.copyLabel = copyLabel
    }

    public var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal) {
                Text(text)
                    .font(SwftType.monoSmall)
                    .foregroundStyle(SwftColor.textSecondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
            .scrollIndicators(.never)

            SettingsPillButton(
                copied ? "Copied" : copyLabel,
                systemName: copied ? "checkmark" : "doc.on.doc",
                variant: .quiet
            ) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(1600))
                    copied = false
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(SwftColor.surface))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(SwftColor.borderSubtle))
    }
}

/// Calm inline banner for errors, read-only notices, or hints inside settings.
public struct SettingsBanner: View {
    public enum Tone {
        case info
        case warning
        case error
    }

    let message: String
    let tone: Tone
    let onDismiss: (() -> Void)?

    public init(_ message: String, tone: Tone = .info, onDismiss: (() -> Void)? = nil) {
        self.message = message
        self.tone = tone
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(accent)
            Text(message)
                .font(SwftType.caption)
                .foregroundStyle(SwftColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let onDismiss {
                IconButton("xmark", help: "Dismiss", size: 22, action: onDismiss)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: SwftRadius.l, style: .continuous).fill(background))
        .overlay(RoundedRectangle(cornerRadius: SwftRadius.l, style: .continuous).strokeBorder(border))
    }

    private var symbol: String {
        switch tone {
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "exclamationmark.circle.fill"
        }
    }

    private var accent: Color {
        switch tone {
        case .info: SwftColor.accent
        case .warning: SwftColor.warning
        case .error: SwftColor.danger
        }
    }

    private var background: Color {
        switch tone {
        case .info: SwftColor.accentSoft.opacity(0.45)
        case .warning: SwftColor.warningSoft
        case .error: SwftColor.dangerSoft
        }
    }

    private var border: Color {
        switch tone {
        case .info: SwftColor.accent.opacity(0.2)
        case .warning: SwftColor.warningBorder
        case .error: SwftColor.danger.opacity(0.25)
        }
    }
}

/// Calm grouped empty or placeholder card with an icon tile, title, and description.
public struct SettingsEmptyCard: View {
    let systemName: String
    let title: String
    let description: String

    public init(systemName: String, title: String, description: String) {
        self.systemName = systemName
        self.title = title
        self.description = description
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(SwftColor.surface)
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(SwftColor.borderSubtle))
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(SwftColor.accent)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(SwftType.headline)
                    .foregroundStyle(SwftColor.textPrimary)
                Text(description)
                    .font(SwftType.label)
                    .foregroundStyle(SwftColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: SwftRadius.xl, style: .continuous).fill(SwftColor.surfaceMuted))
        .overlay(RoundedRectangle(cornerRadius: SwftRadius.xl, style: .continuous).strokeBorder(SwftColor.borderSubtle))
    }
}
