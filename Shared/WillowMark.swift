import AppKit

/// Approved concept A, “回叶”. Original 256 × 256 SVG coordinates.
/// The menu image, app icon and SVG export share these exact contours.
enum WillowMark {
    private enum Segment {
        case move(CGFloat, CGFloat)
        case curve(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
        case close
    }
    private static let contours: [[Segment]] = [
        [.move(209, 38), .curve(120, 15, 41, 65, 36, 143),
         .curve(33, 194, 65, 226, 111, 225), .curve(68, 202, 67, 144, 111, 103),
         .curve(142, 74, 180, 72, 209, 38), .close],
        [.move(209, 64), .curve(221, 112, 201, 156, 154, 170),
         .curve(118, 181, 99, 167, 96, 149), .curve(106, 186, 142, 213, 183, 199),
         .curve(241, 179, 246, 106, 209, 64), .close]
    ]

    static func path(in rect: NSRect) -> NSBezierPath {
        let path = NSBezierPath()
        for contour in contours {
            for segment in contour {
                switch segment {
                case let .move(x, y): path.move(to: NSPoint(x: x, y: y))
                case let .curve(x1, y1, x2, y2, x, y):
                    path.curve(to: NSPoint(x: x, y: y),
                        controlPoint1: NSPoint(x: x1, y: y1), controlPoint2: NSPoint(x: x2, y: y2))
                case .close: path.close()
                }
            }
        }
        // SVG is top-down; AppKit image coordinates are bottom-up.
        let transform = NSAffineTransform()
        transform.translateX(by: rect.minX, yBy: rect.maxY)
        transform.scaleX(by: rect.width / 256, yBy: -rect.height / 256)
        path.transform(using: transform as AffineTransform)
        return path
    }

    static func image(size: CGFloat, template: Bool, color: NSColor = .black) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            (template ? NSColor.black : color).setFill()
            path(in: rect).fill()
            return true
        }
        image.isTemplate = template
        image.accessibilityDescription = "柳风"
        return image
    }

    static var svg: String {
        func n(_ value: CGFloat) -> String { String(format: "%.0f", value) }
        let paths = contours.map { contour in
            let data = contour.map { segment -> String in
                switch segment {
                case let .move(x, y): return "M\(n(x)) \(n(y))"
                case let .curve(x1, y1, x2, y2, x, y):
                    return "C\(n(x1)) \(n(y1)) \(n(x2)) \(n(y2)) \(n(x)) \(n(y))"
                case .close: return "Z"
                }
            }.joined(separator: " ")
            return "<path d=\"\(data)\" fill=\"#000000\"/>"
        }.joined()
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 256 256\" width=\"256\" height=\"256\" role=\"img\"><title>柳风 · 回叶</title>\(paths)</svg>\n"
    }
}
