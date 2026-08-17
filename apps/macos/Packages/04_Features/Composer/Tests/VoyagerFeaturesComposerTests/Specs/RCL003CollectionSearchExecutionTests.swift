import ComposableArchitecture
import Foundation
@_spi(Testing)
@testable import VoyagerEntitiesCollection
@testable import VoyagerFeaturesComposer
import VoyagerShared
import XCTest

@MainActor
final class RCL003CollectionSearchExecutionTests: XCTestCase {
    // MARK: - RCL-003-execute_filtered_collection_retrieval

    /// RCL-003-execute_filtered_collection_retrieval: applyFilters는 SearchClient 실행 결과를 수신함
    /// Composer의 filter 실행 action이 searchClient.applyFilters 요청과 filtersResponse 수신으로 이어지는지 검증한다.
    /// - 검증 내용: applyFilters request payload, lastFiltersResponse, loading 해제 확인
    /// - 사전 조건: collection scope와 deterministic condition이 준비된 Composer 상태
    /// - 기대 결과: SearchClient가 filter request를 받고 성공 response가 reducer 상태에 반영됨
    func testExecuteFilteredCollectionRetrieval_withPreparedFilters_callsSearchClientAndStoresResponse() async throws {
        let recorder = ApplyFiltersRecorder()
        var initialState = ComposerState()
        initialState.scopes = ["/VoyagerFixtures/Documents"]
        let conditionID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000020"))
        initialState.conditionEditors = [
            .init(id: conditionID, condition: makeKindCondition()),
        ]
        initialState.isCollectionMode = true

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.registryClient = makeRegistryClient()
            $0.searchClient.applyFilters = { request in
                recorder.record(request)
                return SearchResponsePayload(
                    itemCount: 2,
                    appliedFilters: request.filters.asAppliedFiltersPayload,
                    items: nil,
                    error: nil,
                )
            }
        }
        // applyFilters는 UUID/Date를 생성하므로 이 테스트는 최종 실행 계약만 검증한다.
        store.exhaustivity = .off

