import Foundation
import Observation
import SwiftUI

/// UI state for the main window. Today it is seeded from MockData; the engineering track swaps the
/// seed for SwftKit stores and keeps these view-state shapes.
@MainActor
@Observable
final class AppModel {
    var sidebar: SidebarState
    var home: HomeState
    var composer: ComposerState
    var details: [ThreadSummary.ID: ThreadDetailState]
    var destination: SidebarDestination = .home
    var sidebarVisible = true
    var now: Date

    init(sidebar: SidebarState, home: HomeState, composer: ComposerState, details: [ThreadSummary.ID: ThreadDetailState], now: Date) {
        self.sidebar = sidebar
        self.home = home
        self.composer = composer
        self.details = details
        self.now = now
    }

    static func mock() -> AppModel {
        let model = AppModel(
            sidebar: MockData.sidebar,
            home: MockData.home,
            composer: MockData.composer(),
            details: [MockData.threadDetail.summary.id: MockData.threadDetail],
            now: MockData.now
        )
        // `-SwftScreen thread` opens straight into the mock thread (used for screenshots).
        if UserDefaults.standard.string(forKey: "SwftScreen") == "thread" {
            model.destination = .thread(MockData.threadDetail.summary.id)
        }
        return model
    }

    var visibleThreads: [ThreadSummary] {
        switch sidebar.filter {
        case .all: sidebar.threads
        case .active: sidebar.threads.filter { $0.activity == .running || $0.activity == .needsApproval }
        case .needsAttention: sidebar.threads.filter { $0.activity == .needsApproval || $0.activity == .failed || $0.activity == .unread }
        }
    }

    var selectedThreadID: ThreadSummary.ID? {
        if case .thread(let id) = destination { id } else { nil }
    }

    func detail(for id: ThreadSummary.ID) -> ThreadDetailState? {
        if let detail = details[id] { return detail }
        guard let summary = sidebar.threads.first(where: { $0.id == id }) else { return nil }
        // Mock: every thread without its own transcript reuses the sample one.
        var sample = MockData.threadDetail
        sample.summary = summary
        return sample
    }

    func open(_ id: ThreadSummary.ID) {
        destination = .thread(id)
        if let index = sidebar.threads.firstIndex(where: { $0.id == id }), sidebar.threads[index].activity == .unread {
            sidebar.threads[index].activity = .idle
        }
    }

    func toggleSidebar() {
        withAnimation(.snappy(duration: 0.22)) { sidebarVisible.toggle() }
    }

    func send() {
        let text = composer.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        composer.text = ""
        let id = selectedThreadID ?? MockData.threadDetail.summary.id
        var detail = detail(for: id) ?? MockData.threadDetail
        detail.items.append(TranscriptItem(id: UUID().uuidString, kind: .user(text)))
        details[id] = detail
        destination = .thread(id)
    }

    func resolveApproval(itemID: TranscriptItem.ID, in threadID: ThreadSummary.ID, approved: Bool) {
        guard var detail = detail(for: threadID),
              let index = detail.items.firstIndex(where: { $0.id == itemID }),
              case .approval(var approval) = detail.items[index].kind else { return }
        approval.status = approved ? .approved : .denied
        detail.items[index].kind = .approval(approval)
        details[threadID] = detail
        if let t = sidebar.threads.firstIndex(where: { $0.id == threadID }), sidebar.threads[t].activity == .needsApproval {
            sidebar.threads[t].activity = .running
        }
    }
}
