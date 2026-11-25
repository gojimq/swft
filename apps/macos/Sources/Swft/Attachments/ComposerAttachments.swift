import AppKit
import Foundation
import ImageIO
import Observation
import SwftDesign
import SwftKit
import UniformTypeIdentifiers

/// Bytes ready to stage: already typed, sized and (for images) in a format the server accepts.
struct AttachmentPayload: Sendable {
    var kind: AttachmentUploadKind
    var name: String
    var mimeType: String
    var data: Data
    /// Decoded, downsampled preview for images; shared by the tray, the flight and the transcript.
    var preview: CGImage?
}

/// Something the user attached: a file on disk, or raw image bytes (a pasted screenshot, a dragged image).
enum AttachmentSource: Sendable {
    case file(URL)
    case imageData(Data, suggestedName: String)
}

enum AttachmentPreparationError: LocalizedError {
    case unreadable(String)
    case undecodableImage(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let name): "Couldn’t read “\(name)”."
        case .undecodableImage(let name): "Couldn’t convert “\(name)” to a supported image."
        }
    }
}

/// Turns attached sources into upload payloads. Images in a format the server rejects (HEIC, TIFF, BMP — the macOS
/// clipboard's and Finder's usual ones) are transcoded to PNG or JPEG, and downscaled if still over the size limit.
enum AttachmentPreparer {
    static func prepare(_ source: AttachmentSource) async throws -> AttachmentPayload {
        try await Task.detached(priority: .userInitiated) {
            switch source {
            case .file(let url):
                let name = url.lastPathComponent
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                    throw AttachmentPreparationError.unreadable(name)
                }
                let type = UTType(filenameExtension: url.pathExtension.lowercased())
                if let type, type.conforms(to: .image), !type.conforms(to: .svg) {
                    return try prepareImage(data: data, name: name, declaredMime: type.preferredMIMEType)
                }
                return AttachmentPayload(
                    kind: .file,
                    name: name,
                    mimeType: type?.preferredMIMEType ?? "application/octet-stream",
                    data: data,
                    preview: nil
                )
            case .imageData(let data, let suggestedName):
                return try prepareImage(data: data, name: suggestedName, declaredMime: sniffImageMime(data))
            }
        }.value
    }

    static func prepareImage(data: Data, name: String, declaredMime: String?) throws -> AttachmentPayload {
        let mime = declaredMime?.lowercased() ?? sniffImageMime(data)
        if let mime, AttachmentLimits.isSupportedImageMimeType(mime), data.count <= AttachmentLimits.maxImageBytes {
            return AttachmentPayload(kind: .image, name: name, mimeType: mime, data: data, preview: SwftImageCache.decode(data))
        }
        guard let transcoded = transcode(data) else { throw AttachmentPreparationError.undecodableImage(name) }
        let base = (name as NSString).deletingPathExtension
        let ext = transcoded.mimeType == "image/png" ? "png" : "jpg"
        return AttachmentPayload(
            kind: .image,
            name: "\(base.isEmpty ? "Image" : base).\(ext)",
            mimeType: transcoded.mimeType,
            data: transcoded.data,
            preview: SwftImageCache.decode(transcoded.data)
        )
    }

    /// PNG when it fits (keeps screenshots crisp and alpha intact), otherwise JPEG, shrinking until under the limit.
    static func transcode(_ data: Data, limit: Int = AttachmentLimits.maxImageBytes) -> (data: Data, mimeType: String)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 8192,
        ]
        guard let full = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        if let png = encode(full, type: .png), png.count <= limit { return (png, "image/png") }
        var image = full
        for _ in 0..<5 {
            if let jpeg = encode(image, type: .jpeg, quality: 0.86), jpeg.count <= limit { return (jpeg, "image/jpeg") }
            guard let smaller = downscale(image, by: 0.7) else { return nil }
            image = smaller
        }
        return nil
    }

    static func sniffImageMime(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(12))
        guard bytes.count >= 4 else { return nil }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "image/gif" }
        if bytes.count >= 12, bytes.starts(with: [0x52, 0x49, 0x46, 0x46]), Array(bytes[8..<12]) == [0x57, 0x45, 0x42, 0x50] { return "image/webp" }
        if bytes.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) || bytes.starts(with: [0x49, 0x49, 0x2A, 0x00]) { return "image/tiff" }
        return nil
    }

    private static func encode(_ image: CGImage, type: UTType, quality: Double? = nil) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else { return nil }
        let properties: [CFString: Any] = quality.map { [kCGImageDestinationLossyCompressionQuality: $0] } ?? [:]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func downscale(_ image: CGImage, by factor: CGFloat) -> CGImage? {
        let width = max(1, Int(CGFloat(image.width) * factor))
        let height = max(1, Int(CGFloat(image.height) * factor))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    // MARK: Pasteboard & drops

    /// Files or images on a pasteboard, or nil when it holds nothing to attach (plain text pastes into the field).
    @MainActor
    static func sources(from pasteboard: NSPasteboard) -> [AttachmentSource]? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty {
            return urls.map(AttachmentSource.file)
        }
        // A rich-text copy can carry an image rendition too; the user meant the text then.
        if pasteboard.string(forType: .string) != nil { return nil }
        for type in [NSPasteboard.PasteboardType.png, .tiff, NSPasteboard.PasteboardType("public.jpeg"), NSPasteboard.PasteboardType("public.heic")] {
            if let data = pasteboard.data(forType: type) {
                return [.imageData(data, suggestedName: "Pasted image.png")]
            }
        }
        return nil
    }

    /// Resolves dropped item providers to sources, delivering them on the main actor.
    @MainActor
    static func loadSources(from providers: [NSItemProvider], completion: @escaping @MainActor ([AttachmentSource]) -> Void) -> Bool {
        let relevant = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) || $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }
        guard !relevant.isEmpty else { return false }
        let group = DispatchGroup()
        let collected = SourceCollector(count: relevant.count)
        for (index, provider) in relevant.enumerated() {
            group.enter()
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { collected.set(.file(url), at: index) }
                    group.leave()
                }
            } else {
                _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    if let data { collected.set(.imageData(data, suggestedName: "Dropped image.png"), at: index) }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            MainActor.assumeIsolated { completion(collected.values) }
        }
        return true
    }
}

