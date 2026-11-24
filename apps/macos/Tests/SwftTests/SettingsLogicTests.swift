import AppKit
import Foundation
import SwftKit
import Testing
@testable import Swft

@Suite("Settings Logic")
struct SettingsLogicTests {
    // MARK: - Sections & Local Preferences

    @Test func parsesSettingsSectionLaunchArguments() {
        #expect(SettingsSection.fromLaunchArgument("general") == .general)
        #expect(SettingsSection.fromLaunchArgument("  PROVIDERS ") == .providers)
        #expect(SettingsSection.fromLaunchArgument("connections") == .connections)
        #expect(SettingsSection.fromLaunchArgument("notifications") == .notifications)
        #expect(SettingsSection.fromLaunchArgument("about") == .about)
        #expect(SettingsSection.fromLaunchArgument("unknown") == nil)
        #expect(SettingsSection.fromLaunchArgument("   ") == nil)
        #expect(SettingsSection.fromLaunchArgument(nil) == nil)
    }

    @Test func persistsAppearanceAndNotificationPreferencesInUserDefaults() throws {
        let suiteName = "SettingsLogicTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(AppearancePreference.load(from: defaults) == .system)
        #expect(AppearancePreference.system.nsAppearanceName == nil)
        #expect(AppearancePreference.light.nsAppearanceName == .aqua)
        #expect(AppearancePreference.dark.nsAppearanceName == .darkAqua)

        defaults.set(AppearancePreference.dark.rawValue, forKey: AppearancePreference.defaultsKey)
        #expect(AppearancePreference.load(from: defaults) == .dark)

        #expect(NotificationModePreference.load(from: defaults) == .off)
        #expect(!NotificationModePreference.off.includesSystemNotification)
        #expect(!NotificationModePreference.off.includesSound)
        #expect(NotificationModePreference.notifications.includesSystemNotification)
        #expect(!NotificationModePreference.notifications.includesSound)
        #expect(!NotificationModePreference.sound.includesSystemNotification)
        #expect(NotificationModePreference.sound.includesSound)
        #expect(NotificationModePreference.notificationsAndSound.includesSystemNotification)
        #expect(NotificationModePreference.notificationsAndSound.includesSound)

        defaults.set(
            NotificationModePreference.notificationsAndSound.rawValue,
            forKey: NotificationModePreference.defaultsKey
        )
        #expect(NotificationModePreference.load(from: defaults) == .notificationsAndSound)
    }

    @Test func mapsIdleCompactionPatchForModernAndLegacyServers() {
        let modern = ServerSettings(idleCompaction: .onReturn)
        let modernPatch = SettingsValuePresentation.idleCompactionPatch(current: modern, next: .beforeCacheExpires)
        #expect(modernPatch.idleCompaction == .beforeCacheExpires)
        #expect(modernPatch.compactIdleThreads == nil)

        let legacyString = ServerSettings(idleCompaction: nil, compactIdleThreads: .string("onReturn"))
        let legacyStringPatch = SettingsValuePresentation.idleCompactionPatch(current: legacyString, next: .off)
        #expect(legacyStringPatch.idleCompaction == nil)
        #expect(legacyStringPatch.compactIdleThreads == .string("off"))

        let legacyBool = ServerSettings(idleCompaction: nil, compactIdleThreads: .bool(false))
        let legacyBoolPatch = SettingsValuePresentation.idleCompactionPatch(current: legacyBool, next: .beforeCacheExpires)
        #expect(legacyBoolPatch.idleCompaction == nil)
        #expect(legacyBoolPatch.compactIdleThreads == .bool(true))
    }

    // MARK: - Provider Formatting, Ordering & Status

