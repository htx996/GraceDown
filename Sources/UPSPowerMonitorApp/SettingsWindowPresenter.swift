import AppKit
import SwiftUI

@MainActor
final class SettingsWindowPresenter: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowPresenter()

    private let settingsFrameAutosaveName = NSWindow.FrameAutosaveName("GraceDownSettingsWindow")
    private let settingsWindowIdentifier = NSUserInterfaceItemIdentifier("GraceDownSettingsWindow")
    private let settingsContentSize = NSSize(width: 940, height: 680)

    private var preferences: UPSMonitorPreferences?
    private var store: UPSMonitorStore?
    private var window: NSWindow?

    func configure(preferences: UPSMonitorPreferences, store: UPSMonitorStore) {
        self.preferences = preferences
        self.store = store
    }

    func show() {
        guard let preferences, let store else {
            return
        }

        AppActivationController.shared.prepareForUserWindow()
        store.start()

        if let window {
            window.makeKeyAndOrderFront(nil)
            clearInitialTextSelection(in: window)
            return
        }

        let rootView = SettingsView(preferences: preferences, store: store)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "GraceDown 设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.identifier = settingsWindowIdentifier
        window.setContentSize(settingsContentSize)
        window.initialFirstResponder = nil
        window.isReleasedWhenClosed = false
        window.delegate = self
        applyStandardFrameRestoration(to: window)

        self.window = window
        AppActivationController.shared.registerUserWindow(window)
        window.makeKeyAndOrderFront(nil)
        clearInitialTextSelection(in: window)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }

    private func clearInitialTextSelection(in window: NSWindow) {
        window.makeFirstResponder(nil)

        DispatchQueue.main.async {
            if window.firstResponder is NSTextView {
                window.makeFirstResponder(nil)
            }
        }
    }

    private func applyStandardFrameRestoration(to window: NSWindow) {
        let restoredSavedFrame = window.setFrameUsingName(settingsFrameAutosaveName)
        window.setFrameAutosaveName(settingsFrameAutosaveName)

        if !restoredSavedFrame {
            window.center()
        }
    }
}
