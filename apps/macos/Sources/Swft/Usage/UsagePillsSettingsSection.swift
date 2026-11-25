import SwftDesign
import SwiftUI

/// Reusable Settings → Providers section letting users choose up to 3 providers to pin as sidebar usage pills.
struct UsagePillsSettingsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let candidates = model.usagePillCandidateGroups
        if !candidates.isEmpty {
            let shownIDs = Set(model.visibleUsagePillGroups.map(\.id))

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Usage pills")
                            .font(SwftType.labelStrong)
                            .foregroundStyle(SwftColor.textPrimary)
                        Text("Show up to \(UsagePillsLogic.maxPills) providers in the sidebar footer. Accounts of the same provider share one pill.")
                            .font(SwftType.caption)
                            .foregroundStyle(SwftColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Text("\(shownIDs.count) of \(UsagePillsLogic.maxPills) shown")
                        .font(SwftType.caption)
                        .monospacedDigit()
                        .foregroundStyle(SwftColor.textTertiary)
                        .fixedSize()
                }

                VStack(spacing: 0) {
                    ForEach(Array(candidates.enumerated()), id: \.element.id) { index, group in
                        if index > 0 {
                            Rectangle()
                                .fill(SwftColor.borderSubtle)
                                .frame(height: 1)
                                .padding(.leading, 52)
                        }
                        row(for: group, isChecked: shownIDs.contains(group.id), shownCount: shownIDs.count)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: SwftRadius.l, style: .continuous)
                        .fill(SwftColor.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SwftRadius.l, style: .continuous)
                        .strokeBorder(SwftColor.borderSubtle, lineWidth: 1)
                )
            }
        }
    }

    private func row(for group: UsagePillGroup, isChecked: Bool, shownCount: Int) -> some View {
        let isFull = !isChecked && shownCount >= UsagePillsLogic.maxPills
        let subtitle = rowSubtitle(for: group, isFull: isFull)

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous)
                    .fill(SwftColor.surfaceMuted)
                    .overlay(
                        RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous)
                            .strokeBorder(SwftColor.borderSubtle, lineWidth: 1)
                    )
                ProviderMark(
                    provider: group.primary.driver,
                    acpAgentID: group.primary.acpAgentId,
                    symbol: group.primary.kind.pickerSymbol,
                    monogram: group.label,
                    size: 14
                )
                .foregroundStyle(group.state.isHealthy ? group.primary.kind.tint : SwftColor.textTertiary)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(group.label)
                    .font(SwftType.label)
                    .foregroundStyle(SwftColor.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Toggle(
                isOn: Binding(
                    get: { isChecked },
                    set: { isOn in
                        model.toggleUsagePill(groupID: group.id, isOn: isOn)
                    }
                )
            ) {
                Text("Show \(group.label) usage pill")
            }
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            .disabled(isFull)
            .accessibilityLabel("Show \(group.label) usage pill")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func rowSubtitle(for group: UsagePillGroup, isFull: Bool) -> String? {
        if isFull {
            return "The sidebar shows up to \(UsagePillsLogic.maxPills) pills. Turn one off to show this one."
        }
        if group.accounts.count > 1 {
            let siblings = group.accounts.map(\.entry)
            let names = group.accounts
                .map { UsagePillsLogic.accountSectionHeader(for: $0.entry, siblings: siblings).title }
                .joined(separator: ", ")
            return "\(group.accounts.count) accounts · \(names)"
        }
        switch group.state {
        case .healthy(let primary, _):
            return "\(UsagePillsLogic.remainingPercent(primary))% left"
        case .expired:
            return "Sign-in expired"
        case .notSignedIn:
            return "Not signed in"
        case .unsupported(let reason), .unavailable(let reason):
            return reason
        }
    }
}