    @Test func formatsProviderVersionsAndAccounts() {
        #expect(ProviderSettingsLogic.formatProviderVersion("0.50.0") == "v0.50.0")
        #expect(ProviderSettingsLogic.formatProviderVersion("v1.2.3") == "v1.2.3")
        #expect(ProviderSettingsLogic.formatProviderVersion("agy_acp_server_20260401_120000_rc1") == "2026-04-01 rc1")
        #expect(ProviderSettingsLogic.formatProviderVersion("agy_acp_server_20260401_120000") == "2026-04-01")
        #expect(ProviderSettingsLogic.formatProviderVersion("   ") == nil)

        let signedIn = ServerProviderAuth(status: .authenticated, type: "oauth", label: "ChatGPT Plus", email: "dev@example.com")
        #expect(ProviderSettingsLogic.formatProviderAccount(signedIn) == "ChatGPT Plus · dev@example.com")

        let sameLabelAndEmail = ServerProviderAuth(status: .authenticated, label: "dev@example.com", email: "dev@example.com")
        #expect(ProviderSettingsLogic.formatProviderAccount(sameLabelAndEmail) == "dev@example.com")

        let signedOut = ServerProviderAuth(status: .unauthenticated, label: "ChatGPT")
        #expect(ProviderSettingsLogic.formatProviderAccount(signedOut) == nil)
    }

    @Test func sortsProviderEntriesWithDefaultFirstPerDriverAndResolvesExpandID() {
        let providers = [
            makeProvider(id: "codex_work", driver: "codex", displayName: "Codex Work"),
            makeProvider(id: "claudeAgent", driver: "claudeAgent", displayName: "Claude"),
            makeProvider(id: "codex", driver: "codex", displayName: "Codex"),
        ]
        let sorted = ProviderSettingsLogic.sortedProviderEntries(providers: providers, settings: nil)
        #expect(sorted.map(\.id) == ["codex", "codex_work", "claudeAgent"])

        #expect(ProviderSettingsLogic.resolveProviderExpandID(entries: sorted, requestedID: "codex_work") == "codex_work")
        #expect(ProviderSettingsLogic.resolveProviderExpandID(entries: sorted, requestedID: "claudeAgent") == "claudeAgent")
        #expect(ProviderSettingsLogic.resolveProviderExpandID(entries: sorted, requestedID: "missing") == nil)
    }

    @Test func derivesProviderStatusAcrossStates() {
        let disabled = ProviderSettingsLogic.buildProviderEntry(
            snapshot: makeProvider(id: "cursor", driver: "cursor", enabled: false, status: .disabled),
            instanceConfig: nil
        )
        #expect(ProviderSettingsLogic.deriveProviderStatus(disabled) == .init(tone: .neutral, version: nil, text: "Disabled", truncatedMessage: false))

        let updating = ProviderSettingsLogic.buildProviderEntry(
            snapshot: makeProvider(
                id: "codex",
                driver: "codex",
                version: "0.50.0",
                updateState: ServerProviderUpdateState(status: "running", message: "Installing 0.51.0")
            ),
            instanceConfig: nil
        )
        let updatingStatus = ProviderSettingsLogic.deriveProviderStatus(updating)
        #expect(updatingStatus.tone == .working)
        #expect(updatingStatus.version == "v0.50.0")
        #expect(updatingStatus.text == "Updating · Installing 0.51.0")

        let notInstalled = ProviderSettingsLogic.buildProviderEntry(
            snapshot: makeProvider(id: "kiro", driver: "kiro", installed: false, status: .warning),
            instanceConfig: nil
        )
        #expect(ProviderSettingsLogic.deriveProviderStatus(notInstalled).text == "Not installed")

        let unauth = ProviderSettingsLogic.buildProviderEntry(
            snapshot: makeProvider(
                id: "antigravity",
                driver: "antigravity",
                version: "2026-04-01",
                status: .warning,
                auth: ServerProviderAuth(status: .unauthenticated, label: "Google account")
            ),
            instanceConfig: nil
        )
        let unauthStatus = ProviderSettingsLogic.deriveProviderStatus(unauth)
        #expect(unauthStatus.tone == .warning)
        #expect(unauthStatus.text == "Not signed in · Google account")

        let uncheckedAgy = ProviderSettingsLogic.buildProviderEntry(
            snapshot: makeProvider(
                id: "antigravity",
                driver: "antigravity",
                status: .warning,
                auth: ServerProviderAuth(status: .unknown, type: "oauth-personal")
            ),
            instanceConfig: nil
        )
        #expect(ProviderSettingsLogic.deriveProviderStatus(uncheckedAgy).text == "Installed · Sign-in not checked")

        let readyWithAdvisory = ProviderSettingsLogic.buildProviderEntry(
            snapshot: makeProvider(
                id: "codex",
                driver: "codex",
                version: "0.50.0",
                status: .ready,
                auth: ServerProviderAuth(status: .authenticated, label: "Plus", email: "dev@example.com"),
                versionAdvisory: ServerProviderVersionAdvisory(status: "outdated", latestVersion: "0.52.0")
            ),
            instanceConfig: nil
        )
        let readyStatus = ProviderSettingsLogic.deriveProviderStatus(readyWithAdvisory)
        #expect(readyStatus.tone == .ready)
        #expect(readyStatus.text == "Signed in · Plus · dev@example.com · Update available: v0.52.0")

        let longErr = String(repeating: "x", count: 160)
        let errorEntry = ProviderSettingsLogic.buildProviderEntry(
            snapshot: makeProvider(id: "pi", driver: "pi", status: .error, message: longErr),
            instanceConfig: nil
        )
        let errStatus = ProviderSettingsLogic.deriveProviderStatus(errorEntry)
        #expect(errStatus.tone == .error)
        #expect(errStatus.truncatedMessage)
        #expect(errStatus.text.hasSuffix("…"))
    }

