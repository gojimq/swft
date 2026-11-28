import AppKit
import Foundation
import SwftDesign
import SwftKit

// MARK: - Sections & Local Preferences

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general
    case providers
    case connections
    case notifications
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .providers: "Providers"
        case .connections: "Connections"
        case .notifications: "Notifications"
        case .about: "About"
        }
    }

    var systemName: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .providers: "square.stack.3d.up"
        case .connections: "network"
        case .notifications: "bell"
        case .about: "info.circle"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Appearance, default model, and new-thread preferences."
        case .providers: "Manage provider accounts, sign-in, and CLI options."
        case .connections: "Connect to Swft servers on other machines."
        case .notifications: "Control system alerts and sounds for background threads."
        case .about: "App version, local server status, and storage paths."
        }
    }

    static func fromLaunchArgument(_ raw: String?) -> SettingsSection? {
        guard let normalized = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !normalized.isEmpty
        else { return nil }
        return SettingsSection(rawValue: normalized)
    }
}

enum AppearancePreference: String, CaseIterable, Identifiable, Hashable {
    case system
    case light
    case dark

    static let defaultsKey = "SwftAppearanceMode"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var nsAppearanceName: NSAppearance.Name? {
        switch self {
        case .system: nil
        case .light: .aqua
        case .dark: .darkAqua
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> AppearancePreference {
        guard let raw = defaults.string(forKey: defaultsKey),
              let parsed = AppearancePreference(rawValue: raw)
        else { return .system }
        return parsed
    }
}

enum UIScalePreference {
    static let defaultsKey = "SwftUIScale"

    static func load(from defaults: UserDefaults = .standard) -> CGFloat {
        guard defaults.object(forKey: defaultsKey) != nil else { return SwftUIScale.defaultScale }
        let raw = defaults.double(forKey: defaultsKey)
        guard raw > 0 else { return SwftUIScale.defaultScale }
        return SwftUIScale.clamp(CGFloat(raw))
    }

    static func save(_ scale: CGFloat, to defaults: UserDefaults = .standard) {
        let clamped = SwftUIScale.clamp(scale)
        if SwftUIScale.isDefault(clamped) {
            defaults.removeObject(forKey: defaultsKey)
        } else {
            defaults.set(Double(clamped), forKey: defaultsKey)
        }
    }
}

enum NotificationModePreference: String, CaseIterable, Identifiable, Hashable {
    case off = "off"
    case notifications = "notifications"
    case sound = "sound"
    case notificationsAndSound = "notifications-and-sound"

    static let defaultsKey = "SwftNotificationMode"
    static let notifyOnCompleteKey = "SwftNotifyOnComplete"
    static let notifyOnAttentionKey = "SwftNotifyOnAttention"
    static let inAppBannerKey = "SwftInAppNotificationsEnabled"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: "Off"
        case .notifications: "Notifications only"
        case .sound: "Sound only"
        case .notificationsAndSound: "Notifications with sound"
        }
    }

    var includesSystemNotification: Bool {
        self == .notifications || self == .notificationsAndSound
    }

    var includesSound: Bool {
        self == .sound || self == .notificationsAndSound
    }

    static func load(from defaults: UserDefaults = .standard) -> NotificationModePreference {
        guard let raw = defaults.string(forKey: defaultsKey),
              let parsed = NotificationModePreference(rawValue: raw)
        else { return .off }
        return parsed
    }
}

enum NotificationPermissionState: Equatable {
    case unknown
    case notDetermined
    case authorized
    case denied
    case unavailable

    var statusText: String {
        switch self {
        case .unknown: "Checking permission…"
        case .notDetermined: "Permission not requested yet"
        case .authorized: "Allowed in System Settings"
        case .denied: "Blocked in System Settings"
        case .unavailable: "Available when running Swft.app"
        }
    }
}

// MARK: - Server Setting Presentations & Mapping

enum SettingsValuePresentation {
    static func label(for mode: RuntimeMode) -> String {
        switch mode {
        case .approvalRequired: "Supervised"
        case .autoAcceptEdits: "Auto-accept edits"
        case .auto: "Auto"
        case .fullAccess: "Full access"
        }
    }

    static func description(for mode: RuntimeMode) -> String {
        switch mode {
        case .approvalRequired: "Ask before running commands or editing files."
        case .autoAcceptEdits: "Edit files automatically; ask before running commands."
        case .auto: "Run safe commands and edit files automatically."
        case .fullAccess: "Run commands and edit files without asking."
        }
    }

    static func label(for mode: ThreadEnvMode) -> String {
        switch mode {
        case .local: "Current checkout"
        case .worktree: "New worktree"
        }
    }

    static func label(for mode: ResponseStreamingMode) -> String {
        switch mode {
        case .paragraph: "Show finished paragraphs"
        case .turn: "Wait for the full response"
        }
    }

    static func description(for mode: ResponseStreamingMode) -> String {
        switch mode {
        case .paragraph: "Each paragraph or code block appears as soon as it is complete."
        case .turn: "Text appears once the agent finishes its turn."
        }
    }

    static func label(for mode: IdleCompactionMode) -> String {
        switch mode {
        case .onReturn: "When you return"
        case .beforeCacheExpires: "Before the cache expires (beta)"
        case .off: "Never"
        }
    }

    /// Matches `idleCompactionPatch` in `packages/contracts/src/settings.ts`.
    static func idleCompactionPatch(
        current: ServerSettings,
        next: IdleCompactionMode
    ) -> ServerSettingsPatch {
        if current.idleCompaction != nil {
            return ServerSettingsPatch(idleCompaction: next)
        }
        if case .string = current.compactIdleThreads {
            return ServerSettingsPatch(compactIdleThreads: .string(next.rawValue))
        }
        return ServerSettingsPatch(compactIdleThreads: .bool(next == .beforeCacheExpires))
    }
}

// MARK: - Provider Settings Logic (Ported from Studio's providers.logic.ts)

struct ProviderSettingsFieldOption: Equatable, Identifiable {
    let value: String
    let label: String
    var id: String { value }
}

struct ProviderSettingsFieldSpec: Equatable, Identifiable {
    enum Control: Equatable {
        case text
        case password
        case select([ProviderSettingsFieldOption])
    }

    let key: String
    let label: String
    let description: String
    let placeholder: String
    let control: Control
    let monospaced: Bool
    let clearWhenEmptyOmit: Bool

    var id: String { key }

