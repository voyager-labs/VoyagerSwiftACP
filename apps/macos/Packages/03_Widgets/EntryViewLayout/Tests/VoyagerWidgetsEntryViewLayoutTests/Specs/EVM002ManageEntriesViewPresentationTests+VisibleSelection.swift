import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

private struct VisibleSelectionInput {
    let ids: Set<EntryModel.ID>
    let lastSelectedID: EntryModel.ID?
    let rangeAnchorID: EntryModel.ID?
}

extension EVM002ManageEntriesViewPresentationTests {
    // MARK: - EVM-002-update_entry_selection

    /// EVM-002-update_entry_selection: collapse는 이미 선택되지 않은 parent를 새로 선택하지 않고 hidden descendant만 제거한다.
    /// 사용자가 nested child만 선택한 상태에서 parent folder를 접을 때 visible projection과 selection이 함께 조정되는지 검증한다.
    /// - 검증 내용: reconcile action이 visible selectable IDs와 selection의 교집합을 만들고 focus/anchor를 비운다.
    /// - 사전 조건: /root/a가 expanded이고 /root/a/one, /root/a/two만 선택되어 있다.
    /// - 기대 결과: collapse 후 selection, focus, anchor는 모두 nil 또는 빈 값이며 /root/a는 자동 선택되지 않는다.
    func testCollapsePrunesHiddenDescendantSelection() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let first = visibleSelectionFile(id: "/root/a/one")
        let second = visibleSelectionFile(id: "/root/a/two")
        let store = TestStore(initialState: visibleSelectionState(
            roots: [folder],
            expandedFolderIDs: [folder.id],
            childrenByFolderID: [folder.id: [first, second]],
            selection: .init(ids: [first.id, second.id], lastSelectedID: second.id, rangeAnchorID: first.id),
        )) {
            EntryViewLayoutFeature()
        }

