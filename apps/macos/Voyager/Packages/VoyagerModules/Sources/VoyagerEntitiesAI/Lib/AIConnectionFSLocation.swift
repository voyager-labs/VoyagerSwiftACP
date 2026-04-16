import Foundation

public enum AIConnectionFSLocation {
    public static let directoryName = ".voyager/config"
    public static let payloadFileName = "ai_connections.json"
    public static let lockFileName = "ai_connections.lock"
    public static let quarantinePrefix = "ai_connections.corrupted"

    public static func directoryURL(homeDirectoryURL: URL) -> URL {
        homeDirectoryURL
            .appendingPathComponent(".voyager", isDirectory: true)
            .appendingPathComponent("config", isDirectory: true)
    }

    public static func payloadFileURL(homeDirectoryURL: URL) -> URL {
        directoryURL(homeDirectoryURL: homeDirectoryURL)
            .appendingPathComponent(payloadFileName)
    }

    public static func lockFileURL(homeDirectoryURL: URL) -> URL {
        directoryURL(homeDirectoryURL: homeDirectoryURL)
            .appendingPathComponent(lockFileName)
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