    // MARK: - Provider Options, Custom Models, Environment & Accounts

    @Test func validatesFieldsAndBuildsNextConfig() throws {
        let claudeFields = ProviderSettingsLogic.fields(for: "claudeAgent", config: nil)
        let compactField = try #require(claudeFields.first { $0.key == "autoCompactWindow" })
        #expect(ProviderSettingsLogic.validateFieldValue("", for: compactField) == nil)
        #expect(ProviderSettingsLogic.validateFieldValue("300000", for: compactField) == nil)
        #expect(ProviderSettingsLogic.validateFieldValue("50000", for: compactField) != nil)
        #expect(ProviderSettingsLogic.validateFieldValue("abc", for: compactField) != nil)

        let binaryField = try #require(claudeFields.first { $0.key == "binaryPath" })
        let added = ProviderSettingsLogic.nextConfig(from: nil, field: binaryField, value: "/usr/local/bin/claude")
        #expect(added?["binaryPath"] == .string("/usr/local/bin/claude"))
        let cleared = ProviderSettingsLogic.nextConfig(from: added, field: binaryField, value: "   ")
        #expect(cleared == nil)

        // Antigravity binaryPath keeps empty string instead of omitting.
        let agyFields = ProviderSettingsLogic.fields(for: "antigravity", config: nil)
        let agyBin = try #require(agyFields.first { $0.key == "binaryPath" })
        let agyCleared = ProviderSettingsLogic.nextConfig(from: ["binaryPath": .string("/tmp/agy")], field: agyBin, value: "")
        #expect(agyCleared?["binaryPath"] == .string(""))

        // ACP Registry switches fields based on source.
        let acpRegistryFields = ProviderSettingsLogic.fields(for: "acpRegistry", config: nil)
        #expect(acpRegistryFields.contains { $0.key == "agentId" })
        let acpLocalFields = ProviderSettingsLogic.fields(for: "acpRegistry", config: ["source": .string("local")])
        #expect(!acpLocalFields.contains { $0.key == "agentId" })
        #expect(acpLocalFields.contains { $0.key == "commandPath" })
    }

