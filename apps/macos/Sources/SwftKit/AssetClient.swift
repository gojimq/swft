import Foundation

// MARK: - RPC Method Tags

public extension RPCMethod {
    static let assetsCreateUrl = "assets.createUrl"
    static let attachmentsCreateUploadUrl = "attachments.createUploadUrl"
    static let attachmentsDelete = "attachments.delete"
}

// MARK: - Asset Resources (`packages/contracts/src/assets.ts`)

/// The subset of the server's `AssetResource` union this client mints signed URLs for.
public enum AssetResource: Codable, Sendable, Hashable {
    case attachment(attachmentId: String, fileName: String? = nil, mimeType: String? = nil, disposition: String? = "inline")
    case mediaFile(threadId: String, path: String)
    case workspaceFile(threadId: String, path: String)
    case draftWorkspaceFile(cwd: String, path: String)
    case toolOutputImage(threadId: String, itemId: String, index: Int)

    private enum CodingKeys: String, CodingKey {
        case _tag, attachmentId, fileName, mimeType, disposition, threadId, cwd, path, itemId, index
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .attachment(let attachmentId, let fileName, let mimeType, let disposition):
            try c.encode("attachment", forKey: ._tag)
            try c.encode(attachmentId, forKey: .attachmentId)
            try c.encodeIfPresent(fileName, forKey: .fileName)
            try c.encodeIfPresent(mimeType, forKey: .mimeType)
            try c.encodeIfPresent(disposition, forKey: .disposition)
        case .mediaFile(let threadId, let path):
            try c.encode("media-file", forKey: ._tag)
            try c.encode(threadId, forKey: .threadId)
            try c.encode(path, forKey: .path)
        case .workspaceFile(let threadId, let path):
            try c.encode("workspace-file", forKey: ._tag)
            try c.encode(threadId, forKey: .threadId)
            try c.encode(path, forKey: .path)
        case .draftWorkspaceFile(let cwd, let path):
            try c.encode("draft-workspace-file", forKey: ._tag)
            try c.encode(cwd, forKey: .cwd)
            try c.encode(path, forKey: .path)
        case .toolOutputImage(let threadId, let itemId, let index):
            try c.encode("tool-output-image", forKey: ._tag)
            try c.encode(threadId, forKey: .threadId)
            try c.encode(itemId, forKey: .itemId)
            try c.encode(index, forKey: .index)
        }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try c.decode(String.self, forKey: ._tag)
        switch tag {
        case "attachment":
            self = .attachment(
                attachmentId: try c.decode(String.self, forKey: .attachmentId),
                fileName: try c.decodeIfPresent(String.self, forKey: .fileName),
                mimeType: try c.decodeIfPresent(String.self, forKey: .mimeType),
                disposition: try c.decodeIfPresent(String.self, forKey: .disposition)
            )
        case "media-file":
            self = .mediaFile(threadId: try c.decode(String.self, forKey: .threadId), path: try c.decode(String.self, forKey: .path))
        case "workspace-file":
            self = .workspaceFile(threadId: try c.decode(String.self, forKey: .threadId), path: try c.decode(String.self, forKey: .path))
        case "draft-workspace-file":
            self = .draftWorkspaceFile(cwd: try c.decode(String.self, forKey: .cwd), path: try c.decode(String.self, forKey: .path))
        case "tool-output-image":
            self = .toolOutputImage(
                threadId: try c.decode(String.self, forKey: .threadId),
                itemId: try c.decode(String.self, forKey: .itemId),
                index: try c.decode(Int.self, forKey: .index)
            )
        default:
            throw DecodingError.dataCorruptedError(forKey: ._tag, in: c, debugDescription: "Unsupported asset resource \(tag)")
        }
    }
}

public struct AssetCreateUrlInput: Codable, Sendable, Equatable {
    public let resource: AssetResource
    public init(resource: AssetResource) { self.resource = resource }
}

