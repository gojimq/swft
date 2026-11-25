import Foundation

// MARK: - Server Self-Update Wire Models

public struct ServerSelfUpdateInput: Codable, Sendable, Equatable {
    public let targetVersion: String
    public let targetDatabaseMigration: Int?
    public let stageOnly: Bool?

    public init(
        targetVersion: String,
        targetDatabaseMigration: Int? = nil,
        stageOnly: Bool? = nil
    ) {
        self.targetVersion = targetVersion
        self.targetDatabaseMigration = targetDatabaseMigration
        self.stageOnly = stageOnly
    }
}

public enum ServerSelfUpdateProgressStage: String, Codable, Sendable, Equatable {
    case downloading
    case installing
}

public enum ServerSelfUpdateMethod: String, Codable, Sendable, Equatable {
    case bootService = "boot-service"
    case respawn = "respawn"
    case desktopManaged = "desktop-app"

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "boot-service":
            self = .bootService
        case "respawn":
            self = .respawn
        case "desktop-app", "desktop-managed":
            self = .desktopManaged
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown ServerSelfUpdateMethod: '\(raw)'"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ServerSelfUpdateResult: Codable, Sendable, Equatable {
    public let targetVersion: String
    public let method: ServerSelfUpdateMethod
    public let updateId: String?
    public let desktopUpdateToken: String?

    public init(
        targetVersion: String,
        method: ServerSelfUpdateMethod,
        updateId: String? = nil,
        desktopUpdateToken: String? = nil
    ) {
        self.targetVersion = targetVersion
        self.method = method
        self.updateId = updateId
        self.desktopUpdateToken = desktopUpdateToken
    }
}

public enum ServerSelfUpdateProgressEvent: Codable, Sendable, Equatable {
    case progress(stage: ServerSelfUpdateProgressStage)
    case complete(result: ServerSelfUpdateResult)

    private enum CodingKeys: String, CodingKey {
        case type
        case stage
        case result
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "progress":
            let stage = try container.decode(ServerSelfUpdateProgressStage.self, forKey: .stage)
            self = .progress(stage: stage)
        case "complete":
            let result = try container.decode(ServerSelfUpdateResult.self, forKey: .result)
            self = .complete(result: result)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown ServerSelfUpdateProgressEvent type: '\(type)'"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .progress(let stage):
            try container.encode("progress", forKey: .type)
            try container.encode(stage, forKey: .stage)
        case .complete(let result):
            try container.encode("complete", forKey: .type)
            try container.encode(result, forKey: .result)
        }
    }
}

// MARK: - Semver

public struct SwftSemver: Comparable, Sendable, Equatable, Hashable, CustomStringConvertible, Codable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: [String]
    public let raw: String

    public var description: String { raw }
    public var isPrerelease: Bool { !prerelease.isEmpty }

    public init?( _ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withoutV: String
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            withoutV = String(trimmed.dropFirst())
        } else {
            withoutV = trimmed
        }

        // Strip optional build metadata (+...) after validating it is non-empty if present.
        let mainAndPre: String
        if let plusIndex = withoutV.firstIndex(of: "+") {
            let buildMeta = withoutV[withoutV.index(after: plusIndex)...]
            guard !buildMeta.isEmpty else { return nil }
            mainAndPre = String(withoutV[..<plusIndex])
        } else {
            mainAndPre = withoutV
        }

        let coreString: String
        let prereleaseParts: [String]
        if let dashIndex = mainAndPre.firstIndex(of: "-") {
            coreString = String(mainAndPre[..<dashIndex])
            let preString = String(mainAndPre[mainAndPre.index(after: dashIndex)...])
            guard !preString.isEmpty else { return nil }
            let parts = preString.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            for part in parts {
                guard !part.isEmpty else { return nil }
                guard part.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
                    return nil
                }
                if part.allSatisfy(\.isNumber), part.count > 1, part.hasPrefix("0") {
                    return nil
                }
            }
            prereleaseParts = parts
        } else {
            coreString = mainAndPre
            prereleaseParts = []
        }

        let coreParts = coreString.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard coreParts.count == 3 else { return nil }

        var parsedNumbers: [Int] = []
        parsedNumbers.reserveCapacity(3)
        for part in coreParts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            if part.count > 1 && part.hasPrefix("0") { return nil }
            guard let number = Int(part), number >= 0 else { return nil }
            parsedNumbers.append(number)
        }

        self.major = parsedNumbers[0]
        self.minor = parsedNumbers[1]
        self.patch = parsedNumbers[2]
        self.prerelease = prereleaseParts
        self.raw = withoutV
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawString = try container.decode(String.self)
        guard let parsed = SwftSemver(rawString) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid semver string: '\(rawString)'"
            )
        }
        self = parsed
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }

    public static func == (lhs: SwftSemver, rhs: SwftSemver) -> Bool {
        lhs.major == rhs.major
            && lhs.minor == rhs.minor
            && lhs.patch == rhs.patch
            && lhs.prerelease == rhs.prerelease
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(major)
        hasher.combine(minor)
        hasher.combine(patch)
        hasher.combine(prerelease)
    }

    public static func < (lhs: SwftSemver, rhs: SwftSemver) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        // Per SemVer 2.0: a normal release has higher precedence than a pre-release.
        if lhs.prerelease.isEmpty && rhs.prerelease.isEmpty { return false }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }

        let count = min(lhs.prerelease.count, rhs.prerelease.count)
        for index in 0..<count {
            let left = lhs.prerelease[index]
            let right = rhs.prerelease[index]
            if left == right { continue }
            let leftInt = Int(left)
            let rightInt = Int(right)
            switch (leftInt, rightInt) {
            case (.some(let l), .some(let r)):
                return l < r
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return left < right
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}

// MARK: - GitHub Release Models

public struct SwftReleaseAsset: Codable, Sendable, Equatable {
    public let name: String
    public let downloadURL: URL
    public let apiURL: URL
    public let sizeBytes: Int64

    public init(
        name: String,
        downloadURL: URL,
        apiURL: URL,
        sizeBytes: Int64
    ) {
        self.name = name
        self.downloadURL = downloadURL
        self.apiURL = apiURL
        self.sizeBytes = sizeBytes
    }
}

public struct SwftReleaseInfo: Codable, Sendable, Equatable {
    public let version: String
    public let semver: SwftSemver
    public let tagName: String
    public let name: String
    public let notes: String
    public let htmlURL: URL
    public let publishedAt: Date?
    public let macosAppAsset: SwftReleaseAsset?
    public let serverAssets: [String: SwftReleaseAsset]
    public let checksumsAsset: SwftReleaseAsset?

    public init(
        version: String,
        semver: SwftSemver,
        tagName: String,
        name: String,
        notes: String,
        htmlURL: URL,
        publishedAt: Date?,
        macosAppAsset: SwftReleaseAsset?,
        serverAssets: [String: SwftReleaseAsset],
        checksumsAsset: SwftReleaseAsset?
    ) {
        self.version = version
        self.semver = semver
        self.tagName = tagName
        self.name = name
        self.notes = notes
        self.htmlURL = htmlURL
        self.publishedAt = publishedAt
        self.macosAppAsset = macosAppAsset
        self.serverAssets = serverAssets
        self.checksumsAsset = checksumsAsset
    }

    /// Returns the server archive asset matching an environment's platform (e.g. `darwin-arm64`, `linux-x64`).
    public func serverAsset(for platform: ExecutionEnvironmentPlatform) -> SwftReleaseAsset? {
        let osKey = platform.os == "windows" ? "win32" : platform.os
        return serverAssets["\(osKey)-\(platform.arch)"]
    }
}