    @Test func validatesCustomModelsAndEnvironmentVariables() {
        let builtIns = [
            ProviderModelEntry(slug: "gpt-6-astra", name: "GPT-6 Astra", subProvider: nil, isCustom: false),
        ]
        #expect(ProviderSettingsLogic.validateCustomModelSlug("custom-1", driver: "codex", models: builtIns, customModels: []) == .success("custom-1"))
        #expect(ProviderSettingsLogic.validateCustomModelSlug("gpt-6-astra", driver: "codex", models: builtIns, customModels: []) == .failure(.message("That model is already built in.")))
        #expect(ProviderSettingsLogic.validateCustomModelSlug("custom-1", driver: "codex", models: builtIns, customModels: ["custom-1"]) == .failure(.message("That custom model is already saved.")))
        #expect(ProviderSettingsLogic.validateCustomModelSlug("any", driver: "antigravity", models: [], customModels: []) == .failure(.message("Antigravity does not support custom models.")))

        #expect(ProviderSettingsLogic.isValidEnvironmentVariableName("OPENAI_API_KEY"))
        #expect(ProviderSettingsLogic.isValidEnvironmentVariableName("_CUSTOM_1"))
        #expect(!ProviderSettingsLogic.isValidEnvironmentVariableName("1BAD"))
        #expect(!ProviderSettingsLogic.isValidEnvironmentVariableName("BAD-NAME"))
        #expect(!ProviderSettingsLogic.isValidEnvironmentVariableName(""))

        let env1 = ProviderSettingsLogic.nextEnvironment(from: [], settingName: "CURSOR_API_KEY", value: "sk-1", sensitive: true)
        #expect(env1.count == 1)
        #expect(env1[0].sensitive)
        let env2 = ProviderSettingsLogic.nextEnvironment(from: env1, settingName: "CURSOR_API_KEY", value: "   ", sensitive: true)
        #expect(env2.isEmpty)
    }

    @Test func buildsEnabledConfigDroppingLegacyFlagAndDerivesAccountDrafts() throws {
        let legacy = ProviderInstanceConfig(
            driver: "codex",
            enabled: nil,
            config: .object(["enabled": .bool(true), "binaryPath": .string("/usr/bin/codex")])
        )
        let disabled = ProviderSettingsLogic.buildEnabledInstanceConfig(previous: legacy, enabled: false)
        #expect(disabled.enabled == false)
        #expect(disabled.configObject?["enabled"] == nil)
        #expect(disabled.configObject?["binaryPath"] == .string("/usr/bin/codex"))

        let id1 = ProviderSettingsLogic.deriveAccountInstanceID(driver: "codex", name: "Work Account!", existingIDs: ["codex"])
        #expect(id1 == "codex_work_account")
        let id2 = ProviderSettingsLogic.deriveAccountInstanceID(driver: "codex", name: "Work Account!", existingIDs: ["codex", "codex_work_account"])
        #expect(id2 == "codex_work_account_2")

        #expect(ProviderSettingsLogic.suggestClaudeConfigDir(for: "Claude Work") == "~/.claude-work")
        #expect(ProviderSettingsLogic.suggestClaudeConfigDir(for: "Claude Code") == "~/.claude-account")
        #expect(ProviderSettingsLogic.claudeLoginCommand(homePath: "~/.claude-work") == "mkdir -p ~/.claude-work && CLAUDE_CONFIG_DIR=~/.claude-work claude auth login")
        #expect(ProviderSettingsLogic.claudeLoginCommand(homePath: "~/my dir") == "mkdir -p ~/'my dir' && CLAUDE_CONFIG_DIR=~/'my dir' claude auth login")

        let codexDraft = try ProviderSettingsLogic.buildCreateAccountDraft(
            preset: .codex,
            name: "Personal",
            accentColor: "#3b82f6",
            existingIDs: ["codex"]
        ).get()
        #expect(codexDraft.instanceId == "codex_personal")
        #expect(codexDraft.instance.configObject?["setupMode"] == .string("managed"))

        let claudeDraft = try ProviderSettingsLogic.buildCreateAccountDraft(
            preset: .claude,
            name: "Claude Work",
            claudeConfigDir: "~/.claude-work",
            existingIDs: ["claudeAgent"]
        ).get()
        #expect(claudeDraft.instance.driver == "claudeAgent")
        #expect(claudeDraft.instance.configObject?["homePath"] == .string("~/.claude-work"))

        let emptyError = ProviderSettingsLogic.buildCreateAccountDraft(preset: .codex, name: "   ", existingIDs: [])
        #expect(emptyError == .failure(.message("Enter a name for this account.")))
    }

