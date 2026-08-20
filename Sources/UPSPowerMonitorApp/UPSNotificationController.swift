import Foundation
@preconcurrency import UserNotifications

@MainActor
final class UPSNotificationController: NSObject, UNUserNotificationCenterDelegate {
    static let shared = UPSNotificationController()

    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
    }

    func prepare() {
        Task { @MainActor in
            _ = await requestAuthorizationIfNeeded()
        }
    }

    func notifyConnectionLost(upsName: String, sourceLine: String, errorDescription: String) {
        post(
            identifier: "connection-lost",
            title: "UPS 连接中断",
            body: "\(upsName) · \(sourceLine)\n\(errorDescription)",
            playsSound: true
        )
    }

    func notifyConnectionRestored(upsName: String, sourceLine: String) {
        post(
            identifier: "connection-restored",
            title: "UPS 连接已恢复",
            body: "\(upsName) · \(sourceLine)",
            playsSound: false
        )
    }

    func notifySwitchedToBattery(upsName: String, sourceLine: String) {
        post(
            identifier: "power-battery",
            title: "UPS 已切换到电池供电",
            body: "\(upsName) · \(sourceLine)\nGraceDown 正在监控关机条件。",
            playsSound: true
        )
    }

    func notifyUtilityPowerRestored(upsName: String, sourceLine: String) {
        post(
            identifier: "power-utility",
            title: "市电供电已恢复",
            body: "\(upsName) · \(sourceLine)\n自动关机倒计时已取消。",
            playsSound: false
        )
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    private func post(
        identifier: String,
        title: String,
        body: String,
        playsSound: Bool
    ) {
        Task { @MainActor in
            guard await requestAuthorizationIfNeeded() else {
                return
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.threadIdentifier = "GraceDown.UPSStatus"
            if playsSound {
                content.sound = .default
            }

            let request = UNNotificationRequest(
                identifier: "GraceDown.\(identifier).\(UUID().uuidString)",
                content: content,
                trigger: nil
            )

            do {
                try await center.add(request)
            } catch {
                // Notification failures should not affect UPS monitoring or shutdown rules.
            }
        }
    }

    private func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }
}
