import Foundation
import Testing
@testable import SwftKit

@Suite("Contract Models Encode/Decode")
struct ContractModelsTests {
    @Test func decodesRealEnvironmentDiscoveryAndAuthResponses() throws {
        let decoder = SwftJSON.makeDecoder()

        let envJSON = """
        {
          "environmentId": "603033b9-f97d-42a3-9075-583217adfa8b",
          "label": "Jim's MacBook Pro",
          "platform": { "os": "darwin", "arch": "arm64", "machine": "laptop" },
          "serverVersion": "0.1.11",
          "orchestrationProtocolVersion": 2,
          "databaseMigration": 111,
          "capabilities": {
            "repositoryIdentity": true,
            "connectionProbe": true,
            "threadStop": true,
            "threadForceStop": true,
            "threadVisitedTracking": true,
            "shellThreadFamilies": true,
            "shellOlderSettled": true,
            "someFutureCapability": true
          }
        }
        """
        let env = try decoder.decode(ExecutionEnvironmentDescriptor.self, from: Data(envJSON.utf8))
        #expect(env.environmentId == "603033b9-f97d-42a3-9075-583217adfa8b")
        #expect(env.platform.os == "darwin")
        #expect(env.orchestrationProtocolVersion == 2)
        #expect(env.capabilities.threadStop == true)
        #expect(env.capabilities.threadVisitedTracking == true)

        let tokenJSON = """
        {
          "access_token": "tok_123",
          "issued_token_type": "urn:ietf:params:oauth:token-type:access_token",
          "token_type": "Bearer",
          "expires_in": 2591999,
          "scope": "orchestration:read orchestration:operate"
        }
        """
        let token = try decoder.decode(AuthAccessTokenResult.self, from: Data(tokenJSON.utf8))
        #expect(token.accessToken == "tok_123")
        #expect(token.tokenType == "Bearer")

        let ticketJSON = """
        {
          "ticket": "ws_ticket_abc",
          "expiresAt": "2026-11-24T20:01:00.411Z"
        }
        """
        let ticket = try decoder.decode(AuthWebSocketTicketResult.self, from: Data(ticketJSON.utf8))
        #expect(ticket.ticket == "ws_ticket_abc")
    }