    @Test func derivesAuthInstallViewsAndFormatsAboutPaths() {
        let entry = ProviderSettingsLogic.buildProviderEntry(
            snapshot: makeProvider(
                id: "codex",
                driver: "codex",
                installed: true,
                status: .warning,
                auth: ServerProviderAuth(status: .unauthenticated),
                setup: ServerProviderSetup(canAuthenticate: true, canInstall: true)
            ),
            instanceConfig: nil
        )
        let waitingState = ProviderAuthState(
            instanceId: "codex",
            phase: .waiting,
            flowId: "flow-1",
            interaction: .browser(id: "i-1", url: "https://example.com/auth", requiresConsent: false, acceptsCallback: true)
        )
        let authView = ProviderSettingsLogic.deriveProviderAuthView(
            provider: entry,
            authState: waitingState,
            authError: nil,
            isRemote: false
        )
        #expect(authView.active)
        #expect(authView.actionURL == "https://example.com/auth")
        #expect(authView.showCallbackInput)
        #expect(authView.canCancel)
        #expect(!authView.canStart)

        let downloading = ProviderInstallState(
            driver: "codex",
            operationId: "op-1",
            phase: .downloading,
            downloadedBytes: 5_000_000,
            totalBytes: 10_000_000
        )
        let installView = ProviderSettingsLogic.deriveProviderInstallView(provider: entry, installState: downloading)
        #expect(installView.active)
        #expect(installView.progressFraction == 0.5)
        #expect(installView.canCancel)
        #expect(!installView.canInstall)

        #expect(ProviderSettingsLogic.isWebURL("https://example.com/login"))
        #expect(!ProviderSettingsLogic.isWebURL("javascript:alert(1)"))
        #expect(!ProviderSettingsLogic.isWebURL("file:///etc/passwd"))

        #expect(AboutSettingsLogic.abbreviateHomePath("/Users/alice/Library/Application Support/Swft", homeDirectory: "/Users/alice") == "~/Library/Application Support/Swft")
        #expect(AboutSettingsLogic.abbreviateHomePath("/opt/swft", homeDirectory: "/Users/alice") == "/opt/swft")
        #expect(AboutSettingsLogic.formatPlatform(ExecutionEnvironmentPlatform(os: "darwin", arch: "arm64")) == "macOS (arm64)")
    }

    // MARK: - Model Picker Signed-Out Deep-Link Hook

    @MainActor
    @Test func modelPickerSignedOutActionDeepLinksToProvidersAndPreservesFallback() {
        let model = AppModel.mock()
        model.destination = .home
        model.toggleModelPicker()
        #expect(model.modelPicker != nil)

        // Default hook deep-links to Settings -> Providers and expands the requested provider.
        model.runPickerPanelAction(harnessID: "antigravity")
        #expect(model.destination == .settings)
        #expect(model.settings.section == .providers)
        #expect(model.settings.expandedProviderID == "antigravity")
        #expect(model.modelPicker == nil)

        // Removing the hook restores the previous fallback without navigating away.
        model.destination = .home
        model.openProviderSettingsAction = nil
        model.runPickerPanelAction(harnessID: "antigravity")
        #expect(model.destination == .home)
    }

    // MARK: - Helpers

    private func makeProvider(
        id: String,
        driver: String,
        displayName: String? = nil,
        enabled: Bool = true,
        installed: Bool = true,
        version: String? = nil,
        status: ServerProviderState = .ready,
        auth: ServerProviderAuth = ServerProviderAuth(status: .authenticated),
        message: String? = nil,
        setup: ServerProviderSetup? = nil,
        versionAdvisory: ServerProviderVersionAdvisory? = nil,
        updateState: ServerProviderUpdateState? = nil
    ) -> ServerProvider {
        ServerProvider(
            instanceId: id,
            driver: driver,
            displayName: displayName,
            enabled: enabled,
            installed: installed,
            version: version,
            status: status,
            auth: auth,
            checkedAt: Date(timeIntervalSince1970: 1_700_000_000),
            message: message,
            models: [],
            setup: setup,
            versionAdvisory: versionAdvisory,
            updateState: updateState
        )
    }
}
