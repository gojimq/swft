#if os(macOS)
import Darwin
import Foundation

/// Tailscale host status parsed from `tailscale status --json`, matching `packages/tailscale/src/tailscale.ts`.
public struct TailscaleHostInfo: Sendable, Equatable {
    public let installed: Bool
    public let binaryPath: String?
    public let running: Bool
    public let magicDNSName: String?
    public let tailnetIPv4: [String]
    public let httpsServeEnabled: Bool?
    public let activeServeURL: String?

    public init(
        installed: Bool = false,
        binaryPath: String? = nil,
        running: Bool = false,
        magicDNSName: String? = nil,
        tailnetIPv4: [String] = [],
        httpsServeEnabled: Bool? = nil,
        activeServeURL: String? = nil
    ) {
        self.installed = installed
        self.binaryPath = binaryPath
        self.running = running
        self.magicDNSName = magicDNSName
        self.tailnetIPv4 = tailnetIPv4
        self.httpsServeEnabled = httpsServeEnabled
        self.activeServeURL = activeServeURL
    }

    public var suggestedHTTPSBaseURL: String? {
        guard running, let magicDNSName, !magicDNSName.isEmpty else { return nil }
        return "https://\(magicDNSName)"
    }
}

public struct LocalNetworkInfo: Sendable, Equatable {
    public let lanIPv4Addresses: [String]
    public let tailscale: TailscaleHostInfo

    public init(lanIPv4Addresses: [String] = [], tailscale: TailscaleHostInfo = TailscaleHostInfo()) {
        self.lanIPv4Addresses = lanIPv4Addresses
        self.tailscale = tailscale
    }
}

public enum HostNetworkError: Error, Sendable, LocalizedError {
    case tailscaleNotInstalled
    case tailscaleCommandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .tailscaleNotInstalled:
            return "Tailscale CLI was not found on this Mac."
        case .tailscaleCommandFailed(let message):
            return message
        }
    }
}

/// Probes Tailscale CLI status and local private LAN IPv4 addresses for the "Share this Mac" section.
public enum HostNetworkHelper {
    public static func resolveTailscaleBinary(
        envPath: String? = ProcessInfo.processInfo.environment["PATH"],
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        var candidates = [
            "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
            "/opt/homebrew/bin/tailscale",
            "/usr/local/bin/tailscale",
        ]
        if let envPath {
            for dir in envPath.split(separator: ":").map(String.init) where !dir.isEmpty {
                candidates.append((dir as NSString).appendingPathComponent("tailscale"))
            }
        }
        var seen: Set<String> = []
        for path in candidates where seen.insert(path).inserted {
            if isExecutable(path) { return path }
        }
        return nil
    }

    public static func parseTailscaleStatusJSON(_ data: Data, binaryPath: String?) -> TailscaleHostInfo {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return TailscaleHostInfo(installed: binaryPath != nil, binaryPath: binaryPath)
        }
        let backendState = object["BackendState"] as? String
        let running = backendState == "Running"
        let selfNode = object["Self"] as? [String: Any]
        let rawDNS = (selfNode?["DNSName"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let magicDNS = rawDNS?.isEmpty == false ? rawDNS : nil
        let ips = (selfNode?["TailscaleIPs"] as? [String] ?? []).filter(isTailscaleIPv4)
        let capMap = selfNode?["CapMap"] as? [String: Any]
        let httpsServeEnabled = capMap.map { $0.keys.contains("https") }

        return TailscaleHostInfo(
            installed: binaryPath != nil,
            binaryPath: binaryPath,
            running: running,
            magicDNSName: magicDNS,
            tailnetIPv4: ips,
            httpsServeEnabled: httpsServeEnabled
        )
    }

    public static func isTailscaleIPv4(_ address: String) -> Bool {
        let parts = address.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        return parts[0] == 100 && parts[1] >= 64 && parts[1] <= 127
    }

    public static func isPrivateLANIPv4(_ address: String) -> Bool {
        let parts = address.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        if parts[0] == 10 { return true }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        if parts[0] == 192 && parts[1] == 168 { return true }
        return false
    }

    public static func detectLANIPv4Addresses() -> [String] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(first) }

