import Foundation

/// 앱 테마 설정 (라이트/다크/시스템)
public enum AppTheme: String, CaseIterable, Equatable, Sendable {
    case light
    case dark
    case system

    var displayName: String {
        switch self {
        case .light:
            "Light"
        case .dark:
            "Dark"
        case .system:
            "Auto"
        }
    }
}

/// 설정 화면의 섹션 구분
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            "General"
        case .appearance:
            "Appearance"
        }
    }

    var iconName: String {
        switch self {
        case .general:
            "gear"
        case .appearance:
            "paintbrush"
        }
    }
}
