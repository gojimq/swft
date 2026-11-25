import AppKit
import SwiftUI

// Dumb building blocks for the composer's model picker. The app composes them; nothing here knows about providers.

/// Text that swaps cleanly when its value changes: the new string replaces the old one in place and rises in, so two
/// values never overlap (an interpolating crossfade would show both mid-swap).
public struct SwapText: View {
    let value: String

    public init(_ value: String) { self.value = value }

    public var body: some View {
        Text(value).lineLimit(1).swftSwap(on: value)
    }
}

extension View {
    /// Swaps this view out whenever `key` changes: the old content leaves at once and the new content fades and rises
    /// in on its own animation, so old and new never show together. The layout around it is left to the caller.
    public func swftSwap<Key: Hashable & Sendable>(on key: Key) -> some View {
        modifier(SwapOnChange(key: key))
    }
}

/// Visual state for a single-view in-place content swap (`swftSwap(on:)`).
public struct SwapVisualState: Equatable, Sendable {
    public var opacity: Double
    public var offsetY: CGFloat

    public init(opacity: Double, offsetY: CGFloat) {
        self.opacity = opacity
        self.offsetY = offsetY
    }

    public static let settled = SwapVisualState(opacity: 1, offsetY: 0)
}

/// Pure motion parameters for single-view in-place content swaps (`swftSwap(on:)`).
public enum SwapMotion {
    public static let riseOffset: CGFloat = 4
    public static let duration: TimeInterval = 0.11
    public static let reduceMotionDuration: TimeInterval = 0.1

    public static func startState(reduceMotion: Bool) -> SwapVisualState {
        SwapVisualState(opacity: 0, offsetY: reduceMotion ? 0 : riseOffset)
    }

    public static func duration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? reduceMotionDuration : duration
    }
}

private struct SwapOnChange<Key: Hashable & Sendable>: ViewModifier {
    let key: Key
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let start = SwapMotion.startState(reduceMotion: reduceMotion)
        let duration = SwapMotion.duration(reduceMotion: reduceMotion)
        // Single-view keyframe animation (no `.id(key)` / `ZStack` transition siblings) so rapid
        // back-and-forth key changes can never leave overlapping copies stacked on top of each other.
        content
            .transaction(value: key) { $0.animation = nil }
            .keyframeAnimator(initialValue: SwapVisualState.settled, trigger: key) { view, state in
                view
                    .opacity(state.opacity)
                    .offset(y: state.offsetY)
            } keyframes: { _ in
                KeyframeTrack(\.opacity) {
                    MoveKeyframe(start.opacity)
                    CubicKeyframe(SwapVisualState.settled.opacity, duration: duration)
                }
                KeyframeTrack(\.offsetY) {
                    MoveKeyframe(start.offsetY)
                    if reduceMotion {
                        LinearKeyframe(SwapVisualState.settled.offsetY, duration: duration)
                    } else {
                        CubicKeyframe(SwapVisualState.settled.offsetY, duration: duration)
                    }
                }
            }
    }
}

/// A provider identity mark: renders the real provider vector icon, with a neutral fallback.
public struct ProviderMark: View {
    let provider: String?
    let acpAgentID: String?
    let iconURL: String?
    let symbol: String?
    let monogram: String
    let size: CGFloat
    let renderingMode: ProviderIconRenderingMode

    public init(symbol: String?, monogram: String, size: CGFloat = 14) {
        self.provider = nil
        self.acpAgentID = nil
        self.iconURL = nil
        self.symbol = symbol
        self.monogram = monogram
        self.size = size
        self.renderingMode = .original
    }

    public init(
        provider: String?,
        acpAgentID: String? = nil,
        iconURL: String? = nil,
        symbol: String? = nil,
        monogram: String = "",
        size: CGFloat = 14,
        renderingMode: ProviderIconRenderingMode = .original
    ) {
        self.provider = provider
        self.acpAgentID = acpAgentID
        self.iconURL = iconURL
        self.symbol = symbol
        self.monogram = monogram
        self.size = size
        self.renderingMode = renderingMode
    }

    public var body: some View {
        let resolved = ProviderIconKind.resolve(
            driver: provider,
            acpAgentID: acpAgentID,
            iconURL: iconURL,
            name: monogram,
            legacySymbol: symbol
        )
        ProviderIcon(resolved: resolved, size: size, renderingMode: renderingMode)
    }
}

/// Tiny identity dot for a provider instance's accent color.
public struct AccentDot: View {
    let color: Color

    public init(_ color: Color) { self.color = color }

