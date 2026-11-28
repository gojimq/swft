import AVFoundation
import CryptoKit
import Foundation
import SwiftUI

/// Lightweight media-type classifier for SwftDesign views (matches `SwftKit`'s `ImageSourceLocation.mediaKind`).
public enum SwftMediaClassifier {
    private static let videoExtensions: Set<String> = ["mp4", "m4v", "mov", "webm", "mkv", "avi", "ogv"]

    public static func fileExtension(for rawSource: String) -> String? {
        var source = rawSource.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.hasPrefix("<"), source.hasSuffix(">"), source.count >= 2 {
            source = String(source.dropFirst().dropLast())
        }
        let lower = source.lowercased()
        if lower.hasPrefix("data:video/mp4") { return "mp4" }
        if lower.hasPrefix("data:video/quicktime") { return "mov" }
        if lower.hasPrefix("data:video/webm") { return "webm" }
        let stripped = source.split(whereSeparator: { $0 == "?" || $0 == "#" }).first.map(String.init) ?? source
        let pathPart: String
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("file://"),
           let url = URL(string: stripped)
        {
            pathPart = url.path(percentEncoded: false)
        } else {
            pathPart = stripped.removingPercentEncoding ?? stripped
        }
        let ext = (pathPart as NSString).pathExtension.lowercased()
        return ext.isEmpty ? nil : ext
    }

    public static func isVideo(_ rawSource: String) -> Bool {
        let lower = rawSource.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.hasPrefix("data:video/") { return true }
        guard let ext = fileExtension(for: rawSource) else { return false }
        return videoExtensions.contains(ext)
    }

    public static func formatDuration(_ seconds: TimeInterval) -> String? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        let total = Int(seconds.rounded())
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

/// Resolves a media source string (host path, signed `/api/assets/...`, or remote URL) to a local file URL.
public struct SwftMediaLoader: Sendable {
    public var scope: String
    public var isCacheOnly: Bool
    public var fetchFile: @Sendable (String) async throws -> URL

    public init(scope: String, fetchFile: @escaping @Sendable (String) async throws -> URL) {
        self.scope = scope
        self.isCacheOnly = false
        self.fetchFile = fetchFile
    }

    private init(scope: String, isCacheOnly: Bool, fetchFile: @escaping @Sendable (String) async throws -> URL) {
        self.scope = scope
        self.isCacheOnly = isCacheOnly
        self.fetchFile = fetchFile
    }

    public static let cacheOnly = SwftMediaLoader(scope: "", isCacheOnly: true) { _ in
        throw CocoaError(.fileReadNoSuchFile)
    }
}

extension EnvironmentValues {
    @Entry public var swftMediaLoader: SwftMediaLoader = .cacheOnly
}

/// Cached local video file plus extracted poster frame, natural orientation-corrected aspect ratio, and duration.
public struct SwftVideoAsset: Sendable {
    public let localURL: URL
    public let poster: CGImage?
    public let aspectRatio: CGFloat
    public let duration: TimeInterval
    public let isPlayable: Bool

    public init(
        localURL: URL,
        poster: CGImage?,
        aspectRatio: CGFloat,
        duration: TimeInterval,
        isPlayable: Bool
    ) {
        self.localURL = localURL
        self.poster = poster
        self.aspectRatio = aspectRatio
        self.duration = duration
        self.isPlayable = isPlayable
    }
}

/// Bounded on-disk video cache shared across transcript rows. Downloads stream directly to disk with the real
/// extension so `AVPlayer` plays reliably over local, LAN, and Cloudflare Tunnel connections without signed-URL expiry.
@MainActor
public final class SwftVideoCache {
    public static let shared = SwftVideoCache()

    private nonisolated static let maxDiskBytes: UInt64 = 250 * 1024 * 1024
    private var memory: [String: SwftVideoAsset] = [:]
    private var inflight: [String: Task<SwftVideoAsset?, Never>] = [:]
    private var failed: Set<String> = []

    public init() {}

    public func cacheKey(source: String, scope: String) -> String {
        let lower = source.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("data:") {
            return "video:\(source)"
        }
        return "video:\(scope):\(source)"
    }

    public func asset(for key: String) -> SwftVideoAsset? {
        guard let cached = memory[key] else { return nil }
        if FileManager.default.fileExists(atPath: cached.localURL.path) {
            return cached
        }
        memory.removeValue(forKey: key)
        return nil
    }

    public func hasFailed(_ key: String) -> Bool {
        failed.contains(key)
    }

