import CoreGraphics
import Foundation
import SwftDesign
import Testing
@testable import Swft
@testable import SwftKit

@Suite("Project Deletion, Missing-Folder Recovery & Routing")
struct ProjectDeletionTests {
    private let broken = ProjectRef(
        id: "p-broken",
        name: "Deleted Scratch",
        initials: "DS",
        tint: 0,
        workspaceRoot: "/tmp/deleted-scratch",
        isWorkspaceMissing: true
    )
    private let swft = ProjectRef(
        id: "p-swft",
        name: "Swft",
        initials: "SW",
        tint: 1,
        workspaceRoot: "/Users/dev/code/swft",
        isWorkspaceMissing: false
    )
    private let studio = ProjectRef(
        id: "p-studio",
        name: "Studio",
        initials: "ST",
        tint: 2,
        workspaceRoot: "/Users/dev/code/studio",
        isWorkspaceMissing: false
    )

    // MARK: - Pure Logic

    @Test func localWorkspaceMissingCheckProbesDiskOnlyForLocalEnvironments() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("swft-proj-check-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let filePath = tempRoot.appendingPathComponent("not-a-folder.txt")
        try Data("hi".utf8).write(to: filePath)

        // Existing local directory -> not missing.
        #expect(!ProjectDeletionLogic.isWorkspaceMissing(workspaceRoot: tempRoot.path, isLocalEnvironment: true))
        // Regular file is not a valid workspace directory -> missing.
        #expect(ProjectDeletionLogic.isWorkspaceMissing(workspaceRoot: filePath.path, isLocalEnvironment: true))

        // Removed local directory -> missing.
        let missingPath = tempRoot.appendingPathComponent("gone", isDirectory: true).path
        #expect(ProjectDeletionLogic.isWorkspaceMissing(workspaceRoot: missingPath, isLocalEnvironment: true))

        // Remote environment paths are NEVER probed on this Mac.
        #expect(!ProjectDeletionLogic.isWorkspaceMissing(workspaceRoot: missingPath, isLocalEnvironment: false))
        #expect(!ProjectDeletionLogic.isWorkspaceMissing(workspaceRoot: "/srv/remote-only/repo", isLocalEnvironment: false))

        // Nil / blank paths are not marked missing.
        #expect(!ProjectDeletionLogic.isWorkspaceMissing(workspaceRoot: nil, isLocalEnvironment: true))
        #expect(!ProjectDeletionLogic.isWorkspaceMissing(workspaceRoot: "   ", isLocalEnvironment: true))
    }

    @Test func defaultSelectionSkipsMissingFolderProjectsAndNeverTrapsUser() {
        // Launch default skips leading broken project and chooses first healthy project.
        #expect(
            NoProjectLogic.resolveSelectedProject(
                projects: [broken, swft, studio],
                selectedProjectID: nil,
                isNoProjectSelected: false
            )?.id == swft.id
        )

