import Foundation
import SwiftUI

/// Lifecycle status rendered by SwftDesign's inline subagent indicator primitives.
public enum SubagentBadgeStatus: Hashable, Sendable {
    case pending
    case running
    case waiting
    case idle
    case completed
    case failed
    case cancelled
    case interrupted

    public var isActive: Bool {
        switch self {
        case .pending, .running, .waiting: true
        default: false
        }
    }

    public var showsSpinner: Bool {
        switch self {
        case .pending, .running: true
        default: false
        }
    }

    public var isWaiting: Bool { self == .waiting }
    public var isFailed: Bool { self == .failed }
    public var isCompleted: Bool { self == .completed }

    var dotColor: Color {
        switch self {
        case .pending, .running: SwftColor.accent
        case .waiting: SwftColor.warning
        case .completed: SwftColor.success
        case .failed: SwftColor.danger
        case .cancelled, .interrupted, .idle: SwftColor.textTertiary
        }
    }

    var textColor: Color {
        switch self {
        case .pending, .running: SwftColor.accent
        case .waiting: SwftColor.warning
        case .failed: SwftColor.danger
        case .completed, .cancelled, .interrupted, .idle: SwftColor.textTertiary
        }
    }
}

/// Environment hook allowing snapshot/unit tests to pin subagent elapsed clocks deterministically.
extension EnvironmentValues {
    @Entry public var subagentClockNow: Date? = nil
}

/// Pure elapsed-time formatter shared between live subagent views and Swft's display logic.
public enum SubagentElapsedFormatter {
    public static func format(
        startedAt: Date?,
        completedAt: Date?,
        isActive: Bool,
        now: Date
    ) -> String? {
        guard let startedAt else { return nil }
        let end: Date
        if isActive {
            end = now
        } else if let completedAt {
            end = completedAt
        } else {
            return nil
        }
        let seconds = max(0, Int(floor(end.timeIntervalSince(startedAt))))
        return formatSeconds(seconds)
    }

    public static func formatSeconds(_ totalSeconds: Int) -> String {
        let seconds = max(0, totalSeconds)
        let minutes = seconds / 60
        if minutes == 0 {
            return "\(seconds)s"
        }
        let hours = minutes / 60
        if hours == 0 {
            let remSeconds = seconds % 60
            return "\(minutes)m \(String(format: "%02d", remSeconds))s"
        }
        let remMinutes = minutes % 60
        return "\(hours)h \(String(format: "%02d", remMinutes))m"
    }
}

/// Descriptor for one provider avatar chip in a standalone subagent row or stacked group header.
public struct SubagentAvatarSpec: Identifiable, Hashable, Sendable {
    public let id: String
    public let icon: ResolvedProviderIcon
    public let status: SubagentBadgeStatus?

    public init(id: String, icon: ResolvedProviderIcon, status: SubagentBadgeStatus? = nil) {
        self.id = id
        self.icon = icon
        self.status = status
    }
}

/// Plain presentation model for a single inline subagent row.
public struct SubagentRowModel: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let modelLabel: String?
    public let remoteEnvironmentLabel: String?
    public let detail: String?
    public let statusLabel: String
    public let status: SubagentBadgeStatus
    public let icon: ResolvedProviderIcon
    public let startedAt: Date?
    public let completedAt: Date?
    public let canOpenThread: Bool
    public let prompt: String?
    public let expandedBodyLabel: String?
    public let expandedBodyText: String?
    public let workspaceLabel: String?
    public let helpText: String

    public init(
        id: String,
        title: String,
        modelLabel: String? = nil,
        remoteEnvironmentLabel: String? = nil,
        detail: String? = nil,
        statusLabel: String,
        status: SubagentBadgeStatus,
        icon: ResolvedProviderIcon,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        canOpenThread: Bool,
        prompt: String? = nil,
        expandedBodyLabel: String? = nil,
        expandedBodyText: String? = nil,
        workspaceLabel: String? = nil,
        helpText: String = ""
    ) {
        self.id = id
        self.title = title
        self.modelLabel = modelLabel
        self.remoteEnvironmentLabel = remoteEnvironmentLabel
        self.detail = detail
        self.statusLabel = statusLabel
        self.status = status
        self.icon = icon
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.canOpenThread = canOpenThread
        self.prompt = prompt
        self.expandedBodyLabel = expandedBodyLabel
        self.expandedBodyText = expandedBodyText
        self.workspaceLabel = workspaceLabel
        self.helpText = helpText
    }

    public var hasInlineDetails: Bool {
        !canOpenThread && (
            (prompt?.isEmpty == false)
            || (expandedBodyText?.isEmpty == false)
            || (workspaceLabel?.isEmpty == false)
        )
    }
}

