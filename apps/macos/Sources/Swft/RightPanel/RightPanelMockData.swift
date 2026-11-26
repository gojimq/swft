import AppKit
import Foundation
import SwftDesign
import SwftKit

/// Self-contained fixtures for all 5 right-panel surfaces when running in `AppModel.isMock` mode.
enum RightPanelMockData {
    static let now = Date()

    // MARK: - Browser / Preview Sessions

    static func previewSessions(for threadID: String) -> [PreviewSessionSnapshot] {
        [
            PreviewSessionSnapshot(
                threadId: threadID,
                tabId: "mock-preview-1",
                navStatus: .success(url: "http://localhost:5173", title: "Swft Dev App"),
                canGoBack: false,
                canGoForward: false,
                runtime: .server,
                headless: true,
                updatedAt: SwftJSON.formatISO8601(now)
            ),
        ]
    }

    // MARK: - Workspace Files

    static let directoryEntries: [String: [ProjectEntry]] = [
        "": [
            ProjectEntry(path: "Sources", kind: .directory),
            ProjectEntry(path: "Tests", kind: .directory),
            ProjectEntry(path: "Assets", kind: .directory),
            ProjectEntry(path: "Package.swift", kind: .file),
            ProjectEntry(path: "README.md", kind: .file),
            ProjectEntry(path: ".build", kind: .directory, ignored: true),
        ],
        "Sources": [
            ProjectEntry(path: "Sources/Swft", kind: .directory),
            ProjectEntry(path: "Sources/SwftKit", kind: .directory),
        ],
        "Sources/Swft": [
            ProjectEntry(path: "Sources/Swft/AppModel.swift", kind: .file),
            ProjectEntry(path: "Sources/Swft/RootView.swift", kind: .file),
        ],
        "Sources/SwftKit": [
            ProjectEntry(path: "Sources/SwftKit/ServerConnection.swift", kind: .file),
        ],
        "Tests": [
            ProjectEntry(path: "Tests/RightPanelTests.swift", kind: .file),
        ],
        "Assets": [
            ProjectEntry(path: "Assets/preview-banner.png", kind: .file),
            ProjectEntry(path: "Assets/archive.zip", kind: .file),
        ],
    ]

    static let fileContents: [String: String] = [
        "Package.swift": """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "Swft",
            platforms: [.macOS(.v15)],
            products: [
                .executable(name: "Swft", targets: ["Swft"]),
                .library(name: "SwftKit", targets: ["SwftKit"]),
                .library(name: "SwftDesign", targets: ["SwftDesign"]),
            ]
        )
        """,
        "README.md": """
        # Swft Native macOS App

        Swft is a native SwiftUI desktop client for **T3 Code** servers, supporting local and paired remote environments.

        ## Right Sidebar Surfaces
        - **Browser** (`B`): Native `WKWebView` with live URL bar and agent preview sessions.
        - **Files** (`F`): Remote-capable workspace explorer and syntax-friendly viewer.
        - **Linked items** (`L`): Pull requests, issues, and related threads.
        - **Device** (`M`): Live iOS Simulator and Android Emulator viewport.
        - **Side chat** (`S`): Fork a quick side question while the main run continues.
        """,
        "Sources/Swft/AppModel.swift": """
        import Foundation
        import Observation
        import SwftKit

        @MainActor
        @Observable
        final class AppModel {
            let rightPanel = RightPanelStore()
            var destination: SidebarDestination = .home
        }
        """,
        "Sources/Swft/RootView.swift": """
        import SwftDesign
        import SwiftUI

        struct RootView: View {
            @Environment(AppModel.self) private var model

            var body: some View {
                HStack(spacing: 0) {
                    SidebarView()
                    MainContentArea()
                    if let threadID = model.selectedThreadID, model.rightPanel.isOpen(for: threadID) {
                        RightPanelContainerView(threadID: threadID)
                    }
                }
            }
        }
        """,
        "Sources/SwftKit/ServerConnection.swift": """
        import Foundation

        public actor ServerConnection {
            public let httpBaseURL: URL
            public func call<Payload: Encodable & Sendable, Response: Decodable & Sendable>(
                tag: String,
                payload: Payload
            ) async throws -> Response {
                fatalError("Mock")
            }
        }
        """,
        "Tests/RightPanelTests.swift": """
        import Testing
        @testable import Swft

        @Suite("Right Panel")
        struct RightPanelTests {
            @Test func opensFiveIncludedSurfaces() {
                #expect(RightPanelSurfaceKind.allCases.count == 5)
            }
        }
        """,
    ]

