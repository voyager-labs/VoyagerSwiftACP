import AppKit
import ComposableArchitecture
import Foundation
import VoyagerFeaturesEntryOperations

/// Grid/List 각각 하나씩 보유하며 외부 drop 획득 세션의 local 수명을 소유하는 controller.
///
/// - `activeSessionID`: 이 controller가 직접 시작한 세션의 local ID만 추적한다. TCA state에 두지
///   않는다(Shared actor 경계를 넘지 않는 AppKit/coordinator 소유 상태).
/// - begin 라우팅 위임: promise/mixed 외부 drop의 획득 시작을 공유 adapter
///   `beginExternalDropAcquisition`에 위임하고 반환된 accepted action을 store로 보낸다.
/// - terminal transition 관찰: render-loop가 reducer의 종단 전이(non-nil → nil)를
///   `handleSessionTerminal`로 알려주면 local ID를 해제한다.
/// - cancel: 소유한 세션을 취소하고 `.externalDropCancelSession`을 store로 보낸다.
///
/// **cross-Grid/List 직렬화**: 두 controller가 같은 store를 보므로 `beginAcquisition`의 첫 guard는
/// 같은 store의 `state.entryOperations.activeExternalDrop == nil`을 본다. 이 shared TCA state가
/// cross-view 직렬화의 유일한 owner다. 첫 controller가 adapter begin 직후 `.accepted`를 synchronous
/// send해 shared state를 채우므로, 두 번째 controller는 adapter/client 호출 전에 false를 반환한다.
@MainActor
final class ExternalDropSessionController {
    private let store: StoreOf<EntryViewLayoutFeature>
    private let clientProvider: () -> ExternalDropAcquisitionClient
    private let clearDropState: () -> Void
    private var activeExternalDropSessionID: ExternalDropSessionID?

    /// 이 controller가 현재 소유 중인 local session ID. terminal 전이·cancel 후 nil.
    var activeSessionID: ExternalDropSessionID? {
        activeExternalDropSessionID
    }

    init(
        store: StoreOf<EntryViewLayoutFeature>,
        clientProvider: @escaping () -> ExternalDropAcquisitionClient,
        clearDropState: @escaping () -> Void,
    ) {
        self.store = store
        self.clientProvider = clientProvider
        self.clearDropState = clearDropState
    }

    /// promise/mixed 외부 drop의 획득 세션을 시작한다.
    ///
    /// 첫 guard는 shared TCA `activeExternalDrop` — 두 Grid/List controller가 같은 store를 보므로
    /// 어느 쪽이 먼저 세션을 열면 다른 쪽은 adapter/client 호출 전에 false를 반환한다. 그 다음에
    /// local 소유 세션도 없어야 진행한다(첫 guard가 이미 shared를 차단하지만 안전망).
    @discardableResult
    func beginAcquisition(
        draggingInfo: any NSDraggingInfo,
        negotiation: VoyagerFeaturesEntryOperations.ExternalDropNegotiation,
        destinationPath: String,
    ) -> Bool {
        guard store.state.entryOperations.activeExternalDrop == nil else {
            EntryViewLayoutDropValidationAdapter.validationLogger.info("acquisition rejected shared-active")
            return false
        }
        guard activeExternalDropSessionID == nil else {
            EntryViewLayoutDropValidationAdapter.validationLogger.info("acquisition rejected owned-session")
            return false
        }
        return EntryViewLayoutDropValidationAdapter.beginExternalDropAcquisition(
            activeSessionID: &activeExternalDropSessionID,
            context: .init(
                client: clientProvider(),
                sendAccepted: { [store] request in
                    store.send(.view(.externalDropAccepted(request: request)))
                },
                clearDropState: clearDropState,
            ),
            draggingInfo: draggingInfo,
            negotiation: negotiation,
            destinationPath: destinationPath,
        )
    }

    /// 세션 종단(성공/실패/취소)을 render-loop에서 관찰해 owned ID를 해제한다.
    /// reducer가 `.succeeded`/`.failed`/`.cancelled`에서 `activeExternalDrop`을 nil로 만들고,
    /// 그 전이(non-nil → nil)를 받아 local 소유 세션을 정리한다.
    func handleSessionTerminal(
        previousActive: ExternalDropActiveSession?,
        currentActive: ExternalDropActiveSession?,
    ) {
        guard previousActive != nil, currentActive == nil else { return }
        activeExternalDropSessionID = nil
    }

    /// 현재 소유 세션이 있으면 정확히 그 세션만 취소하고 local ID를 해제한다.
    /// representable teardown / current-path change에서 호출된다.
    func cancel() {
        guard let sessionID = activeExternalDropSessionID else { return }
        activeExternalDropSessionID = nil
        clientProvider().cancel(sessionID)
        store.send(.view(.externalDropCancelSession(sessionID)))
    }
}
