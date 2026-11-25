import Foundation
import Testing
@testable import SwftKit

@Suite("Asset & attachment wire contracts")
struct AssetClientTests {
    private func json(_ value: some Encodable) throws -> [String: Any] {
        let data = try SwftJSON.makeEncoder().encode(value)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func encodesAttachmentResourceWithInlineDisposition() throws {
        let input = AssetCreateUrlInput(resource: .attachment(attachmentId: "pending-abc", fileName: "shot.png", mimeType: "image/png"))
        let resource = try #require(try json(input)["resource"] as? [String: Any])
        #expect(resource["_tag"] as? String == "attachment")
        #expect(resource["attachmentId"] as? String == "pending-abc")
        #expect(resource["fileName"] as? String == "shot.png")
        #expect(resource["mimeType"] as? String == "image/png")
        #expect(resource["disposition"] as? String == "inline")
    }

    @Test func omitsAbsentOptionalAttachmentKeys() throws {
        let resource = try json(AssetResource.attachment(attachmentId: "a1", fileName: nil, mimeType: nil, disposition: nil))
        #expect(Set(resource.keys) == ["_tag", "attachmentId"])
    }

    @Test func encodesMediaFileAndToolOutputImage() throws {
        let media = try json(AssetResource.mediaFile(threadId: "thr-1", path: "/work/my shot.png"))
        #expect(media["_tag"] as? String == "media-file")
        #expect(media["threadId"] as? String == "thr-1")
        #expect(media["path"] as? String == "/work/my shot.png")

        let tool = try json(AssetResource.toolOutputImage(threadId: "thr-1", itemId: "item-9", index: 2))
        #expect(tool["_tag"] as? String == "tool-output-image")
        #expect(tool["itemId"] as? String == "item-9")
        #expect(tool["index"] as? Int == 2)
    }

    @Test func resourcesRoundTrip() throws {
        let resources: [AssetResource] = [
            .attachment(attachmentId: "a", fileName: "f.png", mimeType: "image/png", disposition: "inline"),
            .mediaFile(threadId: "t", path: "screenshots/out.png"),
            .toolOutputImage(threadId: "t", itemId: "i", index: 0),
        ]
        for resource in resources {
            let data = try SwftJSON.makeEncoder().encode(resource)
            #expect(try SwftJSON.makeDecoder().decode(AssetResource.self, from: data) == resource)
        }
    }

    @Test func encodesUploadInputs() throws {
        let image = try json(AttachmentCreateUploadUrlInput(type: .image, name: "shot.png", mimeType: "image/png", sizeBytes: 1234))
        #expect(image["type"] as? String == "image")
        #expect(image["name"] as? String == "shot.png")
        #expect(image["mimeType"] as? String == "image/png")
        #expect(image["sizeBytes"] as? Int == 1234)

        let file = try json(AttachmentCreateUploadUrlInput(type: .file, name: "notes.md", mimeType: "text/markdown", sizeBytes: 9))
        #expect(file["type"] as? String == "file")

        let delete = try json(AttachmentDeleteInput(attachmentId: "pending-1"))
        #expect(delete["attachmentId"] as? String == "pending-1")
    }

    @Test func decodesUploadAndAssetResults() throws {
        let upload = try SwftJSON.makeDecoder().decode(AttachmentCreateUploadUrlResult.self, from: Data("""
        {"attachmentId":"pending-x1","relativeUrl":"/api/attachments/upload/eyJ2.sig","expiresAt":1800000600000}
        """.utf8))
        #expect(upload.attachmentId == "pending-x1")
        #expect(upload.relativeUrl == "/api/attachments/upload/eyJ2.sig")
        #expect(upload.expiresAt == 1_800_000_600_000)

        let full = try SwftJSON.makeDecoder().decode(AssetCreateUrlResult.self, from: Data("""
        {"relativeUrl":"/api/assets/tok/shot.png","expiresAt":1.5,"sourcePath":"/work/shot.png","imageDimensions":{"width":1440,"height":900},"fileRevision":"r1"}
        """.utf8))
        #expect(full.imageDimensions == AssetImageDimensions(width: 1440, height: 900))
        #expect(full.sourcePath == "/work/shot.png")
        #expect(full.fileRevision == "r1")

        let minimal = try SwftJSON.makeDecoder().decode(AssetCreateUrlResult.self, from: Data(#"{"relativeUrl":"/api/assets/t/a.png","expiresAt":2}"#.utf8))
        #expect(minimal.imageDimensions == nil)
        #expect(minimal.sourcePath == nil)
    }

    @Test func resolvesRelativeURLsAgainstTheEnvironmentOrigin() throws {
        let local = try #require(URL(string: "http://127.0.0.1:3773"))
        #expect(AssetURLResolver.resolve("/api/assets/t/a.png", against: local)?.absoluteString == "http://127.0.0.1:3773/api/assets/t/a.png")
        let tunnel = try #require(URL(string: "https://box.example.com/proxy/"))
        #expect(AssetURLResolver.resolve("/api/attachments/upload/p.s", against: tunnel)?.absoluteString == "https://box.example.com/proxy/api/attachments/upload/p.s")
    }

    @Test func classifiesImageSources() {
        #expect(ImageSourceLocation.classify("https://example.com/a.png") == .remote(URL(string: "https://example.com/a.png")!))
        #expect(ImageSourceLocation.classify("/api/assets/tok/a.png") == .serverRelative("/api/assets/tok/a.png"))
        #expect(ImageSourceLocation.classify("/Users/me/shot.png") == .mediaFile(path: "/Users/me/shot.png"))
        #expect(ImageSourceLocation.classify("file:///Users/me/my%20shot.png") == .mediaFile(path: "/Users/me/my shot.png"))
        #expect(ImageSourceLocation.classify("~/Desktop/a.png") == .mediaFile(path: "~/Desktop/a.png"))
        #expect(ImageSourceLocation.classify("screenshots/out.png") == .mediaFile(path: "screenshots/out.png"))
        #expect(ImageSourceLocation.classify("C:\\shots\\a.png") == .mediaFile(path: "C:\\shots\\a.png"))
        #expect(ImageSourceLocation.classify("javascript:alert(1)") == .unsupported)
        #expect(ImageSourceLocation.classify("") == .unsupported)

        let png = Data([0x89, 0x50, 0x4E, 0x47])
        #expect(ImageSourceLocation.classify("data:image/png;base64,\(png.base64EncodedString())") == .inlineData(png, mimeType: "image/png"))
        #expect(ImageSourceLocation.classify("data:text/plain;base64,aGk=") == .unsupported)
    }

    @Test func enforcesAttachmentLimits() {
        let tenMiB = AttachmentLimits.maxImageBytes
        #expect(AttachmentLimits.rejection(adding: (.image, "ok.png", tenMiB), to: []) == nil)
        #expect(AttachmentLimits.rejection(adding: (.image, "big.png", tenMiB + 1), to: []) != nil)
        #expect(AttachmentLimits.rejection(adding: (.file, "big.zip", AttachmentLimits.maxFileBytes + 1), to: []) != nil)
        #expect(AttachmentLimits.rejection(adding: (.file, "empty.txt", 0), to: []) != nil)
        let eightImages = Array(repeating: (type: AttachmentUploadKind.image, sizeBytes: tenMiB), count: 8)
        #expect(AttachmentLimits.rejection(adding: (.image, "ninth.png", 1), to: eightImages) != nil)
        #expect(AttachmentLimits.rejection(adding: (.file, "file.txt", 1), to: eightImages) == nil)
        let full = Array(repeating: (type: AttachmentUploadKind.file, sizeBytes: 1), count: AttachmentLimits.maxAttachments)
        #expect(AttachmentLimits.rejection(adding: (.file, "one-more.txt", 1), to: full) != nil)
        #expect(AttachmentLimits.isSupportedImageMimeType("IMAGE/PNG"))
        #expect(!AttachmentLimits.isSupportedImageMimeType("image/heic"))
    }
}
