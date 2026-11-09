import AppKit

private typealias Point = (CGFloat, CGFloat)

private func curve(_ start: Point, _ segments: [(Point, Point, Point)],
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

private func svgPath(_ path: CGPath) -> String {
    func coordinate(_ p: CGPoint) -> String { String(format: "%.3f %.3f", p.x, p.y) }
    var components: [String] = []
    path.applyWithBlock { pointer in
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
    return components.joined(separator: " ")
}

/// A simplified cloud and two gusts, drawn as a monochrome template for the status bar.
enum WillowMark {
    static let size = NSSize(width: 20, height: 16)

    private static let cloud: CGPath = {
        let body = CGMutablePath()
        body.addPath(curve((3.3, 12.4), [
            ((1.4, 12.4), (0.5, 11.0), (0.5, 9.5)),
            ((0.5, 8.2), (1.2, 7.2), (2.3, 6.8)),
            ((2.3, 4.7), (3.7, 3.1), (5.6, 3.1)),
            ((7.1, 3.1), (8.1, 3.9), (8.6, 5.0)),
            ((10.4, 5.0), (11.6, 6.0), (11.6, 7.3)),
            ((11.6, 8.0), (11.2, 8.4), (10.6, 8.7)),
            ((11.1, 9.4), (10.8, 10.3), (10.2, 10.7)),
            ((9.9, 12.2), (8.7, 12.9), (7.2, 12.9)),
            ((6.3, 12.9), (5.7, 12.6), (5.2, 12.3)),
            ((4.6, 12.5), (3.9, 12.5), (3.3, 12.4))
        ], closed: true))
        let eye = curve((6.6, 7.6), [
            ((7.3, 7.0), (8.3, 7.0), (8.9, 7.8))
        ])
        body.addPath(eye.copy(strokingWithWidth: 1.05, lineCap: .round, lineJoin: .round, miterLimit: 4))
        body.addEllipse(in: CGRect(x: 8.8, y: 9.0, width: 1.25, height: 1.1))
        return body
    }()

    private static let gusts = [
        curve((11.9, 9.4), [
            ((14.2, 9.4), (17.2, 9.4), (18.2, 8.4)),
            ((19.2, 7.4), (18.7, 6.2), (17.6, 6.1)),
            ((16.9, 6.0), (16.4, 6.3), (16.3, 6.8))
        ]),
        curve((11.5, 11.2), [
            ((13.6, 11.2), (16.8, 11.3), (17.2, 12.6)),
            ((17.6, 14.0), (15.4, 14.4), (15.0, 13.1))
        ])
    ].map { $0.copy(strokingWithWidth: 1.25, lineCap: .round, lineJoin: .round, miterLimit: 4) }

    static func image(height: CGFloat) -> NSImage {
        let scale = height / size.height
        let image = NSImage(size: NSSize(width: size.width * scale, height: height), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.translateBy(x: rect.minX, y: rect.maxY)
            context.scaleBy(x: rect.width / size.width, y: -rect.height / size.height)
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(cloud)
            context.fillPath(using: .evenOdd)
            for gust in gusts {
                context.addPath(gust)
                context.fillPath()
            }
            context.restoreGState()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "柳风云朵吹风"
        return image
    }

    static var svg: String {
        let paths = gusts.map { "<path d=\"\(svgPath($0))\"/>" }.joined()
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="16" viewBox="0 0 20 16">
        <path fill-rule="evenodd" d="\(svgPath(cloud))"/>\(paths)
        </svg>
        """ + "\n"
    }
}

/// The cloud and gust use the same outlines in Icon Composer and legacy builds.
enum WillowAppMark {
    private static let sourceOrigin: CGFloat = 58
    private static let sourceSize: CGFloat = 1138
    private static let ink: UInt32 = 0x126C73
    private static let cloudTint: UInt32 = 0xDFEFE7
    private static let tileTint: UInt32 = 0xF8F0DD

    private struct Artwork {
        let color: UInt32
        let path: CGPath
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
        let paths = art.map { layer in
            "<path fill=\"\(String(format: "#%06X", layer.color))\" d=\"\(svgPath(layer.path))\"/>"
        }.joined()
        let viewBox = "\(sourceOrigin) \(sourceOrigin) \(sourceSize) \(sourceSize)"
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1024\" height=\"1024\" viewBox=\"\(viewBox)\">\(paths)</svg>\n"
    }

    static var composerLayers: [(name: String, svg: String)] {
        [("Cloud.svg", svg(cloud)), ("Gust.svg", svg(gust))]
    }
}
