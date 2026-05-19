import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
/// FileManager content 리네임 라이프사이클에서 레이아웃 전환과 rename 상태 소유권 계약을 검증한다.
final class FileManagerContentRenameLifecycleTests: XCTestCase {
    /// testChangeLayoutCancelsActiveRenameWhenSwitchingListToGrid 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
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

    /// testChangeLayoutCancelsActiveRenameWhenSwitchingGridToList 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
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

    /// testChangeLayoutDoesNotCancelWhenTargetLayoutMatchesCurrentMode 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
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