    public var body: some View {
        Circle().fill(color)
            .frame(width: 6, height: 6)
            .accessibilityHidden(true)
    }
}

/// The rounded floating menu panel the picker lives in: frosted interactive Liquid Glass.
public struct PickerPanelSurface<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: SwftRadius.menu, style: .continuous)
        content
            .clipShape(shape)
            .swftPickerGlass(in: shape)
    }
}

/// Translucent hairline between the picker's sections.
public struct PickerDivider: View {
    public init() {}

    public var body: some View {
        Rectangle().fill(PickerPolish.divider).frame(height: 1)
    }
}

/// "Search models" field at the top of the panel.
public struct PickerSearchField: View {
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    let placeholder: String

    public init(text: Binding<String>, focus: FocusState<Bool>.Binding, placeholder: String = "Search models") {
        self._text = text
        self.focus = focus
        self.placeholder = placeholder
    }

    public var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(SwftColor.textTertiary)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(SwftColor.placeholder))
                .textFieldStyle(.plain)
                .font(SwftType.label)
                .foregroundStyle(SwftColor.textPrimary)
                .focused(focus)
                // Pin the line box so AppKit's field editor taking over on focus can't nudge the baseline.
                .frame(height: 18)
                .accessibilityLabel(placeholder)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }
}

// MARK: - Rail

public struct PickerRailItem: Identifiable, Hashable {
    public let id: String
    public var provider: String?
    public var acpAgentID: String?
    public var iconURL: String?
    public var symbol: String?
    public var monogram: String
    public var tint: Color
    public var accent: Color?
    public var tooltip: String
    public var inUse: Bool

    public init(id: String, symbol: String?, monogram: String, tint: Color, accent: Color?, tooltip: String, inUse: Bool) {
        self.id = id
        self.provider = nil
        self.acpAgentID = nil
        self.iconURL = nil
        self.symbol = symbol
        self.monogram = monogram
        self.tint = tint
        self.accent = accent
        self.tooltip = tooltip
        self.inUse = inUse
    }

    public init(
        id: String,
        provider: String?,
        acpAgentID: String? = nil,
        iconURL: String? = nil,
        symbol: String? = nil,
        monogram: String,
        tint: Color,
        accent: Color?,
        tooltip: String,
        inUse: Bool
    ) {
        self.id = id
        self.provider = provider
        self.acpAgentID = acpAgentID
        self.iconURL = iconURL
        self.symbol = symbol
        self.monogram = monogram
        self.tint = tint
        self.accent = accent
        self.tooltip = tooltip
        self.inUse = inUse
    }
}

/// Vertical provider tabs with one selection tile that glides between them.
public struct PickerRail: View {
    let items: [PickerRailItem]
    let selectedID: String?
    let keyboardFocused: Bool
    let onSelect: (String) -> Void
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(items: [PickerRailItem], selectedID: String?, keyboardFocused: Bool, onSelect: @escaping (String) -> Void) {
        self.items = items
        self.selectedID = selectedID
        self.keyboardFocused = keyboardFocused
        self.onSelect = onSelect
    }

    public var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 3) {
                ForEach(items) { item in
                    RailTab(item: item, selected: item.id == selectedID, keyboardFocused: keyboardFocused && item.id == selectedID, namespace: ns) {
                        onSelect(item.id)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.never)
        .frame(width: 36)
        .animation(SwftMotion.resolve(SwftMotion.glide, reduceMotion: reduceMotion), value: selectedID)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Providers")
    }

    private struct RailTab: View {
        let item: PickerRailItem
        let selected: Bool
        let keyboardFocused: Bool
        let namespace: Namespace.ID
        let action: () -> Void
        @State private var hovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
            Button(action: action) {
                let resolved = ProviderIconKind.resolve(
                    driver: item.provider,
                    acpAgentID: item.acpAgentID,
                    iconURL: item.iconURL,
                    name: item.monogram,
                    legacySymbol: item.symbol
                )
                ProviderIcon(resolved: resolved, size: 15)
                    .foregroundStyle(selected ? SwftColor.accent : (hovering ? SwftColor.textPrimary : SwftColor.textTertiary))
                    .opacity(selected || hovering || !resolved.hasBrandColor ? 1 : 0.78)
                    .frame(width: 36, height: 36)
                    .background {
                        ZStack {
                            if hovering && !selected { shape.fill(PickerPolish.hoverFill) }
                            if selected {
                                shape.fill(PickerPolish.railSelection).matchedGeometryEffect(id: "rail.selection", in: namespace)
                            }
                        }
                    }
                    .overlay { if keyboardFocused { shape.strokeBorder(SwftColor.accent.opacity(0.55), lineWidth: 1.5) } }
                    .overlay(alignment: .bottomTrailing) {
                        if let accent = item.accent { AccentDot(accent).padding(6) }
                    }
                    .overlay(alignment: .topTrailing) {
                        if item.inUse {
                            Circle().fill(SwftColor.accent).frame(width: 5, height: 5).padding(5)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(shape)
            }
            .buttonStyle(TactilePressStyle(shape: shape, pressScale: PickerPolish.tabPressScale))
            .onHover { hovering = $0 }
            .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: hovering)
            .help(item.tooltip)
            .accessibilityLabel(item.inUse ? "\(item.tooltip), in use" : item.tooltip)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
        }
    }
}

