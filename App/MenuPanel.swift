import AppKit

final class QuickPanelController: NSViewController {
    var onShowMain: (() -> Void)?
    var onSettings: (() -> Void)?
    var onQuit: (() -> Void)?
    var onCleaning: (() -> Void)?
    var onUpdates: (() -> Void)?
    var onSetEnabled: ((Bool) -> Void)?
    var onCurve: ((String) -> Void)?

    static let size = NSSize(width: 308, height: 350)
    private let statusPill = StatusPill()
    private let temperatureLabel = numberLabel("—", size: 34)
    private let fans = [NSTextField(labelWithString: ""), NSTextField(labelWithString: "")]
    private let toggleControl = NSSwitch()
    private let curveChoices = CurveChoices(buttonHeight: 29)

    override func loadView() {
        let root = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.size))
        root.material = .popover
        root.blendingMode = .withinWindow
        root.state = .active

        let mark = NSImageView(image: leafIcon(size: 23, template: true))
        mark.contentTintColor = Palette.accentText
        let header = hstack([mark, label("柳风", size: 16, weight: .semibold), spacer(), statusPill], spacing: 7)
        statusPill.fontSize = 11

        let card = CardView()
        card.radius = 12
        let temperature = hstack([temperatureLabel, telemetryLabel("°C")], spacing: 3)
        temperature.alignment = .firstBaseline
        let readings = hstack([
            vstack([telemetryLabel("最高温度"), temperature], spacing: 1), spacer(),
            vstack(fans.enumerated().map { index, reading in
                hstack([telemetryLabel("风扇 \(index + 1)"), reading], spacing: 8)
            }, spacing: 5, alignment: .trailing)
        ])
        pin(readings, in: card, NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12))

        toggleControl.target = self
        toggleControl.action = #selector(toggle)
        toggleControl.controlSize = .small
        toggleControl.setAccessibilityLabel("风扇调节")
        curveChoices.onSelect = { [weak self] in self?.onCurve?($0) }
        let controls = vstack([hstack([label("风扇调节", size: 13, weight: .semibold), spacer(), toggleControl]), curveChoices], spacing: 7)
        fillWidth(controls)
        let panel = MenuRowButton(title: "风扇面板", symbol: "slider.horizontal.3", target: self, action: #selector(showMain))
        let clean = MenuRowButton(title: "擦拭模式", symbol: "keyboard", target: self, action: #selector(clean))
        let settings = MenuRowButton(title: "设置…", symbol: "gearshape", target: self, action: #selector(showSettings))
        let updates = MenuRowButton(title: "检查更新…", symbol: "arrow.triangle.2.circlepath", target: self, action: #selector(updates))
        let quit = MenuRowButton(title: "退出柳风", symbol: "power", target: self, action: #selector(quit))
        let separator = SeparatorLine()
        let stack = vstack([header, card, controls, separator, panel, clean, settings, updates, quit], spacing: 0)
        stack.setCustomSpacing(10, after: header)
        stack.setCustomSpacing(12, after: card)
        stack.setCustomSpacing(9, after: controls)
        stack.setCustomSpacing(4, after: separator)
        fillWidth(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 13),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -13),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -10)
        ])
        self.view = root
    }

    func update(_ snapshot: FanSnapshot) {
        ensureViewLoaded()
        temperatureLabel.stringValue = snapshot.temperature.map { String(format: "%.0f", $0) } ?? "—"
        temperatureLabel.textColor = Palette.heat(snapshot.temperature)
        statusPill.active = snapshot.active
        statusPill.text = snapshot.active ? "正在调节" : "系统自动"
        for (index, reading) in fans.enumerated() {
            reading.attributedStringValue = speedText(snapshot.fans.indices.contains(index) ? snapshot.fans[index].rpm : nil, size: 15)
        }
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
