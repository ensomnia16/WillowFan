import AppKit

final class QuickPanelController: NSViewController {
    var onShowMain: (() -> Void)?
    var onSettings: (() -> Void)?
    var onQuit: (() -> Void)?
    var onCleaning: (() -> Void)?
    var onUpdates: (() -> Void)?
    var onSetEnabled: ((Bool) -> Void)?
    var onCurve: ((String) -> Void)?

    static let size = NSSize(width: 320, height: 374)
    private let statusPill = StatusPill()
    private let temperatureLabel = numberLabel("—°", size: 38)
    private let fansLabel = NSTextField(labelWithString: "")
    private let toggleControl = NSSwitch()
    private let curveChoices = CurveChoices(buttonHeight: 26)

    override func loadView() {
        let root = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.size))
        root.material = .popover
        root.blendingMode = .withinWindow
        root.state = .active
        let mark = NSImageView(image: leafIcon(size: 20, template: false))
        let header = hstack([mark, label("柳风", size: 14, weight: .semibold), spacer(), statusPill], spacing: 6)
        statusPill.fontSize = 11
        fansLabel.maximumNumberOfLines = 0
        fansLabel.alignment = .right
        let readings = hstack([vstack([label("最高温度", size: 11, color: .secondaryLabelColor), temperatureLabel], spacing: 2), spacer(), fansLabel])
        toggleControl.target = self
        toggleControl.action = #selector(toggle)
        toggleControl.controlSize = .small
        curveChoices.onSelect = { [weak self] in self?.onCurve?($0) }
        let controls = vstack([hstack([label("风扇调节", size: 13, weight: .medium), spacer(), toggleControl]), curveChoices], spacing: 8)
        fillWidth(controls)
        let primary = vstack([
            MenuRowButton(title: "风扇面板", symbol: "slider.horizontal.3", target: self, action: #selector(showMain)),
            MenuRowButton(title: "擦拭模式", symbol: "keyboard", target: self, action: #selector(clean))
        ], spacing: 2)
        let secondary = vstack([
            MenuRowButton(title: "设置…", symbol: "gearshape", target: self, action: #selector(showSettings)),
            MenuRowButton(title: "检查更新…", symbol: "arrow.triangle.2.circlepath", target: self, action: #selector(updates)),
            MenuRowButton(title: "退出柳风", symbol: "power", target: self, action: #selector(quit))
        ], spacing: 2)
        fillWidth(primary)
        fillWidth(secondary)
        let stack = vstack([header, readings, SeparatorLine(), controls, SeparatorLine(), primary, SeparatorLine(), secondary], spacing: 10)
        fillWidth(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -14)
        ])
        self.view = root
    }

    func update(_ snapshot: FanSnapshot) {
        ensureViewLoaded()
        temperatureLabel.stringValue = snapshot.temperature.map { String(format: "%.0f°", $0) } ?? "—°"
        temperatureLabel.textColor = Palette.heat(snapshot.temperature)
        statusPill.active = snapshot.active
        statusPill.text = snapshot.active ? "调节中" : "系统自动"
        let fans = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.paragraphSpacing = 4
        for index in 0..<2 {
            if index > 0 { fans.append(NSAttributedString(string: "\n")) }
            fans.append(NSAttributedString(string: "风扇 \(index + 1)  ", attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
            fans.append(speedText(snapshot.fans.indices.contains(index) ? snapshot.fans[index].rpm : nil, size: 16))
        }
        fans.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: fans.length))
        fansLabel.attributedStringValue = fans
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
