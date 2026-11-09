import AppKit

struct ThermalSample {
    let time: TimeInterval
    let degrees: Double?

    static let span: TimeInterval = 120

    static func demonstration() -> [ThermalSample] {
        let temperatures: [Double] = [50, 52, 51, 54, 57, 55, 59, 62, 60, 61, 64, 67, 65, 66, 70, 69, 68]
        return temperatures.enumerated().map { ThermalSample(time: Double($0.offset) * 7.5, degrees: $0.element) }
    }
}

final class ThermalTrendView: NSView {
    var samples: [ThermalSample] = [] { didSet { needsDisplay = true } }
    var showsScale = true

    override func draw(_ dirtyRect: NSRect) {
        let plot = bounds.insetBy(dx: 3, dy: 5)
        guard plot.width > 0 && plot.height > 0 else { return }
        let first = (samples.last?.time ?? 0) - ThermalSample.span
        let lower = 40.0, upper = 100.0
        func point(_ sample: ThermalSample, _ degrees: Double) -> NSPoint {
            let elapsed = min(max((sample.time - first) / ThermalSample.span, 0), 1)
            let fraction = min(max((degrees - lower) / (upper - lower), 0), 1)
            return NSPoint(x: plot.minX + plot.width * elapsed, y: plot.minY + plot.height * fraction)
        }
        let grid = NSBezierPath()
        for line in 0...3 {
            let y = plot.minY + plot.height * Double(line) / 3
            grid.move(to: NSPoint(x: plot.minX, y: y))
            grid.line(to: NSPoint(x: plot.maxX, y: y))
        }
        Palette.hair.setStroke()
        grid.lineWidth = 1
        grid.stroke()

        var runs: [[NSPoint]] = [[]]
        for sample in samples where sample.time >= first {
            if let degrees = sample.degrees, degrees.isFinite {
                runs[runs.count - 1].append(point(sample, degrees))
            } else if !runs.last!.isEmpty {
                runs.append([])
            }
        }
        for points in runs where !points.isEmpty {
            let trace = NSBezierPath()
            trace.move(to: points[0])
            points.dropFirst().forEach { trace.line(to: $0) }
            if points.count > 1 {
                let fill = trace.copy() as! NSBezierPath
                fill.line(to: NSPoint(x: points.last!.x, y: plot.minY))
                fill.line(to: NSPoint(x: points[0].x, y: plot.minY))
                fill.close()
                Palette.accent.withAlphaComponent(0.10).setFill()
                fill.fill()
            }
            Palette.accent.setStroke()
            trace.lineWidth = showsScale ? 2 : 1.5
            trace.lineCapStyle = .round
            trace.lineJoinStyle = .round
            trace.stroke()
        }
        if let last = samples.last, let degrees = last.degrees, degrees.isFinite {
            let marker = point(last, degrees)
            Palette.accentText.setFill()
            NSBezierPath(ovalIn: NSRect(x: marker.x - 2.5, y: marker.y - 2.5, width: 5, height: 5)).fill()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

func sectionHeading(_ title: String, symbol: String, trailing: NSView? = nil) -> NSStackView {
    let caption = label(title, size: 12, weight: .semibold)
    let row = hstack([symbolBadge(symbol, size: 16), caption, spacer()] + (trailing.map { [$0] } ?? []), spacing: 6)
    return row
}

func symbolBadge(_ symbol: String, size: CGFloat = 28) -> NSView {
    let badge = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
    badge.symbolConfiguration = .init(pointSize: size * 0.66, weight: .medium)
    badge.contentTintColor = Palette.accentText
    badge.setAccessibilityElement(false)
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

/// Uses the hardware's reported RPM range. Unknown ranges show the value without a bar.
final class FanReadingRow: NSView {
    private let caption = label("", size: 12)
    private let value = NSTextField(labelWithString: "")
    private let bar = BarView()

    init(_ title: String, compact: Bool = false) {
        super.init(frame: .zero)
        caption.stringValue = title
        caption.widthAnchor.constraint(equalToConstant: compact ? 48 : 55).isActive = true
        bar.color = Palette.accent
        bar.thickness = compact ? 3 : 4
        bar.setContentHuggingPriority(.defaultLow, for: .horizontal)
        value.alignment = .right
        value.widthAnchor.constraint(equalToConstant: compact ? 72 : 82).isActive = true
        pin(hstack([caption, bar, value], spacing: 8), in: self, insets(0))
        update(nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ fan: FanState?) {
        value.attributedStringValue = speedText(fan?.rpm, size: 14)
        if let fan, fan.maximum > fan.minimum {
            bar.fraction = (Double(fan.rpm) - Double(fan.minimum)) / (Double(fan.maximum) - Double(fan.minimum))
            let target = fan.mode == "forced" ? " · 目标 \(fan.target) RPM" : ""
            toolTip = "硬件范围 \(fan.minimum)–\(fan.maximum) RPM\(target)"
        } else {
            bar.fraction = 0
            toolTip = nil
        }
    }
}
