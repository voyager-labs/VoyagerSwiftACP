import AppKit
import ComposableArchitecture
import Foundation

public struct AppearanceSettingsClient: Sendable {
    public var loadTheme: @Sendable () -> AppTheme
    public var applyTheme: @Sendable (AppTheme) async -> Void
    public var applyThemeSync: @Sendable (AppTheme) -> Void

    public nonisolated init(
        loadTheme: @escaping @Sendable () -> AppTheme,
        applyTheme: @escaping @Sendable (AppTheme) async -> Void,
        applyThemeSync: @escaping @Sendable (AppTheme) -> Void
    ) {
        self.loadTheme = loadTheme
        self.applyTheme = applyTheme
        self.applyThemeSync = applyThemeSync
    }
}

extension AppearanceSettingsClient: DependencyKey {
    private static func themeToAppearanceName(_ theme: AppTheme) -> NSAppearance.Name? {
        switch theme {
        case .light:
            .aqua
        case .dark:
            .darkAqua
        case .system:
            nil
        }
    }

    @MainActor
    private static func applyAppearance(_ theme: AppTheme) {
        if let appearanceName = themeToAppearanceName(theme) {
            NSApp.appearance = NSAppearance(named: appearanceName)
        } else {
            NSApp.appearance = nil
        }
    }

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
                    applyAppearance(theme)
                }
            },
            applyThemeSync: { theme in
                if Thread.isMainThread {
                    MainActor.assumeIsolated {
                        applyAppearance(theme)
                    }
                } else {
                    DispatchQueue.main.sync {
                        applyAppearance(theme)
                    }
                }
            }
        )
    }

    public nonisolated static var testValue: AppearanceSettingsClient {
        AppearanceSettingsClient(
            loadTheme: { .system },
            applyTheme: { _ in },
            applyThemeSync: { _ in }
        )
    }

    public nonisolated static var previewValue: AppearanceSettingsClient {
        AppearanceSettingsClient(
            loadTheme: { .system },
            applyTheme: { _ in },
            applyThemeSync: { _ in }
        )
    }
}

public extension DependencyValues {
    nonisolated var appearanceSettingsClient: AppearanceSettingsClient {
        get { self[AppearanceSettingsClient.self] }
        set { self[AppearanceSettingsClient.self] = newValue }
    }
}
