import Foundation

// MARK: - FileManagerHostScenario

/// Progressive entry loading host QA 시나리오 축.
public enum FileManagerHostProgressiveEntryLoadingScenario: String, Sendable, Equatable {
    case none
    case success
    case partialFailure
}

public enum FileManagerHostDelayedNavigationScenario: String, Sendable, Equatable {
    case none
    case rootNavigation
    case tabSwitch
}

public enum FileManagerHostPermissionScenario: String, Sendable, Equatable {
    case none
    case denied
    case retry
}

public enum FileManagerHostCollectionScenario: String, Sendable, Equatable {
    case none
    case directory
}

public enum FileManagerHostLargeFolderScenario: String, Sendable, Equatable {
    case none
    case oneThousand
    case concurrent
}

/// Host 주입 시나리오 struct. 향후 축 추가 가능한 구조.
public struct FileManagerHostScenario: Sendable, Equatable {
    public var progressiveEntryLoading: FileManagerHostProgressiveEntryLoadingScenario
    public var delayedNavigation: FileManagerHostDelayedNavigationScenario
    public var permission: FileManagerHostPermissionScenario
    public var collection: FileManagerHostCollectionScenario
    public var largeFolder: FileManagerHostLargeFolderScenario

    public init(
        progressiveEntryLoading: FileManagerHostProgressiveEntryLoadingScenario = .none,
        delayedNavigation: FileManagerHostDelayedNavigationScenario = .none,
        permission: FileManagerHostPermissionScenario = .none,
        collection: FileManagerHostCollectionScenario = .none,
        largeFolder: FileManagerHostLargeFolderScenario = .none,
    ) {
        self.progressiveEntryLoading = progressiveEntryLoading
        self.delayedNavigation = delayedNavigation
        self.permission = permission
        self.collection = collection
        self.largeFolder = largeFolder
    }
}

// MARK: - FileManagerHostPreset

/// Named preset combinations. 환경변수 또는 Settings Picker에서 선택 가능.
public enum FileManagerHostPreset: String, Sendable, Equatable, CaseIterable {
    case `default`
    case contentTabSwitcherContent
    case contentTabSwitcherFallback
    case contentTabSwitcherEmpty
    case contentTabSwitcherLoading
    case contentTabSwitcherError
    case progressiveEntryLoading = "progressive-entry-loading"
    case progressiveEntryLoadingFailure = "progressive-entry-loading-failure"
    case delayedRootNavigation = "delayed-root-navigation"
    case delayedTabSwitch = "delayed-tab-switch"
    case permissionDenied = "permission-denied"
    case permissionRetry = "permission-retry"
    case collectionDirectory = "collection-directory"
    case largeFolder1000 = "large-folder-1000"
    case concurrentLargeFolders = "concurrent-large-folders"

    public var scenario: FileManagerHostScenario {
        switch self {
        case .default,
             .contentTabSwitcherContent,
             .contentTabSwitcherFallback,
             .contentTabSwitcherEmpty,
             .contentTabSwitcherLoading,
             .contentTabSwitcherError:
            FileManagerHostScenario()
        case .progressiveEntryLoading:
            FileManagerHostScenario(progressiveEntryLoading: .success)
        case .progressiveEntryLoadingFailure:
            FileManagerHostScenario(progressiveEntryLoading: .partialFailure)
        case .delayedRootNavigation:
            FileManagerHostScenario(
                progressiveEntryLoading: .success,
                delayedNavigation: .rootNavigation,
            )
        case .delayedTabSwitch:
            FileManagerHostScenario(
                progressiveEntryLoading: .success,
                delayedNavigation: .tabSwitch,
            )
        case .permissionDenied:
            FileManagerHostScenario(permission: .denied)
        case .permissionRetry:
            FileManagerHostScenario(permission: .retry)
        case .collectionDirectory:
            FileManagerHostScenario(collection: .directory)
        case .largeFolder1000:
            FileManagerHostScenario(largeFolder: .oneThousand)
        case .concurrentLargeFolders:
            FileManagerHostScenario(largeFolder: .concurrent)
        }
    }

    public var switcherPresentationSource: FileManagerContentTabSwitcherPresentation.Source? {
        switch self {
        case .contentTabSwitcherContent, .contentTabSwitcherFallback, .contentTabSwitcherEmpty:
            .automatic
        case .contentTabSwitcherLoading:
            .loading
        case .contentTabSwitcherError:
            .error(message: "Unable to load recent tabs.")
        default:
            nil
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
