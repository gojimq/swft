import Foundation
import Testing
@testable import Swft
@testable import SwftKit

private func harness(_ id: String, _ driver: String, _ label: String, acp: String? = nil, account: String? = nil, unauthenticated: Bool = false, reason: String? = nil) -> PickerHarness {
    PickerHarness(id: id, driver: driver, acpAgentId: acp, label: label, kind: .other, account: account, unauthenticated: unauthenticated, unavailableReason: reason)
}

/// Ported from Studio's `modelPicker.logic.test.ts` / `useModelPickerState.test.ts`.
@Suite("Model picker logic")
struct ModelPickerLogicTests {
    @Test func disambiguatorIsNilForALoneInstance() {
        let all = [harness("codex", "codex", "Codex"), harness("claude", "claudeAgent", "Claude")]
        #expect(ModelPickerLogic.disambiguator(of: all[0], among: all) == nil)
    }

    @Test func disambiguatorStripsRedundantDriverPrefixes() {
        let all = [
            harness("codex", "codex", "Codex", account: "ChatGPT · work@example.com"),
            harness("codex_personal", "codex", "Codex Personal", account: "ChatGPT · me@example.com"),
            harness("codex_team", "codex", "ChatGPT - Team"),
        ]
        #expect(ModelPickerLogic.disambiguator(of: all[0], among: all) == "Codex")
        #expect(ModelPickerLogic.disambiguator(of: all[1], among: all) == "Personal")
        #expect(ModelPickerLogic.disambiguator(of: all[2], among: all) == "Team")
    }

    @Test func disambiguatorFallsBackToAccountThenID() {
        let sameLabel = [
            harness("codex", "codex", "Codex", account: "ChatGPT · work@example.com"),
            harness("codex_2", "codex", "Codex", account: "ChatGPT · me@example.com"),
        ]
        #expect(ModelPickerLogic.disambiguator(of: sameLabel[0], among: sameLabel) == "work@example.com")
        #expect(ModelPickerLogic.disambiguator(of: sameLabel[1], among: sameLabel) == "me@example.com")
        let bare = [harness("claude_a", "claudeAgent", "Claude"), harness("claude_b", "claudeAgent", "Claude")]
        #expect(ModelPickerLogic.disambiguator(of: bare[0], among: bare) == "claude_a")
    }

    @Test func groupsByDriverKeepingRailOrderAndACPAgentsApart() {
        let claude = harness("claude", "claudeAgent", "Claude")
        let codex = harness("codex", "codex", "Codex")
        let cursor = harness("cursor", "cursor", "Cursor")
        let personal = harness("codex_personal", "codex", "Codex Personal")
        let devinA = harness("acp_devin", "acpRegistry", "Devin", acp: "devin")
        let devinB = harness("acp_devin_work", "acpRegistry", "Devin Work", acp: "devin")
        let goose = harness("acp_goose", "acpRegistry", "Goose", acp: "goose")
        let all = [claude, codex, cursor, personal, devinA, goose, devinB]
        let groups = ModelPickerLogic.groups(all)
        #expect(groups.map(\.id) == ["claudeAgent", "codex", "cursor", "acpRegistry:devin", "acpRegistry:goose"])
        #expect(groups[1] == HarnessGroup(id: "codex", label: "Codex", harnesses: [codex, personal]))
        #expect(groups[3].label == "Devin")
        #expect(ModelPickerLogic.groupTooltip(groups[0], all: all) == "Claude")
        #expect(ModelPickerLogic.groupTooltip(groups[1], all: all) == "Codex · 2 accounts")

        let custom = ModelPickerLogic.groups([harness("codex_work", "codex", "Work"), harness("codex_home", "codex", "Home")])
        #expect(custom[0].label == "Codex")
    }

