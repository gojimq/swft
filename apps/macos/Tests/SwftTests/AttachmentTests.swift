import AppKit
import Foundation
import SwftDesign
import SwftKit
import SwiftUI
import Testing
@testable import Swft

@Suite("Markdown images")
struct MarkdownImageParserTests {
    @Test func standaloneImageBecomesItsOwnBlock() {
        #expect(MarkdownBlockParser.parse("![Shot](/work/shot.png)") == [.image(alt: "Shot", source: "/work/shot.png")])
    }

    @Test func angleBracketPathsKeepTheirSpaces() {
        #expect(MarkdownBlockParser.parse("![Shot](</work/my shot.png>)") == [.image(alt: "Shot", source: "/work/my shot.png")])
    }

    @Test func titlesAreDroppedFromTheSource() {
        #expect(MarkdownBlockParser.parse(#"![Chart](out/chart.png "Width sweep")"#) == [.image(alt: "Chart", source: "out/chart.png")])
        #expect(MarkdownBlockParser.parse("![a](<x y.png> 'T')") == [.image(alt: "a", source: "x y.png")])
    }

    @Test func fencedCodeIsNeverScannedForImages() {
        let markdown = "```md\n![not](an-image)\n```"
        #expect(MarkdownBlockParser.parse(markdown) == [.code(language: "md", source: "![not](an-image)")])
    }

    @Test func inlineCodeSpansAreNotImages() {
        #expect(MarkdownBlockParser.parse("Use `![alt](path)` syntax.") == [.text("Use `![alt](path)` syntax.")])
    }

    @Test func incompleteSyntaxStaysProseWhileStreaming() {
        #expect(MarkdownBlockParser.parse("Here: ![shot](/work/sh") == [.text("Here: ![shot](/work/sh")])
    }

    @Test func mixedProseImageAndCodeKeepTheirOrder() {
        let markdown = """
        Before the fix:

        ![Before](https://example.com/before.png)
        It clips here, see ![After](after.png) for the fix.

        ```swift
        let x = 1
        ```
        - ![Listed](list.png)
        """
        #expect(MarkdownBlockParser.parse(markdown) == [
            .text("Before the fix:"),
            .image(alt: "Before", source: "https://example.com/before.png"),
            .text("It clips here, see"),
            .image(alt: "After", source: "after.png"),
            .text("for the fix."),
            .code(language: "swift", source: "let x = 1"),
            .image(alt: "Listed", source: "list.png"),
        ])
    }

    @Test func nestedBracketsAndParensInTargets() {
        #expect(MarkdownBlockParser.parse("![a [b] c](shots/(1).png)") == [.image(alt: "a [b] c", source: "shots/(1).png")])
    }
}

