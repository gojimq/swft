import CoreText
import Foundation
import SwiftUI

/// Bundled Google Sans Flex (SIL OFL 1.1, see Resources/Fonts/OFL.txt) registered at runtime.
/// Every token falls back to the system font when registration fails.
public enum SwftFonts {
    /// Registers the bundled font once. Safe to call repeatedly; returns whether the font is usable.
    @discardableResult
    public static func register() -> Bool { baseDescriptor != nil }

    nonisolated(unsafe) static let baseDescriptor: CTFontDescriptor? = {
        guard let url = fontURL else { return nil }
        var error: Unmanaged<CFError>?
        let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        // "Already registered" is fine (e.g. a second window or a test host).
        if !ok, let err = error?.takeRetainedValue(), CFErrorGetCode(err) != CTFontManagerError.alreadyRegistered.rawValue {
            return nil
        }
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else { return nil }
        return descriptors.first
    }()

    /// The resources bundle lives next to the executable under `swift run`, and in Contents/Resources inside Swft.app.
    /// SwiftPM's `Bundle.module` only probes the former, so look in the app bundle first.
    static var resourceBundle: Bundle? {
        let name = "Swft_SwftDesign.bundle"
        let candidates = [Bundle.main.resourceURL, Bundle.main.bundleURL, Bundle.main.executableURL?.deletingLastPathComponent()]
        for base in candidates.compactMap({ $0 }) {
            if let bundle = Bundle(url: base.appendingPathComponent(name)) { return bundle }
        }
        return nil
    }

    static var fontURL: URL? {
        let bundle = resourceBundle
        return bundle?.url(forResource: "GoogleSansFlex", withExtension: "ttf")
            ?? bundle?.url(forResource: "GoogleSansFlex", withExtension: "ttf", subdirectory: "Fonts")
    }

    private static func tag(_ s: String) -> Int {
        s.unicodeScalars.reduce(0) { ($0 << 8) | Int($1.value) }
    }

    /// Google Sans Flex at an exact variable weight (100–1000) with optical size matched to the point size.
    public static func flex(_ size: CGFloat, weight: CGFloat = 400, rounded: CGFloat = 0) -> Font {
        guard var descriptor = baseDescriptor else {
            return .system(size: size, weight: systemWeight(weight))
        }
        let axes: [(String, CGFloat)] = [("wght", weight), ("opsz", min(max(size, 6), 144)), ("ROND", rounded)]
        for (name, value) in axes {
            descriptor = CTFontDescriptorCreateCopyWithVariation(descriptor, tag(name) as CFNumber, value)
        }
        return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
    }

    static func systemWeight(_ w: CGFloat) -> Font.Weight {
        switch w {
        case ..<250: .light
        case ..<450: .regular
        case ..<550: .medium
        case ..<650: .semibold
        default: .bold
        }
    }
}

/// Type scale. Sizes follow the reference: quiet 13–15pt UI text, a large light greeting.
public enum SwftType {
    public static let greeting = SwftFonts.flex(30, weight: 420)
    public static let title = SwftFonts.flex(20, weight: 500)
    public static let headline = SwftFonts.flex(15, weight: 560)
    public static let body = SwftFonts.flex(15, weight: 400)
    public static let bodyStrong = SwftFonts.flex(15, weight: 560)
    public static let composer = SwftFonts.flex(16, weight: 400)
    public static let sidebar = SwftFonts.flex(13.5, weight: 420)
    public static let sidebarStrong = SwftFonts.flex(13.5, weight: 600)
    public static let rowTitle = SwftFonts.flex(13.5, weight: 600)
    public static let rowTitleRead = SwftFonts.flex(13.5, weight: 480)
    public static let label = SwftFonts.flex(13, weight: 450)
    public static let labelStrong = SwftFonts.flex(13, weight: 580)
    public static let caption = SwftFonts.flex(12, weight: 420)
    public static let captionStrong = SwftFonts.flex(12, weight: 580)
    public static let micro = SwftFonts.flex(10, weight: 700)
    public static let brand = SwftFonts.flex(19, weight: 560, rounded: 40)
    public static let mono = Font.system(size: 12.5, design: .monospaced)
    public static let monoSmall = Font.system(size: 11.5, design: .monospaced)
}
