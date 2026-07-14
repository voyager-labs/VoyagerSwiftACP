import Foundation

/// 세션 종료 이유. .accountSessionDidEnd notification의 userInfo로 전달된다.
/// AppLifecycleFeature가 이 값을 읽어 guard 표시 이유를 구분한다.
public enum AccountSessionEndReason: String, Sendable, Equatable {
    /// 사용자 명시적 로그아웃
    case explicitSignOut
    /// 세션 토큰 만료
    case sessionExpired
}