    @Test func detailShowsReasonsAndOnlyCollidingAccounts() {
        let codex = harness("codex", "codex", "Codex", account: "ChatGPT Plus Subscription · gojimq@example.com")
        let personal = harness("codex_personal", "codex", "Codex Personal", account: "ChatGPT · me@example.com")
        #expect(ModelPickerLogic.detail(of: codex, among: [codex, personal]) == nil)
        let twin = harness("codex_2", "codex", "codex ", account: "ChatGPT · me@example.com")
        #expect(ModelPickerLogic.detail(of: codex, among: [codex, twin]) == "gojimq@example.com")
        #expect(ModelPickerLogic.detail(of: twin, among: [codex, twin]) == "me@example.com")
        var off = codex
        off.unavailableReason = "Turned off"
        #expect(ModelPickerLogic.detail(of: off, among: [off]) == "Turned off")
        var signedOut = codex
        signedOut.unauthenticated = true
        #expect(ModelPickerLogic.detail(of: signedOut, among: [signedOut]) == "Not signed in")
    }

    @Test func accountTooltips() {
        #expect(ModelPickerLogic.accountTooltip(harness("codex", "codex", "Codex", account: "ChatGPT Plus · a@b.com")) == "Codex · a@b.com")
        #expect(ModelPickerLogic.accountTooltip(harness("p", "codex", "Codex Personal", unauthenticated: true)) == "Codex Personal · Not signed in")
        #expect(ModelPickerLogic.accountTooltip(harness("q", "codex", "Codex Plain")) == "Codex Plain")
    }

