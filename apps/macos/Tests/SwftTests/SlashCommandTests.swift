import Foundation
import Testing
@testable import Swft
@testable import SwftKit

@Suite("Slash Command Logic")
struct SlashCommandLogicTests {
    @Test func detectsTriggerAtStartAndMidPromptWhileIgnoringPaths() {
        let bare = SlashCommandLogic.detectTrigger(in: "/")
        #expect(bare == SlashCommandTrigger(query: "", rangeStart: 0, rangeEnd: 1, isAtPromptStart: true))

        let prefix = SlashCommandLogic.detectTrigger(in: "/lea")
        #expect(prefix == SlashCommandTrigger(query: "lea", rangeStart: 0, rangeEnd: 4, isAtPromptStart: true))

        let indented = SlashCommandLogic.detectTrigger(in: "  /comp")
        #expect(indented == SlashCommandTrigger(query: "comp", rangeStart: 2, rangeEnd: 7, isAtPromptStart: true))

        let midPrompt = SlashCommandLogic.detectTrigger(in: "Switch via /mod")
        #expect(midPrompt == SlashCommandTrigger(query: "mod", rangeStart: 11, rangeEnd: 15, isAtPromptStart: false))

        let midCursor = SlashCommandLogic.detectTrigger(in: "Please /mod now", cursorUTF16: 11)
        #expect(midCursor == SlashCommandTrigger(query: "mod", rangeStart: 7, rangeEnd: 11, isAtPromptStart: false))

        // Trailing space ends the token.
        #expect(SlashCommandLogic.detectTrigger(in: "/learn ") == nil)
        #expect(SlashCommandLogic.detectTrigger(in: "plain text") == nil)

        // File paths with a second slash or backslash are ignored, even if caret precedes the second slash.
        #expect(SlashCommandLogic.detectTrigger(in: "/usr/bin") == nil)
        #expect(SlashCommandLogic.detectTrigger(in: "/src/a.ts", cursorUTF16: 3) == nil)
        #expect(SlashCommandLogic.detectTrigger(in: "open /Users/dev/file.swift") == nil)
        #expect(SlashCommandLogic.detectTrigger(in: #"/foo\bar"#, cursorUTF16: 3) == nil)
    }

    @Test func replacesTriggerRangeAndSwallowsDuplicateTrailingSpace() {
        let atStart = SlashCommandLogic.replaceRange(in: "/lea", rangeStart: 0, rangeEnd: 4, replacement: "/learn ")
        #expect(atStart.text == "/learn ")
        #expect(atStart.cursorUTF16 == 7)

        let beforeSpace = SlashCommandLogic.replaceRange(
            in: "/lea existing args",
            rangeStart: 0,
            rangeEnd: 4,
            replacement: "/learn "
        )
        #expect(beforeSpace.text == "/learn existing args")
        #expect(beforeSpace.cursorUTF16 == 7)

        let clearBuiltIn = SlashCommandLogic.replaceRange(
            in: "hello /mod world",
            rangeStart: 6,
            rangeEnd: 10,
            replacement: "",
            swallowTrailingSpace: false
        )
        #expect(clearBuiltIn.text == "hello  world")
        #expect(clearBuiltIn.cursorUTF16 == 6)
    }

    @Test func buildsCatalogWithDeduplicationPromptPositionAndSkillFiltering() {
        let providerCommands = [
            ServerProviderSlashCommand(name: "learn", description: "Save instructions", input: .init(hint: "topic")),
            ServerProviderSlashCommand(name: "clear", description: "Provider clear should be hidden"),
            ServerProviderSlashCommand(name: "test-t3-app", description: "Duplicate of visible skill"),
            ServerProviderSlashCommand(name: "compact", description: "Compact thread"),
        ]
        let skills = [
            ServerProviderSkill(name: "test-t3-app", description: "Browser testing", path: "/repo/.agents/skills/test-t3-app/SKILL.md", scope: "repo", enabled: true),
            ServerProviderSkill(name: "agent-only", path: "/repo/.agents/skills/a/SKILL.md", enabled: true, userInvocable: false),
            ServerProviderSkill(name: "disabled", path: "/repo/.agents/skills/d/SKILL.md", enabled: false),
            ServerProviderSkill(name: "test-t3-app", description: "Duplicate name", path: "/other/SKILL.md", scope: "user", enabled: true),
        ]

        let atStart = SlashCommandLogic.catalog(
            providerCommands: providerCommands,
            providerSkills: skills,
            providerLabel: "Antigravity",
            providerDriver: "antigravity",
            isAtPromptStart: true,
            supportsFreshSession: true,
            supportsSideChat: true,
            supportsPlanModeToggle: true
        )
        #expect(atStart.map(\.label) == ["/model", "/clear", "/plan", "/side", "/btw", "/learn", "/compact", "/skill:test-t3-app"])

        // Mid-prompt only keeps `/model` and user-invocable skills.
        let midPrompt = SlashCommandLogic.catalog(
            providerCommands: providerCommands,
            providerSkills: skills,
            providerLabel: "Antigravity",
            providerDriver: "antigravity",
            isAtPromptStart: false,
            supportsFreshSession: true,
            supportsSideChat: true,
            supportsPlanModeToggle: true
        )
        #expect(midPrompt.map(\.label) == ["/model", "/skill:test-t3-app"])
    }

