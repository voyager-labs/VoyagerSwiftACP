import ComposableArchitecture
import Foundation
@testable import Voyager
import XCTest

@MainActor
final class ComposerQueryFeedbackLifecycleTests: XCTestCase {
    func testChangedFiltersContinueToApplyFiltersWithoutShowingToast() async {
        let applyRecorder = ApplyFiltersRecorder()
        let activeRequestID = UUID()
        let searchResponse = SearchResponsePayload(
            itemCount: 0,
            appliedFilters: AppliedFiltersPayload(
                scopes: ["/tmp"],
                conditions: [
                    SearchConditionPayload(
                        propertyKey: "name",
                        operator: "contains",
                        value: .string("draft"),
                    ),
                ],
            ),
            items: nil,
            error: nil,
        )

        let store = TestStore(initialState: ComposerState(
            scopes: ["/tmp"],
            isLoadingSearch: true,
            queryRenderPhase: .searching,
            submittedSearchFilters: SearchFiltersPayload(scopes: ["/tmp"], conditions: []),
            activeSearchRequestID: activeRequestID,
        )) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient.applyFilters = { request in
                await applyRecorder.record(request)
                return .init(
                    itemCount: 2,
                    appliedFilters: request.filters.asAppliedFiltersPayload,
                    items: nil,
                    error: nil,
                )
            }
        }
        store.exhaustivity = .off

        await store.send(.searchResponse(activeRequestID, .success(searchResponse)))

        let recordedRequest = await applyRecorder.last()
        XCTAssertEqual(recordedRequest?.filters.conditions.count, 1)
        XCTAssertNil(store.state.transientFeedback)
        XCTAssertTrue(store.state.isLoadingFilters)
    }

    func testNoOpSearchSkipsApplyFiltersWithoutShowingFeedback() async {
        let applyRecorder = ApplyFiltersRecorder()
        let activeRequestID = UUID()
        let searchResponse = SearchResponsePayload(
            itemCount: 0,
            appliedFilters: AppliedFiltersPayload(scopes: ["/tmp"], conditions: []),
            items: nil,
            error: nil,
        )

        let store = TestStore(initialState: ComposerState(
            scopes: ["/tmp"],
            isLoadingSearch: true,
            queryRenderPhase: .searching,
            submittedSearchFilters: SearchFiltersPayload(scopes: ["/tmp"], conditions: []),
            activeSearchRequestID: activeRequestID,
        )) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient.applyFilters = { request in
                await applyRecorder.record(request)
                return .init(
                    itemCount: 0,
                    appliedFilters: request.filters.asAppliedFiltersPayload,
                    items: nil,
                    error: nil,
                )
            }
        }
        store.exhaustivity = .off

        await store.send(.searchResponse(activeRequestID, .success(searchResponse)))

        await XCTAssertNil(applyRecorder.last())
        XCTAssertEqual(store.state.queryRenderPhase, .idle)
        XCTAssertNil(store.state.transientFeedback)
    }

    func testSearchFailureShowsPolicyErrorFeedback() async {
        let activeRequestID = UUID()
        let store = TestStore(initialState: ComposerState(
            scopes: ["/tmp"],
            isLoadingSearch: true,
            queryRenderPhase: .searching,
            activeSearchRequestID: activeRequestID,
        )) {
            ComposerFeature()
        }
        store.exhaustivity = .off

        await store.send(.searchResponse(
            activeRequestID,
            .failure(MockLocalizedError("LLM_CONVERSION_FAILED: timeout")),
        ))

        XCTAssertEqual(store.state.transientFeedback?.kind, .error)
        XCTAssertEqual(store.state.transientFeedback?.message, ComposerQueryFeedbackPolicy.conversionFailureMessage)
        XCTAssertEqual(store.state.queryRenderPhase, .failed)
    }

    func testStaleFilterResponseDoesNotMutateFeedbackOrPhase() async {
        let activeRequestID = UUID()
        let staleRequestID = UUID()
        let initialFeedback = ComposerTransientFeedback(id: UUID(), kind: .info, message: "existing")
        let initialState = ComposerState(
            scopes: ["/tmp"],
            isLoadingFilters: true,
            isFilteringInFlight: true,
            queryRenderPhase: .chipsAppliedPendingList,
            transientFeedback: initialFeedback,
            activeFiltersRequestID: activeRequestID,
        )

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        }
        store.exhaustivity = .off

        await store.send(.filtersResponse(
            staleRequestID,
            .failure(MockLocalizedError("HELPER_UNAVAILABLE: xpc disconnected")),
        ))

        XCTAssertEqual(store.state.queryRenderPhase, .chipsAppliedPendingList)
        XCTAssertEqual(store.state.transientFeedback, initialFeedback)
        XCTAssertEqual(store.state.activeFiltersRequestID, activeRequestID)
    }
}

private actor ApplyFiltersRecorder {
    private var requests: [FiltersOnlyRequestPayload] = []

    func record(_ request: FiltersOnlyRequestPayload) {
        requests.append(request)
    }

    func last() -> FiltersOnlyRequestPayload? {
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

private extension SearchFiltersPayload {
    var asAppliedFiltersPayload: AppliedFiltersPayload {
        AppliedFiltersPayload(scopes: scopes, conditions: conditions)
    }
}
