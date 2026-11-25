import Foundation

// MARK: - Environment Discovery & Auth

public struct ExecutionEnvironmentPlatform: Codable, Sendable, Equatable {
    public let os: String
    public let arch: String
    public let machine: String?

    public init(os: String, arch: String, machine: String? = nil) {
        self.os = os
        self.arch = arch
        self.machine = machine
    }
}

public struct ExecutionEnvironmentCapabilities: Codable, Sendable, Equatable {
    public let repositoryIdentity: Bool
    public let connectionProbe: Bool
    public let threadStop: Bool
    public let threadForceStop: Bool
    public let threadVisitedTracking: Bool
    public let threadSettlement: Bool
    public let threadPinning: Bool
    public let threadSnooze: Bool
    public let shellThreadFamilies: Bool
    public let shellOlderSettled: Bool
    public let providerWorkspaceSnapshotsOnDemand: Bool
    public let commandOutputStreaming: Bool
    public let freshContext: Bool

    public init(
        repositoryIdentity: Bool = false,
        connectionProbe: Bool = false,
        threadStop: Bool = false,
        threadForceStop: Bool = false,
        threadVisitedTracking: Bool = false,
        threadSettlement: Bool = false,
        threadPinning: Bool = false,
        threadSnooze: Bool = false,
        shellThreadFamilies: Bool = false,
        shellOlderSettled: Bool = false,
        providerWorkspaceSnapshotsOnDemand: Bool = false,
        commandOutputStreaming: Bool = false,
        freshContext: Bool = false
    ) {
        self.repositoryIdentity = repositoryIdentity
        self.connectionProbe = connectionProbe
        self.threadStop = threadStop
        self.threadForceStop = threadForceStop
        self.threadVisitedTracking = threadVisitedTracking
        self.threadSettlement = threadSettlement
        self.threadPinning = threadPinning
        self.threadSnooze = threadSnooze
        self.shellThreadFamilies = shellThreadFamilies
        self.shellOlderSettled = shellOlderSettled
        self.providerWorkspaceSnapshotsOnDemand = providerWorkspaceSnapshotsOnDemand
        self.commandOutputStreaming = commandOutputStreaming
        self.freshContext = freshContext
    }

    private enum CodingKeys: String, CodingKey {
        case repositoryIdentity
        case connectionProbe
        case threadStop
        case threadForceStop
        case threadVisitedTracking
        case threadSettlement
        case threadPinning
        case threadSnooze
        case shellThreadFamilies
        case shellOlderSettled
        case providerWorkspaceSnapshotsOnDemand
        case commandOutputStreaming
        case freshContext
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.repositoryIdentity = try c.decodeIfPresent(Bool.self, forKey: .repositoryIdentity) ?? false
        self.connectionProbe = try c.decodeIfPresent(Bool.self, forKey: .connectionProbe) ?? false
        self.threadStop = try c.decodeIfPresent(Bool.self, forKey: .threadStop) ?? false
        self.threadForceStop = try c.decodeIfPresent(Bool.self, forKey: .threadForceStop) ?? false
        self.threadVisitedTracking = try c.decodeIfPresent(Bool.self, forKey: .threadVisitedTracking) ?? false
        self.threadSettlement = try c.decodeIfPresent(Bool.self, forKey: .threadSettlement) ?? false
        self.threadPinning = try c.decodeIfPresent(Bool.self, forKey: .threadPinning) ?? false
        self.threadSnooze = try c.decodeIfPresent(Bool.self, forKey: .threadSnooze) ?? false
        self.shellThreadFamilies = try c.decodeIfPresent(Bool.self, forKey: .shellThreadFamilies) ?? false
        self.shellOlderSettled = try c.decodeIfPresent(Bool.self, forKey: .shellOlderSettled) ?? false
        self.providerWorkspaceSnapshotsOnDemand =
            try c.decodeIfPresent(Bool.self, forKey: .providerWorkspaceSnapshotsOnDemand) ?? false
        self.commandOutputStreaming = try c.decodeIfPresent(Bool.self, forKey: .commandOutputStreaming) ?? false
        self.freshContext = try c.decodeIfPresent(Bool.self, forKey: .freshContext) ?? false
    }
}

