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

    /// 첫 root batch 전에 stream이 실패하면 이전 Directory의 표시 행이 남지 않는지 검증한다.
    func testRootStreamFailureBeforeFirstBatchClearsRenderedEntries() {
        let staleEntry = makeHierarchyIntegrationEntry(id: "/previous/stale.txt", name: "stale.txt")
        var state = EntryViewLayoutState()
        state.entries = [staleEntry]
        state.entryOperations.isLoading = true
        state.entryOperations.loadingContext.generation = 1
        state.entryOperations.loadingContext.sourceKind = .directory

        _ = EntryViewLayoutFeature().reduce(
            into: &state,
            action: .entryOperations(.loading(.streamFailed(generation: 1))),
        )

        XCTAssertTrue(state.entryOperations.items.isEmpty)
        XCTAssertTrue(state.entries.isEmpty)
    }

    /// 숨김 파일 설정 변경 시 expanded folder cache를 새 설정으로 다시 로드하는지 검증한다.
    func testHiddenFilesChangeReloadsExpandedFolderCache() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let staleChild = makeHierarchyIntegrationEntry(id: "/root/a/visible.txt", name: "visible.txt")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.showHiddenFiles = true
        state.hierarchy = .init(
            rootPath: "/root",
            expandedFolderIDs: [folder.id],
            foldersByID: [
                folder.id: .init(
                    children: [staleChild],
                    phase: .loaded,
                    generation: 4,
                ),
            ],
        )
        let store = TestStore(initialState: state) {
            EntryListHierarchyReducer()
        }

        await store.send(.hierarchy(.hiddenFilesSettingChanged)) {
            $0.hierarchy.foldersByID[folder.id] = .init(phase: .loading, generation: 5)
            $0.outlineProjectionRevision = 2
        }
        await store.receive { action in
            guard case let .entryOperations(.loading(.cancelFolderItems(requestID))) = action else { return false }
            return requestID.folderID == folder.id
        }
        await store.receive { action in
            guard case let .entryOperations(.loading(.loadFolderItems(request))) = action else { return false }
            return request.id.folderID == folder.id && request.showHidden
        }
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

    /// EVM-002-toggle_directory_expansion_in_list: 계층 projection 비활성 목록은 folder disclosure를 숨긴다.
    /// Recents, Tags, collection, grouping 목록에서 동작하지 않는 빈 확장 UI가 노출되지 않는지 검증한다.
    /// - 검증 내용: root hierarchy context가 없는 list folder의 isItemExpandable 결과
    /// - 사전 조건: list mode root entries에 folder가 있지만 hierarchy.rootPath는 비어 있음
    /// - 기대 결과: data source가 folder를 expandable로 보고하지 않음
    func testInactiveHierarchyDoesNotExposeFolderDisclosure() throws {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        let store = Store(initialState: state) {
            EntryViewLayoutFeature()
        }
        let coordinator = EntryListCoordinator(store: store)
        let view = EntryListView(frame: .zero)

        coordinator.bind(to: view)

        let item = try XCTUnwrap(view.tableView.item(atRow: 0))
        XCTAssertFalse(coordinator.outlineView(view.tableView, isItemExpandable: item))
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
