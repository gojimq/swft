import Foundation
import Testing
@testable import SwftKit

@Suite("Subagent Wire Contracts & Live Reduction")
struct SubagentContractTests {
    private static func makeDummyConnection() -> ServerConnection {
        ServerConnection(
            httpBaseURL: URL(string: "http://127.0.0.1:1")!,
            credential: .bootstrapToken("test")
        )
    }

    @Test func decodesSubagentTurnItemsAndProjectionSubagentsWithForwardCompat() throws {
        let decoder = SwftJSON.makeDecoder()
        let json = """
        {
          "kind": "snapshot",
          "snapshotSequence": 42,
          "projection": {
            "thread": {
              "id": "thr-parent",
              "projectId": "proj-1",
              "title": "Refactor transport",
              "providerInstanceId": "claudeAgent",
              "modelSelection": { "instanceId": "claudeAgent", "model": "claude-opus-4-6" },
              "runtimeMode": "full-access",
              "interactionMode": "default",
              "branch": "main",
              "worktreePath": null,
              "activeProviderThreadId": "pt-1",
              "creationSource": "web",
              "delegatedFrom": null,
              "lineage": { "parentThreadId": null, "relationshipToParent": null, "rootThreadId": "thr-parent" },
              "createdAt": "2026-11-24T19:00:00.000Z",
              "updatedAt": "2026-11-24T19:05:00.000Z",
              "archivedAt": null,
              "settledOverride": null,
              "settledAt": null,
              "lastVisitedAt": null,
              "deletedAt": null
            },
            "runs": [],
            "attempts": [],
            "subagents": [
              {
                "id": "node-sub-1",
                "threadId": "thr-parent",
                "runId": "run-1",
                "parentNodeId": "node-root",
                "origin": "app_owned",
                "createdBy": "agent",
                "driver": "codex",
                "providerInstanceId": "codex",
                "providerThreadId": "pt-sub-1",
                "childThreadId": "thr-child-1",
                "nativeTaskRef": null,
                "prompt": "Audit WebSocket reconnection",
                "title": "Subagent: Codebase Researcher",
                "model": "gpt-6.1",
                "modelSelection": { "instanceId": "codex", "model": "gpt-6.1" },
                "executedModel": "gpt-6.1",
                "status": "running",
                "progress": "Reading ServerConnection.swift",
                "result": null,
                "startedAt": "2026-11-24T19:01:00.000Z",
                "completedAt": null,
                "updatedAt": "2026-11-24T19:01:14.000Z",
                "futureExtraField": { "nested": true }
              },
              {
                "id": "node-sub-remote",
                "threadId": "thr-parent",
                "runId": "run-1",
                "parentNodeId": "node-root",
                "origin": "app_owned",
                "createdBy": "agent",
                "driver": "claudeAgent",
                "providerInstanceId": "claudeAgent",
                "providerThreadId": null,
                "childThreadId": null,
                "remoteChild": {
                  "environmentId": "env-studio",
                  "threadId": "thr-remote-9",
                  "label": "Mac Studio",
                  "title": "Benchmark Metal kernels",
                  "runId": "run-remote-1"
                },
                "nativeTaskRef": null,
                "prompt": "Run GPU benchmarks",
                "title": "GPU Benchmarker",
                "model": null,
                "status": "completed",
                "result": "Throughput +18%",
                "startedAt": "2026-11-24T19:01:00.000Z",
                "completedAt": "2026-11-24T19:02:22.000Z",
                "updatedAt": "2026-11-24T19:02:22.000Z"
              }
            ],
            "providerThreads": [],
            "runtimeRequests": [],
            "messages": [],
            "plans": [],
            "turnItems": [],
            "visibleTurnItems": [
              {
                "position": 0,
                "visibility": "local",
                "sourceThreadId": "thr-parent",
                "sourceItemId": "item-sub-1",
                "item": {
                  "type": "subagent",
                  "id": "item-sub-1",
                  "threadId": "thr-parent",
                  "runId": "run-1",
                  "nodeId": "node-sub-1",
                  "providerThreadId": "pt-1",
                  "providerTurnId": "turn-1",
                  "parentItemId": null,
                  "ordinal": 1,
                  "status": "running",
                  "title": "Subagent: Codebase Researcher",
                  "startedAt": "2026-11-24T19:01:00.000Z",
                  "completedAt": null,
                  "updatedAt": "2026-11-24T19:01:14.000Z",
                  "subagentId": "node-sub-1",
                  "origin": "app_owned",
                  "driver": "codex",
                  "providerInstanceId": "codex",
                  "childThreadId": "thr-child-1",
                  "prompt": "",
                  "promptOmitted": true,
                  "progress": "Reading ServerConnection.swift",
                  "result": null,
                  "unknownFutureProp": 42
                }
              },
              {
                "position": 1,
                "visibility": "local",
                "sourceThreadId": "thr-parent",
                "sourceItemId": "item-sub-remote",
                "item": {
                  "type": "subagent",
                  "id": "item-sub-remote",
                  "threadId": "thr-parent",
                  "runId": "run-1",
                  "nodeId": "node-sub-remote",
                  "providerThreadId": "pt-1",
                  "providerTurnId": "turn-1",
                  "parentItemId": null,
                  "ordinal": 2,
                  "status": "completed",
                  "title": "GPU Benchmarker",
                  "startedAt": "2026-11-24T19:01:00.000Z",
                  "completedAt": "2026-11-24T19:02:22.000Z",
                  "updatedAt": "2026-11-24T19:02:22.000Z",
                  "subagentId": "node-sub-remote",
                  "origin": "app_owned",
                  "driver": "claudeAgent",
                  "providerInstanceId": "claudeAgent",
                  "childThreadId": null,
                  "remoteChild": {
                    "environmentId": "env-studio",
                    "threadId": "thr-remote-9",
                    "label": "Mac Studio",
                    "title": "Benchmark Metal kernels"
                  },
                  "prompt": "Run GPU benchmarks",
                  "result": "Throughput +18%"
                }
              }
            ],
            "updatedAt": "2026-11-24T19:02:22.000Z"
          }
        }
        """

        let streamItem = try decoder.decode(ThreadStreamItem.self, from: Data(json.utf8))
        guard case .snapshot(let seq, let projection) = streamItem else {
            Issue.record("Expected snapshot")
            return
        }
        #expect(seq == 42)
        #expect(projection.subagents.count == 2)

        let firstSub = projection.subagents[0]
        #expect(firstSub.id == "node-sub-1")
        #expect(firstSub.childThreadId == "thr-child-1")
        #expect(firstSub.model == "gpt-6.1")
        #expect(firstSub.executedModel == "gpt-6.1")
        #expect(firstSub.modelSelection?.model == "gpt-6.1")
        #expect(firstSub.isActive)

        let remoteSub = projection.subagents[1]
        #expect(remoteSub.remoteChild?.environmentId == "env-studio")
        #expect(remoteSub.remoteChild?.threadId == "thr-remote-9")
        #expect(remoteSub.remoteChild?.label == "Mac Studio")
        #expect(!remoteSub.isActive)

        if case .subagent(
            let subagentId,
            let origin,
            let driver,
            let instanceId,
            let childThreadId,
            let remoteChild,
            let prompt,
            let progress,
            let result,
            let promptOmitted,
            let resultOmitted
        ) = projection.visibleTurnItems[0].item.kind {
            #expect(subagentId == "node-sub-1")
            #expect(origin == "app_owned")
            #expect(driver == "codex")
            #expect(instanceId == "codex")
            #expect(childThreadId == "thr-child-1")
            #expect(remoteChild == nil)
            #expect(prompt.isEmpty)
            #expect(promptOmitted)
            #expect(!resultOmitted)
            #expect(progress == "Reading ServerConnection.swift")
            #expect(result == nil)
        } else {
            Issue.record("Expected subagent TurnItem")
        }

        if case .subagent(_, _, _, _, let childId, let remoteChild, _, _, let result, _, _) = projection.visibleTurnItems[1].item.kind {
            #expect(childId == nil)
            #expect(remoteChild?.environmentId == "env-studio")
            #expect(result == "Throughput +18%")
        } else {
            Issue.record("Expected remote subagent TurnItem")
        }
    }

