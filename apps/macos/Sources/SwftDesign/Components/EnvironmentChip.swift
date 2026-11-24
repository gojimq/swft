import SwiftUI

/// Connection health displayed quietly on an `EnvironmentChip`.
public enum EnvironmentChipStatus: Equatable, Sendable {
    case connected
    case connecting
    case offline
}

/// Plain value describing one selectable environment inside `EnvironmentChip`.
public struct EnvironmentChipItem: Identifiable, Hashable, Sendable {
    public let id: String
    public var label: String
    public var machineSymbol: String
    public var status: EnvironmentChipStatus
    public var isLocal: Bool
    public var detail: String?

    public init(
        id: String,
        label: String,
        machineSymbol: String,
        status: EnvironmentChipStatus = .connected,
        isLocal: Bool = false,
        detail: String? = nil
    ) {
        self.id = id
        self.label = label
        self.machineSymbol = machineSymbol
        self.status = status
        self.isLocal = isLocal
        self.detail = detail
    }
}

/// Composer accessory chip showing the target execution environment (machine icon + name)
/// with a menu of available environments.
public struct EnvironmentChip: View {
    let items: [EnvironmentChipItem]
    let selectedID: String?
    var isLocked: Bool
    let onSelect: (String) -> Void
    let onManageConnections: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        items: [EnvironmentChipItem],
        selectedID: String?,
        isLocked: Bool = false,
        onSelect: @escaping (String) -> Void,
        onManageConnections: (() -> Void)? = nil
    ) {
        self.items = items
        self.selectedID = selectedID
        self.isLocked = isLocked
        self.onSelect = onSelect
        self.onManageConnections = onManageConnections
    }

    private var selected: EnvironmentChipItem? {
        if let selectedID, let match = items.first(where: { $0.id == selectedID }) {
            return match
        }
        return items.first
    }

    public var body: some View {
        if let selected {
            if isLocked {
                lockedLabel(for: selected)
            } else {
                interactiveMenu(for: selected)
            }
        }
    }

    private func lockedLabel(for item: EnvironmentChipItem) -> some View {
        HStack(spacing: 5) {
            Image(systemName: item.machineSymbol)
                .font(.system(size: 11.5, weight: .medium))
            Text(item.label)
                .font(SwftType.label)
                .lineLimit(1)
            statusIndicator(for: item.status)
        }
        .foregroundStyle(SwftColor.textTertiary)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .help("Running on \(item.label). Environment cannot be changed after a thread starts.")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Running on \(item.label)")
    }

    private func interactiveMenu(for item: EnvironmentChipItem) -> some View {
        Menu {
            Section("Run on") {
                ForEach(items) { env in
                    Button {
                        onSelect(env.id)
                    } label: {
                        HStack {
                            Label(menuRowTitle(for: env), systemImage: env.machineSymbol)
                            if env.id == item.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            if let onManageConnections {
                Divider()
                Button {
                    onManageConnections()
                } label: {
                    Label("Add another machine…", systemImage: "plus")
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: item.machineSymbol)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(item.status == .connected ? SwftColor.textSecondary : statusTint(for: item.status))
                SwapText(item.label)
                    .font(SwftType.label)
                    .foregroundStyle(SwftColor.textPrimary)
                    .frame(maxWidth: 140, alignment: .leading)
                statusIndicator(for: item.status)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(SwftColor.textTertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .contentShape(Capsule())
            .accessibilityElement(children: .combine)
        }
        .menuStyle(.button)
        .buttonStyle(HoverFillStyle(shape: Capsule()))
        .menuIndicator(.hidden)
        .fixedSize()
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: item.status)
        .help(helpText(for: item))
        .accessibilityLabel(accessibilityText(for: item))
    }

    @ViewBuilder
    private func statusIndicator(for status: EnvironmentChipStatus) -> some View {
        switch status {
        case .connected:
            EmptyView()
        case .connecting:
            Circle()
                .fill(SwftColor.warning)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
        case .offline:
            Circle()
                .fill(SwftColor.danger)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
        }
    }

    private func statusTint(for status: EnvironmentChipStatus) -> Color {
        switch status {
        case .connected: SwftColor.textSecondary
        case .connecting: SwftColor.warning
        case .offline: SwftColor.danger
        }
    }

    private func menuRowTitle(for item: EnvironmentChipItem) -> String {
        switch item.status {
        case .connected:
            return item.isLocal ? "\(item.label) (This Mac)" : item.label
        case .connecting:
            return "\(item.label) — Connecting…"
        case .offline:
            return "\(item.label) — Offline"
        }
    }

    private func helpText(for item: EnvironmentChipItem) -> String {
        switch item.status {
        case .connected: "Run new thread on \(item.label)"
        case .connecting: "\(item.label) (connecting…)"
        case .offline: "\(item.label) (offline)"
        }
    }

    private func accessibilityText(for item: EnvironmentChipItem) -> String {
        switch item.status {
        case .connected: "Environment: \(item.label)"
        case .connecting: "Environment: \(item.label), connecting"
        case .offline: "Environment: \(item.label), offline"
        }
    }
}
