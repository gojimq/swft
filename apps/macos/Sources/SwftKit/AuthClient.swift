import CryptoKit
import Foundation

/// Credential used to establish an authenticated server session.
public enum AuthCredential: Sendable, Equatable {
    /// Static bootstrap token (from `DesktopBackendBootstrap.desktopBootstrapToken` or one-time pairing token).
    case bootstrapToken(String)
    /// Rotating desktop bootstrap secret (`DesktopBackendBootstrap.desktopBootstrapSecret`).
    case rotatingBootstrapSecret(String)
    /// Pre-exchanged bearer access token.
    case bearerToken(String)
}

/// Derives rotating desktop bootstrap tokens matching `packages/shared/src/desktopBootstrapToken.ts`.
public enum DesktopBootstrapToken {
    public static let windowSeconds: TimeInterval = 12 * 60 * 60

    public static func derive(secret: String, now: Date = Date()) -> String {
        let windowIndex = Int64(floor(now.timeIntervalSince1970 / windowSeconds))
        let key = SymmetricKey(data: Data(secret.utf8))
        let message = Data("t3-desktop-bootstrap:\(windowIndex)".utf8)
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }
}

/// HTTP client for environment discovery, OAuth token exchange, and WebSocket ticket minting.
public struct AuthClient: Sendable {
    public static let supportedOrchestrationProtocolVersion = 2

    private static let tokenExchangeGrantType = "urn:ietf:params:oauth:grant-type:token-exchange"
    private static let bootstrapTokenType = "urn:t3:params:oauth:token-type:environment-bootstrap"
    private static let accessTokenType = "urn:ietf:params:oauth:token-type:access_token"

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func discoverEnvironment(baseURL: URL) async throws -> ExecutionEnvironmentDescriptor {
        let url = endpointURL(baseURL: baseURL, path: "/.well-known/t3/environment")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        let descriptor = try SwftJSON.makeDecoder().decode(ExecutionEnvironmentDescriptor.self, from: data)
        guard descriptor.orchestrationProtocolVersion == Self.supportedOrchestrationProtocolVersion else {
            throw RPCError.incompatibleProtocol(serverVersion: descriptor.orchestrationProtocolVersion)
        }
        return descriptor
    }

    public func exchangeBootstrapToken(
        baseURL: URL,
        bootstrapToken: String,
        clientLabel: String = "Swft",
        clientIdentity: ClientIdentity = .current
    ) async throws -> AuthAccessTokenResult {
        let url = endpointURL(baseURL: baseURL, path: "/oauth/token")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let formItems: [(String, String)] = [
            ("grant_type", Self.tokenExchangeGrantType),
            ("subject_token", bootstrapToken),
            ("subject_token_type", Self.bootstrapTokenType),
            ("requested_token_type", Self.accessTokenType),
            ("client_label", clientLabel),
            ("client_device_type", clientIdentity.deviceType),
            ("client_os", clientIdentity.os),
        ]
        request.httpBody = Data(formURLEncoded(formItems).utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RPCError.protocolError("Non-HTTP response from /oauth/token")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RPCError.authenticationFailed(body.isEmpty ? "HTTP \(http.statusCode)" : body)
        }
        try validateHTTPResponse(response, data: data)
        return try SwftJSON.makeDecoder().decode(AuthAccessTokenResult.self, from: data)
    }

    public func mintWebSocketTicket(
        baseURL: URL,
        accessToken: String
    ) async throws -> AuthWebSocketTicketResult {
        try await mintTicket(baseURL: baseURL, accessToken: accessToken, use: "rpc")
    }

    public func mintMediaTicket(
        baseURL: URL,
        accessToken: String
    ) async throws -> AuthWebSocketTicketResult {
        try await mintTicket(baseURL: baseURL, accessToken: accessToken, use: "media")
    }

    private func mintTicket(
        baseURL: URL,
        accessToken: String,
        use: String
    ) async throws -> AuthWebSocketTicketResult {
        let primaryURL = endpointURL(baseURL: baseURL, path: "/api/auth/websocket-ticket/\(use)")
        let (data, response) = try await postWebSocketTicket(url: primaryURL, accessToken: accessToken)

        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            let legacyURL = endpointURL(baseURL: baseURL, path: "/api/auth/websocket-ticket")
            let (legacyData, legacyResponse) = try await postWebSocketTicket(
                url: legacyURL,
                accessToken: accessToken
            )
            return try decodeTicketResponse(data: legacyData, response: legacyResponse)
        }

