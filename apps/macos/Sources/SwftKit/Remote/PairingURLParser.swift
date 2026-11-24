import Foundation

/// Parsed remote pairing destination normalized to HTTP/WS origin plus one-time pairing credential.
public struct ParsedPairingTarget: Sendable, Equatable {
    public let httpBaseURL: URL
    public let wsBaseURL: URL
    public let credential: String
    public let suggestedLabel: String?

    public init(
        httpBaseURL: URL,
        wsBaseURL: URL,
        credential: String,
        suggestedLabel: String? = nil
    ) {
        self.httpBaseURL = httpBaseURL
        self.wsBaseURL = wsBaseURL
        self.credential = credential
        self.suggestedLabel = suggestedLabel
    }

    public var isHTTPS: Bool {
        httpBaseURL.scheme?.lowercased() == "https"
    }
}

public enum PairingParseError: Error, Sendable, Equatable, LocalizedError {
    case emptyAddress
    case missingToken
    case invalidURL(String)
    case unsupportedScheme(String)

    public var errorDescription: String? {
        switch self {
        case .emptyAddress:
            return "Paste a pairing link or enter a server address."
        case .missingToken:
            return "Enter a pairing token, or paste the full pairing link."
        case .invalidURL(let raw):
            return "That server address is not a valid URL: \(raw)"
        case .unsupportedScheme(let scheme):
            return "Unsupported URL scheme '\(scheme)'. Use http:// or https://."
        }
    }
}

/// Parses and formats T3/Studio pairing URLs, hosted pairing links, and `t3code://pair` app links.
/// Mirrors `packages/shared/src/remote.ts` and Studio's `live/pairing.ts`.
public enum PairingURLParser {
    private static let supportedSchemes: Set<String> = ["http", "https", "ws", "wss"]

    /// Accepts:
    /// - Direct pairing link: `http://127.0.0.1:3773/pair#token=...` or `?token=...`
    /// - Hosted pairing link: `https://app.t3.codes/pair?host=https://mac.example.com&label=Mac#token=...`
    /// - App deep link: `t3code://pair?pairingUrl=...` (or `t3code-<channel>://pair?...` / `swft://pair?...`)
    /// - Separate server host/URL + pairing token
    public static func parse(address: String, token: String? = nil) throws -> ParsedPairingTarget {
        let rawAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawToken = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !rawAddress.isEmpty else {
            throw PairingParseError.emptyAddress
        }

        let candidate = readPairingAppLink(rawAddress) ?? rawAddress
        let parsedURL = tryParseURL(candidate)

        if let parsedURL {
            if let hosted = readHostedPairingRequest(parsedURL) {
                let backendURL = try normalizeBackendBaseURL(hosted.host)
                return ParsedPairingTarget(
                    httpBaseURL: toHTTPBaseURL(backendURL),
                    wsBaseURL: toWSBaseURL(backendURL),
                    credential: hosted.token,
                    suggestedLabel: hosted.label.isEmpty ? nil : hosted.label
                )
            }

            if let embeddedToken = pairingToken(from: parsedURL) {
                try validateSupportedScheme(parsedURL)
                return ParsedPairingTarget(
                    httpBaseURL: toHTTPBaseURL(parsedURL),
                    wsBaseURL: toWSBaseURL(parsedURL),
                    credential: embeddedToken,
                    suggestedLabel: nil
                )
            }
        }

        guard !rawToken.isEmpty else {
            throw PairingParseError.missingToken
        }

        let normalizedBase = try normalizeBackendBaseURL(candidate)
        return ParsedPairingTarget(
            httpBaseURL: toHTTPBaseURL(normalizedBase),
            wsBaseURL: toWSBaseURL(normalizedBase),
            credential: rawToken,
            suggestedLabel: nil
        )
    }

    /// Builds a canonical `<origin>/pair#token=<encoded>` pairing link.
    public static func buildPairingInviteURL(
        baseURL: String,
        token: String
    ) -> (origin: String, pairingURL: String)? {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty, !trimmedToken.isEmpty else { return nil }

        guard let parsed = tryParseURL(trimmedBase),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = parsed.host(),
              !host.isEmpty
        else { return nil }

        let origin = formatOrigin(scheme: scheme, host: host, port: parsed.port)
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encodedToken = trimmedToken.addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmedToken
        return (origin, "\(origin)/pair#token=\(encodedToken)")
    }

