import ComposableArchitecture
import Foundation
@_spi(Testing)
@testable import VoyagerEntitiesCollection
@testable import VoyagerFeaturesComposer
import VoyagerShared
import XCTest

private actor SearchCancellationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var wasCancelled = false

    func wait() async throws -> SearchResponsePayload {
        try await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                let waiters = startWaiters
                startWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
            throw CancellationError()
        } onCancel: {
            Task { await self.markCancelled() }
        }
    }

    func waitUntilStarted() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func cancellationObserved() -> Bool {
        wasCancelled
    }

    private func markCancelled() {
        wasCancelled = true
        continuation?.resume()
        continuation = nil
    }
}

private final class RCL004MetricRecorder: @unchecked Sendable {
    struct Call {
        let name: String
        let tags: [String: String]?
    }

    private let lock = NSLock()
    private var recordedCalls: [Call] = []

    func record(_ metric: ComposerProductMetric) {
        let call: Call = switch metric {
        case let .queryResult(operationID, result, durationMilliseconds):
            .init(
                name: ComposerCollectionFilterMetrics.queryResult,
                tags: tags(result: result, operationID: operationID, durationMilliseconds: durationMilliseconds),
            )
        case let .applyResult(operationID, result, durationMilliseconds):
            .init(
                name: ComposerCollectionFilterMetrics.applyResult,
                tags: tags(result: result, operationID: operationID, durationMilliseconds: durationMilliseconds),
            )
        }
        lock.lock()
        recordedCalls.append(call)
        lock.unlock()
    }

    func record(name: String, value _: Double, tags: [String: String]?, level _: ComposerMetricLevel) {
        lock.lock()
        recordedCalls.append(Call(name: name, tags: tags))
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

    var calls: [Call] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCalls
    }
}

private final class RCL004SearchRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedRequests: [SearchRequestPayload] = []

    func record(_ request: SearchRequestPayload) {
        lock.lock()
        recordedRequests.append(request)
        lock.unlock()
    }

    var requests: [SearchRequestPayload] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }
}

@MainActor
final class RCL004ComposeCollectionFilterTests: XCTestCase {
    // MARK: - RCL-004-submit_collection_filter_query

    /// RCL-004-submit_collection_filter_query: 입력된 자연어 query는 변환 요청 상태로 전환됨
    /// submit 시 query text를 trim하고 active search request를 생성하는지 검증한다.
    /// - 검증 내용: loading/search phase, submitted filters, active request, input clear 상태 확인
    /// - 사전 조건: collection scope가 선택되어 있고 query field에 공백 포함 문장이 입력됨
    /// - 기대 결과: query 변환 in-flight 상태가 시작되고 사용자 입력은 비워짐
    func testSubmitCollectionFilterQuery_withText_entersSearchInFlightState() {
        var state = ComposerState()
        state.text = "  find invoices  "
        state.scopes = ["/VoyagerFixtures/Documents"]
        state.includeDirectories = true

        _ = ComposerFeature().reduce(into: &state, action: .submit)

        XCTAssertTrue(state.isLoadingSearch)
        XCTAssertFalse(state.isLoadingFilters)
        XCTAssertEqual(state.queryRenderPhase, .searching)
        XCTAssertEqual(state.text, "")
        let requestID = state.activeSearchRequestID
        XCTAssertNotNil(requestID)
        XCTAssertEqual(state.queryRecoveryContext?.rawText, "  find invoices  ")
        XCTAssertEqual(state.queryRecoveryContext?.capturedInputRevision, 0)
        XCTAssertEqual(state.queryRecoveryContext?.stage, requestID.map(ComposerQueryRecoveryContext.Stage.search))
        XCTAssertEqual(state.inputRevision, 0)
        XCTAssertEqual(state.submittedSearchFilters?.scopes, ["/VoyagerFixtures/Documents"])
        XCTAssertTrue(state.includeDirectories)
    }

    /// RCL-004-submit_collection_filter_query: query submit 자체는 Product event를 기록하지 않음
    /// 최초 submit은 silent하고 재제출은 submit event 없이 이전 query terminal만 기록하는지 검증한다.
    /// - 검증 내용: 최초 submit capture 0건, 재제출 시 이전 operation의 cancelled terminal 1건
    /// - 사전 조건: 비공백 query를 최초 제출한 뒤 다른 비공백 query를 재제출함
    /// - 기대 결과: 별도 submit event 없이 이전 query만 종료되고 최신 원문 복구 상태가 유지됨
    func testSubmitCollectionFilterQuery_recordsOnlySupersededTerminalOnResubmit() throws {
        let recorder = RCL004MetricRecorder()
        var state = ComposerState()
        state.text = "find invoices"
        var firstRequestID: UUID?

        withDependencies {
            $0.composerMetricClient = ComposerMetricClient(recordProductMetric: recorder.record)
        } operation: {
            _ = ComposerFeature().reduce(into: &state, action: .submit)
            firstRequestID = state.activeSearchRequestID
            XCTAssertTrue(recorder.calls.isEmpty)
            state.text = "find reports"
            _ = ComposerFeature().reduce(into: &state, action: .submit)
        }

        let supersededRequestID = try XCTUnwrap(firstRequestID)
        XCTAssertEqual(recorder.calls.map(\.name), [ComposerCollectionFilterMetrics.queryResult])
        let call = try XCTUnwrap(recorder.calls.first)
        XCTAssertEqual(call.tags?["result_status"], "cancelled")
        XCTAssertEqual(call.tags?["operation_id"], supersededRequestID.uuidString.lowercased())
        XCTAssertEqual(state.queryRecoveryContext?.rawText, "find reports")
        XCTAssertEqual(
            state.queryRecoveryContext?.stage,
            state.activeSearchRequestID.map(ComposerQueryRecoveryContext.Stage.search),
        )
    }

    /// RCL-004-submit_collection_filter_query: 공백 query는 submit metric을 기록하지 않음
    /// 기존 비어 있는 query guard가 metric 기록보다 먼저 동작하는지 검증한다.
    /// - 검증 내용: whitespace-only submit에서 metric capture와 search loading이 모두 없음
    /// - 사전 조건: query field에 공백만 입력됨
    /// - 기대 결과: reducer가 no-op으로 종료되고 metric은 기록되지 않음
    func testSubmitCollectionFilterQuery_withWhitespace_doesNotRecordMetric() {
        let recorder = RCL004MetricRecorder()
        var state = ComposerState()
        state.text = " \n\t "

        withDependencies {
            $0.composerMetricClient = ComposerMetricClient { name, value, tags, level in
                recorder.record(name: name, value: value, tags: tags, level: level)
            }
        } operation: {
            _ = ComposerFeature().reduce(into: &state, action: .submit)
        }

        XCTAssertTrue(recorder.calls.isEmpty)
        XCTAssertFalse(state.isLoadingSearch)
        XCTAssertEqual(state.text, " \n\t ")
        XCTAssertNil(state.activeSearchRequestID)
    }

    /// RCL-004-submit_collection_filter_query: 변환 중 throw가 발생하면 제출 원문을 그대로 복원함
    /// 공백과 Unicode를 포함한 사용자 입력이 전송 payload와 별개로 보존되는 대표 실패 경로를 검증한다.
    /// - 검증 내용: search payload trim, 변환 실패 후 visible text의 scalar 단위 원문 복원
    /// - 사전 조건: synthetic Unicode query의 앞뒤에 공백과 개행이 있고 search client가 throw함
    /// - 기대 결과: 요청에는 trim된 query가 전달되고 입력창에는 제출 전 원문이 정확히 복원됨
    func testSubmitCollectionFilterQuery_whenConversionThrows_restoresExactRawInput() async {
        let rawQuery = " \tVOY589_SYNTHETIC_청구서.PDF  \n"
        let trimmedQuery = "VOY589_SYNTHETIC_청구서.PDF"
        let recorder = RCL004SearchRequestRecorder()
        let clock = TestClock()
        var initialState = ComposerState()
        initialState.text = rawQuery
        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.searchClient.search = { request in
                recorder.record(request)
                throw MockLocalizedError("LLM_CONVERSION_FAILED: synthetic")
            }
        }
        // store.exhaustivity = .off: 생성되는 request UUID보다 visible 복원 계약을 검증한다.
        store.exhaustivity = .off

        await store.send(.submit)
        await store.receive(\.internal.searchResponse)

        XCTAssertEqual(recorder.requests.map(\.query), [trimmedQuery])
        XCTAssertEqual(store.state.text, rawQuery)
        XCTAssertEqual(store.state.text.unicodeScalars.count, rawQuery.unicodeScalars.count)
        XCTAssertNil(store.state.queryRecoveryContext)

