import SwiftUI

/// Primary sidebar navigation row ("New thread", "Projects", …). Capsule selection like the reference.
public struct SidebarNavRow: View {
    let title: String
    let systemName: String
    var isSelected: Bool
    var isProminent: Bool
    var trailing: String?
    let action: () -> Void

    public init(_ title: String, systemName: String, isSelected: Bool = false, isProminent: Bool = false, trailing: String? = nil, action: @escaping () -> Void = {}) {
        self.title = title
        self.systemName = systemName
        self.isSelected = isSelected
        self.isProminent = isProminent
        self.trailing = trailing
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 16)
                Text(title)
                    .font(isProminent ? SwftType.sidebarStrong : SwftType.sidebar)
                Spacer(minLength: 0)
                if let trailing {
                    Text(trailing).font(SwftType.caption).foregroundStyle(SwftColor.textTertiary)
                }
            }
            .foregroundStyle(SwftColor.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: SwftLayout.sidebarRowHeight)
            .contentShape(Capsule())
        }
        .buttonStyle(SidebarSelectionButtonStyle(shape: RoundedRectangle(cornerRadius: SwftRadius.l, style: .continuous), selected: isSelected, pressScale: SidebarSelectionMotion.rowPressScale))
    }
}

/// Quiet section label with an optional trailing control (e.g. the "All ▾" filter).
public struct SidebarSectionHeader<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    public init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 4) {
            Text(title).font(SwftType.sectionHeader).foregroundStyle(SwftColor.textTertiary)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.leading, 9)
        .padding(.trailing, 6)
        .frame(height: 28)
    }
}

extension SidebarSectionHeader where Trailing == EmptyView {
    public init(_ title: String) { self.init(title) { EmptyView() } }
}

/// Visual state for the trailing status slot of an inbox row.
public enum InboxRowStatus: Equatable, Sendable {
    case none
    case running
    case needsApproval
    case unread
    case failed
}

/// Three-line thread inbox row: project + time / title / location, with provider and status trailing.
public struct ThreadInboxRow: View {
    public struct Model: Equatable {
        public var projectName: String
        public var projectInitials: String?
        public var projectTint: Int
        public var time: String
        public var title: String
        public var location: String?
        public var locationSymbol: String
        public var status: InboxRowStatus
        public var providerSymbol: String
        public var providerTint: Color
        public var providerName: String
        public var providerDriver: String?
        public var providerAcpAgentID: String?
        public var providerIconURL: String?

        public init(projectName: String, projectInitials: String?, projectTint: Int, time: String, title: String, location: String?, locationSymbol: String, status: InboxRowStatus, providerSymbol: String, providerTint: Color, providerName: String) {
            self.projectName = projectName
            self.projectInitials = projectInitials
            self.projectTint = projectTint
            self.time = time
            self.title = title
            self.location = location
            self.locationSymbol = locationSymbol
            self.status = status
            self.providerSymbol = providerSymbol
            self.providerTint = providerTint
            self.providerName = providerName
            self.providerDriver = nil
            self.providerAcpAgentID = nil
            self.providerIconURL = nil
        }

        public init(projectName: String, projectInitials: String?, projectTint: Int, time: String, title: String, location: String?, locationSymbol: String, status: InboxRowStatus, providerSymbol: String, providerTint: Color, providerName: String, providerDriver: String?, providerAcpAgentID: String? = nil, providerIconURL: String? = nil) {
            self.projectName = projectName
            self.projectInitials = projectInitials
            self.projectTint = projectTint
            self.time = time
            self.title = title
            self.location = location
            self.locationSymbol = locationSymbol
            self.status = status
            self.providerSymbol = providerSymbol
            self.providerTint = providerTint
            self.providerName = providerName
            self.providerDriver = providerDriver
            self.providerAcpAgentID = providerAcpAgentID
            self.providerIconURL = providerIconURL
        }
    }

    let model: Model
    var isSelected: Bool
    let action: () -> Void

    public init(_ model: Model, isSelected: Bool, action: @escaping () -> Void = {}) {
        self.model = model
        self.isSelected = isSelected
        self.action = action
    }

    private var emphasized: Bool { model.status != .none || isSelected }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    ProjectChip(initials: model.projectInitials ?? "", tint: model.projectTint, size: 15, dashed: model.projectInitials == nil)
                    Text(model.projectName)
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(model.time)
                        .font(SwftType.caption)
                        .monospacedDigit()
                        .foregroundStyle(model.status == .unread ? SwftColor.accent : SwftColor.textTertiary)
                }
                Text(model.title)
                    .font(emphasized ? SwftType.rowTitle : SwftType.rowTitleRead)
                    .foregroundStyle(SwftColor.textPrimary)
                    .lineLimit(1)
                    .swftTitleSwap(model.title)
                HStack(spacing: 5) {
                    if let location = model.location {
                        Image(systemName: model.locationSymbol)
                            .font(.system(size: 9.5, weight: .medium))
                        Text(location)
                            .font(SwftType.caption)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    statusView
                        .id(model.status)
                        .transition(.opacity.combined(with: .scale(scale: 0.6)))
                    ProviderGlyph(provider: model.providerDriver, acpAgentID: model.providerAcpAgentID, iconURL: model.providerIconURL, symbol: model.providerSymbol, tint: model.providerTint, name: model.providerName)
                }
                .foregroundStyle(SwftColor.textTertiary)
                .frame(height: 16)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(RoundedRectangle(cornerRadius: SwftRadius.l, style: .continuous))
        }
        .buttonStyle(SidebarSelectionButtonStyle(shape: RoundedRectangle(cornerRadius: SwftRadius.l, style: .continuous), selected: isSelected, pressScale: SidebarSelectionMotion.rowPressScale))
        .animation(SwftMotion.pop, value: model.status)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var statusView: some View {
        switch model.status {
        case .none:
            EmptyView()
        case .running:
            ProgressView()
                .controlSize(.mini)
                .frame(width: 16, height: 16)
                .help("Running")
        case .needsApproval:
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 10.5))
                .foregroundStyle(SwftColor.warning)
                .frame(width: 16, height: 16)
                .help("Needs approval")
        case .unread:
            Circle()
                .fill(SwftColor.accent)
                .frame(width: 7, height: 7)
                .frame(width: 16, height: 16)
                .help("Unread")
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(SwftColor.danger)
                .frame(width: 16, height: 16)
                .help("Failed")
        }
    }
}

/// Account row pinned at the bottom of the sidebar.
public struct AccountRow: View {
    let name: String
    let detail: String
    let action: () -> Void

    public init(name: String, detail: String, action: @escaping () -> Void = {}) {
        self.name = name
        self.detail = detail
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle()
                    .fill(SwftColor.chip(1).fill)
                    .overlay(Text(String(name.prefix(1))).font(SwftFonts.flex(13, weight: 600)).foregroundStyle(SwftColor.chip(1).ink))
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).font(SwftType.label).foregroundStyle(SwftColor.textPrimary)
                    Text(detail).font(SwftType.caption).foregroundStyle(SwftColor.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous))
        }
        .buttonStyle(HoverFillStyle(shape: RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous)))
    }
}