/// Thread-safe slot array for drop results arriving on arbitrary queues.
private final class SourceCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var slots: [AttachmentSource?]

    init(count: Int) { slots = Array(repeating: nil, count: count) }

    func set(_ source: AttachmentSource, at index: Int) {
        lock.withLock { slots[index] = source }
    }

    var values: [AttachmentSource] { lock.withLock { slots.compactMap { $0 } } }
}

/// The composer's staged attachments. Each upload starts the moment it is attached (mint a signed slot, POST the bytes),
/// so by the time the user sends, the attachment is usually ready and the message flies on frame 0.
@MainActor
@Observable
final class ComposerAttachments {
    struct Staged: Identifiable, Equatable {
        let id: String
        var kind: TranscriptAttachment.Kind
        var name: String
        var mimeType: String
        var sizeBytes: Int
        var previewKey: String?
        var serverID: String?
        var status: ComposerAttachmentItem.Status
        /// The environment the bytes went to; a send elsewhere cannot reference them.
        var connectionID: ObjectIdentifier?
    }

    private(set) var staged: [Staged] = []
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var connections: [String: ServerConnection] = [:]
    @ObservationIgnored var onError: ((String) -> Void)?

    var items: [ComposerAttachmentItem] {
        staged.map {
            ComposerAttachmentItem(id: $0.id, kind: $0.kind, name: $0.name, mimeType: $0.mimeType, sizeBytes: $0.sizeBytes, previewKey: $0.previewKey, status: $0.status)
        }
    }

    var isEmpty: Bool { staged.isEmpty }
    var isUploading: Bool { staged.contains { $0.status == .uploading } }

    /// Uploaded attachments, as the transcript and the dispatch reference them (by server id).
    var ready: [TranscriptAttachment] {
        staged.compactMap { item in
            guard item.status == .ready, let serverID = item.serverID else { return nil }
            return TranscriptAttachment(id: serverID, kind: item.kind, name: item.name, mimeType: item.mimeType, sizeBytes: item.sizeBytes)
        }
    }

    func readyAttachments(for connection: ServerConnection?) -> [TranscriptAttachment]? {
        let target = connection.map(ObjectIdentifier.init)
        let readyItems = staged.filter { $0.status == .ready }
        guard readyItems.allSatisfy({ $0.connectionID == target }) else { return nil }
        return ready
    }

    /// Prepares and stages each source, then uploads it to `connection` (nil = mock: ready at once, nothing sent).
    func add(_ sources: [AttachmentSource], connection: ServerConnection?) {
        for source in sources {
            Task { await self.stage(source, connection: connection) }
        }
    }

    func stage(_ source: AttachmentSource, connection: ServerConnection?) async {
        let payload: AttachmentPayload
        do {
            payload = try await AttachmentPreparer.prepare(source)
        } catch {
            onError?(error.localizedDescription)
            return
        }
        let existing = staged.filter { if case .failed = $0.status { false } else { true } }.map { (type: $0.kind == .image ? AttachmentUploadKind.image : .file, sizeBytes: $0.sizeBytes) }
        if let rejection = AttachmentLimits.rejection(adding: (payload.kind, payload.name, payload.data.count), to: existing) {
            onError?(rejection)
            return
        }

        let localID = "local-\(UUID().uuidString.lowercased())"
        let previewKey = payload.preview.map { image in
            let key = "composer:\(localID)"
            SwftImageCache.shared.store(image, for: key, pinned: true)
            return key
        }
        staged.append(Staged(
            id: localID,
            kind: payload.kind == .image ? .image : .file,
            name: payload.name,
            mimeType: payload.mimeType,
            sizeBytes: payload.data.count,
            previewKey: previewKey,
            serverID: nil,
            status: .uploading,
            connectionID: connection.map(ObjectIdentifier.init)
        ))

        guard let connection else {
            let mockID = "mock-\(UUID().uuidString.lowercased())"
            adoptServerID(mockID, for: localID, preview: payload.preview)
            update(localID) { $0.status = .ready }
            return
        }
        connections[localID] = connection
        tasks[localID] = Task { await self.upload(payload, localID: localID, connection: connection) }
    }

