import SwiftUI

/// One rendered quota window row inside the Liquid Glass breakdown card.
public struct UsageBreakdownWindowRow: Identifiable, Equatable, Sendable {
    public let id: String
    public var label: String
    public var remainingPercent: Int
    public var paceRemainingPercent: Int?
    public var resetCountdown: String?

    public init(
        id: String,
        label: String,
        remainingPercent: Int,
        paceRemainingPercent: Int? = nil,
        resetCountdown: String? = nil
    ) {
        self.id = id
        self.label = label
        self.remainingPercent = remainingPercent
        self.paceRemainingPercent = paceRemainingPercent
        self.resetCountdown = resetCountdown
    }
}

/// Grouped rows under an optional model family subheader (account-wide windows have `family == nil`).
public struct UsageBreakdownWindowGroup: Identifiable, Equatable, Sendable {
    public var id: String { family ?? "__account__" }
    public var family: String?
    public var rows: [UsageBreakdownWindowRow]

    public init(family: String?, rows: [UsageBreakdownWindowRow]) {
        self.family = family
        self.rows = rows
    }
}

/// One account section inside the breakdown card.
public struct UsageBreakdownAccountSection: Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var detail: String?
    public var accentColor: Color?
    public var isHealthy: Bool
    public var isExpired: Bool
    public var isRenewing: Bool
    public var statusMessage: String?
    public var errorMessage: String?
    public var windowGroups: [UsageBreakdownWindowGroup]
    public var historicalGroups: [UsageBreakdownWindowGroup]

    public init(
        id: String,
        title: String,
        detail: String? = nil,
        accentColor: Color? = nil,
        isHealthy: Bool,
        isExpired: Bool = false,
        isRenewing: Bool = false,
        statusMessage: String? = nil,
        errorMessage: String? = nil,
        windowGroups: [UsageBreakdownWindowGroup] = [],
        historicalGroups: [UsageBreakdownWindowGroup] = []
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.accentColor = accentColor
        self.isHealthy = isHealthy
        self.isExpired = isExpired
        self.isRenewing = isRenewing
        self.statusMessage = statusMessage
        self.errorMessage = errorMessage
        self.windowGroups = windowGroups
        self.historicalGroups = historicalGroups
    }
}

/// Explicit pacing summary shown in the breakdown card footer.
public struct UsageBreakdownPaceFooter: Equatable, Sendable {
    public var tone: UsagePillPaceTone
    public var isDepleted: Bool
    public var text: String

    public init(tone: UsagePillPaceTone, isDepleted: Bool = false, text: String) {
        self.tone = tone
        self.isDepleted = isDepleted
        self.text = text
    }
}

/// Pure view model for the floating Liquid Glass usage breakdown card.
public struct UsageBreakdownCardModel: Equatable, Sendable {
    public var id: String
    public var providerName: String
    public var providerSymbol: String?
    public var providerTint: Color
    public var headerDetail: String?
    public var isHealthy: Bool
    public var accounts: [UsageBreakdownAccountSection]
    public var paceFooter: UsageBreakdownPaceFooter?
    public var actionHint: String
    public var actionHintShowsRefreshIcon: Bool

    public init(
        id: String,
        providerName: String,
        providerSymbol: String?,
        providerTint: Color,
        headerDetail: String? = nil,
        isHealthy: Bool,
        accounts: [UsageBreakdownAccountSection],
        paceFooter: UsageBreakdownPaceFooter? = nil,
        actionHint: String,
        actionHintShowsRefreshIcon: Bool = false
    ) {
        self.id = id
        self.providerName = providerName
        self.providerSymbol = providerSymbol
        self.providerTint = providerTint
        self.headerDetail = headerDetail
        self.isHealthy = isHealthy
        self.accounts = accounts
        self.paceFooter = paceFooter
        self.actionHint = actionHint
        self.actionHintShowsRefreshIcon = actionHintShowsRefreshIcon
    }
}

/// Floating Liquid Glass breakdown popover displaying per-account quota windows, linear pace bars, and status footer.
public struct UsageBreakdownCard: View {
    let model: UsageBreakdownCardModel
    let onOpenAccount: (String) -> Void
    let onRefreshAccount: (String) -> Void

    public init(
        _ model: UsageBreakdownCardModel,
        onOpenAccount: @escaping (String) -> Void = { _ in },
        onRefreshAccount: @escaping (String) -> Void = { _ in }
    ) {
        self.model = model
        self.onOpenAccount = onOpenAccount
        self.onRefreshAccount = onRefreshAccount
    }

