import Foundation
import Testing
@testable import Swft
@testable import SwftKit

@Suite("Usage Limits Wire Contracts & Pacing Pills")
struct UsagePillsTests {
    private static let expiredMessage =
        "Antigravity's saved sign-in has expired. Start an Antigravity turn to renew it, then refresh limits."

    private static let baseTime = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeWindow(
        id: String,
        kind: UsageWindowKind,
        label: String? = nil,
        usedPercent: Double,
        modelIds: [String]? = nil,
        providerIds: [String]? = nil,
        resetsInMins: Double? = nil,
        windowDurationMins: Int? = nil
    ) -> UsageWindow {
        UsageWindow(
            id: id,
            kind: kind,
            label: label ?? id,
            modelIds: modelIds,
            providerIds: providerIds,
            usedPercent: usedPercent,
            resetsAt: resetsInMins.map { Self.baseTime.addingTimeInterval($0 * 60) },
            windowDurationMins: windowDurationMins
        )
    }

    private func makeEntry(
        id: String,
        driver: String? = nil,
        acpAgentId: String? = nil,
        label: String? = nil,
        kind: ProviderKind = .other,
        accentHex: String? = nil,
        account: String? = nil,
        listed: Bool = true,
        enabled: Bool = true,
        installed: Bool = true,
        unauthenticated: Bool = false,
        unavailableReason: String? = nil,
        usageLimits: UsageLimitsSnapshot? = nil
    ) -> UsageProviderEntry {
        UsageProviderEntry(
            id: id,
            driver: driver ?? id,
            acpAgentId: acpAgentId,
            label: label ?? id,
            kind: kind,
            accentHex: accentHex,
            account: account,
            listed: listed,
            enabled: enabled,
            installed: installed,
            unauthenticated: unauthenticated,
            unavailableReason: unavailableReason,
            usageLimits: usageLimits
        )
    }

    private func makeHealthyLimits(_ windows: [UsageWindow]) -> UsageLimitsSnapshot {
        UsageLimitsSnapshot(checkedAt: Self.baseTime, windows: windows)
    }

    // MARK: - 1. Wire Contract Decoding

    @Test func decodesServerProviderUsageLimitsIncludingOptionalFieldsAndUnknownKind() throws {
        let decoder = SwftJSON.makeDecoder()
        let json = """
        {
          "instanceId": "claudeAgent",
          "driver": "claudeAgent",
          "displayName": "Claude",
          "enabled": true,
          "installed": true,
          "status": "ready",
          "auth": { "status": "authenticated", "label": "Claude Max", "email": "dev@example.com" },
          "checkedAt": "2026-11-24T19:00:00.000Z",
          "models": [],
          "usageLimits": {
            "checkedAt": "2026-11-24T19:00:00.000Z",
            "zeroSpendCap": false,
            "credentialFingerprint": "fp_abc123",
            "windows": [
              {
                "id": "five_hour",
                "kind": "session",
                "label": "5-hour",
                "usedPercent": 36.5,
                "resetsAt": "2026-11-24T21:14:00.000Z",
                "windowDurationMins": 300
              },
              {
                "id": "weekly_sonnet",
                "kind": "weekly",
                "label": "Weekly · Sonnet",
                "modelIds": ["claude-sonnet-5-5"],
                "usedPercent": 42
              },
              {
                "id": "future_window",
                "kind": "quarterly",
                "label": "Quarterly",
                "providerIds": ["anthropic"],
                "usedPercent": 12
              }
            ]
          }
        }
        """

        let provider = try decoder.decode(ServerProvider.self, from: Data(json.utf8))
        let limits = try #require(provider.usageLimits)
        #expect(limits.zeroSpendCap == false)
        #expect(limits.credentialFingerprint == "fp_abc123")
        #expect(limits.unavailable == nil)
        #expect(limits.windows.count == 3)

        let session = limits.windows[0]
        #expect(session.id == "five_hour")
        #expect(session.kind == .session)
        #expect(session.label == "5-hour")
        #expect(session.usedPercent == 36.5)
        #expect(session.resetsAt != nil)
        #expect(session.windowDurationMins == 300)
        #expect(session.modelIds == nil)

        let weekly = limits.windows[1]
        #expect(weekly.kind == .weekly)
        #expect(weekly.modelIds == ["claude-sonnet-5-5"])
        #expect(weekly.resetsAt == nil)
        #expect(weekly.windowDurationMins == nil)

        let future = limits.windows[2]
        #expect(future.kind == .unknown("quarterly"))
        #expect(future.kind.rawValue == "quarterly")
        #expect(future.providerIds == ["anthropic"])
    }

