import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
final class FileManagerContentSyncReducerTests: XCTestCase {
    func testExternalChangeReloadsRecentsRoute() async {
        var state = FileManagerContentState()
        state.navigation.navigationState = .recents
        state.entryViewLayout.showHiddenFiles = true
        let store = makeStore(initialState: state)

        await store.send(.externalFileSystemChanged(["/Users/test/file.txt"]))
        await store.receive(\.entryViewLayout.entryOperations.loading.loadRecentItems, true)
    }

    func testExternalChangeReloadsTagsRoute() async {
        var state = FileManagerContentState()
        state.navigation.navigationState = .tags("Work")
        let store = makeStore(initialState: state)

        await store.send(.externalFileSystemChanged(["/Users/test/file.txt"]))
        await store.receive(\.entryViewLayout.entryOperations.loading.loadTagItems)
    }

    func testExternalChangeIgnoresOpenedCollectionDocumentPath() async {
        let collectionURL = URL(fileURLWithPath: "/Users/test/Collections/Work.voyagercollection")
        var state = FileManagerContentState()
        state.navigation.navigationState = .collection(.init(
            kind: .file(url: collectionURL, name: "Work"),
            context: CollectionContext(query: "", scopes: [], conditions: []),
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        ))
        state.collection.collectionSession.document = .init(url: collectionURL, name: "Work")
        let store = makeStore(initialState: state)

        await store.send(.externalFileSystemChanged([
            collectionURL.path,
            collectionURL.appendingPathComponent("metadata.json").path,
        ]))
    }

    func testFolderNavigationStartsWatcherAndForwardsExternalChanges() async {
        let currentPath = "/Users/test/Folder"
        let changedPath = "/Users/test/Folder/new.txt"
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder(currentPath)
        let store = TestStore(initialState: state) {
            FileManagerContentNavigationBridgeReducer()
        } withDependencies: {
            $0.entryWatchingClient.startWatchingDirectory = { url in
                XCTAssertEqual(url.path, currentPath)
                return AsyncStream { continuation in
                    continuation.yield([changedPath])
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.internal(.applyNavigationState(.folder(currentPath))))
        await store.receive(\.entryViewLayout.internal.clearCollectionPresentation)
        await store.receive(\.entryViewLayout.entryOperations.loading.loadItems)
        await store.receive(\.externalFileSystemChanged, [changedPath])
    }

    func testExternalFolderChildChangeReloadsCurrentFolder() async {
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder("/Users/test/Folder")
        state.entryViewLayout.showHiddenFiles = true
        let store = makeStore(initialState: state)

        await store.send(.externalFileSystemChanged(["/Users/test/Folder/new.txt"]))
        await store.receive(\.entryViewLayout.entryOperations.loading.loadItems)
    }

    func testExternalSiblingChangeDoesNotReloadCurrentFolder() async {
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder("/Users/test/Folder")
        let store = makeStore(initialState: state)

        await store.send(.externalFileSystemChanged(["/Users/test/Other/file.txt"]))
    }

    private func makeStore(initialState: FileManagerContentState)
        -> TestStore<FileManagerContentState, FileManagerContentAction>
    {
        TestStore(initialState: initialState) {
            FileManagerContentSyncReducer()
        }
    }
}