/// Plain presentation model for a collapsible group of consecutive parallel subagents.
public struct SubagentGroupModel: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let statusSummary: String
    public let avatars: [SubagentAvatarSpec]
    public let totalCount: Int
    public let isActive: Bool
    public let hasSpinnerActivity: Bool
    public let hasWaiting: Bool
    public let hasFailed: Bool
    public let startedAt: Date?
    public let completedAt: Date?
    public let members: [SubagentRowModel]

    public init(
        id: String,
        title: String,
        statusSummary: String,
        avatars: [SubagentAvatarSpec],
        totalCount: Int,
        isActive: Bool,
        hasSpinnerActivity: Bool,
        hasWaiting: Bool,
        hasFailed: Bool,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        members: [SubagentRowModel]
    ) {
        self.id = id
        self.title = title
        self.statusSummary = statusSummary
        self.avatars = avatars
        self.totalCount = totalCount
        self.isActive = isActive
        self.hasSpinnerActivity = hasSpinnerActivity
        self.hasWaiting = hasWaiting
        self.hasFailed = hasFailed
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.members = members
    }
}

// MARK: - Avatar & Elapsed Primitives

/// Circular provider icon badge with a crisp corner status indicator ringed by the surface color.
public struct SubagentAvatarView: View, Equatable {
    public let icon: ResolvedProviderIcon
    public let status: SubagentBadgeStatus?
    public let ringColor: Color

    public init(
        icon: ResolvedProviderIcon,
        status: SubagentBadgeStatus? = nil,
        ringColor: Color = SwftColor.canvas
    ) {
        self.icon = icon
        self.status = status
        self.ringColor = ringColor
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(SwftColor.surface)
                .overlay(Circle().strokeBorder(SwftColor.borderSubtle, lineWidth: 1))
                .overlay {
                    ProviderIcon(resolved: icon, size: 13)
                        .foregroundStyle(icon == .mark(.generic) ? SwftColor.textTertiary : SwftColor.textSecondary)
                }
                .frame(width: 24, height: 24)
                .overlay(Circle().stroke(ringColor, lineWidth: 1.5))

            if let status {
                statusBadge(status)
                    .offset(x: 2, y: 2)
            }
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func statusBadge(_ status: SubagentBadgeStatus) -> some View {
        ZStack {
            Circle()
                .fill(status.dotColor)
                .frame(width: 10, height: 10)
            if status == .completed {
                Image(systemName: "checkmark")
                    .font(.system(size: 5.5, weight: .bold))
                    .foregroundStyle(SwftColor.canvas)
            } else if status == .failed {
                Image(systemName: "xmark")
                    .font(.system(size: 5.5, weight: .bold))
                    .foregroundStyle(SwftColor.canvas)
            }
        }
        .overlay(Circle().stroke(ringColor, lineWidth: 1.5))
    }
}

/// Overlapping provider avatar stack for grouped parallel subagents (up to 3 avatars + overflow count).
public struct SubagentAvatarStack: View, Equatable {
    public let avatars: [SubagentAvatarSpec]
    public let totalCount: Int
    public let ringColor: Color

    public init(
        avatars: [SubagentAvatarSpec],
        totalCount: Int,
        ringColor: Color = SwftColor.codeBackground
    ) {
        self.avatars = avatars
        self.totalCount = totalCount
        self.ringColor = ringColor
    }

