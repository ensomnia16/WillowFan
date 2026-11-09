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

    override func draw(_ dirtyRect: NSRect) {
        let plot = NSRect(x: 34, y: 11, width: bounds.width - 42, height: bounds.height - 22)
        guard plot.width > 0 && plot.height > 0 else { return }
        Palette.plot.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()

        let first = (samples.last?.time ?? 0) - ThermalSample.span
        let visible = samples.filter { $0.time >= first }
        let temperatures = visible.compactMap(\.degrees).filter(\.isFinite)
        let lower = min(40, floor((temperatures.min() ?? 40) / 20) * 20)
        let upper = max(100, ceil((temperatures.max() ?? 100) / 20) * 20)
        func point(_ sample: ThermalSample, _ degrees: Double) -> NSPoint {
            let elapsed = min(max((sample.time - first) / ThermalSample.span, 0), 1)
            let fraction = min(max((degrees - lower) / (upper - lower), 0), 1)
            return NSPoint(x: plot.minX + plot.width * elapsed, y: plot.minY + plot.height * fraction)
        }
        let grid = NSBezierPath()
        let axisStyle: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        for line in 0...3 {
            let y = plot.minY + plot.height * Double(line) / 3
            let value = lower + (upper - lower) * Double(line) / 3
            let tick = String(format: "%.0f°", value) as NSString
            let size = tick.size(withAttributes: axisStyle)
            tick.draw(at: NSPoint(x: plot.minX - size.width - 5, y: y - size.height / 2), withAttributes: axisStyle)
            grid.move(to: NSPoint(x: plot.minX, y: y))
            grid.line(to: NSPoint(x: plot.maxX, y: y))
        }
        for minute in 0...2 {
            let x = plot.minX + plot.width * Double(minute) / 2
            grid.move(to: NSPoint(x: x, y: plot.minY))
            grid.line(to: NSPoint(x: x, y: plot.maxY))
        }
        Palette.hair.setStroke()
        grid.lineWidth = 1
        grid.stroke()

        var runs: [[NSPoint]] = [[]]
        for sample in visible {
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
            trace.lineWidth = 1.5
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

final class SensorListController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let table = NSTableView()
    private let search = NSSearchField()
    private let count = telemetryLabel("")
    private var readings: [(String, Double)] = []
    private var displayed: [(String, Double)] = []

    override func loadView() {
        let page = NSView()
        search.placeholderString = "搜索传感器编号"
        search.setAccessibilityLabel("搜索传感器编号")
        search.delegate = self
        search.widthAnchor.constraint(equalToConstant: 190).isActive = true
        let header = hstack([label("温度传感器", size: 20, weight: .semibold), count, spacer(), search], spacing: 12)

        for (id, title, width) in [("sensor", "传感器编号", 190.0), ("temperature", "温度 (°C)", 110.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            table.addTableColumn(column)
        }
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.usesAlternatingRowBackgroundColors = true
        table.allowsColumnReordering = false
        table.selectionHighlightStyle = .none
        table.rowHeight = 23
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityLabel("实时温度传感器")
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = table

        let layout = vstack([header, scroll], spacing: 12)
        fillWidth(layout)
        pin(layout, in: page, insets(20))
        view = page
        filter()
    }

    func update(_ readings: [(String, Double)]) {
        self.readings = readings
        if isViewLoaded { filter() }
    }

    func controlTextDidChange(_ notification: Notification) { filter() }

    private func filter() {
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        displayed = query.isEmpty ? readings : readings.filter { $0.0.localizedCaseInsensitiveContains(query) }
        count.stringValue = readings.isEmpty ? "等待读数" : displayed.isEmpty ? "无匹配项" : "\(displayed.count) 项"
        table.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { displayed.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let reading = displayed[row]
        if tableColumn?.identifier.rawValue == "sensor" {
            let field = label(reading.0, size: 12)
            field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            return field
        }
        return numberLabel(String(format: "%.1f", reading.1), size: 12, color: Palette.heat(reading.1))
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

final class SensorListButton: NSButton {
    init(target: AnyObject, action: Selector) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        setButtonType(.momentaryPushIn)
        setAccessibilityLabel("查看全部温度传感器")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showCount(_ count: Int) {
        isHidden = count == 0
        let title = "全部 \(count) 项 ›"
        guard attributedTitle.string != title else { return }
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: Palette.accentText
        ])
    }
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
        let reading = NSMutableAttributedString(attributedString: speedText(fan?.rpm, size: 14))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        reading.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: reading.length))
        value.attributedStringValue = reading
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
