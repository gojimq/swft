import AppKit
import Foundation
import SwftDesign
import SwiftUI
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

    func assistant(
        _ id: String,
        _ text: String,
        streaming: Bool = false,
        start: Double,
        end: Double? = nil
    ) -> TranscriptItem {
        TranscriptItem(
            id: id,
            kind: .assistant(blocks: [.text(text)], streaming: streaming),
            startedAt: at(start),
            completedAt: end.map(at)
        )
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

    @Test func aTurnWithMultipleNoticesFoldsThemIntoOneRow() {
        let items = [
            user("u", "Hi", start: 0),
            TranscriptItem(id: "n1", kind: .notice(title: "MCP server a failed to start", message: "timed out", isError: false)),
            TranscriptItem(id: "n2", kind: .notice(title: "MCP server b failed to start", message: "not found", isError: false)),
            TranscriptItem(id: "n3", kind: .notice(title: "MCP server c failed to start", message: "refused", isError: false)),
            assistant("a", "Hello", start: 1, end: 3),
        ]
        let rows = TranscriptLayout.rows(for: items, isRunning: false)
        #expect(rows.map(\.id) == ["u", "work:u", "a"])
        guard case .work(let fold) = rows[1] else { Issue.record("expected a fold"); return }
        #expect(!fold.isLive)
        #expect(fold.title == "3 notices")
        #expect(fold.steps.map(\.id) == ["n1", "n2", "n3"])
        #expect(TranscriptLayout.summaryLabel(fold.steps) == "3 notices")
    }

    @Test func plainExchangeHasNoFold() {
        let items = [user("u", "Hi", start: 0), assistant("a", "Hello", start: 1, end: 2)]
        #expect(TranscriptLayout.rows(for: items, isRunning: false).map(\.id) == ["u", "a"])
    }

    @Test func liveTurnKeepsInterimAssistantMessagesVisibleAndFoldsThemOnSettleLikeT3Code() {
        let liveItems = [
            user("u1", "Align the picker", start: 0),
            tool("th1", .thinking, "Thought", "I'm aligning the panel's trailing edge with the trigger chip.", start: 1, end: 2),
            assistant("c1", "Got it: the picker's right edge should line up with the right edge of the model pill.", start: 2, end: 3),
            tool("th2", .thinking, "Thought", "**Checking simulator output**\n\nLook at frame coordinates next.", start: 3, end: 4),
            tool("cmd1", .command, "Running", "swift test --filter Picker", .running, start: 4),
        ]
        // While live: pre-message thought folds quietly above the assistant message, the assistant message stays
        // visible inline in full, and the trailing live work group surfaces its latest thought above the running tool.
        let liveRows = TranscriptLayout.rows(for: liveItems, isRunning: true)
        #expect(liveRows.map(\.id) == ["u1", "work:u1", "c1", "work:u1:th2"])

        guard case .work(let preFold) = liveRows[1] else { Issue.record("expected pre-message fold"); return }
        #expect(!preFold.isLive)
        #expect(preFold.title == "Thought")
        #expect(preFold.liveThought == nil)

        guard case .assistant(let msgID, _, _) = liveRows[2] else { Issue.record("expected inline assistant message"); return }
        #expect(msgID == "c1")

        guard case .work(let tailFold) = liveRows[3] else { Issue.record("expected live tail fold"); return }
        #expect(tailFold.isLive)
        #expect(tailFold.title == "Running swift test --filter Picker")
        #expect(tailFold.liveThought == WorkThoughtPreview(id: "th2", text: "Checking simulator output"))

        // Once settled: everything before the final answer collapses into one quiet "Worked for …" row.
        let settledItems = [
            user("u1", "Align the picker", start: 0),
            tool("th1", .thinking, "Thought", "I'm aligning the panel's trailing edge with the trigger chip.", start: 1, end: 2),
            assistant("c1", "Got it: the picker's right edge should line up with the right edge of the model pill.", start: 2, end: 3),
            tool("th2", .thinking, "Thought", "**Checking simulator output**", start: 3, end: 4),
            tool("cmd1", .command, "Ran", "swift test --filter Picker", .succeeded, start: 4, end: 10),
            assistant("a1", "The model picker's right edge now lines up with the model pill.", start: 10, end: 12),
        ]
        let settledRows = TranscriptLayout.rows(for: settledItems, isRunning: false)
        #expect(settledRows.map(\.id) == ["u1", "work:u1", "a1"])
        guard case .work(let settledFold) = settledRows[1] else { Issue.record("expected settled fold"); return }
        #expect(!settledFold.isLive)
        #expect(settledFold.title == "Worked for 12s")
        #expect(settledFold.liveThought == nil)
        #expect(settledFold.steps.map(\.id) == ["th1", "c1", "th2", "cmd1"])
    }

    @Test func liveThoughtLineMirrorsT3CodeHeadingAndSentenceRules() {
        // Bold heading takes precedence (Codex summaries).
        #expect(TranscriptLayout.liveThoughtLine(from: "**Designing composer draft state**\n\nMore details here.") == "Designing composer draft state")

        // Prose flattens markdown and extracts the first sentence (Claude / Gemini thoughts).
        let claude = "I'm aligning the panel's trailing edge with the `trigger` chip. Next I'll check the **margin**."
        #expect(TranscriptLayout.liveThoughtLine(from: claude) == "I'm aligning the panel's trailing edge with the trigger chip.")

        // CJK sentence terminator without trailing space.
        #expect(TranscriptLayout.liveThoughtLine(from: "まず設定を確認します。次にビルドします。") == "まず設定を確認します。")

        // Empty or ellipsis-only placeholders return nil.
        #expect(TranscriptLayout.liveThoughtLine(from: "…") == nil)
        #expect(TranscriptLayout.liveThoughtLine(from: "   \n ") == nil)
    }

    @Test func blurSwapLogicDisablesBlurAndDelayUnderReduceMotion() {
        #expect(SwftBlurSwapLogic.activeBlurRadius(SwftMotion.blurSwapRadius, reduceMotion: false) == SwftMotion.blurSwapRadius)
        #expect(SwftBlurSwapLogic.insertionDelay(reduceMotion: false) == SwftMotion.blurSwapDelay)

        #expect(SwftBlurSwapLogic.activeBlurRadius(SwftMotion.blurSwapRadius, reduceMotion: true) == 0)
        #expect(SwftBlurSwapLogic.insertionDelay(reduceMotion: true) == 0)
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

@MainActor
@Observable
private final class LiveWorkHarnessState {
    var fold: WorkFold
    var isExpanded = false
    init(fold: WorkFold) { self.fold = fold }
}

private struct LiveWorkHarnessView: View {
    let state: LiveWorkHarnessState
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            UserBubble("Align the right edge of the model picker with the model pill.")
            AssistantMessage {
                MessageText(
                    "Got it: the picker's right edge should line up with the right edge of the model pill, and the picker can sit over the composer, right above the pill.",
                    streaming: false
                )
            }
            WorkFoldView(fold: state.fold, isExpanded: state.isExpanded) {
                state.isExpanded.toggle()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: SwftLayout.contentMaxWidth, alignment: .leading)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SwftColor.canvas)
    }
}