        await store.send(.applyFilters)
        await store.receive(\.internal.filtersResponse)

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(recorder.last()?.filters.scopes, ["/VoyagerFixtures/Documents"])
        XCTAssertEqual(recorder.last()?.filters.conditions.map(\.propertyKey), ["kind"])
        XCTAssertEqual(store.state.lastFiltersResponse?.itemCount, 2)
        XCTAssertFalse(store.state.isLoadingFilters)
        XCTAssertFalse(store.state.isFilteringInFlight)
    }

    /// RCL-003-execute_filtered_collection_retrieval: condition 없는 scope-only filter는 검색 실행을 시작하지 않음
    /// VOY-342의 조건 없는 재검색 차단 계약을 Composer package 내부에서 직접 검증한다.
    /// - 검증 내용: SearchClient 미호출, loading/inflight/request 상태 초기화 확인
    /// - 사전 조건: collection mode이고 scope만 준비됐으며 condition은 비어 있음
    /// - 기대 결과: applyFilters는 no-op/cancel 경로로 종료되고 filtersResponse가 발생하지 않음
    func testExecuteFilteredCollectionRetrieval_withScopeOnlyFilters_doesNotCallSearchClient() async {
        let recorder = ApplyFiltersRecorder()
        var initialState = ComposerState()
        initialState.scopes = ["/VoyagerFixtures/Documents"]
        initialState.conditionEditors = []
        initialState.isCollectionMode = true

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.registryClient = makeRegistryClient()
            $0.searchClient.applyFilters = { request in
                recorder.record(request)
                return SearchResponsePayload(itemCount: 1)
            }
        }
        // applyFilters는 Date를 기록하므로 no-op 이후 최종 계약을 직접 검증한다.
        store.exhaustivity = .off

        await store.send(.applyFilters)

        XCTAssertEqual(recorder.count, 0)
        XCTAssertFalse(store.state.isLoadingFilters)
        XCTAssertFalse(store.state.isFilteringInFlight)
        XCTAssertNil(store.state.activeFiltersRequestID)
        XCTAssertNil(store.state.activeFiltersMetricSource)
        XCTAssertNil(store.state.pendingSearchQuery)
        XCTAssertNil(store.state.lastFiltersResponse)
    }

    /// RCL-003-execute_filtered_collection_retrieval: 일반 Composer에서도 scope-only filter는 검색 실행을 시작하지 않음
    /// condition chip 제거 후 scope만 남은 상태가 SearchClient 호출로 이어지지 않는지 검증한다.
    /// - 검증 내용: non-collection 상태에서도 SearchClient 미호출, loading/inflight/request 상태 초기화 확인
    /// - 사전 조건: collection mode가 아니고 scope만 준비됐으며 condition은 비어 있음
    /// - 기대 결과: applyFilters는 no-op/cancel 경로로 종료되고 filtersResponse가 발생하지 않음
    func testExecuteFilteredCollectionRetrieval_withNonCollectionScopeOnlyFilters_doesNotCallSearchClient() async {
        let recorder = ApplyFiltersRecorder()
        var initialState = ComposerState()
        initialState.scopes = ["/VoyagerFixtures/Documents"]
        initialState.conditionEditors = []
        initialState.isCollectionMode = false

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.registryClient = makeRegistryClient()
            $0.searchClient.applyFilters = { request in
                recorder.record(request)
                return SearchResponsePayload(itemCount: 1)
            }
        }
        // applyFilters는 Date를 기록하므로 no-op 이후 최종 계약을 직접 검증한다.
        store.exhaustivity = .off

        await store.send(.applyFilters)

        XCTAssertEqual(recorder.count, 0)
        XCTAssertFalse(store.state.isLoadingFilters)
        XCTAssertFalse(store.state.isFilteringInFlight)
        XCTAssertNil(store.state.activeFiltersRequestID)
        XCTAssertNil(store.state.activeFiltersMetricSource)
        XCTAssertNil(store.state.pendingSearchQuery)
        XCTAssertNil(store.state.lastFiltersResponse)
    }

    /// RCL-003-execute_filtered_collection_retrieval: value commit은 filter 실행을 한 번만 시작한다.
    /// parent condition mutation이 실제 SearchClient chain으로 이어질 때 중복 apply effect를 만들지 않는지 검증한다.
    /// - 검증 내용: single value commit, one applyFilters request, committed payload
    /// - 사전 조건: 실행 가능한 kind condition을 가진 collection-mode Composer
    /// - 기대 결과: 새 value가 포함된 filter request가 정확히 한 번 실행되고 response가 반영됨
    func testExecuteFilteredCollectionRetrieval_valueCommitCallsSearchClientExactlyOnce() async throws {
        let recorder = ApplyFiltersRecorder()
        let conditionID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000021"))
        var initialState = ComposerState()
        initialState.scopes = ["/VoyagerFixtures/Documents"]
        initialState.conditionEditors = [.init(id: conditionID, condition: makeKindCondition())]
        initialState.isCollectionMode = true

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.registryClient = makeRegistryClient()
            $0.searchClient.applyFilters = { request in
                recorder.record(request)
                return SearchResponsePayload(
                    itemCount: 1,
                    appliedFilters: request.filters.asAppliedFiltersPayload,
                    items: nil,
                    error: nil,
                )
            }
        }
        // value commit은 내부 filtersResponse까지 발생하므로 외부 실행 계약만 검증한다.
        store.exhaustivity = .off

        await store.send(.conditionEditor(.element(
            id: conditionID,
            action: .delegate(.commitValues(
                values: ["image"],
                displayValues: ["image"],
                selectedUnitCode: nil,
            )),
        )))
        await store.receive(\.internal.filtersResponse)

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(recorder.last()?.filters.conditions.map(\.propertyKey), ["kind"])
        XCTAssertEqual(recorder.last()?.filters.conditions.first?.value, .string("image"))
        XCTAssertEqual(store.state.conditionEditors[id: conditionID]?.condition.values, ["image"])
        XCTAssertEqual(store.state.lastFiltersResponse?.itemCount, 1)
    }
}

private func makeRegistryClient() -> RegistryClient {
    .init(
        allProperties: { [] },
        labelForKey: { $0 },
        propertyTypeString: { _ in "string" },
        propertyUnitSpec: { _ in nil },
        operatorCodes: { _ in ["eq"] },
        operatorDefinition: { _ in
            OperatorDefinition(
                uiLabel: "Equals",
                mdqueryOperator: "==",
                valueShape: nil,
                valueCount: nil,
                allowedTypes: ["string"],
                inverseOf: nil,
                aliases: nil,
                uiValueKind: ["string": "singleText"],
            )
        },
        resolvePropertyKey: { .canonical($0) },
        resolveCondition: { _, _, values, sourcePayload in
            makeKindCondition(values: values, sourcePayload: sourcePayload)
        },
    )
}

private func makeKindCondition(
    values: [String]? = ["pdf"],
    sourcePayload: CollectionCondition? = nil,
) -> Condition {
    Condition(
        property: .init(
            key: "kind",
            label: "Kind",
            type: .string,
            unitContract: nil,
            operatorOptions: [.init(code: "eq", label: "Equals")],
        ),
        operation: .init(
            code: "eq",
            label: "Equals",
            valueContract: .init(shape: .single, count: .fixed(1), input: .singleText),
        ),
        values: values,
        availability: .available,
        opaqueSource: sourcePayload,
    )
}

private final class ApplyFiltersRecorder: @unchecked Sendable {
    private var requests: [FiltersOnlyRequestPayload] = []

    func record(_ request: FiltersOnlyRequestPayload) {
        requests.append(request)
    }

    var count: Int {
        requests.count
    }

    func last() -> FiltersOnlyRequestPayload? {
        requests.last
    }
}

private extension SearchFiltersPayload {
    var asAppliedFiltersPayload: AppliedFiltersPayload {
        .init(
            scopes: scopes,
            excludedScopes: excludedScopes,
            includeSubfolders: includeSubfolders,
            conditions: conditions,
        )
    }
}
