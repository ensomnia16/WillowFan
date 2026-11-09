import AppKit

@main
struct MakeIcon {
    static func main() throws {
        let destination = CommandLine.arguments[1]
        let canvas = NSRect(x: 0, y: 0, width: 1024, height: 1024)
        let image = NSImage(size: canvas.size, flipped: false) { _ in
            func color(_ r: Double, _ g: Double, _ b: Double) -> NSColor {
                NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
            }
            let tile = NSBezierPath(roundedRect: canvas.insetBy(dx: 100, dy: 100), xRadius: 177, yRadius: 177)
            NSGradient(starting: color(247, 251, 255), ending: color(222, 232, 247))?.draw(in: tile, angle: -75)
            let artwork = NSRect(x: 205, y: 205, width: 614, height: 614)
            color(40, 90, 181).setFill()
            WillowMark.appPath(in: artwork).fill()
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
        if CommandLine.arguments.count > 3 {
            let folder = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (name, svg) in WillowMark.composerLayers {
                try svg.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
            }
        }
    }
}
