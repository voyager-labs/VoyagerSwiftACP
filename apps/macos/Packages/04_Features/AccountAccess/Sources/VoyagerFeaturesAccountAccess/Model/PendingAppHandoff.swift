import Foundation

/// 인증 handoff 요청 후 콜백 대기 중인 보류 상태.
/// 앱이 외부 브라우저로 이동한 후 콜백 deep link로 돌아올 때까지 메모리에 유지한다.
public struct PendingAppHandoff: Sendable, Equatable {
    public let state: String
    public let context: AppHandoffContext
    public let createdAt: Date

    public init(state: String, context: AppHandoffContext, createdAt: Date) {
        self.state = state
        self.context = context
        self.createdAt = createdAt
    }
}
