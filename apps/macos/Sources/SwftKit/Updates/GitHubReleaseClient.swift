import Foundation

// MARK: - Token Persistence

/// Persists the optional GitHub token used to check and download releases from private repositories.
public struct UpdateTokenStore: Sendable {
    public static let account = KeychainCredentialStore.githubReleaseTokenAccount

    private let store: any CredentialStore

    public init(store: any CredentialStore = KeychainCredentialStore()) {
        self.store = store
    }

    public func readToken() throws -> String? {
        guard let raw = try store.read(account: Self.account) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func saveToken(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try store.delete(account: Self.account)
        } else {
            try store.write(trimmed, account: Self.account)
        }
    }

    public func deleteToken() throws {
        try store.delete(account: Self.account)
    }

    public static func readToken() throws -> String? {
        try UpdateTokenStore().readToken()
    }

    public static func saveToken(_ token: String) throws {
        try UpdateTokenStore().saveToken(token)
    }

    public static func deleteToken() throws {
        try UpdateTokenStore().deleteToken()
    }
}

// MARK: - Errors

public enum GitHubReleaseClientError: Error, Sendable, Equatable, LocalizedError {
    case invalidRepository(String)
    case noReleasesPublished
    case authenticationRequired(repository: String)
    case rateLimited(resetAt: Date?)
    case httpError(statusCode: Int, message: String?)
    case invalidResponse(String)
    case missingAsset(String)
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRepository(let repo):
            return "Invalid GitHub repository identifier: '\(repo)'."
        case .noReleasesPublished:
            return "No published GitHub Releases were found."
        case .authenticationRequired(let repo):
            return "Authentication required to access releases for \(repo). Add a GitHub token in Settings → Updates."
        case .rateLimited(let resetAt):
            if let resetAt {
                let formatter = RelativeDateTimeFormatter()
                let rel = formatter.localizedString(for: resetAt, relativeTo: Date())
                return "GitHub API rate limit exceeded. Try again \(rel) or add a GitHub token."
            }
            return "GitHub API rate limit exceeded. Add a GitHub token in Settings → Updates or try again later."
        case .httpError(let statusCode, let message):
            if let message, !message.isEmpty {
                return "GitHub request failed (HTTP \(statusCode)): \(message)"
            }
            return "GitHub request failed (HTTP \(statusCode))."
        case .invalidResponse(let detail):
            return "Unexpected response from GitHub Releases: \(detail)"
        case .missingAsset(let name):
            return "Release is missing required asset '\(name)'."
        case .networkError(let detail):
            return "Network error while contacting GitHub: \(detail)"
        }
    }
}

// MARK: - Redirect Delegate

private final class ManualRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}

// MARK: - Client

/// Fetches release metadata, checksums, and release assets from GitHub Releases.
/// Supports both unauthenticated public repos and token-authenticated private repos
/// (using GitHub's two-step API redirect without leaking `Authorization` to S3).
public struct GitHubReleaseClient: Sendable {
    public static let defaultRepository = "gojimq/swft"
    public static let defaultAPIBaseURL = URL(string: "https://api.github.com")!

    public typealias DataTransport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    public typealias DownloadTransport = @Sendable (
        URLRequest,
        URL,
        @escaping @Sendable (Double?) -> Void
    ) async throws -> HTTPURLResponse

    public let repository: String
    public let apiBaseURL: URL

    private let tokenStore: UpdateTokenStore
    private let environment: [String: String]
    private let dataTransport: DataTransport
    private let redirectInspectTransport: DataTransport
    private let downloadTransport: DownloadTransport

