import Foundation

public struct NetworkUPSConfiguration: Equatable, Sendable {
    public let host: String
    public let port: Int
    public let upsName: String
    public let username: String
    public let password: String
    public let timeoutSeconds: TimeInterval

    public init(
        host: String,
        port: Int = 3493,
        upsName: String = "",
        username: String = "",
        password: String = "",
        timeoutSeconds: TimeInterval = 4
    ) {
        self.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        self.port = port
        self.upsName = upsName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        self.password = password
        self.timeoutSeconds = timeoutSeconds
    }
}

public enum NUTPowerSourceError: Error, LocalizedError, Sendable {
    case missingHost
    case noUPSFound
    case streamUnavailable
    case connectionTimedOut
    case connectionFailed(String)
    case writeFailed
    case readTimedOut
    case serverError(String)

    public var errorDescription: String? {
        switch self {
        case .missingHost:
            "请先配置 NAS 地址"
        case .noUPSFound:
            "NAS NUT 服务没有返回 UPS"
        case .streamUnavailable:
            "无法创建到 NAS 的网络流"
        case .connectionTimedOut:
            "连接 NAS NUT 服务超时"
        case .connectionFailed(let message):
            if message.localizedCaseInsensitiveContains("network is down") {
                "连接 NAS NUT 服务失败：macOS 已阻止 GraceDown 访问本地网络，请在系统设置 > 隐私与安全性 > 本地网络中允许 GraceDown。"
            } else {
                "连接 NAS NUT 服务失败：\(message)"
            }
        case .writeFailed:
            "发送 NUT 命令失败"
        case .readTimedOut:
            "读取 NAS UPS 数据超时"
        case .serverError(let message):
            "NUT 服务返回错误：\(message)"
        }
    }
}

public struct NUTPowerSourceProvider: PowerSourceProviding, Sendable {
    public let configuration: NetworkUPSConfiguration

    public init(configuration: NetworkUPSConfiguration) {
        self.configuration = configuration
    }

    public func snapshots() throws -> [PowerSourceSnapshot] {
        guard !configuration.host.isEmpty else {
            throw NUTPowerSourceError.missingHost
        }

        let client = NUTClient(configuration: configuration)
        let upsName = try client.resolveUPSName()
        let variables = try client.variables(for: upsName)
        let sourceDescription = "\(configuration.host):\(configuration.port)/\(upsName)"

        return [
            NUTPowerSourceMapper.snapshot(
                upsName: upsName,
                variables: variables,
                sourceDescription: sourceDescription
            )
        ].compactMap { $0 }
    }
}

public struct NUTClient: Sendable {
    private let configuration: NetworkUPSConfiguration

    public init(configuration: NetworkUPSConfiguration) {
        self.configuration = configuration
    }

    public func resolveUPSName() throws -> String {
        if !configuration.upsName.isEmpty {
            return configuration.upsName
        }

        return try withConnection { connection in
            try authenticateIfNeeded(connection)
            let lines = try connection.multilineResponse(
                command: "LIST UPS",
                endLinePrefix: "END LIST UPS"
            )
            guard let firstUPS = NUTResponseParser.parseUPSList(lines: lines).first else {
                throw NUTPowerSourceError.noUPSFound
            }
            return firstUPS.name
        }
    }

    public func variables(for upsName: String) throws -> [String: String] {
        try withConnection { connection in
            try authenticateIfNeeded(connection)
            let lines = try connection.multilineResponse(
                command: "LIST VAR \(upsName)",
                endLinePrefix: "END LIST VAR"
            )
            return NUTResponseParser.parseVariables(lines: lines, upsName: upsName)
        }
    }

    private func withConnection<T>(_ body: (NUTStreamConnection) throws -> T) throws -> T {
        let connection = try NUTStreamConnection(configuration: configuration)
        defer {
            connection.close()
        }
        return try body(connection)
    }