    private var isMultiAccount: Bool { model.accounts.count > 1 }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isMultiAccount {
                hairline.padding(.top, 9)
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.accounts.enumerated()), id: \.element.id) { index, account in
                            if index > 0 {
                                hairline.padding(.vertical, 8)
                            }
                            multiAccountSection(account)
                        }
                    }
                    .padding(.vertical, 9)
                }
                .scrollIndicators(.automatic)
                .frame(maxHeight: 280)
                .fixedSize(horizontal: false, vertical: true)
            } else if let account = model.accounts.first {
                singleAccountBody(account)
                    .padding(.top, 10)
            }

            footer
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(width: 260)
        .swftUsagePopoverGlass(cornerRadius: 18)
    }

    private var header: some View {
        HStack(spacing: 6) {
            ProviderMark(
                symbol: model.providerSymbol,
                monogram: model.providerName,
                size: 13.5
            )
            .foregroundStyle(model.isHealthy ? model.providerTint : SwftColor.textSecondary.opacity(0.6))

            Text(model.providerName)
                .font(SwftType.labelStrong)
                .foregroundStyle(SwftColor.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let detail = model.headerDetail {
                Text(detail)
                    .font(SwftType.caption)
                    .monospacedDigit()
                    .foregroundStyle(SwftColor.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    @ViewBuilder
    private func singleAccountBody(_ account: UsageBreakdownAccountSection) -> some View {
        if account.isHealthy {
            UsageWindowRowsGrid(groups: account.windowGroups)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                accountStatusLine(account)
                if !account.historicalGroups.isEmpty {
                    UsageWindowRowsGrid(groups: account.historicalGroups)
                        .opacity(0.55)
                }
                if let error = account.errorMessage {
                    accountErrorBlock(error, accountID: account.id)
                }
            }
        }
    }

    private func multiAccountSection(_ account: UsageBreakdownAccountSection) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Button {
                    onOpenAccount(account.id)
                } label: {
                    HStack(spacing: 5) {
                        if let accent = account.accentColor {
                            AccentDot(accent)
                        }
                        Text(account.title)
                            .font(SwftType.captionStrong)
                            .foregroundStyle(account.isHealthy ? SwftColor.textPrimary : SwftColor.textSecondary)
                            .lineLimit(1)
                        if let detail = account.detail {
                            Text("· \(detail)")
                                .font(SwftFonts.flex(11, weight: 420))
                                .foregroundStyle(SwftColor.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)

                if account.isExpired {
                    Button {
                        onRefreshAccount(account.id)
                    } label: {
                        HStack(spacing: 3) {
                            if account.isRenewing {
                                ProgressView()
                                    .controlSize(.mini)
                                    .scaleEffect(0.7)
                                    .frame(width: 10, height: 10)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 9.5, weight: .semibold))
                            }
                            Text(account.isRenewing ? "Refreshing…" : "Refresh")
                                .font(SwftFonts.flex(11, weight: 520))
                        }
                        .foregroundStyle(SwftColor.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(SwftColor.hover))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(account.isRenewing)
                }
            }

            if account.isHealthy {
                UsageWindowRowsGrid(groups: account.windowGroups)
            } else {
                accountStatusLine(account)
                if !account.historicalGroups.isEmpty {
                    UsageWindowRowsGrid(groups: account.historicalGroups)
                        .opacity(0.55)
                }
                if let error = account.errorMessage {
                    accountErrorBlock(error, accountID: account.id)
                }
            }
        }
    }

    @ViewBuilder
    private func accountStatusLine(_ account: UsageBreakdownAccountSection) -> some View {
        HStack(spacing: 6) {
            if account.isExpired && account.isRenewing {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.75)
                    .frame(width: 12, height: 12)
                Text("Refreshing sign-in…")
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.textSecondary)
            } else if let statusMessage = account.statusMessage {
                Text(statusMessage)
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func accountErrorBlock(_ message: String, accountID: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message)
                .font(SwftFonts.flex(11, weight: 420))
                .foregroundStyle(SwftColor.danger)
                .fixedSize(horizontal: false, vertical: true)
            Button("Settings → Providers") {
                onOpenAccount(accountID)
            }
            .buttonStyle(.plain)
            .font(SwftFonts.flex(11, weight: 520))
            .foregroundStyle(SwftColor.accent)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            hairline.padding(.top, isMultiAccount ? 2 : 10).padding(.bottom, 4)

            if let pace = model.paceFooter {
                HStack(spacing: 5) {
                    Circle()
                        .fill(paceDotColor(pace))
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(pace.text)
                        .font(SwftFonts.flex(11.5, weight: 520))
                        .monospacedDigit()
                        .foregroundStyle(pace.isDepleted ? SwftColor.danger : SwftColor.textPrimary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 4) {
                if model.actionHintShowsRefreshIcon {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(SwftColor.textSecondary)
                }
                Text(model.actionHint)
                    .font(SwftFonts.flex(11, weight: 420))
                    .foregroundStyle(SwftColor.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    private func paceDotColor(_ pace: UsageBreakdownPaceFooter) -> Color {
        if pace.isDepleted { return SwftColor.danger }
        switch pace.tone {
        case .ahead: return SwftColor.warning
        case .on: return SwftColor.accent
        case .under: return SwftColor.success
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(SwftColor.borderSubtle)
            .frame(height: 1)
    }
}

/// Aligned window rows (`[label] [linear meter with vertical pace tick] [78%] [2h 14m]`).
public struct UsageWindowRowsGrid: View {
    let groups: [UsageBreakdownWindowGroup]

    public init(groups: [UsageBreakdownWindowGroup]) {
        self.groups = groups
    }

    private var hasAnyReset: Bool {
        groups.contains { group in
            group.rows.contains { $0.resetCountdown != nil }
        }
    }

    public var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                if let family = group.family {
                    GridRow {
                        Text(family)
                            .font(SwftFonts.flex(10.5, weight: 560))
                            .foregroundStyle(SwftColor.textTertiary)
                            .lineLimit(1)
                            .padding(.top, index > 0 ? 4 : 0)
                            .gridCellColumns(hasAnyReset ? 4 : 3)
                    }
                }
                ForEach(group.rows) { row in
                    let depleted = row.remainingPercent <= 10
                    GridRow(alignment: .center) {
                        Text(row.label)
                            .font(SwftFonts.flex(11.5, weight: 440))
                            .foregroundStyle(SwftColor.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(minWidth: 46, maxWidth: 74, alignment: .leading)

                        UsageLinearMeterBar(
                            remainingPercent: row.remainingPercent,
                            paceRemainingPercent: row.paceRemainingPercent
                        )
                        .frame(minWidth: 52, maxWidth: .infinity)
                        .gridCellUnsizedAxes(.vertical)

                        Text("\(row.remainingPercent)%")
                            .font(SwftFonts.flex(11.5, weight: 600))
                            .monospacedDigit()
                            .foregroundStyle(depleted ? SwftColor.danger : SwftColor.textPrimary)
                            .lineLimit(1)
                            .fixedSize()
                            .gridColumnAlignment(.trailing)

                        if hasAnyReset {
                            Text(row.resetCountdown ?? "")
                                .font(SwftFonts.flex(11, weight: 420))
                                .monospacedDigit()
                                .foregroundStyle(SwftColor.textTertiary)
                                .lineLimit(1)
                                .fixedSize()
                                .gridColumnAlignment(.trailing)
                        }
                    }
                }
            }
        }
    }
}

/// Compact linear quota bar with an overlaid vertical pace tick.
public struct UsageLinearMeterBar: View {
    let remainingPercent: Int
    let paceRemainingPercent: Int?

    public init(remainingPercent: Int, paceRemainingPercent: Int? = nil) {
        self.remainingPercent = remainingPercent
        self.paceRemainingPercent = paceRemainingPercent
    }

    public var body: some View {
        let clamped = max(0, min(100, remainingPercent))
        let depleted = clamped <= 10

        GeometryReader { geo in
            let width = geo.size.width
            let fillWidth: CGFloat = clamped == 0 ? 0 : max(4, width * CGFloat(clamped) / 100.0)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(SwftUsageColor.meterTrack)
                    .frame(height: 4)

                if fillWidth > 0 {
                    Capsule()
                        .fill(depleted ? SwftColor.danger : SwftUsageColor.meterFill)
                        .frame(width: fillWidth, height: 4)
                }

                if let paceRemainingPercent {
                    let clampedPace = max(0, min(100, paceRemainingPercent))
                    let rawX = width * CGFloat(clampedPace) / 100.0
                    let tickX = min(max(rawX, 1), max(1, width - 1))

                    Capsule()
                        .fill(SwftUsageColor.meterTick)
                        .frame(width: 1.5, height: 10)
                        .position(x: tickX, y: geo.size.height / 2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}