    @Test func decodesMissingUsageLimitsAndUnavailablePayloads() throws {
        let decoder = SwftJSON.makeDecoder()
        let missingJSON = """
        {
          "instanceId": "codex",
          "driver": "codex",
          "enabled": true,
          "installed": true,
          "status": "ready",
          "auth": { "status": "authenticated" },
          "checkedAt": "2026-11-24T19:00:00Z",
          "models": []
        }
        """
        let providerWithoutLimits = try decoder.decode(ServerProvider.self, from: Data(missingJSON.utf8))
        #expect(providerWithoutLimits.usageLimits == nil)

        let unavailableJSON = """
        {
          "checkedAt": "2026-11-24T19:00:00.000Z",
          "windows": [
            { "id": "broken_entry_missing_usedPercent", "kind": "session", "label": "Broken" },
            { "id": "valid_monthly", "kind": "monthly", "label": "Monthly", "usedPercent": 20 }
          ],
          "unavailable": {
            "reason": "probeFailed",
            "message": "Antigravity's saved sign-in has expired."
          }
        }
        """
        let limits = try decoder.decode(ServerProviderUsageLimits.self, from: Data(unavailableJSON.utf8))
        #expect(limits.unavailable?.reason == .probeFailed)
        #expect(limits.unavailable?.message == "Antigravity's saved sign-in has expired.")
        // Forward-compatible array decoding skips malformed window items rather than failing.
        #expect(limits.windows.count == 1)
        #expect(limits.windows[0].id == "valid_monthly")
        #expect(limits.windows[0].kind == .monthly)

        // Unknown unavailable reason also decodes cleanly.
        let futureReasonJSON = #"{"reason":"rateLimited","message":"Try again later"}"#
        let unavailable = try decoder.decode(ServerProviderUsageUnavailable.self, from: Data(futureReasonJSON.utf8))
        #expect(unavailable.reason == .unknown("rateLimited"))
        #expect(unavailable.reason.rawValue == "rateLimited")
    }

    @Test func adaptsServerProviderUsageLimitsThroughSwftAdapters() {
        let serverLimits = ServerProviderUsageLimits(
            checkedAt: Self.baseTime,
            windows: [
                ServerProviderUsageWindow(
                    id: "5h",
                    kind: .session,
                    label: "5-hour",
                    usedPercent: 25,
                    resetsAt: Self.baseTime.addingTimeInterval(150 * 60),
                    windowDurationMins: 300
                ),
            ]
        )
        let provider = ServerProvider(
            instanceId: "claudeAgent",
            driver: "claudeAgent",
            displayName: "Claude",
            accentColor: "#D97757",
            enabled: true,
            installed: true,
            status: .ready,
            auth: ServerProviderAuth(status: .authenticated, label: "Claude Max", email: "jim@work.dev"),
            checkedAt: Self.baseTime,
            models: [],
            usageLimits: serverLimits
        )

        let entry = SwftAdapters.usageProvider(from: provider)
        #expect(entry.id == "claudeAgent")
        #expect(entry.kind == .claude)
        #expect(entry.accentHex == "#d97757")
        #expect(entry.account == "Claude Max · jim@work.dev")
        #expect(entry.usageLimits?.windows.count == 1)
        #expect(entry.usageLimits?.windows.first?.kind == .session)
    }

    // MARK: - 2. Exact Pacing Math & Reset Countdown

    @Test func remainingPercentClampsAndRounds() {
        #expect(UsagePillsLogic.remainingPercent(makeWindow(id: "a", kind: .session, usedPercent: 0)) == 100)
        #expect(UsagePillsLogic.remainingPercent(makeWindow(id: "b", kind: .session, usedPercent: 100)) == 0)
        #expect(UsagePillsLogic.remainingPercent(makeWindow(id: "c", kind: .session, usedPercent: -10)) == 100)
        #expect(UsagePillsLogic.remainingPercent(makeWindow(id: "d", kind: .session, usedPercent: 125)) == 0)
        #expect(UsagePillsLogic.remainingPercent(makeWindow(id: "e", kind: .session, usedPercent: 36.4)) == 64)
        #expect(UsagePillsLogic.remainingPercent(makeWindow(id: "f", kind: .session, usedPercent: 36.5)) == 64)
        #expect(UsagePillsLogic.remainingPercent(makeWindow(id: "g", kind: .session, usedPercent: 36.6)) == 63)
    }