    static func searchEntries(query: String) -> [ProjectEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = directoryEntries.values.flatMap { $0 }
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.path.lowercased().contains(trimmed) }
    }

    static func mockImagePNGData(title: String = "Swft Preview", size: CGSize = CGSize(width: 390, height: 844)) -> Data {
        let width = Int(size.width)
        let height = Int(size.height)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let gradient = CGGradient(
                colorsSpace: space,
                colors: [
                    CGColor(srgbRed: 0.11, green: 0.14, blue: 0.22, alpha: 1),
                    CGColor(srgbRed: 0.07, green: 0.09, blue: 0.14, alpha: 1),
                ] as CFArray,
                locations: [0, 1]
              )
        else { return Data() }

        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
        ctx.setFillColor(CGColor(srgbRed: 0.28, green: 0.56, blue: 0.96, alpha: 0.28))
        let cardRect = CGRect(x: width / 10, y: height / 3, width: width * 8 / 10, height: height / 4)
        ctx.fill(cardRect)
        ctx.setFillColor(CGColor(srgbRed: 0.95, green: 0.97, blue: 1, alpha: 0.85))
        ctx.fill(CGRect(x: width * 3 / 10, y: height - 34, width: width * 4 / 10, height: 6))

        guard let cgImage = ctx.makeImage() else { return Data() }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }

    // MARK: - Linked Items

    static let pullRequests: [ThreadPullRequestLink] = [
        ThreadPullRequestLink(
            host: "github.com",
            repository: "pingdotgg/t3code",
            number: 1842,
            url: "https://github.com/pingdotgg/t3code/pull/1842",
            source: "agent",
            linkedAt: now.addingTimeInterval(-18 * 60),
            snapshot: ThreadPullRequestSnapshot(
                state: "open",
                title: "feat(macos): add native right sidebar with 5 backend-wired surfaces",
                headBranch: "t3/macos-right-sidebar-surfaces",
                baseBranch: "swft/integration",
                isDraft: false,
                updatedAt: now.addingTimeInterval(-5 * 60),
                syncedAt: now.addingTimeInterval(-60),
                author: ThreadPullRequestActor(login: "jimwell", name: "Jimwell"),
                additions: 1420,
                deletions: 68,
                changedFiles: 19,
                reviewDecision: "approved",
                checksState: "passing",
                mergeability: "mergeable"
            ),
            watch: ThreadPullRequestWatch(startedAt: now.addingTimeInterval(-15 * 60), passed: true, conflicting: false)
        ),
        ThreadPullRequestLink(
            host: "github.com",
            repository: "pingdotgg/t3code",
            number: 1795,
            url: "https://github.com/pingdotgg/t3code/pull/1795",
            source: "manual",
            linkedAt: now.addingTimeInterval(-180 * 60),
            snapshot: ThreadPullRequestSnapshot(
                state: "merged",
                title: "fix(macos): fade in new-thread first message and smooth send-flight scroll",
                headBranch: "t3/macos-send-flight-scroll-fix",
                baseBranch: "swft/integration",
                isDraft: false,
                updatedAt: now.addingTimeInterval(-120 * 60),
                syncedAt: now.addingTimeInterval(-90 * 60),
                author: ThreadPullRequestActor(login: "jimwell", name: "Jimwell"),
                additions: 318,
                deletions: 44,
                changedFiles: 7,
                checksState: "passing"
            )
        ),
    ]

    static let issues: [ThreadIssueLink] = [
        ThreadIssueLink(
            tracker: "github",
            host: "github.com",
            scope: "pingdotgg/t3code",
            key: "412",
            projectId: MockData.swft.id,
            url: "https://github.com/pingdotgg/t3code/issues/412",
            source: "agent",
            linkedAt: now.addingTimeInterval(-45 * 60),
            displayKey: "#412",
            title: "Bring T3 Code right-panel surfaces to native Swft macOS app"
        ),
        ThreadIssueLink(
            tracker: "linear",
            host: "linear.app",
            scope: "SWF",
            key: "SWF-88",
            projectId: MockData.swft.id,
            url: "https://linear.app/swft/issue/SWF-88",
            source: "manual",
            linkedAt: now.addingTimeInterval(-120 * 60),
            displayKey: "SWF-88",
            title: "Support remote environment file browsing and simulator preview"
        ),
    ]

    static func relatedThreads(for parentThreadID: String) -> [LinkedThreadSummaryItem] {
        [
            LinkedThreadSummaryItem(
                id: "mock-subagent-1",
                title: "Audit SwftKit RPC wire schemas",
                relation: .subagent,
                status: .idle,
                updatedAt: now.addingTimeInterval(-6 * 60)
            ),
            LinkedThreadSummaryItem(
                id: "mock-sidechat-1",
                title: "WKWebView URL normalization edge cases",
                relation: .sideChat,
                status: .idle,
                updatedAt: now.addingTimeInterval(-12 * 60)
            ),
        ]
    }

    // MARK: - Devices

    static func deviceState(for threadID: String) -> DeviceServiceState {
        DeviceServiceState(
            hostStatus: .ready,
            hostStatuses: [
                "local": DeviceHostStatusEntry(status: .ready),
            ],
            hosts: [
                DeviceHostSummary(
                    id: "local",
                    label: "This Mac",
                    kind: "local",
                    platforms: [
                        DevicePlatformAvailability(platform: .ios, available: true),
                        DevicePlatformAvailability(platform: .android, available: true),
                    ],
                    hubInstalled: true,
                    agentDeviceInstalled: true
                ),
            ],
            devices: [
                DeviceSummary(
                    hostId: "local",
                    id: "mock-ios-16-pro",
                    platform: .ios,
                    name: "iPhone 16 Pro",
                    version: "iOS 18.4",
                    booted: true
                ),
                DeviceSummary(
                    hostId: "local",
                    id: "mock-ipad-air",
                    platform: .ios,
                    name: "iPad Air 11-inch",
                    version: "iOS 18.4",
                    booted: false
                ),
                DeviceSummary(
                    hostId: "local",
                    id: "mock-pixel-9",
                    platform: .android,
                    name: "Pixel 9 Pro API 35",
                    version: "Android 15",
                    booted: false
                ),
            ],
            sessions: [
                DeviceSession(
                    threadId: threadID,
                    hostId: "local",
                    deviceId: "mock-ios-16-pro",
                    platform: .ios,
                    openedAt: SwftJSON.formatISO8601(now)
                ),
            ],
            onboardingCompleted: true,
            agentAccessEnabled: true,
            hubBasePath: "/api/device-hub",
            revision: 1
        )
    }

    // MARK: - Side Chat

    static func initialMockSideChatMessages() -> [TranscriptItem] {
        [
            TranscriptItem(
                id: "mock-sc-1",
                kind: .user("Can you summarize what files changed on this branch without interrupting the main run?"),
                startedAt: now.addingTimeInterval(-90)
            ),
            TranscriptItem(
                id: "mock-sc-2",
                kind: .assistant(
                    blocks: [
                        .text("Sure — this side chat is forked at the parent thread's latest stable checkpoint. So far the main thread has added the **RightPanelStore** tab manager and wired the five surfaces (**Browser**, **Files**, **Linked items**, **Device**, and **Side chat**)."),
                    ],
                    streaming: false
                ),
                startedAt: now.addingTimeInterval(-85),
                completedAt: now.addingTimeInterval(-80)
            ),
        ]
    }
}

/// Unified linked/related thread item shown in the Linked Items surface.
struct LinkedThreadSummaryItem: Identifiable, Equatable, Hashable, Sendable {
    enum Relation: String, Hashable, Sendable {
        case parent = "Parent thread"
        case sideChat = "Side chat"
        case subagent = "Subagent"
        case fork = "Forked thread"
        case linked = "Related thread"

        var iconName: String {
            switch self {
            case .parent: "arrow.turn.left.up"
            case .sideChat: "bubble.left.and.bubble.right"
            case .subagent: "cpu"
            case .fork: "arrow.triangle.branch"
            case .linked: "link"
            }
        }
    }

    let id: String
    let title: String
    let relation: Relation
    let status: ThreadActivity
    let updatedAt: Date
}
