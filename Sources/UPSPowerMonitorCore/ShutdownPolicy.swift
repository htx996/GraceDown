import Foundation

public struct ShutdownRules: Equatable, Sendable {
    public let isEnabled: Bool
    public let lowBatteryPercent: Int
    public let lowRuntimeMinutes: Int
    public let gracePeriodSeconds: Int
    public let triggerOnLowBatteryPercent: Bool
    public let triggerOnLowRuntime: Bool
    public let statusConditions: Set<PowerSourceStatus>
    public let triggerOnLowBatterySignal: Bool
    public let triggerOnConnectionLoss: Bool

    public var triggerOnBatteryPower: Bool {
        statusConditions.contains(.onBattery)
    }

    public init(
        isEnabled: Bool,
        lowBatteryPercent: Int,
        lowRuntimeMinutes: Int,
        gracePeriodSeconds: Int,
        triggerOnLowBatteryPercent: Bool = true,
        triggerOnLowRuntime: Bool = true,
        triggerOnBatteryPower: Bool = true,
        triggerOnLowBatterySignal: Bool,
        triggerOnConnectionLoss: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.lowBatteryPercent = lowBatteryPercent
        self.lowRuntimeMinutes = lowRuntimeMinutes
        self.gracePeriodSeconds = max(gracePeriodSeconds, 0)
        self.triggerOnLowBatteryPercent = triggerOnLowBatteryPercent
        self.triggerOnLowRuntime = triggerOnLowRuntime
        self.statusConditions = triggerOnBatteryPower ? [.onBattery] : []
        self.triggerOnLowBatterySignal = triggerOnLowBatterySignal
        self.triggerOnConnectionLoss = triggerOnConnectionLoss
    }

    public init(
        isEnabled: Bool,
        lowBatteryPercent: Int,
        lowRuntimeMinutes: Int,
        gracePeriodSeconds: Int,
        triggerOnLowBatteryPercent: Bool = true,
        triggerOnLowRuntime: Bool = true,
        statusConditions: Set<PowerSourceStatus>,
        triggerOnLowBatterySignal: Bool,
        triggerOnConnectionLoss: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.lowBatteryPercent = lowBatteryPercent
        self.lowRuntimeMinutes = lowRuntimeMinutes
        self.gracePeriodSeconds = max(gracePeriodSeconds, 0)
        self.triggerOnLowBatteryPercent = triggerOnLowBatteryPercent
        self.triggerOnLowRuntime = triggerOnLowRuntime
        self.statusConditions = statusConditions
        self.triggerOnLowBatterySignal = triggerOnLowBatterySignal
        self.triggerOnConnectionLoss = triggerOnConnectionLoss
    }
}

public enum ShutdownAction: Equatable, Sendable {
    case none
    case wait
    case executeShutdown
    case cancel
}

public struct ShutdownDecision: Equatable, Sendable {
    public let action: ShutdownAction
    public let reason: String?
    public let secondsRemaining: Int

    public init(action: ShutdownAction, reason: String? = nil, secondsRemaining: Int = 0) {
        self.action = action
        self.reason = reason
        self.secondsRemaining = max(secondsRemaining, 0)
    }
}

public struct ShutdownEvaluator: Sendable {
    private var pendingSince: Date?
    private var didExecuteForCurrentEvent = false

    public init() {}

    public mutating func evaluate(
        snapshot: PowerSourceSnapshot?,
        rules: ShutdownRules,
        now: Date
    ) -> ShutdownDecision {
        guard rules.isEnabled else {
            reset()
            return ShutdownDecision(action: .none)
        }

        guard let snapshot, let reason = triggerReason(for: snapshot, rules: rules) else {
            return cancelPendingConditionIfNeeded()
        }

        return evaluateTrigger(reason: reason, gracePeriodSeconds: rules.gracePeriodSeconds, now: now)
    }

    public mutating func evaluateConnectionLoss(
        rules: ShutdownRules,
        now: Date
    ) -> ShutdownDecision {
        guard rules.isEnabled else {
            reset()
            return ShutdownDecision(action: .none)
        }

        guard rules.triggerOnConnectionLoss else {
            return cancelPendingConditionIfNeeded()
        }

        return evaluateTrigger(
            reason: "NAS NUT 连接中断",
            gracePeriodSeconds: rules.gracePeriodSeconds,
            now: now
        )
    }

    private mutating func evaluateTrigger(
        reason: String,
        gracePeriodSeconds: Int,
        now: Date
    ) -> ShutdownDecision {
        if pendingSince == nil {
            pendingSince = now
            didExecuteForCurrentEvent = false
        }

        let elapsed = Int(now.timeIntervalSince(pendingSince ?? now))
        if elapsed >= gracePeriodSeconds {
            if didExecuteForCurrentEvent {
                return ShutdownDecision(action: .none, reason: reason)
            }

            didExecuteForCurrentEvent = true
            return ShutdownDecision(action: .executeShutdown, reason: reason)
        }

        return ShutdownDecision(
            action: .wait,
            reason: reason,
            secondsRemaining: gracePeriodSeconds - elapsed
        )
    }

    private mutating func cancelPendingConditionIfNeeded() -> ShutdownDecision {
        if pendingSince != nil || didExecuteForCurrentEvent {
            reset()
            return ShutdownDecision(action: .cancel)
        }

        return ShutdownDecision(action: .none)
    }

    private mutating func reset() {
        pendingSince = nil
        didExecuteForCurrentEvent = false
    }

    private func triggerReason(for snapshot: PowerSourceSnapshot, rules: ShutdownRules) -> String? {
        let isBatteryEvent = snapshot.status == .onBattery || snapshot.hasLowBatterySignal

        if isBatteryEvent,
           rules.triggerOnLowBatteryPercent,
           let chargePercent = snapshot.chargePercent,
           chargePercent <= rules.lowBatteryPercent {
            return "UPS 电量 \(chargePercent)% 低于 \(rules.lowBatteryPercent)%"
        }

        if isBatteryEvent,
           rules.triggerOnLowRuntime,
           let timeToEmptyMinutes = snapshot.timeToEmptyMinutes,
           timeToEmptyMinutes >= 0,
           timeToEmptyMinutes <= rules.lowRuntimeMinutes {
            return "UPS 剩余 \(timeToEmptyMinutes) 分钟低于 \(rules.lowRuntimeMinutes) 分钟"
        }

        if rules.triggerOnLowBatterySignal, snapshot.hasLowBatterySignal {
            return "UPS 发出低电量信号"
        }

        if rules.statusConditions.contains(snapshot.status) {
            return statusConditionReason(for: snapshot.status)
        }

        return nil
    }

    private func statusConditionReason(for status: PowerSourceStatus) -> String {
        switch status {
        case .onBattery:
            return "UPS 切换到电池供电"
        case .onACPower:
            return "UPS 当前为市电供电"
        case .charging:
            return "UPS 正在充电"
        case .charged:
            return "UPS 电池已充满"
        case .offline:
            return "UPS 已离线"
        case .unknown:
            return "UPS 状态未知"
        }
    }
}
