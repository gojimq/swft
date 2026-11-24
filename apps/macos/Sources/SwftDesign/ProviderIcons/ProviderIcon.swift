import AppKit
import SwiftUI

/// Controls whether provider marks with native brand colors render in color or adopt the foreground tint.
public enum ProviderIconRenderingMode: Hashable, Sendable {
    /// Brand-colored where the original mark is colored (Claude, Antigravity, Kiro, Muse Code);
    /// monochrome marks tint to the surrounding foreground style.
    case original
    /// Forces every mark into monochrome foreground tinting.
    case monochrome
}

/// Renders the vector mark for a coding-agent provider or sub-provider at any point size (crisp at 12–20pt).
public struct ProviderIcon: View {
    public let resolved: ResolvedProviderIcon
    public let size: CGFloat
    public let renderingMode: ProviderIconRenderingMode

    public init(
        provider: String,
        size: CGFloat = 14,
        acpAgentID: String? = nil,
        iconURL: String? = nil,
        renderingMode: ProviderIconRenderingMode = .original
    ) {
        self.resolved = ProviderIconKind.resolve(driver: provider, acpAgentID: acpAgentID, iconURL: iconURL)
        self.size = size
        self.renderingMode = renderingMode
    }

    public init(
        kind: ProviderIconKind,
        size: CGFloat = 14,
        renderingMode: ProviderIconRenderingMode = .original
    ) {
        self.resolved = .mark(kind)
        self.size = size
        self.renderingMode = renderingMode
    }

    public init(
        resolved: ResolvedProviderIcon,
        size: CGFloat = 14,
        renderingMode: ProviderIconRenderingMode = .original
    ) {
        self.resolved = resolved
        self.size = size
        self.renderingMode = renderingMode
    }

