import AppKit
import SwiftUI

@MainActor
final class AppActivationController: NSObject {
    static let shared = AppActivationController()
    private let userWindows = NSHashTable<NSWindow>.weakObjects()
    private var observedWindows = Set<ObjectIdentifier>()

    func configureForMenuBarLaunch() {
        NSApp.setActivationPolicy(.accessory)
    }

    func prepareForUserWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func registerUserWindow(_ window: NSWindow) {
        let identifier = ObjectIdentifier(window)
        userWindows.add(window)
        prepareForUserWindow()

        guard !observedWindows.contains(identifier) else {
            return
        }

        observedWindows.insert(identifier)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
    }

    func hideDockIconIfNoUserWindows() {
        let visibleUserWindows = userWindows.allObjects.filter(\.isVisible)
        if visibleUserWindows.isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @objc private func userWindowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }

        userWindows.remove(window)
        observedWindows.remove(ObjectIdentifier(window))
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.willCloseNotification,
            object: window
        )

        Task { @MainActor in
            hideDockIconIfNoUserWindows()
        }
    }
}

struct UserWindowActivationObserver: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Task { @MainActor in
            guard let window = nsView.window else {
                return
            }

            AppActivationController.shared.registerUserWindow(window)
        }
    }
}
