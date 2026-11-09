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

    // Three swept blades leave a triangular opening at the center.
    private static let appStart = CGPoint(x: 124, y: 113)
    private static let appBlade: [(CGPoint, CGPoint, CGPoint)] = [
        (.init(x: 105, y: 101), .init(x: 101, y: 76), .init(x: 111, y: 55)),
        (.init(x: 125, y: 25), .init(x: 159, y: 10), .init(x: 190, y: 24)),
        (.init(x: 193, y: 26), .init(x: 193, y: 28), .init(x: 189, y: 29)),
        (.init(x: 165, y: 35), .init(x: 151, y: 49), .init(x: 152, y: 67)),
        (.init(x: 153, y: 87), .init(x: 148, y: 106), .init(x: 137, y: 113)),
        (.init(x: 132, y: 116), .init(x: 128, y: 116), .init(x: 124, y: 113))
    ]

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

    static func appPath(in rect: NSRect) -> NSBezierPath {
        bladePath(in: rect, start: appStart, curves: appBlade)
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

    static var composerLayers: [String: String] {
        let header = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1024\" height=\"1024\" viewBox=\"-44 -44 344 344\">"
        let blades = svgBlades(start: appStart, curves: appBlade, fill: "#285AB5")
        return ["Rotor.svg": header + blades + "</svg>\n"]
    }
}
