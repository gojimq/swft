import Foundation
import Testing
@testable import SwftKit

@Suite("Settings Models Encode/Decode")
struct SettingsModelsTests {
    @Test func decodesFullServerSettingsAndDefaults() throws {
        let decoder = SwftJSON.makeDecoder()
        let json = """
        {
          "defaultModelSelection": {
            "instanceId": "codex",
            "model": "gpt-6-astra",
            "options": [{ "id": "reasoningEffort", "value": "high" }]
          },
          "defaultRuntimeMode": "approval-required",
          "defaultThreadEnvMode": "worktree",
          "responseStreamingMode": "turn",
          "keepAwakeWhileAgentsWork": false,
          "continueThreadsAfterServerUpdate": false,
          "sidebarAutoSettleOnMerge": false,
          "enableProviderUpdateChecks": false,
          "idleCompaction": "beforeCacheExpires",
          "providerInstances": {
            "codex-work": {
              "driver": "codex",
              "displayName": "Codex (Work)",
              "accentColor": "#1A73E8",
              "enabled": true,
              "environment": [
                { "name": "OPENAI_API_KEY", "value": "", "sensitive": true, "valueRedacted": true }
              ],
              "config": { "binaryPath": "/opt/homebrew/bin/codex" }
            }
          }
        }
        """
        let settings = try decoder.decode(ServerSettings.self, from: Data(json.utf8))
        #expect(settings.defaultModelSelection?.instanceId == "codex")
        #expect(settings.defaultModelSelection?.model == "gpt-6-astra")
        #expect(settings.defaultModelSelection?.options == [.string("reasoningEffort", "high")])
        #expect(settings.defaultRuntimeMode == .approvalRequired)
        #expect(settings.defaultThreadEnvMode == .worktree)
        #expect(settings.responseStreamingMode == .turn)
        #expect(settings.keepAwakeWhileAgentsWork == false)
        #expect(settings.continueThreadsAfterServerUpdate == false)
        #expect(settings.sidebarAutoSettleOnMerge == false)
        #expect(settings.enableProviderUpdateChecks == false)
        #expect(settings.idleCompaction == .beforeCacheExpires)
        #expect(settings.effectiveIdleCompaction == .beforeCacheExpires)

        let work = try #require(settings.providerInstances["codex-work"])
        #expect(work.driver == "codex")
        #expect(work.displayName == "Codex (Work)")
        #expect(work.accentColor == "#1A73E8")
        #expect(work.environment?.count == 1)
        #expect(work.environment?.first?.valueRedacted == true)
        #expect(work.configObject?["binaryPath"] == .string("/opt/homebrew/bin/codex"))

        // Empty object decodes with safe defaults.
        let empty = try decoder.decode(ServerSettings.self, from: Data("{}".utf8))
        #expect(empty.defaultRuntimeMode == .fullAccess)
        #expect(empty.responseStreamingMode == .paragraph)
        #expect(empty.keepAwakeWhileAgentsWork == true)
        #expect(empty.effectiveIdleCompaction == .onReturn)
        #expect(empty.providerInstances.isEmpty)
    }

