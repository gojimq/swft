import Foundation

// MARK: - Provider Setup & Advisories

public struct ServerProviderSetup: Codable, Sendable, Equatable {
    public let canAuthenticate: Bool
    public let canInstall: Bool
    public let documentationUrl: String?

    public init(
        canAuthenticate: Bool,
        canInstall: Bool,
        documentationUrl: String? = nil
    ) {
        self.canAuthenticate = canAuthenticate
        self.canInstall = canInstall
        self.documentationUrl = documentationUrl
    }
}

public struct ServerProviderVersionAdvisory: Codable, Sendable, Equatable {
    public let status: String
    public let currentVersion: String?
    public let latestVersion: String?
    public let updateCommand: String?
    public let canUpdate: Bool
    public let checkedAt: Date?
    public let message: String?

    public init(
        status: String,
        currentVersion: String? = nil,
        latestVersion: String? = nil,
        updateCommand: String? = nil,
        canUpdate: Bool = false,
        checkedAt: Date? = nil,
        message: String? = nil
    ) {
        self.status = status
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.updateCommand = updateCommand
        self.canUpdate = canUpdate
        self.checkedAt = checkedAt
        self.message = message
    }

    private enum CodingKeys: String, CodingKey {
        case status, currentVersion, latestVersion, updateCommand, canUpdate, checkedAt, message
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.status = try c.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        self.currentVersion = try c.decodeIfPresent(String.self, forKey: .currentVersion)
        self.latestVersion = try c.decodeIfPresent(String.self, forKey: .latestVersion)
        self.updateCommand = try c.decodeIfPresent(String.self, forKey: .updateCommand)
        self.canUpdate = try c.decodeIfPresent(Bool.self, forKey: .canUpdate) ?? false
        self.checkedAt = try c.decodeIfPresent(Date.self, forKey: .checkedAt)
        self.message = try c.decodeIfPresent(String.self, forKey: .message)
    }
}

public struct ServerProviderCompatibilityAdvisory: Codable, Sendable, Equatable {
    public let status: String
    public let latestVersionStatus: String?
    public let message: String?
    public let recommendedVersion: String?
    public let recommendedRange: String?

    public init(
        status: String,
        latestVersionStatus: String? = nil,
        message: String? = nil,
        recommendedVersion: String? = nil,
        recommendedRange: String? = nil
    ) {
        self.status = status
        self.latestVersionStatus = latestVersionStatus
        self.message = message
        self.recommendedVersion = recommendedVersion
        self.recommendedRange = recommendedRange
    }
}

public struct ServerProviderUpdateState: Codable, Sendable, Equatable {
    public let status: String
    public let startedAt: Date?
    public let finishedAt: Date?
    public let message: String?
    public let output: String?

    public init(
        status: String,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        message: String? = nil,
        output: String? = nil
    ) {
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.message = message
        self.output = output
    }
}

// MARK: - Server Settings Enums

public enum ThreadEnvMode: String, Codable, Sendable, CaseIterable, Hashable {
    case local = "local"
    case worktree = "worktree"
}

public enum ResponseStreamingMode: String, Codable, Sendable, CaseIterable, Hashable {
    case paragraph = "paragraph"
    case turn = "turn"
}

public enum IdleCompactionMode: String, Codable, Sendable, CaseIterable, Hashable {
    case onReturn = "onReturn"
    case beforeCacheExpires = "beforeCacheExpires"
    case off = "off"
}

// MARK: - Provider Instance Config & Mutations

public struct ProviderInstanceEnvironmentVariable: Codable, Sendable, Equatable {
    public let name: String
    public let value: String
    public let sensitive: Bool
    public let valueRedacted: Bool?
    /// Preserved verbatim when the server stores a secret provider reference.
    public let secret: JSONValue?

    public var isSecretReference: Bool { secret != nil }

    public init(
        name: String,
        value: String,
        sensitive: Bool = false,
        valueRedacted: Bool? = nil,
        secret: JSONValue? = nil
    ) {
        self.name = name
        self.value = value
        self.sensitive = sensitive
        self.valueRedacted = valueRedacted
        self.secret = secret
    }

