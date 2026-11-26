import Foundation

// MARK: - Provider Usage Limits Wire Contracts
// Mirrors `packages/contracts/src/providerUsageLimits.ts`.

public enum ServerProviderUsageWindowKind: Sendable, Equatable, Hashable {
    case session
    case weekly
    case monthly
    case other
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .session: "session"
        case .weekly: "weekly"
        case .monthly: "monthly"
        case .other: "other"
        case .unknown(let value): value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "session": self = .session
        case "weekly": self = .weekly
        case "monthly": self = .monthly
        case "other": self = .other
        default: self = .unknown(rawValue)
        }
    }
}

extension ServerProviderUsageWindowKind: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self.init(rawValue: raw)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ServerProviderUsageWindow: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let kind: ServerProviderUsageWindowKind
    public let label: String
    public let modelIds: [String]?
    public let providerIds: [String]?
    public let usedPercent: Double
    public let resetsAt: Date?
    public let windowDurationMins: Int?

    public init(
        id: String,
        kind: ServerProviderUsageWindowKind,
        label: String,
        modelIds: [String]? = nil,
        providerIds: [String]? = nil,
        usedPercent: Double,
        resetsAt: Date? = nil,
        windowDurationMins: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.modelIds = modelIds
        self.providerIds = providerIds
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.windowDurationMins = windowDurationMins
    }
}

extension ServerProviderUsageWindow: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case label
        case modelIds
        case providerIds
        case usedPercent
        case resetsAt
        case windowDurationMins
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.kind = try c.decode(ServerProviderUsageWindowKind.self, forKey: .kind)
        self.label = try c.decode(String.self, forKey: .label)
        self.modelIds = try c.decodeIfPresent([String].self, forKey: .modelIds)
        self.providerIds = try c.decodeIfPresent([String].self, forKey: .providerIds)
        self.usedPercent = try c.decode(Double.self, forKey: .usedPercent)
        if let rawDate = try? c.decodeIfPresent(String.self, forKey: .resetsAt) {
            self.resetsAt = SwftJSON.parseISO8601(rawDate)
        } else {
            self.resetsAt = try? c.decodeIfPresent(Date.self, forKey: .resetsAt)
        }
        self.windowDurationMins = try c.decodeIfPresent(Int.self, forKey: .windowDurationMins)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(label, forKey: .label)
        try c.encodeIfPresent(modelIds, forKey: .modelIds)
        try c.encodeIfPresent(providerIds, forKey: .providerIds)
        try c.encode(usedPercent, forKey: .usedPercent)
        try c.encodeIfPresent(resetsAt, forKey: .resetsAt)
        try c.encodeIfPresent(windowDurationMins, forKey: .windowDurationMins)
    }
}

public enum ServerProviderUsageUnavailableReason: Sendable, Equatable, Hashable {
    case unsupported
    case probeFailed
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .unsupported: "unsupported"
        case .probeFailed: "probeFailed"
        case .unknown(let value): value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "unsupported": self = .unsupported
        case "probeFailed": self = .probeFailed
        default: self = .unknown(rawValue)
        }
    }
}

extension ServerProviderUsageUnavailableReason: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self.init(rawValue: raw)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ServerProviderUsageUnavailable: Codable, Sendable, Equatable, Hashable {
    public let reason: ServerProviderUsageUnavailableReason
    public let message: String?

    public init(reason: ServerProviderUsageUnavailableReason, message: String? = nil) {
        self.reason = reason
        self.message = message
    }
}

public struct ServerProviderExternalUsage: Codable, Sendable, Equatable, Hashable {
    public let label: String
    public let url: String

    public init(label: String, url: String) {
        self.label = label
        self.url = url
    }
}

public struct ServerProviderUsageLimits: Sendable, Equatable, Hashable {
    public let checkedAt: Date
    public let windows: [ServerProviderUsageWindow]
    public let zeroSpendCap: Bool?
    public let credentialFingerprint: String?
    public let externalUsage: ServerProviderExternalUsage?
    public let unavailable: ServerProviderUsageUnavailable?

    public init(
        checkedAt: Date,
        windows: [ServerProviderUsageWindow] = [],
        zeroSpendCap: Bool? = nil,
        credentialFingerprint: String? = nil,
        unavailable: ServerProviderUsageUnavailable? = nil,
        externalUsage: ServerProviderExternalUsage? = nil
    ) {
        self.checkedAt = checkedAt
        self.windows = windows
        self.zeroSpendCap = zeroSpendCap
        self.credentialFingerprint = credentialFingerprint
        self.externalUsage = externalUsage
        self.unavailable = unavailable
    }
}

extension ServerProviderUsageLimits: Codable {
    private enum CodingKeys: String, CodingKey {
        case checkedAt
        case windows
        case zeroSpendCap
        case credentialFingerprint
        case externalUsage
        case unavailable
    }

    private struct FailableWindow: Decodable {
        let value: ServerProviderUsageWindow?

        init(from decoder: any Decoder) throws {
            self.value = try? ServerProviderUsageWindow(from: decoder)
        }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let rawDate = try? c.decode(String.self, forKey: .checkedAt),
           let parsed = SwftJSON.parseISO8601(rawDate)
        {
            self.checkedAt = parsed
        } else {
            self.checkedAt = try c.decode(Date.self, forKey: .checkedAt)
        }
        // Mirrors ForwardCompatibleArray: skip individual unrecognized/malformed entries instead of failing config sync.
        if let rawWindows = try c.decodeIfPresent([FailableWindow].self, forKey: .windows) {
            self.windows = rawWindows.compactMap(\.value)
        } else {
            self.windows = []
        }
        self.zeroSpendCap = try c.decodeIfPresent(Bool.self, forKey: .zeroSpendCap)
        self.credentialFingerprint = try c.decodeIfPresent(String.self, forKey: .credentialFingerprint)
        self.externalUsage = try c.decodeIfPresent(ServerProviderExternalUsage.self, forKey: .externalUsage)
        self.unavailable = try c.decodeIfPresent(ServerProviderUsageUnavailable.self, forKey: .unavailable)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(checkedAt, forKey: .checkedAt)
        try c.encode(windows, forKey: .windows)
        try c.encodeIfPresent(zeroSpendCap, forKey: .zeroSpendCap)
        try c.encodeIfPresent(credentialFingerprint, forKey: .credentialFingerprint)
        try c.encodeIfPresent(externalUsage, forKey: .externalUsage)
        try c.encodeIfPresent(unavailable, forKey: .unavailable)
    }
}
