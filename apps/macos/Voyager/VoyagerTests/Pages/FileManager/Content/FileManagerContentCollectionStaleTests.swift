import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
final class FileManagerContentCollectionStaleTests: XCTestCase {
    func testFileSystemChangedMarksOpenCollectionStaleWithoutReload() async {
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
        initialState.navigation.currentPath = "Collection"
        initialState.collectionSession.openedURL = URL(fileURLWithPath: "/tmp/voyager/sample.voycoll")
        initialState.collectionSession.openedName = "sample"
        initialState.collectionSession.isStale = false

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.entries(.fileSystemChanged(["/tmp/voyager/a.txt"]))) {
            $0.collectionSession.isStale = true
        }
        await store.finish()
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
        initialState.navigation.currentPath = "Collection"
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

        await store.send(.entries(.fileSystemChanged(["/tmp/other/a.txt"])))
        await store.finish()
    }

    func testFileSystemChangedMarksCollectionStaleForMatchingScope() async {
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
        initialState.navigation.currentPath = "Collection"
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

        await store.send(.entries(.fileSystemChanged(["/tmp/voyager/sub/a.txt"]))) {
            $0.collectionSession.isStale = true
        }
        await store.finish()
    }
}
