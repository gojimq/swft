import SwiftUI

/// One machine's line inside the pill while a multi-machine update runs.
public struct HomeUpdatePillRow: Identifiable, Equatable, Sendable {
    public enum Tone: Equatable, Sendable {
        case pending
        case active
        case success
        case failure
    }

    public let id: String
    public let label: String
    public let symbol: String
    public let detail: String
    public let tone: Tone

    public init(id: String, label: String, symbol: String, detail: String, tone: Tone) {
        self.id = id
        self.label = label
        self.symbol = symbol
        self.detail = detail
        self.tone = tone
    }
}

public enum HomeUpdatePillState: Equatable, Sendable {
    case available(message: String, actionTitle: String, actionHelp: String)
    case progress(headline: String, detail: String?, fraction: Double?, rows: [HomeUpdatePillRow])
    case attention(summary: String, rows: [HomeUpdatePillRow], canContinueLocal: Bool)
    case done(message: String)
    case failed(message: String)

    var rows: [HomeUpdatePillRow] {
        switch self {
        case .progress(_, _, _, let rows), .attention(_, let rows, _): rows
        default: []
        }
    }
}

public struct HomeUpdatePillActions {
    public var update: () -> Void
    public var retry: () -> Void
    public var continueLocal: () -> Void
    public var dismiss: () -> Void

    public init(
        update: @escaping () -> Void = {},
        retry: @escaping () -> Void = {},
        continueLocal: @escaping () -> Void = {},
        dismiss: @escaping () -> Void = {}
    ) {
        self.update = update
        self.retry = retry
        self.continueLocal = continueLocal
        self.dismiss = dismiss
    }
}

/// Spacing contract between Home's greeting, the pill, and the composer, plus the reveal curve.
public enum HomeUpdatePillMetrics {
    /// Greeting → composer when no pill is showing (Home's resting layout).
    public static let restingGap: CGFloat = 28
    public static let gapBelowGreeting: CGFloat = 14
    public static let gapAboveComposer: CGFloat = 22
    /// The greeting keeps this bottom padding; the slot supplies the rest so the hidden total stays `restingGap`.
    public static let greetingPadding: CGFloat = gapBelowGreeting
    static let fixedTail: CGFloat = restingGap - gapBelowGreeting
    static let revealedTail: CGFloat = gapAboveComposer - fixedTail
    /// Share of the reveal spent opening the gap before the pill starts to fade in (and, collapsing, after it is gone).
    public static let fadeLead: CGFloat = 0.35

    public static func opacity(_ fraction: CGFloat, reduceMotion: Bool) -> Double {
        let value = SwftDisclosureMath.clamped(fraction)
        if reduceMotion { return Double(value) }
        return Double(max(0, (value - fadeLead) / (1 - fadeLead)))
    }

    public static func scale(_ fraction: CGFloat, reduceMotion: Bool) -> CGFloat {
        reduceMotion ? 1 : 0.94 + 0.06 * CGFloat(opacity(fraction, reduceMotion: false))
    }
}

/// Home's slot under the greeting. Revealing opens the gap first (the greeting eases up) and then the glass fades in;
/// hiding fades the glass first and then closes the gap so the greeting glides back down to rest above the composer.
/// The pill stays mounted across phases and morphs in place. Reduce Motion crossfades at full height instead.
public struct HomeUpdatePillSlot: View {
    let state: HomeUpdatePillState?
    let actions: HomeUpdatePillActions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fraction: CGFloat
    @State private var shown: HomeUpdatePillState?

    public init(state: HomeUpdatePillState?, actions: HomeUpdatePillActions) {
        self.state = state
        self.actions = actions
        _fraction = State(initialValue: state == nil ? 0 : 1)
        _shown = State(initialValue: state)
    }

    public var body: some View {
        VStack(spacing: 0) {
            PillRevealLayout(fraction: fraction, reduceMotion: reduceMotion) {
                if let shown {
                    HomeUpdatePill(state: state ?? shown, actions: actions)
                        .padding(.bottom, HomeUpdatePillMetrics.revealedTail)
                        .frame(maxWidth: .infinity)
                        .transition(.identity)
                }
            }
            .modifier(PillRevealFade(fraction: fraction, reduceMotion: reduceMotion))
            Color.clear.frame(height: HomeUpdatePillMetrics.fixedTail)
        }
        .allowsHitTesting(state != nil)
        .accessibilityHidden(state == nil)
        .onChange(of: state) { _, next in
            if let next { shown = next }
        }
        .onChange(of: state != nil) { _, visible in
            withAnimation(SwftMotion.resolve(SwftMotion.arrival, reduceMotion: reduceMotion)) {
                fraction = visible ? 1 : 0
            } completion: {
                if state == nil, fraction == 0 { shown = nil }
            }
        }
    }
}

