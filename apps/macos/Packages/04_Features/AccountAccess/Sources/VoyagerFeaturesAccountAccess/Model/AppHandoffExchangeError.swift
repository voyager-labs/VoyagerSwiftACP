import Foundation

/// VOY-334 `/auth/app-handoff/exchange` 호출 시 발생 가능한 에러.
/// 서버 에러 코드를 타입 안전한 케이스로 매핑한다.
/// 토큰·세션 정보는 로깅하지 않는다.
public nonisolated enum AppHandoffExchangeError: Error, Equatable, Sendable {
    /// 티켓이 이미 사용됨 (HTTP 409)
    case ticketAlreadyUsed
    /// 콜백 state가 서버 대기 상태와 불일치 (HTTP 400)
    case stateMismatch
    /// 티켓이 유효하지 않거나 만료됨 (HTTP 404)
    case invalidOrExpiredTicket
    /// 계정 불일치 (HTTP 403)
    case accountMismatch
    /// Supabase 세션 발급 실패 (HTTP 500)
    case sessionIssuanceFailed
    /// 서버 응답 디코딩 실패
    case decodingFailure
    /// 네트워크 오류
    case networkFailure
    /// 알 수 없는 서버 에러 코드
    case unknownGatewayCode(String)
}
