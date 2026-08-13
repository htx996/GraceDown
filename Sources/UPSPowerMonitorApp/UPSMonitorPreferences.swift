import Foundation
import UPSPowerMonitorCore

enum UPSConnectionMode: String, CaseIterable, Identifiable, Sendable {
    case networkNUT
    case localIOKit

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .networkNUT:
            "NAS NUT"
        case .localIOKit:
            "本机 UPS"
        }
    }
}

struct UPSMonitorConfiguration: Sendable {
    let connectionMode: UPSConnectionMode
    let networkUPS: NetworkUPSConfiguration
    let pollIntervalSeconds: TimeInterval
    let shutdownRules: ShutdownRules
}

@MainActor
final class UPSMonitorPreferences: ObservableObject {
    @Published var connectionMode: UPSConnectionMode {
        didSet { defaults.set(connectionMode.rawValue, forKey: Keys.connectionMode) }
    }

    @Published var nasHost: String {
        didSet { defaults.set(nasHost, forKey: Keys.nasHost) }
    }

    @Published var nasPort: Int {
        didSet { defaults.set(nasPort, forKey: Keys.nasPort) }
    }

    @Published var upsName: String {
        didSet { defaults.set(upsName, forKey: Keys.upsName) }
    }

    @Published var username: String {
        didSet { defaults.set(username, forKey: Keys.username) }
    }

    @Published var password: String {
        didSet { defaults.set(password, forKey: Keys.password) }
    }

    @Published var pollIntervalSeconds: Int {
        didSet { defaults.set(pollIntervalSeconds, forKey: Keys.pollIntervalSeconds) }
    }

    @Published var autoShutdownEnabled: Bool {
        didSet { defaults.set(autoShutdownEnabled, forKey: Keys.autoShutdownEnabled) }
    }

    @Published var lowBatteryPercent: Int {
        didSet { defaults.set(lowBatteryPercent, forKey: Keys.lowBatteryPercent) }
    }

    @Published var triggerOnLowBatteryPercent: Bool {
        didSet { defaults.set(triggerOnLowBatteryPercent, forKey: Keys.triggerOnLowBatteryPercent) }
    }

    @Published var lowRuntimeMinutes: Int {
        didSet { defaults.set(lowRuntimeMinutes, forKey: Keys.lowRuntimeMinutes) }
    }

    @Published var triggerOnLowRuntime: Bool {
        didSet { defaults.set(triggerOnLowRuntime, forKey: Keys.triggerOnLowRuntime) }
    }

    @Published var shutdownGracePeriodSeconds: Int {
        didSet { defaults.set(shutdownGracePeriodSeconds, forKey: Keys.shutdownGracePeriodSeconds) }
    }

    @Published var shutdownStatusConditions: Set<PowerSourceStatus> {
        didSet { defaults.set(Self.rawStatuses(shutdownStatusConditions), forKey: Keys.shutdownStatusConditions) }
    }