public struct ExecutionEnvironmentDescriptor: Codable, Sendable, Equatable, Identifiable {
    public let environmentId: String
    public let label: String
    public let platform: ExecutionEnvironmentPlatform
    public let serverVersion: String
    public let orchestrationProtocolVersion: Int?
    public let databaseMigration: Int?
    public let capabilities: ExecutionEnvironmentCapabilities

    public var id: String { environmentId }

    public init(
        environmentId: String,
        label: String,
        platform: ExecutionEnvironmentPlatform,
        serverVersion: String,
        orchestrationProtocolVersion: Int? = 2,
        databaseMigration: Int? = nil,
        capabilities: ExecutionEnvironmentCapabilities = ExecutionEnvironmentCapabilities()
    ) {
        self.environmentId = environmentId
        self.label = label
        self.platform = platform
        self.serverVersion = serverVersion
        self.orchestrationProtocolVersion = orchestrationProtocolVersion
        self.databaseMigration = databaseMigration
        self.capabilities = capabilities
    }
}

public struct ServerAuthDescriptor: Codable, Sendable, Equatable {
    public let policy: String
    public let bootstrapMethods: [String]
    public let sessionMethods: [String]
    public let sessionCookieName: String

    public init(
        policy: String,
        bootstrapMethods: [String],
        sessionMethods: [String],
        sessionCookieName: String
    ) {
        self.policy = policy
        self.bootstrapMethods = bootstrapMethods
        self.sessionMethods = sessionMethods
        self.sessionCookieName = sessionCookieName
    }
}

public struct AuthAccessTokenResult: Codable, Sendable, Equatable {
    public let accessToken: String
    public let issuedTokenType: String
    public let tokenType: String
    public let expiresIn: Double
    public let scope: String

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case issuedTokenType = "issued_token_type"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case scope
    }

    public init(
        accessToken: String,
        issuedTokenType: String,
        tokenType: String,
        expiresIn: Double,
        scope: String
    ) {
        self.accessToken = accessToken
        self.issuedTokenType = issuedTokenType
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.scope = scope
    }
}

public struct AuthWebSocketTicketResult: Codable, Sendable, Equatable {
    public let ticket: String
    public let expiresAt: Date

    public init(ticket: String, expiresAt: Date) {
        self.ticket = ticket
        self.expiresAt = expiresAt
    }
}

// MARK: - Provider Modes, Models & Options

public enum RuntimeMode: String, Codable, Sendable, CaseIterable, Hashable {
    case approvalRequired = "approval-required"
    case autoAcceptEdits = "auto-accept-edits"
    case auto = "auto"
    case fullAccess = "full-access"
}

public enum ProviderInteractionMode: String, Codable, Sendable, CaseIterable, Hashable {
    case `default` = "default"
    case plan = "plan"
}

public struct ProviderOptionChoice: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let description: String?
    public let isDefault: Bool?

    public init(id: String, label: String, description: String? = nil, isDefault: Bool? = nil) {
        self.id = id
        self.label = label
        self.description = description
        self.isDefault = isDefault
    }
}

public enum ProviderOptionDescriptor: Sendable, Equatable, Identifiable {
    case select(SelectOption)
    case boolean(BooleanOption)
    case unknown(id: String, type: String)

    public struct SelectOption: Codable, Sendable, Equatable {
        public let id: String
        public let label: String
        public let description: String?
        public let options: [ProviderOptionChoice]
        public let currentValue: String?
        public let role: String?

        public init(
            id: String,
            label: String,
            description: String? = nil,
            options: [ProviderOptionChoice],
            currentValue: String? = nil,
            role: String? = nil
        ) {
            self.id = id
            self.label = label
            self.description = description
            self.options = options
            self.currentValue = currentValue
            self.role = role
        }
    }

    public struct BooleanOption: Codable, Sendable, Equatable {
        public let id: String
        public let label: String
        public let description: String?
        public let currentValue: Bool?

        public init(
            id: String,
            label: String,
            description: String? = nil,
            currentValue: Bool? = nil
        ) {
            self.id = id
            self.label = label
            self.description = description
            self.currentValue = currentValue
        }
    }

    public var id: String {
        switch self {
        case .select(let option): return option.id
        case .boolean(let option): return option.id
        case .unknown(let id, _): return id
        }
    }

