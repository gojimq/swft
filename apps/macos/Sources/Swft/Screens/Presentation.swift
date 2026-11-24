import SwftDesign
import SwiftUI

// Maps view state onto design-system component models. Keep presentation decisions here, not in the views.

extension ProviderKind {
    var symbol: String {
        switch self {
        case .claude: "asterisk"
        case .codex: "hexagon"
        case .cursor: "cursorarrow"
        case .opencode: "chevron.left.forwardslash.chevron.right"
        case .gemini: "sparkle"
        case .other: "circle.dashed"
        }
    }

    var tint: Color {
        switch self {
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex: SwftColor.textSecondary
        case .cursor: SwftColor.textSecondary
        case .opencode: SwftColor.success
        case .gemini: SwftColor.accent
        case .other: SwftColor.textTertiary
        }
    }
}

extension ServerStatus {
    var pillTitle: String {
        switch self {
        case .starting: "Starting server…"
        case .connecting: "Connecting…"
        case .connected: "Local server"
        case .reconnecting: "Reconnecting…"
        case .failed: "Server error"
        }
    }

    var dotColor: Color {
        switch self {
        case .starting, .connecting, .reconnecting: SwftColor.warning
        case .connected: SwftColor.success
        case .failed: SwftColor.danger
        }
    }

    var needsRetry: Bool {
        switch self {
        case .failed, .reconnecting: true
        case .starting, .connecting, .connected: false
        }
    }
}

extension ThreadSummary {
    func inboxModel(now: Date) -> ThreadInboxRow.Model {
        let (locationText, locationSymbol): (String?, String) = switch location {
        case .branch(let b): (b, "arrow.triangle.branch")
        case .host(let h): (h, "laptopcomputer")
        case nil: (nil, "")
        }
        return ThreadInboxRow.Model(
            projectName: project?.name ?? "No project",
            projectInitials: project?.initials,
            projectTint: project?.tint ?? 0,
            time: RelativeTime.short(from: updatedAt, to: now),
            title: title,
            location: locationText,
            locationSymbol: locationSymbol,
            status: activity.inboxStatus,
            providerSymbol: provider.symbol,
            providerTint: provider.tint,
            providerName: providerLabel
        )
    }
}

extension ThreadActivity {
    var inboxStatus: InboxRowStatus {
        switch self {
        case .idle: .none
        case .running: .running
        case .needsApproval: .needsApproval
        case .unread: .unread
        case .failed: .failed
        }
    }
}

extension ToolCallItem.Status {
    var cardStatus: ToolCallStatus {
        switch self {
        case .running: .running
        case .succeeded: .succeeded
        case .failed: .failed
        }
    }
}

extension ApprovalItem.Status {
    var cardStatus: ApprovalStatus {
        switch self {
        case .pending: .pending
        case .approved: .approved
        case .denied: .denied
        }
    }
}

extension ToolCallItem {
    var symbol: String {
        switch kind {
        case .command: "terminal"
        case .read: "doc.text"
        case .edit: "pencil"
        case .search: "magnifyingglass"
        case .thinking: "brain"
        }
    }

    var durationText: String? {
        guard let duration else { return nil }
        return duration < 1 ? "\(Int(duration * 1000))ms" : String(format: "%.1fs", duration)
    }
}

enum RelativeTime {
    /// Compact inbox timestamps: "now", "2m", "5h", "3d", "6w".
    static func short(from date: Date, to now: Date) -> String {
        let s = max(0, now.timeIntervalSince(date))
        switch s {
        case ..<60: return "now"
        case ..<3600: return "\(Int(s / 60))m"
        case ..<86400: return "\(Int(s / 3600))h"
        case ..<(86400 * 7): return "\(Int(s / 86400))d"
        default: return "\(Int(s / (86400 * 7)))w"
        }
    }
}
