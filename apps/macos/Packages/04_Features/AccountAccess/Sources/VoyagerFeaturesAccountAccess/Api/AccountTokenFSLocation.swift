import Foundation
import VoyagerEntitiesAi

// REFACTOR: 향후 VoyagerShared/CredentialStore로 AIConnectionFileStore와 통합 예정
public enum AccountTokenFSLocation {
    public static let directoryName = ".voyager"
    public static let payloadFileName = "account_tokens.json"
    public static let quarantinePrefix = "account_tokens.corrupted"

    public static func directoryURL(homeDirectoryURL: URL) -> URL {
        homeDirectoryURL
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    public static func accountTokensFileURL(
        homeDirectoryURL: URL = AiConnectionRootResolver.resolveBaseRoot(),
    ) -> URL {
        directoryURL(homeDirectoryURL: homeDirectoryURL)
            .appendingPathComponent(payloadFileName)
    }

    public static func quarantineFileURL(
        directoryURL: URL,
        iso8601String: String,
    ) -> URL {
        let safeTimestamp = iso8601String.replacingOccurrences(of: ":", with: "-")
        return directoryURL.appendingPathComponent("\(quarantinePrefix)-\(safeTimestamp).json")
    }

    public static func quarantineFileURL(
        directoryURL: URL,
        generatedAt: Date = Date(),
    ) -> URL {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: generatedAt).replacingOccurrences(of: ":", with: "-")
        return directoryURL.appendingPathComponent("\(quarantinePrefix)-\(timestamp).json")
    }
}
