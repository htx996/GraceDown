import Foundation

public enum PowerSourceKind: String, Equatable, Sendable {
    case ups
    case internalBattery
    case other

    init(type: String?, transportType: String?) {
        let sourceType = type?.lowercased()
        let transport = transportType?.lowercased()

        if sourceType == "ups" || transport == "usb" || transport == "ethernet" || transport == "serial" {
            self = .ups
        } else if sourceType == "internalbattery" || transport == "internal" {
            self = .internalBattery
        } else {
            self = .other
        }
    }

    public var displayName: String {
        switch self {
        case .ups:
            "UPS"
        case .internalBattery:
            "内置电池"
        case .other:
            "电源"
        }
    }
}

public enum PowerSourceStatus: String, CaseIterable, Hashable, Sendable {
    case onACPower
    case onBattery
    case charging
    case charged
    case offline
    case unknown

    init(rawState: String?, isCharging: Bool, isCharged: Bool) {
        if rawState == "Battery Power" {
            self = .onBattery
        } else if isCharged {
            self = .charged
        } else if isCharging {
            self = .charging
        } else if rawState == "AC Power" {
            self = .onACPower
        } else if rawState == "Off Line" {
            self = .offline
        } else {
            self = .unknown
        }
    }

    public var displayName: String {
        switch self {
        case .onACPower:
            "市电供电"
        case .onBattery:
            "电池供电"
        case .charging:
            "正在充电"
        case .charged:
            "已充满"
        case .offline:
            "已离线"
        case .unknown:
            "未知状态"
        }
    }
}

