import AppKit
import Foundation

@MainActor
final class AppearanceSettingsUtils {
    static let shared = AppearanceSettingsUtils()

    private init() {}

    func loadTheme() -> AppTheme {
        if let themeString = UserDefaults.standard.string(forKey: SettingsKeys.theme),
           let theme = AppTheme(rawValue: themeString)
        {
            return theme
        }
        return .system
    }

    func applyTheme(_ theme: AppTheme) {
        let appearance: NSAppearance.Name? = switch theme {
        case .light:
            .aqua
        case .dark:
            .darkAqua
        case .system:
            nil
        }

        if let appearance = appearance {
            NSApp.appearance = NSAppearance(named: appearance)
        } else {
            NSApp.appearance = nil
        }
    }
}
