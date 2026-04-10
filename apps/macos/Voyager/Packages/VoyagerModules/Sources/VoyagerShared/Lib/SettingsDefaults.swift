import Foundation

public enum SettingsDefaults {
    public static func defaultTabPath(userDefaultsClient: UserDefaultsClient = .liveValue) -> String {
        userDefaultsClient.string(SettingsKeys.defaultTabPath) ?? NSHomeDirectory()
    }
}