        // Even if selectedProjectID points at a project whose folder disappeared, recover to healthy project.
        #expect(
            NoProjectLogic.resolveSelectedProject(
                projects: [broken, swft],
                selectedProjectID: broken.id,
                isNoProjectSelected: false
            )?.id == swft.id
        )

        // If every remaining project has a missing folder, fall back cleanly to nil ("No project").
        #expect(
            NoProjectLogic.resolveSelectedProject(
                projects: [broken],
                selectedProjectID: nil,
                isNoProjectSelected: false
            ) == nil
        )

        // Switching environments also skips missing-folder projects (even on name match).
        let brokenNamedSwft = ProjectRef(
            id: "p-broken-swft",
            name: "Swft",
            initials: "SW",
            tint: 0,
            workspaceRoot: "/tmp/gone-swft",
            isWorkspaceMissing: true
        )
        #expect(
            RemoteLogic.findProjectForEnvironment(
                projects: [brokenNamedSwft, studio],
                preferredName: "Swft"
            )?.id == studio.id
        )
        #expect(
            RemoteLogic.findProjectForEnvironment(
                projects: [brokenNamedSwft],
                preferredName: "Swft"
            ) == nil
        )
    }

    @Test func postDeleteSelectionRecoversToNextValidProjectOrNoProject() {
        // Deleting selected project advances to the next healthy project (skipping missing ones).
        let afterSelected = ProjectDeletionLogic.nextSelectionAfterDeleting(
            deletedProjectID: swft.id,
            wasSelected: true,
            wasNoProjectSelected: false,
            currentSelectedProjectID: swft.id,
            remainingProjects: [broken, studio]
        )
        #expect(afterSelected == ProjectPostDeleteSelection(selectedProjectID: studio.id, isNoProjectSelected: false))

        // Deleting selected project with no valid projects left clears selection so Home falls back cleanly.
        let afterLastValid = ProjectDeletionLogic.nextSelectionAfterDeleting(
            deletedProjectID: studio.id,
            wasSelected: true,
            wasNoProjectSelected: false,
            currentSelectedProjectID: studio.id,
            remainingProjects: [broken]
        )
        #expect(afterLastValid == ProjectPostDeleteSelection(selectedProjectID: nil, isNoProjectSelected: false))

        // Deleting a non-selected project preserves the currently selected project.
        let afterNonSelected = ProjectDeletionLogic.nextSelectionAfterDeleting(
            deletedProjectID: studio.id,
            wasSelected: false,
            wasNoProjectSelected: false,
            currentSelectedProjectID: swft.id,
            remainingProjects: [swft]
        )
        #expect(afterNonSelected == ProjectPostDeleteSelection(selectedProjectID: swft.id, isNoProjectSelected: false))

        // Deleting a project while explicitly in "No project" mode preserves "No project".
        let whileNoProject = ProjectDeletionLogic.nextSelectionAfterDeleting(
            deletedProjectID: swft.id,
            wasSelected: false,
            wasNoProjectSelected: true,
            currentSelectedProjectID: nil,
            remainingProjects: [studio]
        )
        #expect(whileNoProject == ProjectPostDeleteSelection(selectedProjectID: nil, isNoProjectSelected: true))
    }

    @Test func confirmationCopyReflectsThreadsMissingFoldersAndDiskSafety() {
        let emptyCopy = ProjectDeletionLogic.confirmation(
            for: swft,
            threadCounts: ProjectThreadCounts(listed: 0, archived: 0)
        )
        #expect(emptyCopy.title == "Remove “Swft”?")
        #expect(emptyCopy.confirmLabel == "Remove")
        #expect(emptyCopy.message.contains("Your files on disk will not be deleted."))

        let oneThreadCopy = ProjectDeletionLogic.confirmation(
            for: swft,
            threadCounts: ProjectThreadCounts(listed: 1, archived: 0)
        )
        #expect(oneThreadCopy.message.contains("1 thread"))
        #expect(!oneThreadCopy.message.contains("1 threads"))
        #expect(oneThreadCopy.message.contains("Your files on disk will not be deleted."))

        let manyAndArchivedCopy = ProjectDeletionLogic.confirmation(
            for: swft,
            threadCounts: ProjectThreadCounts(listed: 3, archived: 2)
        )
        #expect(manyAndArchivedCopy.message.contains("3 threads"))
        #expect(manyAndArchivedCopy.message.contains("2 archived threads"))
        #expect(manyAndArchivedCopy.message.contains("Your files on disk will not be deleted."))

        let missingCopy = ProjectDeletionLogic.confirmation(
            for: broken,
            threadCounts: ProjectThreadCounts(listed: 0, archived: 0)
        )
        #expect(missingCopy.message.contains("no longer exists on disk"))
        #expect(missingCopy.message.contains("No files on disk will be deleted."))
    }

    @Test func displayPathAbbreviatesOnlyLocalHomeDirectoryAndClampsPanelOffset() {
        #expect(ProjectDeletionLogic.displayPath("/Users/jim/code/swft", homeDirectory: "/Users/jim", isLocal: true) == "~/code/swft")
        #expect(ProjectDeletionLogic.displayPath("/Users/jim", homeDirectory: "/Users/jim/", isLocal: true) == "~")
        // Sibling prefix must never be mangled into "~my/code".
        #expect(ProjectDeletionLogic.displayPath("/Users/jimmy/code", homeDirectory: "/Users/jim", isLocal: true) == "/Users/jimmy/code")
        // Remote paths are left untouched.
        #expect(ProjectDeletionLogic.displayPath("/Users/jim/code/swft", homeDirectory: "/Users/jim", isLocal: false) == "/Users/jim/code/swft")

        // Popover leading offset aligns with trigger and clamps within composer bounds.
        let composer = CGRect(x: 100, y: 200, width: 744, height: 95)
        #expect(
            ProjectDeletionLogic.panelLeadingOffset(
                triggerFrame: CGRect(x: 146, y: 250, width: 80, height: 30),
                composerFrame: composer,
                panelWidth: 312
            ) == 46
        )
        #expect(
            ProjectDeletionLogic.panelLeadingOffset(
                triggerFrame: CGRect(x: 700, y: 250, width: 80, height: 30),
                composerFrame: composer,
                panelWidth: 312
            ) == 432
        )
    }

    // MARK: - AppModel Mock Mode

    @Test @MainActor func mockAppModelDeletesSelectedNonSelectedAndLastProjectCleanly() async {
        let model = AppModel.mock()
        #expect(model.selectedProject?.id == MockData.swft.id)
        model.actionError = "Stale workspace error"

        // Deleting a non-selected project preserves the selected project and removes that project's threads.
        let initialStudioThreads = model.projectThreadCounts(for: MockData.studio).listed
        #expect(initialStudioThreads > 0)
        let err1 = await model.deleteProject(MockData.studio)
        #expect(err1 == nil)
        #expect(model.actionError == nil)
        #expect(!model.projects.contains(where: { $0.id == MockData.studio.id }))
        #expect(model.selectedProject?.id == MockData.swft.id)
        #expect(model.projectThreadCounts(for: MockData.studio).listed == 0)

        // Open a thread in Swft, then delete Swft -> detaches thread back to Home and advances to next project.
        model.open("t1")
        #expect(model.selectedThreadID == "t1")
        let err2 = await model.deleteProject(MockData.swft)
        #expect(err2 == nil)
        #expect(model.destination == .home)
        #expect(!model.projects.contains(where: { $0.id == MockData.swft.id }))
        #expect(model.selectedProject?.id == MockData.api.id)

        // Delete remaining projects -> falls back cleanly to "No project".
        for remaining in model.projects {
            let err = await model.deleteProject(remaining)
            #expect(err == nil)
        }
        #expect(model.projects.isEmpty)
        #expect(model.selectedProject == nil)
        #expect(model.composerProjectChipState(contextLabel: model.composer.contextLabel) == .noProject("No project"))
    }

    @Test @MainActor func pickerTogglingIsMutuallyExclusiveAndClosesOnNavigation() {
        let model = AppModel.mock()
        #expect(!model.isProjectPickerOpen)
        #expect(model.modelPicker == nil)

        model.toggleProjectPicker()
        #expect(model.isProjectPickerOpen)

        // Opening model picker closes project picker.
        model.toggleModelPicker()
        #expect(model.modelPicker != nil)
        #expect(!model.isProjectPickerOpen)

        // Opening project picker closes model picker.
        model.toggleProjectPicker()
        #expect(model.isProjectPickerOpen)
        #expect(model.modelPicker == nil)

        // Switching destination closes project picker.
        model.destination = .projects
        #expect(!model.isProjectPickerOpen)

        model.destination = .home
        model.toggleProjectPicker()
        #expect(model.isProjectPickerOpen)
        model.clearProject()
        #expect(!model.isProjectPickerOpen)
    }

    // MARK: - Live-Mode Routing & Disk Recovery

    @Test @MainActor func liveAppModelSkipsMissingLocalFolderAndRoutesLocalVsRemoteDeletes() async throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("swft-live-proj-\(UUID().uuidString)", isDirectory: true)
        let healthyDir = tempRoot.appendingPathComponent("healthy-repo", isDirectory: true)
        let missingDir = tempRoot.appendingPathComponent("deleted-repo", isDirectory: true)
        try fm.createDirectory(at: healthyDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let localDescriptor = ExecutionEnvironmentDescriptor(
            environmentId: "env-local",
            label: "This Mac",
            platform: ExecutionEnvironmentPlatform(os: "darwin", arch: "arm64", machine: "laptop"),
            serverVersion: "0.1.11"
        )
        let localConn = ServerConnection(
            httpBaseURL: URL(string: "http://127.0.0.1:3773")!,
            credential: .bootstrapToken("local")
        )
        let localStore = ThreadsStore(connection: localConn)
        localStore.applyConnectionState(.connected(localDescriptor))
        localStore.apply(.snapshot(ServerConfig(
            environment: localDescriptor,
            auth: ServerAuthDescriptor(policy: "local", bootstrapMethods: [], sessionMethods: [], sessionCookieName: "s"),
            cwd: healthyDir.path,
            providers: [],
            scratchWorkspaceRoot: "/tmp/swft-scratch"
        )))

        let brokenShell = ProjectShell(
            id: "p-local-broken",
            title: "Old Scratch",
            workspaceRoot: missingDir.path,
            createdAt: now,
            updatedAt: now
        )
        let healthyShell = ProjectShell(
            id: "p-local-healthy",
            title: "Healthy Repo",
            workspaceRoot: healthyDir.path,
            createdAt: now,
            updatedAt: now
        )
        let brokenThread = ThreadShell(
            id: "t-broken-1",
            projectId: "p-local-broken",
            title: "Failed start",
            providerInstanceId: "claudeAgent",
            modelSelection: ModelSelection(instanceId: "claudeAgent", model: "opus"),
            createdAt: now,
            updatedAt: now
        )
        localStore.apply(.snapshot(
            ShellSnapshot(snapshotSequence: 1, projects: [brokenShell, healthyShell], threads: [brokenThread]),
            resolvedRepositoryIdentityRoots: nil
        ))

        let model = AppModel.testingLive(localStore: localStore)
        let localEndpoint = ServerEndpoint(
            httpBaseURL: URL(string: "http://127.0.0.1:3773")!,
            wsBaseURL: URL(string: "ws://127.0.0.1:3773/ws")!,
            port: 3773,
            bootstrapToken: "local",
            pid: 1,
            baseDirectory: tempRoot,
            environment: localDescriptor
        )
        model.registerLocalEnvironment(endpoint: localEndpoint, connection: localConn, store: localStore)

        // Verify local missing-folder detection & auto-selection skipping.
        let localProjects = model.projects
        #expect(localProjects.count == 2)
        #expect(localProjects[0].id == "p-local-broken")
        #expect(localProjects[0].isWorkspaceMissing == true)
        #expect(localProjects[1].id == "p-local-healthy")
        #expect(localProjects[1].isWorkspaceMissing == false)

        // On launch (selectedProjectID == nil), Swft skips the broken first project and selects Healthy Repo!
        #expect(model.selectedProject?.id == "p-local-healthy")

        // Attempting to explicitly select the missing project fails gracefully with an informative actionError.
        #expect(!model.selectProject("p-local-broken"))
        #expect(model.actionError?.contains("no longer exists on disk") == true)
        #expect(model.selectedProject?.id == "p-local-healthy")

        // Deleting the broken project routes `project.delete` (force: true) to localStore and clears stale actionError.
        var deletedLocalIDs: [String] = []
        localStore.projectMutationOverride = { _, mutation in
            if case .delete(_, let projectId, let force) = mutation {
                #expect(force == true)
                deletedLocalIDs.append(projectId)
                return ProjectShell(id: projectId, title: "Old Scratch", workspaceRoot: missingDir.path, createdAt: now, updatedAt: now, deletedAt: now)
            }
            throw RPCError.protocolError("unexpected mutation")
        }

        let brokenRef = try #require(localProjects.first(where: { $0.id == "p-local-broken" }))
        #expect(model.projectThreadCounts(for: brokenRef).listed == 1)

        let localDeleteError = await model.deleteProject(brokenRef)
        #expect(localDeleteError == nil)
        #expect(deletedLocalIDs == ["p-local-broken"])
        #expect(model.actionError == nil)
        #expect(model.projects.map(\.id) == ["p-local-healthy"])
        #expect(model.selectedProject?.id == "p-local-healthy")

        // If the healthy folder is later removed on disk and refreshed, Swft falls back to "No project" cleanly.
        try fm.removeItem(at: healthyDir)
        model.refreshLocalProjectAvailability()
        #expect(model.projects.first?.isWorkspaceMissing == true)
        #expect(model.selectedProject == nil)
        #expect(model.composerProjectChipState(contextLabel: model.composer.contextLabel) == .noProject("No project"))
    }

    @Test @MainActor func liveMultiEnvironmentDeleteRoutesToRemoteStoreAndNeverMarksRemotePathsMissing() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let localDescriptor = ExecutionEnvironmentDescriptor(
            environmentId: "env-local",
            label: "This Mac",
            platform: ExecutionEnvironmentPlatform(os: "darwin", arch: "arm64", machine: "laptop"),
            serverVersion: "0.1.11"
        )
        let remoteDescriptor = ExecutionEnvironmentDescriptor(
            environmentId: "env-remote-box",
            label: "Linux Box",
            platform: ExecutionEnvironmentPlatform(os: "linux", arch: "x64", machine: "server"),
            serverVersion: "0.1.11"
        )

        let localConn = ServerConnection(httpBaseURL: URL(string: "http://127.0.0.1:3773")!, credential: .bootstrapToken("local"))
        let localStore = ThreadsStore(connection: localConn)
        localStore.applyConnectionState(.connected(localDescriptor))

        let remoteConn = ServerConnection(httpBaseURL: URL(string: "https://linux.example.com")!, credential: .bearerToken("remote"))
        let remoteStore = ThreadsStore(connection: remoteConn)
        remoteStore.applyConnectionState(.connected(remoteDescriptor))

        let remoteProject1 = ProjectShell(
            id: "p-remote-1",
            title: "Inference",
            workspaceRoot: "/srv/nonexistent-on-mac/inference",
            createdAt: now,
            updatedAt: now
        )
        let remoteProject2 = ProjectShell(
            id: "p-remote-2",
            title: "Trainer",
            workspaceRoot: "/srv/nonexistent-on-mac/trainer",
            createdAt: now,
            updatedAt: now
        )
        remoteStore.apply(.snapshot(
            ShellSnapshot(snapshotSequence: 1, projects: [remoteProject1, remoteProject2], threads: []),
            resolvedRepositoryIdentityRoots: nil
        ))

        let model = AppModel.testingLive(localStore: localStore)
        model.registerLocalEnvironment(
            endpoint: ServerEndpoint(
                httpBaseURL: URL(string: "http://127.0.0.1:3773")!,
                wsBaseURL: URL(string: "ws://127.0.0.1:3773/ws")!,
                port: 3773,
                bootstrapToken: "local",
                pid: 1,
                baseDirectory: FileManager.default.temporaryDirectory,
                environment: localDescriptor
            ),
            connection: localConn,
            store: localStore
        )

        // Inject the connected remote environment into the ephemeral registry for routing verification.
        let remoteEntry = ManagedEnvironment(
            id: remoteDescriptor.environmentId,
            isLocal: false,
            httpBaseURL: URL(string: "https://linux.example.com")!,
            connection: remoteConn,
            threadsStore: remoteStore,
            lastKnownLabel: "Linux Box",
            lastKnownMachine: "server",
            lastKnownOS: "linux",
            lastKnownServerVersion: "0.1.11"
        )
        model.environmentRegistry.insertEnvironmentForTesting(remoteEntry)

        model.selectEnvironment("env-remote-box")
        #expect(model.activeComposerEnvironmentID == "env-remote-box")
        #expect(model.projects.count == 2)
        // Remote paths must NEVER be marked missing by local FileManager checks!
        #expect(model.projects.allSatisfy { !$0.isWorkspaceMissing })
        #expect(model.selectedProject?.id == "p-remote-1")

        var localCalls = 0
        var remoteDeletedIDs: [String] = []
        localStore.projectMutationOverride = { _, _ in
            localCalls += 1
            throw RPCError.protocolError("local should not be called")
        }
        remoteStore.projectMutationOverride = { _, mutation in
            if case .delete(_, let projectId, let force) = mutation {
                #expect(force == true)
                remoteDeletedIDs.append(projectId)
                return ProjectShell(id: projectId, title: "Inference", workspaceRoot: remoteProject1.workspaceRoot, createdAt: now, updatedAt: now, deletedAt: now)
            }
            throw RPCError.protocolError("unexpected mutation")
        }

        let target = try #require(model.projects.first(where: { $0.id == "p-remote-1" }))
        let err = await model.deleteProject(target)
        #expect(err == nil)
        #expect(localCalls == 0)
        #expect(remoteDeletedIDs == ["p-remote-1"])
        #expect(model.projects.map(\.id) == ["p-remote-2"])
        #expect(model.selectedProject?.id == "p-remote-2")

        // When remote disconnects, attempting to delete fails cleanly without calling the RPC.
        remoteStore.applyConnectionState(.disconnected)
        let nextTarget = try #require(model.projects.first(where: { $0.id == "p-remote-2" }))
        let offlineError = await model.deleteProject(nextTarget)
        #expect(offlineError?.contains("Connect to Linux Box") == true)
        #expect(remoteDeletedIDs == ["p-remote-1"])
        #expect(model.projects.map(\.id) == ["p-remote-2"])
    }

    @Test @MainActor func externalProjectRemovedPushRecoversSelectedProjectImmediately() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("swft-push-del-\(UUID().uuidString)", isDirectory: true)
        let dirA = tempRoot.appendingPathComponent("repo-a", isDirectory: true)
        let dirB = tempRoot.appendingPathComponent("repo-b", isDirectory: true)
        try fm.createDirectory(at: dirA, withIntermediateDirectories: true)
        try fm.createDirectory(at: dirB, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let descriptor = ExecutionEnvironmentDescriptor(
            environmentId: "env-local",
            label: "This Mac",
            platform: ExecutionEnvironmentPlatform(os: "darwin", arch: "arm64", machine: "laptop"),
            serverVersion: "0.1.11"
        )
        let conn = ServerConnection(httpBaseURL: URL(string: "http://127.0.0.1:3773")!, credential: .bootstrapToken("local"))
        let store = ThreadsStore(connection: conn)
        store.applyConnectionState(.connected(descriptor))
        store.apply(.snapshot(
            ShellSnapshot(
                snapshotSequence: 1,
                projects: [
                    ProjectShell(id: "p-a", title: "Repo A", workspaceRoot: dirA.path, createdAt: now, updatedAt: now),
                    ProjectShell(id: "p-b", title: "Repo B", workspaceRoot: dirB.path, createdAt: now, updatedAt: now),
                ],
                threads: []
            ),
            resolvedRepositoryIdentityRoots: nil
        ))

        let model = AppModel.testingLive(localStore: store)
        #expect(model.selectProject("p-a"))
        #expect(model.selectedProject?.id == "p-a")

        // Another client deletes Repo A -> server pushes project.removed -> selection recovers to Repo B.
        store.apply(.projectRemoved(sequence: 2, projectId: "p-a"))
        #expect(model.projects.map(\.id) == ["p-b"])
        #expect(model.selectedProject?.id == "p-b")

        // Removing the last remaining project recovers cleanly to nil ("No project").
        store.apply(.projectRemoved(sequence: 3, projectId: "p-b"))
        #expect(model.projects.isEmpty)
        #expect(model.selectedProject == nil)
    }
}