    @Test func elapsedShareAndPaceRemainingPercentMatchSpec() {
        // Halfway through a 5-hour (300m) window: 150m left -> elapsed 0.5 -> paceRemaining 50%.
        let half = makeWindow(id: "s", kind: .session, usedPercent: 50, resetsInMins: 150, windowDurationMins: 300)
        #expect(UsagePillsLogic.elapsedShare(half, now: Self.baseTime) == 0.5)
        #expect(UsagePillsLogic.paceRemainingPercent(half, now: Self.baseTime) == 50)

        // 25% elapsed (225m remaining of 300m) -> paceRemaining 75%.
        let quarter = makeWindow(id: "q", kind: .session, usedPercent: 20, resetsInMins: 225, windowDurationMins: 300)
        #expect(UsagePillsLogic.elapsedShare(quarter, now: Self.baseTime) == 0.25)
        #expect(UsagePillsLogic.paceRemainingPercent(quarter, now: Self.baseTime) == 75)

        // Already past reset -> elapsed clamped to 1.0 -> paceRemaining 0%.
        let past = makeWindow(id: "p", kind: .session, usedPercent: 80, resetsInMins: -5, windowDurationMins: 300)
        #expect(UsagePillsLogic.elapsedShare(past, now: Self.baseTime) == 1.0)
        #expect(UsagePillsLogic.paceRemainingPercent(past, now: Self.baseTime) == 0)

        // Reset further out than duration -> elapsed clamped to 0.0 -> paceRemaining 100%.
        let future = makeWindow(id: "f", kind: .session, usedPercent: 0, resetsInMins: 400, windowDurationMins: 300)
        #expect(UsagePillsLogic.elapsedShare(future, now: Self.baseTime) == 0.0)
        #expect(UsagePillsLogic.paceRemainingPercent(future, now: Self.baseTime) == 100)

        // Missing duration or zero duration returns nil.
        let noDuration = makeWindow(id: "nd", kind: .session, usedPercent: 40, resetsInMins: 60, windowDurationMins: nil)
        #expect(UsagePillsLogic.elapsedShare(noDuration, now: Self.baseTime) == nil)
        #expect(UsagePillsLogic.paceRemainingPercent(noDuration, now: Self.baseTime) == nil)

        let zeroDuration = makeWindow(id: "zd", kind: .session, usedPercent: 40, resetsInMins: 60, windowDurationMins: 0)
        #expect(UsagePillsLogic.elapsedShare(zeroDuration, now: Self.baseTime) == nil)
    }

    @Test func paceOfRespectsExactMinus5AndPlus5Thresholds() {
        // 50% elapsed (150m left of 300m)
        func pace(used: Double) -> LimitPace? {
            let w = makeWindow(id: "w", kind: .session, usedPercent: used, resetsInMins: 150, windowDurationMins: 300)
            return UsagePillsLogic.paceOf(w, now: Self.baseTime)
        }

        #expect(pace(used: 55.1) == .ahead)
        #expect(pace(used: 55.0) == .on)
        #expect(pace(used: 50.0) == .on)
        #expect(pace(used: 45.0) == .on)
        #expect(pace(used: 44.9) == .under)

        let untimed = makeWindow(id: "u", kind: .session, usedPercent: 90)
        #expect(UsagePillsLogic.paceOf(untimed, now: Self.baseTime) == nil)
    }

    @Test func formatResetCountdownAndResetsInPhrase() {
        let nowWindow = makeWindow(id: "now", kind: .session, usedPercent: 50, resetsInMins: 0)
        #expect(UsagePillsLogic.formatResetCountdown(nowWindow, now: Self.baseTime) == "Now")
        #expect(UsagePillsLogic.formatResetsInPhrase(nowWindow, now: Self.baseTime) == "resets now")

        let soonWindow = makeWindow(id: "soon", kind: .session, usedPercent: 50, resetsInMins: 0.5)
        #expect(UsagePillsLogic.formatResetCountdown(soonWindow, now: Self.baseTime) == "<1m")
        #expect(UsagePillsLogic.formatResetsInPhrase(soonWindow, now: Self.baseTime) == "resets momentarily")

        let minsWindow = makeWindow(id: "mins", kind: .session, usedPercent: 50, resetsInMins: 42)
        #expect(UsagePillsLogic.formatResetCountdown(minsWindow, now: Self.baseTime) == "42m")
        #expect(UsagePillsLogic.formatResetsInPhrase(minsWindow, now: Self.baseTime) == "resets in 42m")

        let hoursWindow = makeWindow(id: "hrs", kind: .session, usedPercent: 50, resetsInMins: 2 * 60 + 14)
        #expect(UsagePillsLogic.formatResetCountdown(hoursWindow, now: Self.baseTime) == "2h 14m")
        #expect(UsagePillsLogic.formatResetsInPhrase(hoursWindow, now: Self.baseTime) == "resets in 2h 14m")

        let daysWindow = makeWindow(id: "days", kind: .weekly, usedPercent: 50, resetsInMins: 3 * 24 * 60 + 18 * 60)
        #expect(UsagePillsLogic.formatResetCountdown(daysWindow, now: Self.baseTime) == "3d 18h")

        let noResetWindow = makeWindow(id: "none", kind: .session, usedPercent: 50)
        #expect(UsagePillsLogic.formatResetCountdown(noResetWindow, now: Self.baseTime) == nil)
    }

