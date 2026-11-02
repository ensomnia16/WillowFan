import AppKit
import ApplicationServices

final class CleaningCoverView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        let text = NSMutableAttributedString(string: "擦拭模式\n", attributes: [
            .font: NSFont.systemFont(ofSize: 22, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85)
        ])
        text.append(NSAttributedString(string: "长按 ⌃⌥⌘K 2 秒退出\n", attributes: [
            .font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.white.withAlphaComponent(0.75)
        ]))
        text.append(NSAttributedString(string: "5 分钟后自动退出", attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.white.withAlphaComponent(0.6)
        ]))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 16
        text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
        let width = min(500, bounds.width - 40)
        text.draw(in: NSRect(x: (bounds.width - width) / 2, y: bounds.midY - 70, width: width, height: 140))
    }
}

private final class CleaningWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

final class CleaningModeController {
    static let shared = CleaningModeController()
    private var windows: [NSWindow] = []
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var unlock = UnlockGesture()
    private var startedAt: TimeInterval = 0
    private let requiredModifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
    var isActive: Bool { tap != nil }

    static func openPermissions() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func start() {
        guard !isActive else { return }
        guard AXIsProcessTrusted() else {
            permissionAlert(message: "在系统设置的“辅助功能”中允许柳风，然后重试。", inputMonitoring: false)
            return
        }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                return Unmanaged<CleaningModeController>.fromOpaque(context).takeUnretainedValue().handle(type, event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            permissionAlert(message: "无法屏蔽键盘。在系统设置中允许柳风使用输入监控，然后重试。", inputMonitoring: true)
            return
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0), !NSScreen.screens.isEmpty else {
            CFMachPortInvalidate(tap)
            return
        }
        self.tap = tap
        self.source = source
        unlock = UnlockGesture()
        startedAt = ProcessInfo.processInfo.systemUptime
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        for screen in NSScreen.screens {
            let window = CleaningWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.level = .screenSaver
            window.backgroundColor = .black
            window.isOpaque = true
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.contentView = CleaningCoverView(frame: NSRect(origin: .zero, size: screen.frame.size))
            window.isReleasedWhenClosed = false
            window.orderFrontRegardless()
            windows.append(window)
        }
        windows.first?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            if self.unlock.isComplete(at: now) || now - self.startedAt >= 300 { self.stop() }
        }
        for name in [NSApplication.didChangeScreenParametersNotification, NSApplication.willTerminateNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.stop() })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.stop() })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.stop() })
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        windows.forEach { $0.close() }
        windows.removeAll()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        unlock = UnlockGesture()
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        // If macOS disables interception, dismiss the covers immediately.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async { [weak self] in self?.stop() }
            return Unmanaged.passUnretained(event)
        }
        let matches = event.flags.intersection(requiredModifiers) == requiredModifiers
        let isK = event.getIntegerValueField(.keyboardEventKeycode) == 40
        switch type {
        case .keyDown:
            unlock.keyDown(isUnlockKey: isK, modifiersMatch: matches,
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0, at: ProcessInfo.processInfo.systemUptime)
        case .keyUp: unlock.keyUp(isUnlockKey: isK)
        case .flagsChanged: unlock.modifiersChanged(match: matches)
        default: break
        }
        return nil
    }

    private func permissionAlert(message: String, inputMonitoring: Bool) {
        let alert = NSAlert()
        alert.messageText = "需要键盘权限"
        alert.informativeText = message
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let pane = inputMonitoring ? "Privacy_ListenEvent" : "Privacy_Accessibility"
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
        }
    }
}
