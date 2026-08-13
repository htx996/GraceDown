import Foundation

enum UpdaterError: LocalizedError {
    case missingArgument(String)
    case invalidURL(String)
    case missingMountedApp(URL)
    case timedOutWaitingForAppExit
    case installDestinationOutsideApplications(URL)
    case commandFailed(String, Int32, String)

    var errorDescription: String? {
        switch self {
        case .missingArgument(let name):
            "缺少参数：\(name)"
        case .invalidURL(let value):
            "无效路径：\(value)"
        case .missingMountedApp(let volumeURL):
            "挂载卷内没有找到 GraceDown.app：\(volumeURL.path)"
        case .timedOutWaitingForAppExit:
            "等待 GraceDown 退出超时"
        case .installDestinationOutsideApplications(let url):
            "安装目标不在 /Applications：\(url.path)"
        case .commandFailed(let launchPath, let status, let output):
            "\(launchPath) 执行失败，退出码 \(status)：\(output)"
        }
    }
}

struct Arguments {
    let dmgURL: URL
    let currentAppURL: URL
    let bundleIdentifier: String
    let parentPID: Int32

    init(arguments: [String]) throws {
        self.dmgURL = try Self.urlValue(after: "--dmg", arguments: arguments)
        self.currentAppURL = try Self.urlValue(after: "--app", arguments: arguments)
        self.bundleIdentifier = try Self.stringValue(after: "--bundle-id", arguments: arguments)
        self.parentPID = Int32(try Self.stringValue(after: "--parent-pid", arguments: arguments)) ?? 0
    }

    private static func urlValue(after option: String, arguments: [String]) throws -> URL {
        let value = try stringValue(after: option, arguments: arguments)
        guard let url = URL(string: value), url.isFileURL else {
            throw UpdaterError.invalidURL(value)
        }
        return url
    }

    private static func stringValue(after option: String, arguments: [String]) throws -> String {
        guard let index = arguments.firstIndex(of: option),
              index + 1 < arguments.count
        else {
            throw UpdaterError.missingArgument(option)
        }
        return arguments[index + 1]
    }
}

@discardableResult
func runCommand(_ launchPath: String, _ arguments: [String]) throws -> String {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = output

    try process.run()
    process.waitUntilExit()

    let data = output.fileHandleForReading.readDataToEndOfFile()
    let text = String(data: data, encoding: .utf8) ?? ""

    guard process.terminationStatus == 0 else {
        throw UpdaterError.commandFailed(launchPath, process.terminationStatus, text)
    }

    return text
}

func waitForParentExit(pid: Int32, timeout: TimeInterval = 20) throws {
    guard pid > 0 else {
        return
    }

    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if kill(pid, 0) != 0 {
            return
        }
        Thread.sleep(forTimeInterval: 0.2)
    }

    throw UpdaterError.timedOutWaitingForAppExit
}

func mountDMG(_ dmgURL: URL) throws -> URL {
    let output = try runCommand("/usr/bin/hdiutil", [
        "attach",
        dmgURL.path,
        "-nobrowse",
        "-noverify",
        "-plist"
    ])

    guard let data = output.data(using: .utf8),
          let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
          let entities = plist["system-entities"] as? [[String: Any]]
    else {
        throw UpdaterError.commandFailed("/usr/bin/hdiutil", 0, "无法读取挂载结果")
    }

    for entity in entities {
        if let mountPoint = entity["mount-point"] as? String {
            return URL(fileURLWithPath: mountPoint, isDirectory: true)
        }
    }

    throw UpdaterError.commandFailed("/usr/bin/hdiutil", 0, "未返回挂载路径")
}

func unmount(_ volumeURL: URL) {
    _ = try? runCommand("/usr/bin/hdiutil", ["detach", volumeURL.path, "-quiet"])
}

func installApp(from volumeURL: URL, to currentAppURL: URL) throws {
    let sourceAppURL = volumeURL.appendingPathComponent("GraceDown.app", isDirectory: true)
    guard FileManager.default.fileExists(atPath: sourceAppURL.path) else {
        throw UpdaterError.missingMountedApp(volumeURL)
    }

    guard currentAppURL.path.hasPrefix("/Applications/") else {
        throw UpdaterError.installDestinationOutsideApplications(currentAppURL)
    }

    let temporaryBackupURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("GraceDown-Previous-\(UUID().uuidString).app", isDirectory: true)

    try FileManager.default.moveItem(at: currentAppURL, to: temporaryBackupURL)

    do {
        try FileManager.default.copyItem(at: sourceAppURL, to: currentAppURL)
        try? FileManager.default.removeItem(at: temporaryBackupURL)
    } catch {
        if FileManager.default.fileExists(atPath: temporaryBackupURL.path),
           !FileManager.default.fileExists(atPath: currentAppURL.path) {
            try? FileManager.default.moveItem(at: temporaryBackupURL, to: currentAppURL)
        }
        throw error
    }
}

func relaunchApp(_ appURL: URL) throws {
    try runCommand("/usr/bin/open", [appURL.path])
}

func writeFailure(_ error: Error) {
    let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("GraceDown-Updater.log")
    try? "\(Date()) \(message)\n".write(to: logURL, atomically: true, encoding: .utf8)
}

do {
    let arguments = try Arguments(arguments: Array(CommandLine.arguments.dropFirst()))
    try waitForParentExit(pid: arguments.parentPID)
    let volumeURL = try mountDMG(arguments.dmgURL)
    defer {
        unmount(volumeURL)
    }

    try installApp(from: volumeURL, to: arguments.currentAppURL)
    try relaunchApp(arguments.currentAppURL)
} catch {
    writeFailure(error)
    exit(1)
}