    @Test @MainActor func threadStoreHydratesAndReducesLiveSubagentUpdates() throws {
        let store = ThreadStore(connection: Self.makeDummyConnection(), threadId: "thr-1")
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)

        let thread = AppThread(
            id: "thr-1",
            projectId: "proj-1",
            title: "Parent thread",
            providerInstanceId: "claudeAgent",
            modelSelection: ModelSelection(instanceId: "claudeAgent", model: "opus"),
            createdAt: t0,
            updatedAt: t0
        )
        let initialSubagent = SubagentSummary(
            id: "sub-1",
            threadId: "thr-1",
            runId: "run-1",
            origin: "app_owned",
            driver: "codex",
            providerInstanceId: "codex",
            childThreadId: "thr-child-1",
            prompt: "Inspect lock ordering",
            title: "Lock Auditor",
            model: "gpt-6.1",
            status: "running",
            progress: "Scanning Sources/SwftKit",
            result: nil,
            startedAt: t0,
            completedAt: nil,
            updatedAt: t0
        )
        let initialItem = TurnItem(
            id: "item-sub-1",
            threadId: "thr-1",
            runId: "run-1",
            providerTurnId: "turn-1",
            ordinal: 1,
            status: "running",
            title: "Lock Auditor",
            startedAt: t0,
            completedAt: nil,
            updatedAt: t0,
            kind: .subagent(
                subagentId: "sub-1",
                origin: "app_owned",
                driver: "codex",
                providerInstanceId: "codex",
                childThreadId: "thr-child-1",
                remoteChild: nil,
                prompt: "",
                progress: "Scanning Sources/SwftKit",
                result: nil,
                promptOmitted: true,
                resultOmitted: false
            )
        )