    @Test func providerPlanCommandSuppressesBuiltInPlanToggle() {
        let items = SlashCommandLogic.catalog(
            providerCommands: [ServerProviderSlashCommand(name: "plan", description: "Provider plan")],
            providerSkills: [],
            providerLabel: "Antigravity",
            providerDriver: "antigravity",
            isAtPromptStart: true,
            supportsFreshSession: false,
            supportsSideChat: false,
            supportsPlanModeToggle: true
        )
        let planItems = items.filter { $0.name == "plan" }
        #expect(planItems.count == 1)
        #expect(planItems[0].group == .provider)
    }

    @Test func filtersAndRanksExactPrefixFuzzyAndSkillQueries() {
        let items = SlashCommandLogic.catalog(
            providerCommands: [
                ServerProviderSlashCommand(name: "learn", description: "Persist learnings"),
                ServerProviderSlashCommand(name: "compact", description: "Compact context"),
                ServerProviderSlashCommand(name: "grill-me", description: "Interactive design interview"),
                ServerProviderSlashCommand(name: "goal", description: "Autonomous goal mode"),
            ],
            providerSkills: [
                ServerProviderSkill(name: "test-t3-app", description: "Browser panel UI verification", path: "/repo/.agents/skills/test-t3-app/SKILL.md", scope: "repo", enabled: true),
            ],
            providerLabel: "Antigravity",
            providerDriver: "antigravity",
            isAtPromptStart: true,
            supportsFreshSession: true,
            supportsSideChat: false,
            supportsPlanModeToggle: false
        )

        #expect(SlashCommandLogic.filterAndRank(items, query: "lea").first?.name == "learn")
        #expect(SlashCommandLogic.filterAndRank(items, query: "comp").first?.name == "compact")
        #expect(SlashCommandLogic.filterAndRank(items, query: "mod").first?.name == "model")
        #expect(SlashCommandLogic.filterAndRank(items, query: "gm").first?.name == "grill-me")
        #expect(SlashCommandLogic.filterAndRank(items, query: "skill:test").first?.name == "test-t3-app")
        #expect(SlashCommandLogic.filterAndRank(items, query: "zzzz").isEmpty)

        // Browsing (empty query) groups into sections; searching returns a single flat ranked section.
        let browsingSections = SlashCommandLogic.sections(for: items, query: "", providerLabel: "Antigravity")
        #expect(browsingSections.map(\.title) == ["Built-in", "Antigravity", "Skills"])
        let searchSections = SlashCommandLogic.sections(for: SlashCommandLogic.filterAndRank(items, query: "lea"), query: "lea", providerLabel: "Antigravity")
        #expect(searchSections.count == 1)
        #expect(searchSections[0].title == nil)
    }

    @Test func resolvesSkillSourceKindsFromPathAndScope() {
        #expect(SlashCommandLogic.resolveSkillSourceKind(path: "/Users/dev/.codex/plugins/foo/SKILL.md", scope: "user") == .app)
        #expect(SlashCommandLogic.resolveSkillSourceKind(path: "/Users/dev/.agents/plugins/bar/SKILL.md", scope: nil) == .app)
        #expect(SlashCommandLogic.resolveSkillSourceKind(path: "/repo/SKILL.md", scope: "repo") == .repo)
        #expect(SlashCommandLogic.resolveSkillSourceKind(path: "/repo/SKILL.md", scope: "workspace") == .project)
        #expect(SlashCommandLogic.resolveSkillSourceKind(path: "/home/SKILL.md", scope: "user") == .personal)
        #expect(SlashCommandLogic.resolveSkillSourceKind(path: "/sys/SKILL.md", scope: "system") == .system)
        #expect(SlashCommandLogic.resolveSkillSourceKind(path: "/misc/SKILL.md", scope: nil) == .other)
    }

