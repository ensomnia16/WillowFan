import AppKit
import Sparkle

final class UpdateManager: NSObject, SPUUpdaterDelegate {
    static let shared = UpdateManager()
    private lazy var controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)

    var checksAutomatically: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var installsAutomatically: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set { controller.updater.automaticallyDownloadsUpdates = newValue }
    }

    var canCheck: Bool { controller.updater.canCheckForUpdates }
    var feedURL: URL? { controller.updater.feedURL }

    private(set) var probeResult: [String: Any]?
    private var probing = false
    func start() { controller.startUpdater() }
    func probe() { probing = true; probeResult = nil; controller.updater.checkForUpdateInformation() }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        if probing { probeResult = ["state": "available", "version": item.displayVersionString, "build": item.versionString] }
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        if probing {
            var report: [String: Any] = ["state": "no-update", "details": error.localizedDescription]
            if let latest = (error as NSError).userInfo[SPULatestAppcastItemFoundKey] as? SUAppcastItem {
                report["latestVersion"] = latest.displayVersionString
                report["latestBuild"] = latest.versionString
            }
            probeResult = report
        }
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        if probing && probeResult == nil { probeResult = ["state": "error", "details": error.localizedDescription] }
    }
    @objc func checkForUpdates(_ sender: Any? = nil) { controller.checkForUpdates(sender) }
}
