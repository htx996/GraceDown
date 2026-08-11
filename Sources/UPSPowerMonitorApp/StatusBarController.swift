import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    static let shared = StatusBarController()

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let updateChecker = GitHubUpdateChecker(owner: "htx996", repository: "GraceDown")
    private var popover: NSPopover?
    private var store: UPSMonitorStore?
    private var cancellables = Set<AnyCancellable>()
    private var isCheckingForUpdates = false

    func configure(store: UPSMonitorStore) {
        self.store = store
        install()
        observeStore(store)
    }

    func install() {
        guard let button = statusItem.button else {
            return
        }

        button.image = StatusBarUPSIconRenderer.image(width: 31, height: 18)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateTooltip()
    }

    func invalidate() {
        closePopover()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover(from: sender)
            return
        }

        switch event.type {
        case .rightMouseUp:
            showContextMenu(from: sender)
        default:
            togglePopover(from: sender)
        }
    }

    @objc private func openSettings(_ sender: Any?) {
        closePopover()
        SettingsWindowPresenter.shared.show()
    }

    @objc private func runDiagnostics(_ sender: Any?) {
        closePopover()
        guard let store else {
            showAlert(title: "运行诊断", message: "监控服务尚未初始化。")
            return
        }

        store.start()
        store.refresh()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.showDiagnosticsResult()
        }
    }

    @objc private func openAbout(_ sender: Any?) {
        closePopover()
        AboutWindowPresenter.shared.show()
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        closePopover()
        guard !isCheckingForUpdates else {
            return
        }

        isCheckingForUpdates = true
        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let result = try await updateChecker.check(currentVersion: appVersion)
                isCheckingForUpdates = false
                showUpdateResult(result)
            } catch {
                isCheckingForUpdates = false
                showAlert(
                    title: "检查更新",
                    message: error.localizedDescription
                )
            }
        }
    }

    @objc private func quitApp(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    private func togglePopover(from button: NSStatusBarButton) {
        if popover?.isShown == true {
            closePopover()
        } else {
            showPopover(from: button)
        }
    }

    private func showPopover(from button: NSStatusBarButton) {
        guard let store else {
            return
        }

        store.start()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: MonitorPopoverView(
                store: store,
                closeAction: { [weak self] in
                    self?.closePopover()
                },
                settingsAction: { [weak self] in
                    self?.openSettings(nil)
                }
            )
        )

        self.popover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func closePopover() {
        popover?.performClose(nil)
        popover = nil
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        closePopover()

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(menuItem(
            title: "设置",
            symbolName: "gearshape",
            action: #selector(openSettings(_:)),
            keyEquivalent: ",",
            modifiers: [.command]
        ))
        menu.addItem(menuItem(
            title: "运行诊断",
            symbolName: "stethoscope",
            action: #selector(runDiagnostics(_:))
        ))
        menu.addItem(menuItem(
            title: "关于 GraceDown",
            symbolName: "info.circle",
            action: #selector(openAbout(_:))
        ))
        menu.addItem(menuItem(
            title: "检查更新",
            symbolName: "arrow.triangle.2.circlepath",
            action: #selector(checkForUpdates(_:))
        ))
        menu.addItem(.separator())
        menu.addItem(menuItem(
            title: "退出 GraceDown",
            symbolName: "power",
            action: #selector(quitApp(_:)),
            keyEquivalent: "q",
            modifiers: [.command]
        ))

        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    private func menuItem(
        title: String,
        symbolName: String,
        action: Selector,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        item.isEnabled = true
        return item
    }

    private func observeStore(_ store: UPSMonitorStore) {
        cancellables.removeAll()

        store.$selectedUPS
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateTooltip()
            }
            .store(in: &cancellables)

        store.$errorMessage
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateTooltip()
            }
            .store(in: &cancellables)
    }

    private func updateTooltip() {
        guard let button = statusItem.button else {
            return
        }

        button.toolTip = store?.menuBarTitle ?? "GraceDown"
    }

    private func showDiagnosticsResult() {
        guard let store else {
            showAlert(title: "运行诊断", message: "监控服务尚未初始化。")
            return
        }

        let snapshot = store.selectedUPS
        let lines = [
            "连接状态：\(snapshot == nil ? "未连接" : "已连接")",
            "UPS：\(snapshot?.name ?? "-")",
            "来源：\(store.sourceDescription)",
            "供电状态：\(snapshot?.status.displayName ?? "-")",
            "电量：\(snapshot?.chargePercent.map { "\($0)%" } ?? "-")",
            "剩余时间：\(snapshot?.runtimeDescription ?? "-")",
            "最后刷新：\(store.lastRefreshDescription)",
            "错误：\(store.errorMessage ?? "无")"
        ]

        showAlert(title: "运行诊断", message: lines.joined(separator: "\n"))
    }

    private func showAlert(title: String, message: String) {
        AppActivationController.shared.prepareForUserWindow()

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()

        AppActivationController.shared.hideDockIconIfNoUserWindows()
    }

    private func showUpdateResult(_ result: UpdateCheckResult) {
        switch result {
        case .updateAvailable(let currentVersion, let latestVersion, let releaseURL):
            AppActivationController.shared.prepareForUserWindow()

            let alert = NSAlert()
            alert.messageText = "发现新版本"
            alert.informativeText = "当前版本：\(currentVersion)\n最新版本：\(latestVersion)"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "打开 GitHub")
            alert.addButton(withTitle: "稍后")

            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(releaseURL)
            }

            AppActivationController.shared.hideDockIconIfNoUserWindows()
        case .upToDate(let currentVersion, let latestVersion):
            showAlert(
                title: "检查更新",
                message: "GraceDown 已是最新版本。\n当前版本：\(currentVersion)\n最新版本：\(latestVersion)"
            )
        case .noRelease:
            showAlert(
                title: "检查更新",
                message: "GitHub 仓库还没有发布 Release。"
            )
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private var appVersionDescription: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return "\(appVersion) (\(build))"
    }
}
