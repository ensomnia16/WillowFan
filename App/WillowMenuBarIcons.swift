import AppKit

/// Fit the 16 pt image exactly; no title, badge, or additional content width.
func configureWillowMenuBarButton(_ item: NSStatusItem) {
    item.length = 16
    item.button?.title = ""
    item.button?.imagePosition = .imageOnly
    item.button?.imageScaling = .scaleNone
}

/// Mode names remain available in the tooltip and menu; the glyph stays solid.
enum WillowMenuBarMode: String, CaseIterable {
    case quiet, balanced, active

    var title: String {
        switch self {
        case .quiet: return "安静"
        case .balanced: return "均衡"
        case .active: return "积极"
        }
    }


}

/// Native 16 × 16 pt template images, cached once and tinted by macOS.
/// Pass nil while the curve is unavailable; it draws only the rotor.
func willowMenuBarIcon(for mode: WillowMenuBarMode?) -> NSImage {
    WillowMenuBarArtwork.images[mode?.rawValue ?? "unknown"]!
}

func willowRotorImage(size: CGFloat, template: Bool, color: NSColor) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        willowMenuBarIcon(for: nil).draw(in: rect,
            from: .zero,
            operation: .sourceOver, fraction: 1)
        (template ? NSColor.black : color).setFill()
        rect.fill(using: .sourceIn)
        return true
    }
    image.isTemplate = template
    image.accessibilityDescription = "柳风风扇"
    return image
}

private enum WillowMenuBarArtwork {
    static let images: [String: NSImage] = {
        var result: [String: NSImage] = [:]
        for mode in WillowMenuBarMode.allCases.map(Optional.some) + [nil] {
            let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
                guard let context = NSGraphicsContext.current?.cgContext else { return false }
                context.saveGState()
                context.translateBy(x: 1, y: -1.5)
                NSColor.black.setStroke()
                NSColor.black.setFill()
                for angle in [0.0, 120.0, 240.0] {
                    let blade = NSBezierPath()
                    blade.move(to: NSPoint(x: 8, y: 8.6))
                    blade.curve(to: NSPoint(x: 6.9, y: 5),
                                controlPoint1: NSPoint(x: 5.9, y: 8.1),
                                controlPoint2: NSPoint(x: 5.5, y: 6.1))
                    blade.curve(to: NSPoint(x: 10.2, y: 4.1),
                                controlPoint1: NSPoint(x: 7.8, y: 4.2),
                                controlPoint2: NSPoint(x: 9.1, y: 4.9))
                    blade.curve(to: NSPoint(x: 8, y: 8.6),
                                controlPoint1: NSPoint(x: 11, y: 6.3),
                                controlPoint2: NSPoint(x: 9.9, y: 8.2))
                    blade.close()
                    let transform = AffineTransform(translationByX: -8, byY: -9)
                    var rotation = transform
                    rotation.append(AffineTransform(rotationByDegrees: CGFloat(angle)))
                    rotation.append(AffineTransform(translationByX: 8, byY: 9))
                    blade.transform(using: rotation)
                    var enlarged = AffineTransform(translationByX: -8, byY: -9)
                    enlarged.append(AffineTransform(scaleByX: 1.35, byY: 1.35))
                    enlarged.append(AffineTransform(translationByX: 8, byY: 9))
                    blade.transform(using: enlarged)
                    blade.fill()
                }
                if let context = NSGraphicsContext.current?.cgContext {
                    context.saveGState()
                    context.setBlendMode(.clear)
                    context.fillEllipse(in: NSRect(x: 6.55, y: 7.55, width: 2.9, height: 2.9))
                    context.restoreGState()
                }
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: 7.1, y: 8.1, width: 1.8, height: 1.8)).fill()
                context.restoreGState()
                return true
            }
            image.isTemplate = true
            image.accessibilityDescription = mode.map { "柳风 · \($0.title)" } ?? "柳风 · 读取模式中"
            result[mode?.rawValue ?? "unknown"] = image
        }
        return result
    }()
}