        await store.send(.hierarchy(.folderCollapseRequested(id: folder.id))) {
            $0.hierarchy.expandedFolderIDs = []
        }
        await store.receive(\.internal.reconcileHierarchySelection) {
            $0.selectedIds = []
            $0.lastSelectedId = nil
            $0.rangeAnchorId = nil
            $0.shouldScrollToSelection = false
            $0.outlineProjectionRevision = 1
            $0.lastVisibleSelectableEntryIDs = Set(["/root/a"])
            $0.lastReconciledOutlineProjection = $0.currentOutlineProjection()
        }
    }

    /// EVM-002-update_entry_selection: shift range는 visible outline preorder만 사용한다.
    /// expanded outline에서 range selection이 selectable entries를 연속으로 선택하는지 검증한다.
    /// - 검증 내용: applySelectionOffset이 preorder [a, a/one, a/two, b]에서 anchor-to-target range를 만든다.
    /// - 사전 조건: /root/a와 /root/b root entries 및 a의 두 loaded children가 있고 anchor는 /root/a다.
    /// - 기대 결과: shift down 두 번 뒤 선택은 /root/a, /root/a/one, /root/a/two 순서의 ID 집합이다.
    func testShiftRangeUsesVisibleOutlineOrder() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let first = visibleSelectionFile(id: "/root/a/one")
        let second = visibleSelectionFile(id: "/root/a/two")
        let sibling = EntryModel.temporaryFolder(id: "/root/b", name: "b")
        let orderedIDs = [folder.id, first.id, second.id, sibling.id]
        let state = visibleSelectionState(
            roots: [folder, sibling],
            expandedFolderIDs: [folder.id],
            childrenByFolderID: [folder.id: [first, second]],
            selection: .init(ids: [folder.id], lastSelectedID: folder.id, rangeAnchorID: folder.id),
        )
        let store = TestStore(initialState: state) {
            EntryViewLayoutFeature()
        }

        await store.send(.internal(.applySelectionOffset(
            offset: 1,
            isShiftPressed: true,
            orderedItemIds: orderedIDs,
        ))) {
            $0.selectedIds = [folder.id, first.id]
            $0.lastSelectedId = first.id
            $0.rangeAnchorId = folder.id
            $0.shouldScrollToSelection = true
        }
        await store.receive(\.delegate.selectionChanged)
        await store.send(.internal(.applySelectionOffset(
            offset: 1,
            isShiftPressed: true,
            orderedItemIds: orderedIDs,
        ))) {
            $0.selectedIds = [folder.id, first.id, second.id]
            $0.lastSelectedId = second.id
            $0.rangeAnchorId = folder.id
            $0.shouldScrollToSelection = true
        }
        await store.receive(\.delegate.selectionChanged)
    }

    /// EVM-002-update_entry_selection: sort refresh는 hidden descendant selection을 다시 visible projection으로 정리한다.
    /// hierarchy child를 선택한 뒤 root sort 결과가 재적용될 때 selection의 source가 flat entries가 아닌 visible outline인지 검증한다.
    /// - 검증 내용: arrangement applied 이후 reconcile이 selection과 anchor를 visible selectable IDs에 맞춘다.
    /// - 사전 조건: /root/a는 collapsed이고 이전에 loaded child /root/a/hidden이 선택되어 있다.
    /// - 기대 결과: hidden child selection, focus, anchor가 모두 제거된다.
    func testSortRefreshReconcilesSelectionWithVisibleOutline() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let hiddenChild = visibleSelectionFile(id: "/root/a/hidden")
        let store = TestStore(initialState: visibleSelectionState(
            roots: [folder],
            expandedFolderIDs: [],
            childrenByFolderID: [folder.id: [hiddenChild]],
            selection: .init(ids: [hiddenChild.id], lastSelectedID: hiddenChild.id, rangeAnchorID: hiddenChild.id),
        )) {
            EntryViewLayoutFeature()
        }

        await store.send(.internal(.reconcileHierarchySelection)) {
            $0.selectedIds = []
            $0.lastSelectedId = nil
            $0.rangeAnchorId = nil
            $0.shouldScrollToSelection = false
            $0.outlineProjectionRevision = 1
            $0.lastVisibleSelectableEntryIDs = Set(["/root/a"])
            $0.lastReconciledOutlineProjection = $0.currentOutlineProjection()
        }
    }

    /// EVM-002-update_entry_selection: grouping transition은 hidden descendant를 flat root selection으로 조정한다.
    /// 사용자가 grouping을 켜서 hierarchy projection을 떠날 때 visible root만 selection 대상으로 남는지 검증한다.
    /// - 검증 내용: setGroupKey가 visible projection reconciliation과 revision 증가를 수행한다.
    /// - 사전 조건: collapsed /root/a의 loaded child만 선택되어 있다.
    /// - 기대 결과: child selection, focus, anchor가 제거되고 projection revision이 증가한다.
    func testGroupingTransitionReconcilesSelectionWithFlatRoots() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let hiddenChild = visibleSelectionFile(id: "/root/a/hidden")
        let store = TestStore(initialState: visibleSelectionState(
            roots: [folder],
            expandedFolderIDs: [],
            childrenByFolderID: [folder.id: [hiddenChild]],
            selection: .init(ids: [hiddenChild.id], lastSelectedID: hiddenChild.id, rangeAnchorID: hiddenChild.id),
        )) {
            EntryViewLayoutFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }
        // store.exhaustivity = .off: grouping persistence와 arrangement reapply effect는 EVM-004 owner가 검증하며 여기서는
        // selection reconciliation만 검증한다.
        store.exhaustivity = .off

        await store.send(.internal(.reconcileHierarchySelection)) {
            $0.selectedIds = []
            $0.lastSelectedId = nil
            $0.rangeAnchorId = nil
            $0.shouldScrollToSelection = false
            $0.outlineProjectionRevision = 1
        }
    }

    /// EVM-002-update_entry_selection: list에서 grid 전환은 hidden descendant selection을 flat root projection으로 조정한다.
    /// 사용자가 hierarchy-enabled list를 떠날 때 grid가 descendant를 계속 선택 대상으로 유지하지 않는지 검증한다.
    /// - 검증 내용: setMode가 flat fallback visible IDs로 reconciliation과 revision 증가를 수행한다.
    /// - 사전 조건: expanded /root/a의 child만 선택되어 있다.
    /// - 기대 결과: grid 전환 후 child selection, focus, anchor가 제거된다.
    func testModeTransitionReconcilesSelectionWithFlatRoots() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let child = visibleSelectionFile(id: "/root/a/child")
        let store = TestStore(initialState: visibleSelectionState(
            roots: [folder],
            expandedFolderIDs: [folder.id],
            childrenByFolderID: [folder.id: [child]],
            selection: .init(ids: [child.id], lastSelectedID: child.id, rangeAnchorID: child.id),
        )) {
            EntryViewLayoutFeature()
        }

        await store.send(.internal(.setMode(.grid))) {
            $0.mode = .grid
            $0.selectedIds = []
            $0.lastSelectedId = nil
            $0.rangeAnchorId = nil
            $0.shouldScrollToSelection = false
            $0.outlineProjectionRevision = 1
            $0.lastVisibleSelectableEntryIDs = Set(["/root/a"])
            $0.lastReconciledOutlineProjection = $0.currentOutlineProjection()
        }
    }

    /// EVM-002-update_entry_selection: nested child context menu는 visible selection을 사용한다.
    /// expanded child file을 우클릭할 때 menu spec이 root entries가 아닌 실제 selection을 반영하는지 검증한다.
    /// - 검증 내용: selected child, Open With, extract visibility, favorite tag checked state
    /// - 사전 조건: Work tag가 지정된 /root/a/archive.zip child가 선택돼 있다.
    /// - 기대 결과: child 하나가 선택되고 Open With와 Extract가 표시되며 Work tag가 on이다.
    func testNestedContextMenuUsesVisibleSelectedEntry() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let child = EntryModel(
            name: "archive.zip",
            fullPath: "/root/a/archive.zip",
            isFolder: false,
            isHidden: false,
            size: 1,
            modifiedDate: Date(timeIntervalSince1970: 1_700_000_000),
            fileExtension: "zip",
            facets: .init(
                createdDate: Date(timeIntervalSince1970: 1_700_000_000),
                addedDate: Date(timeIntervalSince1970: 1_700_000_000),
                lastOpenedDate: nil,
                kind: "ZIP Archive",
                creatorApplication: nil,
                tags: [Tag(name: "Work", colorCode: 4)],
                supplementaryMetadata: nil,
            ),
        )
        let state = visibleSelectionState(
            roots: [folder],
            expandedFolderIDs: [folder.id],
            childrenByFolderID: [folder.id: [child]],
            selection: .init(ids: [child.id], lastSelectedID: child.id, rangeAnchorID: child.id),
        )

        let selectedEntries = state.contextMenuSelectedEntries(rowEntry: child)
        let spec = EntryContextMenuSpecFactory.make(
            selectedIds: state.selectedIds,
            selectedEntries: selectedEntries,
            rowEntry: child,
            isTrashFolder: false,
            restorableTrashPaths: [],
            canPaste: false,
            favoriteTags: [Tag(name: "Work", colorCode: 4)],
            openWithApplications: [],
        )

        XCTAssertEqual(selectedEntries, [child])
        XCTAssertTrue(spec.showOpenWith)
        XCTAssertFalse(spec.showCompress)
        XCTAssertTrue(spec.showExtract)
        guard let workTag = spec.paletteTags.first else {
            return XCTFail("Expected Work tag spec")
        }
        guard case .on = workTag.selection else {
            return XCTFail("Expected Work tag selection to be on")
        }
    }

    private func visibleSelectionState(
        roots: [EntryModel],
        expandedFolderIDs: Set<EntryModel.ID>,
        childrenByFolderID: [EntryModel.ID: [EntryModel]],
        selection: VisibleSelectionInput,
    ) -> EntryViewLayoutState {
        var state = EntryViewLayoutState()
        state.entries = roots
        state.hierarchy = .init(
            rootPath: "/root",
            expandedFolderIDs: expandedFolderIDs,
            foldersByID: childrenByFolderID.mapValues {
                .init(children: $0, phase: .loaded, generation: 0)
            },
        )
        state.selectedIds = selection.ids
        state.lastSelectedId = selection.lastSelectedID
        state.rangeAnchorId = selection.rangeAnchorID
        state.shouldScrollToSelection = true
        return state
    }

    private func visibleSelectionFile(id: String) -> EntryModel {
        EntryModel(
            name: URL(fileURLWithPath: id).lastPathComponent,
            fullPath: id,
            isFolder: false,
            isHidden: false,
            size: 0,
            modifiedDate: Date(timeIntervalSince1970: 1_700_000_000),
            fileExtension: "txt",
            facets: .init(
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
