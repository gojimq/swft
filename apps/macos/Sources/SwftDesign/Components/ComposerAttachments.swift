import AppKit
import SwiftUI

/// One staged attachment in the composer tray.
public struct ComposerAttachmentItem: Identifiable, Hashable, Sendable {
    public enum Status: Hashable, Sendable {
        case uploading
        case ready
        case failed(String)
    }

    public let id: String
    public var kind: TranscriptAttachment.Kind
    public var name: String
    public var mimeType: String
    public var sizeBytes: Int
    /// `SwftImageCache` key of the local preview (images only), present from the moment the item is staged.
    public var previewKey: String?
    public var status: Status

    public init(id: String, kind: TranscriptAttachment.Kind, name: String, mimeType: String, sizeBytes: Int, previewKey: String?, status: Status) {
        self.id = id
        self.kind = kind
        self.name = name
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.previewKey = previewKey
        self.status = status
    }
}

public enum ComposerAttachmentMetrics {
    public static let thumbnailSide: CGFloat = 60
    public static let fileChipMaxWidth: CGFloat = 220
    public static let cornerRadius: CGFloat = 14
    public static let spacing: CGFloat = 8
    /// The remove button overhangs the card's corner slightly; the tray pads for it.
    public static let removeOverhang: CGFloat = 6
}

/// Horizontal strip of staged attachments at the top of the composer.
public struct ComposerAttachmentTray: View {
    let items: [ComposerAttachmentItem]
    let onRemove: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(items: [ComposerAttachmentItem], onRemove: @escaping (String) -> Void) {
        self.items = items
        self.onRemove = onRemove
    }

    public var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: ComposerAttachmentMetrics.spacing) {
                ForEach(items) { item in
                    ComposerAttachmentCard(item: item) {
                        withAnimation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion)) {
                            onRemove(item.id)
                        }
                    }
                    .transition(.swftPop(reduceMotion: reduceMotion, scale: 0.85))
                }
            }
            .padding(.top, ComposerAttachmentMetrics.removeOverhang)
            .padding(.trailing, ComposerAttachmentMetrics.removeOverhang)
        }
        .scrollIndicators(.never)
        .animation(SwftMotion.resolve(SwftMotion.spring, reduceMotion: reduceMotion), value: items.map(\.id))
        .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: items.map(\.status))
    }
}

struct ComposerAttachmentCard: View {
    let item: ComposerAttachmentItem
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ComposerAttachmentMetrics.cornerRadius, style: .continuous)
        content(shape: shape)
            .overlay(shape.strokeBorder(isFailed ? SwftColor.danger.opacity(0.55) : SwftColor.borderSubtle))
            .overlay(alignment: .topTrailing) {
                RemoveAttachmentButton(name: item.name, action: onRemove)
                    .offset(x: ComposerAttachmentMetrics.removeOverhang, y: -ComposerAttachmentMetrics.removeOverhang)
                    .opacity(hovering || isFailed ? 1 : 0)
                    .scaleEffect(hovering || isFailed ? 1 : 0.8)
            }
            .contentShape(shape)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.14), value: hovering)
            .help(helpText)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(item.name))
            .accessibilityValue(Text(statusText ?? AttachmentMetrics.formattedSize(item.sizeBytes)))
    }

    private var isFailed: Bool { if case .failed = item.status { true } else { false } }

    private var statusText: String? {
        switch item.status {
        case .uploading: "Uploading…"
        case .ready: nil
        case .failed(let message): message
        }
    }

    private var helpText: String {
        if case .failed(let message) = item.status { return "\(item.name): \(message)" }
        return item.name
    }

    @ViewBuilder private func content(shape: RoundedRectangle) -> some View {
        switch item.kind {
        case .image:
            ZStack {
                shape.fill(SwftColor.surfaceMuted)
                if let key = item.previewKey, let image = SwftImageCache.shared.image(for: key) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: ComposerAttachmentMetrics.thumbnailSide, height: ComposerAttachmentMetrics.thumbnailSide)
                } else {
                    Image(systemName: "photo").foregroundStyle(SwftColor.textTertiary)
                }
                statusOverlay
            }
            .frame(width: ComposerAttachmentMetrics.thumbnailSide, height: ComposerAttachmentMetrics.thumbnailSide)
            .clipShape(shape)
        case .file:
            HStack(spacing: 10) {
                ZStack {
                    FileGlyph(mimeType: item.mimeType, name: item.name, side: 36)
                    if item.status == .uploading {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(SwftColor.surface.opacity(0.55))
                            .frame(width: 36, height: 36)
                        ProgressView().controlSize(.small)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(SwftType.label)
                        .foregroundStyle(SwftColor.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(statusText ?? AttachmentMetrics.formattedSize(item.sizeBytes))
                        .font(SwftType.caption)
                        .foregroundStyle(isFailed ? SwftColor.danger.opacity(0.9) : SwftColor.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .frame(maxWidth: ComposerAttachmentMetrics.fileChipMaxWidth, alignment: .leading)
            .frame(height: ComposerAttachmentMetrics.thumbnailSide)
            .fixedSize(horizontal: true, vertical: false)
            .background(shape.fill(SwftColor.surface))
        }
    }

    @ViewBuilder private var statusOverlay: some View {
        switch item.status {
        case .uploading:
            Rectangle().fill(Color.black.opacity(0.22))
            ProgressView().controlSize(.small).tint(.white)
        case .failed:
            Rectangle().fill(Color.black.opacity(0.3))
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        case .ready:
            EmptyView()
        }
    }
}

private struct RemoveAttachmentButton: View {
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(SwftColor.textPrimary)
                .frame(width: 20, height: 20)
                .background(Circle().fill(SwftColor.surfaceRaised))
                .overlay(Circle().strokeBorder(SwftColor.border))
                .shadow(color: SwftColor.shadow, radius: 3, y: 1)
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.85))
        .help("Remove \(name)")
        .accessibilityLabel(Text("Remove \(name)"))
    }
}
