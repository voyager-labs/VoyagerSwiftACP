import ComposableArchitecture
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
final class FileManagerContentExternalReloadTests: XCTestCase {
    func testFileSystemChangedReloadsCurrentFolderForDirectChildPath() async {
        var initialState = FileManagerContentState()
        initialState.navigation.seedInitialFolderPath("/tmp/voyager")

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.entries(.fileSystemChanged(["/tmp/voyager/a.txt"])))
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loadItems(path: path, showHidden: showHidden))) = action
            else {
                return false
            }
            return path == "/tmp/voyager" && showHidden == false
        }
    }

    func testFileSystemChangedReloadsCurrentFolderForNestedPath() async {
        var initialState = FileManagerContentState()
        initialState.navigation.seedInitialFolderPath("/tmp/voyager")

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.entries(.fileSystemChanged(["/tmp/voyager/subdir/a.txt"])))
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loadItems(path: path, showHidden: showHidden))) = action
            else {
                return false
            }
            return path == "/tmp/voyager" && showHidden == false
        }
    }

    func testFileSystemChangedDoesNotReloadUnrelatedFolder() async {
        var initialState = FileManagerContentState()
        initialState.navigation.seedInitialFolderPath("/tmp/voyager")

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.entries(.fileSystemChanged(["/tmp/other/a.txt"])))
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
        initialState.navigation.currentPath = "Collection"

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.entries(.fileSystemChanged(["/tmp/voyager/a.txt"])))
        await store.finish()
    }

    func testFileSystemChangedReloadsRecentsRoute() async {
        var initialState = FileManagerContentState()
        initialState.navigation.navigationState = .recents
        initialState.navigation.currentPath = "Recents"

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.entries(.fileSystemChanged(["/tmp/voyager/a.txt"])))
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loadRecentItems(showHidden: showHidden))) = action
            else {
                return false
            }
            return showHidden == false
        }
    }

    func testFileSystemChangedReloadsTagRoute() async {
        var initialState = FileManagerContentState()
        initialState.navigation.navigationState = .tags(tagName: "blue")
        initialState.navigation.currentPath = "Tags"

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.entries(.fileSystemChanged(["/tmp/voyager/a.txt"])))
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loadTagItems(tagName: tagName, showHidden: showHidden))) =
                action
            else {
                return false
            }
            return tagName == "blue" && showHidden == false
        }
    }

    func testFileSystemChangedReloadsComputerRoute() async {
        var initialState = FileManagerContentState()
        initialState.navigation.navigationState = .computer
        initialState.navigation.currentPath = "Computer"

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.entries(.fileSystemChanged(["/tmp/voyager/a.txt"])))
        await store.receive { action in
            guard case .entryViewLayout(.entryOperations(.loadComputerItems)) = action else {
                return false
            }
            return true
        }
    }
}
