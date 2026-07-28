import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
extension EVM002ManageEntriesViewPresentationTests {
    /// 단계적 root stream의 첫 batch가 terminal event 전에 실제 표시 목록으로 동기화되는지 검증한다.
    func testRootStreamCoreBatchUpdatesRenderedEntriesBeforeTerminal() {
        let entry = makeHierarchyIntegrationEntry(id: "/root/first.txt", name: "first.txt")
        var state = EntryViewLayoutState()
        state.entryOperations.isLoading = true
        state.entryOperations.loadingContext.generation = 1
        state.entryOperations.loadingContext.sourceKind = .directory

        _ = EntryViewLayoutFeature().reduce(
            into: &state,
            action: .entryOperations(.loading(.streamEvent(.init(
                generation: 1,
                event: .coreBatch(items: [entry], batchIndex: 0),
            )))),
        )

        XCTAssertEqual(state.entryOperations.items, [entry])
        XCTAssertEqual(state.entries, [entry])
    }

    /// 계층 projection의 child payload가 command와 selection에서 사용할 실제 EntryModel 목록으로 노출되는지 검증한다.
    func testVisibleSelectableEntriesIncludeNestedPayloads() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let child = makeHierarchyIntegrationEntry(id: "/root/a/file", name: "file")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.hierarchy = .init(
            rootPath: "/root",
            expandedFolderIDs: [folder.id],
            foldersByID: [folder.id: .init(children: [child], phase: .loaded)],
        )

        XCTAssertEqual(
            state.visibleSelectableEntries(isNormalDirectoryPage: true).map(\.id),
            [folder.id, child.id],
        )
    }

    /// store projection이 coordinator의 NSOutlineView row graph를 직접 구성하는지 검증한다.
    func testHierarchyProjectionDrivesCoordinatorRows() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let child = makeHierarchyIntegrationEntry(id: "/root/a/file", name: "file")
        let sibling = makeHierarchyIntegrationEntry(id: "/root/sibling", name: "sibling")
        var state = EntryViewLayoutState()
        state.entries = [folder, sibling]
        state.hierarchy = .init(
            rootPath: "/root",
            expandedFolderIDs: [folder.id],
            foldersByID: [folder.id: .init(children: [child], phase: .loaded)],
        )
        state.outlineProjectionRevision = 1
        let store = Store(initialState: state) {
            EntryViewLayoutFeature()
        }
        let coordinator = EntryListCoordinator(store: store)
        let view = EntryListView(frame: .zero)

        coordinator.bind(to: view)

        XCTAssertEqual(view.tableView.numberOfRows, 3)
        XCTAssertEqual(
            (0 ..< view.tableView.numberOfRows).compactMap { row in
                guard let item = view.tableView.item(atRow: row) as? EntryListOutlineItem,
                      case let .entry(entry) = item.kind
                else { return nil }
                return entry.id
            },
            [folder.id, child.id, sibling.id],
        )
    }

    private func makeHierarchyIntegrationEntry(id: String, name: String) -> EntryModel {
        EntryModel(
            name: name,
            fullPath: id,
            isFolder: false,
            isHidden: false,
            size: 0,
            modifiedDate: Date(timeIntervalSince1970: 1_700_000_000),
            fileExtension: "txt",
            facets: EntryFacets(
                createdDate: Date(timeIntervalSince1970: 1_700_000_000),
                addedDate: Date(timeIntervalSince1970: 1_700_000_000),
                lastOpenedDate: nil,
                kind: "Text",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
    }
}
