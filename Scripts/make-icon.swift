import AppKit

@main
struct MakeIcon {
    static func main() throws {
        let destination = CommandLine.arguments[1]
        let canvas = NSRect(x: 0, y: 0, width: 1024, height: 1024)
        let image = NSImage(size: canvas.size, flipped: false) { _ in
            let tile = NSBezierPath(roundedRect: canvas.insetBy(dx: 24, dy: 24), xRadius: 216, yRadius: 216)
            NSColor(srgbRed: 35 / 255, green: 92 / 255, blue: 67 / 255, alpha: 1).setFill()
            tile.fill()
            NSColor(srgbRed: 245 / 255, green: 251 / 255, blue: 246 / 255, alpha: 1).setFill()
            // Optical placement compensates for the symbol's asymmetric internal padding.
            WillowMark.path(in: NSRect(x: 44, y: 64, width: 896, height: 896)).fill()
            return true
        }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: canvas)
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
        if CommandLine.arguments.count > 2 {
            try WillowMark.svg.write(toFile: CommandLine.arguments[2], atomically: true, encoding: .utf8)
        }
    }
}
