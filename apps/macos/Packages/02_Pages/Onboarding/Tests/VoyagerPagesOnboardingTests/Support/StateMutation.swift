import VoyagerFeaturesBetaAccess
@testable import VoyagerPagesOnboarding

// MARK: - 상태 변이 헬퍼

/// 테스트에서 반복 사용하는 상태 변이 패턴을 네임스페이스로 제공합니다.
enum StateMutation {
    /// betaAccess 상태를 active/none/true로 설정합니다.
    /// verificationResponse(.active) 수신 후의 상태 변이와 동일합니다.
    static func applyActiveBetaAccess(state: inout OnboardingFeature.State) {
        state.betaAccess.status = .active
        state.betaAccess.reason = .none
        state.betaAccess.isComplete = true
    }
}
