import AppKit

/// Keeps the environmental reading visually distinct from the controls.
final class TemperatureSurface: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let tile = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 16, yRadius: 16)
        let top = dynamic(rgb(0x205E4C), rgb(0x1D493D))
        let bottom = dynamic(rgb(0x123A32), rgb(0x142F29))
        NSGradient(starting: top, ending: bottom)?.draw(in: tile, angle: -68)
        NSGraphicsContext.saveGraphicsState()
        tile.addClip()
        rgb(0xA3E3C3, 0.13).setFill()
        WillowMark.path(in: NSRect(x: bounds.maxX - 127, y: -30, width: 159, height: 159)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

func symbolBadge(_ symbol: String, size: CGFloat = 28) -> NSView {
    let badge = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
    badge.symbolConfiguration = .init(pointSize: size * 0.58, weight: .medium)
    badge.contentTintColor = Palette.accentText
    badge.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        badge.widthAnchor.constraint(equalToConstant: size),
        badge.heightAnchor.constraint(equalToConstant: size)
    ])
    return badge
}

func telemetryLabel(_ title: String) -> NSTextField {
    label(title, size: 11, weight: .medium, color: .secondaryLabelColor)
}
