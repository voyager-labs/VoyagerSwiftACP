import ComposableArchitecture
import Foundation
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

    private func makeStore(initialState: FileManagerContentState)
        -> TestStore<FileManagerContentState, FileManagerContentAction>
    {
        TestStore(initialState: initialState) {
            FileManagerContentSyncReducer()
        }
    }
}