    private enum CodingKeys: String, CodingKey {
        case name, value, sensitive, valueRedacted, secret
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decode(String.self, forKey: .name)
        self.value = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
        self.sensitive = try c.decodeIfPresent(Bool.self, forKey: .sensitive) ?? false
        self.valueRedacted = try c.decodeIfPresent(Bool.self, forKey: .valueRedacted)
        self.secret = try c.decodeIfPresent(JSONValue.self, forKey: .secret)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(value, forKey: .value)
        try c.encode(sensitive, forKey: .sensitive)
        try c.encodeIfPresent(valueRedacted, forKey: .valueRedacted)
        try c.encodeIfPresent(secret, forKey: .secret)
    }
}

public struct ProviderInstanceConfig: Codable, Sendable, Equatable {
    public var driver: String
    public var displayName: String?
    public var accentColor: String?
    public var environment: [ProviderInstanceEnvironmentVariable]?
    public var enabled: Bool?
    public var config: JSONValue?

    public init(
        driver: String,
        displayName: String? = nil,
        accentColor: String? = nil,
        environment: [ProviderInstanceEnvironmentVariable]? = nil,
        enabled: Bool? = nil,
        config: JSONValue? = nil
    ) {
        self.driver = driver
        self.displayName = displayName
        self.accentColor = accentColor
        self.environment = environment
        self.enabled = enabled
        self.config = config
    }

    public var configObject: [String: JSONValue]? {
        config?.objectValue
    }
}

public enum ProviderInstanceMutation: Sendable, Equatable, Encodable {
    case create(instanceId: String, instance: ProviderInstanceConfig)
    case upsert(instanceId: String, instance: ProviderInstanceConfig)
    case remove(instanceId: String)

    private enum CodingKeys: String, CodingKey {
        case operation, instanceId, instance
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .create(let instanceId, let instance):
            try c.encode("create", forKey: .operation)
            try c.encode(instanceId, forKey: .instanceId)
            try c.encode(instance, forKey: .instance)
        case .upsert(let instanceId, let instance):
            try c.encode("upsert", forKey: .operation)
            try c.encode(instanceId, forKey: .instanceId)
            try c.encode(instance, forKey: .instance)
        case .remove(let instanceId):
            try c.encode("remove", forKey: .operation)
            try c.encode(instanceId, forKey: .instanceId)
        }
    }
}

// MARK: - ServerSettings & Patches

public struct ServerSettings: Codable, Sendable, Equatable {
    public var defaultModelSelection: ModelSelection?
    public var defaultRuntimeMode: RuntimeMode
    public var defaultThreadEnvMode: ThreadEnvMode?
    public var responseStreamingMode: ResponseStreamingMode
    public var keepAwakeWhileAgentsWork: Bool
    public var continueThreadsAfterServerUpdate: Bool
    public var sidebarAutoSettleOnMerge: Bool
    public var enableProviderUpdateChecks: Bool
    public var idleCompaction: IdleCompactionMode?
    public var compactIdleThreads: JSONValue?
    public var providerInstances: [String: ProviderInstanceConfig]

    public var effectiveIdleCompaction: IdleCompactionMode {
        if let idleCompaction { return idleCompaction }
        if case .string(let raw) = compactIdleThreads, let parsed = IdleCompactionMode(rawValue: raw) {
            return parsed
        }
        if case .bool(let flag) = compactIdleThreads {
            return flag ? .beforeCacheExpires : .onReturn
        }
        return .onReturn
    }

