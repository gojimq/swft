import AppKit
import AVFoundation
import AVKit
import SwiftUI

/// Inline video in agent prose (`![alt](clip.mp4)`): renders an upright first-frame poster with zero idle player
/// overhead and transitions to native `AVPlayerView` inline playback on click (auto-pausing on disappear).
public struct MessageVideo: View {
    let source: String
    let alt: String

    @Environment(\.swftMediaLoader) private var loader
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var asset: SwftVideoAsset?
    @State private var failed = false
    @State private var isPlaying = false
    @State private var player: AVPlayer?
    @State private var hovering = false
    @State private var retryNonce = 0

    public static let maxWidth: CGFloat = 560
    public static let maxHeight: CGFloat = 420

    public init(source: String, alt: String) {
        self.source = source
        self.alt = alt
    }

    private var caption: String {
        alt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? MessageImage.fileName(source)
            : alt
    }

    private struct LoadKey: Hashable {
        let scope: String
        let source: String
        let retryNonce: Int
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: AttachmentMetrics.cornerRadius, style: .continuous)
        Group {
            if let loaded = asset {
                let frameSize = fittedSize(aspectRatio: loaded.aspectRatio)
                if loaded.isPlayable {
                    ZStack {
                        if isPlaying, let player {
                            InlineAVPlayerView(player: player)
                                .frame(width: frameSize.width, height: frameSize.height)
                        } else {
                            posterView(for: loaded, size: frameSize)
                        }
                    }
                    .frame(width: frameSize.width, height: frameSize.height)
                    .background(Color.black.opacity(0.92))
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(SwftColor.borderSubtle))
                    .onHover { hovering = $0 }
                } else {
                    unsupportedPlayableCard(url: loaded.localURL, shape: shape)
                }
            } else if failed {
                failurePill
            } else {
                shape
                    .fill(SwftColor.surfaceMuted)
                    .frame(width: 280, height: MessageImage.placeholderHeight)
                    .overlay(ProgressView().controlSize(.small).opacity(0.6))
                    .overlay(shape.strokeBorder(SwftColor.borderSubtle))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: LoadKey(scope: loader.scope, source: source, retryNonce: retryNonce)) {
            let key = SwftVideoCache.shared.cacheKey(source: source, scope: loader.scope)
            if let cached = SwftVideoCache.shared.asset(for: key) {
                asset = cached
                failed = false
                return
            }
            if SwftVideoCache.shared.hasFailed(key) {
                asset = nil
                failed = true
                return
            }
            asset = nil
            failed = false
            let loaded = await SwftVideoCache.shared.load(source: source, using: loader)
            guard !Task.isCancelled else { return }
            asset = loaded
            failed = (loaded == nil)
        }
        .onDisappear {
            stopPlayback()
        }
    }

    @ViewBuilder
    private func posterView(for loaded: SwftVideoAsset, size: CGSize) -> some View {
        ZStack {
            if let poster = loaded.poster {
                Image(decorative: poster, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height)
            } else {
                Rectangle()
                    .fill(SwftColor.surfaceMuted)
                    .frame(width: size.width, height: size.height)
            }

            // Subtle vignette so the centered play button stays legible over bright frames.
            Color.black.opacity(hovering ? 0.22 : 0.14)

            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 52, height: 52)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: 1.5)
                }
                .shadow(color: Color.black.opacity(0.32), radius: 10, y: 3)
                .scaleEffect(hovering && !reduceMotion ? 1.06 : 1.0)
                .animation(SwftMotion.resolve(SwftMotion.quick, reduceMotion: reduceMotion), value: hovering)
        }
        .overlay(alignment: .bottom) {
            let badge = SwftMediaClassifier.formatDuration(loaded.duration)
            if !caption.isEmpty || badge != nil {
                HStack(spacing: 8) {
                    if !caption.isEmpty {
                        Text(caption)
                            .font(SwftType.caption)
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.black.opacity(0.58)))
                    }
                    Spacer(minLength: 4)
                    if let badge {
                        Text(badge)
                            .font(SwftType.captionStrong.monospacedDigit())
                            .foregroundStyle(.white)
                            .fixedSize()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.black.opacity(0.64)))
                    }
                }
                .padding(10)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { startPlayback(url: loaded.localURL) }
        .accessibilityLabel(Text("Play video: \(caption)"))
        .accessibilityAddTraits(.isButton)
    }

    private func unsupportedPlayableCard(url: URL, shape: RoundedRectangle) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "film")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(SwftColor.accent)
            Text(caption)
                .font(SwftType.label)
                .foregroundStyle(SwftColor.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button("Open") {
                NSWorkspace.shared.open(url)
            }
            .buttonStyle(HoverFillStyle(shape: Capsule()))
            .font(SwftType.captionStrong)
            .foregroundStyle(SwftColor.accent)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: 380, minHeight: 42)
        .background(shape.fill(SwftColor.surfaceMuted))
        .overlay(shape.strokeBorder(SwftColor.borderSubtle))
    }

    private var failurePill: some View {
        Button {
            let key = SwftVideoCache.shared.cacheKey(source: source, scope: loader.scope)
            SwftVideoCache.shared.retry(key)
            failed = false
            retryNonce += 1
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "video.slash")
                    .font(.system(size: 13))
                Text(caption)
                    .font(SwftType.label)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(SwftColor.textTertiary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Capsule().fill(SwftColor.surfaceMuted))
        }
        .buttonStyle(.plain)
        .help("Couldn’t load video — click to retry")
    }

    private func fittedSize(aspectRatio: CGFloat) -> CGSize {
        let ratio = max(0.35, min(3.0, aspectRatio))
        // Keep portrait clips tall and clear (up to maxHeight) and landscape clips wide up to maxWidth.
        let widthLimitedHeight = Self.maxWidth / ratio
        if widthLimitedHeight <= Self.maxHeight {
            return CGSize(width: Self.maxWidth, height: max(140, widthLimitedHeight))
        }
        let heightLimitedWidth = Self.maxHeight * ratio
        return CGSize(width: max(200, heightLimitedWidth), height: Self.maxHeight)
    }

    private func startPlayback(url: URL) {
        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.actionAtItemEnd = .pause
        player = avPlayer
        isPlaying = true
        avPlayer.play()
    }

    private func stopPlayback() {
        player?.pause()
        player = nil
        isPlaying = false
    }
}

private struct InlineAVPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.videoGravity = .resizeAspect
        view.showsFullScreenToggleButton = true
        view.allowsPictureInPicturePlayback = true
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
