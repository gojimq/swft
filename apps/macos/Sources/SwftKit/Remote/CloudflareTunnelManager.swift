import Darwin
import Foundation
import Observation
import os

/// Cloudflare Tunnel modes matching Studio's `cloudflareTunnel.cjs`.
public enum CloudflareTunnelMode: String, Codable, Sendable, CaseIterable, Hashable {
    case off
    case quick
    case named
    case external

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .quick: "Quick"
        case .named: "Named"
        case .external: "External"
        }
    }
}

public enum CloudflareTunnelPhase: String, Sendable, Equatable {
    case off
    case starting
    case running
    case error

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .starting: "Starting"
        case .running: "Running"
        case .error: "Error"
        }
    }
}

public struct CloudflareTunnelItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let createdAt: String?
    public let connectionsCount: Int

    public init(id: String, name: String, createdAt: String? = nil, connectionsCount: Int = 0) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.connectionsCount = connectionsCount
    }
}

public struct CloudflareTunnelConfig: Codable, Sendable, Equatable {
    public var mode: CloudflareTunnelMode
    public var publicUrl: String
    public var tunnelName: String

    public init(mode: CloudflareTunnelMode = .off, publicUrl: String = "", tunnelName: String = "") {
        self.mode = mode
        self.publicUrl = publicUrl
        self.tunnelName = tunnelName
    }
}

public struct CloudflareTunnelStatus: Sendable, Equatable {
    public var mode: CloudflareTunnelMode
    public var phase: CloudflareTunnelPhase
    public var publicUrl: String
    public var tunnelName: String
    public var activePublicUrl: String?
    public var localPort: Int?
    public var cloudflaredInstalled: Bool
    public var cloudflaredPath: String?
    public var error: String?

    public init(
        mode: CloudflareTunnelMode = .off,
        phase: CloudflareTunnelPhase = .off,
        publicUrl: String = "",
        tunnelName: String = "",
        activePublicUrl: String? = nil,
        localPort: Int? = nil,
        cloudflaredInstalled: Bool = false,
        cloudflaredPath: String? = nil,
        error: String? = nil
    ) {
        self.mode = mode
        self.phase = phase
        self.publicUrl = publicUrl
        self.tunnelName = tunnelName
        self.activePublicUrl = activePublicUrl
        self.localPort = localPort
        self.cloudflaredInstalled = cloudflaredInstalled
        self.cloudflaredPath = cloudflaredPath
        self.error = error
    }
}

/// Pure parsing, normalization, binary resolution, and config persistence helpers matching Studio's `cloudflareTunnel.cjs`.
public enum CloudflareTunnelHelpers {
    public static let configFilename = "tunnel.json"

    public static func extractQuickTunnelURL(from output: String) -> String? {
        let pattern = #/https://[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?\.trycloudflare\.com\b/#
        guard !output.isEmpty, let match = output.firstMatch(of: pattern) else {
            return nil
        }
        return String(match.0).lowercased()
    }

    public static func isNamedTunnelReadyLine(_ text: String) -> Bool {
        text.localizedCaseInsensitiveContains("registered tunnel connection")
    }

    public static func normalizePublicURL(_ rawURL: String) -> String? {
        PairingURLParser.normalizeHTTPSPublicURL(rawURL)
    }

    private struct RawTunnelEntry: Decodable {
        let id: String?
        let name: String?
        let created_at: String?
        let connections: [JSONValue]?
    }

    public static func parseTunnelListJSON(_ data: Data) -> [CloudflareTunnelItem] {
        guard !data.isEmpty,
              let raw = try? JSONDecoder().decode([RawTunnelEntry].self, from: data)
        else { return [] }

        return raw.compactMap { entry in
            let name = entry.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { return nil }
            let id = entry.id?.trimmingCharacters(in: .whitespacesAndNewlines)
            return CloudflareTunnelItem(
                id: id?.isEmpty == false ? id! : name,
                name: name,
                createdAt: entry.created_at,
                connectionsCount: entry.connections?.count ?? 0
            )
        }
    }

    public static func resolveCloudflaredBinary(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        envPath: String? = ProcessInfo.processInfo.environment["PATH"],
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        var candidates: [String] = [
            homeDirectory.appendingPathComponent(".local/bin/cloudflared").path,
            "/opt/homebrew/bin/cloudflared",
            "/usr/local/bin/cloudflared",
        ]
        if let envPath {
            for dir in envPath.split(separator: ":").map(String.init) where !dir.isEmpty {
                candidates.append((dir as NSString).appendingPathComponent("cloudflared"))
            }
        }
        var seen: Set<String> = []
        for candidate in candidates where seen.insert(candidate).inserted {
            if isExecutable(candidate) {
                return candidate
            }
        }
        return nil
    }

