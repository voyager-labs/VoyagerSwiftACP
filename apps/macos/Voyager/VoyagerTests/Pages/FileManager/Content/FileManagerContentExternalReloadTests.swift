import ComposableArchitecture
@testable import Voyager
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
}
