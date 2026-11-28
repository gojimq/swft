import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A message attachment as the transcript shows it: what it is and the server id its bytes live under.
public struct TranscriptAttachment: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case image
        case file
    }

    public let id: String
    public var kind: Kind
    public var name: String
    public var mimeType: String
    public var sizeBytes: Int

    public init(id: String, kind: Kind, name: String, mimeType: String, sizeBytes: Int) {
        self.id = id
        self.kind = kind
        self.name = name
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
    }

    public var imageReference: SwftImageReference {
        .attachment(id: id, name: name, mimeType: mimeType)
    }
}

/// Fixed attachment geometry. Sizes never depend on load state (only a lone image's width follows its aspect ratio
/// once decoded), so rows never jump vertically.
public enum AttachmentMetrics {
    public static let singleImageHeight: CGFloat = 200
    public static let singleImageMinWidth: CGFloat = 120
    public static let singleImageMaxWidth: CGFloat = 320
    public static let tileSide: CGFloat = 108
    public static let fileChipWidth: CGFloat = 228
    public static let fileChipHeight: CGFloat = 52
    public static let spacing: CGFloat = 6
    /// Gap between the attachment strip and the text bubble below it.
    public static let stripToBubbleSpacing: CGFloat = 6
    public static let cornerRadius: CGFloat = 16

    /// A lone image keeps its aspect ratio at a fixed height; anything else is a grid of square tiles and file chips.
    public static func usesSingleImageLayout(_ attachments: [TranscriptAttachment]) -> Bool {
        attachments.count == 1 && attachments[0].kind == .image
    }

    /// Width of a lone image at `singleImageHeight`; square until its aspect ratio (width / height) is known.
    public static func singleImageWidth(aspectRatio: CGFloat?) -> CGFloat {
        guard let aspectRatio, aspectRatio.isFinite, aspectRatio > 0 else { return singleImageHeight }
        return min(singleImageMaxWidth, max(singleImageMinWidth, (singleImageHeight * aspectRatio).rounded()))
    }

    public static func itemSize(_ attachment: TranscriptAttachment, single: Bool, aspectRatio: CGFloat?) -> CGSize {
        switch attachment.kind {
        case .image where single:
            return CGSize(width: singleImageWidth(aspectRatio: aspectRatio), height: singleImageHeight)
        case .image:
            return CGSize(width: tileSide, height: tileSide)
        case .file:
            return CGSize(width: fileChipWidth, height: fileChipHeight)
        }
    }

    public static func formattedSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(0, bytes)), countStyle: .file)
    }

    /// SF Symbol for a file attachment's type.
    public static func symbol(mimeType: String, name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        let type = UTType(mimeType: mimeType) ?? UTType(filenameExtension: ext)
        guard let type else { return "doc" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return "film" }
        if type.conforms(to: .audio) { return "waveform" }
        if type.conforms(to: .archive) { return "doc.zipper" }
        if type.conforms(to: .spreadsheet) || ext == "csv" { return "tablecells" }
        if type.conforms(to: .presentation) { return "rectangle.on.rectangle" }
        if type.conforms(to: .sourceCode) || type.conforms(to: .script) || type.conforms(to: .json) || type.conforms(to: .xml) {
            return "chevron.left.forwardslash.chevron.right"
        }
        if type.conforms(to: .text) { return "doc.text" }
        return "doc"
    }
}

/// Wrapping row layout aligned to the trailing edge (user turns) or the leading edge (agent attachments). It hugs its
/// widest row so the turn unit stays as tight as its content.
public struct AttachmentFlowLayout: Layout {
    public var spacing: CGFloat
    public var trailing: Bool

    public init(spacing: CGFloat = AttachmentMetrics.spacing, trailing: Bool = true) {
        self.spacing = spacing
        self.trailing = trailing
    }

