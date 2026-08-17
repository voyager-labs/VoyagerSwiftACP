import Foundation

// MARK: - FileManagerHostPreset

/// Named preset combinations. 환경변수 또는 Settings Picker에서 선택 가능.
public enum FileManagerHostPreset: String, Sendable, Equatable, CaseIterable {
    case `default`
    case contentTabSwitcherContent
    case contentTabSwitcherFallback
    case contentTabSwitcherEmpty
    case contentTabSwitcherLoading
    case contentTabSwitcherError

    public var switcherPresentationSource: FileManagerContentTabSwitcherPresentation.Source? {
        switch self {
        case .default:
            nil
        case .contentTabSwitcherContent, .contentTabSwitcherFallback, .contentTabSwitcherEmpty:
            .automatic
        case .contentTabSwitcherLoading:
            .loading
        case .contentTabSwitcherError:
            .error(message: "Unable to load recent tabs.")
        }
    }

    /// `FILE_MANAGER_HOST_SCENARIO` 환경변수에서 preset 해석.
    /// nil 또는 알 수 없는 값은 `.default`로 폴백.
    public static func resolveFromEnvironment() -> FileManagerHostPreset {
        guard let rawValue = ProcessInfo.processInfo.environment["FILE_MANAGER_HOST_SCENARIO"],
              let preset = FileManagerHostPreset(rawValue: rawValue)
        else { return .default }
        return preset
    }
}

public enum FileManagerHostAppearance: Equatable, Sendable {
    case system
    case light
    case dark
    case invalid(String)

    public static func resolve(rawValue: String?) -> Self {
        guard let rawValue else { return .system }
        return switch rawValue {
        case "light":
            .light
        case "dark":
            .dark
        default:
            .invalid(rawValue)
        }
    }

    public static func resolveFromEnvironment() -> Self {
        resolve(rawValue: ProcessInfo.processInfo.environment["FILE_MANAGER_HOST_APPEARANCE"])
    }
}
