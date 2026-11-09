import AppKit

/// A three-blade axial fan: filled rotor and a separate outer housing.
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

    static func path(in rect: NSRect, layer: Int = 0) -> NSBezierPath {
        let path = NSBezierPath()
        func point(_ p: CGPoint) -> NSPoint {
            NSPoint(x: rect.minX + p.x * rect.width / 256, y: rect.maxY - p.y * rect.height / 256)
        }
        func centeredOval(_ radius: CGFloat) -> NSRect {
            rect.insetBy(dx: rect.width * (128 - radius) / 256, dy: rect.height * (128 - radius) / 256)
        }
        if layer == 1 {
            path.windingRule = .evenOdd
            path.appendOval(in: centeredOval(116))
            path.appendOval(in: centeredOval(107))
            return path
        }
        if layer == 2 {
            path.appendOval(in: centeredOval(22))
            return path
        }
        for index in 0..<3 {
            path.move(to: point(rotated(start, by: index)))
            for (a, b, end) in blade {
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
            path(in: artwork).fill()
            path(in: artwork, layer: 2).fill()
            return true
        }
        image.isTemplate = template
        image.accessibilityDescription = "柳风风扇"
        return image
    }

    private static func rotorElements(fill: String, hubCap: String? = nil) -> String {
        func coordinate(_ p: CGPoint) -> String { String(format: "%.3f %.3f", p.x, p.y) }
        let paths = (0..<3).map { index in
            let first = coordinate(rotated(start, by: index))
            let tail = blade.map { a, b, end in
                "C" + [a, b, end].map { coordinate(rotated($0, by: index)) }.joined(separator: " ")
            }.joined(separator: " ")
            return "<path d=\"M\(first) \(tail) Z\" fill=\"\(fill)\"/>"
        }.joined()
        let hub = "<circle cx=\"128\" cy=\"128\" r=\"22\" fill=\"\(fill)\"/>"
        let cap = hubCap.map { "<circle cx=\"128\" cy=\"128\" r=\"13\" fill=\"\($0)\"/>" } ?? ""
        return paths + hub + cap
    }

    static var svg: String {
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 256 256\" width=\"256\" height=\"256\">\(rotorElements(fill: "#000000"))</svg>\n"
    }

    static var composerLayers: [String: String] {
        let header = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1024\" height=\"1024\" viewBox=\"-28 -28 312 312\">"
        return [
            "Rotor.svg": header + rotorElements(fill: "#E8F8F5", hubCap: "#83C8C4") + "</svg>\n",
            "Housing.svg": header + "<circle cx=\"128\" cy=\"128\" r=\"111.5\" fill=\"none\" stroke=\"#67ABA8\" stroke-width=\"9\"/></svg>\n"
        ]
    }
}