        await store.send(.internal(.clearTransientFeedback))
        await store.finish()
    }

    /// RCL-004-submit_collection_filter_query: accepted no-op success는 제출 뒤의 최신 입력을 보존함
    /// 변환 성공 응답이 filter 실행 없이 종료될 때 clear 상태와 후속 사용자 입력을 덮어쓰지 않는지 검증한다.
    /// - 검증 내용: submit-owned clear, 후속 setText, active response 수락 뒤 visible text 보존
    /// - 사전 조건: query를 제출한 뒤 사용자가 새 synthetic text를 입력하고 unchanged response가 도착함
    /// - 기대 결과: 제출 직후에는 비어 있고 response 처리 뒤에는 최신 사용자 입력이 유지됨
    func testSubmitCollectionFilterQuery_whenAcceptedNoOpSucceeds_preservesNewerVisibleInput() {
        var state = ComposerState()
        state.text = "VOY589_SYNTHETIC_청구서.PDF"

        _ = ComposerFeature().reduce(into: &state, action: .submit)
        XCTAssertEqual(state.text, "")
        let requestID = state.activeSearchRequestID
        guard let requestID else {
            return XCTFail("submit must create an active search request")
        }

        _ = ComposerFeature().reduce(into: &state, action: .setText("VOY589_SYNTHETIC_NEW"))
        _ = ComposerFeature().reduce(
            into: &state,
            action: .searchResponse(
                requestID,
                .success(SearchResponsePayload(
                    itemCount: 0,
                    queryConversion: SearchQueryConversionMetadataPayload(outcome: .unchangedResult),
                )),
            ),
        )

        XCTAssertEqual(state.text, "VOY589_SYNTHETIC_NEW")
        XCTAssertNil(state.activeSearchRequestID)
        XCTAssertFalse(state.isLoadingSearch)
    }

    /// RCL-004-submit_collection_filter_query: 복원된 query를 수정해 재제출하면 새 trimmed 요청이 성공함
    /// conversion error payload 뒤 복원된 입력을 사용자가 수정하고 즉시 재제출하는 retry 경로를 검증한다.
    /// - 검증 내용: 첫 실패의 원문 복원, 수정된 retry payload trim, 새 request 성공 후 visible clear
    /// - 사전 조건: 첫 search는 conversion error payload를 반환하고 두 번째 search는 unchanged success를 반환함
    /// - 기대 결과: 두 요청이 각각 trim되어 전송되고 retry 성공 뒤 active search와 visible text가 정리됨
    func testSubmitCollectionFilterQuery_afterConversionFailureEditAndResubmit_sendsTrimmedSuccessfulRetry() async {
        let firstRawQuery = " \tVOY589_SYNTHETIC_FIRST.PDF  \n"
        let retryRawQuery = "  VOY589_SYNTHETIC_RETRY.PDF \n"
        let recorder = RCL004SearchRequestRecorder()
        let clock = TestClock()
        var initialState = ComposerState()
        initialState.text = firstRawQuery
        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.searchClient.search = { request in
                recorder.record(request)
                if recorder.requests.count == 1 {
                    return SearchResponsePayload(
                        itemCount: 0,
                        error: SearchErrorPayload(code: "LLM_CONVERSION_FAILED", details: "synthetic"),
                        queryConversion: SearchQueryConversionMetadataPayload(outcome: .conversionFailure),
                    )
                }
                return SearchResponsePayload(
                    itemCount: 0,
                    queryConversion: SearchQueryConversionMetadataPayload(outcome: .unchangedResult),
                )
            }
        }
        // store.exhaustivity = .off: 생성되는 request UUID보다 retry의 public visible/payload 계약을 검증한다.
        store.exhaustivity = .off

        await store.send(.submit)
        await store.receive(\.internal.searchResponse)
        XCTAssertEqual(store.state.text, firstRawQuery)

        await store.send(.setText(retryRawQuery))
        await store.send(.submit)
        await store.receive(\.internal.searchResponse)

        XCTAssertEqual(
            recorder.requests.map(\.query),
            ["VOY589_SYNTHETIC_FIRST.PDF", "VOY589_SYNTHETIC_RETRY.PDF"],
        )
        XCTAssertEqual(store.state.text, "")
        XCTAssertNil(store.state.activeSearchRequestID)
        XCTAssertFalse(store.state.isLoadingSearch)

        await store.send(.internal(.clearTransientFeedback))
        await store.finish()
    }

    // MARK: - RCL-004-type_collection_filter_query

    /// RCL-004-type_collection_filter_query: query field 입력은 현재 text 상태와 feedback 표시를 갱신함
    /// 사용자가 query를 입력하면 이전 transient feedback을 지우고 입력 text를 reducer 상태에 반영하는지 검증한다.
    /// - 검증 내용: text state 갱신, 기존 feedback clear 확인
    /// - 사전 조건: 이전 query failure feedback이 표시된 상태에서 새 query text를 입력함
    /// - 기대 결과: 입력 문장이 text에 반영되고 이전 feedback은 사라짐
    func testTypeCollectionFilterQuery_withExistingFeedback_updatesTextAndClearsFeedback() {
        var state = ComposerState()
        state.text = "old query"
        state.transientFeedback = ComposerTransientFeedback(id: UUID(), kind: .error, message: "previous failure")
        let recoveryRequestID = UUID()
        state.captureQueryRecovery(rawText: "submitted query", requestID: recoveryRequestID)

        _ = ComposerFeature().reduce(into: &state, action: .setText("find reports"))

        XCTAssertEqual(state.text, "find reports")
        XCTAssertEqual(state.inputRevision, 1)
        XCTAssertNil(state.transientFeedback)
        XCTAssertEqual(state.queryRecoveryContext?.stage, .search(recoveryRequestID))

        _ = ComposerFeature().reduce(into: &state, action: .setText("find reports"))
        XCTAssertEqual(state.inputRevision, 2)

        _ = ComposerFeature().reduce(into: &state, action: .setText(""))
        XCTAssertEqual(state.inputRevision, 3)

        _ = ComposerFeature().reduce(into: &state, action: .setText(""))
        XCTAssertEqual(state.inputRevision, 4)
        XCTAssertEqual(state.text, "")
        XCTAssertNotNil(state.queryRecoveryContext)
    }

    // MARK: - RCL-004-generate_filter_changes_from_query

    /// RCL-004-generate_filter_changes_from_query: 변환 성공 response는 generated filter 적용 대기 상태로 전환됨
    /// query 변환이 generated change set을 반환하면 filter 적용 요청 상태가 만들어지는지 검증한다.
    /// - 검증 내용: search loading 해제, filters in-flight 시작, generated 조건 response 보존 확인
    /// - 사전 조건: active search request가 있고 변환 response가 `generatedChangeSet` 조건을 반환함
    /// - 기대 결과: query phase가 chips-applied-pending-list로 바뀌고 filters request가 생성됨
    func testGenerateFilterChangesFromQuery_withGeneratedCondition_startsFilterApplication() {
        let requestID = UUID()
        var state = makeSearchLoadingState(activeRequestID: requestID)
        state.captureQueryRecovery(rawText: "VOY589_SYNTHETIC", requestID: requestID)
        let response = SearchResponsePayload(
            itemCount: 0,
            appliedFilters: AppliedFiltersPayload(
                scopes: ["/VoyagerFixtures/Documents"],
                conditions: [
                    SearchConditionPayload(propertyKey: "kind", operator: "eq", value: .string("pdf")),
                ],
            ),
            queryConversion: SearchQueryConversionMetadataPayload(outcome: .generatedChangeSet),
        )

        withDependencies {
            $0.registryClient = makeRegistryClient()
            $0.uuid = .constant(UUID())
        } operation: {
            let recoveryBeforeStaleResponse = state.queryRecoveryContext
            _ = ComposerFeature().reduce(into: &state, action: .searchResponse(UUID(), .success(response)))
            XCTAssertEqual(state.activeSearchRequestID, requestID)
            XCTAssertEqual(state.queryRecoveryContext, recoveryBeforeStaleResponse)
            XCTAssertTrue(state.isLoadingSearch)

            _ = ComposerFeature().reduce(into: &state, action: .searchResponse(requestID, .success(response)))
        }

        XCTAssertFalse(state.isLoadingSearch)
        XCTAssertTrue(state.isLoadingFilters)
        XCTAssertTrue(state.isFilteringInFlight)
        XCTAssertNil(state.activeSearchRequestID)
        let filtersRequestID = state.activeFiltersRequestID
        XCTAssertNotNil(filtersRequestID)
        XCTAssertEqual(
            state.queryRecoveryContext?.stage,
            filtersRequestID.map(ComposerQueryRecoveryContext.Stage.filters),
        )
        XCTAssertEqual(state.queryRecoveryContext?.capturedInputRevision, 0)
        XCTAssertEqual(state.queryRenderPhase, .chipsAppliedPendingList)
        XCTAssertNil(state.transientFeedback)
    }

    // MARK: - RCL-004-apply_generated_filter_changes

    /// RCL-004-apply_generated_filter_changes: generated scope-only 변경은 filter 실행 요청으로 이어지지 않음
    /// query 변환 결과가 condition 없이 scope만 변경할 때 검색 실행을 시작하지 않는지 검증한다.
    /// - 검증 내용: 변경된 scope response 수락, filters in-flight 미시작, active filters request 정리 확인
    /// - 사전 조건: active search request가 있고 generated change set이 condition 없는 새 scope를 반환함
    /// - 기대 결과: scope 변경은 반영되지만 즉시 execution request는 준비되지 않음
    func testApplyGeneratedFilterChanges_withGeneratedScopeOnly_doesNotStartFilterExecution() {
        let requestID = UUID()
        var state = makeSearchLoadingState(activeRequestID: requestID)
        state.captureQueryRecovery(rawText: "VOY589_SYNTHETIC", requestID: requestID)
        let response = SearchResponsePayload(
            itemCount: 0,
            appliedFilters: AppliedFiltersPayload(
                scopes: ["/VoyagerFixtures/Documents", "/VoyagerFixtures/Notes"],
                conditions: [],
            ),
            queryConversion: SearchQueryConversionMetadataPayload(outcome: .generatedChangeSet),
        )

        withDependencies {
            $0.registryClient = makeRegistryClient()
        } operation: {
            _ = ComposerFeature().reduce(into: &state, action: .searchResponse(requestID, .success(response)))
        }

        XCTAssertFalse(state.isLoadingSearch)
        XCTAssertFalse(state.isLoadingFilters)
        XCTAssertFalse(state.isFilteringInFlight)
        XCTAssertEqual(state.queryRenderPhase, .idle)
        XCTAssertNil(state.activeFiltersRequestID)
        XCTAssertEqual(
            state.lastSearchResponse?.appliedFilters?.scopes,
            ["/VoyagerFixtures/Documents", "/VoyagerFixtures/Notes"],
        )
        XCTAssertNil(state.queryRecoveryContext)
    }

    /// RCL-004-apply_generated_filter_changes: generated filter 성공은 query 복원 context를 폐기함
    /// 변환 단계에서 execution 단계로 retarget된 context가 최종 성공 뒤 남지 않는지 검증한다.
    /// - 검증 내용: active filters response success 수락 뒤 internal recovery context disposal
    /// - 사전 조건: generated filter request ID를 소유한 query recovery context가 있음
    /// - 기대 결과: filter 성공 상태를 반영하고 이전 제출 원문 context는 제거됨
    func testApplyGeneratedFilterChanges_whenExecutionSucceeds_discardsQueryRecovery() {
        let requestID = UUID()
        var state = makeFiltersLoadingState(activeRequestID: requestID)
        state.queryRecoveryContext = ComposerQueryRecoveryContext(
            rawText: "VOY589_SYNTHETIC",
            capturedInputRevision: state.inputRevision,
            stage: .filters(requestID),
        )

        withDependencies {
            $0.registryClient = makeRegistryClient()
        } operation: {
            _ = ComposerFeature().reduce(
                into: &state,
                action: .filtersResponse(requestID, .success(SearchResponsePayload(itemCount: 1))),
            )
        }

        XCTAssertNil(state.queryRecoveryContext)
        XCTAssertNil(state.activeFiltersRequestID)
        XCTAssertFalse(state.isLoadingFilters)
    }

    /// RCL-004-apply_generated_filter_changes: filter 성공 handoff는 visible draft가 아닌 제출 query를 사용함
    /// A 처리 중 B를 입력해도 FileManager collection context에는 A가 전달되는지 검증한다.
    /// - 검증 내용: query-owned filter response success 전 request-bound pending query projection
    /// - 사전 조건: A의 generated filter request 중 B가 visible draft와 pending query를 대체함
    /// - 기대 결과: visible B는 유지되고 handoff query만 제출된 A로 복원됨
    func testApplyGeneratedFilterChanges_whenVisibleDraftChanges_usesSubmittedQueryForHandoff() {
        let submittedQuery = "VOY589_SYNTHETIC_SUBMITTED"
        let visibleDraft = "VOY589_SYNTHETIC_DRAFT"
        var state = makeGeneratedFilterStageState(rawText: submittedQuery)
        guard let requestID = state.activeFiltersRequestID else {
            return XCTFail("generated response must create an active filters request")
        }

        _ = ComposerFeature().reduce(into: &state, action: .setText(visibleDraft))
        state.pendingSearchQuery = visibleDraft

        withDependencies {
            $0.registryClient = makeRegistryClient()
            $0.uuid = .constant(UUID())
        } operation: {
            _ = ComposerFeature().reduce(
                into: &state,
                action: .filtersResponse(requestID, .success(SearchResponsePayload(itemCount: 1))),
            )
        }

        XCTAssertEqual(state.text, visibleDraft)
        XCTAssertEqual(state.pendingSearchQuery, submittedQuery)
    }

    /// RCL-004-apply_generated_filter_changes: manual apply는 query 복원 context보다 우선함
    /// 사용자가 명시적으로 현재 filter를 적용하면 이전 자연어 submit context가 폐기되는지 검증한다.
    /// - 검증 내용: applyFilters action의 internal recovery context supersession
    /// - 사전 조건: active search 단계의 synthetic recovery context와 condition 없는 filter가 있음
    /// - 기대 결과: manual apply가 context를 제거하고 이전 제출 원문은 복원 대상에서 제외됨
    func testApplyGeneratedFilterChanges_whenManualApplySupersedes_discardsQueryRecovery() {
        let requestID = UUID()
        var state = makeSearchLoadingState(activeRequestID: requestID)
        state.captureQueryRecovery(rawText: "VOY589_SYNTHETIC", requestID: requestID)

        _ = ComposerFeature().reduce(into: &state, action: .applyFilters)

        XCTAssertNil(state.queryRecoveryContext)
        XCTAssertNil(state.activeSearchRequestID)
    }
}

extension RCL004ComposeCollectionFilterTests {
    // MARK: - RCL-004-show_query_conversion_failure_feedback

    /// RCL-004-show_query_conversion_failure_feedback: query 변환 실패는 conversion feedback으로 표시됨
    /// search response failure가 execution failure와 다른 feedback copy를 갖는지 검증한다.
    /// - 검증 내용: loading 해제, failed phase, transient feedback kind/message 확인
    /// - 사전 조건: active search request가 있고 변환 client가 `LLM_CONVERSION_FAILED` 오류를 반환함
    /// - 기대 결과: conversion failure feedback copy가 표시되고 active request가 정리됨
    func testShowQueryConversionFailureFeedback_withActiveSearchFailure_marksConversionFailure() {
        let requestID = UUID()
        var state = makeSearchLoadingState(activeRequestID: requestID)

        _ = ComposerFeature().reduce(
            into: &state,
            action: .searchResponse(requestID, .failure(MockLocalizedError("LLM_CONVERSION_FAILED: timeout"))),
        )

        XCTAssertFalse(state.isLoadingSearch)
        XCTAssertFalse(state.isLoadingFilters)
        XCTAssertNil(state.activeSearchRequestID)
        XCTAssertEqual(state.queryRenderPhase, .failed)
        XCTAssertEqual(state.transientFeedback?.kind, .error)
        XCTAssertEqual(state.transientFeedback?.message, ComposerQueryFeedbackPolicy.conversionFailureMessage)
    }

