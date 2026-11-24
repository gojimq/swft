import SwiftUI

extension View {
    /// Liquid Glass on macOS 26+, a translucent material with a hairline on macOS 15.
    @ViewBuilder
    public func swftGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay(shape.stroke(SwftColor.borderSubtle, lineWidth: 1))
        }
    }

    /// The system's soft scroll-edge fade under floating bars (macOS 26+); no-op on macOS 15.
    @ViewBuilder
    public func scrollEdgeSoftIfAvailable() -> some View {
        if #available(macOS 26, *) {
            scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            self
        }
    }
}

/// Gemini-style circular "jump to latest" button that floats above the composer.
public struct ScrollToBottomButton: View {
    let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.down")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(SwftColor.textPrimary)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(HoverFillStyle(shape: Circle(), pressScale: 0.9))
        .swftGlass(in: Circle(), interactive: true)
        .shadow(color: SwftColor.shadow, radius: 6, y: 2)
        .help("Scroll to latest")
        .accessibilityLabel("Scroll to latest")
    }
}
