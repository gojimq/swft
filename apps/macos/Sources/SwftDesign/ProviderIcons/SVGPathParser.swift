import CoreGraphics
import Foundation
import SwiftUI

/// Lightweight SVG path data (`d="..."`) and basic `<svg>` element parser for provider marks.
/// Supports all SVG 1.1 / SVG 2 path commands (`M/m`, `L/l`, `H/h`, `V/v`, `C/c`, `S/s`, `Q/q`, `T/t`, `A/a`, `Z/z`)
/// including implicit repeated commands, decimal-delimited numbers, and compressed arc flags.
public enum SVGPathParser {
    public struct SubpathData: Sendable {
        public let path: Path
        public let evenOdd: Bool

        public init(path: Path, evenOdd: Bool = false) {
            self.path = path
            self.evenOdd = evenOdd
        }
    }

    public struct ParsedSVG: Sendable {
        public let viewBox: CGRect
        public let paths: [SubpathData]

        public init(viewBox: CGRect, paths: [SubpathData]) {
            self.viewBox = viewBox
            self.paths = paths
        }
    }

    /// Parses an SVG `d` path string into an immutable SwiftUI `Path` in viewBox coordinates.
    public static func parsePath(_ d: String) -> Path {
        Path(parseCGPath(d))
    }

    private static func parseCGPath(_ d: String) -> CGPath {
        let path = CGMutablePath()
        var scanner = Scanner(d)
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastCommand: UInt8 = 0
        var lastCubicControl: CGPoint?
        var lastQuadControl: CGPoint?
        var command: UInt8 = 0

        while true {
            scanner.skipSeparators()
            guard !scanner.isAtEnd else { break }

            if let nextCmd = scanner.peekCommand() {
                scanner.advance()
                command = nextCmd
            } else if command == 0 {
                break
            }

            switch command {
            case UInt8(ascii: "M"), UInt8(ascii: "m"):
                let relative = command == UInt8(ascii: "m")
                guard let x = scanner.readNumber(), let y = scanner.readNumber() else {
                    return path.copy() ?? path
                }
                let target = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.move(to: target)
                current = target
                subpathStart = target
                lastCubicControl = nil
                lastQuadControl = nil
                lastCommand = command
                // Per SVG spec, subsequent coordinate pairs after M/m are implicit L/l.
                command = relative ? UInt8(ascii: "l") : UInt8(ascii: "L")

            case UInt8(ascii: "L"), UInt8(ascii: "l"):
                let relative = command == UInt8(ascii: "l")
                guard let x = scanner.readNumber(), let y = scanner.readNumber() else {
                    return path.copy() ?? path
                }
                let target = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.addLine(to: target)
                current = target
                lastCubicControl = nil
                lastQuadControl = nil
                lastCommand = command

            case UInt8(ascii: "H"), UInt8(ascii: "h"):
                let relative = command == UInt8(ascii: "h")
                guard let x = scanner.readNumber() else { return path.copy() ?? path }
                let target = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: target)
                current = target
                lastCubicControl = nil
                lastQuadControl = nil
                lastCommand = command

            case UInt8(ascii: "V"), UInt8(ascii: "v"):
                let relative = command == UInt8(ascii: "v")
                guard let y = scanner.readNumber() else { return path.copy() ?? path }
                let target = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: target)
                current = target
                lastCubicControl = nil
                lastQuadControl = nil
                lastCommand = command

            case UInt8(ascii: "C"), UInt8(ascii: "c"):
                let relative = command == UInt8(ascii: "c")
                guard let x1 = scanner.readNumber(), let y1 = scanner.readNumber(),
                      let x2 = scanner.readNumber(), let y2 = scanner.readNumber(),
                      let x = scanner.readNumber(), let y = scanner.readNumber()
                else { return path.copy() ?? path }
                let base = relative ? current : .zero
                let c1 = CGPoint(x: base.x + x1, y: base.y + y1)
                let c2 = CGPoint(x: base.x + x2, y: base.y + y2)
                let end = CGPoint(x: base.x + x, y: base.y + y)
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end
                lastCubicControl = c2
                lastQuadControl = nil
                lastCommand = command

            case UInt8(ascii: "S"), UInt8(ascii: "s"):
                let relative = command == UInt8(ascii: "s")
                guard let x2 = scanner.readNumber(), let y2 = scanner.readNumber(),
                      let x = scanner.readNumber(), let y = scanner.readNumber()
                else { return path.copy() ?? path }
                let c1: CGPoint
                if let prev = lastCubicControl, isCubic(lastCommand) {
                    c1 = CGPoint(x: 2 * current.x - prev.x, y: 2 * current.y - prev.y)
                } else {
                    c1 = current
                }
                let base = relative ? current : .zero
                let c2 = CGPoint(x: base.x + x2, y: base.y + y2)
                let end = CGPoint(x: base.x + x, y: base.y + y)
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end
                lastCubicControl = c2
                lastQuadControl = nil
                lastCommand = command

            case UInt8(ascii: "Q"), UInt8(ascii: "q"):
                let relative = command == UInt8(ascii: "q")
                guard let x1 = scanner.readNumber(), let y1 = scanner.readNumber(),
                      let x = scanner.readNumber(), let y = scanner.readNumber()
                else { return path.copy() ?? path }
                let base = relative ? current : .zero
                let c = CGPoint(x: base.x + x1, y: base.y + y1)
                let end = CGPoint(x: base.x + x, y: base.y + y)
                path.addQuadCurve(to: end, control: c)
                current = end
                lastQuadControl = c
                lastCubicControl = nil
                lastCommand = command

            case UInt8(ascii: "T"), UInt8(ascii: "t"):
                let relative = command == UInt8(ascii: "t")
                guard let x = scanner.readNumber(), let y = scanner.readNumber() else {
                    return path.copy() ?? path
                }
                let c: CGPoint
                if let prev = lastQuadControl, isQuadratic(lastCommand) {
                    c = CGPoint(x: 2 * current.x - prev.x, y: 2 * current.y - prev.y)
                } else {
                    c = current
                }
                let base = relative ? current : .zero
                let end = CGPoint(x: base.x + x, y: base.y + y)
                path.addQuadCurve(to: end, control: c)
                current = end
                lastQuadControl = c
                lastCubicControl = nil
                lastCommand = command

            case UInt8(ascii: "A"), UInt8(ascii: "a"):
                let relative = command == UInt8(ascii: "a")
                guard let rx = scanner.readNumber(), let ry = scanner.readNumber(),
                      let rotation = scanner.readNumber(),
                      let largeArc = scanner.readFlag(),
                      let sweep = scanner.readFlag(),
                      let x = scanner.readNumber(), let y = scanner.readNumber()
                else { return path.copy() ?? path }
                let end = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                addArc(
                    to: path,
                    from: current,
                    to: end,
                    rx: rx,
                    ry: ry,
                    xAxisRotationDegrees: rotation,
                    largeArc: largeArc,
                    sweep: sweep
                )
                current = end
                lastCubicControl = nil
                lastQuadControl = nil
                lastCommand = command

            case UInt8(ascii: "Z"), UInt8(ascii: "z"):
                path.closeSubpath()
                current = subpathStart
                lastCubicControl = nil
                lastQuadControl = nil
                lastCommand = command
                command = 0

            default:
                return path.copy() ?? path
            }
        }

        return path.copy() ?? path
    }

    /// Computes an aspect-fit (`xMidYMid meet`) transform mapping `viewBox` into `rect`.
    public static func fitTransform(viewBox: CGRect, into rect: CGRect) -> CGAffineTransform {
        guard viewBox.width > 0, viewBox.height > 0, rect.width > 0, rect.height > 0 else {
            return .identity
        }
        let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
        let scaledW = viewBox.width * scale
        let scaledH = viewBox.height * scale
        let tx = rect.minX + (rect.width - scaledW) / 2 - viewBox.minX * scale
        let ty = rect.minY + (rect.height - scaledH) / 2 - viewBox.minY * scale
        return CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: tx, ty: ty)
    }

    /// Transforms a `Path` from `viewBox` into `rect` preserving aspect ratio.
    public static func fittedPath(_ path: Path, viewBox: CGRect, in rect: CGRect) -> Path {
        path.applying(fitTransform(viewBox: viewBox, into: rect))
    }

    /// Parses a standalone monochrome `<svg>` document (such as an ACP registry CDN icon) into vector paths.
    public static func parseSVGDocument(_ data: Data) -> ParsedSVG? {
        let delegate = SVGXMLCollector()
        let xml = XMLParser(data: data)
        xml.delegate = delegate
        xml.shouldProcessNamespaces = false
        guard xml.parse(), !delegate.paths.isEmpty else { return nil }
        let viewBox: CGRect
        if let declared = delegate.viewBox, declared.width > 0, declared.height > 0 {
            viewBox = declared
        } else {
            let union = delegate.paths.reduce(CGRect.null) { $0.union($1.path.boundingRect) }
            guard !union.isNull, union.width > 0, union.height > 0 else { return nil }
            viewBox = union
        }
        return ParsedSVG(viewBox: viewBox, paths: delegate.paths)
    }

    // MARK: - Private helpers

    private static func isCubic(_ cmd: UInt8) -> Bool {
        cmd == UInt8(ascii: "C") || cmd == UInt8(ascii: "c") || cmd == UInt8(ascii: "S") || cmd == UInt8(ascii: "s")
    }

    private static func isQuadratic(_ cmd: UInt8) -> Bool {
        cmd == UInt8(ascii: "Q") || cmd == UInt8(ascii: "q") || cmd == UInt8(ascii: "T") || cmd == UInt8(ascii: "t")
    }

    /// Converts an SVG elliptical arc to cubic Bezier segments per W3C SVG 1.1 Appendix F.6.5–F.6.6.
    private static func addArc(
        to path: CGMutablePath,
        from start: CGPoint,
        to end: CGPoint,
        rx rawRx: CGFloat,
        ry rawRy: CGFloat,
        xAxisRotationDegrees: CGFloat,
        largeArc: Bool,
        sweep: Bool
    ) {
        if abs(start.x - end.x) < 1e-9, abs(start.y - end.y) < 1e-9 { return }
        var rx = abs(rawRx)
        var ry = abs(rawRy)
        if rx < 1e-9 || ry < 1e-9 {
            path.addLine(to: end)
            return
        }

        let phi = xAxisRotationDegrees * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        let dx2 = (start.x - end.x) / 2
        let dy2 = (start.y - end.y) / 2
        let x1p = cosPhi * dx2 + sinPhi * dy2
        let y1p = -sinPhi * dx2 + cosPhi * dy2

        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let root = sqrt(lambda)
            rx *= root
            ry *= root
        }

        let rx2 = rx * rx
        let ry2 = ry * ry
        let x1p2 = x1p * x1p
        let y1p2 = y1p * y1p
        let num = max(0, rx2 * ry2 - rx2 * y1p2 - ry2 * x1p2)
        let den = rx2 * y1p2 + ry2 * x1p2
        let coef = (largeArc == sweep ? -1.0 : 1.0) * (den > 0 ? sqrt(num / den) : 0)
        let cxp = coef * (rx * y1p / ry)
        let cyp = coef * (-ry * x1p / rx)

        let midX = (start.x + end.x) / 2
        let midY = (start.y + end.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        }

        let ux = (x1p - cxp) / rx
        let uy = (y1p - cyp) / ry
        let vx = (-x1p - cxp) / rx
        let vy = (-y1p - cyp) / ry

        let theta1 = angle(1, 0, ux, uy)
        var dTheta = angle(ux, uy, vx, vy)
        if !sweep, dTheta > 0 { dTheta -= 2 * .pi }
        if sweep, dTheta < 0 { dTheta += 2 * .pi }

        let segmentCount = max(1, Int(ceil(abs(dTheta) / (.pi / 2))))
        let delta = dTheta / CGFloat(segmentCount)
        let alpha = (4.0 / 3.0) * tan(delta / 4.0)

        func map(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let px = rx * x + cxp
            let py = ry * y + cyp
            return CGPoint(
                x: cosPhi * px - sinPhi * py + midX,
                y: sinPhi * px + cosPhi * py + midY
            )
        }

        for i in 0..<segmentCount {
            let t1 = theta1 + CGFloat(i) * delta
            let t2 = t1 + delta
            let cos1 = cos(t1), sin1 = sin(t1)
            let cos2 = cos(t2), sin2 = sin(t2)
            let c1 = map(cos1 - alpha * sin1, sin1 + alpha * cos1)
            let c2 = map(cos2 + alpha * sin2, sin2 - alpha * cos2)
            let p2 = i == segmentCount - 1 ? end : map(cos2, sin2)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
    }

    private struct Scanner {
        let bytes: [UInt8]
        var index = 0

        init(_ string: String) {
            self.bytes = Array(string.utf8)
        }

        var isAtEnd: Bool { index >= bytes.count }

        mutating func advance() { index += 1 }

        mutating func skipSeparators() {
            while index < bytes.count {
                let b = bytes[index]
                if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D || b == UInt8(ascii: ",") {
                    index += 1
                } else {
                    break
                }
            }
        }

        func peekCommand() -> UInt8? {
            guard index < bytes.count else { return nil }
            let b = bytes[index]
            switch b {
            case UInt8(ascii: "M"), UInt8(ascii: "m"),
                 UInt8(ascii: "L"), UInt8(ascii: "l"),
                 UInt8(ascii: "H"), UInt8(ascii: "h"),
                 UInt8(ascii: "V"), UInt8(ascii: "v"),
                 UInt8(ascii: "C"), UInt8(ascii: "c"),
                 UInt8(ascii: "S"), UInt8(ascii: "s"),
                 UInt8(ascii: "Q"), UInt8(ascii: "q"),
                 UInt8(ascii: "T"), UInt8(ascii: "t"),
                 UInt8(ascii: "A"), UInt8(ascii: "a"),
                 UInt8(ascii: "Z"), UInt8(ascii: "z"):
                return b
            default:
                return nil
            }
        }

        mutating func readFlag() -> Bool? {
            skipSeparators()
            guard index < bytes.count else { return nil }
            let b = bytes[index]
            if b == UInt8(ascii: "0") {
                index += 1
                return false
            }
            if b == UInt8(ascii: "1") {
                index += 1
                return true
            }
            return nil
        }

        mutating func readNumber() -> CGFloat? {
            skipSeparators()
            guard index < bytes.count else { return nil }
            let start = index
            if bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") {
                index += 1
            }
            var hasDigits = false
            while index < bytes.count, bytes[index] >= UInt8(ascii: "0"), bytes[index] <= UInt8(ascii: "9") {
                hasDigits = true
                index += 1
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
                index += 1
                while index < bytes.count, bytes[index] >= UInt8(ascii: "0"), bytes[index] <= UInt8(ascii: "9") {
                    hasDigits = true
                    index += 1
                }
            }
            guard hasDigits else {
                index = start
                return nil
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
                let expStart = index
                index += 1
                if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") {
                    index += 1
                }
                var expDigits = false
                while index < bytes.count, bytes[index] >= UInt8(ascii: "0"), bytes[index] <= UInt8(ascii: "9") {
                    expDigits = true
                    index += 1
                }
                if !expDigits {
                    index = expStart
                }
            }
            guard let text = String(bytes: bytes[start..<index], encoding: .ascii),
                  let value = Double(text)
            else { return nil }
            return CGFloat(value)
        }
    }
}

