import Foundation

// MARK: - FileManagerHostScenario

/// Progressive entry loading host QA 시나리오 축.
public enum FileManagerHostProgressiveEntryLoadingScenario: String, Sendable, Equatable {
    case none
    case success
    case partialFailure
}

/// Host 주입 시나리오 struct. 향후 축 추가 가능한 구조.
public struct FileManagerHostScenario: Sendable, Equatable {
    public var progressiveEntryLoading: FileManagerHostProgressiveEntryLoadingScenario

    public init(
        progressiveEntryLoading: FileManagerHostProgressiveEntryLoadingScenario = .none,
    ) {
        self.progressiveEntryLoading = progressiveEntryLoading
    }
}

// MARK: - FileManagerHostPreset

/// Named preset combinations. 환경변수 또는 Settings Picker에서 선택 가능.
public enum FileManagerHostPreset: String, Sendable, Equatable, CaseIterable {
    case `default`
    case progressiveEntryLoading = "progressive-entry-loading"
    case progressiveEntryLoadingFailure = "progressive-entry-loading-failure"

    public var scenario: FileManagerHostScenario {
        switch self {
        case .default:
            FileManagerHostScenario()
        case .progressiveEntryLoading:
            FileManagerHostScenario(progressiveEntryLoading: .success)
        case .progressiveEntryLoadingFailure:
            FileManagerHostScenario(progressiveEntryLoading: .partialFailure)
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
