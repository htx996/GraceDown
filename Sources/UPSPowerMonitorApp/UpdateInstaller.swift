import AppKit
import Foundation

enum UpdateInstallerError: LocalizedError {
    case missingBundleIdentifier
    case missingUpdater
    case appIsNotInApplications(URL)

    var errorDescription: String? {
        switch self {
        case .missingBundleIdentifier:
            "自动更新失败：缺少应用标识。"
        case .missingUpdater:
            "自动更新失败：安装器缺失。"
        case .appIsNotInApplications(let appURL):
            "自动更新仅支持安装在“应用程序”中的 GraceDown。当前路径：\(appURL.path)"
        }
    }
}

struct UpdateInstaller {
    func installAndRelaunch(from dmgURL: URL) throws {
        let bundle = Bundle.main
        let appURL = bundle.bundleURL
        let bundleIdentifier = bundle.bundleIdentifier

        guard let bundleIdentifier else {
            throw UpdateInstallerError.missingBundleIdentifier
        }

        guard appURL.path.hasPrefix("/Applications/") else {
            throw UpdateInstallerError.appIsNotInApplications(appURL)
        }

        let updaterURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("GraceDownUpdater")

        guard FileManager.default.isExecutableFile(atPath: updaterURL.path) else {
            throw UpdateInstallerError.missingUpdater
        }

        let process = Process()
        process.executableURL = updaterURL
        process.arguments = [
            "--dmg", dmgURL.absoluteString,
            "--app", appURL.absoluteString,
            "--bundle-id", bundleIdentifier,
            "--parent-pid", String(ProcessInfo.processInfo.processIdentifier)
        ]

        try process.run()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.terminate(nil)
        }
    }
}
