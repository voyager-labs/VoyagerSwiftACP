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

    /// EVM-002-toggle_directory_expansion_in_list: canonical watcher path가 lexical hierarchy key를 다시 로드한다.
    /// symlink를 통해 연 folder가 실경로 이벤트를 받아도 expanded child cache가 stale로 남지 않는지 검증한다.
    /// - 검증 내용: `/private/var` affected path가 `/var` folder ID의 새 load request를 생성함
    /// - 사전 조건: 실제 symlink인 lexical `/var` folder가 expanded loaded 상태임
    /// - 기대 결과: lexical folder ID를 유지한 채 generation을 올리고 loading 상태로 전환함
    func testCanonicalInvalidationReloadsLexicalHierarchyFolder() async {
        let folder = EntryModel.temporaryFolder(id: "/var", name: "var")
        let staleChild = makeHierarchyIntegrationEntry(id: "/var/stale.txt", name: "stale.txt")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.hierarchy = .init(
            rootPath: "/",
            expandedFolderIDs: [folder.id],
            foldersByID: [
                folder.id: .init(
                    children: [staleChild],
                    phase: .loaded,
                    generation: 2,
                ),
            ],
        )
        let store = TestStore(initialState: state) {
            EntryListHierarchyReducer()
        }

        await store.send(.hierarchy(.hierarchyInvalidated(
            affectedPaths: ["/private/var"],
            removedPrefixes: [],
        ))) {
            $0.hierarchy.foldersByID[folder.id] = .init(phase: .loading, generation: 3)
            $0.outlineProjectionRevision = 2
        }
        await store.receive { action in
            guard case let .entryOperations(.loading(.loadFolderItems(request))) = action else { return false }
            return request.id.folderID == folder.id && request.path == folder.fullPath
        }
    }

    /// EVM-002-update_entry_selection: nested child context menu는 visible hierarchy row를 현재 대상으로 사용한다.
    /// expanded child를 우클릭한 뒤 Rename이 root-only snapshot 때문에 no-op 되지 않는지 검증한다.
    /// - 검증 내용: child row context menu target의 Rename delegate action
    /// - 사전 조건: root folder 아래 child가 visible·selected 상태임
    /// - 기대 결과: child EntryModel을 대상으로 startRename action이 실행됨
    func testNestedChildContextMenuStartsRename() throws {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let child = makeHierarchyIntegrationEntry(id: "/root/a/file.txt", name: "file.txt")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.selectedIds = [child.id]
        state.hierarchy = .init(
            rootPath: "/root",
            expandedFolderIDs: [folder.id],
            foldersByID: [folder.id: .init(children: [child], phase: .loaded)],
        )
        let store = Store(initialState: state) {
            Reduce<EntryViewLayoutState, EntryViewLayoutAction> { state, action in
                guard case let .delegate(.startRename(item, _)) = action else { return .none }
                state.entryOperations.renamingItemId = item.id
                return .none
            }
        }
        let coordinator = EntryListCoordinator(store: store)
        let view = EntryListView(frame: .zero)
        let event = try XCTUnwrap(NSEvent.otherEvent(
            with: .applicationDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 0,
            data1: 0,
            data2: 0,
        ))

        coordinator.bind(to: view)
        _ = coordinator.contextMenu(forRow: 1, event: event)
        coordinator.contextMenuCoordinator?.contextMenuStartRename()

        XCTAssertEqual(store.state.entryOperations.renamingItemId, child.id)
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
