import AppKit
import SwftDesign
import SwftKit
import SwiftUI

/// Runtime installation and in-app sign-in controls for an expanded provider row.
/// Mirrors Studio's `ProviderSetupControls.tsx` + `useProviderSetup.ts`.
struct ProviderSetupControlsView: View {
    @Environment(AppModel.self) private var model
    let provider: ProviderEntry
    let disabled: Bool

    @State private var selectedMethodID = ""
    @State private var credentialValues: [String: String] = [:]
    @State private var callbackURLDraft = ""
    @State private var manualCallbackExpanded = false
    @State private var copiedTarget: String?
    @State private var confirmAction: ConfirmAction?

    private enum ConfirmAction {
        case logout
        case removeInstall
    }

    private var settings: SettingsController { model.settings }
    private var installState: ProviderInstallState? { settings.installStates[provider.id] }
    private var authState: ProviderAuthState? { settings.authStates[provider.id] }
    private var isPending: Bool { settings.setupPendingIDs.contains(provider.id) }
    private var controlsDisabled: Bool { disabled || isPending }

    private var installView: ProviderInstallViewModel {
        ProviderSettingsLogic.deriveProviderInstallView(provider: provider, installState: installState)
    }

    private var authView: ProviderAuthViewModel {
        ProviderSettingsLogic.deriveProviderAuthView(
            provider: provider,
            authState: authState,
            authError: settings.authErrors[provider.id],
            isRemote: false,
            runtimeInstalled: provider.supportsInstall ? installView.installed : provider.installed
        )
    }

