#if os(macOS)
import CryptoKit
import Foundation

// MARK: - Local App Update Models

public enum LocalAppUpdateEligibility: Sendable, Equatable {
    case eligible(appURL: URL)
    case ineligible(reason: String)
}

public enum LocalAppUpdateStage: Sendable, Equatable {
    case downloading(fraction: Double?)
    case verifying
    case extracting
    case ready
}

public struct StagedAppUpdate: Sendable, Equatable {
    public let version: String
    public let stagingDirectory: URL
    public let appURL: URL
    public let sha256: String

    public init(
        version: String,
        stagingDirectory: URL,
        appURL: URL,
        sha256: String
    ) {
        self.version = version
        self.stagingDirectory = stagingDirectory
        self.appURL = appURL
        self.sha256 = sha256
    }
}

public enum LocalAppUpdaterError: Error, Sendable, Equatable, LocalizedError {
    case ineligible(String)
    case missingAppAsset(version: String)
    case missingExpectedChecksum(assetName: String)
    case checksumMismatch(expected: String, actual: String)
    case extractionFailed(status: Int32, stderr: String)
    case invalidAppBundle(String)
    case versionMismatch(expected: String, actual: String?)
    case swapFailed(String)
    case helperLaunchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .ineligible(let reason):
            return reason
        case .missingAppAsset(let version):
            return "Release v\(version) does not include a macOS Swft.app archive."
        case .missingExpectedChecksum(let assetName):
            return "SHA256SUMS does not contain a checksum for \(assetName); refusing to install an unverified archive."
        case .checksumMismatch(let expected, let actual):
            return "SHA-256 verification failed (expected \(expected), got \(actual))."
        case .extractionFailed(let status, let stderr):
            return "Failed to extract Swft.app (ditto exited with status \(status)): \(stderr)"
        case .invalidAppBundle(let detail):
            return "Downloaded update does not contain a valid Swft.app bundle: \(detail)"
        case .versionMismatch(let expected, let actual):
            return "Extracted Swft.app version (\(actual ?? "unknown")) does not match expected release version \(expected)."
        case .swapFailed(let detail):
            return "Failed to replace Swft.app: \(detail)"
        case .helperLaunchFailed(let detail):
            return "Failed to launch update helper: \(detail)"
        }
    }
}

// MARK: - Local App Updater

/// Downloads, SHA-256 verifies, extracts, and atomically swaps `Swft.app` on macOS.
public struct LocalAppUpdater: Sendable {
    public let cacheBaseDirectory: URL

