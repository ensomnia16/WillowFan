import AppKit
import ServiceManagement
import ApplicationServices

final class PreferencesController: NSViewController {
    static let size = NSSize(width: 460, height: 280)
    var onChange: (() -> Void)?
    private let loginCheck = NSButton(checkboxWithTitle: "登录时启动", target: nil, action: nil)
    private let loginNote = label("", size: 11, color: .secondaryLabelColor)
    private let loginSettingsButton = NSButton(title: "登录项设置…", target: nil, action: nil)
    private let launchCheck = NSButton(checkboxWithTitle: "启动时显示风扇面板", target: nil, action: nil)
    private let checks = NSButton(checkboxWithTitle: "自动检查更新", target: nil, action: nil)
    private let installs = NSButton(checkboxWithTitle: "自动下载并安装", target: nil, action: nil)
    private let refreshPicker = NSPopUpButton()

    override func loadView() {
        let root = BackgroundView(frame: NSRect(origin: .zero, size: Self.size))
        for button in [loginCheck, launchCheck, checks, installs] { button.target = self }
        loginCheck.action = #selector(loginChanged)
        launchCheck.action = #selector(changed)
        checks.action = #selector(updateSettings)
        installs.action = #selector(updateSettings)
        loginSettingsButton.target = self
        loginSettingsButton.action = #selector(openLoginItems)
        loginSettingsButton.bezelStyle = .rounded
        loginSettingsButton.controlSize = .small
        refreshPicker.addItems(withTitles: ["2 秒", "5 秒", "10 秒", "30 秒"])
        refreshPicker.target = self
        refreshPicker.action = #selector(changed)
        refreshPicker.controlSize = .small
        let login = hstack([loginCheck, spacer(), loginSettingsButton])
        let refresh = hstack([label("刷新间隔", size: 13), spacer(), refreshPicker])
        let checkButton = NSButton(title: "检查更新…", target: self, action: #selector(checkUpdates))
        checkButton.bezelStyle = .rounded
        checkButton.controlSize = .small
        let updateRow = hstack([checks, spacer(), checkButton])
        let permission = NSButton(title: "键盘权限…", target: self, action: #selector(openPermissions))
        permission.bezelStyle = .rounded
        permission.controlSize = .small
        let cleaning = hstack([label("擦拭模式", size: 13), spacer(), permission])
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let github = NSButton(title: "GitHub", target: self, action: #selector(openGitHub))
        github.bezelStyle = .inline
        github.controlSize = .small
        let footer = hstack([label("柳风 \(version)", size: 11, color: .secondaryLabelColor), spacer(), github])
        let stack = vstack([login, loginNote, launchCheck, refresh, SeparatorLine(), updateRow, installs, SeparatorLine(), cleaning, footer], spacing: 12)
        fillWidth(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -20)
        ])
        self.view = root
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        launchCheck.state = UISettings.showMainWindowAtLaunch ? .on : .off
        let choices: [TimeInterval] = [2, 5, 10, 30]
        refreshPicker.selectItem(at: choices.firstIndex(of: UISettings.displayRefreshSeconds) ?? 1)
        checks.state = UpdateManager.shared.checksAutomatically ? .on : .off
        installs.state = UpdateManager.shared.installsAutomatically ? .on : .off
        installs.isEnabled = checks.state == .on
        showLoginStatus()
    }

    private func showLoginStatus(error: Error? = nil) {
        let status = LoginItem.status
        loginCheck.state = status == .enabled || status == .requiresApproval ? .on : .off
        loginSettingsButton.isHidden = status != .requiresApproval && error == nil
        loginNote.stringValue = error.map { "登录项未更改：\($0.localizedDescription)" } ?? (status == .requiresApproval ? "需要在系统设置中允许登录项。" : "")
        loginNote.isHidden = loginNote.stringValue.isEmpty
    }

    @objc private func loginChanged() {
        do { try LoginItem.set(loginCheck.state == .on); showLoginStatus() }
        catch { showLoginStatus(error: error) }
    }
    @objc private func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }
    @objc private func openPermissions() { CleaningModeController.openPermissions() }
    @objc private func checkUpdates() { UpdateManager.shared.checkForUpdates(nil) }
    @objc private func openGitHub() { NSWorkspace.shared.open(URL(string: "https://github.com/ensomnia16/WillowFan")!) }
    @objc private func updateSettings() {
        UpdateManager.shared.checksAutomatically = checks.state == .on
        UpdateManager.shared.installsAutomatically = installs.state == .on
        installs.isEnabled = checks.state == .on
    }
    @objc private func changed() {
        UISettings.showMainWindowAtLaunch = launchCheck.state == .on
        let choices: [TimeInterval] = [2, 5, 10, 30]
        let index = refreshPicker.indexOfSelectedItem
        if choices.indices.contains(index) { UISettings.displayRefreshSeconds = choices[index] }
        onChange?()
    }
}
