import ComposableArchitecture
import Foundation
import IdentifiedCollections
@testable import Voyager
import XCTest

@MainActor
final class EntryOperationsRecentTagTests: XCTestCase {
    func testLoadRecentItemsSuccessLoadsItemsAndResetsLoading() async {
        let item = makeEntry(path: "/tmp/recent.txt")

        let store = TestStore(initialState: EntryOperationsState()) {
            EntryOperationsLoadingReducer()
        } withDependencies: {
            $0.entryLoadingClient.loadRecentItems = { _, _ in [item] }
            $0.workspaceClient = .testValue
        }

        await store.send(.loadRecentItems(showHidden: false)) {
            $0.isLoading = true
        }
        await store.receive(\.itemsLoaded) {
            $0.loadingContext.items = IdentifiedArray(uniqueElements: [item])
            $0.isLoading = false
            $0.isReloading = false
        }
    }

    func testLoadTagItemsEmptyResultIsDeterministic() async {
        let store = TestStore(initialState: EntryOperationsState()) {
            EntryOperationsLoadingReducer()
        } withDependencies: {
            $0.entryLoadingClient.loadFilesWithTag = { _, _, _ in [] }
            $0.workspaceClient = .testValue
        }

        await store.send(.loadTagItems(tagName: "Work", showHidden: false)) {
            $0.isLoading = true
        }
        await store.receive(\.itemsLoaded) {
            $0.loadingContext.items = []
            $0.isLoading = false
            $0.isReloading = false
        }
    }

    private func makeEntry(path: String) -> EntryModel {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return EntryModel(
            name: URL(fileURLWithPath: path).lastPathComponent,
            fullPath: path,
            isFolder: false,
            isHidden: false,
            size: 1,
            modifiedDate: date,
            fileExtension: "txt",
            facets: EntryFacets(
                createdDate: date,
                addedDate: date,
                lastOpenedDate: date,
                kind: "Text",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
    }
}
