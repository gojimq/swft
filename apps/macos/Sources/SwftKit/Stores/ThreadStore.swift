import Foundation
import Observation

/// Observable store for a single open thread: streams turn/message/tool-call/approval events
/// and dispatches message, interrupt, mode, and approval commands.
@MainActor
@Observable
public final class ThreadStore {
    public let connection: ServerConnection
    public let threadId: String

    public private(set) var projection: ThreadProjection?
    /// Monotonic counter incremented whenever `projection` changes, enabling O(1) memoization in UI adapters.
    public private(set) var projectionVersion: UInt64 = 0
    public private(set) var isSynchronized: Bool = false
    public private(set) var lastSequence: Int?
    public private(set) var lastError: String?

    private var stateMonitorTask: Task<Void, Never>?
    private var subscriptionTask: Task<Void, Never>?

    public init(
        connection: ServerConnection,
        threadId: String,
        initialProjection: ThreadProjection? = nil
    ) {
        self.connection = connection
        self.threadId = threadId
        self.projection = initialProjection
    }

    // MARK: - Derived State

    public var thread: AppThread? { projection?.thread }
    public var visibleItems: [ProjectedTurnItem] { projection?.visibleTurnItems ?? [] }
    public var runs: [Run] { projection?.runs ?? [] }
    public var subagents: [SubagentSummary] { projection?.subagents ?? [] }
    public var messages: [ConversationMessage] { projection?.messages ?? [] }
    public var plans: [PlanArtifact] { projection?.plans ?? [] }

    public var activeRun: Run? {
        runs.last { $0.status.isActive }
    }

    public var isRunning: Bool {
        activeRun != nil
    }

    public var pendingRuntimeRequests: [RuntimeRequest] {
        (projection?.runtimeRequests ?? []).filter(\.isPending)
    }

    public var pendingApprovals: [RuntimeRequest] {
        pendingRuntimeRequests.filter(\.isApproval)
    }

    public var pendingUserInputs: [RuntimeRequest] {
        pendingRuntimeRequests.filter(\.isUserInput)
    }

    // MARK: - Lifecycle

    public func start() {
        guard stateMonitorTask == nil else { return }
        stateMonitorTask = Task { [weak self] in
            guard let self else { return }
            let updates = await connection.stateUpdates()
            for await state in updates {
                guard !Task.isCancelled else { break }
                switch state {
                case .connected:
                    self.lastError = nil
                    self.startSubscription()
                case .disconnected:
                    self.stopSubscription()
                    self.isSynchronized = false
                case .reconnecting(_, let reason):
                    self.stopSubscription()
                    self.isSynchronized = false
                    self.lastError = reason
                case .failed(let reason):
                    self.stopSubscription()
                    self.isSynchronized = false
                    self.lastError = reason
                case .connecting:
                    break
                }
            }
        }
    }

    public func stop() {
        stateMonitorTask?.cancel()
        stateMonitorTask = nil
        stopSubscription()
    }

