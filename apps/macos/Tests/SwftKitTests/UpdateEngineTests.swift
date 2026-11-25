import CryptoKit
import Foundation
import os
import Testing
@testable import SwftKit

@Suite("Update Engine")
struct UpdateEngineTests {
    // MARK: - Semver

    @Test func parsesAndOrdersSemverVersions() {
        #expect(SwftSemver("0.2.0")?.major == 0)
        #expect(SwftSemver("0.2.0")?.minor == 2)
        #expect(SwftSemver("0.2.0")?.patch == 0)
        #expect(SwftSemver("v1.4.2")?.raw == "1.4.2")
        #expect(SwftSemver("V2.0.0-beta.1")?.prerelease == ["beta", "1"])

        // Standard ordering
        #expect(SwftSemver("0.1.0")! < SwftSemver("0.1.1")!)
        #expect(SwftSemver("0.1.9")! < SwftSemver("0.2.0")!)
        #expect(SwftSemver("0.9.9")! < SwftSemver("1.0.0")!)

        // Prerelease precedence per SemVer 2.0
        #expect(SwftSemver("1.0.0-alpha")! < SwftSemver("1.0.0-alpha.1")!)
        #expect(SwftSemver("1.0.0-alpha.1")! < SwftSemver("1.0.0-alpha.beta")!)
        #expect(SwftSemver("1.0.0-alpha.2")! < SwftSemver("1.0.0-alpha.10")!)
        #expect(SwftSemver("1.0.0-beta")! < SwftSemver("1.0.0-rc.1")!)
        #expect(SwftSemver("1.0.0-rc.1")! < SwftSemver("1.0.0")!)
        #expect(SwftSemver("v1.0.0")! == SwftSemver("1.0.0")!)

        // Build metadata ignored for equality/ordering
        #expect(SwftSemver("1.2.3+build.1")! == SwftSemver("1.2.3+build.2")!)

        // Invalid versions rejected
        #expect(SwftSemver("") == nil)
        #expect(SwftSemver("1.2") == nil)
        #expect(SwftSemver("1.2.3.4") == nil)
        #expect(SwftSemver("01.2.3") == nil)
        #expect(SwftSemver("1.2.3-") == nil)
        #expect(SwftSemver("latest") == nil)
        #expect(SwftSemver("vv1.0.0") == nil)
    }

    // MARK: - Wire Capabilities & Events

    @Test func decodesSelfUpdateCapabilitiesAndBackwardCompatibility() throws {
        let decoder = SwftJSON.makeDecoder()

        let fullJSON = """
        {
          "repositoryIdentity": true,
          "serverSelfUpdate": "boot-service",
          "serverSelfUpdateProgress": true,
          "serverUpdateStaging": true,
          "desktopAppUpdate": true
        }
        """
        let full = try decoder.decode(ExecutionEnvironmentCapabilities.self, from: Data(fullJSON.utf8))
        #expect(full.serverSelfUpdate == .bootService)
        #expect(full.serverSelfUpdateProgress == true)
        #expect(full.serverUpdateStaging == true)
        #expect(full.desktopAppUpdate == true)

        let desktopManagedJSON = #"{"serverSelfUpdate":"desktop-managed"}"#
        let desktopManaged = try decoder.decode(
            ExecutionEnvironmentCapabilities.self,
            from: Data(desktopManagedJSON.utf8)
        )
        #expect(desktopManaged.serverSelfUpdate == .desktopManaged)
        #expect(desktopManaged.serverSelfUpdateProgress == false)
        #expect(desktopManaged.serverUpdateStaging == false)
        #expect(desktopManaged.desktopAppUpdate == false)

        // Absent fields and unknown future capability enum values stay backward-compatible.
        let legacyJSON = #"{"repositoryIdentity":false,"serverSelfUpdate":"future-mode"}"#
        let legacy = try decoder.decode(ExecutionEnvironmentCapabilities.self, from: Data(legacyJSON.utf8))
        #expect(legacy.serverSelfUpdate == nil)
        #expect(legacy.serverSelfUpdateProgress == false)
        #expect(legacy.serverUpdateStaging == false)
        #expect(legacy.desktopAppUpdate == false)
    }