/// Collects basic geometric primitives from an external monochrome SVG document.
private final class SVGXMLCollector: NSObject, XMLParserDelegate {
    var viewBox: CGRect?
    var paths: [SVGPathParser.SubpathData] = []
    private var ignoredDepth = 0

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes: [String: String] = [:]
    ) {
        let tag = elementName.lowercased()
        if ignoredDepth > 0 {
            ignoredDepth += 1
            return
        }
        if tag == "defs" || tag == "clippath" || tag == "mask" || tag == "title" || tag == "desc" || tag == "metadata" {
            ignoredDepth = 1
            return
        }

        if tag == "svg" {
            if let vb = attributes["viewBox"] ?? attributes["viewbox"] {
                let nums = parseNumbers(vb)
                if nums.count == 4, nums[2] > 0, nums[3] > 0 {
                    viewBox = CGRect(x: nums[0], y: nums[1], width: nums[2], height: nums[3])
                }
            } else if let w = parseDimension(attributes["width"]), let h = parseDimension(attributes["height"]), w > 0, h > 0 {
                viewBox = CGRect(x: 0, y: 0, width: w, height: h)
            }
            return
        }

        if let fill = attributes["fill"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           fill == "none"
        {
            // Stroke-only paths: convert stroke to outline if strokeWidth is available.
            if let stroke = attributes["stroke"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               stroke != "none"
            {
                let width = parseDimension(attributes["stroke-width"]) ?? 1.5
                if let raw = geometricPath(tag: tag, attributes: attributes) {
                    let stroked = raw.copy(
                        strokingWithWidth: width,
                        lineCap: .round,
                        lineJoin: .round,
                        miterLimit: 4
                    )
                    paths.append(.init(path: Path(stroked), evenOdd: false))
                }
            }
            return
        }

        if let raw = geometricPath(tag: tag, attributes: attributes) {
            let evenOdd = attributes["fill-rule"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "evenodd"
            paths.append(.init(path: Path(raw), evenOdd: evenOdd))
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if ignoredDepth > 0 {
            ignoredDepth -= 1
        }
    }

    private func geometricPath(tag: String, attributes: [String: String]) -> CGPath? {
        switch tag {
        case "path":
            guard let d = attributes["d"], !d.isEmpty else { return nil }
            let parsed = SVGPathParser.parsePath(d).cgPath
            return parsed.isEmpty ? nil : parsed

        case "rect":
            let x = parseDimension(attributes["x"]) ?? 0
            let y = parseDimension(attributes["y"]) ?? 0
            guard let w = parseDimension(attributes["width"]),
                  let h = parseDimension(attributes["height"]),
                  w > 0, h > 0
            else { return nil }
            let rx = min(w / 2, parseDimension(attributes["rx"]) ?? parseDimension(attributes["ry"]) ?? 0)
            let ry = min(h / 2, parseDimension(attributes["ry"]) ?? parseDimension(attributes["rx"]) ?? 0)
            let rect = CGRect(x: x, y: y, width: w, height: h)
            if rx > 0 || ry > 0 {
                return CGPath(roundedRect: rect, cornerWidth: rx, cornerHeight: ry, transform: nil)
            }
            return CGPath(rect: rect, transform: nil)

        case "circle":
            let cx = parseDimension(attributes["cx"]) ?? 0
            let cy = parseDimension(attributes["cy"]) ?? 0
            guard let r = parseDimension(attributes["r"]), r > 0 else { return nil }
            return CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2), transform: nil)

        case "ellipse":
            let cx = parseDimension(attributes["cx"]) ?? 0
            let cy = parseDimension(attributes["cy"]) ?? 0
            guard let rx = parseDimension(attributes["rx"]),
                  let ry = parseDimension(attributes["ry"]),
                  rx > 0, ry > 0
            else { return nil }
            return CGPath(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2), transform: nil)

        case "polygon", "polyline":
            guard let pts = attributes["points"] else { return nil }
            let nums = parseNumbers(pts)
            guard nums.count >= 4 else { return nil }
            let p = CGMutablePath()
            p.move(to: CGPoint(x: nums[0], y: nums[1]))
            var i = 2
            while i + 1 < nums.count {
                p.addLine(to: CGPoint(x: nums[i], y: nums[i + 1]))
                i += 2
            }
            if tag == "polygon" { p.closeSubpath() }
            return p.copy()

        case "line":
            let x1 = parseDimension(attributes["x1"]) ?? 0
            let y1 = parseDimension(attributes["y1"]) ?? 0
            let x2 = parseDimension(attributes["x2"]) ?? 0
            let y2 = parseDimension(attributes["y2"]) ?? 0
            let p = CGMutablePath()
            p.move(to: CGPoint(x: x1, y: y1))
            p.addLine(to: CGPoint(x: x2, y: y2))
            return p.copy()

        default:
            return nil
        }
    }

    private func parseNumbers(_ raw: String) -> [CGFloat] {
        raw.replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .compactMap { Double($0).map { CGFloat($0) } }
    }

    private func parseDimension(_ raw: String?) -> CGFloat? {
        guard let raw else { return nil }
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "px", with: "")
        return Double(cleaned).map { CGFloat($0) }
    }
}