    @Test func decodesServerConfigProvidersAndOptionDescriptors() throws {
        let decoder = SwftJSON.makeDecoder()
        let eventJSON = """
        {
          "version": 1,
          "type": "snapshot",
          "config": {
            "environment": {
              "environmentId": "env-1",
              "label": "Local Mac",
              "platform": { "os": "darwin", "arch": "arm64", "machine": "laptop" },
              "serverVersion": "0.1.11",
              "orchestrationProtocolVersion": 2,
              "capabilities": { "repositoryIdentity": true }
            },
            "auth": {
              "policy": "desktop-managed-local",
              "bootstrapMethods": ["desktop-bootstrap"],
              "sessionMethods": ["bearer-access-token"],
              "sessionCookieName": "t3_session"
            },
            "cwd": "/Users/dev/project",
            "hostname": "MacBookPro",
            "serverTime": "2026-11-24T19:56:01.086Z",
            "providers": [
              {
                "instanceId": "codex",
                "driver": "codex",
                "displayName": "Codex",
                "enabled": true,
                "installed": true,
                "version": "0.50.0",
                "status": "ready",
                "auth": { "status": "authenticated", "label": "ChatGPT Plus" },
                "checkedAt": "2026-11-24T19:56:00.000Z",
                "models": [
                  {
                    "slug": "gpt-6-astra",
                    "name": "GPT-6 Astra",
                    "shortName": "Astra",
                    "isCustom": false,
                    "isDefault": true,
                    "capabilities": {
                      "optionDescriptors": [
                        {
                          "id": "reasoningEffort",
                          "label": "Reasoning",
                          "type": "select",
                          "role": "reasoning",
                          "currentValue": "medium",
                          "options": [
                            { "id": "low", "label": "Low" },
                            { "id": "medium", "label": "Medium", "isDefault": true },
                            { "id": "high", "label": "High" }
                          ]
                        },
                        {
                          "id": "fastMode",
                          "label": "Fast Mode",
                          "type": "boolean",
                          "currentValue": false
                        },
                        {
                          "id": "futureControl",
                          "type": "slider"
                        }
                      ]
                    }
                  }
                ]
              }
            ]
          }
        }
        """

        let event = try decoder.decode(ServerConfigStreamEvent.self, from: Data(eventJSON.utf8))
        guard case .snapshot(let config) = event else {
            Issue.record("Expected snapshot event")
            return
        }
        #expect(config.hostname == "MacBookPro")
        #expect(config.providers.count == 1)
        let provider = config.providers[0]
        #expect(provider.instanceId == "codex")
        #expect(provider.models.count == 1)
        let descriptors = provider.models[0].optionDescriptors
        #expect(descriptors.count == 3)
        #expect(descriptors[0].isReasoningControl)
        if case .boolean(let fast) = descriptors[1] {
            #expect(fast.id == "fastMode")
            #expect(fast.currentValue == false)
        } else {
            Issue.record("Expected boolean descriptor")
        }
        if case .unknown(let id, let type) = descriptors[2] {
            #expect(id == "futureControl")
            #expect(type == "slider")
        } else {
            Issue.record("Expected unknown descriptor fallback")
        }

        // Unknown stream event type decodes without error.
        let unknownEvent = try decoder.decode(
            ServerConfigStreamEvent.self,
            from: Data(#"{"version":1,"type":"environmentThemesUpdated","payload":{"themes":[]}}"#.utf8)
        )
        #expect(unknownEvent == .unknown(type: "environmentThemesUpdated"))
    }

    @Test func decodesAndEncodesModelSelectionFormats() throws {
        let decoder = SwftJSON.makeDecoder()
        let encoder = SwftJSON.makeEncoder()

        // Legacy provider key + legacy options object
        let legacyJSON = #"{"provider":"claudeAgent","model":"claude-opus-5-5","options":{"effort":"high","fast":true}}"#
        let decoded = try decoder.decode(ModelSelection.self, from: Data(legacyJSON.utf8))
        #expect(decoded.instanceId == "claudeAgent")
        #expect(decoded.model == "claude-opus-5-5")
        #expect(decoded.options == [.string("effort", "high"), .bool("fast", true)])

        // Encodes canonical wire form
        let reencoded = try encoder.encode(decoded)
        let json = try JSONDecoder().decode(JSONValue.self, from: reencoded)
        #expect(json["instanceId"] == .string("claudeAgent"))
        #expect(json["model"] == .string("claude-opus-5-5"))
        #expect(json["options"]?.arrayValue?.count == 2)
    }

    @Test func decodesThreadProjectionAndForwardCompatibleTurnItems() throws {
        let decoder = SwftJSON.makeDecoder()
        let streamJSON = """
        {
          "kind": "snapshot",
          "snapshotSequence": 14,
          "projection": {
            "thread": {
              "id": "thr-1",
              "projectId": "proj-1",
              "title": "Fix race condition",
              "providerInstanceId": "codex",
              "modelSelection": { "instanceId": "codex", "model": "gpt-6-astra" },
              "runtimeMode": "approval-required",
              "interactionMode": "default",
              "branch": "fix/race",
              "worktreePath": "/tmp/wt-1",
              "activeProviderThreadId": "pt-1",
              "lineage": { "parentThreadId": null, "relationshipToParent": null, "rootThreadId": "thr-1" },
              "createdAt": "2026-11-24T19:00:00.000Z",
              "updatedAt": "2026-11-24T19:05:00.000Z",
              "archivedAt": null,
              "settledOverride": null,
              "settledAt": null,
              "lastVisitedAt": "2026-11-24T19:04:00.000Z",
              "deletedAt": null
            },
            "runs": [],
            "attempts": [],
            "subagents": [],
            "providerThreads": [],
            "runtimeRequests": [
              {
                "id": "req-1",
                "nodeId": "node-1",
                "providerTurnId": "turn-1",
                "kind": "command",
                "status": "pending",
                "responseCapability": { "type": "live", "providerSessionId": "sess-1", "supportsFeedback": true },
                "createdAt": "2026-11-24T19:05:00.000Z",
                "resolvedAt": null
              }
            ],
            "messages": [],
            "plans": [],
            "turnItems": [],
            "visibleTurnItems": [
              {
                "position": 0,
                "visibility": "local",
                "sourceThreadId": "thr-1",
                "sourceItemId": "item-1",
                "item": {
                  "type": "assistant_message",
                  "id": "item-1",
                  "threadId": "thr-1",
                  "runId": "run-1",
                  "nodeId": "node-1",
                  "providerThreadId": "pt-1",
                  "providerTurnId": "turn-1",
                  "parentItemId": null,
                  "ordinal": 1,
                  "status": "running",
                  "title": null,
                  "startedAt": "2026-11-24T19:04:10.000Z",
                  "completedAt": null,
                  "updatedAt": "2026-11-24T19:04:12.000Z",
                  "messageId": "msg-1",
                  "text": "Investigating the lock...",
                  "streaming": true
                }
              },
              {
                "position": 1,
                "visibility": "local",
                "sourceThreadId": "thr-1",
                "sourceItemId": "item-2",
                "item": {
                  "type": "approval_request",
                  "id": "item-2",
                  "threadId": "thr-1",
                  "runId": "run-1",
                  "nodeId": "node-1",
                  "providerThreadId": "pt-1",
                  "providerTurnId": "turn-1",
                  "parentItemId": null,
                  "ordinal": 2,
                  "status": "waiting",
                  "title": "Run swift test",
                  "startedAt": "2026-11-24T19:05:00.000Z",
                  "completedAt": null,
                  "updatedAt": "2026-11-24T19:05:00.000Z",
                  "requestId": "req-1",
                  "requestKind": "command",
                  "prompt": "Allow `swift test`?"
                }
              },
              {
                "position": 2,
                "visibility": "local",
                "sourceThreadId": "thr-1",
                "sourceItemId": "item-3",
                "item": {
                  "type": "brand_new_future_item",
                  "id": "item-3",
                  "threadId": "thr-1",
                  "runId": "run-1",
                  "nodeId": "node-1",
                  "providerThreadId": null,
                  "providerTurnId": null,
                  "parentItemId": null,
                  "ordinal": 3,
                  "status": "completed",
                  "title": null,
                  "startedAt": null,
                  "completedAt": null,
                  "updatedAt": "2026-11-24T19:05:01.000Z",
                  "customField": 123
                }
              }
            ],
            "updatedAt": "2026-11-24T19:05:01.000Z"
          }
        }
        """

        let streamItem = try decoder.decode(ThreadStreamItem.self, from: Data(streamJSON.utf8))
        guard case .snapshot(let seq, let projection) = streamItem else {
            Issue.record("Expected thread snapshot")
            return
        }
        #expect(seq == 14)
        #expect(projection.thread.branch == "fix/race")
        #expect(projection.runtimeRequests.count == 1)
        #expect(projection.runtimeRequests[0].isPending)
        #expect(projection.runtimeRequests[0].isApproval)
        #expect(projection.visibleTurnItems.count == 3)

        if case .assistantMessage(_, let text, let streaming, _, _, _) = projection.visibleTurnItems[0].item.kind {
            #expect(text == "Investigating the lock...")
            #expect(streaming)
        } else {
            Issue.record("Expected assistant_message")
        }

        if case .approvalRequest(let requestId, let kind, let prompt, _, _, _, _) = projection.visibleTurnItems[1].item.kind {
            #expect(requestId == "req-1")
            #expect(kind == "command")
            #expect(prompt == "Allow `swift test`?")
        } else {
            Issue.record("Expected approval_request")
        }

        if case .unknown(let type, let raw) = projection.visibleTurnItems[2].item.kind {
            #expect(type == "brand_new_future_item")
            #expect(raw["customField"] == .int(123))
        } else {
            Issue.record("Expected unknown fallback for future turn item")
        }
    }

    @Test func encodesOrchestrationCommandsAccurately() throws {
        let encoder = SwftJSON.makeEncoder()

        // thread.create MUST encode explicit `null` for required `Schema.NullOr` branch/worktreePath.
        let createCmd = OrchestrationCommand.createThread(
            commandId: "cmd-1",
            threadId: "thr-1",
            projectId: "proj-1",
            title: "My thread",
            modelSelection: ModelSelection(instanceId: "codex", model: "gpt-6-astra")
        )
        let createObj = try JSONDecoder().decode(JSONValue.self, from: encoder.encode(createCmd))
        #expect(createObj["type"] == .string("thread.create"))
        #expect(createObj["createdBy"] == .string("user"))
        #expect(createObj["creationSource"] == .string("web"))
        #expect(createObj["branch"] == .null)
        #expect(createObj["worktreePath"] == .null)

        // message.dispatch with thinking/reasoning option + steer mode
        let sendCmd = OrchestrationCommand.dispatchMessage(
            commandId: "cmd-2",
            threadId: "thr-1",
            messageId: "msg-1",
            text: "Ship it",
            modelSelection: ModelSelection(
                instanceId: "claudeAgent",
                model: "claude-opus-5-5",
                options: [.string("effort", "high")]
            ),
            deliveryIntent: .steer,
            dispatchMode: .steerActive(targetRunId: "run-9")
        )
        let sendObj = try JSONDecoder().decode(JSONValue.self, from: encoder.encode(sendCmd))
        #expect(sendObj["type"] == .string("message.dispatch"))
        #expect(sendObj["attachments"] == .array([]))
        #expect(sendObj["dispatchMode"]?["type"] == .string("steer_active"))
        #expect(sendObj["dispatchMode"]?["targetRunId"] == .string("run-9"))
        #expect(sendObj["modelSelection"]?["options"]?.arrayValue?.first?["id"] == .string("effort"))

        // runtime-request.respond for approval
        let approveCmd = OrchestrationCommand.respondToRuntimeRequest(
            commandId: "cmd-3",
            threadId: "thr-1",
            requestId: "req-1",
            decision: .acceptForSession,
            feedback: "Looks safe"
        )
        let approveObj = try JSONDecoder().decode(JSONValue.self, from: encoder.encode(approveCmd))
        #expect(approveObj["type"] == .string("runtime-request.respond"))
        #expect(approveObj["decision"] == .string("acceptForSession"))
        #expect(approveObj["feedback"] == .string("Looks safe"))
    }
}
