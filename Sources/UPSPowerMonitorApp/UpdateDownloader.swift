import CryptoKit
import Foundation

enum UpdateDownloaderError: LocalizedError {
    case invalidHTTPResponse
    case requestFailed(Int)
    case missingChecksum
    case checksumMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .invalidHTTPResponse:
            "下载更新失败：服务器返回无效响应。"
        case .requestFailed(let statusCode):
            "下载更新失败：HTTP \(statusCode)。"
        case .missingChecksum:
            "下载更新失败：未找到校验文件。"
        case .checksumMismatch:
            "下载更新失败：安装包校验未通过。"
        }
    }
}

struct UpdateDownloader {
    func download(_ release: GitHubReleaseDownload) async throws -> URL {
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GraceDown-\(release.version).dmg")

        try? FileManager.default.removeItem(at: destinationURL)

        let checksum = try await downloadChecksum(from: release.checksumURL)
        let downloadedURL = try await downloadFile(from: release.dmgURL, to: destinationURL)
        try verify(downloadedURL, expectedChecksum: checksum)

        return downloadedURL
    }

    private func downloadChecksum(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("GraceDown", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)

        guard let text = String(data: data, encoding: .utf8),
              let checksum = text.split(whereSeparator: \.isWhitespace).first
        else {
            throw UpdateDownloaderError.missingChecksum
        }

        return String(checksum).lowercased()
    }

    private func downloadFile(from url: URL, to destinationURL: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        request.setValue("GraceDown", forHTTPHeaderField: "User-Agent")

        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        try validate(response)

        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        return destinationURL
    }

    private func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateDownloaderError.invalidHTTPResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw UpdateDownloaderError.requestFailed(httpResponse.statusCode)
        }
    }

    private func verify(_ fileURL: URL, expectedChecksum: String) throws {
        let data = try Data(contentsOf: fileURL)
        let actualChecksum = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()

        guard actualChecksum == expectedChecksum else {
            throw UpdateDownloaderError.checksumMismatch(expected: expectedChecksum, actual: actualChecksum)
        }
    }
}
