import Foundation

// MARK: - Usage Summary Wire Contracts
// Mirrors `packages/contracts/src/usage.ts`.

public enum UsageContract {
    public static let currentVersion: Int = 6
    public static let mergeCompatibleSince: Int = 4
}

/// Sum uncached input, cache reads, and cache writes for input totals; reasoning is already included in output.
public struct UsageTokenTotals: Codable, Sendable, Equatable, Hashable {
    public let uncachedInputTokens: Int
    public let cachedInputTokens: Int
    public let cacheCreationTokens: Int
    public let outputTokens: Int
    public let reasoningTokens: Int

    public var totalInputTokens: Int {
        uncachedInputTokens + cachedInputTokens + cacheCreationTokens
    }

    public var totalTokens: Int {
        totalInputTokens + outputTokens
    }

    public init(
        uncachedInputTokens: Int = 0,
        cachedInputTokens: Int = 0,
        cacheCreationTokens: Int = 0,
        outputTokens: Int = 0,
        reasoningTokens: Int = 0
    ) {
        self.uncachedInputTokens = uncachedInputTokens
        self.cachedInputTokens = cachedInputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
    }
}

public struct UsageCategoryCost: Codable, Sendable, Equatable, Hashable {
    public let input: Double
    public let cacheRead: Double
    public let cacheWrite: Double
    public let output: Double

    public init(input: Double = 0, cacheRead: Double = 0, cacheWrite: Double = 0, output: Double = 0) {
        self.input = input
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.output = output
    }
}

public struct UsageBucket: Codable, Sendable, Equatable, Hashable {
    public let day: String
    public let hourStart: String?
    public let provider: String
    public let model: String
    public let sourcePath: String?
    public let totals: UsageTokenTotals
    public let costUsd: Double
    public let cacheSavingsUsd: Double
    public let categoryCostUsd: UsageCategoryCost?
    public let fastCostUsd: Double?
    public let ultrafastCostUsd: Double?
    public let speedPremiumUsd: Double?
    public let costSource: String
    public let records: Int
    public let unpricedRecords: Int
    public let unpricedTokens: Int?
    public let sessions: Int

    public init(
        day: String,
        hourStart: String? = nil,
        provider: String,
        model: String,
        sourcePath: String? = nil,
        totals: UsageTokenTotals,
        costUsd: Double,
        cacheSavingsUsd: Double = 0,
        categoryCostUsd: UsageCategoryCost? = nil,
        fastCostUsd: Double? = nil,
        ultrafastCostUsd: Double? = nil,
        speedPremiumUsd: Double? = nil,
        costSource: String = "modelPriced",
        records: Int = 0,
        unpricedRecords: Int = 0,
        unpricedTokens: Int? = nil,
        sessions: Int = 0
    ) {
        self.day = day
        self.hourStart = hourStart
        self.provider = provider
        self.model = model
        self.sourcePath = sourcePath
        self.totals = totals
        self.costUsd = costUsd
        self.cacheSavingsUsd = cacheSavingsUsd
        self.categoryCostUsd = categoryCostUsd
        self.fastCostUsd = fastCostUsd
        self.ultrafastCostUsd = ultrafastCostUsd
        self.speedPremiumUsd = speedPremiumUsd
        self.costSource = costSource
        self.records = records
        self.unpricedRecords = unpricedRecords
        self.unpricedTokens = unpricedTokens
        self.sessions = sessions
    }
}

public struct UsageSourceFingerprint: Codable, Sendable, Equatable, Hashable {
    public let hostId: String
    public let provider: String
    public let resolvedHomePath: String
    public let volumeId: String
    public let physicalSourceId: String?

    public init(
        hostId: String,
        provider: String,
        resolvedHomePath: String,
        volumeId: String = "",
        physicalSourceId: String? = nil
    ) {
        self.hostId = hostId
        self.provider = provider
        self.resolvedHomePath = resolvedHomePath
        self.volumeId = volumeId
        self.physicalSourceId = physicalSourceId
    }
}

public struct UsageSource: Codable, Sendable, Equatable, Hashable {
    public let fingerprint: UsageSourceFingerprint
    public let status: String
    public let scannedFiles: Int
    public let skippedFiles: Int
    public let malformedRecords: Int
    public let distinctSessions: Int
    public let message: String?
    public let refreshing: Bool?

    public init(
        fingerprint: UsageSourceFingerprint,
        status: String,
        scannedFiles: Int = 0,
        skippedFiles: Int = 0,
        malformedRecords: Int = 0,
        distinctSessions: Int = 0,
        message: String? = nil,
        refreshing: Bool? = nil
    ) {
        self.fingerprint = fingerprint
        self.status = status
        self.scannedFiles = scannedFiles
        self.skippedFiles = skippedFiles
        self.malformedRecords = malformedRecords
        self.distinctSessions = distinctSessions
        self.message = message
        self.refreshing = refreshing
    }
}