    @Published var triggerOnLowBatterySignal: Bool {
        didSet { defaults.set(triggerOnLowBatterySignal, forKey: Keys.triggerOnLowBatterySignal) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.connectionMode = UPSConnectionMode(
            rawValue: defaults.string(forKey: Keys.connectionMode) ?? ""
        ) ?? .networkNUT
        self.nasHost = defaults.string(forKey: Keys.nasHost) ?? ""
        self.nasPort = Self.int(defaults, Keys.nasPort, defaultValue: 3493)
        self.upsName = defaults.string(forKey: Keys.upsName) ?? ""
        self.username = defaults.string(forKey: Keys.username) ?? ""
        self.password = defaults.string(forKey: Keys.password) ?? ""
        self.pollIntervalSeconds = Self.int(defaults, Keys.pollIntervalSeconds, defaultValue: 10)
        self.autoShutdownEnabled = defaults.object(forKey: Keys.autoShutdownEnabled) as? Bool ?? false
        self.lowBatteryPercent = Self.int(defaults, Keys.lowBatteryPercent, defaultValue: 20)
        self.triggerOnLowBatteryPercent = defaults.object(forKey: Keys.triggerOnLowBatteryPercent) as? Bool ?? true
        self.lowRuntimeMinutes = Self.int(defaults, Keys.lowRuntimeMinutes, defaultValue: 10)
        self.triggerOnLowRuntime = defaults.object(forKey: Keys.triggerOnLowRuntime) as? Bool ?? true
        self.shutdownGracePeriodSeconds = Self.int(defaults, Keys.shutdownGracePeriodSeconds, defaultValue: 60)
        self.shutdownStatusConditions = Self.statusConditions(defaults)
        self.triggerOnLowBatterySignal = defaults.object(forKey: Keys.triggerOnLowBatterySignal) as? Bool ?? true
    }

    var configuration: UPSMonitorConfiguration {
        UPSMonitorConfiguration(
            connectionMode: connectionMode,
            networkUPS: NetworkUPSConfiguration(
                host: nasHost,
                port: clamped(nasPort, 1, 65_535),
                upsName: upsName,
                username: username,
                password: password,
                timeoutSeconds: 4
            ),
            pollIntervalSeconds: TimeInterval(clamped(pollIntervalSeconds, 1, 300)),
            shutdownRules: ShutdownRules(
                isEnabled: autoShutdownEnabled,
                lowBatteryPercent: clamped(lowBatteryPercent, 1, 100),
                lowRuntimeMinutes: clamped(lowRuntimeMinutes, 1, 240),
                gracePeriodSeconds: clamped(shutdownGracePeriodSeconds, 0, 3600),
                triggerOnLowBatteryPercent: triggerOnLowBatteryPercent,
                triggerOnLowRuntime: triggerOnLowRuntime,
                statusConditions: shutdownStatusConditions,
                triggerOnLowBatterySignal: triggerOnLowBatterySignal
            )
        )
    }

    private func clamped(_ value: Int, _ minimum: Int, _ maximum: Int) -> Int {
        min(max(value, minimum), maximum)
    }

    private static func int(_ defaults: UserDefaults, _ key: String, defaultValue: Int) -> Int {
        let value = defaults.integer(forKey: key)
        return defaults.object(forKey: key) == nil ? defaultValue : value
    }

    private static func statusConditions(_ defaults: UserDefaults) -> Set<PowerSourceStatus> {
        if let rawStatuses = defaults.stringArray(forKey: Keys.shutdownStatusConditions) {
            return Set(rawStatuses.compactMap(PowerSourceStatus.init(rawValue:)))
        }

        let triggerOnBatteryPower = defaults.object(forKey: Keys.triggerOnBatteryPower) as? Bool ?? true
        return triggerOnBatteryPower ? [.onBattery] : []
    }

    private static func rawStatuses(_ statuses: Set<PowerSourceStatus>) -> [String] {
        let order: [PowerSourceStatus] = [.onBattery, .onACPower, .charged]
        return statuses.sorted { lhs, rhs in
            (order.firstIndex(of: lhs) ?? order.count) < (order.firstIndex(of: rhs) ?? order.count)
        }.map(\.rawValue)
    }

    private enum Keys {
        static let connectionMode = "connectionMode"
        static let nasHost = "nasHost"
        static let nasPort = "nasPort"
        static let upsName = "upsName"
        static let username = "username"
        static let password = "password"
        static let pollIntervalSeconds = "pollIntervalSeconds"
        static let autoShutdownEnabled = "autoShutdownEnabled"
        static let lowBatteryPercent = "lowBatteryPercent"
        static let triggerOnLowBatteryPercent = "triggerOnLowBatteryPercent"
        static let lowRuntimeMinutes = "lowRuntimeMinutes"
        static let triggerOnLowRuntime = "triggerOnLowRuntime"
        static let shutdownGracePeriodSeconds = "shutdownGracePeriodSeconds"
        static let shutdownStatusConditions = "shutdownStatusConditions"
        static let triggerOnBatteryPower = "triggerOnBatteryPower"
        static let triggerOnLowBatterySignal = "triggerOnLowBatterySignal"
    }
}
