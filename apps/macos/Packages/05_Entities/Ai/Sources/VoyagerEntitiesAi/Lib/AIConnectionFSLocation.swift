import Foundation

public enum AIConnectionFSLocation {
    public static let directoryName = ".voyager"
    public static let payloadFileName = "auth.json"
    public static let lockFileName = "auth.lock"
    public static let quarantinePrefix = "auth.corrupted"

    public static func directoryURL(homeDirectoryURL: URL) -> URL {
        homeDirectoryURL
            .appendingPathComponent(".voyager", isDirectory: true)
    }

    public static func payloadFileURL(homeDirectoryURL: URL) -> URL {
        directoryURL(homeDirectoryURL: homeDirectoryURL)
            .appendingPathComponent(payloadFileName)
    }

    public static func lockFileURL(homeDirectoryURL: URL) -> URL {
        directoryURL(homeDirectoryURL: homeDirectoryURL)
            .appendingPathComponent(lockFileName)
    }

    public static func projectDirectoryURL(repoRootURL: URL) -> URL {
        repoRootURL
            .appendingPathComponent(".voyager", isDirectory: true)
    }

    public static func projectPayloadFileURL(repoRootURL: URL) -> URL {
        projectDirectoryURL(repoRootURL: repoRootURL)
            .appendingPathComponent(payloadFileName)
    }

    public static func projectLockFileURL(repoRootURL: URL) -> URL {
        projectDirectoryURL(repoRootURL: repoRootURL)
            .appendingPathComponent(lockFileName)
    }

    public static func quarantineFileURL(
        directoryURL: URL,
        generatedAt: Date = Date()
    ) -> URL {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: generatedAt).replacingOccurrences(of: ":", with: "-")
        return directoryURL.appendingPathComponent("\(quarantinePrefix)-\(timestamp).json")
    }
}
