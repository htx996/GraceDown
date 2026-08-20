import Combine
import Foundation
import UPSPowerMonitorCore

@MainActor
final class UPSMonitorStore: ObservableObject {
    @Published private(set) var snapshots: [PowerSourceSnapshot] = []
    @Published private(set) var selectedUPS: PowerSourceSnapshot?
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var lastRefreshDurationMilliseconds: Int?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var shutdownDecision = ShutdownDecision(action: .none)
    @Published private(set) var shutdownCommandMessage: String?

    private let preferences: UPSMonitorPreferences
    private let shutdownExecutor: any SystemShutdownExecuting
    private let notificationController: UPSNotificationController
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var shutdownTask: Task<Void, Never>?
    private var lastRefreshAttempt: Date?
    private var lastDetectedNetworkSourceKey: String?
    private var consecutiveNetworkRefreshFailures = 0
    private var didNotifyNetworkConnectionLoss = false
    private var lastPowerSupplyNotificationState: PowerSupplyNotificationState?
    private var lastKnownNotificationUPSName: String?
    private var lastKnownNotificationSourceLine: String?
    private var shutdownEvaluator = ShutdownEvaluator()

    init(
        preferences: UPSMonitorPreferences,
        shutdownExecutor: any SystemShutdownExecuting = AppleScriptShutdownExecutor(),
        notificationController: UPSNotificationController = .shared
    ) {
        self.preferences = preferences
        self.shutdownExecutor = shutdownExecutor
        self.notificationController = notificationController
    }

