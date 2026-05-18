import ComposableArchitecture
@testable import VoyagerEntitiesCollection
import VoyagerShared
import XCTest

@MainActor
final class CollectionRefreshWritebackPolicyTests: XCTestCase {
    private func makeOpenedHydratedState(
        compatibility: CollectionFileCompatibilityMetadata? = nil
    ) -> CollectionState {
        var state = CollectionState()
        state.collectionSession.phase = .opened(
            kind: .hydratedSnapshot,
            base: .stale,
            inflight: .refreshingHydratedSnapshot
        )
        state.collectionSession.document = .init(
            url: URL(fileURLWithPath: "/tmp/test.col"),
            name: "test",
            compatibility: compatibility
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
            writeBackReason: .allowed
        )
    }

    private func makeWriteBackBlockedCompatibility() -> CollectionFileCompatibilityMetadata {
        .init(
            sourceSchemaVersion: nil,
            migrationPath: [],
            warnings: [],
            usedDefinitionFallback: false,
            writeBackAllowed: false,
            writeBackReason: .blockedFutureMinorVersion
        )
    }

    func testRefreshResponse_withCleanStateAndWriteBackAllowed_triggersWriteback() {
        var state = makeOpenedHydratedState(
            compatibility: makeWriteBackAllowedCompatibility()
        )
        let shouldWriteBack = state.applyRefreshResponse(wasDirtyBeforeApplyingResponse: false)

        XCTAssertTrue(shouldWriteBack)
        XCTAssertTrue(state.collectionSession.phase.isInflightWriteBack)
    }

    func testRefreshResponse_withDirtyState_doesNotTriggerWriteback() {
        var state = makeOpenedHydratedState(
            compatibility: makeWriteBackAllowedCompatibility()
        )
        let shouldWriteBack = state.applyRefreshResponse(wasDirtyBeforeApplyingResponse: true)

        XCTAssertFalse(shouldWriteBack)
        XCTAssertFalse(state.collectionSession.phase.isInflightRefresh)
        XCTAssertFalse(state.collectionSession.phase.isInflightWriteBack)
    }

    func testRefreshResponse_withWriteBackBlocked_doesNotTriggerWriteback() {
        var state = makeOpenedHydratedState(
            compatibility: makeWriteBackBlockedCompatibility()
        )
        let shouldWriteBack = state.applyRefreshResponse(wasDirtyBeforeApplyingResponse: false)

        XCTAssertFalse(shouldWriteBack)
        XCTAssertFalse(state.collectionSession.phase.isInflightRefresh)
        XCTAssertFalse(state.collectionSession.phase.isInflightWriteBack)
    }

    func testRefreshResponse_withNoCompatibility_defaultsToWriteBackAllowed() {
        var state = makeOpenedHydratedState(compatibility: nil)
        let shouldWriteBack = state.applyRefreshResponse(wasDirtyBeforeApplyingResponse: false)

        XCTAssertTrue(shouldWriteBack)
    }

    func testRefreshResponse_notInInflightRefresh_isNoOp() {
        var state = CollectionState()
        state.collectionSession.phase = .opened(
            kind: .hydratedSnapshot,
            base: .ready,
            inflight: .none
        )
        let shouldWriteBack = state.applyRefreshResponse(wasDirtyBeforeApplyingResponse: false)

        XCTAssertFalse(shouldWriteBack)
    }

    func testRefreshFailed_whenInflightRefresh_transitionsToRefreshFailed() {
        var state = makeOpenedHydratedState()
        XCTAssertTrue(state.collectionSession.phase.isInflightRefresh)

        state.collectionSession.failRefreshOrWriteBack()

        if case .refreshFailed(.hydratedSnapshot) = state.collectionSession.phase {} else {
            XCTFail("Expected .refreshFailed(.hydratedSnapshot)")
        }
    }

    func testRefreshFailed_whenNotInflightRefresh_stillTransitionsPhase() {
        var state = CollectionState()
        state.collectionSession.phase = .opened(
            kind: .hydratedSnapshot,
            base: .stale,
            inflight: .none
        )
        XCTAssertFalse(state.collectionSession.phase.isInflightRefresh)

        state.collectionSession.failRefreshOrWriteBack()

        if case .refreshFailed(.hydratedSnapshot) = state.collectionSession.phase {} else {
            XCTFail("Expected .refreshFailed(.hydratedSnapshot)")
        }
    }

    func testWriteBackFailure_whenInflightWriteBack_transitionsToRefreshFailed() {
        var state = makeOpenedHydratedState()
        state.collectionSession.beginWriteBackAfterRefresh()
        XCTAssertTrue(state.collectionSession.phase.isInflightWriteBack)

        state.collectionSession.failRefreshOrWriteBack()

        if case .refreshFailed(.hydratedSnapshot) = state.collectionSession.phase {} else {
            XCTFail("Expected .refreshFailed(.hydratedSnapshot)")
        }
    }

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

    func testSaveFailure_notInflightWriteBack_doesNotTransitionPhase() {
        var state = CollectionState()
        state.collectionSession.phase = .opened(
            kind: .definition,
            base: .ready,
            inflight: .none
        )
        let phaseBefore = state.collectionSession.phase

        if state.collectionSession.phase.isInflightWriteBack {
            state.collectionSession.failRefreshOrWriteBack()
        }

        XCTAssertEqual(state.collectionSession.phase, phaseBefore)
    }

    func testReducer_refreshResponseReceived_withWriteback_marksWritebackInFlightWithoutDelegate() async {
        let store = TestStore(
            initialState: makeOpenedHydratedState(
                compatibility: makeWriteBackAllowedCompatibility()
            )
        ) {
            CollectionFeature()
        }

        let response = SearchResponsePayload(itemCount: 0)

        await store.send(.refreshResponseReceived(response, wasDirtyBeforeApplyingResponse: false)) {
            $0.collectionSession.phase = .opened(
                kind: .hydratedSnapshot,
                base: .stale,
                inflight: .writingBackRefreshedSnapshot
            )
        }
    }

    func testReducer_refreshResponseReceived_withoutWriteback_noDelegate() async {
        let initialState = makeOpenedHydratedState(
            compatibility: makeWriteBackAllowedCompatibility()
        )
        let response = SearchResponsePayload(itemCount: 0)

        let store = TestStore(
            initialState: initialState
        ) {
            CollectionFeature()
        }

        await store.send(.refreshResponseReceived(response, wasDirtyBeforeApplyingResponse: true)) {
            $0.collectionSession.phase = .opened(
                kind: .hydratedSnapshot,
                base: .stale,
                inflight: .none
            )
        }
    }

    func testReducer_refreshFailed_whenInflightRefresh_transitionsState() async {
        let store = TestStore(
            initialState: makeOpenedHydratedState()
        ) {
            CollectionFeature()
        }

        await store.send(.refreshFailed) {
            $0.collectionSession.phase = .refreshFailed(kind: .hydratedSnapshot)
        }
    }

    func testReducer_refreshFailed_whenNotInflightRefresh_isNoOp() async {
        var initialState = CollectionState()
        initialState.collectionSession.phase = .opened(
            kind: .hydratedSnapshot,
            base: .ready,
            inflight: .none
        )

        let store = TestStore(initialState: initialState) {
            CollectionFeature()
        }

        await store.send(.refreshFailed)
    }

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
