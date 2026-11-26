import AppKit
import SwftDesign
import SwiftUI

/// Floating Liquid Glass slash-command menu anchored to the composer.
struct SlashCommandPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let composerFrame: CGRect
    let opensBelow: Bool

    @State private var panelFrame: CGRect = .zero

    static let minWidth: CGFloat = 380
    static let maxWidth: CGFloat = 520
    private static let maxListHeight: CGFloat = 296

    private var resolvedWidth: CGFloat {
        guard composerFrame.width > 0 else { return 460 }
        return min(Self.maxWidth, max(Self.minWidth, composerFrame.width - 16))
    }

    var body: some View {
        let items = model.slashCommandItems
        let sections = model.slashCommandSections
        let highlightedID = model.highlightedSlashCommandID
        let isSearching = !(model.activeSlashCommandTrigger?.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        PickerPanelSurface {
            VStack(alignment: .leading, spacing: 0) {
                if items.isEmpty {
                    emptyState
                } else {
                    commandList(
                        items: items,
                        sections: sections,
                        highlightedID: highlightedID,
                        showSourceBadge: isSearching
                    )
                    PickerDivider()
                    footerHint
                }
            }
        }
        .frame(width: resolvedWidth)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { panelFrame = $0 }
        .background(
            SlashCommandEventMonitor(
                isInside: { point in panelFrame.contains(point) || composerFrame.contains(point) },
                onKey: { key in
                    model.handleSlashCommandKey(key)
                },
                onOutsideClick: {
                    withAnimation(SwftMotion.resolve(SwftMotion.popover, reduceMotion: reduceMotion)) {
                        model.dismissSlashCommandMenu()
                    }
                }
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Slash commands")
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "slash.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SwftColor.textTertiary)
            Text("No matching command.")
                .font(SwftType.caption)
                .foregroundStyle(SwftColor.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func commandList(
        items: [SlashCommandItem],
        sections: [SlashCommandSection],
        highlightedID: String?,
        showSourceBadge: Bool
    ) -> some View {
        let estimatedHeight = Self.estimatedContentHeight(sections: sections)
        let needsScroll = estimatedHeight > Self.maxListHeight

        return ScrollViewReader { proxy in
            Group {
                if needsScroll {
                    ScrollView {
                        rowsContent(sections: sections, highlightedID: highlightedID, showSourceBadge: showSourceBadge)
                    }
                    .scrollIndicators(.never)
                    .frame(height: Self.maxListHeight)
                } else {
                    rowsContent(sections: sections, highlightedID: highlightedID, showSourceBadge: showSourceBadge)
                }
            }
            .onChange(of: highlightedID) { _, nextID in
                guard let nextID else { return }
                withAnimation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion)) {
                    proxy.scrollTo(nextID, anchor: .center)
                }
            }
        }
    }

    private func rowsContent(
        sections: [SlashCommandSection],
        highlightedID: String?,
        showSourceBadge: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(sections) { section in
                if let title = section.title {
                    PickerSectionHeader(title: title, trailing: nil)
                }
                ForEach(section.items) { item in
                    SlashCommandRow(
                        item: item,
                        isHighlighted: item.id == highlightedID,
                        showSourceBadge: showSourceBadge || item.group == .skill,
                        onHover: { hovering in
                            if hovering, model.slashCommandHighlightedID != item.id {
                                model.slashCommandHighlightedID = item.id
                            }
                        },
                        onSelect: {
                            withAnimation(SwftMotion.resolve(SwftMotion.popover, reduceMotion: reduceMotion)) {
                                model.selectSlashCommand(item)
                            }
                        }
                    )
                    .id(item.id)
                }
            }
        }
        .padding(6)
    }

    private var footerHint: some View {
        HStack(spacing: 12) {
            hintChip(keys: "↑↓", label: "Navigate")
            hintChip(keys: "⇥ / ↵", label: "Select")
            hintChip(keys: "esc", label: "Dismiss")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func hintChip(keys: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(SwftType.monoSmall)
                .foregroundStyle(SwftColor.textSecondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(PickerPolish.hoverFill))
            Text(label)
                .font(SwftType.caption)
                .foregroundStyle(SwftColor.textTertiary)
        }
    }

    private static func estimatedContentHeight(sections: [SlashCommandSection]) -> CGFloat {
        let headerCount = sections.filter { $0.title != nil }.count
        let rowCount = sections.reduce(0) { $0 + $1.items.count }
        return CGFloat(headerCount) * 26 + CGFloat(rowCount) * 36 + 14
    }
}

// MARK: - Command Row

private struct SlashCommandRow: View {
    let item: SlashCommandItem
    let isHighlighted: Bool
    let showSourceBadge: Bool
    let onHover: (Bool) -> Void
    let onSelect: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Button(action: onSelect) {
            HStack(spacing: 8) {
                commandLabel
                    .layoutPriority(1)

                if let hint = item.inputHint {
                    Text(hint)
                        .font(SwftType.monoSmall)
                        .foregroundStyle(SwftColor.textTertiary)
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(PickerPolish.hoverFill)
                        )
                }

                Text(item.description)
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showSourceBadge {
                    sourceBadge
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                shape.fill(
                    isHighlighted
                        ? PickerPolish.highlightFill
                        : (isHovering ? PickerPolish.hoverFill : .clear)
                )
            )
            .contentShape(shape)
        }
        .buttonStyle(TactilePressStyle(shape: shape))
        .onHover { hovering in
            isHovering = hovering
            onHover(hovering)
        }
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: isHighlighted)
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: isHovering)
        .help(item.description)
        .accessibilityLabel("\(item.label), \(item.description)")
        .accessibilityAddTraits(isHighlighted ? [.isSelected] : [])
    }

    @ViewBuilder
    private var commandLabel: some View {
        if case .skill(let skill) = item.kind {
            HStack(spacing: 0) {
                Text("/skill:")
                    .font(SwftType.monoSmall)
                    .foregroundStyle(SwftColor.textTertiary)
                Text(skill.resolvedDisplayName)
                    .font(SwftType.labelStrong)
                    .foregroundStyle(SwftColor.textPrimary)
            }
            .lineLimit(1)
        } else {
            Text(item.label)
                .font(SwftType.labelStrong)
                .foregroundStyle(SwftColor.textPrimary)
                .lineLimit(1)
        }
    }

    private var sourceBadge: some View {
        HStack(spacing: 3) {
            if case .skill(let kind) = item.source {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 9.5, weight: .medium))
            }
            Text(item.source.badgeLabel)
                .font(SwftType.micro)
        }
        .foregroundStyle(SwftColor.textTertiary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(PickerPolish.hoverFill))
        .fixedSize()
    }
}