    public init(
        defaultModelSelection: ModelSelection? = nil,
        defaultRuntimeMode: RuntimeMode = .fullAccess,
        defaultThreadEnvMode: ThreadEnvMode? = nil,
        responseStreamingMode: ResponseStreamingMode = .paragraph,
        keepAwakeWhileAgentsWork: Bool = true,
        continueThreadsAfterServerUpdate: Bool = true,
        sidebarAutoSettleOnMerge: Bool = true,
        enableProviderUpdateChecks: Bool = true,
        idleCompaction: IdleCompactionMode? = nil,
        compactIdleThreads: JSONValue? = nil,
        providerInstances: [String: ProviderInstanceConfig] = [:]
    ) {
        self.defaultModelSelection = defaultModelSelection
        self.defaultRuntimeMode = defaultRuntimeMode
        self.defaultThreadEnvMode = defaultThreadEnvMode
        self.responseStreamingMode = responseStreamingMode
        self.keepAwakeWhileAgentsWork = keepAwakeWhileAgentsWork
        self.continueThreadsAfterServerUpdate = continueThreadsAfterServerUpdate
        self.sidebarAutoSettleOnMerge = sidebarAutoSettleOnMerge
        self.enableProviderUpdateChecks = enableProviderUpdateChecks
        self.idleCompaction = idleCompaction
        self.compactIdleThreads = compactIdleThreads
        self.providerInstances = providerInstances
    }

    private enum CodingKeys: String, CodingKey {
        case defaultModelSelection
        case defaultRuntimeMode
        case defaultThreadEnvMode
        case responseStreamingMode
        case keepAwakeWhileAgentsWork
        case continueThreadsAfterServerUpdate
        case sidebarAutoSettleOnMerge
        case enableProviderUpdateChecks
        case idleCompaction
        case compactIdleThreads
        case providerInstances
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.defaultModelSelection = try c.decodeIfPresent(ModelSelection.self, forKey: .defaultModelSelection)
        let rawMode = try c.decodeIfPresent(String.self, forKey: .defaultRuntimeMode)
        self.defaultRuntimeMode = rawMode.flatMap(RuntimeMode.init(rawValue:)) ?? .fullAccess
        let rawEnvMode = try c.decodeIfPresent(String.self, forKey: .defaultThreadEnvMode)
        self.defaultThreadEnvMode = rawEnvMode.flatMap(ThreadEnvMode.init(rawValue:))
        let rawStream = try c.decodeIfPresent(String.self, forKey: .responseStreamingMode)
        self.responseStreamingMode = rawStream.flatMap(ResponseStreamingMode.init(rawValue:)) ?? .paragraph
        self.keepAwakeWhileAgentsWork = try c.decodeIfPresent(Bool.self, forKey: .keepAwakeWhileAgentsWork) ?? true
        self.continueThreadsAfterServerUpdate = try c.decodeIfPresent(Bool.self, forKey: .continueThreadsAfterServerUpdate) ?? true
        self.sidebarAutoSettleOnMerge = try c.decodeIfPresent(Bool.self, forKey: .sidebarAutoSettleOnMerge) ?? true
        self.enableProviderUpdateChecks = try c.decodeIfPresent(Bool.self, forKey: .enableProviderUpdateChecks) ?? true
        let rawIdle = try c.decodeIfPresent(String.self, forKey: .idleCompaction)
        self.idleCompaction = rawIdle.flatMap(IdleCompactionMode.init(rawValue:))
        self.compactIdleThreads = try c.decodeIfPresent(JSONValue.self, forKey: .compactIdleThreads)
        self.providerInstances = try c.decodeIfPresent([String: ProviderInstanceConfig].self, forKey: .providerInstances) ?? [:]
    }
}

/// Distinguishes "omit key from patch" vs "explicitly encode `null` to clear a nullable setting".
public enum PatchValue<Value: Encodable & Sendable & Equatable>: Sendable, Equatable {
    case unchanged
    case set(Value?)
}

public struct ServerSettingsPatch: Encodable, Sendable, Equatable {
    public var defaultModelSelection: PatchValue<ModelSelection>
    public var defaultRuntimeMode: RuntimeMode?
    public var defaultThreadEnvMode: PatchValue<ThreadEnvMode>
    public var responseStreamingMode: ResponseStreamingMode?
    public var keepAwakeWhileAgentsWork: Bool?
    public var continueThreadsAfterServerUpdate: Bool?
    public var sidebarAutoSettleOnMerge: Bool?
    public var enableProviderUpdateChecks: Bool?
    public var idleCompaction: IdleCompactionMode?
    public var compactIdleThreads: JSONValue?

