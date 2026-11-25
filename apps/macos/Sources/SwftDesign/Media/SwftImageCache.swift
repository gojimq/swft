import AppKit
import ImageIO
import SwiftUI

/// What a transcript or composer image points at. The app's `SwftImageLoader` turns a reference into bytes (signed
/// asset URL, direct fetch, data URI); design views only ever see references and decoded images.
public enum SwftImageReference: Hashable, Sendable {
    /// A chat attachment by its server id (user uploads and agent attachments).
    case attachment(id: String, name: String?, mimeType: String?)
    /// A message's image target: `https://…`, `data:image/…`, `/api/assets/…`, or a host/workspace path.
    case source(String)

    /// Attachments and self-contained sources are global; paths are only meaningful inside the thread (`scope`).
    public func cacheKey(scope: String) -> String {
        switch self {
        case .attachment(let id, _, _):
            return Self.attachmentKey(id)
        case .source(let source):
            let lower = source.lowercased()
            if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("data:") {
                return "source:\(source)"
            }
            return "source:\(scope):\(source)"
        }
    }

    public static func attachmentKey(_ id: String) -> String { "attachment:\(id)" }
}

/// Resolves image references to bytes for the screen it is installed on (bound to that thread's environment).
public struct SwftImageLoader: Sendable {
    public var scope: String
    public var fetch: @Sendable (SwftImageReference) async throws -> Data

    public init(scope: String, fetch: @escaping @Sendable (SwftImageReference) async throws -> Data) {
        self.scope = scope
        self.fetch = fetch
    }

    /// Only images already in `SwftImageCache` render; anything else shows its quiet fallback.
    public static let cacheOnly = SwftImageLoader(scope: "") { _ in throw CocoaError(.fileReadNoSuchFile) }
}

/// A clicked image, shown full size by the screen's lightbox.
public struct SwftImagePreview: Identifiable, Hashable, Sendable {
    public var id: String { cacheKey }
    public let cacheKey: String
    public let reference: SwftImageReference
    public let caption: String

    public init(cacheKey: String, reference: SwftImageReference, caption: String) {
        self.cacheKey = cacheKey
        self.reference = reference
        self.caption = caption
    }
}

public struct SwftImagePreviewAction: Sendable {
    let handler: @MainActor @Sendable (SwftImagePreview) -> Void

    public init(_ handler: @escaping @MainActor @Sendable (SwftImagePreview) -> Void) {
        self.handler = handler
    }

    @MainActor public func callAsFunction(_ preview: SwftImagePreview) { handler(preview) }
}

extension EnvironmentValues {
    @Entry public var swftImageLoader: SwftImageLoader = .cacheOnly
    /// Nil where images are not clickable (the send-flight overlay, the composer).
    @Entry public var swftImagePreviewAction: SwftImagePreviewAction? = nil
}

/// In-memory decoded image cache shared by the composer, the send flight, the transcript and the lightbox, so a sent
/// attachment shows the same pixels in all four with no blank frame. Loads are deduplicated per key.
@MainActor
public final class SwftImageCache {
    public static let shared = SwftImageCache()

    /// Longest decoded edge. Large enough for a crisp full-window lightbox, small enough to keep memory bounded.
    public nonisolated static let maxPixelSize = 2048

    private let cache = NSCache<NSString, CGImage>()
    /// Images this client produced (composer attachments, mock fixtures); never evicted, since nothing can refetch
    /// them before their upload is visible to the server.
    private var pinned: [String: CGImage] = [:]
    private var inflight: [String: Task<CGImage?, Never>] = [:]
    private var failed: Set<String> = []

    public init() {
        cache.totalCostLimit = 384 * 1024 * 1024
    }

    public func image(for key: String) -> CGImage? {
        pinned[key] ?? cache.object(forKey: key as NSString)
    }

    public func hasFailed(_ key: String) -> Bool { failed.contains(key) }

    public func store(_ image: CGImage, for key: String, pinned isPinned: Bool = false) {
        failed.remove(key)
        if isPinned {
            pinned[key] = image
        } else {
            cache.setObject(image, forKey: key as NSString, cost: image.bytesPerRow * image.height)
        }
    }

    public func unpin(_ key: String) {
        pinned.removeValue(forKey: key)
    }

    /// Loads `key` once, sharing the result with every concurrent caller. Returns nil (and remembers the failure until
    /// `retry`) when the bytes cannot be fetched or decoded.
    public func load(_ key: String, fetch: @escaping @Sendable () async throws -> Data) async -> CGImage? {
        if let image = image(for: key) { return image }
        if failed.contains(key) { return nil }
        if let running = inflight[key] { return await running.value }
        let task = Task<CGImage?, Never> {
            guard let data = try? await fetch() else { return nil }
            return await Task.detached(priority: .userInitiated) { Self.decode(data) }.value
        }
        inflight[key] = task
        let image = await task.value
        inflight.removeValue(forKey: key)
        if let image {
            store(image, for: key)
        } else {
            failed.insert(key)
        }
        return image
    }

    public func retry(_ key: String) {
        failed.remove(key)
    }

    /// Decodes and downsamples (EXIF orientation applied) off the main actor.
    public nonisolated static func decode(_ data: Data, maxPixelSize: Int = SwftImageCache.maxPixelSize) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

public enum SwftImagePhase {
    case loading
    case success(CGImage)
    case failure
}

/// Renders an image reference through the environment's loader. The cache is consulted during render, so an image
/// that is already decoded (a just-sent attachment, a revisited thread) is on screen in the very first frame.
public struct SwftCachedImage<Content: View>: View {
    let reference: SwftImageReference
    let content: (SwftImagePhase) -> Content
    @Environment(\.swftImageLoader) private var loader
    @State private var settledKey: String?
    @State private var failedKey: String?

    public init(_ reference: SwftImageReference, @ViewBuilder content: @escaping (SwftImagePhase) -> Content) {
        self.reference = reference
        self.content = content
    }

    public var body: some View {
        let key = reference.cacheKey(scope: loader.scope)
        content(phase(for: key))
            .task(id: key) {
                guard SwftImageCache.shared.image(for: key) == nil else { return }
                let fetch = loader.fetch
                let reference = reference
                let image = await SwftImageCache.shared.load(key) { try await fetch(reference) }
                if image == nil { failedKey = key } else { settledKey = key }
            }
    }

    private func phase(for key: String) -> SwftImagePhase {
        if let image = SwftImageCache.shared.image(for: key) { return .success(image) }
        if failedKey == key || SwftImageCache.shared.hasFailed(key) { return .failure }
        _ = settledKey
        return .loading
    }
}