    private var combinedError: String? {
        settings.setupActionErrors[provider.id]
            ?? settings.authErrors[provider.id]
            ?? settings.installErrors[provider.id]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if provider.supportsInstall {
                installControls
            }

            if provider.supportsInstall && provider.supportsAuth {
                Divider().overlay(SwftColor.borderSubtle)
            }

            if provider.supportsAuth {
                authControls
            }

            if let combinedError {
                SettingsBanner(combinedError, tone: .error)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: SwftRadius.l, style: .continuous).fill(SwftColor.surface))
        .overlay(RoundedRectangle(cornerRadius: SwftRadius.l, style: .continuous).strokeBorder(SwftColor.borderSubtle))
        .confirmationDialog(
            confirmAction == .logout ? "Sign out" : "Remove downloaded runtime",
            isPresented: Binding(
                get: { confirmAction != nil },
                set: { if !$0 { confirmAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if confirmAction == .logout {
                Button("Sign out", role: .destructive) {
                    settings.logoutProviderAuth(for: provider.id)
                    confirmAction = nil
                }
            } else if confirmAction == .removeInstall {
                Button("Remove", role: .destructive) {
                    settings.removeProviderInstallation(for: provider.id)
                    confirmAction = nil
                }
            }
            Button("Cancel", role: .cancel) { confirmAction = nil }
        } message: {
            if confirmAction == .logout {
                Text("Sign out of \(provider.label)? Running threads that share this sign-in will stop. Thread history is kept.")
            } else {
                Text("Remove the managed runtime for \(provider.label)? Your sign-in and thread history are kept.")
            }
        }
    }

    private var installControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Runtime")
                        .font(SwftType.labelStrong)
                        .foregroundStyle(SwftColor.textPrimary)
                    Text(installView.description)
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textSecondary)
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    if installView.canCancel, let operationID = installState?.operationId {
                        SettingsPillButton("Cancel", variant: .quiet, disabled: controlsDisabled) {
                            settings.cancelProviderInstall(for: provider.id, operationID: operationID)
                        }
                    } else if installView.canInstall {
                        SettingsPillButton(
                            installView.actionLabel,
                            variant: (!installView.installed || installView.updateAvailable) ? .primary : .secondary,
                            isLoading: installView.active,
                            disabled: controlsDisabled || authView.active || settings.installErrors[provider.id] != nil
                        ) {
                            settings.startProviderInstall(for: provider.id)
                        }
                    }
                    if installView.canRemove {
                        SettingsPillButton("Remove", variant: .quiet, disabled: controlsDisabled || authView.active) {
                            confirmAction = .removeInstall
                        }
                    }
                }
            }

            if let progress = installView.progressFraction {
                SettingsProgressBar(fraction: progress)
            }
        }
    }

    private var authControls: some View {
        let methods = authState?.methods ?? []
        let interaction = authState?.interaction
        let showCallbackForm = authView.actionURL != nil
            && authState?.flowId != nil
            && authView.active
            && (authView.showCallbackInput || manualCallbackExpanded)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Account")
                        .font(SwftType.labelStrong)
                        .foregroundStyle(SwftColor.textPrimary)
                    Text(authView.description)
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    if !authView.active && methods.count > 1 {
                        Menu {
                            Button("Provider default") { selectedMethodID = "" }
                            ForEach(methods) { method in
                                Button(method.name) { selectedMethodID = method.id }
                            }
                        } label: {
                            let label = methods.first(where: { $0.id == selectedMethodID })?.name ?? "Provider default"
                            SettingsMenuTrigger(label, disabled: controlsDisabled)
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    }

                    if let actionURL = authView.actionURL {
                        SettingsPillButton("Open browser", systemName: "safari", variant: .primary, disabled: controlsDisabled) {
                            let requiresConsent: Bool
                            if case .browser(_, _, let consent, _) = interaction {
                                requiresConsent = consent
                            } else {
                                requiresConsent = false
                            }
                            settings.openProviderSignInURL(
                                for: provider.id,
                                url: actionURL,
                                requiresConsent: requiresConsent,
                                flowID: authState?.flowId,
                                interactionID: interaction?.id
                            )
                        }
                        SettingsPillButton(
                            copiedTarget == "url" ? "Copied" : "Copy link",
                            systemName: copiedTarget == "url" ? "checkmark" : "doc.on.doc",
                            variant: .quiet,
                            disabled: controlsDisabled
                        ) {
                            copyToClipboard(actionURL, target: "url")
                        }
                    }

                    if authView.needsExternalSetup,
                       let docs = provider.setup?.documentationUrl,
                       ProviderSettingsLogic.isWebURL(docs),
                       let url = URL(string: docs)
                    {
                        SettingsPillButton("Open docs", systemName: "arrow.up.right", variant: .secondary) {
                            NSWorkspace.shared.open(url)
                        }
                    } else if authView.canCancel, let flowID = authState?.flowId {
                        SettingsPillButton("Cancel", variant: .quiet, disabled: controlsDisabled) {
                            settings.cancelProviderAuth(for: provider.id, flowID: flowID)
                        }
                    } else if !authView.active && !authView.needsExternalSetup && provider.setup?.canAuthenticate != false {
                        SettingsPillButton(
                            authView.startLabel,
                            variant: authView.signedIn ? .secondary : .primary,
                            isLoading: isPending,
                            disabled: controlsDisabled || !authView.canStart || installView.active || settings.authErrors[provider.id] != nil
                        ) {
                            startSignIn(methods: methods)
                        }
                    }

                    if authView.canLogout {
                        SettingsPillButton("Sign out", variant: .quiet, disabled: controlsDisabled || installView.active) {
                            confirmAction = .logout
                        }
                    }
                }
            }

            if let statusMessage = authView.statusMessage {
                Text(statusMessage)
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case .deviceCode(_, _, let userCode) = interaction, authView.active {
                HStack(spacing: 8) {
                    Text("Enter code")
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textSecondary)
                    Text(userCode)
                        .font(SwftType.mono)
                        .foregroundStyle(SwftColor.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(SwftColor.surfaceMuted))
                        .textSelection(.enabled)
                    SettingsPillButton(
                        copiedTarget == "code" ? "Copied" : "Copy code",
                        systemName: copiedTarget == "code" ? "checkmark" : "doc.on.doc",
                        variant: .quiet
                    ) {
                        copyToClipboard(userCode, target: "code")
                    }
                }
            }

            if case .credentials(let interactionID, let fields) = interaction, authView.active, let flowID = authState?.flowId {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(fields) { field in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(field.label)
                                .font(SwftType.caption)
                                .foregroundStyle(SwftColor.textSecondary)
                            Group {
                                if field.secret {
                                    SecureField("", text: bindingForCredential(field.name))
                                } else {
                                    TextField("", text: bindingForCredential(field.name))
                                }
                            }
                            .textFieldStyle(.plain)
                            .font(SwftType.monoSmall)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(SwftColor.surfaceMuted))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(SwftColor.borderSubtle))
                            .disabled(controlsDisabled)
                        }
                    }
                    SettingsPillButton("Connect", variant: .primary, disabled: controlsDisabled) {
                        settings.respondProviderAuth(
                            for: provider.id,
                            flowID: flowID,
                            interactionID: interactionID,
                            response: .credentials(values: credentialValues)
                        )
                        credentialValues.removeAll()
                    }
                }
            }

            if authView.actionURL != nil,
               authState?.flowId != nil,
               authView.active,
               !authView.showCallbackInput,
               !manualCallbackExpanded,
               !isDeviceCode(interaction)
            {
                Button("Having trouble? Paste redirect URL") {
                    manualCallbackExpanded = true
                }
                .buttonStyle(.plain)
                .font(SwftType.caption)
                .foregroundStyle(SwftColor.accent)
            }

            if showCallbackForm, let flowID = authState?.flowId {
                VStack(alignment: .leading, spacing: 6) {
                    Text("If sign-in does not return automatically, paste the localhost redirect URL from your browser:")
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textTertiary)
                    HStack(spacing: 8) {
                        TextField("http://localhost:...", text: $callbackURLDraft)
                            .textFieldStyle(.plain)
                            .font(SwftType.monoSmall)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(SwftColor.surfaceMuted))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(SwftColor.borderSubtle))
                            .disabled(controlsDisabled)
                        SettingsPillButton(
                            "Continue",
                            variant: .primary,
                            disabled: controlsDisabled || callbackURLDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ) {
                            let url = callbackURLDraft
                            callbackURLDraft = ""
                            settings.completeProviderAuth(for: provider.id, flowID: flowID, callbackURL: url)
                        }
                    }
                }
            }
        }
    }

    private func isDeviceCode(_ interaction: ProviderAuthInteraction?) -> Bool {
        if case .deviceCode = interaction { return true }
        return false
    }

    private func startSignIn(methods: [ProviderAuthMethod]) {
        let chosen: String?
        if !selectedMethodID.isEmpty, methods.contains(where: { $0.id == selectedMethodID }) {
            chosen = selectedMethodID
        } else if authView.signedIn, methods.contains(where: { $0.id == "chatgpt-change-account" }) {
            chosen = "chatgpt-change-account"
        } else {
            chosen = nil
        }
        manualCallbackExpanded = false
        settings.startProviderAuth(for: provider.id, methodID: chosen)
    }

    private func bindingForCredential(_ name: String) -> Binding<String> {
        Binding(
            get: { credentialValues[name] ?? "" },
            set: { credentialValues[name] = $0 }
        )
    }

    private func copyToClipboard(_ value: String, target: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copiedTarget = target
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1600))
            if copiedTarget == target { copiedTarget = nil }
        }
    }
}
