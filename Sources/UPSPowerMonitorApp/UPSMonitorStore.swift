import Combine
import Foundation
import UPSPowerMonitorCore

@MainActor
final class UPSMonitorStore: ObservableObject {
    @Published private(set) var snapshots: [PowerSourceSnapshot] = []
    @Published private(set) var selectedUPS: PowerSourceSnapshot?
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var shutdownDecision = ShutdownDecision(action: .none)
    @Published private(set) var shutdownCommandMessage: String?

    private let preferences: UPSMonitorPreferences
    private let shutdownExecutor: any SystemShutdownExecuting
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var shutdownTask: Task<Void, Never>?
    private var lastRefreshAttempt: Date?
    private var shutdownEvaluator = ShutdownEvaluator()

    init(
        preferences: UPSMonitorPreferences,
        shutdownExecutor: any SystemShutdownExecuting = AppleScriptShutdownExecutor()
    ) {
        self.preferences = preferences
        self.shutdownExecutor = shutdownExecutor
    }

    func start() {
        refresh()

        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
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
        lastRefreshAttempt = Date()
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

                switch result {
                case .success(let snapshots):
                    self.errorMessage = nil
                    self.snapshots = snapshots
                    self.selectedUPS = snapshots.first { $0.kind == .ups }
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.snapshots = []
                    self.selectedUPS = nil
                }

                self.evaluateShutdownPolicy()
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