    public var body: some View {
        let visible = Array(avatars.prefix(3))
        let overflow = max(0, totalCount - visible.count)
        HStack(spacing: -8) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, spec in
                SubagentAvatarView(icon: spec.icon, status: nil, ringColor: ringColor)
                    .zIndex(Double(visible.count - index))
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(SwftType.micro)
                    .monospacedDigit()
                    .foregroundStyle(SwftColor.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(SwftColor.surfaceMuted))
                    .overlay(Circle().strokeBorder(SwftColor.borderSubtle, lineWidth: 1))
                    .overlay(Circle().stroke(ringColor, lineWidth: 1.5))
                    .zIndex(0)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Displays a subagent's elapsed time. Only mounts a 1 Hz `TimelineView` while the subagent is actively running
/// and no test clock override is supplied; settled or offscreen rows render a completely static `Text`.
public struct SubagentElapsedLabel: View, Equatable {
    public let startedAt: Date?
    public let completedAt: Date?
    public let isActive: Bool
    public let prefix: String?
    public let prefixColor: Color

    @Environment(\.subagentClockNow) private var clockNow

    public init(
        startedAt: Date?,
        completedAt: Date?,
        isActive: Bool,
        prefix: String? = nil,
        prefixColor: Color = SwftColor.textTertiary
    ) {
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.isActive = isActive
        self.prefix = prefix
        self.prefixColor = prefixColor
    }

    nonisolated public static func == (lhs: SubagentElapsedLabel, rhs: SubagentElapsedLabel) -> Bool {
        lhs.startedAt == rhs.startedAt
            && lhs.completedAt == rhs.completedAt
            && lhs.isActive == rhs.isActive
            && lhs.prefix == rhs.prefix
    }

    public var body: some View {
        if isActive, startedAt != nil, clockNow == nil {
            TimelineView(.periodic(from: startedAt ?? Date(), by: 1)) { context in
                content(at: context.date)
            }
        } else {
            content(at: clockNow ?? completedAt ?? startedAt ?? Date())
        }
    }

    @ViewBuilder
    private func content(at now: Date) -> some View {
        let elapsed = SubagentElapsedFormatter.format(
            startedAt: startedAt,
            completedAt: completedAt,
            isActive: isActive,
            now: now
        )
        if prefix != nil || elapsed != nil {
            HStack(spacing: 4) {
                if let prefix {
                    Text(prefix)
                        .foregroundStyle(prefixColor)
                }
                if prefix != nil, elapsed != nil {
                    Text("·")
                        .foregroundStyle(SwftColor.textTertiary)
                }
                if let elapsed {
                    Text(elapsed)
                        .foregroundStyle(SwftColor.textTertiary)
                        .monospacedDigit()
                }
            }
            .font(SwftType.caption)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

// MARK: - Single Subagent Inline Row

/// Compact inline subagent indicator rendered directly in the transcript (or embedded inside an expanded group).
/// Clicking opens a delegated child thread when `model.canOpenThread`, or smoothly discloses prompt/summary details
/// for provider-native / non-navigable subagents.
public struct SubagentInlineCard: View, Equatable {
    public let model: SubagentRowModel
    public let embedded: Bool
    public let isExpanded: Bool
    public let onAction: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        model: SubagentRowModel,
        embedded: Bool = false,
        isExpanded: Bool = false,
        onAction: @escaping () -> Void = {}
    ) {
        self.model = model
        self.embedded = embedded
        self.isExpanded = isExpanded
        self.onAction = onAction
    }

    nonisolated public static func == (lhs: SubagentInlineCard, rhs: SubagentInlineCard) -> Bool {
        lhs.model == rhs.model
            && lhs.embedded == rhs.embedded
            && lhs.isExpanded == rhs.isExpanded
    }

    private var interactive: Bool {
        model.canOpenThread || model.hasInlineDetails
    }

    private var containerFill: Color {
        if embedded {
            return hovering && interactive ? SwftColor.hover : .clear
        }
        return hovering && interactive ? SwftColor.surfaceMuted : SwftColor.codeBackground
    }

    private var containerStroke: Color {
        if model.status.isFailed {
            return SwftColor.danger.opacity(0.28)
        }
        if model.status.isWaiting {
            return SwftColor.warningBorder
        }
        return SwftColor.borderSubtle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if interactive {
                Button(action: onAction) {
                    rowContent
                }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
                .help(model.helpText)
                .accessibilityLabel(model.canOpenThread ? "Open subagent \(model.title)" : model.title)
                .accessibilityValue(model.canOpenThread ? model.statusLabel : (isExpanded ? "Expanded, \(model.statusLabel)" : "Collapsed, \(model.statusLabel)"))
            } else {
                rowContent
                    .help(model.helpText)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(model.title)
                    .accessibilityValue(model.statusLabel)
            }

            if model.hasInlineDetails {
                SwftDisclosure(isExpanded: isExpanded) {
                    inlineDetails
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if embedded {
                RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous)
                    .fill(containerFill)
            } else {
                RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous)
                    .fill(containerFill)
            }
        }
        .overlay {
            if !embedded {
                RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous)
                    .strokeBorder(containerStroke, lineWidth: 1)
            }
        }
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: hovering)
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            SubagentAvatarView(
                icon: model.icon,
                status: model.status,
                ringColor: embedded ? SwftColor.codeBackground : containerFill
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 6) {
                    Text(model.title)
                        .font(SwftType.labelStrong)
                        .foregroundStyle(SwftColor.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let modelLabel = model.modelLabel {
                        Text(modelLabel)
                            .font(SwftType.caption)
                            .foregroundStyle(SwftColor.textSecondary)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(SwftColor.surfaceMuted))
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    if let remoteLabel = model.remoteEnvironmentLabel {
                        Text("on \(remoteLabel)")
                            .font(SwftType.caption)
                            .foregroundStyle(SwftColor.textTertiary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }

                if let detail = model.detail {
                    Text(detail)
                        .font(SwftType.caption)
                        .foregroundStyle(model.status.isFailed ? SwftColor.danger : SwftColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(detail.contains("/") && !detail.contains(" ") ? .middle : .tail)
                } else {
                    Text(model.statusLabel)
                        .font(SwftType.caption)
                        .foregroundStyle(model.status.textColor)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 7) {
                if model.status.showsSpinner {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 12, height: 12)
                }

                SubagentElapsedLabel(
                    startedAt: model.startedAt,
                    completedAt: model.completedAt,
                    isActive: model.status.isActive,
                    prefix: model.detail != nil ? model.statusLabel : nil,
                    prefixColor: model.status.textColor
                )

                if interactive {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(hovering ? SwftColor.textSecondary : SwftColor.textTertiary)
                        .rotationEffect(.degrees(!model.canOpenThread && isExpanded ? 90 : 0))
                        .animation(SwftMotion.resolve(SwftMotion.disclosure, reduceMotion: reduceMotion), value: isExpanded)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, embedded ? 8 : 12)
        .padding(.vertical, embedded ? 7 : 9)
        .contentShape(Rectangle())
    }

    private var inlineDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(SwftColor.borderSubtle)
                .frame(height: 1)

            if let workspace = model.workspaceLabel {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(SwftColor.textTertiary)
                    Text(workspace)
                        .font(SwftType.monoSmall)
                        .foregroundStyle(SwftColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if let prompt = model.prompt, !prompt.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Prompt")
                        .font(SwftType.captionStrong)
                        .foregroundStyle(SwftColor.textTertiary)
                    Text(prompt)
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textSecondary)
                        .lineSpacing(2)
                        .lineLimit(8)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let bodyText = model.expandedBodyText, !bodyText.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.expandedBodyLabel ?? "Summary")
                        .font(SwftType.captionStrong)
                        .foregroundStyle(model.status.isFailed ? SwftColor.danger : SwftColor.textTertiary)
                    Text(bodyText)
                        .font(SwftType.caption)
                        .foregroundStyle(model.status.isFailed ? SwftColor.danger : SwftColor.textPrimary)
                        .lineSpacing(2)
                        .lineLimit(12)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous)
                                .fill(model.status.isFailed ? SwftColor.dangerSoft : SwftColor.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous)
                                .strokeBorder(model.status.isFailed ? SwftColor.danger.opacity(0.25) : SwftColor.borderSubtle, lineWidth: 1)
                        )
                }
            }
        }
        .padding(.horizontal, embedded ? 10 : 12)
        .padding(.bottom, embedded ? 8 : 10)
    }
}