        return try decodeTicketResponse(data: data, response: response)
    }

    public func resolveAccessToken(
        baseURL: URL,
        credential: AuthCredential,
        clientLabel: String = "Swft",
        clientIdentity: ClientIdentity = .current
    ) async throws -> String {
        switch credential {
        case .bearerToken(let token):
            return token
        case .bootstrapToken(let token):
            let result = try await exchangeBootstrapToken(
                baseURL: baseURL,
                bootstrapToken: token,
                clientLabel: clientLabel,
                clientIdentity: clientIdentity
            )
            return result.accessToken
        case .rotatingBootstrapSecret(let secret):
            let derived = DesktopBootstrapToken.derive(secret: secret)
            let result = try await exchangeBootstrapToken(
                baseURL: baseURL,
                bootstrapToken: derived,
                clientLabel: clientLabel,
                clientIdentity: clientIdentity
            )
            return result.accessToken
        }
    }

    public func webSocketURL(
        httpBaseURL: URL,
        ticket: String,
        clientIdentity: ClientIdentity = .current
    ) throws -> URL {
        guard var components = URLComponents(url: httpBaseURL, resolvingAgainstBaseURL: false) else {
            throw RPCError.protocolError("Invalid base URL: \(httpBaseURL.absoluteString)")
        }
        switch components.scheme?.lowercased() {
        case "https", "wss":
            components.scheme = "wss"
        case "http", "ws":
            components.scheme = "ws"
        default:
            throw RPCError.protocolError("Unsupported URL scheme: \(components.scheme ?? "nil")")
        }

        let trimmedBasePath = components.path.hasSuffix("/")
            ? String(components.path.dropLast())
            : components.path
        components.path = trimmedBasePath + "/ws"
        components.queryItems = [
            URLQueryItem(name: "orchestrationProtocol", value: "\(Self.supportedOrchestrationProtocolVersion)"),
            URLQueryItem(name: "wsTicket", value: ticket),
            URLQueryItem(name: "frameParts", value: "1"),
            URLQueryItem(name: "clientSurface", value: clientIdentity.surface),
            URLQueryItem(name: "clientDeviceType", value: clientIdentity.deviceType),
            URLQueryItem(name: "clientOs", value: clientIdentity.os),
            URLQueryItem(name: "connectionMethod", value: "direct"),
        ]
        guard let url = components.url else {
            throw RPCError.protocolError("Failed to construct WebSocket URL")
        }
        return url
    }

    // MARK: - Helpers

    private func postWebSocketTicket(url: URL, accessToken: String) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await session.data(for: request)
    }

    private func decodeTicketResponse(data: Data, response: URLResponse) throws -> AuthWebSocketTicketResult {
        guard let http = response as? HTTPURLResponse else {
            throw RPCError.protocolError("Non-HTTP response from websocket ticket endpoint")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RPCError.authenticationFailed(body.isEmpty ? "HTTP \(http.statusCode)" : body)
        }
        try validateHTTPResponse(response, data: data)
        return try SwftJSON.makeDecoder().decode(AuthWebSocketTicketResult.self, from: data)
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw RPCError.protocolError("Expected HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RPCError.httpError(statusCode: http.statusCode, body: body)
        }
    }

    private func endpointURL(baseURL: URL, path: String) -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL.appendingPathComponent(path)
        }
        let trimmedBase = components.path.hasSuffix("/")
            ? String(components.path.dropLast())
            : components.path
        components.path = trimmedBase + path
        components.query = nil
        components.fragment = nil
        return components.url ?? baseURL.appendingPathComponent(path)
    }

    private func formURLEncoded(_ items: [(String, String)]) -> String {
        items.map { key, value in
            "\(percentEncodeFormComponent(key))=\(percentEncodeFormComponent(value))"
        }.joined(separator: "&")
    }

    private func percentEncodeFormComponent(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
