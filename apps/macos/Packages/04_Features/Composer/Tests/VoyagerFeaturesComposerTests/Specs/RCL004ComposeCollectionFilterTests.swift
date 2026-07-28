import ComposableArchitecture
import Foundation
@_spi(Testing)
@testable import VoyagerEntitiesCollection
@testable import VoyagerFeaturesComposer
import VoyagerShared
import XCTest

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
            $0.uuid = .constant(UUID())
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

private struct MockLocalizedError: LocalizedError, Equatable {
    let rawMessage: String

    init(_ rawMessage: String) {
        self.rawMessage = rawMessage
    }

    var errorDescription: String? {
        rawMessage
    }
}
