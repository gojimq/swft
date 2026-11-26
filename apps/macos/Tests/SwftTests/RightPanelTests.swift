import Foundation
import SwftDesign
import Testing
@testable import Swft
@testable import SwftKit

@Suite("Right Panel Surfaces, Tab System & Multi-Environment Routing")
struct RightPanelTests {

    // MARK: - Strict Surface Inclusions & Exclusions

    @Test func exposesExactlyFiveIncludedSurfacesAndExcludesTerminalDiffPullRequest() {
        let kinds = RightPanelSurfaceKind.allCases
        #expect(kinds == [.browser, .files, .linkedItems, .device, .sideChat])
        #expect(kinds.count == 5)

        // Included single-key shortcuts (case-insensitive)
        #expect(RightPanelLogic.surfaceKind(forKey: "B") == .browser)
        #expect(RightPanelLogic.surfaceKind(forKey: "b") == .browser)
        #expect(RightPanelLogic.surfaceKind(forKey: "F") == .files)
        #expect(RightPanelLogic.surfaceKind(forKey: "f") == .files)
        #expect(RightPanelLogic.surfaceKind(forKey: "L") == .linkedItems)
        #expect(RightPanelLogic.surfaceKind(forKey: "l") == .linkedItems)
        #expect(RightPanelLogic.surfaceKind(forKey: "M") == .device)
        #expect(RightPanelLogic.surfaceKind(forKey: "m") == .device)
        #expect(RightPanelLogic.surfaceKind(forKey: "S") == .sideChat)
        #expect(RightPanelLogic.surfaceKind(forKey: "s") == .sideChat)

        // Deliberately excluded surfaces: Terminal (T), Diff (D), Pull request (P)
        #expect(RightPanelLogic.surfaceKind(forKey: "T") == nil)
        #expect(RightPanelLogic.surfaceKind(forKey: "t") == nil)
        #expect(RightPanelLogic.surfaceKind(forKey: "D") == nil)
        #expect(RightPanelLogic.surfaceKind(forKey: "d") == nil)
        #expect(RightPanelLogic.surfaceKind(forKey: "P") == nil)
        #expect(RightPanelLogic.surfaceKind(forKey: "p") == nil)

        // Never match when command/control/option modifiers are held
        #expect(RightPanelLogic.surfaceKind(forKey: "B", hasCommandOrControlOrOption: true) == nil)
        #expect(RightPanelLogic.surfaceKind(forKey: "F", hasCommandOrControlOrOption: true) == nil)
        #expect(RightPanelLogic.surfaceKind(forKey: "ab") == nil)
        #expect(RightPanelLogic.surfaceKind(forKey: "") == nil)
    }

    // MARK: - Tab Lifecycle & Per-Thread Persistence

