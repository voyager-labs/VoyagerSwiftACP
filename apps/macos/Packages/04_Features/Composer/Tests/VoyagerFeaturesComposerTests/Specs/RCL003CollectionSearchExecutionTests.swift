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

    /// RCL-003-execute_filtered_collection_retrieval: ordinary zero response remains an accepted success
    /// A zero-item response without an embedded error must retain the normal accepted-response contract.
    /// - 검증 내용: accepted request/response correlation, applied filters, loading cleanup, success metric
    /// - 사전 조건: an active filter request with a valid zero-item response
    /// - 기대 결과: the response is accepted as success and no failure feedback is presented
    func testExecuteFilteredCollectionRetrieval_ordinaryZeroResponseRemainsAcceptedSuccess() {
        let requestID = UUID()
        let recorder = ComposerMetricRecorder()
        let appliedFilters = AppliedFiltersPayload(
            scopes: ["/VoyagerFixtures/Documents"],
            includeSubfolders: true,
            conditions: [],
        )
        var state = ComposerState()
        state.activeFiltersRequestID = requestID
        state.isLoadingFilters = true
        state.isFilteringInFlight = true

        withDependencies {
            $0.composerMetricClient = ComposerMetricClient { name, value, tags, level in
                recorder.record(name: name, value: value, tags: tags, level: level)
            }
            $0.registryClient = makeRegistryClient()
        } operation: {
            _ = ComposerSearchLifecycleReducer().reduce(
                into: &state,
                action: .filtersResponse(
                    requestID,
                    .success(.init(itemCount: 0, appliedFilters: appliedFilters)),
                ),
            )
        }

        XCTAssertEqual(state.lastAcceptedFiltersRequestID, requestID)
        XCTAssertEqual(state.lastFiltersResponse?.itemCount, 0)
        XCTAssertEqual(state.scopes, ["/VoyagerFixtures/Documents"])
        XCTAssertFalse(state.isLoadingFilters)
        XCTAssertFalse(state.isFilteringInFlight)
        XCTAssertNil(state.activeFiltersRequestID)
        XCTAssertNil(state.lastFailedFiltersRequestID)
        XCTAssertNil(state.transientFeedback)
        XCTAssertEqual(recorder.names, [ComposerCollectionFilterMetrics.applyResult])
        XCTAssertEqual(recorder.outcomes, ["applied"])
    }

    /// RCL-003-execute_filtered_collection_retrieval: thrown filter failure keeps the existing failure lifecycle
    /// The established thrown-error path must clear only process state and emit failure feedback/metrics.
    /// - 검증 내용: loading/request/timing cleanup, failed feedback, query reset, failure-only metric
    /// - 사전 조건: an active filter request that terminates with a thrown error
    /// - 기대 결과: the request finishes as an execution failure without a success metric
    func testExecuteFilteredCollectionRetrieval_thrownFailureKeepsExistingFailureLifecycle() {
        let requestID = UUID()
        let recorder = ComposerMetricRecorder()
        var state = ComposerState()
        state.activeFiltersRequestID = requestID
        state.activeFiltersMetricSource = ComposerCollectionFilterMetrics.sourceManualApply
        state.filtersStartedAt = Date(timeIntervalSince1970: 1)
        state.isLoadingFilters = true
        state.isFilteringInFlight = true
        state.queryRenderPhase = .chipsAppliedPendingList
        let previousResponse = SearchResponsePayload(itemCount: 4)
        state.lastFiltersResponse = previousResponse

        withDependencies {
            $0.composerMetricClient = ComposerMetricClient { name, value, tags, level in
                recorder.record(name: name, value: value, tags: tags, level: level)
            }
            $0.continuousClock = ImmediateClock()
        } operation: {
            _ = ComposerSearchLifecycleReducer().reduce(
                into: &state,
                action: .filtersResponse(requestID, .failure(RCL003FilterFailure.thrown)),
            )
        }

        XCTAssertFalse(state.isLoadingFilters)
        XCTAssertFalse(state.isFilteringInFlight)
        XCTAssertNil(state.activeFiltersRequestID)
        XCTAssertEqual(state.lastFailedFiltersRequestID, requestID)
        XCTAssertEqual(state.lastFiltersResponse, previousResponse)
        XCTAssertNil(state.activeFiltersMetricSource)
        XCTAssertNil(state.filtersStartedAt)
        XCTAssertEqual(state.queryRenderPhase, .idle)
        XCTAssertEqual(state.transientFeedback?.kind, .error)
        XCTAssertEqual(
            recorder.names,
            [ComposerCollectionFilterMetrics.applyDuration, ComposerCollectionFilterMetrics.applyResult],
        )
        XCTAssertEqual(recorder.outcomes, ["execution_failure"])
    }

    /// RCL-003-execute_filtered_collection_retrieval: embedded error is rejected before accepted state mutation
    /// Error-bearing success payloads must share failure cleanup while preserving the last accepted result and filters.
    /// - 검증 내용: prior accepted response/filter preservation, lifecycle cleanup, failure feedback and metric
    /// - 사전 조건: an active request after a previously accepted filtered response
    /// - 기대 결과: no accepted-success state mutates and only execution failure is recorded
    func testExecuteFilteredCollectionRetrieval_embeddedErrorRejectsBeforeAcceptedStateMutation() {
        let previousRequestID = UUID()
        let requestID = UUID()
        let recorder = ComposerMetricRecorder()
        let previousFilters = AppliedFiltersPayload(
            scopes: ["/VoyagerFixtures/Previous"],
            includeSubfolders: false,
            conditions: [],
        )
        let previousResponse = SearchResponsePayload(
            itemCount: 3,
            appliedFilters: previousFilters,
            items: [.string("/VoyagerFixtures/Previous/report.md")],
        )
        var state = ComposerState()
        state.scopes = ["/VoyagerFixtures/Previous"]
        state.scopeEditor.includeSubfolders = false
        state.scopeEditor.committedSelection = state.scopeEditor.selection
        state.scopeEditor.committedIncludeSubfolders = false
        state.lastAcceptedFiltersRequestID = previousRequestID
        state.lastFiltersResponse = previousResponse
        state.activeFiltersRequestID = requestID
        state.activeFiltersMetricSource = ComposerCollectionFilterMetrics.sourceManualApply
        state.filtersStartedAt = Date(timeIntervalSince1970: 1)
        state.isLoadingFilters = true
        state.isFilteringInFlight = true

        let malformedResponse = SearchResponsePayload(
            itemCount: 0,
            appliedFilters: .init(scopes: ["/VoyagerFixtures/Mutated"], includeSubfolders: true),
            items: [],
            error: .init(code: "filter_execution_failed", details: "malformed response"),
        )
        withDependencies {
            $0.composerMetricClient = ComposerMetricClient { name, value, tags, level in
                recorder.record(name: name, value: value, tags: tags, level: level)
            }
            $0.registryClient = makeRegistryClient()
            $0.continuousClock = ImmediateClock()
        } operation: {
            _ = ComposerSearchLifecycleReducer().reduce(
                into: &state,
                action: .filtersResponse(requestID, .success(malformedResponse)),
            )
        }

        XCTAssertEqual(state.lastAcceptedFiltersRequestID, previousRequestID)
        XCTAssertEqual(state.lastFiltersResponse, previousResponse)
        XCTAssertEqual(state.scopes, ["/VoyagerFixtures/Previous"])
        XCTAssertFalse(state.scopeEditor.includeSubfolders)
        XCTAssertEqual(state.scopeEditor.committedSelection, state.scopeEditor.selection)
        XCTAssertFalse(state.scopeEditor.committedIncludeSubfolders)
        XCTAssertFalse(state.isLoadingFilters)
        XCTAssertFalse(state.isFilteringInFlight)
        XCTAssertNil(state.activeFiltersRequestID)
        XCTAssertEqual(state.lastFailedFiltersRequestID, requestID)
        XCTAssertNil(state.activeFiltersMetricSource)
        XCTAssertNil(state.filtersStartedAt)
        XCTAssertEqual(state.transientFeedback?.kind, .error)
        XCTAssertEqual(
            recorder.names,
            [ComposerCollectionFilterMetrics.applyDuration, ComposerCollectionFilterMetrics.applyResult],
        )
        XCTAssertEqual(recorder.outcomes, ["execution_failure"])
    }

    /// RCL-003-execute_filtered_collection_retrieval: stale and duplicate terminal IDs mutate nothing
    /// Correlation must reject a stale response and reject repeated delivery after the active request is cleared.
    /// - 검증 내용: stale no-op, first failure correlation, duplicate no-op, metric cardinality
    /// - 사전 조건: one active request plus a different stale request identifier
    /// - 기대 결과: only the first active terminal response records one failure and one result metric
    func testExecuteFilteredCollectionRetrieval_staleAndDuplicateFailuresMutateOnlyOnce() {
        let staleRequestID = UUID()
        let requestID = UUID()
        let recorder = ComposerMetricRecorder()
        let previousResponse = SearchResponsePayload(itemCount: 2)
        var state = ComposerState()
        state.activeFiltersRequestID = requestID
        state.lastFiltersResponse = previousResponse
        state.isLoadingFilters = true
        state.isFilteringInFlight = true
        let response = SearchResponsePayload(
            itemCount: 0,
            error: .init(code: "filter_execution_failed"),
        )

        withDependencies {
            $0.composerMetricClient = ComposerMetricClient { name, value, tags, level in
                recorder.record(name: name, value: value, tags: tags, level: level)
            }
            $0.continuousClock = ImmediateClock()
        } operation: {
            _ = ComposerSearchLifecycleReducer().reduce(
                into: &state,
                action: .filtersResponse(staleRequestID, .success(response)),
            )
            XCTAssertEqual(state.activeFiltersRequestID, requestID)
            XCTAssertNil(state.lastFailedFiltersRequestID)
            XCTAssertTrue(recorder.names.isEmpty)

            _ = ComposerSearchLifecycleReducer().reduce(
                into: &state,
                action: .filtersResponse(requestID, .success(response)),
            )
            _ = ComposerSearchLifecycleReducer().reduce(
                into: &state,
                action: .filtersResponse(requestID, .success(response)),
            )
        }

        XCTAssertEqual(state.lastFailedFiltersRequestID, requestID)
        XCTAssertEqual(state.lastFiltersResponse, previousResponse)
        XCTAssertNil(state.activeFiltersRequestID)
        XCTAssertEqual(recorder.names, [ComposerCollectionFilterMetrics.applyResult])
        XCTAssertEqual(recorder.outcomes, ["execution_failure"])
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

    // MARK: - RCL-003-execute_filtered_collection_retrieval

    /// RCL-003-execute_filtered_collection_retrieval: 검색 취소는 canonical metric만 기록함
    /// 취소 action이 legacy alias와 canonical event를 중복 기록하지 않는지 검증한다.
    /// - 검증 내용: canonical cancel capture 1건, legacy capture 0건, 검색 상태 초기화
    /// - 사전 조건: 검색 요청이 진행 중인 Composer 상태와 실제 metric recorder
    /// - 기대 결과: 취소 후 canonical metric만 관찰되고 활성 요청이 해제됨
    func testCancelSearch_recordsCanonicalMetricOnceWithoutLegacyAlias() {
        let recorder = ComposerMetricRecorder()
        var state = ComposerState()
        state.isLoadingSearch = true
        state.activeSearchRequestID = UUID()

        withDependencies {
            $0.composerMetricClient = ComposerMetricClient { name, value, tags, level in
                recorder.record(name: name, value: value, tags: tags, level: level)
            }
        } operation: {
            _ = ComposerFeature().reduce(into: &state, action: .view(.cancelSearch))
        }

        XCTAssertEqual(recorder.names, [ComposerCollectionFilterMetrics.queryResult])
        XCTAssertFalse(recorder.names.contains(ComposerCollectionFilterMetrics.legacySearchCancel))
        XCTAssertNil(state.activeSearchRequestID)
        XCTAssertFalse(state.isLoadingSearch)
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

final class ComposerMetricRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [(name: String, tags: [String: String]?)] = []

    func record(name: String, value _: Double, tags: [String: String]?, level _: ComposerMetricLevel) {
        lock.lock()
        calls.append((name, tags))
        lock.unlock()
    }

    var names: [String] {
        lock.lock()
        defer { lock.unlock() }
        return calls.map(\.name)
    }

    var outcomes: [String] {
        lock.lock()
        defer { lock.unlock() }
        return calls.compactMap { $0.tags?["outcome"] }
    }
}

private enum RCL003FilterFailure: Error {
    case thrown
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
