@_spi(Internals) import ComposableArchitecture
import Foundation
@testable import VoyagerEntitiesCollection
import VoyagerShared
import XCTest

@MainActor
final class RCL003RetrieveEntriesWithFiltersTests: XCTestCase {
    // MARK: - RCL-003-mark_collection_results_as_stale

    /// RCL-003-mark_collection_results_as_stale: 포함 scope 변경은 열린 collection을 stale로 표시
    /// 외부 파일 변경이 collection scope에 포함될 때 refresh 대상 상태로 전환되는지 검증한다.
    /// - 검증 내용: 관련 path 변경이 `CollectionSessionPhase.BaseStatus.stale`로 전환되는지 확인
    /// - 사전 조건: `/VoyagerFixtures/Documents` scope를 가진 열린 collection session
    /// - 기대 결과: session phase가 stale이 되고 refresh blocking reason이 nil이 됨
    func testExternalPathsChanged_withIncludedScope_marksCollectionStale() async {
        let store = TestStore(initialState: makeOpenedReadyState()) {
            CollectionFeature()
        }

        await store.send(.externalPathsChanged(["/VoyagerFixtures/Documents/report.md"])) {
            $0.collectionSession.phase = .opened(kind: .definition, base: .stale, inflight: .none)
        }

        XCTAssertNil(store.state.refreshBlockingReason(
            isCollectionMode: true,
            isDirty: false,
            isSearching: false,
        ))
    }

    /// RCL-003-mark_collection_results_as_stale: 제외 scope 변경은 stale 전환에서 제외
    /// 제외된 하위 path의 변경은 collection 결과를 stale로 만들지 않는지 검증한다.
    /// - 검증 내용: excludedScopes에 포함된 path 변경이 phase를 유지하는지 확인
    /// - 사전 조건: `/VoyagerFixtures/Documents/Archive`가 excludedScopes인 열린 collection session
    /// - 기대 결과: phase가 ready로 유지되고 refresh blocking reason은 `notStale`임
    func testExternalPathsChanged_withExcludedScope_keepsCollectionReady() async {
        let initialState = makeOpenedReadyState()
        let store = TestStore(initialState: initialState) {
            CollectionFeature()
        }

        await store.send(.externalPathsChanged(["/VoyagerFixtures/Documents/Archive/old.md"]))

        XCTAssertEqual(store.state.collectionSession.phase, initialState.collectionSession.phase)
        XCTAssertEqual(
            store.state.refreshBlockingReason(isCollectionMode: true, isDirty: false, isSearching: false),
            .notStale,
        )
    }

    /// RCL-003-mark_collection_results_as_stale: register는 기존 invalidation timestamp를 보존함
    /// 저장된 collection을 다시 열며 relevance root를 재등록해도 이미 감지한 stale 상태가 사라지지 않는지 검증한다.
    /// - 검증 내용: registerCollection 이후 lastInvalidatedAt 유지와 consumeInvalidation true 확인
    /// - 사전 조건: 같은 collection path에 invalidated record가 이미 저장됨
    /// - 기대 결과: reopen/register 후에도 refresh 대상 상태가 유지됨
    func testRegisterCollection_withExistingInvalidation_preservesStaleTimestamp() {
        let client = CollectionStalenessClient.live(userDefaultsClient: UserDefaultsClient.testValue)
        let collectionPath = "/VoyagerFixtures/Collections/report.voycoll"
        let invalidatedAt = Date(timeIntervalSince1970: 1_700_000_100)

        client.upsertRecord(
            collectionPath,
            CollectionStalenessRecord(
                definitionFingerprint: "before-reopen",
                relevanceRoots: ["/VoyagerFixtures/Documents"],
                excludedScopes: [],
                includeSubfolders: true,
                lastInvalidatedAt: invalidatedAt,
            ),
        )
        client.registerCollection(
            collectionPath,
            ["/VoyagerFixtures/Documents", "/VoyagerFixtures/Documents/../Documents"],
            ["/VoyagerFixtures/Documents/Archive"],
            true,
        )

        let record = client.record(collectionPath)
        XCTAssertEqual(record?.lastInvalidatedAt, invalidatedAt)
        XCTAssertEqual(record?.relevanceRoots, ["/VoyagerFixtures/Documents"])
        XCTAssertEqual(record?.excludedScopes, ["/VoyagerFixtures/Documents/Archive"])
        XCTAssertTrue(client.consumeInvalidation(collectionPath))
        XCTAssertFalse(client.consumeInvalidation(collectionPath))
    }

