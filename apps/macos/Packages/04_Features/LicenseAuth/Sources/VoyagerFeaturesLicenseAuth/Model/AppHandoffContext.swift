import Foundation

/// App→Web→App 인증 handoff에서 콜백의 용도를 식별하는 컨텍스트.
/// 외부에서 임의 값을 주입하지 못하도록 allowlist로 검증한다.
public enum AppHandoffContext: String, Sendable, Equatable {
    case onboarding

    /// 허용된 컨텍스트 집합.
    /// 콜백 파싱 시 이 집합에 포함되지 않은 context 값은 거부한다.
    public static var allowed: Set<AppHandoffContext> {
        [.onboarding]
    }
}
