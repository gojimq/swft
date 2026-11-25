import SwiftUI

/// Visual status for a tonal fuel pill's pacing tick.
public enum UsagePillPaceTone: Equatable, Sendable, Hashable {
    case ahead
    case on
    case under
}

/// Pure view model for one sidebar Tonal Fuel Pill.
public struct TonalFuelPillModel: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case healthy(
            remainingPercent: Int,
            paceRemainingPercent: Int?,
            paceTone: UsagePillPaceTone?,
            secondaryRemainingPercent: Int?
        )
        case expired(isRenewing: Bool)
        case notSignedIn
        case unavailable
    }

    public var id: String
    public var providerName: String
    public var providerDriver: String?
    public var providerAcpAgentID: String?
    public var providerSymbol: String?
    public var providerTint: Color
    public var accountCount: Int
    public var status: Status
    public var accessibilityLabel: String

    public init(
        id: String,
        providerName: String,
        providerDriver: String? = nil,
        providerAcpAgentID: String? = nil,
        providerSymbol: String?,
        providerTint: Color,
        accountCount: Int = 1,
        status: Status,
        accessibilityLabel: String
    ) {
        self.id = id
        self.providerName = providerName
        self.providerDriver = providerDriver
        self.providerAcpAgentID = providerAcpAgentID
        self.providerSymbol = providerSymbol
        self.providerTint = providerTint
        self.accountCount = accountCount
        self.status = status
        self.accessibilityLabel = accessibilityLabel
    }
}