    @Test @MainActor func managesTabsPerThreadWithIndependentState() {
        let store = RightPanelStore()
        let threadA = "thr-a"
        let threadB = "thr-b"

        #expect(!store.isOpen(for: threadA))
        #expect(store.tabs(for: threadA).isEmpty)

        // Toggle open & maximize, then closing clears maximize
        store.togglePanel(for: threadA)
        #expect(store.isOpen(for: threadA))
        store.toggleMaximized(for: threadA)
        #expect(store.isMaximized(for: threadA))
        store.togglePanel(for: threadA)
        #expect(!store.isOpen(for: threadA))
        #expect(!store.isMaximized(for: threadA))

        // Opening a new tab always appends a fresh launcher tab; picking a surface replaces only that tab
        let launcher1 = store.openLauncherTab(for: threadA)
        let launcher2 = store.openLauncherTab(for: threadA)
        #expect(launcher1.id != launcher2.id)
        #expect(store.tabs(for: threadA).count == 2)
        #expect(store.activeTab(for: threadA)?.id == launcher2.id)

        let browserTab = store.openSurface(.browser, for: threadA, replacingLauncherTabID: launcher2.id)
        #expect(store.tabs(for: threadA).count == 2)
        #expect(store.activeTab(for: threadA)?.id == browserTab.id)
        store.closeTab(launcher1.id, for: threadA)
        #expect(store.tabs(for: threadA).count == 1)

        // Update browser tab title & URL
        store.updateBrowserTab(
            tabID: browserTab.id,
            urlString: "http://localhost:5173",
            pageTitle: "Swft App",
            for: threadA
        )
        #expect(store.activeTab(for: threadA)?.title == "Swft App")

        // Open Files & Linked items tabs (Linked items deduplicates)
        let filesTab = store.openFiles(selectedFilePath: "Sources/Swft/AppModel.swift", for: threadA)
        #expect(filesTab.title == "AppModel.swift")
        let linked1 = store.openLinkedItems(for: threadA)
        let linked2 = store.openLinkedItems(for: threadA)
        #expect(linked1.id == linked2.id)
        #expect(store.tabs(for: threadA).count == 3)

        // Thread B has completely separate state
        #expect(!store.isOpen(for: threadB))
        #expect(store.tabs(for: threadB).isEmpty)
        let sideB = store.openSideChat(sideThreadId: "side-b-1", title: "Quick check", for: threadB)
        #expect(store.isOpen(for: threadB))
        #expect(store.tabs(for: threadB).count == 1)
        #expect(store.activeTab(for: threadB)?.id == sideB.id)
        #expect(store.tabs(for: threadA).count == 3)

        // Activate & close active tab selects neighbor
        store.activateTab(filesTab.id, for: threadA)
        #expect(store.activeTab(for: threadA)?.id == filesTab.id)
        store.closeTab(filesTab.id, for: threadA)
        #expect(store.tabs(for: threadA).count == 2)
        #expect(store.activeTab(for: threadA)?.id == linked1.id)

        // Close others & close all
        let secondBrowser = store.openBrowser(urlString: "https://t3.codes", for: threadA)
        #expect(store.tabs(for: threadA).count == 3)
        store.closeOtherTabs(keeping: secondBrowser.id, for: threadA)
        #expect(store.tabs(for: threadA).map(\.id) == [secondBrowser.id])
        store.closeAllTabs(for: threadA)
        #expect(store.tabs(for: threadA).isEmpty)
        #expect(store.activeTab(for: threadA) == nil)
        // Thread B remains untouched
        #expect(store.tabs(for: threadB).count == 1)
    }

    @Test @MainActor func tracksOpenFilesAndMultipleDeviceOrSideChatTabs() {
        let store = RightPanelStore()
        let threadID = "thr-files"

        let filesTab = store.openFiles(selectedFilePath: "README.md", for: threadID)
        store.updateFilesTab(tabID: filesTab.id, selectedFilePath: "Package.swift", folderPath: "", for: threadID)
        if case .files(let state) = store.activeTab(for: threadID)?.payload {
            #expect(state.openFilePaths == ["README.md", "Package.swift"])
            #expect(state.selectedFilePath == "Package.swift")
        } else {
            Issue.record("Expected files tab payload")
        }

        store.closeOpenFile("Package.swift", inTabID: filesTab.id, for: threadID)
        if case .files(let state) = store.activeTab(for: threadID)?.payload {
            #expect(state.openFilePaths == ["README.md"])
            #expect(state.selectedFilePath == "README.md")
        } else {
            Issue.record("Expected files tab payload after closing file")
        }

        // Device tab deduplicates by deviceId + hostId
        let dev1 = store.openDevice(hostId: "local", deviceId: "sim-1", platform: .ios, deviceName: "iPhone 16 Pro", for: threadID)
        let dev1Again = store.openDevice(hostId: "local", deviceId: "sim-1", platform: .ios, deviceName: "iPhone 16 Pro", for: threadID)
        let dev2 = store.openDevice(hostId: "local", deviceId: "emu-1", platform: .android, deviceName: "Pixel 9", for: threadID)
        #expect(dev1.id == dev1Again.id)
        #expect(dev1.id != dev2.id)
        #expect(dev1.title == "iPhone 16 Pro")
        #expect(dev2.iconName == "smartphone")
    }

