import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import SwftDesign

/// Renders a crisp, high-contrast scannable QR code inside a white quiet-zone card
/// so phone cameras scan reliably in both Light and Dark appearances.
struct QRCodeView: View {
    let value: String
    var size: CGFloat = 156

    var body: some View {
        Group {
            if let cgImage = Self.makeCGImage(from: value) {
                Image(decorative: cgImage, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous)
                    .fill(SwftColor.surfaceMuted)
                    .frame(width: size, height: size)
                    .overlay {
                        Image(systemName: "qrcode")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(SwftColor.textTertiary)
                    }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SwftRadius.m, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: SwftColor.shadow.opacity(0.6), radius: 8, y: 2)
        .accessibilityLabel("Pairing QR code")
    }

    nonisolated static func makeCGImage(from string: String) -> CGImage? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        let context = CIContext()
        return context.createCGImage(outputImage, from: outputImage.extent)
    }
}