/// Compact 30pt Gemini-style tonal fuel gauge pill with inline pacing tick and optional 2pt secondary bar.
public struct TonalFuelPill: View {
    let model: TonalFuelPillModel
    var isPopoverOpen: Bool
    let onHoverChange: (Bool) -> Void
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        _ model: TonalFuelPillModel,
        isPopoverOpen: Bool = false,
        onHoverChange: @escaping (Bool) -> Void = { _ in },
        action: @escaping () -> Void = {}
    ) {
        self.model = model
        self.isPopoverOpen = isPopoverOpen
        self.onHoverChange = onHoverChange
        self.action = action
    }

    private var isActive: Bool { isHovering || isPopoverOpen }

    private var isDepleted: Bool {
        if case .healthy(let remaining, _, _, _) = model.status {
            return remaining <= 10
        }
        return false
    }

    private var isExpired: Bool {
        if case .expired = model.status { return true }
        return false
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                pillBackground
                pillForeground
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .clipShape(Capsule())
            .overlay { pillBorder }
            .contentShape(Capsule())
        }
        .buttonStyle(FuelPillButtonStyle(reduceMotion: reduceMotion))
        .onHover { hovering in
            isHovering = hovering
            onHoverChange(hovering)
        }
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: isActive)
        .accessibilityLabel(model.accessibilityLabel)
    }

    @ViewBuilder
    private var pillBackground: some View {
        switch model.status {
        case .healthy(let remaining, let paceRemaining, let paceTone, let secondaryRemaining):
            GeometryReader { geo in
                let width = geo.size.width
                let clamped = max(0, min(100, remaining))
                let fillWidth: CGFloat = clamped == 0 ? 0 : max(6, width * CGFloat(clamped) / 100.0)
                let fillColor: Color = if isDepleted {
                    isActive ? SwftUsageColor.fuelFillDepletedHover : SwftUsageColor.fuelFillDepleted
                } else {
                    isActive ? SwftUsageColor.fuelFillHover : SwftUsageColor.fuelFill
                }

                ZStack(alignment: .leading) {
                    Capsule().fill(isDepleted ? SwftUsageColor.pillTrackDepleted : SwftUsageColor.pillTrack)

                    if fillWidth > 0 {
                        Rectangle()
                            .fill(fillColor)
                            .frame(width: fillWidth)
                            .animation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion), value: clamped)
                    }

                    if let paceRemaining {
                        let clampedPace = max(0, min(100, paceRemaining))
                        let rawX = width * CGFloat(clampedPace) / 100.0
                        let tickX = min(max(rawX, 9), max(9, width - 9))
                        let tickColor: Color = if isDepleted {
                            SwftUsageColor.paceTickDepleted
                        } else if paceTone == .ahead {
                            SwftUsageColor.paceTickAhead
                        } else {
                            SwftUsageColor.paceTick
                        }
                        let guideColor = isDepleted ? SwftUsageColor.paceGuideDepleted : SwftUsageColor.paceGuide

                        // Whisper-soft full-height guide paired with a crisp top-edge tick so pacing reads
                        // at a glance without colliding with the icon or percentage text.
                        Rectangle()
                            .fill(guideColor)
                            .frame(width: 1, height: geo.size.height)
                            .position(x: tickX, y: geo.size.height / 2)
                            .allowsHitTesting(false)

                        Capsule()
                            .fill(tickColor)
                            .frame(width: 2, height: 5.5)
                            .position(x: tickX, y: 3.5)
                            .allowsHitTesting(false)
                    }

                    if let secondaryRemaining {
                        let secondaryClamped = max(0, min(100, secondaryRemaining))
                        let barInset: CGFloat = 10
                        let barMaxWidth = max(0, width - barInset * 2)
                        let barFillWidth: CGFloat = secondaryClamped == 0 ? 0 : max(4, barMaxWidth * CGFloat(secondaryClamped) / 100.0)
                        let barColor = secondaryClamped <= 10 ? SwftColor.danger : SwftUsageColor.secondaryFill

                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(SwftUsageColor.secondaryTrack)
                                .frame(width: barMaxWidth, height: 2)
                            if barFillWidth > 0 {
                                Capsule()
                                    .fill(barColor)
                                    .frame(width: barFillWidth, height: 2)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 2)
                        .allowsHitTesting(false)
                    }
                }
            }
        case .expired, .notSignedIn, .unavailable:
            Capsule().fill(isActive ? SwftUsageColor.pillTrack : SwftUsageColor.pillTrackMuted)
        }
    }

    @ViewBuilder
    private var pillForeground: some View {
        switch model.status {
        case .healthy(let remaining, _, _, let secondaryRemaining):
            HStack(spacing: 4) {
                ProviderMark(
                    provider: model.providerDriver,
                    acpAgentID: model.providerAcpAgentID,
                    symbol: model.providerSymbol,
                    monogram: model.providerName,
                    size: 13
                )
                .foregroundStyle(isDepleted ? SwftColor.danger : model.providerTint)

                Text("\(remaining)%")
                    .font(SwftFonts.flex(12, weight: 600))
                    .monospacedDigit()
                    .foregroundStyle(isDepleted ? SwftColor.danger : SwftColor.textPrimary)
                    .lineLimit(1)

                if model.accountCount > 1 {
                    Text("\(model.accountCount)")
                        .font(SwftFonts.flex(9.5, weight: 700))
                        .monospacedDigit()
                        .foregroundStyle(isDepleted ? SwftColor.danger : SwftColor.textSecondary)
                        .frame(minWidth: 14, minHeight: 14)
                        .padding(.horizontal, 2)
                        .background(Capsule().fill(SwftUsageColor.countBadgeFill))
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, secondaryRemaining != nil ? 2 : 0)

        case .expired(let isRenewing):
            HStack(spacing: 4) {
                ProviderMark(
                    provider: model.providerDriver,
                    acpAgentID: model.providerAcpAgentID,
                    symbol: model.providerSymbol,
                    monogram: model.providerName,
                    size: 13
                )
                .foregroundStyle(SwftColor.textSecondary.opacity(isActive ? 0.85 : 0.55))

                if isRenewing {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.75)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isActive ? SwftColor.textPrimary : SwftColor.textSecondary)
                }
            }
            .padding(.horizontal, 6)

        case .notSignedIn, .unavailable:
            HStack(spacing: 4) {
                ProviderMark(
                    provider: model.providerDriver,
                    acpAgentID: model.providerAcpAgentID,
                    symbol: model.providerSymbol,
                    monogram: model.providerName,
                    size: 13
                )
                .foregroundStyle(SwftColor.textSecondary.opacity(isActive ? 0.8 : 0.5))

                Text("—")
                    .font(SwftFonts.flex(11.5, weight: 500))
                    .foregroundStyle(SwftColor.textTertiary)
            }
            .padding(.horizontal, 6)
        }
    }

    @ViewBuilder
    private var pillBorder: some View {
        if isExpired {
            Capsule()
                .strokeBorder(
                    isActive ? SwftUsageColor.pillBorderDashedHover : SwftUsageColor.pillBorderDashed,
                    style: StrokeStyle(lineWidth: 1, dash: [3.5, 2.5])
                )
        } else if isDepleted {
            Capsule()
                .strokeBorder(
                    isActive ? SwftUsageColor.pillBorderDepletedHover : SwftUsageColor.pillBorderDepleted,
                    lineWidth: 1
                )
        } else {
            Capsule()
                .strokeBorder(
                    isActive ? SwftUsageColor.pillBorderHover : SwftUsageColor.pillBorder,
                    lineWidth: 1
                )
        }
    }
}

private struct FuelPillButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}