    var isSecret: Bool {
        if case .password = control { return true }
        return false
    }
}

struct ProviderEnvironmentFieldSpec: Equatable, Identifiable {
    let name: String
    let label: String
    let description: String
    let placeholder: String
    let sensitive: Bool

    var id: String { name }
}

struct ProviderModelEntry: Equatable, Identifiable {
    let slug: String
    let name: String
    let subProvider: String?
    let isCustom: Bool

    var id: String { slug }
}

struct ProviderStatusDisplay: Equatable {
    enum Tone: Equatable {
        case ready
        case working
        case warning
        case error
        case neutral
    }

    let tone: Tone
    let version: String?
    let text: String
    let truncatedMessage: Bool
}

struct ProviderEntry: Equatable, Identifiable {
    let id: String
    let driver: String
    let label: String
    let displayName: String
    let defaultLabel: String
    let kind: ProviderKind
    let accentColor: String?
    let isDefault: Bool
    let enabled: Bool
    let installed: Bool
    let status: ServerProviderState
    let availability: String?
    let message: String?
    let version: String?
    let account: String?
    let auth: ServerProviderAuth
    let setup: ServerProviderSetup?
    let versionAdvisory: ServerProviderVersionAdvisory?
    let compatibilityAdvisory: ServerProviderCompatibilityAdvisory?
    let updateState: ServerProviderUpdateState?
    let models: [ProviderModelEntry]
    let customModels: [String]
    let canManageCustomModels: Bool
    let config: [String: JSONValue]?
    let fields: [ProviderSettingsFieldSpec]
    let environmentFields: [ProviderEnvironmentFieldSpec]
    let environment: [ProviderInstanceEnvironmentVariable]
    let unknownDriver: Bool

    var supportsInstall: Bool { setup?.canInstall == true }

    var supportsAuth: Bool {
        setup?.canAuthenticate == true || (driver == "acpRegistry" && installed)
    }
}

struct ProviderAuthViewModel: Equatable {
    let active: Bool
    let signedIn: Bool
    let isDiscovering: Bool
    let needsExternalSetup: Bool
    let description: String
    let statusMessage: String?
    let actionURL: String?
    let showCallbackInput: Bool
    let canStart: Bool
    let startLabel: String
    let canCancel: Bool
    let canLogout: Bool
    let terminalUnsupported: Bool
}

struct ProviderInstallViewModel: Equatable {
    let active: Bool
    let installed: Bool
    let updateAvailable: Bool
    let progressFraction: Double?
    let description: String
    let actionLabel: String
    let canInstall: Bool
    let canCancel: Bool
    let canRemove: Bool
}

enum AddAccountPresetID: String, CaseIterable, Identifiable, Hashable {
    case codex
    case antigravity
    case cursor
    case claude
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .codex: "Codex"
        case .antigravity: "Antigravity"
        case .cursor: "Cursor"
        case .claude: "Claude"
        case .other: "Other provider"
        }
    }

    var description: String {
        switch self {
        case .codex: "Managed ChatGPT sign-in with its own account session."
        case .antigravity: "Separate Google, Gemini Enterprise, or API key account."
        case .cursor: "Separate Cursor sign-in or API key."
        case .claude: "Isolated CLAUDE_CONFIG_DIR folder for another Claude login."
        case .other: "OpenCode, Pi, Grok, Kiro, Muse, fx, or ACP."
        }
    }

    var driver: String? {
        switch self {
        case .codex: "codex"
        case .antigravity: "antigravity"
        case .cursor: "cursor"
        case .claude: "claudeAgent"
        case .other: nil
        }
    }

    var providerKind: ProviderKind {
        switch self {
        case .codex: .codex
        case .antigravity: .gemini
        case .cursor: .cursor
        case .claude: .claude
        case .other: .other
        }
    }
}

struct AccentSwatch: Equatable, Identifiable {
    let hex: String
    let name: String
    var id: String { hex }
}

struct DriverOption: Equatable, Identifiable {
    let value: String
    let label: String
    var id: String { value }
}

struct CreateAccountDraft: Equatable {
    let instanceId: String
    let instance: ProviderInstanceConfig
}

enum ProviderSettingsLogic {
    static let maxCustomModelLength = 256
    private static let maxStatusMessageLength = 120
    private static let maxEnvVarNameLength = 128
    private static let reservedDefaultIDs: Set<String> = ["codex", "claudeAgent"]
    private static let defaultDisabledDrivers: Set<String> = [
        "cursor", "grok", "fx", "kiro", "muse", "pi", "opencode", "antigravity",
    ]

    static let accentSwatches: [AccentSwatch] = [
        AccentSwatch(hex: "#3b82f6", name: "Blue"),
        AccentSwatch(hex: "#8b5cf6", name: "Violet"),
        AccentSwatch(hex: "#10b981", name: "Emerald"),
        AccentSwatch(hex: "#f59e0b", name: "Amber"),
        AccentSwatch(hex: "#f43f5e", name: "Rose"),
        AccentSwatch(hex: "#06b6d4", name: "Cyan"),
        AccentSwatch(hex: "#f97316", name: "Orange"),
        AccentSwatch(hex: "#ec4899", name: "Pink"),
    ]

    static let driverDisplayNames: [String: String] = [
        "codex": "Codex",
        "claudeAgent": "Claude",
        "cursor": "Cursor",
        "antigravity": "Antigravity",
        "opencode": "OpenCode",
        "pi": "Pi",
        "grok": "Grok",
        "kiro": "Kiro",
        "muse": "Muse",
        "fx": "fx",
        "acpRegistry": "ACP Agent",
    ]

    static let otherProviderDrivers: [DriverOption] = [
        DriverOption(value: "opencode", label: "OpenCode"),
        DriverOption(value: "pi", label: "Pi"),
        DriverOption(value: "grok", label: "Grok"),
        DriverOption(value: "kiro", label: "Kiro"),
        DriverOption(value: "muse", label: "Muse"),
        DriverOption(value: "fx", label: "fx"),
        DriverOption(value: "acpRegistry", label: "ACP Agent"),
    ]

    static func customModelPlaceholder(for driver: String) -> String {
        switch driver {
        case "codex": "gpt-5.4-codex"
        case "claudeAgent": "claude-sonnet-5"
        case "cursor": "claude-sonnet-4-6"
        case "opencode": "openai/gpt-5"
        case "pi": "anthropic/claude-sonnet-5"
        default: "model-id"
        }
    }