    // MARK: - RCL-003-apply_deterministic_filters

    /// RCL-003-apply_deterministic_filters: collection file condition은 registry 정의를 통해 deterministic filter로 resolve됨
    /// 저장된 `.voycoll` condition payload가 검색 실행 전 canonical condition으로 변환되는지 검증한다.
    /// - 검증 내용: scopes/excludedScopes 보존, condition property/operator/value resolve 확인
    /// - 사전 조건: `condition_collection.voycoll` fixture와 동일한 kind/size 조건을 가진 collection file
    /// - 기대 결과: deterministic filter resolution 결과가 canonical condition 두 개를 반환함
    func testApplyDeterministicFilters_withConditionFile_resolvesCanonicalConditions() {
        let file = VoyagerCollectionFile(
            id: "rcl-filter-resolution",
            name: "RCL Filter Resolution",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            query: "invoice",
            scopes: ["/VoyagerFixtures/Documents"],
            excludedScopes: ["/VoyagerFixtures/Documents/Archive"],
            conditions: [
                CollectionCondition(propertyKey: "kind", operatorCode: "eq", value: .string("pdf")),
                CollectionCondition(propertyKey: "size", operatorCode: "gt", value: .number(1024)),
            ],
            snapshot: nil,
            snapshotMeta: nil,
            appVersion: "VOY-346-test",
        )

        let resolved = CollectionFilterResolution.resolve(file: file, registryClient: makeDeterministicRegistryClient())

        XCTAssertEqual(resolved.scopes, ["/VoyagerFixtures/Documents"])
        XCTAssertEqual(resolved.excludedScopes, ["/VoyagerFixtures/Documents/Archive"])
        XCTAssertEqual(resolved.conditions.map(\.propertyKey), ["kind", "size"])
        XCTAssertEqual(resolved.conditions.map(\.operatorCode), ["eq", "gt"])
        XCTAssertEqual(resolved.unknownKeys, [])
    }

    // MARK: - RCL-003-request_collection_results_refresh

    /// RCL-003-request_collection_results_refresh: dirty collection은 refresh 요청을 막음
    /// 저장되지 않은 filter 변경이 있을 때 stale refresh가 실행되지 않아야 한다.
    /// - 검증 내용: dirty 상태의 refresh blocking reason이 `dirtyCollection`인지 확인
    /// - 사전 조건: baseline과 현재 collectionContext가 다른 stale collection session
    /// - 기대 결과: refresh 요청 전 gate가 dirty 사유를 반환함
    func testRefreshBlockingReason_withDirtyCollection_returnsDirtyCollection() {
        var state = makeOpenedReadyState()
        state.collectionSession.markInvalidatedLocally()
        state.collectionContext = CollectionContext(
            query: "changed",
            scopes: ["/VoyagerFixtures/Documents"],
            excludedScopes: ["/VoyagerFixtures/Documents/Archive"],
            conditions: [],
        )

        XCTAssertEqual(
            state.refreshBlockingReason(isCollectionMode: true, isDirty: state.isDirty, isSearching: false),
            .dirtyCollection,
        )
    }

