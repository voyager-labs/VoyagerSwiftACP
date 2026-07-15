import Foundation

// MARK: - Session lapse guard 축

/// Session lapse guard 시나리오 축. Host에서 guard view의 상태를 주입하여
/// 프로덕션 앱 bootstrap 없이 다양한 session lapse UI를 검증한다.
public enum FileManagerHostSessionLapseScenario: String, Sendable, Equatable, CaseIterable {
    /// guard 없음 (기본 동작)
    case none
    /// guard 활성화 — session expired 상태
    case active
    /// guard 활성화 + sign-in 실패
    case signInFailed
}

// MARK: - FileManagerHostScenario

/// Host 주입 시나리오 struct. 향후 축 추가 가능한 구조.
public struct FileManagerHostScenario: Sendable, Equatable {
    public var sessionLapse: FileManagerHostSessionLapseScenario

    public init(sessionLapse: FileManagerHostSessionLapseScenario = .none) {
        self.sessionLapse = sessionLapse
    }
}

// MARK: - FileManagerHostPreset

/// Named preset combinations. 환경변수 또는 Settings Picker에서 선택 가능.
public enum FileManagerHostPreset: String, Sendable, Equatable, CaseIterable {
    case `default`
    case sessionLapseGuard = "session-lapse-guard"
    case sessionLapseSignInFailed = "session-lapse-sign-in-failed"

    public var scenario: FileManagerHostScenario {
        switch self {
        case .default:
            FileManagerHostScenario(sessionLapse: .none)
        case .sessionLapseGuard:
            FileManagerHostScenario(sessionLapse: .active)
        case .sessionLapseSignInFailed:
            FileManagerHostScenario(sessionLapse: .signInFailed)
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
