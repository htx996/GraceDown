import Foundation

public struct NUTUPS: Equatable, Sendable {
    public let name: String
    public let description: String

    public init(name: String, description: String) {
        self.name = name
        self.description = description
    }
}

public enum NUTResponseParser {
    public static func parseUPSList(lines: [String]) -> [NUTUPS] {
        lines.compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, parts[0] == "UPS" else {
                return nil
            }

            return NUTUPS(
                name: String(parts[1]),
                description: unquotedValue(String(parts[2]))
            )
        }
    }

    public static func parseVariables(lines: [String], upsName: String) -> [String: String] {
        var variables: [String: String] = [:]

        for line in lines {
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, parts[0] == "VAR", parts[1] == upsName[...] else {
                continue
            }

            variables[String(parts[2])] = unquotedValue(String(parts[3]))
        }

        return variables
    }

    static func unquotedValue(_ rawValue: String) -> String {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value.removeFirst()
            value.removeLast()
        }

        return value
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