    /// RCL-003-request_collection_results_refresh: refresh 중 중복 요청은 refreshInFlight로 차단
    /// 이미 hydrated snapshot refresh가 진행 중이면 새 refresh를 시작하지 않는지 검증한다.
    /// - 검증 내용: inflight refresh 상태의 blocking reason 확인
    /// - 사전 조건: stale 상태에서 `refreshRequested`가 먼저 처리된 열린 collection session
    /// - 기대 결과: phase inflight가 refreshingHydratedSnapshot이고 blocking reason은 `refreshInFlight`임
    func testRefreshRequested_whenStale_entersInflightAndBlocksDuplicateRefresh() async {
        var state = makeOpenedReadyState()
        state.collectionSession.markInvalidatedLocally()
        let store = TestStore(initialState: state) {
            CollectionFeature()
        }

        await store.send(.refreshRequested) {
            $0.collectionSession.phase = .opened(
                kind: .definition,
                base: .stale,
                inflight: .refreshingHydratedSnapshot,
            )
        }

        XCTAssertEqual(
            store.state.refreshBlockingReason(isCollectionMode: true, isDirty: false, isSearching: false),
            .refreshInFlight,
        )
    }

    // MARK: - RCL-003-refresh_collection_results

    /// RCL-003-refresh_collection_results: empty refresh response는 빈 결과 상태로 refresh를 종료
    /// refresh 결과가 0건이어도 error가 아니라 정상 empty result로 처리되는지 검증한다.
    /// - 검증 내용: `SearchResponsePayload(itemCount: 0)` 수신 후 refresh inflight가 종료되는지 확인
    /// - 사전 조건: stale hydrated snapshot refresh가 진행 중이고 dirty 상태가 아님
    /// - 기대 결과: writeback 없이 inflight가 none으로 바뀌며 refreshFailed가 되지 않음
    func testRefreshResponseReceived_withEmptyResult_finishesRefreshWithoutError() async {
        var state = makeOpenedReadyState()
        state.collectionSession.phase = .opened(
            kind: .hydratedSnapshot,
            base: .stale,
            inflight: .refreshingHydratedSnapshot,
        )
        state.collectionSession.document?.compatibility = makeWriteBackBlockedCompatibility()
        let store = TestStore(initialState: state) {
            CollectionFeature()
        }

        await store.send(.refreshResponseReceived(.init(itemCount: 0), wasDirtyBeforeApplyingResponse: false)) {
            $0.collectionSession.phase = .opened(kind: .hydratedSnapshot, base: .stale, inflight: .none)
        }
    }

    /// RCL-003-refresh_collection_results: refresh 실패는 refreshFailed phase로 전환된다.
    /// refresh effect 실패가 열린 collection session의 실패 상태로 관찰되는지 검증한다.
    /// - 검증 내용: inflight refresh 중 `refreshFailed` 수신 시 phase 전환
    /// - 사전 조건: hydrated snapshot stale refresh가 진행 중인 collection session
    /// - 기대 결과: session phase가 `refreshFailed(kind: .hydratedSnapshot)`가 됨
    func testRefreshFailed_whileRefreshingHydratedSnapshot_marksRefreshFailed() async {
        var state = makeOpenedReadyState()
        state.collectionSession.phase = .opened(
            kind: .hydratedSnapshot,
            base: .stale,
            inflight: .refreshingHydratedSnapshot,
        )
        let store = TestStore(initialState: state) {
            CollectionFeature()
        }

        await store.send(.refreshFailed) {
            $0.collectionSession.phase = .refreshFailed(kind: .hydratedSnapshot)
        }
    }

    /// RCL-003-refresh_collection_results: writeback 완료는 refreshed ready session으로 전환된다.
    /// refresh 결과 writeback 성공 후 baseline과 navigation payload가 갱신되는지 검증한다.
    /// - 검증 내용: writeBackCompleted 후 document/baseline/phase와 delegate payload
    /// - 사전 조건: stale definition collection이 writeback inflight 상태임
    /// - 기대 결과: session은 ready가 되고 writeBackNavigationPrepared delegate가 발생함
    func testWriteBackCompleted_afterRefresh_updatesBaselineAndNavigation() async {
        var state = makeOpenedReadyState()
        state.collectionSession.phase = .opened(
            kind: .definition,
            base: .stale,
            inflight: .writingBackRefreshedSnapshot,
        )
        let savedContext = CollectionContext(query: "refreshed", scopes: ["/VoyagerFixtures/Documents"], conditions: [])
        let completion = CollectionSaveCompletion(
            url: URL(fileURLWithPath: "/VoyagerFixtures/Collections/refreshed.voycoll"),
            file: makeRefreshedFile(query: "refreshed"),
            savedContext: savedContext,
        )
        let actions = await reduce(&state, action: .writeBackCompleted(completion))

        XCTAssertEqual(state.collectionContext, savedContext)
        XCTAssertEqual(state.collectionSession.document?.url, completion.url)
        XCTAssertEqual(state.collectionSession.document?.name, "refreshed")
        XCTAssertEqual(state.collectionSession.metadata.baseline, CollectionBaseline(context: savedContext))
        XCTAssertEqual(state.collectionSession.phase, .opened(kind: .definition, base: .ready, inflight: .none))
        XCTAssertNotNil(writeBackNavigation(from: actions))
    }