    @Test func decodesServerSelfUpdateProgressEvents() throws {
        let decoder = SwftJSON.makeDecoder()

        let downloading = try decoder.decode(
            ServerSelfUpdateProgressEvent.self,
            from: Data(#"{"type":"progress","stage":"downloading"}"#.utf8)
        )
        #expect(downloading == .progress(stage: .downloading))

        let installing = try decoder.decode(
            ServerSelfUpdateProgressEvent.self,
            from: Data(#"{"type":"progress","stage":"installing"}"#.utf8)
        )
        #expect(installing == .progress(stage: .installing))

        let completeBoot = try decoder.decode(
            ServerSelfUpdateProgressEvent.self,
            from: Data("""
            {
              "type": "complete",
              "result": {
                "targetVersion": "0.2.0",
                "method": "boot-service",
                "updateId": "upd-123"
              }
            }
            """.utf8)
        )
        #expect(
            completeBoot == .complete(
                result: ServerSelfUpdateResult(
                    targetVersion: "0.2.0",
                    method: .bootService,
                    updateId: "upd-123",
                    desktopUpdateToken: nil
                )
            )
        )

        let completeDesktop = try decoder.decode(
            ServerSelfUpdateProgressEvent.self,
            from: Data("""
            {
              "type": "complete",
              "result": {
                "targetVersion": "0.2.0",
                "method": "desktop-app",
                "desktopUpdateToken": "tok-abc"
              }
            }
            """.utf8)
        )
        #expect(
            completeDesktop == .complete(
                result: ServerSelfUpdateResult(
                    targetVersion: "0.2.0",
                    method: .desktopManaged,
                    updateId: nil,
                    desktopUpdateToken: "tok-abc"
                )
            )
        )
    }

    // MARK: - GitHubReleaseClient

    private static func httpResponse(
        url: URL,
        status: Int = 200,
        headers: [String: String] = [:]
    ) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    private static let sampleReleaseJSON = """
    {
      "tag_name": "v0.2.0",
      "name": "Swft v0.2.0",
      "body": "Multi-environment updates!",
      "html_url": "https://github.com/gojimq/swft/releases/tag/v0.2.0",
      "published_at": "2026-11-25T10:00:00Z",
      "assets": [
        {
          "name": "Swft-0.2.0-darwin-arm64.zip",
          "url": "https://api.github.com/repos/gojimq/swft/releases/assets/1001",
          "browser_download_url": "https://github.com/gojimq/swft/releases/download/v0.2.0/Swft-0.2.0-darwin-arm64.zip",
          "size": 42000000
        },
        {
          "name": "t3-0.2.0-darwin-arm64.tar.gz",
          "url": "https://api.github.com/repos/gojimq/swft/releases/assets/1002",
          "browser_download_url": "https://github.com/gojimq/swft/releases/download/v0.2.0/t3-0.2.0-darwin-arm64.tar.gz",
          "size": 25000000
        },
        {
          "name": "t3-0.2.0-linux-x64.tar.gz",
          "url": "https://api.github.com/repos/gojimq/swft/releases/assets/1003",
          "browser_download_url": "https://github.com/gojimq/swft/releases/download/v0.2.0/t3-0.2.0-linux-x64.tar.gz",
          "size": 24000000
        },
        {
          "name": "SHA256SUMS",
          "url": "https://api.github.com/repos/gojimq/swft/releases/assets/1004",
          "browser_download_url": "https://github.com/gojimq/swft/releases/download/v0.2.0/SHA256SUMS",
          "size": 256
        }
      ]
    }
    """