    @Test func shortLabelsStripPrefixesAndKeepShortNames() {
        #expect(ModelPickerLogic.accountShortLabels([
            harness("codex", "codex", "Codex"),
            harness("codex_personal", "codex", "Codex Personal"),
            harness("codex_enterprise", "codex", "Codex Enterprise"),
        ]) == ["codex": "Codex", "codex_personal": "Personal", "codex_enterprise": "Enterprise"])
        #expect(ModelPickerLogic.accountShortLabels([
            harness("acp_devin", "acpRegistry", "Devin", acp: "devin"),
            harness("acp_devin_work", "acpRegistry", "Devin Work", acp: "devin"),
        ]) == ["acp_devin": "Devin", "acp_devin_work": "Work"])
    }

    @Test func shortLabelsFallBackToTwoCharacters() {
        #expect(ModelPickerLogic.accountShortLabels([
            harness("codex", "codex", "Codex"),
            harness("codex_long", "codex", "Codex Engineering"),
            harness("codex_num", "codex", "Codex 42-Sandbox-Cluster"),
            harness("codex_punct", "codex", "---Production Workspace---"),
        ]) == ["codex": "Codex", "codex_long": "En", "codex_num": "42", "codex_punct": "Pr"])
    }

    @Test func shortLabelsPreferTheDifferingPart() {
        #expect(ModelPickerLogic.accountShortLabels([
            harness("codex_a", "codex", "Codex Engineering Production"),
            harness("codex_b", "codex", "Codex Engineering Staging"),
        ]) == ["codex_a": "Production", "codex_b": "Staging"])
        #expect(ModelPickerLogic.accountShortLabels([
            harness("codex", "codex", "Codex"),
            harness("codex_acme_eng", "codex", "Codex Acme Engineering"),
            harness("codex_acme_stage", "codex", "Codex Acme Staging"),
        ]) == ["codex": "Codex", "codex_acme_eng": "En", "codex_acme_stage": "Staging"])
    }

    @Test func shortLabelsExpandCollidingAbbreviations() {
        #expect(ModelPickerLogic.accountShortLabels([
            harness("codex_prod", "codex", "Codex Production Engineering"),
            harness("codex_proto", "codex", "Codex Prototyping Lab"),
        ]) == ["codex_prod": "Prod", "codex_proto": "Prot"])
        #expect(ModelPickerLogic.accountShortLabels([
            harness("codex_en", "codex", "Codex En"),
            harness("codex_eng", "codex", "Codex Engineering"),
        ]) == ["codex_en": "En", "codex_eng": "Eng"])
    }

    @Test func shortLabelsUseEmailPartsOrIDForIdenticalNames() {
        #expect(ModelPickerLogic.accountShortLabels([
            harness("codex", "codex", "Codex", account: "ChatGPT · work@example.com"),
            harness("codex_2", "codex", "Codex", account: "ChatGPT · me@example.com"),
        ]) == ["codex": "work", "codex_2": "me"])
        #expect(ModelPickerLogic.accountShortLabels([
            harness("codex", "codex", "Codex", account: "ChatGPT · jim@work.com"),
            harness("codex_2", "codex", "Codex", account: "ChatGPT · jim@gmail.com"),
        ]) == ["codex": "work.com", "codex_2": "gmail.com"])
        #expect(ModelPickerLogic.accountShortLabels([
            harness("codex_a", "codex", "Codex"),
            harness("codex_b", "codex", "Codex"),
        ]) == ["codex_a": "codex_a", "codex_b": "codex_b"])
    }

    @Test func initialAccount() {
        let signedOut = harness("codex_out", "codex", "Codex Out", unauthenticated: true, reason: "Not signed in")
        let ready = harness("codex_ready", "codex", "Codex Ready")
        let disabled = harness("codex_off", "codex", "Codex Off", reason: "Turned off")
        #expect(ModelPickerLogic.initialHarnessID(in: [ready, signedOut], current: "codex_out") == "codex_out")
        #expect(ModelPickerLogic.initialHarnessID(in: [signedOut, disabled, ready], current: "claude") == "codex_ready")
        #expect(ModelPickerLogic.initialHarnessID(in: [signedOut, disabled], current: "claude") == "codex_out")
    }

    @Test func searchMatchesLabelLocationSubProviderAndAccount() {
        let catalog = PickerCatalog(
            harnesses: [
                PickerHarness(id: "claude", driver: "claudeAgent", label: "Claude", kind: .claude, account: "Max plan · work@example.com"),
                PickerHarness(id: "opencode", driver: "opencode", label: "OpenCode", kind: .opencode),
            ],
            models: [
                ModelOption(id: "claude::fable", instanceId: "claude", name: "Fable 5.2", provider: .claude),
                ModelOption(id: "opencode::ds", instanceId: "opencode", name: "DeepSeek V4", provider: .opencode, subProvider: "OpenRouter"),
            ]
        )
        #expect(ModelPickerLogic.locationLabel(catalog.models[0], in: catalog) == "Claude")
        #expect(ModelPickerLogic.locationLabel(catalog.models[1], in: catalog) == "OpenCode via OpenRouter")
        #expect(ModelPickerLogic.matches(catalog.models[0], needle: "fable work@example", in: catalog))
        #expect(ModelPickerLogic.matches(catalog.models[1], needle: "openrouter deepseek", in: catalog))
        #expect(!ModelPickerLogic.matches(catalog.models[1], needle: "claude deepseek", in: catalog))
        #expect(ModelPickerLogic.harness("missing", in: catalog).label == "missing")
    }
}

@Suite("Model picker navigation")
struct ModelPickerNavigationTests {
    let catalog = MockData.pickerCatalog
    let opus = MockData.models[0]

    func content(_ session: ModelPickerSession, current: ModelOption? = nil) -> ModelPickerContent {
        let current = current ?? opus
        return ModelPickerContent(catalog: catalog, session: session, currentModel: current, currentInstanceId: current.instanceId, offersPanelAction: true)
    }

    @discardableResult
    func press(_ key: ModelPickerKey, _ session: inout ModelPickerSession, level: String? = "high") -> ModelPickerCommand?? {
        ModelPickerLogic.handle(key, session: &session, content: content(session), currentLevelID: level)
    }