public struct AssetImageDimensions: Codable, Sendable, Equatable {
    public let width: Int
    public let height: Int
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct AssetCreateUrlResult: Codable, Sendable, Equatable {
    public let relativeUrl: String
    public let expiresAt: Double
    public let sourcePath: String?
    public let imageDimensions: AssetImageDimensions?
    public let fileRevision: String?

    public init(relativeUrl: String, expiresAt: Double, sourcePath: String? = nil, imageDimensions: AssetImageDimensions? = nil, fileRevision: String? = nil) {
        self.relativeUrl = relativeUrl
        self.expiresAt = expiresAt
        self.sourcePath = sourcePath
        self.imageDimensions = imageDimensions
        self.fileRevision = fileRevision
    }
}

// MARK: - Attachment Uploads

public enum AttachmentUploadKind: String, Codable, Sendable, Hashable {
    case image
    case file
}

public struct AttachmentCreateUploadUrlInput: Codable, Sendable, Equatable {
    public let type: AttachmentUploadKind
    public let name: String
    public let mimeType: String
    public let sizeBytes: Int

    public init(type: AttachmentUploadKind, name: String, mimeType: String, sizeBytes: Int) {
        self.type = type
        self.name = name
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
    }
}

public struct AttachmentCreateUploadUrlResult: Codable, Sendable, Equatable {
    public let attachmentId: String
    public let relativeUrl: String
    public let expiresAt: Double

    public init(attachmentId: String, relativeUrl: String, expiresAt: Double) {
        self.attachmentId = attachmentId
        self.relativeUrl = relativeUrl
        self.expiresAt = expiresAt
    }
}

public struct AttachmentDeleteInput: Codable, Sendable, Equatable {
    public let attachmentId: String
    public init(attachmentId: String) { self.attachmentId = attachmentId }
}

/// Server-side send limits (`chatAttachment.ts`), checked before anything is uploaded.
public enum AttachmentLimits {
    public static let maxAttachments = 100
    public static let maxImageBytes = 10 * 1024 * 1024
    public static let maxTotalImageBytes = 80 * 1024 * 1024
    public static let maxFileBytes = 50 * 1024 * 1024
    public static let supportedImageMimeTypes: Set<String> = ["image/gif", "image/jpeg", "image/png", "image/webp"]

    public static func isSupportedImageMimeType(_ mimeType: String) -> Bool {
        supportedImageMimeTypes.contains(mimeType.lowercased())
    }

    /// Why adding `candidate` to `existing` would break a limit, or nil when it fits.
    public static func rejection(
        adding candidate: (type: AttachmentUploadKind, name: String, sizeBytes: Int),
        to existing: [(type: AttachmentUploadKind, sizeBytes: Int)]
    ) -> String? {
        if existing.count >= maxAttachments {
            return "You can attach up to \(maxAttachments) files per message."
        }
        if candidate.sizeBytes < 1 {
            return "“\(candidate.name)” is empty."
        }
        switch candidate.type {
        case .image:
            if candidate.sizeBytes > maxImageBytes {
                return "“\(candidate.name)” is larger than \(maxImageBytes / 1024 / 1024) MB."
            }
            let imageBytes = existing.filter { $0.type == .image }.reduce(0) { $0 + $1.sizeBytes }
            if imageBytes + candidate.sizeBytes > maxTotalImageBytes {
                return "Images in one message can total at most \(maxTotalImageBytes / 1024 / 1024) MB."
            }
        case .file:
            if candidate.sizeBytes > maxFileBytes {
                return "“\(candidate.name)” is larger than \(maxFileBytes / 1024 / 1024) MB."
            }
        }
        return nil
    }
}

public enum AssetTransferError: LocalizedError, Sendable, Equatable {
    case invalidURL(String)
    case httpStatus(Int, String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let value): "Invalid asset URL: \(value)"
        case .httpStatus(let status, let detail): detail.isEmpty ? "Upload rejected (\(status))." : "Upload rejected (\(status)): \(detail)"
        }
    }
}

// MARK: - ServerConnection Asset RPCs

public extension ServerConnection {
    func createAssetURL(_ resource: AssetResource) async throws -> AssetCreateUrlResult {
        try await call(tag: RPCMethod.assetsCreateUrl, payload: AssetCreateUrlInput(resource: resource))
    }

    func createAttachmentUploadURL(_ input: AttachmentCreateUploadUrlInput) async throws -> AttachmentCreateUploadUrlResult {
        try await call(tag: RPCMethod.attachmentsCreateUploadUrl, payload: input)
    }

