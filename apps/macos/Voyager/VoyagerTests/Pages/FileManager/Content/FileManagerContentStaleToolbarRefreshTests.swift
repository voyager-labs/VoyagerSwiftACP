import ComposableArchitecture
import Foundation
@testable import Voyager
import XCTest

@MainActor
final class FileManagerToolbarRefreshTests: XCTestCase {
    func testRefreshStaleCollectionDispatchesSubmitForQueryCollections() async {
        let store = TestStore(initialState: makeState(query: "report", isDirty: false)) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.searchClient = .testValue
        }
        store.exhaustivity = .off

        XCTAssertNil(store.state.refreshBlockingReason)
        await store.send(.view(.refreshStaleCollection)) {
            $0.collectionSession.phase = .opened(kind: .definition, base: .stale, inflight: .refreshingHydratedSnapshot)
        }
        await store.receive { action in
            guard case .composer(.view(.setText("report"))) = action else {
                return false
            }
            return true
        }
        await store.receive { action in
            guard case .composer(.view(.submit)) = action else {
                return false
            }
            return true
        }
    }

    func testRefreshStaleCollectionDispatchesApplyFiltersForEmptyQueryCollections() async {
        let store = TestStore(initialState: makeState(query: "", isDirty: false)) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.searchClient = .testValue
        }
        store.exhaustivity = .off

        XCTAssertNil(store.state.refreshBlockingReason)
        await store.send(.view(.refreshStaleCollection)) {
            $0.collectionSession.phase = .opened(kind: .definition, base: .stale, inflight: .refreshingHydratedSnapshot)
        }
        await store.receive { action in
            guard case .composer(.view(.applyFilters)) = action else {
                return false
            }
            return true
        }
    }

    func testRefreshStaleCollectionDoesNothingWhenCollectionIsDirty() async {
        let store = TestStore(initialState: makeState(query: "report", isDirty: true)) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.searchClient = .testValue
        }
        store.exhaustivity = .off

        await store.send(.view(.refreshStaleCollection))

        XCTAssertEqual(store.state.refreshBlockingReason, .dirtyCollection)
        let inflightStatus = store.state.collectionSession.phase.inflightStatus
        XCTAssertNotEqual(inflightStatus, .refreshingHydratedSnapshot)
        XCTAssertNotEqual(inflightStatus, .writingBackRefreshedSnapshot)
    }

    func testRefreshStaleCollectionDoesNothingWithoutSavedCollectionPrerequisites() async {
        let store = TestStore(initialState: makeState(
            query: "report",
            isDirty: false,
            hasCollectionPrerequisites: false,
        )) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.searchClient = .testValue
        }
        store.exhaustivity = .off

        await store.send(.view(.refreshStaleCollection))

        XCTAssertEqual(store.state.refreshBlockingReason, .missingOpenedURL)
        let inflightStatus = store.state.collectionSession.phase.inflightStatus
        XCTAssertNotEqual(inflightStatus, .refreshingHydratedSnapshot)
        XCTAssertNotEqual(inflightStatus, .writingBackRefreshedSnapshot)
    }
}

@MainActor
private func makeState(
    query: String,
    isDirty: Bool,
    hasCollectionPrerequisites: Bool = true,
) -> FileManagerContentState {
    var state = FileManagerContentState()
    state.entryViewLayout.isCollectionMode = true
    state.collectionSession.phase = .opened(kind: .definition, base: .stale, inflight: .none)
    let baseline = CollectionContext(query: query, scopes: ["/tmp"], conditions: [])
    state.collectionSession.metadata.baseline = hasCollectionPrerequisites ? .init(context: baseline) : nil
    state.collectionSession.document = hasCollectionPrerequisites ? .init(
        url: URL(fileURLWithPath: "/tmp/demo.voycoll"),
        name: "demo",
        compatibility: nil,
    ) : nil
    state.collectionContext = hasCollectionPrerequisites
        ? (isDirty
            ? CollectionContext(query: query + "-dirty", scopes: ["/tmp"], conditions: [])
            : baseline)
        : nil
    state.composer.collectionContext = state.collectionContext
    state.composer.isCollectionMode = true
    state.composer.pendingSearchQuery = query.isEmpty ? nil : query
    return state
}