    // MARK: - 3. Multi-Account Grouping, Window Selection & Expiry Detection

    @Test func classifiesHealthyExpiredNotSignedInUnsupportedAndUnavailable() {
        let healthy = makeEntry(
            id: "claude",
            driver: "claudeAgent",
            usageLimits: makeHealthyLimits([makeWindow(id: "s", kind: .session, usedPercent: 20)])
        )
        #expect(UsagePillsLogic.classify(healthy)?.kind == .healthy)

        let expired = makeEntry(
            id: "antigravity",
            driver: "antigravity",
            usageLimits: UsageLimitsSnapshot(
                checkedAt: Self.baseTime,
                unavailable: UsageUnavailable(reason: .probeFailed, message: Self.expiredMessage)
            )
        )
        #expect(UsagePillsLogic.classify(expired) == .expired(reason: "Sign-in expired"))

        // Expired detection is restricted to Antigravity driver.
        let codexSameMessage = makeEntry(
            id: "codex",
            driver: "codex",
            usageLimits: UsageLimitsSnapshot(
                checkedAt: Self.baseTime,
                unavailable: UsageUnavailable(reason: .probeFailed, message: Self.expiredMessage)
            )
        )
        #expect(UsagePillsLogic.classify(codexSameMessage)?.kind == .unavailable)

        let signedOut = makeEntry(id: "signedOut", unauthenticated: true, unavailableReason: "Not signed in")
        #expect(UsagePillsLogic.classify(signedOut) == .notSignedIn(reason: "Not signed in"))

        let unsupported = makeEntry(
            id: "apiKey",
            usageLimits: UsageLimitsSnapshot(
                checkedAt: Self.baseTime,
                unavailable: UsageUnavailable(reason: .unsupported)
            )
        )
        #expect(UsagePillsLogic.classify(unsupported) == .unsupported(reason: "Usage limits not available"))

        // Disabled, uninstalled, unlisted, or no-limits providers are excluded.
        #expect(UsagePillsLogic.classify(makeEntry(id: "off", enabled: false, usageLimits: makeHealthyLimits([makeWindow(id: "s", kind: .session, usedPercent: 10)]))) == nil)
        #expect(UsagePillsLogic.classify(makeEntry(id: "missing", installed: false, usageLimits: makeHealthyLimits([makeWindow(id: "s", kind: .session, usedPercent: 10)]))) == nil)
        #expect(UsagePillsLogic.classify(makeEntry(id: "hidden", listed: false, usageLimits: makeHealthyLimits([makeWindow(id: "s", kind: .session, usedPercent: 10)]))) == nil)
        #expect(UsagePillsLogic.classify(makeEntry(id: "nolimits")) == nil)
    }