// MARK: - Fresh Session Banner (/clear)

/// Subtle dismissible pill shown above the composer when `/clear` has armed a fresh session for the next turn.
struct FreshSessionBanner: View {
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(SwftColor.accent)
            Text("Next message starts a fresh session")
                .font(SwftType.captionStrong)
                .foregroundStyle(SwftColor.textPrimary)
            Text("Earlier messages stay visible")
                .font(SwftType.caption)
                .foregroundStyle(SwftColor.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button("Undo", action: onUndo)
                .font(SwftType.captionStrong)
                .foregroundStyle(SwftColor.accent)
                .buttonStyle(.plain)
                .help("Keep the current session")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous)
                .fill(SwftColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous)
                .strokeBorder(SwftColor.border)
        )
    }
}

// MARK: - Window-Level Keyboard & Click Handling

private struct SlashCommandEventMonitor: NSViewRepresentable {
    let isInside: (CGPoint) -> Bool
    let onKey: (SlashCommandKey) -> Bool
    let onOutsideClick: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.parent = self
        context.coordinator.install(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator {
        var parent: SlashCommandEventMonitor?
        private var monitors: [Any] = []
        private weak var view: NSView?

        func install(for view: NSView) {
            self.view = view
            monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let window = event.window.map(ObjectIdentifier.init)
                let keyCode = event.keyCode
                let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
                let handled = MainActor.assumeIsolated {
                    self?.handleKey(keyCode, flags: flags, window: window) ?? false
                }
                return handled ? nil : event
            } as Any)
            monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                let window = event.window.map(ObjectIdentifier.init)
                let height = event.window?.contentView?.bounds.height ?? 0
                let point = CGPoint(x: event.locationInWindow.x, y: height - event.locationInWindow.y)
                MainActor.assumeIsolated { self?.handleClick(at: point, window: window) }
                return event
            } as Any)
        }

        func uninstall() {
            monitors.forEach(NSEvent.removeMonitor)
            monitors.removeAll()
        }

        private var windowID: ObjectIdentifier? { view?.window.map(ObjectIdentifier.init) }

        private func handleKey(_ keyCode: UInt16, flags: NSEvent.ModifierFlags, window: ObjectIdentifier?) -> Bool {
            guard window != nil, window == windowID, let parent else { return false }
            // Never swallow shortcuts with Cmd/Ctrl/Option, or Shift+Return / Shift+Tab.
            guard flags.isEmpty else { return false }
            let key: SlashCommandKey? = switch keyCode {
            case 126: .up
            case 125: .down
            case 48: .tab
            case 36, 76: .enter
            case 53: .escape
            default: nil
            }
            guard let key else { return false }
            return parent.onKey(key)
        }

        private func handleClick(at point: CGPoint, window: ObjectIdentifier?) {
            guard let parent else { return }
            if window != windowID || !parent.isInside(point) { parent.onOutsideClick() }
        }
    }
}

