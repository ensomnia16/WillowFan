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

/// The three open curves are outlined before export so Icon Composer and
/// the legacy rasterizer use the same filled shapes.
enum WillowAppMark {
    private static let canvasSize: CGFloat = 1024
    private static let contours: [(CGPoint, CGPoint, [(CGPoint, CGPoint, CGPoint)])] = [
        (.init(x: 296, y: 429), .init(x: 528, y: 429), [
            (.init(x: 598, y: 429), .init(x: 639, y: 387), .init(x: 628, y: 338)),
            (.init(x: 620, y: 301), .init(x: 582, y: 287), .init(x: 548, y: 298))
        ]),
        (.init(x: 243, y: 515), .init(x: 688, y: 515), [
            (.init(x: 743, y: 515), .init(x: 777, y: 480), .init(x: 765, y: 438)),
            (.init(x: 756, y: 409), .init(x: 728, y: 394), .init(x: 700, y: 399))
        ]),
        (.init(x: 332, y: 602), .init(x: 555, y: 602), [
            (.init(x: 625, y: 602), .init(x: 661, y: 644), .init(x: 650, y: 691)),
            (.init(x: 641, y: 731), .init(x: 595, y: 744), .init(x: 564, y: 728))
        ])
    ]

    private static let outlines = contours.map { start, lineEnd, curves in
        let stroke = CGMutablePath()
        stroke.move(to: start)
        stroke.addLine(to: lineEnd)
        for (a, b, end) in curves { stroke.addCurve(to: end, control1: a, control2: b) }
        return stroke.copy(strokingWithWidth: 45, lineCap: .round, lineJoin: .round, miterLimit: 4)
    }

    static func draw(in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: rect.width / canvasSize, y: -rect.height / canvasSize)
        context.setFillColor(NSColor(srgbRed: 246 / 255, green: 239 / 255, blue: 222 / 255, alpha: 1).cgColor)
        for outline in outlines {
            context.addPath(outline)
            context.fillPath()
        }
        context.restoreGState()
    }

    static var composerSVG: String {
        func coordinate(_ p: CGPoint) -> String { String(format: "%.3f %.3f", p.x, p.y) }
        let elements = outlines.map { outline in
            var components: [String] = []
            outline.applyWithBlock { pointer in
                let element = pointer.pointee
                let points = element.points
                switch element.type {
                case .moveToPoint: components.append("M" + coordinate(points[0]))
                case .addLineToPoint: components.append("L" + coordinate(points[0]))
                case .addQuadCurveToPoint:
                    components.append("Q" + coordinate(points[0]) + " " + coordinate(points[1]))
                case .addCurveToPoint:
                    components.append("C" + coordinate(points[0]) + " " + coordinate(points[1]) + " " + coordinate(points[2]))
                case .closeSubpath: components.append("Z")
                @unknown default: break
                }
            }
            return "<path fill=\"#F6EFDE\" d=\"\(components.joined(separator: " "))\"/>"
        }.joined()
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1024\" height=\"1024\" viewBox=\"0 0 1024 1024\">\(elements)</svg>\n"
    }
}
