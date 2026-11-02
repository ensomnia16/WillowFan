import AppKit
import ServiceManagement
import ApplicationServices

extension NSViewController { func ensureViewLoaded() { _ = view } }

func run(_ path: String, _ arguments: [String]) -> (Int32, String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    } catch { return (-1, error.localizedDescription) }
}

func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
func appleScriptQuote(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

func label(_ title: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
    let field = NSTextField(labelWithString: title)
    field.font = NSFont.systemFont(ofSize: size, weight: weight)
    field.textColor = color
    field.lineBreakMode = .byWordWrapping
    field.maximumNumberOfLines = 0
    return field
}

// MARK: - Look

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

func dynamic(_ light: NSColor, _ dark: NSColor) -> NSColor {
    NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light }
}

enum Palette {
    static let ground = dynamic(rgb(0xF5F6F4), rgb(0x1E1F1E))
    static let card = dynamic(rgb(0xFFFFFF), rgb(0x2B2D2B))
    static let fill = dynamic(rgb(0xE9EBE6), rgb(0x3A3D3A))
    static let hair = dynamic(rgb(0xE2E4DF), rgb(0x3A3C3A))
    static let accent = dynamic(rgb(0x357A50), rgb(0x5FB480))
    static let accentSoft = dynamic(rgb(0xE3F0E7), rgb(0x5FB480, 0.18))
    static let accentText = dynamic(rgb(0x2F6E4A), rgb(0x8FD3A8))

    /// Cool blue below 55 °C, then yellow, orange and red as the hottest sensor climbs.
    static func heat(_ temperature: Double?) -> NSColor {
        guard let t = temperature else { return .secondaryLabelColor }
        if t >= 85 { return dynamic(rgb(0xB63927), rgb(0xF07A5E)) }
        if t >= 70 { return dynamic(rgb(0x9D5412), rgb(0xF0A04B)) }
        if t >= 55 { return dynamic(rgb(0x8A6612), rgb(0xE3C25A)) }
        return dynamic(rgb(0x246B91), rgb(0x6CB4DA))
    }
}

func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight = .semibold) -> NSFont {
    let base = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: descriptor, size: size) ?? base
}

func numberLabel(_ title: String, size: CGFloat, weight: NSFont.Weight = .semibold, color: NSColor = .labelColor) -> NSTextField {
    let field = label(title, size: size, weight: weight, color: color)
    field.font = roundedFont(size, weight)
    field.maximumNumberOfLines = 1
    return field
}

func speedText(_ rpm: Int?, size: CGFloat) -> NSAttributedString {
    let text = NSMutableAttributedString(string: rpm.map(String.init) ?? "—",
                                         attributes: [.font: roundedFont(size), .foregroundColor: NSColor.labelColor])
    text.append(NSAttributedString(string: " RPM", attributes: [.font: NSFont.systemFont(ofSize: max(10, size * 0.45), weight: .medium),
                                                                .foregroundColor: NSColor.secondaryLabelColor]))
    return text
}

func spacer() -> NSView {
    let view = NSView()
    view.setContentHuggingPriority(.init(1), for: .horizontal)
    view.setContentCompressionResistancePriority(.init(1), for: .horizontal)
    return view
}

func hstack(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = spacing
    return stack
}

func vstack(_ views: [NSView], spacing: CGFloat = 4, alignment: NSLayoutConstraint.Attribute = .leading) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .vertical
    stack.alignment = alignment
    stack.spacing = spacing
    return stack
}

/// Pins `content` inside `container` with the given insets.
func pin(_ content: NSView, in container: NSView, _ inset: NSEdgeInsets) {
    content.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(content)
    NSLayoutConstraint.activate([
        content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset.left),
        content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset.right),
        content.topAnchor.constraint(equalTo: container.topAnchor, constant: inset.top),
        content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -inset.bottom)
    ])
}

func insets(_ value: CGFloat) -> NSEdgeInsets { NSEdgeInsets(top: value, left: value, bottom: value, right: value) }

