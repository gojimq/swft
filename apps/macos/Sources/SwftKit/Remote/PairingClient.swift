import Foundation

/// Response from `POST /api/auth/pairing-token`.
public struct AuthPairingCredentialResult: Codable, Sendable, Equatable {
    public let id: String
    public let credential: String
    public let label: String?
    public let expiresAt: Date

    public init(id: String, credential: String, label: String? = nil, expiresAt: Date) {
        self.id = id
        self.credential = credential
        self.label = label
        self.expiresAt = expiresAt
    }
}

/// Request payload for `POST /api/auth/pairing-token`.
public struct AuthCreatePairingCredentialInput: Encodable, Sendable, Equatable {
    public let label: String?
    public let scopes: [String]?

    public init(label: String? = nil, scopes: [String]? = nil) {
        self.label = label
        self.scopes = scopes
    }
}

/// Verified and exchanged remote environment session ready to persist and connect.
public struct PairedRemoteSession: Sendable, Equatable {
    public let descriptor: ExecutionEnvironmentDescriptor
    public let httpBaseURL: URL
    public let accessToken: String
    public let scope: String
    public let expiresIn: Double
    public let suggestedLabel: String?

    public init(
        descriptor: ExecutionEnvironmentDescriptor,
        httpBaseURL: URL,
        accessToken: String,
        scope: String,
        expiresIn: Double,
        suggestedLabel: String? = nil
    ) {
        self.descriptor = descriptor
        self.httpBaseURL = httpBaseURL
        self.accessToken = accessToken
        self.scope = scope
        self.expiresIn = expiresIn
        self.suggestedLabel = suggestedLabel
    }
}

public enum PairingError: Error, Sendable, Equatable, LocalizedError {
    case environmentMismatch(expected: String, actual: String, actualLabel: String)
    case httpsDowngradeNotAllowed(label: String)

    public var errorDescription: String? {
        switch self {
        case .environmentMismatch(_, _, let actualLabel):
            return "That pairing link belongs to \"\(actualLabel)\", not the server you are re-pairing."
        case .httpsDowngradeNotAllowed(let label):
            return "\"\(label)\" was paired over HTTPS and cannot be downgraded to plain HTTP."
        }
    }
}

/// Performs remote pairing discovery + token exchange and host-side pairing token issuance,
/// reusing `AuthClient` without altering its public API.
public struct PairingClient: Sendable {
    private let authClient: AuthClient
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
        self.authClient = AuthClient(session: session)
    }

    /// Discovers the remote environment, enforces protocol v2 and optional identity pinning,
    /// and exchanges the one-time pairing credential for a bearer access token.
    public func pairRemote(
        target: ParsedPairingTarget,
        expectedEnvironmentId: String? = nil,
        clientLabel: String = "Swft"
    ) async throws -> PairedRemoteSession {
        let descriptor = try await authClient.discoverEnvironment(baseURL: target.httpBaseURL)
        if let expected = expectedEnvironmentId, descriptor.environmentId != expected {
            throw PairingError.environmentMismatch(
                expected: expected,
                actual: descriptor.environmentId,
                actualLabel: descriptor.label
            )
        }

        let exchanged = try await authClient.exchangeBootstrapToken(
            baseURL: target.httpBaseURL,
            bootstrapToken: target.credential,
            clientLabel: clientLabel
        )
        return PairedRemoteSession(
            descriptor: descriptor,
            httpBaseURL: target.httpBaseURL,
            accessToken: exchanged.accessToken,
            scope: exchanged.scope,
            expiresIn: exchanged.expiresIn,
            suggestedLabel: target.suggestedLabel
        )
    }

    /// Issues a one-time pairing token on a host environment (`POST /api/auth/pairing-token`).
    public func createPairingCredential(
        baseURL: URL,
        accessToken: String,
        label: String? = nil,
        scopes: [String]? = nil
    ) async throws -> AuthPairingCredentialResult {
        let url = endpointURL(baseURL: baseURL, path: "/api/auth/pairing-token")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let trimmedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = AuthCreatePairingCredentialInput(
            label: trimmedLabel?.isEmpty == false ? trimmedLabel : nil,
            scopes: scopes
        )
        request.httpBody = try SwftJSON.makeEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RPCError.protocolError("Non-HTTP response from /api/auth/pairing-token")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RPCError.authenticationFailed(body.isEmpty ? "HTTP \(http.statusCode)" : body)
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RPCError.httpError(statusCode: http.statusCode, body: body)
        }
        return try SwftJSON.makeDecoder().decode(AuthPairingCredentialResult.self, from: data)
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
}
