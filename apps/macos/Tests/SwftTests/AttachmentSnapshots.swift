import AppKit
import SwftDesign
import SwiftUI
import Testing
@testable import Swft

/// Offscreen review shots of the attachment components (composer tray, user turn, agent images), rendered outside a
/// scroll view so the offscreen capture draws them. Skipped unless `SWFT_SNAPSHOT_DIR` is set.
@MainActor
@Suite("AttachmentSnapshots", .enabled(if: ProcessInfo.processInfo.environment["SWFT_SNAPSHOT_DIR"] != nil))
struct AttachmentSnapshots {
    @Test(arguments: ["light", "dark"])
    func components(appearance: String) throws {
        MockData.seedImageCache()
        let detail = MockData.attachmentsDetail
        let staged = [
            ComposerAttachmentItem(id: "a", kind: .image, name: "Screenshot.png", mimeType: "image/png", sizeBytes: 482_113, previewKey: SwftImageReference.attachmentKey("mock-shot"), status: .ready),
            ComposerAttachmentItem(id: "b", kind: .image, name: "chart.png", mimeType: "image/png", sizeBytes: 96_400, previewKey: SwftImageReference.attachmentKey("mock-chart"), status: .uploading),
            ComposerAttachmentItem(id: "c", kind: .file, name: "environment-switch.log", mimeType: "text/plain", sizeBytes: 18_204, previewKey: nil, status: .ready),
            ComposerAttachmentItem(id: "d", kind: .file, name: "huge-archive.zip", mimeType: "application/zip", sizeBytes: 90_000_000, previewKey: nil, status: .failed("Upload failed")),
        ]
        let view = VStack(alignment: .leading, spacing: 28) {
            ForEach(detail.rows) { row in
                switch row {
                case .user(_, let text, let attachments):
                    UserBubble(text, attachments: attachments)
                case .assistant(_, let blocks, _):
                    AssistantMessage {
                        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                            switch block {
                            case .text(let text): MessageText(text)
                            case .code(let language, let source): CodeBlock(source, language: language)
                            case .image(let alt, let source): MessageImage(source: source, alt: alt)
                            case .attachments(let attachments): AttachmentStrip(attachments, trailing: false)
                            }
                        }
                    }
                default:
                    EmptyView()
                }
            }
            UserBubble("", attachments: [
                TranscriptAttachment(id: "mock-shot", kind: .image, name: "a.png", mimeType: "image/png", sizeBytes: 1),
                TranscriptAttachment(id: "mock-chart", kind: .image, name: "b.png", mimeType: "image/png", sizeBytes: 1),
                TranscriptAttachment(id: "missing", kind: .image, name: "c.png", mimeType: "image/png", sizeBytes: 1),
            ])
            PillComposer(
                text: .constant("Here’s the clipping"),
                placeholder: "Reply…",
                attachments: ComposerAttachmentHandlers(items: staged),
                onSend: {}
            ) { EmptyView() }
        }
        .padding(32)
        .frame(width: 760)
        .background(SwftColor.canvas)

        try Self.capture(view, appearance: appearance, name: "attachment-components-\(appearance)", size: CGSize(width: 760, height: 1320))
    }

    static func capture(_ view: some View, appearance: String, name: String, size: CGSize) throws {
        SwftFonts.register()
        let renderer = ImageRenderer(content: view
            .environment(\.colorScheme, appearance == "dark" ? .dark : .light)
            .frame(width: size.width, height: size.height, alignment: .top))
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let rep = NSBitmapImageRep(cgImage: image)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: Snapshots.directory, withIntermediateDirectories: true)
        try png.write(to: Snapshots.directory.appendingPathComponent("\(name).png"))
    }
}
