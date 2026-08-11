import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var retainedDelegate: AppDelegate?

    private let preferences = UPSMonitorPreferences()
    private lazy var store = UPSMonitorStore(preferences: preferences)

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppActivationController.shared.configureForMenuBarLaunch()
        SettingsWindowPresenter.shared.configure(preferences: preferences, store: store)
        StatusBarController.shared.configure(store: store)
        store.start()
        SettingsWindowPresenter.shared.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        AppActivationController.shared.hideDockIconIfNoUserWindows()
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        SettingsWindowPresenter.shared.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        StatusBarController.shared.invalidate()
    }
}
