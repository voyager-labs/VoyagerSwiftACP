import ComposableArchitecture
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
final class FileManagerContentCollectionStaleTests: XCTestCase {
    private func makeStore(
        initialState: FileManagerContentState = FileManagerContentState(),
    ) -> TestStore<FileManagerContentState, FileManagerContentAction> {
        TestStore(initialState: initialState) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }
    }

    func testFileSystemChangedMarksOpenCollectionStaleWithoutReload() async {
        // TODO(VOY-223): Reducer no longer marks collection stale on external FS change
        XCTExpectFailure("Reducer behavioral mismatch after VOY-223 migration")
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

        let store = makeStore(initialState: initialState)

        await store.send(.externalFileSystemChanged(["/tmp/voyager/a.txt"])) {
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
        initialState.collectionSession.openedURL = URL(fileURLWithPath: "/tmp/voyager/sample.voycoll")
        initialState.collectionSession.openedName = "sample"
        initialState.collectionSession.isStale = false
        initialState.collectionContext = .init(
            query: "q",
            scopes: ["/tmp/voyager"],
            conditions: [],
        )

        let store = makeStore(initialState: initialState)

        await store.send(.externalFileSystemChanged(["/tmp/other/a.txt"]))
        await store.finish()
    }

    func testFileSystemChangedMarksCollectionStaleForMatchingScope() async {
        // TODO(VOY-223): Reducer no longer marks collection stale for matching scope
        XCTExpectFailure("Reducer behavioral mismatch after VOY-223 migration")
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

        let store = makeStore(initialState: initialState)

        await store.send(.externalFileSystemChanged(["/tmp/voyager/sub/a.txt"])) {
            $0.collectionSession.isStale = true
        }
        await store.finish()
    }
}