    @Test func parsesLatestReleaseJSONAndChecksums() async throws {
        let capturedRequests = OSAllocatedUnfairLock<[URLRequest]>(initialState: [])
        let client = GitHubReleaseClient(
            dataTransport: { request in
                capturedRequests.withLock { $0.append(request) }
                return (Data(Self.sampleReleaseJSON.utf8), Self.httpResponse(url: request.url!))
            },
            downloadTransport: { request, destinationURL, onProgress in
                let checksums = """
                \(String(repeating: "a", count: 64))  Swft-0.2.0-darwin-arm64.zip
                \(String(repeating: "B", count: 64)) *t3-0.2.0-darwin-arm64.tar.gz
                invalid line
                """
                try Data(checksums.utf8).write(to: destinationURL)
                onProgress(1.0)
                return Self.httpResponse(url: request.url!)
            }
        )

        let release = try await client.fetchLatestRelease()
        #expect(release.version == "0.2.0")
        #expect(release.semver == SwftSemver("0.2.0")!)
        #expect(release.tagName == "v0.2.0")
        #expect(release.notes == "Multi-environment updates!")
        #expect(release.macosAppAsset?.name == "Swft-0.2.0-darwin-arm64.zip")
        #expect(release.serverAssets["darwin-arm64"]?.name == "t3-0.2.0-darwin-arm64.tar.gz")
        #expect(release.serverAssets["linux-x64"]?.name == "t3-0.2.0-linux-x64.tar.gz")
        #expect(
            release.serverAsset(for: ExecutionEnvironmentPlatform(os: "darwin", arch: "arm64"))?.name
                == "t3-0.2.0-darwin-arm64.tar.gz"
        )
        #expect(release.checksumsAsset?.name == "SHA256SUMS")

        let reqs = capturedRequests.withLock { $0 }
        #expect(reqs.count == 1)
        #expect(reqs[0].url?.absoluteString == "https://api.github.com/repos/gojimq/swft/releases/latest")
        #expect(reqs[0].value(forHTTPHeaderField: "Authorization") == nil)