    /// RCL-004-show_query_conversion_failure_feedback: response error payload도 conversion feedback으로 표시됨
    /// search response success 내부의 error payload가 throw failure와 같은 conversion 실패 copy를 갖는지 검증한다.
    /// - 검증 내용: loading 해제, failed phase, transient feedback kind/message 확인
    /// - 사전 조건: active search request가 있고 response payload에 `LLM_CONVERSION_FAILED` 오류가 포함됨
    /// - 기대 결과: conversion failure feedback copy가 표시되고 active request가 정리됨
    func testShowQueryConversionFailureFeedback_withResponseErrorPayload_marksConversionFailure() {
        let requestID = UUID()
        var state = makeSearchLoadingState(activeRequestID: requestID)
        let response = SearchResponsePayload(
            itemCount: 0,
            error: SearchErrorPayload(code: "LLM_CONVERSION_FAILED", details: "provider timeout"),
            queryConversion: SearchQueryConversionMetadataPayload(outcome: .conversionFailure),
        )

        _ = ComposerFeature().reduce(into: &state, action: .searchResponse(requestID, .success(response)))

        XCTAssertFalse(state.isLoadingSearch)
        XCTAssertFalse(state.isLoadingFilters)
        XCTAssertNil(state.activeSearchRequestID)
        XCTAssertEqual(state.queryRenderPhase, .failed)
        XCTAssertEqual(state.transientFeedback?.kind, .error)
        XCTAssertEqual(state.transientFeedback?.message, ComposerQueryFeedbackPolicy.conversionFailureMessage)
    }

    /// RCL-004-show_query_conversion_failure_feedback: response error payload는 제출 원문을 그대로 복원함
    /// success envelope 안의 conversion error도 throw failure와 동일한 visible recovery를 제공하는지 검증한다.
    /// - 검증 내용: active response-error 처리 뒤 공백/Unicode 원문 복원과 search terminal state
    /// - 사전 조건: raw synthetic query를 submit한 active search가 conversion error payload를 반환함
    /// - 기대 결과: 입력창에 exact raw query가 복원되고 active search는 정리됨
    func testShowQueryConversionFailureFeedback_withResponseErrorPayload_restoresExactRawInput() {
        let rawQuery = " \tVOY589_SYNTHETIC_청구서.PDF  \n"
        var state = ComposerState()
        state.text = rawQuery
        _ = ComposerFeature().reduce(into: &state, action: .submit)
        guard let requestID = state.activeSearchRequestID else {
            return XCTFail("submit must create an active search request")
        }

        _ = ComposerFeature().reduce(
            into: &state,
            action: .searchResponse(requestID, .success(makeConversionErrorResponse())),
        )

        XCTAssertEqual(state.text, rawQuery)
        XCTAssertEqual(state.text.unicodeScalars.count, rawQuery.unicodeScalars.count)
        XCTAssertNil(state.activeSearchRequestID)
        XCTAssertFalse(state.isLoadingSearch)
        XCTAssertEqual(state.transientFeedback?.message, ComposerQueryFeedbackPolicy.conversionFailureMessage)
        XCTAssertNil(state.queryRecoveryContext)
    }

    /// RCL-004-show_query_conversion_failure_feedback: 실패보다 늦은 모든 setText intent가 복원보다 우선함
    /// 새 non-empty 입력, submit-clear와 같은 explicit empty, type-then-delete empty를 각각 검증한다.
    /// - 검증 내용: matching active failure 뒤 최신 non-empty/empty visible text 보존
    /// - 사전 조건: 각 query submit 뒤 response 도착 전에 서로 다른 setText intent가 수신됨
    /// - 기대 결과: 이전 제출 원문이 최신 사용자 입력을 덮어쓰지 않음
    func testShowQueryConversionFailureFeedback_afterNewerTextIntents_preservesLatestVisibleInput() {
        var nonEmptyState = ComposerState()
        nonEmptyState.text = "VOY589_SYNTHETIC_A"
        _ = ComposerFeature().reduce(into: &nonEmptyState, action: .submit)
        guard let nonEmptyRequestID = nonEmptyState.activeSearchRequestID else {
            return XCTFail("submit must create an active search request")
        }
        _ = ComposerFeature().reduce(into: &nonEmptyState, action: .setText("VOY589_SYNTHETIC_NEW"))
        _ = ComposerFeature().reduce(
            into: &nonEmptyState,
            action: .searchResponse(nonEmptyRequestID, .failure(MockLocalizedError("synthetic"))),
        )
        XCTAssertEqual(nonEmptyState.text, "VOY589_SYNTHETIC_NEW")
        XCTAssertNil(nonEmptyState.queryRecoveryContext)

        var explicitEmptyState = ComposerState()
        explicitEmptyState.text = "VOY589_SYNTHETIC_B"
        _ = ComposerFeature().reduce(into: &explicitEmptyState, action: .submit)
        guard let explicitEmptyRequestID = explicitEmptyState.activeSearchRequestID else {
            return XCTFail("submit must create an active search request")
        }
        XCTAssertEqual(explicitEmptyState.text, "")
        _ = ComposerFeature().reduce(into: &explicitEmptyState, action: .setText(""))
        _ = ComposerFeature().reduce(
            into: &explicitEmptyState,
            action: .searchResponse(explicitEmptyRequestID, .success(makeConversionErrorResponse())),
        )
        XCTAssertEqual(explicitEmptyState.text, "")
        XCTAssertNil(explicitEmptyState.queryRecoveryContext)

        var deletedState = ComposerState()
        deletedState.text = "VOY589_SYNTHETIC_C"
        _ = ComposerFeature().reduce(into: &deletedState, action: .submit)
        guard let deletedRequestID = deletedState.activeSearchRequestID else {
            return XCTFail("submit must create an active search request")
        }
        _ = ComposerFeature().reduce(into: &deletedState, action: .setText("VOY589_SYNTHETIC_TYPED"))
        _ = ComposerFeature().reduce(into: &deletedState, action: .setText(""))
        _ = ComposerFeature().reduce(
            into: &deletedState,
            action: .searchResponse(deletedRequestID, .failure(MockLocalizedError("synthetic"))),
        )
        XCTAssertEqual(deletedState.text, "")
        XCTAssertNil(deletedState.queryRecoveryContext)
    }

    /// RCL-004-show_query_conversion_failure_feedback: A filter를 대체한 B 실패는 stale filter lock을 남기지 않음
    /// generated filter 단계의 A를 B submit이 대체하고 B가 실패한 뒤 늦은 A 응답이 도착하는 race를 검증한다.
    /// - 검증 내용: 즉시 filter lifecycle 정리, B failure terminal state, late A response full no-op
    /// - 사전 조건: A가 filter stage에 진입한 뒤 B가 새 active search request로 제출됨
    /// - 기대 결과: B 실패 뒤 B 원문만 복원되고 Composer가 stale filter Stop 없이 failed 상태가 됨
    func testShowQueryConversionFailureFeedback_afterAtoBResubmit_ignoresLateASearchAndFilterResponses() {
        let queryB = "VOY589_SYNTHETIC_B"
        var state = makeGeneratedFilterStageState(rawText: "VOY589_SYNTHETIC_A")
        guard
            let searchRequestA = state.lastAcceptedSearchRequestID,
            let filtersRequestA = state.activeFiltersRequestID
        else {
            return XCTFail("generated response A must establish search and filter ownership")
        }

        _ = ComposerFeature().reduce(into: &state, action: .setText(queryB))
        _ = ComposerFeature().reduce(into: &state, action: .submit)
        XCTAssertTrue(state.scopeEditor.selection.isRootOnly)
        XCTAssertTrue(state.conditions.isEmpty)
        guard let searchRequestB = state.activeSearchRequestID else {
            return XCTFail("submit B must create an active search request")
        }
        XCTAssertFalse(state.isLoadingFilters)
        XCTAssertFalse(state.isFilteringInFlight)
        XCTAssertNil(state.activeFiltersRequestID)
        XCTAssertNil(state.lastAcceptedFiltersRequestID)
        XCTAssertNil(state.activeFiltersMetricSource)
        XCTAssertNil(state.filtersStartedAt)

        _ = ComposerFeature().reduce(
            into: &state,
            action: .searchResponse(
                searchRequestB,
                .failure(MockLocalizedError("LLM_CONVERSION_FAILED: synthetic B failure")),
            ),
        )
        XCTAssertEqual(state.text, queryB)
        XCTAssertFalse(state.isLoadingSearch)
        XCTAssertFalse(state.isLoadingFilters)
        XCTAssertFalse(state.isFilteringInFlight)
        XCTAssertNil(state.activeSearchRequestID)
        XCTAssertNil(state.activeFiltersRequestID)
        XCTAssertEqual(state.queryRenderPhase, .failed)
        XCTAssertEqual(state.transientFeedback?.message, ComposerQueryFeedbackPolicy.conversionFailureMessage)
        XCTAssertNil(state.queryRecoveryContext)
        let stateAfterBFailure = state

        _ = ComposerFeature().reduce(
            into: &state,
            action: .searchResponse(searchRequestA, .failure(MockLocalizedError("stale synthetic"))),
        )
        _ = ComposerFeature().reduce(
            into: &state,
            action: .filtersResponse(filtersRequestA, .failure(MockLocalizedError("stale synthetic"))),
        )

        XCTAssertEqual(state, stateAfterBFailure)
    }

    /// RCL-004-show_query_conversion_failure_feedback: A filter를 대체한 B Stop은 Composer를 완전히 idle로 만듦
    /// generated filter 단계의 A를 B submit이 대체한 직후 사용자가 B 변환을 중단하는 경로를 검증한다.
    /// - 검증 내용: superseded filter lifecycle 정리, B 원문 복원, Stop 뒤 processing state 해제
    /// - 사전 조건: A가 filter stage에 진입한 뒤 B가 새 active search request로 제출됨
    /// - 기대 결과: B Stop 뒤 B 원문이 복원되고 search/filter ownership과 Stop 상태가 모두 사라짐
    func testShowQueryConversionFailureFeedback_afterAtoBResubmitAndStop_leavesComposerIdle() {
        let queryB = "VOY589_SYNTHETIC_B_STOP"
        var state = makeGeneratedFilterStageState(rawText: "VOY589_SYNTHETIC_A_STOP")
        guard let filtersRequestA = state.activeFiltersRequestID else {
            return XCTFail("generated response A must create an active filters request")
        }

        _ = ComposerFeature().reduce(into: &state, action: .setText(queryB))
        _ = ComposerFeature().reduce(into: &state, action: .submit)
        XCTAssertFalse(state.isLoadingFilters)
        XCTAssertFalse(state.isFilteringInFlight)
        XCTAssertNil(state.activeFiltersRequestID)
        XCTAssertNil(state.activeFiltersMetricSource)
        XCTAssertNil(state.filtersStartedAt)

        _ = ComposerFeature().reduce(into: &state, action: .cancelSearch)

        XCTAssertEqual(state.text, queryB)
        XCTAssertNil(state.transientFeedback)
        XCTAssertFalse(state.isLoadingSearch)
        XCTAssertFalse(state.isLoadingFilters)
        XCTAssertFalse(state.isFilteringInFlight)
        XCTAssertNil(state.activeSearchRequestID)
        XCTAssertNil(state.activeFiltersRequestID)
        XCTAssertEqual(state.queryRenderPhase, .idle)
        XCTAssertNil(state.queryRecoveryContext)
        let stateAfterBStop = state

        _ = ComposerFeature().reduce(
            into: &state,
            action: .filtersResponse(filtersRequestA, .failure(MockLocalizedError("stale synthetic"))),
        )
        XCTAssertEqual(state, stateAfterBStop)
    }

