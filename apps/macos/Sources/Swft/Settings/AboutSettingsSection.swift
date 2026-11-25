import SwftDesign
import SwiftUI

struct AboutSettingsSection: View {
    @Environment(AppModel.self) private var model

    private var settings: SettingsController { model.settings }

    private var statusBadge: (text: String, tone: SettingsStatusBadge.Tone) {
        switch model.serverStatus {
        case .starting:
            return ("Starting local server…", .warning)
        case .connecting:
            return ("Connecting…", .warning)
        case .connected(let label, let count, let port):
            let portSuffix = port.map { " :\($0)" } ?? ""
            let unit = count == 1 ? "provider" : "providers"
            return ("\(label)\(portSuffix) · \(count) \(unit)", .ready)
        case .reconnecting(let attempt, _):
            return ("Reconnecting (attempt \(attempt))…", .warning)
        case .failed:
            return ("Server offline", .error)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            identityCard

            AboutUpdatesCard()

            SettingsSectionCard("Server") {
                SettingsRow("Local server", description: serverStatusDescription) {
                    HStack(spacing: 10) {
                        SettingsStatusBadge(statusBadge.text, tone: statusBadge.tone)
                        if !model.isMock {
                            SettingsPillButton(
                                model.serverStatus.isConnected ? "Reconnect" : "Retry",
                                systemName: "arrow.clockwise",
                                variant: model.serverStatus.needsRetry ? .primary : .secondary
                            ) {
                                model.retryConnection()
                            }
                        }
                    }
                }

                SettingsRowDivider()

                SettingsValueRow(
                    "Server version",
                    value: settings.environmentDescriptor.map { "v\($0.serverVersion)" } ?? "Not connected",
                    monospaced: settings.environmentDescriptor != nil
                ) {
                    if let proto = settings.environmentDescriptor?.orchestrationProtocolVersion {
                        Text("Protocol v\(proto)")
                            .font(SwftType.caption)
                            .foregroundStyle(SwftColor.textTertiary)
                    }
                }

                if let env = settings.environmentDescriptor {
                    SettingsRowDivider()
                    SettingsValueRow(
                        "Environment",
                        value: "\(env.label) · \(AboutSettingsLogic.formatPlatform(env.platform))"
                    )
                }
            }

            SettingsSectionCard("Storage") {
                let dataPath = AboutSettingsLogic.abbreviateHomePath(settings.dataDirectoryURL.path)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Data folder")
                                .font(SwftType.labelStrong)
                                .foregroundStyle(SwftColor.textPrimary)
                            Text("Stores threads, database state, logs, and local configuration.")
                                .font(SwftType.caption)
                                .foregroundStyle(SwftColor.textSecondary)
                        }
                        Spacer(minLength: 8)
                        SettingsPillButton(
                            "Reveal in Finder",
                            systemName: "folder",
                            variant: .secondary
                        ) {
                            settings.revealDataFolderInFinder()
                        }
                    }
                    SettingsCopyableCode(dataPath, copyLabel: "Copy path")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 13)

                if let cwd = settings.serverWorkingDirectory {
                    SettingsRowDivider()
                    SettingsValueRow(
                        "Server working directory",
                        value: AboutSettingsLogic.abbreviateHomePath(cwd),
                        monospaced: true
                    )
                }
            }
        }
    }

    private var identityCard: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(SwftColor.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(SwftColor.borderSubtle)
                    )
                SwftMark(size: 26)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Swft")
                        .font(SwftType.brand)
                        .foregroundStyle(SwftColor.textPrimary)
                    Text("v\(settings.appVersion)")
                        .font(SwftType.monoSmall)
                        .foregroundStyle(SwftColor.onSend)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(Capsule().fill(SwftColor.accentSoft))
                }
                Text("Native macOS client for coding agents.")
                    .font(SwftType.label)
                    .foregroundStyle(SwftColor.textSecondary)
            }

            Spacer(minLength: 8)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: SwftRadius.xl, style: .continuous).fill(SwftColor.surfaceMuted))
        .overlay(RoundedRectangle(cornerRadius: SwftRadius.xl, style: .continuous).strokeBorder(SwftColor.borderSubtle))
    }

    private var serverStatusDescription: String? {
        if case .failed(let message) = model.serverStatus {
            return message
        }
        return nil
    }
}
