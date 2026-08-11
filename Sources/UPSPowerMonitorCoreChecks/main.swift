import Foundation
import UPSPowerMonitorCore

private final class CheckRunner {
    private var failures = 0

    func fail(_ message: String) {
        failures += 1
        print("FAIL: \(message)")
    }

    func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        if actual != expected {
            fail("\(message) expected \(expected), got \(actual)")
        }
    }

    func requireSnapshot(_ snapshot: PowerSourceSnapshot?, _ message: String) -> PowerSourceSnapshot {
        guard let snapshot else {
            fail(message)
            exit(1)
        }
        return snapshot
    }

    func parsesUPSDictionaryAndDerivesMenuTitle() {
    let snapshot = requireSnapshot(PowerSourceSnapshot(dictionary: [
        "Name": "CyberPower CP1500",
        "Type": "UPS",
        "Transport Type": "USB",
        "Power Source State": "Battery Power",
        "Current Capacity": 47,
        "Max Capacity": 100,
        "Time to Empty": 36,
        "Is Charging": false,
        "Is Charged": false,
        "Is Present": true,
        "Voltage": 121_000,
        "Current": -2_400
    ]), "UPS dictionary should parse")

        expectEqual(snapshot.name, "CyberPower CP1500", "name")
        expectEqual(snapshot.kind, .ups, "kind")
        expectEqual(snapshot.status, .onBattery, "status")
        expectEqual(snapshot.chargePercent, 47, "charge percent")
        expectEqual(snapshot.runtimeDescription, "36 min", "runtime")
        expectEqual(snapshot.menuTitle, "UPS 47%", "menu title")
        expectEqual(snapshot.voltageDescription, "121.0 V", "voltage")
        expectEqual(snapshot.currentDescription, "-2.4 A", "current")
    }

    func preferredSnapshotChoosesUPSBeforeInternalBattery() {
    let internalBattery = requireSnapshot(PowerSourceSnapshot(dictionary: [
        "Name": "MacBook Battery",
        "Type": "InternalBattery",
        "Transport Type": "Internal",
        "Power Source State": "AC Power",
        "Current Capacity": 80,
        "Max Capacity": 100,
        "Is Present": true
    ]), "internal battery should parse")
    let ups = requireSnapshot(PowerSourceSnapshot(dictionary: [
        "Name": "APC Back-UPS",
        "Type": "UPS",
        "Transport Type": "USB",
        "Power Source State": "AC Power",
        "Current Capacity": 94,
        "Max Capacity": 100,
        "Is Present": true
    ]), "UPS should parse")

        expectEqual(PowerSourceSnapshot.preferred(from: [internalBattery, ups]), ups, "preferred snapshot")
    }

    func capacityPercentageUsesMaxCapacityAndClamps() {
    let snapshot = requireSnapshot(PowerSourceSnapshot(dictionary: [
        "Name": "Lab UPS",
        "Type": "UPS",
        "Power Source State": "AC Power",
        "Current Capacity": 180,
        "Max Capacity": 160,
        "Is Present": true
    ]), "clamped UPS should parse")

        expectEqual(snapshot.chargePercent, 100, "clamped charge percent")
    }

    func unavailableRuntimeFormatsAsDash() {
        let snapshot = requireSnapshot(PowerSourceSnapshot(dictionary: [
            "Name": "Lab UPS",
        "Type": "UPS",
        "Power Source State": "AC Power",
        "Current Capacity": 90,
        "Max Capacity": 100,
        "Time to Empty": -1,
        "Is Present": true
    ]), "runtime UPS should parse")

        expectEqual(snapshot.runtimeDescription, "-", "unknown runtime")
    }

    func parsesNUTUPSListAndVariables() {
        let upsList = NUTResponseParser.parseUPSList(lines: [
            "BEGIN LIST UPS",
            "UPS ugreen-ups \"UGREEN NAS UPS\"",
            "END LIST UPS"
        ])

        expectEqual(upsList, [NUTUPS(name: "ugreen-ups", description: "UGREEN NAS UPS")], "NUT UPS list")

        let variables = NUTResponseParser.parseVariables(lines: [
            "BEGIN LIST VAR ugreen-ups",
            "VAR ugreen-ups ups.status \"OB LB DISCHRG\"",
            "VAR ugreen-ups battery.charge \"18\"",
            "VAR ugreen-ups battery.runtime \"420\"",
            "VAR ugreen-ups input.voltage \"219.5\"",
            "VAR ugreen-ups ups.load \"37\"",
            "VAR ugreen-ups ups.model \"Back-UPS 950\"",
            "END LIST VAR ugreen-ups"
        ], upsName: "ugreen-ups")

        expectEqual(variables["ups.status"], "OB LB DISCHRG", "NUT status")
        expectEqual(variables["battery.charge"], "18", "NUT charge")
        expectEqual(variables["ups.model"], "Back-UPS 950", "NUT model")
    }

    func mapsNUTVariablesToSnapshot() {
        let snapshot = requireSnapshot(NUTPowerSourceMapper.snapshot(
            upsName: "ugreen-ups",
            variables: [
                "ups.status": "OB LB DISCHRG",
                "battery.charge": "18",
                "battery.runtime": "420",
                "input.voltage": "219.5",
                "ups.load": "37",
                "ups.model": "Back-UPS 950",
                "device.serial": "SN1234"
            ]
        ), "NUT variables should map to a UPS snapshot")

        expectEqual(snapshot.name, "Back-UPS 950", "NUT snapshot name")
        expectEqual(snapshot.status, .onBattery, "NUT snapshot status")
        expectEqual(snapshot.chargePercent, 18, "NUT snapshot charge")
        expectEqual(snapshot.runtimeDescription, "7 min", "NUT runtime seconds to minutes")
        expectEqual(snapshot.voltageDescription, "219.5 V", "NUT input voltage")
        expectEqual(snapshot.loadDescription, "37%", "NUT load")
        expectEqual(snapshot.hasLowBatterySignal, true, "NUT low battery signal")
    }

    func shutdownPolicyWaitsForGraceAndCancelsOnRecovery() {
        let lowBatterySnapshot = requireSnapshot(PowerSourceSnapshot(dictionary: [
            "Name": "NAS UPS",
            "Type": "UPS",
            "Power Source State": "Battery Power",
            "Current Capacity": 18,
            "Max Capacity": 100,
            "Time to Empty": 7,
            "Status Flags": "OB LB DISCHRG",
            "Is Present": true
        ]), "shutdown snapshot should parse")
        let acSnapshot = requireSnapshot(PowerSourceSnapshot(dictionary: [
            "Name": "NAS UPS",
            "Type": "UPS",
            "Power Source State": "AC Power",
            "Current Capacity": 92,
            "Max Capacity": 100,
            "Time to Empty": -1,
            "Status Flags": "OL",
            "Is Present": true
        ]), "recovered snapshot should parse")
        let rules = ShutdownRules(
            isEnabled: true,
            lowBatteryPercent: 20,
            lowRuntimeMinutes: 10,
            gracePeriodSeconds: 60,
            triggerOnLowBatterySignal: true
        )
        var evaluator = ShutdownEvaluator()
        let start = Date(timeIntervalSince1970: 1_000)

        let pending = evaluator.evaluate(snapshot: lowBatterySnapshot, rules: rules, now: start)
        expectEqual(pending.action, .wait, "shutdown should wait before grace period")
        expectEqual(pending.reason, "UPS 电量 18% 低于 20%", "shutdown reason")

        let execute = evaluator.evaluate(snapshot: lowBatterySnapshot, rules: rules, now: start.addingTimeInterval(61))
        expectEqual(execute.action, .executeShutdown, "shutdown should execute after grace period")

        let recovered = evaluator.evaluate(snapshot: acSnapshot, rules: rules, now: start.addingTimeInterval(70))
        expectEqual(recovered.action, .cancel, "shutdown should cancel when AC returns")
    }

    func shutdownPolicyCanTriggerWhenUPSIsOnBatteryPower() {
        let onBatterySnapshot = requireSnapshot(PowerSourceSnapshot(dictionary: [
            "Name": "NAS UPS",
            "Type": "UPS",
            "Power Source State": "Battery Power",
            "Current Capacity": 88,
            "Max Capacity": 100,
            "Time to Empty": 42,
            "Status Flags": "OB DISCHRG",
            "Is Present": true
        ]), "on-battery shutdown snapshot should parse")
        let rules = ShutdownRules(
            isEnabled: true,
            lowBatteryPercent: 20,
            lowRuntimeMinutes: 10,
            gracePeriodSeconds: 60,
            triggerOnBatteryPower: true,
            triggerOnLowBatterySignal: false
        )
        var evaluator = ShutdownEvaluator()
        let start = Date(timeIntervalSince1970: 3_000)

        let pending = evaluator.evaluate(snapshot: onBatterySnapshot, rules: rules, now: start)
        expectEqual(pending.action, .wait, "on-battery shutdown should wait")
        expectEqual(pending.reason, "UPS 切换到电池供电", "on-battery shutdown reason")
        expectEqual(pending.secondsRemaining, 60, "on-battery grace countdown")

        let disabledRules = ShutdownRules(
            isEnabled: true,
            lowBatteryPercent: 20,
            lowRuntimeMinutes: 10,
            gracePeriodSeconds: 60,
            triggerOnBatteryPower: false,
            triggerOnLowBatterySignal: false
        )
        var disabledEvaluator = ShutdownEvaluator()
        let ignored = disabledEvaluator.evaluate(snapshot: onBatterySnapshot, rules: disabledRules, now: start)
        expectEqual(ignored.action, .none, "on-battery condition can be disabled")
    }

    func shutdownPolicyCanMatchSingleOrMultiplePowerStatuses() {
        let chargedSnapshot = requireSnapshot(PowerSourceSnapshot(dictionary: [
            "Name": "NAS UPS",
            "Type": "UPS",
            "Power Source State": "AC Power",
            "Current Capacity": 100,
            "Max Capacity": 100,
            "Is Charged": true,
            "Status Flags": "OL",
            "Is Present": true
        ]), "charged shutdown snapshot should parse")
        let acSnapshot = requireSnapshot(PowerSourceSnapshot(dictionary: [
            "Name": "NAS UPS",
            "Type": "UPS",
            "Power Source State": "AC Power",
            "Current Capacity": 88,
            "Max Capacity": 100,
            "Status Flags": "OL",
            "Is Present": true
        ]), "AC shutdown snapshot should parse")
        let multiStatusRules = ShutdownRules(
            isEnabled: true,
            lowBatteryPercent: 20,
            lowRuntimeMinutes: 10,
            gracePeriodSeconds: 60,
            statusConditions: [.charged, .onBattery],
            triggerOnLowBatterySignal: false
        )
        var multiStatusEvaluator = ShutdownEvaluator()
        let start = Date(timeIntervalSince1970: 4_000)

        let matched = multiStatusEvaluator.evaluate(snapshot: chargedSnapshot, rules: multiStatusRules, now: start)
        expectEqual(matched.action, .wait, "selected charged status should trigger")
        expectEqual(matched.reason, "UPS 电池已充满", "selected charged status reason")
        expectEqual(matched.secondsRemaining, 60, "selected charged status countdown")

        let singleStatusRules = ShutdownRules(
            isEnabled: true,
            lowBatteryPercent: 20,
            lowRuntimeMinutes: 10,
            gracePeriodSeconds: 60,
            statusConditions: [.onBattery],
            triggerOnLowBatterySignal: false
        )
        var singleStatusEvaluator = ShutdownEvaluator()
        let ignored = singleStatusEvaluator.evaluate(snapshot: acSnapshot, rules: singleStatusRules, now: start)
        expectEqual(ignored.action, .none, "unselected AC status should not trigger")
    }

    func shutdownPolicyCanDisableBatteryPercentAndRuntimeConditions() {
        let lowBatterySnapshot = requireSnapshot(PowerSourceSnapshot(dictionary: [
            "Name": "NAS UPS",
            "Type": "UPS",
            "Power Source State": "Battery Power",
            "Current Capacity": 5,
            "Max Capacity": 100,
            "Time to Empty": 2,
            "Status Flags": "OB DISCHRG",
            "Is Present": true
        ]), "low battery condition snapshot should parse")
        let disabledThresholdRules = ShutdownRules(
            isEnabled: true,
            lowBatteryPercent: 20,
            lowRuntimeMinutes: 10,
            gracePeriodSeconds: 60,
            triggerOnLowBatteryPercent: false,
            triggerOnLowRuntime: false,
            statusConditions: [],
            triggerOnLowBatterySignal: false
        )
        var disabledThresholdEvaluator = ShutdownEvaluator()
        let start = Date(timeIntervalSince1970: 5_000)

        let ignored = disabledThresholdEvaluator.evaluate(snapshot: lowBatterySnapshot, rules: disabledThresholdRules, now: start)
        expectEqual(ignored.action, .none, "disabled percent and runtime conditions should not trigger")

        let runtimeOnlyRules = ShutdownRules(
            isEnabled: true,
            lowBatteryPercent: 20,
            lowRuntimeMinutes: 10,
            gracePeriodSeconds: 60,
            triggerOnLowBatteryPercent: false,
            triggerOnLowRuntime: true,
            statusConditions: [],
            triggerOnLowBatterySignal: false
        )
        var runtimeOnlyEvaluator = ShutdownEvaluator()
        let runtimeMatched = runtimeOnlyEvaluator.evaluate(snapshot: lowBatterySnapshot, rules: runtimeOnlyRules, now: start)
        expectEqual(runtimeMatched.action, .wait, "runtime condition can be selected alone")
        expectEqual(runtimeMatched.reason, "UPS 剩余 2 分钟低于 10 分钟", "runtime-only reason")
    }

    func disabledShutdownPolicyNeverTriggers() {
        let snapshot = requireSnapshot(PowerSourceSnapshot(dictionary: [
            "Name": "NAS UPS",
            "Type": "UPS",
            "Power Source State": "Battery Power",
            "Current Capacity": 5,
            "Max Capacity": 100,
            "Status Flags": "OB LB",
            "Is Present": true
        ]), "disabled shutdown snapshot should parse")
        var evaluator = ShutdownEvaluator()

        let decision = evaluator.evaluate(
            snapshot: snapshot,
            rules: ShutdownRules(
                isEnabled: false,
                lowBatteryPercent: 20,
                lowRuntimeMinutes: 10,
                gracePeriodSeconds: 60,
                triggerOnLowBatterySignal: true
            ),
            now: Date(timeIntervalSince1970: 2_000)
        )

        expectEqual(decision.action, .none, "disabled shutdown action")
    }

    func finish() {
        if failures > 0 {
            print("\(failures) core check(s) failed")
            exit(1)
        }

        print("All UPSPowerMonitorCore checks passed")
    }
}

private let runner = CheckRunner()

runner.parsesUPSDictionaryAndDerivesMenuTitle()
runner.preferredSnapshotChoosesUPSBeforeInternalBattery()
runner.capacityPercentageUsesMaxCapacityAndClamps()
runner.unavailableRuntimeFormatsAsDash()
runner.parsesNUTUPSListAndVariables()
runner.mapsNUTVariablesToSnapshot()
runner.shutdownPolicyWaitsForGraceAndCancelsOnRecovery()
runner.shutdownPolicyCanTriggerWhenUPSIsOnBatteryPower()
runner.shutdownPolicyCanMatchSingleOrMultiplePowerStatuses()
runner.shutdownPolicyCanDisableBatteryPercentAndRuntimeConditions()
runner.disabledShutdownPolicyNeverTriggers()
runner.finish()
