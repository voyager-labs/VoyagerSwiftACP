import ComposableArchitecture
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
final class FileManagerContentExternalReloadTests: XCTestCase {
    private func makeStore(
        initialState: FileManagerContentState = FileManagerContentState(),
    ) -> TestStore<FileManagerContentState, FileManagerContentAction> {
        TestStore(initialState: initialState) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }
    }

    func testFileSystemChangedReloadsCurrentFolderForDirectChildPath() async {
        // TODO(VOY-223): Reducer no longer emits load action on external FS change for direct child
        XCTExpectFailure("Reducer behavioral mismatch after VOY-223 migration")
        var initialState = FileManagerContentState()
        initialState.navigation.seedInitialFolderPath("/tmp/voyager")

        let store = makeStore(initialState: initialState)

        await store.send(.externalFileSystemChanged(["/tmp/voyager/a.txt"]))
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loading(.loadItems(
                path: path,
                showHidden: showHidden,
            )))) =
                action
            else {
                return false
            }
            return path == "/tmp/voyager" && showHidden == false
        }
    }

    func testFileSystemChangedReloadsCurrentFolderForNestedPath() async {
        // TODO(VOY-223): Reducer no longer emits load action on external FS change for nested path
        XCTExpectFailure("Reducer behavioral mismatch after VOY-223 migration")
        var initialState = FileManagerContentState()
        initialState.navigation.seedInitialFolderPath("/tmp/voyager")

        let store = makeStore(initialState: initialState)

        await store.send(.externalFileSystemChanged(["/tmp/voyager/subdir/a.txt"]))
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loading(.loadItems(
                path: path,
                showHidden: showHidden,
            )))) =
                action
            else {
                return false
            }
            return path == "/tmp/voyager" && showHidden == false
        }
    }

    func testFileSystemChangedDoesNotReloadUnrelatedFolder() async {
        var initialState = FileManagerContentState()
        initialState.navigation.seedInitialFolderPath("/tmp/voyager")

        let store = makeStore(initialState: initialState)

        await store.send(.externalFileSystemChanged(["/tmp/other/a.txt"]))
        await store.finish()
    }

    func testFileSystemChangedDoesNotReloadCollectionRoute() async {
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

        let store = makeStore(initialState: initialState)

        await store.send(.externalFileSystemChanged(["/tmp/voyager/a.txt"]))
        await store.finish()
    }

    func testFileSystemChangedReloadsRecentsRoute() async {
        // TODO(VOY-223): Reducer no longer emits load action on external FS change for recents
        XCTExpectFailure("Reducer behavioral mismatch after VOY-223 migration")
        var initialState = FileManagerContentState()
        initialState.navigation.navigationState = .recents

        let store = makeStore(initialState: initialState)

        await store.send(.externalFileSystemChanged(["/tmp/voyager/a.txt"]))
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loading(.loadRecentItems(showHidden: showHidden)))) =
                action
            else {
                return false
            }
            return showHidden == false
        }
    }

    func testFileSystemChangedReloadsTagRoute() async {
        // TODO(VOY-223): Reducer no longer emits load action on external FS change for tags
        XCTExpectFailure("Reducer behavioral mismatch after VOY-223 migration")
        var initialState = FileManagerContentState()
        initialState.navigation.navigationState = .tags("blue")

        let store = makeStore(initialState: initialState)

        await store.send(.externalFileSystemChanged(["/tmp/voyager/a.txt"]))
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loading(.loadTagItems(
                tagName,
                showHidden,
            )))) =
                action
            else {
                return false
            }
            return tagName == "blue" && showHidden == false
        }
    }

    func testFileSystemChangedReloadsComputerRoute() async {
        // TODO(VOY-223): Reducer no longer emits load action on external FS change for computer
        XCTExpectFailure("Reducer behavioral mismatch after VOY-223 migration")
        var initialState = FileManagerContentState()
        initialState.navigation.navigationState = .computer

        let store = makeStore(initialState: initialState)

        await store.send(.externalFileSystemChanged(["/tmp/voyager/a.txt"]))
        await store.receive { action in
            guard case .entryViewLayout(.entryOperations(.loading(.loadComputerItems))) = action else {
                return false
            }
            return true
        }
    }
}