    public var isReasoningControl: Bool {
        if case .select(let option) = self {
            return option.role == "reasoning" || option.id.lowercased().contains("reason") || option.id.lowercased().contains("effort")
        }
        return false
    }
}

extension ProviderOptionDescriptor: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case label
        case description
        case options
        case currentValue
        case role
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "select":
            self = .select(try SelectOption(from: decoder))
        case "boolean":
            self = .boolean(try BooleanOption(from: decoder))
        default:
            let id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
            self = .unknown(id: id, type: type)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .select(let opt):
            try c.encode("select", forKey: .type)
            try c.encode(opt.id, forKey: .id)
            try c.encode(opt.label, forKey: .label)
            try c.encodeIfPresent(opt.description, forKey: .description)
            try c.encode(opt.options, forKey: .options)
            try c.encodeIfPresent(opt.currentValue, forKey: .currentValue)
            try c.encodeIfPresent(opt.role, forKey: .role)
        case .boolean(let opt):
            try c.encode("boolean", forKey: .type)
            try c.encode(opt.id, forKey: .id)
            try c.encode(opt.label, forKey: .label)
            try c.encodeIfPresent(opt.description, forKey: .description)
            try c.encodeIfPresent(opt.currentValue, forKey: .currentValue)
        case .unknown(let id, let type):
            try c.encode(type, forKey: .type)
            try c.encode(id, forKey: .id)
        }
    }
}

public enum ProviderOptionValue: Sendable, Hashable, Codable {
    case string(String)
    case bool(Bool)

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            throw DecodingError.typeMismatch(
                String.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected String or Bool option value"
                )
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        }
    }
}

public struct ProviderOptionSelection: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let value: ProviderOptionValue

    public init(id: String, value: ProviderOptionValue) {
        self.id = id
        self.value = value
    }

    public static func string(_ id: String, _ value: String) -> ProviderOptionSelection {
        ProviderOptionSelection(id: id, value: .string(value))
    }

    public static func bool(_ id: String, _ value: Bool) -> ProviderOptionSelection {
        ProviderOptionSelection(id: id, value: .bool(value))
    }
}

public struct ModelCapabilities: Codable, Sendable, Equatable {
    public let optionDescriptors: [ProviderOptionDescriptor]?

    public init(optionDescriptors: [ProviderOptionDescriptor]? = nil) {
        self.optionDescriptors = optionDescriptors
    }
}

public struct ModelSelection: Sendable, Hashable {
    public let instanceId: String
    public let model: String
    public let options: [ProviderOptionSelection]?

    public init(
        instanceId: String,
        model: String,
        options: [ProviderOptionSelection]? = nil
    ) {
        self.instanceId = instanceId
        self.model = model
        self.options = options?.isEmpty == true ? nil : options
    }
}

extension ModelSelection: Codable {
    private enum CodingKeys: String, CodingKey {
        case instanceId
        case provider
        case model
        case options
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let instanceId = try c.decodeIfPresent(String.self, forKey: .instanceId) {
            self.instanceId = instanceId
        } else if let provider = try c.decodeIfPresent(String.self, forKey: .provider) {
            self.instanceId = provider
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.instanceId,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "ModelSelection requires instanceId or provider"
                )
            )
        }
        self.model = try c.decode(String.self, forKey: .model)

        // Accept canonical array `[{id, value}]` or legacy object `{key: value}`.
        if try !c.contains(.options) || c.decodeNil(forKey: .options) {
            self.options = nil
        } else if let array = try? c.decode([ProviderOptionSelection].self, forKey: .options) {
            self.options = array.isEmpty ? nil : array
        } else if let legacy = try? c.decode([String: JSONValue].self, forKey: .options) {
            let entries: [ProviderOptionSelection] = legacy.keys.sorted().compactMap { key in
                let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedKey.isEmpty, let raw = legacy[key] else { return nil }
                switch raw {
                case .string(let value):
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : ProviderOptionSelection(id: trimmedKey, value: .string(trimmed))
                case .bool(let value):
                    return ProviderOptionSelection(id: trimmedKey, value: .bool(value))
                default:
                    return nil
                }
            }
            self.options = entries.isEmpty ? nil : entries
        } else {
            self.options = nil
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(instanceId, forKey: .instanceId)
        try c.encode(model, forKey: .model)
        if let options, !options.isEmpty {
            try c.encode(options, forKey: .options)
        }
    }
}