    public func store(_ asset: SwftVideoAsset, for key: String) {
        failed.remove(key)
        memory[key] = asset
    }

    public func retry(_ key: String) {
        failed.remove(key)
        memory.removeValue(forKey: key)
    }

    public func load(source: String, using loader: SwftMediaLoader) async -> SwftVideoAsset? {
        let key = cacheKey(source: source, scope: loader.scope)
        if let existing = asset(for: key) { return existing }
        if failed.contains(key) { return nil }
        if let running = inflight[key] { return await running.value }
        guard !loader.isCacheOnly else { return nil }

        let ext = SwftMediaClassifier.fileExtension(for: source) ?? "mp4"
        let cachedDiskURL = Self.diskURL(for: key, fileExtension: ext)
        let fetchFile = loader.fetchFile

        let task = Task<SwftVideoAsset?, Never> {
            let fileURL: URL
            if FileManager.default.fileExists(atPath: cachedDiskURL.path) {
                fileURL = cachedDiskURL
            } else {
                guard let downloadedURL = try? await fetchFile(source) else { return nil }
                do {
                    try Self.persist(downloadedURL, to: cachedDiskURL)
                    fileURL = cachedDiskURL
                } catch {
                    fileURL = downloadedURL
                }
            }
            return await Self.inspectVideo(at: fileURL)
        }

        inflight[key] = task
        let loaded = await task.value
        inflight.removeValue(forKey: key)

        if let loaded {
            memory[key] = loaded
            failed.remove(key)
        } else {
            failed.insert(key)
        }
        return loaded
    }

    private nonisolated static func cacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("SwftVideoCache", isDirectory: true)
    }

    private nonisolated static func diskURL(for key: String, fileExtension: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let safeExt = fileExtension.filter { $0.isLetter || $0.isNumber }
        let ext = safeExt.isEmpty ? "mp4" : safeExt
        return cacheDirectory().appendingPathComponent("\(hex).\(ext)")
    }

    private nonisolated static func persist(_ sourceURL: URL, to destinationURL: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if sourceURL.standardizedFileURL == destinationURL.standardizedFileURL { return }
        try? fm.removeItem(at: destinationURL)
        do {
            try fm.moveItem(at: sourceURL, to: destinationURL)
        } catch {
            try fm.copyItem(at: sourceURL, to: destinationURL)
            try? fm.removeItem(at: sourceURL)
        }
        trimDiskCacheIfNeeded(in: destinationURL.deletingLastPathComponent())
    }

    private nonisolated static func trimDiskCacheIfNeeded(in directory: URL) {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var entries: [(url: URL, size: UInt64, date: Date)] = []
        var totalSize: UInt64 = 0
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize
            else { continue }
            let byteCount = UInt64(max(0, size))
            totalSize += byteCount
            entries.append((url, byteCount, values.contentModificationDate ?? .distantPast))
        }
        guard totalSize > maxDiskBytes else { return }
        let target = maxDiskBytes * 3 / 4
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            guard totalSize > target else { break }
            try? fm.removeItem(at: entry.url)
            totalSize = totalSize > entry.size ? totalSize - entry.size : 0
        }
    }

    public nonisolated static func inspectVideo(at url: URL) async -> SwftVideoAsset {
        let asset = AVURLAsset(url: url)
        let isPlayable = (try? await asset.load(.isPlayable)) ?? false
        let duration = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0

        var aspectRatio: CGFloat = 16.0 / 9.0
        if let tracks = try? await asset.loadTracks(withMediaType: .video), let track = tracks.first {
            let natural = (try? await track.load(.naturalSize)) ?? .zero
            let transform = (try? await track.load(.preferredTransform)) ?? .identity
            let oriented = natural.applying(transform)
            let w = abs(oriented.width)
            let h = abs(oriented.height)
            if w > 0, h > 0 {
                aspectRatio = max(0.35, min(3.0, w / h))
            }
        }

        var poster: CGImage?
        if isPlayable {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1120, height: 840)
            let sampleTime = CMTime(seconds: min(0.15, max(0, duration * 0.05)), preferredTimescale: 600)
            if let sampled = try? await generator.image(at: sampleTime).image {
                poster = sampled
            } else if let firstFrame = try? await generator.image(at: .zero).image {
                poster = firstFrame
            }
        }

        return SwftVideoAsset(
            localURL: url,
            poster: poster,
            aspectRatio: aspectRatio,
            duration: duration.isFinite ? max(0, duration) : 0,
            isPlayable: isPlayable
        )
    }
}
