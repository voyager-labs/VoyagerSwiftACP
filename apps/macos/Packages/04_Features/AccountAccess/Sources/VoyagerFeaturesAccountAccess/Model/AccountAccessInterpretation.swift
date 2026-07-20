import Foundation

/// ONB-002 인증 축 상태
/// 계정 세션 여부와 로그인 진행 상태로부터 도출
nonisolated public enum AccountAccessAuthAxis: Equatable, Sendable {
    case signedOut
    case signInInProgress
    case signedIn
    case signInFailed
}

/// ONB-002 Access Unlock 단계 상태
/// PRODUCT TOML user_visible_status 계약: pending / complete / blocked / error
nonisolated public enum AccountAccessStepState: Equatable, Sendable {
    case pending
    case complete
    case blocked
    case error
}

/// VOY-397: ONB recovery 경로에서 화면에 표시할 primary CTA 투영.
/// direct checkout(.checkout)은 core ONB recovery에서 숨김.
nonisolated public enum AccessUnlockPrimaryCTA: Equatable, Sendable {
    case login
    case account
    case webPricing
    case retry
    case next
    case pending
    case eligibleDownload
}