    static func defaultLabel(for driver: String) -> String {
        driverDisplayNames[driver] ?? driver
    }

    static func isKnownDriver(_ driver: String) -> Bool {
        driverDisplayNames[driver] != nil
    }

    // MARK: - Provider Entries & Ordering

    static func sortedProviderEntries(
        providers: [ServerProvider],
        settings: ServerSettings?
    ) -> [ProviderEntry] {
        let instances = settings?.providerInstances ?? [:]
        let built = providers.map { snapshot in
            buildProviderEntry(
                snapshot: snapshot,
                instanceConfig: instances[snapshot.instanceId]
            )
        }
        // Group by driver keeping first-seen order; each driver's default instance first, then custom instances.
        var driverOrder: [String] = []
        var buckets: [String: [ProviderEntry]] = [:]
        for entry in built {
            if buckets[entry.driver] == nil {
                driverOrder.append(entry.driver)
            }
            buckets[entry.driver, default: []].append(entry)
        }
        var sorted: [ProviderEntry] = []
        for driver in driverOrder {
            let group = buckets[driver] ?? []
            sorted.append(contentsOf: group.filter(\.isDefault))
            sorted.append(contentsOf: group.filter { !$0.isDefault })
        }
        return sorted
    }

    static func buildProviderEntry(
        snapshot: ServerProvider,
        instanceConfig: ProviderInstanceConfig?
    ) -> ProviderEntry {
        let driver = snapshot.driver
        let isDefault = snapshot.instanceId == driver
        let fallbackLabel = defaultLabel(for: driver)
        let explicitDisplayName = instanceConfig?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedLabel: String = {
            if !explicitDisplayName.isEmpty { return explicitDisplayName }
            if let snapName = snapshot.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !snapName.isEmpty {
                return snapName
            }
            return fallbackLabel
        }()
        let accent = SwftAdapters.normalizedAccentHex(instanceConfig?.accentColor)
            ?? SwftAdapters.normalizedAccentHex(snapshot.accentColor)
        let rawConfig = instanceConfig?.configObject
        let customModels = readCustomModelSlugs(driver: driver, config: rawConfig)
        let models = deriveModelsForDisplay(liveModels: snapshot.models, customModels: customModels)
        let effectiveEnabled = instanceConfig.map(resolveInstanceEnabled) ?? snapshot.enabled
        let known = isKnownDriver(driver)

        return ProviderEntry(
            id: snapshot.instanceId,
            driver: driver,
            label: resolvedLabel,
            displayName: explicitDisplayName,
            defaultLabel: fallbackLabel,
            kind: SwftAdapters.providerKind(driver: driver, instanceId: snapshot.instanceId),
            accentColor: accent,
            isDefault: isDefault,
            enabled: effectiveEnabled,
            installed: snapshot.installed,
            status: snapshot.status,
            availability: snapshot.availability,
            message: snapshot.message,
            version: snapshot.version,
            account: formatProviderAccount(snapshot.auth),
            auth: snapshot.auth,
            setup: snapshot.setup,
            versionAdvisory: snapshot.versionAdvisory,
            compatibilityAdvisory: snapshot.compatibilityAdvisory,
            updateState: snapshot.updateState,
            models: models,
            customModels: customModels,
            canManageCustomModels: driver != "antigravity" && known,
            config: rawConfig,
            fields: fields(for: driver, config: rawConfig),
            environmentFields: environmentFields(for: driver),
            environment: instanceConfig?.environment ?? [],
            unknownDriver: !known
        )
    }

    static func resolveInstanceEnabled(_ instance: ProviderInstanceConfig) -> Bool {
        let legacyConfigEnabled = instance.configObject?["enabled"]?.boolValue
        if instance.enabled == false || legacyConfigEnabled == false {
            return false
        }
        return instance.enabled ?? legacyConfigEnabled ?? !defaultDisabledDrivers.contains(instance.driver)
    }

    static func resolveProviderExpandID(
        entries: [ProviderEntry],
        requestedID: String?
    ) -> String? {
        guard let trimmed = requestedID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        if let exact = entries.first(where: { $0.id == trimmed }) {
            return exact.id
        }
        return entries.first(where: { $0.driver == trimmed })?.id
    }

    // MARK: - Formatting & Status

