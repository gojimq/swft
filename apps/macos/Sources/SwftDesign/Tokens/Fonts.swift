import AppKit
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

    /// Google Sans Flex at an exact variable weight (100–1000).
    /// Defaults match the reference app's text measured at 1x: width 96 and optical size 32 at every point size
    /// (narrower, taller-looking glyphs than the font's defaults).
    public static func flex(_ size: CGFloat, weight: CGFloat = 400, width: CGFloat = 96, opticalSize: CGFloat = 32, rounded: CGFloat = 0) -> Font {
        Font(ctFont(size, weight: weight, width: width, opticalSize: opticalSize, rounded: rounded))
    }

    public static func ctFont(_ size: CGFloat, weight: CGFloat = 400, width: CGFloat = 96, opticalSize: CGFloat = 32, rounded: CGFloat = 0) -> CTFont {
        guard var descriptor = baseDescriptor else {
            return NSFont.systemFont(ofSize: size, weight: nsWeight(weight))
        }
        let axes: [(String, CGFloat)] = [("wght", weight), ("wdth", width), ("opsz", opticalSize), ("ROND", rounded)]
        for (name, value) in axes {
            descriptor = CTFontDescriptorCreateCopyWithVariation(descriptor, tag(name) as CFNumber, value)
        }
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    /// Natural line height (ascent + descent + leading) of a token size, used to derive SwiftUI line spacing.
    public static func lineHeight(_ size: CGFloat) -> CGFloat {
        let font = ctFont(size)
        return CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
    }

    static func nsWeight(_ w: CGFloat) -> NSFont.Weight {
        switch w {
        case ..<250: .light
        case ..<450: .regular
        case ..<550: .medium
        case ..<650: .semibold
        default: .bold
        }
    }
}

/// Type scale, measured against the reference app at the same window size (1pt = 1px).
public enum SwftType {
    public static let greeting = SwftFonts.flex(32.5, weight: 400)
    public static let title = SwftFonts.flex(20, weight: 500)
    /// Assistant markdown headings: crisp hierarchy matching T3 Code (`h1` > `h2` > `h3` > `h4`–`h6`).
    public static let h1 = SwftFonts.flex(19, weight: 640)
    public static let h1Strong = SwftFonts.flex(19, weight: 720)
    public static let heading = SwftFonts.flex(17, weight: 620)
    public static let headingStrong = SwftFonts.flex(17, weight: 700)
    public static let subheading = SwftFonts.flex(15.5, weight: 620)
    public static let subheadingStrong = SwftFonts.flex(15.5, weight: 700)
    public static let minorHeading = SwftFonts.flex(14.5, weight: 620)
    public static let minorHeadingStrong = SwftFonts.flex(14.5, weight: 700)
    public static let headline = SwftFonts.flex(15, weight: 560)
    /// Transcript prose and the user bubble: a calm reading column, a notch under Gemini's 17pt.
    public static let bodySize: CGFloat = 15
    public static let body = SwftFonts.flex(bodySize, weight: 400)
    public static let bodyStrong = SwftFonts.flex(bodySize, weight: 680)
    /// Pitch between transcript lines, ~1.5x the point size.
    public static let bodyLineSpacing: CGFloat = max(0, 22.5 - SwftFonts.lineHeight(bodySize))
    public static let tableHeader = SwftFonts.flex(13.5, weight: 630)
    public static let tableCell = SwftFonts.flex(13.5, weight: 400)
    public static let tableCellStrong = SwftFonts.flex(13.5, weight: 660)
    public static let composer = SwftFonts.flex(17, weight: 400)
    public static let suggestion = SwftFonts.flex(15.5, weight: 400)
    public static let sidebar = SwftFonts.flex(13.75, weight: 400)
    public static let sidebarStrong = SwftFonts.flex(13.75, weight: 560)
    public static let rowTitle = SwftFonts.flex(13.75, weight: 560)
    public static let rowTitleRead = SwftFonts.flex(13.75, weight: 400)
    public static let sectionHeader = SwftFonts.flex(13.5, weight: 400)
    public static let label = SwftFonts.flex(13.75, weight: 400)
    public static let labelStrong = SwftFonts.flex(13.75, weight: 580)
    public static let caption = SwftFonts.flex(12, weight: 420)
    public static let captionStrong = SwftFonts.flex(12, weight: 580)
    public static let micro = SwftFonts.flex(10, weight: 700)
    public static let brand = SwftFonts.flex(19, weight: 500, rounded: 40)
    public static let inlineCode = Font.system(size: 13, design: .monospaced)
    public static let tableInlineCode = Font.system(size: 12, design: .monospaced)
    public static let mono = Font.system(size: 12.5, design: .monospaced)
    public static let monoSmall = Font.system(size: 12, design: .monospaced)
}