    @Test func clampsPanelWidthWithinBoundsAndWindowBudget() {
        #expect(RightPanelLogic.clampedWidth(100) == RightPanelMetrics.minWidth)
        #expect(RightPanelLogic.clampedWidth(1500) == RightPanelMetrics.maxWidth)
        #expect(RightPanelLogic.clampedWidth(520, availableWindowWidth: 1200) == 520)
        // Small window reserves minChatColumnWidth for the transcript
        let constrained = RightPanelLogic.clampedWidth(700, availableWindowWidth: 920)
        #expect(constrained == max(RightPanelMetrics.minWidth, 920 - RightPanelMetrics.minChatColumnWidth))
    }

    // MARK: - Browser URL Normalization & Display Title

    @Test func normalizesBrowserURLsAndRejectsUnsafeSchemes() {
        #expect(RightPanelLogic.normalizeBrowserURL("t3.codes")?.absoluteString == "https://t3.codes")
        #expect(RightPanelLogic.normalizeBrowserURL("docs.swift.org/swift-book")?.absoluteString == "https://docs.swift.org/swift-book")
        #expect(RightPanelLogic.normalizeBrowserURL("localhost:3000")?.absoluteString == "http://localhost:3000")
        #expect(RightPanelLogic.normalizeBrowserURL("localhost:5173/settings")?.absoluteString == "http://localhost:5173/settings")
        #expect(RightPanelLogic.normalizeBrowserURL(":3000")?.absoluteString == "http://localhost:3000")
        #expect(RightPanelLogic.normalizeBrowserURL(":5173/chat")?.absoluteString == "http://localhost:5173/chat")
        #expect(RightPanelLogic.normalizeBrowserURL("127.0.0.1:8080")?.absoluteString == "http://127.0.0.1:8080")
        #expect(RightPanelLogic.normalizeBrowserURL("192.168.1.42:3000")?.absoluteString == "http://192.168.1.42:3000")
        #expect(RightPanelLogic.normalizeBrowserURL("10.0.0.8")?.absoluteString == "http://10.0.0.8")
        #expect(RightPanelLogic.normalizeBrowserURL("100.70.1.2:3773")?.absoluteString == "http://100.70.1.2:3773")
        #expect(RightPanelLogic.normalizeBrowserURL("macmini.local:5173")?.absoluteString == "http://macmini.local:5173")
        #expect(RightPanelLogic.normalizeBrowserURL("[::1]:4000")?.absoluteString == "http://[::1]:4000")
        #expect(RightPanelLogic.normalizeBrowserURL("https://localhost:8443")?.absoluteString == "https://localhost:8443")
        #expect(RightPanelLogic.normalizeBrowserURL("http://example.com")?.absoluteString == "http://example.com")

        // Rejected inputs
        #expect(RightPanelLogic.normalizeBrowserURL("") == nil)
        #expect(RightPanelLogic.normalizeBrowserURL("   ") == nil)
        #expect(RightPanelLogic.normalizeBrowserURL("javascript:alert(1)") == nil)
        #expect(RightPanelLogic.normalizeBrowserURL("file:///etc/passwd") == nil)
        #expect(RightPanelLogic.normalizeBrowserURL("data:text/html,hi") == nil)

        #expect(RightPanelLogic.displayBrowserTitle(title: "My App", urlString: "http://localhost:3000") == "My App")
        #expect(RightPanelLogic.displayBrowserTitle(title: nil, urlString: "http://localhost:5173/test") == "localhost:5173")
        #expect(RightPanelLogic.displayBrowserTitle(title: "  ", urlString: "https://github.com/pingdotgg/t3code") == "github.com")
        #expect(RightPanelLogic.displayBrowserTitle(title: nil, urlString: "") == "Browser")
    }