    public static var defaultCacheBaseDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches", isDirectory: true)
        return caches
            .appendingPathComponent("Swft", isDirectory: true)
            .appendingPathComponent("updates", isDirectory: true)
    }

    public init(cacheBaseDirectory: URL = LocalAppUpdater.defaultCacheBaseDirectory) {
        self.cacheBaseDirectory = cacheBaseDirectory
    }

    // MARK: - Eligibility

    public func canUpdateCurrentApp(
        bundleURL: URL = Bundle.main.bundleURL
    ) -> LocalAppUpdateEligibility {
        let fm = FileManager.default
        let resolved = bundleURL.standardizedFileURL

        guard resolved.pathExtension == "app" else {
            return .ineligible(
                reason: "Automatic app updates require running from a packaged Swft.app bundle."
            )
        }

        if resolved.path.contains("/AppTranslocation/") {
            return .ineligible(
                reason: "Swft.app is running from a translocated path. Move Swft.app to /Applications first."
            )
        }

        let executableURL = resolved.appendingPathComponent("Contents/MacOS/Swft")
        let plistURL = resolved.appendingPathComponent("Contents/Info.plist")
        guard fm.fileExists(atPath: executableURL.path), fm.fileExists(atPath: plistURL.path) else {
            return .ineligible(reason: "Bundle at \(resolved.path) is not a valid Swft.app.")
        }

        if let values = try? resolved.resourceValues(forKeys: [.volumeIsReadOnlyKey]),
           values.volumeIsReadOnly == true
        {
            return .ineligible(
                reason: "Swft.app is on a read-only volume. Copy it to /Applications to enable updates."
            )
        }

        let parentDir = resolved.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: parentDir.path) else {
            return .ineligible(
                reason: "Cannot write to \(parentDir.path). Move Swft.app to a writable Applications folder."
            )
        }

        return .eligible(appURL: resolved)
    }

    // MARK: - Staging & Verification

    public func stageUpdate(
        release: SwftReleaseInfo,
        expectedSHA256: String?,
        releaseClient: GitHubReleaseClient,
        token: String? = nil,
        onProgress: @escaping @Sendable (LocalAppUpdateStage) -> Void = { _ in }
    ) async throws -> StagedAppUpdate {
        guard let asset = release.macosAppAsset else {
            throw LocalAppUpdaterError.missingAppAsset(version: release.version)
        }
        let normalizedExpected = expectedSHA256?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let normalizedExpected, normalizedExpected.count == 64, normalizedExpected.allSatisfy(\.isHexDigit) else {
            throw LocalAppUpdaterError.missingExpectedChecksum(assetName: asset.name)
        }

        let fm = FileManager.default
        let stagingDir = cacheBaseDirectory.appendingPathComponent(release.version, isDirectory: true)
        if fm.fileExists(atPath: stagingDir.path) {
            try fm.removeItem(at: stagingDir)
        }
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        let zipURL = stagingDir.appendingPathComponent(asset.name)
        try await releaseClient.downloadAsset(asset, to: zipURL, token: token) { fraction in
            onProgress(.downloading(fraction: fraction))
        }

        onProgress(.verifying)
        let actualSHA256 = try Self.sha256Hex(ofFileAt: zipURL)
        guard actualSHA256 == normalizedExpected else {
            try? fm.removeItem(at: stagingDir)
            throw LocalAppUpdaterError.checksumMismatch(
                expected: normalizedExpected,
                actual: actualSHA256
            )
        }

        onProgress(.extracting)
        let extractedDir = stagingDir.appendingPathComponent("extracted", isDirectory: true)
        try fm.createDirectory(at: extractedDir, withIntermediateDirectories: true)
        try Self.extractZipWithDitto(zipURL: zipURL, destinationDirectory: extractedDir)

        let stagedAppURL = extractedDir.appendingPathComponent("Swft.app", isDirectory: true)
        let executableURL = stagedAppURL.appendingPathComponent("Contents/MacOS/Swft")
        let plistURL = stagedAppURL.appendingPathComponent("Contents/Info.plist")

        guard fm.fileExists(atPath: executableURL.path) else {
            try? fm.removeItem(at: stagingDir)
            throw LocalAppUpdaterError.invalidAppBundle("Missing Contents/MacOS/Swft.")
        }
        guard fm.fileExists(atPath: plistURL.path) else {
            try? fm.removeItem(at: stagingDir)
            throw LocalAppUpdaterError.invalidAppBundle("Missing Contents/Info.plist.")
        }

        let bundledVersion = try Self.readShortVersionString(fromInfoPlistAt: plistURL)
        guard bundledVersion == release.version else {
            try? fm.removeItem(at: stagingDir)
            throw LocalAppUpdaterError.versionMismatch(
                expected: release.version,
                actual: bundledVersion
            )
        }

        // Remove the downloaded archive once extraction and validation succeed.
        try? fm.removeItem(at: zipURL)

        onProgress(.ready)
        return StagedAppUpdate(
            version: release.version,
            stagingDirectory: stagingDir,
            appURL: stagedAppURL,
            sha256: actualSHA256
        )
    }

    // MARK: - Atomic Swap & Relaunch

    /// Synchronously swaps `staged.appURL` into `targetAppURL` using a sibling backup with rollback on error.
    public func applySwapSynchronously(
        staged: StagedAppUpdate,
        targetAppURL: URL
    ) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: staged.appURL.path) else {
            throw LocalAppUpdaterError.swapFailed("Staged app bundle does not exist at \(staged.appURL.path).")
        }

        let parentDir = targetAppURL.deletingLastPathComponent()
        let backupURL = parentDir.appendingPathComponent(
            ".\(targetAppURL.lastPathComponent).swft-backup-\(UUID().uuidString)",
            isDirectory: true
        )
        let hadExistingTarget = fm.fileExists(atPath: targetAppURL.path)

        if hadExistingTarget {
            do {
                try fm.moveItem(at: targetAppURL, to: backupURL)
            } catch {
                throw LocalAppUpdaterError.swapFailed(
                    "Could not move current app to backup: \(error.localizedDescription)"
                )
            }
        }

        do {
            try fm.moveItem(at: staged.appURL, to: targetAppURL)
        } catch {
            if hadExistingTarget {
                try? fm.moveItem(at: backupURL, to: targetAppURL)
            }
            throw LocalAppUpdaterError.swapFailed(
                "Could not move staged app into place (restored previous app): \(error.localizedDescription)"
            )
        }

        if hadExistingTarget {
            try? fm.removeItem(at: backupURL)
        }
    }

    /// Writes and spawns a detached `/bin/sh` helper that waits for `currentPID` to exit,
    /// atomically swaps `targetAppURL`, relaunches the updated app, and cleans up staging.
    public func installAndRelaunch(
        staged: StagedAppUpdate,
        targetAppURL: URL,
        currentPID: Int32 = ProcessInfo.processInfo.processIdentifier
    ) throws {
        try launchInstallHelper(
            staged: staged,
            targetAppURL: targetAppURL,
            currentPID: currentPID,
            relaunch: true
        )
    }

    /// Internal entry point allowing unit tests to exercise the real helper script without opening a GUI app.
    internal func launchInstallHelper(
        staged: StagedAppUpdate,
        targetAppURL: URL,
        currentPID: Int32,
        relaunch: Bool
    ) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: staged.appURL.path) else {
            throw LocalAppUpdaterError.swapFailed("Staged app bundle missing at \(staged.appURL.path).")
        }

        let scriptURL = staged.stagingDirectory.appendingPathComponent("apply-update.sh")
        let script = makeInstallHelperScript(
            staged: staged,
            targetAppURL: targetAppURL,
            currentPID: currentPID,
            relaunch: relaunch
        )

        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        } catch {
            throw LocalAppUpdaterError.helperLaunchFailed(
                "Could not write install helper script: \(error.localizedDescription)"
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw LocalAppUpdaterError.helperLaunchFailed(error.localizedDescription)
        }
    }

    public func makeInstallHelperScript(
        staged: StagedAppUpdate,
        targetAppURL: URL,
        currentPID: Int32,
        relaunch: Bool = true
    ) -> String {
        let targetParent = targetAppURL.deletingLastPathComponent().path
        let backupName = ".\(targetAppURL.lastPathComponent).swft-backup-\(UUID().uuidString)"
        let backupPath = (targetParent as NSString).appendingPathComponent(backupName)

        let relaunchLine = relaunch
            ? "/usr/bin/open -n \"$TARGET\" >/dev/null 2>&1 || true"
            : ": # relaunch skipped"

        return """
        #!/bin/sh
        set -eu
        PID=\(currentPID)
        TARGET=\(Self.shellQuote(targetAppURL.path))
        STAGED=\(Self.shellQuote(staged.appURL.path))
        BACKUP=\(Self.shellQuote(backupPath))
        STAGING_DIR=\(Self.shellQuote(staged.stagingDirectory.path))

        # Wait up to 15 seconds for the running app process to exit.
        attempts=0
        while [ "$PID" -gt 0 ] && kill -0 "$PID" 2>/dev/null; do
          attempts=$((attempts + 1))
          if [ "$attempts" -ge 150 ]; then
            break
          fi
          sleep 0.1
        done

        had_target=0
        if [ -e "$TARGET" ]; then
          had_target=1
          mv "$TARGET" "$BACKUP"
        fi

        if ! mv "$STAGED" "$TARGET"; then
          if [ "$had_target" -eq 1 ] && [ -e "$BACKUP" ]; then
            mv "$BACKUP" "$TARGET" || true
          fi
          exit 1
        fi

        if [ "$had_target" -eq 1 ]; then
          rm -rf "$BACKUP" || true
        fi

        \(relaunchLine)
        rm -rf "$STAGING_DIR" || true
        """
    }

    // MARK: - Helpers

    public static func sha256Hex(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 65_536) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func readShortVersionString(fromInfoPlistAt url: URL) throws -> String? {
        let data = try Data(contentsOf: url)
        let raw = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dict = raw as? [String: Any] else { return nil }
        return dict["CFBundleShortVersionString"] as? String
    }

    private static func extractZipWithDitto(zipURL: URL, destinationDirectory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-xk", zipURL.path, destinationDirectory.path]
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
            throw LocalAppUpdaterError.extractionFailed(
                status: process.terminationStatus,
                stderr: stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
#endif
