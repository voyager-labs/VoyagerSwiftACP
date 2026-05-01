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

        await store.send(.externalFileSystemChanged(["/tmp/voyager/a.txt"]))
        await store.receive { action in
            let description = String(describing: action)
            return description.contains("loadItems")
                && description.contains("/tmp/voyager")
                && description.contains("false")
        }
    }

    func testFileSystemChangedReloadsCurrentFolderForNestedPath() async {
        var initialState = FileManagerContentState()
        initialState.navigation.seedInitialFolderPath("/tmp/voyager")

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.externalFileSystemChanged(["/tmp/voyager/subdir/a.txt"]))
        await store.receive { action in
            let description = String(describing: action)
            return description.contains("loadItems")
                && description.contains("/tmp/voyager")
                && description.contains("false")
        }
    }

    func testFileSystemChangedDoesNotReloadUnrelatedFolder() async {
        var initialState = FileManagerContentState()
        initialState.navigation.seedInitialFolderPath("/tmp/voyager")

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.externalFileSystemChanged(["/tmp/other/a.txt"]))
        await store.finish()
    }

    func testFileSystemChangedDoesNotReloadCollectionRoute() async {
        var initialState = FileManagerContentState()
        initialState.navigation.navigationState = .collection(
            .init(
                kind: .temporary,
                context: .init(query: "q", scopes: [], includeSubfolders: true, conditions: []),
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
            ),
        )

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.externalFileSystemChanged(["/tmp/voyager/a.txt"]))
        await store.finish()
    }

    func testFileSystemChangedReloadsRecentsRoute() async {
        var initialState = FileManagerContentState()
        initialState.navigation.navigationState = .recents

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.externalFileSystemChanged(["/tmp/voyager/a.txt"]))
        await store.receive { action in
            let description = String(describing: action)
            return description.contains("loadRecentItems") && description.contains("false")
        }
    }

    func testFileSystemChangedReloadsTagRoute() async {
        var initialState = FileManagerContentState()
        initialState.navigation.navigationState = .tags("blue")

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.externalFileSystemChanged(["/tmp/voyager/a.txt"]))
        await store.receive { action in
            let description = String(describing: action)
            return description.contains("loadTagItems")
                && description.contains("blue")
                && description.contains("false")
        }
    }

    func testFileSystemChangedReloadsComputerRoute() async {
        var initialState = FileManagerContentState()
        initialState.navigation.navigationState = .computer

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.externalFileSystemChanged(["/tmp/voyager/a.txt"]))
        await store.receive { action in
            String(describing: action).contains("loadComputerItems")
        }
    }
}