    // MARK: - Files Tree, Classification & PR URL Parsing

    @Test func buildsSortedFileTreeRowsAndClassifiesFiles() {
        let entries: [String: [ProjectEntry]] = [
            "": [
                ProjectEntry(path: "README.md", kind: .file),
                ProjectEntry(path: "Sources", kind: .directory),
                ProjectEntry(path: "Assets", kind: .directory),
                ProjectEntry(path: "Package.swift", kind: .file),
            ],
            "Sources": [
                ProjectEntry(path: "Sources/App.swift", kind: .file),
                ProjectEntry(path: "Sources/Kit", kind: .directory),
            ],
            "Sources/Kit": [
                ProjectEntry(path: "Sources/Kit/Client.swift", kind: .file),
            ],
        ]

        let rows = RightPanelLogic.buildFileTreeRows(
            entriesByDirectory: entries,
            expandedDirectories: ["Sources", "Sources/Kit"]
        )
        #expect(rows.map(\.path) == [
            "Assets",
            "Sources",
            "Sources/Kit",
            "Sources/Kit/Client.swift",
            "Sources/App.swift",
            "Package.swift",
            "README.md",
        ])
        #expect(rows.map(\.depth) == [0, 0, 1, 2, 1, 0, 0])

        let crumbs = RightPanelLogic.breadcrumbSegments(for: "Sources/Swft/AppModel.swift")
        #expect(crumbs.map(\.name) == ["Sources", "Swft", "AppModel.swift"])
        #expect(crumbs.map(\.path) == ["Sources", "Sources/Swft", "Sources/Swft/AppModel.swift"])
        #expect(RightPanelLogic.parentDirectory(of: "Sources/Swft/AppModel.swift") == "Sources/Swft")
        #expect(RightPanelLogic.parentDirectory(of: "README.md") == "")

        #expect(RightPanelLogic.classifyFilePreview(path: "README.md") == .markdown)
        #expect(RightPanelLogic.classifyFilePreview(path: "docs/guide.mdx") == .markdown)
        #expect(RightPanelLogic.classifyFilePreview(path: "Assets/hero.PNG") == .image)
        #expect(RightPanelLogic.classifyFilePreview(path: "build/app.zip") == .binary)
        #expect(RightPanelLogic.classifyFilePreview(path: "Sources/App.swift") == .code(language: "Swift"))
        #expect(RightPanelLogic.classifyFilePreview(path: "Dockerfile") == .code(language: "Dockerfile"))
        #expect(RightPanelLogic.formatByteCount(512) == "512 B")
        #expect(RightPanelLogic.formatByteCount(2_048) == "2.0 KB")
        #expect(RightPanelLogic.formatByteCount(2 * 1_024 * 1_024) == "2.0 MB")
    }

    @Test func parsesGitHubAndGitLabPullRequestURLs() {
        let gh = RightPanelLogic.parsePullRequestURL("https://github.com/pingdotgg/t3code/pull/1842/files")
        #expect(gh?.host == "github.com")
        #expect(gh?.repository == "pingdotgg/t3code")
        #expect(gh?.number == 1842)

        let gl = RightPanelLogic.parsePullRequestURL("https://gitlab.com/acme/platform/swft/-/merge_requests/99")
        #expect(gl?.host == "gitlab.com")
        #expect(gl?.repository == "acme/platform/swft")
        #expect(gl?.number == 99)

        #expect(RightPanelLogic.parsePullRequestURL("https://github.com/pingdotgg/t3code/issues/412") == nil)
        #expect(RightPanelLogic.parsePullRequestURL("not a url") == nil)
    }

    // MARK: - AppModel Mock Mode & Multi-Environment Routing

    @Test @MainActor func appModelMockSupportsAllFiveSurfacesAndToggling() {
        let model = AppModel.mock()
        let threadID = MockData.threadDetail.summary.id
        model.open(threadID)

        #expect(!model.isRightPanelOpenForActiveThread)
        model.toggleRightPanel()
        #expect(model.isRightPanelOpenForActiveThread)
        #expect(model.workspaceRoot(forThreadID: threadID) != nil)
        #expect(!model.linkedPullRequests(forThreadID: threadID).isEmpty)
        #expect(!model.linkedIssues(forThreadID: threadID).isEmpty)
        #expect(!model.relatedThreads(forThreadID: threadID, fetchedFamily: []).isEmpty)

        // Opening a mock side chat in main view seeds and navigates to it cleanly
        model.openSideChatInMainView("mock-side-promoted")
        #expect(model.selectedThreadID == "mock-side-promoted")
        #expect(model.detail(for: "mock-side-promoted") != nil)
    }

    @Test @MainActor func appModelRoutesRightPanelDataToOwningRemoteEnvironment() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let localBaseURL = URL(string: "http://127.0.0.1:4101")!
        let localConn = ServerConnection(httpBaseURL: localBaseURL, credential: .bootstrapToken("local"))
        let localStore = ThreadsStore(connection: localConn)
        let model = AppModel.testingLive(localStore: localStore)

        let localEndpoint = ServerEndpoint(
            httpBaseURL: localBaseURL,
            wsBaseURL: URL(string: "ws://127.0.0.1:4101")!,
            port: 4101,
            bootstrapToken: "local",
            pid: 101,
            baseDirectory: FileManager.default.temporaryDirectory,
            environment: ExecutionEnvironmentDescriptor(
                environmentId: "env-local",
                label: "MacBook Pro",
                platform: ExecutionEnvironmentPlatform(os: "darwin", arch: "arm64", machine: "laptop"),
                serverVersion: "0.1.11"
            )
        )
        model.registerLocalEnvironment(endpoint: localEndpoint, connection: localConn, store: localStore)

        let remoteDescriptor = ExecutionEnvironmentDescriptor(
            environmentId: "env-mini",
            label: "Mac Mini",
            platform: ExecutionEnvironmentPlatform(os: "darwin", arch: "arm64", machine: "desktop"),
            serverVersion: "0.1.11"
        )
        let remoteRegistry = EnvironmentRegistry(
            credentialStore: InMemoryCredentialStore(),
            recordStore: InMemoryEnvironmentRecordStore(),
            pairHandler: { target, _, _ in
                PairedRemoteSession(
                    descriptor: remoteDescriptor,
                    httpBaseURL: target.httpBaseURL,
                    accessToken: "mini-token",
                    scope: "orchestration:read orchestration:operate",
                    expiresIn: 86_400,
                    suggestedLabel: "Mac Mini"
                )
            }
        )
        let remoteEnv = try await remoteRegistry.pairRemote(
            address: "https://macmini.example.ts.net/pair#token=MINI",
            connectImmediately: false
        )

        // Seed a local scratch project + real project on the local store, and a remote project/thread with PRs/issues
        let localProject = ProjectShell(id: "proj-local", title: "LocalApp", workspaceRoot: "/Users/me/local", createdAt: now, updatedAt: now)
        let scratchProject = ProjectShell(id: "proj-scratch", title: "Scratch", workspaceRoot: "/tmp/scratch", createdAt: now, updatedAt: now)
        localStore.apply(ServerConfigStreamEvent.snapshot(ServerConfig(
            environment: localEndpoint.environment,
            auth: ServerAuthDescriptor(
                policy: "local",
                bootstrapMethods: [],
                sessionMethods: [],
                sessionCookieName: "t3_session"
            ),
            cwd: "/Users/me/local",
            providers: [],
            scratchWorkspaceRoot: "/tmp/scratch"
        )))

        let localThread = ThreadShell(
            id: "thr-local-wt",
            projectId: "proj-local",
            title: "Worktree task",
            providerInstanceId: "claudeAgent",
            modelSelection: ModelSelection(instanceId: "claudeAgent", model: "opus"),
            worktreePath: "/Users/me/worktrees/feat-x",
            pullRequests: [
                ThreadPullRequestLink(host: "github.com", repository: "org/repo", number: 10, url: "https://github.com/org/repo/pull/10", source: "agent", linkedAt: now),
                ThreadPullRequestLink(host: "github.com", repository: "org/repo", number: 11, url: "https://github.com/org/repo/pull/11", source: "stack-dismissed", linkedAt: now),
            ],
            issues: [
                ThreadIssueLink(tracker: "github", host: "github.com", scope: "org/repo", key: "55", projectId: "proj-local", url: "https://github.com/org/repo/issues/55", linkedAt: now, displayKey: "#55", title: "Fix sidebar"),
            ],
            createdAt: now,
            updatedAt: now
        )
        let scratchThread = ThreadShell(
            id: "thr-scratch",
            projectId: "proj-scratch",
            title: "Quick question",
            providerInstanceId: "claudeAgent",
            modelSelection: ModelSelection(instanceId: "claudeAgent", model: "opus"),
            createdAt: now,
            updatedAt: now
        )
        let childSideChat = ThreadShell(
            id: "thr-side-1",
            projectId: "proj-local",
            title: "Side chat",
            providerInstanceId: "claudeAgent",
            modelSelection: ModelSelection(instanceId: "claudeAgent", model: "opus"),
            lineage: ThreadLineage(parentThreadId: "thr-local-wt", relationshipToParent: "fork", rootThreadId: "thr-local-wt", sideChat: true),
            createdAt: now,
            updatedAt: now.addingTimeInterval(30)
        )
        localStore.apply(.snapshot(
            ShellSnapshot(snapshotSequence: 1, projects: [localProject, scratchProject], threads: [localThread, scratchThread, childSideChat]),
            resolvedRepositoryIdentityRoots: nil
        ))

        // Worktree path preferred over project root; scratch project returns nil
        #expect(model.workspaceRoot(forThreadID: "thr-local-wt") == "/Users/me/worktrees/feat-x")
        #expect(model.workspaceRoot(forThreadID: "thr-scratch") == nil)

        // Linked PRs filter out stack-dismissed; linked issues & related threads decode cleanly
        let prs = model.linkedPullRequests(forThreadID: "thr-local-wt")
        #expect(prs.map(\.number) == [10])
        #expect(model.linkedIssues(forThreadID: "thr-local-wt").map(\.displayKey) == ["#55"])

        let related = model.relatedThreads(forThreadID: "thr-local-wt", fetchedFamily: [])
        #expect(related.count == 1)
        #expect(related.first?.id == "thr-side-1")
        #expect(related.first?.relation == .sideChat)

        // Verify remote environment thread ownership works cleanly in EnvironmentRegistry
        let remoteProject = ProjectShell(id: "proj-mini", title: "MiniRepo", workspaceRoot: "/Users/mini/code/repo", createdAt: now, updatedAt: now)
        let remoteThread = ThreadShell(
            id: "thr-mini-1",
            projectId: "proj-mini",
            title: "Remote build",
            providerInstanceId: "codex",
            modelSelection: ModelSelection(instanceId: "codex", model: "gpt-6"),
            createdAt: now,
            updatedAt: now
        )
        remoteEnv.threadsStore.apply(.snapshot(
            ShellSnapshot(snapshotSequence: 1, projects: [remoteProject], threads: [remoteThread]),
            resolvedRepositoryIdentityRoots: nil
        ))
        #expect(remoteRegistry.environment(owningThreadID: "thr-mini-1")?.id == "env-mini")
        #expect(model.connection(forThreadID: "thr-local-wt") === localConn)
    }

    // MARK: - Subagent Tabs

    @Test @MainActor func subagentTabLifecycleDeduplicatesReplacesSoleLauncherAndPreservesNeighbors() {
        let store = RightPanelStore()
        let parentID = "thr-parent"

        // Opening a subagent when only an unused .launcher tab exists replaces the launcher tab.
        let launcher = store.openLauncherTab(for: parentID)
        #expect(store.tabs(for: parentID).map(\.id) == [launcher.id])

        let first = store.openSubagentTab(
            SubagentTabState(
                subagentThreadId: "sub-1",
                environmentId: "env-local",
                title: "Codebase Researcher",
                status: .running,
                modelLabel: "Opus 5.5",
                providerDisplayName: "Claude",
                providerDriver: "claudeAgent",
                workspaceLabel: "swft/audit"
            ),
            for: parentID
        )
        #expect(store.isOpen(for: parentID))
        #expect(store.tabs(for: parentID).count == 1)
        #expect(store.activeTab(for: parentID)?.id == first.id)
        #expect(first.surfaceKind == nil)
        #expect(first.title == "Codebase Researcher")
        #expect(first.iconName == "cpu")

        // Opening a second subagent appends a second tab alongside the first.
        let second = store.openSubagentTab(
            SubagentTabState(
                subagentThreadId: "sub-2",
                environmentId: "env-local",
                title: "Test Author",
                status: .waiting,
                modelLabel: "GPT-6.1"
            ),
            for: parentID
        )
        #expect(store.tabs(for: parentID).count == 2)
        #expect(store.activeTab(for: parentID)?.id == second.id)

        // Re-opening the first subagent reuses and activates its tab while merging updated metadata.
        let reopened = store.openSubagentTab(
            SubagentTabState(
                subagentThreadId: "sub-1",
                environmentId: "env-local",
                title: "Codebase Researcher",
                status: .completed
            ),
            for: parentID
        )
        #expect(reopened.id == first.id)
        #expect(store.tabs(for: parentID).count == 2)
        #expect(store.activeTab(for: parentID)?.id == first.id)
        if case .subagent(let merged) = store.activeTab(for: parentID)?.payload {
            #expect(merged.status == .completed)
            #expect(merged.modelLabel == "Opus 5.5")
            #expect(merged.workspaceLabel == "swft/audit")
        } else {
            Issue.record("Expected merged .subagent payload")
        }

        // Closing one subagent tab preserves the other and selects it.
        store.closeTab(first.id, for: parentID)
        #expect(store.tabs(for: parentID).map(\.id) == [second.id])
        #expect(store.activeTab(for: parentID)?.id == second.id)

        // Launcher tab is NOT replaced if another tab already exists alongside it.
        _ = store.openLauncherTab(for: parentID)
        #expect(store.tabs(for: parentID).count == 2)
        let third = store.openSubagentTab(
            SubagentTabState(subagentThreadId: "sub-3", environmentId: "env-local", title: "Reviewer", status: .idle),
            for: parentID
        )
        #expect(store.tabs(for: parentID).count == 3)
        #expect(store.activeTab(for: parentID)?.id == third.id)
    }

    @Test func resolvesSubagentTabTitlesAndStatusDotTones() {
        let blankTitleTab = RightPanelTab(
            id: "subagent:local:s0",
            payload: .subagent(SubagentTabState(subagentThreadId: "s0", title: "   ", status: .idle))
        )
        #expect(blankTitleTab.title == "Subagent")
        #expect(blankTitleTab.iconName == "cpu")
        #expect(blankTitleTab.surfaceKind == nil)

        let namedTab = RightPanelTab(
            id: "subagent:local:s1",
            payload: .subagent(SubagentTabState(subagentThreadId: "s1", title: "Reconnect Fixer", status: .running))
        )
        #expect(namedTab.title == "Reconnect Fixer")

        // Status dot tones for each subagent lifecycle status & live overrides
        #expect(RightPanelLogic.subagentStatusDotTone(status: .pending) == .accent)
        #expect(RightPanelLogic.subagentStatusDotTone(status: .running) == .accent)
        #expect(RightPanelLogic.subagentStatusDotTone(status: .waiting) == .warning)
        #expect(RightPanelLogic.subagentStatusDotTone(status: .completed) == .success)
        #expect(RightPanelLogic.subagentStatusDotTone(status: .failed) == .danger)
        #expect(RightPanelLogic.subagentStatusDotTone(status: .idle) == nil)
        #expect(RightPanelLogic.subagentStatusDotTone(status: .cancelled) == nil)
        #expect(RightPanelLogic.subagentStatusDotTone(status: .interrupted) == nil)

        // Live store overrides take precedence (approvals -> warning, live run -> accent)
        #expect(RightPanelLogic.subagentStatusDotTone(status: .completed, isLiveRunning: true) == .accent)
        #expect(RightPanelLogic.subagentStatusDotTone(status: .running, hasPendingApprovals: true, isLiveRunning: true) == .warning)
    }

    @Test @MainActor func syncsSubagentTabsFromParentUpdatesAndCleansUpStoresOnReleaseAndClose() {
        let store = RightPanelStore()
        let parentID = "thr-parent-sync"
        let conn = ServerConnection(httpBaseURL: URL(string: "http://127.0.0.1:4199")!, credential: .bootstrapToken("tok"))

        let tab = store.openSubagentTab(
            SubagentTabState(
                subagentThreadId: "child-sync-1",
                environmentId: "env-local",
                title: "Initial title",
                status: .running
            ),
            for: parentID
        )

        // Sync from updated parent SubagentItem refreshes title, status, model, and branch.
        let updatedItem = SubagentItem(
            id: "item-sync-1",
            title: "Updated Auditor",
            provider: .codex,
            providerDriver: "codex",
            providerDisplayName: "Codex",
            modelName: "GPT-6.1",
            status: .completed,
            prompt: "Audit sync",
            childThreadID: "child-sync-1",
            worktreeBranch: "fix/sync"
        )
        store.syncSubagentTabs(from: [updatedItem], parentEnvironmentID: "env-local", for: parentID)
        if case .subagent(let synced) = store.activeTab(for: parentID)?.payload {
            #expect(synced.title == "Updated Auditor")
            #expect(synced.status == .completed)
            #expect(synced.modelLabel == "GPT-6.1")
            #expect(synced.workspaceLabel == "fix/sync")
        } else {
            Issue.record("Expected synced .subagent tab")
        }

        // ThreadStore attach/release lifecycle prevents subscription leaks on tab switch and tab close.
        let threadStore = store.ensureSubagentStore(
            subagentThreadId: "child-sync-1",
            connection: conn,
            holderTabID: tab.id
        )
        #expect(store.subagentStores["child-sync-1"] === threadStore)

        // Switching away releases the holder and stops/removes the live store without closing the tab.
        store.releaseSubagentStore(subagentThreadId: "child-sync-1", holderTabID: tab.id)
        #expect(store.subagentStores["child-sync-1"] == nil)
        #expect(store.tabs(for: parentID).count == 1)

        // Re-attaching and closing the tab cleans up the store and pending/optimistic maps.
        _ = store.ensureSubagentStore(subagentThreadId: "child-sync-1", connection: conn, holderTabID: tab.id)
        store.pendingSubagentMessages["child-sync-1"] = [PendingUserMessage(messageID: "m1", text: "hi")]
        store.optimisticSubagentApprovals["child-sync-1"] = ["req-1": .approved]
        store.closeTab(tab.id, for: parentID)
        #expect(store.subagentStores["child-sync-1"] == nil)
        #expect(store.pendingSubagentMessages["child-sync-1"] == nil)
        #expect(store.optimisticSubagentApprovals["child-sync-1"] == nil)
    }
}
