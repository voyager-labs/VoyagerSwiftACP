import Foundation

/// 인증 handoff 요청 후 콜백 대기 중인 보류 상태.
/// 앱이 외부 브라우저로 이동한 후 콜백 deep link로 돌아올 때까지 메모리에 유지한다.
struct PendingAppHandoff: Equatable {
    let state: String
    let context: AppHandoffContext
    let owner: AccountAccessHandoffScope
    let createdAt: Date
}
