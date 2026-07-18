import Foundation

public enum AppVersionInfo {
    public enum ReleaseMetadataError: Error, Equatable {
        case missingReleasedAt
        case malformedReleasedAt
        case nonUTCReleasedAt
        case futureReleasedAt
    }

    public static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    public static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }

    public static var displayText: String {
        "v\(shortVersion) (\(buildNumber))"
    }

    public static func releaseIdentity(
        bundle: Bundle = .main,
        now: Date = .now,
    ) throws -> ReleaseIdentity {
        try ReleaseIdentity(
            releasedAt: bundle.object(forInfoDictionaryKey: "VOYAGER_RELEASED_AT") as? String,
            now: now,
        )
    }
}