    public init(
        defaultModelSelection: PatchValue<ModelSelection> = .unchanged,
        defaultRuntimeMode: RuntimeMode? = nil,
        defaultThreadEnvMode: PatchValue<ThreadEnvMode> = .unchanged,
        responseStreamingMode: ResponseStreamingMode? = nil,
        keepAwakeWhileAgentsWork: Bool? = nil,
        continueThreadsAfterServerUpdate: Bool? = nil,
        sidebarAutoSettleOnMerge: Bool? = nil,
        enableProviderUpdateChecks: Bool? = nil,
        idleCompaction: IdleCompactionMode? = nil,
        compactIdleThreads: JSONValue? = nil
    ) {
        self.defaultModelSelection = defaultModelSelection
        self.defaultRuntimeMode = defaultRuntimeMode
        self.defaultThreadEnvMode = defaultThreadEnvMode
        self.responseStreamingMode = responseStreamingMode
        self.keepAwakeWhileAgentsWork = keepAwakeWhileAgentsWork
        self.continueThreadsAfterServerUpdate = continueThreadsAfterServerUpdate
        self.sidebarAutoSettleOnMerge = sidebarAutoSettleOnMerge
        self.enableProviderUpdateChecks = enableProviderUpdateChecks
        self.idleCompaction = idleCompaction
        self.compactIdleThreads = compactIdleThreads
    }

    private enum CodingKeys: String, CodingKey {
        case defaultModelSelection
        case defaultRuntimeMode
        case defaultThreadEnvMode
        case responseStreamingMode
        case keepAwakeWhileAgentsWork
        case continueThreadsAfterServerUpdate
        case sidebarAutoSettleOnMerge
        case enableProviderUpdateChecks
        case idleCompaction
        case compactIdleThreads
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if case .set(let value) = defaultModelSelection {
            if let value { try c.encode(value, forKey: .defaultModelSelection) }
            else { try c.encodeNil(forKey: .defaultModelSelection) }
        }
        try c.encodeIfPresent(defaultRuntimeMode, forKey: .defaultRuntimeMode)
        if case .set(let value) = defaultThreadEnvMode {
            if let value { try c.encode(value, forKey: .defaultThreadEnvMode) }
            else { try c.encodeNil(forKey: .defaultThreadEnvMode) }
        }
        try c.encodeIfPresent(responseStreamingMode, forKey: .responseStreamingMode)
        try c.encodeIfPresent(keepAwakeWhileAgentsWork, forKey: .keepAwakeWhileAgentsWork)
        try c.encodeIfPresent(continueThreadsAfterServerUpdate, forKey: .continueThreadsAfterServerUpdate)
        try c.encodeIfPresent(sidebarAutoSettleOnMerge, forKey: .sidebarAutoSettleOnMerge)
        try c.encodeIfPresent(enableProviderUpdateChecks, forKey: .enableProviderUpdateChecks)
        try c.encodeIfPresent(idleCompaction, forKey: .idleCompaction)
        try c.encodeIfPresent(compactIdleThreads, forKey: .compactIdleThreads)
    }
}

public struct ServerUpdateSettingsInput: Encodable, Sendable, Equatable {
    public let patch: ServerSettingsPatch
    public let providerInstanceMutation: ProviderInstanceMutation?

    public init(
        patch: ServerSettingsPatch = ServerSettingsPatch(),
        providerInstanceMutation: ProviderInstanceMutation? = nil
    ) {
        self.patch = patch
        self.providerInstanceMutation = providerInstanceMutation
    }
}

// MARK: - Provider Auth & Install Setup Protocol

public struct ProviderSetupInput: Encodable, Sendable, Equatable {
    public let instanceId: String

    public init(instanceId: String) {
        self.instanceId = instanceId
    }
}

