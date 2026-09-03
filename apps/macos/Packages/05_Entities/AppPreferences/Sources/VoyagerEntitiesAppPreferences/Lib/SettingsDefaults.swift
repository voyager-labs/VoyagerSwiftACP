import Foundation
import VoyagerShared

public enum SettingsDefaults {
    public static func persistStartPage(
        _ startPage: StartPage,
        userDefaultsClient: UserDefaultsClient = .liveValue,
    ) {
        switch startPage {
        case .home:
            userDefaultsClient.setString("home", SettingsKeys.defaultStartPageType)
        case let .directory(path):
            userDefaultsClient.setString("directory", SettingsKeys.defaultStartPageType)
            userDefaultsClient.setString(path, SettingsKeys.defaultTabPath)
        }
    }

    public static func defaultTabPath(userDefaultsClient: UserDefaultsClient = .liveValue) -> String {
        userDefaultsClient.string(SettingsKeys.defaultTabPath) ?? NSHomeDirectory()
    }

    public static func defaultStartPage(userDefaultsClient: UserDefaultsClient = .liveValue) -> StartPage {
        let legacyPath = userDefaultsClient.string(SettingsKeys.defaultTabPath)
        let persistedType = userDefaultsClient.string(SettingsKeys.defaultStartPageType)

        switch persistedType {
        case "home":
            return .home
        case "directory":
            if let legacyPath, !legacyPath.isEmpty {
                return .directory(legacyPath)
            }
        default:
            break
        }
        let migratedPage: StartPage = if let legacyPath, !legacyPath.isEmpty, persistedType == nil {
            .directory(legacyPath)
        } else {
            .home
        }
        userDefaultsClient.setString(migratedPage.persistenceValue, SettingsKeys.defaultStartPageType)
        return migratedPage
    }
}

private extension StartPage {
    var persistenceValue: String {
        switch self {
        case .home:
            "home"
        case .directory:
            "directory"
        }
    }
}