    static func formatProviderVersion(_ version: String?) -> String? {
        guard let version = version?.trimmingCharacters(in: .whitespacesAndNewlines), !version.isEmpty else {
            return nil
        }
        if let regex = try? NSRegularExpression(pattern: #"^agy_acp_server_(\d{4})(\d{2})(\d{2})_\d+(?:_(\w+))?$"#),
           let match = regex.firstMatch(in: version, range: NSRange(version.startIndex..., in: version)),
           let yr = Range(match.range(at: 1), in: version),
           let mo = Range(match.range(at: 2), in: version),
           let dy = Range(match.range(at: 3), in: version)
        {
            let suffix: String
            if match.range(at: 4).location != NSNotFound, let cand = Range(match.range(at: 4), in: version) {
                suffix = " \(version[cand])"
            } else {
                suffix = ""
            }
            return "\(version[yr])-\(version[mo])-\(version[dy])\(suffix)"
        }
        if let first = version.first, first.isNumber {
            return "v\(version)"
        }
        return version
    }

    static func providerAuthLabel(_ auth: ServerProviderAuth) -> String? {
        if auth.type == "customEndpoint" { return "Custom API endpoint" }
        let label = auth.label?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let label, !label.isEmpty { return label }
        let type = auth.type?.trimmingCharacters(in: .whitespacesAndNewlines)
        return type?.isEmpty == false ? type : nil
    }

    static func formatProviderAccount(_ auth: ServerProviderAuth) -> String? {
        guard auth.status == .authenticated else { return nil }
        let label = providerAuthLabel(auth)
        let email = auth.email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [label, email].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        if parts.count == 2 && parts[0] == parts[1] { return parts[0] }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func deriveProviderStatus(_ provider: ProviderEntry) -> ProviderStatusDisplay {
        if !provider.enabled || provider.status == .disabled {
            return ProviderStatusDisplay(tone: .neutral, version: nil, text: "Disabled", truncatedMessage: false)
        }

        let version = formatProviderVersion(provider.version)

        if let updateState = provider.updateState,
           updateState.status == "queued" || updateState.status == "running"
        {
            let shortened = shortenMessage(updateState.message)
            let text = shortened.short.map { "Updating · \($0)" } ?? "Updating"
            return ProviderStatusDisplay(tone: .working, version: version, text: text, truncatedMessage: shortened.truncated)
        }

        if provider.availability == "unavailable" {
            let shortened = shortenMessage(provider.message)
            let text = shortened.short.map { "Unavailable · \($0)" } ?? "Unavailable"
            return ProviderStatusDisplay(tone: .error, version: nil, text: text, truncatedMessage: shortened.truncated)
        }

        if !provider.installed {
            return ProviderStatusDisplay(tone: .neutral, version: nil, text: "Not installed", truncatedMessage: false)
        }

        if provider.auth.status == .unauthenticated {
            let label = providerAuthLabel(provider.auth)
            let parts = ["Not signed in"] + (label.map { [$0] } ?? [])
            return ProviderStatusDisplay(tone: .warning, version: version, text: parts.joined(separator: " · "), truncatedMessage: false)
        }

        let advisory = versionAdvisorySuffix(provider.versionAdvisory, provider.compatibilityAdvisory)

        if provider.driver == "antigravity",
           provider.installed,
           provider.status == .warning,
           provider.auth.status == .unknown,
           provider.auth.type == nil || provider.auth.type == "oauth-personal" || provider.auth.type == "oauth-business"
        {
            let parts = ["Installed · Sign-in not checked"] + (advisory.map { [$0] } ?? [])
            return ProviderStatusDisplay(tone: .warning, version: version, text: parts.joined(separator: " · "), truncatedMessage: false)
        }

        if provider.status == .error {
            let shortened = shortenMessage(provider.message)
            let text = shortened.short.map { "Unavailable · \($0)" } ?? "Unavailable"
            return ProviderStatusDisplay(tone: .error, version: version, text: text, truncatedMessage: shortened.truncated)
        }

        if provider.status == .warning {
            if let advisory,
               let compat = provider.compatibilityAdvisory,
               compat.status == "graceful" || compat.status == "unsupported" || compat.status == "broken"
            {
                return ProviderStatusDisplay(tone: .warning, version: version, text: advisory, truncatedMessage: false)
            }
            let shortened = shortenMessage(provider.message)
            let text = shortened.short.map { "Needs attention · \($0)" } ?? "Needs attention"
            return ProviderStatusDisplay(tone: .warning, version: version, text: text, truncatedMessage: shortened.truncated)
        }

        if provider.auth.status == .authenticated {
            var parts = ["Signed in"]
            if let account = formatProviderAccount(provider.auth) { parts.append(account) }
            if let advisory { parts.append(advisory) }
            return ProviderStatusDisplay(tone: .ready, version: version, text: parts.joined(separator: " · "), truncatedMessage: false)
        }

        let parts = ["Available"] + (advisory.map { [$0] } ?? [])
        return ProviderStatusDisplay(tone: .ready, version: version, text: parts.joined(separator: " · "), truncatedMessage: false)
    }

    private static func versionAdvisorySuffix(
        _ advisory: ServerProviderVersionAdvisory?,
        _ compatibility: ServerProviderCompatibilityAdvisory?
    ) -> String? {
        if let compatibility {
            switch compatibility.status {
            case "graceful": return "Limited support"
            case "unsupported": return "Unsupported version"
            case "broken": return "Known broken version"
            default: break
            }
        }
        let latestIsIncompatible = compatibility?.latestVersionStatus == "broken"
            || compatibility?.latestVersionStatus == "unsupported"
        guard let advisory,
              advisory.status != "current",
              advisory.status != "unknown",
              !latestIsIncompatible
        else { return nil }
        if let latest = formatProviderVersion(advisory.latestVersion) {
            return "Update available: \(latest)"
        }
        return "Update available"
    }

    private static func shortenMessage(_ raw: String?) -> (short: String?, truncated: Bool) {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return (nil, false)
        }
        let multiline = trimmed.contains("\n")
        let firstLine = trimmed
            .components(separatedBy: .newlines)
            .first?
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ") ?? ""
        if firstLine.count <= maxStatusMessageLength {
            return (firstLine.isEmpty ? nil : firstLine, multiline)
        }
        let prefix = firstLine.prefix(maxStatusMessageLength - 1).trimmingCharacters(in: .whitespaces)
        return ("\(prefix)…", true)
    }

    // MARK: - Per-Provider Schema Fields

    static func fields(for driver: String, config: [String: JSONValue]?) -> [ProviderSettingsFieldSpec] {
        switch driver {
        case "codex":
            return [
                .init(key: "binaryPath", label: "Binary path", description: "Path to the Codex binary used by this instance.", placeholder: "codex", control: .text, monospaced: true, clearWhenEmptyOmit: true),
                .init(key: "homePath", label: "CODEX_HOME path", description: "Custom Codex home and config directory.", placeholder: "~/.codex", control: .text, monospaced: true, clearWhenEmptyOmit: true),
                .init(key: "shadowHomePath", label: "Shadow home path", description: "Account-specific Codex home. Keeps auth.json separate while sharing state from CODEX_HOME.", placeholder: "~/.codex-swft/personal", control: .text, monospaced: true, clearWhenEmptyOmit: true),
                .init(key: "launchArgs", label: "Launch arguments", description: "Additional CLI arguments passed to codex app-server on session start.", placeholder: "", control: .text, monospaced: true, clearWhenEmptyOmit: true),
            ]
        case "claudeAgent":
            return [
                .init(key: "binaryPath", label: "Binary path", description: "Path to the Claude binary used by this instance.", placeholder: "claude", control: .text, monospaced: true, clearWhenEmptyOmit: true),
                .init(key: "homePath", label: "CLAUDE_CONFIG_DIR path", description: "Custom Claude home and config directory. Keeps .claude.json and .claude separate.", placeholder: "~/.claude", control: .text, monospaced: true, clearWhenEmptyOmit: true),
                .init(key: "autoCompactWindow", label: "Auto-compact after", description: "Compact after 100,000 to 1,000,000 tokens. Leave empty to use Claude's default.", placeholder: "e.g. 300000", control: .text, monospaced: true, clearWhenEmptyOmit: true),
                .init(
                    key: "idleCompaction",
                    label: "Compact idle threads",
                    description: "Overrides the global idle compaction setting for this Claude account.",
                    placeholder: "",
                    control: .select([
                        .init(value: "default", label: "Use default"),
                        .init(value: "onReturn", label: "When you return"),
                        .init(value: "beforeCacheExpires", label: "Before the cache expires (beta)"),
                        .init(value: "off", label: "Never"),
                    ]),
                    monospaced: false,
                    clearWhenEmptyOmit: true
                ),
                .init(key: "launchArgs", label: "Launch arguments", description: "Additional CLI arguments passed on session start.", placeholder: "e.g. --chrome", control: .text, monospaced: true, clearWhenEmptyOmit: true),
            ]
        case "antigravity":
            return [
                .init(
                    key: "authMethod",
                    label: "Sign-in method",
                    description: "Google accounts use your subscription; API keys and Agent Platform bill usage.",
                    placeholder: "",
                    control: .select([
                        .init(value: "oauth-personal", label: "Google account"),
                        .init(value: "oauth-business", label: "Gemini Enterprise"),
                        .init(value: "gemini-api-key", label: "Gemini API key"),
                        .init(value: "agent-platform", label: "Agent Platform (Vertex AI)"),
                    ]),
                    monospaced: false,
                    clearWhenEmptyOmit: true
                ),
                .init(key: "apiKey", label: "API key", description: "Gemini or Vertex AI express key. Stored separately on the host.", placeholder: "Optional", control: .password, monospaced: true, clearWhenEmptyOmit: true),
                .init(key: "gcpProject", label: "GCP project", description: "Required for Gemini Enterprise. Agent Platform uses it when no API key is set.", placeholder: "my-project-id", control: .text, monospaced: true, clearWhenEmptyOmit: true),
                .init(key: "gcpLocation", label: "GCP location", description: "Region for Gemini Enterprise or Agent Platform.", placeholder: "us-central1", control: .text, monospaced: true, clearWhenEmptyOmit: true),
                .init(key: "binaryPath", label: "Binary path", description: "Custom ACP executable. Leave empty to select automatically.", placeholder: "Automatic", control: .text, monospaced: true, clearWhenEmptyOmit: false),
            ]
        case "opencode":
            return [
                .init(key: "binaryPath", label: "Binary path", description: "Path to the OpenCode binary.", placeholder: "opencode", control: .text, monospaced: true, clearWhenEmptyOmit: true),
                .init(key: "serverUrl", label: "Server URL", description: "Leave blank to let the local server spawn OpenCode when needed.", placeholder: "http://127.0.0.1:4096", control: .text, monospaced: true, clearWhenEmptyOmit: true),
                .init(key: "serverPassword", label: "Server password", description: "Stored separately on the host.", placeholder: "Optional", control: .password, monospaced: true, clearWhenEmptyOmit: true),
            ]
        case "pi":
            return [
                .init(key: "binaryPath", label: "Binary path", description: "Path to the Pi coding agent binary.", placeholder: "pi", control: .text, monospaced: true, clearWhenEmptyOmit: true),
                .init(key: "launchArgs", label: "Launch arguments", description: "Additional CLI arguments passed to pi --mode rpc on session start.", placeholder: "", control: .text, monospaced: true, clearWhenEmptyOmit: true),
            ]
        case "grok":
            return [
                .init(key: "binaryPath", label: "Binary path", description: "Path to the Grok CLI binary.", placeholder: "grok", control: .text, monospaced: true, clearWhenEmptyOmit: true),
            ]
        case "kiro":
            return [
                .init(key: "binaryPath", label: "Binary path", description: "Path to the Kiro CLI binary.", placeholder: "kiro-cli", control: .text, monospaced: true, clearWhenEmptyOmit: true),
            ]
        case "muse":
            return [
                .init(key: "binaryPath", label: "Binary path", description: "Path to the Muse Code binary. Sign in with `muse login` on this machine.", placeholder: "muse", control: .text, monospaced: true, clearWhenEmptyOmit: true),
            ]
        case "fx":
            return [
                .init(key: "binaryPath", label: "Binary path", description: "Path to the fx binary. All fx instances on this machine share its login.", placeholder: "fx", control: .text, monospaced: true, clearWhenEmptyOmit: true),
            ]
        case "acpRegistry":
            let isLocal = config?["source"]?.stringValue == "local"
            if isLocal {
                return [
                    .init(
                        key: "source",
                        label: "ACP source",
                        description: "Choose a registry agent or a local command.",
                        placeholder: "",
                        control: .select([
                            .init(value: "registry", label: "ACP Registry"),
                            .init(value: "local", label: "Local command"),
                        ]),
                        monospaced: false,
                        clearWhenEmptyOmit: true
                    ),
                    .init(key: "commandPath", label: "Executable", description: "Executable name or path on this machine.", placeholder: "e.g. dsh", control: .text, monospaced: true, clearWhenEmptyOmit: true),
                ]
            }
            return [
                .init(
                    key: "source",
                    label: "ACP source",
                    description: "Choose a registry agent or a local command.",
                    placeholder: "",
                    control: .select([
                        .init(value: "registry", label: "ACP Registry"),
                        .init(value: "local", label: "Local command"),
                    ]),
                    monospaced: false,
                    clearWhenEmptyOmit: true
                ),
                .init(key: "agentId", label: "Registry agent ID", description: "Agent identifier from the official ACP Registry, for example 'devin'.", placeholder: "devin", control: .text, monospaced: true, clearWhenEmptyOmit: false),
                .init(key: "commandPath", label: "Executable override", description: "Overrides the distribution executable while keeping its arguments and environment.", placeholder: "Registry default", control: .text, monospaced: true, clearWhenEmptyOmit: true),
                .init(key: "authMethodId", label: "Authentication method", description: "Optional ACP authentication method ID.", placeholder: "auto", control: .text, monospaced: true, clearWhenEmptyOmit: true),
            ]
        default:
            return []
        }
    }

    static func environmentFields(for driver: String) -> [ProviderEnvironmentFieldSpec] {
        switch driver {
        case "cursor":
            return [
                .init(
                    name: "CURSOR_API_KEY",
                    label: "Cursor API key",
                    description: "Optional. Overrides browser sign-in for this provider.",
                    placeholder: "Paste API key",
                    sensitive: true
                ),
            ]
        case "kiro":
            return [
                .init(
                    name: "KIRO_API_KEY",
                    label: "Kiro API key",
                    description: "Optional. Signs in without `kiro-cli login` (Kiro Pro and above).",
                    placeholder: "Paste API key",
                    sensitive: true
                ),
            ]
        default:
            return []
        }
    }

    static func validateFieldValue(_ raw: String, for field: ProviderSettingsFieldSpec) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if field.key == "autoCompactWindow" {
            guard let count = Int(trimmed), count >= 100_000, count <= 1_000_000 else {
                return "Enter a number between 100000 and 1000000."
            }
        }
        return nil
    }

