import Foundation
import Testing
@testable import SwftKit

@Suite("Project Deletion Wire Contracts & ThreadsStore")
struct ProjectDeletionContractTests {
    private static func makeDummyConnection() -> ServerConnection {
        ServerConnection(
            httpBaseURL: URL(string: "http://127.0.0.1:1")!,
            credential: .bootstrapToken("test")
        )
    }

    @Test func encodesProjectDeleteMutationWithAndWithoutForce() throws {
        let encoder = SwftJSON.makeEncoder()

        let defaultDelete = ProjectMutation.delete(commandId: "cmd-1", projectId: "proj-1")
        let defaultJSON = try JSONDecoder().decode(JSONValue.self, from: encoder.encode(defaultDelete))
        #expect(defaultJSON["type"] == .string("project.delete"))
        #expect(defaultJSON["commandId"] == .string("cmd-1"))
        #expect(defaultJSON["projectId"] == .string("proj-1"))
        #expect(defaultJSON["force"] == nil)

        let forcedDelete = ProjectMutation.delete(commandId: "cmd-2", projectId: "proj-2", force: true)
        let forcedJSON = try JSONDecoder().decode(JSONValue.self, from: encoder.encode(forcedDelete))
        #expect(forcedJSON["type"] == .string("project.delete"))
        #expect(forcedJSON["commandId"] == .string("cmd-2"))
        #expect(forcedJSON["projectId"] == .string("proj-2"))
        #expect(forcedJSON["force"] == .bool(true))

        let unforcedDelete = ProjectMutation.delete(commandId: "cmd-3", projectId: "proj-3", force: false)
        let unforcedJSON = try JSONDecoder().decode(JSONValue.self, from: encoder.encode(unforcedDelete))
        #expect(unforcedJSON["force"] == .bool(false))
    }

    @Test func decodesDeletedProjectShellAndProjectRemovedStreamItem() throws {
        let decoder = SwftJSON.makeDecoder()

        let deletedProjectJSON = """
        {
          "id": "proj-old",
          "title": "Old Scratch",
          "workspaceRoot": "/tmp/deleted-repo",
          "defaultModelSelection": null,
          "scripts": [],
          "createdAt": "2026-11-20T10:00:00.000Z",
          "updatedAt": "2026-11-25T10:00:00.000Z",
          "deletedAt": "2026-11-25T10:05:00.000Z"
        }
        """
        let decoded = try decoder.decode(ProjectShell.self, from: Data(deletedProjectJSON.utf8))
        #expect(decoded.id == "proj-old")
        #expect(decoded.deletedAt != nil)

        let removedJSON = """
        {
          "kind": "project.removed",
          "sequence": 42,
          "projectId": "proj-old"
        }
        """
        let item = try decoder.decode(ShellStreamItem.self, from: Data(removedJSON.utf8))
        #expect(item == .projectRemoved(sequence: 42, projectId: "proj-old"))
    }

    @Test @MainActor func threadsStoreProjectRemovedCleansProjectAndItsThreads() {
        let store = ThreadsStore(connection: Self.makeDummyConnection())
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let doomed = ProjectShell(id: "proj-old", title: "Old", workspaceRoot: "/tmp/old", createdAt: now, updatedAt: now)
        let keeper = ProjectShell(id: "proj-keep", title: "Keep", workspaceRoot: "/tmp/keep", createdAt: now, updatedAt: now)

        let doomedActive = ThreadShell(
            id: "thr-old-1",
            projectId: "proj-old",
            title: "Stale thread",
            providerInstanceId: "claudeAgent",
            modelSelection: ModelSelection(instanceId: "claudeAgent", model: "opus"),
            createdAt: now,
            updatedAt: now
        )
        let doomedArchived = ThreadShell(
            id: "thr-old-arch",
            projectId: "proj-old",
            title: "Archived stale",
            providerInstanceId: "claudeAgent",
            modelSelection: ModelSelection(instanceId: "claudeAgent", model: "opus"),
            createdAt: now,
            updatedAt: now,
            archivedAt: now
        )
        let keeperThread = ThreadShell(
            id: "thr-keep-1",
            projectId: "proj-keep",
            title: "Active work",
            providerInstanceId: "claudeAgent",
            modelSelection: ModelSelection(instanceId: "claudeAgent", model: "opus"),
            createdAt: now,
            updatedAt: now
        )

        store.apply(.snapshot(
            ShellSnapshot(
                snapshotSequence: 10,
                projects: [doomed, keeper],
                threads: [doomedActive, keeperThread],
                archivedThreads: [doomedArchived]
            ),
            resolvedRepositoryIdentityRoots: nil
        ))

        // Stale sequence is ignored.
        store.apply(.projectRemoved(sequence: 10, projectId: "proj-old"))
        #expect(store.projects.map(\.id) == ["proj-old", "proj-keep"])
        #expect(store.threads.map(\.id) == ["thr-old-1", "thr-keep-1"])
        #expect(store.archivedThreads.map(\.id) == ["thr-old-arch"])

        // Newer sequence removes the project and all threads belonging to it.
        store.apply(.projectRemoved(sequence: 11, projectId: "proj-old"))
        #expect(store.projects.map(\.id) == ["proj-keep"])
        #expect(store.threads.map(\.id) == ["thr-keep-1"])
        #expect(store.archivedThreads.isEmpty)
        #expect(store.lastSequence == 11)
    }