    /// RCL-004-show_query_conversion_failure_feedback: explicit search Stop은 실패 feedback 없이 원문을 복원함
    /// 사용자가 변환 중 Stop을 선택하면 수정/재시도를 위해 제출 원문이 돌아오는지 검증한다.
    /// - 검증 내용: matching active search 취소의 exact visible restoration과 feedback 부재
    /// - 사전 조건: raw synthetic query submit 이후 search request가 active임
    /// - 기대 결과: Stop 뒤 원문이 복원되고 search loading/request가 정리되며 새 failure feedback이 없음
    func testShowQueryConversionFailureFeedback_whenSearchIsStopped_restoresExactRawInputWithoutFailureFeedback() {
        let rawQuery = "  VOY589_SYNTHETIC_STOP_SEARCH.PDF \n"
        var state = ComposerState()
        state.text = rawQuery
        _ = ComposerFeature().reduce(into: &state, action: .submit)

        _ = ComposerFeature().reduce(into: &state, action: .cancelSearch)

        XCTAssertEqual(state.text, rawQuery)
        XCTAssertNil(state.transientFeedback)
        XCTAssertNil(state.activeSearchRequestID)
        XCTAssertFalse(state.isLoadingSearch)
        XCTAssertEqual(state.queryRenderPhase, .idle)
        XCTAssertNil(state.queryRecoveryContext)
    }

    // MARK: - RCL-004-show_query_execution_failure_feedback

    /// RCL-004-show_query_execution_failure_feedback: filter 실행 실패는 execution feedback으로 표시됨
    /// filter response failure가 conversion failure와 다른 feedback copy를 갖는지 검증한다.
    /// - 검증 내용: filter in-flight 해제, idle phase reset, transient feedback kind/message 확인
    /// - 사전 조건: active filters request가 있고 helper 실행이 `HELPER_UNAVAILABLE` 오류를 반환함
    /// - 기대 결과: execution failure feedback copy가 표시되고 active request가 정리됨
    func testShowQueryExecutionFailureFeedback_withActiveFilterFailure_marksExecutionFailure() {
        let requestID = UUID()
        var state = makeFiltersLoadingState(activeRequestID: requestID)

        _ = ComposerFeature().reduce(
            into: &state,
            action: .filtersResponse(requestID, .failure(MockLocalizedError("HELPER_UNAVAILABLE: xpc disconnected"))),
        )

        XCTAssertFalse(state.isLoadingSearch)
        XCTAssertFalse(state.isLoadingFilters)
        XCTAssertFalse(state.isFilteringInFlight)
        XCTAssertNil(state.activeFiltersRequestID)
        XCTAssertEqual(state.queryRenderPhase, .idle)
        XCTAssertEqual(state.transientFeedback?.kind, .error)
        XCTAssertEqual(state.transientFeedback?.message, ComposerQueryFeedbackPolicy.executionFailureMessage)
    }

    /// RCL-004-show_query_execution_failure_feedback: generated filter 실패는 제출 원문을 그대로 복원함
    /// accepted conversion이 filter stage로 넘어간 뒤 execution failure가 발생하는 terminal recovery를 검증한다.
    /// - 검증 내용: generated stage handoff, exact visible restoration, execution feedback과 spinner reset
    /// - 사전 조건: raw synthetic query가 generated condition으로 변환되어 query-owned filter request가 active임
    /// - 기대 결과: filter failure 뒤 원문이 복원되고 execution state가 정리됨
    func testShowQueryExecutionFailureFeedback_withGeneratedFilterFailure_restoresExactRawInput() {
        let rawQuery = " \tVOY589_SYNTHETIC_EXECUTION.PDF  \n"
        var state = ComposerState()
        state.text = rawQuery
        _ = ComposerFeature().reduce(into: &state, action: .submit)
        guard let searchRequestID = state.activeSearchRequestID else {
            return XCTFail("submit must create an active search request")
        }
        withDependencies {
            $0.registryClient = makeRegistryClient()
            $0.uuid = .constant(UUID())
        } operation: {
            _ = ComposerFeature().reduce(
                into: &state,
                action: .searchResponse(searchRequestID, .success(makeGeneratedConditionResponse())),
            )
        }
        guard let filtersRequestID = state.activeFiltersRequestID else {
            return XCTFail("generated response must create an active filters request")
        }

        _ = ComposerFeature().reduce(
            into: &state,
            action: .filtersResponse(filtersRequestID, .failure(MockLocalizedError("HELPER_UNAVAILABLE: synthetic"))),
        )

        XCTAssertEqual(state.text, rawQuery)
        XCTAssertEqual(state.text.unicodeScalars.count, rawQuery.unicodeScalars.count)
        XCTAssertFalse(state.isLoadingFilters)
        XCTAssertFalse(state.isFilteringInFlight)
        XCTAssertNil(state.activeFiltersRequestID)
        XCTAssertEqual(state.queryRenderPhase, .idle)
        XCTAssertEqual(state.transientFeedback?.message, ComposerQueryFeedbackPolicy.executionFailureMessage)
        XCTAssertNil(state.queryRecoveryContext)
    }

    /// RCL-004-show_query_execution_failure_feedback: generated multi-scope failure는 제출 baseline으로 복원함
    /// rollback 시 일반 applied-filter의 local multi-scope 보존 정책이 baseline 복원을 막지 않는지 검증한다.
    /// - 검증 내용: generated multi-scope 적용 후 execution failure의 direct scope rollback
    /// - 사전 조건: 제출 전 root-only state에서 두 scope가 생성되고 filter execution이 실패함
    /// - 기대 결과: generated scope/condition이 모두 제출 전 baseline으로 돌아감
    func testShowQueryExecutionFailureFeedback_withGeneratedMultiScopeFailure_restoresSubmittedBaseline() {
        var state = makeGeneratedFilterStageState(
            rawText: "VOY589_SYNTHETIC_MULTI_SCOPE_FAILURE",
            response: makeGeneratedConditionResponse(
                scopes: ["/VoyagerFixtures/Documents", "/VoyagerFixtures/Notes"],
            ),
        )
        guard let requestID = state.activeFiltersRequestID else {
            return XCTFail("generated response must create an active filters request")
        }
        XCTAssertEqual(state.scopeEditor.selection.explicitBases.count, 2)

        _ = ComposerFeature().reduce(
            into: &state,
            action: .filtersResponse(requestID, .failure(MockLocalizedError("synthetic"))),
        )

        XCTAssertTrue(state.scopeEditor.selection.isRootOnly)
        XCTAssertTrue(state.conditions.isEmpty)
    }

    /// RCL-004-show_query_execution_failure_feedback: execution failure 복원문은 즉시 재제출할 수 있음
    /// generated filter failure 직후 별도 edit 없이 같은 원문을 retry하는 public lifecycle을 검증한다.
    /// - 검증 내용: 원문 복원, 새 search request ID, retry 성공 뒤 terminal cleanup
    /// - 사전 조건: 첫 query가 filter execution failure로 종료되어 visible input에 복원됨
    /// - 기대 결과: immediate resubmit이 이전 ID와 다른 search를 만들고 accepted success로 정리됨
    func testShowQueryExecutionFailureFeedback_afterImmediateResubmit_startsNewSuccessfulRetry() {
        let rawQuery = "  VOY589_SYNTHETIC_EXECUTION_RETRY.PDF \n"
        var state = ComposerState()
        state.text = rawQuery
        _ = ComposerFeature().reduce(into: &state, action: .submit)
        guard let firstSearchRequestID = state.activeSearchRequestID else {
            return XCTFail("first submit must create an active search request")
        }
        withDependencies {
            $0.registryClient = makeRegistryClient()
            $0.uuid = .constant(UUID())
        } operation: {
            _ = ComposerFeature().reduce(
                into: &state,
                action: .searchResponse(firstSearchRequestID, .success(makeGeneratedConditionResponse())),
            )
        }
        guard let firstFiltersRequestID = state.activeFiltersRequestID else {
            return XCTFail("generated response must create an active filters request")
        }
        _ = ComposerFeature().reduce(
            into: &state,
            action: .filtersResponse(firstFiltersRequestID, .failure(MockLocalizedError("synthetic"))),
        )
        XCTAssertEqual(state.text, rawQuery)
        XCTAssertTrue(state.scopeEditor.selection.isRootOnly)
        XCTAssertTrue(state.conditions.isEmpty)

        _ = ComposerFeature().reduce(into: &state, action: .submit)
        guard let retrySearchRequestID = state.activeSearchRequestID else {
            return XCTFail("retry submit must create an active search request")
        }
        XCTAssertNotEqual(retrySearchRequestID, firstSearchRequestID)
        XCTAssertEqual(state.text, "")
        withDependencies {
            $0.registryClient = makeRegistryClient()
            $0.uuid = .constant(UUID())
        } operation: {
            _ = ComposerFeature().reduce(
                into: &state,
                action: .searchResponse(retrySearchRequestID, .success(makeGeneratedConditionResponse())),
            )
        }

        guard let retryFiltersRequestID = state.activeFiltersRequestID else {
            return XCTFail("retry must re-execute generated filters")
        }
        XCTAssertTrue(state.isFilteringInFlight)

        withDependencies {
            $0.registryClient = makeRegistryClient()
            $0.uuid = .constant(UUID())
        } operation: {
            _ = ComposerFeature().reduce(
                into: &state,
                action: .filtersResponse(retryFiltersRequestID, .success(SearchResponsePayload(itemCount: 0))),
            )
        }

        XCTAssertNil(state.activeSearchRequestID)
        XCTAssertFalse(state.isLoadingSearch)
        XCTAssertEqual(state.text, "")
    }

    /// RCL-004-show_query_execution_failure_feedback: query-owned filter Stop은 실패 feedback 없이 원문을 복원함
    /// 변환으로 시작된 filter execution을 사용자가 중단할 때 submit 문장을 다시 편집할 수 있는지 검증한다.
    /// - 검증 내용: post-query filter cancellation의 exact restoration과 feedback 부재
    /// - 사전 조건: raw synthetic query가 generated condition으로 변환되어 filter request가 active임
    /// - 기대 결과: Stop 뒤 원문이 복원되고 filter ownership/spinner가 정리되며 failure feedback은 없음
    func testShowQueryExecutionFailureFeedback_whenQueryOwnedFiltersAreStopped_restoresExactRawInputWithoutFailureFeedback() {
        let rawQuery = "  VOY589_SYNTHETIC_STOP_FILTERS.PDF \n"
        var state = ComposerState()
        state.text = rawQuery
        _ = ComposerFeature().reduce(into: &state, action: .submit)
        guard let searchRequestID = state.activeSearchRequestID else {
            return XCTFail("submit must create an active search request")
        }
        withDependencies {
            $0.registryClient = makeRegistryClient()
            $0.uuid = .constant(UUID())
        } operation: {
            _ = ComposerFeature().reduce(
                into: &state,
                action: .searchResponse(searchRequestID, .success(makeGeneratedConditionResponse())),
            )
        }

        _ = ComposerFeature().reduce(into: &state, action: .cancelFilters)

        XCTAssertEqual(state.text, rawQuery)
        XCTAssertNil(state.transientFeedback)
        XCTAssertNil(state.activeFiltersRequestID)
        XCTAssertFalse(state.isLoadingFilters)
        XCTAssertFalse(state.isFilteringInFlight)
        XCTAssertTrue(state.scopeEditor.selection.isRootOnly)
        XCTAssertTrue(state.conditions.isEmpty)
        XCTAssertEqual(state.queryRenderPhase, .idle)
        XCTAssertNil(state.queryRecoveryContext)
    }