    private func reduce(
        _ state: inout CollectionState,
        action: CollectionAction,
    ) async -> [CollectionAction] {
        let effect = CollectionFeature().reduce(into: &state, action: action)
        var actions: [CollectionAction] = []
        for await action in effect.actions {
            actions.append(action)
        }
        return actions
    }

    private func writeBackNavigation(from actions: [CollectionAction]) -> CollectionWriteBackNavigationPayload? {
        for action in actions {
            if case let .delegate(.writeBackNavigationPrepared(payload)) = action {
                return payload
            }
        }
        return nil
    }

    private func makeDeterministicRegistryClient() -> RegistryClient {
        RegistryClient(
            allProperties: { [] },
            labelForKey: { key in
                switch key {
                case "kind": "Kind"
                case "size": "Size"
                default: key
                }
            },
            propertyTypeString: { key in
                switch key {
                case "size": "number"
                default: "string"
                }
            },
            propertyUnitSpec: { _ in nil },
            operatorCodes: { key in
                switch key {
                case "kind": ["eq"]
                case "size": ["gt"]
                default: []
                }
            },
            operatorDefinition: { code in
                switch code {
                case "eq": OperatorDefinition(uiLabel: "is", uiValueKind: ["string": "singleText"])
                case "gt": OperatorDefinition(uiLabel: "greater than", uiValueKind: ["number": "singleNumber"])
                default: OperatorDefinition(uiLabel: code, uiValueKind: ["string": "singleText"])
                }
            },
            operatorValueUIKind: { code, typeKey in
                switch (code, typeKey) {
                case ("eq", "string"): "singleText"
                case ("gt", "number"): "singleNumber"
                default: "singleText"
                }
            },
            resolvePropertyKey: { .canonical($0) },
        )
    }

    private func makeOpenedReadyState() -> CollectionState {
        let context = CollectionContext(
            query: "report",
            scopes: ["/VoyagerFixtures/Documents"],
            excludedScopes: ["/VoyagerFixtures/Documents/Archive"],
            conditions: [],
        )
        var state = CollectionState()
        state.collectionContext = context
        state.collectionSession.phase = .opened(kind: .definition, base: .ready, inflight: .none)
        state.collectionSession.document = .init(
            url: URL(fileURLWithPath: "/VoyagerFixtures/Collections/report.voycoll"),
            name: "report",
            compatibility: makeWriteBackBlockedCompatibility(),
        )
        state.collectionSession.metadata.baseline = CollectionBaseline(context: context)
        return state
    }

    private func makeRefreshedFile(query: String) -> VoyagerCollectionFile {
        VoyagerCollectionFile(
            id: "rcl-003-refreshed",
            name: "refreshed",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            query: query,
            scopes: ["/VoyagerFixtures/Documents"],
            conditions: [],
            snapshot: nil,
            snapshotMeta: nil,
            appVersion: nil,
        )
    }

    private func makeWriteBackBlockedCompatibility() -> CollectionFileCompatibilityMetadata {
        .init(
            sourceSchemaVersion: .init(major: 1, minor: 1),
            migrationPath: [],
            warnings: [],
            usedDefinitionFallback: false,
            writeBackAllowed: false,
            writeBackReason: .blockedFutureMinorVersion,
        )
    }
}