    @Test func workspaceSnapshotFreshnessRespectsTTLAndCooldown() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let freshSnapshot = ServerProviderWorkspaceSnapshot(
            cwd: "/repo",
            checkedAt: now.addingTimeInterval(-60),
            slashCommands: [],
            slashCommandsPending: false,
            skills: []
        )
        let pendingSnapshot = ServerProviderWorkspaceSnapshot(
            cwd: "/repo",
            checkedAt: now.addingTimeInterval(-60),
            slashCommands: [],
            slashCommandsPending: true,
            skills: []
        )
        let providerWithFresh = makeTestProvider(instanceId: "antigravity", driver: "antigravity", snapshots: [freshSnapshot])
        let providerWithPending = makeTestProvider(instanceId: "antigravity", driver: "antigravity", snapshots: [pendingSnapshot])

        #expect(SlashCommandLogic.shouldRefreshWorkspaceSnapshot(provider: providerWithFresh, cwd: "/repo", lastRequestedAt: nil, now: now) == false)
        #expect(SlashCommandLogic.shouldRefreshWorkspaceSnapshot(provider: providerWithFresh, cwd: "/other", lastRequestedAt: nil, now: now) == true)
        #expect(SlashCommandLogic.shouldRefreshWorkspaceSnapshot(provider: providerWithPending, cwd: "/repo", lastRequestedAt: nil, now: now) == true)
        #expect(SlashCommandLogic.shouldRefreshWorkspaceSnapshot(provider: providerWithPending, cwd: "/repo", lastRequestedAt: now.addingTimeInterval(-3), now: now) == false)
        #expect(SlashCommandLogic.shouldRefreshWorkspaceSnapshot(provider: providerWithPending, cwd: "/repo", lastRequestedAt: now.addingTimeInterval(-15), now: now) == true)
    }
}

@MainActor
@Suite("Slash Command AppModel Integration")
struct SlashCommandAppModelTests {
    @Test func mockModeExposesBuiltInProviderCommandsAndSkillsAndFiltersByModel() {
        let model = AppModel.mock()
        model.composerText = "/"

        #expect(model.isSlashCommandMenuOpen)
        let labels = model.slashCommandItems.map(\.label)
        #expect(labels.contains("/model"))
        #expect(labels.contains("/clear"))
        #expect(labels.contains("/learn"))
        #expect(labels.contains("/compact"))
        #expect(labels.contains("/plan"))
        #expect(labels.contains("/skill:test-t3-app"))

        // Switching to Codex surfaces Codex's `/review` command.
        let codexModel = MockData.models.first { $0.instanceId == "codex" }!
        model.selectModel(codexModel)
        #expect(model.slashCommandItems.map(\.label).contains("/review"))
    }

    @Test func keyboardNavigationSelectionAndEscapeDismissal() {
        let model = AppModel.mock()
        model.composerText = "/"
        let initialItems = model.slashCommandItems
        #expect(initialItems.count >= 5)
        #expect(model.highlightedSlashCommandID == initialItems[0].id)

        // Down moves to second item; Up wraps around cleanly.
        #expect(model.handleSlashCommandKey(.down) == true)
        #expect(model.highlightedSlashCommandID == initialItems[1].id)
        #expect(model.handleSlashCommandKey(.up) == true)
        #expect(model.highlightedSlashCommandID == initialItems[0].id)
        #expect(model.handleSlashCommandKey(.up) == true)
        #expect(model.highlightedSlashCommandID == initialItems.last?.id)

        // Escape dismisses for this trigger and stays dismissed while continuing the same token.
        #expect(model.handleSlashCommandKey(.escape) == true)
        #expect(model.isSlashCommandMenuOpen == false)
        model.composerText = "/lea"
        #expect(model.isSlashCommandMenuOpen == false)

        // Clearing the token and typing a new `/` re-opens the menu.
        model.composerText = ""
        model.composerText = "/lea"
        #expect(model.isSlashCommandMenuOpen == true)
        #expect(model.slashCommandItems.first?.name == "learn")

        // Tab selects `/learn`, inserts `/learn `, places cursor after space, and closes menu.
        #expect(model.handleSlashCommandKey(.tab) == true)
        #expect(model.composerText == "/learn ")
        #expect(model.composerCursorUTF16 == 7)
        #expect(model.pendingComposerCursorUTF16 == 7)
        #expect(model.isSlashCommandMenuOpen == false)
    }