    @Test func resolvesLegacyCompactIdleThreadsModes() throws {
        let decoder = SwftJSON.makeDecoder()

        let boolTrue = try decoder.decode(ServerSettings.self, from: Data(#"{"compactIdleThreads":true}"#.utf8))
        #expect(boolTrue.effectiveIdleCompaction == .beforeCacheExpires)

        let boolFalse = try decoder.decode(ServerSettings.self, from: Data(#"{"compactIdleThreads":false}"#.utf8))
        #expect(boolFalse.effectiveIdleCompaction == .onReturn)

        let stringOff = try decoder.decode(ServerSettings.self, from: Data(#"{"compactIdleThreads":"off"}"#.utf8))
        #expect(stringOff.effectiveIdleCompaction == .off)

        let explicit = try decoder.decode(
            ServerSettings.self,
            from: Data(#"{"idleCompaction":"off","compactIdleThreads":true}"#.utf8)
        )
        #expect(explicit.effectiveIdleCompaction == .off)
    }

    @Test func encodesServerSettingsPatchDistinguishingOmitVsNull() throws {
        let encoder = SwftJSON.makeEncoder()

        let partial = ServerSettingsPatch(
            defaultModelSelection: .unchanged,
            defaultRuntimeMode: .autoAcceptEdits,
            defaultThreadEnvMode: .set(nil),
            keepAwakeWhileAgentsWork: false
        )
        let partialJSON = try JSONDecoder().decode(JSONValue.self, from: encoder.encode(partial))
        #expect(partialJSON["defaultModelSelection"] == nil)
        #expect(partialJSON["defaultRuntimeMode"] == .string("auto-accept-edits"))
        #expect(partialJSON["defaultThreadEnvMode"] == .null)
        #expect(partialJSON["keepAwakeWhileAgentsWork"] == .bool(false))
        #expect(partialJSON["responseStreamingMode"] == nil)

        let clearModel = ServerSettingsPatch(
            defaultModelSelection: .set(nil),
            defaultThreadEnvMode: .set(.worktree)
        )
        let clearJSON = try JSONDecoder().decode(JSONValue.self, from: encoder.encode(clearModel))
        #expect(clearJSON["defaultModelSelection"] == .null)
        #expect(clearJSON["defaultThreadEnvMode"] == .string("worktree"))
    }

    @Test func encodesProviderInstanceMutationsAndPreservesSecretReferences() throws {
        let encoder = SwftJSON.makeEncoder()
        let decoder = SwftJSON.makeDecoder()

        let secretEnvJSON = """
        {
          "name": "API_KEY",
          "value": "",
          "sensitive": true,
          "valueRedacted": true,
          "secret": { "provider": "keychain", "ref": "swft-api-key" }
        }
        """
        let envVar = try decoder.decode(ProviderInstanceEnvironmentVariable.self, from: Data(secretEnvJSON.utf8))
        #expect(envVar.isSecretReference)
        let roundTrip = try JSONDecoder().decode(JSONValue.self, from: encoder.encode(envVar))
        #expect(roundTrip["secret"]?["provider"] == .string("keychain"))
        #expect(roundTrip["secret"]?["ref"] == .string("swft-api-key"))

        let createInput = ServerUpdateSettingsInput(
            patch: ServerSettingsPatch(),
            providerInstanceMutation: .create(
                instanceId: "codex-work",
                instance: ProviderInstanceConfig(
                    driver: "codex",
                    displayName: "Codex Work",
                    accentColor: "#1A73E8",
                    environment: [envVar],
                    enabled: true,
                    config: .object(["homePath": .string("~/.codex-work")])
                )
            )
        )
        let createObj = try JSONDecoder().decode(JSONValue.self, from: encoder.encode(createInput))
        #expect(createObj["providerInstanceMutation"]?["operation"] == .string("create"))
        #expect(createObj["providerInstanceMutation"]?["instanceId"] == .string("codex-work"))
        #expect(createObj["providerInstanceMutation"]?["instance"]?["driver"] == .string("codex"))

        let removeObj = try JSONDecoder().decode(
            JSONValue.self,
            from: encoder.encode(ProviderInstanceMutation.remove(instanceId: "codex-work"))
        )
        #expect(removeObj["operation"] == .string("remove"))
        #expect(removeObj["instanceId"] == .string("codex-work"))
        #expect(removeObj["instance"] == nil)
    }

    @Test func decodesSettingsUpdatedStreamEventAndProviderSetupMetadata() throws {
        let decoder = SwftJSON.makeDecoder()

        let settingsEventJSON = """
        {
          "version": 1,
          "type": "settingsUpdated",
          "payload": {
            "settings": {
              "defaultRuntimeMode": "auto",
              "keepAwakeWhileAgentsWork": false
            }
          }
        }
        """
        let event = try decoder.decode(ServerConfigStreamEvent.self, from: Data(settingsEventJSON.utf8))
        guard case .settingsUpdated(let updated) = event else {
            Issue.record("Expected settingsUpdated event")
            return
        }
        #expect(updated.defaultRuntimeMode == .auto)
        #expect(updated.keepAwakeWhileAgentsWork == false)

        let providerJSON = """
        {
          "instanceId": "antigravity",
          "driver": "antigravity",
          "displayName": "Antigravity",
          "enabled": true,
          "installed": true,
          "version": "2026-04-01",
          "status": "warning",
          "auth": { "status": "unauthenticated", "canLogout": true },
          "checkedAt": "2026-11-24T19:56:00.000Z",
          "models": [],
          "setup": {
            "canAuthenticate": true,
            "canInstall": true,
            "documentationUrl": "https://example.com/docs"
          },
          "versionAdvisory": {
            "status": "outdated",
            "currentVersion": "1.0.0",
            "latestVersion": "1.2.0",
            "canUpdate": true
          }
        }
        """
        let provider = try decoder.decode(ServerProvider.self, from: Data(providerJSON.utf8))
        #expect(provider.auth.canLogout == true)
        #expect(provider.setup?.canAuthenticate == true)
        #expect(provider.setup?.canInstall == true)
        #expect(provider.setup?.documentationUrl == "https://example.com/docs")
        #expect(provider.versionAdvisory?.latestVersion == "1.2.0")
    }

    @Test func decodesAndEncodesProviderAuthAndInstallStates() throws {
        let decoder = SwftJSON.makeDecoder()
        let encoder = SwftJSON.makeEncoder()

        let browserStateJSON = """
        {
          "instanceId": "codex",
          "phase": "waiting",
          "flowId": "flow-1",
          "authorizationUrl": "https://auth.example.com/start",
          "methods": [
            { "id": "oauth", "name": "Sign in with browser", "type": "oauth" }
          ],
          "interaction": {
            "type": "browser",
            "id": "int-1",
            "url": "https://auth.example.com/start",
            "requiresConsent": true,
            "acceptsCallback": true
          }
        }
        """
        let authState = try decoder.decode(ProviderAuthState.self, from: Data(browserStateJSON.utf8))
        #expect(authState.phase == .waiting)
        #expect(authState.flowId == "flow-1")
        #expect(authState.methods?.first?.id == "oauth")
        if case .browser(let id, let url, let consent, let callback) = authState.interaction {
            #expect(id == "int-1")
            #expect(url == "https://auth.example.com/start")
            #expect(consent == true)
            #expect(callback == true)
        } else {
            Issue.record("Expected browser interaction")
        }

        let credInteraction = try decoder.decode(
            ProviderAuthInteraction.self,
            from: Data(#"{"type":"credentials","id":"int-2","fields":[{"name":"apiKey","label":"API Key","secret":true}]}"#.utf8)
        )
        if case .credentials(let id, let fields) = credInteraction {
            #expect(id == "int-2")
            #expect(fields.count == 1)
            #expect(fields[0].secret == true)
        } else {
            Issue.record("Expected credentials interaction")
        }

        let futureInteraction = try decoder.decode(
            ProviderAuthInteraction.self,
            from: Data(#"{"type":"qrCode","id":"int-3"}"#.utf8)
        )
        #expect(futureInteraction == .unknown(id: "int-3", type: "qrCode"))

        let responseObj = try JSONDecoder().decode(
            JSONValue.self,
            from: encoder.encode(ProviderAuthResponse.credentials(values: ["apiKey": "sk-test"]))
        )
        #expect(responseObj["type"] == .string("credentials"))
        #expect(responseObj["values"]?["apiKey"] == .string("sk-test"))

        let installJSON = """
        {
          "driver": "antigravity",
          "operationId": "op-9",
          "phase": "downloading",
          "downloadedBytes": 5242880,
          "totalBytes": 10485760,
          "version": "2026-04-02",
          "canRemove": false,
          "message": "Downloading runtime…"
        }
        """
        let install = try decoder.decode(ProviderInstallState.self, from: Data(installJSON.utf8))
        #expect(install.phase == .downloading)
        #expect(install.downloadedBytes == 5_242_880)
        #expect(install.totalBytes == 10_485_760)
    }

    private static var isIntegrationDisabled: Bool {
        let value = ProcessInfo.processInfo.environment["SWFT_SKIP_INTEGRATION_TESTS"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return value == "1" || value == "true" || value == "yes"
    }

    @Test(
        "Reads and updates real server settings and provider accounts over WebSocket RPC",
        .disabled(if: SettingsModelsTests.isIntegrationDisabled, "Skipped via SWFT_SKIP_INTEGRATION_TESTS")
    )
    func readsAndWritesServerSettingsOverLiveRPC() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swftkit-settings-int-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let serverProcess = ServerProcess(
            configuration: ServerLaunchConfiguration(baseDirectory: tempDir, readinessTimeout: .seconds(25))
        )
        let endpoint = try await serverProcess.start()
        let connection = ServerConnection(
            httpBaseURL: endpoint.httpBaseURL,
            credential: .bootstrapToken(endpoint.bootstrapToken),
            clientLabel: "SwftKit Settings Integration Test"
        )

        do {
            _ = try await connection.connect()

            let initial = try await connection.getSettings()
            #expect(initial.defaultRuntimeMode == .fullAccess || initial.defaultRuntimeMode == .approvalRequired)

            let updated = try await connection.updateSettings(
                ServerUpdateSettingsInput(
                    patch: ServerSettingsPatch(
                        defaultRuntimeMode: .approvalRequired,
                        defaultThreadEnvMode: .set(.worktree),
                        responseStreamingMode: .turn,
                        keepAwakeWhileAgentsWork: false
                    )
                )
            )
            #expect(updated.defaultRuntimeMode == .approvalRequired)
            #expect(updated.defaultThreadEnvMode == .worktree)
            #expect(updated.responseStreamingMode == .turn)
            #expect(updated.keepAwakeWhileAgentsWork == false)

            // Create and remove a secondary provider account instance via providerInstanceMutation.
            let created = try await connection.updateSettings(
                ServerUpdateSettingsInput(
                    patch: ServerSettingsPatch(),
                    providerInstanceMutation: .create(
                        instanceId: "codex_test_account",
                        instance: ProviderInstanceConfig(
                            driver: "codex",
                            displayName: "Codex Test",
                            accentColor: "#3b82f6",
                            enabled: true,
                            config: .object(["setupMode": .string("managed")])
                        )
                    )
                )
            )
            #expect(created.providerInstances["codex_test_account"]?.displayName == "Codex Test")
            #expect(created.providerInstances["codex_test_account"]?.accentColor == "#3b82f6")

            let removed = try await connection.updateSettings(
                ServerUpdateSettingsInput(
                    patch: ServerSettingsPatch(),
                    providerInstanceMutation: .remove(instanceId: "codex_test_account")
                )
            )
            #expect(removed.providerInstances["codex_test_account"] == nil)

            let persisted = try await connection.getSettings()
            #expect(persisted.defaultRuntimeMode == .approvalRequired)
            #expect(persisted.keepAwakeWhileAgentsWork == false)

            await connection.disconnect()
            await serverProcess.stop()
        } catch {
            await connection.disconnect()
            await serverProcess.stop()
            throw error
        }
    }
}