// MARK: - Server Providers & ServerConfig

public enum ServerProviderState: String, Codable, Sendable, Hashable {
    case ready
    case warning
    case error
    case disabled
}

public enum ServerProviderAuthStatus: String, Codable, Sendable, Hashable {
    case authenticated
    case unauthenticated
    case unknown
}

public struct ServerProviderAuth: Codable, Sendable, Equatable {
    public let status: ServerProviderAuthStatus
    public let type: String?
    public let label: String?
    public let email: String?
    public let canLogout: Bool?

    public init(
        status: ServerProviderAuthStatus,
        type: String? = nil,
        label: String? = nil,
        email: String? = nil
    ) {
        self.status = status
        self.type = type
        self.label = label
        self.email = email
        self.canLogout = nil
    }

    public init(
        status: ServerProviderAuthStatus,
        type: String? = nil,
        label: String? = nil,
        email: String? = nil,
        canLogout: Bool?
    ) {
        self.status = status
        self.type = type
        self.label = label
        self.email = email
        self.canLogout = canLogout
    }
}

public struct ServerProviderModel: Codable, Sendable, Equatable, Identifiable {
    public let slug: String
    public let name: String
    public let shortName: String?
    public let subProvider: String?
    public let aliases: [String]?
    public let badge: String?
    public let isCustom: Bool
    public let isDefault: Bool?
    public let isLegacy: Bool?
    public let capabilities: ModelCapabilities?

    public var id: String { slug }
    public var displayName: String { shortName ?? name }
    public var optionDescriptors: [ProviderOptionDescriptor] {
        capabilities?.optionDescriptors ?? []
    }

    public init(
        slug: String,
        name: String,
        shortName: String? = nil,
        subProvider: String? = nil,
        aliases: [String]? = nil,
        badge: String? = nil,
        isCustom: Bool = false,
        isDefault: Bool? = nil,
        isLegacy: Bool? = nil,
        capabilities: ModelCapabilities? = nil
    ) {
        self.slug = slug
        self.name = name
        self.shortName = shortName
        self.subProvider = subProvider
        self.aliases = aliases
        self.badge = badge
        self.isCustom = isCustom
        self.isDefault = isDefault
        self.isLegacy = isLegacy
        self.capabilities = capabilities
    }
}

public struct ServerProviderSubProvider: Codable, Sendable, Equatable {
    public let name: String
    public let unavailableReason: String?

    public init(name: String, unavailableReason: String? = nil) {
        self.name = name
        self.unavailableReason = unavailableReason
    }
}

public struct ServerProvider: Codable, Sendable, Equatable, Identifiable {
    public let instanceId: String
    public let driver: String
    public let displayName: String?
    public let accentColor: String?
    public let iconUrl: String?
    public let badgeLabel: String?
    public let showInteractionModeToggle: Bool?
    public let supportedRuntimeModes: [RuntimeMode]?
    public let enabled: Bool
    public let installed: Bool
    public let version: String?
    public let status: ServerProviderState
    public let auth: ServerProviderAuth
    public let checkedAt: Date
    public let message: String?
    public let availability: String?
    public let unavailableReason: String?
    public let models: [ServerProviderModel]
    public let subProviders: [ServerProviderSubProvider]?
    public let setup: ServerProviderSetup?
    public let versionAdvisory: ServerProviderVersionAdvisory?
    public let compatibilityAdvisory: ServerProviderCompatibilityAdvisory?
    public let updateState: ServerProviderUpdateState?
    public let usageLimits: ServerProviderUsageLimits?

    public var id: String { instanceId }
    public var label: String { displayName ?? driver }
    public var isAvailable: Bool { availability != "unavailable" }

