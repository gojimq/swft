import Foundation
import Testing
@testable import SwftKit

@Suite("Remote Connections & Multi-Environment Registry")
struct RemoteEnvironmentTests {
    private static var isIntegrationDisabled: Bool {
        let value = ProcessInfo.processInfo.environment["SWFT_SKIP_INTEGRATION_TESTS"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return value == "1" || value == "true" || value == "yes"
    }

    // MARK: - Pairing URL Parsing

    @Test func parsesDirectHostedAppLinkAndSeparateTokenInputs() throws {
        // Direct URL with hash fragment token
        let direct = try PairingURLParser.parse(address: "http://127.0.0.1:3773/pair#token=PAIR-1234")
        #expect(direct.httpBaseURL.absoluteString == "http://127.0.0.1:3773")
        #expect(direct.wsBaseURL.absoluteString == "ws://127.0.0.1:3773")
        #expect(direct.credential == "PAIR-1234")
        #expect(!direct.isHTTPS)

        // Direct URL with query token and wss scheme
        let wss = try PairingURLParser.parse(address: "wss://mac.example.com:8443/pair?token=SECRET_TOK")
        #expect(wss.httpBaseURL.absoluteString == "https://mac.example.com:8443")
        #expect(wss.wsBaseURL.absoluteString == "wss://mac.example.com:8443")
        #expect(wss.credential == "SECRET_TOK")
        #expect(wss.isHTTPS)

        // Hosted app pairing URL (host in query, token in fragment)
        let hosted = try PairingURLParser.parse(
            address: "https://app.t3.codes/pair?host=https://studio.ts.net&label=Mac%20Studio#token=HOSTED-99"
        )
        #expect(hosted.httpBaseURL.absoluteString == "https://studio.ts.net")
        #expect(hosted.credential == "HOSTED-99")
        #expect(hosted.suggestedLabel == "Mac Studio")

        // App deep link wrapping a direct pairing URL
        let appLink = try PairingURLParser.parse(
            address: "t3code://pair?pairingUrl=https%3A%2F%2Fbox.trycloudflare.com%2Fpair%23token%3DAPP-77"
        )
        #expect(appLink.httpBaseURL.absoluteString == "https://box.trycloudflare.com")
        #expect(appLink.credential == "APP-77")

        // Separate host + token: loopback defaults to http, remote defaults to https
        let loopbackHost = try PairingURLParser.parse(address: "127.0.0.1:4100", token: "TOK-LOCAL")
        #expect(loopbackHost.httpBaseURL.absoluteString == "http://127.0.0.1:4100")
        #expect(loopbackHost.credential == "TOK-LOCAL")

        let remoteHost = try PairingURLParser.parse(address: "workstation.example.com", token: "TOK-REM")
        #expect(remoteHost.httpBaseURL.absoluteString == "https://workstation.example.com")
        #expect(remoteHost.credential == "TOK-REM")
        #expect(remoteHost.isHTTPS)
    }

    @Test func rejectsInvalidOrIncompletePairingInputs() {
        #expect(throws: PairingParseError.emptyAddress) {
            try PairingURLParser.parse(address: "   ")
        }
        #expect(throws: PairingParseError.missingToken) {
            try PairingURLParser.parse(address: "https://mac.example.com")
        }
        #expect(throws: PairingParseError.self) {
            try PairingURLParser.parse(address: "ftp://mac.example.com", token: "abc")
        }
    }

    @Test func buildsPairingInviteURLAndClassifiesLoopbackOrigins() {
        let built = PairingURLParser.buildPairingInviteURL(
            baseURL: "https://Studio.Example.com/ignored?x=1",
            token: "ABCD+1234/=="
        )
        #expect(built?.origin == "https://Studio.Example.com")
        #expect(built?.pairingURL == "https://Studio.Example.com/pair#token=ABCD%2B1234%2F%3D%3D")
        #expect(PairingURLParser.isLoopbackOrigin("http://127.0.0.1:3773"))
        #expect(PairingURLParser.isLoopbackOrigin("http://localhost:3773"))
        #expect(!PairingURLParser.isLoopbackOrigin("https://amber-river.trycloudflare.com"))
    }

    // MARK: - Cloudflare Tunnel & Tailscale Helpers

    @Test func extractsQuickTunnelURLNormalizesPublicURLAndParsesTunnelList() throws {
        let banner = """
        2026-11-24T12:00:00Z INF +--------------------------------------------------+
        2026-11-24T12:00:00Z INF |  https://Amber-River-4821.trycloudflare.com      |
        2026-11-24T12:00:00Z INF +--------------------------------------------------+
        """
        #expect(
            CloudflareTunnelHelpers.extractQuickTunnelURL(from: banner)
                == "https://amber-river-4821.trycloudflare.com"
        )
        #expect(CloudflareTunnelHelpers.extractQuickTunnelURL(from: "http://insecure.trycloudflare.com") == nil)
        #expect(CloudflareTunnelHelpers.extractQuickTunnelURL(from: "nothing here") == nil)

        #expect(
            CloudflareTunnelHelpers.normalizePublicURL("https://Swft.Example.com/pair#token=abc")
                == "https://swft.example.com"
        )
        #expect(
            CloudflareTunnelHelpers.normalizePublicURL("swft.example.com:8443/path")
                == "https://swft.example.com:8443"
        )
        #expect(CloudflareTunnelHelpers.normalizePublicURL("http://swft.example.com") == nil)
        #expect(CloudflareTunnelHelpers.normalizePublicURL("   ") == nil)

        let listJSON = Data("""
        [
          {"id": "uuid-1", "name": "mac-studio", "created_at": "2026-01-01T00:00:00Z", "connections": [{"id":"c1"}, {"id":"c2"}]},
          {"id": "uuid-2", "name": "", "connections": []}
        ]
        """.utf8)
        let parsed = CloudflareTunnelHelpers.parseTunnelListJSON(listJSON)
        #expect(parsed == [
            CloudflareTunnelItem(id: "uuid-1", name: "mac-studio", createdAt: "2026-01-01T00:00:00Z", connectionsCount: 2)
        ])

        // Persist tunnel config atomically in temp dir
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swft-tunnel-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        #expect(CloudflareTunnelHelpers.readConfig(from: tempDir) == CloudflareTunnelConfig())
        let written = try CloudflareTunnelHelpers.writeConfig(
            CloudflareTunnelConfig(mode: .external, publicUrl: "studio.mydomain.com/extra", tunnelName: " home-mac "),
            to: tempDir
        )
        #expect(written == CloudflareTunnelConfig(mode: .external, publicUrl: "https://studio.mydomain.com", tunnelName: "home-mac"))
        #expect(CloudflareTunnelHelpers.readConfig(from: tempDir) == written)

        #expect(
            CloudflareTunnelHelpers.namedTunnelArguments(targetURL: "http://127.0.0.1:54197", tunnelName: "swft")
                == ["tunnel", "--no-autoupdate", "--config", "/dev/null", "run", "--url", "http://127.0.0.1:54197", "swft"]
        )

        let namedConfig = CloudflareTunnelConfig(mode: .named, publicUrl: "https://swft.example.com", tunnelName: "swft")
        #expect(CloudflareTunnelHelpers.shouldAutoStart(
            config: namedConfig,
            localPort: 54197,
            runningPort: nil,
            isProcessRunning: false,
            userStopped: false
        ))
        #expect(!CloudflareTunnelHelpers.shouldAutoStart(
            config: namedConfig,
            localPort: 54197,
            runningPort: 54197,
            isProcessRunning: true,
            userStopped: false
        ))
        #expect(CloudflareTunnelHelpers.shouldAutoStart(
            config: namedConfig,
            localPort: 55000,
            runningPort: 54197,
            isProcessRunning: true,
            userStopped: false
        ))
        #expect(!CloudflareTunnelHelpers.shouldAutoStart(
            config: namedConfig,
            localPort: 54197,
            runningPort: nil,
            isProcessRunning: false,
            userStopped: true
        ))
        #expect(!CloudflareTunnelHelpers.shouldAutoStart(
            config: CloudflareTunnelConfig(mode: .named, publicUrl: "", tunnelName: "swft"),
            localPort: 54197,
            runningPort: nil,
            isProcessRunning: false,
            userStopped: false
        ))
        #expect(CloudflareTunnelHelpers.shouldAutoStart(
            config: CloudflareTunnelConfig(mode: .quick),
            localPort: 55000,
            runningPort: 54197,
            isProcessRunning: true,
            userStopped: false
        ))
        #expect(!CloudflareTunnelHelpers.shouldAutoStart(
            config: CloudflareTunnelConfig(mode: .quick),
            localPort: 54197,
            runningPort: nil,
            isProcessRunning: false,
            userStopped: false
        ))
        #expect(!CloudflareTunnelHelpers.shouldAutoStart(
            config: CloudflareTunnelConfig(mode: .off),
            localPort: 54197,
            runningPort: nil,
            isProcessRunning: false,
            userStopped: false
        ))
    }

    @Test func parsesTailscaleStatusAndClassifiesPrivateAddresses() {
        let json = Data("""
        {
          "BackendState": "Running",
          "Self": {
            "DNSName": "mac-studio.tail1234.ts.net.",
            "TailscaleIPs": ["100.70.1.2", "fd7a:115c:a1e0::1"],
            "CapMap": {"https": []}
          }
        }
        """.utf8)
        let info = HostNetworkHelper.parseTailscaleStatusJSON(json, binaryPath: "/usr/local/bin/tailscale")
        #expect(info.installed)
        #expect(info.running)
        #expect(info.magicDNSName == "mac-studio.tail1234.ts.net")
        #expect(info.tailnetIPv4 == ["100.70.1.2"])
        #expect(info.httpsServeEnabled == true)
        #expect(info.suggestedHTTPSBaseURL == "https://mac-studio.tail1234.ts.net")

        #expect(HostNetworkHelper.isTailscaleIPv4("100.64.0.1"))
        #expect(HostNetworkHelper.isTailscaleIPv4("100.127.255.254"))
        #expect(!HostNetworkHelper.isTailscaleIPv4("192.168.1.5"))
        #expect(HostNetworkHelper.isPrivateLANIPv4("192.168.1.5"))
        #expect(HostNetworkHelper.isPrivateLANIPv4("10.0.0.42"))
        #expect(HostNetworkHelper.isPrivateLANIPv4("172.16.4.1"))
        #expect(!HostNetworkHelper.isPrivateLANIPv4("8.8.8.8"))
    }

    // MARK: - Persistence & Keychain Isolation

    @Test func persistsSavedRecordsToDiskWithoutLeakingSecretsAndScopesKeychainService() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swft-records-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = FileEnvironmentRecordStore(baseDirectory: tempDir)
        #expect(try store.load().isEmpty)

        let addedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let record = SavedEnvironmentRecord(
            id: "env-studio",
            customLabel: "Office Studio",
            lastKnownLabel: "Mac Studio",
            httpBaseURL: URL(string: "https://studio.example.com")!,
            machine: "desktop",
            os: "darwin",
            serverVersion: "0.1.11",
            pairedOverHTTPS: true,
            addedAt: addedAt
        )
        try store.save([record])
        let loaded = try store.load()
        #expect(loaded == [record])

        let rawJSON = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(!rawJSON.contains("access_token"))
        #expect(!rawJSON.contains("secret"))

        // Custom SWFT_HOME gets an isolated Keychain service name, distinct from default.
        let defaultService = KeychainCredentialStore.serviceName(forBaseDirectory: ServerLaunchConfiguration.defaultBaseDirectory)
        let scratchService = KeychainCredentialStore.serviceName(forBaseDirectory: tempDir)
        #expect(defaultService == KeychainCredentialStore.defaultService)
        #expect(scratchService != defaultService)
        #expect(scratchService.hasPrefix("\(KeychainCredentialStore.defaultService)."))
    }

    // MARK: - EnvironmentRegistry Lifecycle, Persistence & Routing

    @Test @MainActor func registryPairsPersistsReloadsRenamesRemovesAndRoutesThreads() async throws {
        let keychain = InMemoryCredentialStore()
        let records = InMemoryEnvironmentRecordStore()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let studioDescriptor = ExecutionEnvironmentDescriptor(
            environmentId: "env-studio",
            label: "Mac Studio",
            platform: ExecutionEnvironmentPlatform(os: "darwin", arch: "arm64", machine: "desktop"),
            serverVersion: "0.1.11"
        )
        let buildDescriptor = ExecutionEnvironmentDescriptor(
            environmentId: "env-build",
            label: "Build Box",
            platform: ExecutionEnvironmentPlatform(os: "linux", arch: "x64", machine: "server"),
            serverVersion: "0.1.11"
        )

        let registry = EnvironmentRegistry(
            credentialStore: keychain,
            recordStore: records,
            pairHandler: { target, expectedId, _ in
                let desc = target.httpBaseURL.host()?.contains("build") == true ? buildDescriptor : studioDescriptor
                if let expectedId, desc.environmentId != expectedId {
                    throw PairingError.environmentMismatch(
                        expected: expectedId,
                        actual: desc.environmentId,
                        actualLabel: desc.label
                    )
                }
                return PairedRemoteSession(
                    descriptor: desc,
                    httpBaseURL: target.httpBaseURL,
                    accessToken: "bearer-\(desc.environmentId)-\(target.credential)",
                    scope: "orchestration:read orchestration:operate",
                    expiresIn: 86_400,
                    suggestedLabel: target.suggestedLabel
                )
            }
        )

        // Register local Mac first
        let localEndpoint = ServerEndpoint(
            httpBaseURL: URL(string: "http://127.0.0.1:4001")!,
            wsBaseURL: URL(string: "ws://127.0.0.1:4001")!,
            port: 4001,
            bootstrapToken: "local-boot",
            pid: 100,
            baseDirectory: FileManager.default.temporaryDirectory,
            environment: ExecutionEnvironmentDescriptor(
                environmentId: "env-local",
                label: "MacBook Pro",
                platform: ExecutionEnvironmentPlatform(os: "darwin", arch: "arm64", machine: "laptop"),
                serverVersion: "0.1.11"
            )
        )
        let localConn = ServerConnection(httpBaseURL: localEndpoint.httpBaseURL, credential: .bootstrapToken("local-boot"))
        let localStore = ThreadsStore(connection: localConn)
        registry.registerLocal(endpoint: localEndpoint, connection: localConn, threadsStore: localStore)

        // Pair two remotes (without opening real sockets)
        let studio = try await registry.pairRemote(
            address: "https://studio.example.com/pair#token=PAIR-STUDIO",
            connectImmediately: false
        )
        let build = try await registry.pairRemote(
            address: "https://build.example.com/pair#token=PAIR-BUILD",
            connectImmediately: false
        )

        // Sorting: local first, then remotes alphabetically (Build Box < Mac Studio)
        #expect(registry.entries.map(\.id) == ["env-local", "env-build", "env-studio"])
        #expect(try keychain.read(account: "env-studio") == "bearer-env-studio-PAIR-STUDIO")
        #expect(try keychain.read(account: "env-build") == "bearer-env-build-PAIR-BUILD")
        #expect(try records.load().count == 2)

        // Reject HTTPS -> HTTP downgrade on re-pair
        await #expect(throws: PairingError.self) {
            try await registry.pairRemote(
                address: "http://studio.example.com/pair#token=DOWNGRADE",
                expectedEnvironmentId: "env-studio",
                connectImmediately: false
            )
        }

        // Rename remote & verify persistence + re-sort
        try registry.renameRemote(id: "env-studio", customLabel: "Alpha Studio")
        #expect(studio.displayLabel == "Alpha Studio")
        #expect(registry.entries.map(\.id) == ["env-local", "env-studio", "env-build"])

        // Re-pair preserves custom label and rotates Keychain token
        let repaired = try await registry.pairRemote(
            address: "https://studio-v2.example.com/pair#token=NEW-TOK",
            expectedEnvironmentId: "env-studio",
            connectImmediately: false
        )
        #expect(repaired.displayLabel == "Alpha Studio")
        #expect(try keychain.read(account: "env-studio") == "bearer-env-studio-NEW-TOK")

        // Thread and project routing across local + remote environments
        let localProject = ProjectShell(id: "p-local", title: "Swft", workspaceRoot: "/code/swft", createdAt: now, updatedAt: now)
        let localThread = ThreadShell(
            id: "t-local",
            projectId: "p-local",
            title: "Local work",
            providerInstanceId: "claudeAgent",
            modelSelection: ModelSelection(instanceId: "claudeAgent", model: "opus"),
            createdAt: now,
            updatedAt: now.addingTimeInterval(-30)
        )
        localStore.apply(.snapshot(ShellSnapshot(snapshotSequence: 1, projects: [localProject], threads: [localThread]), resolvedRepositoryIdentityRoots: nil))

        let remoteProject = ProjectShell(id: "p-remote", title: "Runner", workspaceRoot: "/srv/runner", createdAt: now, updatedAt: now)
        let remoteThread = ThreadShell(
            id: "t-remote",
            projectId: "p-remote",
            title: "Remote build",
            providerInstanceId: "codex",
            modelSelection: ModelSelection(instanceId: "codex", model: "gpt-6.1"),
            createdAt: now,
            updatedAt: now
        )
        build.threadsStore.apply(.snapshot(ShellSnapshot(snapshotSequence: 1, projects: [remoteProject], threads: [remoteThread]), resolvedRepositoryIdentityRoots: nil))

        #expect(registry.environment(owningThreadID: "t-local")?.id == "env-local")
        #expect(registry.environment(owningThreadID: "t-remote")?.id == "env-build")
        #expect(registry.environment(owningProjectID: "p-remote")?.id == "env-build")
        #expect(registry.allListedThreads.map(\.thread.id) == ["t-remote", "t-local"])

        // Reload in a brand-new EnvironmentRegistry using the same recordStore & Keychain stub
        let reloaded = EnvironmentRegistry(credentialStore: keychain, recordStore: records)
        await reloaded.loadSavedRemotes(autoConnect: false)
        #expect(reloaded.entries.map(\.id) == ["env-studio", "env-build"])
        #expect(reloaded.environment(id: "env-studio")?.displayLabel == "Alpha Studio")
        #expect(reloaded.environment(id: "env-studio")?.hasMissingCredentials == false)

        // Missing Keychain credential surfaces cleanly without crashing
        try keychain.delete(account: "env-build")
        let missingCredRegistry = EnvironmentRegistry(credentialStore: keychain, recordStore: records)
        await missingCredRegistry.loadSavedRemotes(autoConnect: false)
        #expect(missingCredRegistry.environment(id: "env-build")?.hasMissingCredentials == true)

        // Removing local is forbidden; removing remote cleans both record store and keychain
        await #expect(throws: EnvironmentRegistryError.cannotRemoveLocal) {
            try await registry.removeRemote(id: "env-local")
        }
        try await registry.removeRemote(id: "env-studio")
        #expect(registry.environment(id: "env-studio") == nil)
        #expect(try keychain.read(account: "env-studio") == nil)
        #expect(try records.load().map(\.id) == ["env-build"])
    }

    // MARK: - Live Two-Server Pairing & Remote Thread Launch

    @Test(
        "Boots two isolated Node servers, pairs remote via real pairing token, and launches a thread on the remote server",
        .disabled(if: RemoteEnvironmentTests.isIntegrationDisabled, "Skipped via SWFT_SKIP_INTEGRATION_TESTS")
    )
    @MainActor
    func pairsAndLaunchesThreadAcrossTwoLiveServers() async throws {
        let rootDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swft-two-server-\(UUID().uuidString)", isDirectory: true)
        let localDir = rootDir.appendingPathComponent("local-home", isDirectory: true)
        let remoteDir = rootDir.appendingPathComponent("remote-home", isDirectory: true)
        let remoteWorkspace = rootDir.appendingPathComponent("remote-project", isDirectory: true)
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remoteWorkspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let localServer = ServerProcess(
            configuration: ServerLaunchConfiguration(baseDirectory: localDir, readinessTimeout: .seconds(25))
        )
        let remoteServer = ServerProcess(
            configuration: ServerLaunchConfiguration(baseDirectory: remoteDir, readinessTimeout: .seconds(25))
        )

        let localEndpoint = try await localServer.start()
        let remoteEndpoint = try await remoteServer.start()
        #expect(localEndpoint.port != remoteEndpoint.port)
        #expect(localEndpoint.environment.environmentId != remoteEndpoint.environment.environmentId)

        let keychain = InMemoryCredentialStore()
        let records = InMemoryEnvironmentRecordStore()
        let registry = await MainActor.run {
            EnvironmentRegistry(credentialStore: keychain, recordStore: records, clientLabel: "Swft Remote Test")
        }

        let localConn = ServerConnection(
            httpBaseURL: localEndpoint.httpBaseURL,
            credential: .bootstrapToken(localEndpoint.bootstrapToken),
            clientLabel: "Swft Local"
        )
        let remoteAdminConn = ServerConnection(
            httpBaseURL: remoteEndpoint.httpBaseURL,
            credential: .bootstrapToken(remoteEndpoint.bootstrapToken),
            clientLabel: "Remote Host Admin"
        )

        do {
            let localStore = await MainActor.run { ThreadsStore(connection: localConn) }
            await MainActor.run {
                registry.registerLocal(endpoint: localEndpoint, connection: localConn, threadsStore: localStore)
                localStore.start()
            }
            _ = try await localConn.connect()

            // Mint a real one-time pairing credential on Server #2 (as if user clicked "Pair device" on Server #2)
            _ = try await remoteAdminConn.connect()
            let remoteAdminToken = try await remoteAdminConn.currentAccessToken()
            let pairingClient = PairingClient()
            let minted = try await pairingClient.createPairingCredential(
                baseURL: remoteEndpoint.httpBaseURL,
                accessToken: remoteAdminToken,
                label: "Remote Integration Test"
            )
            let builtInvite = try #require(
                PairingURLParser.buildPairingInviteURL(
                    baseURL: remoteEndpoint.httpBaseURL.absoluteString,
                    token: minted.credential
                )
            )

            // Pair Server #2 into our EnvironmentRegistry via its pairing URL!
            let pairedRemote = try await registry.pairRemote(address: builtInvite.pairingURL)
            #expect(pairedRemote.id == remoteEndpoint.environment.environmentId)
            #expect(await MainActor.run { pairedRemote.isConnected })
            #expect(try keychain.read(account: pairedRemote.id)?.isEmpty == false)

            // Wait briefly for ServerConfig & shell snapshot to arrive on remote ThreadsStore
            let deadline = ContinuousClock.now + .seconds(10)
            while ContinuousClock.now < deadline {
                let ready = await MainActor.run {
                    pairedRemote.threadsStore.isSynchronized && !pairedRemote.threadsStore.providers.isEmpty
                }
                if ready { break }
                try await Task.sleep(for: .milliseconds(100))
            }

            // Create a project and thread on the REMOTE server, then verify routing + ThreadStore!
            let remoteProject = try await pairedRemote.threadsStore.createProject(
                title: "Remote Repo",
                workspaceRoot: remoteWorkspace.path
            )
            let provider = try #require(await MainActor.run { pairedRemote.threadsStore.providers.first })
            let modelSlug = provider.models.first?.slug ?? "gpt-6-astra"
            let remoteThreadID = try await pairedRemote.threadsStore.createThread(
                projectId: remoteProject.id,
                title: "Launched on remote server",
                modelSelection: ModelSelection(instanceId: provider.instanceId, model: modelSlug)
            )

            // Wait for the thread.updated event to land in remote ThreadsStore
            let shellDeadline = ContinuousClock.now + .seconds(10)
            while ContinuousClock.now < shellDeadline {
                let found = await MainActor.run {
                    registry.environment(owningThreadID: remoteThreadID)?.id == pairedRemote.id
                }
                if found { break }
                try await Task.sleep(for: .milliseconds(100))
            }

            let ownerID = await MainActor.run { registry.environment(owningThreadID: remoteThreadID)?.id }
            #expect(ownerID == pairedRemote.id)

            // Verify ThreadStore opens and loads the snapshot via the remote environment's connection
            let threadStream: AsyncThrowingStream<ThreadStreamItem, any Error> = pairedRemote.connection.subscribe(
                tag: RPCMethod.orchestrationSubscribeThread,
                payload: SubscribeThreadInput(threadId: remoteThreadID, requestCompletionMarker: true)
            )
            var loadedTitle: String?
            for try await item in threadStream {
                if case .snapshot(_, let projection) = item {
                    loadedTitle = projection.thread.title
                    break
                }
            }
            #expect(loadedTitle == "Launched on remote server")

            // Verify our host-side invite minting on Server #1 also succeeds end-to-end
            let localInvite = try await registry.createPairingInvite()
            #expect(localInvite.environmentId == localEndpoint.environment.environmentId)
            #expect(localInvite.pairingURL.contains("/pair#token="))
            #expect(localInvite.isLoopback)

            await registry.disconnectAll()
            await localConn.disconnect()
            await remoteAdminConn.disconnect()
            await localServer.stop()
            await remoteServer.stop()
        } catch {
            await registry.disconnectAll()
            await localConn.disconnect()
            await remoteAdminConn.disconnect()
            await localServer.stop()
            await remoteServer.stop()
            throw error
        }
    }
}
