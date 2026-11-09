import AppKit

/// Packages the user-approved W2 artwork into the app's existing .icns route.
@main
struct MakeIcon {
    static func main() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let asset = root.appendingPathComponent("Assets/WillowFan-W2.png")
        guard let source = NSImage(contentsOf: asset),
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024,
                  pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw NSError(domain: "WillowIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot load W2 artwork"])
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        context.shouldAntialias = true
        let bounds = NSRect(x: 96, y: 96, width: 832, height: 832)
        let tile = NSBezierPath(roundedRect: bounds, xRadius: 182, yRadius: 182)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        shadow.shadowBlurRadius = 14
        shadow.set()
        NSColor.white.setFill()
        tile.fill()
        NSShadow().set()
        tile.addClip()
        source.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let normalized = bitmap.converting(to: .sRGB, renderingIntent: .default) ?? bitmap
        let png = normalized.representation(using: .png, properties: [:])!
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        if CommandLine.arguments.count > 2 {
            let mark = try Data(contentsOf: root.appendingPathComponent("Assets/WillowMark-W2.svg"))
            try mark.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
        }
    }
}