public struct ProviderAuthMethod: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let accountEmail: String?
    public let canRemove: Bool?
    public let name: String
    public let description: String?
    public let type: String

    public init(
        id: String,
        accountEmail: String? = nil,
        canRemove: Bool? = nil,
        name: String,
        description: String? = nil,
        type: String
    ) {
        self.id = id
        self.accountEmail = accountEmail
        self.canRemove = canRemove
        self.name = name
        self.description = description
        self.type = type
    }
}

public struct ProviderAuthCredentialField: Codable, Sendable, Equatable, Identifiable {
    public let name: String
    public let label: String
    public let secret: Bool

    public var id: String { name }

    public init(name: String, label: String, secret: Bool) {
        self.name = name
        self.label = label
        self.secret = secret
    }
}

public enum ProviderAuthInteraction: Sendable, Equatable {
    case browser(id: String, url: String, requiresConsent: Bool, acceptsCallback: Bool?)
    case deviceCode(id: String, url: String, userCode: String)
    case terminal(id: String, output: String, outputOffset: Int?)
    case credentials(id: String, fields: [ProviderAuthCredentialField])
    case unknown(id: String, type: String)

    public var id: String {
        switch self {
        case .browser(let id, _, _, _),
             .deviceCode(let id, _, _),
             .terminal(let id, _, _),
             .credentials(let id, _),
             .unknown(let id, _):
            return id
        }
    }
}