    public static func measure(_ sizes: [CGSize], maxWidth: CGFloat, spacing: CGFloat) -> CGSize {
        let rows = rows(sizes, maxWidth: maxWidth, spacing: spacing)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    static func rows(_ sizes: [CGSize], maxWidth: CGFloat, spacing: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for (index, size) in sizes.enumerated() {
            let added = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty && added > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return Self.measure(sizes, maxWidth: proposal.width ?? .infinity, spacing: spacing)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var y = bounds.minY
        for row in Self.rows(sizes, maxWidth: bounds.width, spacing: spacing) {
            var x = trailing ? bounds.maxX - row.width : bounds.minX
            for index in row.indices {
                let size = sizes[index]
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }
}

// MARK: - Transcript attachment views

/// The attachments of one message: image tiles (or one larger image) and file chips, wrapping within the column.
public struct AttachmentStrip: View {
    let attachments: [TranscriptAttachment]
    let trailing: Bool
    let interactive: Bool

    public init(_ attachments: [TranscriptAttachment], trailing: Bool = true, interactive: Bool = true) {
        self.attachments = attachments
        self.trailing = trailing
        self.interactive = interactive
    }

    public var body: some View {
        let single = AttachmentMetrics.usesSingleImageLayout(attachments)
        AttachmentFlowLayout(spacing: AttachmentMetrics.spacing, trailing: trailing) {
            ForEach(attachments) { attachment in
                switch attachment.kind {
                case .image:
                    AttachmentImageTile(attachment: attachment, single: single, interactive: interactive)
                case .file:
                    AttachmentFileChip(attachment: attachment)
                }
            }
        }
    }
}

struct AttachmentImageTile: View {
    let attachment: TranscriptAttachment
    let single: Bool
    let interactive: Bool
    @Environment(\.swftImagePreviewAction) private var preview
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AttachmentMetrics.cornerRadius, style: .continuous)
        SwftCachedImage(attachment.imageReference) { phase in
            let aspect: CGFloat? = if case .success(let image) = phase, image.height > 0 { CGFloat(image.width) / CGFloat(image.height) } else { nil }
            let size = AttachmentMetrics.itemSize(attachment, single: single, aspectRatio: aspect)
            ZStack {
                shape.fill(SwftColor.surfaceMuted)
                switch phase {
                case .success(let image):
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height)
                case .loading:
                    ProgressView().controlSize(.small).opacity(0.6)
                case .failure:
                    Image(systemName: "photo")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(SwftColor.textTertiary)
                        .help("\(attachment.name) is unavailable")
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            .overlay(shape.strokeBorder(SwftColor.borderSubtle))
            .overlay(shape.fill(Color.black.opacity(hovering && interactive ? 0.06 : 0)))
            .contentShape(shape)
            .onTapGesture {
                guard interactive, let preview, case .success = phase else { return }
                preview(SwftImagePreview(
                    cacheKey: SwftImageReference.attachmentKey(attachment.id),
                    reference: attachment.imageReference,
                    caption: attachment.name
                ))
            }
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(attachment.name)
        .accessibilityLabel(Text("Image \(attachment.name)"))
        .accessibilityAddTraits(interactive ? .isButton : [])
    }
}

struct AttachmentFileChip: View {
    let attachment: TranscriptAttachment

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        HStack(spacing: 10) {
            FileGlyph(mimeType: attachment.mimeType, name: attachment.name)
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.name)
                    .font(SwftType.label)
                    .foregroundStyle(SwftColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(AttachmentMetrics.formattedSize(attachment.sizeBytes))
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(width: AttachmentMetrics.fileChipWidth, height: AttachmentMetrics.fileChipHeight)
        .background(shape.fill(SwftColor.surface))
        .overlay(shape.strokeBorder(SwftColor.border.opacity(0.8)))
        .help(attachment.name)
        .accessibilityElement(children: .combine)
    }
}

struct FileGlyph: View {
    let mimeType: String
    let name: String
    var side: CGFloat = 36

    var body: some View {
        Image(systemName: AttachmentMetrics.symbol(mimeType: mimeType, name: name))
            .font(.system(size: side * 0.42, weight: .regular))
            .foregroundStyle(SwftColor.accent)
            .frame(width: side, height: side)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(SwftColor.accentSoft.opacity(0.7)))
    }
}

/// Inline image in agent prose (`![alt](source)`): natural aspect ratio up to the column width and a bounded height.
public struct MessageImage: View {
    let source: String
    let alt: String
    @Environment(\.swftImageLoader) private var loader
    @Environment(\.swftImagePreviewAction) private var preview

    public static let maxHeight: CGFloat = 420
    public static let maxWidth: CGFloat = 560
    public static let placeholderHeight: CGFloat = 180

    public init(source: String, alt: String) {
        self.source = source
        self.alt = alt
    }

    public var body: some View {
        if SwftMediaClassifier.isVideo(source) {
            MessageVideo(source: source, alt: alt)
        } else {
            imageBody
        }
    }

    @ViewBuilder
    private var imageBody: some View {
        let reference = SwftImageReference.source(source)
        let shape = RoundedRectangle(cornerRadius: AttachmentMetrics.cornerRadius, style: .continuous)
        SwftCachedImage(reference) { phase in
            switch phase {
            case .success(let image):
                let aspect = image.height > 0 ? CGFloat(image.width) / CGFloat(image.height) : 1
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(aspect, contentMode: .fit)
                    // Decoded pixels are treated as 2x points, so screenshots render near their native size.
                    .frame(maxWidth: min(max(CGFloat(image.width) / 2, 160), Self.maxWidth), maxHeight: Self.maxHeight, alignment: .leading)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(SwftColor.borderSubtle))
                    .contentShape(shape)
                    .onTapGesture {
                        preview?(SwftImagePreview(cacheKey: reference.cacheKey(scope: loader.scope), reference: reference, caption: alt.isEmpty ? Self.fileName(source) : alt))
                    }
                    .accessibilityLabel(Text(alt.isEmpty ? "Image" : alt))
                    .accessibilityAddTraits(.isButton)
            case .loading:
                shape.fill(SwftColor.surfaceMuted)
                    .frame(width: 260, height: Self.placeholderHeight)
                    .overlay(ProgressView().controlSize(.small).opacity(0.6))
            case .failure:
                HStack(spacing: 8) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 13))
                    Text(alt.isEmpty ? Self.fileName(source) : alt)
                        .font(SwftType.label)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundStyle(SwftColor.textTertiary)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(Capsule().fill(SwftColor.surfaceMuted))
                .help("Couldn’t load \(source.hasPrefix("data:") ? "inline image" : source)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func fileName(_ source: String) -> String {
        if source.lowercased().hasPrefix("data:") { return "Image" }
        let trimmed = source.split(separator: "?").first.map(String.init) ?? source
        let last = (trimmed as NSString).lastPathComponent
        return last.isEmpty ? "Image" : (last.removingPercentEncoding ?? last)
    }
}

// MARK: - User turn

/// One sent user turn: its attachments above an optional text bubble, trailing-aligned.
public struct UserTurnContent: View {
    let text: String
    let attachments: [TranscriptAttachment]
    let pillOpacity: Double
    let interactive: Bool

    public init(text: String, attachments: [TranscriptAttachment], pillOpacity: Double = 1, interactive: Bool = true) {
        self.text = text
        self.attachments = attachments
        self.pillOpacity = pillOpacity
        self.interactive = interactive
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: AttachmentMetrics.stripToBubbleSpacing) {
            if !attachments.isEmpty {
                AttachmentStrip(attachments, trailing: true, interactive: interactive)
            }
            if UserBubbleMetrics.hasText(text) {
                Text(text)
                    .font(SwftType.body)
                    .foregroundStyle(SwftColor.textPrimary)
                    .lineSpacing(SwftType.bodyLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, UserBubbleMetrics.horizontalPadding)
                    .padding(.vertical, UserBubbleMetrics.verticalPadding)
                    .background(
                        RoundedRectangle(cornerRadius: UserBubbleMetrics.cornerRadius, style: .continuous)
                            .fill(SwftColor.userBubble.opacity(pillOpacity))
                    )
            }
        }
    }
}
