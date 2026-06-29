import ComposableArchitecture

// MARK: - SessionLapseGuardWindowClient

/// ACC-003-guard_session_lapse: 과거 NSPanel 기반 클라이언트. SessionLapseGuardView가 FileManager 오버레이로 이관되어 no-op이나 기존 테스트 스텁
/// 호환성을 위해 타입 보존.
struct SessionLapseGuardWindowClient {
    var showWindow: @Sendable () async -> Void
    var closeWindow: @Sendable () async -> Void
}

// MARK: - DependencyKey

extension SessionLapseGuardWindowClient: DependencyKey {
    nonisolated static var liveValue: SessionLapseGuardWindowClient {
        .init(
            showWindow: {},
            closeWindow: {},
        )
    }

    nonisolated static var testValue: SessionLapseGuardWindowClient {
        .init(
            showWindow: {},
            closeWindow: {},
        )
    }

    nonisolated static var previewValue: SessionLapseGuardWindowClient {
        testValue
    }
}

// MARK: - DependencyValues

extension DependencyValues {
    nonisolated var sessionLapseGuardWindowClient: SessionLapseGuardWindowClient {
        get { self[SessionLapseGuardWindowClient.self] }
        set { self[SessionLapseGuardWindowClient.self] = newValue }
    }
}