public struct PowerSourceSnapshot: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let kind: PowerSourceKind
    public let transportType: String?
    public let status: PowerSourceStatus
    public let currentCapacity: Int?
    public let maxCapacity: Int?
    public let timeToEmptyMinutes: Int?
    public let timeToFullChargeMinutes: Int?
    public let isPresent: Bool
    public let isCharging: Bool
    public let isCharged: Bool
    public let voltageMillivolts: Int?
    public let currentMilliamps: Int?
    public let loadPercent: Int?
    public let realPowerWatts: Double?
    public let health: String?
    public let serialNumber: String?
    public let statusFlags: [String]
    public let sourceDescription: String?

    public init?(
        dictionary: [String: Any]
    ) {
        let isPresent = Self.boolValue(dictionary["Is Present"]) ?? true
        guard isPresent else {
            return nil
        }

        let name = Self.stringValue(dictionary["Name"]) ?? "Unknown UPS"
        let type = Self.stringValue(dictionary["Type"])
        let transportType = Self.stringValue(dictionary["Transport Type"])
        let isCharging = Self.boolValue(dictionary["Is Charging"]) ?? false
        let isCharged = Self.boolValue(dictionary["Is Charged"]) ?? false
        let rawState = Self.stringValue(dictionary["Power Source State"])
        let sourceID = Self.stringValue(dictionary["Power Source ID"])

        self.id = sourceID ?? [type, transportType, name].compactMap(\.self).joined(separator: ":")
        self.name = name
        self.kind = PowerSourceKind(type: type, transportType: transportType)
        self.transportType = transportType
        self.status = PowerSourceStatus(rawState: rawState, isCharging: isCharging, isCharged: isCharged)
        self.currentCapacity = Self.intValue(dictionary["Current Capacity"])
        self.maxCapacity = Self.intValue(dictionary["Max Capacity"])
        self.timeToEmptyMinutes = Self.intValue(dictionary["Time to Empty"])
        self.timeToFullChargeMinutes = Self.intValue(dictionary["Time to Full Charge"])
        self.isPresent = isPresent
        self.isCharging = isCharging
        self.isCharged = isCharged
        self.voltageMillivolts = Self.intValue(dictionary["Voltage"])
        self.currentMilliamps = Self.intValue(dictionary["Current"])
        self.loadPercent = Self.intValue(dictionary["Load Percent"])
        self.realPowerWatts = Self.doubleValue(dictionary["Real Power Watts"])
        self.health = Self.stringValue(dictionary["BatteryHealth"])
        self.serialNumber = Self.stringValue(dictionary["Hardware Serial Number"])
        self.statusFlags = Self.statusFlagsValue(dictionary["Status Flags"])
        self.sourceDescription = Self.stringValue(dictionary["Source Description"])
    }

    public static func preferred(from snapshots: [PowerSourceSnapshot]) -> PowerSourceSnapshot? {
        snapshots.first { $0.kind == .ups } ?? snapshots.first
    }

    public var chargePercent: Int? {
        guard let currentCapacity else {
            return nil
        }

        let rawPercent: Int
        if let maxCapacity, maxCapacity > 0 {
            rawPercent = Int((Double(currentCapacity) / Double(maxCapacity) * 100).rounded())
        } else {
            rawPercent = currentCapacity
        }

        return min(max(rawPercent, 0), 100)
    }

    public var menuTitle: String {
        guard let chargePercent else {
            return "\(kind.displayName) --"
        }
        return "\(kind.displayName) \(chargePercent)%"
    }

    public var runtimeDescription: String {
        if let timeToEmptyMinutes, timeToEmptyMinutes >= 0 {
            return Self.formatMinutes(timeToEmptyMinutes)
        }

        if let timeToFullChargeMinutes, timeToFullChargeMinutes >= 0 {
            return Self.formatMinutes(timeToFullChargeMinutes)
        }

        return "-"
    }

    public var voltageDescription: String {
        guard let voltageMillivolts else {
            return "-"
        }
        return String(format: "%.1f V", Double(voltageMillivolts) / 1000)
    }

    public var currentDescription: String {
        guard let currentMilliamps else {
            return "-"
        }
        return String(format: "%.1f A", Double(currentMilliamps) / 1000)
    }

    public var powerDescription: String {
        if let realPowerWatts {
            return String(format: "%.0f W", realPowerWatts)
        }

        guard let voltageMillivolts, let currentMilliamps else {
            return "-"
        }
        let watts = abs(Double(voltageMillivolts) * Double(currentMilliamps) / 1_000_000)
        return String(format: "%.0f W", watts)
    }

    public var loadDescription: String {
        if let loadPercent {
            return "\(min(max(loadPercent, 0), 100))%"
        }

        return powerDescription
    }

    public var hasLowBatterySignal: Bool {
        let flags = Set(statusFlags.map { $0.uppercased() })
        return flags.contains("LB") || flags.contains("FSD")
    }

    public var powerSupplyDisplayName: String {
        let flags = Set(statusFlags.map { $0.uppercased() })

        if flags.contains("OB") || flags.contains("DISCHRG") {
            return "电池供电"
        }

        if flags.contains("OL") {
            return "市电供电"
        }

        switch status {
        case .onBattery:
            return "电池供电"
        case .onACPower, .charging, .charged:
            return "市电供电"
        case .offline:
            return "已离线"
        case .unknown:
            return "未知状态"
        }
    }

    public var symbolName: String {
        guard let chargePercent else {
            return "battery.0percent"
        }

        switch chargePercent {
        case 76...100:
            return status == .onBattery ? "battery.100percent" : "battery.100percent.bolt"
        case 51...75:
            return "battery.75percent"
        case 26...50:
            return "battery.50percent"
        case 1...25:
            return "battery.25percent"
        default:
            return "battery.0percent"
        }
    }

    private static func formatMinutes(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours) h"
            }
            return "\(hours) h \(remainingMinutes) min"
        }

        return "\(minutes) min"
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String {
            return value
        }

        if let value = value as? NSNumber {
            return value.stringValue
        }

        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }

        if let value = value as? NSNumber {
            return value.intValue
        }

        if let value = value as? String {
            return Int(value)
        }

        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }

        if let value = value as? Float {
            return Double(value)
        }

        if let value = value as? Int {
            return Double(value)
        }

        if let value = value as? NSNumber {
            return value.doubleValue
        }

        if let value = value as? String {
            return Double(value)
        }

        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }

        if let value = value as? NSNumber {
            return value.boolValue
        }

        if let value = value as? String {
            switch value.lowercased() {
            case "true", "yes", "1":
                return true
            case "false", "no", "0":
                return false
            default:
                return nil
            }
        }

        return nil
    }

    private static func statusFlagsValue(_ value: Any?) -> [String] {
        if let value = value as? [String] {
            return value
        }

        guard let value = stringValue(value) else {
            return []
        }

        return value
            .split(whereSeparator: { $0 == " " || $0 == "," || $0 == ";" })
            .map(String.init)
    }
}
