import ComposableArchitecture
@testable import Voyager
@testable import VoyagerPagesFileManager
import struct VoyagerEntitiesCollection.CollectionContext
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import VoyagerShared
import XCTest

@MainActor
final class FileManagerContentExternalReloadTests: XCTestCase {
    private func extractLoadItems(from action: FileManagerContentAction) -> (path: String, showHidden: Bool)? {
        let evAction = (/FileManagerContentAction.entryViewLayout).extract(from: action)
        let eoAction = evAction.flatMap { (/EntryViewLayoutFeature.Action.entryOperations).extract(from: $0) }
        let loadingAction = eoAction.flatMap { (/EntryOperationsAction.loading).extract(from: $0) }
        guard let loadingAction, case let .loadItems(path, showHidden) = loadingAction else { return nil }
        return (path, showHidden)
    }

    private func extractLoadRecentItems(from action: FileManagerContentAction) -> Bool? {
        let evAction = (/FileManagerContentAction.entryViewLayout).extract(from: action)
        let eoAction = evAction.flatMap { (/EntryViewLayoutFeature.Action.entryOperations).extract(from: $0) }
        let loadingAction = eoAction.flatMap { (/EntryOperationsAction.loading).extract(from: $0) }
        guard let loadingAction, case let .loadRecentItems(showHidden) = loadingAction else { return nil }
        return showHidden
    }

    private func extractLoadTagItems(from action: FileManagerContentAction) -> (tagName: String, showHidden: Bool)? {
        let evAction = (/FileManagerContentAction.entryViewLayout).extract(from: action)
        let eoAction = evAction.flatMap { (/EntryViewLayoutFeature.Action.entryOperations).extract(from: $0) }
        let loadingAction = eoAction.flatMap { (/EntryOperationsAction.loading).extract(from: $0) }
        guard let loadingAction, case let .loadTagItems(tagName, showHidden) = loadingAction else { return nil }
        return (tagName, showHidden)
    }

    private func isLoadComputerItems(_ action: FileManagerContentAction) -> Bool {
        let evAction = (/FileManagerContentAction.entryViewLayout).extract(from: action)
        let eoAction = evAction.flatMap { (/EntryViewLayoutFeature.Action.entryOperations).extract(from: $0) }
        let loadingAction = eoAction.flatMap { (/EntryOperationsAction.loading).extract(from: $0) }
        guard let loadingAction, case .loadComputerItems = loadingAction else { return false }
        return true
    }

    func testFileSystemChangedReloadsCurrentFolderForDirectChildPath() async {
        var initialState = FileManagerContentState()
        initialState.navigation.seedInitialFolderPath("/tmp/voyager")

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        store.exhaustivity = .off

        await store.send(.externalFileSystemChanged(["/tmp/voyager/a.txt"]))
        await store.receive { action in
            guard let result = self.extractLoadItems(from: action) else { return false }
            return result.path == "/tmp/voyager" && !result.showHidden
        }
    }

    func testFileSystemChangedReloadsCurrentFolderForNestedPath() async {
        var initialState = FileManagerContentState()
        initialState.navigation.seedInitialFolderPath("/tmp/voyager")

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        store.exhaustivity = .off

        await store.send(.externalFileSystemChanged(["/tmp/voyager/subdir/a.txt"]))
        await store.receive { action in
            guard let result = self.extractLoadItems(from: action) else { return false }
            return result.path == "/tmp/voyager" && !result.showHidden
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

        store.exhaustivity = .off

        await store.send(.externalFileSystemChanged(["/tmp/voyager/a.txt"]))
        await store.receive { action in
            guard let showHidden = self.extractLoadRecentItems(from: action) else { return false }
            return !showHidden
        }
    }

    func testFileSystemChangedReloadsTagRoute() async {
        var initialState = FileManagerContentState()
        initialState.navigation.navigationState = .tags("blue")

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        store.exhaustivity = .off

        await store.send(.externalFileSystemChanged(["/tmp/voyager/a.txt"]))
        await store.receive { action in
            guard let result = self.extractLoadTagItems(from: action) else { return false }
            return result.tagName == "blue" && !result.showHidden
        }
    }

    func testFileSystemChangedReloadsComputerRoute() async {
        var initialState = FileManagerContentState()
        initialState.navigation.navigationState = .computer

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        store.exhaustivity = .off

        await store.send(.externalFileSystemChanged(["/tmp/voyager/a.txt"]))
        await store.receive { action in
            self.isLoadComputerItems(action)
        }
    }
}
