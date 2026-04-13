import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerShared
import XCTest

@MainActor
final class ComposerFeedbackContractTests: XCTestCase {
    func testSubmitStoresBaselineAndRequestIDs() async throws {
        let recorder = SearchRequestRecorder()
        let initialState = ComposerState(
            text: "images tagged blue",
            scopes: ["/tmp"],
        )

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient.search = { request in
                await recorder.record(request)
                try await Task.sleep(for: .seconds(3600))
                return VoyagerShared.SearchResponsePayload(itemCount: 0, appliedFilters: nil, items: nil, error: nil)
            }
            $0.searchClient.applyFilters = { _ in
                XCTFail("applyFilters should not run before search response is delivered")
                return VoyagerShared.SearchResponsePayload(itemCount: 0, appliedFilters: nil, items: nil, error: nil)
            }
        }
        store.exhaustivity = .off

        await store.send(ComposerAction.submit)

        XCTAssertEqual(
            store.state.submittedSearchFilters,
            VoyagerShared.SearchFiltersPayload(scopes: ["/tmp"], conditions: []),
        )
        XCTAssertNotNil(store.state.activeSearchRequestID)
        XCTAssertNil(store.state.activeFiltersRequestID)
        XCTAssertTrue(store.state.isLoadingSearch)
        XCTAssertEqual(store.state.queryRenderPhase, ComposerQueryRenderPhase.searching)
        XCTAssertEqual(store.state.text, "")

        let recordedRequest = try XCTUnwrap(recorder.last())
        XCTAssertEqual(recordedRequest.query, "images tagged blue")
        XCTAssertEqual(recordedRequest.filters, VoyagerShared.SearchFiltersPayload(scopes: ["/tmp"], conditions: []))

        await store.send(ComposerAction.cancelSearch)

        XCTAssertNil(store.state.activeSearchRequestID)
        XCTAssertEqual(
            store.state.submittedSearchFilters,
            VoyagerShared.SearchFiltersPayload(scopes: ["/tmp"], conditions: []),
        )
        XCTAssertFalse(store.state.isLoadingSearch)
        XCTAssertEqual(store.state.queryRenderPhase, ComposerQueryRenderPhase.idle)
    }

    func testStaleResponseDoesNotMutateComposerState() async {
        let activeSearchRequestID = UUID()
        let staleSearchRequestID = UUID()
        var initialState = ComposerState()
        initialState.scopes = ["/tmp"]
        initialState.isLoadingSearch = true
        initialState.queryRenderPhase = .searching
        initialState.submittedSearchFilters = VoyagerShared.SearchFiltersPayload(scopes: ["/tmp"], conditions: [])
        initialState.activeSearchRequestID = activeSearchRequestID
        initialState.lastSearchResponse = nil

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        }
        store.exhaustivity = .off

        await store.send(ComposerAction.searchResponse(
            staleSearchRequestID,
            .success(VoyagerShared.SearchResponsePayload(itemCount: 1, appliedFilters: nil, items: nil, error: nil)),
        ))

        XCTAssertEqual(store.state, initialState)
    }
}

private final class SearchRequestRecorder: @unchecked Sendable {
    private var requests: [VoyagerShared.SearchRequestPayload] = []

    func record(_ request: VoyagerShared.SearchRequestPayload) {
        requests.append(request)
    }

    func last() -> VoyagerShared.SearchRequestPayload? {
        requests.last
    }
}