// MARK: - Grouped Parallel Subagents Card

/// Collapsible inline card grouping 2+ consecutive parallel subagents spawned in a turn.
public struct SubagentGroupCard: View, Equatable {
    public let model: SubagentGroupModel
    public let isExpanded: Bool
    public let expandedMemberIDs: Set<String>
    public let onToggleGroup: () -> Void
    public let onMemberAction: (SubagentRowModel) -> Void

    @State private var hoveringHeader = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        model: SubagentGroupModel,
        isExpanded: Bool,
        expandedMemberIDs: Set<String> = [],
        onToggleGroup: @escaping () -> Void = {},
        onMemberAction: @escaping (SubagentRowModel) -> Void = { _ in }
    ) {
        self.model = model
        self.isExpanded = isExpanded
        self.expandedMemberIDs = expandedMemberIDs
        self.onToggleGroup = onToggleGroup
        self.onMemberAction = onMemberAction
    }

    nonisolated public static func == (lhs: SubagentGroupCard, rhs: SubagentGroupCard) -> Bool {
        lhs.model == rhs.model
            && lhs.isExpanded == rhs.isExpanded
            && lhs.expandedMemberIDs == rhs.expandedMemberIDs
    }

    private var summaryColor: Color {
        if model.hasSpinnerActivity { return SwftColor.accent }
        if model.hasWaiting { return SwftColor.warning }
        if model.hasFailed { return SwftColor.danger }
        return SwftColor.textTertiary
    }

    private var headerFill: Color {
        hoveringHeader ? SwftColor.surfaceMuted : SwftColor.codeBackground
    }

    private var borderStroke: Color {
        if !model.isActive && model.hasFailed {
            return SwftColor.danger.opacity(0.28)
        }
        if model.hasWaiting && !model.hasSpinnerActivity {
            return SwftColor.warningBorder
        }
        return SwftColor.borderSubtle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggleGroup) {
                HStack(spacing: 10) {
                    SubagentAvatarStack(
                        avatars: model.avatars,
                        totalCount: model.totalCount,
                        ringColor: headerFill
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.title)
                            .font(SwftType.labelStrong)
                            .foregroundStyle(SwftColor.textPrimary)
                            .lineLimit(1)
                        Text(model.statusSummary)
                            .font(SwftType.caption)
                            .foregroundStyle(summaryColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 7) {
                        if model.hasSpinnerActivity {
                            ProgressView()
                                .controlSize(.mini)
                                .frame(width: 12, height: 12)
                        }

                        SubagentElapsedLabel(
                            startedAt: model.startedAt,
                            completedAt: model.completedAt,
                            isActive: model.isActive
                        )

                        Image(systemName: "chevron.right")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(hoveringHeader || isExpanded ? SwftColor.textSecondary : SwftColor.textTertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .animation(SwftMotion.resolve(SwftMotion.disclosure, reduceMotion: reduceMotion), value: isExpanded)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoveringHeader = $0 }
            .accessibilityLabel(model.title)
            .accessibilityValue("\(isExpanded ? "Expanded" : "Collapsed"), \(model.statusSummary)")

            SwftDisclosure(isExpanded: isExpanded) {
                VStack(alignment: .leading, spacing: 2) {
                    Rectangle()
                        .fill(SwftColor.borderSubtle)
                        .frame(height: 1)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 4)

                    ForEach(model.members) { member in
                        SubagentInlineCard(
                            model: member,
                            embedded: true,
                            isExpanded: expandedMemberIDs.contains(member.id)
                        ) {
                            onMemberAction(member)
                        }
                        .equatable()
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous)
                .fill(SwftColor.codeBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous)
                .strokeBorder(borderStroke, lineWidth: 1)
        )
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: hoveringHeader)
    }
}

// MARK: - Child Thread TopBar Navigation Chrome

/// Back-to-parent breadcrumb pill shown in `TopBar` when viewing a delegated subagent child thread.
public struct SubagentBackBreadcrumb: View {
    public let parentTitle: String
    public let action: () -> Void

    public init(parentTitle: String, action: @escaping () -> Void) {
        self.parentTitle = parentTitle
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10.5, weight: .semibold))
                Text(parentTitle)
                    .font(SwftType.captionStrong)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 160, alignment: .leading)
            }
            .foregroundStyle(SwftColor.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(Capsule().fill(SwftColor.surfaceMuted))
            .overlay(Capsule().strokeBorder(SwftColor.borderSubtle, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(HoverFillStyle(shape: Capsule()))
        .help("Return to \(parentTitle)")
        .accessibilityLabel("Back to \(parentTitle)")
    }
}

/// Subtle capsule tag identifying a child subagent thread in `TopBar`.
public struct SubagentHeaderBadge: View {
    public init() {}

    public var body: some View {
        Text("Subagent")
            .font(SwftType.caption)
            .foregroundStyle(SwftColor.textTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(SwftColor.surfaceMuted))
            .fixedSize(horizontal: true, vertical: false)
    }
}
