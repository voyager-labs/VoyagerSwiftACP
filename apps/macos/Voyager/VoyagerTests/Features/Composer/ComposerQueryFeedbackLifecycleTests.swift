import ComposableArchitecture
import Foundation
@testable import Voyager
@testable import VoyagerFeaturesComposer
import VoyagerShared
import XCTest

/// Composer 쿼리 피드백 생명주기 — 필터 유효/변경 없음/실패/stale 전이를 검증.
@MainActor
final class ComposerQueryFeedbackLifecycleTests: XCTestCase {
    /// testChangedFiltersContinueToApplyFiltersWithoutShowingToast 테스트 동작을 검증한다.
    func testChangedFiltersContinueToApplyFiltersWithoutShowingToast() async {
        let applyRecorder = ApplyFiltersRecorder()
        let activeRequestID = UUID()
        let searchResponse = VoyagerShared.SearchResponsePayload(
            itemCount: 0,
            appliedFilters: VoyagerShared.AppliedFiltersPayload(
                scopes: ["/tmp"],
                conditions: [
                    VoyagerShared.SearchConditionPayload(
                        propertyKey: "name",
                        operator: "contains",
                        value: .string("draft"),
                    ),
                ],
            ),
            items: nil,
            error: nil,
        )

        var initialState = ComposerState()
        initialState.scopes = ["/tmp"]
        initialState.isLoadingSearch = true
        initialState.queryRenderPhase = .searching
        initialState.submittedSearchFilters = VoyagerShared.SearchFiltersPayload(scopes: ["/tmp"], conditions: [])
        initialState.activeSearchRequestID = activeRequestID

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient.applyFilters = { request in
                await applyRecorder.record(request)
                return VoyagerShared.SearchResponsePayload(
                    itemCount: 2,
                    appliedFilters: request.filters.asAppliedFiltersPayload,
                    items: nil,
                    error: nil,
                )
            }
        }
        store.exhaustivity = .off

        await store.send(ComposerAction.searchResponse(activeRequestID, .success(searchResponse)))

        let recordedRequest = applyRecorder.last()
        XCTAssertEqual(recordedRequest?.filters.conditions.count, 1)
        XCTAssertNil(store.state.transientFeedback)
        XCTAssertTrue(store.state.isLoadingFilters)
    }

    /// testNoOpSearchSkipsApplyFiltersWithoutShowingFeedback 테스트 동작을 검증한다.
    func testNoOpSearchSkipsApplyFiltersWithoutShowingFeedback() async {
        let applyRecorder = ApplyFiltersRecorder()
        let activeRequestID = UUID()
        let searchResponse = VoyagerShared.SearchResponsePayload(
            itemCount: 0,
            appliedFilters: VoyagerShared.AppliedFiltersPayload(scopes: ["/tmp"], conditions: []),
            items: nil,
            error: nil,
        )

        var initialState = ComposerState()
        initialState.scopes = ["/tmp"]
        initialState.isLoadingSearch = true
        initialState.queryRenderPhase = .searching
        initialState.submittedSearchFilters = VoyagerShared.SearchFiltersPayload(scopes: ["/tmp"], conditions: [])
        initialState.activeSearchRequestID = activeRequestID

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient.applyFilters = { request in
                await applyRecorder.record(request)
                return VoyagerShared.SearchResponsePayload(
                    itemCount: 0,
                    appliedFilters: request.filters.asAppliedFiltersPayload,
                    items: nil,
                    error: nil,
                )
            }
        }
        store.exhaustivity = .off

        await store.send(ComposerAction.searchResponse(activeRequestID, .success(searchResponse)))

        XCTAssertNil(applyRecorder.last())
        XCTAssertEqual(store.state.queryRenderPhase, ComposerQueryRenderPhase.idle)
        XCTAssertNil(store.state.transientFeedback)
    }

    /// testSearchFailureShowsPolicyErrorFeedback 테스트 동작을 검증한다.
    func testSearchFailureShowsPolicyErrorFeedback() async {
        let activeRequestID = UUID()
        var initialState = ComposerState()
        initialState.scopes = ["/tmp"]
        initialState.isLoadingSearch = true
        initialState.queryRenderPhase = .searching
        initialState.activeSearchRequestID = activeRequestID

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        }
        store.exhaustivity = .off

        await store.send(ComposerAction.searchResponse(
            activeRequestID,
            .failure(MockLocalizedError("LLM_CONVERSION_FAILED: timeout")),
        ))

        XCTAssertEqual(store.state.transientFeedback?.kind, .error)
        XCTAssertEqual(store.state.transientFeedback?.message, ComposerQueryFeedbackPolicy.conversionFailureMessage)
        XCTAssertEqual(store.state.queryRenderPhase, .failed)
    }

    /// testStaleFilterResponseDoesNotMutateFeedbackOrPhase 테스트 동작을 검증한다.
    func testStaleFilterResponseDoesNotMutateFeedbackOrPhase() async {
        let activeRequestID = UUID()
        let staleRequestID = UUID()
        let initialFeedback = ComposerTransientFeedback(id: UUID(), kind: .info, message: "existing")
        var initialState = ComposerState()
        initialState.scopes = ["/tmp"]
        initialState.isLoadingFilters = true
        initialState.isFilteringInFlight = true
        initialState.queryRenderPhase = .chipsAppliedPendingList
        initialState.transientFeedback = initialFeedback
        initialState.activeFiltersRequestID = activeRequestID

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        }
        store.exhaustivity = .off

        await store.send(ComposerAction.filtersResponse(
            staleRequestID,
            .failure(MockLocalizedError("HELPER_UNAVAILABLE: xpc disconnected")),
        ))

        XCTAssertEqual(store.state.queryRenderPhase, ComposerQueryRenderPhase.chipsAppliedPendingList)
        XCTAssertEqual(store.state.transientFeedback, initialFeedback)
        XCTAssertEqual(store.state.activeFiltersRequestID, activeRequestID)
    }
}

private final class ApplyFiltersRecorder: @unchecked Sendable {
    private var requests: [VoyagerShared.FiltersOnlyRequestPayload] = []

    func record(_ request: VoyagerShared.FiltersOnlyRequestPayload) {
        requests.append(request)
    }

    func last() -> VoyagerShared.FiltersOnlyRequestPayload? {
        requests.last
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

private extension VoyagerShared.SearchFiltersPayload {
    var asAppliedFiltersPayload: VoyagerShared.AppliedFiltersPayload {
        VoyagerShared.AppliedFiltersPayload(scopes: scopes, conditions: conditions)
    }
}
