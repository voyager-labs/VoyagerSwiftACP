import ComposableArchitecture
@testable import VoyagerEntitiesCollection
import VoyagerShared
import XCTest

@MainActor
final class CollectionRefreshWritebackPolicyTests: XCTestCase {
    private func makeOpenedHydratedState(
        compatibility: CollectionFileCompatibilityMetadata? = nil,
    ) -> CollectionState {
        var state = CollectionState()
        state.collectionSession.phase = .opened(
            kind: .hydratedSnapshot,
            base: .stale,
            inflight: .refreshingHydratedSnapshot,
        )
        state.collectionSession.document = .init(
            url: URL(fileURLWithPath: "/tmp/test.col"),
            name: "test",
            compatibility: compatibility,
        )
        let context = CollectionContext(query: "test", scopes: ["/tmp"], conditions: [])
        state.collectionContext = context
        state.collectionSession.metadata.baseline = .init(context: context)
        return state
    }

    private func makeWriteBackAllowedCompatibility() -> CollectionFileCompatibilityMetadata {
        .init(
            sourceSchemaVersion: nil,
            migrationPath: [],
            warnings: [],
            usedDefinitionFallback: false,
            writeBackAllowed: true,
            writeBackReason: .allowed,
        )
    }

    private func makeWriteBackBlockedCompatibility() -> CollectionFileCompatibilityMetadata {
        .init(
            sourceSchemaVersion: nil,
            migrationPath: [],
            warnings: [],
            usedDefinitionFallback: false,
            writeBackAllowed: false,
            writeBackReason: .blockedFutureMinorVersion,
        )
    }

    /// hydrated snapshot이 깨끗하면 refresh 이후 writeback이 시작되는지 검증
    func testRefreshResponse_withCleanStateAndWriteBackAllowed_triggersWriteback() {
        var state = makeOpenedHydratedState(
            compatibility: makeWriteBackAllowedCompatibility(),
        )
        let shouldWriteBack = state.applyRefreshResponse(wasDirtyBeforeApplyingResponse: false)

        XCTAssertTrue(shouldWriteBack)
        XCTAssertTrue(state.collectionSession.phase.isInflightWriteBack)
    }

    /// dirty 상태에서는 refresh 후 writeback을 시작하지 않는지 검증
    func testRefreshResponse_withDirtyState_doesNotTriggerWriteback() {
        var state = makeOpenedHydratedState(
            compatibility: makeWriteBackAllowedCompatibility(),
        )
        let shouldWriteBack = state.applyRefreshResponse(wasDirtyBeforeApplyingResponse: true)

        XCTAssertFalse(shouldWriteBack)
        XCTAssertFalse(state.collectionSession.phase.isInflightRefresh)
        XCTAssertFalse(state.collectionSession.phase.isInflightWriteBack)
    }

    /// writeback이 금지된 경우 refresh만 끝내고 추가 저장을 하지 않는지 검증
    func testRefreshResponse_withWriteBackBlocked_doesNotTriggerWriteback() {
        var state = makeOpenedHydratedState(
            compatibility: makeWriteBackBlockedCompatibility(),
        )
        let shouldWriteBack = state.applyRefreshResponse(wasDirtyBeforeApplyingResponse: false)

        XCTAssertFalse(shouldWriteBack)
        XCTAssertFalse(state.collectionSession.phase.isInflightRefresh)
        XCTAssertFalse(state.collectionSession.phase.isInflightWriteBack)
    }

    /// compatibility 정보가 없으면 기본적으로 writeback 허용으로 보는지 검증
    func testRefreshResponse_withNoCompatibility_defaultsToWriteBackAllowed() {
        var state = makeOpenedHydratedState(compatibility: nil)
        let shouldWriteBack = state.applyRefreshResponse(wasDirtyBeforeApplyingResponse: false)

        XCTAssertTrue(shouldWriteBack)
    }

    /// inflight refresh가 아니면 refresh 응답이 noop인지를 검증
    func testRefreshResponse_notInInflightRefresh_isNoOp() {
        var state = CollectionState()
        state.collectionSession.phase = .opened(
            kind: .hydratedSnapshot,
            base: .ready,
            inflight: .none,
        )
        let shouldWriteBack = state.applyRefreshResponse(wasDirtyBeforeApplyingResponse: false)

        XCTAssertFalse(shouldWriteBack)
    }

    /// refresh 실패가 inflight 상태에서 실패 상태로 전환되는지 검증
    func testRefreshFailed_whenInflightRefresh_transitionsToRefreshFailed() {
        var state = makeOpenedHydratedState()
        XCTAssertTrue(state.collectionSession.phase.isInflightRefresh)

        state.collectionSession.failRefreshOrWriteBack()

        if case .refreshFailed(.hydratedSnapshot) = state.collectionSession.phase {} else {
            XCTFail("Expected .refreshFailed(.hydratedSnapshot)")
        }
    }