@Suite("Attachment adapters")
struct AttachmentAdapterTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let shot = ChatAttachment(type: "image", id: "att-shot", name: "shot.png", mimeType: "image/png", sizeBytes: 4096)
    private let log = ChatAttachment(type: "file", id: "att-log", name: "run.log", mimeType: "text/plain", sizeBytes: 512)

    private func item(_ kind: TurnItemKind, id: String = "i1") -> TurnItem {
        TurnItem(id: id, threadId: "thr-1", ordinal: 1, status: "completed", updatedAt: t0, kind: kind)
    }

    private func map(_ kind: TurnItemKind) -> TranscriptItem? {
        SwftAdapters.transcriptItem(from: item(kind), requestsByID: [:], optimisticApprovals: [:])
    }

    @Test func userMessageKeepsTextAndAttachments() {
        let mapped = map(.userMessage(messageId: "m", text: "Look", inputIntent: "turn_start", attachments: [shot, log], createdBy: "user", creationSource: "web"))
        #expect(mapped?.kind == .user("Look", attachments: [
            TranscriptAttachment(id: "att-shot", kind: .image, name: "shot.png", mimeType: "image/png", sizeBytes: 4096),
            TranscriptAttachment(id: "att-log", kind: .file, name: "run.log", mimeType: "text/plain", sizeBytes: 512),
        ]))
    }

    @Test func attachmentOnlyMessageHasNoTextPill() {
        let mapped = map(.userMessage(messageId: "m", text: "  \n", inputIntent: "turn_start", attachments: [shot], createdBy: "user", creationSource: "web"))
        guard case .user(let text, let attachments)? = mapped?.kind else {
            Issue.record("expected a user item")
            return
        }
        #expect(text.isEmpty)
        #expect(attachments.map(\.id) == ["att-shot"])
    }

    @Test func emptyUserMessageIsDropped() {
        #expect(map(.userMessage(messageId: "m", text: "", inputIntent: "turn_start", attachments: [], createdBy: "user", creationSource: "web")) == nil)
    }

    @Test func assistantAttachmentsAndMarkdownImagesRender() {
        let mapped = map(.assistantMessage(messageId: "a", text: "Result:\n![Chart](out/chart.png)", streaming: false, phase: nil, delivery: nil, attachments: [shot]))
        #expect(mapped?.kind == .assistant(blocks: [
            .text("Result:"),
            .image(alt: "Chart", source: "out/chart.png"),
            .attachments([TranscriptAttachment(id: "att-shot", kind: .image, name: "shot.png", mimeType: "image/png", sizeBytes: 4096)]),
        ], streaming: false))
    }

    @Test func assistantAttachmentOnlyMessageIsKept() {
        let mapped = map(.assistantMessage(messageId: "a", text: "", streaming: false, phase: nil, delivery: nil, attachments: [log]))
        guard case .assistant(let blocks, _)? = mapped?.kind else {
            Issue.record("expected an assistant item")
            return
        }
        #expect(blocks.count == 1)
    }

    @Test func unknownAttachmentTypesRenderAsFiles() {
        let odd = ChatAttachment(type: "snapshot", id: "x", name: "x.bin", mimeType: "image/png", sizeBytes: 1)
        #expect(SwftAdapters.transcriptAttachment(from: odd).kind == .file)
    }

    @Test func viewedImagePathRidesOnTheToolStep() {
        let mapped = map(.dynamicTool(toolName: "view_image", viewedImagePath: "/work/shot.png", input: nil, output: nil, outputOmitted: false))
        guard case .toolCall(let call)? = mapped?.kind else {
            Issue.record("expected a tool call")
            return
        }
        #expect(call.imagePath == "/work/shot.png")
    }

    @Test func chatAttachmentRoundTrip() {
        let display = SwftAdapters.transcriptAttachment(from: shot)
        #expect(SwftAdapters.chatAttachment(from: display) == shot)
    }

    @Test func pendingMessageWithAttachmentsKeepsItsRowThroughTheEcho() {
        let attachment = SwftAdapters.transcriptAttachment(from: shot)
        let pending = [PendingUserMessage(messageID: "msg-new", text: "", attachments: [attachment])]
        let thread = AppThread(id: "thr-1", projectId: "p", title: "T", providerInstanceId: "claudeAgent", modelSelection: ModelSelection(instanceId: "claudeAgent", model: "haiku"), branch: "main", createdAt: t0, updatedAt: t0)
        let summary = ThreadSummary(id: "thr-1", title: "T", project: nil, location: nil, provider: .claude, activity: .idle, updatedAt: t0)

        let before = SwftAdapters.threadDetail(from: ThreadProjection(thread: thread, runtimeRequests: [], visibleTurnItems: [], updatedAt: t0), summary: summary, pendingUserMessages: pending)
        let echo = item(.userMessage(messageId: "msg-new", text: "", inputIntent: "turn_start", attachments: [shot], createdBy: "user", creationSource: "web"), id: "server-item")
        let projected = ProjectedTurnItem(position: 0, visibility: .local, sourceThreadId: "thr-1", sourceItemId: echo.id, item: echo)
        let after = SwftAdapters.threadDetail(from: ThreadProjection(thread: thread, runtimeRequests: [], visibleTurnItems: [projected], updatedAt: t0), summary: summary, pendingUserMessages: pending)

        #expect(before.rows == [.user(id: "msg-new", text: "", attachments: [attachment])])
        #expect(after.rows == before.rows)
    }
}