    @Test func opensOnTheCurrentProviderWithSearchFocused() {
        let codex = ModelPickerSession(catalog: catalog, currentInstanceId: "codex_personal")
        #expect(codex.browsingGroupID == "codex")
        #expect(codex.focus == .search)
        let session = ModelPickerSession(catalog: catalog, currentInstanceId: "claudeAgent")
        let view = content(session)
        #expect(view.activeHarness?.id == "claudeAgent")
        #expect(view.rows.map(\.name) == ["Opus 5.5", "Sonnet 5.5", "Haiku 5.5", "Fable 5.2"])
        #expect(view.thinkingLevels.count == 5)
    }

    @Test func groupOpensOnTheThreadsAccount() {
        var session = ModelPickerSession(catalog: catalog, currentInstanceId: "codex_personal")
        let personal = MockData.models.first { $0.instanceId == "codex_personal" }!
        let view = ModelPickerContent(catalog: catalog, session: session, currentModel: personal, currentInstanceId: "codex_personal", offersPanelAction: true)
        #expect(view.activeHarness?.id == "codex_personal")
        #expect(view.hasAccountSwitcher)
        session.selectAccount("codex", inGroup: "codex")
        #expect(ModelPickerContent(catalog: catalog, session: session, currentModel: personal, currentInstanceId: "codex_personal", offersPanelAction: true).activeHarness?.id == "codex")
    }

    @Test func searchIsFlatAcrossProvidersAndReturnPicksTheFirst() {
        var session = ModelPickerSession(catalog: catalog, currentInstanceId: "claudeAgent")
        session.setQuery("gpt")
        let view = content(session)
        #expect(view.searchResults.map(\.id) == ["codex::gpt", "codex::luna", "codex_personal::gpt", "codex_personal::astra"])
        #expect(!view.hasAccountSwitcher)
        #expect(press(.enter, &session) == .some(.pick(view.searchResults[0])))
        // Left and right stay with the field so the caret can move.
        #expect(press(.left, &session) == nil)
        #expect(press(.down, &session) == .some(nil))
        #expect(session.focus == .row(0))
        press(.down, &session)
        #expect(press(.enter, &session) == .some(.pick(view.searchResults[1])))
        // Typing again returns the highlight to the field.
        session.setQuery("gpt 6")
        #expect(session.focus == .search)
    }

    @Test func downFromSearchLandsOnTheCurrentModel() {
        var session = ModelPickerSession(catalog: catalog, currentInstanceId: "claudeAgent")
        let sonnet = MockData.models[1]
        _ = ModelPickerLogic.handle(.down, session: &session, content: content(session, current: sonnet), currentLevelID: nil)
        #expect(session.focus == .row(1))
    }

    @Test func railWalksGroupsAndHandsOffToThePanel() {
        var session = ModelPickerSession(catalog: catalog, currentInstanceId: "claudeAgent")
        session.focus = .rail
        press(.down, &session)
        #expect(session.browsingGroupID == "codex")
        #expect(session.groupStep == 1)
        // A multi-account group enters on its switcher.
        press(.right, &session)
        #expect(session.focus == .accounts)
        press(.right, &session)
        #expect(content(session).activeHarness?.id == "codex_personal")
        press(.down, &session)
        #expect(session.focus == .row(0))
        press(.left, &session)
        #expect(session.focus == .rail)
        press(.up, &session)
        #expect(session.browsingGroupID == "claudeAgent")
        #expect(session.groupStep == -1)
        press(.up, &session)
        #expect(session.focus == .search)
    }

    @Test func rowsWalkIntoTheThinkingSliderWhichSetsLevels() {
        var session = ModelPickerSession(catalog: catalog, currentInstanceId: "claudeAgent")
        session.focus = .row(3)
        press(.down, &session)
        #expect(session.focus == .thinking)
        #expect(press(.right, &session, level: "high") == .some(.selectLevel("xhigh")))
        #expect(press(.left, &session, level: "low") == .some(nil))
        press(.up, &session)
        #expect(session.focus == .row(3))
        session.focus = .row(0)
        press(.up, &session)
        #expect(session.focus == .search)
        #expect(press(.escape, &session) == .some(.close))
    }

