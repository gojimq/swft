import Foundation

// MARK: - Side Chat & Thread Projection RPC Helpers

public enum ThreadForkSourcePoint: Encodable, Sendable, Equatable {
    case latestStable
    case run(runId: String)
    case checkpoint(checkpointId: String)

    private enum CodingKeys: String, CodingKey {
        case type, runId, checkpointId
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .latestStable:
            try c.encode("latest_stable", forKey: .type)
        case .run(let runId):
            try c.encode("run", forKey: .type)
            try c.encode(runId, forKey: .runId)
        case .checkpoint(let checkpointId):
            try c.encode("checkpoint", forKey: .type)
            try c.encode(checkpointId, forKey: .checkpointId)
        }
    }
}

public struct GetThreadProjectionInput: Encodable, Sendable, Equatable {
    public let threadId: String

    public init(threadId: String) {
        self.threadId = threadId
    }
}

public extension ServerConnection {
    /// Forks `sourceThreadId` at its latest stable point into a hidden side chat (`lineage.sideChat == true`).
    @discardableResult
    func forkSideChat(
        sourceThreadId: String,
        targetThreadId: String = UUID().uuidString,
        title: String = "Side chat"
    ) async throws -> String {
        let _: DispatchCommandResult = try await call(
            tag: RPCMethod.orchestrationDispatchCommand,
            payload: OrchestrationCommand.forkThread(
                sourceThreadId: sourceThreadId,
                targetThreadId: targetThreadId,
                sourcePoint: .latestStable,
                title: title,
                sideChat: true
            )
        )
        return targetThreadId
    }

    func getThreadProjection(threadId: String) async throws -> ThreadProjection {
        try await call(
            tag: RPCMethod.orchestrationGetThreadProjection,
            payload: GetThreadProjectionInput(threadId: threadId)
        )
    }
}

public extension ThreadsStore {
    /// Forks the active thread's latest stable point into a side chat thread and returns its new ID.
    @discardableResult
    func forkSideChat(
        sourceThreadId: String,
        targetThreadId: String = UUID().uuidString,
        title: String = "Side chat"
    ) async throws -> String {
        try await connection.forkSideChat(
            sourceThreadId: sourceThreadId,
            targetThreadId: targetThreadId,
            title: title
        )
    }

    /// Deletes a side chat thread (pass `onlyIfUnused: true` when closing an untouched side chat).
    func deleteSideChat(threadId: String, onlyIfUnused: Bool = false) async throws {
        let _: DispatchCommandResult = try await connection.call(
            tag: RPCMethod.orchestrationDispatchCommand,
            payload: OrchestrationCommand.deleteThread(
                threadId: threadId,
                onlyIfUnused: onlyIfUnused ? true : nil
            )
        )
    }
}