    @Test @MainActor func threadsStoreDeleteProjectSendsMutationAndUpdatesStateAtomically() async throws {
        let store = ThreadsStore(connection: Self.makeDummyConnection())
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let doomed = ProjectShell(id: "proj-del", title: "Doomed", workspaceRoot: "/tmp/doomed", createdAt: now, updatedAt: now)
        let survivor = ProjectShell(id: "proj-ok", title: "Survivor", workspaceRoot: "/tmp/ok", createdAt: now, updatedAt: now)
        let doomedThread = ThreadShell(
            id: "thr-del",
            projectId: "proj-del",
            title: "Will go away",
            providerInstanceId: "codex",
            modelSelection: ModelSelection(instanceId: "codex", model: "gpt-6.1"),
            createdAt: now,
            updatedAt: now
        )
        let survivorThread = ThreadShell(
            id: "thr-ok",
            projectId: "proj-ok",
            title: "Stays put",
            providerInstanceId: "codex",
            modelSelection: ModelSelection(instanceId: "codex", model: "gpt-6.1"),
            createdAt: now,
            updatedAt: now
        )

        store.apply(.snapshot(
            ShellSnapshot(snapshotSequence: 5, projects: [doomed, survivor], threads: [doomedThread, survivorThread]),
            resolvedRepositoryIdentityRoots: nil
        ))

        var capturedTag: String?
        var capturedMutation: ProjectMutation?

        // First verify failure leaves store state unchanged.
        struct DeleteFailure: Error {}
        store.projectMutationOverride = { tag, mutation in
            capturedTag = tag
            capturedMutation = mutation
            throw DeleteFailure()
        }
        await #expect(throws: DeleteFailure.self) {
            try await store.deleteProject(projectId: "proj-del", force: true)
        }
        #expect(capturedTag == RPCMethod.projectsMutate)
        #expect(store.projects.map(\.id) == ["proj-del", "proj-ok"])
        #expect(store.threads.map(\.id) == ["thr-del", "thr-ok"])

        // Now verify success sends project.delete with force: true and cleans store immediately.
        store.projectMutationOverride = { tag, mutation in
            capturedTag = tag
            capturedMutation = mutation
            return ProjectShell(
                id: "proj-del",
                title: "Doomed",
                workspaceRoot: "/tmp/doomed",
                createdAt: now,
                updatedAt: now,
                deletedAt: now
            )
        }

        let deleted = try await store.deleteProject(projectId: "proj-del", force: true)
        #expect(deleted.id == "proj-del")
        #expect(deleted.deletedAt == now)
        #expect(capturedTag == "projects.mutate")
        if case .delete(let commandId, let projectId, let force) = capturedMutation {
            #expect(!commandId.isEmpty)
            #expect(projectId == "proj-del")
            #expect(force == true)
        } else {
            Issue.record("Expected ProjectMutation.delete")
        }
        #expect(store.projects.map(\.id) == ["proj-ok"])
        #expect(store.threads.map(\.id) == ["thr-ok"])
    }
}
