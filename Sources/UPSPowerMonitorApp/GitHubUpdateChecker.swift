import Foundation

struct GitHubRelease: Decodable, Sendable {
    let tagName: String
    let name: String?
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
    }
}

enum UpdateCheckResult: Sendable {
    case updateAvailable(currentVersion: String, latestVersion: String, releaseURL: URL)
    case upToDate(currentVersion: String, latestVersion: String)
    case noRelease
}

enum GitHubUpdateCheckerError: LocalizedError {
    case invalidResponse
    case rateLimited
    case requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "GitHub 返回的数据无效"
        case .rateLimited:
            "GitHub 请求次数暂时受限，请稍后再试"
        case .requestFailed(let statusCode):
            "GitHub 检查更新失败，HTTP \(statusCode)"
        }
    }
}

struct GitHubUpdateChecker {
    let owner: String
    let repository: String

    func check(currentVersion: String) async throws -> UpdateCheckResult {
        guard let release = try await latestRelease() else {
            return .noRelease
        }

        let latestVersion = Self.normalizedVersion(release.tagName)

        if Self.compareVersions(latestVersion, currentVersion) == .orderedDescending {
            return .updateAvailable(
                currentVersion: currentVersion,
                latestVersion: latestVersion,
                releaseURL: release.htmlURL
            )
        }

        return .upToDate(currentVersion: currentVersion, latestVersion: latestVersion)
    }

    private func latestRelease() async throws -> GitHubRelease? {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("GraceDown", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubUpdateCheckerError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return try JSONDecoder().decode(GitHubRelease.self, from: data)
        case 404:
            return nil
        case 403, 429:
            throw GitHubUpdateCheckerError.rateLimited
        default:
            throw GitHubUpdateCheckerError.requestFailed(httpResponse.statusCode)
        }
    }

    static func normalizedVersion(_ version: String) -> String {
        let trimmed = version
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("v") {
            return String(trimmed.dropFirst())
        }

        return trimmed
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let leftParts = versionParts(lhs)
        let rightParts = versionParts(rhs)
        let count = max(leftParts.count, rightParts.count)

        for index in 0..<count {
            let left = index < leftParts.count ? leftParts[index] : 0
            let right = index < rightParts.count ? rightParts[index] : 0
            if left < right {
                return .orderedAscending
            }
            if left > right {
                return .orderedDescending
            }
        }

        return .orderedSame
    }

    private static func versionParts(_ version: String) -> [Int] {
        normalizedVersion(version)
            .split(separator: ".", omittingEmptySubsequences: false)
            .map { part in
                let digits = part.prefix { $0.isNumber }
                return Int(digits) ?? 0
            }
    }
}