    @Test func foldsMultiAccountDriversPicksTightestPrimaryAndSecondaryWindowsAndIgnoresSignedOutSiblings() {
        let claudeWork = makeEntry(
            id: "claude_work",
            driver: "claudeAgent",
            label: "Claude Work",
            kind: .claude,
            account: "Claude Max · work@example.com",
            usageLimits: makeHealthyLimits([
                makeWindow(id: "5h-work", kind: .session, label: "5-hour", usedPercent: 60),
                makeWindow(id: "wk-work", kind: .weekly, label: "Weekly", usedPercent: 30),
                // Scoped sublimit is tighter than account-wide weekly, so unscoped weekly must win for the pill bar.
                makeWindow(id: "wk-sonnet", kind: .weekly, label: "Weekly · Sonnet", usedPercent: 95, modelIds: ["sonnet"]),
            ])
        )
        let claudePersonal = makeEntry(
            id: "claude_personal",
            driver: "claudeAgent",
            label: "Claude Personal",
            kind: .claude,
            account: "Claude Pro · me@example.com",
            usageLimits: makeHealthyLimits([
                makeWindow(id: "5h-personal", kind: .session, label: "5-hour", usedPercent: 25),
                makeWindow(id: "wk-personal", kind: .weekly, label: "Weekly", usedPercent: 92),
            ])
        )
        let claudeSignedOut = makeEntry(
            id: "claude_out",
            driver: "claudeAgent",
            label: "Claude Signed Out",
            kind: .claude,
            unauthenticated: true,
            unavailableReason: "Not signed in"
        )

        let groups = UsagePillsLogic.candidateGroups(from: [claudeWork, claudePersonal, claudeSignedOut])
        #expect(groups.count == 1)

        let group = groups[0]
        #expect(group.id == "claudeAgent")
        #expect(group.label == "Claude")
        // Signed-out sibling is hidden when signed-in siblings exist.
        #expect(group.accounts.map(\.id) == ["claude_work", "claude_personal"])
        #expect(group.allAccounts.count == 3)

        // Primary = tightest session (60% used -> 40% left); secondary = tightest unscoped weekly (92% used -> 8% left).
        if case .healthy(let primary, let secondary) = group.state {
            #expect(primary.id == "5h-work")
            #expect(UsagePillsLogic.remainingPercent(primary) == 40)
            #expect(secondary?.id == "wk-personal")
            #expect(secondary.map(UsagePillsLogic.remainingPercent) == 8)
        } else {
            Issue.record("Expected healthy grouped state")
        }

        // Because wk-personal is <= 10% left, clicking the pill deep-links to claude_personal.
        #expect(group.openTargetId == "claude_personal")
    }

    @Test func splitsScopedWindowsIntoModelFamilyGroups() {
        let windows = [
            makeWindow(id: "w1", kind: .session, label: "5-hour", usedPercent: 20),
            makeWindow(id: "w2", kind: .weekly, label: "Weekly · Sonnet", usedPercent: 45),
            makeWindow(id: "w3", kind: .session, label: "Gemini 3 Pro · 5-hour", usedPercent: 70),
            makeWindow(id: "w4", kind: .weekly, label: "Gemini 3 Pro · Weekly", usedPercent: 30),
        ]
        let groups = UsagePillsLogic.usageWindowGroups(windows)
        #expect(groups.count == 3)
        #expect(groups[0].family == nil)
        #expect(groups[0].rows.map(\.label) == ["5-hour"])
        #expect(groups[1].family == "Sonnet")
        #expect(groups[1].rows.map(\.label) == ["Weekly"])
        #expect(groups[2].family == "Gemini 3 Pro")
        #expect(groups[2].rows.map(\.label) == ["Session", "Weekly"])
    }

    // MARK: - 4. Max-3 Selection, Toggling & Persistence

    @Test func enforcesMaxThreeSelectionAndMigratesLegacyInstanceIDs() {
        let entries = [
            makeEntry(id: "claude_work", driver: "claudeAgent", label: "Claude Work", usageLimits: makeHealthyLimits([makeWindow(id: "c", kind: .session, usedPercent: 20)])),
            makeEntry(id: "codex", driver: "codex", label: "Codex", usageLimits: makeHealthyLimits([makeWindow(id: "x", kind: .session, usedPercent: 30)])),
            makeEntry(id: "antigravity", driver: "antigravity", label: "Antigravity", usageLimits: makeHealthyLimits([makeWindow(id: "g", kind: .session, usedPercent: 91)])),
            makeEntry(id: "cursor", driver: "cursor", label: "Cursor", usageLimits: makeHealthyLimits([makeWindow(id: "r", kind: .monthly, usedPercent: 10)])),
        ]

        // Default selection (nil) picks first 3 healthy/expired driver groups.
        let defaultShown = UsagePillsLogic.visibleGroups(from: entries, selected: nil)
        #expect(defaultShown.map(\.id) == ["claudeAgent", "codex", "antigravity"])
        #expect(defaultShown.count == MAX_USAGE_PILLS)

        // Turning a 4th provider on while at cap changes nothing.
        let blocked = UsagePillsLogic.toggleSelection(entries: entries, selected: nil, groupID: "cursor", isOn: true)
        #expect(blocked == ["claudeAgent", "codex", "antigravity"])

        // Turning one off leaves 2, then adding the 4th succeeds.
        let afterOff = UsagePillsLogic.toggleSelection(entries: entries, selected: nil, groupID: "codex", isOn: false)
        #expect(afterOff == ["claudeAgent", "antigravity"])
        let afterAdd = UsagePillsLogic.toggleSelection(entries: entries, selected: afterOff, groupID: "cursor", isOn: true)
        #expect(afterAdd == ["claudeAgent", "antigravity", "cursor"])

        // Legacy instance id `claude_work` migrates to driver group `claudeAgent`, preserving unknown ids.
        let migrated = UsagePillsLogic.migrateSelection(["claude_work", "claudeAgent", "offlineProvider"], entries: entries)
        #expect(migrated == ["claudeAgent", "offlineProvider"])
    }

