import ComposableArchitecture
import Foundation
@testable import Voyager
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

@MainActor
final class ComposerQueryFeedbackLifecycleTests: XCTestCase {
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

        await store.send(ComposerAction.filtersResponse(
            staleRequestID,
            .failure(MockLocalizedError("HELPER_UNAVAILABLE: xpc disconnected")),
        ))

        XCTAssertEqual(store.state.queryRenderPhase, .chipsAppliedPendingList)
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
