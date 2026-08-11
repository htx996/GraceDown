import Foundation

protocol SystemShutdownExecuting: Sendable {
    func requestShutdown() throws
}

enum SystemShutdownError: Error, LocalizedError, Sendable {
    case commandFailed(Int32, String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let status, let output):
            "macOS 关机命令失败（\(status)）：\(output)"
        }
    }
}

struct AppleScriptShutdownExecutor: SystemShutdownExecuting {
    func requestShutdown() throws {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "tell application \"System Events\" to shut down"
        ]
        process.standardError = pipe
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self)
            throw SystemShutdownError.commandFailed(process.terminationStatus, output)
        }
    }
}