/// Stretches every arranged subview of a vertical stack to its full width.
func fillWidth(_ stack: NSStackView) {
    for view in stack.arrangedSubviews { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
}

/// Approved concept A: two willow leaves enclosing recirculating airflow.
func leafIcon(size: CGFloat, template: Bool) -> NSImage {
    WillowMark.image(size: size, template: template, color: Palette.accent)
}

// MARK: - Model

struct FanState {
    var rpm = 0
    var target = 0
    var minimum = 0
    var maximum = 0
    var mode = "auto"
}

struct FanSnapshot {
    var temperature: Double?
    var sensor: String
    var fans: [FanState]
    var curve: String
    var enabled: Bool
    var serviceRunning: Bool
    var installed: Bool

    var active: Bool {
        enabled && serviceRunning && installed && !fans.isEmpty && fans.allSatisfy { $0.mode == "forced" }
    }
}

let curveNames = ["quiet", "balanced", "active"]
let curveTitles = ["安静", "均衡", "积极"]
let curveDescriptions = ["quiet": "优先安静，温度升高后逐步提速。", "balanced": "兼顾噪声与散热。", "active": "更早升速，适合持续负载。"]

// MARK: - Components

final class BackgroundView: NSView {
    var color: NSColor = Palette.ground { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) { color.setFill(); dirtyRect.fill() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

class CardView: NSView {
    var radius: CGFloat = 12

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        Palette.card.setFill()
        path.fill()
        Palette.hair.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

final class SeparatorLine: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 1) }
    override func draw(_ dirtyRect: NSRect) { Palette.hair.setFill(); bounds.fill() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

/// Capsule showing whether 柳风 is currently driving the fans.
final class StatusPill: NSView {
    var active = false { didSet { needsDisplay = true } }
    var text = "系统自动" { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var fontSize: CGFloat = 12 { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }

    private var attributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
         .foregroundColor: active ? Palette.accentText : NSColor.secondaryLabelColor]
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil((text as NSString).size(withAttributes: attributes).width) + 30, height: fontSize + 10)
    }

    override func draw(_ dirtyRect: NSRect) {
        let capsule = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        (active ? Palette.accentSoft : Palette.fill).setFill()
        capsule.fill()
        let dot = NSBezierPath(ovalIn: NSRect(x: 10, y: bounds.midY - 3.5, width: 7, height: 7))
        (active ? Palette.accent : NSColor.secondaryLabelColor).setFill()
        dot.fill()
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: 22, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }

    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

/// One option of a small mutually exclusive group, drawn as an outlined pill.
final class ChoiceButton: NSButton {
    var isChosen = false { didSet { needsDisplay = true } }
    var height: CGFloat = 28

    init(title: String, tag: Int, target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        self.title = title
        self.tag = tag
        self.target = target
        self.action = action
        isBordered = false
        setButtonType(.momentaryPushIn)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { NSSize(width: 56, height: height) }
    override var isEnabled: Bool { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        if isChosen { Palette.accentSoft.setFill(); path.fill() }
        else if isHighlighted { Palette.fill.setFill(); path.fill() }
        (isChosen ? Palette.accent : Palette.hair).setStroke()
        path.lineWidth = 1
        path.stroke()
        let color: NSColor = !isEnabled ? .tertiaryLabelColor : isChosen ? Palette.accentText : .labelColor
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: isChosen ? .semibold : .regular),
                                                         .foregroundColor: color]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }

    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

/// A row of 安静 / 均衡 / 积极 pills.
final class CurveChoices: NSStackView {
    private(set) var buttons: [ChoiceButton] = []
    var onSelect: ((String) -> Void)?

    init(buttonHeight: CGFloat = 28) {
        super.init(frame: .zero)
        orientation = .horizontal
        distribution = .fillEqually
        spacing = 6
        for (index, title) in curveTitles.enumerated() {
            let button = ChoiceButton(title: title, tag: index, target: nil, action: #selector(pressed(_:)))
            button.target = self
            button.height = buttonHeight
            buttons.append(button)
            addArrangedSubview(button)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ curve: String, enabled: Bool) {
        let index = curveNames.firstIndex(of: curve) ?? 2
        for button in buttons {
            button.isChosen = button.tag == index
            button.isEnabled = enabled
        }
    }

    @objc private func pressed(_ sender: ChoiceButton) {
        guard curveNames.indices.contains(sender.tag) else { return }
        show(curveNames[sender.tag], enabled: true)
        onSelect?(curveNames[sender.tag])
    }
}

/// Plain menu-style row with an SF Symbol, used at the bottom of the menu-bar panel.
final class MenuRowButton: NSButton {
    private let symbol: String
    private var hovering = false { didSet { needsDisplay = true } }

    init(title: String, symbol: String, target: AnyObject?, action: Selector) {
        self.symbol = symbol
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        setButtonType(.momentaryPushIn)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 28) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func draw(_ dirtyRect: NSRect) {
        if hovering || isHighlighted {
            Palette.accentSoft.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            .applying(.init(paletteColors: [hovering ? Palette.accentText : .secondaryLabelColor]))
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
            let size = image.size
            image.draw(in: NSRect(x: 8 + (18 - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height))
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: NSPoint(x: 34, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }
}

/// Thin capsule bar used for sensor temperatures and CPU load.
final class BarView: NSView {
    var fraction: Double = 0 { didSet { needsDisplay = true } }
    var color: NSColor = Palette.accent { didSet { needsDisplay = true } }
    var thickness: CGFloat = 6

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: thickness) }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSRect(x: 0, y: bounds.midY - thickness / 2, width: bounds.width, height: thickness)
        Palette.fill.setFill()
        NSBezierPath(roundedRect: track, xRadius: thickness / 2, yRadius: thickness / 2).fill()
        let width = max(thickness, track.width * CGFloat(min(max(fraction, 0), 1)))
        guard fraction > 0 else { return }
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: track.minY, width: width, height: thickness), xRadius: thickness / 2, yRadius: thickness / 2).fill()
    }

    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

final class FanCardView: CardView {
    private let fanGlyph = NSImageView(image: NSImage(systemSymbolName: "fanblades", accessibilityDescription: "风扇")!)
    private let nameLabel = label("左侧风扇", size: 12, color: .secondaryLabelColor)
    private let speedLabel = NSTextField(labelWithString: "")
    private let detailLabel = label("等待风扇读数", size: 11, color: .secondaryLabelColor)

    init(name: String) {
        super.init(frame: .zero)
        nameLabel.stringValue = name
        detailLabel.font = roundedFont(11, .regular)
        detailLabel.maximumNumberOfLines = 1
        detailLabel.lineBreakMode = .byTruncatingTail
        fanGlyph.translatesAutoresizingMaskIntoConstraints = false
        fanGlyph.contentTintColor = Palette.accent
        fanGlyph.imageScaling = .scaleProportionallyUpOrDown
        fanGlyph.widthAnchor.constraint(equalToConstant: 32).isActive = true
        fanGlyph.heightAnchor.constraint(equalToConstant: 32).isActive = true
        let text = vstack([nameLabel, speedLabel, detailLabel], spacing: 2)
        let content = hstack([fanGlyph, text], spacing: 12)
        pin(content, in: self, NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 12))
        update(nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ fan: FanState?) {
        guard let fan else {
            speedLabel.attributedStringValue = speedText(nil, size: 26)
            detailLabel.stringValue = "等待风扇读数"
            return
        }
        speedLabel.attributedStringValue = speedText(fan.rpm, size: 26)
        detailLabel.stringValue = fan.mode == "forced" ? "目标 \(fan.target) RPM" : "系统自动"
        toolTip = "硬件范围 \(fan.minimum)–\(fan.maximum) RPM"
    }
}

final class SensorRowView: NSView {
    private let nameLabel = NSTextField(labelWithString: "—")
    private let bar = BarView()
    private let valueLabel = numberLabel("—", size: 13, weight: .medium)

    init() {
        super.init(frame: .zero)
        nameLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        nameLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        for view in [nameLabel, bar, valueLabel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            nameLabel.widthAnchor.constraint(equalToConstant: 56),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            bar.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: valueLabel.leadingAnchor, constant: -12),
            bar.centerYAnchor.constraint(equalTo: centerYAnchor),
            bar.heightAnchor.constraint(equalToConstant: 6),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 44),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ reading: (String, Double)?) {
        isHidden = reading == nil
        guard let reading else { return }
        nameLabel.stringValue = reading.0
        valueLabel.stringValue = String(format: "%.0f°", reading.1)
        bar.fraction = (reading.1 - 40) / 60
        bar.color = Palette.heat(reading.1)
    }
}

final class CurveChart: NSView {
    var selected = "active" { didSet { needsDisplay = true } }
    var base = 60.0 { didSet { needsDisplay = true } }
    var temperature: Double? { didSet { needsDisplay = true } }

    private let presets: [(String, [(Double, Double)])] = [
        ("quiet", [(40, 0), (55, 0), (65, 0.10), (75, 0.30), (85, 0.55), (95, 0.82), (100, 1)]),
        ("balanced", [(40, 0), (50, 0.10), (60, 0.22), (70, 0.42), (80, 0.65), (90, 0.85), (100, 1)]),
        ("active", [(40, 0.10), (50, 0.24), (60, 0.40), (70, 0.58), (80, 0.75), (90, 0.90), (100, 1)])
    ]

    private func shifted(_ points: [(Double, Double)]) -> [(Double, Double)] {
        points.map { ($0.0 + base - 60, $0.1) }
    }

    private func value(at temperature: Double, on points: [(Double, Double)]) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if temperature <= first.0 { return first.1 }
        if temperature >= last.0 { return last.1 }
        for (a, b) in zip(points, points.dropFirst()) where temperature <= b.0 {
            return a.1 + (b.1 - a.1) * (temperature - a.0) / (b.0 - a.0)
        }
        return last.1
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let plot = NSRect(x: 40, y: 24, width: bounds.width - 52, height: bounds.height - 34)
        let x: (Double) -> CGFloat = { plot.minX + CGFloat(min(max(($0 - 40) / 60, 0), 1)) * plot.width }
        let y: (Double) -> CGFloat = { plot.minY + CGFloat($0) * plot.height }
        let small: [NSAttributedString.Key: Any] = [.font: roundedFont(10, .regular), .foregroundColor: NSColor.secondaryLabelColor]

        for step in 0...4 {
            let fraction = Double(step) / 4
            let line = NSBezierPath()
            line.move(to: NSPoint(x: plot.minX, y: y(fraction)))
            line.line(to: NSPoint(x: plot.maxX, y: y(fraction)))
            line.lineWidth = 1
            Palette.hair.setStroke()
            line.stroke()
            let text = "\(step * 25)%" as NSString
            let size = text.size(withAttributes: small)
            text.draw(at: NSPoint(x: plot.minX - size.width - 8, y: y(fraction) - size.height / 2), withAttributes: small)
        }
        for degrees in stride(from: 40, through: 100, by: 15) {
            let text = "\(degrees)°" as NSString
            let size = text.size(withAttributes: small)
            text.draw(at: NSPoint(x: x(Double(degrees)) - size.width / 2, y: plot.minY - size.height - 6), withAttributes: small)
        }

        for (name, points) in presets where name != selected {
            let path = NSBezierPath()
            for (index, point) in shifted(points).enumerated() {
                let p = NSPoint(x: x(point.0), y: y(point.1))
                if index == 0 { path.move(to: p) } else { path.line(to: p) }
            }
            path.lineWidth = 1.5
            path.lineJoinStyle = .round
            NSColor.tertiaryLabelColor.setStroke()
            path.stroke()
        }
        guard let points = presets.first(where: { $0.0 == selected }).map({ shifted($0.1) }) else { return }
        let curve = NSBezierPath()
        for (index, point) in points.enumerated() {
            let p = NSPoint(x: x(point.0), y: y(point.1))
            if index == 0 { curve.move(to: p) } else { curve.line(to: p) }
        }
        let area = curve.copy() as! NSBezierPath
        area.line(to: NSPoint(x: x(points.last!.0), y: plot.minY))
        area.line(to: NSPoint(x: x(points.first!.0), y: plot.minY))
        area.close()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: plot).addClip()
        Palette.accent.withAlphaComponent(0.10).setFill()
        area.fill()
        curve.lineWidth = 2.5
        curve.lineJoinStyle = .round
        curve.lineCapStyle = .round
        Palette.accent.setStroke()
        curve.stroke()
        NSGraphicsContext.restoreGraphicsState()

        if let temperature {
            let clamped = min(max(temperature, 40), 100)
            let marker = NSBezierPath()
            marker.move(to: NSPoint(x: x(clamped), y: plot.minY))
            marker.line(to: NSPoint(x: x(clamped), y: plot.maxY))
            marker.lineWidth = 1
            marker.setLineDash([3, 3], count: 2, phase: 0)
            NSColor.secondaryLabelColor.setStroke()
            marker.stroke()
            let point = NSPoint(x: x(clamped), y: y(value(at: clamped, on: points)))
            let dot = NSBezierPath(ovalIn: NSRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
            Palette.card.setFill(); dot.fill()
            dot.lineWidth = 2.5
            Palette.heat(temperature).setStroke(); dot.stroke()
        }
    }

    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

// MARK: - Main window

final class FanController: NSViewController {
    var onSnapshot: ((FanSnapshot) -> Void)?
    private var temperature: Double?
    private var sensor = "—"
    private var fans: [FanState] = []
    private var sensors: [(String, Double)] = []
    private var target = 60.0
    private var curveName = "active"
    private var enabled = false
    private var serviceUpdateRequired = ControlService.needsUpdate()
    private var serviceRunning = false
    private var onBattery = false
    private var busy = false
    private var statusError = ""
    private var actionError = ""
    private var pendingTarget = false
    private var refreshInFlight = false
    private var targetWrite: DispatchWorkItem?
    private var timer: Timer?

    /// Shown in the window toolbar by the app delegate.
    let tabControl = NSSegmentedControl(labels: ["概览", "曲线", "进程"], trackingMode: .selectOne, target: nil, action: nil)
    let statusPill = StatusPill()

    private let tabView = NSTabView()
    private let temperatureLabel = numberLabel("—°", size: 64)
    private let heroDetail = label("传感器 —", size: 12, color: .secondaryLabelColor)
    private let leftFan = FanCardView(name: "风扇 1")
    private let rightFan = FanCardView(name: "风扇 2")
    private let sensorRows = (0..<6).map { _ in SensorRowView() }
    private let sensorEmpty = label("等待传感器读数", size: 12, color: .secondaryLabelColor)
    private let performance = PerformanceController()
    private let switchControl = NSSwitch()
    private let switchDetail = label("关闭后交还系统控制", size: 11, color: .secondaryLabelColor)
    private let overviewCurves = CurveChoices()
    private let chartCurves = CurveChoices(buttonHeight: 26)
    private let curveChart = CurveChart()
    private let curveDescription = label("更早升速，适合持续负载。", size: 11, color: .secondaryLabelColor)
    private let chartDescription = label("更早升速，适合持续负载。", size: 12, color: .secondaryLabelColor)
    private let slider = NSSlider(value: 60, minValue: 50, maxValue: 70, target: nil, action: nil)
    private let targetLabel = numberLabel("60 °C", size: 12, weight: .medium)
    private let effectiveLabel = label("有效基准 60 °C", size: 10, color: .secondaryLabelColor)
    private let chartBaseLabel = label("", size: 12, color: .secondaryLabelColor)
    private let serviceLabel = label("控制服务未安装", size: 11, weight: .medium)
    private let serviceDetail = label("安装后即可启用风扇曲线。", size: 11, color: .secondaryLabelColor)
    private let installButton = NSButton(title: "安装服务…", target: nil, action: nil)
    private let errorLabel = label("", size: 11, color: .systemRed)

    private var enginePath: String { Bundle.main.path(forResource: "willowfan-engine", ofType: nil)! }
    private var installed: Bool { FileManager.default.isExecutableFile(atPath: "/Library/PrivilegedHelperTools/com.willowfan.engine") }
    private var configPath: String { NSHomeDirectory() + "/Library/Application Support/WillowFan/config.toml" }
    private var heartbeatPath: String { NSHomeDirectory() + "/Library/Application Support/WillowFan/heartbeat" }

    var snapshot: FanSnapshot {
        FanSnapshot(temperature: temperature, sensor: sensor, fans: fans, curve: curveName,
                    enabled: enabled, serviceRunning: serviceRunning, installed: installed)
    }

    override func loadView() {
        let root = BackgroundView(frame: NSRect(x: 0, y: 0, width: 760, height: 540))
        tabView.tabViewType = .noTabsNoBorder
        tabView.drawsBackground = false
        for (title, page) in [("概览", makeOverview()), ("曲线", makeCurvePage()), ("进程", makeProcessPage())] {
            let item = NSTabViewItem(identifier: title)
            item.label = title
            item.view = page
            tabView.addTabViewItem(item)
        }
        tabControl.selectedSegment = 0
        tabControl.target = self
        tabControl.action = #selector(tabChanged)
        statusPill.translatesAutoresizingMaskIntoConstraints = false

        let footer = makeFooter()
        let line = SeparatorLine()
        for view in [tabView, line, footer] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tabView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            tabView.topAnchor.constraint(equalTo: root.topAnchor),
            line.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            line.topAnchor.constraint(equalTo: tabView.bottomAnchor),
            line.heightAnchor.constraint(equalToConstant: 1),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            footer.topAnchor.constraint(equalTo: line.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 36),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        self.view = root
    }

    private func makeOverview() -> NSView {
        let page = NSView()

        let hero = CardView()
        let heroStack = vstack([label("最高温度", size: 12, color: .secondaryLabelColor), temperatureLabel, heroDetail], spacing: 4)
        heroDetail.maximumNumberOfLines = 1
        heroDetail.lineBreakMode = .byTruncatingTail
        pin(heroStack, in: hero, insets(20))

        let controls = CardView()
        switchControl.target = self
        switchControl.action = #selector(toggle)
        let switchText = vstack([label("风扇调节", size: 13, weight: .semibold), switchDetail], spacing: 2)
        let switchRow = hstack([switchText, spacer(), switchControl])
        overviewCurves.onSelect = { [weak self] in self?.selectCurve($0) }
        slider.numberOfTickMarks = 21
        slider.allowsTickMarkValuesOnly = true
        slider.controlSize = .small
        slider.trackFillColor = Palette.accent
        slider.target = self
        slider.action = #selector(sliderChanged)
        let baseHeader = hstack([label("温度基准", size: 11, color: .secondaryLabelColor), spacer(), targetLabel])
        let baseBounds = hstack([label("更早升速", size: 10, color: .secondaryLabelColor), spacer(), effectiveLabel, spacer(),
                                 label("更安静", size: 10, color: .secondaryLabelColor)])
        let curveLabel = label("曲线", size: 11, color: .secondaryLabelColor)
        let controlStack = vstack([switchRow, SeparatorLine(), curveLabel, overviewCurves,
                                   SeparatorLine(), baseHeader, slider, baseBounds], spacing: 10)
        controlStack.setCustomSpacing(14, after: switchRow)
        controlStack.setCustomSpacing(6, after: curveLabel)
        controlStack.setCustomSpacing(14, after: overviewCurves)
        controlStack.setCustomSpacing(4, after: slider)
        fillWidth(controlStack)
        let controlHolder = NSView()
        controlStack.translatesAutoresizingMaskIntoConstraints = false
        controlHolder.addSubview(controlStack)
        NSLayoutConstraint.activate([
            controlStack.leadingAnchor.constraint(equalTo: controlHolder.leadingAnchor),
            controlStack.trailingAnchor.constraint(equalTo: controlHolder.trailingAnchor),
            controlStack.topAnchor.constraint(equalTo: controlHolder.topAnchor)
        ])
        pin(controlHolder, in: controls, insets(16))

        let fanRow = NSStackView(views: [leftFan, rightFan])
        fanRow.orientation = .horizontal
        fanRow.distribution = .fillEqually
        fanRow.spacing = 16

        let sensorCard = CardView()
        let sensorHeader = hstack([label("温度传感器", size: 13, weight: .semibold), spacer(),
                                   label("", size: 11)])
        let sensorStack = vstack([sensorHeader] + sensorRows + [sensorEmpty], spacing: 4)
        sensorStack.setCustomSpacing(10, after: sensorHeader)
        fillWidth(sensorStack)
        let sensorHolder = NSView()
        sensorStack.translatesAutoresizingMaskIntoConstraints = false
        sensorHolder.addSubview(sensorStack)
        NSLayoutConstraint.activate([
            sensorStack.leadingAnchor.constraint(equalTo: sensorHolder.leadingAnchor),
            sensorStack.trailingAnchor.constraint(equalTo: sensorHolder.trailingAnchor),
            sensorStack.topAnchor.constraint(equalTo: sensorHolder.topAnchor)
        ])
        pin(sensorHolder, in: sensorCard, NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16))

        for view in [hero, controls, fanRow, sensorCard] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            page.addSubview(view)
        }
        NSLayoutConstraint.activate([
            hero.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 20),
            hero.topAnchor.constraint(equalTo: page.topAnchor, constant: 20),
            hero.widthAnchor.constraint(equalToConstant: 248),
            controls.leadingAnchor.constraint(equalTo: hero.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: hero.trailingAnchor),
            controls.topAnchor.constraint(equalTo: hero.bottomAnchor, constant: 16),
            controls.bottomAnchor.constraint(equalTo: page.bottomAnchor, constant: -20),
            fanRow.leadingAnchor.constraint(equalTo: hero.trailingAnchor, constant: 16),
            fanRow.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -20),
            fanRow.topAnchor.constraint(equalTo: hero.topAnchor),
            fanRow.heightAnchor.constraint(equalToConstant: 104),
            sensorCard.leadingAnchor.constraint(equalTo: fanRow.leadingAnchor),
            sensorCard.trailingAnchor.constraint(equalTo: fanRow.trailingAnchor),
            sensorCard.topAnchor.constraint(equalTo: fanRow.bottomAnchor, constant: 16),
            sensorCard.bottomAnchor.constraint(equalTo: page.bottomAnchor, constant: -20)
        ])
        return page
    }

    private func makeCurvePage() -> NSView {
        let page = NSView()
        let card = CardView()
        chartCurves.onSelect = { [weak self] in self?.selectCurve($0) }
        chartCurves.widthAnchor.constraint(equalToConstant: 216).isActive = true
        let header = hstack([vstack([label("风扇曲线", size: 13, weight: .semibold), chartDescription], spacing: 2), spacer(), chartCurves])
        let footnote = hstack([chartBaseLabel, spacer(), label("相对转速 %", size: 11, color: .secondaryLabelColor)])
        for view in [header, curveChart, footnote] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(view)
        }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            header.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            curveChart.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            curveChart.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            curveChart.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 18),
            footnote.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            footnote.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            footnote.topAnchor.constraint(equalTo: curveChart.bottomAnchor, constant: 12),
            footnote.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
        pin(card, in: page, insets(20))
        return page
    }

    private func makeProcessPage() -> NSView {
        let page = NSView()
        addChild(performance)
        pin(performance.view, in: page, insets(20))
        return page
    }

    private func makeFooter() -> NSView {
        installButton.bezelStyle = .rounded
        installButton.controlSize = .small
        installButton.target = self
        installButton.action = #selector(install)
        serviceDetail.maximumNumberOfLines = 1
        serviceDetail.lineBreakMode = .byTruncatingTail
        errorLabel.maximumNumberOfLines = 1
        errorLabel.lineBreakMode = .byTruncatingTail
        errorLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        serviceDetail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return hstack([serviceLabel, serviceDetail, spacer(), errorLabel, installButton], spacing: 8)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateUI()
        refresh()
        resetRefreshTimer()
        performance.refresh()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        performance.setShown(tabControl.selectedSegment == 2)
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        performance.setShown(false)
    }

    func selectTab(_ index: Int) {
        guard (0..<tabView.numberOfTabViewItems).contains(index) else { return }
        tabControl.selectedSegment = index
        tabView.selectTabViewItem(at: index)
        performance.setShown(index == 2 && view.window?.isVisible == true)
    }

    @objc private func tabChanged() { selectTab(tabControl.selectedSegment) }

    func resetRefreshTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: UISettings.displayRefreshSeconds, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func resetPerformanceRefreshTimer() { performance.resetRefreshTimer() }

    private func heartbeat() {
        let manager = FileManager.default
        let folder = (heartbeatPath as NSString).deletingLastPathComponent
        try? manager.createDirectory(atPath: folder, withIntermediateDirectories: true)
        if !manager.fileExists(atPath: heartbeatPath) { manager.createFile(atPath: heartbeatPath, contents: Data()) }
        try? manager.setAttributes([.modificationDate: Date()], ofItemAtPath: heartbeatPath)
    }

    func refresh() {
        heartbeat()
        guard !refreshInFlight else { return }
        refreshInFlight = true
        let path = enginePath
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let status = run(path, ["status"])
            let service = run("/bin/launchctl", ["print", "system/com.willowfan.engine"])
            let power = run("/usr/bin/pmset", ["-g", "batt"])
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshInFlight = false
                self.serviceRunning = service.0 == 0 && service.1.contains("state = running")
                self.onBattery = power.1.contains("Battery Power")
                if status.0 == 0 { self.parse(status.1); self.statusError = "" }
                else { self.statusError = status.1.trimmingCharacters(in: .whitespacesAndNewlines) }
                self.updateUI()
                self.onSnapshot?(self.snapshot)
            }
        }
    }

    private func parse(_ output: String) {
        var newFans: [FanState] = []
        var newSensors: [(String, Double)] = []
        for raw in output.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let words = line.split(separator: " ")
            if line.hasPrefix("Hottest sensor:"), words.count >= 5 {
                temperature = Double(words[4])
                sensor = String(words[2])
            } else if line.hasPrefix("Sensor "), words.count >= 4,
                      let value = Double(words[2]) {
                newSensors.append((String(words[1].dropLast()), value))
            } else if line.hasPrefix("Fan ") {
                func field(_ name: String) -> Double {
                    let text = words.first(where: { $0.hasPrefix(name + "=") }).map { $0.dropFirst(name.count + 1) }
                    return Double(text ?? "0") ?? 0
                }
                let mode = words.first(where: { $0.hasPrefix("mode=") }).map { String($0.dropFirst(5)) } ?? "unknown"
                newFans.append(FanState(rpm: Int(field("current")), target: Int(field("target")), minimum: Int(field("min")), maximum: Int(field("max")), mode: mode))
            } else if line.hasPrefix("target_temp"), !pendingTarget {
                target = Double(line.components(separatedBy: "=").last?.trimmingCharacters(in: .whitespaces) ?? "") ?? 60
            } else if line.hasPrefix("enabled") { enabled = line.hasSuffix("true") }
            else if line.hasPrefix("curve =") { curveName = String(words.last ?? "active") }
        }
        fans = newFans
        sensors = Array(newSensors.prefix(6))
    }

    private func updateBaseLabels() {
        targetLabel.stringValue = "\(Int(target)) °C"
        effectiveLabel.stringValue = onBattery ? "电池 \(Int(target + 5)) °C" : ""
        chartBaseLabel.stringValue = onBattery
            ? "基准 \(Int(target + 5)) °C（电池）"
            : "基准 \(Int(target)) °C"
        curveChart.base = target + (onBattery ? 5 : 0)
    }

    private func updateUI() {
        let active = enabled && installed && serviceRunning && !fans.isEmpty && fans.allSatisfy { $0.mode == "forced" }
        temperatureLabel.stringValue = temperature.map { String(format: "%.0f°", $0) } ?? "—°"
        temperatureLabel.textColor = Palette.heat(temperature)
        heroDetail.stringValue = onBattery ? "电池供电" : "接入电源"
        statusPill.active = active
        statusPill.text = active ? "正在调节" : "系统自动"
        leftFan.update(fans.first)
        rightFan.update(fans.count > 1 ? fans[1] : nil)
        for (index, row) in sensorRows.enumerated() { row.update(sensors.indices.contains(index) ? sensors[index] : nil) }
        sensorEmpty.isHidden = !sensors.isEmpty
        switchControl.state = enabled && installed ? .on : .off
        switchControl.isEnabled = installed && serviceRunning && !busy
        switchDetail.stringValue = !installed ? "需要先安装控制服务" : !serviceRunning ? "控制服务未运行" : "关闭后交还系统控制"
        slider.isEnabled = !busy
        overviewCurves.show(curveName, enabled: !busy)
        chartCurves.show(curveName, enabled: !busy)
        curveChart.selected = curveName
        curveChart.temperature = temperature
        curveDescription.stringValue = curveDescriptions[curveName] ?? ""
        chartDescription.stringValue = curveDescriptions[curveName] ?? ""
        if !pendingTarget { slider.doubleValue = target }
        updateBaseLabels()
        if !installed {
            serviceLabel.stringValue = "控制服务未安装"
            serviceDetail.stringValue = "安装后即可启用风扇曲线。"
        } else if !serviceRunning {
            serviceLabel.stringValue = "控制服务未运行"
            serviceDetail.stringValue = "风扇由系统自动管理。"
        } else if active {
            serviceLabel.stringValue = "服务正常"
            serviceDetail.stringValue = ""
        } else if enabled {
            serviceLabel.stringValue = "控制服务正在等待"
            serviceDetail.stringValue = ""
        } else {
            serviceLabel.stringValue = "服务正常"
            serviceDetail.stringValue = ""
        }
        installButton.isHidden = installed && serviceRunning && !serviceUpdateRequired
        installButton.isEnabled = !busy
        installButton.title = busy ? "正在安装…" : serviceUpdateRequired ? "更新服务…" : installed ? "修复服务…" : "安装服务…"
        let messages = [actionError, statusError].filter { !$0.isEmpty }
        errorLabel.stringValue = messages.joined(separator: "  ")
        errorLabel.toolTip = messages.joined(separator: "\n")
        errorLabel.isHidden = messages.isEmpty
    }

    @objc private func toggle() {
        setEnabled(switchControl.state == .on)
    }

    func setEnabled(_ desired: Bool) {
        guard installed && serviceRunning else { updateUI(); return }
        if desired { heartbeat() }
        let path = enginePath
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = run(path, [desired ? "on" : "off"])
            DispatchQueue.main.async {
                self?.actionError = result.0 == 0 ? "" : result.1
                self?.refresh()
            }
        }
    }

    @objc private func sliderChanged() {
        target = slider.doubleValue.rounded()
        updateBaseLabels()
        targetWrite?.cancel()
        pendingTarget = true
        let value = Int(target), path = enginePath
        let work = DispatchWorkItem { [weak self] in
            let result = run(path, ["target", String(value)])
            DispatchQueue.main.async {
                self?.pendingTarget = false
                self?.actionError = result.0 == 0 ? "" : result.1
                self?.refresh()
            }
        }
        targetWrite = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    func selectCurve(_ name: String) {
        guard curveNames.contains(name) else { return }
        curveName = name
        curveChart.selected = name
        overviewCurves.show(name, enabled: !busy)
        chartCurves.show(name, enabled: !busy)
        curveDescription.stringValue = curveDescriptions[name] ?? ""
        chartDescription.stringValue = curveDescriptions[name] ?? ""
        let path = enginePath
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = run(path, ["curve", name])
            DispatchQueue.main.async {
                self?.actionError = result.0 == 0 ? "" : result.1
                self?.refresh()
            }
        }
    }

    @objc private func install() {
        guard !busy else { return }
        busy = true; updateUI()
        let script = Bundle.main.path(forResource: "install-service", ofType: "sh")!
        let command = "/bin/bash \(shellQuote(script)) \(shellQuote(enginePath)) \(shellQuote(configPath))"
        let source = "do shell script \(appleScriptQuote(command)) with administrator privileges"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = run("/usr/bin/osascript", ["-e", source])
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                if result.0 == 0 {
                    self.heartbeat()
                    self.serviceUpdateRequired = false
                    self.actionError = ""
                } else { self.actionError = "安装未完成：" + result.1.trimmingCharacters(in: .whitespacesAndNewlines) }
                self.refresh()
            }
        }
    }

    func repairServiceIfNeeded() { if serviceUpdateRequired { install() } }

    func stop() {
        // A missing heartbeat returns control to macOS on the next service tick.
        // Keep the chosen curve and enabled preference across automatic updates.
        try? FileManager.default.removeItem(atPath: heartbeatPath)
    }
}

