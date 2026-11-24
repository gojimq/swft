import Foundation
import SwftDesign
import SwftKit
import Testing
@testable import Swft

@Suite("No-Project Selection, Display & Launch")
struct NoProjectTests {
    private let swft = ProjectRef(id: "p-swft", name: "Swft", initials: "SW", tint: 0, workspaceRoot: "/code/swft")
    private let studio = ProjectRef(id: "p-studio", name: "Studio", initials: "ST", tint: 1, workspaceRoot: "/code/studio")

    @Test func selectionHonorsExplicitNoProjectAndResetsWhenProjectChosen() {
        // Default: picks first project when nothing selected and not cleared.
        #expect(
            NoProjectLogic.resolveSelectedProject(
                projects: [swft, studio],
                selectedProjectID: nil,
                isNoProjectSelected: false
            )?.id == swft.id
        )

        // Explicit no-project overrides fallback to first project.
        #expect(
            NoProjectLogic.resolveSelectedProject(
                projects: [swft, studio],
                selectedProjectID: nil,
                isNoProjectSelected: true
            ) == nil
        )
        #expect(
            NoProjectLogic.resolveSelectedProject(
                projects: [swft, studio],
                selectedProjectID: swft.id,
                isNoProjectSelected: true
            ) == nil
        )

        // Picking a specific project selects it when not cleared.
        #expect(
            NoProjectLogic.resolveSelectedProject(
                projects: [swft, studio],
                selectedProjectID: studio.id,
                isNoProjectSelected: false
            )?.id == studio.id
        )

        // Empty project list always yields nil.
        #expect(
            NoProjectLogic.resolveSelectedProject(
                projects: [],
                selectedProjectID: nil,
                isNoProjectSelected: false
            ) == nil
        )
    }

    @Test func homeLaunchResolvesProjectOrScratchOrUnavailableReason() {
        let connected = ServerStatus.connected(label: "MacBook Pro", providerCount: 2, port: 51234)
        let scratchRoot = "/Users/dev/Library/Application Support/Swft/userdata/scratch"

        // Selected project launches directly into that project even if scratch is unavailable.
        #expect(
            NoProjectLogic.resolveHomeLaunch(
                selectedProject: swft,
                isMock: false,
                serverStatus: connected,
                environmentLabel: "MacBook Pro",
                scratchWorkspaceRoot: nil
            ) == .ready(.project(id: swft.id))
        )

        // No selected project + scratch root available launches as project-less.
        #expect(
            NoProjectLogic.resolveHomeLaunch(
                selectedProject: nil,
                isMock: false,
                serverStatus: connected,
                environmentLabel: "MacBook Pro",
                scratchWorkspaceRoot: scratchRoot
            ) == .ready(.noProject)
        )

        // No selected project + connected without scratch root explains unavailability.
        #expect(
            NoProjectLogic.resolveHomeLaunch(
                selectedProject: nil,
                isMock: false,
                serverStatus: connected,
                environmentLabel: "MacBook Pro",
                scratchWorkspaceRoot: nil
            ) == .unavailable(reason: "MacBook Pro does not support starting without a project.")
        )

        // Disconnected / connecting explains waiting or reconnecting.
        #expect(
            NoProjectLogic.resolveHomeLaunch(
                selectedProject: nil,
                isMock: false,
                serverStatus: .connecting,
                environmentLabel: "MacBook Pro",
                scratchWorkspaceRoot: nil
            ) == .unavailable(reason: "Wait for MacBook Pro to connect to start without a project.")
        )
        #expect(
            NoProjectLogic.resolveHomeLaunch(
                selectedProject: nil,
                isMock: false,
                serverStatus: .failed(message: "offline"),
                environmentLabel: nil,
                scratchWorkspaceRoot: nil
            ) == .unavailable(reason: "Connect to the local server to start without a project.")
        )

        // Mock mode always allows project-less launches.
        #expect(
            NoProjectLogic.resolveHomeLaunch(
                selectedProject: nil,
                isMock: true,
                serverStatus: .starting,
                environmentLabel: nil,
                scratchWorkspaceRoot: nil
            ) == .ready(.noProject)
        )
    }

    @Test func resolveLaunchProjectIDCallsEnsureScratchOnlyForNoProject() async throws {
        actor Counter {
            var calls = 0
            func increment() -> Int {
                calls += 1
                return calls
            }
        }
        let counter = Counter()

        let directID = try await NoProjectLogic.resolveLaunchProjectID(for: .project(id: "proj-42")) {
            _ = await counter.increment()
            return "proj-scratch"
        }
        #expect(directID == "proj-42")
        #expect(await counter.calls == 0)

        let scratchID = try await NoProjectLogic.resolveLaunchProjectID(for: .noProject) {
            _ = await counter.increment()
            return "proj-scratch"
        }
        #expect(scratchID == "proj-scratch")
        #expect(await counter.calls == 1)

        struct Boom: Error {}
        await #expect(throws: Boom.self) {
            _ = try await NoProjectLogic.resolveLaunchProjectID(for: .noProject) {
                throw Boom()
            }
        }
    }

    @Test func detectsProjectlessThreadsAndDerivesComposerChipState() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let projectThread = ThreadSummary(
            id: "t-proj",
            title: "Fix chip",
            project: swft,
            location: .branch("swft/feat-no-project"),
            provider: .claude,
            activity: .idle,
            updatedAt: now
        )
        let liveScratchThread = ThreadSummary(
            id: "t-scratch",
            title: "Quick thought",
            project: nil,
            location: .host("MacBook Pro"),
            provider: .claude,
            activity: .idle,
            updatedAt: now
        )
        let mockNoProjectThread = ThreadSummary(
            id: "t-mock-none",
            title: "Sketch copy",
            project: MockData.none,
            location: .host("MacBook Pro"),
            provider: .opencode,
            activity: .idle,
            updatedAt: now
        )

        #expect(!NoProjectLogic.isProjectless(projectThread))
        #expect(NoProjectLogic.isProjectless(liveScratchThread))
        #expect(NoProjectLogic.isProjectless(mockNoProjectThread))

        let projectLabel = NoProjectLogic.composerContextLabel(
            selectedThread: projectThread,
            selectedProject: nil,
            isMock: false
        )
        #expect(projectLabel == "Swft · swft/feat-no-project")
        #expect(
            NoProjectLogic.composerChipState(
                selectedThread: projectThread,
                contextLabel: projectLabel,
                hasProjects: true,
                canStartWithoutProject: true,
                isConnected: true,
                isNoProjectSelected: false
            ) == .project("Swft · swft/feat-no-project")
        )

        // Both nil-project and initials-nil (MockData.none) threads yield nil contextLabel and dashed no-project chip.
        for thread in [liveScratchThread, mockNoProjectThread] {
            let label = NoProjectLogic.composerContextLabel(
                selectedThread: thread,
                selectedProject: swft,
                isMock: true,
                mockDefaultProjectID: swft.id,
                mockDefaultContextLabel: "Swft · main"
            )
            #expect(label == nil)
            #expect(
                NoProjectLogic.composerChipState(
                    selectedThread: thread,
                    contextLabel: label,
                    hasProjects: true,
                    canStartWithoutProject: true,
                    isConnected: true,
                    isNoProjectSelected: false
                ) == .noProject("No project")
            )
        }

        // Home with no projects when scratch is unsupported falls back to "Add project" prompt.
        #expect(
            NoProjectLogic.composerChipState(
                selectedThread: nil,
                contextLabel: nil,
                hasProjects: false,
                canStartWithoutProject: false,
                isConnected: true,
                isNoProjectSelected: false
            ) == .noProject("Add project")
        )
    }

    @Test func filtersScratchProjectOutOfNonScratchProjectsLookup() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let root = "/Users/dev/Library/Application Support/Swft/userdata/scratch"
        let scratch = ProjectShell(id: "p-scratch", title: "No project", workspaceRoot: root, createdAt: now, updatedAt: now)
        let real = ProjectShell(id: "p-real", title: "Swft", workspaceRoot: "/Users/dev/swft", createdAt: now, updatedAt: now)

        let filtered = NoProjectLogic.nonScratchProjectsByID(
            projects: [scratch, real],
            scratchWorkspaceRoot: root
        )
        #expect(filtered.keys.sorted() == ["p-real"])
    }

    @Test @MainActor func appModelMockClearsReselectsAndLaunchesProjectlessThread() {
        let model = AppModel.mock()
        #expect(model.selectedProject?.id == MockData.swft.id)
        #expect(model.composer.contextLabel == "Swft · main")
        #expect(model.composerProjectChipState(contextLabel: model.composer.contextLabel) == .project("Swft · main"))

        // Switching to another mock project updates contextLabel instead of pinning Swft · main.
        model.selectProject(MockData.studio.id)
        #expect(model.selectedProject?.id == MockData.studio.id)
        #expect(model.composer.contextLabel == "Studio")

        // Clearing project enters the no-project state.
        model.clearProject()
        #expect(model.isNoProjectSelected)
        #expect(model.selectedProject == nil)
        #expect(model.composer.contextLabel == nil)
        #expect(model.composerProjectChipState(contextLabel: model.composer.contextLabel) == .noProject("No project"))

        // Sending from Home with no project creates and opens a project-less thread.
        let beforeCount = model.sidebar.threads.count
        model.composerText = "Draft release notes without opening a repo"
        model.send()

        #expect(model.composerText.isEmpty)
        #expect(model.sidebar.threads.count == beforeCount + 1)
        let openedID = model.selectedThreadID
        #expect(openedID != nil)
        let createdSummary = openedID.flatMap(model.threadSummary(for:))
        #expect(createdSummary?.project == nil)
        #expect(createdSummary?.title == "Draft release notes without opening a repo")
        #expect(model.composer.contextLabel == nil)
        #expect(model.composerProjectChipState(contextLabel: model.composer.contextLabel) == .noProject("No project"))

        // Navigating back to Home preserves no-project until a project is picked again.
        model.goHome()
        #expect(model.selectedProject == nil)
        #expect(model.isNoProjectSelected)

        model.selectProject(MockData.swft.id)
        #expect(!model.isNoProjectSelected)
        #expect(model.selectedProject?.id == MockData.swft.id)
        #expect(model.composer.contextLabel == "Swft · main")

        // Opening the existing mock "No project" thread (t6) shows the composer in no-project state.
        model.open("t6")
        #expect(model.composer.contextLabel == nil)
        #expect(model.composerProjectChipState(contextLabel: model.composer.contextLabel) == .noProject("No project"))
    }
}
