import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
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

    private func makeStore(initialState: FileManagerContentState)
        -> TestStore<FileManagerContentState, FileManagerContentAction>
    {
        TestStore(initialState: initialState) {
            FileManagerContentSyncReducer()
        }
    }
}
