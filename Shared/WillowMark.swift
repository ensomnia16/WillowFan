import AppKit

/// Vector artwork for the compact status item and the app icon.
enum WillowMark {
    private static let blade: [(CGPoint, CGPoint, CGPoint)] = [
        (.init(x: 111, y: 98), .init(x: 113, y: 67), .init(x: 133, y: 42)),
        (.init(x: 146, y: 26), .init(x: 169, y: 26), .init(x: 186, y: 42)),
        (.init(x: 203, y: 57), .init(x: 207, y: 75), .init(x: 192, y: 85)),
        (.init(x: 181, y: 93), .init(x: 168, y: 91), .init(x: 156, y: 101)),
        (.init(x: 146, y: 108), .init(x: 145, y: 120), .init(x: 144, y: 128)),
        (.init(x: 132, y: 130), .init(x: 122, y: 128), .init(x: 117, y: 121))
    ]
    private static let start = CGPoint(x: 117, y: 121)

    private static func rotated(_ p: CGPoint, by index: Int) -> CGPoint {
        let angle = CGFloat(index) * 2 * .pi / 3
        return CGPoint(x: 128 + (p.x - 128) * cos(angle) - (p.y - 128) * sin(angle),
                       y: 128 + (p.x - 128) * sin(angle) + (p.y - 128) * cos(angle))
    }

    private static func bladePath(in rect: NSRect, start: CGPoint,
                                  curves: [(CGPoint, CGPoint, CGPoint)]) -> NSBezierPath {
        let path = NSBezierPath()
        func point(_ p: CGPoint) -> NSPoint {
            NSPoint(x: rect.minX + p.x * rect.width / 256, y: rect.maxY - p.y * rect.height / 256)
        }
        for index in 0..<3 {
            path.move(to: point(rotated(start, by: index)))
            for (a, b, end) in curves {
                path.curve(to: point(rotated(end, by: index)),
                           controlPoint1: point(rotated(a, by: index)), controlPoint2: point(rotated(b, by: index)))
            }
            path.close()
        }
        return path
    }

    static func image(size: CGFloat, template: Bool, color: NSColor = .black) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            (template ? NSColor.black : color).setFill()
            let artwork = rect.insetBy(dx: -size * 0.065, dy: -size * 0.065)
            bladePath(in: artwork, start: start, curves: blade).fill()
            NSBezierPath(ovalIn: artwork.insetBy(dx: artwork.width * 106 / 256, dy: artwork.height * 106 / 256)).fill()
            return true
        }
        image.isTemplate = template
        image.accessibilityDescription = "柳风风扇"
        return image
    }

    private static func svgBlades(start: CGPoint, curves: [(CGPoint, CGPoint, CGPoint)], fill: String) -> String {
        func coordinate(_ p: CGPoint) -> String { String(format: "%.3f %.3f", p.x, p.y) }
        return (0..<3).map { index in
            let first = coordinate(rotated(start, by: index))
            let tail = curves.map { a, b, end in
                "C" + [a, b, end].map { coordinate(rotated($0, by: index)) }.joined(separator: " ")
            }.joined(separator: " ")
            return "<path d=\"M\(first) \(tail) Z\" fill=\"\(fill)\"/>"
        }.joined()
    }

    static var svg: String {
        let blades = svgBlades(start: start, curves: blade, fill: "#000000")
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 256 256\" width=\"256\" height=\"256\">\(blades)<circle cx=\"128\" cy=\"128\" r=\"22\"/></svg>\n"
    }

}

/// The cloud and gust use the same outlines in Icon Composer and legacy builds.
enum WillowAppMark {
    private static let sourceOrigin: CGFloat = 58
    private static let sourceSize: CGFloat = 1138
    private static let ink: UInt32 = 0x126C73
    private static let cloudTint: UInt32 = 0xDFEFE7
    private static let tileTint: UInt32 = 0xF8F0DD
    private typealias Point = (CGFloat, CGFloat)

    private struct Artwork {
        let color: UInt32
        let path: CGPath
    }