    static func readConfigString(_ config: [String: JSONValue]?, key: String) -> String {
        config?[key]?.stringValue ?? ""
    }

    static func isConfiguredSecret(_ config: [String: JSONValue]?, key: String) -> Bool {
        guard let value = config?[key] else { return false }
        switch value {
        case .string(let s): return !s.isEmpty
        case .object: return true // Secret reference object
        default: return false
        }
    }

    static func nextConfig(
        from config: [String: JSONValue]?,
        field: ProviderSettingsFieldSpec,
        value: String
    ) -> [String: JSONValue]? {
        var next = config ?? [:]
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if field.clearWhenEmptyOmit && trimmed.isEmpty {
            next.removeValue(forKey: field.key)
        } else {
            next[field.key] = .string(value)
        }
        return next.isEmpty ? nil : next
    }

    // MARK: - Custom Models

    static func readCustomModelSlugs(driver: String, config: [String: JSONValue]?) -> [String] {
        guard driver != "antigravity",
              let array = config?["customModels"]?.arrayValue
        else { return [] }
        return array.compactMap { entry -> String? in
            if let str = entry.stringValue {
                let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            if let slug = entry["slug"]?.stringValue {
                let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            return nil
        }
    }

    static func deriveModelsForDisplay(
        liveModels: [ServerProviderModel],
        customModels: [String]
    ) -> [ProviderModelEntry] {
        let serverBuiltIns = liveModels.filter { !$0.isCustom }
        let builtInSlugs = Set(serverBuiltIns.map(\.slug))
        var result = serverBuiltIns.map {
            ProviderModelEntry(slug: $0.slug, name: $0.name, subProvider: $0.subProvider, isCustom: false)
        }
        for slug in customModels where !builtInSlugs.contains(slug) {
            result.append(ProviderModelEntry(slug: slug, name: slug, subProvider: nil, isCustom: true))
        }
        return result
    }

    static func validateCustomModelSlug(
        _ rawInput: String,
        driver: String,
        models: [ProviderModelEntry],
        customModels: [String]
    ) -> Result<String, SettingsValidationError> {
        if driver == "antigravity" {
            return .failure(.message("Antigravity does not support custom models."))
        }
        let normalized = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return .failure(.message("Enter a model ID."))
        }
        if models.contains(where: { !$0.isCustom && $0.slug == normalized }) {
            return .failure(.message("That model is already built in."))
        }
        if normalized.count > maxCustomModelLength {
            return .failure(.message("Model IDs must be \(maxCustomModelLength) characters or less."))
        }
        if customModels.contains(normalized) {
            return .failure(.message("That custom model is already saved."))
        }
        return .success(normalized)
    }

    static func nextConfigWithCustomModels(
        from config: [String: JSONValue]?,
        slugs: [String]
    ) -> [String: JSONValue] {
        var next = config ?? [:]
        next["customModels"] = .array(slugs.map { .string($0) })
        return next
    }

    // MARK: - Environment Variables

    static func isValidEnvironmentVariableName(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxEnvVarNameLength else { return false }
        let scalars = trimmed.unicodeScalars
        guard let first = scalars.first,
              (first >= "a" && first <= "z") || (first >= "A" && first <= "Z") || first == "_"
        else { return false }
        return scalars.allSatisfy { s in
            (s >= "a" && s <= "z") || (s >= "A" && s <= "Z") || (s >= "0" && s <= "9") || s == "_"
        }
    }

    static func nextEnvironment(
        from current: [ProviderInstanceEnvironmentVariable],
        settingName name: String,
        value: String,
        sensitive: Bool
    ) -> [ProviderInstanceEnvironmentVariable] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        var result: [ProviderInstanceEnvironmentVariable] = []
        var found = false
        for item in current {
            if item.name != name {
                result.append(item)
                continue
            }
            found = true
            if !trimmed.isEmpty {
                result.append(ProviderInstanceEnvironmentVariable(name: name, value: trimmed, sensitive: sensitive))
            }
        }
        if !found && !trimmed.isEmpty {
            result.append(ProviderInstanceEnvironmentVariable(name: name, value: trimmed, sensitive: sensitive))
        }
        return result
    }

