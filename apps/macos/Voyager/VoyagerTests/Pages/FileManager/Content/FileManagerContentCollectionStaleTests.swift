import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerShared
import XCTest

@MainActor
final class FileManagerContentCollectionStaleTests: XCTestCase {
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
        initialState.collectionSession.openedURL = URL(fileURLWithPath: "/tmp/voyager/sample.voycoll")
        initialState.collectionSession.openedName = "sample"
        initialState.collectionSession.isStale = false

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.externalFileSystemChanged(["/tmp/voyager/a.txt"]))
        await store.finish()

        XCTAssertFalse(store.state.collectionSession.isStale)
        XCTAssertNil(store.state.collectionSession.staleReason)
        XCTAssertNil(store.state.collectionSession.lastRefreshAt)
    }

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
        initialState.collectionSession.openedURL = URL(fileURLWithPath: "/tmp/voyager/sample.voycoll")
        initialState.collectionSession.openedName = "sample"
        initialState.collectionSession.isStale = false
        initialState.collectionContext = .init(
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
        initialState.collectionSession.openedURL = URL(fileURLWithPath: "/tmp/voyager/sample.voycoll")
        initialState.collectionSession.openedName = "sample"
        initialState.collectionSession.isStale = false
        initialState.collectionContext = .init(
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
        initialState.collectionSession.openedURL = URL(fileURLWithPath: "/tmp/voyager/sample.voycoll")
        initialState.collectionSession.openedName = "sample"
        initialState.collectionSession.isStale = false
        initialState.collectionContext = .init(
            query: "q",
            scopes: ["/tmp/voyager"],
            conditions: [],
        )

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.externalFileSystemChanged(["/tmp/voyager/sub/a.txt"]))
        await store.finish()

        XCTAssertFalse(store.state.collectionSession.isStale)
        XCTAssertNil(store.state.collectionSession.staleReason)
        XCTAssertNil(store.state.collectionSession.lastRefreshAt)
    }

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
        initialState.collectionSession.openedURL = URL(fileURLWithPath: "/tmp/voyager/sample.voycoll")
        initialState.collectionSession.openedName = "sample"
        initialState.collectionSession.isStale = false
        initialState.collectionSession.lastRefreshAt = .distantFuture
        initialState.collectionContext = .init(
            query: "q",
            scopes: ["/tmp/voyager"],
            conditions: [],
        )

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.externalFileSystemChanged(["/tmp/voyager/sub/a.txt"]))
        await store.finish()

        XCTAssertFalse(store.state.collectionSession.isStale)
        XCTAssertNil(store.state.collectionSession.staleReason)
        XCTAssertEqual(store.state.collectionSession.lastRefreshAt, .distantFuture)
    }

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
        initialState.collectionSession.openedURL = URL(fileURLWithPath: "/tmp/voyager/sample.voycoll")
        initialState.collectionSession.openedName = "sample"
        initialState.collectionContext = .init(query: "report", scopes: ["/tmp/voyager"], conditions: [])
        initialState.collectionSession.lastRefreshAt = .distantFuture
        initialState.collectionSession.baseline = .init(
            context: .init(query: "before", scopes: ["/tmp/voyager"], conditions: []),
        )
        initialState.collectionContext = .init(query: "after", scopes: ["/tmp/voyager"], conditions: [])

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        XCTAssertTrue(store.state.isOpenedCollectionDirty)
        XCTAssertEqual(store.state.collectionSessionRefreshBlockingReason, .notStale)

        await store.send(.externalFileSystemChanged(["/tmp/voyager/sub/a.txt"]))
        await store.finish()

        XCTAssertTrue(store.state.isOpenedCollectionDirty)
        XCTAssertFalse(store.state.collectionSession.isStale)
        XCTAssertNil(store.state.collectionSession.staleReason)
        XCTAssertEqual(store.state.collectionSession.lastRefreshAt, .distantFuture)
        XCTAssertEqual(store.state.collectionSessionRefreshBlockingReason, .notStale)
    }

    func testFileSystemChangedPreservesExistingStaleReasonWhileKeepingRefreshMarker() async {
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
        initialState.collectionSession.openedURL = URL(fileURLWithPath: "/tmp/voyager/sample.voycoll")
        initialState.collectionSession.openedName = "sample"
        initialState.collectionContext = .init(query: "report", scopes: ["/tmp/voyager"], conditions: [])
        initialState.collectionSession.isStale = true
        initialState.collectionSession.staleReason = .snapshotHydratedOnOpen
        initialState.collectionSession.lastRefreshAt = .distantFuture

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.externalFileSystemChanged(["/tmp/voyager/sub/a.txt"]))
        await store.finish()

        XCTAssertTrue(store.state.collectionSession.isStale)
        XCTAssertEqual(store.state.collectionSession.staleReason, .snapshotHydratedOnOpen)
        XCTAssertEqual(store.state.collectionSession.lastRefreshAt, .distantFuture)
    }
}