    @Test func signedOutProviderOffersItsActionAndSubProvidersSection() {
        var session = ModelPickerSession(catalog: catalog, currentInstanceId: "claudeAgent")
        session.selectGroup("antigravity", in: content(session).groups)
        let signedOut = content(session)
        #expect(signedOut.rows.isEmpty)
        #expect(signedOut.hasPanelAction)
        session.focus = .rail
        press(.right, &session)
        #expect(session.focus == .action)
        #expect(press(.enter, &session) == .some(.panelAction(harnessID: "antigravity")))

        session.selectGroup("opencode", in: signedOut.groups)
        let open = content(session)
        #expect(open.sections.map(\.title) == ["OpenRouter", "Anthropic API"])
        #expect(open.sections[1].unavailableReason == "No API key")
        #expect(open.rows.map(\.name) == ["DeepSeek V4", "Kimi K3"])
    }

    @Test func modelWithoutLevelsHasNoSlider() {
        let cursor = MockData.models.first { $0.instanceId == "cursor" }!
        let session = ModelPickerSession(catalog: catalog, currentInstanceId: "cursor")
        #expect(!content(session, current: cursor).hasThinkingSlider)
    }
}

@Suite("Model picker catalog adapter")
struct ModelPickerAdapterTests {
    func provider(_ id: String, driver: String = "codex", displayName: String? = nil, accent: String? = nil, enabled: Bool = true, installed: Bool = true, status: ServerProviderState = .ready, auth: ServerProviderAuth = .init(status: .authenticated, label: "ChatGPT", email: "work@example.com"), message: String? = nil, models: [ServerProviderModel] = [.init(slug: "gpt", name: "GPT-6.1", badge: "new")], subProviders: [ServerProviderSubProvider]? = nil) -> ServerProvider {
        ServerProvider(instanceId: id, driver: driver, displayName: displayName, accentColor: accent, enabled: enabled, installed: installed, status: status, auth: auth, checkedAt: Date(), message: message, models: models, subProviders: subProviders)
    }

    @Test func mapsIdentityAvailabilityAndModels() {
        let catalog = SwftAdapters.pickerCatalog(from: [
            provider("codex", accent: " #3B82F6 "),
            provider("codex_personal", displayName: "Codex Personal", accent: "not-a-hex", status: .warning, auth: .init(status: .unauthenticated, label: "ChatGPT"), models: []),
            provider("off", enabled: false),
            provider("cursor", driver: "cursor", installed: false),
        ])
        #expect(catalog.harnesses.map(\.id) == ["codex", "codex_personal", "cursor"])
        let codex = catalog.harnesses[0]
        #expect(codex.accentHex == "#3b82f6")
        #expect(codex.account == "ChatGPT · work@example.com")
        #expect(codex.unavailableReason == nil)
        let personal = catalog.harnesses[1]
        #expect(personal.label == "Codex Personal")
        #expect(personal.unauthenticated)
        #expect(personal.unavailableReason == "Not signed in")
        #expect(personal.accentHex == nil)
        #expect(personal.account == nil)
        #expect(catalog.harnesses[2].unavailableReason == "Not installed")
        #expect(catalog.models.first?.isNew == true)
    }

    @Test func carriesSubProviders() {
        let catalog = SwftAdapters.pickerCatalog(from: [
            provider("opencode", driver: "opencode", status: .warning, models: [.init(slug: "ds", name: "DeepSeek V4", subProvider: "OpenRouter")], subProviders: [.init(name: "OpenRouter"), .init(name: "Anthropic", unavailableReason: "No API key")]),
        ])
        #expect(catalog.harnesses[0].unavailableReason == nil)
        #expect(catalog.harnesses[0].subProviders?.count == 2)
        #expect(catalog.models.first?.subProvider == "OpenRouter")
    }
}