        var results: [String] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            let flags = Int32(current.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0,
                  let addr = current.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET)
            else { continue }

            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let status = getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &hostBuffer,
                socklen_t(hostBuffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if status == 0 {
                let bytes = hostBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                let ip = String(decoding: bytes, as: UTF8.self)
                if isPrivateLANIPv4(ip) && !results.contains(ip) {
                    results.append(ip)
                }
            }
        }
        return results
    }

    public static func probeNetwork() async -> LocalNetworkInfo {
        let lan = detectLANIPv4Addresses()
        let tsPath = resolveTailscaleBinary()
        guard let tsPath else {
            return LocalNetworkInfo(lanIPv4Addresses: lan, tailscale: TailscaleHostInfo(installed: false))
        }
        let result = await runCLI(binaryPath: tsPath, arguments: ["status", "--json"])
        let tsInfo: TailscaleHostInfo
        if result.exitCode == 0 {
            tsInfo = parseTailscaleStatusJSON(result.stdout, binaryPath: tsPath)
        } else {
            tsInfo = TailscaleHostInfo(installed: true, binaryPath: tsPath, running: false)
        }
        return LocalNetworkInfo(lanIPv4Addresses: lan, tailscale: tsInfo)
    }

    public static func enableTailscaleServe(localPort: Int, servePort: Int = 443) async throws -> String {
        guard let tsPath = resolveTailscaleBinary() else {
            throw HostNetworkError.tailscaleNotInstalled
        }
        let target = "http://127.0.0.1:\(localPort)"
        let result = await runCLI(
            binaryPath: tsPath,
            arguments: ["serve", "--bg", "--https=\(servePort)", target]
        )
        guard result.exitCode == 0 else {
            let errText = String(data: result.stderr, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw HostNetworkError.tailscaleCommandFailed(
                errText?.isEmpty == false ? errText! : "tailscale serve exited with code \(result.exitCode)."
            )
        }
        let info = await probeNetwork()
        if let dns = info.tailscale.magicDNSName {
            return servePort == 443 ? "https://\(dns)" : "https://\(dns):\(servePort)"
        }
        throw HostNetworkError.tailscaleCommandFailed("Tailscale Serve started, but MagicDNS hostname is unavailable.")
    }

    public static func disableTailscaleServe(servePort: Int = 443) async throws {
        guard let tsPath = resolveTailscaleBinary() else {
            throw HostNetworkError.tailscaleNotInstalled
        }
        let result = await runCLI(
            binaryPath: tsPath,
            arguments: ["serve", "--https=\(servePort)", "--set-path=/", "off"]
        )
        guard result.exitCode == 0 else {
            let errText = String(data: result.stderr, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw HostNetworkError.tailscaleCommandFailed(
                errText?.isEmpty == false ? errText! : "Could not stop Tailscale Serve."
            )
        }
    }

    private struct CLIOutput: Sendable {
        let exitCode: Int32
        let stdout: Data
        let stderr: Data
    }

    private static func runCLI(binaryPath: String, arguments: [String]) async -> CLIOutput {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: binaryPath)
                proc.arguments = arguments
                let stdout = Pipe()
                let stderr = Pipe()
                proc.standardOutput = stdout
                proc.standardError = stderr
                proc.standardInput = FileHandle.nullDevice
                do {
                    try proc.run()
                    let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                    proc.waitUntilExit()
                    continuation.resume(returning: CLIOutput(exitCode: proc.terminationStatus, stdout: outData, stderr: errData))
                } catch {
                    continuation.resume(returning: CLIOutput(exitCode: -1, stdout: Data(), stderr: Data(error.localizedDescription.utf8)))
                }
            }
        }
    }
}
#endif
