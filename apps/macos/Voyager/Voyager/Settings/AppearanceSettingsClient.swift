import AppKit
import ComposableArchitecture
import Foundation

public struct AppearanceSettingsClient: Sendable {
    public var loadTheme: @Sendable () -> AppTheme
    public var applyTheme: @Sendable (AppTheme) async -> Void

    public nonisolated init(
        loadTheme: @escaping @Sendable () -> AppTheme,
        applyTheme: @escaping @Sendable (AppTheme) async -> Void
    ) {
        self.loadTheme = loadTheme
        self.applyTheme = applyTheme
    }
}

extension AppearanceSettingsClient: DependencyKey {
    public nonisolated static var liveValue: AppearanceSettingsClient {
        AppearanceSettingsClient(
            loadTheme: {
                if let themeString = UserDefaults.standard.string(forKey: "theme"),
                   let theme = AppTheme(rawValue: themeString)
                {
                    return theme
                }
                return .system
            },
            applyTheme: { theme in
                await MainActor.run {
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
        )
    }

    public nonisolated static var testValue: AppearanceSettingsClient {
        AppearanceSettingsClient(
            loadTheme: { .system },
            applyTheme: { _ in }
        )
    }

    public nonisolated static var previewValue: AppearanceSettingsClient {
        AppearanceSettingsClient(
            loadTheme: { .system },
            applyTheme: { _ in }
        )
    }
}

public extension DependencyValues {
    nonisolated var appearanceSettingsClient: AppearanceSettingsClient {
        get { self[AppearanceSettingsClient.self] }
        set { self[AppearanceSettingsClient.self] = newValue }
    }
}