    @Test func returnKeySelectsCommandInsteadOfSubmittingIncompletePrompt() {
        let model = AppModel.mock()
        model.open(MockData.threadDetail.summary.id)
        let beforeCount = model.detail(for: MockData.threadDetail.summary.id)?.items.count ?? 0

        model.composerText = "/comp"
        #expect(model.isSlashCommandMenuOpen == true)
        #expect(model.handleSlashCommandKey(.enter) == true)

        #expect(model.composerText == "/compact ")
        #expect(model.isSlashCommandMenuOpen == false)
        #expect((model.detail(for: MockData.threadDetail.summary.id)?.items.count ?? 0) == beforeCount)
    }

    @Test func builtInModelClearAndSideCommandsExecuteCorrectly() {
        let model = AppModel.mock()

        // `/model` opens the model picker and clears the trigger.
        model.composerText = "/mod"
        #expect(model.handleSlashCommandKey(.enter) == true)
        #expect(model.composerText == "")
        #expect(model.modelPicker != nil)
        #expect(model.isSlashCommandMenuOpen == false)
        model.closeModelPicker()

        // `/clear` inside a thread arms fresh session, and sending disarms it.
        model.open(MockData.threadDetail.summary.id)
        model.composerText = "/cl"
        #expect(model.handleSlashCommandKey(.enter) == true)
        #expect(model.composerText == "")
        #expect(model.isFreshSessionArmedForActiveThread == true)

        model.composerText = "Fresh start question"
        model.send()
        #expect(model.isFreshSessionArmedForActiveThread == false)

        // Verbatim `/clear` sent directly also arms fresh session instead of posting `/clear` text.
        let countBeforeClear = model.detail(for: MockData.threadDetail.summary.id)?.items.count ?? 0
        model.composerText = "/clear"
        model.send()
        #expect(model.isFreshSessionArmedForActiveThread == true)
        #expect((model.detail(for: MockData.threadDetail.summary.id)?.items.count ?? 0) == countBeforeClear)

        // `/side` hook handles `/side <prompt>` cleanly.
        var capturedSidePrompt: String?
        model.onSideChatCommand = { capturedSidePrompt = $0 }
        model.composerText = "/si"
        #expect(model.slashCommandItems.first?.name == "side")
        #expect(model.handleSlashCommandKey(.tab) == true)
        #expect(model.composerText == "/side ")
        model.composerText = "/side quick check"
        model.send()
        #expect(capturedSidePrompt == "quick check")
        #expect(model.composerText == "")
    }

    @Test func mutualExclusionWithModelPickerAndProjectPicker() {
        let model = AppModel.mock()
        model.composerText = "/lea"
        #expect(model.isSlashCommandMenuOpen == true)

        model.toggleProjectPicker()
        #expect(model.isProjectPickerOpen == true)
        #expect(model.isSlashCommandMenuOpen == false)

        model.closeProjectPicker()
        model.composerText = ""
        model.composerText = "/lea"
        #expect(model.isSlashCommandMenuOpen == true)

        model.toggleModelPicker()
        #expect(model.modelPicker != nil)
        #expect(model.isSlashCommandMenuOpen == false)
    }

