import Foundation
import Testing
@testable import SwftKit

@Suite("Scratch Project Matching & RPC")
struct ScratchProjectTests {
    private static var isIntegrationDisabled: Bool {
        let value = ProcessInfo.processInfo.environment["SWFT_SKIP_INTEGRATION_TESTS"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return value == "1" || value == "true" || value == "yes"
    }

    @Test func normalizesPathsMatchingSharedComparisonRules() {
        #expect(ScratchProjectMatcher.normalizePathForComparison("/Users/dev/Swft/scratch/") == "/Users/dev/Swft/scratch")
        #expect(ScratchProjectMatcher.normalizePathForComparison("  /Users/dev/Swft/scratch///  ") == "/Users/dev/Swft/scratch")
        #expect(ScratchProjectMatcher.normalizePathForComparison("/") == "/")
        #expect(ScratchProjectMatcher.normalizePathForComparison("C:/Users/Dev/Scratch/") == "c:\\users\\dev\\scratch")
        #expect(ScratchProjectMatcher.normalizePathForComparison("C:") == "c:\\")
        #expect(ScratchProjectMatcher.normalizePathForComparison("C:/") == "c:\\")
        #expect(ScratchProjectMatcher.normalizePathForComparison("\\\\Server\\Share\\Scratch\\") == "\\\\server\\share\\scratch")
    }

    @Test func identifiesScratchProjectsByWorkspaceRoot() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let scratchRoot = "/Users/dev/Library/Application Support/Swft/userdata/scratch"
        let scratchProject = ProjectShell(
            id: "proj-scratch",
            title: "No project",
            workspaceRoot: "\(scratchRoot)/",
            createdAt: now,
            updatedAt: now
        )
        let renamedScratch = ProjectShell(
            id: "proj-scratch-renamed",
            title: "Sandbox",
            workspaceRoot: scratchRoot,
            createdAt: now,
            updatedAt: now
        )
        let realProjectNamedNoProject = ProjectShell(
            id: "proj-real",
            title: "No project",
            workspaceRoot: "/Users/dev/code/no-project",
            createdAt: now,
            updatedAt: now
        )

        #expect(scratchProject.isScratch(in: scratchRoot))
        #expect(renamedScratch.isScratch(in: scratchRoot))
        #expect(!realProjectNamedNoProject.isScratch(in: scratchRoot))
        #expect(!scratchProject.isScratch(in: nil))
        #expect(!scratchProject.isScratch(in: "   "))
    }

    @Test func decodesEnsureScratchResultAndMethodTag() throws {
        #expect(RPCMethod.projectsEnsureScratch == "projects.ensureScratch")
        let data = Data(#"{"projectId":"proj-scratch-123"}"#.utf8)
        let decoded = try SwftJSON.makeDecoder().decode(ProjectEnsureScratchResult.self, from: data)
        #expect(decoded == ProjectEnsureScratchResult(projectId: "proj-scratch-123"))
    }

    @Test @MainActor func threadsStoreExposesScratchProjectFromConfigAndSnapshot() {
        let connection = ServerConnection(
            httpBaseURL: URL(string: "http://127.0.0.1:1")!,
            credential: .bootstrapToken("test")
        )
        let store = ThreadsStore(connection: connection)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let scratchRoot = "/tmp/swft-scratch-test/userdata/scratch"

        let env = ExecutionEnvironmentDescriptor(
            environmentId: "env-1",
            label: "MacBook Pro",
            platform: ExecutionEnvironmentPlatform(os: "darwin", arch: "arm64"),
            serverVersion: "0.1.11"
        )
        let config = ServerConfig(
            environment: env,
            auth: ServerAuthDescriptor(policy: "local", bootstrapMethods: [], sessionMethods: [], sessionCookieName: "s"),
            cwd: "/tmp",
            providers: [],
            scratchWorkspaceRoot: scratchRoot
        )
        let scratchProject = ProjectShell(
            id: "proj-scratch",
            title: "No project",
            workspaceRoot: scratchRoot,
            projectIcon: .lucide(name: "message-square-dashed", color: "gray"),
            createdAt: now,
            updatedAt: now
        )
        let realProject = ProjectShell(
            id: "proj-swft",
            title: "Swft",
            workspaceRoot: "/Users/dev/swft",
            createdAt: now,
            updatedAt: now
        )

        store.apply(.snapshot(config))
        store.apply(.snapshot(
            ShellSnapshot(snapshotSequence: 1, projects: [scratchProject, realProject], threads: []),
            resolvedRepositoryIdentityRoots: nil
        ))

        // Disconnected store reports no available scratch root until connected, while still recognizing the scratch project.
        #expect(store.availableScratchWorkspaceRoot == nil)
        #expect(store.scratchProject?.id == "proj-scratch")
        #expect(store.isScratchProject(scratchProject))
        #expect(!store.isScratchProject(realProject))
    }

    @Test(
        "Ensures scratch project and launches a project-less thread with a per-thread scratch folder",
        .disabled(if: ScratchProjectTests.isIntegrationDisabled, "Skipped via SWFT_SKIP_INTEGRATION_TESTS")
    )
    func ensuresScratchProjectAndLaunchesThreadAgainstLocalServer() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swftkit-scratch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let serverProcess = ServerProcess(
            configuration: ServerLaunchConfiguration(
                baseDirectory: tempDir,
                readinessTimeout: .seconds(25)
            )
        )
        let endpoint = try await serverProcess.start()
        let connection = ServerConnection(
            httpBaseURL: endpoint.httpBaseURL,
            credential: .bootstrapToken(endpoint.bootstrapToken),
            clientLabel: "SwftKit Scratch Integration Test"
        )

        do {
            _ = try await connection.connect()
            let config: ServerConfig = try await connection.call(
                tag: RPCMethod.serverGetConfig,
                payload: EmptyPayload()
            )
            let scratchRoot = try #require(config.scratchWorkspaceRoot)
            #expect(!scratchRoot.isEmpty)

            let store = await MainActor.run { ThreadsStore(connection: connection) }
            let first = try await store.ensureScratchProject()
            let second = try await store.ensureScratchProject()
            #expect(!first.projectId.isEmpty)
            #expect(first.projectId == second.projectId)

            let provider = try #require(config.providers.first(where: { $0.enabled && !$0.models.isEmpty }) ?? config.providers.first)
            let modelSlug = try #require(provider.models.first?.slug)

            let launchResult = try await store.launchThread(
                LaunchThreadInput(
                    projectId: first.projectId,
                    title: "Quick scratch question",
                    generateTitle: false,
                    modelSelection: ModelSelection(instanceId: provider.instanceId, model: modelSlug),
                    runtimeMode: .fullAccess,
                    interactionMode: .default,
                    workspaceStrategy: .root()
                )
            )
            #expect(launchResult.projection.thread.projectId == first.projectId)
            #expect(launchResult.projection.thread.branch == nil)

            let threadWorktree = try #require(launchResult.projection.thread.worktreePath)
            let normalizedRoot = ScratchProjectMatcher.normalizePathForComparison(scratchRoot)
            let normalizedWorktree = ScratchProjectMatcher.normalizePathForComparison(threadWorktree)
            #expect(normalizedWorktree.hasPrefix("\(normalizedRoot)/"))
            #expect(FileManager.default.fileExists(atPath: threadWorktree))

            await connection.disconnect()
            await serverProcess.stop()
        } catch {
            await connection.disconnect()
            await serverProcess.stop()
            throw error
        }
    }
}
