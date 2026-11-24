import Foundation
import Testing
@testable import SwftKit

@Suite("Server Process Integration")
struct ServerIntegrationTests {
    private static var isIntegrationDisabled: Bool {
        let value = ProcessInfo.processInfo.environment["SWFT_SKIP_INTEGRATION_TESTS"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return value == "1" || value == "true" || value == "yes"
    }

    @Test(
        "Boots local Node server in temp dir, connects via WebSocket, and lists providers",
        .disabled(if: ServerIntegrationTests.isIntegrationDisabled, "Skipped via SWFT_SKIP_INTEGRATION_TESTS")
    )
    func bootsServerConnectsAndListsProviders() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swftkit-integration-\(UUID().uuidString)", isDirectory: true)
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
        #expect(endpoint.port > 0)
        #expect(endpoint.pid > 0)
        #expect(endpoint.environment.orchestrationProtocolVersion == 2)

        let connection = ServerConnection(
            httpBaseURL: endpoint.httpBaseURL,
            credential: .bootstrapToken(endpoint.bootstrapToken),
            clientLabel: "SwftKit Integration Test"
        )

        do {
            let descriptor = try await connection.connect()
            #expect(descriptor.environmentId == endpoint.environment.environmentId)

            let config: ServerConfig = try await connection.call(
                tag: RPCMethod.serverGetConfig,
                payload: EmptyPayload()
            )
            #expect(config.environment.environmentId == endpoint.environment.environmentId)
            #expect(!config.providers.isEmpty)

            // Verify streaming subscription + Ack flow control delivers both snapshot and synchronized chunks.
            let shellStream: AsyncThrowingStream<ShellStreamItem, any Error> = connection.subscribe(
                tag: RPCMethod.orchestrationSubscribeShell,
                payload: SubscribeShellInput(requestCompletionMarker: true)
            )
            var sawSnapshot = false
            var sawSynchronized = false
            for try await item in shellStream {
                switch item {
                case .snapshot:
                    sawSnapshot = true
                case .synchronized:
                    sawSynchronized = true
                default:
                    break
                }
                if sawSnapshot && sawSynchronized {
                    break
                }
            }
            #expect(sawSnapshot)
            #expect(sawSynchronized)

            // Verify project creation, thread creation, and ThreadStore subscription end-to-end.
            let workspaceDir = tempDir.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceDir, withIntermediateDirectories: true)

            let threadsStore = await MainActor.run { ThreadsStore(connection: connection) }
            let project = try await threadsStore.createProject(
                title: "Swft Test Project",
                workspaceRoot: workspaceDir.path
            )
            #expect(project.title == "Swft Test Project")

            let providerId = config.providers.first?.instanceId ?? "codex"
            let modelSlug = config.providers.first?.models.first?.slug ?? "gpt-6-astra"
            let threadId = try await threadsStore.createThread(
                projectId: project.id,
                title: "Integration thread",
                modelSelection: ModelSelection(instanceId: providerId, model: modelSlug)
            )

            let threadStream: AsyncThrowingStream<ThreadStreamItem, any Error> = connection.subscribe(
                tag: RPCMethod.orchestrationSubscribeThread,
                payload: SubscribeThreadInput(threadId: threadId, requestCompletionMarker: true)
            )
            var loadedThreadTitle: String?
            for try await item in threadStream {
                if case .snapshot(_, let projection) = item {
                    loadedThreadTitle = projection.thread.title
                    break
                }
            }
            #expect(loadedThreadTitle == "Integration thread")

            await connection.disconnect()
            await serverProcess.stop()
            #expect(await serverProcess.isRunning == false)
        } catch {
            await connection.disconnect()
            await serverProcess.stop()
            throw error
        }
    }
}
