import ComposableArchitecture
import Foundation
@testable import Voyager
import XCTest

@MainActor
final class FileManagerContentRenameLifecycleTests: XCTestCase {
    func testChangeLayoutCancelsActiveRenameWhenSwitchingListToGrid() async {
        let entry = makeEntry(name: "TestFile.txt", fullPath: "/tmp/voyager/TestFile.txt")

        var initialState = FileManagerContentState()
        initialState.entryViewLayout.mode = .list
        initialState.navigation.seedInitialFolderPath("/tmp/voyager")
        initialState.entryViewLayout.entries = [entry]
        initialState.entryViewLayout.entryOperations.renamingItemId = entry.id
        initialState.entryViewLayout.entryOperations.renamingText = "TestFile"

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }
        store.exhaustivity = .off

        await store.send(.view(.changeLayout(.grid))) {
            $0.entryViewLayout.mode = .grid
        }

        await store.receive { action in
            guard case .entryViewLayout(.entryOperations(.edit(.cancelRename))) = action else { return false }
            return true
        }

        await store.finish()
    }

    func testChangeLayoutCancelsActiveRenameWhenSwitchingGridToList() async {
        let entry = makeEntry(name: "TestFile.txt", fullPath: "/tmp/voyager/TestFile.txt")

        var initialState = FileManagerContentState()
        initialState.entryViewLayout.mode = .grid
        initialState.navigation.seedInitialFolderPath("/tmp/voyager")
        initialState.entryViewLayout.entries = [entry]
        initialState.entryViewLayout.entryOperations.renamingItemId = entry.id
        initialState.entryViewLayout.entryOperations.renamingText = "TestFile"

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }
        store.exhaustivity = .off

        await store.send(.view(.changeLayout(.list))) {
            $0.entryViewLayout.mode = .list
        }

        await store.receive { action in
            guard case .entryViewLayout(.entryOperations(.edit(.cancelRename))) = action else { return false }
            return true
        }

        await store.finish()
    }

    func testChangeLayoutDoesNotCancelWhenTargetLayoutMatchesCurrentMode() async {
        let entry = makeEntry(name: "TestFile.txt", fullPath: "/tmp/voyager/TestFile.txt")

        var initialState = FileManagerContentState()
        initialState.entryViewLayout.mode = .list
        initialState.navigation.seedInitialFolderPath("/tmp/voyager")
        initialState.entryViewLayout.entries = [entry]
        initialState.entryViewLayout.entryOperations.renamingItemId = entry.id
        initialState.entryViewLayout.entryOperations.renamingText = "TestFile"

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }
        store.exhaustivity = .off

        await store.send(.view(.changeLayout(.list))) {
            $0.entryViewLayout.mode = .list
        }

        await store.finish()
    }

    private func makeEntry(
        name: String,
        fullPath: String,
        isFolder: Bool = false,
        fileExtension: String = "txt",
    ) -> EntryModel {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return EntryModel(
            name: name,
            fullPath: fullPath,
            isFolder: isFolder,
            isHidden: false,
            size: 1,
            modifiedDate: date,
            fileExtension: fileExtension,
            facets: EntryFacets(
                createdDate: date,
                addedDate: date,
                lastOpenedDate: nil,
                kind: isFolder ? "Folder" : "Text",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
    }
}
