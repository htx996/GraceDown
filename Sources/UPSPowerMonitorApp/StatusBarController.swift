import AppKit
import Combine
import QuartzCore
import SwiftUI

private enum PopoverState {
    case closed
    case opening
    case open
    case closing

    var isTransitioning: Bool {
        self == .opening || self == .closing
    }
}

@MainActor
final class StatusBarController: NSObject {
    static let shared = StatusBarController()

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let updateChecker = GitHubUpdateChecker(owner: "htx996", repository: "GraceDown")
    private var popoverWindow: MenuBarMonitorPanel?
    private var localPopoverEventMonitor: Any?
    private var globalPopoverEventMonitor: Any?
    private var store: UPSMonitorStore?
    private var cancellables = Set<AnyCancellable>()
    private var isCheckingForUpdates = false
    private var popoverState = PopoverState.closed

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
        guard !popoverState.isTransitioning else {
            return
        }

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
        switch popoverState {
        case .open:
            closePopover()
        case .closed:
            showPopover(from: button)
        case .opening, .closing:
            break
        }
    }

    private func showPopover(from button: NSStatusBarButton) {
        guard popoverState == .closed, popoverWindow == nil, let store else {
            return
        }

        store.start()

        closePopover()

        let hostingController = NSHostingController(
            rootView: MonitorPopoverView(
                store: store,
                closeAction: { [weak self] in
                    self?.closePopover()
                },
                settingsAction: { [weak self] in
                    self?.openSettings(nil)
                },
                diagnosticsAction: { [weak self] in
                    self?.runDiagnostics(nil)
                }
            )
        )
        hostingController.view.frame = NSRect(x: 0, y: 0, width: MenuBarMonitorPanel.width, height: 1)

        let fittingSize = hostingController.view.fittingSize
        let panelHeight = max(1, ceil(fittingSize.height))
        let panelSize = NSSize(width: MenuBarMonitorPanel.width, height: panelHeight)
        hostingController.view.frame = NSRect(origin: .zero, size: panelSize)

        let panel = MenuBarMonitorPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.setContentSize(panelSize)
        panel.position(relativeTo: button)

        popoverWindow = panel
        popoverState = .opening
        installPopoverEventMonitors()
        panel.showWithScaleAnimation { [weak self, weak panel] in
            guard let self, let panel, self.popoverWindow === panel else {
                return
            }

            self.popoverState = .open
        }
    }

    private func closePopover() {
        guard popoverState == .open else {
            return
        }

        removePopoverEventMonitors()
        guard let panel = popoverWindow else {
            popoverState = .closed
            return
        }

        popoverState = .closing
        panel.closeWithScaleAnimation { [weak self, weak panel] in
            guard let self, let panel, self.popoverWindow === panel else {
                return
            }

            self.popoverWindow = nil
            self.popoverState = .closed
        }
    }

    private func installPopoverEventMonitors() {
        removePopoverEventMonitors()

        localPopoverEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else {
                return event
            }

            if event.type == .keyDown, event.keyCode == 53 {
                closePopover()
                return nil
            }

            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                guard let panel = popoverWindow, panel.isVisible else {
                    return event
                }

                if event.window == panel || eventIsInsideStatusButton(event) {
                    return event
                }

                closePopover()
            }

            return event
        }

        globalPopoverEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func removePopoverEventMonitors() {
        if let localPopoverEventMonitor {
            NSEvent.removeMonitor(localPopoverEventMonitor)
            self.localPopoverEventMonitor = nil
        }

        if let globalPopoverEventMonitor {
            NSEvent.removeMonitor(globalPopoverEventMonitor)
            self.globalPopoverEventMonitor = nil
        }
    }

    private func eventIsInsideStatusButton(_ event: NSEvent) -> Bool {
        guard let button = statusItem.button, event.window == button.window else {
            return false
        }

        let point = button.convert(event.locationInWindow, from: nil)
        return button.bounds.contains(point)
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
            "供电状态：\(snapshot?.powerSupplyDisplayName ?? "-")",
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

@MainActor
private final class MenuBarMonitorPanel: NSPanel {
    static let width: CGFloat = MonitorPopoverView.preferredWidth

    private static let screenPadding: CGFloat = 8
    private static let statusItemSpacing: CGFloat = 7
    private static let collapsedScale: CGFloat = 0.08
    private static let openDuration: TimeInterval = 0.18
    private static let closeDuration: TimeInterval = 0.14

    private var expandedFrame = NSRect.zero
    private var collapsedFrame = NSRect.zero
    private var animationWindow: MenuBarPanelAnimationWindow?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)

        isFloatingPanel = true
        isReleasedWhenClosed = false
        isOpaque = false
        hasShadow = true
        backgroundColor = .clear
        level = .popUpMenu
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    func position(relativeTo button: NSStatusBarButton) {
        guard let buttonWindow = button.window else {
            center()
            return
        }

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRectOnScreen = buttonWindow.convertToScreen(buttonRectInWindow)
        let screenFrame = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: Self.width, height: frame.height)
        let size = frame.size

        let proposedX = buttonRectOnScreen.midX - size.width / 2
        let x = min(
            max(proposedX, screenFrame.minX + Self.screenPadding),
            screenFrame.maxX - size.width - Self.screenPadding
        )

        let belowY = buttonRectOnScreen.minY - size.height - Self.statusItemSpacing
        let aboveY = buttonRectOnScreen.maxY + Self.statusItemSpacing
        let y: CGFloat
        let anchorY: CGFloat
        if belowY >= screenFrame.minY + Self.screenPadding {
            y = belowY
            anchorY = buttonRectOnScreen.minY
        } else {
            y = min(aboveY, screenFrame.maxY - size.height - Self.screenPadding)
            anchorY = buttonRectOnScreen.maxY
        }

        expandedFrame = NSRect(origin: NSPoint(x: x, y: y), size: size)
        collapsedFrame = Self.collapsedFrame(for: size, anchor: NSPoint(x: buttonRectOnScreen.midX, y: anchorY))
        setFrame(expandedFrame, display: false)
    }

    func showWithScaleAnimation(completion: @escaping @MainActor @Sendable () -> Void) {
        closeAnimationWindow()
        MenuBarPanelAnimationWindow.closeAll()
        hasShadow = false
        setFrame(expandedFrame, display: false)
        alphaValue = 0
        orderFrontRegardless()
        displayIfNeeded()

        guard let snapshotImage = snapshotImage() else {
            animateWindow(to: expandedFrame, alpha: 1, duration: Self.openDuration) { [weak self] in
                self?.hasShadow = true
                self?.invalidateShadow()
                completion()
            }
            return
        }

        let animationWindow = MenuBarPanelAnimationWindow(image: snapshotImage, frame: collapsedFrame)
        self.animationWindow = animationWindow
        animationWindow.alphaValue = 0.18
        animationWindow.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.openDuration
            context.allowsImplicitAnimation = true
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.92, 0.22, 1)
            animationWindow.animator().setFrame(expandedFrame, display: true)
            animationWindow.animator().alphaValue = 1
        } completionHandler: { [weak self, weak animationWindow] in
            Task { @MainActor in
                self?.alphaValue = 1
                self?.hasShadow = true
                self?.invalidateShadow()
                if self?.animationWindow === animationWindow {
                    self?.animationWindow = nil
                }
                animationWindow?.close()
                completion()
            }
        }
    }

    func closeWithScaleAnimation(completion: @escaping @MainActor @Sendable () -> Void) {
        closeAnimationWindow()
        MenuBarPanelAnimationWindow.closeAll()
        hasShadow = false
        guard let snapshotImage = snapshotImage() else {
            animateWindow(to: collapsedFrame, alpha: 0, duration: Self.closeDuration) { [weak self] in
                self?.close()
                completion()
            }
            return
        }

        let animationWindow = MenuBarPanelAnimationWindow(image: snapshotImage, frame: expandedFrame)
        self.animationWindow = animationWindow
        animationWindow.orderFrontRegardless()
        alphaValue = 0

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.closeDuration
            context.allowsImplicitAnimation = true
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 0.02, 0.78, 0.34)
            animationWindow.animator().setFrame(collapsedFrame, display: true)
            animationWindow.animator().alphaValue = 0
        } completionHandler: { [weak self, weak animationWindow] in
            Task { @MainActor in
                if self?.animationWindow === animationWindow {
                    self?.animationWindow = nil
                }
                animationWindow?.close()
                self?.close()
                completion()
            }
        }
    }

    private func closeAnimationWindow() {
        animationWindow?.close()
        animationWindow = nil
    }

    private static func collapsedFrame(for expandedSize: NSSize, anchor: NSPoint) -> NSRect {
        let size = NSSize(
            width: max(1, expandedSize.width * collapsedScale),
            height: max(1, expandedSize.height * collapsedScale)
        )

        return NSRect(
            x: anchor.x - size.width / 2,
            y: anchor.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func animateWindow(
        to frame: NSRect,
        alpha: CGFloat,
        duration: TimeInterval,
        completion: @escaping @MainActor @Sendable () -> Void
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.allowsImplicitAnimation = true
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.92, 0.22, 1)
            animator().setFrame(frame, display: true)
            animator().alphaValue = alpha
        } completionHandler: {
            Task { @MainActor in
                completion()
            }
        }
    }

    private func snapshotImage() -> NSImage? {
        guard let contentView else {
            return nil
        }

        contentView.layoutSubtreeIfNeeded()
        contentView.displayIfNeeded()

        let bounds = contentView.bounds
        guard let bitmap = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }

        bitmap.size = bounds.size
        contentView.cacheDisplay(in: bounds, to: bitmap)

        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmap)
        return image
    }
}

@MainActor
private final class MenuBarPanelAnimationWindow: NSPanel {
    private static var activeWindows: [MenuBarPanelAnimationWindow] = []

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    static func closeAll() {
        activeWindows.forEach { $0.close() }
        activeWindows.removeAll()
    }

    init(image: NSImage, frame: NSRect) {
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: frame.size))
        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]
        imageView.wantsLayer = true
        imageView.layer?.magnificationFilter = .linear
        imageView.layer?.minificationFilter = .linear

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        contentView = imageView
        isFloatingPanel = true
        isReleasedWhenClosed = false
        isOpaque = false
        hasShadow = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        level = .popUpMenu
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        Self.activeWindows.append(self)
    }

    override func close() {
        super.close()
        Self.activeWindows.removeAll { $0 === self }
    }
}
