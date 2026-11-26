import Foundation
import Observation
import SwftDesign

/// Payload for the first message sent from Home so Home can fade it in at the transcript's top
/// simultaneously while the composer slides down to dock.
struct NewThreadLaunchMessage: Equatable, Sendable {
    let text: String
    let attachments: [TranscriptAttachment]

    init(text: String, attachments: [TranscriptAttachment] = []) {
        self.text = text
        self.attachments = attachments
    }
}

/// Home → new thread, as pure state. Sending from Home starts a launch: Home's greeting and suggestions step aside
/// while the composer docks to the bottom and the first message fades into its resting top-of-transcript position.
/// The thread's screen takes over once both the dock has settled and the server has created the thread, whichever
/// comes last. Anything that leaves Home (or returns to a fresh Home) cancels, and a late server reply for a
/// cancelled launch is ignored, so it never yanks the user elsewhere.
struct NewThreadLaunchState: Equatable {
    enum Phase: Equatable {
        case idle
        /// Home is stepping aside; `threadID` is set once the server has created the thread.
        case launching(docked: Bool, threadID: String?)
        /// The new thread's screen has just taken over from Home, so it appears in place without its entrance fade.
        case handedOff(threadID: String)
    }

    private(set) var token = 0
    private(set) var phase: Phase = .idle

    var isLaunching: Bool {
        if case .launching = phase { true } else { false }
    }

    /// The token of the launch in flight, or nil.
    var launchingToken: Int? { isLaunching ? token : nil }

    var handoffThreadID: String? {
        if case .handedOff(let id) = phase { id } else { nil }
    }

    /// Starts a launch, superseding any earlier one, and returns its token.
    mutating func begin() -> Int {
        token += 1
        phase = .launching(docked: false, threadID: nil)
        return token
    }

    /// The composer finished docking. Returns the thread to hand off to if the server already answered.
    mutating func dockSettled(token: Int) -> String? {
        guard token == self.token, case .launching(_, let threadID) = phase else { return nil }
        phase = .launching(docked: true, threadID: threadID)
        return handOffIfReady()
    }

    /// The server created the thread. Returns it if the hand-off can happen now; `isCurrent` reports whether the
    /// launch is still alive at all (false means the reply should be dropped).
    mutating func resolve(token: Int, threadID: String) -> (isCurrent: Bool, handoff: String?) {
        guard token == self.token, case .launching(let docked, _) = phase else { return (false, nil) }
        phase = .launching(docked: docked, threadID: threadID)
        return (true, handOffIfReady())
    }

    /// The server rejected the launch; Home brings its content back.
    mutating func fail(token: Int) {
        guard token == self.token, isLaunching else { return }
        phase = .idle
    }

    /// The user navigated: drop any launch in flight and forget the last hand-off.
    mutating func cancel() {
        if isLaunching { token += 1 }
        phase = .idle
    }

    /// Home went away without a hand-off (the user switched screens mid-launch).
    mutating func abandon() {
        guard isLaunching else { return }
        cancel()
    }

    private mutating func handOffIfReady() -> String? {
        guard case .launching(true, let threadID?) = phase else { return nil }
        phase = .handedOff(threadID: threadID)
        return threadID
    }
}

extension Notification.Name {
    /// Posted on the main actor when a new thread is cleared to take over from Home (the composer has docked while
    /// the first message faded into place, and the server has created the thread); the thread becomes the destination
    /// in the same or the next main-actor turn. `userInfo`: `"threadID"` (String) and `"text"` (String, the first
    /// message). `AppModel` then emits a handoff `ThreadSendEvent` so `ThreadView` takes over seamlessly in place.
    static let swftNewThreadDidHandOff = Notification.Name("SwftNewThreadDidHandOff")
}

/// Drives `NewThreadLaunchState` for the app: Home's view reports the dock settling, `AppModel.send()` awaits the
/// hand-off. Event-driven (no timers): the waiting send resumes on whichever of dock/reply arrives last, or on cancel.
@MainActor
@Observable
final class NewThreadLauncher {
    private(set) var state = NewThreadLaunchState()
    /// The first message currently fading in on Home during a launch; cleared on handoff, failure, or cancellation.
    private(set) var launchingMessage: NewThreadLaunchMessage?
    @ObservationIgnored private var waiter: (token: Int, continuation: CheckedContinuation<Bool, Never>)?
    @ObservationIgnored private var firstMessage = ""

    var launchingToken: Int? { state.launchingToken }

    /// True for the screen that has just taken over from Home (skips its entrance fade).
    func isHandoff(to destination: SidebarDestination) -> Bool {
        guard let id = state.handoffThreadID else { return false }
        return destination == .thread(id)
    }

    func begin(text: String, attachments: [TranscriptAttachment] = []) -> Int {
        resumeWaiter(false)
        firstMessage = text
        launchingMessage = NewThreadLaunchMessage(text: text, attachments: attachments)
        return state.begin()
    }

    func dockSettled(token: Int) {
        guard let id = state.dockSettled(token: token) else { return }
        handedOff(id)
        resumeWaiter(true)
    }

    /// Suspends until the new thread may take over from Home. False when the launch was cancelled or superseded:
    /// the caller must then leave navigation alone.
    func awaitHandoff(token: Int, threadID: String) async -> Bool {
        let (isCurrent, handoff) = state.resolve(token: token, threadID: threadID)
        guard isCurrent else { return false }
        if let id = handoff {
            handedOff(id)
            return true
        }
        return await withCheckedContinuation { continuation in
            resumeWaiter(false)
            waiter = (token, continuation)
        }
    }

    func fail(token: Int) {
        state.fail(token: token)
        if !state.isLaunching {
            launchingMessage = nil
            resumeWaiter(false)
        }
    }

    func cancel() {
        state.cancel()
        launchingMessage = nil
        resumeWaiter(false)
    }

    func abandon() {
        guard state.isLaunching else { return }
        cancel()
    }

    private func handedOff(_ threadID: String) {
        launchingMessage = nil
        NotificationCenter.default.post(name: .swftNewThreadDidHandOff, object: nil, userInfo: ["threadID": threadID, "text": firstMessage])
    }

    private func resumeWaiter(_ value: Bool) {
        guard let waiter else { return }
        self.waiter = nil
        waiter.continuation.resume(returning: value)
    }
}
