import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
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
        XCTAssertNotNil(state.activeSearchRequestID)
        XCTAssertEqual(state.submittedSearchFilters?.scopes, ["/VoyagerFixtures/Documents"])
        XCTAssertTrue(state.includeDirectories)
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

        _ = ComposerFeature().reduce(into: &state, action: .setText("find reports"))

        XCTAssertEqual(state.text, "find reports")
        XCTAssertNil(state.transientFeedback)
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
        } operation: {
            _ = ComposerFeature().reduce(into: &state, action: .searchResponse(requestID, .success(response)))
        }

        XCTAssertFalse(state.isLoadingSearch)
        XCTAssertTrue(state.isLoadingFilters)
        XCTAssertTrue(state.isFilteringInFlight)
        XCTAssertNil(state.activeSearchRequestID)
        XCTAssertNotNil(state.activeFiltersRequestID)
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
    }

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
        state.conditions = [Condition(propertyKey: "kind", propertyLabel: "Kind", propertyType: "string")]
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
        XCTAssertEqual(state.conditions.map(\.propertyKey), ["kind"])
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
            operatorValueUIKind: { _, _ in "singleText" },
            resolvePropertyKey: { .canonical($0) },
        )
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
