import AppKit

final class QuickPanelController: NSViewController {
    var onShowMain: (() -> Void)?
    var onSettings: (() -> Void)?
    var onQuit: (() -> Void)?
    var onCleaning: (() -> Void)?
    var onUpdates: (() -> Void)?
    var onSetEnabled: ((Bool) -> Void)?
    var onCurve: ((String) -> Void)?

    static let size = NSSize(width: 312, height: 442)
    private let statusPill = StatusPill()
    private let temperatureLabel = numberLabel("—", size: 29)
    private let trend = ThermalTrendView()
    private let fans = [FanReadingRow("风扇 1", compact: true), FanReadingRow("风扇 2", compact: true)]
    private let sensorRows = (0..<3).map { _ in SensorRowView() }
    private let sensorEmpty = telemetryLabel("等待读数")
    private let toggleControl = NSSwitch()
    private let curveChoices = CurveChoices(buttonHeight: 25)

    override func loadView() {
        let root = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.size))
        root.material = .popover
        root.blendingMode = .withinWindow
        root.state = .active

        let mark = NSImageView(image: fanIcon(size: 19, template: true))
        mark.contentTintColor = Palette.accentText
        let header = hstack([mark, label("柳风", size: 15, weight: .semibold), spacer(), statusPill], spacing: 7)
        statusPill.fontSize = 11

        trend.showsScale = false
        trend.heightAnchor.constraint(equalToConstant: 43).isActive = true
        let degree = hstack([temperatureLabel, telemetryLabel("°C")], spacing: 4)
        degree.alignment = .firstBaseline
        let temperature = hstack([degree, trend], spacing: 14)
        let trendTitle = sectionHeading("最高温度", symbol: "thermometer.medium", trailing: telemetryLabel("近 2 分钟"))

        let fanStack = vstack([sectionHeading("风扇转速", symbol: "fanblades")] + fans, spacing: 4)
        fillWidth(fanStack)
        let sensors = vstack([sectionHeading("温度传感器", symbol: "sensor")] + sensorRows + [sensorEmpty], spacing: 0)
        sensors.setCustomSpacing(2, after: sensors.arrangedSubviews[0])
        fillWidth(sensors)

        toggleControl.target = self
        toggleControl.action = #selector(toggle)
        toggleControl.controlSize = .small
        toggleControl.setAccessibilityLabel("风扇调节")
        curveChoices.onSelect = { [weak self] in self?.onCurve?($0) }
        let controls = vstack([sectionHeading("风扇调节", symbol: "slider.horizontal.3", trailing: toggleControl), curveChoices], spacing: 4)
        fillWidth(controls)

        func row(_ left: MenuRowButton, _ right: NSView) -> NSStackView {
            let group = hstack([left, right], spacing: 4)
            group.distribution = .fillEqually
            return group
        }
        let actions = vstack([
            row(MenuRowButton(title: "风扇面板", symbol: "slider.horizontal.3", target: self, action: #selector(showMain)),
                MenuRowButton(title: "擦拭模式", symbol: "keyboard", target: self, action: #selector(clean))),
            row(MenuRowButton(title: "设置…", symbol: "gearshape", target: self, action: #selector(showSettings)),
                MenuRowButton(title: "检查更新…", symbol: "arrow.triangle.2.circlepath", target: self, action: #selector(updates))),
            row(MenuRowButton(title: "退出柳风", symbol: "power", target: self, action: #selector(quit)),
                spacer())
        ], spacing: 0)
        fillWidth(actions)

        let stack = vstack([
            header, SeparatorLine(), trendTitle, temperature, SeparatorLine(),
            fanStack, SeparatorLine(), sensors, SeparatorLine(), controls, SeparatorLine(), actions
        ], spacing: 5)
        stack.setCustomSpacing(0, after: trendTitle)
        fillWidth(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 13),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -13),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -9)
        ])
        self.view = root
    }

    func update(_ snapshot: FanSnapshot) {
        ensureViewLoaded()
        temperatureLabel.stringValue = snapshot.temperature.map { String(format: "%.0f", $0) } ?? "—"
        temperatureLabel.textColor = Palette.heat(snapshot.temperature)
        trend.samples = snapshot.history
        statusPill.active = snapshot.active
        statusPill.text = snapshot.active ? "正在调节" : "系统自动"
        for (index, reading) in fans.enumerated() {
            reading.update(snapshot.fans.indices.contains(index) ? snapshot.fans[index] : nil)
        }
        for (index, row) in sensorRows.enumerated() {
            row.update(snapshot.sensors.indices.contains(index) ? snapshot.sensors[index] : nil)
        }
        sensorEmpty.isHidden = !snapshot.sensors.isEmpty
        toggleControl.state = snapshot.enabled && snapshot.installed ? .on : .off
        toggleControl.isEnabled = snapshot.installed && snapshot.serviceRunning
        curveChoices.show(snapshot.curve, enabled: true)
    }

    @objc private func toggle() { onSetEnabled?(toggleControl.state == .on) }
    @objc private func showMain() { onShowMain?() }
    @objc private func showSettings() { onSettings?() }
    @objc private func clean() { onCleaning?() }
    @objc private func updates() { onUpdates?() }
    @objc private func quit() { onQuit?() }
}
