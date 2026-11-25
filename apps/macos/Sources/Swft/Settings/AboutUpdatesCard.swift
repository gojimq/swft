import SwftDesign
import SwftKit
import SwiftUI

/// Settings → About → Updates: release status, per-environment readiness, remote setup, and private-repo access.
struct AboutUpdatesCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsServerSetup = false
    @State private var showsTokenAccess = false
    @State private var tokenDraft = ""

    static let serverInstallCommand =
        "curl -fsSL https://raw.githubusercontent.com/gojimq/swft/swft/main/scripts/install-swft-server.sh | bash"

    private var updates: UpdateCoordinator { model.updates }

    var body: some View {
        SettingsSectionCard("Updates") {
            statusRow
            let environments = updates.environmentSnapshots
            if !environments.isEmpty {
                SettingsRowDivider()
                environmentRows(environments)
            }
            SettingsRowDivider()
            disclosureHeader(
                "Remote server setup",
                detail: "Install the Swft server service on a new Mac so it can update remotely.",
                isExpanded: $showsServerSetup
            )
            SwftDisclosure(isExpanded: showsServerSetup) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Run this on the remote Mac, then pair it from Settings → Connections.")
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textSecondary)
                    SettingsCopyableCode(Self.serverInstallCommand, copyLabel: "Copy command")
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
            }
            SettingsRowDivider()
            disclosureHeader(
                "Private repository access",
                detail: "Optional GitHub token for checking releases of a private repository.",
                isExpanded: $showsTokenAccess,
                badge: updates.hasSavedToken ? ("Saved in Keychain", .ready) : nil
            )
            SwftDisclosure(isExpanded: showsTokenAccess) {
                tokenEditor
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
            }
        }
    }

    // MARK: Status

    private var statusRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsRow("Software update", description: statusDescription, statusIsError: isErrorStatus) {
                HStack(spacing: 8) {
                    SettingsStatusBadge(statusBadge.text, tone: statusBadge.tone)
                    statusActions
                }
            }
            if case .updating(_, _, let progress?, _) = updates.phase {
                SettingsProgressBar(fraction: progress)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
        .animation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion), value: updates.phase)
    }

    @ViewBuilder
    private var statusActions: some View {
        if case .partialFailure(_, _, let canContinueLocal) = updates.phase {
            SettingsPillButton("Retry", systemName: "arrow.clockwise", variant: .secondary) { updates.retryFailed() }
            if canContinueLocal {
                SettingsPillButton("Update this Mac", variant: .primary) { updates.continueLocalUpdate() }
            }
        } else {
            SettingsPillButton(
                "Check now",
                systemName: "arrow.clockwise",
                variant: .secondary,
                isLoading: updates.checkStatus == .checking,
                disabled: updates.isRunning
            ) {
                Task { await updates.checkForUpdates(userInitiated: true) }
            }
            if let plan = updates.plan, plan.hasActionableUpdate, !updates.isRunning {
                SettingsPillButton(UpdateLogic.actionTitle(targetCount: plan.targetCount), variant: .primary) {
                    updates.startUpdate()
                }
                .help(UpdateLogic.actionHeadline(version: plan.release.version, targetCount: plan.targetCount))
            }
        }
    }

    private var statusBadge: (text: String, tone: SettingsStatusBadge.Tone) {
        if updates.isRunning { return ("Updating", .warning) }
        if case .partialFailure = updates.phase { return ("Needs attention", .error) }
        if case .failed = updates.phase { return ("Update failed", .error) }
        switch updates.checkStatus {
        case .idle: return ("Not checked", .neutral)
        case .checking: return ("Checking…", .warning)
        case .upToDate: return ("Up to date", .ready)
        case .available: return ("v\(updates.release?.version ?? "") available", .warning)
        case .noReleases: return ("No releases yet", .neutral)
        case .failed: return ("Check failed", .error)
        }
    }

    private var isErrorStatus: Bool {
        if case .failed = updates.checkStatus { return true }
        if case .partialFailure = updates.phase { return true }
        if case .failed = updates.phase { return true }
        return false
    }

    private var statusDescription: String {
        switch updates.phase {
        case .updating(let headline, let detail, _, _):
            return [headline, detail].compactMap { $0 }.joined(separator: " · ")
        case .partialFailure(let summary, _, _):
            return summary
        case .completed(let message), .failed(let message):
            return message
        case .hidden, .available:
            break
        }
        let base: String = switch updates.checkStatus {
        case .idle: "Swft checks \(GitHubReleaseClient.defaultRepository) for new releases every few hours."
        case .checking: "Checking \(GitHubReleaseClient.defaultRepository)…"
        case .upToDate: "You're on the latest release."
        case .available: updates.updateHeadline.map { "\($0)." } ?? "A new release is available."
        case .noReleases: "No releases published yet on \(GitHubReleaseClient.defaultRepository)."
        case .failed(let message): message
        }
        guard let checked = updates.lastCheckedAt else { return base }
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        let relative = formatter.localizedString(for: checked, relativeTo: max(model.now, Date(), checked))
        return "\(base) Last checked \(relative)."
    }

    // MARK: Environments

    private func environmentRows(_ environments: [UpdateEnvironmentSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(environments.sorted { $0.isLocal && !$1.isLocal }) { env in
                HStack(spacing: 10) {
                    Image(systemName: env.machineSymbol)
                        .font(.system(size: 13))
                        .foregroundStyle(SwftColor.textSecondary)
                        .frame(width: 20)
                    Text(env.label)
                        .font(SwftType.label)
                        .foregroundStyle(SwftColor.textPrimary)
                        .lineLimit(1)
                    if let version = env.isLocal ? updates.localAppVersion : env.serverVersion {
                        Text("v\(version)")
                            .font(SwftType.monoSmall)
                            .foregroundStyle(SwftColor.textTertiary)
                    }
                    Spacer(minLength: 8)
                    environmentStatus(env)
                }
                .frame(minHeight: 32)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func environmentStatus(_ env: UpdateEnvironmentSnapshot) -> some View {
        let targetID = env.isLocal ? UpdateTargetEntry.localID : env.id
        if let target = updates.targets.first(where: { $0.id == targetID }) {
            SettingsStatusBadge(UpdateLogic.statusDetail(target.status), tone: tone(target.status))
        } else if let readiness = UpdateLogic.readiness(of: env, localAppVersion: updates.localAppVersion, release: updates.release) {
            SettingsStatusBadge(readiness.title, tone: tone(readiness))
                .help(readiness == .needsServiceInstall ? UpdateLogic.serviceInstallReason : "")
        }
    }

    private func tone(_ readiness: EnvironmentUpdateReadiness) -> SettingsStatusBadge.Tone {
        switch readiness {
        case .upToDate, .readyForRemoteUpdates: .ready
        case .updateAvailable, .needsServiceInstall: .warning
        case .offline: .neutral
        }
    }

    private func tone(_ status: UpdateTargetStatus) -> SettingsStatusBadge.Tone {
        switch status {
        case .succeeded: .ready
        case .failed: .error
        case .queued, .skipped: .neutral
        case .downloading, .verifying, .installing, .restarting: .warning
        }
    }

    // MARK: Disclosures

    private func disclosureHeader(
        _ title: String,
        detail: String,
        isExpanded: Binding<Bool>,
        badge: (text: String, tone: SettingsStatusBadge.Tone)? = nil
    ) -> some View {
        Button {
            withAnimation(SwftMotion.resolve(SwftMotion.disclosure, reduceMotion: reduceMotion)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(SwftType.labelStrong)
                        .foregroundStyle(SwftColor.textPrimary)
                    Text(detail)
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if let badge {
                    SettingsStatusBadge(badge.text, tone: badge.tone)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SwftColor.textTertiary)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isExpanded.wrappedValue ? "Expanded" : "Collapsed")
    }

    private var tokenEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SecureField(updates.hasSavedToken ? "Replace saved token" : "GitHub token (repo read access)", text: $tokenDraft)
                    .textFieldStyle(.plain)
                    .font(SwftType.monoSmall)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous).fill(SwftColor.surface))
                    .overlay(RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous).strokeBorder(SwftColor.borderSubtle))
                    .onSubmit(saveToken)
                SettingsPillButton("Save", variant: .primary, disabled: tokenDraft.trimmingCharacters(in: .whitespaces).isEmpty) {
                    saveToken()
                }
                if updates.hasSavedToken {
                    SettingsPillButton("Remove", variant: .destructive) {
                        updates.removeToken()
                    }
                }
            }
            if let error = updates.tokenError {
                Text(error)
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.danger)
            } else {
                Text("Stored in your Keychain and only sent to api.github.com.")
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.textTertiary)
            }
        }
    }

    private func saveToken() {
        let token = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        updates.saveToken(token)
        tokenDraft = ""
        if updates.tokenError == nil {
            model.checkForUpdates(userInitiated: false)
        }
    }
}
