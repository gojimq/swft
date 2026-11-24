import Foundation
import Testing
@testable import Swft
@testable import SwftKit

@Suite("Transcript work folding")
struct TranscriptLayoutTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    func tool(_ id: String, _ kind: ToolCallItem.Kind, _ title: String, _ detail: String, _ status: ToolCallItem.Status = .succeeded, start: Double, end: Double? = nil) -> TranscriptItem {
        TranscriptItem(
            id: id,
            kind: .toolCall(ToolCallItem(kind: kind, title: title, detail: detail, status: status, duration: nil, output: nil)),
            startedAt: at(start),
            completedAt: end.map(at)
        )
    }

    func assistant(_ id: String, _ text: String, streaming: Bool = false, start: Double, end: Double? = nil) -> TranscriptItem {
        TranscriptItem(id: id, kind: .assistant(blocks: [.text(text)], streaming: streaming), startedAt: at(start), completedAt: end.map(at))
    }

    func user(_ id: String, _ text: String, start: Double) -> TranscriptItem {
        TranscriptItem(id: id, kind: .user(text), startedAt: at(start))
    }

    @Test func settledTurnFoldsAllWorkIntoOneRowAboveTheAnswer() {
        let items = [
            user("u1", "Read the files", start: 0),
            tool("r1", .read, "Read", "hello.swift", start: 1, end: 1.1),
            tool("r2", .read, "Read", "README.md", start: 1.2, end: 1.3),
            tool("th", .thinking, "Thought", "Three lines", start: 2, end: 3),
            assistant("c1", "Interim commentary", start: 3, end: 3.2),
            tool("c2", .command, "Ran", "swift build", start: 4, end: 9),
            TranscriptItem(id: "n1", kind: .notice(title: "MCP sign-in", message: "Needs a sign-in", isError: false), startedAt: at(9)),
            assistant("a1", "Final answer", start: 10, end: 12.4),
        ]
        let rows = TranscriptLayout.rows(for: items, isRunning: false)
        #expect(rows.map(\.id) == ["u1", "work:u1", "a1"])
        guard case .work(let fold) = rows[1] else { Issue.record("expected a fold"); return }
        #expect(fold.title == "Worked for 12s")
        #expect(!fold.isLive)
        #expect(fold.failedCount == 0)
        #expect(fold.steps.map(\.id) == ["r1", "r2", "th", "c1", "c2", "n1"])
        #expect(TranscriptLayout.summaryLabel(fold.steps) == "Read 2 files, ran swift build")
    }

    @Test func failuresSurfaceAsACountOnTheFold() {
        let items = [
            user("u1", "Build", start: 0),
            tool("c1", .command, "Ran", "swift build", .failed, start: 1, end: 2),
            tool("c2", .command, "Ran", "swift build -v", start: 3, end: 4),
            assistant("a1", "Fixed", start: 5, end: 6),
        ]
        guard case .work(let fold) = TranscriptLayout.rows(for: items, isRunning: false)[1] else {
            Issue.record("expected a fold"); return
        }
        #expect(fold.failedCount == 1)
        #expect(TranscriptLayout.summaryLabel(fold.steps) == "Ran 2 commands")
    }

    @Test func liveTurnShowsTheCurrentStepOverASummaryOfFinishedWork() {
        let items = [
            user("u1", "Old", start: 0),
            assistant("a0", "Old answer", start: 1, end: 2),
            user("u2", "Go", start: 10),
            tool("r1", .read, "Read", "Sources/App/hello.swift", start: 11, end: 11.1),
            tool("c1", .command, "Running", "swift build", .running, start: 12),
        ]
        let rows = TranscriptLayout.rows(for: items, isRunning: true)
        #expect(rows.map(\.id) == ["u1", "a0", "u2", "work:u2"])
        guard case .work(let fold) = rows[3] else { Issue.record("expected a fold"); return }
        #expect(fold.isLive)
        #expect(fold.title == "Running swift build")
        #expect(fold.subtitle == "Read 1 file")
    }

    @Test func liveTurnThinkingAndReadingUseShortLabels() {
        let thinking = [user("u", "Go", start: 0), tool("t", .thinking, "Thinking", "…", .running, start: 1)]
        guard case .work(let a) = TranscriptLayout.rows(for: thinking, isRunning: true)[1] else { Issue.record("fold"); return }
        #expect(a.title == "Thinking…")
        #expect(a.subtitle == nil)

        let reading = [user("u", "Go", start: 0), tool("r", .read, "Reading", "/tmp/repo/hello.swift", .running, start: 1)]
        guard case .work(let b) = TranscriptLayout.rows(for: reading, isRunning: true)[1] else { Issue.record("fold"); return }
        #expect(b.title == "Reading hello.swift")
    }

    @Test func foldKeepsItsIdentityWhenTheTurnSettles() {
        let running = [user("u", "Go", start: 0), tool("r", .read, "Reading", "a.swift", .running, start: 1)]
        let settled = [
            user("u", "Go", start: 0),
            tool("r", .read, "Read", "a.swift", start: 1, end: 2),
            assistant("a", "Done", start: 3, end: 4),
        ]
        let liveID = TranscriptLayout.rows(for: running, isRunning: true).compactMap(\.workFoldID)
        let settledID = TranscriptLayout.rows(for: settled, isRunning: false).compactMap(\.workFoldID)
        #expect(liveID == ["work:u"])
        #expect(liveID == settledID)
    }

    @Test func streamingAnswerStaysVisibleBelowASettledFold() {
        let items = [
            user("u", "Go", start: 0),
            tool("r", .read, "Read", "a.swift", start: 1, end: 2),
            assistant("a", "Writing", streaming: true, start: 3),
        ]
        let rows = TranscriptLayout.rows(for: items, isRunning: true)
        #expect(rows.map(\.id) == ["u", "work:u", "a"])
        guard case .work(let fold) = rows[1] else { Issue.record("fold"); return }
        #expect(!fold.isLive)
        #expect(fold.title == "Read 1 file")
    }

    @Test func pendingApprovalsAndErrorsStayVisible() {
        let approval = ApprovalItem(requestId: "q", title: "Run command?", message: "", command: "rm -rf build", status: .pending)
        let items = [
            user("u", "Go", start: 0),
            tool("r", .read, "Read", "a.swift", start: 1, end: 2),
            TranscriptItem(id: "e", kind: .notice(title: "Provider error", message: "boom", isError: true)),
            TranscriptItem(id: "p", kind: .approval(approval)),
        ]
        let rows = TranscriptLayout.rows(for: items, isRunning: true)
        #expect(rows.map(\.id) == ["u", "work:u", "e", "p"])
        guard case .work(let fold) = rows[1] else { Issue.record("fold"); return }
        // Waiting on the reader, not working: no spinner.
        #expect(!fold.isLive)
    }

    @Test func resolvedApprovalsFoldIntoTheWork() {
        var approval = ApprovalItem(requestId: "q", title: "Run command?", message: "", command: "ls", status: .approved)
        approval.status = .approved
        let items = [
            user("u", "Go", start: 0),
            TranscriptItem(id: "p", kind: .approval(approval), startedAt: at(1)),
            assistant("a", "Done", start: 2, end: 3),
        ]
        #expect(TranscriptLayout.rows(for: items, isRunning: false).map(\.id) == ["u", "work:u", "a"])
    }

    @Test func aTurnWithOnlyANoticeShowsItAsAQuietLine() {
        let items = [
            user("u", "Hi", start: 0),
            TranscriptItem(id: "n", kind: .notice(title: "MCP sign-in", message: "Needs a sign-in", isError: false)),
            assistant("a", "Hello", start: 1, end: 2),
        ]
        let rows = TranscriptLayout.rows(for: items, isRunning: false)
        #expect(rows.map(\.id) == ["u", "n", "a"])
        if case .note(_, _, _, let isError) = rows[1] { #expect(!isError) } else { Issue.record("expected a note") }
    }

    @Test func plainExchangeHasNoFold() {
        let items = [user("u", "Hi", start: 0), assistant("a", "Hello", start: 1, end: 2)]
        #expect(TranscriptLayout.rows(for: items, isRunning: false).map(\.id) == ["u", "a"])
    }

    @Test func formatsDurations() {
        #expect(TranscriptLayout.formatDuration(12.4) == "12s")
        #expect(TranscriptLayout.formatDuration(125) == "2m 5s")
        #expect(TranscriptLayout.formatDuration(180) == "3m")
        #expect(TranscriptLayout.formatDuration(3720) == "1h 2m")
    }

    // MARK: - Thread switching

    func projection(_ id: String, title: String) -> ThreadProjection {
        ThreadProjection(
            thread: AppThread(
                id: id,
                projectId: "p",
                title: title,
                providerInstanceId: "claudeAgent",
                modelSelection: ModelSelection(instanceId: "claudeAgent", model: "haiku"),
                createdAt: t0,
                updatedAt: t0
            ),
            updatedAt: t0
        )
    }

    @Test func recentProjectionsOnlyAnswerForTheThreadAskedAbout() {
        var recent = RecentProjections()
        recent.remember(projection("a", title: "A"))
        recent.remember(projection("b", title: "B"))
        recent.remember(nil)
        #expect(recent.projection(for: "a")?.thread.title == "A")
        #expect(recent.projection(for: "b")?.thread.title == "B")
        #expect(recent.projection(for: "c") == nil)

        // Leaving A again replaces its entry rather than duplicating it, and it moves to the front.
        recent.remember(projection("a", title: "A2"))
        #expect(recent.entries.map(\.thread.id) == ["a", "b"])
        #expect(recent.projection(for: "a")?.thread.title == "A2")
    }

    @Test func recentProjectionsEvictTheOldest() {
        var recent = RecentProjections(limit: 2)
        for id in ["a", "b", "c"] { recent.remember(projection(id, title: id)) }
        #expect(recent.entries.map(\.thread.id) == ["c", "b"])
        #expect(recent.projection(for: "a") == nil)
    }
}
