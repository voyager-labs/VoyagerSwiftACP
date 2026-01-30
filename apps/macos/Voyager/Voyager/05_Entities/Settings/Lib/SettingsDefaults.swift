import Foundation

enum SettingsDefaults {
    static func defaultTabPath(userDefaultsClient: UserDefaultsClient = .liveValue) -> String {
        userDefaultsClient.string(SettingsKeys.defaultTabPath) ?? NSHomeDirectory()
    }
}