    /// RCL-004-show_query_execution_failure_feedback: collection cleanup은 실행 중 작업만 정리함
    /// collection session 종료 시 query/filter/feedback process 상태를 비우고 작성 중인 filter 정의는 보존하는지 검증한다.
    /// - 검증 내용: search/filter request와 timing, pending query, transient feedback 정리 및 durable draft 보존
    /// - 사전 조건: search와 filter process 상태가 남아 있고 사용자가 작성한 query/scope/condition이 존재함
    /// - 기대 결과: process 상태는 idle로 돌아가고 사용자 작성 filter 정의는 유지됨
    func testCleanupCollectionWork_withInFlightProcessState_preservesDurableDraft() {
        let searchID = UUID()
        let filtersID = UUID()
        var state = ComposerState()
        state.text = "keep this query"
        state.scopes = ["/VoyagerFixtures/Documents"]
        state.conditionEditors = [
            .init(
                id: UUID(),
                condition: .init(
                    property: .init(
                        key: "kind",
                        label: "Kind",
                        type: .string,
                        unitContract: nil,
                        operatorOptions: [],
                    ),
                    operation: nil,
                    values: nil,
                    availability: .available,
                    opaqueSource: nil,
                ),
            ),
        ]
        state.isLoadingSearch = true
        state.isLoadingFilters = true
        state.isFilteringInFlight = true
        state.activeSearchRequestID = searchID
        state.activeFiltersRequestID = filtersID
        state.lastAcceptedSearchRequestID = searchID
        state.lastAcceptedFiltersRequestID = filtersID
        state.pendingSearchQuery = "pending query"
        state.queryRenderPhase = .searching
        state.searchStartedAt = Date(timeIntervalSince1970: 1_700_000_000)
        state.filtersStartedAt = Date(timeIntervalSince1970: 1_700_000_001)
        state.activeFiltersMetricSource = "manual"
        state.transientFeedback = ComposerTransientFeedback(id: UUID(), kind: .error, message: "failure")

        _ = ComposerFeature().reduce(into: &state, action: .internal(.cleanupCollectionWork))

        XCTAssertFalse(state.isLoadingSearch)
        XCTAssertFalse(state.isLoadingFilters)
        XCTAssertFalse(state.isFilteringInFlight)
        XCTAssertNil(state.activeSearchRequestID)
        XCTAssertNil(state.activeFiltersRequestID)
        XCTAssertNil(state.lastAcceptedSearchRequestID)
        XCTAssertNil(state.lastAcceptedFiltersRequestID)
        XCTAssertNil(state.pendingSearchQuery)
        XCTAssertNil(state.searchStartedAt)
        XCTAssertNil(state.filtersStartedAt)
        XCTAssertNil(state.activeFiltersMetricSource)
        XCTAssertNil(state.transientFeedback)
        XCTAssertEqual(state.queryRenderPhase, .idle)
        XCTAssertEqual(state.text, "keep this query")
        XCTAssertEqual(state.scopes, ["/VoyagerFixtures/Documents"])
        XCTAssertEqual(state.conditions.map(\.property.key), ["kind"])
    }

    /// RCL-004-apply_generated_filter_changes: collection cleanup은 활성 apply terminal을 한 번 기록함
    /// cleanup 이후 반복 cleanup과 늦은 response가 중복 terminal event를 만들지 않는지 검증한다.
    /// - 검증 내용: cancelled apply event 1건, 기존 operation ID와 duration, 활성 요청 해제
    /// - 사전 조건: 시작 시각과 request ID가 있는 활성 filter apply
    /// - 기대 결과: 첫 cleanup만 terminal을 기록하고 후속 cleanup/response는 무시됨
    func testCleanupCollectionWork_withActiveApply_recordsOneCancelledTerminal() throws {
        let recorder = RCL004MetricRecorder()
        let requestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000024"))
        var state = makeFiltersLoadingState(activeRequestID: requestID)

        withDependencies {
            $0.composerMetricClient = ComposerMetricClient(recordProductMetric: recorder.record)
        } operation: {
            let feature = ComposerFeature()
            _ = feature.reduce(into: &state, action: .internal(.cleanupCollectionWork))
            _ = feature.reduce(into: &state, action: .internal(.cleanupCollectionWork))
            _ = feature.reduce(
                into: &state,
                action: .internal(.filtersResponse(requestID, .success(SearchResponsePayload(itemCount: 1)))),
            )
        }

        XCTAssertEqual(recorder.calls.map(\.name), [ComposerCollectionFilterMetrics.applyResult])
        let call = try XCTUnwrap(recorder.calls.first)
        XCTAssertEqual(call.tags?["result_status"], "cancelled")
        XCTAssertEqual(call.tags?["operation_id"], requestID.uuidString.lowercased())
        XCTAssertNotNil(Int(call.tags?["duration_ms"] ?? ""))
        XCTAssertNil(state.activeFiltersRequestID)
        XCTAssertFalse(state.isFilteringInFlight)
    }

    /// RCL-004-apply_generated_filter_changes: post-query apply 재제출은 복원 후 이전 apply를 종료함
    /// 새 query의 filter snapshot 전에 query-owned generated filters를 원래 제출 filter로 복원하는지 검증한다.
    /// - 검증 내용: 이전 apply cancelled terminal 1건, 원래 filter 복원, B request/recovery 유지, 늦은 응답 무시
    /// - 사전 조건: query A가 generated condition을 만들고 post-query filter apply가 active임
    /// - 기대 결과: A apply만 종료되고 복원된 filter로 query B가 active이며 submit event는 기록되지 않음
    func testApplyGeneratedFilterChanges_resubmitDuringPostQueryApply_restoresThenTerminalizesPreviousApply() throws {
        let recorder = RCL004MetricRecorder()
        var state = makeGeneratedFilterStageState(rawText: "query A")
        let requestA = try XCTUnwrap(state.activeFiltersRequestID)
        XCTAssertEqual(state.conditions.map(\.property.key), ["kind"])
        state.text = "  query B  "

        withDependencies {
            $0.registryClient = makeRegistryClient()
            $0.uuid = .constant(UUID())
            $0.composerMetricClient = ComposerMetricClient(recordProductMetric: recorder.record)
        } operation: {
            _ = ComposerFeature().reduce(into: &state, action: .submit)
        }

        let requestB = try XCTUnwrap(state.activeSearchRequestID)
        XCTAssertNil(state.activeFiltersRequestID)
        XCTAssertTrue(state.isLoadingSearch)
        XCTAssertFalse(state.isLoadingFilters)
        XCTAssertFalse(state.isFilteringInFlight)
        XCTAssertTrue(state.conditions.isEmpty)
        XCTAssertEqual(state.submittedSearchFilters?.conditions.isEmpty, true)
        XCTAssertEqual(state.queryRecoveryContext?.rawText, "  query B  ")
        XCTAssertEqual(state.queryRecoveryContext?.stage, .search(requestB))
        XCTAssertEqual(recorder.calls.map(\.name), [ComposerCollectionFilterMetrics.applyResult])
        let call = try XCTUnwrap(recorder.calls.first)
        XCTAssertEqual(call.tags?["result_status"], "cancelled")
        XCTAssertEqual(call.tags?["operation_id"], requestA.uuidString.lowercased())

        let stateAfterResubmit = state
        let feature = ComposerFeature()
        _ = feature.reduce(
            into: &state,
            action: .filtersResponse(requestA, .failure(MockLocalizedError("synthetic"))),
        )
        _ = feature.reduce(
            into: &state,
            action: .filtersResponse(requestA, .success(SearchResponsePayload(itemCount: 1))),
        )
        XCTAssertEqual(state, stateAfterResubmit)
        XCTAssertEqual(recorder.calls.map(\.name), [ComposerCollectionFilterMetrics.applyResult])
    }

    /// RCL-004-apply_generated_filter_changes: manual apply 재제출은 현재 filter를 보존하고 이전 apply를 종료함
    /// manual filter cancellation의 no-restoration 정책 뒤 현재 filter snapshot으로 새 query를 시작하는지 검증한다.
    /// - 검증 내용: 이전 apply cancelled terminal 1건, 현재 filter 보존, B request/recovery 유지, 늦은 응답 무시
    /// - 사전 조건: 사용자가 만든 kind filter의 manual apply가 active이고 query B가 입력됨
    /// - 기대 결과: manual apply만 종료되고 현재 kind filter를 포함한 B가 active이며 submit event는 기록되지 않음
    func testApplyGeneratedFilterChanges_resubmitDuringManualApply_preservesFiltersAndTerminalizesPreviousApply(
    ) throws {
        let recorder = RCL004MetricRecorder()
        var state = makeGeneratedFilterStageState(rawText: "query A")
        let requestA = try XCTUnwrap(state.activeFiltersRequestID)
        state.activeFiltersMetricSource = ComposerCollectionFilterMetrics.sourceManualApply
        state.discardQueryRecovery()
        state.text = "query B"

        withDependencies {
            $0.registryClient = makeRegistryClient()
            $0.composerMetricClient = ComposerMetricClient(recordProductMetric: recorder.record)
        } operation: {
            _ = ComposerFeature().reduce(into: &state, action: .submit)
        }

        let requestB = try XCTUnwrap(state.activeSearchRequestID)
        XCTAssertNil(state.activeFiltersRequestID)
        XCTAssertTrue(state.isLoadingSearch)
        XCTAssertEqual(state.conditions.map(\.property.key), ["kind"])
        XCTAssertEqual(state.submittedSearchFilters?.conditions.map(\.propertyKey), ["kind"])
        XCTAssertEqual(state.queryRecoveryContext?.rawText, "query B")
        XCTAssertEqual(state.queryRecoveryContext?.stage, .search(requestB))
        XCTAssertEqual(recorder.calls.map(\.name), [ComposerCollectionFilterMetrics.applyResult])
        let call = try XCTUnwrap(recorder.calls.first)
        XCTAssertEqual(call.tags?["result_status"], "cancelled")
        XCTAssertEqual(call.tags?["operation_id"], requestA.uuidString.lowercased())

        let stateAfterResubmit = state
        let feature = ComposerFeature()
        _ = feature.reduce(
            into: &state,
            action: .filtersResponse(requestA, .failure(MockLocalizedError("synthetic"))),
        )
        _ = feature.reduce(
            into: &state,
            action: .filtersResponse(requestA, .success(SearchResponsePayload(itemCount: 1))),
        )
        XCTAssertEqual(state, stateAfterResubmit)
        XCTAssertEqual(recorder.calls.map(\.name), [ComposerCollectionFilterMetrics.applyResult])
    }

    /// RCL-004-apply_generated_filter_changes: Composer dismissal은 활성 filter/scope lifecycle을 보존함
    /// scope editor 변경을 auto-apply하는 동안 Composer를 닫아도 filter lifecycle이 유지되는지 검증한다.
    /// - 검증 내용: active filter request, loading/in-flight 상태, scope editor pending 변경 보존
    /// - 사전 조건: filter apply가 진행 중이고 scope editor에 pending rule 변경이 있음
    /// - 기대 결과: dismissal 후 active filter와 scope lifecycle이 유지되고 query만 종료됨
    func testSetPresentedDismissal_withActiveFilterAndPendingScopeChange_preservesLifecycle() {
        let filterID = UUID()
        var state = makeFiltersLoadingState(activeRequestID: filterID)
        state.isPresented = true
        state.scopeEditor.isPresented = true
        state.scopeEditor.selection = .explicit(
            bases: [ComposerScopeBase(path: "/VoyagerFixtures/Documents")],
            exceptions: [],
        )
        state.pendingSearchQuery = "find invoices"

        _ = ComposerFeature().reduce(into: &state, action: .view(.setPresented(false)))

        XCTAssertFalse(state.isPresented)
        XCTAssertTrue(state.isLoadingFilters)
        XCTAssertTrue(state.isFilteringInFlight)
        XCTAssertEqual(state.activeFiltersRequestID, filterID)
        XCTAssertTrue(state.scopeEditor.isPresented)
        XCTAssertTrue(state.scopeEditor.hasPendingScopeRuleChanges)
    }

    /// RCL-004-show_query_execution_failure_feedback: collection cleanup은 실행 중 effect를 함께 취소함
    /// semantic cleanup이 search client 작업과 transient feedback timer를 모두 종료하는지 검증한다.
    /// - 검증 내용: search cancellation handler 실행 및 feedback dismiss action 미발생
    /// - 사전 조건: search effect와 feedback timer가 동시에 실행 중임
    /// - 기대 결과: cleanup 후 search가 취소되고 clock을 진행해도 stale feedback action이 전달되지 않음
    func testCleanupCollectionWork_withRunningEffects_cancelsSearchAndFeedbackTimer() async {
        let gate = SearchCancellationGate()
        let clock = TestClock()
        var initialState = ComposerState()
        initialState.text = "find invoices"
        initialState.scopes = ["/VoyagerFixtures/Documents"]
        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.searchClient.search = { _ in try await gate.wait() }
        }
        // store.exhaustivity = .off: UUID 기반 request action보다 effect 취소 결과를 검증한다.
        store.exhaustivity = .off

