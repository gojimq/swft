import Foundation
import Testing
@testable import SwftKit

@Suite("Right Panel Wire Contracts (Files, Preview, Linked Items, Device, Side Chat)")
struct RightPanelClientTests {

    // MARK: - Files & Workspace Assets

    @Test func encodesAndDecodesFilesRPCContracts() throws {
        let encoder = SwftJSON.makeEncoder()
        let decoder = SwftJSON.makeDecoder()

        let listInput = ProjectListEntriesInput(cwd: "/Users/mini/code/swft", directoryPath: "Sources/Swft")
        let listObj = try decoder.decode(JSONValue.self, from: encoder.encode(listInput))
        #expect(listObj["cwd"] == .string("/Users/mini/code/swft"))
        #expect(listObj["directoryPath"] == .string("Sources/Swft"))

        // Limit clamped into [1, 200]
        let searchInput = ProjectSearchEntriesInput(cwd: "/repo", query: "AppModel", limit: 999, kind: .file, imageOnly: false)
        let searchObj = try decoder.decode(JSONValue.self, from: encoder.encode(searchInput))
        #expect(searchObj["limit"] == .int(200))
        #expect(searchObj["kind"] == .string("file"))
        #expect(searchObj["imageOnly"] == .bool(false))

        let listJSON = """
        {
          "entries": [
            { "path": "Sources/Swft", "kind": "directory" },
            { "path": "Sources/Swft/AppModel.swift", "kind": "file", "ignored": false },
            { "path": ".build", "kind": "directory", "ignored": true }
          ],
          "truncated": false
        }
        """
        let listResult = try decoder.decode(ProjectListEntriesResult.self, from: Data(listJSON.utf8))
        #expect(listResult.entries.count == 3)
        #expect(listResult.entries[0].name == "Swft")
        #expect(listResult.entries[1].name == "AppModel.swift")
        #expect(listResult.entries[2].ignored == true)

        let readJSON = """
        {
          "relativePath": "README.md",
          "contents": "# Swft\\n",
          "byteLength": 7,
          "truncated": false,
          "exists": true
        }
        """
        let readResult = try decoder.decode(ProjectReadFileResult.self, from: Data(readJSON.utf8))
        #expect(readResult.relativePath == "README.md")
        #expect(readResult.byteLength == 7)
        #expect(readResult.exists == true)

        let metaJSON = """
        {
          "entries": [
            { "kind": "file", "byteLength": 12345, "mimeType": "application/zip" },
            null
          ]
        }
        """
        let metaResult = try decoder.decode(FilesystemGetMetadataResult.self, from: Data(metaJSON.utf8))
        #expect(metaResult.entries.count == 2)
        #expect(metaResult.entries[0]?.mimeType == "application/zip")
        #expect(metaResult.entries[1] == nil)

        // Workspace image asset resources
        let wsAsset = AssetResource.workspaceFile(threadId: "thr-1", path: "Assets/logo.png")
        let wsObj = try decoder.decode(JSONValue.self, from: encoder.encode(wsAsset))
        #expect(wsObj["_tag"] == .string("workspace-file"))
        #expect(wsObj["threadId"] == .string("thr-1"))
        #expect(wsObj["path"] == .string("Assets/logo.png"))

        let draftAsset = AssetResource.draftWorkspaceFile(cwd: "/repo", path: "img.png")
        let draftObj = try decoder.decode(JSONValue.self, from: encoder.encode(draftAsset))
        #expect(draftObj["_tag"] == .string("draft-workspace-file"))
        #expect(draftObj["cwd"] == .string("/repo"))
    }

    // MARK: - Preview / Browser Contracts

