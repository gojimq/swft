import CryptoKit
import Foundation
import os
import Security

/// Abstraction for persisting sensitive environment credentials (bearer access tokens).
public protocol CredentialStore: Sendable {
    func read(account: String) throws -> String?
    func write(_ secret: String, account: String) throws
    func delete(account: String) throws
}

public enum CredentialStoreError: Error, Sendable, Equatable, LocalizedError {
    case encodingFailed
    case keychainStatus(OSStatus, operation: String)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode credential as UTF-8."
        case .keychainStatus(let status, let operation):
            #if os(macOS)
            let message = SecCopyErrorMessageString(status, nil) as String?
            if let message, !message.isEmpty {
                return "Keychain \(operation) failed (\(status)): \(message)"
            }
            #endif
            return "Keychain \(operation) failed (OSStatus \(status))."
        }
    }
}

/// Persists remote environment credentials in the macOS Keychain under a dedicated service name.
public final class KeychainCredentialStore: CredentialStore {
    public static let defaultService = "com.swft.remote-credentials"

    public let service: String

    public init(service: String = KeychainCredentialStore.defaultService) {
        self.service = service
    }

    /// Derives an isolated Keychain service name when running against a custom `SWFT_HOME`
    /// so scratch or test launches never collide with the developer's live Swft credentials.
    public static func serviceName(forBaseDirectory baseDirectory: URL) -> String {
        let normalized = baseDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        let defaultPath = SwftStoragePaths.defaultBaseDirectory
            .standardizedFileURL.resolvingSymlinksInPath().path
        if normalized == defaultPath {
            return defaultService
        }
        let digest = SHA256.hash(data: Data(normalized.utf8))
        let suffix = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return "\(defaultService).\(suffix)"
    }

    public func read(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw CredentialStoreError.keychainStatus(status, operation: "read")
        }
        guard let data = result as? Data, let secret = String(data: data, encoding: .utf8) else {
            throw CredentialStoreError.encodingFailed
        }
        return secret
    }

    public func write(_ secret: String, account: String) throws {
        guard let data = secret.data(using: .utf8) else {
            throw CredentialStoreError.encodingFailed
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw CredentialStoreError.keychainStatus(updateStatus, operation: "update")
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CredentialStoreError.keychainStatus(addStatus, operation: "add")
        }
    }

    public func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychainStatus(status, operation: "delete")
        }
    }

    // MARK: - GitHub Release Token Convenience

    public static let githubReleaseTokenAccount = "github-release-token"

    public static func readGitHubReleaseToken(
        service: String = KeychainCredentialStore.defaultService
    ) throws -> String? {
        try KeychainCredentialStore(service: service).read(account: githubReleaseTokenAccount)
    }

    public static func saveGitHubReleaseToken(
        _ token: String,
        service: String = KeychainCredentialStore.defaultService
    ) throws {
        try KeychainCredentialStore(service: service).write(token, account: githubReleaseTokenAccount)
    }

    public static func deleteGitHubReleaseToken(
        service: String = KeychainCredentialStore.defaultService
    ) throws {
        try KeychainCredentialStore(service: service).delete(account: githubReleaseTokenAccount)
    }
}

/// Thread-safe in-memory credential store for unit tests, mock mode, and isolated runs.
public final class InMemoryCredentialStore: CredentialStore {
    private let storage = OSAllocatedUnfairLock<[String: String]>(initialState: [:])

    public init(initial: [String: String] = [:]) {
        storage.withLock { $0 = initial }
    }

    public func read(account: String) throws -> String? {
        storage.withLock { $0[account] }
    }

    public func write(_ secret: String, account: String) throws {
        storage.withLock { $0[account] = secret }
    }

    public func delete(account: String) throws {
        storage.withLock { _ = $0.removeValue(forKey: account) }
    }

    public var allAccounts: Set<String> {
        storage.withLock { Set($0.keys) }
    }
}