// MARK: - Menu-bar panel

// MARK: - Processes

struct ProcessUsage {
    let pid: Int
    let cpuPercent: Double
    let residentMB: Double
    let executable: String

    var name: String { URL(fileURLWithPath: executable).lastPathComponent }
}

final class PerformanceController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private var processes: [ProcessUsage] = []
    private var displayed: [ProcessUsage] = []
    private var systemCPU: Double?
    private var timer: Timer?
    private var loading = false
    private var isShown = false

    private let cpuLabel = numberLabel("—%", size: 30)
    private let processCountLabel = label("读取中", size: 11, color: .secondaryLabelColor)
    private let cpuBar = BarView()
    private let sortControl = NSSegmentedControl(labels: ["CPU", "内存"], trackingMode: .selectOne, target: nil, action: nil)
    private let table = NSTableView()
    private let errorLabel = label("", size: 11, color: .systemRed)

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 446))

        let heading = vstack([label("性能监测", size: 13, weight: .semibold),
                              label("", size: 11)], spacing: 2)
        sortControl.selectedSegment = 0
        sortControl.target = self
        sortControl.action = #selector(sortChanged)
        sortControl.controlSize = .small
        let activityButton = NSButton(title: "活动监视器…", target: self, action: #selector(openActivityMonitor))
        activityButton.bezelStyle = .rounded
        activityButton.controlSize = .small
        let header = hstack([heading, spacer(), sortControl, activityButton], spacing: 10)

        let summary = CardView()
        cpuBar.color = Palette.accent
        let summaryStack = vstack([label("整机 CPU 占用", size: 11, color: .secondaryLabelColor), cpuLabel, cpuBar, processCountLabel], spacing: 6)
        fillWidth(summaryStack)
        let summaryHolder = NSView()
        summaryStack.translatesAutoresizingMaskIntoConstraints = false
        summaryHolder.addSubview(summaryStack)
        NSLayoutConstraint.activate([
            summaryStack.leadingAnchor.constraint(equalTo: summaryHolder.leadingAnchor),
            summaryStack.trailingAnchor.constraint(equalTo: summaryHolder.trailingAnchor),
            summaryStack.topAnchor.constraint(equalTo: summaryHolder.topAnchor)
        ])
        pin(summaryHolder, in: summary, insets(16))

        let columns: [(String, String, CGFloat)] = [
            ("name", "进程", 220), ("pid", "PID", 60), ("cpu", "CPU", 70), ("memory", "内存", 80)
        ]
        for (identifier, title, width) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            column.minWidth = identifier == "name" ? 140 : 50
            if identifier != "name" { column.headerCell.alignment = .right }
            table.addTableColumn(column)
        }
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 26
        table.style = .plain
        table.backgroundColor = .clear
        table.usesAlternatingRowBackgroundColors = false
        table.gridStyleMask = []
        table.intercellSpacing = NSSize(width: 8, height: 0)
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.documentView = table
        let tableCard = CardView()
        pin(scroll, in: tableCard, NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8))

        let note = label("", size: 11)
        table.toolTip = "单进程 CPU 按单个核心计，可超过 100%；内存为常驻内存。"
        errorLabel.isHidden = true
        let footer = hstack([note, spacer(), errorLabel])

        for view in [header, summary, tableCard, footer] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.topAnchor.constraint(equalTo: root.topAnchor),
            summary.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            summary.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
            summary.widthAnchor.constraint(equalToConstant: 220),
            summary.heightAnchor.constraint(equalToConstant: 132),
            tableCard.leadingAnchor.constraint(equalTo: summary.trailingAnchor, constant: 16),
            tableCard.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            tableCard.topAnchor.constraint(equalTo: summary.topAnchor),
            tableCard.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        self.view = root
    }

    /// Only poll processes while the 进程 tab is on screen.
    func setShown(_ shown: Bool) {
        guard shown != isShown else { return }
        isShown = shown
        resetRefreshTimer()
        if shown { refresh() }
    }

    func resetRefreshTimer() {
        timer?.invalidate()
        timer = nil
        guard isShown else { return }
        timer = Timer.scheduledTimer(withTimeInterval: UISettings.displayRefreshSeconds, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        guard !loading else { return }
        loading = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let top = run("/usr/bin/top", ["-l", "1", "-n", "0"])
            let ps = run("/bin/ps", ["-A", "-o", "pid=,pcpu=,rss=,comm="])
            let cpu = Self.parseSystemCPU(top.1)
            let list = Self.parseProcesses(ps.1)
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading = false
                self.systemCPU = cpu
                self.processes = list
                self.cpuLabel.stringValue = cpu.map { String(format: "%.0f%%", $0) } ?? "—%"
                self.cpuBar.fraction = (cpu ?? 0) / 100
                self.processCountLabel.stringValue = "\(list.count) 个进程 · 每 \(Int(UISettings.displayRefreshSeconds)) 秒更新"
                self.errorLabel.stringValue = ps.0 == 0 && top.0 == 0 ? "" : "无法读取完整的性能数据"
                self.errorLabel.isHidden = self.errorLabel.stringValue.isEmpty
                self.updateRanking()
            }
        }
    }

    private func updateRanking() {
        let byMemory = sortControl.selectedSegment == 1
        displayed = Array(processes.sorted { left, right in
            let a = byMemory ? left.residentMB : left.cpuPercent
            let b = byMemory ? right.residentMB : right.cpuPercent
            return a == b ? left.pid < right.pid : a > b
        }.prefix(12))
        table.reloadData()
    }

    @objc private func sortChanged() { updateRanking() }
    @objc private func openActivityMonitor() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
    }

    func numberOfRows(in tableView: NSTableView) -> Int { displayed.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, displayed.indices.contains(row) else { return nil }
        let process = displayed[row]
        let identifier = tableColumn.identifier.rawValue
        let value: String
        switch identifier {
        case "name": value = process.name
        case "pid": value = String(process.pid)
        case "cpu": value = String(format: "%.1f%%", process.cpuPercent)
        default: value = String(format: "%.0f MB", process.residentMB)
        }
        let cell = NSTableCellView()
        let field = label(value, size: 12, color: identifier == "pid" ? .secondaryLabelColor : .labelColor)
        field.lineBreakMode = .byTruncatingMiddle
        field.maximumNumberOfLines = 1
        field.toolTip = identifier == "name" ? process.executable : nil
        if identifier != "name" {
            field.font = roundedFont(12, .regular)
            field.alignment = .right
        }
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    private static func parseSystemCPU(_ output: String) -> Double? {
        let pattern = try! NSRegularExpression(pattern: #"CPU usage: ([0-9.]+)% user, ([0-9.]+)% sys"#)
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = pattern.firstMatch(in: output, range: range),
              let userRange = Range(match.range(at: 1), in: output),
              let systemRange = Range(match.range(at: 2), in: output),
              let user = Double(output[userRange]), let system = Double(output[systemRange]) else { return nil }
        return min(max(user + system, 0), 100)
    }

    private static func parseProcesses(_ output: String) -> [ProcessUsage] {
        let pattern = try! NSRegularExpression(pattern: #"^\s*(\d+)\s+([0-9.]+)\s+(\d+)\s+(.+)$"#)
        return output.split(separator: "\n").compactMap { raw in
            let line = String(raw)
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = pattern.firstMatch(in: line, range: range) else { return nil }
            let parts = (1...4).compactMap { index -> String? in
                guard let range = Range(match.range(at: index), in: line) else { return nil }
                return String(line[range])
            }
            guard parts.count == 4, let pid = Int(parts[0]), let cpu = Double(parts[1]),
                  let rss = Double(parts[2]), !parts[3].isEmpty else { return nil }
            return ProcessUsage(pid: pid, cpuPercent: cpu, residentMB: rss / 1024, executable: parts[3])
        }
    }
}

// MARK: - Settings

enum UISettings {
    private static let defaults = UserDefaults.standard

    static var showMainWindowAtLaunch: Bool {
        get { defaults.object(forKey: "showMainWindowAtLaunch") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "showMainWindowAtLaunch") }
    }

    static var displayRefreshSeconds: TimeInterval {
        get {
            let value = defaults.double(forKey: "displayRefreshSeconds")
            return [2.0, 5.0, 10.0, 30.0].contains(value) ? value : 5.0
        }
        set { defaults.set(newValue, forKey: "displayRefreshSeconds") }
    }
}

/// Opening 柳风 at login, through the system Login Items list.
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static func set(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
    }

    /// Turns the login item on once, the first time this version runs; afterwards the user's choice in 设置 stands.
    static func enableByDefaultOnce() {
        let key = "loginItemDefaultApplied"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        if status == .notRegistered { try? set(true) }
    }
}