private struct PillRevealLayout: Layout {
    var fraction: CGFloat
    let reduceMotion: Bool

    var animatableData: CGFloat {
        get { fraction }
        set { fraction = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return CGSize(width: proposal.width ?? 0, height: 0) }
        let natural = child.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(
            width: proposal.width ?? natural.width,
            height: SwftDisclosureMath.revealedHeight(natural: natural.height, fraction: fraction, reduceMotion: reduceMotion)
        )
    }

    /// Centred rather than clipped, so the glass edge and its shadow never get sliced while the gap opens.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        let natural = child.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        child.place(
            at: CGPoint(x: bounds.midX, y: bounds.midY),
            anchor: .center,
            proposal: ProposedViewSize(width: bounds.width, height: natural.height)
        )
    }
}

private struct PillRevealFade: ViewModifier, Animatable {
    var fraction: CGFloat
    let reduceMotion: Bool

    nonisolated var animatableData: CGFloat {
        get { fraction }
        set { fraction = newValue }
    }

    func body(content: Content) -> some View {
        content
            .opacity(HomeUpdatePillMetrics.opacity(fraction, reduceMotion: reduceMotion))
            .scaleEffect(HomeUpdatePillMetrics.scale(fraction, reduceMotion: reduceMotion))
    }
}

/// Calm Liquid Glass capsule announcing and narrating an update.
public struct HomeUpdatePill: View {
    let state: HomeUpdatePillState
    let actions: HomeUpdatePillActions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastRows: [HomeUpdatePillRow] = []

    public init(state: HomeUpdatePillState, actions: HomeUpdatePillActions) {
        self.state = state
        self.actions = actions
    }