    private func startSubscription() {
        stopSubscription()
        let resumeSequence = lastSequence
        subscriptionTask = Task { [weak self] in
            guard let self else { return }
            let stream: AsyncThrowingStream<ThreadStreamItem, any Error> =
                connection.subscribe(
                    tag: RPCMethod.orchestrationSubscribeThread,
                    payload: SubscribeThreadInput(
                        threadId: threadId,
                        afterSequence: resumeSequence,
                        requestCompletionMarker: true
                    )
                )
            do {
                for try await item in stream {
                    guard !Task.isCancelled else { break }
                    self.apply(item)
                }
            } catch {
                if !Task.isCancelled {
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    private func stopSubscription() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
    }

    // MARK: - Reducer (mirrors orchestrationV2Projection.ts + orchestrationV2Timeline.ts)

    internal func apply(_ item: ThreadStreamItem) {
        switch item {
        case .snapshot(let snapshotSequence, var nextProjection):
            if !nextProjection.subagents.isEmpty {
                for index in nextProjection.turnItems.indices {
                    nextProjection.turnItems[index] = hydrateSubagentBodies(nextProjection.turnItems[index], in: nextProjection)
                }
                for index in nextProjection.visibleTurnItems.indices {
                    let hydrated = hydrateSubagentBodies(nextProjection.visibleTurnItems[index].item, in: nextProjection)
                    if hydrated != nextProjection.visibleTurnItems[index].item {
                        let existing = nextProjection.visibleTurnItems[index]
                        nextProjection.visibleTurnItems[index] = ProjectedTurnItem(
                            position: existing.position,
                            visibility: existing.visibility,
                            sourceThreadId: existing.sourceThreadId,
                            sourceItemId: existing.sourceItemId,
                            item: hydrated
                        )
                    }
                }
            }
            projection = nextProjection
            projectionVersion &+= 1
            lastSequence = snapshotSequence

        case .synchronized:
            isSynchronized = true

        case .event(let sequence, let event):
            if let lastSequence, sequence <= lastSequence { return }
            applyEvent(event)
            lastSequence = sequence

        case .unknownEvent(let sequence, _):
            if let lastSequence, sequence <= lastSequence { return }
            lastSequence = sequence

        case .unknown:
            break
        }
    }

    private func applyEvent(_ event: DomainEvent) {
        guard var current = projection, event.threadId == current.thread.id else { return }

        switch event.kind {
        case .threadUpdated(let updatedThread, let updatesActivityTimestamp):
            current.thread = updatedThread
            if updatesActivityTimestamp {
                current.updatedAt = event.occurredAt
            }

        case .threadVisitRecorded(let visit):
            current.thread.lastVisitedAt = visit.lastVisitedAt

        case .runUpserted(var run):
            let previous = current.runs.first { $0.id == run.id }
            // Preserve previously-submitted run output when lifecycle updates omit it.
            if run.output == nil, let existingOutput = previous?.output {
                run.output = existingOutput
            }
            upsert(run, into: &current.runs)
            current.updatedAt = event.occurredAt
            pruneHiddenVisibleItems(&current)
            if previous?.status == .queued && run.status != .queued {
                restoreQueuedUserItems(forRunId: run.id, in: &current)
            }

        case .runOutputSubmitted(let runId, let output):
            if let index = current.runs.firstIndex(where: { $0.id == runId }) {
                current.runs[index].output = output
            }
            current.updatedAt = event.occurredAt

        case .runAttemptUpserted(let attempt):
            upsert(attempt, into: &current.attempts)
            current.updatedAt = event.occurredAt
            pruneHiddenVisibleItems(&current)

        case .subagentUpdated(let subagent):
            let previous = current.subagents.first { $0.id == subagent.id }
            upsert(subagent.restoringDedupedBodies(from: previous), into: &current.subagents)
            current.updatedAt = event.occurredAt

        case .providerThreadUpdated(let providerThread):
            if providerThread.appThreadId == current.thread.id && !providerThread.isQueuedPlaceholder {
                current.thread.activeProviderThreadId = providerThread.id
            }
            upsert(providerThread, into: &current.providerThreads)
            current.updatedAt = event.occurredAt

        case .runtimeRequestUpdated(let request):
            upsert(request, into: &current.runtimeRequests)
            current.updatedAt = event.occurredAt

        case .messageUpdated(let message):
            upsert(message, into: &current.messages)
            current.updatedAt = event.occurredAt

        case .planUpdated(let plan):
            upsert(plan, into: &current.plans)
            current.updatedAt = event.occurredAt

        case .turnItemUpdated(let rawItem):
            let item = hydrateSubagentBodies(rawItem, in: current)
            upsertFromEnd(item, into: &current.turnItems)
            current.updatedAt = event.occurredAt
            if isItemVisible(item, in: current) {
                upsertVisibleItem(item, into: &current.visibleTurnItems)
            } else {
                removeVisibleItem(sourceItemId: item.id, from: &current.visibleTurnItems)
            }

        case .ignored:
            current.updatedAt = event.occurredAt
        }

        projection = current
        projectionVersion &+= 1
    }

    private func hydrateSubagentBodies(_ item: TurnItem, in projection: ThreadProjection) -> TurnItem {
        guard case .subagent(
            let subagentId,
            let origin,
            let driver,
            let providerInstanceId,
            let childThreadId,
            let remoteChild,
            let prompt,
            let progress,
            let result,
            let promptOmitted,
            let resultOmitted
        ) = item.kind, promptOmitted || resultOmitted else {
            return item
        }
        let subagent = projection.subagents.first { $0.id == subagentId }
        let previousItem = projection.turnItems.last { $0.id == item.id }
        let previousPrompt: String?
        let previousResult: String?
        if case .subagent(_, _, _, _, _, _, let prevPrompt, _, let prevResult, _, _) = previousItem?.kind {
            previousPrompt = prevPrompt
            previousResult = prevResult
        } else {
            previousPrompt = nil
            previousResult = nil
        }
        let resolvedPrompt = (promptOmitted && prompt.isEmpty)
            ? ((subagent?.prompt.isEmpty == false ? subagent?.prompt : nil) ?? previousPrompt ?? prompt)
            : prompt
        let resolvedResult = (resultOmitted && (result == nil || result?.isEmpty == true))
            ? (subagent?.result ?? previousResult ?? result)
            : result
        return TurnItem(
            id: item.id,
            threadId: item.threadId,
            runId: item.runId,
            nodeId: item.nodeId,
            providerThreadId: item.providerThreadId,
            providerTurnId: item.providerTurnId,
            parentItemId: item.parentItemId,
            ordinal: item.ordinal,
            status: item.status,
            title: item.title,
            startedAt: item.startedAt,
            completedAt: item.completedAt,
            updatedAt: item.updatedAt,
            kind: .subagent(
                subagentId: subagentId,
                origin: origin,
                driver: driver,
                providerInstanceId: providerInstanceId,
                childThreadId: childThreadId,
                remoteChild: remoteChild,
                prompt: resolvedPrompt,
                progress: progress,
                result: resolvedResult,
                promptOmitted: false,
                resultOmitted: false
            )
        )
    }

    private func isItemVisible(_ item: TurnItem, in projection: ThreadProjection) -> Bool {
        if let runId = item.runId {
            if projection.runs.contains(where: { $0.id == runId && $0.status == .rolledBack }) {
                return false
            }
            if case .userMessage(_, _, let inputIntent, _, _, _) = item.kind,
               inputIntent == "queued_turn",
               projection.runs.contains(where: {
                   $0.id == runId && ($0.status == .queued || ($0.status == .cancelled && $0.startedAt == nil))
               })
            {
                return false
            }
            if case .runInterruptResult = item.kind, let nodeId = item.nodeId {
                let isSuperseded = projection.attempts.contains {
                    $0.runId == runId && $0.rootNodeId == nodeId && $0.status == "superseded"
                }
                if isSuperseded {
                    let hasRequest = projection.turnItems.contains {
                        if case .runInterruptRequest = $0.kind {
                            return $0.runId == runId
                        }
                        return false
                    }
                    if !hasRequest { return false }
                }
            }
        }
        return true
    }

    private func pruneHiddenVisibleItems(_ projection: inout ThreadProjection) {
        let snapshot = projection
        let originalCount = projection.visibleTurnItems.count
        projection.visibleTurnItems.removeAll { row in
            row.visibility == .local && !isItemVisible(row.item, in: snapshot)
        }
        if projection.visibleTurnItems.count != originalCount {
            renumber(&projection.visibleTurnItems)
        }
    }

    private func restoreQueuedUserItems(forRunId runId: String, in projection: inout ThreadProjection) {
        for item in projection.turnItems where item.runId == runId {
            guard case .userMessage(_, _, let inputIntent, _, _, _) = item.kind,
                  inputIntent == "queued_turn",
                  isItemVisible(item, in: projection)
            else { continue }
            upsertVisibleItem(item, into: &projection.visibleTurnItems)
        }
    }

    private func upsertVisibleItem(_ item: TurnItem, into rows: inout [ProjectedTurnItem]) {
        if let existingIndex = rows.lastIndex(where: { $0.sourceItemId == item.id }) {
            let previous = rows[existingIndex]
            if previous.visibility == .local
                && previous.sourceThreadId == item.threadId
                && previous.item.ordinal == item.ordinal
            {
                rows[existingIndex] = ProjectedTurnItem(
                    position: previous.position,
                    visibility: .local,
                    sourceThreadId: item.threadId,
                    sourceItemId: item.id,
                    item: item
                )
                return
            }
            rows.remove(at: existingIndex)
        }

        let newRow = ProjectedTurnItem(
            position: 0,
            visibility: .local,
            sourceThreadId: item.threadId,
            sourceItemId: item.id,
            item: item
        )

        let insertionIndex = rows.firstIndex { candidate in
            candidate.visibility == .local
                && (candidate.item.ordinal > item.ordinal
                    || (candidate.item.ordinal == item.ordinal && candidate.item.id > item.id))
        } ?? rows.endIndex
        rows.insert(newRow, at: insertionIndex)
        renumber(&rows)
    }

    private func removeVisibleItem(sourceItemId: String, from rows: inout [ProjectedTurnItem]) {
        guard let index = rows.firstIndex(where: { $0.sourceItemId == sourceItemId }) else { return }
        rows.remove(at: index)
        renumber(&rows)
    }

    private func renumber(_ rows: inout [ProjectedTurnItem]) {
        for idx in rows.indices where rows[idx].position != idx {
            rows[idx].position = idx
        }
    }

    private func upsert<T: Identifiable>(_ item: T, into array: inout [T]) {
        if let index = array.firstIndex(where: { $0.id == item.id }) {
            array[index] = item
        } else {
            array.append(item)
        }
    }

    private func upsertFromEnd<T: Identifiable>(_ item: T, into array: inout [T]) {
        if let index = array.lastIndex(where: { $0.id == item.id }) {
            array[index] = item
        } else {
            array.append(item)
        }
    }

    // MARK: - Actions

    /// Sends a user message, updating thread runtime/interaction modes beforehand if changed.
    @discardableResult
    /// `messageId` is chosen by the caller so an optimistic transcript row can be matched to the server's echo.
    public func sendMessage(
        text: String,
        messageId: String = UUID().uuidString,
        modelSelection: ModelSelection? = nil,
        runtimeMode: RuntimeMode? = nil,
        interactionMode: ProviderInteractionMode? = nil,
        dispatchMode: MessageDispatchMode? = nil,
        deliveryIntent: MessageDeliveryIntent? = .auto,
        attachments: [ChatAttachment] = []
    ) async throws -> DispatchCommandResult {
        if let runtimeMode, runtimeMode != thread?.runtimeMode {
            try await setRuntimeMode(runtimeMode)
        }
        if let interactionMode, interactionMode != thread?.interactionMode {
            try await setInteractionMode(interactionMode)
        }

        let resolvedDispatchMode: MessageDispatchMode
        if let dispatchMode {
            resolvedDispatchMode = dispatchMode
        } else if activeRun != nil {
            resolvedDispatchMode = .queueAfterActive
        } else {
            resolvedDispatchMode = .startImmediately
        }

        return try await connection.call(
            tag: RPCMethod.orchestrationDispatchCommand,
            payload: OrchestrationCommand.dispatchMessage(
                threadId: threadId,
                messageId: messageId,
                text: text,
                attachments: attachments,
                modelSelection: modelSelection,
                deliveryIntent: deliveryIntent,
                dispatchMode: resolvedDispatchMode
            )
        )
    }

    /// Stops the active turn using `thread.stop` when supported, falling back to `run.interrupt`.
    public func interrupt(reason: String? = nil) async throws {
        let supportsThreadStop = await connection.environment?.capabilities.threadStop ?? true
        if supportsThreadStop {
            let _: DispatchCommandResult = try await connection.call(
                tag: RPCMethod.orchestrationDispatchCommand,
                payload: OrchestrationCommand.stopThread(threadId: threadId, reason: reason)
            )
        } else if let runId = activeRun?.id {
            let _: DispatchCommandResult = try await connection.call(
                tag: RPCMethod.orchestrationDispatchCommand,
                payload: OrchestrationCommand.interruptRun(
                    threadId: threadId,
                    runId: runId,
                    reason: reason,
                    holdQueue: true
                )
            )
        }
    }

    @discardableResult
    public func forceStop(runId: String? = nil) async throws -> ForceStopThreadResult {
        try await connection.call(
            tag: RPCMethod.orchestrationForceStopThread,
            payload: ForceStopThreadInput(threadId: threadId, runId: runId ?? activeRun?.id)
        )
    }

    public func respondToApproval(
        requestId: String,
        decision: ProviderApprovalDecision,
        feedback: String? = nil
    ) async throws {
        let _: DispatchCommandResult = try await connection.call(
            tag: RPCMethod.orchestrationDispatchCommand,
            payload: OrchestrationCommand.respondToRuntimeRequest(
                threadId: threadId,
                requestId: requestId,
                decision: decision,
                feedback: feedback
            )
        )
    }

    public func respondToUserInput(
        requestId: String,
        answers: [String: JSONValue]
    ) async throws {
        let _: DispatchCommandResult = try await connection.call(
            tag: RPCMethod.orchestrationDispatchCommand,
            payload: OrchestrationCommand.respondToRuntimeRequest(
                threadId: threadId,
                requestId: requestId,
                answers: answers
            )
        )
    }

    public func setRuntimeMode(_ runtimeMode: RuntimeMode) async throws {
        let _: DispatchCommandResult = try await connection.call(
            tag: RPCMethod.orchestrationDispatchCommand,
            payload: OrchestrationCommand.setRuntimeMode(threadId: threadId, runtimeMode: runtimeMode)
        )
    }

    public func setInteractionMode(_ interactionMode: ProviderInteractionMode) async throws {
        let _: DispatchCommandResult = try await connection.call(
            tag: RPCMethod.orchestrationDispatchCommand,
            payload: OrchestrationCommand.setInteractionMode(
                threadId: threadId,
                interactionMode: interactionMode
            )
        )
    }

    public func setModelSelection(_ modelSelection: ModelSelection) async throws {
        let _: DispatchCommandResult = try await connection.call(
            tag: RPCMethod.orchestrationDispatchCommand,
            payload: OrchestrationCommand.setModelSelection(
                threadId: threadId,
                modelSelection: modelSelection
            )
        )
    }
}