    func start() {
        refresh()

        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshIfNeeded()
                }
            }
        }
    }

    func refreshIfNeeded() {
        let now = Date()
        let interval = preferences.configuration.pollIntervalSeconds
        guard lastRefreshAttempt == nil || now.timeIntervalSince(lastRefreshAttempt ?? now) >= interval else {
            return
        }

        refresh()
    }

    func refresh() {
        guard refreshTask == nil else {
            return
        }

        let configuration = preferences.configuration
        let refreshStartedAt = Date()
        lastRefreshAttempt = refreshStartedAt
        isRefreshing = true

        refreshTask = Task { [weak self] in
            let result = await Self.readSnapshots(configuration: configuration)

            await MainActor.run {
                guard let self else {
                    return
                }

                self.refreshTask = nil
                self.isRefreshing = false
                self.lastRefresh = Date()
                self.lastRefreshDurationMilliseconds = max(
                    1,
                    Int(Date().timeIntervalSince(refreshStartedAt) * 1000)
                )

                switch result {
                case .success(let snapshots):
                    self.errorMessage = nil
                    self.snapshots = snapshots
                    self.selectedUPS = snapshots.first { $0.kind == .ups }
                    self.handleRefreshSuccessNotifications(configuration: configuration)
                    self.evaluateShutdownPolicy()
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.handleRefreshFailureNotifications(error: error, configuration: configuration)
                    self.evaluateShutdownPolicyForConnectionLoss(configuration: configuration)
                }
            }
        }
    }

    var menuBarTitle: String {
        selectedUPS?.menuTitle ?? "UPS --"
    }

    var menuBarSymbolName: String {
        selectedUPS?.symbolName ?? "battery.0percent"
    }

    var lastRefreshDescription: String {
        guard let lastRefresh else {
            return "-"
        }

        return lastRefresh.formatted(date: .omitted, time: .standard)
    }

    var sourceDescription: String {
        if let selectedUPS, let sourceDescription = selectedUPS.sourceDescription {
            return sourceDescription
        }

        switch preferences.connectionMode {
        case .networkNUT:
            let host = preferences.nasHost.trimmingCharacters(in: .whitespacesAndNewlines)
            return host.isEmpty ? "未配置 NAS" : "\(host):\(preferences.nasPort)"
        case .localIOKit:
            return "本机 IOKit"
        }
    }

    var shutdownStatusDescription: String {
        if let shutdownCommandMessage {
            return shutdownCommandMessage
        }

        switch shutdownDecision.action {
        case .wait:
            let reason = shutdownDecision.reason ?? "触发自动关机条件"
            return "\(reason)，\(shutdownDecision.secondsRemaining) 秒后关机"
        case .executeShutdown:
            return "正在请求 macOS 关机"
        case .cancel:
            return "自动关机条件已解除"
        case .none:
            return preferences.autoShutdownEnabled ? "自动关机已启用" : "自动关机未启用"
        }
    }

    var shutdownStateTitle: String {
        if shutdownDecision.action == .wait {
            return "\(shutdownDecision.secondsRemaining) 秒后"
        }

        if shutdownDecision.action == .executeShutdown {
            return "执行中"
        }

        return preferences.autoShutdownEnabled ? "已启用" : "未启用"
    }

    var shutdownRuleBrief: String {
        let rules = preferences.configuration.shutdownRules
        var conditions: [String] = []
        let selectedStatuses = orderedStatusConditions(in: rules.statusConditions)
        conditions.append(contentsOf: selectedStatuses.map(\.displayName))
        if rules.triggerOnLowBatteryPercent {
            conditions.append("低于 \(rules.lowBatteryPercent)%")
        }
        if rules.triggerOnLowRuntime {
            conditions.append("低于 \(rules.lowRuntimeMinutes) 分钟")
        }
        if rules.triggerOnLowBatterySignal {
            conditions.append("低电量")
        }
        if rules.triggerOnConnectionLoss, preferences.connectionMode == .networkNUT {
            conditions.append("连接中断")
        }

        return conditions.isEmpty ? "未选择" : conditions.joined(separator: " / ")
    }

    var shutdownGraceDescription: String {
        "\(preferences.configuration.shutdownRules.gracePeriodSeconds) 秒确认"
    }

    var lowBatteryMonitoringDescription: String {
        let rules = preferences.configuration.shutdownRules
        return rules.triggerOnLowBatterySignal || rules.triggerOnLowBatteryPercent ? "已监听" : "未监听"
    }

    var shutdownRuleSummary: String {
        let rules = preferences.configuration.shutdownRules
        var conditions: [String] = []
        let selectedStatuses = orderedStatusConditions(in: rules.statusConditions)
        if !selectedStatuses.isEmpty {
            let statusText = selectedStatuses.map(\.displayName).joined(separator: " / ")
            conditions.append("状态为 \(statusText)")
        }
        if rules.triggerOnLowBatteryPercent {
            conditions.append("低于 \(rules.lowBatteryPercent)%")
        }
        if rules.triggerOnLowRuntime {
            conditions.append("低于 \(rules.lowRuntimeMinutes) 分钟")
        }
        if rules.triggerOnLowBatterySignal {
            conditions.append("UPS 低电量信号")
        }
        if rules.triggerOnConnectionLoss, preferences.connectionMode == .networkNUT {
            conditions.append("NAS NUT 连接中断")
        }

        let conditionText = conditions.isEmpty ? "未选择关机条件" : conditions.joined(separator: " 或 ")
        return "条件持续 \(rules.gracePeriodSeconds) 秒后关机 · \(conditionText)"
    }

    private func orderedStatusConditions(in statuses: Set<PowerSourceStatus>) -> [PowerSourceStatus] {
        let order: [PowerSourceStatus] = [.onBattery, .onACPower, .charged]
        let ordered = order.filter { statuses.contains($0) }
        let remaining = statuses.filter { !order.contains($0) }.sorted { $0.displayName < $1.displayName }
        return ordered + remaining
    }

    private static func readSnapshots(
        configuration: UPSMonitorConfiguration
    ) async -> Result<[PowerSourceSnapshot], Error> {
        await Task.detached(priority: .utility) {
            do {
                let provider: any PowerSourceProviding
                switch configuration.connectionMode {
                case .networkNUT:
                    provider = NUTPowerSourceProvider(configuration: configuration.networkUPS)
                case .localIOKit:
                    provider = IOKitPowerSourceProvider()
                }

                return .success(try provider.snapshots())
            } catch {
                return .failure(error)
            }
        }.value
    }

    private func evaluateShutdownPolicy() {
        let decision = shutdownEvaluator.evaluate(
            snapshot: selectedUPS,
            rules: preferences.configuration.shutdownRules,
            now: Date()
        )
        handleShutdownDecision(decision)
    }

    private func evaluateShutdownPolicyForConnectionLoss(configuration: UPSMonitorConfiguration) {
        guard configuration.connectionMode == .networkNUT else {
            evaluateShutdownPolicy()
            return
        }

        guard lastDetectedNetworkSourceKey == Self.networkSourceKey(for: configuration.networkUPS) else {
            evaluateShutdownPolicy()
            return
        }

        let decision = shutdownEvaluator.evaluateConnectionLoss(
            rules: preferences.configuration.shutdownRules,
            now: Date()
        )
        handleShutdownDecision(decision)
    }

    private static func networkSourceKey(for configuration: NetworkUPSConfiguration) -> String {
        [
            configuration.host.lowercased(),
            String(configuration.port),
            configuration.upsName.lowercased()
        ].joined(separator: ":")
    }

    private func handleRefreshSuccessNotifications(configuration: UPSMonitorConfiguration) {
        if configuration.connectionMode == .networkNUT {
            let sourceKey = Self.networkSourceKey(for: configuration.networkUPS)
            let isSameKnownSource = lastDetectedNetworkSourceKey == sourceKey

            if !isSameKnownSource {
                lastPowerSupplyNotificationState = nil
                didNotifyNetworkConnectionLoss = false
            }

            consecutiveNetworkRefreshFailures = 0

            if let selectedUPS {
                updateLastKnownNotificationDetails(snapshot: selectedUPS, configuration: configuration)

                if didNotifyNetworkConnectionLoss, isSameKnownSource {
                    notificationController.notifyConnectionRestored(
                        upsName: notificationUPSName(snapshot: selectedUPS),
                        sourceLine: notificationSourceLine(snapshot: selectedUPS, configuration: configuration)
                    )
                }

                didNotifyNetworkConnectionLoss = false
                lastDetectedNetworkSourceKey = sourceKey
            }
        } else {
            consecutiveNetworkRefreshFailures = 0
            didNotifyNetworkConnectionLoss = false
        }

        guard let selectedUPS else {
            return
        }

        notifyPowerSupplyTransitionIfNeeded(snapshot: selectedUPS, configuration: configuration)
    }

    private func handleRefreshFailureNotifications(error: Error, configuration: UPSMonitorConfiguration) {
        guard configuration.connectionMode == .networkNUT else {
            return
        }

        guard lastDetectedNetworkSourceKey == Self.networkSourceKey(for: configuration.networkUPS) else {
            return
        }

        consecutiveNetworkRefreshFailures += 1

        guard consecutiveNetworkRefreshFailures >= 3, !didNotifyNetworkConnectionLoss else {
            return
        }

        didNotifyNetworkConnectionLoss = true
        notificationController.notifyConnectionLost(
            upsName: lastKnownNotificationUPSName ?? "UPS",
            sourceLine: lastKnownNotificationSourceLine ?? Self.networkSourceLine(configuration: configuration.networkUPS),
            errorDescription: error.localizedDescription
        )
    }

    private func notifyPowerSupplyTransitionIfNeeded(
        snapshot: PowerSourceSnapshot,
        configuration: UPSMonitorConfiguration
    ) {
        guard let currentState = PowerSupplyNotificationState(snapshot: snapshot) else {
            return
        }

        defer {
            lastPowerSupplyNotificationState = currentState
        }

        guard let previousState = lastPowerSupplyNotificationState,
              previousState != currentState else {
            return
        }

        switch currentState {
        case .battery:
            notificationController.notifySwitchedToBattery(
                upsName: notificationUPSName(snapshot: snapshot),
                sourceLine: notificationSourceLine(snapshot: snapshot, configuration: configuration)
            )
        case .utility:
            guard previousState == .battery else {
                return
            }
            notificationController.notifyUtilityPowerRestored(
                upsName: notificationUPSName(snapshot: snapshot),
                sourceLine: notificationSourceLine(snapshot: snapshot, configuration: configuration)
            )
        }
    }

    private func updateLastKnownNotificationDetails(
        snapshot: PowerSourceSnapshot,
        configuration: UPSMonitorConfiguration
    ) {
        lastKnownNotificationUPSName = notificationUPSName(snapshot: snapshot)
        lastKnownNotificationSourceLine = notificationSourceLine(snapshot: snapshot, configuration: configuration)
    }

    private func notificationUPSName(snapshot: PowerSourceSnapshot) -> String {
        snapshot.name.isEmpty ? "UPS" : snapshot.name
    }

    private func notificationSourceLine(
        snapshot: PowerSourceSnapshot,
        configuration: UPSMonitorConfiguration
    ) -> String {
        if let sourceDescription = snapshot.sourceDescription,
           let separator = sourceDescription.lastIndex(of: "/"),
           separator < sourceDescription.index(before: sourceDescription.endIndex) {
            let address = String(sourceDescription[..<separator])
            let upsName = String(sourceDescription[sourceDescription.index(after: separator)...])
            return "\(upsName) · \(address)"
        }

        switch configuration.connectionMode {
        case .networkNUT:
            return Self.networkSourceLine(configuration: configuration.networkUPS)
        case .localIOKit:
            return "本机 IOKit"
        }
    }

    private static func networkSourceLine(configuration: NetworkUPSConfiguration) -> String {
        let upsName = configuration.upsName.isEmpty ? "UPS" : configuration.upsName
        return "\(upsName) · \(configuration.host):\(configuration.port)"
    }

    private func handleShutdownDecision(_ decision: ShutdownDecision) {
        shutdownDecision = decision

        switch decision.action {
        case .executeShutdown:
            requestSystemShutdown(reason: decision.reason)
        case .cancel:
            shutdownCommandMessage = nil
        case .none, .wait:
            break
        }
    }

    private func requestSystemShutdown(reason: String?) {
        guard shutdownTask == nil else {
            return
        }

        shutdownCommandMessage = reason.map { "正在请求 macOS 关机：\($0)" } ?? "正在请求 macOS 关机"

        let executor = shutdownExecutor
        shutdownTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                do {
                    try executor.requestShutdown()
                    return Result<Void, Error>.success(())
                } catch {
                    return Result<Void, Error>.failure(error)
                }
            }.value

            await MainActor.run {
                self.shutdownTask = nil
                switch result {
                case .success:
                    self.shutdownCommandMessage = "macOS 关机命令已发出"
                case .failure(let error):
                    self.shutdownCommandMessage = error.localizedDescription
                }
            }
        }
    }
}

private enum PowerSupplyNotificationState {
    case battery
    case utility

    init?(snapshot: PowerSourceSnapshot) {
        let flags = Set(snapshot.statusFlags.map { $0.uppercased() })

        if flags.contains("OB") || flags.contains("DISCHRG") {
            self = .battery
            return
        }

        if flags.contains("OL") {
            self = .utility
            return
        }

        switch snapshot.status {
        case .onBattery:
            self = .battery
        case .onACPower, .charging, .charged:
            self = .utility
        case .offline, .unknown:
            return nil
        }
    }
}