    private static let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    public var body: some View {
        let rows = state.rows
        HuggingWidthLayout(maxWidth: SwftLayout.composerMaxWidth) {
            VStack(alignment: .leading, spacing: 0) {
                mainRow
                SwftDisclosure(isExpanded: !rows.isEmpty, animation: SwftMotion.spring) {
                    machineRows(rows.isEmpty ? lastRows : rows)
                }
            }
            .swftGlass(in: Self.shape)
            .overlay(Self.shape.strokeBorder(SwftColor.borderSubtle, lineWidth: 0.5))
            .background(Self.shape.fill(SwftColor.glassTint).shadow(color: SwftColor.shadow, radius: 10, y: 3))
        }
        .animation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion), value: state)
        .onChange(of: rows, initial: true) { _, next in
            if !next.isEmpty { lastRows = next }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Software update")
    }

    private var mainRow: some View {
        HStack(spacing: 10) {
            leadingMark
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 6) {
                title
                if case .progress(_, _, let fraction?, _) = state {
                    SlimProgressBar(fraction: fraction)
                        .transition(.opacity)
                }
            }
            .layoutPriority(1)
            trailingControls
        }
        .padding(.leading, 14)
        .padding(.trailing, hasTrailingControls ? 7 : 18)
        .padding(.vertical, 7)
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private var leadingMark: some View {
        switch state {
        case .available:
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(SwftColor.accent)
                .transition(.swftPop(reduceMotion: reduceMotion))
        case .progress:
            ProgressView()
                .controlSize(.small)
                .transition(.opacity)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(SwftColor.success)
                .transition(.swftPop(reduceMotion: reduceMotion))
        case .attention, .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SwftColor.warning)
                .transition(.swftPop(reduceMotion: reduceMotion))
        }
    }

    @ViewBuilder
    private var title: some View {
        switch state {
        case .available(let message, _, _):
            primaryText(message)
        case .progress(let headline, let detail, _, _):
            HStack(spacing: 0) {
                primaryText(headline)
                if let detail {
                    Text(" · \(detail)")
                        .font(SwftType.label)
                        .foregroundStyle(SwftColor.textSecondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                }
            }
        case .attention(let summary, _, _):
            primaryText(summary, lines: 2)
        case .done(let message):
            primaryText(message)
        case .failed(let message):
            primaryText(message, lines: 2)
        }
    }

    private func primaryText(_ text: String, lines: Int = 1) -> some View {
        Text(text)
            .font(SwftType.labelStrong)
            .foregroundStyle(SwftColor.textPrimary)
            .lineLimit(lines)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.opacity)
    }

    private var hasTrailingControls: Bool {
        switch state {
        case .available, .attention, .failed: true
        case .progress, .done: false
        }
    }

    @ViewBuilder
    private var trailingControls: some View {
        switch state {
        case .available(_, let actionTitle, let actionHelp):
            HStack(spacing: 2) {
                PillCapsuleButton(actionTitle, prominent: true, action: actions.update)
                    .help(actionHelp)
                    .accessibilityHint(actionHelp)
                    .padding(.leading, 6)
                IconButton("xmark", help: "Dismiss", size: 28, action: actions.dismiss)
            }
        case .attention(_, _, let canContinueLocal):
            HStack(spacing: 6) {
                PillCapsuleButton("Retry", prominent: !canContinueLocal, action: actions.retry)
                if canContinueLocal {
                    PillCapsuleButton("Update this Mac", prominent: true, action: actions.continueLocal)
                        .help("Restart this Mac's Swft on the new version even though some environments failed")
                }
                IconButton("xmark", help: "Dismiss", size: 28, action: actions.dismiss)
            }
            .padding(.leading, 6)
        case .failed:
            IconButton("xmark", help: "Dismiss", size: 28, action: actions.dismiss)
                .padding(.leading, 4)
        case .progress, .done:
            EmptyView()
        }
    }

    private func machineRows(_ rows: [HomeUpdatePillRow]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Rectangle()
                .fill(SwftColor.borderSubtle)
                .frame(height: 1)
                .padding(.bottom, 6)
            ForEach(rows) { row in
                HStack(spacing: 8) {
                    Image(systemName: row.symbol)
                        .font(.system(size: 11.5))
                        .foregroundStyle(SwftColor.textTertiary)
                        .frame(width: 18)
                    Text(row.label)
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 20)
                    rowMark(row.tone)
                        .frame(width: 14, height: 14)
                    Text(row.detail)
                        .font(SwftType.caption)
                        .foregroundStyle(row.tone == .failure ? SwftColor.danger : SwftColor.textSecondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                }
                .frame(height: 24)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func rowMark(_ tone: HomeUpdatePillRow.Tone) -> some View {
        switch tone {
        case .pending:
            Image(systemName: "clock")
                .font(.system(size: 10.5))
                .foregroundStyle(SwftColor.textTertiary)
        case .active:
            ProgressView().controlSize(.mini)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(SwftColor.success)
        case .failure:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(SwftColor.danger)
        }
    }
}

private struct PillCapsuleButton: View {
    let title: String
    let prominent: Bool
    let action: () -> Void

    init(_ title: String, prominent: Bool, action: @escaping () -> Void) {
        self.title = title
        self.prominent = prominent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(SwftType.captionStrong)
                .foregroundStyle(prominent ? SwftColor.onSend : SwftColor.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(Capsule().fill(prominent ? SwftColor.sendFill : SwftColor.surface))
                .overlay(Capsule().strokeBorder(prominent ? Color.clear : SwftColor.borderSubtle))
                .contentShape(Capsule())
        }
        .buttonStyle(HoverFillStyle(shape: Capsule()))
    }
}

/// Thin determinate bar; scales a capsule instead of measuring, so it stays as wide as the text above it.
private struct SlimProgressBar: View {
    let fraction: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let clamped = min(max(fraction, 0), 1)
        Capsule()
            .fill(SwftColor.borderSubtle)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(SwftColor.accent)
                    .scaleEffect(x: max(0.02, clamped), y: 1, anchor: .leading)
            }
            .frame(height: 3)
            .frame(minWidth: 160)
            .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: clamped)
            .accessibilityElement()
            .accessibilityLabel("Progress")
            .accessibilityValue("\(Int(clamped * 100)) percent")
    }
}

/// Hugs its content's ideal width up to `maxWidth`, wrapping beyond that.
private struct HuggingWidthLayout: Layout {
    let maxWidth: CGFloat

    private func width(for proposal: ProposedViewSize, child: LayoutSubview) -> CGFloat {
        let ideal = child.sizeThatFits(.unspecified).width
        return min(ideal, maxWidth, proposal.width ?? .infinity)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        return child.sizeThatFits(ProposedViewSize(width: width(for: proposal, child: child), height: nil))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        let width = min(bounds.width, width(for: proposal, child: child))
        child.place(
            at: CGPoint(x: bounds.midX, y: bounds.midY),
            anchor: .center,
            proposal: ProposedViewSize(width: width, height: bounds.height)
        )
    }
}