    @Test func persistsSelectionAndLastGoodCacheInUserDefaults() {
        let suiteName = "swft-usage-pills-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(UsagePillsStore.loadSelection(from: defaults) == nil)
        UsagePillsStore.saveSelection(["claudeAgent", "codex"], to: defaults)
        #expect(UsagePillsStore.loadSelection(from: defaults) == ["claudeAgent", "codex"])

        let entry = makeEntry(
            id: "antigravity",
            driver: "antigravity",
            usageLimits: makeHealthyLimits([makeWindow(id: "5h", kind: .session, label: "5-hour", usedPercent: 55)])
        )
        let merged = UsagePillsStore.mergedLastGoodLimits([:], environmentID: "env-1", entries: [entry])
        #expect(merged?.count == 1)
        UsagePillsStore.saveLastGoodLimits(merged ?? [:], to: defaults)

        let reloaded = UsagePillsStore.loadLastGoodLimits(from: defaults)
        #expect(UsagePillsStore.cachedInstanceIDs(in: reloaded, environmentID: "env-1") == ["antigravity"])
        #expect(UsagePillsStore.cachedInstanceIDs(in: reloaded, environmentID: "env-2").isEmpty)

        // Merging identical limits returns nil so no redundant write happens.
        #expect(UsagePillsStore.mergedLastGoodLimits(reloaded, environmentID: "env-1", entries: [entry]) == nil)
    }

    @Test func stripsPlanNoiseAndBuildsCleanAccountSectionHeaders() {
        #expect(UsagePillsLogic.shortPlanLabel("ChatGPT Plus Subscription") == "Plus")
        #expect(UsagePillsLogic.shortPlanLabel("Claude Max plan") == "Max")
        #expect(UsagePillsLogic.shortPlanLabel("Google account") == nil)

        let work = makeEntry(id: "claude_work", driver: "claudeAgent", label: "Claude Work", account: "Claude Max · jim@work.dev")
        let personal = makeEntry(id: "claude_personal", driver: "claudeAgent", label: "Claude Personal", account: "Claude Pro · jim@example.com")
        let header = UsagePillsLogic.accountSectionHeader(for: work, siblings: [work, personal])
        #expect(header.title == "Work")
        #expect(header.detail == "Max")
    }

    @Test @MainActor func mockAppModelExposesThreeDefaultPillsAndSupportsSettingsToggling() {
        let model = AppModel.mock()
        #expect(model.visibleUsagePillGroups.map(\.id) == ["claudeAgent", "codex", "antigravity"])
        #expect(model.usagePillCandidateGroups.count == 4)
        #expect(model.visibleUsagePillGroups[0].accounts.count == 2)

        // Antigravity mock pill is 9% remaining and ahead of pace.
        if case .healthy(let primary, let secondary) = model.visibleUsagePillGroups[2].state {
            #expect(UsagePillsLogic.remainingPercent(primary) == 9)
            #expect(UsagePillsLogic.paceOf(primary, now: model.now) == .ahead)
            #expect(secondary != nil)
        } else {
            Issue.record("Expected healthy Antigravity mock pill")
        }

        // Toggling off Codex and enabling Cursor updates visible pills.
        model.toggleUsagePill(groupID: "codex", isOn: false)
        model.toggleUsagePill(groupID: "cursor", isOn: true)
        #expect(model.visibleUsagePillGroups.map(\.id) == ["claudeAgent", "antigravity", "cursor"])

        // Clicking a pill triggers settings navigation + deep-link hook.
        var openedID: String?
        model.onOpenProviderSettings = { openedID = $0 }
        model.openProviderSettings(instanceId: "claudeAgent")
        #expect(model.destination == .settings)
        #expect(model.requestedSettingsProviderID == "claudeAgent")
        #expect(openedID == "claudeAgent")
    }
}
