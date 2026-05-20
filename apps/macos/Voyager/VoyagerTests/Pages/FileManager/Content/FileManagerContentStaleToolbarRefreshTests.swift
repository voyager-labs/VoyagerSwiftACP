import ComposableArchitecture
import Foundation
@testable import Voyager
@testable import VoyagerPagesFileManager
import VoyagerEntitiesCollection
import VoyagerFeaturesComposer
import XCTest

@MainActor
/// FileManager content stale 상태에서 툴바 리프레시 라우팅 계약을 검증한다.
final class FileManagerToolbarRefreshTests: XCTestCase {
    /// testRefreshStaleCollectionDispatchesSubmitForQueryCollections 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testRefreshStaleCollectionDispatchesSubmitForQueryCollections() async {
        let store = TestStore(initialState: makeState(query: "report", isDirty: false)) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.searchClient = .testValue
        }
        store.exhaustivity = .off

        XCTAssertNil(store.state.collection.refreshBlockingReason(
            isCollectionMode: store.state.isCollectionMode,
            isDirty: store.state.isOpenedCollectionDirty,
            isSearching: store.state.composer.isCollectionSearching,
        ))
        await store.send(.view(.refreshStaleCollection)) {
            $0.collection.collectionSession.phase = .opened(
                kind: .definition,
                base: .stale,
                inflight: .refreshingHydratedSnapshot,
            )
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

    /// testRefreshStaleCollectionDispatchesApplyFiltersForEmptyQueryCollections 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testRefreshStaleCollectionDispatchesApplyFiltersForEmptyQueryCollections() async {
        let store = TestStore(initialState: makeState(query: "", isDirty: false)) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.searchClient = .testValue
        }
        store.exhaustivity = .off

        XCTAssertNil(store.state.collection.refreshBlockingReason(
            isCollectionMode: store.state.isCollectionMode,
            isDirty: store.state.isOpenedCollectionDirty,
            isSearching: store.state.composer.isCollectionSearching,
        ))
        await store.send(.view(.refreshStaleCollection)) {
            $0.collection.collectionSession.phase = .opened(
                kind: .definition,
                base: .stale,
                inflight: .refreshingHydratedSnapshot,
            )
        }
        await store.receive { action in
            guard case .composer(.view(.applyFilters)) = action else {
                return false
            }
            return true
        }
    }

    /// testRefreshStaleCollectionDoesNothingWhenCollectionIsDirty 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testRefreshStaleCollectionDoesNothingWhenCollectionIsDirty() async {
        let store = TestStore(initialState: makeState(query: "report", isDirty: true)) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.searchClient = .testValue
        }
        store.exhaustivity = .off

        await store.send(.view(.refreshStaleCollection))

        XCTAssertEqual(store.state.collection.refreshBlockingReason(
            isCollectionMode: store.state.isCollectionMode,
            isDirty: store.state.isOpenedCollectionDirty,
            isSearching: store.state.composer.isCollectionSearching,
        ), .dirtyCollection)
        XCTAssertNotEqual(store.state.collection.collectionSession.phase.inflightStatus, .refreshingHydratedSnapshot)
        XCTAssertNotEqual(store.state.collection.collectionSession.phase.inflightStatus, .writingBackRefreshedSnapshot)
    }

    /// testRefreshStaleCollectionDoesNothingWithoutSavedCollectionPrerequisites 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
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

        XCTAssertEqual(store.state.collection.refreshBlockingReason(
            isCollectionMode: store.state.isCollectionMode,
            isDirty: store.state.isOpenedCollectionDirty,
            isSearching: store.state.composer.isCollectionSearching,
        ), .missingOpenedURL)
        XCTAssertNotEqual(store.state.collection.collectionSession.phase.inflightStatus, .refreshingHydratedSnapshot)
        XCTAssertNotEqual(store.state.collection.collectionSession.phase.inflightStatus, .writingBackRefreshedSnapshot)
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
    state.collection.collectionSession.phase = .opened(kind: .definition, base: .stale, inflight: .none)
    let baseline = CollectionContext(query: query, scopes: ["/tmp"], conditions: [])
    state.collection.collectionSession.metadata.baseline = hasCollectionPrerequisites ? .init(context: baseline) : nil
    if hasCollectionPrerequisites {
        state.collection.collectionSession.document = .init(
            url: URL(fileURLWithPath: "/tmp/demo.voycoll"),
            name: "demo",
            compatibility: nil,
        )
    }
    state.collection.collectionContext = hasCollectionPrerequisites
        ? (isDirty
            ? CollectionContext(query: query + "-dirty", scopes: ["/tmp"], conditions: [])
            : baseline)
        : nil
    state.syncComposerCollectionState()
    state.composer.pendingSearchQuery = query.isEmpty ? nil : query
    return state
}