    @Test func routesSlashCommandsBetweenLocalAndRemoteEnvironmentsAndWorkspaceSnapshots() {
        let localURL = URL(string: "http://127.0.0.1:3773")!
        let localConn = ServerConnection(httpBaseURL: localURL, credential: .bootstrapToken("local"))
        let localStore = ThreadsStore(connection: localConn)
        let localSnapshot = ServerProviderWorkspaceSnapshot(
            cwd: "/Users/local/swft",
            checkedAt: Date(),
            slashCommands: [
                ServerProviderSlashCommand(name: "local-workspace-cmd", description: "From local workspace snapshot"),
            ],
            skills: []
        )
        let localProvider = makeTestProvider(
            instanceId: "antigravity",
            driver: "antigravity",
            displayName: "Antigravity",
            slashCommands: [
                ServerProviderSlashCommand(name: "local-machine-cmd", description: "From local machine"),
            ],
            snapshots: [localSnapshot]
        )
        let localDescriptor = seedStore(
            localStore,
            envID: "env-local",
            label: "Local Mac",
            providers: [localProvider],
            projects: [makeTestProject(id: "p-local", title: "Swft", root: "/Users/local/swft")]
        )

        let remoteURL = URL(string: "https://vps.example.com")!
        let remoteConn = ServerConnection(httpBaseURL: remoteURL, credential: .bootstrapToken("remote"))
        let remoteStore = ThreadsStore(connection: remoteConn)
        let remoteProvider = makeTestProvider(
            instanceId: "claudeAgent",
            driver: "claudeAgent",
            displayName: "Claude Remote",
            slashCommands: [
                ServerProviderSlashCommand(name: "remote-deploy", description: "Deploy on remote VPS", input: .init(hint: "env")),
            ],
            skills: [
                ServerProviderSkill(name: "vps-health", path: "/srv/app/.agents/skills/vps-health/SKILL.md", scope: "project", enabled: true),
            ]
        )
        let remoteDescriptor = seedStore(
            remoteStore,
            envID: "env-vps",
            label: "Build VPS",
            providers: [remoteProvider],
            projects: [makeTestProject(id: "p-remote", title: "App", root: "/srv/app")]
        )

        let model = AppModel.testingLive(localStore: localStore)
        model.localWorkspaceDirectoryExists = { _ in true }
        model.registerLocalEnvironment(
            endpoint: ServerEndpoint(
                httpBaseURL: localURL,
                wsBaseURL: URL(string: "ws://127.0.0.1:3773/ws")!,
                port: 3773,
                bootstrapToken: "local",
                pid: 1,
                baseDirectory: FileManager.default.temporaryDirectory,
                environment: localDescriptor
            ),
            connection: localConn,
            store: localStore
        )
        let remoteEntry = ManagedEnvironment(
            id: remoteDescriptor.environmentId,
            isLocal: false,
            httpBaseURL: remoteURL,
            connection: remoteConn,
            threadsStore: remoteStore,
            lastKnownLabel: "Build VPS",
            lastKnownMachine: "server",
            lastKnownOS: "linux",
            lastKnownServerVersion: "0.2.0"
        )
        model.environmentRegistry.insertEnvironmentForTesting(remoteEntry)

        // Targeting local environment with `/Users/local/swft` project uses local workspace snapshot commands.
        model.selectedProjectID = "p-local"
        model.composerText = "/"
        let localNames = model.slashCommandItems.map(\.name)
        #expect(localNames.contains("local-workspace-cmd"))
        #expect(!localNames.contains("remote-deploy"))

        // Switching Home composer to remote VPS surfaces remote provider's slash commands & skills!
        model.selectEnvironment("env-vps")
        model.composerText = "/"
        let remoteNames = model.slashCommandItems.map(\.name)
        #expect(remoteNames.contains("remote-deploy"))
        #expect(remoteNames.contains("vps-health"))
        #expect(!remoteNames.contains("local-workspace-cmd"))
    }
}

// MARK: - Test Helpers

private func makeTestProvider(
    instanceId: String,
    driver: String,
    displayName: String? = nil,
    slashCommands: [ServerProviderSlashCommand] = [],
    skills: [ServerProviderSkill] = [],
    snapshots: [ServerProviderWorkspaceSnapshot]? = nil
) -> ServerProvider {
    ServerProvider(
        instanceId: instanceId,
        driver: driver,
        displayName: displayName,
        enabled: true,
        installed: true,
        status: .ready,
        auth: ServerProviderAuth(status: .authenticated),
        checkedAt: Date(),
        models: [ServerProviderModel(slug: "default-model", name: "Default Model", isDefault: true)],
        slashCommands: slashCommands,
        skills: skills,
        workspaceSnapshots: snapshots
    )
}

private func makeTestProject(id: String, title: String, root: String) -> ProjectShell {
    ProjectShell(
        id: id,
        title: title,
        workspaceRoot: root,
        createdAt: Date(),
        updatedAt: Date()
    )
}

@MainActor
@discardableResult
private func seedStore(
    _ store: ThreadsStore,
    envID: String,
    label: String,
    providers: [ServerProvider],
    projects: [ProjectShell]
) -> ExecutionEnvironmentDescriptor {
    let descriptor = ExecutionEnvironmentDescriptor(
        environmentId: envID,
        label: label,
        platform: ExecutionEnvironmentPlatform(os: "darwin", arch: "arm64"),
        serverVersion: "0.2.0",
        capabilities: ExecutionEnvironmentCapabilities(freshContext: true)
    )
    let config = ServerConfig(
        environment: descriptor,
        auth: ServerAuthDescriptor(policy: "local", bootstrapMethods: [], sessionMethods: [], sessionCookieName: "t3"),
        cwd: projects.first?.workspaceRoot ?? "/",
        providers: providers
    )
    store.applyConnectionState(.connected(descriptor))
    store.apply(.snapshot(config))
    store.apply(.snapshot(
        ShellSnapshot(snapshotSequence: 1, projects: projects, threads: [], archivedThreads: []),
        resolvedRepositoryIdentityRoots: nil
    ))
    return descriptor
}
