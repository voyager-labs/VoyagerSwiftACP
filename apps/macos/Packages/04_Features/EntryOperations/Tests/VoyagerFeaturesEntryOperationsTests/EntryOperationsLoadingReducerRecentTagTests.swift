import ComposableArchitecture
import Foundation
import IdentifiedCollections
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
@testable import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
final class EntryOperationsRecentTagTests: XCTestCase {
    /// 최근 항목 로드 성공 시 항목이 채워지고 로딩 상태가 해제되는지 검증
    func testLoadRecentItemsSuccessLoadsItemsAndResetsLoading() async {
        let item = makeEntry(path: "/tmp/recent.txt")

        let store = TestStore(initialState: EntryOperationsState()) {
            EntryOperationsLoadingReducer()
        } withDependencies: {
            $0.entryLoadingClient.loadRecentItems = { _, _ in [item] }
            $0.workspaceClient = .testValue
        }

        await store.send(.loading(.loadRecentItems(showHidden: false))) {
            $0.isLoading = true
        }
        await store.receive(\.loading.itemsLoaded) {
            $0.loadingContext.items = IdentifiedArray(uniqueElements: [item])
            $0.isLoading = false
            $0.isReloading = false
        }
    }

    /// 태그 항목이 비어 있어도 결과가 결정적으로 빈 배열로 정리되는지 검증
    func testLoadTagItemsEmptyResultIsDeterministic() async {
        let store = TestStore(initialState: EntryOperationsState()) {
            EntryOperationsLoadingReducer()
        } withDependencies: {
            $0.entryLoadingClient.loadFilesWithTag = { _, _, _ in [] }
            $0.workspaceClient = .testValue
        }

        await store.send(.loading(.loadTagItems(tagName: "Work", showHidden: false))) {
            $0.isLoading = true
        }
        await store.receive(\.loading.itemsLoaded) {
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