// MARK: - Rows

/// One model in the list. The thread's current model is bold with a Google-blue check.
public struct PickerModelRow: View {
    let title: String
    let isCurrent: Bool
    let isNew: Bool
    let isHighlighted: Bool
    let leading: PickerRailItem?
    let detail: String?
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(title: String, isCurrent: Bool, isNew: Bool, isHighlighted: Bool, leading: PickerRailItem? = nil, detail: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.isCurrent = isCurrent
        self.isNew = isNew
        self.isHighlighted = isHighlighted
        self.leading = leading
        self.detail = detail
        self.action = action
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Button(action: action) {
            HStack(spacing: 8) {
                if let leading {
                    ProviderMark(provider: leading.provider, acpAgentID: leading.acpAgentID, iconURL: leading.iconURL, symbol: leading.symbol, monogram: leading.monogram, size: 13)
                        .foregroundStyle(SwftColor.textTertiary)
                        .frame(width: 16)
                    if let accent = leading.accent { AccentDot(accent) }
                }
                Text(title)
                    .font(isCurrent ? SwftType.labelStrong : SwftType.label)
                    .foregroundStyle(SwftColor.textPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)
                if isNew { NewBadge() }
                if let detail {
                    Text(detail).font(SwftType.caption).foregroundStyle(SwftColor.textTertiary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(SwftColor.accent)
                        .transition(.swftPop(reduceMotion: reduceMotion, scale: 0.5))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(shape.fill(isHighlighted ? PickerPolish.highlightFill : (hovering ? PickerPolish.hoverFill : .clear)))
            .contentShape(shape)
        }
        .buttonStyle(TactilePressStyle(shape: shape))
        .onHover { hovering = $0 }
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: hovering)
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: isHighlighted)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }
}

public struct NewBadge: View {
    public init() {}

    public var body: some View {
        Text("New")
            .font(SwftFonts.flex(10.5, weight: 600))
            .foregroundStyle(SwftColor.onSend)
            .padding(.horizontal, 6)
            .frame(height: 17)
            .background(Capsule().fill(SwftColor.accentSoft))
    }
}

/// Provider name (with accent dot) and a trailing detail such as the account or why it is unavailable.
public struct PickerProviderHeader: View {
    let title: String
    let accent: Color?
    let detail: String?
    let tooltip: String?

    public init(title: String, accent: Color?, detail: String?, tooltip: String?) {
        self.title = title
        self.accent = accent
        self.detail = detail
        self.tooltip = tooltip
    }

    public var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                if let accent { AccentDot(accent) }
                Text(title).font(SwftType.labelStrong).foregroundStyle(SwftColor.textPrimary).lineLimit(1)
            }
            .help(tooltip ?? "")
            Spacer(minLength: 8)
            if let detail {
                Text(detail).font(SwftType.caption).foregroundStyle(SwftColor.textTertiary).lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
    }
}

/// Sub-provider section label (e.g. "OpenRouter") with an optional unavailable reason.
public struct PickerSectionHeader: View {
    let title: String
    let trailing: String?

    public init(title: String, trailing: String?) {
        self.title = title
        self.trailing = trailing
    }

    public var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                if ProviderIconKind.resolveSubProvider(title) != nil {
                    SubProviderIcon(name: title, size: 11.5)
                } else {
                    Image(systemName: "square.stack.3d.up").font(.system(size: 10, weight: .medium))
                }
                Text(title).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let trailing { Text(trailing).lineLimit(1) }
        }
        .font(SwftType.caption)
        .foregroundStyle(SwftColor.textTertiary)
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}

/// Quiet note in the panel (reasons, empty states).
public struct PickerNote: View {
    let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .font(SwftType.caption)
            .foregroundStyle(SwftColor.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
    }
}

/// Filled pill for the panel's one action ("Sign in in Settings").
public struct PickerActionButton: View {
    let title: String
    let isHighlighted: Bool
    let action: () -> Void