    private func authenticateIfNeeded(_ connection: NUTStreamConnection) throws {
        if !configuration.username.isEmpty {
            _ = try connection.singleLineResponse(command: "USERNAME \(configuration.username)")
        }

        if !configuration.password.isEmpty {
            _ = try connection.singleLineResponse(command: "PASSWORD \(configuration.password)")
        }
    }
}

private final class NUTStreamConnection {
    private let input: InputStream
    private let output: OutputStream
    private let timeoutSeconds: TimeInterval
    private var bufferedLines: [String] = []
    private var pendingText = ""

    init(configuration: NetworkUPSConfiguration) throws {
        var inputStream: InputStream?
        var outputStream: OutputStream?
        Stream.getStreamsToHost(
            withName: configuration.host,
            port: configuration.port,
            inputStream: &inputStream,
            outputStream: &outputStream
        )

        guard let inputStream, let outputStream else {
            throw NUTPowerSourceError.streamUnavailable
        }

        self.input = inputStream
        self.output = outputStream
        self.timeoutSeconds = configuration.timeoutSeconds

        input.open()
        output.open()

        try waitUntilOpen(input)
        try waitUntilOpen(output)
    }

    func close() {
        input.close()
        output.close()
    }

    func singleLineResponse(command: String) throws -> String {
        try write(command)
        let line = try readLine()
        try throwIfServerError(line)
        return line
    }

    func multilineResponse(command: String, endLinePrefix: String) throws -> [String] {
        try write(command)

        var lines: [String] = []
        while true {
            let line = try readLine()
            try throwIfServerError(line)
            lines.append(line)

            if line.hasPrefix(endLinePrefix) {
                return lines
            }
        }
    }

    private func waitUntilOpen(_ stream: Stream) throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)

        while Date() < deadline {
            switch stream.streamStatus {
            case .open:
                return
            case .error:
                throw NUTPowerSourceError.connectionFailed(stream.streamError?.localizedDescription ?? "unknown error")
            default:
                Thread.sleep(forTimeInterval: 0.02)
            }
        }

        throw NUTPowerSourceError.connectionTimedOut
    }

    private func write(_ command: String) throws {
        let data = Data((command + "\n").utf8)
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                throw NUTPowerSourceError.writeFailed
            }

            var bytesWritten = 0
            while bytesWritten < data.count {
                let count = output.write(
                    baseAddress.advanced(by: bytesWritten),
                    maxLength: data.count - bytesWritten
                )

                if count <= 0 {
                    throw NUTPowerSourceError.writeFailed
                }

                bytesWritten += count
            }
        }
    }

    private func readLine() throws -> String {
        if !bufferedLines.isEmpty {
            return bufferedLines.removeFirst()
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var buffer = [UInt8](repeating: 0, count: 1024)

        while Date() < deadline {
            if input.hasBytesAvailable {
                let count = input.read(&buffer, maxLength: buffer.count)
                if count < 0 {
                    throw NUTPowerSourceError.connectionFailed(input.streamError?.localizedDescription ?? "read error")
                }

                if count == 0 {
                    Thread.sleep(forTimeInterval: 0.02)
                    continue
                }

                pendingText += String(decoding: buffer.prefix(count), as: UTF8.self)
                drainCompleteLines()

                if !bufferedLines.isEmpty {
                    return bufferedLines.removeFirst()
                }
            } else {
                Thread.sleep(forTimeInterval: 0.02)
            }
        }

        throw NUTPowerSourceError.readTimedOut
    }

    private func drainCompleteLines() {
        while let newlineIndex = pendingText.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
            let line = String(pendingText[..<newlineIndex])
            pendingText.removeSubrange(...newlineIndex)
            if !line.isEmpty {
                bufferedLines.append(line)
            }
        }
    }

    private func throwIfServerError(_ line: String) throws {
        if line.hasPrefix("ERR ") {
            throw NUTPowerSourceError.serverError(line)
        }
    }
}
