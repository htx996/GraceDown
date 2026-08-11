import Foundation

public enum NUTPowerSourceMapper {
    public static func snapshot(
        upsName: String,
        variables: [String: String],
        sourceDescription: String? = nil
    ) -> PowerSourceSnapshot? {
        let statusFlags = statusFlags(from: variables["ups.status"])
        let chargePercent = intValue(variables["battery.charge"])
        let runtimeMinutes = runtimeMinutes(fromSecondsValue: variables["battery.runtime"])
        let voltageMillivolts = millivolts(from: variables["input.voltage"] ?? variables["output.voltage"])
        let loadPercent = intValue(variables["ups.load"])
        let realPowerWatts = doubleValue(variables["ups.realpower"] ?? variables["ups.power"])

        let modelName = firstNonEmpty([
            variables["device.model"],
            variables["ups.model"],
            [variables["ups.mfr"], variables["ups.model"]].compactMap { $0 }.joined(separator: " "),
            upsName
        ]) ?? upsName

        return PowerSourceSnapshot(dictionary: [
            "Power Source ID": "nut:\(upsName)",
            "Name": modelName,
            "Type": "UPS",
            "Transport Type": "Ethernet",
            "Power Source State": powerSourceState(fromStatusFlags: statusFlags),
            "Current Capacity": chargePercent as Any,
            "Max Capacity": 100,
            "Time to Empty": runtimeMinutes as Any,
            "Is Charging": statusFlags.contains("CHRG"),
            "Is Charged": (chargePercent ?? 0) >= 100 && statusFlags.contains("OL"),
            "Is Present": true,
            "Voltage": voltageMillivolts as Any,
            "Load Percent": loadPercent as Any,
            "Real Power Watts": realPowerWatts as Any,
            "BatteryHealth": batteryHealth(from: variables) as Any,
            "Hardware Serial Number": variables["device.serial"] as Any,
            "Status Flags": statusFlags.joined(separator: " "),
            "Source Description": sourceDescription as Any
        ])
    }

    private static func statusFlags(from value: String?) -> [String] {
        (value ?? "")
            .split(whereSeparator: { $0 == " " || $0 == "," || $0 == ";" })
            .map { String($0).uppercased() }
    }

    private static func powerSourceState(fromStatusFlags flags: [String]) -> String {
        if flags.contains("OB") || flags.contains("LB") || flags.contains("DISCHRG") {
            return "Battery Power"
        }

        if flags.contains("OL") {
            return "AC Power"
        }

        if flags.contains("OFF") {
            return "Off Line"
        }

        return "Unknown"
    }

    private static func runtimeMinutes(fromSecondsValue value: String?) -> Int? {
        guard let seconds = doubleValue(value), seconds >= 0 else {
            return nil
        }

        return Int(seconds / 60)
    }

    private static func millivolts(from value: String?) -> Int? {
        guard let volts = doubleValue(value) else {
            return nil
        }

        return Int((volts * 1000).rounded())
    }

    private static func intValue(_ value: String?) -> Int? {
        guard let value, let double = Double(value) else {
            return nil
        }

        return Int(double.rounded())
    }

    private static func doubleValue(_ value: String?) -> Double? {
        guard let value else {
            return nil
        }

        return Double(value)
    }

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        values.compactMap { value -> String? in
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }

            return value
        }.first
    }

    private static func batteryHealth(from variables: [String: String]) -> String? {
        variables["battery.status"] ?? variables["battery.health"]
    }
}