    public init(_ title: String, isHighlighted: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isHighlighted = isHighlighted
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(SwftType.captionStrong)
                .foregroundStyle(SwftColor.onSend)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().fill(SwftColor.sendFill))
                .overlay { if isHighlighted { Capsule().strokeBorder(SwftColor.accent, lineWidth: 1.5).padding(-3) } }
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
}

// MARK: - Account switcher

public struct PickerAccountItem: Identifiable, Hashable {
    public let id: String
    public var label: String
    public var accent: Color?
    public var tooltip: String
    public var inUse: Bool

    public init(id: String, label: String, accent: Color?, tooltip: String, inUse: Bool) {
        self.id = id
        self.label = label
        self.accent = accent
        self.tooltip = tooltip
        self.inUse = inUse
    }
}

/// Segmented pill switching between a provider's accounts; the raised segment glides.
public struct PickerAccountSwitcher: View {
    let items: [PickerAccountItem]
    let selectedID: String?
    let keyboardFocused: Bool
    let onSelect: (String) -> Void
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(items: [PickerAccountItem], selectedID: String?, keyboardFocused: Bool, onSelect: @escaping (String) -> Void) {
        self.items = items
        self.selectedID = selectedID
        self.keyboardFocused = keyboardFocused
        self.onSelect = onSelect
    }

    public var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(items) { item in
                    let selected = item.id == selectedID
                    Button { onSelect(item.id) } label: {
                        HStack(spacing: 6) {
                            if let accent = item.accent { AccentDot(accent) }
                            Text(item.label).lineLimit(1)
                        }
                        .font(selected ? SwftType.captionStrong : SwftType.caption)
                        .foregroundStyle(selected ? SwftColor.textPrimary : SwftColor.textTertiary)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: 120)
                        .frame(height: 26)
                        .background {
                            if selected {
                                Capsule().fill(PickerPolish.switcherThumb)
                                    .shadow(color: SwftColor.shadow, radius: 1.5, y: 0.5)
                                    .overlay(Capsule().strokeBorder(keyboardFocused ? SwftColor.accent.opacity(0.6) : PickerPolish.divider, lineWidth: keyboardFocused ? 1.5 : 0.5))
                                    .matchedGeometryEffect(id: "account.selection", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(TactilePressStyle(shape: Capsule(), pressScale: PickerPolish.segmentPressScale, pressedFill: selected ? .clear : PickerPolish.hoverFill))
                    .help(item.tooltip)
                    .accessibilityLabel(item.inUse ? "\(item.tooltip), in use" : item.tooltip)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
            .padding(2)
            .background(Capsule().fill(PickerPolish.switcherTrack))
        }
        .scrollIndicators(.never)
        .fixedSize(horizontal: false, vertical: true)
        .animation(SwftMotion.resolve(SwftMotion.glide, reduceMotion: reduceMotion), value: selectedID)
    }
}

// MARK: - Thinking

/// "Thinking" stepped slider over a model's real levels; the thumb and fill ease to each stop.
public struct ThinkingSlider: View {
    let levels: [String]
    let index: Int
    let keyboardFocused: Bool
    let onChange: (Int) -> Void
    @State private var dragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let thumb: CGFloat = 16

    public init(levels: [String], index: Int, keyboardFocused: Bool, onChange: @escaping (Int) -> Void) {
        self.levels = levels
        self.index = index
        self.keyboardFocused = keyboardFocused
        self.onChange = onChange
    }

    public var body: some View {
        let last = max(levels.count - 1, 1)
        let clamped = min(max(index, 0), levels.count - 1)
        VStack(spacing: 6) {
            HStack {
                Text("Thinking").foregroundStyle(SwftColor.textSecondary)
                Spacer()
                SwapText(levels.indices.contains(clamped) ? levels[clamped] : "").foregroundStyle(SwftColor.textPrimary)
            }
            .font(SwftType.caption)
            .transaction(value: clamped) { $0.animation = nil }

            GeometryReader { geo in
                let travel = geo.size.width - thumb
                let x = travel * CGFloat(clamped) / CGFloat(last)
                ZStack(alignment: .leading) {
                    Capsule().fill(PickerPolish.sliderTrack).frame(height: 6)
                    HStack(spacing: 0) {
                        ForEach(levels.indices, id: \.self) { stop in
                            if stop > 0 { Spacer(minLength: 0) }
                            Circle().fill(stop <= clamped ? Color.clear : SwftColor.textTertiary.opacity(0.55)).frame(width: 4, height: 4)
                        }
                    }
                    .padding(.horizontal, thumb / 2 - 2)
                    Capsule().fill(SwftColor.accent).frame(width: x + thumb, height: 6)
                    Circle()
                        .fill(Color.white)
                        .frame(width: thumb, height: thumb)
                        .shadow(color: .black.opacity(0.22), radius: 2.5, y: 1)
                        .overlay(Circle().strokeBorder(SwftColor.accent, lineWidth: 2))
                        .overlay { if keyboardFocused { Circle().strokeBorder(SwftColor.accent.opacity(0.35), lineWidth: 3).padding(-4) } }
                        .scaleEffect(dragging && !reduceMotion ? 1.15 : 1)
                        .offset(x: x)
                }
                .frame(height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragging = true
                            let step = Int(((value.location.x - thumb / 2) / max(travel, 1) * CGFloat(last)).rounded())
                            let next = min(max(step, 0), levels.count - 1)
                            if next != clamped { onChange(next) }
                        }
                        .onEnded { _ in dragging = false }
                )
            }
            .frame(height: 22)
            // Levels are steps, so even a drag jumps; keep thumb and fill tight so rapid scrubbing never trails.
            .animation(SwftMotion.resolve(SwftMotion.snap, reduceMotion: reduceMotion), value: clamped)
            .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: dragging)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .accessibilityElement()
        .accessibilityLabel("Thinking level")
        .accessibilityValue(levels.indices.contains(clamped) ? levels[clamped] : "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if clamped < levels.count - 1 { onChange(clamped + 1) }
            case .decrement: if clamped > 0 { onChange(clamped - 1) }
            @unknown default: break
            }
        }
    }
}