    public init(
        instanceId: String,
        driver: String,
        displayName: String? = nil,
        accentColor: String? = nil,
        iconUrl: String? = nil,
        badgeLabel: String? = nil,
        showInteractionModeToggle: Bool? = nil,
        supportedRuntimeModes: [RuntimeMode]? = nil,
        enabled: Bool,
        installed: Bool,
        version: String? = nil,
        status: ServerProviderState,
        auth: ServerProviderAuth,
        checkedAt: Date,
        message: String? = nil,
        availability: String? = nil,
        unavailableReason: String? = nil,
        models: [ServerProviderModel],
        subProviders: [ServerProviderSubProvider]? = nil,
        usageLimits: ServerProviderUsageLimits? = nil
    ) {
        self.instanceId = instanceId
        self.driver = driver
        self.displayName = displayName
        self.accentColor = accentColor
        self.iconUrl = iconUrl
        self.badgeLabel = badgeLabel
        self.showInteractionModeToggle = showInteractionModeToggle
        self.supportedRuntimeModes = supportedRuntimeModes
        self.enabled = enabled
        self.installed = installed
        self.version = version
        self.status = status
        self.auth = auth
        self.checkedAt = checkedAt
        self.message = message
        self.availability = availability
        self.unavailableReason = unavailableReason
        self.models = models
        self.subProviders = subProviders
        self.setup = nil
        self.versionAdvisory = nil
        self.compatibilityAdvisory = nil
        self.updateState = nil
        self.usageLimits = usageLimits
    }

    public init(
        instanceId: String,
        driver: String,
        displayName: String? = nil,
        accentColor: String? = nil,
        iconUrl: String? = nil,
        badgeLabel: String? = nil,
        showInteractionModeToggle: Bool? = nil,
        supportedRuntimeModes: [RuntimeMode]? = nil,
        enabled: Bool,
        installed: Bool,
        version: String? = nil,
        status: ServerProviderState,
        auth: ServerProviderAuth,
        checkedAt: Date,
        message: String? = nil,
        availability: String? = nil,
        unavailableReason: String? = nil,
        models: [ServerProviderModel],
        subProviders: [ServerProviderSubProvider]? = nil,
        setup: ServerProviderSetup?,
        versionAdvisory: ServerProviderVersionAdvisory? = nil,
        compatibilityAdvisory: ServerProviderCompatibilityAdvisory? = nil,
        updateState: ServerProviderUpdateState? = nil,
        usageLimits: ServerProviderUsageLimits? = nil
    ) {
        self.instanceId = instanceId
        self.driver = driver
        self.displayName = displayName
        self.accentColor = accentColor
        self.iconUrl = iconUrl
        self.badgeLabel = badgeLabel
        self.showInteractionModeToggle = showInteractionModeToggle
        self.supportedRuntimeModes = supportedRuntimeModes
        self.enabled = enabled
        self.installed = installed
        self.version = version
        self.status = status
        self.auth = auth
        self.checkedAt = checkedAt
        self.message = message
        self.availability = availability
        self.unavailableReason = unavailableReason
        self.models = models
        self.subProviders = subProviders
        self.setup = setup
        self.versionAdvisory = versionAdvisory
        self.compatibilityAdvisory = compatibilityAdvisory
        self.updateState = updateState
        self.usageLimits = usageLimits
    }