    private static func curve(_ start: Point, _ segments: [(Point, Point, Point)],
                              closed: Bool = false) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: start.0, y: start.1))
        for (a, b, end) in segments {
            path.addCurve(to: CGPoint(x: end.0, y: end.1),
                          control1: CGPoint(x: a.0, y: a.1),
                          control2: CGPoint(x: b.0, y: b.1))
        }
        if closed { path.closeSubpath() }
        return path
    }

    private static func line(_ path: CGPath, width: CGFloat) -> Artwork {
        Artwork(color: ink, path: path.copy(strokingWithWidth: width, lineCap: .round,
                                          lineJoin: .round, miterLimit: 4))
    }

    private static let cloudOutline = curve((246, 457), [
        ((248, 396), (299, 354), (361, 354)),
        ((401, 354), (439, 372), (460, 400)),
        ((511, 376), (565, 414), (566, 473)),
        ((621, 476), (666, 519), (667, 579)),
        ((668, 607), (656, 632), (642, 650)),
        ((650, 700), (611, 770), (556, 785)),
        ((523, 795), (492, 794), (468, 781)),
        ((427, 818), (353, 823), (303, 769)),
        ((257, 795), (206, 789), (175, 755)),
        ((149, 728), (142, 688), (159, 650)),
        ((128, 634), (117, 600), (124, 563)),
        ((136, 504), (176, 457), (246, 457))
    ], closed: true)

    private static let cloud: [Artwork] = {
        let mouth = CGPath(ellipseIn: CGRect(x: 504, y: 648, width: 39, height: 72), transform: nil)
        return [
            Artwork(color: cloudTint, path: cloudOutline),
            line(cloudOutline, width: 15),
            line(curve((359, 506), [
                ((402, 483), (428, 531), (452, 546)),
                ((469, 557), (482, 549), (483, 532))
            ]), width: 11),
            line(curve((382, 567), [((405, 550), (436, 549), (458, 568))]), width: 9),
            line(curve((514, 537), [
                ((530, 570), (553, 533), (574, 517)),
                ((580, 512), (587, 510), (594, 511))
            ]), width: 11),
            line(curve((537, 568), [((556, 553), (576, 553), (593, 563))]), width: 9),
            line(curve((519, 553), [
                ((522, 574), (541, 581), (536, 598)),
                ((531, 615), (503, 614), (486, 602))
            ]), width: 11),
            line(curve((439, 596), [
                ((480, 622), (475, 687), (449, 708)),
                ((438, 717), (427, 721), (415, 724))
            ]), width: 12),
            line(curve((579, 598), [((561, 616), (553, 647), (571, 671))]), width: 10),
            Artwork(color: tileTint, path: mouth),
            line(mouth, width: 12)
        ]
    }()

    private static let gust = [
        line(curve((546, 676), [
            ((686, 687), (835, 673), (921, 635)),
            ((972, 613), (1014, 578), (998, 541)),
            ((985, 509), (947, 502), (915, 525))
        ]), width: 13),
        line(curve((547, 691), [
            ((759, 722), (984, 736), (1080, 646)),
            ((1142, 588), (1120, 506), (1051, 464)),
            ((984, 423), (892, 440), (851, 500)),
            ((819, 548), (850, 599), (914, 598))
        ]), width: 15),
        line(curve((546, 703), [
            ((680, 730), (790, 769), (849, 806))
        ]), width: 8),
        line(curve((740, 716), [
            ((879, 721), (1041, 743), (1041, 822)),
            ((1041, 868), (990, 900), (931, 900)),
            ((890, 900), (855, 874), (860, 837)),
            ((865, 806), (900, 781), (936, 788)),
            ((983, 796), (980, 837), (940, 842))
        ]), width: 15)
    ]

    static func draw(in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: rect.width / sourceSize, y: -rect.height / sourceSize)
        context.translateBy(x: -sourceOrigin, y: -sourceOrigin)
        for art in cloud + gust {
            let color = NSColor(srgbRed: CGFloat((art.color >> 16) & 255) / 255,
                                green: CGFloat((art.color >> 8) & 255) / 255,
                                blue: CGFloat(art.color & 255) / 255, alpha: 1)
            context.setFillColor(color.cgColor)
            context.addPath(art.path)
            context.fillPath()
        }
        context.restoreGState()
    }

    private static func svg(_ art: [Artwork]) -> String {
        func coordinate(_ p: CGPoint) -> String { String(format: "%.3f %.3f", p.x, p.y) }
        let paths = art.map { layer in
            var components: [String] = []
            layer.path.applyWithBlock { pointer in
                let element = pointer.pointee
                let p = element.points
                switch element.type {
                case .moveToPoint: components.append("M" + coordinate(p[0]))
                case .addLineToPoint: components.append("L" + coordinate(p[0]))
                case .addQuadCurveToPoint: components.append("Q" + coordinate(p[0]) + " " + coordinate(p[1]))
                case .addCurveToPoint:
                    components.append("C" + coordinate(p[0]) + " " + coordinate(p[1]) + " " + coordinate(p[2]))
                case .closeSubpath: components.append("Z")
                @unknown default: break
                }
            }
            return "<path fill=\"\(String(format: "#%06X", layer.color))\" d=\"\(components.joined(separator: " "))\"/>"
        }.joined()
        let viewBox = "\(sourceOrigin) \(sourceOrigin) \(sourceSize) \(sourceSize)"
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1024\" height=\"1024\" viewBox=\"\(viewBox)\">\(paths)</svg>\n"
    }

    static var composerLayers: [(name: String, svg: String)] {
        [("Cloud.svg", svg(cloud)), ("Gust.svg", svg(gust))]
    }
}