    /// Normalizes a user-supplied HTTPS public tunnel URL to its origin (`https://host[:port]`).
    /// Rejects non-HTTPS schemes and malformed URLs.
    public static func normalizeHTTPSPublicURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = hasExplicitScheme(trimmed) ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: withScheme),
              components.scheme?.lowercased() == "https",
              let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty
        else { return nil }
        return formatOrigin(scheme: "https", host: host.lowercased(), port: components.port)
    }

    public static func isLoopbackOrigin(_ rawOrigin: String) -> Bool {
        guard let url = tryParseURL(rawOrigin), let host = url.host() else { return false }
        return isLoopbackHost(host)
    }

    public static func isLoopbackHost(_ raw: String) -> Bool {
        let hostPart = raw.split(maxSplits: 1, whereSeparator: { $0 == "/" || $0 == "?" || $0 == "#" }).first.map(String.init) ?? ""
        if hostPart.hasPrefix("[") {
            guard let endIndex = hostPart.firstIndex(of: "]") else { return false }
            let inside = hostPart[hostPart.index(after: hostPart.startIndex)..<endIndex].lowercased()
            return inside == "::1"
        }
        let hostname = hostPart.split(separator: ":", maxSplits: 1).first?.lowercased() ?? ""
        return hostname == "localhost"
            || hostname == "127.0.0.1"
            || hostname == "0.0.0.0"
            || hostname == "::1"
            || hostname.hasSuffix(".localhost")
    }

    /// Unwraps `t3code://pair?pairingUrl=...`, `t3code-<channel>://pair?pairingUrl=...`, or `swft://pair?pairingUrl=...`.
    public static func readPairingAppLink(_ value: String) -> String? {
        guard let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(),
              isAppLinkScheme(scheme),
              components.host?.lowercased() == "pair",
              components.path.isEmpty || components.path == "/"
        else { return nil }

        let target = components.queryItems?
            .first(where: { $0.name == "pairingUrl" })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return target?.isEmpty == false ? target : nil
    }

    // MARK: - Helpers

    private struct HostedPairingRequest {
        let host: String
        let token: String
        let label: String
    }

    private static func readHostedPairingRequest(_ url: URL) -> HostedPairingRequest? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let host = components.queryItems?
            .first(where: { $0.name == "host" })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let token = pairingToken(from: url) ?? ""
        let label = components.queryItems?
            .first(where: { $0.name == "label" })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !host.isEmpty, !token.isEmpty else { return nil }
        return HostedPairingRequest(host: host, token: token, label: label)
    }

    private static func pairingToken(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        if let fragment = components.fragment, !fragment.isEmpty {
            let trimmedFragment = fragment.hasPrefix("#") ? String(fragment.dropFirst()) : fragment
            if let fragmentToken = parseFormQueryParameter(named: "token", in: trimmedFragment) {
                return fragmentToken
            }
        }
        if let queryToken = components.queryItems?
            .first(where: { $0.name == "token" })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !queryToken.isEmpty
        {
            return queryToken
        }
        return nil
    }

    private static func parseFormQueryParameter(named name: String, in raw: String) -> String? {
        var fake = URLComponents()
        fake.percentEncodedQuery = raw
        if let match = fake.queryItems?.first(where: { $0.name == name })?.value {
            let trimmed = match.replacingOccurrences(of: "+", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        for pair in raw.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, String(parts[0]) == name else { continue }
            let decoded = String(parts[1])
                .replacingOccurrences(of: "+", with: " ")
                .removingPercentEncoding?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let decoded, !decoded.isEmpty { return decoded }
        }
        return nil
    }

    private static func isAppLinkScheme(_ scheme: String) -> Bool {
        if scheme == "t3code" || scheme == "swft" {
            return true
        }
        if scheme.hasPrefix("t3code-") {
            let suffix = scheme.dropFirst("t3code-".count)
            return !suffix.isEmpty && suffix.allSatisfy { $0.isASCII && $0.isLetter }
        }
        return false
    }

    private static func hasExplicitScheme(_ raw: String) -> Bool {
        guard let range = raw.range(of: "://") else { return false }
        let scheme = raw[..<range.lowerBound]
        guard let first = scheme.first, first.isASCII, first.isLetter else { return false }
        return scheme.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == ".") }
    }

    private static func addDefaultScheme(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasPrefix("/") {
            trimmed.removeFirst()
        }
        if hasExplicitScheme(trimmed) {
            return trimmed
        }
        let scheme = isLoopbackHost(trimmed) ? "http" : "https"
        return "\(scheme)://\(trimmed)"
    }

    private static func tryParseURL(_ raw: String) -> URL? {
        let withScheme = addDefaultScheme(raw)
        guard let components = URLComponents(string: withScheme),
              let host = components.host,
              !host.isEmpty
        else { return nil }
        return components.url
    }

    private static func normalizeBackendBaseURL(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PairingParseError.emptyAddress
        }
        let withScheme = addDefaultScheme(trimmed)
        guard var components = URLComponents(string: withScheme),
              let host = components.host,
              !host.isEmpty
        else {
            throw PairingParseError.invalidURL(trimmed)
        }
        let scheme = components.scheme?.lowercased() ?? ""
        guard supportedSchemes.contains(scheme) else {
            throw PairingParseError.unsupportedScheme(scheme)
        }
        components.scheme = scheme
        components.path = ""
        components.query = nil
        components.fragment = nil
        guard let url = components.url else {
            throw PairingParseError.invalidURL(trimmed)
        }
        return url
    }

    private static func validateSupportedScheme(_ url: URL) throws {
        let scheme = url.scheme?.lowercased() ?? ""
        guard supportedSchemes.contains(scheme) else {
            throw PairingParseError.unsupportedScheme(scheme)
        }
    }

    private static func toHTTPBaseURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        switch components.scheme?.lowercased() {
        case "ws": components.scheme = "http"
        case "wss": components.scheme = "https"
        default: components.scheme = components.scheme?.lowercased()
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url ?? url
    }

    private static func toWSBaseURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        switch components.scheme?.lowercased() {
        case "http": components.scheme = "ws"
        case "https": components.scheme = "wss"
        default: components.scheme = components.scheme?.lowercased()
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url ?? url
    }

    private static func formatOrigin(scheme: String, host: String, port: Int?) -> String {
        let formattedHost = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        if let port {
            let isDefault = (scheme == "http" && port == 80) || (scheme == "https" && port == 443)
            if !isDefault {
                return "\(scheme)://\(formattedHost):\(port)"
            }
        }
        return "\(scheme)://\(formattedHost)"
    }
}
