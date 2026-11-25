import Foundation

/// Optimistic local override while a live `thread.settle` or `thread.unsettle` RPC is in flight.
struct OptimisticSettlement: Equatable, Sendable {
    let isSettled: Bool
    let settledAt: Date?
    let token: UUID

    init(isSettled: Bool, settledAt: Date?, token: UUID = UUID()) {
        self.isSettled = isSettled
        self.settledAt = settledAt
        self.token = token
    }
}

/// Partitioned sidebar thread slices ready for rendering.
struct SettledPartition: Equatable {
    /// Active (non-settled) threads matching the current `ThreadFilter`.
    let active: [ThreadSummary]
    /// All settled threads, sorted by `settledAt ?? updatedAt` descending.
    let settled: [ThreadSummary]
    /// Settled rows to render: all settled threads when expanded, or only the selected settled thread when collapsed.
    let visibleSettled: [ThreadSummary]
}

/// Pure partitioning, sorting, and selection helpers for settled threads.
enum SettledThreadsLogic {
    static let expandedDefaultsKey = "SwftSettledSectionExpanded"

    /// Applies pending optimistic settle/unsettle overrides without hiding canonical server timestamps once synced.
    static func applyOptimisticSettlements(
        to threads: [ThreadSummary],
        overrides: [ThreadSummary.ID: OptimisticSettlement]
    ) -> [ThreadSummary] {
        guard !overrides.isEmpty else { return threads }
        return threads.map { thread in
            guard let override = overrides[thread.id], override.isSettled != thread.isSettled else {
                return thread
            }
            var updated = thread
            updated.isSettled = override.isSettled
            updated.settledAt = override.settledAt
            return updated
        }
    }

    /// Sorts settled threads by `settledAt ?? updatedAt` descending (most recently settled first),
    /// breaking timestamp ties deterministically by ascending thread ID.
    static func sortSettled(_ threads: [ThreadSummary]) -> [ThreadSummary] {
        threads.sorted { lhs, rhs in
            let lDate = lhs.settledAt ?? lhs.updatedAt
            let rDate = rhs.settledAt ?? rhs.updatedAt
            if lDate != rDate { return lDate > rDate }
            return lhs.id < rhs.id
        }
    }

    /// Partitions threads into filtered active threads and sorted settled threads,
    /// keeping the currently selected settled thread visible even when the Settled shelf is collapsed.
    static func partition(
        threads: [ThreadSummary],
        filter: ThreadFilter,
        isSettledExpanded: Bool,
        selectedThreadID: ThreadSummary.ID?
    ) -> SettledPartition {
        var activeCandidates: [ThreadSummary] = []
        var settledCandidates: [ThreadSummary] = []
        activeCandidates.reserveCapacity(threads.count)

        for thread in threads {
            if thread.isSettled {
                settledCandidates.append(thread)
            } else {
                activeCandidates.append(thread)
            }
        }

        let filteredActive = filterActive(activeCandidates, using: filter)
        let sortedSettled = sortSettled(settledCandidates)
        let visibleSettled: [ThreadSummary]
        if isSettledExpanded {
            visibleSettled = sortedSettled
        } else if let selectedThreadID,
                  let selectedSettled = sortedSettled.first(where: { $0.id == selectedThreadID })
        {
            visibleSettled = [selectedSettled]
        } else {
            visibleSettled = []
        }

        return SettledPartition(
            active: filteredActive,
            settled: sortedSettled,
            visibleSettled: visibleSettled
        )
    }

    /// Picks the next active thread to open after settling the currently selected thread,
    /// preferring the thread immediately following it before wrapping earlier in the list.
    static func nextActiveThreadID(
        afterSettling id: ThreadSummary.ID,
        activeThreads: [ThreadSummary]
    ) -> ThreadSummary.ID? {
        guard let index = activeThreads.firstIndex(where: { $0.id == id }) else {
            return activeThreads.first(where: { $0.id != id })?.id
        }
        let after = activeThreads.index(after: index)
        if after < activeThreads.endIndex {
            return activeThreads[after].id
        }
        if index > activeThreads.startIndex {
            return activeThreads[activeThreads.startIndex].id
        }
        return nil
    }

    private static func filterActive(
        _ threads: [ThreadSummary],
        using filter: ThreadFilter
    ) -> [ThreadSummary] {
        switch filter {
        case .all:
            return threads
        case .active:
            return threads.filter { $0.activity == .running || $0.activity == .needsApproval }
        case .needsAttention:
            return threads.filter { $0.activity == .needsApproval || $0.activity == .failed || $0.activity == .unread }
        }
    }
}