    public static func readConfig(from baseDirectory: URL) -> CloudflareTunnelConfig {
        let url = baseDirectory.appendingPathComponent(configFilename)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CloudflareTunnelConfig.self, from: data)
        else {
            return CloudflareTunnelConfig()
        }
        return sanitize(decoded)
    }

    @discardableResult
    public static func writeConfig(_ config: CloudflareTunnelConfig, to baseDirectory: URL) throws -> CloudflareTunnelConfig {
        let sanitized = sanitize(config)
        let fileURL = baseDirectory.appendingPathComponent(configFilename)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(sanitized)
        data.append(0x0A)
        let tempURL = baseDirectory.appendingPathComponent(".\(configFilename).\(UUID().uuidString).tmp")
        try data.write(to: tempURL, options: .atomic)
        do {
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
        return sanitized
    }

    public static func sanitize(_ config: CloudflareTunnelConfig) -> CloudflareTunnelConfig {
        let trimmedURL = config.publicUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedURL = trimmedURL.isEmpty ? "" : (normalizePublicURL(trimmedURL) ?? "")
        let trimmedName = config.tunnelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return CloudflareTunnelConfig(mode: config.mode, publicUrl: normalizedURL, tunnelName: trimmedName)
    }

    public static func summarizeOutputTail(_ tail: String) -> String? {
        tail.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last(where: { !$0.isEmpty })
    }
}

/// Manages an optional `cloudflared` child process for sharing this Mac over HTTPS.
/// Terminates ONLY the exact PID it spawned; never kills processes by name or pattern.
@MainActor
@Observable
public final class CloudflareTunnelController {
    public private(set) var status: CloudflareTunnelStatus
    public private(set) var namedTunnels: [CloudflareTunnelItem] = []
    public private(set) var isBusy: Bool = false
    public private(set) var isLoadingTunnels: Bool = false

    private let baseDirectory: URL
    private let resolveBinary: @Sendable () -> String?
    private let listTunnelsHandler: @Sendable (_ binaryPath: String) async -> [CloudflareTunnelItem]

    @ObservationIgnored private let trackedPID = OSAllocatedUnfairLock<Int32?>(initialState: nil)
    @ObservationIgnored private var config: CloudflareTunnelConfig
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var stdoutPipe: Pipe?
    @ObservationIgnored private var stderrPipe: Pipe?
    @ObservationIgnored private var namedReadyTask: Task<Void, Never>?
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var stopping = false
    @ObservationIgnored private var outputTail = ""
    @ObservationIgnored private var localPort: Int?

    public init(
        baseDirectory: URL = ServerLaunchConfiguration.defaultBaseDirectory,
        localPort: Int? = nil,
        resolveBinary: (@Sendable () -> String?)? = nil,
        listTunnelsHandler: (@Sendable (_ binaryPath: String) async -> [CloudflareTunnelItem])? = nil
    ) {
        self.baseDirectory = baseDirectory
        self.localPort = localPort
        let resolver = resolveBinary ?? { CloudflareTunnelHelpers.resolveCloudflaredBinary() }
        self.resolveBinary = resolver
        self.listTunnelsHandler = listTunnelsHandler ?? { binaryPath in
            await Self.runTunnelListCommand(binaryPath: binaryPath)
        }

        let loaded = CloudflareTunnelHelpers.readConfig(from: baseDirectory)
        self.config = loaded
        let binaryPath = resolver()

        var initialPhase: CloudflareTunnelPhase = .off
        var initialActiveURL: String?
        if loaded.mode == .external, !loaded.publicUrl.isEmpty,
           let normalized = CloudflareTunnelHelpers.normalizePublicURL(loaded.publicUrl)
        {
            initialPhase = .running
            initialActiveURL = normalized
        }

        self.status = CloudflareTunnelStatus(
            mode: loaded.mode,
            phase: initialPhase,
            publicUrl: loaded.publicUrl,
            tunnelName: loaded.tunnelName,
            activePublicUrl: initialActiveURL,
            localPort: localPort,
            cloudflaredInstalled: binaryPath != nil,
            cloudflaredPath: binaryPath,
            error: nil
        )
    }

    /// Synchronously sends SIGTERM to ONLY the exact `cloudflared` PID spawned by this controller.
    public nonisolated func terminateImmediately() {
        let pid = trackedPID.withLock { current -> Int32? in
            let captured = current
            current = nil
            return captured
        }
        if let pid, pid > 0 {
            _ = Darwin.kill(pid, SIGTERM)
        }
    }

    public func updateLocalPort(_ port: Int?) {
        localPort = port
        status.localPort = port
    }

