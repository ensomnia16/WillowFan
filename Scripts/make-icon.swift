import AppKit

let destination = CommandLine.arguments[1]
let side: CGFloat = 1024
let canvas = NSRect(x: 0, y: 0, width: side, height: side)
let center = NSPoint(x: side / 2, y: side / 2)

let image = NSImage(size: canvas.size, flipped: false) { _ in
    // Rounded-square silhouette for the legacy .icns format, with a soft drop shadow.
    let tile = NSBezierPath(roundedRect: canvas.insetBy(dx: 18, dy: 18), xRadius: 222, yRadius: 222)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSGradient(starting: NSColor(calibratedRed: 0.30, green: 0.58, blue: 0.42, alpha: 1),
               ending: NSColor(calibratedRed: 0.11, green: 0.32, blue: 0.23, alpha: 1))!
        .draw(in: tile, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    let leaf = NSBezierPath()
    leaf.move(to: NSPoint(x: 225, y: 195))
    leaf.curve(to: NSPoint(x: 805, y: 830), controlPoint1: NSPoint(x: 160, y: 620), controlPoint2: NSPoint(x: 545, y: 820))
    leaf.curve(to: NSPoint(x: 225, y: 195), controlPoint1: NSPoint(x: 855, y: 425), controlPoint2: NSPoint(x: 610, y: 165))
    leaf.close()
    let vein = NSBezierPath()
    vein.move(to: NSPoint(x: 265, y: 245))
    vein.curve(to: NSPoint(x: 725, y: 745), controlPoint1: NSPoint(x: 430, y: 490), controlPoint2: NSPoint(x: 590, y: 635))
    vein.curve(to: NSPoint(x: 265, y: 245), controlPoint1: NSPoint(x: 575, y: 580), controlPoint2: NSPoint(x: 385, y: 370))
    vein.close()
    leaf.append(vein)
    leaf.windingRule = .evenOdd
    NSColor(calibratedRed: 0.93, green: 0.98, blue: 0.89, alpha: 1).setFill()
    leaf.fill()
    let stem = NSBezierPath()
    stem.move(to: NSPoint(x: 170, y: 135))
    stem.line(to: NSPoint(x: 285, y: 270))
    stem.lineWidth = 32
    stem.lineCapStyle = .round
    NSColor(calibratedRed: 0.93, green: 0.98, blue: 0.89, alpha: 1).setStroke()
    stem.stroke()
    return true
}

let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
image.draw(in: canvas)
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