        store.apply(.snapshot(
            snapshotSequence: 1,
            projection: ThreadProjection(
                thread: thread,
                subagents: [initialSubagent],
                turnItems: [initialItem],
                visibleTurnItems: [
                    ProjectedTurnItem(
                        position: 0,
                        visibility: .local,
                        sourceThreadId: "thr-1",
                        sourceItemId: "item-sub-1",
                        item: initialItem
                    )
                ],
                updatedAt: t0
            )
        ))

        // Snapshot hydration restores omitted prompt from projection.subagents.
        if case .subagent(_, _, _, _, _, _, let hydratedPrompt, _, _, _, _) = store.visibleItems[0].item.kind {
            #expect(hydratedPrompt == "Inspect lock ordering")
        } else {
            Issue.record("Expected hydrated subagent item")
        }

        // Live `subagent.updated` with deduped prompt preserves prompt and updates status/result/completedAt.
        let versionBefore = store.projectionVersion
        let decoder = SwftJSON.makeDecoder()
        let eventJSON = """
        {
          "kind": "event",
          "sequence": 2,
          "event": {
            "id": "ev-sub-2",
            "threadId": "thr-1",
            "runId": "run-1",
            "nodeId": "sub-1",
            "occurredAt": "2026-11-24T19:01:22.000Z",
            "type": "subagent.updated",
            "payload": {
              "id": "sub-1",
              "threadId": "thr-1",
              "runId": "run-1",
              "origin": "app_owned",
              "driver": "codex",
              "providerInstanceId": "codex",
              "childThreadId": "thr-child-1",
              "prompt": "",
              "promptOmitted": true,
              "title": "Lock Auditor",
              "model": "gpt-6.1",
              "status": "completed",
              "progress": "Done",
              "result": "Verified zero deadlocks across actors.",
              "startedAt": "2026-11-24T19:00:00.000Z",
              "completedAt": "2026-11-24T19:01:22.000Z",
              "updatedAt": "2026-11-24T19:01:22.000Z"
            }
          }
        }
        """
        let streamUpdate = try decoder.decode(ThreadStreamItem.self, from: Data(eventJSON.utf8))
        store.apply(streamUpdate)

        #expect(store.projectionVersion == versionBefore + 1)
        #expect(store.subagents.count == 1)
        #expect(store.subagents[0].status == "completed")
        #expect(store.subagents[0].prompt == "Inspect lock ordering")
        #expect(store.subagents[0].result == "Verified zero deadlocks across actors.")
        #expect(store.subagents[0].completedAt != nil)
    }
}
