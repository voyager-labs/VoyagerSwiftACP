import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesCollection
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

/// FileManager collection stale 전파와 상태 보존 계약을 검증한다.
@MainActor
final class FileManagerContentCollectionStaleTests: XCTestCase {
    /// testFileSystemChangedDoesNotMarkOpenCollectionStaleWithoutReload 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testFileSystemChangedDoesNotMarkOpenCollectionStaleWithoutReload() async {
        var initialState = FileManagerContentState()
        initialState.navigation.navigationState = .collection(
            .init(
                kind: .temporary,
                context: .init(query: "q", scopes: [], conditions: []),
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
            ),
        )
        initialState.collection.collectionSession.document = .init(
            url: URL(fileURLWithPath: "/tmp/voyager/sample.voycoll"),
            name: "sample",
            compatibility: nil,
        )
        initialState.collection.collectionSession.phase = .opened(kind: .definition, base: .ready, inflight: .none)

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.externalFileSystemChanged(["/tmp/voyager/a.txt"]))
        await store.finish()

        XCTAssertFalse(store.state.collection.collectionSession.phase.isStale)
        XCTAssertNil(store.state.collection.collectionSession.metadata.lastRefreshAt)
    }

    /// testFileSystemChangedDoesNotMarkCollectionStaleForUnrelatedScope 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testFileSystemChangedDoesNotMarkCollectionStaleForUnrelatedScope() async {
        var initialState = FileManagerContentState()
        initialState.navigation.navigationState = .collection(
            .init(
                kind: .temporary,
                context: .init(query: "q", scopes: [], conditions: []),
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
            ),
        )
        initialState.collection.collectionSession.document = .init(
            url: URL(fileURLWithPath: "/tmp/voyager/sample.voycoll"),
            name: "sample",
            compatibility: nil,
        )
        initialState.collection.collectionSession.phase = .opened(kind: .definition, base: .ready, inflight: .none)
        initialState.collection.collectionContext = .init(
            query: "q",
            scopes: ["/tmp/voyager"],
            conditions: [],
        )

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.externalFileSystemChanged(["/tmp/other/a.txt"]))
        await store.finish()
    }

    /// testFileSystemChangedDoesNotMarkCollectionStaleForSiblingCollectionDocument 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testFileSystemChangedDoesNotMarkCollectionStaleForSiblingCollectionDocument() async {
        var initialState = FileManagerContentState()
        initialState.navigation.navigationState = .collection(
            .init(
                kind: .file(url: URL(fileURLWithPath: "/tmp/voyager/sample.voycoll"), name: "sample"),
                context: .init(query: "q", scopes: ["/tmp/voyager"], conditions: []),
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
            ),
        )
        initialState.collection.collectionSession.document = .init(
            url: URL(fileURLWithPath: "/tmp/voyager/sample.voycoll"),
            name: "sample",
            compatibility: nil,
        )
        initialState.collection.collectionSession.phase = .opened(kind: .definition, base: .ready, inflight: .none)
        initialState.collection.collectionContext = .init(
            query: "q",
            scopes: ["/tmp/voyager"],
            conditions: [],
        )

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.externalFileSystemChanged(["/tmp/voyager/other.voycoll"]))
        await store.finish()
    }

    /// testFileSystemChangedDoesNotMarkCollectionStaleForMatchingScope 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testFileSystemChangedDoesNotMarkCollectionStaleForMatchingScope() async {
        var initialState = FileManagerContentState()
        initialState.navigation.navigationState = .collection(
            .init(
                kind: .temporary,
                context: .init(query: "q", scopes: [], conditions: []),
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
            ),
        )
        initialState.collection.collectionSession.document = .init(
            url: URL(fileURLWithPath: "/tmp/voyager/sample.voycoll"),
            name: "sample",
            compatibility: nil,
        )
        initialState.collection.collectionSession.phase = .opened(kind: .definition, base: .ready, inflight: .none)
        initialState.collection.collectionContext = .init(
            query: "q",
            scopes: ["/tmp/voyager"],
            conditions: [],
        )

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.externalFileSystemChanged(["/tmp/voyager/sub/a.txt"]))
        await store.finish()

        XCTAssertFalse(store.state.collection.collectionSession.phase.isStale)
        XCTAssertNil(store.state.collection.collectionSession.metadata.lastRefreshAt)
    }

    /// testFileSystemChangedDoesNotReopenRefreshBoundaryForStaleCollection 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testFileSystemChangedDoesNotReopenRefreshBoundaryForStaleCollection() async {
        var initialState = FileManagerContentState()
        initialState.navigation.navigationState = .collection(
            .init(
                kind: .temporary,
                context: .init(query: "q", scopes: [], conditions: []),
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
            ),
        )
        initialState.collection.collectionSession.document = .init(
            url: URL(fileURLWithPath: "/tmp/voyager/sample.voycoll"),
            name: "sample",
            compatibility: nil,
        )
        initialState.collection.collectionSession.phase = .opened(kind: .definition, base: .ready, inflight: .none)
        initialState.collection.collectionSession.metadata.lastRefreshAt = .distantFuture
        initialState.collection.collectionContext = .init(
            query: "q",
            scopes: ["/tmp/voyager"],
            conditions: [],
        )

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.externalFileSystemChanged(["/tmp/voyager/sub/a.txt"]))
        await store.finish()

        XCTAssertFalse(store.state.collection.collectionSession.phase.isStale)
        XCTAssertEqual(store.state.collection.collectionSession.metadata.lastRefreshAt, .distantFuture)
    }

    /// testFileSystemChangedKeepsDirtyStateWhileInvalidatingCollection 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testFileSystemChangedKeepsDirtyStateWhileInvalidatingCollection() async {
        var initialState = FileManagerContentState()
        initialState.entryViewLayout.isCollectionMode = true
        initialState.navigation.navigationState = .collection(
            .init(
                kind: .temporary,
                context: .init(query: "report", scopes: ["/tmp/voyager"], conditions: []),
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
            ),
        )
        initialState.collection.collectionSession.document = .init(
            url: URL(fileURLWithPath: "/tmp/voyager/sample.voycoll"),
            name: "sample",
            compatibility: nil,
        )
        initialState.collection.collectionContext = .init(query: "report", scopes: ["/tmp/voyager"], conditions: [])
        initialState.collection.collectionSession.metadata.lastRefreshAt = .distantFuture
        initialState.collection.collectionSession.metadata.baseline = .init(
            context: .init(query: "before", scopes: ["/tmp/voyager"], conditions: []),
        )
        initialState.collection.collectionContext = .init(query: "after", scopes: ["/tmp/voyager"], conditions: [])

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        XCTAssertTrue(store.state.isOpenedCollectionDirty)
        XCTAssertEqual(store.state.collection.refreshBlockingReason(
            isCollectionMode: store.state.isCollectionMode,
            isDirty: store.state.isOpenedCollectionDirty,
            isSearching: store.state.composer.isCollectionSearching,
        ), .notStale)

        await store.send(.externalFileSystemChanged(["/tmp/voyager/sub/a.txt"]))
        await store.finish()

        XCTAssertTrue(store.state.isOpenedCollectionDirty)
        XCTAssertFalse(store.state.collection.collectionSession.phase.isStale)
        XCTAssertEqual(store.state.collection.collectionSession.metadata.lastRefreshAt, .distantFuture)
        XCTAssertEqual(store.state.collection.refreshBlockingReason(
            isCollectionMode: store.state.isCollectionMode,
            isDirty: store.state.isOpenedCollectionDirty,
            isSearching: store.state.composer.isCollectionSearching,
        ), .notStale)
    }

    /// testFileSystemChangedPreservesExistingRefreshMarker 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testFileSystemChangedPreservesExistingRefreshMarker() async {
        var initialState = FileManagerContentState()
        initialState.entryViewLayout.isCollectionMode = true
        initialState.navigation.navigationState = .collection(
            .init(
                kind: .temporary,
                context: .init(query: "report", scopes: ["/tmp/voyager"], conditions: []),
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
            ),
        )
        initialState.collection.collectionSession.document = .init(
            url: URL(fileURLWithPath: "/tmp/voyager/sample.voycoll"),
            name: "sample",
            compatibility: nil,
        )
        initialState.collection.collectionContext = .init(query: "report", scopes: ["/tmp/voyager"], conditions: [])
        initialState.collection.collectionSession.phase = .opened(kind: .definition, base: .stale, inflight: .none)
        initialState.collection.collectionSession.metadata.lastRefreshAt = .distantFuture

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.externalFileSystemChanged(["/tmp/voyager/sub/a.txt"]))
        await store.finish()

        XCTAssertTrue(store.state.collection.collectionSession.phase.isStale)
        XCTAssertEqual(store.state.collection.collectionSession.metadata.lastRefreshAt, .distantFuture)
    }
}