        let checksums = try await client.fetchChecksums(for: release)
        #expect(checksums["Swft-0.2.0-darwin-arm64.zip"] == String(repeating: "a", count: 64))
        #expect(checksums["t3-0.2.0-darwin-arm64.tar.gz"] == String(repeating: "b", count: 64))
        #expect(checksums.count == 2)
    }

    @Test func downloadsPublicAssetDirectlyWithoutAuthorization() async throws {
        let payload = Data("public-asset-bytes".utf8)
        let seenDownloadRequests = OSAllocatedUnfairLock<[URLRequest]>(initialState: [])

        let client = GitHubReleaseClient(
            dataTransport: { _ in
                Issue.record("Public download should not call API redirect endpoint")
                throw GitHubReleaseClientError.invalidResponse("unexpected")
            },
            downloadTransport: { request, destinationURL, onProgress in
                seenDownloadRequests.withLock { $0.append(request) }
                try payload.write(to: destinationURL)
                onProgress(0.5)
                onProgress(1.0)
                return Self.httpResponse(url: request.url!)
            }
        )

        let asset = SwftReleaseAsset(
            name: "Swft-0.2.0-darwin-arm64.zip",
            downloadURL: URL(string: "https://github.com/gojimq/swft/releases/download/v0.2.0/Swft-0.2.0-darwin-arm64.zip")!,
            apiURL: URL(string: "https://api.github.com/repos/gojimq/swft/releases/assets/1001")!,
            sizeBytes: Int64(payload.count)
        )

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("swft-public-test-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let progressEvents = OSAllocatedUnfairLock<[Double?]>(initialState: [])
        try await client.downloadAsset(asset, to: tempFile) { fraction in
            progressEvents.withLock { $0.append(fraction) }
        }

        #expect(try Data(contentsOf: tempFile) == payload)
        #expect(progressEvents.withLock { $0 } == [0.5, 1.0])

        let reqs = seenDownloadRequests.withLock { $0 }
        #expect(reqs.count == 1)
        #expect(reqs[0].url == asset.downloadURL)
        #expect(reqs[0].value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func downloadsPrivateAssetViaTwoStepRedirectAndStripsAuthorizationForS3() async throws {
        let payload = Data("private-asset-bytes".utf8)
        let signedURL = URL(string: "https://objects.githubusercontent.com/signed/asset?sig=xyz")!
        let step1Requests = OSAllocatedUnfairLock<[URLRequest]>(initialState: [])
        let step2Requests = OSAllocatedUnfairLock<[URLRequest]>(initialState: [])

        let memoryStore = InMemoryCredentialStore()
        let tokenStore = UpdateTokenStore(store: memoryStore)
        try tokenStore.saveToken("ghp_private_repo_token")

        let client = GitHubReleaseClient(
            tokenStore: tokenStore,
            dataTransport: { _ in
                throw GitHubReleaseClientError.invalidResponse("unused")
            },
            redirectInspectTransport: { request in
                step1Requests.withLock { $0.append(request) }
                let response = Self.httpResponse(
                    url: request.url!,
                    status: 302,
                    headers: ["Location": signedURL.absoluteString]
                )
                return (Data(), response)
            },
            downloadTransport: { request, destinationURL, onProgress in
                step2Requests.withLock { $0.append(request) }
                try payload.write(to: destinationURL)
                onProgress(1.0)
                return Self.httpResponse(url: request.url!)
            }
        )

        let asset = SwftReleaseAsset(
            name: "Swft-0.2.0-darwin-arm64.zip",
            downloadURL: URL(string: "https://github.com/gojimq/swft/releases/download/v0.2.0/Swft-0.2.0-darwin-arm64.zip")!,
            apiURL: URL(string: "https://api.github.com/repos/gojimq/swft/releases/assets/1001")!,
            sizeBytes: Int64(payload.count)
        )

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("swft-private-test-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        try await client.downloadAsset(asset, to: tempFile)

        #expect(try Data(contentsOf: tempFile) == payload)

        let req1 = step1Requests.withLock { $0 }
        #expect(req1.count == 1)
        #expect(req1[0].url == asset.apiURL)
        #expect(req1[0].value(forHTTPHeaderField: "Authorization") == "Bearer ghp_private_repo_token")
        #expect(req1[0].value(forHTTPHeaderField: "Accept") == "application/octet-stream")

        let req2 = step2Requests.withLock { $0 }
        #expect(req2.count == 1)
        #expect(req2[0].url == signedURL)
        // CRITICAL: Authorization MUST be stripped on the S3 redirect request.
        #expect(req2[0].value(forHTTPHeaderField: "Authorization") == nil)
    }

    // MARK: - LocalAppUpdater

    private static func makeFakeAppBundle(
        at appURL: URL,
        version: String,
        markerText: String = "v"
    ) throws {
        let fm = FileManager.default
        let macOSDir = appURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try fm.createDirectory(at: macOSDir, withIntermediateDirectories: true)

        let binaryURL = macOSDir.appendingPathComponent("Swft")
        try Data("#!/bin/sh\necho \(markerText)\n".utf8).write(to: binaryURL)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>CFBundleName</key><string>Swft</string>
          <key>CFBundleIdentifier</key><string>dev.swft.app</string>
          <key>CFBundleExecutable</key><string>Swft</string>
          <key>CFBundleShortVersionString</key><string>\(version)</string>
        </dict>
        </plist>
        """
        try Data(plist.utf8).write(to: appURL.appendingPathComponent("Contents/Info.plist"))
    }

    private static func zipAppWithDitto(appURL: URL, zipURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", appURL.path, zipURL.path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    @Test func stagesVerifiesSHA256ExtractsAndSwapsTempAppBundle() async throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("swft-updater-test-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        // Build a fake Swft.app v0.2.0 and zip it with ditto.
        let sourceDir = tempRoot.appendingPathComponent("source", isDirectory: true)
        let sourceApp = sourceDir.appendingPathComponent("Swft.app", isDirectory: true)
        try Self.makeFakeAppBundle(at: sourceApp, version: "0.2.0", markerText: "new-version")

        let sourceZip = tempRoot.appendingPathComponent("Swft-0.2.0-darwin-arm64.zip")
        try Self.zipAppWithDitto(appURL: sourceApp, zipURL: sourceZip)
        let zipBytes = try Data(contentsOf: sourceZip)
        let expectedSHA256 = try LocalAppUpdater.sha256Hex(ofFileAt: sourceZip)

        let release = SwftReleaseInfo(
            version: "0.2.0",
            semver: SwftSemver("0.2.0")!,
            tagName: "v0.2.0",
            name: "Swft v0.2.0",
            notes: "",
            htmlURL: URL(string: "https://github.com/gojimq/swft/releases/tag/v0.2.0")!,
            publishedAt: nil,
            macosAppAsset: SwftReleaseAsset(
                name: "Swft-0.2.0-darwin-arm64.zip",
                downloadURL: URL(string: "https://github.com/gojimq/swft/releases/download/v0.2.0/Swft-0.2.0-darwin-arm64.zip")!,
                apiURL: URL(string: "https://api.github.com/repos/gojimq/swft/releases/assets/1")!,
                sizeBytes: Int64(zipBytes.count)
            ),
            serverAssets: [:],
            checksumsAsset: nil
        )

        let releaseClient = GitHubReleaseClient(
            dataTransport: { request in (Data(), Self.httpResponse(url: request.url!)) },
            downloadTransport: { request, destinationURL, onProgress in
                try zipBytes.write(to: destinationURL)
                onProgress(1.0)
                return Self.httpResponse(url: request.url!)
            }
        )

        let cacheDir = tempRoot.appendingPathComponent("cache", isDirectory: true)
        let updater = LocalAppUpdater(cacheBaseDirectory: cacheDir)

        // 1. Checksum mismatch MUST be rejected before extraction.
        let wrongSHA = String(repeating: "0", count: 64)
        await #expect(throws: LocalAppUpdaterError.checksumMismatch(expected: wrongSHA, actual: expectedSHA256)) {
            _ = try await updater.stageUpdate(
                release: release,
                expectedSHA256: wrongSHA,
                releaseClient: releaseClient
            )
        }

        // 2. Matching checksum succeeds, extracts with ditto, and validates CFBundleShortVersionString.
        let stages = OSAllocatedUnfairLock<[LocalAppUpdateStage]>(initialState: [])
        let staged = try await updater.stageUpdate(
            release: release,
            expectedSHA256: expectedSHA256,
            releaseClient: releaseClient
        ) { stage in
            stages.withLock { $0.append(stage) }
        }
        #expect(staged.version == "0.2.0")
        #expect(staged.sha256 == expectedSHA256)
        #expect(fm.fileExists(atPath: staged.appURL.appendingPathComponent("Contents/MacOS/Swft").path))
        #expect(stages.withLock { $0 }.contains(.verifying))
        #expect(stages.withLock { $0 }.contains(.extracting))
        #expect(stages.withLock { $0 }.last == .ready)

        // 3. Eligibility check on a real temp .app vs non-.app binary.
        let installDir = tempRoot.appendingPathComponent("Applications", isDirectory: true)
        let targetApp = installDir.appendingPathComponent("Swft.app", isDirectory: true)
        try Self.makeFakeAppBundle(at: targetApp, version: "0.1.0", markerText: "old-version")

        #expect(updater.canUpdateCurrentApp(bundleURL: targetApp) == .eligible(appURL: targetApp.standardizedFileURL))
        if case .ineligible = updater.canUpdateCurrentApp(bundleURL: tempRoot.appendingPathComponent("Swft")) {
            // Expected
        } else {
            Issue.record("Non-.app bundle should be ineligible")
        }

        // 4. Atomic swap replaces v0.1.0 with v0.2.0 cleanly.
        try updater.applySwapSynchronously(staged: staged, targetAppURL: targetApp)
        let updatedVersion = try LocalAppUpdater.readShortVersionString(
            fromInfoPlistAt: targetApp.appendingPathComponent("Contents/Info.plist")
        )
        #expect(updatedVersion == "0.2.0")
    }

    @Test func rejectsExtractedBundleWhenInfoPlistVersionMismatchesRelease() async throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("swft-version-mismatch-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let sourceApp = tempRoot.appendingPathComponent("source/Swft.app", isDirectory: true)
        try Self.makeFakeAppBundle(at: sourceApp, version: "0.1.9")
        let sourceZip = tempRoot.appendingPathComponent("Swft-0.2.0-darwin-arm64.zip")
        try Self.zipAppWithDitto(appURL: sourceApp, zipURL: sourceZip)
        let zipBytes = try Data(contentsOf: sourceZip)
        let expectedSHA256 = try LocalAppUpdater.sha256Hex(ofFileAt: sourceZip)

        let release = SwftReleaseInfo(
            version: "0.2.0",
            semver: SwftSemver("0.2.0")!,
            tagName: "v0.2.0",
            name: "Swft v0.2.0",
            notes: "",
            htmlURL: URL(string: "https://github.com/gojimq/swft/releases/tag/v0.2.0")!,
            publishedAt: nil,
            macosAppAsset: SwftReleaseAsset(
                name: "Swft-0.2.0-darwin-arm64.zip",
                downloadURL: URL(string: "https://github.com/gojimq/swft/releases/download/v0.2.0/Swft-0.2.0-darwin-arm64.zip")!,
                apiURL: URL(string: "https://api.github.com/repos/gojimq/swft/releases/assets/1")!,
                sizeBytes: Int64(zipBytes.count)
            ),
            serverAssets: [:],
            checksumsAsset: nil
        )

        let client = GitHubReleaseClient(
            dataTransport: { request in (Data(), Self.httpResponse(url: request.url!)) },
            downloadTransport: { request, destinationURL, _ in
                try zipBytes.write(to: destinationURL)
                return Self.httpResponse(url: request.url!)
            }
        )

        let updater = LocalAppUpdater(cacheBaseDirectory: tempRoot.appendingPathComponent("cache", isDirectory: true))
        await #expect(throws: LocalAppUpdaterError.versionMismatch(expected: "0.2.0", actual: "0.1.9")) {
            _ = try await updater.stageUpdate(
                release: release,
                expectedSHA256: expectedSHA256,
                releaseClient: client
            )
        }
    }

    @Test func helperScriptPerformsSwapAfterDummyProcessExits() async throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("swft-helper-test-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let targetApp = tempRoot.appendingPathComponent("Swft.app", isDirectory: true)
        try Self.makeFakeAppBundle(at: targetApp, version: "0.1.0")

        let stagingDir = tempRoot.appendingPathComponent("staging", isDirectory: true)
        let stagedApp = stagingDir.appendingPathComponent("extracted/Swft.app", isDirectory: true)
        try Self.makeFakeAppBundle(at: stagedApp, version: "0.3.0")

        // Spawn a short-lived dummy process so the helper genuinely waits for PID exit.
        let dummy = Process()
        dummy.executableURL = URL(fileURLWithPath: "/bin/sleep")
        dummy.arguments = ["0.2"]
        try dummy.run()
        let dummyPID = dummy.processIdentifier

        let updater = LocalAppUpdater(cacheBaseDirectory: tempRoot)
        let staged = StagedAppUpdate(
            version: "0.3.0",
            stagingDirectory: stagingDir,
            appURL: stagedApp,
            sha256: String(repeating: "a", count: 64)
        )

        try updater.launchInstallHelper(
            staged: staged,
            targetAppURL: targetApp,
            currentPID: dummyPID,
            relaunch: false
        )

        // Wait up to 5 seconds for the helper script to finish swapping and clean up stagingDir.
        let deadline = ContinuousClock.now + .seconds(5)
        var observedVersion: String?
        while ContinuousClock.now < deadline {
            if let version = try? LocalAppUpdater.readShortVersionString(
                fromInfoPlistAt: targetApp.appendingPathComponent("Contents/Info.plist")
            ), version == "0.3.0", !fm.fileExists(atPath: stagingDir.path) {
                observedVersion = version
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(observedVersion == "0.3.0")
        #expect(!fm.fileExists(atPath: stagingDir.path))
    }

    // MARK: - ServerProcess Bundled Standalone Binary Discovery

    @Test func serverProcessPrefersBundledStandaloneBinaryWithoutRequiringNode() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("swft-server-discovery-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let resourcesDir = tempRoot.appendingPathComponent("Resources", isDirectory: true)
        let serverDir = resourcesDir.appendingPathComponent("server", isDirectory: true)
        try fm.createDirectory(at: serverDir, withIntermediateDirectories: true)

        // Put both server/t3 (SEA binary) and server/bin.mjs to verify server/t3 wins.
        let bundledBinary = serverDir.appendingPathComponent("t3")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: bundledBinary)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledBinary.path)

        let bundledMjs = serverDir.appendingPathComponent("bin.mjs")
        try Data("console.log('hi');\n".utf8).write(to: bundledMjs)

        #expect(ServerProcess.resolveBundledServerBinary(resourceURL: resourcesDir) == bundledBinary)

        // Even with an empty PATH and invalid SWFT_NODE_PATH, bundled server/t3 resolves cleanly without Node!
        let target = try ServerProcess.resolveLaunchTarget(
            configuration: ServerLaunchConfiguration(baseDirectory: tempRoot.appendingPathComponent("home")),
            resourceURL: resourcesDir,
            environment: ["PATH": "", "SWFT_NODE_PATH": "/nonexistent/node"]
        )
        #expect(target == .standaloneBinary(executableURL: bundledBinary))
        #expect(target.executableURL == bundledBinary)
        #expect(target.arguments == ["--bootstrap-fd", "0"])
    }
}