    static func removingEnvironmentVariables(
        from current: [ProviderInstanceEnvironmentVariable],
        names: Set<String>
    ) -> [ProviderInstanceEnvironmentVariable] {
        current.filter { !names.contains($0.name) }
    }

    // MARK: - Provider Instance Config Builders

    static func baseInstanceConfig(
        explicit: ProviderInstanceConfig?,
        driver: String
    ) -> ProviderInstanceConfig {
        explicit ?? ProviderInstanceConfig(driver: driver)
    }

    static func buildEnabledInstanceConfig(
        previous: ProviderInstanceConfig,
        enabled: Bool
    ) -> ProviderInstanceConfig {
        var next = previous
        next.enabled = enabled
        // Drop legacy config.enabled so server resolves instance.enabled cleanly.
        if var obj = previous.configObject, obj.removeValue(forKey: "enabled") != nil {
            next.config = obj.isEmpty ? nil : .object(obj)
        }
        return next
    }

    static func buildDisplayNameInstanceConfig(
        previous: ProviderInstanceConfig,
        displayName: String
    ) -> ProviderInstanceConfig {
        var next = previous
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        next.displayName = trimmed.isEmpty ? nil : trimmed
        return next
    }

    static func buildAccentColorInstanceConfig(
        previous: ProviderInstanceConfig,
        accentColor: String?
    ) -> ProviderInstanceConfig {
        var next = previous
        next.accentColor = SwftAdapters.normalizedAccentHex(accentColor)
        return next
    }

    static func buildConfigInstanceConfig(
        previous: ProviderInstanceConfig,
        config: [String: JSONValue]?
    ) -> ProviderInstanceConfig {
        var next = previous
        if let config, !config.isEmpty {
            next.config = .object(config)
        } else {
            next.config = nil
        }
        return next
    }

