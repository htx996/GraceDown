// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "UPSPowerMonitor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "UPSPowerMonitor", targets: ["UPSPowerMonitorApp"]),
        .executable(name: "UPSPowerMonitorCoreChecks", targets: ["UPSPowerMonitorCoreChecks"]),
        .library(name: "UPSPowerMonitorCore", targets: ["UPSPowerMonitorCore"])
    ],
    targets: [
        .target(name: "UPSPowerMonitorCore"),
        .executableTarget(
            name: "UPSPowerMonitorApp",
            dependencies: ["UPSPowerMonitorCore"]
        ),
        .executableTarget(
            name: "UPSPowerMonitorCoreChecks",
            dependencies: ["UPSPowerMonitorCore"]
        )
    ]
)
