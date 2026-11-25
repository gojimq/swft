import SwftDesign
import SwiftUI

/// Sidebar usage-limits footer showing up to 3 equal-width Tonal Fuel Pills with live pacing
/// and a floating Liquid Glass breakdown popover on hover.
struct SidebarUsageFooter: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var openGroupID: String?
    @State private var hoveredPillID: String?
    @State private var isHoveringCard = false
    @State private var hoverOpenTask: Task<Void, Never>?
    @State private var hoverCloseTask: Task<Void, Never>?

    private var activeGroupID: String? {
        model.previewUsagePopoverGroupID ?? openGroupID
    }

    var body: some View {
        let groups = model.visibleUsagePillGroups
        if !groups.isEmpty {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(SwftColor.borderSubtle)
                    .frame(height: 1)

                HStack(spacing: 6) {
                    ForEach(groups) { group in
                        TonalFuelPill(
                            pillModel(for: group),
                            isPopoverOpen: activeGroupID == group.id,
                            onHoverChange: { hovering in
                                handlePillHover(groupID: group.id, hovering: hovering)
                            },
                            action: {
                                handlePillTap(group)
                            }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .overlay(alignment: .top) {
                if let activeID = activeGroupID,
                   let group = groups.first(where: { $0.id == activeID })
                {
                    VStack(spacing: 0) {
                        UsageBreakdownCard(
                            breakdownModel(for: group),
                            onOpenAccount: { accountID in
                                closePopoverImmediately()
                                model.openProviderSettings(instanceId: accountID)
                            },
                            onRefreshAccount: { accountID in
                                model.refreshUsageProviders(instanceIds: [accountID])
                            }
                        )
                        // Invisible hover bridge spanning the gap between card and pill so moving upward never drops hover.
                        Color.clear
                            .frame(height: 8)
                            .contentShape(Rectangle())
                    }
                    .onHover { hovering in
                        handleCardHover(hovering)
                    }
                    .frame(height: 0, alignment: .bottom)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity
                                .combined(with: .scale(scale: 0.96, anchor: .bottom))
                                .combined(with: .offset(y: 4))
                    )
                }
            }
            .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: activeGroupID)
            .zIndex(20)
            .onAppear {
                model.recordHealthyUsageLimitsIfNeeded()
            }
            .onChange(of: model.usageProviders) { _, _ in
                model.recordHealthyUsageLimitsIfNeeded()
            }
            .onDisappear {
                hoverOpenTask?.cancel()
                hoverCloseTask?.cancel()
            }
        }
    }

    // MARK: - Hover Grace & Click Handling

    private func handlePillHover(groupID: String, hovering: Bool) {
        if hovering {
            hoveredPillID = groupID
            hoverCloseTask?.cancel()
            hoverCloseTask = nil
            hoverOpenTask?.cancel()

            if openGroupID != nil {
                openGroupID = groupID
            } else {
                hoverOpenTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled, hoveredPillID == groupID else { return }
                    openGroupID = groupID
                }
            }
        } else {
            if hoveredPillID == groupID {
                hoveredPillID = nil
            }
            hoverOpenTask?.cancel()
            hoverOpenTask = nil
            scheduleCloseIfUnhovered(delay: .milliseconds(220))
        }
    }

    private func handleCardHover(_ hovering: Bool) {
        isHoveringCard = hovering
        if hovering {
            hoverCloseTask?.cancel()
            hoverCloseTask = nil
        } else {
            scheduleCloseIfUnhovered(delay: .milliseconds(180))
        }
    }

    private func scheduleCloseIfUnhovered(delay: Duration) {
        hoverCloseTask?.cancel()
        hoverCloseTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, hoveredPillID == nil, !isHoveringCard else { return }
            openGroupID = nil
        }
    }

    private func closePopoverImmediately() {
        hoverOpenTask?.cancel()
        hoverCloseTask?.cancel()
        hoveredPillID = nil
        isHoveringCard = false
        openGroupID = nil
        model.previewUsagePopoverGroupID = nil
    }

    private func handlePillTap(_ group: UsagePillGroup) {
        if group.state.isExpired {
            let ids = group.expiredAccounts.map(\.id)
            model.refreshUsageProviders(instanceIds: ids.isEmpty ? [group.openTargetId] : ids)
            return
        }
        closePopoverImmediately()
        model.openProviderSettings(instanceId: group.openTargetId)
    }

    // MARK: - Presentation Mapping

    private func pillModel(for group: UsagePillGroup) -> TonalFuelPillModel {
        let now = model.now
        let isRenewing = group.expiredAccounts.contains { model.isRenewingUsageProvider($0.id) }
        let subject = group.accounts.count > 1 ? "\(group.label) (\(group.accounts.count) accounts)" : group.label

        let status: TonalFuelPillModel.Status
        let accessibilityLabel: String

        switch group.state {
        case .healthy(let primary, let secondary):
            let remaining = UsagePillsLogic.remainingPercent(primary)
            let paceRemaining = UsagePillsLogic.paceRemainingPercent(primary, now: now)
            let pace = UsagePillsLogic.paceOf(primary, now: now)
            let secondaryRemaining = secondary.map(UsagePillsLogic.remainingPercent)
            status = .healthy(
                remainingPercent: remaining,
                paceRemainingPercent: paceRemaining,
                paceTone: pace?.pillTone,
                secondaryRemainingPercent: secondaryRemaining
            )
            var parts = ["\(subject) usage: \(primary.label) \(remaining)% left"]
            if let secondary, let secondaryRemaining {
                parts.append("\(secondary.label) \(secondaryRemaining)% left")
            }
            if let pace {
                parts.append(pace.label)
            }
            accessibilityLabel = parts.joined(separator: ", ") + ". Open provider settings"

        case .expired:
            status = .expired(isRenewing: isRenewing)
            accessibilityLabel = isRenewing
                ? "\(subject): refreshing sign-in"
                : "\(subject): sign-in expired. Click to refresh"

        case .notSignedIn(let reason):
            status = .notSignedIn
            accessibilityLabel = "\(subject): \(reason). Open provider settings"

        case .unsupported(let reason), .unavailable(let reason):
            status = .unavailable
            accessibilityLabel = "\(subject): \(reason). Open provider settings"
        }

        return TonalFuelPillModel(
            id: group.id,
            providerName: group.label,
            providerSymbol: group.primary.kind.pickerSymbol,
            providerTint: group.primary.kind.tint,
            accountCount: group.accounts.count,
            status: status,
            accessibilityLabel: accessibilityLabel
        )
    }

    private func breakdownModel(for group: UsagePillGroup) -> UsageBreakdownCardModel {
        let now = model.now
        let siblings = group.accounts.map(\.entry)
        let isMulti = group.accounts.count > 1

        let headerDetail: String?
        if isMulti {
            headerDetail = "\(group.accounts.count) accounts"
        } else if let first = group.accounts.first {
            headerDetail = UsagePillsLogic.cardHeader(for: first.entry, in: [first.entry]).detail
        } else {
            headerDetail = nil
        }

        let accountSections: [UsageBreakdownAccountSection] = group.accounts.map { account in
            let sectionHeader = UsagePillsLogic.accountSectionHeader(for: account.entry, siblings: siblings)
            let isRenewing = model.isRenewingUsageProvider(account.id)
            let renewError = account.state.isExpired ? model.usageRenewalError(for: account.id) : nil
            let cached = (account.state.isExpired || account.state.kind == .unavailable)
                ? model.cachedUsageLimits(for: account.id)
                : nil

            let statusMessage: String?
            if let reason = account.state.reason {
                if let cached {
                    let asOf = UsagePillsLogic.formatAsOfTime(cached.checkedAt, now: now)
                    statusMessage = "\(reason) · as of \(asOf)"
                } else {
                    statusMessage = reason
                }
            } else {
                statusMessage = nil
            }

            let liveWindows = account.state.isHealthy ? (account.entry.usageLimits?.windows ?? []) : []
            let historicalWindows = cached?.windows ?? []

            return UsageBreakdownAccountSection(
                id: account.id,
                title: sectionHeader.title,
                detail: sectionHeader.detail,
                accentColor: account.entry.accentHex.flatMap { Color(swftHex: $0) },
                isHealthy: account.state.isHealthy,
                isExpired: account.state.isExpired,
                isRenewing: isRenewing,
                statusMessage: statusMessage,
                errorMessage: renewError,
                windowGroups: mapWindowGroups(liveWindows, now: now),
                historicalGroups: mapWindowGroups(historicalWindows, now: now)
            )
        }

        let paceFooter: UsageBreakdownPaceFooter?
        if case .healthy(let primary, _) = group.state,
           let pace = UsagePillsLogic.paceOf(primary, now: now)
        {
            let remaining = UsagePillsLogic.remainingPercent(primary)
            let resetPhrase = UsagePillsLogic.formatResetsInPhrase(primary, now: now)
            let text = resetPhrase.map { "\(pace.label) · \($0)" } ?? pace.label
            paceFooter = UsageBreakdownPaceFooter(
                tone: pace.pillTone,
                isDepleted: remaining <= 10,
                text: text
            )
        } else {
            paceFooter = nil
        }

        let anyRenewing = group.expiredAccounts.contains { model.isRenewingUsageProvider($0.id) }
        let actionHint: String
        let showRefreshIcon: Bool

        switch group.state {
        case .healthy:
            actionHint = "Click pill for Provider settings"
            showRefreshIcon = false
        case .expired:
            if anyRenewing {
                actionHint = "Refreshing sign-in…"
                showRefreshIcon = false
            } else {
                actionHint = group.expiredAccounts.count > 1 ? "Click pill to refresh all" : "Click pill to refresh"
                showRefreshIcon = true
            }
        case .notSignedIn:
            actionHint = "Click pill to sign in in Settings"
            showRefreshIcon = false
        case .unsupported, .unavailable:
            actionHint = "Click pill for Provider settings"
            showRefreshIcon = false
        }

        return UsageBreakdownCardModel(
            id: group.id,
            providerName: group.label,
            providerSymbol: group.primary.kind.pickerSymbol,
            providerTint: group.primary.kind.tint,
            headerDetail: headerDetail,
            isHealthy: group.state.isHealthy,
            accounts: accountSections,
            paceFooter: paceFooter,
            actionHint: actionHint,
            actionHintShowsRefreshIcon: showRefreshIcon
        )
    }

    private func mapWindowGroups(_ windows: [UsageWindow], now: Date) -> [UsageBreakdownWindowGroup] {
        UsagePillsLogic.usageWindowGroups(windows).map { group in
            UsageBreakdownWindowGroup(
                family: group.family,
                rows: group.rows.map { row in
                    UsageBreakdownWindowRow(
                        id: row.id,
                        label: row.label,
                        remainingPercent: UsagePillsLogic.remainingPercent(row.window),
                        paceRemainingPercent: UsagePillsLogic.paceRemainingPercent(row.window, now: now),
                        resetCountdown: UsagePillsLogic.formatResetCountdown(row.window, now: now)
                    )
                }
            )
        }
    }
}
