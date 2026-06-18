import Foundation

/// ONB-002 인증 축 상태
/// 계정 세션 여부와 로그인 진행 상태로부터 도출
public nonisolated enum AccountAccessAuthAxis: Equatable, Sendable {
    case signedOut
    case signInInProgress
    case signedIn
    case signInFailed
}

/// ONB-002 Access Unlock 단계 상태
/// PRODUCT TOML user_visible_status 계약: pending / complete / blocked / error
public nonisolated enum AccountAccessStepState: Equatable, Sendable {
    case pending
    case complete
    case blocked
    case error
}