@Suite("Composer attachments")
@MainActor
struct ComposerAttachmentTests {
    private func pngData(width: Int = 64, height: Int = 32) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        return try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }

    @Test func canSendRules() {
        let ready = ComposerAttachmentItem(id: "a", kind: .image, name: "a", mimeType: "image/png", sizeBytes: 1, previewKey: nil, status: .ready)
        let uploading = ComposerAttachmentItem(id: "b", kind: .file, name: "b", mimeType: "text/plain", sizeBytes: 1, previewKey: nil, status: .uploading)
        let failed = ComposerAttachmentItem(id: "c", kind: .file, name: "c", mimeType: "text/plain", sizeBytes: 1, previewKey: nil, status: .failed("x"))
        #expect(!ComposerAttachmentHandlers.canSend(text: "  ", items: []))
        #expect(ComposerAttachmentHandlers.canSend(text: "hi", items: []))
        #expect(ComposerAttachmentHandlers.canSend(text: "", items: [ready]))
        #expect(!ComposerAttachmentHandlers.canSend(text: "hi", items: [ready, uploading]))
        #expect(!ComposerAttachmentHandlers.canSend(text: "", items: [failed]))
    }

    @Test func unsupportedImagesAreTranscoded() throws {
        let png = try pngData()
        let rep = try #require(NSBitmapImageRep(data: png))
        let tiff = try #require(rep.tiffRepresentation)
        #expect(AttachmentPreparer.sniffImageMime(tiff) == "image/tiff")
        let payload = try AttachmentPreparer.prepareImage(data: tiff, name: "Pasted image.tiff", declaredMime: "image/tiff")
        #expect(payload.kind == .image)
        #expect(payload.mimeType == "image/png")
        #expect(payload.name == "Pasted image.png")
        #expect(AttachmentPreparer.sniffImageMime(payload.data) == "image/png")
        #expect(payload.preview?.width == 64)
    }

    @Test func supportedImagesPassThroughUntouched() throws {
        let png = try pngData()
        let payload = try AttachmentPreparer.prepareImage(data: png, name: "a.png", declaredMime: nil)
        #expect(payload.data == png)
        #expect(payload.mimeType == "image/png")
    }

    @Test func mockSendCarriesAttachmentsIntoTheThreadAndFlight() async throws {
        let model = AppModel.mock()
        model.open(MockData.threadDetail.summary.id)
        await model.composerAttachments.stage(.imageData(try pngData(), suggestedName: "shot.png"), connection: nil)
        #expect(model.composerAttachments.items.map(\.status) == [.ready])
        let staged = try #require(model.composerAttachments.ready.first)
        #expect(SwftImageCache.shared.image(for: SwftImageReference.attachmentKey(staged.id)) != nil)

        // Attachment-only send.
        model.send()
        #expect(model.composerAttachments.isEmpty)
        #expect(model.latestThreadSend?.attachments == [staged])
        let detail = try #require(model.detail(for: MockData.threadDetail.summary.id))
        guard case .user(_, let text, let attachments)? = detail.rows.last(where: { if case .user = $0 { true } else { false } }) else {
            Issue.record("expected the sent row")
            return
        }
        #expect(text.isEmpty)
        #expect(attachments == [staged])
    }

    @Test func emptyComposerDoesNotSend() {
        let model = AppModel.mock()
        model.open(MockData.threadDetail.summary.id)
        model.send()
        #expect(model.latestThreadSend == nil)
    }

    @Test func removingAStagedAttachmentReleasesItsPreview() async throws {
        let attachments = ComposerAttachments()
        await attachments.stage(.imageData(try pngData(), suggestedName: "x.png"), connection: nil)
        let item = try #require(attachments.items.first)
        let key = try #require(item.previewKey)
        #expect(SwftImageCache.shared.image(for: key) != nil)
        attachments.remove(item.id)
        #expect(attachments.isEmpty)
        #expect(SwftImageCache.shared.image(for: key) == nil)
    }

    @Test func oversizedFilesAreRejectedWithAMessage() async {
        let attachments = ComposerAttachments()
        var message: String?
        attachments.onError = { message = $0 }
        await attachments.stage(.imageData(Data(), suggestedName: "empty.png"), connection: nil)
        #expect(attachments.isEmpty)
        #expect(message != nil)
    }

    @Test func promotedServerAttachmentIDsReuseCachedLocalPreview() throws {
        let pendingID = "pending-\(UUID().uuidString.lowercased())"
        let promotedID = "thread-1-\(UUID().uuidString.lowercased())"
        let decoded = try #require(SwftImageCache.decode(try pngData(width: 48, height: 24)))
        SwftImageCache.shared.store(decoded, for: SwftImageReference.attachmentKey(pendingID))

        let pending = [TranscriptAttachment(id: pendingID, kind: .image, name: "shot.png", mimeType: "image/png", sizeBytes: 120)]
        let promoted = [ChatAttachment(type: "image", id: promotedID, name: "shot.png", mimeType: "image/png", sizeBytes: 120)]
        AppModel.aliasAttachmentPreviews(from: pending, to: promoted)

        let aliased = try #require(SwftImageCache.shared.image(for: SwftImageReference.attachmentKey(promotedID)))
        #expect(aliased.width == 48)
        #expect(aliased.height == 24)
    }
}

@Suite("Image lightbox and cache")
@MainActor
struct ImageLightboxTests {
    private func solidGreenImage(width: Int = 160, height: Int = 120) throws -> (CGImage, Data) {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 0.05, green: 0.92, blue: 0.15, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        return (image, png)
    }