        await store.send(.submit)
        await gate.waitUntilStarted()
        await store.send(.internal(.presentTransientFeedback(
            ComposerTransientFeedback(id: UUID(), kind: .error, message: "failure"),
        )))
        await store.send(.internal(.cleanupCollectionWork))
        await clock.advance(by: .seconds(4))
        await store.finish()

        let cancellationObserved = await gate.cancellationObserved()
        XCTAssertTrue(cancellationObserved)
        XCTAssertNil(store.state.transientFeedback)
    }

    /// RCL-004-show_query_execution_failure_feedback: feedback 정리는 활성 query/filter 상태를 보존함
    /// discard semantic action이 feedback timer만 취소하는지 검증한다.
    /// - 검증 내용: transient feedback 제거, search/filter process 상태 보존, 4초 후 stale dismissal 미발생
    /// - 사전 조건: search/filter가 진행 중이고 feedback dismiss timer가 실행 중임
    /// - 기대 결과: feedback만 제거되고 활성 search/filter 상태는 유지됨
    func testClearTransientFeedback_preservesActiveSearchAndFilterState() async {
        let searchID = UUID()
        let filtersID = UUID()
        let feedbackID = UUID()
        let clock = TestClock()
        var initialState = ComposerState()
        initialState.text = "find invoices"
        initialState.scopes = ["/VoyagerFixtures/Documents"]
        initialState.isLoadingSearch = true
        initialState.isLoadingFilters = true
        initialState.isFilteringInFlight = true
        initialState.activeSearchRequestID = searchID
        initialState.activeFiltersRequestID = filtersID
        initialState.lastAcceptedSearchRequestID = searchID
        initialState.lastAcceptedFiltersRequestID = filtersID
        initialState.pendingSearchQuery = "pending invoices"
        initialState.queryRenderPhase = .searching
        initialState.searchStartedAt = Date(timeIntervalSince1970: 1_700_000_000)
        initialState.filtersStartedAt = Date(timeIntervalSince1970: 1_700_000_001)
        let feedback = ComposerTransientFeedback(
            id: feedbackID,
            kind: .error,
            message: "failure",
        )
        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.continuousClock = clock
        }
        store.exhaustivity = .off

        await store.send(.internal(.presentTransientFeedback(feedback)))
        await store.send(.internal(.clearTransientFeedback))

        XCTAssertNil(store.state.transientFeedback)
        XCTAssertTrue(store.state.isLoadingSearch)
        XCTAssertTrue(store.state.isLoadingFilters)
        XCTAssertTrue(store.state.isFilteringInFlight)
        XCTAssertEqual(store.state.activeSearchRequestID, searchID)
        XCTAssertEqual(store.state.activeFiltersRequestID, filtersID)
        XCTAssertEqual(store.state.lastAcceptedSearchRequestID, searchID)
        XCTAssertEqual(store.state.lastAcceptedFiltersRequestID, filtersID)
        XCTAssertEqual(store.state.pendingSearchQuery, "pending invoices")
        XCTAssertEqual(store.state.queryRenderPhase, .searching)
        XCTAssertEqual(store.state.searchStartedAt, initialState.searchStartedAt)
        XCTAssertEqual(store.state.filtersStartedAt, initialState.filtersStartedAt)

        await clock.advance(by: .seconds(4))
        await store.finish()
    }

    // MARK: - RCL-004-feedback_dismiss_cancellation_ownership

    /// RCL-004-feedback_dismiss_cancellation_ownership: 서로 다른 owner의 feedback timer는 서로 취소하지 않음
    /// 두 Composer child가 공유하는 cancellation registry에서 한 owner의 feedback가 다른 owner의 timer를 대체하거나 지우지 않는지 검증한다.
    /// - 검증 내용: owner A timer 유지 중 owner B presentation과 clear가 owner A feedback에 영향을 주지 않는지 확인
    /// - 사전 조건: deterministic owner UUID 두 개와 하나의 TestClock으로 두 Composer child를 조합함
    /// - 기대 결과: owner A feedback는 자기 timer가 만료될 때만 지워지고 owner B clear는 owner A timer를 취소하지 않음
    func testFeedbackDismissCancellation_withDifferentOwners_isolatedInSharedReducerTree() async throws {
        let ownerA = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))
        let ownerB = try XCTUnwrap(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
        let clock = TestClock()
        let feedbackA = try ComposerTransientFeedback(
            id: XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111")),
            kind: .error,
            message: "A",
        )
        let feedbackB = try ComposerTransientFeedback(
            id: XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
            kind: .info,
            message: "B",
        )
        let store = TestStore(initialState: ComposerPairState(ownerA: ownerA, ownerB: ownerB)) {
            ComposerPairFeature()
        } withDependencies: {
            $0.continuousClock = clock
        }
        store.exhaustivity = .off

        await store.send(.first(.internal(.presentTransientFeedback(feedbackA))))
        await clock.advance(by: .seconds(3))
        await store.send(.second(.internal(.presentTransientFeedback(feedbackB))))
        await store.send(.second(.internal(.clearTransientFeedback)))
        XCTAssertEqual(store.state.first.transientFeedback, feedbackA)
        XCTAssertNil(store.state.second.transientFeedback)

        await clock.advance(by: .seconds(1))
        await store.receive(\.first)
        XCTAssertNil(store.state.first.transientFeedback)
        await store.finish()
    }

    /// RCL-004-feedback_dismiss_cancellation_ownership: 같은 owner의 feedback presentation은 이전 timer를 대체함
    /// 같은 Composer에서 새 feedback를 표시하면 이전 timer가 아니라 새 timer 기준으로 dismiss되는지 검증한다.
    /// - 검증 내용: 첫 timer 만료 시점에는 두 번째 feedback가 유지되고 두 번째 timer 만료 후 지워지는지 확인
    /// - 사전 조건: 하나의 owner가 같은 TestClock에서 두 feedback를 순서대로 표시함
    /// - 기대 결과: 두 번째 presentation이 첫 timer를 대체하고 새 4초 timer가 시작됨
    func testFeedbackDismissCancellation_withSameOwner_replacesPreviousTimer() async throws {
        let ownerID = try XCTUnwrap(UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"))
        let clock = TestClock()
        let first = try ComposerTransientFeedback(
            id: XCTUnwrap(UUID(uuidString: "33333333-3333-3333-3333-333333333333")),
            kind: .error,
            message: "first",
        )
        let second = try ComposerTransientFeedback(
            id: XCTUnwrap(UUID(uuidString: "44444444-4444-4444-4444-444444444444")),
            kind: .info,
            message: "second",
        )
        let store = TestStore(initialState: ComposerPairState(ownerA: ownerID, ownerB: UUID())) {
            ComposerPairFeature()
        } withDependencies: {
            $0.continuousClock = clock
        }
        store.exhaustivity = .off

        await store.send(.first(.internal(.presentTransientFeedback(first))))
        await clock.advance(by: .seconds(3))
        await store.send(.first(.internal(.presentTransientFeedback(second))))
        await clock.advance(by: .seconds(1))
        XCTAssertEqual(store.state.first.transientFeedback, second)
        await clock.advance(by: .seconds(3))
        await store.receive(\.first)
        XCTAssertNil(store.state.first.transientFeedback)
        await store.finish()
    }

    /// RCL-004-feedback_dismiss_cancellation_ownership: 같은 owner의 clear는 feedback timer만 취소함
    /// transient feedback을 즉시 지워도 search/filter 진행 상태와 효과가 보존되는지 검증한다.
    /// - 검증 내용: clear 후 feedback가 없고 활성 search/filter 상태가 유지되며 timer action이 늦게 도착하지 않는지 확인
    /// - 사전 조건: owner가 지정된 Composer에 search/filter 상태와 feedback timer가 있음
    /// - 기대 결과: clear는 현재 owner timer와 transient feedback만 정리함
    func testFeedbackDismissCancellation_withSameOwner_clearCancelsTimerAndPreservesSearchState() async throws {
        let ownerID = try XCTUnwrap(UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD"))
        let searchID = try XCTUnwrap(UUID(uuidString: "55555555-5555-5555-5555-555555555555"))
        let filtersID = try XCTUnwrap(UUID(uuidString: "66666666-6666-6666-6666-666666666666"))
        let clock = TestClock()
        var initialState = ComposerPairState(ownerA: ownerID, ownerB: UUID())
        initialState.first.text = "find invoices"
        initialState.first.isLoadingSearch = true
        initialState.first.isLoadingFilters = true
        initialState.first.isFilteringInFlight = true
        initialState.first.activeSearchRequestID = searchID
        initialState.first.activeFiltersRequestID = filtersID
        initialState.first.pendingSearchQuery = "pending invoices"
        initialState.first.queryRenderPhase = .searching
        let feedback = try ComposerTransientFeedback(
            id: XCTUnwrap(UUID(uuidString: "77777777-7777-7777-7777-777777777777")),
            kind: .error,
            message: "failure",
        )
        let store = TestStore(initialState: initialState) {
            ComposerPairFeature()
        } withDependencies: {
            $0.continuousClock = clock
        }
        store.exhaustivity = .off

        await store.send(.first(.internal(.presentTransientFeedback(feedback))))
        await store.send(.first(.internal(.clearTransientFeedback)))
        XCTAssertNil(store.state.first.transientFeedback)
        XCTAssertTrue(store.state.first.isLoadingSearch)
        XCTAssertTrue(store.state.first.isLoadingFilters)
        XCTAssertTrue(store.state.first.isFilteringInFlight)
        XCTAssertEqual(store.state.first.activeSearchRequestID, searchID)
        XCTAssertEqual(store.state.first.activeFiltersRequestID, filtersID)
        XCTAssertEqual(store.state.first.pendingSearchQuery, "pending invoices")
        XCTAssertEqual(store.state.first.queryRenderPhase, .searching)

        await clock.advance(by: .seconds(4))
        await store.finish()
    }

    /// RCL-004-feedback_dismiss_cancellation_ownership: Composer reset은 cancellation owner를 보존함
    /// collection 전환 중 semantic reset이 window별 feedback timer 격리 key를 제거하지 않는지 검증한다.
    /// - 검증 내용: reset 후 transient state와 draft는 초기화되고 cancellationOwnerID만 유지되는지 확인
    /// - 사전 조건: owner가 지정되고 query, feedback, collection context가 채워진 Composer가 있음
    /// - 기대 결과: reset 이후에도 기존 owner가 유지되어 다음 feedback timer가 다른 window와 격리됨
    func testResetComposerAndSync_preservesCancellationOwner() throws {
        let ownerID = try XCTUnwrap(UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE"))
        var state = ComposerState()
        state.cancellationOwnerID = ownerID
        state.text = "discard me"
        state.transientFeedback = ComposerTransientFeedback(id: UUID(), kind: .error, message: "failure")

        _ = ComposerFeature().reduce(
            into: &state,
            action: .internal(.resetComposerAndSync(
                context: nil,
                url: nil,
                compatibility: nil,
                isCollectionMode: false,
            )),
        )

        XCTAssertEqual(state.cancellationOwnerID, ownerID)
        XCTAssertEqual(state.text, "")
        XCTAssertNil(state.transientFeedback)
        XCTAssertFalse(state.isCollectionMode)
    }

    /// RCL-004-apply_generated_filter_changes: reset은 활성 query와 apply terminal을 각각 한 번 기록함
    /// Composer reset이 동시에 진행 중인 query와 filter apply를 각각 cancellation handler로 종료하는지 검증한다.
    /// - 검증 내용: query/apply cancelled event 각 1건, reset 반복과 늦은 response의 무시
    /// - 사전 조건: active search/filter request와 각 시작 시각이 있는 Composer
    /// - 기대 결과: 두 canonical terminal만 기록되고 reset 후 두 request가 모두 해제됨
    func testResetComposerAndSync_withActiveQueryAndApply_recordsBothCancelledTerminals() throws {
        let recorder = RCL004MetricRecorder()
        let searchID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000027"))
        let filtersID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000028"))
        var state = ComposerState()
        state.isLoadingSearch = true
        state.isLoadingFilters = true
        state.isFilteringInFlight = true
        state.activeSearchRequestID = searchID
        state.activeFiltersRequestID = filtersID
        state.searchStartedAt = Date(timeIntervalSinceNow: -0.2)
        state.filtersStartedAt = Date(timeIntervalSinceNow: -0.1)

        withDependencies {
            $0.composerMetricClient = ComposerMetricClient(recordProductMetric: recorder.record)
        } operation: {
            let feature = ComposerFeature()
            _ = feature.reduce(
                into: &state,
                action: .internal(.resetComposerAndSync(
                    context: nil,
                    url: nil,
                    compatibility: nil,
                    isCollectionMode: false,
                )),
            )
            _ = feature.reduce(
                into: &state,
                action: .internal(.resetComposerAndSync(
                    context: nil,
                    url: nil,
                    compatibility: nil,
                    isCollectionMode: false,
                )),
            )
            _ = feature.reduce(
                into: &state,
                action: .internal(.searchResponse(searchID, .success(SearchResponsePayload(itemCount: 1)))),
            )
            _ = feature.reduce(
                into: &state,
                action: .internal(.filtersResponse(filtersID, .success(SearchResponsePayload(itemCount: 1)))),
            )
        }

        XCTAssertEqual(recorder.calls.map(\.name), [
            ComposerCollectionFilterMetrics.queryResult,
            ComposerCollectionFilterMetrics.applyResult,
        ])
        XCTAssertEqual(recorder.calls.count(where: { $0.tags?["result_status"] == "cancelled" }), 2)
        XCTAssertNil(state.activeSearchRequestID)
        XCTAssertNil(state.activeFiltersRequestID)
    }

    /// RCL-004-apply_generated_filter_changes: 비활성 reset은 incoming context와 owner를 보존함
    /// active operation이 없는 reset이 metric 없이 새 collection context만 반영하는지 검증한다.
    /// - 검증 내용: query/apply metric 0건, context/url/compatibility/mode와 cancellation owner 보존
    /// - 사전 조건: owner가 지정되고 active request가 없는 Composer에 incoming sync payload가 전달됨
    /// - 기대 결과: reset은 event를 기록하지 않고 모든 incoming sync 필드를 정확히 보존함
    func testResetComposerAndSync_withoutActiveOperations_preservesIncomingState() throws {
        let recorder = RCL004MetricRecorder()
        let ownerID = try XCTUnwrap(UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"))
        let context = CollectionContext(
            query: "find reports",
            scopes: ["/VoyagerFixtures/Documents"],
            excludedScopes: ["/VoyagerFixtures/Trash"],
            includeSubfolders: false,
            includeDirectories: true,
        )
        let url = URL(fileURLWithPath: "/VoyagerFixtures/reports.voycoll")
        let compatibility = CollectionFileCompatibilityMetadata(
            sourceSchemaVersion: SchemaVersion(major: 1, minor: 0),
            migrationPath: [.definitionOnlyV1],
            warnings: [],
            usedDefinitionFallback: false,
            writeBackAllowed: true,
            writeBackReason: .allowed,
        )
        var state = ComposerState()
        state.cancellationOwnerID = ownerID

        withDependencies {
            $0.composerMetricClient = ComposerMetricClient(recordProductMetric: recorder.record)
        } operation: {
            _ = ComposerFeature().reduce(
                into: &state,
                action: .internal(.resetComposerAndSync(
                    context: context,
                    url: url,
                    compatibility: compatibility,
                    isCollectionMode: true,
                )),
            )
        }

        XCTAssertTrue(recorder.calls.isEmpty)
        XCTAssertEqual(state.cancellationOwnerID, ownerID)
        XCTAssertEqual(state.collectionContext, context)
        XCTAssertEqual(state.openedCollectionURL, url)
        XCTAssertEqual(state.openedCollectionCompatibility, compatibility)
        XCTAssertTrue(state.isCollectionMode)
    }

    // MARK: - RCL-004-apply_generated_filter_changes

    /// RCL-004-apply_generated_filter_changes: filter 취소는 terminal apply event를 기록함
    /// 활성 apply 취소가 bounded terminal payload를 한 번만 기록하는지 검증한다.
    /// - 검증 내용: apply event 1건, cancelled status, opaque operation ID와 duration
    /// - 사전 조건: filter 실행 중인 Composer 상태와 실제 metric recorder
    /// - 기대 결과: 취소 후 canonical apply metric만 관찰되고 활성 요청이 해제됨
    func testCancelFilters_recordsCanonicalApplyMetricOnceWithoutLegacyAlias() throws {
        let recorder = RCL004MetricRecorder()
        let requestID = UUID()
        let visibleText = "VOY589_SYNTHETIC_MANUAL_CANCEL_NEWER"
        var state = makeFiltersLoadingState(activeRequestID: requestID)
        state.text = visibleText
        state.activeFiltersMetricSource = ComposerCollectionFilterMetrics.sourceManualApply
        state.queryRecoveryContext = ComposerQueryRecoveryContext(
            rawText: "VOY589_SYNTHETIC_MANUAL_CANCEL_OLD",
            capturedInputRevision: state.inputRevision,
            stage: .filters(requestID),
        )

        withDependencies {
            $0.composerMetricClient = ComposerMetricClient(recordProductMetric: recorder.record)
        } operation: {
            _ = ComposerFeature().reduce(into: &state, action: .view(.cancelFilters))
        }

        XCTAssertEqual(recorder.calls.map(\.name), [ComposerCollectionFilterMetrics.applyResult])
        let call = try XCTUnwrap(recorder.calls.first)
        XCTAssertEqual(call.tags?["result_status"], "cancelled")
        XCTAssertEqual(call.tags?["source_surface"], "composer")
        XCTAssertNotNil(UUID(uuidString: call.tags?["operation_id"] ?? ""))
        XCTAssertNotNil(Int(call.tags?["duration_ms"] ?? ""))
        XCTAssertNil(call.tags?["query"])
        XCTAssertNil(call.tags?["filters"])
        XCTAssertNil(state.activeFiltersRequestID)
        XCTAssertFalse(state.isFilteringInFlight)
        XCTAssertEqual(state.text, visibleText)
        XCTAssertNil(state.queryRecoveryContext)
    }

    /// RCL-004-apply_generated_filter_changes: 활성 apply 없는 취소는 event를 기록하지 않음
    /// stale 또는 이미 종료된 apply 취소가 terminal product event를 만들지 않는지 검증한다.
    /// - 검증 내용: active request 없는 cancel의 capture 0건
    /// - 사전 조건: Composer에 활성 filter request가 없음
    /// - 기대 결과: apply event가 기록되지 않음
    func testCancelFilters_withoutActiveRequest_recordsNoMetric() {
        let recorder = RCL004MetricRecorder()
        var state = ComposerState()

        withDependencies {
            $0.composerMetricClient = ComposerMetricClient { name, value, tags, level in
                recorder.record(name: name, value: value, tags: tags, level: level)
            }
        } operation: {
            _ = ComposerFeature().reduce(into: &state, action: .view(.cancelFilters))
        }

        XCTAssertTrue(recorder.calls.isEmpty)
    }

    private func makeSearchLoadingState(activeRequestID: UUID) -> ComposerState {
        var state = ComposerState()
        state.scopes = ["/VoyagerFixtures/Documents"]
        state.isLoadingSearch = true
        state.queryRenderPhase = .searching
        state.activeSearchRequestID = activeRequestID
        state.submittedSearchFilters = makeSearchFilters()
        state.searchStartedAt = Date(timeIntervalSince1970: 1_700_000_000)
        return state
    }

    private func makeFiltersLoadingState(activeRequestID: UUID) -> ComposerState {
        var state = ComposerState()
        state.scopes = ["/VoyagerFixtures/Documents"]
        state.isLoadingFilters = true
        state.isFilteringInFlight = true
        state.queryRenderPhase = .chipsAppliedPendingList
        state.activeFiltersRequestID = activeRequestID
        state.submittedSearchFilters = makeSearchFilters()
        state.filtersStartedAt = Date(timeIntervalSince1970: 1_700_000_000)
        return state
    }

    private func makeSearchFilters() -> SearchFiltersPayload {
        SearchFiltersPayload(
            scopes: ["/VoyagerFixtures/Documents"],
            excludedScopes: [],
            includeSubfolders: true,
            conditions: [],
        )
    }

    private func makeConversionErrorResponse() -> SearchResponsePayload {
        SearchResponsePayload(
            itemCount: 0,
            error: SearchErrorPayload(code: "LLM_CONVERSION_FAILED", details: "synthetic"),
            queryConversion: SearchQueryConversionMetadataPayload(outcome: .conversionFailure),
        )
    }

    private func makeGeneratedConditionResponse(
        scopes: [String] = ["/VoyagerFixtures/Documents"],
    ) -> SearchResponsePayload {
        SearchResponsePayload(
            itemCount: 0,
            appliedFilters: AppliedFiltersPayload(
                scopes: scopes,
                conditions: [
                    SearchConditionPayload(propertyKey: "kind", operator: "eq", value: .string("pdf")),
                ],
            ),
            queryConversion: SearchQueryConversionMetadataPayload(outcome: .generatedChangeSet),
        )
    }

    private func makeRegistryClient() -> RegistryClient {
        .init(
            allProperties: { [] },
            labelForKey: { _ in "Kind" },
            propertyTypeString: { _ in "string" },
            propertyUnitSpec: { _ in nil },
            operatorCodes: { _ in ["eq", "contains"] },
            operatorDefinition: { code in
                .init(
                    uiLabel: code == "eq" ? "Equals" : "Contains",
                    mdqueryOperator: code == "eq" ? "==" : "CONTAINS",
                    valueShape: ValueShape.single,
                    valueCount: .fixed(1),
                    allowedTypes: ["string"],
                    inverseOf: nil,
                    aliases: nil,
                    uiValueKind: ["string": "singleText"],
                )
            },
            resolvePropertyKey: { .canonical($0) },
            resolveCondition: { propertyKey, operatorCode, values, sourcePayload in
                let property = Condition.Property(
                    key: propertyKey,
                    label: "Kind",
                    type: .string,
                    unitContract: nil,
                    operatorOptions: [
                        .init(code: "eq", label: "Equals"),
                        .init(code: "contains", label: "Contains"),
                    ],
                )
                let operation = operatorCode.map { code in
                    Condition.Operation(
                        code: code,
                        label: code == "eq" ? "Equals" : "Contains",
                        valueContract: .init(shape: .single, count: .fixed(1), input: .singleText),
                    )
                }
                return Condition(
                    property: property,
                    operation: operation,
                    values: values,
                    availability: .available,
                    opaqueSource: sourcePayload,
                )
            },
        )
    }
}

extension RCL004ComposeCollectionFilterTests {
    // MARK: - RCL-004-submit_collection_filter_query

    /// RCL-004-submit_collection_filter_query: semantic payload replacement는 이전 query 복원을 폐기함
    /// draft, navigation, open restoration payload가 진행 중 제출보다 우선하는지 검증한다.
    /// - 검증 내용: 각 replacement의 exact text, input revision 증가, recovery context 폐기
    /// - 사전 조건: synthetic query submit 뒤 서로 다른 collection payload가 적용됨
    /// - 기대 결과: payload text가 유지되고 늦은 이전 failure가 이를 덮어쓰지 않음
    func testSemanticPayloadReplacement_discardsSubmittedQueryRecovery() {
        let submittedText = "VOY589_SYNTHETIC_SUBMITTED"
        let context = CollectionContext(query: "VOY589_SYNTHETIC_REPLACEMENT", scopes: [], conditions: [])

        var draftState = ComposerState()
        draftState.text = submittedText
        _ = ComposerFeature().reduce(into: &draftState, action: .submit)
        let draftRequestID = draftState.activeSearchRequestID
        _ = ComposerFeature().reduce(
            into: &draftState,
            action: .applyCollectionDraftRestore(.init(context: context, openedURL: nil)),
        )
        XCTAssertEqual(draftState.text, context.query)
        XCTAssertEqual(draftState.inputRevision, 1)
        XCTAssertNil(draftState.queryRecoveryContext)
        if let draftRequestID {
            _ = ComposerFeature().reduce(
                into: &draftState,
                action: .searchResponse(draftRequestID, .failure(MockLocalizedError("synthetic"))),
            )
        }
        XCTAssertEqual(draftState.text, context.query)

        var navigationState = ComposerState()
        navigationState.text = submittedText
        _ = ComposerFeature().reduce(into: &navigationState, action: .submit)
        let navigationPayload = CollectionNavigationStatePayload(
            context: context,
            document: nil,
            baseline: nil,
            composerText: "VOY589_SYNTHETIC_NAVIGATION",
            scopes: [],
            conditions: [],
        )
        _ = ComposerFeature().reduce(
            into: &navigationState,
            action: .applyCollectionNavigationComposer(navigationPayload),
        )
        XCTAssertEqual(navigationState.text, navigationPayload.composerText)
        XCTAssertEqual(navigationState.inputRevision, 1)
        XCTAssertNil(navigationState.queryRecoveryContext)

        var openState = ComposerState()
        openState.text = submittedText
        _ = ComposerFeature().reduce(into: &openState, action: .submit)
        let openPayload = CollectionOpenRestorationPayload(
            context: context,
            compatibility: nil,
            navigation: nil,
            shouldRestoreStaleNavigation: false,
            queryTrigger: nil,
            hydratedOpenPayload: nil,
            isEmptyDefinition: false,
            unsupportedFilterKeys: [],
        )
        openState.applyCollectionOpenRestorationComposerPayload(
            openPayload,
            registryClient: makeRegistryClient(),
        )
        XCTAssertEqual(openState.text, context.query)
        XCTAssertEqual(openState.inputRevision, 1)
        XCTAssertNil(openState.queryRecoveryContext)
    }

    /// RCL-004-submit_collection_filter_query: full reset은 새 revision/context로 이전 제출을 폐기함
    /// semantic reset 뒤 늦은 matching failure가 abandoned query를 복원하지 않는지 검증한다.
    /// - 검증 내용: reset의 fresh text/revision/context와 cancellation owner 보존
    /// - 사전 조건: owner가 있는 Composer에 active synthetic query submit이 존재함
    /// - 기대 결과: reset 뒤 owner만 유지되고 늦은 failure는 public text를 변경하지 않음
    func testResetComposerAndSync_discardsSubmittedQueryRecovery() {
        let ownerID = UUID()
        var state = ComposerState()
        state.cancellationOwnerID = ownerID
        state.text = "VOY589_SYNTHETIC_RESET"
        _ = ComposerFeature().reduce(into: &state, action: .submit)
        let requestID = state.activeSearchRequestID

        _ = ComposerFeature().reduce(
            into: &state,
            action: .internal(.resetComposerAndSync(
                context: nil,
                url: nil,
                compatibility: nil,
                isCollectionMode: false,
            )),
        )

        XCTAssertEqual(state.cancellationOwnerID, ownerID)
        XCTAssertEqual(state.text, "")
        XCTAssertEqual(state.inputRevision, 0)
        XCTAssertNil(state.queryRecoveryContext)
        if let requestID {
            _ = ComposerFeature().reduce(
                into: &state,
                action: .searchResponse(requestID, .failure(MockLocalizedError("synthetic"))),
            )
        }
        XCTAssertEqual(state.text, "")
    }

    /// RCL-004-submit_collection_filter_query: scope reexecution은 semantic replacement 뒤 새 submit을 소유함
    /// scope editor commit으로 재실행할 때 이전 context가 아닌 새 request가 query 복원을 소유하는지 검증한다.
    /// - 검증 내용: replacement revision 증가, 새 active request/context capture, submit-owned clear
    /// - 사전 조건: 기존 submit과 pending scope 변경 및 non-empty collection query가 있음
    /// - 기대 결과: 새 search context가 trimmed query와 증가한 revision을 캡처함
    func testScopeTriggeredReexecution_replacesRecoveryBeforeNewSubmit() async {
        var initialState = ComposerState()
        initialState.text = "  VOY589_SYNTHETIC_SCOPE  "
        _ = ComposerFeature().reduce(into: &initialState, action: .submit)
        initialState.pendingSearchQuery = "  VOY589_SYNTHETIC_SCOPE  "
        initialState.scopeEditor.isPresented = true
        initialState.scopes = ["/VoyagerFixtures/Documents"]
        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.registryClient = makeRegistryClient()
            $0.uuid = .constant(UUID())
            $0.searchClient.search = { _ in
                SearchResponsePayload(
                    itemCount: 0,
                    queryConversion: SearchQueryConversionMetadataPayload(outcome: .unchangedResult),
                )
            }
        }
        // store.exhaustivity = .off: scope dismiss의 부수 state보다 새 query recovery ownership을 검증한다.
        store.exhaustivity = .off

        await store.send(.scopeEditorSetPresented(false))
        await store.receive(\.view.submit)

        XCTAssertEqual(store.state.inputRevision, 1)
        XCTAssertEqual(store.state.text, "")
        XCTAssertEqual(store.state.queryRecoveryContext?.rawText, "VOY589_SYNTHETIC_SCOPE")
        XCTAssertEqual(store.state.queryRecoveryContext?.capturedInputRevision, 1)
        XCTAssertEqual(
            store.state.queryRecoveryContext?.stage,
            store.state.activeSearchRequestID.map(ComposerQueryRecoveryContext.Stage.search),
        )

        await store.receive(\.internal.searchResponse)
        await store.finish()
    }

    // MARK: - RCL-004-apply_generated_filter_changes

    /// RCL-004-apply_generated_filter_changes: filter stage clear-all은 active lifecycle을 semantic clear함
    /// generated filter 실행 중 Clear All 뒤 늦은 matching failure가 처리 상태나 제출문을 되살리지 않는지 검증한다.
    /// - 검증 내용: clear revision 증가, filter ownership/processing/context 폐기, late filter failure full no-op
    /// - 사전 조건: synthetic query가 generated filter stage에 진입함
    /// - 기대 결과: clear-all이 최종 사용자 intent가 되어 visible text가 계속 비어 있음
    func testClearAllDuringFilterStage_discardsSubmittedQueryRecovery() {
        var state = makeGeneratedFilterStageState(rawText: "VOY589_SYNTHETIC_CLEAR_ALL")
        let requestID = state.activeFiltersRequestID

        _ = ComposerFeature().reduce(into: &state, action: .clearAll)

        XCTAssertEqual(state.text, "")
        XCTAssertEqual(state.inputRevision, 1)
        XCTAssertFalse(state.isLoadingFilters)
        XCTAssertFalse(state.isFilteringInFlight)
        XCTAssertNil(state.activeFiltersRequestID)
        XCTAssertNil(state.lastAcceptedFiltersRequestID)
        XCTAssertNil(state.activeFiltersMetricSource)
        XCTAssertNil(state.filtersStartedAt)
        XCTAssertNil(state.queryRecoveryContext)
        let stateAfterClearAll = state
        if let requestID {
            _ = ComposerFeature().reduce(
                into: &state,
                action: .filtersResponse(requestID, .failure(MockLocalizedError("synthetic"))),
            )
        }
        XCTAssertEqual(state, stateAfterClearAll)
    }

    // MARK: - RCL-004-show_query_execution_failure_feedback

    /// RCL-004-show_query_execution_failure_feedback: Composer dismiss는 lifecycle별 recovery 정책을 적용함
    /// search dismiss, exact live filter 유지, cancelled filter dismiss의 서로 다른 context 처리를 검증한다.
    /// - 검증 내용: search discard, matching live filter retain, cancelled filter discard
    /// - 사전 조건: 각 stage에 synthetic recovery context가 존재함
    /// - 기대 결과: intentionally alive인 exact filter context만 dismiss 이후 남음
    func testDismiss_appliesExactSearchAndFilterRecoveryPolicy() {
        var searchState = ComposerState()
        searchState.text = "VOY589_SYNTHETIC_DISMISS_SEARCH"
        _ = ComposerFeature().reduce(into: &searchState, action: .submit)
        _ = ComposerFeature().reduce(into: &searchState, action: .setPresented(false))
        XCTAssertNil(searchState.queryRecoveryContext)
        XCTAssertEqual(searchState.text, "")

        let filterRawText = "VOY589_SYNTHETIC_DISMISS_FILTER"
        var liveFilterState = makeGeneratedFilterStageState(rawText: filterRawText)
        let liveRequestID = liveFilterState.activeFiltersRequestID
        let liveContext = liveFilterState.queryRecoveryContext
        _ = ComposerFeature().reduce(into: &liveFilterState, action: .setPresented(false))
        XCTAssertEqual(liveFilterState.queryRecoveryContext, liveContext)
        XCTAssertEqual(liveFilterState.activeFiltersRequestID, liveRequestID)
        if let liveRequestID {
            _ = ComposerFeature().reduce(
                into: &liveFilterState,
                action: .filtersResponse(liveRequestID, .failure(MockLocalizedError("synthetic"))),
            )
        }
        XCTAssertEqual(liveFilterState.text, filterRawText)

        let cancelledRequestID = UUID()
        var cancelledFilterState = ComposerState()
        cancelledFilterState.queryRecoveryContext = ComposerQueryRecoveryContext(
            rawText: "VOY589_SYNTHETIC_CANCELLED_FILTER",
            capturedInputRevision: cancelledFilterState.inputRevision,
            stage: .filters(cancelledRequestID),
        )
        _ = ComposerFeature().reduce(into: &cancelledFilterState, action: .setPresented(false))
        XCTAssertNil(cancelledFilterState.queryRecoveryContext)
    }

    /// RCL-004-show_query_execution_failure_feedback: cleanup은 matching late failure 전에 recovery를 폐기함
    /// collection cleanup 뒤 이전 filter failure가 도착해도 abandoned query가 복원되지 않는지 검증한다.
    /// - 검증 내용: cleanup 직후 context disposal과 late response public no-op
    /// - 사전 조건: generated filter request와 exact raw synthetic recovery가 active임
    /// - 기대 결과: cleanup 뒤 text/context/feedback가 유지되고 늦은 failure는 무시됨
    func testCleanupThenLateMatchingFailure_doesNotRestoreSubmittedQuery() {
        var state = makeGeneratedFilterStageState(rawText: "VOY589_SYNTHETIC_CLEANUP")
        let requestID = state.activeFiltersRequestID

        _ = ComposerFeature().reduce(into: &state, action: .internal(.cleanupCollectionWork))
        let textAfterCleanup = state.text
        let feedbackAfterCleanup = state.transientFeedback

        XCTAssertNil(state.queryRecoveryContext)
        if let requestID {
            _ = ComposerFeature().reduce(
                into: &state,
                action: .filtersResponse(requestID, .failure(MockLocalizedError("synthetic"))),
            )
        }
        XCTAssertEqual(state.text, textAfterCleanup)
        XCTAssertEqual(state.transientFeedback, feedbackAfterCleanup)
        XCTAssertNil(state.queryRecoveryContext)
    }

    private func makeGeneratedFilterStageState(
        rawText: String,
        response: SearchResponsePayload? = nil,
    ) -> ComposerState {
        var state = ComposerState()
        state.text = rawText
        _ = ComposerFeature().reduce(into: &state, action: .submit)
        guard let requestID = state.activeSearchRequestID else {
            preconditionFailure("submit must create an active request")
        }
        withDependencies {
            $0.registryClient = makeRegistryClient()
            $0.uuid = .constant(UUID())
        } operation: {
            _ = ComposerFeature().reduce(
                into: &state,
                action: .searchResponse(requestID, .success(response ?? makeGeneratedConditionResponse())),
            )
        }
        return state
    }
}

private struct ComposerPairState: Equatable {
    var first: ComposerState
    var second: ComposerState

    init(ownerA: UUID, ownerB: UUID) {
        first = ComposerState()
        first.cancellationOwnerID = ownerA
        second = ComposerState()
        second.cancellationOwnerID = ownerB
    }
}

@CasePathable
private enum ComposerPairAction {
    case first(ComposerFeature.Action)
    case second(ComposerFeature.Action)
}

@Reducer
private struct ComposerPairFeature {
    typealias State = ComposerPairState
    typealias Action = ComposerPairAction

    var body: some ReducerOf<Self> {
        Scope(state: \.first, action: \.first) {
            ComposerFeature()
        }
        Scope(state: \.second, action: \.second) {
            ComposerFeature()
        }
    }
}

private struct MockLocalizedError: LocalizedError, Equatable {
    let rawMessage: String

    init(_ rawMessage: String) {
        self.rawMessage = rawMessage
    }

    var errorDescription: String? {
        rawMessage
    }
}