// MARK: - NSTextView Cursor Sync & Placement

/// Observes the composer field editor's selection range and applies pending caret placement after command insertion.
struct ComposerCursorObserver: NSViewRepresentable {
    let text: String
    let pendingCursorUTF16: Int?
    let cursorRequestID: UInt64
    let onCursorChange: (Int) -> Void
    let onAppliedPendingCursor: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.parent = self
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyPendingCursorIfNeeded(
            requestID: cursorRequestID,
            targetUTF16: pendingCursorUTF16,
            expectedText: text
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ComposerCursorObserver?
        private weak var hostView: NSView?
        private var isObserving = false
        private var lastAppliedRequestID: UInt64 = 0

        func attach(to view: NSView) {
            self.hostView = view
            guard !isObserving else { return }
            isObserving = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleTextViewSelectionDidChange(_:)),
                name: NSTextView.didChangeSelectionNotification,
                object: nil
            )
        }

        func detach() {
            if isObserving {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSTextView.didChangeSelectionNotification,
                    object: nil
                )
                isObserving = false
            }
        }

        @objc private func handleTextViewSelectionDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            handleSelectionChange(
                location: textView.selectedRange().location,
                text: textView.string,
                windowID: textView.window.map(ObjectIdentifier.init)
            )
        }

        private func handleSelectionChange(location: Int, text: String, windowID: ObjectIdentifier?) {
            guard let parent,
                  let hostWindowID = hostView?.window.map(ObjectIdentifier.init),
                  hostWindowID == windowID,
                  text == parent.text
            else { return }
            parent.onCursorChange(location)
        }

        func applyPendingCursorIfNeeded(requestID: UInt64, targetUTF16: Int?, expectedText: String) {
            guard requestID != lastAppliedRequestID, let targetUTF16 else { return }
            lastAppliedRequestID = requestID
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let window = self.hostView?.window,
                      let textView = window.firstResponder as? NSTextView,
                      textView.string == expectedText
                else {
                    self?.parent?.onAppliedPendingCursor()
                    return
                }
                let clamped = max(0, min((textView.string as NSString).length, targetUTF16))
                textView.setSelectedRange(NSRange(location: clamped, length: 0))
                self.parent?.onAppliedPendingCursor()
            }
        }
    }
}
