import Foundation
import SwftDesign
import Testing
@testable import Swft

@Suite("NewThreadLaunchState")
struct NewThreadLaunchStateTests {
    @Test func handsOffOnceDockedWhenTheServerAnswersFirst() {
        var state = NewThreadLaunchState()
        let token = state.begin()
        #expect(state.isLaunching)
        let reply = state.resolve(token: token, threadID: "t-new")
        #expect(reply.isCurrent)
        #expect(reply.handoff == nil)
        #expect(state.dockSettled(token: token) == "t-new")
        #expect(state.handoffThreadID == "t-new")
        #expect(!state.isLaunching)
    }

    @Test func handsOffOnTheReplyWhenTheDockSettlesFirst() {
        var state = NewThreadLaunchState()
        let token = state.begin()
        #expect(state.dockSettled(token: token) == nil)
        #expect(state.resolve(token: token, threadID: "t-new").handoff == "t-new")
    }

    @Test func navigatingAwayDropsALateReply() {
        var state = NewThreadLaunchState()
        let token = state.begin()
        state.cancel()
        #expect(state.resolve(token: token, threadID: "t-new").isCurrent == false)
        #expect(state.dockSettled(token: token) == nil)
        #expect(state.phase == .idle)
    }

    @Test func aStaleDockCompletionCannotHandOffANewerLaunch() {
        var state = NewThreadLaunchState()
        let first = state.begin()
        state.cancel()
        let second = state.begin()
        _ = state.resolve(token: second, threadID: "t-second")
        // The first launch's interrupted dock animation completes late.
        #expect(state.dockSettled(token: first) == nil)
        #expect(state.isLaunching)
        #expect(state.dockSettled(token: second) == "t-second")
    }

    @Test func failureBringsHomeBackAndIgnoresOtherTokens() {
        var state = NewThreadLaunchState()
        let token = state.begin()
        state.fail(token: token + 1)
        #expect(state.isLaunching)
        state.fail(token: token)
        #expect(state.phase == .idle)
    }

    @Test func abandonOnlyCancelsALaunchInFlight() {
        var state = NewThreadLaunchState()
        let token = state.begin()
        _ = state.dockSettled(token: token)
        _ = state.resolve(token: token, threadID: "t-new")
        // Home disappears because the thread took over: the hand-off must survive.
        state.abandon()
        #expect(state.handoffThreadID == "t-new")
        let next = state.begin()
        state.abandon()
        #expect(state.resolve(token: next, threadID: "t-other").isCurrent == false)
    }

    @Test func cancelForgetsTheHandOff() {
        var state = NewThreadLaunchState()
        let token = state.begin()
        _ = state.dockSettled(token: token)
        _ = state.resolve(token: token, threadID: "t-new")
        state.cancel()
        #expect(state.handoffThreadID == nil)
    }
}

@MainActor
@Suite("NewThreadLauncher")
struct NewThreadLauncherTests {
    @Test func waitingSendResumesWhenTheDockSettles() async {
        let launcher = NewThreadLauncher()
        let token = launcher.begin(text: "hi")
        let waiting = Task { await launcher.awaitHandoff(token: token, threadID: "t-new") }
        await Self.drain { launcher.state.phase == .launching(docked: false, threadID: "t-new") }
        launcher.dockSettled(token: token)
        #expect(await waiting.value)
        #expect(launcher.isHandoff(to: .thread("t-new")))
        #expect(!launcher.isHandoff(to: .home))
    }

    @Test func waitingSendGivesUpWhenTheUserNavigates() async {
        let launcher = NewThreadLauncher()
        let token = launcher.begin(text: "hi")
        let waiting = Task { await launcher.awaitHandoff(token: token, threadID: "t-new") }
        await Self.drain { launcher.state.phase == .launching(docked: false, threadID: "t-new") }
        launcher.cancel()
        #expect(await waiting.value == false)
        #expect(!launcher.isHandoff(to: .thread("t-new")))
    }

    @Test func aNewLaunchReleasesTheOldWaiter() async {
        let launcher = NewThreadLauncher()
        let first = launcher.begin(text: "one")
        let waiting = Task { await launcher.awaitHandoff(token: first, threadID: "t-one") }
        await Self.drain { launcher.state.phase == .launching(docked: false, threadID: "t-one") }
        let second = launcher.begin(text: "two")
        #expect(await waiting.value == false)
        launcher.dockSettled(token: second)
        #expect(await launcher.awaitHandoff(token: second, threadID: "t-two"))
    }

    @Test func postsTheHandOffHookWithTheFirstMessage() async {
        let launcher = NewThreadLauncher()
        let token = launcher.begin(text: "Fix the flaky test")
        #expect(launcher.launchingMessage == NewThreadLaunchMessage(text: "Fix the flaky test"))
        launcher.dockSettled(token: token)
        nonisolated(unsafe) var received: [AnyHashable: Any]?
        let observer = NotificationCenter.default.addObserver(forName: .swftNewThreadDidHandOff, object: nil, queue: nil) { received = $0.userInfo }
        defer { NotificationCenter.default.removeObserver(observer) }
        #expect(await launcher.awaitHandoff(token: token, threadID: "t-new"))
        #expect(launcher.launchingMessage == nil)
        #expect(received?["threadID"] as? String == "t-new")
        #expect(received?["text"] as? String == "Fix the flaky test")
    }

