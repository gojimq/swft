import Foundation

// MARK: - Settings & Provider Setup RPC Method Tags

public extension RPCMethod {
    static let serverGetSettings = "server.getSettings"
    static let serverUpdateSettings = "server.updateSettings"

    static let providerAuthStart = "provider.auth.start"
    static let providerAuthRespond = "provider.auth.respond"
    static let providerAuthComplete = "provider.auth.complete"
    static let providerAuthCancel = "provider.auth.cancel"
    static let providerAuthLogout = "provider.auth.logout"
    static let providerAuthSubscribe = "provider.auth.subscribe"

    static let providerInstallStart = "provider.install.start"
    static let providerInstallCancel = "provider.install.cancel"
    static let providerInstallSubscribe = "provider.install.subscribe"
    static let providerInstallRemove = "provider.install.remove"
}

private struct EmptyRPCPayload: Encodable, Sendable {}

// MARK: - ServerConnection Settings & Provider Setup RPCs

public extension ServerConnection {
    func getSettings() async throws -> ServerSettings {
        try await call(tag: RPCMethod.serverGetSettings, payload: EmptyRPCPayload())
    }

    @discardableResult
    func updateSettings(_ input: ServerUpdateSettingsInput) async throws -> ServerSettings {
        try await call(tag: RPCMethod.serverUpdateSettings, payload: input)
    }

    nonisolated func subscribeProviderAuth(instanceId: String) -> AsyncThrowingStream<ProviderAuthState, any Error> {
        subscribe(tag: RPCMethod.providerAuthSubscribe, payload: ProviderSetupInput(instanceId: instanceId))
    }

    @discardableResult
    func startProviderAuth(_ input: ProviderAuthStartInput) async throws -> ProviderAuthState {
        try await call(tag: RPCMethod.providerAuthStart, payload: input)
    }

    @discardableResult
    func respondProviderAuth(_ input: ProviderAuthRespondInput) async throws -> ProviderAuthState {
        try await call(tag: RPCMethod.providerAuthRespond, payload: input)
    }

    @discardableResult
    func completeProviderAuth(_ input: ProviderAuthCompleteInput) async throws -> ProviderAuthState {
        try await call(tag: RPCMethod.providerAuthComplete, payload: input)
    }

    @discardableResult
    func cancelProviderAuth(_ input: ProviderAuthCancelInput) async throws -> ProviderAuthState {
        try await call(tag: RPCMethod.providerAuthCancel, payload: input)
    }

    @discardableResult
    func logoutProviderAuth(instanceId: String) async throws -> ProviderAuthState {
        try await call(tag: RPCMethod.providerAuthLogout, payload: ProviderSetupInput(instanceId: instanceId))
    }

    nonisolated func subscribeProviderInstall(instanceId: String) -> AsyncThrowingStream<ProviderInstallState, any Error> {
        subscribe(tag: RPCMethod.providerInstallSubscribe, payload: ProviderSetupInput(instanceId: instanceId))
    }

    @discardableResult
    func startProviderInstall(instanceId: String) async throws -> ProviderInstallState {
        try await call(tag: RPCMethod.providerInstallStart, payload: ProviderSetupInput(instanceId: instanceId))
    }

    @discardableResult
    func cancelProviderInstall(_ input: ProviderInstallCancelInput) async throws -> ProviderInstallState {
        try await call(tag: RPCMethod.providerInstallCancel, payload: input)
    }

    @discardableResult
    func removeProviderInstallation(instanceId: String) async throws -> ProviderInstallState {
        try await call(tag: RPCMethod.providerInstallRemove, payload: ProviderSetupInput(instanceId: instanceId))
    }
}

// MARK: - ThreadsStore Settings Helpers

public extension ThreadsStore {
    @discardableResult
    func refreshProvidersCatalog(instanceId: String? = nil, reloadSecrets: Bool = true) async throws -> [ServerProvider] {
        let result: ServerRefreshProvidersResult = try await connection.call(
            tag: RPCMethod.serverRefreshProviders,
            payload: ServerRefreshProvidersInput(
                instanceId: instanceId,
                cwd: nil,
                fresh: true,
                refreshModels: true,
                modelCatalogOnly: nil,
                reloadSecrets: reloadSecrets
            )
        )
        applyRefreshedProviders(result.providers)
        return result.providers
    }
}
