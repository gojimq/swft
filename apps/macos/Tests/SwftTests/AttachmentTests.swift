import AppKit
import Foundation
import SwftDesign
import SwftKit
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

@Suite("Attachment send flight")
@MainActor
struct AttachmentSendFlightTests {
    private let image = TranscriptAttachment(id: "img-1", kind: .image, name: "a.png", mimeType: "image/png", sizeBytes: 10)
    private let file = TranscriptAttachment(id: "file-1", kind: .file, name: "a.txt", mimeType: "text/plain", sizeBytes: 10)

    @Test func textOnlyTurnMatchesTheBubbleEstimate() {
        let text = UserBubbleMetrics.estimatedTurnSize(text: "Hello", attachments: [], maxWidth: 600)
        #expect(text == UserBubbleMetrics.estimatedSize(for: "Hello", maxWidth: 600))
    }

    @Test func imagesOnlyTurnIsJustTheStrip() {
        let single = UserBubbleMetrics.estimatedTurnSize(text: "", attachments: [image], maxWidth: 600, aspectRatio: { _ in 16.0 / 9.0 })
        #expect(single == CGSize(width: AttachmentMetrics.singleImageWidth(aspectRatio: 16.0 / 9.0), height: AttachmentMetrics.singleImageHeight))
        #expect(single.width == 320 || single.width == (200 * 16.0 / 9.0).rounded())

        let unknownAspect = UserBubbleMetrics.estimatedTurnSize(text: " ", attachments: [image], maxWidth: 600)
        #expect(unknownAspect == CGSize(width: AttachmentMetrics.singleImageHeight, height: AttachmentMetrics.singleImageHeight))
    }

    @Test func textAndAttachmentsStackWithTheStripGap() {
        let attachments = [image, file]
        let strip = AttachmentMetrics.stripSize(for: attachments, maxWidth: 600)
        #expect(strip == CGSize(width: AttachmentMetrics.tileSide + AttachmentMetrics.spacing + AttachmentMetrics.fileChipWidth, height: AttachmentMetrics.fileChipHeight > AttachmentMetrics.tileSide ? AttachmentMetrics.fileChipHeight : AttachmentMetrics.tileSide))
        let pill = UserBubbleMetrics.estimatedSize(for: "Look at these", maxWidth: 600)
        let turn = UserBubbleMetrics.estimatedTurnSize(text: "Look at these", attachments: attachments, maxWidth: 600)
        #expect(turn.height == strip.height + AttachmentMetrics.stripToBubbleSpacing + pill.height)
        #expect(turn.width == max(strip.width, pill.width))
    }

    @Test func stripWrapsWithinTheColumn() {
        let five = (0..<5).map { TranscriptAttachment(id: "i\($0)", kind: .image, name: "\($0).png", mimeType: "image/png", sizeBytes: 1) }
        let side = AttachmentMetrics.tileSide
        let gap = AttachmentMetrics.spacing
        let narrow = AttachmentMetrics.stripSize(for: five, maxWidth: side * 3 + gap * 2)
        #expect(narrow == CGSize(width: side * 3 + gap * 2, height: side * 2 + gap))
    }

    @Test func landingFrameTucksATallTurnAboveTheComposer() {
        let viewport = CGSize(width: 1000, height: 360)
        let size = UserBubbleMetrics.estimatedTurnSize(text: "Look", attachments: [image, file, image], maxWidth: 600)
        let frame = SendFlightLogic.landingFrame(viewportSize: viewport, topInset: 76, bottomInset: 200, bubbleSize: size)
        #expect(frame.size == size)
        // The turn is taller than the stream room, so it ends `bottomInset` above the viewport bottom.
        #expect(frame.maxY + SendFlightLogic.userRowVerticalPadding == viewport.height - 200)
        #expect(frame.maxX == (viewport.width + min(viewport.width - 64, 760)) / 2)
    }

    @Test func cachedAspectRatioDrivesTheEstimate() throws {
        let context = try #require(CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let cg = try #require(context.makeImage())
        let attachment = TranscriptAttachment(id: "aspect-\(UUID().uuidString)", kind: .image, name: "w.png", mimeType: "image/png", sizeBytes: 1)
        SwftImageCache.shared.store(cg, for: SwftImageReference.attachmentKey(attachment.id), pinned: true)
        defer { SwftImageCache.shared.unpin(SwftImageReference.attachmentKey(attachment.id)) }
        let size = SendFlightLogic.estimatedTurnSize(text: "", attachments: [attachment], maxWidth: 600)
        #expect(size == CGSize(width: 320, height: 200))
    }

    @Test func sendEventCarriesAttachmentsIntoTheFlight() {
        let coordinator = SendFlightCoordinator()
        var detail = MockData.threadDetail
        detail.items.append(TranscriptItem(id: "u-att", kind: .user("", attachments: [image])))
        coordinator.syncThread(detail: detail, isBusy: false)
        let event = ThreadSendEvent(threadID: detail.summary.id, text: "", attachments: [image], optimisticItemID: "u-att")
        #expect(coordinator.beginSend(event, detail: detail, reduceMotion: false) == .startFlight)
        #expect(coordinator.activeFlight?.attachments == [image])
        #expect(coordinator.isBubbleHiddenForFlight(rowID: "u-att", in: detail))
        coordinator.cancelFlight(clearPendingStreamRoom: true)
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