extension ProviderAuthInteraction: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, id, url, requiresConsent, acceptsCallback, userCode, output, outputOffset, fields
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        let id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        switch type {
        case "browser":
            self = .browser(
                id: id,
                url: try c.decode(String.self, forKey: .url),
                requiresConsent: try c.decodeIfPresent(Bool.self, forKey: .requiresConsent) ?? false,
                acceptsCallback: try c.decodeIfPresent(Bool.self, forKey: .acceptsCallback)
            )
        case "deviceCode":
            self = .deviceCode(
                id: id,
                url: try c.decode(String.self, forKey: .url),
                userCode: try c.decode(String.self, forKey: .userCode)
            )
        case "terminal":
            self = .terminal(
                id: id,
                output: try c.decodeIfPresent(String.self, forKey: .output) ?? "",
                outputOffset: try c.decodeIfPresent(Int.self, forKey: .outputOffset)
            )
        case "credentials":
            self = .credentials(
                id: id,
                fields: try c.decodeIfPresent([ProviderAuthCredentialField].self, forKey: .fields) ?? []
            )
        default:
            self = .unknown(id: id, type: type)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .browser(let id, let url, let requiresConsent, let acceptsCallback):
            try c.encode("browser", forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(url, forKey: .url)
            try c.encode(requiresConsent, forKey: .requiresConsent)
            try c.encodeIfPresent(acceptsCallback, forKey: .acceptsCallback)
        case .deviceCode(let id, let url, let userCode):
            try c.encode("deviceCode", forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(url, forKey: .url)
            try c.encode(userCode, forKey: .userCode)
        case .terminal(let id, let output, let outputOffset):
            try c.encode("terminal", forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(output, forKey: .output)
            try c.encodeIfPresent(outputOffset, forKey: .outputOffset)
        case .credentials(let id, let fields):
            try c.encode("credentials", forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(fields, forKey: .fields)
        case .unknown(let id, let type):
            try c.encode(type, forKey: .type)
            try c.encode(id, forKey: .id)
        }
    }
}

public enum ProviderAuthResponse: Sendable, Equatable, Encodable {
    case browser(action: String)
    case credentials(values: [String: String])

    private enum CodingKeys: String, CodingKey {
        case type, action, values
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .browser(let action):
            try c.encode("browser", forKey: .type)
            try c.encode(action, forKey: .action)
        case .credentials(let values):
            try c.encode("credentials", forKey: .type)
            try c.encode(values, forKey: .values)
        }
    }
}

public enum ProviderAuthPhase: String, Codable, Sendable, Hashable {
    case idle
    case starting
    case waiting
    case verifying
    case succeeded
    case failed
    case cancelled
}

public struct ProviderAuthState: Codable, Sendable, Equatable {
    public let instanceId: String
    public let phase: ProviderAuthPhase
    public let flowId: String?
    public let authorizationUrl: String?
    public let expiresAt: Date?
    public let message: String?
    public let methods: [ProviderAuthMethod]?
    public let interaction: ProviderAuthInteraction?
    public let credentialOwner: String?

    public init(
        instanceId: String,
        phase: ProviderAuthPhase,
        flowId: String? = nil,
        authorizationUrl: String? = nil,
        expiresAt: Date? = nil,
        message: String? = nil,
        methods: [ProviderAuthMethod]? = nil,
        interaction: ProviderAuthInteraction? = nil,
        credentialOwner: String? = nil
    ) {
        self.instanceId = instanceId
        self.phase = phase
        self.flowId = flowId
        self.authorizationUrl = authorizationUrl
        self.expiresAt = expiresAt
        self.message = message
        self.methods = methods
        self.interaction = interaction
        self.credentialOwner = credentialOwner
    }
}

public struct ProviderAuthStartInput: Encodable, Sendable, Equatable {
    public let instanceId: String
    public let methodId: String?
    public let returnUrl: String?
    public let callbackMode: String?

    public init(
        instanceId: String,
        methodId: String? = nil,
        returnUrl: String? = nil,
        callbackMode: String? = nil
    ) {
        self.instanceId = instanceId
        self.methodId = methodId
        self.returnUrl = returnUrl
        self.callbackMode = callbackMode
    }
}

public struct ProviderAuthRespondInput: Encodable, Sendable, Equatable {
    public let instanceId: String
    public let flowId: String
    public let interactionId: String
    public let response: ProviderAuthResponse

    public init(
        instanceId: String,
        flowId: String,
        interactionId: String,
        response: ProviderAuthResponse
    ) {
        self.instanceId = instanceId
        self.flowId = flowId
        self.interactionId = interactionId
        self.response = response
    }
}

public struct ProviderAuthCompleteInput: Encodable, Sendable, Equatable {
    public let instanceId: String
    public let flowId: String
    public let callbackUrl: String

    public init(instanceId: String, flowId: String, callbackUrl: String) {
        self.instanceId = instanceId
        self.flowId = flowId
        self.callbackUrl = callbackUrl
    }
}

public struct ProviderAuthCancelInput: Encodable, Sendable, Equatable {
    public let instanceId: String
    public let flowId: String

    public init(instanceId: String, flowId: String) {
        self.instanceId = instanceId
        self.flowId = flowId
    }
}

public enum ProviderInstallPhase: String, Codable, Sendable, Hashable {
    case idle
    case downloading
    case extracting
    case verifying
    case succeeded
    case failed
    case cancelled
}

public struct ProviderInstallState: Codable, Sendable, Equatable {
    public let driver: String
    public let operationId: String?
    public let phase: ProviderInstallPhase
    public let downloadedBytes: Int
    public let totalBytes: Int?
    public let version: String?
    public let installedVersion: String?
    public let executablePath: String?
    public let source: String?
    public let canRemove: Bool
    public let message: String?

    public init(
        driver: String,
        operationId: String? = nil,
        phase: ProviderInstallPhase,
        downloadedBytes: Int = 0,
        totalBytes: Int? = nil,
        version: String? = nil,
        installedVersion: String? = nil,
        executablePath: String? = nil,
        source: String? = nil,
        canRemove: Bool = false,
        message: String? = nil
    ) {
        self.driver = driver
        self.operationId = operationId
        self.phase = phase
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
        self.version = version
        self.installedVersion = installedVersion
        self.executablePath = executablePath
        self.source = source
        self.canRemove = canRemove
        self.message = message
    }
}

public struct ProviderInstallCancelInput: Encodable, Sendable, Equatable {
    public let instanceId: String
    public let operationId: String

    public init(instanceId: String, operationId: String) {
        self.instanceId = instanceId
        self.operationId = operationId
    }
}