public struct UsagePricing: Codable, Sendable, Equatable, Hashable {
    public let status: String
    public let source: String
    public let fetchedAt: String?
    public let knownModels: Int

    public init(
        status: String,
        source: String,
        fetchedAt: String? = nil,
        knownModels: Int = 0
    ) {
        self.status = status
        self.source = source
        self.fetchedAt = fetchedAt
        self.knownModels = knownModels
    }
}

public struct UsageSummaryInput: Codable, Sendable, Equatable, Hashable {
    public let sinceDay: String
    public let untilDay: String
    public let timeZone: String
    public let resolution: String?
    public let sinceTime: String?
    public let untilTime: String?
    public let awaitRefresh: Bool?
    public let provisional: Bool?

    public init(
        sinceDay: String,
        untilDay: String,
        timeZone: String,
        resolution: String? = nil,
        sinceTime: String? = nil,
        untilTime: String? = nil,
        awaitRefresh: Bool? = nil,
        provisional: Bool? = nil
    ) {
        self.sinceDay = sinceDay
        self.untilDay = untilDay
        self.timeZone = timeZone
        self.resolution = resolution
        self.sinceTime = sinceTime
        self.untilTime = untilTime
        self.awaitRefresh = awaitRefresh
        self.provisional = provisional
    }
}

public struct UsageSummary: Sendable, Equatable, Hashable {
    public let contractVersion: Int
    public let readAt: String
    public let timeZone: String
    public let sinceDay: String
    public let untilDay: String
    public let buckets: [UsageBucket]
    public let sources: [UsageSource]
    public let pricing: UsagePricing
    public let scanDurationMs: Int

    public var readAtDate: Date? {
        SwftJSON.parseISO8601(readAt)
    }

    public init(
        contractVersion: Int = UsageContract.currentVersion,
        readAt: String,
        timeZone: String,
        sinceDay: String,
        untilDay: String,
        buckets: [UsageBucket] = [],
        sources: [UsageSource] = [],
        pricing: UsagePricing,
        scanDurationMs: Int = 0
    ) {
        self.contractVersion = contractVersion
        self.readAt = readAt
        self.timeZone = timeZone
        self.sinceDay = sinceDay
        self.untilDay = untilDay
        self.buckets = buckets
        self.sources = sources
        self.pricing = pricing
        self.scanDurationMs = scanDurationMs
    }
}

extension UsageSummary: Codable {
    private enum CodingKeys: String, CodingKey {
        case contractVersion
        case readAt
        case timeZone
        case sinceDay
        case untilDay
        case buckets
        case sources
        case pricing
        case scanDurationMs
    }

    private struct FailableEntry<T: Decodable>: Decodable {
        let value: T?

        init(from decoder: any Decoder) throws {
            self.value = try? T(from: decoder)
        }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.contractVersion = try c.decode(Int.self, forKey: .contractVersion)
        self.readAt = try c.decode(String.self, forKey: .readAt)
        self.timeZone = try c.decode(String.self, forKey: .timeZone)
        self.sinceDay = try c.decode(String.self, forKey: .sinceDay)
        self.untilDay = try c.decode(String.self, forKey: .untilDay)
        // Mirrors ForwardCompatibleArray: skip individual unrecognized/malformed entries instead of failing decoding.
        if let rawBuckets = try c.decodeIfPresent([FailableEntry<UsageBucket>].self, forKey: .buckets) {
            self.buckets = rawBuckets.compactMap(\.value)
        } else {
            self.buckets = []
        }
        if let rawSources = try c.decodeIfPresent([FailableEntry<UsageSource>].self, forKey: .sources) {
            self.sources = rawSources.compactMap(\.value)
        } else {
            self.sources = []
        }
        self.pricing = try c.decode(UsagePricing.self, forKey: .pricing)
        self.scanDurationMs = try c.decodeIfPresent(Int.self, forKey: .scanDurationMs) ?? 0
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(contractVersion, forKey: .contractVersion)
        try c.encode(readAt, forKey: .readAt)
        try c.encode(timeZone, forKey: .timeZone)
        try c.encode(sinceDay, forKey: .sinceDay)
        try c.encode(untilDay, forKey: .untilDay)
        try c.encode(buckets, forKey: .buckets)
        try c.encode(sources, forKey: .sources)
        try c.encode(pricing, forKey: .pricing)
        try c.encode(scanDurationMs, forKey: .scanDurationMs)
    }
}