    private func upload(_ payload: AttachmentPayload, localID: String, connection: ServerConnection) async {
        do {
            let minted = try await connection.createAttachmentUploadURL(AttachmentCreateUploadUrlInput(
                type: payload.kind,
                name: payload.name,
                mimeType: payload.mimeType,
                sizeBytes: payload.data.count
            ))
            guard !Task.isCancelled, contains(localID) else {
                Task { try? await connection.deleteAttachment(minted.attachmentId) }
                return
            }
            adoptServerID(minted.attachmentId, for: localID, preview: payload.preview)
            try await connection.uploadAttachmentBytes(payload.data, relativeUrl: minted.relativeUrl, mimeType: payload.mimeType)
            guard !Task.isCancelled else { return }
            update(localID) { $0.status = .ready }
        } catch {
            guard !Task.isCancelled else { return }
            update(localID) { $0.status = .failed(Self.uploadFailureMessage(error)) }
        }
        tasks.removeValue(forKey: localID)
    }

    private func adoptServerID(_ serverID: String, for localID: String, preview: CGImage?) {
        // Registered under the server id now, so the sent bubble and its flight find the same pixels.
        if let preview { SwftImageCache.shared.store(preview, for: SwftImageReference.attachmentKey(serverID), pinned: true) }
        update(localID) { $0.serverID = serverID }
    }

    func remove(_ localID: String) {
        guard let item = staged.first(where: { $0.id == localID }) else { return }
        tasks.removeValue(forKey: localID)?.cancel()
        staged.removeAll { $0.id == localID }
        if let key = item.previewKey { SwftImageCache.shared.unpin(key) }
        if let serverID = item.serverID {
            SwftImageCache.shared.unpin(SwftImageReference.attachmentKey(serverID))
            if let connection = connections[localID] {
                Task { try? await connection.deleteAttachment(serverID) }
            }
        }
        connections.removeValue(forKey: localID)
    }

    /// Hands the uploaded attachments to a send and clears them from the tray; failed ones stay for the user to remove.
    func takeReady(keepPinned: Bool) -> [TranscriptAttachment] {
        let sent = ready
        let sentIDs = Set(sent.map(\.id))
        for item in staged where item.serverID.map(sentIDs.contains) == true {
            if let key = item.previewKey { SwftImageCache.shared.unpin(key) }
            if !keepPinned, let serverID = item.serverID {
                // Live servers can re-serve the image, so it may now be evicted under memory pressure.
                let key = SwftImageReference.attachmentKey(serverID)
                if let image = SwftImageCache.shared.image(for: key) {
                    SwftImageCache.shared.unpin(key)
                    SwftImageCache.shared.store(image, for: key)
                }
            }
            connections.removeValue(forKey: item.id)
        }
        staged.removeAll { $0.serverID.map(sentIDs.contains) == true }
        return sent
    }

    /// Puts attachments from a failed send back in the tray (their uploads still exist on the server).
    func restore(_ attachments: [TranscriptAttachment], connection: ServerConnection?) {
        let restored = attachments.map { attachment in
            let key = SwftImageReference.attachmentKey(attachment.id)
            let localID = "local-\(UUID().uuidString.lowercased())"
            if let connection { connections[localID] = connection }
            return Staged(
                id: localID,
                kind: attachment.kind,
                name: attachment.name,
                mimeType: attachment.mimeType,
                sizeBytes: attachment.sizeBytes,
                previewKey: SwftImageCache.shared.image(for: key) == nil ? nil : key,
                serverID: attachment.id,
                status: .ready,
                connectionID: connection.map(ObjectIdentifier.init)
            )
        }
        staged.insert(contentsOf: restored, at: 0)
    }

    private func contains(_ localID: String) -> Bool { staged.contains { $0.id == localID } }

    private func update(_ localID: String, _ change: (inout Staged) -> Void) {
        guard let index = staged.firstIndex(where: { $0.id == localID }) else { return }
        change(&staged[index])
    }

    static func uploadFailureMessage(_ error: any Error) -> String {
        if case RPCError.disconnected = error { return "Not connected" }
        if let transfer = error as? AssetTransferError, case .httpStatus(let status, _) = transfer { return "Upload rejected (\(status))" }
        if (error as? URLError)?.code == .timedOut { return "Upload timed out" }
        return "Upload failed"
    }
}