    public init(
        repository: String = GitHubReleaseClient.defaultRepository,
        apiBaseURL: URL = GitHubReleaseClient.defaultAPIBaseURL,
        session: URLSession = .shared,
        tokenStore: UpdateTokenStore = UpdateTokenStore(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.repository = repository
        self.apiBaseURL = apiBaseURL
        self.tokenStore = tokenStore
        self.environment = environment
        self.dataTransport = Self.makeLiveDataTransport(session: session)
        self.redirectInspectTransport = Self.makeLiveManualRedirectTransport(session: session)
        self.downloadTransport = Self.makeLiveDownloadTransport(session: session)
    }

    /// Designated initializer for deterministic offline unit tests with custom transports.
    public init(
        repository: String = GitHubReleaseClient.defaultRepository,
        apiBaseURL: URL = GitHubReleaseClient.defaultAPIBaseURL,
        tokenStore: UpdateTokenStore = UpdateTokenStore(store: InMemoryCredentialStore()),
        environment: [String: String] = [:],
        dataTransport: @escaping DataTransport,
        redirectInspectTransport: DataTransport? = nil,
        downloadTransport: @escaping DownloadTransport
    ) {
        self.repository = repository
        self.apiBaseURL = apiBaseURL
        self.tokenStore = tokenStore
        self.environment = environment
        self.dataTransport = dataTransport
        self.redirectInspectTransport = redirectInspectTransport ?? dataTransport
        self.downloadTransport = downloadTransport
    }

    // MARK: - Token Resolution

    public func resolveToken(explicit: String? = nil) -> String? {
        if let explicit = explicit?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
            return explicit
        }
        if let stored = try? tokenStore.readToken(), !stored.isEmpty {
            return stored
        }
        if let swftEnv = environment["SWFT_GITHUB_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !swftEnv.isEmpty
        {
            return swftEnv
        }
        if let ghEnv = environment["GITHUB_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !ghEnv.isEmpty
        {
            return ghEnv
        }
        return nil
    }

    // MARK: - Public API

    public func fetchLatestRelease(token: String? = nil) async throws -> SwftReleaseInfo {
        let (owner, repo) = try parseRepository()
        let endpoint = apiBaseURL
            .appendingPathComponent("repos")
            .appendingPathComponent(owner)
            .appendingPathComponent(repo)
            .appendingPathComponent("releases")
            .appendingPathComponent("latest")

        let resolvedToken = resolveToken(explicit: token)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Swft-Updater", forHTTPHeaderField: "User-Agent")
        if let resolvedToken {
            request.setValue("Bearer \(resolvedToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await performData(request)
        try validateMetadataResponse(response, data: data, hasToken: resolvedToken != nil)

        let payload: GitHubReleasePayload
        do {
            payload = try SwftJSON.makeDecoder().decode(GitHubReleasePayload.self, from: data)
        } catch {
            throw GitHubReleaseClientError.invalidResponse(
                "Could not decode release JSON: \(error.localizedDescription)"
            )
        }

        return try Self.mapReleasePayload(payload)
    }

    public func fetchChecksums(
        for release: SwftReleaseInfo,
        token: String? = nil
    ) async throws -> [String: String] {
        guard let asset = release.checksumsAsset else {
            throw GitHubReleaseClientError.missingAsset("SHA256SUMS")
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("swft-checksums-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await downloadAsset(asset, to: tempURL, token: token) { _ in }
        let text: String
        do {
            text = try String(contentsOf: tempURL, encoding: .utf8)
        } catch {
            throw GitHubReleaseClientError.invalidResponse("SHA256SUMS is not valid UTF-8.")
        }
        return Self.parseChecksums(text)
    }

    public func downloadAsset(
        _ asset: SwftReleaseAsset,
        to destinationURL: URL,
        token: String? = nil,
        onProgress: @escaping @Sendable (Double?) -> Void = { _ in }
    ) async throws {
        let parentDir = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        let resolvedToken = resolveToken(explicit: token)
        if let resolvedToken {
            try await downloadPrivateAsset(
                asset,
                to: destinationURL,
                token: resolvedToken,
                onProgress: onProgress
            )
        } else {
            var request = URLRequest(url: asset.downloadURL)
            request.httpMethod = "GET"
            request.setValue("Swft-Updater", forHTTPHeaderField: "User-Agent")
            let response = try await performDownload(request, to: destinationURL, onProgress: onProgress)
            try validateAssetResponse(response, hasToken: false)
        }
    }

    // MARK: - Parsing Helpers

    /// Parses standard `sha256sum` / `shasum -a 256` output into `[filename: lowercaseHexDigest]`.
    public static func parseChecksums(_ text: String) -> [String: String] {
        var map: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.count > 65 else { continue }
            let digestPart = String(line.prefix(64))
            guard digestPart.allSatisfy(\.isHexDigit) else { continue }
            let rest = line.dropFirst(64)
            guard let firstChar = rest.first, firstChar.isWhitespace else { continue }
            var fileName = rest.trimmingCharacters(in: .whitespaces)
            if fileName.hasPrefix("*") {
                fileName.removeFirst()
            }
            guard !fileName.isEmpty else { continue }
            map[fileName] = digestPart.lowercased()
        }
        return map
    }

    // MARK: - Private Implementation

    private func downloadPrivateAsset(
        _ asset: SwftReleaseAsset,
        to destinationURL: URL,
        token: String,
        onProgress: @escaping @Sendable (Double?) -> Void
    ) async throws {
        // Step 1: Request GitHub asset API endpoint with Authorization and manual redirect handling.
        var step1 = URLRequest(url: asset.apiURL)
        step1.httpMethod = "GET"
        step1.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        step1.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        step1.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        step1.setValue("Swft-Updater", forHTTPHeaderField: "User-Agent")

        let (step1Data, step1Response) = try await performRedirectInspect(step1)

        if (300..<400).contains(step1Response.statusCode) {
            guard let location = step1Response.value(forHTTPHeaderField: "Location"),
                  let signedURL = URL(string: location, relativeTo: asset.apiURL)?.absoluteURL
            else {
                throw GitHubReleaseClientError.invalidResponse(
                    "GitHub asset redirect (\(step1Response.statusCode)) missing Location header."
                )
            }
            // Step 2: Stream bytes from the signed S3/CDN URL WITHOUT the GitHub Authorization header.
            var step2 = URLRequest(url: signedURL)
            step2.httpMethod = "GET"
            step2.setValue("Swft-Updater", forHTTPHeaderField: "User-Agent")
            let step2Response = try await performDownload(step2, to: destinationURL, onProgress: onProgress)
            try validateAssetResponse(step2Response, hasToken: true)
            return
        }

        if (200..<300).contains(step1Response.statusCode) {
            try step1Data.write(to: destinationURL, options: .atomic)
            onProgress(1.0)
            return
        }

        try validateAssetResponse(step1Response, hasToken: true)
    }

    private func parseRepository() throws -> (String, String) {
        let parts = repository
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            throw GitHubReleaseClientError.invalidRepository(repository)
        }
        return (parts[0], parts[1])
    }

    private func performData(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await dataTransport(request)
        } catch let error as GitHubReleaseClientError {
            throw error
        } catch {
            throw GitHubReleaseClientError.networkError(error.localizedDescription)
        }
    }

    private func performRedirectInspect(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await redirectInspectTransport(request)
        } catch let error as GitHubReleaseClientError {
            throw error
        } catch {
            throw GitHubReleaseClientError.networkError(error.localizedDescription)
        }
    }

    private func performDownload(
        _ request: URLRequest,
        to destinationURL: URL,
        onProgress: @escaping @Sendable (Double?) -> Void
    ) async throws -> HTTPURLResponse {
        do {
            return try await downloadTransport(request, destinationURL, onProgress)
        } catch let error as GitHubReleaseClientError {
            throw error
        } catch {
            throw GitHubReleaseClientError.networkError(error.localizedDescription)
        }
    }

    private func validateMetadataResponse(
        _ response: HTTPURLResponse,
        data: Data,
        hasToken: Bool
    ) throws {
        if (200..<300).contains(response.statusCode) {
            return
        }
        let message = Self.extractErrorMessage(from: data)
        if response.statusCode == 401 {
            throw GitHubReleaseClientError.authenticationRequired(repository: repository)
        }
        if response.statusCode == 403 || response.statusCode == 429 {
            let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining")
            let isRateLimit = response.statusCode == 429
                || remaining == "0"
                || (message?.localizedCaseInsensitiveContains("rate limit") == true)
            if isRateLimit {
                let resetAt = response.value(forHTTPHeaderField: "X-RateLimit-Reset")
                    .flatMap(TimeInterval.init)
                    .map(Date.init(timeIntervalSince1970:))
                throw GitHubReleaseClientError.rateLimited(resetAt: resetAt)
            }
            if !hasToken {
                throw GitHubReleaseClientError.authenticationRequired(repository: repository)
            }
        }
        if response.statusCode == 404 {
            if !hasToken {
                throw GitHubReleaseClientError.authenticationRequired(repository: repository)
            }
            throw GitHubReleaseClientError.noReleasesPublished
        }
        throw GitHubReleaseClientError.httpError(statusCode: response.statusCode, message: message)
    }

    private func validateAssetResponse(_ response: HTTPURLResponse, hasToken: Bool) throws {
        if (200..<300).contains(response.statusCode) {
            return
        }
        if response.statusCode == 401 || (response.statusCode == 404 && !hasToken) {
            throw GitHubReleaseClientError.authenticationRequired(repository: repository)
        }
        if response.statusCode == 429 {
            throw GitHubReleaseClientError.rateLimited(resetAt: nil)
        }
        throw GitHubReleaseClientError.httpError(statusCode: response.statusCode, message: nil)
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["message"] as? String
        else { return nil }
        return message
    }

    private static func mapReleasePayload(_ payload: GitHubReleasePayload) throws -> SwftReleaseInfo {
        let normalizedVersion = payload.tagName.hasPrefix("v") || payload.tagName.hasPrefix("V")
            ? String(payload.tagName.dropFirst())
            : payload.tagName

        guard let semver = SwftSemver(normalizedVersion) else {
            throw GitHubReleaseClientError.invalidResponse(
                "Release tag '\(payload.tagName)' is not a valid semver version."
            )
        }
        guard let htmlURL = URL(string: payload.htmlUrl) else {
            throw GitHubReleaseClientError.invalidResponse(
                "Release html_url '\(payload.htmlUrl)' is not a valid URL."
            )
        }

        let assets: [SwftReleaseAsset] = payload.assets.compactMap { raw in
            guard let downloadURL = URL(string: raw.browserDownloadUrl),
                  let apiURL = URL(string: raw.url)
            else { return nil }
            return SwftReleaseAsset(
                name: raw.name,
                downloadURL: downloadURL,
                apiURL: apiURL,
                sizeBytes: raw.size
            )
        }

        let expectedAppName = "Swft-\(normalizedVersion)-darwin-arm64.zip"
        let macosAppAsset =
            assets.first { $0.name == expectedAppName }
            ?? assets.first { $0.name.hasPrefix("Swft-") && $0.name.hasSuffix("-darwin-arm64.zip") }

        let checksumsAsset = assets.first { $0.name == "SHA256SUMS" }

        var serverAssets: [String: SwftReleaseAsset] = [:]
        let serverPrefix = "t3-\(normalizedVersion)-"
        for asset in assets {
            guard asset.name.hasPrefix(serverPrefix) else { continue }
            let remainder = String(asset.name.dropFirst(serverPrefix.count))
            if remainder.hasSuffix(".tar.gz") {
                let platformKey = String(remainder.dropLast(".tar.gz".count))
                if !platformKey.isEmpty {
                    serverAssets[platformKey] = asset
                }
            } else if remainder.hasSuffix(".zip") {
                let platformKey = String(remainder.dropLast(".zip".count))
                if !platformKey.isEmpty {
                    serverAssets[platformKey] = asset
                }
            }
        }

        return SwftReleaseInfo(
            version: normalizedVersion,
            semver: semver,
            tagName: payload.tagName,
            name: payload.name?.isEmpty == false ? payload.name! : payload.tagName,
            notes: payload.body ?? "",
            htmlURL: htmlURL,
            publishedAt: payload.publishedAt,
            macosAppAsset: macosAppAsset,
            serverAssets: serverAssets,
            checksumsAsset: checksumsAsset
        )
    }

    // MARK: - Live URLSession Transports

    private static func makeLiveDataTransport(session: URLSession) -> DataTransport {
        { request in
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw GitHubReleaseClientError.invalidResponse("Non-HTTP response received.")
            }
            return (data, http)
        }
    }

    private static func makeLiveManualRedirectTransport(session: URLSession) -> DataTransport {
        { request in
            let delegate = ManualRedirectDelegate()
            let (data, response) = try await session.data(for: request, delegate: delegate)
            guard let http = response as? HTTPURLResponse else {
                throw GitHubReleaseClientError.invalidResponse("Non-HTTP response received.")
            }
            return (data, http)
        }
    }

    private static func makeLiveDownloadTransport(session: URLSession) -> DownloadTransport {
        { request, destinationURL, onProgress in
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw GitHubReleaseClientError.invalidResponse("Non-HTTP response received.")
            }
            guard (200..<300).contains(http.statusCode) else {
                return http
            }

            let expectedBytes = http.expectedContentLength > 0 ? http.expectedContentLength : nil
            onProgress(expectedBytes != nil ? 0.0 : nil)

            let fm = FileManager.default
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            fm.createFile(atPath: destinationURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: destinationURL)
            defer { try? handle.close() }

            var buffer = Data()
            buffer.reserveCapacity(65_536)
            var received: Int64 = 0
            var lastReportedBytes: Int64 = 0

            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= 65_536 {
                    try handle.write(contentsOf: buffer)
                    received += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    if let expectedBytes, received - lastReportedBytes >= 65_536 {
                        lastReportedBytes = received
                        onProgress(min(1.0, Double(received) / Double(expectedBytes)))
                    }
                }
            }
            if !buffer.isEmpty {
                try handle.write(contentsOf: buffer)
                received += Int64(buffer.count)
            }
            onProgress(1.0)
            return http
        }
    }
}

// MARK: - GitHub API Wire DTOs

private struct GitHubReleasePayload: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlUrl: String
    let publishedAt: Date?
    let assets: [GitHubReleaseAssetPayload]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case publishedAt = "published_at"
        case assets
    }
}

private struct GitHubReleaseAssetPayload: Decodable {
    let name: String
    let url: String
    let browserDownloadUrl: String
    let size: Int64

    private enum CodingKeys: String, CodingKey {
        case name
        case url
        case browserDownloadUrl = "browser_download_url"
        case size
    }
}