    private enum CodingKeys: String, CodingKey {
        case instanceId
        case driver
        case displayName
        case accentColor
        case iconUrl
        case badgeLabel
        case showInteractionModeToggle
        case supportedRuntimeModes
        case enabled
        case installed
        case version
        case status
        case auth
        case checkedAt
        case message
        case availability
        case unavailableReason
        case models
        case subProviders
        case setup
        case versionAdvisory
        case compatibilityAdvisory
        case updateState
        case usageLimits
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.instanceId = try c.decode(String.self, forKey: .instanceId)
        self.driver = try c.decode(String.self, forKey: .driver)
        self.displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        self.accentColor = try c.decodeIfPresent(String.self, forKey: .accentColor)
        self.iconUrl = try c.decodeIfPresent(String.self, forKey: .iconUrl)
        self.badgeLabel = try c.decodeIfPresent(String.self, forKey: .badgeLabel)
        self.showInteractionModeToggle = try c.decodeIfPresent(Bool.self, forKey: .showInteractionModeToggle)
        self.supportedRuntimeModes = try c.decodeIfPresent([RuntimeMode].self, forKey: .supportedRuntimeModes)
        self.enabled = try c.decode(Bool.self, forKey: .enabled)
        self.installed = try c.decode(Bool.self, forKey: .installed)
        self.version = try c.decodeIfPresent(String.self, forKey: .version)
        self.status = try c.decode(ServerProviderState.self, forKey: .status)
        self.auth = try c.decode(ServerProviderAuth.self, forKey: .auth)
        self.checkedAt = try c.decode(Date.self, forKey: .checkedAt)
        self.message = try c.decodeIfPresent(String.self, forKey: .message)
        self.availability = try c.decodeIfPresent(String.self, forKey: .availability)
        self.unavailableReason = try c.decodeIfPresent(String.self, forKey: .unavailableReason)
        self.models = try c.decode([ServerProviderModel].self, forKey: .models)
        self.subProviders = try c.decodeIfPresent([ServerProviderSubProvider].self, forKey: .subProviders)
        self.setup = try c.decodeIfPresent(ServerProviderSetup.self, forKey: .setup)
        self.versionAdvisory = try c.decodeIfPresent(ServerProviderVersionAdvisory.self, forKey: .versionAdvisory)
        self.compatibilityAdvisory = try c.decodeIfPresent(ServerProviderCompatibilityAdvisory.self, forKey: .compatibilityAdvisory)
        self.updateState = try c.decodeIfPresent(ServerProviderUpdateState.self, forKey: .updateState)
        self.usageLimits = try c.decodeIfPresent(ServerProviderUsageLimits.self, forKey: .usageLimits)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(instanceId, forKey: .instanceId)
        try c.encode(driver, forKey: .driver)
        try c.encodeIfPresent(displayName, forKey: .displayName)
        try c.encodeIfPresent(accentColor, forKey: .accentColor)
        try c.encodeIfPresent(iconUrl, forKey: .iconUrl)
        try c.encodeIfPresent(badgeLabel, forKey: .badgeLabel)
        try c.encodeIfPresent(showInteractionModeToggle, forKey: .showInteractionModeToggle)
        try c.encodeIfPresent(supportedRuntimeModes, forKey: .supportedRuntimeModes)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(installed, forKey: .installed)
        try c.encodeIfPresent(version, forKey: .version)
        try c.encode(status, forKey: .status)
        try c.encode(auth, forKey: .auth)
        try c.encode(checkedAt, forKey: .checkedAt)
        try c.encodeIfPresent(message, forKey: .message)
        try c.encodeIfPresent(availability, forKey: .availability)
        try c.encodeIfPresent(unavailableReason, forKey: .unavailableReason)
        try c.encode(models, forKey: .models)
        try c.encodeIfPresent(subProviders, forKey: .subProviders)
        try c.encodeIfPresent(setup, forKey: .setup)
        try c.encodeIfPresent(versionAdvisory, forKey: .versionAdvisory)
        try c.encodeIfPresent(compatibilityAdvisory, forKey: .compatibilityAdvisory)
        try c.encodeIfPresent(updateState, forKey: .updateState)
        try c.encodeIfPresent(usageLimits, forKey: .usageLimits)
    }
}

public struct ServerConfig: Codable, Sendable, Equatable {
    public let environment: ExecutionEnvironmentDescriptor
    public let auth: ServerAuthDescriptor
    public let cwd: String
    public let hostname: String?
    public let providers: [ServerProvider]
    public let serverTime: Date?
    public let scratchWorkspaceRoot: String?
    public let newProjectsRoot: String?
    public let shellResumeCompletionMarker: Bool?
    public let threadResumeCompletionMarker: Bool?
    public let shellThreadFamilies: Bool?
    public let shellOlderSettled: Bool?
    public let settings: ServerSettings?

    public init(
        environment: ExecutionEnvironmentDescriptor,
        auth: ServerAuthDescriptor,
        cwd: String,
        hostname: String? = nil,
        providers: [ServerProvider],
        serverTime: Date? = nil,
        scratchWorkspaceRoot: String? = nil,
        newProjectsRoot: String? = nil,
        shellResumeCompletionMarker: Bool? = nil,
        threadResumeCompletionMarker: Bool? = nil,
        shellThreadFamilies: Bool? = nil,
        shellOlderSettled: Bool? = nil
    ) {
        self.environment = environment
        self.auth = auth
        self.cwd = cwd
        self.hostname = hostname
        self.providers = providers
        self.serverTime = serverTime
        self.scratchWorkspaceRoot = scratchWorkspaceRoot
        self.newProjectsRoot = newProjectsRoot
        self.shellResumeCompletionMarker = shellResumeCompletionMarker
        self.threadResumeCompletionMarker = threadResumeCompletionMarker
        self.shellThreadFamilies = shellThreadFamilies
        self.shellOlderSettled = shellOlderSettled
        self.settings = nil
    }