    @Test func launchingMessageTracksAttachmentsAndClearsOnFailureOrCancel() {
        let launcher = NewThreadLauncher()
        let attachment = TranscriptAttachment(
            id: "att-1",
            kind: .file,
            name: "spec.md",
            mimeType: "text/markdown",
            sizeBytes: 256
        )
        let first = launcher.begin(text: "Review spec", attachments: [attachment])
        #expect(launcher.launchingMessage == NewThreadLaunchMessage(text: "Review spec", attachments: [attachment]))

        // Stale token failure must not clear the active launch message.
        launcher.fail(token: first + 1)
        #expect(launcher.launchingMessage != nil)

        // Matching failure clears the launch message so Home removes the preview cleanly.
        launcher.fail(token: first)
        #expect(launcher.launchingMessage == nil)

        let second = launcher.begin(text: "Try again")
        #expect(launcher.launchingMessage == NewThreadLaunchMessage(text: "Try again"))
        #expect(launcher.launchingToken == second)
        launcher.cancel()
        #expect(launcher.launchingMessage == nil)
    }

    /// Yields until the waiting task has registered (no sleeps).
    private static func drain(until condition: () -> Bool) async {
        for _ in 0..<1000 where !condition() { await Task.yield() }
    }
}

@MainActor
@Suite("NewThreadMock")
struct NewThreadMockTests {
    @Test func homeSendLandsANewRowAndHandsOffAfterTheDock() async {
        let model = AppModel.mock()
        let before = model.sidebar.threads.count
        model.composerText = "Find and fix the failing test"
        model.send()
        #expect(model.sidebar.threads.count == before + 1)
        let row = model.sidebar.threads[0]
        #expect(row.title == "Find and fix the failing test")
        #expect(model.destination == .home)
        let token = model.newThread.launchingToken
        #expect(token != nil)
        model.newThread.dockSettled(token: token!)
        for _ in 0..<1000 where model.destination == .home { await Task.yield() }
        #expect(model.destination == .thread(row.id))
        #expect(model.newThread.isHandoff(to: model.destination))
        model.renameMockThread(row.id, to: "Fix Failing Test")
        #expect(model.threadSummary(for: row.id)?.title == "Fix Failing Test")
    }

    @Test func handoffAdoptsTheFirstMessageAndAFollowUpScrollsWithoutReplaying() async throws {
        let model = AppModel.mock()
        model.composerText = "Find and fix the failing test"
        model.send()
        let row = model.sidebar.threads[0]
        // First message payload is exposed immediately while Home docks so it fades in concurrently with the slide.
        #expect(model.newThread.launchingMessage == NewThreadLaunchMessage(text: "Find and fix the failing test"))
        model.newThread.dockSettled(token: model.newThread.launchingToken!)
        for _ in 0..<1000 where model.destination == .home { await Task.yield() }
        #expect(model.destination == .thread(row.id))
        #expect(model.newThread.launchingMessage == nil)
        let handoff = try #require(model.latestThreadSend)
        #expect(handoff.isHandoff == true)
        #expect(handoff.threadID == row.id)
        #expect(handoff.text == "Find and fix the failing test")

        // The handoff adopts the thread in place (Home already faded the first message in — no second fade).
        let detail = try #require(model.detail(for: row.id))
        let coordinator = SendFlightCoordinator()
        coordinator.syncThread(detail: detail, rows: detail.rows, isBusy: true)
        #expect(coordinator.adoptOnAppear(handoff, detail: detail, rows: detail.rows, isHandoffScreen: true) == .handoff)
        #expect(coordinator.fadeBubbleID == nil)

        // Leaving the thread drops the event, so coming back later can never hold or replay it again.
        model.goHome()
        #expect(model.latestThreadSend == nil)
        model.open(row.id)
        #expect(model.latestThreadSend == nil)

        // A send inside the open thread scrolls to its new turn and fades the message in.
        model.composerText = "One more thing"
        model.send()
        let followUp = try #require(model.latestThreadSend)
        #expect(followUp.isHandoff == false)
        #expect(followUp.threadID == row.id)
        let updatedDetail = try #require(model.detail(for: row.id))
        #expect(coordinator.beginSend(followUp, detail: updatedDetail, rows: updatedDetail.rows) == .scrollToNewTurn(preJumpY: nil))
        #expect(coordinator.fadeBubbleID == followUp.optimisticItemID)
    }

    @Test func newThreadMidLaunchStaysHome() async {
        let model = AppModel.mock()
        model.composerText = "Explain this repo"
        model.send()
        let token = model.newThread.launchingToken!
        model.goHome()
        model.newThread.dockSettled(token: token)
        for _ in 0..<50 { await Task.yield() }
        #expect(model.destination == .home)
        #expect(model.newThread.launchingToken == nil)
    }

    @Test func generatedTitles() {
        #expect(MockData.generatedTitle(for: "find and fix the failing test.") == "Find Fix Failing Test")
        #expect(MockData.generatedTitle(for: "   ") == "New thread")
    }
}
