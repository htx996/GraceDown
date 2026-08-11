import AppKit
import SwiftUI

@MainActor
final class AboutWindowPresenter: NSObject, NSWindowDelegate {
    static let shared = AboutWindowPresenter()

    private let aboutWindowIdentifier = NSUserInterfaceItemIdentifier("GraceDownAboutWindow")
    private var window: NSWindow?

    func show() {
        AppActivationController.shared.prepareForUserWindow()

        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(rootView: AboutView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "关于 GraceDown"
        window.styleMask = [.titled, .closable]
        window.identifier = aboutWindowIdentifier
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        self.window = window
        AppActivationController.shared.registerUserWindow(window)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
