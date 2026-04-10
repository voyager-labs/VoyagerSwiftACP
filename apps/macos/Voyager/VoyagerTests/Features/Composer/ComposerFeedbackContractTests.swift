import ComposableArchitecture
import Foundation
@testable import Voyager
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
                try await Task.sleep(for: .hours(1))
                return .init(itemCount: 0, appliedFilters: nil, items: nil, error: nil)
            }
            $0.searchClient.applyFilters = { _ in
                XCTFail("applyFilters should not run before search response is delivered")
                return .init(itemCount: 0, appliedFilters: nil, items: nil, error: nil)
            }
        }
        store.exhaustivity = .off

        await store.send(.submit)

        XCTAssertEqual(store.state.submittedSearchFilters, SearchFiltersPayload(scopes: ["/tmp"], conditions: []))
        XCTAssertNotNil(store.state.activeSearchRequestID)
        XCTAssertNil(store.state.activeFiltersRequestID)
        XCTAssertTrue(store.state.isLoadingSearch)
        XCTAssertEqual(store.state.queryRenderPhase, .searching)
        XCTAssertEqual(store.state.text, "")

        let recordedRequest = try await XCTUnwrap(recorder.last())
        XCTAssertEqual(recordedRequest.query, "images tagged blue")
        XCTAssertEqual(recordedRequest.filters, SearchFiltersPayload(scopes: ["/tmp"], conditions: []))

        await store.send(.cancelSearch)

        XCTAssertNil(store.state.activeSearchRequestID)
        XCTAssertEqual(store.state.submittedSearchFilters, SearchFiltersPayload(scopes: ["/tmp"], conditions: []))
        XCTAssertFalse(store.state.isLoadingSearch)
        XCTAssertEqual(store.state.queryRenderPhase, .idle)
    }

    func testStaleResponseDoesNotMutateComposerState() async {
        let activeSearchRequestID = UUID()
        let staleSearchRequestID = UUID()
        var initialState = ComposerState(
            scopes: ["/tmp"],
            isLoadingSearch: true,
            queryRenderPhase: .searching,
            submittedSearchFilters: SearchFiltersPayload(scopes: ["/tmp"], conditions: []),
            activeSearchRequestID: activeSearchRequestID,
        )
        initialState.lastSearchResponse = nil

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        }
        store.exhaustivity = .off

        await store.send(.searchResponse(
            staleSearchRequestID,
            .success(.init(itemCount: 1, appliedFilters: nil, items: nil, error: nil)),
        ))

        XCTAssertEqual(store.state, initialState)
    }
}

private actor SearchRequestRecorder {
    private var requests: [SearchRequestPayload] = []

    func record(_ request: SearchRequestPayload) {
        requests.append(request)
    }

    func last() -> SearchRequestPayload? {
        requests.last
    }
}