    private func hostOffscreen<V: View>(_ view: V, size: CGSize = CGSize(width: 640, height: 480)) -> (NSWindow, NSHostingView<V>) {
        SwftFonts.register()
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -4000, y: -4000), size: size),
            styleMask: [.titled, .fullSizeContentView, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        window.orderBack(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.45))
        return (window, host)
    }

    private func containsBrightGreenPixel(in view: NSView) throws -> Bool {
        view.layoutSubtreeIfNeeded()
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let stepX = max(1, rep.pixelsWide / 80)
        let stepY = max(1, rep.pixelsHigh / 80)
        for y in stride(from: 0, to: rep.pixelsHigh, by: stepY) {
            for x in stride(from: 0, to: rep.pixelsWide, by: stepX) {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if color.greenComponent > 0.7 && color.redComponent < 0.3 && color.blueComponent < 0.3 {
                    return true
                }
            }
        }
        return false
    }

    private func accessibilityStrings(in root: Any) -> [String] {
        var result: [String] = []
        var visited = Set<ObjectIdentifier>()
        var stack: [AnyObject] = [root as AnyObject]
        while let current = stack.popLast() {
            let id = ObjectIdentifier(current)
            guard visited.insert(id).inserted else { continue }
            if let element = current as? any NSAccessibilityProtocol {
                if let label = element.accessibilityLabel(), !label.isEmpty { result.append(label) }
                if let title = element.accessibilityTitle(), !title.isEmpty { result.append(title) }
                if let value = element.accessibilityValue() as? String, !value.isEmpty { result.append(value) }
                if let children = element.accessibilityChildren() {
                    for child in children {
                        stack.append(child as AnyObject)
                    }
                }
            }
            if let view = current as? NSView {
                for subview in view.subviews {
                    stack.append(subview)
                }
            }
        }
        return result
    }

    @Test func lightboxDisplaysThreadScopedImageViaPreviewCacheKey() throws {
        let reference = SwftImageReference.source("/workspace/dog-\(UUID().uuidString).png")
        let scope = "env-1:thr-dog"
        let key = reference.cacheKey(scope: scope)
        let (image, _) = try solidGreenImage()
        SwftImageCache.shared.store(image, for: key, pinned: true)
        defer { SwftImageCache.shared.unpin(key) }

        let preview = SwftImagePreview(cacheKey: key, reference: reference, caption: "dog.png")
        // Intentionally uses the default `.cacheOnly` loader so only `preview.cacheKey` can resolve the scoped image.
        let (window, host) = hostOffscreen(
            SwftImageLightbox(preview: preview, onClose: {})
        )
        defer { window.orderOut(nil) }

        #expect(try containsBrightGreenPixel(in: host))
        #expect(!accessibilityStrings(in: host).contains { $0.localizedCaseInsensitiveContains("Image unavailable") })
    }

    @Test func threadViewPropagatesImageLoaderIntoLightboxOverlay() throws {
        let model = AppModel.mock()
        let detail = MockData.threadDetail
        let threadScope = model.imageLoader(forThreadID: detail.summary.id).scope
        #expect(!threadScope.isEmpty)

        let reference = SwftImageReference.source("/workspace/dog-\(UUID().uuidString).png")
        let scopedKey = reference.cacheKey(scope: threadScope)
        let (image, _) = try solidGreenImage()
        SwftImageCache.shared.store(image, for: scopedKey, pinned: true)
        defer { SwftImageCache.shared.unpin(scopedKey) }

        // Force a miss on `preview.cacheKey` so the lightbox must resolve via ThreadView's inherited `swftImageLoader`.
        let preview = SwftImagePreview(cacheKey: "evicted-\(UUID().uuidString)", reference: reference, caption: "dog.png")
        let (window, host) = hostOffscreen(
            ThreadView(detail: detail, initialImagePreview: preview)
                .environment(model),
            size: CGSize(width: 900, height: 680)
        )
        defer { window.orderOut(nil) }

        #expect(try containsBrightGreenPixel(in: host))
        #expect(!accessibilityStrings(in: host).contains { $0.localizedCaseInsensitiveContains("Image unavailable") })
    }

    @Test func cacheOnlyLoaderDoesNotPoisonGlobalKeys() async throws {
        let (_, png) = try solidGreenImage(width: 64, height: 32)
        let references: [SwftImageReference] = [
            .attachment(id: "global-att-\(UUID().uuidString)", name: "dog.png", mimeType: "image/png"),
            .source("https://example.com/dog-\(UUID().uuidString).png"),
        ]
        let realLoader = SwftImageLoader(scope: "env-1:thr-1") { _ in png }

        for reference in references {
            let key = reference.cacheKey(scope: realLoader.scope)
            #expect(reference.cacheKey(scope: SwftImageLoader.cacheOnly.scope) == key)

            let cacheOnlyResult = await SwftImageCache.shared.load(reference, using: .cacheOnly)
            #expect(cacheOnlyResult == nil)
            #expect(!SwftImageCache.shared.hasFailed(key))

            let (window, _) = hostOffscreen(
                SwftCachedImage(reference) { phase in
                    if case .failure = phase { Text("unavailable") } else { Color.clear }
                },
                size: CGSize(width: 120, height: 80)
            )
            window.orderOut(nil)
            #expect(!SwftImageCache.shared.hasFailed(key))

            let loaded = await SwftImageCache.shared.load(reference, using: realLoader)
            let decoded = try #require(loaded)
            #expect(decoded.width == 64)
            #expect(decoded.height == 32)
        }
    }
}
