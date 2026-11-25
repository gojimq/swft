import Foundation
import Testing
@testable import SwftKit

@Suite("Settled Thread Wire Contracts")
struct SettledContractTests {
    @Test func encodesSettleAndUnsettleCommands() throws {
        let encoder = SwftJSON.makeEncoder()

        let settleCmd = OrchestrationCommand.settleThread(commandId: "cmd-settle", threadId: "thr-42")
        let settleObj = try JSONDecoder().decode(JSONValue.self, from: encoder.encode(settleCmd))
        #expect(settleObj["type"] == .string("thread.settle"))
        #expect(settleObj["commandId"] == .string("cmd-settle"))
        #expect(settleObj["threadId"] == .string("thr-42"))

        let unsettleCmd = OrchestrationCommand.unsettleThread(commandId: "cmd-unsettle", threadId: "thr-42")
        let unsettleObj = try JSONDecoder().decode(JSONValue.self, from: encoder.encode(unsettleCmd))
        #expect(unsettleObj["type"] == .string("thread.unsettle"))
        #expect(unsettleObj["commandId"] == .string("cmd-unsettle"))
        #expect(unsettleObj["threadId"] == .string("thr-42"))
        #expect(unsettleObj["reason"] == .string("user"))
    }

    @Test func decodesThreadShellSettledMetadata() throws {
        let decoder = SwftJSON.makeDecoder()

        let settledJSON = """
        {
          "id": "thr-1",
          "projectId": "proj-1",
          "title": "Done task",
          "providerInstanceId": "codex",
          "modelSelection": { "instanceId": "codex", "model": "gpt-6-astra" },
          "runtimeMode": "full-access",
          "interactionMode": "default",
          "lineage": { "parentThreadId": null, "relationshipToParent": null, "rootThreadId": "thr-1" },
          "status": "idle",
          "createdAt": "2026-11-24T10:00:00.000Z",
          "updatedAt": "2026-11-24T11:00:00.000Z",
          "settledOverride": "settled",
          "settledAt": "2026-11-24T12:00:00.000Z"
        }
        """
        let settled = try decoder.decode(ThreadShell.self, from: Data(settledJSON.utf8))
        #expect(settled.isSettled)
        #expect(settled.settledOverride == "settled")
        #expect(settled.settledAt != nil)

        // Explicit active override wins even if a historic settledAt timestamp is present.
        let activeOverrideJSON = """
        {
          "id": "thr-2",
          "projectId": "proj-1",
          "title": "Reopened task",
          "providerInstanceId": "codex",
          "modelSelection": { "instanceId": "codex", "model": "gpt-6-astra" },
          "runtimeMode": "full-access",
          "interactionMode": "default",
          "lineage": { "parentThreadId": null, "relationshipToParent": null, "rootThreadId": "thr-2" },
          "status": "idle",
          "createdAt": "2026-11-24T10:00:00.000Z",
          "updatedAt": "2026-11-24T11:00:00.000Z",
          "settledOverride": "active",
          "settledAt": "2026-11-24T12:00:00.000Z",
          "unsettledAt": "2026-11-24T13:00:00.000Z"
        }
        """
        let reopened = try decoder.decode(ThreadShell.self, from: Data(activeOverrideJSON.utf8))
        #expect(!reopened.isSettled)
        #expect(reopened.unsettledAt != nil)
    }

    @Test @MainActor func threadsStorePopulatesSettledAtOnSidebarItems() {
        let connection = ServerConnection(
            httpBaseURL: URL(string: "http://127.0.0.1:1")!,
            credential: .bootstrapToken("test")
        )
        let store = ThreadsStore(connection: connection)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let settledAt = now.addingTimeInterval(-3600)

        let project = ProjectShell(
            id: "proj-1",
            title: "Swft",
            workspaceRoot: "/tmp/swft",
            createdAt: now,
            updatedAt: now
        )
        let settledThread = ThreadShell(
            id: "thr-settled",
            projectId: "proj-1",
            title: "Shipped feature",
            providerInstanceId: "claudeAgent",
            modelSelection: ModelSelection(instanceId: "claudeAgent", model: "opus"),
            createdAt: now.addingTimeInterval(-7200),
            updatedAt: now.addingTimeInterval(-5400),
            settledOverride: "settled",
            settledAt: settledAt
        )

        store.apply(.snapshot(
            ShellSnapshot(snapshotSequence: 1, projects: [project], threads: [settledThread]),
            resolvedRepositoryIdentityRoots: nil
        ))

        #expect(store.sidebarItems.count == 1)
        #expect(store.sidebarItems[0].isSettled)
        #expect(store.sidebarItems[0].settledAt == settledAt)
    }
}