    static func buildEnvironmentInstanceConfig(
        previous: ProviderInstanceConfig,
        environment: [ProviderInstanceEnvironmentVariable]
    ) -> ProviderInstanceConfig {
        var next = previous
        let cleaned = environment.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        next.environment = cleaned.isEmpty ? nil : cleaned
        return next
    }

    // MARK: - Add Account Draft & ID Derivation

    static func deriveAccountInstanceID(
        driver: String,
        name: String,
        existingIDs: Set<String>
    ) -> String {
        let taken = reservedDefaultIDs.union(existingIDs)
        let slug = slugify(name)
        let base = slug.isEmpty ? "\(driver)_account" : "\(driver)_\(slug)"
        if !taken.contains(base) { return base }
        var suffix = 2
        while true {
            let suffixText = "_\(suffix)"
            let candidate = "\(base.prefix(64 - suffixText.count))\(suffixText)"
            if !taken.contains(candidate) { return candidate }
            suffix += 1
        }
    }

    private static func slugify(_ value: String) -> String {
        let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var out = ""
        var lastWasUnderscore = false
        for scalar in lowered.unicodeScalars {
            let isAlnum = (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9")
            if isAlnum {
                out.unicodeScalars.append(scalar)
                lastWasUnderscore = false
            } else if !lastWasUnderscore && !out.isEmpty {
                out.append("_")
                lastWasUnderscore = true
            }
        }
        while out.last == "_" { out.removeLast() }
        return String(out.prefix(48))
    }

    static func suggestClaudeConfigDir(for name: String) -> String {
        var lowered = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let regex = try? NSRegularExpression(pattern: #"^claude(?:\s+code)?(?:[\s_-]+|$)"#) {
            let range = NSRange(lowered.startIndex..., in: lowered)
            lowered = regex.stringByReplacingMatches(in: lowered, range: range, withTemplate: "")
        }
        var slug = ""
        var lastWasDash = false
        for scalar in lowered.unicodeScalars {
            let isAlnum = (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9")
            if isAlnum {
                slug.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash && !slug.isEmpty {
                slug.append("-")
                lastWasDash = true
            }
        }
        while slug.last == "-" { slug.removeLast() }
        let capped = String(slug.prefix(32))
        return capped.isEmpty ? "~/.claude-account" : "~/.claude-\(capped)"
    }

    static func claudeLoginCommand(homePath: String) -> String {
        let trimmed = homePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let dir = shellQuotePath(trimmed.isEmpty ? "~/.claude-account" : trimmed)
        return "mkdir -p \(dir) && CLAUDE_CONFIG_DIR=\(dir) claude auth login"
    }

    private static func shellQuotePath(_ path: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._/@+-")
        if path.hasPrefix("~/") {
            let rest = String(path.dropFirst(2))
            if !rest.isEmpty && rest.unicodeScalars.allSatisfy({ safe.contains($0) }) {
                return path
            }
            let escaped = rest.replacingOccurrences(of: "'", with: "'\\''")
            return "~/'\(escaped)'"
        }
        if !path.isEmpty && path.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return path
        }
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    static func buildCreateAccountDraft(
        preset: AddAccountPresetID,
        otherDriver: String? = nil,
        name: String,
        accentColor: String? = nil,
        claudeConfigDir: String? = nil,
        existingIDs: Set<String>
    ) -> Result<CreateAccountDraft, SettingsValidationError> {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return .failure(.message("Enter a name for this account."))
        }
        let driver: String
        if preset == .other {
            driver = otherDriver?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? otherProviderDrivers.first?.value
                ?? ""
        } else {
            driver = preset.driver ?? ""
        }
        guard !driver.isEmpty else {
            return .failure(.message("Choose a provider."))
        }

        let instanceID = deriveAccountInstanceID(driver: driver, name: trimmedName, existingIDs: existingIDs)
        let normalizedAccent = SwftAdapters.normalizedAccentHex(accentColor)

        var configObj: [String: JSONValue]?
        switch preset {
        case .codex:
            configObj = ["setupMode": .string("managed")]
        case .claude:
            let dir = claudeConfigDir?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? suggestClaudeConfigDir(for: trimmedName)
            configObj = ["homePath": .string(dir)]
        default:
            break
        }

        let instance = ProviderInstanceConfig(
            driver: driver,
            displayName: trimmedName,
            accentColor: normalizedAccent,
            environment: nil,
            enabled: true,
            config: configObj.map { .object($0) }
        )
        return .success(CreateAccountDraft(instanceId: instanceID, instance: instance))
    }

    // MARK: - Provider Auth & Install View Derivation

    static func deriveProviderAuthView(
        provider: ProviderEntry,
        authState: ProviderAuthState?,
        authError: String?,
        isRemote: Bool,
        runtimeInstalled: Bool? = nil
    ) -> ProviderAuthViewModel {
        let interaction = authState?.interaction
        let active = authState?.phase == .starting || authState?.phase == .waiting || authState?.phase == .verifying
        let signedIn = provider.auth.status == .authenticated
            || (provider.auth.status == .unknown && authState?.phase == .succeeded)
        let isDiscovering = provider.driver == "acpRegistry"
            && !active
            && !signedIn
            && authError == nil
            && authState?.methods == nil
        let needsExternalSetup = !active
            && !signedIn
            && (provider.setup?.canAuthenticate == false
                || (provider.driver == "acpRegistry" && authState?.methods?.isEmpty == true))
        let usesCredentials = provider.driver == "antigravity"
            && (provider.auth.type == "gemini-api-key" || provider.auth.type == "agent-platform")
        let terminalUnsupported: Bool
        if active, case .terminal = interaction {
            terminalUnsupported = true
        } else {
            terminalUnsupported = false
        }

        let description: String
        if active {
            if authState?.phase == .starting {
                description = authState?.message ?? (usesCredentials ? "Connecting…" : "Starting sign-in…")
            } else if authState?.phase == .verifying {
                description = usesCredentials ? "Checking credentials and loading models…" : "Checking your account…"
            } else {
                switch interaction {
                case .terminal:
                    description = "This provider requires an interactive terminal to sign in. Use the provider's CLI, then refresh."
                case .credentials:
                    description = "Enter your credentials below."
                case .deviceCode:
                    description = "Open the sign-in page and enter the code below."
                default:
                    description = "Finish signing in in your browser."
                }
            }
        } else if signedIn {
            if let email = provider.auth.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
                description = "Signed in as \(email)."
            } else {
                description = "Signed in."
            }
        } else if isDiscovering {
            description = "Discovering sign-in methods…"
        } else if needsExternalSetup {
            description = "No in-app sign-in advertised. Follow the provider's documentation."
        } else if usesCredentials {
            description = "Connect to load models."
        } else {
            description = "Sign in to use this account."
        }

        let statusMessage: String?
        if authState?.phase == .failed {
            statusMessage = authState?.message
        } else if authState?.phase == .idle, let msg = authState?.message, msg.hasPrefix("Signed out locally.") {
            statusMessage = msg
        } else {
            statusMessage = nil
        }

        let actionURL: String?
        switch interaction {
        case .browser(_, let url, _, _), .deviceCode(_, let url, _):
            actionURL = url
        default:
            actionURL = authState?.authorizationUrl
        }

        let showCallbackInput: Bool
        if active, actionURL != nil {
            if case .browser(_, _, _, let acceptsCallback) = interaction {
                showCallbackInput = acceptsCallback == true || isRemote
            } else {
                showCallbackInput = interaction == nil
            }
        } else {
            showCallbackInput = false
        }

        let installed = runtimeInstalled ?? provider.installed
        let canStart = !active
            && !isDiscovering
            && !needsExternalSetup
            && provider.setup?.canAuthenticate != false
            && provider.enabled
            && installed
            && authState != nil

        let startLabel: String
        if signedIn {
            startLabel = "Change account"
        } else if authState?.phase == .failed || authState?.phase == .cancelled {
            startLabel = usesCredentials ? "Retry connection" : "Retry sign-in"
        } else {
            startLabel = usesCredentials ? "Connect" : "Sign in"
        }

        let canCancel = active && authState?.flowId != nil
        let canLogout = !active
            && signedIn
            && (provider.auth.canLogout ?? provider.setup?.canAuthenticate ?? false)
            && authState != nil

        return ProviderAuthViewModel(
            active: active,
            signedIn: signedIn,
            isDiscovering: isDiscovering,
            needsExternalSetup: needsExternalSetup,
            description: description,
            statusMessage: statusMessage,
            actionURL: actionURL,
            showCallbackInput: showCallbackInput,
            canStart: canStart,
            startLabel: startLabel,
            canCancel: canCancel,
            canLogout: canLogout,
            terminalUnsupported: terminalUnsupported
        )
    }

    static func deriveProviderInstallView(
        provider: ProviderEntry,
        installState: ProviderInstallState?
    ) -> ProviderInstallViewModel {
        let active = installState?.phase == .downloading
            || installState?.phase == .extracting
            || installState?.phase == .verifying
        let usesCustomBinary = !readConfigString(provider.config, key: "binaryPath")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let installed = provider.installed || (!usesCustomBinary && installState?.installedVersion != nil)
        let updateAvailable = installed
            && installState?.source != "local"
            && installState?.version != nil
            && installState?.installedVersion != nil
            && installState?.version != installState?.installedVersion

        let progressFraction: Double?
        if installState?.phase == .downloading,
           let total = installState?.totalBytes,
           total > 0,
           let downloaded = installState?.downloadedBytes
        {
            progressFraction = min(1.0, max(0.0, Double(downloaded) / Double(total)))
        } else {
            progressFraction = nil
        }

        let description: String
        guard let installState else {
            return ProviderInstallViewModel(
                active: false,
                installed: installed,
                updateAvailable: false,
                progressFraction: nil,
                description: "Checking runtime…",
                actionLabel: installed ? "Install managed runtime" : "Install runtime",
                canInstall: provider.setup?.canInstall == true,
                canCancel: false,
                canRemove: false
            )
        }

        switch installState.phase {
        case .downloading:
            let dl = String(format: "%.1f", Double(installState.downloadedBytes) / 1_000_000)
            if let total = installState.totalBytes, total > 0 {
                let tot = String(format: "%.1f", Double(total) / 1_000_000)
                description = "Downloading \(dl) MB of \(tot) MB…"
            } else {
                description = "Downloading \(dl) MB…"
            }
        case .extracting:
            description = "Extracting runtime…"
        case .verifying:
            description = "Verifying runtime…"
        default:
            if installed {
                if let installedVersion = installState.installedVersion {
                    let formatted = formatProviderVersion(installedVersion) ?? installedVersion
                    description = installState.source == "local"
                        ? "Installed locally · \(formatted)"
                        : "Managed runtime · \(formatted)"
                } else {
                    description = "Installed."
                }
            } else if installState.phase == .failed, let msg = installState.message, !msg.isEmpty {
                description = msg
            } else if let total = installState.totalBytes, total > 0 {
                let mb = Int(ceil(Double(total) / 1_000_000))
                description = "Not installed · \(mb) MB download"
            } else {
                description = "Not installed."
            }
        }

        let actionLabel: String
        if installState.installedVersion != nil {
            actionLabel = updateAvailable ? "Update runtime" : "Reinstall runtime"
        } else if installState.phase == .failed || installState.phase == .cancelled {
            actionLabel = "Retry install"
        } else {
            actionLabel = installed ? "Install managed runtime" : "Install runtime"
        }

        return ProviderInstallViewModel(
            active: active,
            installed: installed,
            updateAvailable: updateAvailable,
            progressFraction: progressFraction,
            description: description,
            actionLabel: actionLabel,
            canInstall: !active && provider.setup?.canInstall == true,
            canCancel: active && installState.operationId != nil,
            canRemove: !active && installState.canRemove
        )
    }

    static func isWebURL(_ raw: String) -> Bool {
        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else { return false }
        return true
    }
}

enum SettingsValidationError: Error, Equatable, LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): text
        }
    }
}

// MARK: - About Formatting

enum AboutSettingsLogic {
    static func abbreviateHomePath(_ path: String, homeDirectory: String = NSHomeDirectory()) -> String {
        guard !homeDirectory.isEmpty else { return path }
        if path == homeDirectory { return "~" }
        let prefix = homeDirectory.hasSuffix("/") ? homeDirectory : homeDirectory + "/"
        if path.hasPrefix(prefix) {
            return "~/" + path.dropFirst(prefix.count)
        }
        return path
    }

    static func formatPlatform(_ platform: ExecutionEnvironmentPlatform) -> String {
        let osLabel: String = switch platform.os.lowercased() {
        case "darwin": "macOS"
        case "linux": "Linux"
        case "win32", "windows": "Windows"
        default: platform.os
        }
        return "\(osLabel) (\(platform.arch))"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