// MARK: - Trigger

/// The composer button that opens the picker: provider mark, optional account disambiguator, model, effort, chevron.
public struct ModelPickerTrigger: View {
    let mark: PickerRailItem?
    let disambiguator: String?
    let model: String
    let effort: String?
    let isOpen: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(mark: PickerRailItem?, disambiguator: String?, model: String, effort: String?, isOpen: Bool, action: @escaping () -> Void) {
        self.mark = mark
        self.disambiguator = disambiguator
        self.model = model
        self.effort = effort
        self.isOpen = isOpen
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                // Keep the provider mark and model name steady when only the thinking effort changes;
                // when the model itself changes, both segments swap in lockstep so effort never slides across it.
                modelIdentity
                    .fixedSize()
                    .swftSwap(on: modelSwapKey)
                if let effort {
                    Text(effort)
                        .foregroundStyle(SwftColor.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                        .swftSwap(on: swapKey)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(SwftColor.textTertiary)
                    .rotationEffect(.degrees(isOpen && !reduceMotion ? 180 : 0))
            }
            .font(SwftType.label)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .contentShape(Capsule())
        }
        .buttonStyle(HoverFillStyle(shape: Capsule(), selected: isOpen))
        .animation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion), value: isOpen)
        // A new model or effort resizes the pill at once; only the swapped label segment rises in.
        .transaction(value: swapKey) { $0.animation = nil }
        .fixedSize()
    }

    private var modelSwapKey: String {
        Self.modelSwapKey(markID: mark?.id, disambiguator: disambiguator, model: model)
    }

    private var swapKey: String {
        Self.swapKey(markID: mark?.id, disambiguator: disambiguator, model: model, effort: effort)
    }

    nonisolated public static func modelSwapKey(markID: String?, disambiguator: String?, model: String) -> String {
        [markID ?? "", disambiguator ?? "", model].joined(separator: "\u{1F}")
    }

    nonisolated public static func swapKey(markID: String?, disambiguator: String?, model: String, effort: String?) -> String {
        [markID ?? "", disambiguator ?? "", model, effort ?? ""].joined(separator: "\u{1F}")
    }

    private var modelIdentity: some View {
        HStack(spacing: 5) {
            if let mark {
                ProviderMark(provider: mark.provider, acpAgentID: mark.acpAgentID, iconURL: mark.iconURL, symbol: mark.symbol, monogram: mark.monogram, size: 13)
                    .foregroundStyle(SwftColor.textSecondary)
                if let accent = mark.accent { AccentDot(accent) }
            }
            if let disambiguator {
                Text(disambiguator).foregroundStyle(SwftColor.textTertiary).lineLimit(1).frame(maxWidth: 96)
            }
            Text(model).foregroundStyle(SwftColor.textPrimary).lineLimit(1)
        }
    }
}

extension Color {
    /// `#rrggbb` → Color; nil for anything else.
    public init?(swftHex hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self = Color(nsColor: NSColor(hex: value))
    }
}