    func deleteAttachment(_ attachmentId: String) async throws {
        try await callVoid(tag: RPCMethod.attachmentsDelete, payload: AttachmentDeleteInput(attachmentId: attachmentId))
    }

    /// Resolves a server-relative URL (`/api/...`) against this environment's HTTP origin (local, LAN or tunnel).
    nonisolated func resolveServerURL(_ relativeUrl: String) throws -> URL {
        guard let url = AssetURLResolver.resolve(relativeUrl, against: httpBaseURL) else {
            throw AssetTransferError.invalidURL(relativeUrl)
        }
        return url
    }

    /// POSTs raw bytes to a signed upload URL. The signature lives in the path, so no bearer token is sent.
    func uploadAttachmentBytes(_ data: Data, relativeUrl: String, mimeType: String) async throws {
        var request = URLRequest(url: try resolveServerURL(relativeUrl))
        request.httpMethod = "POST"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(data.count), forHTTPHeaderField: "Content-Length")
        request.timeoutInterval = 120
        let (body, response) = try await session.upload(for: request, from: data)
        try Self.ensureSuccess(response, body: body)
    }

    /// GETs the bytes behind a signed asset URL.
    func fetchAssetData(relativeUrl: String) async throws -> Data {
        var request = URLRequest(url: try resolveServerURL(relativeUrl))
        request.timeoutInterval = 60
        let (body, response) = try await session.data(for: request)
        try Self.ensureSuccess(response, body: body)
        return body
    }

    /// Mints a signed URL for `resource` and downloads it.
    func fetchAsset(_ resource: AssetResource) async throws -> Data {
        let minted = try await createAssetURL(resource)
        return try await fetchAssetData(relativeUrl: minted.relativeUrl)
    }

    /// Streams the asset behind a signed relative URL directly to a temporary file on disk with `preferredExtension`.
    func downloadAssetDataToTemporaryFile(relativeUrl: String, preferredExtension: String? = nil) async throws -> URL {
        var request = URLRequest(url: try resolveServerURL(relativeUrl))
        request.timeoutInterval = 180
        let (tempURL, response) = try await session.download(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let previewData = (try? Data(contentsOf: tempURL, options: .mappedIfSafe).prefix(300)) ?? Data()
            try? FileManager.default.removeItem(at: tempURL)
            try Self.ensureSuccess(response, body: Data(previewData))
        }
        return try Self.moveDownloadedTempFile(tempURL, preferredExtension: preferredExtension)
    }

    /// Mints a signed URL for `resource` and streams it directly to a temporary file on disk.
    func downloadAssetToTemporaryFile(_ resource: AssetResource, preferredExtension: String? = nil) async throws -> URL {
        let minted = try await createAssetURL(resource)
        return try await downloadAssetDataToTemporaryFile(relativeUrl: minted.relativeUrl, preferredExtension: preferredExtension)
    }

    private static func moveDownloadedTempFile(_ tempURL: URL, preferredExtension: String?) throws -> URL {
        let ext = preferredExtension?
            .trimmingCharacters(in: CharacterSet(charactersIn: ". \t\r\n"))
            .lowercased()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swft-asset-downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let filename = (ext?.isEmpty == false) ? "\(UUID().uuidString.lowercased()).\(ext!)" : UUID().uuidString.lowercased()
        let destination = dir.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }

    private static func ensureSuccess(_ response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let detail = String(data: body.prefix(300), encoding: .utf8) ?? ""
            throw AssetTransferError.httpStatus(http.statusCode, detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

public enum AssetURLResolver {
    /// Joins a root-relative path onto the server origin, keeping any base path prefix (e.g. a reverse proxy).
    public static func resolve(_ relativeUrl: String, against base: URL) -> URL? {
        guard relativeUrl.hasPrefix("/") else { return URL(string: relativeUrl) }
        var root = base.absoluteString
        while root.hasSuffix("/") { root.removeLast() }
        return URL(string: root + relativeUrl)
    }
}

// MARK: - Media Kind & Image Source Classification

/// Media type inferred from a markdown media path, URL, or data URI (matching `packages/shared/src/mediaPreview.ts`).
public enum MediaSourceKind: Equatable, Sendable {
    case image
    case video
    case audio
}

/// Where a media item a message points at (markdown `![](target)`, a viewed path) is fetched from.
public enum ImageSourceLocation: Equatable, Sendable {
    /// `http(s)://` — fetched directly.
    case remote(URL)
    /// `data:<mime>;base64,...` — decoded in place.
    case inlineData(Data, mimeType: String)
    /// `/api/assets/...` or another server route — resolved against the thread's environment origin.
    case serverRelative(String)
    /// A host file path (absolute, `~/`, `file://` or workspace-relative) — minted as a `media-file` asset.
    case mediaFile(path: String)
    case unsupported

    private static let videoExtensions: Set<String> = ["mp4", "m4v", "mov", "webm", "mkv", "avi", "ogv"]
    private static let audioExtensions: Set<String> = ["mp3", "wav", "m4a", "aac", "flac", "ogg", "oga", "opus", "aiff", "weba"]
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "avif", "bmp", "ico", "svg", "tif", "tiff"]

    /// Lowercase file extension extracted from a path, `file://`, or `http(s)://` URL (stripping query/fragment).
    public static func fileExtension(for rawSource: String) -> String? {
        var source = rawSource.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.hasPrefix("<"), source.hasSuffix(">"), source.count >= 2 {
            source = String(source.dropFirst().dropLast())
        }
        let lower = source.lowercased()
        if lower.hasPrefix("data:") {
            guard let comma = source.firstIndex(of: ",") else { return nil }
            let header = source[source.index(source.startIndex, offsetBy: 5)..<comma].lowercased()
            let mime = header.split(separator: ";").first.map(String.init) ?? ""
            switch mime {
            case "video/mp4": return "mp4"
            case "video/quicktime": return "mov"
            case "video/webm": return "webm"
            default: return nil
            }
        }
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

    public static func mediaKind(for rawSource: String) -> MediaSourceKind? {
        var trimmed = rawSource.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("<"), trimmed.hasSuffix(">"), trimmed.count >= 2 {
            trimmed = String(trimmed.dropFirst().dropLast())
        }
        if trimmed.hasPrefix("data:video/") { return .video }
        if trimmed.hasPrefix("data:audio/") { return .audio }
        if trimmed.hasPrefix("data:image/") { return .image }
        guard let ext = fileExtension(for: rawSource) else { return nil }
        if videoExtensions.contains(ext) { return .video }
        if audioExtensions.contains(ext) { return .audio }
        if imageExtensions.contains(ext) { return .image }
        return nil
    }

    public static func classify(_ rawSource: String) -> ImageSourceLocation {
        var source = rawSource.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.hasPrefix("<"), source.hasSuffix(">"), source.count >= 2 {
            source = String(source.dropFirst().dropLast())
        }
        guard !source.isEmpty else { return .unsupported }
        let lower = source.lowercased()

        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return URL(string: source).map(ImageSourceLocation.remote) ?? .unsupported
        }
        if lower.hasPrefix("data:") {
            return decodeDataURI(source) ?? .unsupported
        }
        if lower.hasPrefix("file://") {
            guard let url = URL(string: source), url.isFileURL else { return .unsupported }
            let path = url.path(percentEncoded: false)
            return path.isEmpty ? .unsupported : .mediaFile(path: path)
        }
        if source.hasPrefix("/api/") {
            return .serverRelative(source)
        }
        // Any other scheme (`mailto:`, `javascript:`, …) is not an image location.
        if let colon = source.firstIndex(of: ":"), !source.hasPrefix("/"), !source.hasPrefix("~"),
           source[..<colon].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }),
           source.distance(from: source.startIndex, to: colon) > 1
        {
            return .unsupported
        }
        let path = source.removingPercentEncoding ?? source
        return .mediaFile(path: path)
    }

    private static func decodeDataURI(_ source: String) -> ImageSourceLocation? {
        guard let comma = source.firstIndex(of: ",") else { return nil }
        let header = source[source.index(source.startIndex, offsetBy: 5)..<comma].lowercased()
        let parts = header.split(separator: ";").map(String.init)
        guard let mime = parts.first,
              (mime.hasPrefix("image/") || mime.hasPrefix("video/") || mime.hasPrefix("audio/")),
              parts.contains("base64")
        else { return nil }
        let payload = String(source[source.index(after: comma)...])
        guard let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters), !data.isEmpty else { return nil }
        return .inlineData(data, mimeType: mime)
    }
}