    /// inflight가 아니어도 fail 호출이 phase를 refreshFailed로 전환하는지 검증
    func testRefreshFailed_whenNotInflightRefresh_stillTransitionsPhase() {
        var state = CollectionState()
        state.collectionSession.phase = .opened(
            kind: .hydratedSnapshot,
            base: .stale,
            inflight: .none,
        )
        XCTAssertFalse(state.collectionSession.phase.isInflightRefresh)

        state.collectionSession.failRefreshOrWriteBack()

        if case .refreshFailed(.hydratedSnapshot) = state.collectionSession.phase {} else {
            XCTFail("Expected .refreshFailed(.hydratedSnapshot)")
        }
    }

    /// writeback 실패가 refreshFailed 상태로 전환되는지 검증
    func testWriteBackFailure_whenInflightWriteBack_transitionsToRefreshFailed() {
        var state = makeOpenedHydratedState()
        state.collectionSession.beginWriteBackAfterRefresh()
        XCTAssertTrue(state.collectionSession.phase.isInflightWriteBack)

        state.collectionSession.failRefreshOrWriteBack()

        if case .refreshFailed(.hydratedSnapshot) = state.collectionSession.phase {} else {
            XCTFail("Expected .refreshFailed(.hydratedSnapshot)")
        }
    }

    /// save 실패 경로가 writeback 실패와 동일한 phase 전환을 만드는지 검증
    func testSaveFailure_inflightWriteBack_transitionsState() {
        var state = makeOpenedHydratedState()
        state.collectionSession.beginWriteBackAfterRefresh()
        XCTAssertTrue(state.collectionSession.phase.isInflightWriteBack)

        if state.collectionSession.phase.isInflightWriteBack {
            state.collectionSession.failRefreshOrWriteBack()
        }

        if case .refreshFailed(.hydratedSnapshot) = state.collectionSession.phase {} else {
            XCTFail("Expected .refreshFailed(.hydratedSnapshot)")
        }
    }

    /// writeback이 아니면 fail 호출이 phase를 변경하지 않는지 검증
    func testSaveFailure_notInflightWriteBack_doesNotTransitionPhase() {
        var state = CollectionState()
        state.collectionSession.phase = .opened(
            kind: .definition,
            base: .ready,
            inflight: .none,
        )
        let phaseBefore = state.collectionSession.phase

        if state.collectionSession.phase.isInflightWriteBack {
            state.collectionSession.failRefreshOrWriteBack()
        }

        XCTAssertEqual(state.collectionSession.phase, phaseBefore)
    }

    /// refresh 응답을 받으면 writeback 플래그가 설정되는 reducer 경로를 검증
    func testReducer_refreshResponseReceived_withWriteback_marksWritebackInFlightWithoutDelegate() async {
        let store = TestStore(
            initialState: makeOpenedHydratedState(
                compatibility: makeWriteBackAllowedCompatibility(),
            ),
        ) {
            CollectionFeature()
        }

        let response = SearchResponsePayload(itemCount: 0)

        await store.send(.refreshResponseReceived(response, wasDirtyBeforeApplyingResponse: false)) {
            $0.collectionSession.phase = .opened(
                kind: .hydratedSnapshot,
                base: .stale,
                inflight: .writingBackRefreshedSnapshot,
            )
        }
    }

    /// dirty 상태인 refresh 응답은 writeback 없이 종료되는지 검증
    func testReducer_refreshResponseReceived_withoutWriteback_noDelegate() async {
        let initialState = makeOpenedHydratedState(
            compatibility: makeWriteBackAllowedCompatibility(),
        )
        let response = SearchResponsePayload(itemCount: 0)

        let store = TestStore(
            initialState: initialState,
        ) {
            CollectionFeature()
        }

        await store.send(.refreshResponseReceived(response, wasDirtyBeforeApplyingResponse: true)) {
            $0.collectionSession.phase = .opened(
                kind: .hydratedSnapshot,
                base: .stale,
                inflight: .none,
            )
        }
    }

    /// refresh 실패 액션이 phase를 실패 상태로 바꾸는지 검증
    func testReducer_refreshFailed_whenInflightRefresh_transitionsState() async {
        let store = TestStore(
            initialState: makeOpenedHydratedState(),
        ) {
            CollectionFeature()
        }

        await store.send(.refreshFailed) {
            $0.collectionSession.phase = .refreshFailed(kind: .hydratedSnapshot)
        }
    }

    /// refresh 중이 아니면 refreshFailed 액션이 noop인지 검증
    func testReducer_refreshFailed_whenNotInflightRefresh_isNoOp() async {
        var initialState = CollectionState()
        initialState.collectionSession.phase = .opened(
            kind: .hydratedSnapshot,
            base: .ready,
            inflight: .none,
        )

        let store = TestStore(initialState: initialState) {
            CollectionFeature()
        }

        await store.send(.refreshFailed)
    }

    /// writeBackFailed 액션이 실패 상태로 전환되는지 검증
    func testReducer_writeBackFailed_transitionsState() async {
        var initialState = makeOpenedHydratedState()
        initialState.collectionSession.beginWriteBackAfterRefresh()

        let store = TestStore(initialState: initialState) {
            CollectionFeature()
        }

        await store.send(.writeBackFailed) {
            $0.collectionSession.phase = .refreshFailed(kind: .hydratedSnapshot)
        }
    }
}