/// Optional visual capture verifying T3 Code-style live turn (inline assistant text + live thought blur-swap above tool row).
/// Run with: `SWFT_LIVE_WORK_SHOTS_DIR=/tmp/swft-live-work swift test --filter LiveWorkMotionSnapshots`
@MainActor
@Suite(
    "LiveWorkMotionSnapshots",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SWFT_LIVE_WORK_SHOTS_DIR"] != nil)
)
struct LiveWorkMotionSnapshots {
    static let directory = URL(
        fileURLWithPath: ProcessInfo.processInfo.environment["SWFT_LIVE_WORK_SHOTS_DIR"] ?? NSTemporaryDirectory()
    )

    @Test func captureLiveWorkLayoutAndBlurSwap() throws {
        SwftFonts.register()
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)

        let steps1: [WorkStep] = [
            WorkStep(id: "th1", kind: .thought("I'm aligning the panel's trailing edge with the trigger chip's trailing edge, with the panel's bottom sitting just above the chip. Next I'll verify the margins.")),
            WorkStep(id: "cmd1", kind: .tool(.init(kind: .command, title: "Running", detail: "swift test --filter PickerAlignment", status: .running, duration: nil, output: nil))),
        ]
        let fold1 = WorkFold(
            id: "work:u1:th1",
            steps: steps1,
            isLive: true,
            title: "Running swift test --filter PickerAlignment",
            subtitle: "Read 2 files",
            liveThought: TranscriptLayout.latestThoughtPreview(in: steps1),
            failedCount: 0
        )

        let steps2 = steps1 + [
            WorkStep(id: "th2", kind: .thought("**Verifying dark-mode border contrast**\n\nCheck light and dark captures next.")),
        ]
        let fold2 = WorkFold(
            id: "work:u1:th1",
            steps: steps2,
            isLive: true,
            title: "Running ./scripts/bundle.sh debug",
            subtitle: "Read 2 files, ran 1 command",
            liveThought: TranscriptLayout.latestThoughtPreview(in: steps2),
            failedCount: 0
        )

        for (appearanceName, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            let state = LiveWorkHarnessState(fold: fold1)
            let size = CGSize(width: 780, height: 360)
            let window = NSWindow(
                contentRect: CGRect(origin: CGPoint(x: 100, y: 140), size: size),
                styleMask: [.titled, .fullSizeContentView, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.appearance = NSAppearance(named: appearance)
            let host = NSHostingView(
                rootView: LiveWorkHarnessView(state: state)
                    .frame(width: size.width, height: size.height)
                    .preferredColorScheme(appearance == .darkAqua ? .dark : .light)
            )
            host.frame = CGRect(origin: .zero, size: size)
            window.contentView = host
            window.orderFrontRegardless()
            defer { window.orderOut(nil) }

            let wid = window.windowNumber
            func grab(_ suffix: String) throws {
                host.layoutSubtreeIfNeeded()
                let out = Self.directory.appendingPathComponent("\(appearanceName)-\(suffix).png").path
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                p.arguments = ["-x", "-o", "-l", "\(wid)", out]
                try p.run()
                p.waitUntilExit()
            }

            RunLoop.main.run(until: Date().addingTimeInterval(0.35))
            try grab("01-live-collapsed")

            if appearanceName == "light" {
                state.fold = fold2
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                try grab("02-blur-swap-mid")
                RunLoop.main.run(until: Date().addingTimeInterval(0.35))
                try grab("03-blur-swap-settled")
            }

            state.isExpanded = true
            RunLoop.main.run(until: Date().addingTimeInterval(0.35))
            try grab("04-expanded")
        }
    }
}
