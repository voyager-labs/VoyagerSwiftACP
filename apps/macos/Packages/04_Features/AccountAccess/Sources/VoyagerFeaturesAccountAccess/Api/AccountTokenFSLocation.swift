import Foundation

/// ADR 001: 계정 토큰은 ~/.voyager/account_tokens.json에 저장 (home 고정).
/// AI connection 저장소와 달리 project-root resolver를 사용하지 않는다.
enum AccountTokenFSLocation {
    static let directoryName = ".voyager"
    static let payloadFileName = "account_tokens.json"
    static let handoffStagingFileName = "account_tokens.handoff-staging.json"
    static let quarantinePrefix = "account_tokens.corrupted"
    static let lockFileName = "account_tokens.lock"
    static let rollbackMarkerFileName = "account_tokens.rollback-pending"

    static func directoryURL(homeDirectoryURL: URL) -> URL {
        homeDirectoryURL
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    static func accountTokensFileURL(
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
    ) -> URL {
        directoryURL(homeDirectoryURL: homeDirectoryURL)
            .appendingPathComponent(payloadFileName)
    }

    static func lockFileURL(
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
    ) -> URL {
        directoryURL(homeDirectoryURL: homeDirectoryURL)
            .appendingPathComponent(lockFileName)
    }

    static func handoffStagingFileURL(
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
    ) -> URL {
        directoryURL(homeDirectoryURL: homeDirectoryURL)
            .appendingPathComponent(handoffStagingFileName)
    }

    static func rollbackMarkerFileURL(
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
    ) -> URL {
        directoryURL(homeDirectoryURL: homeDirectoryURL)
            .appendingPathComponent(rollbackMarkerFileName)
    }

    static func quarantineFileURL(
        directoryURL: URL,
        iso8601String: String,
    ) -> URL {
        let safeTimestamp = iso8601String.replacingOccurrences(of: ":", with: "-")
        return directoryURL.appendingPathComponent("\(quarantinePrefix)-\(safeTimestamp).json")
    }

    static func quarantineFileURL(
        directoryURL: URL,
        generatedAt: Date = Date(),
    ) -> URL {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: generatedAt).replacingOccurrences(of: ":", with: "-")
        return directoryURL.appendingPathComponent("\(quarantinePrefix)-\(timestamp).json")
    }
}
