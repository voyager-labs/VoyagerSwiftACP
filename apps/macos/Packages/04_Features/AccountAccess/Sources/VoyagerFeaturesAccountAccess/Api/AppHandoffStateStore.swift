import Foundation

/// 인증 handoff 보류 상태를 메모리에 저장·조회하는 actor.
/// 콜백 deep link 수신 시 state 일치를 검증하고, 조회 후 즉시 제거한다(일회성 토큰).
actor AppHandoffStateStore {
    private var pending: PendingAppHandoff?

    nonisolated static let shared = AppHandoffStateStore()

    init() {}

    func store(_ pending: PendingAppHandoff) {
        self.pending = pending
    }

    /// expectedState와 일치하면 보류 상태를 반환하고 제거한다.
    /// 불일치 또는 미저장 시 nil을 반환한다.
    func retrieveAndClear(expectedState: String) -> PendingAppHandoff? {
        guard let current = pending, current.state == expectedState else { return nil }
        pending = nil
        return current
    }

    func clear() {
        pending = nil
    }
}
