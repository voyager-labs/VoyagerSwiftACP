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
        let metricRecorder = ComposerMetricRecorder()
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
            $0.composerMetricClient = ComposerMetricClient(recordProductMetric: metricRecorder.record)
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
        XCTAssertEqual(metricRecorder.names, [ComposerCollectionFilterMetrics.applyResult])
        XCTAssertEqual(metricRecorder.callsSnapshot.first?.tags?["result_status"], "success")
    }

    /// RCL-003-execute_filtered_collection_retrieval: 빈 query terminal은 query event 하나를 기록함
    /// accepted query가 빈 결과로 종료될 때 submit/duration 분리 없이 terminal event 하나만 기록하는지 검증한다.
    /// - 검증 내용: empty status, bounded duration, operation identity, 원문 property 부재
    /// - 사전 조건: 활성 search request와 빈 결과 response
    /// - 기대 결과: query result event 하나가 terminal payload로 기록됨
    func testExecuteFilteredCollectionRetrieval_emptyQueryResult_recordsOneTerminalEvent() throws {
        let recorder = ComposerMetricRecorder()
        let requestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000022"))
        var state = ComposerState()
        state.activeSearchRequestID = requestID
        state.searchStartedAt = Date(timeIntervalSinceNow: -0.1)

        withDependencies {
            $0.registryClient = makeRegistryClient()
            $0.composerMetricClient = ComposerMetricClient(recordProductMetric: recorder.record)
        } operation: {
            _ = ComposerFeature().reduce(
                into: &state,
                action: .searchResponse(requestID, .success(SearchResponsePayload(itemCount: 0))),
            )
        }

        XCTAssertEqual(recorder.names, [ComposerCollectionFilterMetrics.queryResult])
        let call = try XCTUnwrap(recorder.callsSnapshot.first)
        XCTAssertEqual(call.tags?["result_status"], "empty")
        XCTAssertEqual(call.tags?["source_surface"], "composer")
        XCTAssertEqual(call.tags?["operation_id"], requestID.uuidString.lowercased())
        XCTAssertNotNil(Int(call.tags?["duration_ms"] ?? ""))
        XCTAssertNil(call.tags?["query"])
        XCTAssertNil(call.tags?["filters"])
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

    /// RCL-003-execute_filtered_collection_retrieval: 검색 취소는 terminal query event를 기록함
    /// 활성 query 취소가 bounded terminal payload를 한 번만 기록하는지 검증한다.
    /// - 검증 내용: query event 1건, cancelled status, opaque operation ID와 duration
    /// - 사전 조건: 검색 요청이 진행 중인 Composer 상태와 실제 metric recorder
    /// - 기대 결과: 취소 후 canonical metric만 관찰되고 활성 요청이 해제됨
    func testCancelSearch_recordsCanonicalMetricOnceWithoutLegacyAlias() throws {
        let recorder = ComposerMetricRecorder()
        var state = ComposerState()
        state.isLoadingSearch = true
        state.activeSearchRequestID = UUID()
        state.searchStartedAt = Date(timeIntervalSinceNow: -0.1)

        withDependencies {
            $0.composerMetricClient = ComposerMetricClient(recordProductMetric: recorder.record)
        } operation: {
            _ = ComposerFeature().reduce(into: &state, action: .view(.cancelSearch))
        }

        XCTAssertEqual(recorder.names, [ComposerCollectionFilterMetrics.queryResult])
        let call = try XCTUnwrap(recorder.callsSnapshot.first)
        XCTAssertEqual(call.tags?["result_status"], "cancelled")
        XCTAssertEqual(call.tags?["source_surface"], "composer")
        XCTAssertNotNil(UUID(uuidString: call.tags?["operation_id"] ?? ""))
        XCTAssertNotNil(Int(call.tags?["duration_ms"] ?? ""))
        XCTAssertNil(call.tags?["query"])
        XCTAssertNil(call.tags?["filters"])
        XCTAssertNil(state.activeSearchRequestID)
        XCTAssertFalse(state.isLoadingSearch)
    }

    /// RCL-003-execute_filtered_collection_retrieval: 활성 query 없는 취소는 event를 기록하지 않음
    /// stale 또는 이미 종료된 query 취소가 terminal product event를 만들지 않는지 검증한다.
    /// - 검증 내용: active request 없는 cancel의 capture 0건
    /// - 사전 조건: Composer에 활성 search request가 없음
    /// - 기대 결과: 상태와 metric 모두 변경되지 않음
    func testCancelSearch_withoutActiveRequest_recordsNoMetric() {
        let recorder = ComposerMetricRecorder()
        var state = ComposerState()

        withDependencies {
            $0.composerMetricClient = ComposerMetricClient(recordProductMetric: recorder.record)
        } operation: {
            _ = ComposerFeature().reduce(into: &state, action: .view(.cancelSearch))
        }

        XCTAssertTrue(recorder.names.isEmpty)
    }

    /// RCL-003-execute_filtered_collection_retrieval: collection cleanup은 활성 query terminal을 한 번 기록함
    /// cleanup 이후 반복 cleanup과 늦은 response가 중복 terminal event를 만들지 않는지 검증한다.
    /// - 검증 내용: cancelled query event 1건, 기존 operation ID와 duration, 활성 요청 해제
    /// - 사전 조건: 시작 시각과 request ID가 있는 활성 query
    /// - 기대 결과: 첫 cleanup만 terminal을 기록하고 후속 cleanup/response는 무시됨
    func testCleanupCollectionWork_withActiveQuery_recordsOneCancelledTerminal() throws {
        let recorder = ComposerMetricRecorder()
        let requestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000023"))
        var state = ComposerState()
        state.isLoadingSearch = true
        state.activeSearchRequestID = requestID
        state.searchStartedAt = Date(timeIntervalSinceNow: -0.1)

        withDependencies {
            $0.composerMetricClient = ComposerMetricClient(recordProductMetric: recorder.record)
        } operation: {
            let feature = ComposerFeature()
            _ = feature.reduce(into: &state, action: .internal(.cleanupCollectionWork))
            _ = feature.reduce(into: &state, action: .internal(.cleanupCollectionWork))
            _ = feature.reduce(
                into: &state,
                action: .internal(.searchResponse(requestID, .success(SearchResponsePayload(itemCount: 1)))),
            )
        }

        XCTAssertEqual(recorder.names, [ComposerCollectionFilterMetrics.queryResult])
        let call = try XCTUnwrap(recorder.callsSnapshot.first)
        XCTAssertEqual(call.tags?["result_status"], "cancelled")
        XCTAssertEqual(call.tags?["operation_id"], requestID.uuidString.lowercased())
        XCTAssertNotNil(Int(call.tags?["duration_ms"] ?? ""))
        XCTAssertNil(state.activeSearchRequestID)
        XCTAssertFalse(state.isLoadingSearch)
    }

    /// RCL-003-execute_filtered_collection_retrieval: Composer dismissal은 활성 query terminal을 한 번 기록함
    /// Composer를 닫을 때 활성 query가 canonical cancelled terminal로 종료되는지 검증한다.
    /// - 검증 내용: dismissal 1회, 반복 dismissal, 늦은 response 이후 cancelled query event 1건
    /// - 사전 조건: 검색 요청이 진행 중인 Composer 상태
    /// - 기대 결과: dismissal만 cancelled metric을 기록하고 반복/늦은 event는 no-op임
    func testSetPresentedDismissal_withActiveQuery_recordsOneCancelledTerminal() throws {
        let recorder = ComposerMetricRecorder()
        let requestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000025"))
        var state = ComposerState()
        state.isPresented = true
        state.isLoadingSearch = true
        state.activeSearchRequestID = requestID
        state.searchStartedAt = Date(timeIntervalSinceNow: -0.1)

        withDependencies {
            $0.composerMetricClient = ComposerMetricClient(recordProductMetric: recorder.record)
        } operation: {
            let feature = ComposerFeature()
            _ = feature.reduce(into: &state, action: .view(.setPresented(false)))
            _ = feature.reduce(into: &state, action: .view(.setPresented(false)))
            _ = feature.reduce(
                into: &state,
                action: .internal(.searchResponse(requestID, .success(SearchResponsePayload(itemCount: 1)))),
            )
        }

        XCTAssertEqual(recorder.names, [ComposerCollectionFilterMetrics.queryResult])
        let call = try XCTUnwrap(recorder.callsSnapshot.first)
        XCTAssertEqual(call.tags?["result_status"], "cancelled")
        XCTAssertEqual(call.tags?["operation_id"], requestID.uuidString.lowercased())
        XCTAssertNotNil(Int(call.tags?["duration_ms"] ?? ""))
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

    func record(_ metric: ComposerProductMetric) {
        let call: (name: String, tags: [String: String]) = switch metric {
        case let .queryResult(operationID, result, durationMilliseconds):
            (
                ComposerCollectionFilterMetrics.queryResult,
                tags(result: result, operationID: operationID, durationMilliseconds: durationMilliseconds),
            )
        case let .applyResult(operationID, result, durationMilliseconds):
            (
                ComposerCollectionFilterMetrics.applyResult,
                tags(result: result, operationID: operationID, durationMilliseconds: durationMilliseconds),
            )
        }
        lock.lock()
        calls.append(call)
        lock.unlock()
    }

    func record(name: String, value _: Double, tags: [String: String]?, level _: ComposerMetricLevel) {
        lock.lock()
        calls.append((name, tags))
        lock.unlock()
    }

    private func tags(
        result: ComposerProductMetricResult,
        operationID: UUID,
        durationMilliseconds: Int?,
    ) -> [String: String] {
        var tags = [
            "result_status": result.rawValue,
            "source_surface": ComposerCollectionFilterMetrics.sourceSurface,
            "operation_id": operationID.uuidString.lowercased(),
        ]
        if let durationMilliseconds {
            tags["duration_ms"] = String(durationMilliseconds)
        }
        return tags
    }

    var names: [String] {
        lock.lock()
        defer { lock.unlock() }
        return calls.map(\.name)
    }

    var callsSnapshot: [(name: String, tags: [String: String]?)] {
        lock.lock()
        defer { lock.unlock() }
        return calls
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