    public init(
        environment: ExecutionEnvironmentDescriptor,
        auth: ServerAuthDescriptor,
        cwd: String,
        hostname: String? = nil,
        providers: [ServerProvider],
        serverTime: Date? = nil,
        scratchWorkspaceRoot: String? = nil,
        newProjectsRoot: String? = nil,
        shellResumeCompletionMarker: Bool? = nil,
        threadResumeCompletionMarker: Bool? = nil,
        shellThreadFamilies: Bool? = nil,
        shellOlderSettled: Bool? = nil,
        settings: ServerSettings?
    ) {
        self.environment = environment
        self.auth = auth
        self.cwd = cwd
        self.hostname = hostname
        self.providers = providers
        self.serverTime = serverTime
        self.scratchWorkspaceRoot = scratchWorkspaceRoot
        self.newProjectsRoot = newProjectsRoot
        self.shellResumeCompletionMarker = shellResumeCompletionMarker
        self.threadResumeCompletionMarker = threadResumeCompletionMarker
        self.shellThreadFamilies = shellThreadFamilies
        self.shellOlderSettled = shellOlderSettled
        self.settings = settings
    }
}

public struct SubscribeServerConfigInput: Encodable, Sendable {
    public let workspaceSnapshotsOnDemand: Bool?
    public let providerStatusDeltas: Bool?

    public init(workspaceSnapshotsOnDemand: Bool? = nil, providerStatusDeltas: Bool? = nil) {
        self.workspaceSnapshotsOnDemand = workspaceSnapshotsOnDemand
        self.providerStatusDeltas = providerStatusDeltas
    }
}

public enum ServerConfigStreamEvent: Sendable, Equatable {
    case snapshot(ServerConfig)
    case providerStatuses([ServerProvider])
    case settingsUpdated(ServerSettings)
    case unknown(type: String)
}

extension ServerConfigStreamEvent: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type
        case config
        case payload
    }

    private struct ProviderStatusesPayload: Decodable {
        let providers: [ServerProvider]
    }

    private struct SettingsUpdatedPayload: Decodable {
        let settings: ServerSettings
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "snapshot":
            let config = try c.decode(ServerConfig.self, forKey: .config)
            self = .snapshot(config)
        case "providerStatuses":
            let payload = try c.decode(ProviderStatusesPayload.self, forKey: .payload)
            self = .providerStatuses(payload.providers)
        case "settingsUpdated":
            let payload = try c.decode(SettingsUpdatedPayload.self, forKey: .payload)
            self = .settingsUpdated(payload.settings)
        default:
            self = .unknown(type: type)
        }
    }
}

public struct ServerRefreshProvidersInput: Encodable, Sendable {
    public let instanceId: String?
    public let cwd: String?
    public let fresh: Bool?
    public let refreshModels: Bool?
    public let modelCatalogOnly: Bool?
    public let reloadSecrets: Bool?

    public init(
        instanceId: String? = nil,
        cwd: String? = nil,
        fresh: Bool? = nil,
        refreshModels: Bool? = nil,
        modelCatalogOnly: Bool? = nil
    ) {
        self.instanceId = instanceId
        self.cwd = cwd
        self.fresh = fresh
        self.refreshModels = refreshModels
        self.modelCatalogOnly = modelCatalogOnly
        self.reloadSecrets = nil
    }

    public init(
        instanceId: String? = nil,
        cwd: String? = nil,
        fresh: Bool? = nil,
        refreshModels: Bool? = nil,
        modelCatalogOnly: Bool? = nil,
        reloadSecrets: Bool?
    ) {
        self.instanceId = instanceId
        self.cwd = cwd
        self.fresh = fresh
        self.refreshModels = refreshModels
        self.modelCatalogOnly = modelCatalogOnly
        self.reloadSecrets = reloadSecrets
    }
}

public struct ServerRefreshProvidersResult: Codable, Sendable, Equatable {
    public let providers: [ServerProvider]
}

public struct ServerProbeResult: Codable, Sendable, Equatable {
    public let serverTime: Date?
}