    public func configure(
        mode: CloudflareTunnelMode? = nil,
        publicUrl: String? = nil,
        tunnelName: String? = nil
    ) async {
        isBusy = true
        defer { isBusy = false }

        let nextMode = mode ?? config.mode
        let nextTunnelName = tunnelName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? config.tunnelName
        var nextPublicURL = config.publicUrl
        var publicURLError: String?

        if let publicUrl {
            let trimmed = publicUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                nextPublicURL = ""
            } else if let normalized = CloudflareTunnelHelpers.normalizePublicURL(trimmed) {
                nextPublicURL = normalized
            } else {
                publicURLError = "Enter a valid https:// public URL."
            }
        }

        let modeChanged = nextMode != config.mode
        let nameChanged = nextTunnelName != config.tunnelName

        config = CloudflareTunnelConfig(mode: nextMode, publicUrl: nextPublicURL, tunnelName: nextTunnelName)
        _ = try? CloudflareTunnelHelpers.writeConfig(config, to: baseDirectory)

        if modeChanged || (nextMode == .named && nameChanged) || nextMode == .off {
            await stopChildProcess()
            status.activePublicUrl = nil
            status.phase = .off
            status.error = nil
        }

        let binaryPath = resolveBinary()
        status.mode = config.mode
        status.publicUrl = config.publicUrl
        status.tunnelName = config.tunnelName
        status.cloudflaredInstalled = binaryPath != nil
        status.cloudflaredPath = binaryPath

        if let publicURLError {
            status.phase = .error
            status.activePublicUrl = nil
            status.error = publicURLError
            return
        }

        if nextMode == .external {
            await stopChildProcess()
            if !nextPublicURL.isEmpty {
                status.phase = .running
                status.activePublicUrl = nextPublicURL
                status.error = nil
            } else {
                status.phase = .off
                status.activePublicUrl = nil
                status.error = nil
            }
            return
        }

        if nextMode == .named && process?.isRunning == true && status.phase == .running {
            status.activePublicUrl = nextPublicURL.isEmpty ? nil : nextPublicURL
            status.error = nil
            return
        }

