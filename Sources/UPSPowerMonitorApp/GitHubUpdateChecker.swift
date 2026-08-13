import Foundation

struct GitHubLatestRelease: Sendable {
    let tagName: String
    let htmlURL: URL
    let dmgURL: URL
    let checksumURL: URL
}

enum UpdateCheckResult: Sendable {
    case updateAvailable(currentVersion: String, latestVersion: String, download: GitHubReleaseDownload)
    case upToDate(currentVersion: String, latestVersion: String)
    case noRelease
}

struct GitHubReleaseDownload: Sendable {
    let version: String
    let releaseURL: URL
    let dmgURL: URL
    let checksumURL: URL
}

enum GitHubUpdateCheckerError: LocalizedError {
    case invalidResponse
    case requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "GitHub 返回的数据无效"
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
                download: GitHubReleaseDownload(
                    version: latestVersion,
                    releaseURL: release.htmlURL,
                    dmgURL: release.dmgURL,
                    checksumURL: release.checksumURL
                )
            )
        }

        return .upToDate(currentVersion: currentVersion, latestVersion: latestVersion)
    }

    private func latestRelease() async throws -> GitHubLatestRelease? {
        let url = URL(string: "https://github.com/\(owner)/\(repository)/releases/latest")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("GraceDown", forHTTPHeaderField: "User-Agent")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubUpdateCheckerError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            guard let finalURL = httpResponse.url else {
                throw GitHubUpdateCheckerError.invalidResponse
            }

            if finalURL.path.hasSuffix("/releases") {
                return nil
            }

            guard let tagName = Self.releaseTag(from: finalURL) else {
                throw GitHubUpdateCheckerError.invalidResponse
            }

            let version = Self.normalizedVersion(tagName)
            return GitHubLatestRelease(
                tagName: tagName,
                htmlURL: finalURL,
                dmgURL: releaseAssetURL(tagName: tagName, fileName: "GraceDown-\(version).dmg"),
                checksumURL: releaseAssetURL(tagName: tagName, fileName: "GraceDown-\(version).dmg.sha256")
            )
        case 404:
            return nil
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

    private static func releaseTag(from url: URL) -> String? {
        let components = url.pathComponents
        guard let tagIndex = components.firstIndex(of: "tag"),
              tagIndex + 1 < components.count
        else {
            return nil
        }

        return components[tagIndex + 1].removingPercentEncoding
    }

    private func releaseAssetURL(tagName: String, fileName: String) -> URL {
        URL(string: "https://github.com/\(owner)/\(repository)/releases/download/\(tagName)/\(fileName)")!
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