    @Test func encodesAndDecodesPreviewSessionsAndEvents() throws {
        let decoder = SwftJSON.makeDecoder()
        let encoder = SwftJSON.makeEncoder()

        let listJSON = """
        {
          "sessions": [
            {
              "threadId": "thr-1",
              "tabId": "tab-42",
              "navStatus": { "_tag": "Success", "url": "http://localhost:5173", "title": "Vite App" },
              "canGoBack": true,
              "canGoForward": false,
              "runtime": "server",
              "headless": true,
              "updatedAt": "2026-11-25T12:00:00.000Z"
            }
          ],
          "serverEpoch": "epoch-1",
          "revision": 3
        }
        """
        let list = try decoder.decode(PreviewListResult.self, from: Data(listJSON.utf8))
        #expect(list.sessions.count == 1)
        #expect(list.sessions[0].navStatus.url == "http://localhost:5173")
        #expect(list.sessions[0].navStatus.title == "Vite App")
        #expect(list.sessions[0].runtime == .server)

        // Round-trip PreviewNavStatus variants
        let loading = PreviewNavStatus.loading(url: "https://t3.codes", title: "")
        #expect(loading.isLoading)
        #expect(loading.title == nil)
        let roundTripped = try decoder.decode(PreviewNavStatus.self, from: encoder.encode(loading))
        #expect(roundTripped == loading)

        let openedEventJSON = """
        {
          "type": "opened",
          "threadId": "thr-1",
          "tabId": "tab-99",
          "revision": 4,
          "snapshot": {
            "threadId": "thr-1",
            "tabId": "tab-99",
            "navStatus": { "_tag": "Idle" },
            "canGoBack": false,
            "canGoForward": false,
            "updatedAt": "2026-11-25T12:01:00.000Z"
          }
        }
        """
        let openedEvent = try decoder.decode(PreviewEvent.self, from: Data(openedEventJSON.utf8))
        if case .opened(let threadId, let tabId, let revision, let snapshot) = openedEvent {
            #expect(threadId == "thr-1")
            #expect(tabId == "tab-99")
            #expect(revision == 4)
            #expect(snapshot.navStatus == .idle)
        } else {
            Issue.record("Expected opened preview event")
        }

        let closedEvent = try decoder.decode(
            PreviewEvent.self,
            from: Data(#"{"type":"closed","threadId":"thr-1","tabId":"tab-99","revision":5}"#.utf8)
        )
        #expect(closedEvent == .closed(threadId: "thr-1", tabId: "tab-99", revision: 5))

        let unknownEvent = try decoder.decode(
            PreviewEvent.self,
            from: Data(#"{"type":"future_event"}"#.utf8)
        )
        #expect(unknownEvent == .unknown(type: "future_event"))

        let serversJSON = """
        {
          "servers": [
            { "host": "localhost", "port": 3000, "url": "http://localhost:3000", "processName": "next-server", "pid": 9012 }
          ],
          "scannedAt": "2026-11-25T12:02:00.000Z"
        }
        """
        let servers = try decoder.decode(DiscoveredLocalServerList.self, from: Data(serversJSON.utf8))
        #expect(servers.servers.count == 1)
        #expect(servers.servers[0].id == "localhost:3000")
    }

    // MARK: - Linked Items (PRs, Issues, Thread Family & Commands)

    @Test func decodesLinkedPRsIssuesOnThreadShellAndAppThreadWithSafeDefaults() throws {
        let decoder = SwftJSON.makeDecoder()
        let encoder = SwftJSON.makeEncoder()

        let richShellJSON = """
        {
          "id": "thr-rich",
          "projectId": "proj-1",
          "title": "Right sidebar PR",
          "providerInstanceId": "claudeAgent",
          "modelSelection": { "instanceId": "claudeAgent", "model": "opus" },
          "runtimeMode": "full-access",
          "interactionMode": "default",
          "pullRequests": [
            {
              "host": "github.com",
              "repository": "pingdotgg/t3code",
              "number": 1842,
              "url": "https://github.com/pingdotgg/t3code/pull/1842",
              "source": "agent",
              "linkedAt": "2026-11-25T10:00:00.000Z",
              "snapshot": {
                "state": "open",
                "title": "Native right sidebar",
                "headBranch": "feat/right-panel",
                "baseBranch": "main",
                "isDraft": false,
                "syncedAt": "2026-11-25T10:05:00.000Z",
                "additions": 250,
                "deletions": 14,
                "checksState": "passing"
              },
              "watch": {
                "startedAt": "2026-11-25T10:01:00.000Z",
                "passed": true,
                "conflicting": false
              }
            }
          ],
          "issues": [
            {
              "tracker": "github",
              "host": "github.com",
              "scope": "pingdotgg/t3code",
              "key": "412",
              "projectId": "proj-1",
              "url": "https://github.com/pingdotgg/t3code/issues/412",
              "source": "manual",
              "linkedAt": "2026-11-25T09:00:00.000Z",
              "displayKey": "#412",
              "title": "Add right sidebar"
            }
          ],
          "lineage": { "parentThreadId": null, "relationshipToParent": null, "rootThreadId": "thr-rich" },
          "status": "idle",
          "createdAt": "2026-11-25T08:00:00.000Z",
          "updatedAt": "2026-11-25T10:05:00.000Z"
        }
        """
        let richShell = try decoder.decode(ThreadShell.self, from: Data(richShellJSON.utf8))
        #expect(richShell.pullRequests.count == 1)
        #expect(richShell.pullRequests[0].isWatching)
        #expect(!richShell.pullRequests[0].isDismissed)
        #expect(richShell.pullRequests[0].snapshot?.checksState == "passing")
        #expect(richShell.issues.count == 1)
        #expect(richShell.issues[0].displayKey == "#412")

        // AppThread without pullRequests / issues keys still decodes cleanly with empty arrays
        let minimalAppThreadJSON = """
        {
          "id": "thr-min",
          "projectId": "proj-1",
          "title": "Minimal",
          "providerInstanceId": "codex",
          "modelSelection": { "instanceId": "codex", "model": "gpt-6" },
          "runtimeMode": "full-access",
          "interactionMode": "default",
          "lineage": { "parentThreadId": null, "relationshipToParent": null, "rootThreadId": "thr-min" },
          "createdAt": "2026-11-25T08:00:00.000Z",
          "updatedAt": "2026-11-25T08:00:00.000Z"
        }
        """
        let minimalThread = try decoder.decode(AppThread.self, from: Data(minimalAppThreadJSON.utf8))
        #expect(minimalThread.pullRequests.isEmpty)
        #expect(minimalThread.issues.isEmpty)

        // Command encoding for link/unlink PR & unlink issue
        let linkCmd = OrchestrationCommand.linkPullRequest(
            commandId: "cmd-link",
            threadId: "thr-1",
            host: "github.com",
            repository: "pingdotgg/t3code",
            number: 99,
            url: "https://github.com/pingdotgg/t3code/pull/99",
            source: "manual"
        )
        let linkObj = try decoder.decode(JSONValue.self, from: encoder.encode(linkCmd))
        #expect(linkObj["type"] == .string("thread.pull-request.link"))
        #expect(linkObj["number"] == .int(99))
        #expect(linkObj["repository"] == .string("pingdotgg/t3code"))

        let unlinkPR = OrchestrationCommand.unlinkPullRequest(
            commandId: "cmd-unlink-pr",
            threadId: "thr-1",
            host: "github.com",
            repository: "pingdotgg/t3code",
            number: 99
        )
        let unlinkPRObj = try decoder.decode(JSONValue.self, from: encoder.encode(unlinkPR))
        #expect(unlinkPRObj["type"] == .string("thread.pull-request.unlink"))
        #expect(unlinkPRObj["number"] == .int(99))

        let unlinkIssue = OrchestrationCommand.unlinkIssue(
            commandId: "cmd-unlink-issue",
            threadId: "thr-1",
            tracker: "github",
            host: "github.com",
            scope: "pingdotgg/t3code",
            key: "412"
        )
        let unlinkIssueObj = try decoder.decode(JSONValue.self, from: encoder.encode(unlinkIssue))
        #expect(unlinkIssueObj["type"] == .string("thread.issue.unlink"))
        #expect(unlinkIssueObj["tracker"] == .string("github"))
        #expect(unlinkIssueObj["key"] == .string("412"))

        // ThreadFamilyResult decoding
        let familyJSON = #"{"snapshotSequence": 14, "threads": [\#(richShellJSON)]}"#
        let family = try decoder.decode(ThreadFamilyResult.self, from: Data(familyJSON.utf8))
        #expect(family.snapshotSequence == 14)
        #expect(family.threads.map(\.id) == ["thr-rich"])
    }

    // MARK: - Device Contracts & Hub URLs

    @Test func decodesDeviceStateMergesHostsAndBuildsHubURLs() throws {
        let decoder = SwftJSON.makeDecoder()
        let encoder = SwftJSON.makeEncoder()

        let stateJSON = """
        {
          "hostStatus": "ready",
          "hostStatuses": {
            "local": { "status": "ready" }
          },
          "hosts": [
            { "id": "local", "label": "Mac Mini", "kind": "local", "platforms": [{ "platform": "ios", "available": true }], "hubInstalled": true, "agentDeviceInstalled": true }
          ],
          "easHosts": [
            { "id": "eas-1", "label": "EAS Cloud", "kind": "eas", "platforms": [{ "platform": "ios", "available": true }], "hubInstalled": false, "agentDeviceInstalled": false }
          ],
          "simlockHosts": [
            { "id": "simlock-1", "label": "Simlock", "kind": "simlock", "platforms": [{ "platform": "ios", "available": true }], "hubInstalled": false, "agentDeviceInstalled": false }
          ],
          "devices": [
            { "hostId": "local", "id": "UDID-1", "platform": "ios", "name": "iPhone 16 Pro", "version": "iOS 18.4", "booted": true, "physical": false }
          ],
          "sessions": [
            { "threadId": "thr-1", "hostId": "local", "deviceId": "UDID-1", "platform": "ios", "openedAt": "2026-11-25T10:00:00.000Z" }
          ],
          "onboardingCompleted": true,
          "agentAccessEnabled": true,
          "hubBasePath": "/api/device-hub",
          "revision": 7
        }
        """
        let state = try decoder.decode(DeviceServiceState.self, from: Data(stateJSON.utf8))
        #expect(state.hostStatus == .ready)
        #expect(state.hosts.map(\.id) == ["local", "eas-1", "simlock-1"])
        #expect(state.devices.count == 1)
        #expect(state.devices[0].compositeKey == "local::UDID-1")
        #expect(state.sessions.count == 1)

        // Device actions encode exact discriminated union payloads
        let appearanceObj = try decoder.decode(
            JSONValue.self,
            from: encoder.encode(DeviceActionInput.setAppearance(hostId: "local", deviceId: "UDID-1", value: "dark"))
        )
        #expect(appearanceObj["type"] == .string("setAppearance"))
        #expect(appearanceObj["value"] == .string("dark"))

        let openURLObj = try decoder.decode(
            JSONValue.self,
            from: encoder.encode(DeviceActionInput.openUrl(hostId: "local", deviceId: "UDID-1", url: "myapp://home"))
        )
        #expect(openURLObj["type"] == .string("openUrl"))
        #expect(openURLObj["url"] == .string("myapp://home"))

        let shakeObj = try decoder.decode(
            JSONValue.self,
            from: encoder.encode(DeviceActionInput.shake(hostId: "local", deviceId: "UDID-1"))
        )
        #expect(shakeObj["type"] == .string("shake"))

        // Hub screenshot & input WebSocket URLs (both http -> ws and https -> wss)
        let httpBase = URL(string: "http://127.0.0.1:3773")!
        let httpsBase = URL(string: "https://macmini.ts.net")!

        let iosShot = DeviceHubURLBuilder.screenshotURL(baseURL: httpsBase, hostId: "local", deviceId: "UDID-1", platform: .ios)
        #expect(iosShot?.absoluteString == "https://macmini.ts.net/api/device-hub/vendor/serve-sim/api/screenshot?device=UDID-1&hostId=local")

        let androidShot = DeviceHubURLBuilder.screenshotURL(baseURL: httpBase, hostId: "local", deviceId: "emu-1", platform: .android)
        #expect(androidShot?.absoluteString == "http://127.0.0.1:3773/api/device-hub/vendor/serve-emu/api/screenshot?device=emu-1&hostId=local")

        let iosWS = DeviceHubURLBuilder.inputWebSocketURL(baseURL: httpsBase, hostId: "local", deviceId: "UDID-1", platform: .ios, wsTicket: "TKT-1")
        #expect(iosWS?.absoluteString == "wss://macmini.ts.net/api/device-hub/vendor/serve-sim/helper/ws?device=UDID-1&hostId=local&wsTicket=TKT-1")

        let androidWS = DeviceHubURLBuilder.inputWebSocketURL(baseURL: httpBase, hostId: "local", deviceId: "emu-1", platform: .android, wsTicket: "TKT-2")
        #expect(androidWS?.absoluteString == "ws://127.0.0.1:3773/api/device-hub/vendor/serve-emu/ws?device=emu-1&hostId=local&wsTicket=TKT-2")

        // iOS tagged binary frame prepends tag byte before JSON body
        let frame = try DeviceHubURLBuilder.iosTaggedFrame(tag: 0x03, payload: [
            "type": .string("begin"),
            "x": .double(0.5),
            "y": .double(0.25),
        ])
        #expect(frame.first == 0x03)
        let decodedBody = try decoder.decode(JSONValue.self, from: frame.dropFirst())
        #expect(decodedBody["type"] == .string("begin"))
        #expect(decodedBody["x"] == .double(0.5))
    }

    // MARK: - Side Chat (`thread.fork`)

    @Test func encodesSideChatForkCommandWithLatestStableSourcePoint() throws {
        let encoder = SwftJSON.makeEncoder()
        let decoder = SwftJSON.makeDecoder()

        let forkCmd = OrchestrationCommand.forkThread(
            commandId: "cmd-fork-1",
            sourceThreadId: "thr-parent",
            targetThreadId: "thr-side",
            sourcePoint: .latestStable,
            title: "Side chat",
            sideChat: true
        )
        let obj = try decoder.decode(JSONValue.self, from: encoder.encode(forkCmd))
        #expect(obj["type"] == .string("thread.fork"))
        #expect(obj["commandId"] == .string("cmd-fork-1"))
        #expect(obj["sourceThreadId"] == .string("thr-parent"))
        #expect(obj["targetThreadId"] == .string("thr-side"))
        #expect(obj["title"] == .string("Side chat"))
        #expect(obj["sideChat"] == .bool(true))
        #expect(obj["sourcePoint"]?["type"] == .string("latest_stable"))

        let runPointObj = try decoder.decode(JSONValue.self, from: encoder.encode(ThreadForkSourcePoint.run(runId: "run-9")))
        #expect(runPointObj["type"] == .string("run"))
        #expect(runPointObj["runId"] == .string("run-9"))
    }
}
