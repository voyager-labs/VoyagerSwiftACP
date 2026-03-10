import Foundation

public enum AppVersionInfo {
    public static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    public static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }

    public static var displayText: String {
        "v\(shortVersion) (\(buildNumber))"
    }
}