// MARK: - App

extension NSToolbarItem.Identifier {
    static let tabs = NSToolbarItem.Identifier("tabs")
    static let status = NSToolbarItem.Identifier("status")
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSToolbarDelegate {
    private var statusItem: NSStatusItem!
    private let controller = FanController()
    private let quickPanel = QuickPanelController()
    private let preferences = PreferencesController()
    private let popover = NSPopover()
    private var window: NSWindow!
    private var preferencesWindow: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        LoginItem.enableByDefaultOnce()
        UpdateManager.shared.start()
        let appMenu = NSMenu()
        func appItem(_ title: String, _ action: Selector, _ key: String = "") {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            appMenu.addItem(item)
        }
        appItem("关于柳风", #selector(showAbout))
        appItem("设置…", #selector(showPreferences), ",")
        appItem("检查更新…", #selector(checkUpdates))
        appMenu.addItem(.separator())
        appItem("风扇面板", #selector(showWindow), "0")
        appItem("擦拭模式", #selector(startCleaning))
        appMenu.addItem(.separator())
        appItem("退出柳风", #selector(quitApp), "q")
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem(title: "柳风", action: nil, keyEquivalent: "")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(NSMenuItem(title: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenu.addItem(.separator())
        windowMenu.addItem(NSMenuItem(title: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(.separator())
        let windowMenuItem = NSMenuItem(title: "窗口", action: nil, keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "柳风"
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 760, height: 540))
        let toolbar = NSToolbar(identifier: "WillowFanMain")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.centeredItemIdentifier = .tabs
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.center()

        preferencesWindow = NSWindow(contentRect: NSRect(origin: .zero, size: PreferencesController.size),
                                     styleMask: [.titled, .closable], backing: .buffered, defer: false)
        preferencesWindow.title = "柳风设置"
        preferencesWindow.contentViewController = preferences
        preferencesWindow.isReleasedWhenClosed = false
        preferencesWindow.collectionBehavior.insert(.moveToActiveSpace)
        preferencesWindow.center()
        preferences.onChange = { [weak self] in
            guard let self else { return }
            self.controller.resetRefreshTimer()
            self.controller.resetPerformanceRefreshTimer()
        }

        popover.contentViewController = quickPanel
        popover.contentSize = QuickPanelController.size
        popover.behavior = .transient
        quickPanel.onShowMain = { [weak self] in self?.showWindow() }
        quickPanel.onSettings = { [weak self] in self?.showPreferences() }
        quickPanel.onQuit = { [weak self] in self?.quitApp() }
        quickPanel.onCleaning = { [weak self] in self?.startCleaning() }
        quickPanel.onUpdates = { [weak self] in self?.checkUpdates() }
        quickPanel.onSetEnabled = { [weak self] enabled in self?.controller.setEnabled(enabled) }
        quickPanel.onCurve = { [weak self] curve in self?.controller.selectCurve(curve) }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = leafIcon(size: 18, template: true)
        statusItem.button?.toolTip = "柳风"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        controller.onSnapshot = { [weak self] snapshot in
            guard let self else { return }
            if self.popover.isShown { self.quickPanel.update(snapshot) }
        }
        if UISettings.showMainWindowAtLaunch { showWindow() }
        else { controller.ensureViewLoaded() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.controller.repairServiceIfNeeded() }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.tabs, .flexibleSpace, .status] }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace, .tabs, .flexibleSpace, .status] }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        controller.ensureViewLoaded()
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        switch itemIdentifier {
        case .tabs: item.view = controller.tabControl; item.label = "页面"
        case .status: item.view = controller.statusPill; item.label = "状态"; item.isBordered = false
        default: return nil
        }
        return item
    }

    @objc private func showWindow() {
        popover.close()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.refresh()
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.close(); return }
        guard let button = statusItem.button else { return }
        quickPanel.update(controller.snapshot)
        controller.refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    @objc private func checkUpdates() { popover.close(); UpdateManager.shared.checkForUpdates(nil) }
    @objc private func startCleaning() { popover.close(); CleaningModeController.shared.start() }

    @objc private func showAbout() {
        popover.close()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func showPreferences() {
        popover.close()
        preferencesWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() { NSApp.terminate(nil) }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) { CleaningModeController.shared.stop(); controller.stop() }
}

// MARK: - Entry

/// `--preview <png> [main|curve|process|quick|settings|menubar] [dark]` renders a screen to a PNG for review.
func renderPreview(_ arguments: [String]) -> Never {
    let output = arguments[2]
    let screen = arguments.count > 3 ? arguments[3] : "main"
    let appearance = NSAppearance(named: arguments.contains("dark") ? .darkAqua : .aqua)
    NSApp.appearance = appearance
    let view: NSView
    var keepAlive: AnyObject?
    switch screen {
    case "quick":
        let controller = QuickPanelController()
        controller.update(FanSnapshot(temperature: 68, sensor: "Te02",
                                      fans: [FanState(rpm: 2920, target: 2900, minimum: 1200, maximum: 5779, mode: "forced"),
                                             FanState(rpm: 3119, target: 3100, minimum: 1200, maximum: 6241, mode: "forced")],
                                      curve: "balanced", enabled: true, serviceRunning: true, installed: true))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: QuickPanelController.size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentViewController = controller
        view = controller.view
        keepAlive = window
    case "settings":
        let controller = PreferencesController()
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: PreferencesController.size), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = controller
        controller.viewWillAppear()
        view = controller.view
        keepAlive = window
    case "cleaning":
        view = CleaningCoverView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
    case "menubar":
        let holder = BackgroundView(frame: NSRect(x: 0, y: 0, width: 72, height: 36))
        let image = NSImageView(image: leafIcon(size: 36, template: true))
        image.contentTintColor = .labelColor
        image.frame = NSRect(x: 18, y: 0, width: 36, height: 36)
        holder.addSubview(image)
        view = holder
    default:
        let controller = FanController()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 540), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = controller
        controller.selectTab(["main": 0, "curve": 1, "process": 2][screen] ?? 0)
        if screen == "process" { controller.resetPerformanceRefreshTimer() }
        keepAlive = window
        RunLoop.current.run(until: Date().addingTimeInterval(screen == "process" ? 2.5 : 1.0))
        view = controller.view
    }
    _ = keepAlive
    view.appearance = appearance
    view.layoutSubtreeIfNeeded()
    if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output))
    }
    exit(0)
}

let app = NSApplication.shared
if CommandLine.arguments.contains("--probe-updates") {
    UpdateManager.shared.start()
    UpdateManager.shared.probe()
    let deadline = Date().addingTimeInterval(30)
    while UpdateManager.shared.probeResult == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
    let report = UpdateManager.shared.probeResult ?? ["state": "timeout"]
    let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    exit(report["state"] as? String == "error" || report["state"] as? String == "timeout" ? 1 : 0)
}
if CommandLine.arguments.contains("--diagnostics") {
    UpdateManager.shared.start()
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    let report: [String: Any] = [
        "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
        "updateFeed": UpdateManager.shared.feedURL?.absoluteString ?? "",
        "automaticChecks": UpdateManager.shared.checksAutomatically,
        "automaticInstall": UpdateManager.shared.installsAutomatically,
        "canCheckForUpdates": UpdateManager.shared.canCheck,
        "signedFeedRequired": Bundle.main.object(forInfoDictionaryKey: "SURequireSignedFeed") as? Bool ?? false,
        "accessibilityGranted": AXIsProcessTrusted(),
        "serviceNeedsUpdate": ControlService.needsUpdate()
    ]
    let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    exit(0)
}
if CommandLine.arguments.count >= 3 && CommandLine.arguments[1] == "--preview" { renderPreview(CommandLine.arguments) }
if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--preview-quick" {
    renderPreview([CommandLine.arguments[0], "--preview", CommandLine.arguments[2], "quick"])
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()