    public var body: some View {
        Group {
            switch resolved {
            case .mark(.antigravity):
                AntigravityMarkView(size: size, renderingMode: renderingMode)
            case .mark(.generic):
                GenericAgentMarkView(size: size)
            case .mark(let kind):
                if let spec = ProviderIconArtwork.vectorSpec(for: kind) {
                    VectorMarkView(spec: spec, renderingMode: renderingMode)
                } else {
                    GenericAgentMarkView(size: size)
                }
            case .acpRegistry(let iconURL):
                AcpRegistryMarkView(iconURL: iconURL, size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Renders a sub-provider section icon (e.g. OpenRouter, Anthropic, OpenAI, Ollama) when upstream ships its mark.
public struct SubProviderIcon: View {
    public let name: String
    public let size: CGFloat
    public let renderingMode: ProviderIconRenderingMode

    public init(
        name: String,
        size: CGFloat = 12,
        renderingMode: ProviderIconRenderingMode = .monochrome
    ) {
        self.name = name
        self.size = size
        self.renderingMode = renderingMode
    }

    public var body: some View {
        if let kind = ProviderIconKind.resolveSubProvider(name) {
            ProviderIcon(kind: kind, size: size, renderingMode: renderingMode)
        }
    }
}

// MARK: - Internal Rendering Views

private struct VectorMarkView: View {
    let spec: ProviderIconArtwork.VectorSpec
    let renderingMode: ProviderIconRenderingMode

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let transform = SVGPathParser.fitTransform(viewBox: spec.viewBox, into: rect)

            for layer in spec.layers {
                if renderingMode == .monochrome, layer.originalOnly { continue }
                if renderingMode == .original, layer.monochromeOnly { continue }

                let path = layer.path.applying(transform)
                let fillStyle = FillStyle(eoFill: layer.evenOdd, antialiased: true)

                switch layer.fill {
                case .foreground(let opacity):
                    if opacity < 1 {
                        var sub = context
                        sub.opacity = opacity
                        sub.fill(path, with: .foreground, style: fillStyle)
                    } else {
                        context.fill(path, with: .foreground, style: fillStyle)
                    }

                case .brand(let hex, let monochromeVisible):
                    if renderingMode == .monochrome {
                        if monochromeVisible {
                            context.fill(path, with: .foreground, style: fillStyle)
                        }
                    } else {
                        context.fill(path, with: .color(Color(nsColor: NSColor(hex: hex))), style: fillStyle)
                    }

                case .brandGradient(let gradientSpec):
                    if renderingMode == .monochrome {
                        context.fill(path, with: .foreground, style: fillStyle)
                    } else {
                        let start = gradientSpec.start.applying(transform)
                        let end = gradientSpec.end.applying(transform)
                        let gradient = Gradient(stops: gradientSpec.stops.map {
                            Gradient.Stop(color: Color(nsColor: NSColor(hex: $0.hex)), location: $0.offset)
                        })
                        context.fill(
                            path,
                            with: .linearGradient(gradient, startPoint: start, endPoint: end),
                            style: fillStyle
                        )
                    }
                }
            }
        }
    }
}

private struct AntigravityMarkView: View {
    let size: CGFloat
    let renderingMode: ProviderIconRenderingMode

    var body: some View {
        if let nsImage = ProviderIconArtwork.antigravityImage {
            Image(nsImage: nsImage)
                .renderingMode(renderingMode == .monochrome ? .template : .original)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Canvas(rendersAsynchronously: false) { context, canvasSize in
                let rect = CGRect(origin: .zero, size: canvasSize)
                let path = SVGPathParser.fittedPath(
                    ProviderIconArtwork.antigravityFallbackPath,
                    viewBox: CGRect(x: 0, y: 0, width: 128, height: 128),
                    in: rect
                )
                if renderingMode == .monochrome {
                    context.fill(path, with: .foreground)
                } else {
                    let gradient = Gradient(colors: [
                        Color(nsColor: NSColor(hex: 0xF4B400)),
                        Color(nsColor: NSColor(hex: 0xEA4335)),
                        Color(nsColor: NSColor(hex: 0x34A853)),
                        Color(nsColor: NSColor(hex: 0x4285F4)),
                    ])
                    context.fill(
                        path,
                        with: .linearGradient(
                            gradient,
                            startPoint: CGPoint(x: rect.midX, y: rect.minY),
                            endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                        )
                    )
                }
            }
        }
    }
}

/// Neutral fallback mark matching Studio's `AgentIcon` (concentric circles in a 12×12 box).
private struct GenericAgentMarkView: View {
    let size: CGFloat

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, canvasSize in
            let side = min(canvasSize.width, canvasSize.height)
            let scale = side / 12
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let strokeStyle = StrokeStyle(lineWidth: 1.6 * scale, lineCap: .round, lineJoin: .round)

            let outerR = 4.25 * scale
            let outer = Path(ellipseIn: CGRect(x: center.x - outerR, y: center.y - outerR, width: outerR * 2, height: outerR * 2))
            context.stroke(outer, with: .foreground, style: strokeStyle)

            let innerR = 1.1 * scale
            let inner = Path(ellipseIn: CGRect(x: center.x - innerR, y: center.y - innerR, width: innerR * 2, height: innerR * 2))
            context.stroke(inner, with: .foreground, style: strokeStyle)
        }
    }
}

private struct AcpRegistryMarkView: View {
    let iconURL: URL?
    let size: CGFloat
    private let cache = AcpRegistryIconCache.shared

    var body: some View {
        Group {
            if let iconURL {
                switch cache.entry(for: iconURL) {
                case .svg(let parsed):
                    Canvas(rendersAsynchronously: false) { context, canvasSize in
                        let rect = CGRect(origin: .zero, size: canvasSize)
                        let transform = SVGPathParser.fitTransform(viewBox: parsed.viewBox, into: rect)
                        for item in parsed.paths {
                            context.fill(
                                item.path.applying(transform),
                                with: .foreground,
                                style: FillStyle(eoFill: item.evenOdd, antialiased: true)
                            )
                        }
                    }
                case .raster(let image):
                    Image(nsImage: image)
                        .renderingMode(.template)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                case .loading, .failed:
                    fallbackMark
                }
            } else {
                fallbackMark
            }
        }
        .task(id: iconURL) {
            if let iconURL {
                cache.loadIfNeeded(iconURL)
            }
        }
    }

    @ViewBuilder
    private var fallbackMark: some View {
        if let spec = ProviderIconArtwork.vectorSpec(for: .acpRegistry) {
            VectorMarkView(spec: spec, renderingMode: .monochrome)
        } else {
            GenericAgentMarkView(size: size)
        }
    }
}