        if nextMode == .named && namedTunnels.isEmpty {
            await refreshNamedTunnels()
        }
    }

    public func start() async {
        isBusy = true
        defer { isBusy = false }

        let binaryPath = resolveBinary()
        status.cloudflaredInstalled = binaryPath != nil
        status.cloudflaredPath = binaryPath

        if config.mode == .off {
            status.phase = .off
            status.activePublicUrl = nil
            status.error = nil
            return
        }

        if config.mode == .external {
            await stopChildProcess()
            guard let normalized = CloudflareTunnelHelpers.normalizePublicURL(config.publicUrl) else {
                status.phase = .error
                status.activePublicUrl = nil
                status.error = "Enter a valid https:// public URL for your external tunnel."
                return
            }
            status.phase = .running
            status.activePublicUrl = normalized
            status.error = nil
            return
        }

        await stopChildProcess()

        guard let binaryPath else {
            status.phase = .error
            status.activePublicUrl = nil
            status.error = "cloudflared was not found. Install it with `brew install cloudflared`."
            return
        }

        guard let port = localPort, (1...65535).contains(port) else {
            status.phase = .error
            status.activePublicUrl = nil
            status.error = "Local Swft server is not ready yet."
            return
        }

        let targetURL = "http://127.0.0.1:\(port)"
        let args: [String]
        var expectedNamedURL: String?

        switch config.mode {
        case .quick:
            args = ["tunnel", "--no-autoupdate", "--url", targetURL]
        case .named:
            guard !config.tunnelName.isEmpty else {
                status.phase = .error
                status.activePublicUrl = nil
                status.error = "Select or enter a Cloudflare tunnel name first."
                return
            }
            guard let normalized = CloudflareTunnelHelpers.normalizePublicURL(config.publicUrl) else {
                status.phase = .error
                status.activePublicUrl = nil
                status.error = "Enter the https:// public hostname routed to this Cloudflare tunnel."
                return
            }
            expectedNamedURL = normalized
            args = ["tunnel", "--no-autoupdate", "run", "--url", targetURL, config.tunnelName]
        case .off, .external:
            return
        }

        generation &+= 1
        let runGen = generation
        stopping = false
        outputTail = ""
        status.phase = .starting
        status.activePublicUrl = nil
        status.error = nil

        let child = Process()
        child.executableURL = URL(fileURLWithPath: binaryPath)
        child.arguments = args

        let stdout = Pipe()
        let stderr = Pipe()
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = stdout
        child.standardError = stderr

        let capturedMode = config.mode
        let capturedNamedURL = expectedNamedURL

        let handleChunk: @Sendable (Data) -> Void = { [weak self] data in
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.processOutput(text, generation: runGen, mode: capturedMode, expectedNamedURL: capturedNamedURL)
            }
        }
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                handleChunk(data)
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                handleChunk(data)
            }
        }
        child.terminationHandler = { [weak self] proc in
            let code = proc.terminationStatus
            let reason = proc.terminationReason
            Task { @MainActor [weak self] in
                self?.handleExit(code: code, reason: reason, generation: runGen)
            }
        }

        do {
            try child.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            status.phase = .error
            status.activePublicUrl = nil
            status.error = "Could not start cloudflared: \(error.localizedDescription)"
            return
        }

        process = child
        stdoutPipe = stdout
        stderrPipe = stderr
        trackedPID.withLock { $0 = child.processIdentifier }

        if capturedMode == .named, let expected = capturedNamedURL {
            namedReadyTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled, let self, self.generation == runGen, !self.stopping, self.status.phase == .starting else { return }
                self.status.phase = .running
                self.status.activePublicUrl = expected
                self.status.error = nil
            }
        }
    }

    public func stop() async {
        isBusy = true
        defer { isBusy = false }
        await stopChildProcess()
        status.phase = .off
        status.activePublicUrl = nil
        status.error = nil
    }

    public func refreshNamedTunnels() async {
        let binaryPath = resolveBinary()
        status.cloudflaredInstalled = binaryPath != nil
        status.cloudflaredPath = binaryPath
        guard let binaryPath else {
            namedTunnels = []
            return
        }
        isLoadingTunnels = true
        let items = await listTunnelsHandler(binaryPath)
        namedTunnels = items
        isLoadingTunnels = false
    }

    // MARK: - Private Process Helpers

    private func processOutput(
        _ text: String,
        generation runGen: UInt64,
        mode: CloudflareTunnelMode,
        expectedNamedURL: String?
    ) {
        guard generation == runGen, !stopping else { return }
        outputTail += text
        if outputTail.count > 4096 {
            outputTail = String(outputTail.suffix(4096))
        }

        if mode == .quick && status.phase == .starting {
            let recent = String(outputTail.suffix(512))
            if let found = CloudflareTunnelHelpers.extractQuickTunnelURL(from: recent) {
                status.phase = .running
                status.activePublicUrl = found
                status.error = nil
            }
        } else if mode == .named && status.phase == .starting {
            if CloudflareTunnelHelpers.isNamedTunnelReadyLine(text), let expectedNamedURL {
                namedReadyTask?.cancel()
                namedReadyTask = nil
                status.phase = .running
                status.activePublicUrl = expectedNamedURL
                status.error = nil
            }
        }
    }

    private func handleExit(code: Int32, reason: Process.TerminationReason, generation runGen: UInt64) {
        guard generation == runGen else { return }
        namedReadyTask?.cancel()
        namedReadyTask = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe = nil
        process = nil
        trackedPID.withLock { $0 = nil }

        if stopping {
            status.phase = .off
            status.activePublicUrl = nil
            status.error = nil
            return
        }

        let detail = CloudflareTunnelHelpers.summarizeOutputTail(outputTail)
        let exitSummary = reason == .uncaughtSignal ? "exited on signal \(code)" : "exited with code \(code)"
        status.phase = .error
        status.activePublicUrl = nil
        status.error = detail.map { "cloudflared \(exitSummary): \($0)" } ?? "cloudflared \(exitSummary)."
    }

    private func stopChildProcess() async {
        stopping = true
        generation &+= 1
        namedReadyTask?.cancel()
        namedReadyTask = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        if let child = process, child.isRunning {
            let pid = child.processIdentifier
            _ = Darwin.kill(pid, SIGTERM)
            let deadline = ContinuousClock.now + .seconds(3)
            while child.isRunning && ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
            if child.isRunning {
                _ = Darwin.kill(pid, SIGKILL)
            }
        }

        stdoutPipe = nil
        stderrPipe = nil
        process = nil
        trackedPID.withLock { $0 = nil }
    }

    private static func runTunnelListCommand(binaryPath: String) async -> [CloudflareTunnelItem] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: binaryPath)
                proc.arguments = ["tunnel", "list", "--output", "json"]
                let stdout = Pipe()
                proc.standardOutput = stdout
                proc.standardError = FileHandle.nullDevice
                proc.standardInput = FileHandle.nullDevice

                do {
                    try proc.run()
                    let data = stdout.fileHandleForReading.readDataToEndOfFile()
                    proc.waitUntilExit()
                    guard proc.terminationStatus == 0 else {
                        continuation.resume(returning: [])
                        return
                    }
                    continuation.resume(returning: CloudflareTunnelHelpers.parseTunnelListJSON(data))
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }
}
