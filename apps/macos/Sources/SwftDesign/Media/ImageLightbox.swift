import AppKit
import SwiftUI

/// Full-size image preview over a darkened scrim. Closes on a click outside the image, Esc, or the close button.
public struct SwftImageLightbox: View {
    let preview: SwftImagePreview
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    /// Holds an already-cached image across the lightbox's lifetime so an `NSCache` eviction mid-open cannot flicker.
    @State private var retained: (key: String, image: CGImage)?

    public init(preview: SwftImagePreview, onClose: @escaping () -> Void) {
        self.preview = preview
        self.onClose = onClose
        if let image = SwftImageCache.shared.image(for: preview.cacheKey) {
            _retained = State(initialValue: (preview.cacheKey, image))
        }
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(shown ? 0.72 : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: close)

            VStack(spacing: 14) {
                lightboxImage
                    // Clicks on the image itself never fall through to the scrim.
                    .onTapGesture {}

                if !preview.caption.isEmpty {
                    Text(preview.caption)
                        .font(SwftType.label)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.black.opacity(0.35)))
                }
            }
            .padding(.horizontal, 64)
            .padding(.top, SwftLayout.titlebarHeight + 16)
            .padding(.bottom, 40)
            .scaleEffect(shown || reduceMotion ? 1 : 0.94)
            .opacity(shown ? 1 : 0)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.white.opacity(0.14)))
                    .contentShape(Circle())
            }
            .buttonStyle(PressScaleStyle())
            .keyboardShortcut(.cancelAction)
            .help("Close")
            .accessibilityLabel("Close preview")
            .padding(.top, SwftLayout.titlebarHeight + 4)
            .padding(.trailing, 20)
            .opacity(shown ? 1 : 0)
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : SwftMotion.screen) { shown = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    @ViewBuilder
    private var lightboxImage: some View {
        if let image = resolvedCachedImage {
            renderedImage(image)
        } else {
            SwftCachedImage(preview.reference) { phase in
                switch phase {
                case .success(let image):
                    renderedImage(image)
                case .loading:
                    ProgressView().controlSize(.regular).tint(.white)
                case .failure:
                    Label("Image unavailable", systemImage: "photo")
                        .font(SwftType.label)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
    }

    private var resolvedCachedImage: CGImage? {
        if let image = SwftImageCache.shared.image(for: preview.cacheKey) {
            return image
        }
        if let retained, retained.key == preview.cacheKey {
            return retained.image
        }
        return nil
    }

    private func renderedImage(_ image: CGImage) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: CGFloat(image.width), maxHeight: CGFloat(image.height))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 30, y: 10)
    }

    private func close() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.16)) {
            shown = false
        } completion: {
            onClose()
        }
    }
}
