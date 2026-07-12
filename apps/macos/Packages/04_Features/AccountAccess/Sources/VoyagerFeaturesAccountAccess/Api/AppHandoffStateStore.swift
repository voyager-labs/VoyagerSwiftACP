import Foundation

/// 인증 handoff 보류 상태를 메모리에 저장·조회하는 actor.
/// 콜백 deep link 수신 시 state 일치를 검증하고, 조회 후 즉시 제거한다(일회성 토큰).
actor AppHandoffStateStore {
    private var pending: PendingAppHandoff?

    nonisolated static let shared = AppHandoffStateStore()

    init() {}

    /// 활성 handoff가 없을 때만 새 보류 상태를 저장한다.
    @discardableResult
    func begin(_ pending: PendingAppHandoff) -> Bool {
        guard self.pending == nil else { return false }
        self.pending = pending
        return true
    }

    /// 현재 활성 handoff를 시작한 surface를 반환한다.
    func pendingOwner() -> AccountAccessHandoffScope? {
        pending?.owner
    }

    /// expectedState와 일치하면 보류 상태를 반환하고 제거한다.
    /// 불일치 또는 미저장 시 nil을 반환한다.
    func claim(
        expectedState: String,
        context: AppHandoffContext,
        owner: AccountAccessHandoffScope,
    ) -> PendingAppHandoff? {
        guard let current = pending,
              current.state == expectedState,
              current.context == context,
              current.owner == owner
        else { return nil }
        pending = nil
        return current
    }

    /// state와 owner가 모두 일치할 때만 보류 상태를 제거한다.
    @discardableResult
    func clear(expectedState: String, owner: AccountAccessHandoffScope) -> Bool {
        guard pending?.state == expectedState, pending?.owner == owner else { return false }
        pending = nil
        return true
    }
}
