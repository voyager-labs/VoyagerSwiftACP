import Foundation

public enum AppTheme: String, CaseIterable, Equatable, Sendable {
    case light
    case dark
    case system

    public var displayName: String {
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
