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
        var initialState = FileManagerContentState()
        initialState.navigation.seedInitialFolderPath("/tmp/voyager")

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

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
                context: .init(query: "q", scopes: [], conditions: []),
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
            guard case let .entryViewLayout(.entryOperations(.loading(.loadRecentItems(showHidden: showHidden)))) =
                action
            else {
                return false
            }
            return showHidden == false
        }
    }

    func testFileSystemChangedReloadsTagRoute() async {
        var initialState = FileManagerContentState()
        initialState.navigation.navigationState = .tags(tagName: "blue")

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.externalFileSystemChanged(["/tmp/voyager/a.txt"]))
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loading(.loadTagItems(
                tagName: tagName,
                showHidden: showHidden,
            )))) =
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

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.externalFileSystemChanged(["/tmp/voyager/a.txt"]))
        await store.receive { action in
            guard case .entryViewLayout(.entryOperations(.loading(.loadComputerItems))) = action else {
                return false
            }
            return true
        }
    }
}
