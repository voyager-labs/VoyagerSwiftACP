import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

extension EVM002ManageEntriesViewPresentationTests {
    // MARK: - EVM-002-single_render_transaction_multi_field_projection

    /// EVM-002-single_render_transaction_multi_field_projection: structural projection과 selection, clipboard, rename,
    /// scroll
    /// intent가 실제 render entry point의 한 render에서 최종 상태를 유지한다.
    /// - 검증 내용: processRender의 CATransaction 경로에서 구조 변경 reload 뒤 selection, cut presentation, rename target이 적용되고
    /// scroll intent가 소비된다.
    /// - 사전 조건: 이전 snapshot에는 old entry가 있고 현재 store에는 selected/renaming target과 scroll intent가 있는 새 entry가 있다.
    /// - 기대 결과: table selection은 새 target row를 가리키고 rename target은 유지되며 scroll intent는 reset된다.
    func testSingleRenderProjectionPreservesSelectionRenameAndScrollIntent() throws {
        let oldEntry = EntryModel.temporaryFolder(id: "/root/old", name: "old")
        let targetEntry = EntryModel.temporaryFolder(id: "/root/target", name: "target")
        var previousState = EntryViewLayoutState()
        previousState.entries = [oldEntry]

        var currentState = EntryViewLayoutState()
        currentState.entries = [targetEntry]
        currentState.selectedIds = [targetEntry.id]
        currentState.lastSelectedId = targetEntry.id
        currentState.entryOperations.clipboardItems = [targetEntry.fullPath]
        currentState.entryOperations.clipboardOperation = .cut
        currentState.entryOperations.renamingItemId = targetEntry.id
        currentState.shouldScrollToSelection = true

        let store = Store(initialState: currentState) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: EntryListView(frame: .zero))
        coordinator.tableView.deselectAll(nil)
        coordinator.lastRenamingItemId = nil
        coordinator.lastRenderSnapshot = EntryListCoordinatorRenderSnapshot(state: previousState)

        coordinator.processRender(EntryListCoordinatorRenderSnapshot(state: currentState))

        let targetItem = try XCTUnwrap(coordinator.entryItemById[targetEntry.id])
        XCTAssertEqual(coordinator.tableView.row(forItem: targetItem), coordinator.tableView.selectedRow)
        XCTAssertEqual(coordinator.lastRenamingItemId, targetEntry.id)
        XCTAssertFalse(store.state.shouldScrollToSelection)
        XCTAssertTrue(coordinator.makeEntryCellConfiguration(
            entry: targetEntry,
            columnId: EntryListColumn.name.rawValue,
            columnWidth: 200,
            thumbnail: nil,
            isLoadingChildren: false,
        ).context.isCut)
        XCTAssertTrue(coordinator.makeEntryCellConfiguration(
            entry: targetEntry,
            columnId: EntryListColumn.name.rawValue,
            columnWidth: 200,
            thumbnail: nil,
            isLoadingChildren: false,
        ).context.isRenaming)
        XCTAssertEqual(coordinator.lastRenderSnapshot, EntryListCoordinatorRenderSnapshot(state: currentState))
    }

    /// EVM-002-single_render_transaction_multi_field_projection: 구조 변경과 함께 종료된 rename을 coordinator에 반영한다.
    /// retained row의 구조 갱신이 rename 종료 lifecycle을 건너뛰지 않는지 검증한다.
    /// - 검증 내용: processRender의 구조 rebuild 경로가 nil renamingItemId를 list coordinator에 동기화한다.
    /// - 사전 조건: 이전 snapshot의 retained entry가 rename 중이고 현재 snapshot에는 새 entry와 nil rename target이 있다.
    /// - 기대 결과: 구조 갱신 뒤 coordinator의 이전 rename target이 제거된다.
    func testStructuralRenderClearsRenameCoordinatorWhenStateEndsRename() {
        let retainedEntry = EntryModel.temporaryFolder(id: "/root/retained", name: "retained")
        let insertedEntry = EntryModel.temporaryFolder(id: "/root/inserted", name: "inserted")
        var previousState = EntryViewLayoutState()
        previousState.entries = [retainedEntry]
        previousState.entryOperations.renamingItemId = retainedEntry.id

        var currentState = EntryViewLayoutState()
        currentState.entries = [retainedEntry, insertedEntry]

        let store = Store(initialState: currentState) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: EntryListView(frame: .zero))
        coordinator.lastRenamingItemId = retainedEntry.id
        coordinator.lastRenderSnapshot = EntryListCoordinatorRenderSnapshot(state: previousState)

        coordinator.processRender(EntryListCoordinatorRenderSnapshot(state: currentState))

        XCTAssertNil(coordinator.lastRenamingItemId)
    }

    // MARK: - EVM-002-update_entry_selection

    /// EVM-002-update_entry_selection: group header 본문은 child Entry 선택과 분리된 cursor만 갱신한다.
    func testGroupedRowsKeepHeaderCursorSeparateFromEntrySelection() throws {
        let first = makePresentationFile(id: "/root/a.txt", name: "a.txt")
        let second = makePresentationFile(id: "/root/b.txt", name: "b.txt")
        let third = makePresentationFile(id: "/root/c.txt", name: "c.txt")
        let fixture = Task4Fixture(
            entries: [third, second, first],
            groups: [("Alpha", [first, second]), ("Beta", [third]), ("Empty", [])],
            selected: "/root/stale.txt",
        )
        try fixture.appendDuplicate(first, toGroupNamed: "Alpha")
        fixture.coordinator.isRenderObservationEnabled = false
        let alphaRow = try fixture.groupRow(named: "Alpha")
        try fixture.mouseDownAndFlush(row: alphaRow)
        fixture.assertSelection([], focus: nil, rows: [alphaRow], updates: 1)
        try fixture.assertSelectedGroupRow(alphaRow)
        fixture.coordinator.processRender(EntryListCoordinatorRenderSnapshot(state: fixture.store.state))
        fixture.assertCanonical([], focus: nil, updates: 1)
        XCTAssertEqual(fixture.tableView.selectedRowIndexes, [alphaRow])
        XCTAssertTrue(try fixture.groupRowIsSelected(alphaRow))

        let betaRow = try fixture.groupRow(named: "Beta")
        XCTAssertTrue(try fixture.routeBody(row: betaRow, modifiers: .command))
        fixture.assertSelection([], focus: nil, rows: [betaRow], updates: 1)
        XCTAssertTrue(try fixture.routeBody(row: alphaRow, modifiers: .command))
        fixture.assertSelection([], focus: nil, rows: [alphaRow], updates: 1)
        XCTAssertTrue(try fixture.routeBody(row: betaRow, modifiers: .command))
        fixture.assertSelection([], focus: nil, rows: [betaRow], updates: 1)

        let alphaItem = try XCTUnwrap(fixture.coordinator.groupItemByName["Alpha"])
        fixture.tableView.collapseItem(alphaItem)
        XCTAssertTrue(try fixture.routeBody(row: alphaRow))
        fixture.assertSelection([], focus: nil, rows: [alphaRow], updates: 1)
        XCTAssertTrue(try fixture.routeBody(row: alphaRow))
        XCTAssertTrue(try fixture.routeBlank())
        let emptyItem = try XCTUnwrap(fixture.coordinator.groupItemByName["Empty"])
        XCTAssertFalse(fixture.coordinator.outlineView(fixture.tableView, shouldSelectItem: emptyItem))
        XCTAssertTrue(try fixture.routeBody(row: fixture.groupRow(named: "Empty")))
        fixture.assertCanonical([], focus: nil, updates: 1)

        let entrySelection = Task4Fixture(
            entries: [third, second, first],
            groups: [("Alpha", [first, second]), ("Beta", [third])],
        )
        entrySelection.setSelection([third.id], focus: third.id)
        XCTAssertFalse(try entrySelection.groupRowIsSelected(entrySelection.groupRow(named: "Beta")))
        entrySelection.setSelection([first.id, second.id], focus: second.id)
        XCTAssertFalse(try entrySelection.groupRowIsSelected(entrySelection.groupRow(named: "Alpha")))
    }

    /// EVM-002-update_entry_selection: 그룹 disclosure 입력은 확장 상태만 바꾸고 선택을 갱신하지 않는다.
    /// disclosure frame의 primary/right-click이 그룹 본문 선택 및 Entry 메뉴 경로와 분리되는지 검증한다.
    func testGroupedDisclosureDoesNotMutateSelection() throws {
        let child = makePresentationFile(id: "/root/child.txt", name: "child.txt")
        let outside = makePresentationFile(id: "/root/outside.txt", name: "outside.txt")
        let fixture = Task4Fixture(
            entries: [child, outside],
            groups: [("Alpha", [child]), ("Outside", [outside])],
            selected: outside.id,
        )
        fixture.coordinator.syncListSelectionFromStore()
        let alphaItem = try XCTUnwrap(fixture.coordinator.groupItemByName["Alpha"])
        let alphaRow = try fixture.groupRow(named: "Alpha")
        XCTAssertTrue(fixture.coordinator.outlineView(fixture.tableView, shouldSelectItem: alphaItem))
        XCTAssertTrue(fixture.tableView.isItemExpanded(alphaItem))
        let primary = try fixture.event(row: alphaRow, type: .leftMouseDown, disclosure: true)
        XCTAssertFalse(fixture.tableView.handleCustomSelectionMouseDown(primary).boolValue)
        fixture.tableView.collapseItem(alphaItem)
        XCTAssertFalse(fixture.tableView.isItemExpanded(alphaItem))
        fixture.assertCanonical([outside.id], focus: outside.id, updates: 0)
        let secondary = try fixture.event(row: alphaRow, type: .rightMouseDown, disclosure: true)
        XCTAssertTrue(fixture.tableView.handleCustomSelectionRightMouseDown(secondary).boolValue)
        XCTAssertFalse(fixture.tableView.isItemExpanded(alphaItem))
        fixture.assertCanonical([outside.id], focus: outside.id, updates: 0)
    }

    /// EVM-002-update_entry_selection: 그룹 본문 우클릭은 기존 Entry 메뉴를 만들기 전에 그룹 자식을 Plain 선택한다.
    /// 선택 여부와 무관하게 그룹 순서의 distinct Entry target이 기존 메뉴 builder로 전달되는지 검증한다.
    func testGroupedRightClickReplacesSelectionBeforeExistingEntryMenu() throws {
        let first = makePresentationFile(id: "/root/a.txt", name: "a.txt")
        let second = makePresentationFile(id: "/root/b.txt", name: "b.txt")
        let outside = makePresentationFile(id: "/root/outside.txt", name: "outside.txt")
        let fixture = Task4Fixture(
            entries: [outside, second, first],
            groups: [("Alpha", [first, second]), ("Outside", [outside])],
            selected: outside.id,
        )
        try fixture.appendDuplicate(first, toGroupNamed: "Alpha")
        fixture.coordinator.syncListSelectionFromStore()
        let generationBeforeRightClick = fixture.tableView.selectionTransactionGeneration
        let alphaRow = try fixture.groupRow(named: "Alpha")
        let event = try fixture.event(row: alphaRow, type: .rightMouseDown)
        XCTAssertFalse(fixture.tableView.handleCustomSelectionRightMouseDown(event).boolValue)
        let menu = fixture.coordinator.contextMenu(forRow: alphaRow, event: event)
        fixture.assertCanonical([first.id, second.id], focus: second.id, updates: 1)
        XCTAssertEqual(fixture.tableView.selectionTransactionGeneration, generationBeforeRightClick + 1)
        XCTAssertEqual(fixture.recorder.events.prefix(2), ["selection", "preload:\(first.id),\(second.id)"])
        XCTAssertEqual(fixture.tableView.selectedRowIndexes, IndexSet(integersIn: alphaRow ... alphaRow + 3))
        let titles = Set(menu.items.map(\.title))
        XCTAssertTrue(["Open", "Quick Look", "Get Info", "Share…", "Copy", "Move to Trash"].allSatisfy(titles.contains))
        XCTAssertFalse(titles.contains("Select Group"))
    }

    /// EVM-002-update_entry_selection: collapsed single-entry group context menu disables Rename.
    /// 접힌 그룹의 hidden child를 일반 Entry rename target처럼 노출하지 않는지 검증한다.
    /// - 검증 내용: 단일 child를 가진 collapsed group의 Rename menu item이 비활성화된다.
    /// - 사전 조건: Alpha group이 child 하나를 가지고 collapsed 상태이며 group row를 우클릭한다.
    /// - 기대 결과: 그룹 context menu의 Rename은 disabled이고 일반 Entry 메뉴 계약은 유지된다.
    func testCollapsedSingleEntryGroupDisablesRenameInContextMenu() throws {
        let entry = makePresentationFile(id: "/root/child.txt", name: "child.txt")
        let fixture = Task4Fixture(entries: [entry], groups: [("Alpha", [entry])])
        let groupItem = try XCTUnwrap(fixture.coordinator.groupItemByName["Alpha"])
        fixture.tableView.collapseItem(groupItem)
        let groupRow = try fixture.groupRow(named: "Alpha")
        let event = try fixture.event(row: groupRow, type: .rightMouseDown)
        let menu = fixture.coordinator.contextMenu(forRow: groupRow, event: event)

        let renameItem = try XCTUnwrap(menu.item(withTitle: "Rename"))
        XCTAssertFalse(renameItem.isEnabled)
    }

    /// EVM-002-update_entry_selection: ordinary Entry 입력은 native toggle/range와 기존 action/data-source 경로를 보존한다.
    func testGroupedSelectionPathPreservesNativeEntryClickDoubleClickDragAndRename() throws {
        let entries = ["a", "b", "c", "d"].map {
            makePresentationFile(id: "/root/\($0).txt", name: "\($0).txt")
        }
        let fixture = Task4Fixture(
            entries: entries,
            groups: [("Alpha", Array(entries[1 ... 3]))],
            renaming: entries[3].id,
        )
        fixture.prependRootEntry(entries[0])
        try fixture.selectGroup(named: "Alpha")
        XCTAssertTrue(try fixture.tableView.beginNativeSelection(
            atRow: fixture.entryRow(id: entries[1].id),
            modifierFlags: .command,
        ))
        fixture.tableView.selectRowIndexes(IndexSet(integersIn: 3 ... 4), byExtendingSelection: false)
        fixture.coordinator.outlineViewSelectionDidChange(Notification(name: .init("native-command-remove")))
        fixture.assertCanonical(Set(entries[2 ... 3].map(\.id)), focus: entries[3].id, updates: 2)
        try fixture.selectGroup(named: "Alpha")
        try fixture.mouseDownAndFlush(row: fixture.groupRow(named: "Alpha"), disclosure: true)
        try fixture.mouseDownAndFlush(row: fixture.entryRow(id: entries[0].id), modifiers: .command)
        fixture.assertCanonical(Set(entries.map(\.id)), focus: entries[0].id, updates: 4)
        try fixture.mouseDownAndFlush(row: fixture.groupRow(named: "Alpha"), disclosure: true)
        fixture.setSelection([entries[0].id], focus: entries[0].id)
        XCTAssertTrue(try fixture.routeBody(row: fixture.entryRow(id: entries[1].id), modifiers: .shift))
        fixture.assertSelection(
            Set(entries[0 ... 1].map(\.id)),
            focus: entries[1].id,
            anchor: entries[0].id,
            rows: IndexSet([0, 2]),
            updates: 6,
        )
        XCTAssertFalse(try fixture.routeBody(row: fixture.entryRow(id: entries[3].id), clickCount: 2))
        XCTAssertIdentical(fixture.tableView.target as AnyObject?, fixture.coordinator)
        XCTAssertEqual(fixture.tableView.doubleAction, #selector(EntryListCoordinator.handleDoubleClick))
        let lastItem = try XCTUnwrap(
            fixture.tableView.item(atRow: fixture.entryRow(id: entries[3].id)) as? EntryListOutlineItem,
        )
        let writer = fixture.coordinator.outlineView(fixture.tableView, pasteboardWriterForItem: lastItem) as? NSURL
        XCTAssertEqual(writer?.path, entries[3].fullPath)
        XCTAssertIdentical(fixture.tableView.dataSource as AnyObject?, fixture.coordinator)
        XCTAssertTrue(fixture.coordinator.outlineView(
            fixture.tableView,
            shouldEdit: fixture.tableView.outlineTableColumn,
            item: lastItem,
        ))
    }

    /// EVM-002-update_entry_selection: native group row selection projects child entries.
    /// custom event context 없이도 그룹 row 선택을 canonical selection으로 정규화한다.
    /// VoiceOver 또는 다른 AppKit 경로가 그룹 row를 직접 선택해도 custom pointer path와 같은 canonical selection을 유지하는지 검증한다.
    /// - 검증 내용: context 없는 `outlineViewSelectionDidChange`가 non-empty group row를 child Entry IDs, focus, anchor로 정규화한다.
    /// - 사전 조건: 두 child Entry를 가진 expanded Alpha group과 group row 하나만 native selection으로 지정된 상태다.
    /// - 기대 결과: group child가 canonical selection과 물리 row selection에 반영되고 updateSelection은 한 번 발생한다.
    func testNativeGroupSelectionProjectsChildrenWithoutContext() throws {
        let entries = [
            makePresentationFile(id: "/root/a.txt", name: "a.txt"),
            makePresentationFile(id: "/root/b.txt", name: "b.txt"),
        ]
        let fixture = Task4Fixture(entries: entries, groups: [("Alpha", entries)])
        let groupItem = try XCTUnwrap(fixture.coordinator.groupItemByName["Alpha"])
        let groupRow = try fixture.groupRow(named: "Alpha")
        XCTAssertTrue(fixture.coordinator.outlineView(fixture.tableView, shouldSelectItem: groupItem))
        fixture.tableView.selectRowIndexes(IndexSet(integer: groupRow), byExtendingSelection: false)

        fixture.coordinator.outlineViewSelectionDidChange(Notification(name: .init("native-group-selection")))

        fixture.assertCanonical(Set(entries.map(\.id)), focus: entries[1].id, updates: 1)
        XCTAssertTrue(try fixture.groupRowIsSelected(groupRow))
        XCTAssertTrue(fixture.tableView.selectedRowIndexes.contains(groupRow))
        XCTAssertIdentical(fixture.tableView.activeSelectionOccurrence, groupItem)
    }

    /// EVM-002-update_entry_selection: native multi-group selection projects every selected group.
    /// context 없는 VoiceOver/AppKit 다중 선택에서도 각 group row의 child Entry를 canonical selection에 병합한다.
    /// - 검증 내용: 두 group row를 native selection으로 지정하면 두 그룹의 distinct child ID를 모두 투영한다.
    /// - 사전 조건: 각각 두 child Entry를 가진 Alpha/Beta group row가 함께 선택되어 있다.
    /// - 기대 결과: canonical selection은 네 Entry이고 native group row 선택은 유지된다.
    func testNativeMultipleGroupSelectionProjectsChildrenWithoutContext() throws {
        let entries = [
            makePresentationFile(id: "/root/a.txt", name: "a.txt"),
            makePresentationFile(id: "/root/b.txt", name: "b.txt"),
            makePresentationFile(id: "/root/c.txt", name: "c.txt"),
            makePresentationFile(id: "/root/d.txt", name: "d.txt"),
        ]
        let fixture = Task4Fixture(
            entries: entries,
            groups: [
                ("Alpha", Array(entries[0 ... 1])),
                ("Beta", Array(entries[2 ... 3])),
            ],
        )
        let alphaItem = try XCTUnwrap(fixture.coordinator.groupItemByName["Alpha"])
        let betaItem = try XCTUnwrap(fixture.coordinator.groupItemByName["Beta"])
        let alphaRow = try fixture.groupRow(named: "Alpha")
        let betaRow = try fixture.groupRow(named: "Beta")
        XCTAssertTrue(fixture.coordinator.outlineView(fixture.tableView, shouldSelectItem: alphaItem))
        XCTAssertTrue(fixture.coordinator.outlineView(fixture.tableView, shouldSelectItem: betaItem))
        fixture.tableView.selectRowIndexes(
            IndexSet([alphaRow, betaRow]),
            byExtendingSelection: false,
        )

        fixture.coordinator.outlineViewSelectionDidChange(Notification(name: .init("native-multi-group-selection")))

        fixture.assertCanonical(Set(entries.map(\.id)), focus: entries[3].id, updates: 1)
        XCTAssertEqual(fixture.tableView.selectedRowIndexes, IndexSet([alphaRow, betaRow]))
    }

    /// EVM-002-update_entry_selection: blank-space mouse down clears the current selection.
    /// 목록의 행 바깥 빈 영역을 클릭해도 visible selection contract와 native focus 경로를 유지하는지 검증한다.
    /// - 검증 내용: modifier 없는 빈 공간 mouseDown이 canonical selection과 물리 row selection을 비운다.
    /// - 사전 조건: 하나의 Entry가 선택된 EntryListTableView와 마지막 row 아래의 빈 클릭 위치가 있다.
    /// - 기대 결과: selection이 비고 native mouseDown이 소비되어 updateSelection은 한 번만 발생한다.
    func testBlankSpaceMouseDownClearsSelection() throws {
        let entry = makePresentationFile(id: "/root/a.txt", name: "a.txt")
        let fixture = Task4Fixture(entries: [entry], groups: [("Alpha", [entry])])
        fixture.setSelection([entry.id], focus: entry.id)

        let event = try fixture.event(row: nil, type: .leftMouseDown)
        fixture.tableView.mouseDown(with: event)

        fixture.assertCanonical([], focus: nil, updates: 2)
        XCTAssertTrue(fixture.tableView.selectedRowIndexes.isEmpty)
    }

    /// EVM-002-update_entry_selection: blank-space right-click clears the current selection before its menu opens.
    /// 행 아래 빈 영역에서 context menu를 열어도 이전 Entry가 후속 command target으로 남지 않는지 검증한다.
    /// - 검증 내용: modifier 없는 blank-space rightMouseDown이 canonical/physical selection을 비운다.
    /// - 사전 조건: 하나의 Entry가 선택된 EntryListTableView와 빈 영역 우클릭 이벤트
    /// - 기대 결과: 선택이 비고 기존 blank-space menu 경로로 계속 진행할 수 있다.
    func testBlankSpaceRightMouseDownClearsSelection() throws {
        let entry = makePresentationFile(id: "/root/a.txt", name: "a.txt")
        let fixture = Task4Fixture(entries: [entry], groups: [("Alpha", [entry])])
        fixture.setSelection([entry.id], focus: entry.id)

        try fixture.tableView.rightMouseDown(with: fixture.event(row: nil, type: .rightMouseDown))

        fixture.assertCanonical([], focus: nil, updates: 2)
        XCTAssertTrue(fixture.tableView.selectedRowIndexes.isEmpty)
    }

    /// EVM-002-update_entry_selection: native modifier click은 그룹의 canonical Entry 선택을 보존한다.
    /// 실제 AppKit Shift/Command mouseDown 경로에서 duplicate Entry와 그룹 header를 canonical ID로 정규화하는지 검증한다.
    /// - 검증 내용: modifier event마다 canonical Entry ID와 focus/anchor가 한 번 갱신된다.
    /// - 사전 조건: A root Entry와 B, C, D를 포함한 G1이 expanded 또는 collapsed 상태로 선택되어 있다.
    /// - 기대 결과: Shift A→B는 A,B이고 Command remove/add는 각각 C,D와 A,B,C,D다.
    func testGroupedSelectionPathPreservesAnchorFocusAndSingleCanonicalUpdate() throws {
        let entries = ["a", "b", "c", "d"].map {
            makePresentationFile(id: "/root/\($0).txt", name: "\($0).txt")
        }
        func makeFixture() -> Task4Fixture {
            let fixture = Task4Fixture(entries: entries, groups: [("G1", Array(entries[1 ... 3]))])
            fixture.prependRootEntry(entries[0])
            return fixture
        }
        do {
            let fixture = makeFixture()
            fixture.setSelection([entries[0].id], focus: entries[0].id)
            fixture.assertSelection([entries[0].id], focus: entries[0].id, rows: [0], updates: 1)
            try fixture.mouseDownAndFlush(row: fixture.entryRow(id: entries[1].id), modifiers: .shift)
            fixture.assertSelection(
                Set(entries[0 ... 1].map(\.id)), focus: entries[1].id, anchor: entries[0].id,
                rows: IndexSet([0, 2]), updates: 2,
            )
        }

        do {
            let fixture = makeFixture()
            try fixture.appendDuplicate(entries[1], toGroupNamed: "G1")
            let groupRow = try fixture.groupRow(named: "G1")
            try fixture.selectGroup(named: "G1")
            fixture.assertSelection(
                Set(entries[1 ... 3].map(\.id)), focus: entries[3].id,
                rows: IndexSet(integersIn: groupRow ... groupRow + 4), updates: 1,
            )
            try fixture.mouseDownAndFlush(row: fixture.entryRow(id: entries[1].id), modifiers: .command)
            fixture.assertCanonical(Set(entries[2 ... 3].map(\.id)), focus: entries[3].id, updates: 2)
            let bRows = fixture.visibleRows(id: entries[1].id)
            let selectedBRows = bRows.map(fixture.tableView.selectedRowIndexes.contains)
            XCTAssertEqual(selectedBRows, [false, false])
        }
        do {
            let fixture = makeFixture()
            let groupRow = try fixture.groupRow(named: "G1")
            try fixture.selectGroup(named: "G1")
            try fixture.mouseDownAndFlush(row: groupRow, disclosure: true)
            fixture.assertSelection(
                Set(entries[1 ... 3].map(\.id)), focus: entries[3].id, rows: [groupRow], updates: 1,
            )
            try fixture.mouseDownAndFlush(row: fixture.entryRow(id: entries[0].id), modifiers: .command)
            fixture.assertCanonical(Set(entries.map(\.id)), focus: entries[0].id, updates: 2)
        }
    }

    /// EVM-002-update_entry_selection: Shift 범위는 canonical ID에서 모든 physical occurrence를 다시 투영한다.
    /// 부분 그룹, 그룹 header 목적지, duplicate occurrence와 반복 키보드 반전을 하나의 선택 계약으로 검증한다.
    /// - 검증 내용: pointer/keyboard Shift가 canonical IDs, focus/anchor, projected rows를 정확히 한 번 갱신한다.
    /// - 사전 조건: 확장된 그룹, 범위 밖 duplicate, 부분 선택된 인접 그룹과 고정 occurrence anchor가 있다.
    /// - 기대 결과: 부분 그룹 header는 빠지고 완전 선택 그룹과 모든 visible duplicate만 물리 선택된다.
    func testGroupedRowsMaintainStablePointerAndKeyboardRangeThroughReversal() throws {
        do {
            let entries = ["a", "b", "c", "d"].map {
                makePresentationFile(id: "/root/\($0).txt", name: "\($0).txt")
            }
            let fixture = Task4Fixture(entries: entries, groups: [("G1", Array(entries[1 ... 3]))])
            fixture.prependRootEntry(entries[0])
            try fixture.appendDuplicate(entries[1], toGroupNamed: "G1")
            let rootRow = try fixture.entryRow(id: entries[0].id)
            let groupRow = try fixture.groupRow(named: "G1")
            let duplicateRows = fixture.visibleRows(id: entries[1].id)
            let firstDuplicateRow = try XCTUnwrap(duplicateRows.first)
            fixture.setSelection([entries[0].id], focus: entries[0].id)

            try fixture.mouseDownAndFlush(row: firstDuplicateRow, modifiers: .shift)
            fixture.assertSelection(
                Set(entries[0 ... 1].map(\.id)),
                focus: entries[1].id,
                anchor: entries[0].id,
                rows: IndexSet([rootRow] + duplicateRows),
                updates: 2,
            )

            try fixture.mouseDownAndFlush(row: groupRow, modifiers: .shift)
            fixture.assertSelection(
                Set(entries.map(\.id)),
                focus: entries[3].id,
                anchor: entries[0].id,
                rows: IndexSet([rootRow, groupRow] + entries[1 ... 3].flatMap { fixture.visibleRows(id: $0.id) }),
                updates: 3,
            )
        }

        do {
            let entries = ["b", "c", "d", "e", "f"].map {
                makePresentationFile(id: "/root/\($0).txt", name: "\($0).txt")
            }
            let fixture = Task4Fixture(
                entries: entries,
                groups: [("G1", Array(entries[0 ... 2])), ("G2", Array(entries[3 ... 4]))],
            )
            let firstGroupRow = try fixture.groupRow(named: "G1")
            let secondGroupRow = try fixture.groupRow(named: "G2")
            fixture.setSelection([entries[3].id], focus: entries[3].id)

            try fixture.mouseDownAndFlush(row: firstGroupRow, modifiers: .shift)
            fixture.assertSelection(
                Set(entries[0 ... 3].map(\.id)),
                focus: entries[2].id,
                anchor: entries[3].id,
                rows: IndexSet(
                    [firstGroupRow]
                        + entries[0 ... 2].flatMap { fixture.visibleRows(id: $0.id) }
                        + fixture.visibleRows(id: entries[3].id),
                ),
                updates: 2,
            )
            XCTAssertFalse(fixture.tableView.selectedRowIndexes.contains(secondGroupRow))
        }

        do {
            let entries = ["a", "b", "c", "d"].map {
                makePresentationFile(id: "/root/\($0).txt", name: "\($0).txt")
            }
            let fixture = Task4Fixture(entries: entries, groups: [("G1", Array(entries[1 ... 3]))])
            fixture.prependRootEntry(entries[0])
            let cRow = try fixture.entryRow(id: entries[2].id)
            fixture.setSelection([entries[2].id], focus: entries[2].id)

            try fixture.keyDown(.downArrow, modifiers: .shift)
            fixture.assertSelection(
                Set(entries[2 ... 3].map(\.id)), focus: entries[3].id, anchor: entries[2].id,
                rows: IndexSet(entries[2 ... 3].flatMap { fixture.visibleRows(id: $0.id) }), updates: 2,
            )
            try fixture.keyDown(.upArrow, modifiers: .shift)
            fixture.assertSelection(
                [entries[2].id], focus: entries[2].id, anchor: entries[2].id,
                rows: IndexSet(integer: cRow), updates: 3,
            )
            try fixture.keyDown(.upArrow, modifiers: .shift)
            fixture.assertSelection(
                Set(entries[1 ... 2].map(\.id)), focus: entries[1].id, anchor: entries[2].id,
                rows: IndexSet(entries[1 ... 2].flatMap { fixture.visibleRows(id: $0.id) }), updates: 4,
            )
            try fixture.keyDown(.downArrow, modifiers: .shift)
            fixture.assertSelection(
                [entries[2].id], focus: entries[2].id, anchor: entries[2].id,
                rows: IndexSet(integer: cRow), updates: 5,
            )
            try fixture.keyDown(.downArrow, modifiers: .shift)
            fixture.assertSelection(
                Set(entries[2 ... 3].map(\.id)), focus: entries[3].id, anchor: entries[2].id,
                rows: IndexSet(entries[2 ... 3].flatMap { fixture.visibleRows(id: $0.id) }), updates: 6,
            )
        }
    }

    /// EVM-002-update_entry_selection: 후속 native input은 deferred toggle ownership을 보존한다.
    /// 실제 right-click/keyDown 취소, 두 left-click 소유권, drag session 경계를 검증한다.
    /// - 검증 내용: 후속 input과 같은 turn의 두 Command candidate 이후 canonical selection.
    /// - 사전 조건: expanded G1의 B,C,D와 group header가 모두 선택되어 있다.
    /// - 기대 결과: right/key/drag는 B,C,D를 유지하고 두 left-click은 C,D를 한 번 갱신한다.
    func testZZNativeCommandDragPreservesCanonicalSelection() throws {
        let entries = ["b", "c", "d"].map { makePresentationFile(id: "/root/\($0).txt", name: "\($0).txt") }
        let fixture = Task4Fixture(entries: entries, groups: [("G1", entries)])
        let ids = Set(entries.map(\.id))
        let bRow = try fixture.entryRow(id: entries[0].id)
        try fixture.selectGroup(named: "G1")
        try fixture.mouseDownAndFlush(row: bRow, modifiers: .command) { try fixture.rightMouseDown(row: bRow) }
        try fixture.mouseDownAndFlush(row: bRow, modifiers: .command) { try fixture.keyDown(.rightArrow) }
        fixture.assertSelection(ids, focus: entries[2].id, rows: IndexSet(integersIn: 0 ... 3), updates: 1)
        try fixture.mouseDownAndFlush(row: bRow, modifiers: .command) {
            try fixture.mouseDownAndFlush(row: bRow, modifiers: .command)
        }
        fixture.assertSelection(
            Set(entries[1 ... 2].map(\.id)), focus: entries[2].id, rows: IndexSet(integersIn: 2 ... 3), updates: 2,
        )
        try fixture.selectGroup(named: "G1")
        try fixture.mouseDownAndFlush(row: fixture.entryRow(id: entries[0].id), modifiers: .command, dragOffset: 40)
        fixture.assertCanonical(ids, focus: entries[2].id, updates: 3)
    }

    /// EVM-002-update_entry_selection: store selection 동기화는 중복 occurrence와 완전 선택 그룹만 강조하고 callback을 중복 전송하지 않는다.
    func testGroupedRowsSynchronizeOccurrencesAndSuppressDuplicateCallbacks() throws {
        let first = makePresentationFile(id: "/root/a.txt", name: "a.txt")
        let second = makePresentationFile(id: "/root/b.txt", name: "b.txt")
        let third = makePresentationFile(id: "/root/c.txt", name: "c.txt")
        let fixture = Task4Fixture(
            entries: [first, second, third],
            groups: [("G1", [first, second]), ("G2", [first, third])],
        )
        fixture.coordinator.isRenderObservationEnabled = false
        let firstGroupRow = try fixture.groupRow(named: "G1")
        try fixture.selectGroup(named: "G1")
        fixture.coordinator.processRender(EntryListCoordinatorRenderSnapshot(state: fixture.store.state))
        let duplicateRows = fixture.visibleRows(id: first.id)
        XCTAssertEqual(duplicateRows.count, 2)
        XCTAssertTrue(duplicateRows.allSatisfy(fixture.tableView.selectedRowIndexes.contains))
        XCTAssertTrue(try fixture.groupRowIsSelected(firstGroupRow))
        XCTAssertFalse(try fixture.groupRowIsSelected(fixture.groupRow(named: "G2")))
        XCTAssertEqual(fixture.recorder.updateCount, 1)
        try fixture.mouseDownAndFlush(row: firstGroupRow, disclosure: true)
        XCTAssertFalse(try fixture.tableView.isItemExpanded(XCTUnwrap(fixture.coordinator.groupItemByName["G1"])))
        fixture.assertCanonical([first.id, second.id], focus: second.id, updates: 1)
        fixture.coordinator.processRender(EntryListCoordinatorRenderSnapshot(state: fixture.store.state))
        let collapsedFullRows = IndexSet([firstGroupRow] + fixture.visibleRows(id: first.id))
        XCTAssertEqual(fixture.tableView.selectedRowIndexes, collapsedFullRows)
        XCTAssertTrue(try fixture.groupRowIsSelected(firstGroupRow))
        try fixture.mouseDownAndFlush(row: firstGroupRow, disclosure: true)
        try fixture.selectGroup(named: "G1")
        try fixture.keyDown(.leftArrow)
        fixture.assertCanonical([first.id, second.id], focus: second.id, updates: 1)
        fixture.coordinator.processRender(EntryListCoordinatorRenderSnapshot(state: fixture.store.state))
        XCTAssertEqual(fixture.tableView.selectedRowIndexes, collapsedFullRows)
        try fixture.mouseDownAndFlush(row: firstGroupRow, disclosure: true)
        XCTAssertEqual(fixture.recorder.updateCount, 1)
        fixture.store.send(.view(.updateSelection(
            ids: [first.id], lastSelectedId: first.id, rangeAnchorId: first.id, shouldScrollToSelection: false,
        )))
        fixture.coordinator.syncListSelectionFromStore()
        XCTAssertEqual(fixture.recorder.updateCount, 2)
        try fixture.mouseDownAndFlush(row: firstGroupRow, disclosure: true)
        fixture.assertCanonical([first.id], focus: first.id, updates: 2)
        fixture.coordinator.processRender(EntryListCoordinatorRenderSnapshot(state: fixture.store.state))
        XCTAssertEqual(fixture.tableView.selectedRowIndexes, IndexSet(fixture.visibleRows(id: first.id)))
        XCTAssertFalse(try fixture.groupRowIsSelected(firstGroupRow))
        XCTAssertEqual(fixture.recorder.events.count(where: { $0 == "toggle:G1" }), 5)
        fixture.coordinator.outlineViewSelectionDidChange(Notification(name: .init("t1-current")))
        fixture.store.send(.view(.updateSelection(
            ids: [third.id],
            lastSelectedId: third.id,
            rangeAnchorId: third.id,
            shouldScrollToSelection: false,
        )))
        fixture.coordinator.syncListSelectionFromStore()
        fixture.coordinator.outlineViewSelectionDidChange(Notification(name: .init("delayed-t1")))
        fixture.coordinator.outlineViewSelectionDidChange(Notification(name: .init("duplicate-t2")))
        fixture.assertCanonical([third.id], focus: third.id, updates: 3)
        fixture.store.send(.view(.updateSelection(
            ids: [second.id],
            lastSelectedId: second.id,
            rangeAnchorId: second.id,
            shouldScrollToSelection: false,
        )))
        XCTAssertTrue(try fixture.tableView.beginNativeSelection(atRow: fixture.entryRow(id: third.id)))
        fixture.coordinator.outlineViewSelectionDidChange(Notification(name: .init("native-current-c")))
        fixture.coordinator.outlineViewSelectionDidChange(Notification(name: .init("duplicate-native-current-c")))
        fixture.assertCanonical([third.id], focus: third.id, updates: 5)
        var malformedState = fixture.store.state
        malformedState.selectedIds = [second.id, "group:G1", "/root/stale.txt"]
        malformedState.lastSelectedId = "/root/stale.txt"
        malformedState.rangeAnchorId = "group:G1"
        malformedState.synchronizeEntries([first, second, third])
        XCTAssertEqual(malformedState.selectedIds, [second.id])
        XCTAssertEqual(malformedState.lastSelectedId, second.id)
        XCTAssertEqual(malformedState.rangeAnchorId, second.id)
    }

    /// EVM-002-update_entry_selection: group header는 Entry selection과 분리된 keyboard/disclosure cursor로 동작한다.
    /// 사용자가 entry 행에서 group 행으로 이동하거나 group body를 클릭한 뒤 disclosure 키를 사용하는 경로를 검증한다.
    /// - 검증 내용: Up/Down이 group 행을 포함하고 group body는 child Entry를 선택하지 않는다.
    /// - 사전 조건: root entry 하나와 두 child를 가진 expanded G1 group이 list projection에 있다.
    /// - 기대 결과: group 행만 cursor로 선택되고 Left/Right로 G1을 접고 펼칠 수 있다.
    func testGroupedRowsPreserveKeyboardCursorAcrossProjectionAndDisclosure() throws {
        let entries = ["a", "b", "c"].map {
            makePresentationFile(id: "/root/\($0).txt", name: "\($0).txt")
        }
        let fixture = Task4Fixture(entries: entries, groups: [("G1", Array(entries[1 ... 2]))])
        fixture.prependRootEntry(entries[0])
        let initialGroupRow = try fixture.groupRow(named: "G1")
        fixture.setSelection([entries[0].id], focus: entries[0].id)
        try fixture.keyDown(.downArrow)
        fixture.renderCurrentState()
        fixture.assertSelection([], focus: nil, rows: [initialGroupRow], updates: 2)

        fixture.replaceProjectionWithFreshItems()
        let projectedGroupRow = try fixture.groupRow(named: "G1")
        let firstChildRow = try fixture.entryRow(id: entries[1].id)
        let secondChildRow = try fixture.entryRow(id: entries[2].id)
        try fixture.keyDown(.downArrow)
        fixture.renderCurrentState()
        fixture.assertSelection([entries[1].id], focus: entries[1].id, rows: [firstChildRow], updates: 3)
        try fixture.keyDown(.downArrow)
        fixture.renderCurrentState()
        fixture.assertSelection([entries[2].id], focus: entries[2].id, rows: [secondChildRow], updates: 4)
        try fixture.keyDown(.upArrow)
        fixture.renderCurrentState()
        fixture.assertSelection([entries[1].id], focus: entries[1].id, rows: [firstChildRow], updates: 5)
        try fixture.keyDown(.upArrow)
        fixture.renderCurrentState()
        fixture.assertSelection([], focus: nil, rows: [projectedGroupRow], updates: 6)

        fixture.setSelection([entries[1].id], focus: entries[1].id)
        try fixture.mouseDownAndFlush(row: projectedGroupRow, outlineCellBody: true)
        fixture.assertSelection([], focus: nil, rows: [projectedGroupRow], updates: 8)
        try fixture.keyDown(.leftArrow)
        XCTAssertTrue(fixture.store.state.entryArrangements.collapsedGroups.contains("G1"))

        fixture.replaceProjectionWithFreshItems()
        try fixture.keyDown(.leftArrow)
        XCTAssertTrue(fixture.store.state.entryArrangements.collapsedGroups.contains("G1"))

        fixture.coordinator.processRender(EntryListCoordinatorRenderSnapshot(state: fixture.store.state))
        XCTAssertFalse(try fixture.tableView.isItemExpanded(XCTUnwrap(fixture.coordinator.groupItemByName["G1"])))
        XCTAssertTrue(fixture.tableView.selectedRowIndexes.contains(projectedGroupRow))
        try fixture.keyDown(.rightArrow)
        XCTAssertFalse(fixture.store.state.entryArrangements.collapsedGroups.contains("G1"))
        XCTAssertTrue(try fixture.groupRowIsSelected(projectedGroupRow))
    }

    /// EVM-002-update_entry_selection: keyboard navigation skips visible non-selectable status rows.
    /// 빈 폴더 또는 로드 실패 sentinel이 visible outline에 있어도 다음 selectable Entry로 이동하는지 검증한다.
    /// - 검증 내용: empty/error row를 연속으로 삽입한 상태에서 Down/Up이 두 Entry 사이를 이동한다.
    /// - 사전 조건: first Entry, empty/error status row, second Entry 순서의 visible outline
    /// - 기대 결과: 두 방향 모두 status row를 건너뛰고 대상 Entry만 선택한다.
    func testKeyboardNavigationSkipsNonSelectableStatusRows() throws {
        let first = makePresentationFile(id: "/root/first.txt", name: "first.txt")
        let second = makePresentationFile(id: "/root/second.txt", name: "second.txt")
        let fixture = Task4Fixture(
            entries: [first, second],
            groups: [],
            selected: first.id,
        )
        fixture.coordinator.outlineItems.insert(
            EntryListOutlineItem(kind: .empty(parent: "/root/empty-folder")),
            at: 1,
        )
        fixture.coordinator.outlineItems.insert(
            EntryListOutlineItem(
                kind: .error(parent: "/root/error-folder", failure: .permissionDenied),
            ),
            at: 2,
        )
        fixture.coordinator.rebuildItemIndexes()
        fixture.tableView.reloadData()
        fixture.coordinator.syncListSelectionFromStore()

        try fixture.keyDown(.downArrow)
        fixture.assertSelection([second.id], focus: second.id, rows: [3], updates: 1)
        fixture.setSelection([second.id], focus: second.id)
        try fixture.keyDown(.upArrow)
        fixture.assertSelection([first.id], focus: first.id, rows: [0], updates: 3)
    }

    /// EVM-002-update_entry_selection: projection 교체는 stale occurrence를 버리고 canonical focus와 anchor에서
    /// 새 occurrence를 다시 찾는다.
    func testGroupedRowsReseedAfterProjectionReplacement() throws {
        let entries = ["a", "b", "c"].map {
            makePresentationFile(id: "/root/\($0).txt", name: "\($0).txt")
        }
        let fixture = Task4Fixture(
            entries: entries,
            groups: [("G1", entries)],
            selected: entries[1].id,
        )
        let oldOccurrence = try XCTUnwrap(fixture.coordinator.entryItemsByID[entries[1].id]?.first)
        fixture.replaceProjectionWithFreshItems()
        let newOccurrence = try XCTUnwrap(fixture.coordinator.entryItemsByID[entries[1].id]?.first)
        XCTAssertNotIdentical(oldOccurrence, newOccurrence)
        XCTAssertEqual(fixture.tableView.selectedRowIndexes, IndexSet(integer: 2))
        try fixture.keyDown(.downArrow, modifiers: .shift)
        fixture.assertSelection(
            Set(entries[1 ... 2].map(\.id)),
            focus: entries[2].id,
            anchor: entries[1].id,
            rows: IndexSet(integersIn: 2 ... 3),
            updates: 1,
        )
        fixture.coordinator.outlineViewSelectionDidChange(Notification(name: .init("stale")))
        fixture.assertSelection(
            Set(entries[1 ... 2].map(\.id)),
            focus: entries[2].id,
            anchor: entries[1].id,
            rows: IndexSet(integersIn: 2 ... 3),
            updates: 1,
        )
        fixture.tableView.invalidateSelectionProjection()
        try fixture.keyDown(.upArrow, modifiers: .shift)
        fixture.assertSelection([entries[0].id], focus: entries[0].id, rows: IndexSet(integer: 1), updates: 2)

        let reordered = Task4Fixture(entries: entries, groups: [("G1", entries), ("G2", entries)])
        try reordered.selectGroup(named: "G1")
        reordered.tableView.invalidateSelectionProjection()
        reordered.coordinator.outlineItems.reverse()
        reordered.tableView.reloadData()
        reordered.coordinator.rebuildItemIndexes()
        reordered.coordinator.syncListSelectionFromStore()
        XCTAssertTrue(try reordered.groupRowIsSelected(reordered.groupRow(named: "G1")))
        XCTAssertFalse(try reordered.groupRowIsSelected(reordered.groupRow(named: "G2")))
    }

    // MARK: - EVM-002-toggle_directory_expansion_in_list

    /// EVM-002-toggle_directory_expansion_in_list: stale revision callback은 현재 hierarchy나 selection으로 전달되지 않는다.
    func testStaleProjectionIntentIsIgnored() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.hierarchy = .init(rootPath: "/root")
        state.outlineProjectionRevision = 2
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.sendProjectionIntent(.disclosureExpand(folder.id, revision: 1))
        XCTAssertFalse(store.state.hierarchy.expandedFolderIDs.contains(folder.id))
        coordinator.sendProjectionIntent(.disclosureExpand(folder.id, revision: 2))
        XCTAssertTrue(store.state.hierarchy.expandedFolderIDs.contains(folder.id))
    }

    /// EVM-002-toggle_directory_expansion_in_list: projection 교체는 이전 revision item instance를 재사용하지 않는다.
    func testProjectionReloadRebuildsOutlineItems() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let session = EntryListCoordinatorProjectionSession()
        var firstItem: EntryListOutlineItem?
        session.apply(outlineProjection(revision: 1, roots: [folder])) { _, items in
            firstItem = items.first
        }
        session.apply(outlineProjection(revision: 2, roots: [folder])) { _, items in
            XCTAssertEqual(items.first?.id, firstItem?.id)
            XCTAssertNotIdentical(items.first, firstItem)
        }
    }

    /// EVM-002-toggle_directory_expansion_in_list: 같은 revision의 구조 변경도 최신 projection을 적용한다.
    /// 정렬이나 metadata patch가 ID 집합을 유지한 채 sibling 순서만 바꾸는 경계를 검증한다.
    func testSameRevisionStructuralChangeReappliesProjection() {
        let first = EntryModel.temporaryFolder(id: "/root/first", name: "a")
        let second = EntryModel.temporaryFolder(id: "/root/second", name: "b")
        let renamedFirst = EntryModel.temporaryFolder(id: first.id, name: "z")
        let renamedSecond = EntryModel.temporaryFolder(id: second.id, name: "a")
        let session = EntryListCoordinatorProjectionSession()
        var appliedRootIDs: [[EntryListOutlineProjection.ItemID]] = []
        session.apply(outlineProjection(revision: 1, roots: [first, second])) { projection, _ in
            appliedRootIDs.append(projection.rootItemIDs)
        }
        session.apply(outlineProjection(revision: 1, roots: [renamedFirst, renamedSecond])) { projection, _ in
            appliedRootIDs.append(projection.rootItemIDs)
        }
        XCTAssertEqual(appliedRootIDs, [
            [.entry(first.id), .entry(second.id)],
            [.entry(second.id), .entry(first.id)],
        ])
    }

    /// EVM-002-toggle_directory_expansion_in_list: outline view delegate expand는 store에 folderExpansionRequested를 전달한다.
    /// 키보드 right-arrow가 NSOutlineView.expandItem을 호출하고 delegate callback이 coordinator를 통해 store action으로 전달되는 경로를 검증한다.
    func testOutlineExpandDelegateRequestsFolderExpansion() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.hierarchy = .init(rootPath: "/root")
        state.outlineProjectionRevision = 1
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: EntryListView(frame: .zero))
        coordinator.applyStoreProjection(outlineProjection(revision: 1, roots: [folder]))

        guard let item = coordinator.entryItemById[folder.id] else {
            XCTFail("entryItemById should contain the folder after projection apply")
            return
        }
        let notification = Notification(
            name: NSOutlineView.itemDidExpandNotification,
            object: nil,
            userInfo: ["NSObject": item],
        )
        coordinator.outlineViewItemDidExpand(notification)

        XCTAssertTrue(store.state.hierarchy.expandedFolderIDs.contains(folder.id))
    }

    /// EVM-002-toggle_directory_expansion_in_list: 빈 child-list key가 있는 projection은 folder expansion을 적용한다.
    func testProjectionWithEmptyChildListKeyAppliesFolderExpansion() throws {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.hierarchy = .init(rootPath: "/root")
        state.outlineProjectionRevision = 1
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: EntryListView(frame: .zero))

        coordinator.applyStoreProjection(outlineProjection(revision: 1, roots: [folder]))

        let item = try XCTUnwrap(coordinator.entryItemById[folder.id])
        XCTAssertTrue(coordinator.tableView.isItemExpanded(item))
    }

    /// EVM-002-toggle_directory_expansion_in_list: expanded empty topology에서 root-only projection으로 전환하면 folder를 물리적으로
    /// 접는다.
    /// - 검증 내용: 이전 projection의 children topology가 남아 있으면 새 projection의 visible row 수가 같아도 full reload와 collapse 동기화를
    /// 실행하는지 검증한다.
    /// - 사전 조건: 빈 children key를 가진 expanded folder projection이 적용된 뒤 같은 folder의 collapsed root-only projection이 도착한다.
    /// - 기대 결과: full reload 뒤 새로 reacquire한 outline item이 물리적으로 collapsed 상태다.
    func testExpandedEmptyTopologyCollapsesOnRootOnlyProjection() throws {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.hierarchy = .init(rootPath: "/root")
        state.outlineProjectionRevision = 1
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: EntryListView(frame: .zero))

        coordinator.applyStoreProjection(outlineProjection(revision: 1, roots: [folder]))
        let expandedItem = try XCTUnwrap(coordinator.entryItemById[folder.id])
        XCTAssertTrue(coordinator.tableView.isItemExpanded(expandedItem))

        var collapsedHierarchy = EntryListHierarchyState(rootPath: "/root")
        collapsedHierarchy.setExpandedIDs([])
        let collapsedProjection = EntryListOutlineProjection(
            revision: 2,
            rootEntries: [folder],
            hierarchyState: collapsedHierarchy,
            context: .init(mode: .list, isNormalDirectoryPage: true, hasActiveGrouping: false),
            sortKey: .name,
            sortOrder: .ascending,
        )
        coordinator.applyStoreProjection(collapsedProjection)

        let collapsedItem = try XCTUnwrap(coordinator.entryItemById[folder.id])
        XCTAssertFalse(coordinator.tableView.isItemExpanded(collapsedItem))
    }

    /// EVM-002-toggle_directory_expansion_in_list: outline view delegate collapse는 store에 folderCollapseRequested를
    /// 전달한다.
    /// 키보드 left-arrow가 NSOutlineView.collapseItem을 호출하고 delegate callback이 coordinator를 통해 store action으로 전달되는 경로를
    /// 검증한다.
    /// - 검증 내용: outlineViewItemDidCollapse가 hierarchy-enabled entry에서 store에 collapse request를 발생시킨다.
    /// - 사전 조건: /root/a folder가 expanded 상태로 projection revision 1에 렌더돼 있다.
    /// - 기대 결과: delegate collapse 후 store의 expandedFolderIDs에서 /root/a가 제거된다.
    func testOutlineCollapseDelegateRequestsFolderCollapse() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.hierarchy = .init(rootPath: "/root")
        state.hierarchy.setExpandedIDs([folder.id])
        state.outlineProjectionRevision = 1
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: EntryListView(frame: .zero))
        coordinator.applyStoreProjection(outlineProjection(revision: 1, roots: [folder]))

        guard let item = coordinator.entryItemById[folder.id] else {
            XCTFail("entryItemById should contain the folder after projection apply")
            return
        }
        let notification = Notification(
            name: NSOutlineView.itemDidCollapseNotification,
            object: nil,
            userInfo: ["NSObject": item],
        )
        coordinator.outlineViewItemDidCollapse(notification)

        XCTAssertFalse(store.state.hierarchy.expandedFolderIDs.contains(folder.id))
    }

    /// EVM-002-toggle_directory_expansion_in_list: render settle 전 연속 expand/collapse 입력도 순서대로 반영한다.
    /// 사용자가 disclosure를 빠르게 두 번 조작해도 이전 rendered revision gate가 두 번째 입력을 버리지 않는지 검증한다.
    /// - 검증 내용: 같은 outline item의 expand callback 직후 collapse callback이 canonical view action 경계를 통과한다.
    /// - 사전 조건: revision 1의 collapsed folder가 렌더되어 있고 첫 callback 뒤 store revision만 먼저 증가한다.
    /// - 기대 결과: render loop가 새 projection을 적용하기 전에도 최종 hierarchy 상태는 collapsed다.
    func testRapidExpandThenCollapseBeforeRenderSettles() throws {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.hierarchy = .init(rootPath: "/root")
        state.outlineProjectionRevision = 1
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: EntryListView(frame: .zero))

        let item = try XCTUnwrap(coordinator.entryItemById[folder.id])
        coordinator.outlineViewItemDidExpand(Notification(
            name: NSOutlineView.itemDidExpandNotification,
            object: nil,
            userInfo: ["NSObject": item],
        ))
        XCTAssertTrue(store.state.hierarchy.expandedFolderIDs.contains(folder.id))

        coordinator.outlineViewItemDidCollapse(Notification(
            name: NSOutlineView.itemDidCollapseNotification,
            object: nil,
            userInfo: ["NSObject": item],
        ))

        XCTAssertFalse(store.state.hierarchy.expandedFolderIDs.contains(folder.id))
    }

    /// EVM-002-toggle_directory_expansion_in_list: list로 시작한 뒤 첫 entries load가 도착하면 초기 rows를 렌더링한다.
    /// 사용자가 list mode로 앱을 열었을 때 첫 store emission과 entry load가 같은 main queue turn에 도착하는 경계를 검증한다.
    /// - 검증 내용: initial bind 직후 entries가 채워져도 coordinator가 첫 populated snapshot을 table rows로 반영한다.
    /// - 사전 조건: list와 collection mode가 활성화된 빈 state에 coordinator를 bind하고 즉시 한 entry를 전달한다.
    /// - 기대 결과: store와 table view 모두 한 entry를 보유하며 list가 빈 상태로 남지 않는다.
    func testListColdStartRendersFirstLoadedEntries() async {
        var state = EntryViewLayoutState()
        state.isCollectionMode = true
        let store = Store(initialState: state) {
            EntryViewLayoutFeature()
        }
        let coordinator = EntryListCoordinator(store: store)
        let view = EntryListView(frame: .zero)
        let entry = EntryModel.temporaryFolder(id: "/root/a", name: "a")

        coordinator.bind(to: view)
        store.send(.internal(.setCollectionItems([entry])))
        let renderSettled = expectation(description: "list render settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            renderSettled.fulfill()
        }
        await fulfillment(of: [renderSettled], timeout: 1)

        XCTAssertEqual(store.withState { $0.entries.map(\.id) }, [entry.id])
        XCTAssertEqual(view.tableView.numberOfRows, 1)
    }

    /// EVM-002-toggle_directory_expansion_in_list: guarded programmatic apply 중 newest pending revision만 보관한다.
    /// - 검증 내용: reentrant update는 newest revision만 pending slot에 보관한다.
    /// - 사전 조건: revision 1 apply callback 안에서 revision 2와 stale revision 1을 요청한다.
    /// - 기대 결과: apply 중 guard가 활성화되고 종료 뒤 revision 2만 rendered 된다.
    func testProgrammaticApplyKeepsNewestPendingProjection() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let session = EntryListCoordinatorProjectionSession()
        var appliedRevisions: [Int] = []

        session.apply(outlineProjection(revision: 1, roots: [folder])) { projection, _ in
            appliedRevisions.append(projection.revision)
            XCTAssertTrue(session.isApplyingStoreProjection)
            session.apply(outlineProjection(revision: 2, roots: [folder])) { pendingProjection, _ in
                appliedRevisions.append(pendingProjection.revision)
            }
            session.apply(outlineProjection(revision: 1, roots: [folder])) { _, _ in
                XCTFail("older projection must not replace the pending revision")
            }
        }

        XCTAssertEqual(appliedRevisions, [1, 2])
        XCTAssertEqual(session.renderedProjectionRevision, 2)
        XCTAssertFalse(session.isApplyingStoreProjection)
        XCTAssertNil(session.pendingProjection)
    }

    // MARK: - EVM-002-flat_projection_session_coalescing

    /// EVM-002-flat_projection_session_coalescing: flat rebuild는 projection session revision을 유지한다.
    /// flat 구조 reload가 session reset을 우회하지 않고 동일한 revision gate를 사용하는지 검증한다.
    /// - 검증 내용: flat coordinator bind가 flat projection을 session에 적용하고 반복 rebuild가 동일 구조를 dedup한다.
    /// - 사전 조건: hierarchy가 비활성화된 list state에 두 root entry가 있다.
    /// - 기대 결과: bind와 반복 rebuild 뒤 rendered revision은 유지되고 두 번째 rebuild는 projection을 교체하지 않는다.
    func testFlatRebuildUsesProjectionSessionRevisionGate() {
        let first = EntryModel.temporaryFolder(id: "/root/first", name: "first")
        let second = EntryModel.temporaryFolder(id: "/root/second", name: "second")
        var state = EntryViewLayoutState()
        state.entries = [first, second]
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)

        coordinator.bind(to: EntryListView(frame: .zero))
        XCTAssertEqual(coordinator.renderedProjectionRevision, 0)
        let firstRenderedItem = coordinator.outlineItems.first

        coordinator.rebuildRowsAndReload()

        XCTAssertEqual(coordinator.renderedProjectionRevision, 0)
        XCTAssertIdentical(coordinator.outlineItems.first, firstRenderedItem)
    }

    /// EVM-002-flat_projection_session_coalescing: flat apply는 newest pending projection의 item payload를 함께 유지한다.
    /// - 검증 내용: flatItems overload의 reentrant apply가 revision 2와 concrete item identity를 보존하고 stale revision callback을
    /// 배제한다.
    /// - 사전 조건: revision 1 callback 중 revision 2 flat projection과 stale revision 1 flat projection이 순서대로 도착한다.
    /// - 기대 결과: callback revision은 [1, 2]이고 revision 2 item만 적용되며 rendered/pending 상태가 정리된다.
    func testFlatApplyKeepsNewestPendingItemsAndIgnoresStaleRevision() {
        let first = EntryModel.temporaryFolder(id: "/root/first", name: "first")
        let second = EntryModel.temporaryFolder(id: "/root/second", name: "second")
        let stale = EntryModel.temporaryFolder(id: "/root/stale", name: "stale")
        let session = EntryListCoordinatorProjectionSession()
        let firstItem = EntryListOutlineItem(kind: .entry(first))
        let secondItem = EntryListOutlineItem(kind: .entry(second))
        let staleItem = EntryListOutlineItem(kind: .entry(stale))
        var appliedRevisions: [Int] = []
        var appliedItemIDs: [[String]] = []

        session.apply(
            outlineProjection(revision: 1, roots: [first]),
            flatItems: [firstItem],
        ) { projection, items in
            appliedRevisions.append(projection.revision)
            appliedItemIDs.append(items.map(\.id))
            XCTAssertTrue(session.isApplyingStoreProjection)

            session.apply(
                outlineProjection(revision: 2, roots: [second]),
                flatItems: [secondItem],
            ) { pendingProjection, pendingItems in
                appliedRevisions.append(pendingProjection.revision)
                appliedItemIDs.append(pendingItems.map(\.id))
                XCTAssertIdentical(pendingItems.first, secondItem)
                XCTAssertEqual(pendingProjection.rootItemIDs, [.entry(second.id)])
            }
            session.apply(
                outlineProjection(revision: 1, roots: [stale]),
                flatItems: [staleItem],
            ) { _, _ in
                XCTFail("stale flat projection must not invoke its callback")
            }
        }

        XCTAssertEqual(appliedRevisions, [1, 2])
        XCTAssertEqual(appliedItemIDs, [[firstItem.id], [secondItem.id]])
        XCTAssertEqual(session.renderedProjectionRevision, 2)
        XCTAssertFalse(session.isApplyingStoreProjection)
        XCTAssertNil(session.pendingProjection)
    }

    /// EVM-002-toggle_directory_expansion_in_list: hierarchy render는 저장된 scroll 위치를 복원한다.
    /// flat render와 동일하게 outline projection 적용 뒤 saved offset restore가 실행되는지 검증한다.
    /// - 검증 내용: hierarchy-enabled initial bind의 scroll restore completion flag
    /// - 사전 조건: root entry와 savedScrollOffset이 있고 hierarchy root context가 활성화돼 있다.
    /// - 기대 결과: coordinator가 hierarchy projection 적용 후 scroll 복원을 완료한다.
    func testHierarchyProjectionRestoresSavedScrollPosition() {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        var state = EntryViewLayoutState()
        state.entries = [folder]
        state.hierarchy = .init(rootPath: "/root")
        state.savedScrollOffset = CGPoint(x: 0, y: 20)
        let coordinator = EntryListCoordinator(store: Store(initialState: state) {
            EntryViewLayoutFeature()
        })
        let view = EntryListView(frame: .zero)

        coordinator.bind(to: view)

        XCTAssertEqual(view.scrollView.contentView.bounds.origin, CGPoint(x: 0, y: 20))
    }

    // MARK: - EVM-002-entry_id_row_anchor_structural_reload

    /// EVM-002-entry_id_row_anchor_structural_reload: 구조 reload 뒤 동일 entry의 화면상 pixel offset을 보존한다.
    /// - 검증 내용: 새 row가 anchor 위에 삽입되어 기존 row index가 변해도 top visible entry ID와 pixel offset을 복원한다.
    /// - 사전 조건: 세 entry를 렌더한 뒤 중간 entry를 top visible anchor로 두고 앞에 새 entry를 삽입한다.
    /// - 기대 결과: 구조 변경 후에도 동일 entry가 같은 pixel offset에 남는다.
    func testStructuralReloadPreservesTopVisibleEntryAnchor() throws {
        let anchor = EntryModel.temporaryFolder(id: "/root/anchor", name: "anchor")
        let last = EntryModel.temporaryFolder(id: "/root/last", name: "last")
        let inserted = EntryModel.temporaryFolder(id: "/root/inserted", name: "inserted")
        var state = EntryViewLayoutState()
        state.entries = [anchor, last]
        state.entryOperations.items = [anchor, last]
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        let view = EntryListView(frame: NSRect(x: 0, y: 0, width: 400, height: 20))

        coordinator.bind(to: view)
        view.layoutSubtreeIfNeeded()
        let anchorItem = try XCTUnwrap(coordinator.entryItemById[anchor.id])
        let anchorRow = coordinator.tableView.row(forItem: anchorItem)
        let anchorRect = coordinator.tableView.rect(ofRow: anchorRow)
        coordinator.scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: anchorRect.origin.y - 7))
        coordinator.tableView.layoutSubtreeIfNeeded()
        coordinator.tableView.scrollRowToVisible(anchorRow)
        coordinator.scrollView.contentView.setBoundsOrigin(NSPoint(
            x: 0,
            y: coordinator.tableView.rect(ofRow: anchorRow).origin.y - 7,
        ))
        let beforeRows = coordinator.tableView.rows(in: coordinator.scrollView.contentView.bounds)
        let beforeTopItem = try XCTUnwrap(coordinator.tableView
            .item(atRow: beforeRows.location) as? EntryListOutlineItem)
        guard case let .entry(beforeTopEntry) = beforeTopItem.kind else {
            return XCTFail("Top visible item must be an entry")
        }
        let beforeOffset = coordinator.tableView.rect(ofRow: beforeRows.location).origin.y
            - coordinator.scrollView.contentView.bounds.origin.y

        store.send(.internal(.setCollectionItems([anchor, inserted, last])))
        coordinator.processRender(EntryListCoordinatorRenderSnapshot(state: store.state))

        let afterRows = coordinator.tableView.rows(in: coordinator.scrollView.contentView.bounds)
        let afterTopItem = try XCTUnwrap(coordinator.tableView.item(atRow: afterRows.location) as? EntryListOutlineItem)
        guard case let .entry(afterTopEntry) = afterTopItem.kind else {
            return XCTFail("Top visible item must be an entry")
        }
        let afterOffset = coordinator.tableView.rect(ofRow: afterRows.location).origin.y
            - coordinator.scrollView.contentView.bounds.origin.y

        XCTAssertEqual(beforeTopEntry.id, anchor.id)
        XCTAssertEqual(afterTopEntry.id, anchor.id)
        XCTAssertEqual(afterOffset, beforeOffset, accuracy: 1)

        let beforeColumnReload = try XCTUnwrap(topVisibleEntryAndOffset(for: coordinator))
        var previousColumnState = state
        previousColumnState.listVisibleColumns = [.name, .size]
        coordinator.handleVisibleColumnsChange(
            previous: EntryListCoordinatorRenderSnapshot(state: previousColumnState),
            snapshot: EntryListCoordinatorRenderSnapshot(state: state),
        )
        let afterColumnReload = try XCTUnwrap(topVisibleEntryAndOffset(for: coordinator))
        XCTAssertEqual(afterColumnReload.id, beforeColumnReload.id)
        XCTAssertEqual(afterColumnReload.offset, beforeColumnReload.offset, accuracy: 1)

        var metricState = state
        metricState.listIconSize = 40
        metricState.listTextSize = 18
        let beforeMetricReload = try XCTUnwrap(topVisibleEntryAndOffset(for: coordinator))
        coordinator.updateListMetricsIfNeeded(
            previous: EntryListCoordinatorRenderSnapshot(state: state),
            snapshot: EntryListCoordinatorRenderSnapshot(state: metricState),
        )
        let afterMetricReload = try XCTUnwrap(topVisibleEntryAndOffset(for: coordinator))
        XCTAssertEqual(afterMetricReload.id, beforeMetricReload.id)
        XCTAssertEqual(afterMetricReload.offset, beforeMetricReload.offset, accuracy: 1)
    }

    /// EVM-002-entry_id_row_anchor_structural_reload: 제거된 anchor는 남은 첫 row로 안전하게 대체된다.
    /// - 검증 내용: 구조 변경으로 anchor entry가 없어질 때 stale row/item 접근 없이 남은 visible row를 사용한다.
    /// - 사전 조건: anchor가 top visible row이고 structural projection에서 anchor가 제거된다.
    /// - 기대 결과: 남은 entry가 table의 top visible row가 된다.
    func testStructuralReloadFallsBackWhenTopVisibleEntryIsRemoved() throws {
        let anchor = EntryModel.temporaryFolder(id: "/root/anchor", name: "anchor")
        let retained = EntryModel.temporaryFolder(id: "/root/retained", name: "retained")
        var state = EntryViewLayoutState()
        state.entries = [anchor, retained]
        state.hierarchy = .init(rootPath: "/root")
        state.outlineProjectionRevision = 1
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        let view = EntryListView(frame: NSRect(x: 0, y: 0, width: 400, height: 20))

        coordinator.bind(to: view)
        view.layoutSubtreeIfNeeded()
        let anchorItem = try XCTUnwrap(coordinator.entryItemById[anchor.id])
        coordinator.tableView.scrollRowToVisible(coordinator.tableView.row(forItem: anchorItem))
        coordinator.applyStoreProjection(outlineProjection(revision: 2, roots: [retained]))

        let rows = coordinator.tableView.rows(in: coordinator.scrollView.contentView.bounds)
        let topItem = try XCTUnwrap(coordinator.tableView.item(atRow: rows.location) as? EntryListOutlineItem)
        guard case let .entry(topEntry) = topItem.kind else {
            return XCTFail("Fallback row must be an entry")
        }
        XCTAssertEqual(topEntry.id, retained.id)
    }

    private func topVisibleEntryAndOffset(
        for coordinator: EntryListCoordinator,
    ) -> (id: EntryModel.ID, offset: CGFloat)? {
        let rows = coordinator.tableView.rows(in: coordinator.scrollView.contentView.bounds)
        guard rows.location != NSNotFound,
              rows.length > 0,
              let item = coordinator.tableView.item(atRow: rows.location) as? EntryListOutlineItem,
              case let .entry(entry) = item.kind
        else {
            return nil
        }
        let offset = coordinator.tableView.rect(ofRow: rows.location).origin.y
            - coordinator.scrollView.contentView.bounds.origin.y
        return (entry.id, offset)
    }

    /// EVM-002-toggle_directory_expansion_in_list: root 삭제는 남은 outline item identity를 보존한다.
    /// - 검증 내용: 이동 완료 후 단순 root 삭제가 전체 graph 교체 없이 기존 row 객체를 유지한다.
    /// - 사전 조건: 두 root entry가 렌더된 hierarchy projection에서 첫 entry만 제거된다.
    /// - 기대 결과: 남은 entry의 coordinator index가 삭제 전과 동일한 outline item을 가리킨다.
    func testRootRemovalPreservesRetainedOutlineItemIdentity() {
        let removed = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let retained = EntryModel.temporaryFolder(id: "/root/b", name: "b")
        var state = EntryViewLayoutState()
        state.entries = [removed, retained]
        state.entryOperations.items = [removed, retained]
        state.hierarchy = .init(rootPath: "/root")
        state.hierarchy.setExpandedIDs([removed.id, retained.id])
        let coordinator = EntryListCoordinator(store: Store(initialState: state) {
            EntryViewLayoutFeature()
        })
        coordinator.bind(to: EntryListView(frame: .zero))
        let retainedItem = coordinator.entryItemById[retained.id]

        coordinator.applyStoreProjection(outlineProjection(revision: 1, roots: [retained]))

        XCTAssertNotNil(retainedItem)
        XCTAssertIdentical(coordinator.entryItemById[retained.id], retainedItem)
    }

    /// EVM-002-set_entries_view_as_icon_grid: 단순 root 삭제는 grid 전체 section reload를 요구하지 않는다.
    /// - 검증 내용: 이동 완료로 ID 하나만 제거된 snapshot이 incremental removal 경로로 분류된다.
    /// - 사전 조건: 동일한 ungrouped grid에서 [a, b]가 [b]로 바뀐다.
    /// - 기대 결과: coordinator가 전체 section rebuild를 선택하지 않는다.
    func testGridRootRemovalDoesNotRequireFullSectionReload() {
        let removed = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let retained = EntryModel.temporaryFolder(id: "/root/b", name: "b")
        var previousState = EntryViewLayoutState()
        previousState.isCollectionMode = true
        previousState.entries = [removed, retained]
        let store = Store(initialState: previousState) {
            EntryViewLayoutFeature()
        }
        let coordinator = EntryGridCoordinator(store: store)
        let view = EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        coordinator.bind(to: view)
        coordinator.isRenderObservationEnabled = false
        store.send(.internal(.setCollectionItems([retained])))
        let snapshot = EntryGridRenderSnapshot(state: store.state)

        XCTAssertFalse(coordinator.shouldRebuildSections(
            previous: EntryGridRenderSnapshot(state: previousState),
            snapshot: snapshot,
            changes: snapshot.presentation.changes(from: EntryGridRenderSnapshot(state: previousState).presentation),
        ))
        coordinator.handleSnapshotChanges(
            previous: EntryGridRenderSnapshot(state: previousState),
            snapshot: snapshot,
        )
        XCTAssertEqual(coordinator.sections.flatMap(\.items).map(\.id), [retained.id])
        XCTAssertEqual(view.collectionView.numberOfItems(inSection: 0), 1)
    }

    /// EVM-002-set_entries_view_as_icon_grid: payload-only 갱신은 grid section의 entry 모델도 교체한다.
    /// - 검증 내용: 같은 ID의 name 변경이 전체 reload 없이 coordinator section data source에 반영된다.
    /// - 사전 조건: collection mode grid에 old 이름의 entry가 렌더되어 있고 같은 ID의 새 payload가 도착한다.
    /// - 기대 결과: targeted item refresh 뒤 section이 새 이름을 제공한다.
    func testGridPayloadRefreshUpdatesSectionEntry() {
        let original = EntryModel.temporaryFolder(id: "/root/a", name: "old")
        let updated = EntryModel.temporaryFolder(id: original.id, name: "new")
        var state = EntryViewLayoutState()
        state.isCollectionMode = true
        state.entries = [original]
        let store = Store(initialState: state) {
            EntryViewLayoutFeature()
        }
        let coordinator = EntryGridCoordinator(store: store)
        coordinator.bind(to: EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240)))
        coordinator.isRenderObservationEnabled = false
        let previous = EntryGridRenderSnapshot(state: state)

        store.send(.internal(.setCollectionItems([updated])))
        let snapshot = EntryGridRenderSnapshot(state: store.state)
        coordinator.reloadVisibleItemsForEntryContentChange(
            snapshot: snapshot,
            changes: snapshot.presentation.changes(from: previous.presentation),
        )

        XCTAssertEqual(coordinator.sections.first?.items.first?.name, updated.name)
    }

    /// EVM-002-switch_entries_view: grid와 list는 같은 grouped presentation section을 사용한다.
    /// - 검증 내용: 두 coordinator가 section 순서, 제목, 항목 순서를 공통 projection에서 읽는다.
    /// - 사전 조건: Folders와 Text 두 section이 state에 투영돼 있다.
    /// - 기대 결과: grid section과 list group row가 동일한 두 section을 표현한다.
    func testGridAndListConsumeSharedGroupedSections() {
        let folder = EntryModel.temporaryFolder(id: "/root/folder", name: "folder")
        let file = makePresentationFile(id: "/root/file.txt", name: "file.txt")
        var state = EntryViewLayoutState()
        state.entryArrangements.groupKey = .kind
        state.entries = [folder, file]
        state.entryArrangements.groupedItems = [
            .init(groupName: "Folders", items: [folder]),
            .init(groupName: "Text", items: [file]),
        ]
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let grid = EntryGridCoordinator(store: store)
        let list = EntryListCoordinator(store: store)

        let gridSections = grid.makeSections(state: state)
        let listItems = list.makeOutlineItems(state: state)

        XCTAssertEqual(gridSections.compactMap(\.title), ["Folders", "Text"])
        XCTAssertEqual(listItems.compactMap(\.groupName), ["Folders", "Text"])
        XCTAssertEqual(gridSections.flatMap(\.items).map(\.id), [folder.id, file.id])
        XCTAssertEqual(listItems.flatMap { $0.flattenEntries().map(\.0) }, [folder.id, file.id])
    }

    /// EVM-002-switch_entries_view: 빈 groupName 섹션(groupKey .none)은 group header 없이 flat으로 렌더링된다.
    /// - 검증 내용: EntryArrangementsApplyReducer가 groupKey .none일 때 만드는 빈 이름 그룹이
    ///   presentation에서 title nil로 정규화되어 list/grid 모두 group row 없이 entry만 만든다.
    /// - 사전 조건: groupKey가 .none이고 groupedItems가 빈 이름 그룹 하나로 투영됐다 (컬렉션 검색 결과와 동일 구조).
    /// - 기대 결과: grid section title은 nil이고 list outline items는 group row 없이 entry row만 포함한다.
    func testEmptyGroupNameSectionRendersFlatWithoutGroupHeader() {
        let file = makePresentationFile(id: "/root/file.txt", name: "file.txt")
        var state = EntryViewLayoutState()
        state.entryArrangements.groupKey = .none
        state.entries = [file]
        state.entryArrangements.groupedItems = [
            .init(groupName: "", items: [file]),
        ]
        let store = Store(initialState: state) { EntryViewLayoutFeature() }

        XCTAssertNil(state.presentation.sections.first?.title)

        let gridSections = EntryGridCoordinator(store: store).makeSections(state: state)
        let listItems = EntryListCoordinator(store: store).makeOutlineItems(state: state)

        XCTAssertNil(gridSections.first?.title)
        XCTAssertTrue(listItems.allSatisfy { item in
            if case .entry = item.kind { return true }
            return false
        })
        XCTAssertEqual(listItems.flatMap { $0.flattenEntries().map(\.0) }, [file.id])
    }

    /// EVM-002-switch_entries_view: 접힌 group은 grid와 list에서 동일하게 숨겨진다.
    /// - 검증 내용: 공통 section의 collapse 상태가 두 coordinator의 child 가시성에 적용된다.
    /// - 사전 조건: Text section이 collapsed 상태다.
    /// - 기대 결과: grid item은 숨겨지고 list group은 collapsed 상태를 유지한다.
    func testCollapsedSharedSectionHidesItemsInBothLayouts() {
        let file = makePresentationFile(id: "/root/file.txt", name: "file.txt")
        var state = EntryViewLayoutState()
        state.entryArrangements.groupKey = .kind
        state.entryArrangements.collapsedGroups = ["Text"]
        state.entries = [file]
        state.entryArrangements.groupedItems = [
            .init(groupName: "Text", items: [file]),
        ]
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let gridSection = EntryGridCoordinator(store: store).makeSections(state: state)[0]
        let listGroup = EntryListCoordinator(store: store).makeOutlineItems(state: state)[0]

        XCTAssertTrue(gridSection.isCollapsed)
        XCTAssertTrue(gridSection.items.isEmpty)
        guard case let .group(_, _, isCollapsed) = listGroup.kind else {
            return XCTFail("List projection must preserve a group row")
        }
        XCTAssertTrue(isCollapsed)
        XCTAssertEqual(listGroup.children.flatMap { $0.flattenEntries().map(\.0) }, [file.id])
    }

    /// EVM-002-open_with: grid와 list context menu는 같은 Open With application projection을 사용한다.
    /// - 검증 내용: 두 coordinator가 state에 투영된 application cache를 그대로 반환한다.
    /// - 사전 조건: TextEdit application 정보가 공통 presentation에 있다.
    /// - 기대 결과: grid와 list 모두 TextEdit 한 건을 반환한다.
    func testGridAndListConsumeProjectedOpenWithApplications() {
        let file = makePresentationFile(id: "/root/file.txt", name: "file.txt")
        let application = ApplicationInfo(
            id: "com.apple.TextEdit",
            name: "TextEdit",
            bundleID: "com.apple.TextEdit",
            isDefault: true,
        )
        var state = EntryViewLayoutState()
        state.entries = [file]
        state.entryOperations.commonApplicationsForSelectedFiles = [application]
        let store = Store(initialState: state) { EntryViewLayoutFeature() }

        XCTAssertEqual(
            EntryGridCoordinator(store: store).openWithApplications(selectedEntries: [file]),
            [application],
        )
        XCTAssertEqual(
            EntryListCoordinator(store: store).openWithApplications(selectedEntries: [file]),
            [application],
        )
    }

    /// EVM-002-switch_entries_view: 공통 change set은 구조, payload, selection, expansion 변화를 분리한다.
    /// - 검증 내용: 삽입/삭제/갱신 ID와 UI-only semantic flag가 독립적으로 계산된다.
    /// - 사전 조건: retained entry payload가 바뀌고 sibling이 교체되며 selection과 collapse가 바뀐다.
    /// - 기대 결과: 각 변화가 정확한 change-set field에 기록된다.
    func testPresentationChangeSetClassifiesSemanticChanges() {
        let removed = EntryModel.temporaryFolder(id: "/root/removed", name: "removed")
        let original = EntryModel.temporaryFolder(id: "/root/retained", name: "old")
        let updated = EntryModel.temporaryFolder(id: original.id, name: "new")
        let inserted = EntryModel.temporaryFolder(id: "/root/inserted", name: "inserted")
        let previous = EntryViewLayoutPresentation(
            sections: [
                .init(
                    id: "Folders",
                    title: "Folders",
                    colorCode: nil,
                    items: [removed, original],
                    isCollapsed: false,
                ),
            ],
            selectedIds: [removed.id],
            openWithApplications: [],
        )
        let current = EntryViewLayoutPresentation(
            sections: [
                .init(
                    id: "Folders",
                    title: "Folders",
                    colorCode: nil,
                    items: [updated, inserted],
                    isCollapsed: true,
                ),
            ],
            selectedIds: [updated.id],
            openWithApplications: [],
        )

        let changes = current.changes(from: previous)

        XCTAssertTrue(changes.sectionStructureChanged)
        XCTAssertEqual(changes.insertedEntryIDs, [inserted.id])
        XCTAssertEqual(changes.removedEntryIDs, [removed.id])
        XCTAssertEqual(changes.updatedEntryIDs, [updated.id])
        XCTAssertTrue(changes.selectionChanged)
        XCTAssertTrue(changes.groupExpansionChanged)
        XCTAssertFalse(changes.openWithApplicationsChanged)
    }

    // MARK: - EVM-002-rename_entry_inline

    /// EVM-002-rename_entry_inline: list inline rename 중 Escape는 rename-cancel delegate 경로를 사용한다.
    /// 기존 코드는 Escape에서 `.view(.updateSelection(...))`로 selection/scroll 상태를 재설정했지만,
    /// 수정 후에는 `.delegate(.renameCanceled)`만 방출하고 coordinator가 command를 소비한다.
    /// - 검증 내용: Escape가 true를 반환하고 store의 selection/scroll 상태를 변경하지 않는다.
    /// - 사전 조건: renamingItemId가 설정된 list 상태와 coordinator에 연결된 text field가 있다.
    /// - 기대 결과: cancelOperation command가 true를 반환하고 selectedIds/lastSelectedId/shouldScrollToSelection이 유지된다.
    func testEscapeDuringInlineRenameEmitsRenameCanceledDelegateAndConsumesCommand() {
        let renamingId = "/root/renaming"
        let renamingEntry = EntryModel.temporaryFolder(id: renamingId, name: "renaming")
        var state = EntryViewLayoutState()
        state.entries = [renamingEntry]
        state.selectedIds = [renamingId]
        state.lastSelectedId = renamingId
        state.rangeAnchorId = renamingId
        state.entryOperations.renamingItemId = renamingId
        state.shouldScrollToSelection = true

        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)

        let textField = NSTextField()
        textField.delegate = coordinator
        textField.stringValue = "renaming"

        let handled = coordinator.control(
            textField,
            textView: NSTextView(),
            doCommandBy: #selector(NSResponder.cancelOperation(_:)),
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(store.state.selectedIds, [renamingId])
        XCTAssertEqual(store.state.lastSelectedId, renamingId)
        XCTAssertTrue(store.state.shouldScrollToSelection)
    }
}

extension EVM002ManageEntriesViewPresentationTests {
    // MARK: - EVM-002-single_presentation_delta_per_render

    /// EVM-002-single_presentation_delta_per_render: grid 구조 렌더는 emission snapshot presentation을 한 번만 유도해 소비한다.
    /// 구조 rebuild가 live state를 다시 읽지 않고 전달된 snapshot.presentation에서 섹션을 재구성함을 diverged state로 검증한다.
    /// - 검증 내용: handleSnapshotChanges 구조 rebuild 결과 sections가 snapshot의 new entry만 반영하는지 확인
    /// - 사전 조건: store state가 snapshot과 다른 diverged entry를 갖고 previous/snapshot은 rename 형태(old→new)다.
    /// - 기대 결과: 최종 sections가 live state의 diverged entry가 아닌 snapshot의 renamed entry를 포함한다.
    func testGridStructuralRenameRenderConsumesSnapshotPresentationNotLiveState() {
        let old = EntryModel.temporaryFolder(id: "/root/old", name: "old")
        let renamed = EntryModel.temporaryFolder(id: "/root/new", name: "new")
        let diverged = EntryModel.temporaryFolder(id: "/root/diverged", name: "live-diverged")
        var previousState = EntryViewLayoutState()
        previousState.entries = [old]
        var snapshotState = EntryViewLayoutState()
        snapshotState.entries = [renamed]
        var liveState = EntryViewLayoutState()
        liveState.entries = [diverged]

        let store = Store(initialState: liveState) { EntryViewLayoutFeature() }
        let coordinator = EntryGridCoordinator(store: store)
        coordinator.bind(to: EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240)))
        coordinator.isRenderObservationEnabled = false

        coordinator.handleSnapshotChanges(
            previous: EntryGridRenderSnapshot(state: previousState),
            snapshot: EntryGridRenderSnapshot(state: snapshotState),
        )

        XCTAssertEqual(coordinator.sections.flatMap(\.items).map(\.id), [renamed.id])
        XCTAssertEqual(coordinator.sections.flatMap(\.items).map(\.name), ["new"])
    }

    /// EVM-002-single_presentation_delta_per_render: grid payload-only 렌더는 공유 change set과 snapshot presentation을 소비한다.
    /// payload 재적용이 live state.presentation을 다시 유도하지 않음을 diverged state로 검증한다.
    /// - 검증 내용: payload-only 경로 뒤 섹션이 snapshot의 갱신된 이름을 반영하는지 확인
    /// - 사전 조건: 같은 ID의 payload 변화가 담긴 previous/snapshot과 이름이 다른 diverged live state가 있다.
    /// - 기대 결과: 섹션이 live state의 diverged 이름이 아닌 snapshot의 새 이름을 반영한다.
    func testGridPayloadOnlyRenderConsumesSnapshotPresentationNotLiveState() {
        let original = EntryModel.temporaryFolder(id: "/root/a", name: "old")
        let updated = EntryModel.temporaryFolder(id: "/root/a", name: "snapshot-new")
        let diverged = EntryModel.temporaryFolder(id: "/root/a", name: "live-diverged")
        var previousState = EntryViewLayoutState()
        previousState.entries = [original]
        var snapshotState = EntryViewLayoutState()
        snapshotState.entries = [updated]
        var liveState = EntryViewLayoutState()
        liveState.entries = [diverged]

        let store = Store(initialState: liveState) { EntryViewLayoutFeature() }
        let coordinator = EntryGridCoordinator(store: store)
        coordinator.bind(to: EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240)))
        coordinator.isRenderObservationEnabled = false

        coordinator.handleSnapshotChanges(
            previous: EntryGridRenderSnapshot(state: previousState),
            snapshot: EntryGridRenderSnapshot(state: snapshotState),
        )

        XCTAssertEqual(coordinator.sections.first?.items.first?.name, "snapshot-new")
    }

    /// EVM-002-single_presentation_delta_per_render: list flat group expansion rebuild는 snapshot presentation을 직접 소비한다.
    /// groupExpansionChanged 경로가 새 RenderSnapshot/EntryListOutlineProjection 없이 전달된 snapshot.presentation으로
    /// row를 재구성함을 diverged state로 검증한다.
    /// - 검증 내용: groupExpansionChanged 뒤 Text 그룹이 접히고 row가 snapshot의 entry를 반영하는지 확인
    /// - 사전 조건: previous는 Text 그룹이 펼쳐져 있고 snapshot은 접힘 상태며 live state는 다른 payload의 펼침 상태다.
    /// - 기대 결과: Text 그룹은 접히고 row는 live state의 diverged payload가 아닌 snapshot의 file을 포함한다.
    func testListFlatGroupExpansionRebuildConsumesSnapshotPresentationNotLiveState() throws {
        let folder = EntryModel.temporaryFolder(id: "/root/folder", name: "folder")
        let file = makePresentationFile(id: "/root/file.txt", name: "file.txt")
        let divergedFile = makePresentationFile(id: "/root/diverged.txt", name: "live-diverged")
        var previousState = EntryViewLayoutState()
        previousState.entryArrangements.groupKey = .kind
        previousState.entryArrangements.groupedItems = [
            .init(groupName: "Folders", items: [folder]),
            .init(groupName: "Text", items: [file]),
        ]
        var snapshotState = previousState
        snapshotState.entryArrangements.collapsedGroups = ["Text"]
        var liveState = previousState
        liveState.entryArrangements.groupedItems = [
            .init(groupName: "Folders", items: [folder]),
            .init(groupName: "Text", items: [divergedFile]),
        ]

        let store = Store(initialState: liveState) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: EntryListView(frame: .zero))
        coordinator.isRenderObservationEnabled = false

        coordinator.handleSnapshotChanges(
            previous: EntryListCoordinatorRenderSnapshot(state: previousState),
            snapshot: EntryListCoordinatorRenderSnapshot(state: snapshotState),
        )

        let textGroup = try XCTUnwrap(coordinator.groupItemByName["Text"])
        XCTAssertFalse(coordinator.tableView.isItemExpanded(textGroup))
        XCTAssertEqual(
            coordinator.outlineItems.flatMap { $0.flattenEntries().map(\.0) },
            [folder.id, file.id],
        )
    }

    /// EVM-002-single_presentation_delta_per_render: selection-only emission은 grid 구조 재유도를 유발하지 않는다.
    /// selectedIds만 바뀐 emission에서 어떤 렌더 헬퍼도 섹션 데이터 소스를 다시 만들지 않음을 sentinel로 검증한다.
    /// - 검증 내용: selection 차이만 있는 emission에서 sections가 재작성되지 않고 selection만 collection view에 동기화됨
    /// - 사전 조건: 두 entry를 렌더한 뒤 sections를 비운 sentinel 상태로 만들고 previous/snapshot이 selection만 다르다.
    /// - 기대 결과: sentinel sections가 유지되고 collection view 선택이 snapshot selection을 반영한다.
    func testGridSelectionOnlyRenderSkipsStructuralWorkAndSyncsSelection() {
        let first = EntryModel.temporaryFolder(id: "/root/first", name: "first")
        let second = EntryModel.temporaryFolder(id: "/root/second", name: "second")
        var base = EntryViewLayoutState()
        base.entries = [first, second]
        base.selectedIds = [second.id]
        var previousState = base
        previousState.selectedIds = []

        let store = Store(initialState: base) { EntryViewLayoutFeature() }
        let view = EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let coordinator = EntryGridCoordinator(store: store)
        coordinator.bind(to: view)
        coordinator.isRenderObservationEnabled = false
        // sentinel: 어떤 구조 헬퍼든 updateSections를 부르면 live state 내용으로 채워진다.
        coordinator.sections = []

        coordinator.handleSnapshotChanges(
            previous: EntryGridRenderSnapshot(state: previousState),
            snapshot: EntryGridRenderSnapshot(state: base),
        )

        XCTAssertTrue(coordinator.sections.isEmpty, "selection-only emission은 section 재유도를 유발하지 않아야 함")
        XCTAssertEqual(view.collectionView.selectionIndexPaths, [IndexPath(item: 1, section: 0)])
    }

    /// EVM-002-single_presentation_delta_per_render: selection-only emission은 list row 객체를 교체하지 않는다.
    /// - 검증 내용: selection 차이만 있는 emission에서 outline item identity가 유지되고 selection만 동기화됨
    /// - 사전 조건: 두 entry를 렌더한 flat list에 previous/snapshot이 selection만 다르게 주어진다.
    /// - 기대 결과: outline item 인스턴스가 동일하게 유지되고 첫 row가 선택된다.
    func testListSelectionOnlyRenderKeepsOutlineItemsAndSyncsSelection() {
        let first = EntryModel.temporaryFolder(id: "/root/first", name: "first")
        let second = EntryModel.temporaryFolder(id: "/root/second", name: "second")
        var base = EntryViewLayoutState()
        base.entries = [first, second]
        base.selectedIds = [first.id]
        var previousState = base
        previousState.selectedIds = []

        let store = Store(initialState: base) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: EntryListView(frame: .zero))
        coordinator.isRenderObservationEnabled = false
        let boundItems = coordinator.outlineItems

        coordinator.handleSnapshotChanges(
            previous: EntryListCoordinatorRenderSnapshot(state: previousState),
            snapshot: EntryListCoordinatorRenderSnapshot(state: base),
        )

        XCTAssertEqual(coordinator.outlineItems.map(\.id), boundItems.map(\.id))
        for (rendered, bound) in zip(coordinator.outlineItems, boundItems) {
            XCTAssertIdentical(rendered, bound)
        }
        XCTAssertEqual(coordinator.tableView.selectedRowIndexes, IndexSet(integer: 0))
    }

    // MARK: - EVM-002-atomic_identity_swap

    /// EVM-002-atomic_identity_swap: Grid flat rename/move는 full reload 대신 하나의 incremental batch를 사용한다.
    /// - 검증 내용: before-path 한 건이 after-path로 교체된 change set의 rebuild 판정과 최종 selection을 확인한다.
    /// - 사전 조건: unaffected sibling과 선택된 after-path가 있는 단일 identity swap이다.
    /// - 기대 결과: shouldRebuildSections는 false이고 최종 Grid IDs/selection은 after-path다.
    func testGridFlatIdentitySwapUsesIncrementalBatchAndSelectsAfterPath() {
        for operationName in ["rename", "move"] {
            let before = EntryModel.temporaryFolder(id: "/root/\(operationName)-before", name: "before")
            let after = EntryModel.temporaryFolder(id: "/root/\(operationName)-after", name: "after")
            let unaffected = EntryModel.temporaryFolder(id: "/root/unaffected", name: "unaffected")
            var previousState = EntryViewLayoutState()
            previousState.entries = [before, unaffected]
            var currentState = EntryViewLayoutState()
            currentState.entries = [after, unaffected]
            currentState.selectedIds = [after.id]
            currentState.lastSelectedId = after.id

            let store = Store(initialState: currentState) { EntryViewLayoutFeature() }
            let view = EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
            let coordinator = EntryGridCoordinator(store: store)
            coordinator.bind(to: view)
            coordinator.isRenderObservationEnabled = false
            let previous = EntryGridRenderSnapshot(state: previousState)
            let current = EntryGridRenderSnapshot(state: currentState)
            let changes = current.presentation.changes(from: previous.presentation)

            XCTAssertFalse(
                coordinator.shouldRebuildSections(previous: previous, snapshot: current, changes: changes),
                "\(operationName) identity swap는 하나의 Grid batch여야 한다",
            )
            coordinator.handleSnapshotChanges(previous: previous, snapshot: current)

            XCTAssertEqual(coordinator.sections.flatMap(\.items).map(\.id), [after.id, unaffected.id])
            XCTAssertEqual(view.collectionView.selectionIndexPaths, [IndexPath(item: 0, section: 0)])
        }
    }

    /// EVM-002-atomic_identity_swap: Grid identity swap과 같은 emission의 retained payload 갱신은 구조 배치 후 retained
    /// visible 항목을 다시 그려 화면의 이름을 갱신한다.
    /// - 검증 내용: 구조 batch 뒤 retained updated 항목의 보이는 cell이 새 payload로 reconfigure되는지 확인
    /// - 사전 조건: before→after identity swap과 동시에 retained entry payload가 old→new로 바뀐 단일 emission이 있다.
    /// - 기대 결과: full reload 없이 incremental 경로를 쓰며 retained visible cell의 표시 이름이 new가 된다.
    func testGridIdentitySwapReloadsRetainedUpdatedVisibleEntry() throws {
        let before = EntryModel.temporaryFolder(id: "/root/before", name: "before")
        let after = EntryModel.temporaryFolder(id: "/root/after", name: "after")
        let retainedOld = EntryModel.temporaryFolder(id: "/root/retained", name: "old")
        let retainedNew = EntryModel.temporaryFolder(id: retainedOld.id, name: "new")
        var previousState = EntryViewLayoutState()
        previousState.isCollectionMode = true
        previousState.entries = [retainedOld, before]
        var currentState = EntryViewLayoutState()
        currentState.isCollectionMode = true
        currentState.entries = [retainedNew, after]

        let store = Store(initialState: previousState) { EntryViewLayoutFeature() }
        let view = EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let coordinator = EntryGridCoordinator(store: store)
        coordinator.bind(to: view)
        coordinator.isRenderObservationEnabled = false
        view.layoutSubtreeIfNeeded()
        view.collectionView.layoutSubtreeIfNeeded()
        let previous = EntryGridRenderSnapshot(state: previousState)
        let current = EntryGridRenderSnapshot(state: currentState)
        let changes = current.presentation.changes(from: previous.presentation)

        XCTAssertFalse(
            coordinator.shouldRebuildSections(previous: previous, snapshot: current, changes: changes),
            "identity swap + retained payload 갱신은 하나의 Grid batch여야 한다",
        )
        XCTAssertEqual(changes.updatedEntryIDs, [retainedNew.id])

        let retainedIndexPath = try XCTUnwrap(coordinator.indexPathByEntryId[retainedOld.id])
        XCTAssertEqual(try displayedNameOfItem(at: retainedIndexPath, in: view), "old")

        coordinator.handleSnapshotChanges(previous: previous, snapshot: current)

        XCTAssertEqual(coordinator.sections.flatMap(\.items).map(\.id), [retainedNew.id, after.id])
        XCTAssertEqual(try displayedNameOfItem(at: retainedIndexPath, in: view), "new")
    }

    /// EVM-002-atomic_identity_swap: 그룹화된 Grid의 identity swap은 section 구조 변경으로 full rebuild된다.
    /// - 검증 내용: 다중 section에서 두 번째 section 항목 교체 시 rebuild 판정과 최종 Grid IDs/selection을 확인한다.
    /// - 사전 조건: groupKey .name으로 2개 section이 있고 뒤 section에서 단일 swap이 발생한다.
    /// - 기대 결과: swap이 section entryIDs를 바꿔 structureChanged=true가 되고 incremental 경로는 차단된다.
    func testGridGroupedIdentitySwapUsesFullRebuild() {
        let unaffected = EntryModel.temporaryFolder(id: "/root/m-file", name: "m-file")
        let before = EntryModel.temporaryFolder(id: "/root/z-before", name: "z-before")
        let after = EntryModel.temporaryFolder(id: "/root/z-after", name: "z-after")
        var previousState = EntryViewLayoutState()
        previousState.entries = [unaffected, before]
        previousState.entryArrangements.groupKey = .name
        previousState.entryArrangements.groupedItems = [
            .init(groupName: "m", items: [unaffected]),
            .init(groupName: "z", items: [before]),
        ]
        var currentState = EntryViewLayoutState()
        currentState.entries = [unaffected, after]
        currentState.entryArrangements.groupKey = .name
        currentState.entryArrangements.groupedItems = [
            .init(groupName: "m", items: [unaffected]),
            .init(groupName: "z", items: [after]),
        ]
        currentState.selectedIds = [after.id]
        currentState.lastSelectedId = after.id

        let store = Store(initialState: currentState) { EntryViewLayoutFeature() }
        let view = EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let coordinator = EntryGridCoordinator(store: store)
        coordinator.bind(to: view)
        coordinator.isRenderObservationEnabled = false
        let previous = EntryGridRenderSnapshot(state: previousState)
        let current = EntryGridRenderSnapshot(state: currentState)
        let changes = current.presentation.changes(from: previous.presentation)

        XCTAssertGreaterThanOrEqual(previous.presentation.sections.count, 2)
        // sectionStructure는 entryIDs를 포함하므로 단일 swap도 구조 변경으로 분류된다.
        // 이 덕분에 다중 section에서 incremental 경로(section: 0 고정 index)가 차단된다.
        XCTAssertTrue(changes.sectionStructureChanged, "swap은 속한 section의 entryIDs를 바꾼다")
        XCTAssertTrue(
            coordinator.shouldRebuildSections(previous: previous, snapshot: current, changes: changes),
            "다중 section의 identity swap은 full rebuild로 처리돼야 한다",
        )
        coordinator.handleSnapshotChanges(previous: previous, snapshot: current)

        XCTAssertEqual(coordinator.sections.flatMap(\.items).map(\.id), [unaffected.id, after.id])
        XCTAssertEqual(view.collectionView.selectionIndexPaths, [IndexPath(item: 0, section: 1)])
    }

    /// EVM-002-atomic_identity_swap: List flat rename/move는 한 row batch에서 교체하고 unaffected row identity를 유지한다.
    /// - 검증 내용: tryIncrementalFlatRowUpdate 결과와 retained OutlineItem object identity를 확인한다.
    /// - 사전 조건: 한 section에 before-path와 unaffected sibling이 있고 after-path로 교체된다.
    /// - 기대 결과: incremental update가 true이며 unaffected OutlineItem이 `===`로 유지된다.
    func testListFlatIdentitySwapUsesSingleBatchAndRetainsUnaffectedRow() throws {
        for operationName in ["rename", "move"] {
            let before = EntryModel.temporaryFolder(id: "/root/\(operationName)-before", name: "before")
            let after = EntryModel.temporaryFolder(id: "/root/\(operationName)-after", name: "after")
            let unaffected = EntryModel.temporaryFolder(id: "/root/unaffected", name: "unaffected")
            var previousState = EntryViewLayoutState()
            previousState.entries = [before, unaffected]
            var currentState = EntryViewLayoutState()
            currentState.entries = [after, unaffected]
            let store = Store(initialState: previousState) { EntryViewLayoutFeature() }
            let coordinator = EntryListCoordinator(store: store)
            coordinator.bind(to: EntryListView(frame: .zero))
            coordinator.isRenderObservationEnabled = false
            let retainedItem = try XCTUnwrap(coordinator.entryItemById[unaffected.id])
            let previous = EntryListCoordinatorRenderSnapshot(state: previousState)
            let current = EntryListCoordinatorRenderSnapshot(state: currentState)
            let changes = current.presentation.changes(from: previous.presentation)

            XCTAssertTrue(coordinator.tryIncrementalFlatRowUpdate(
                previous: previous.presentation,
                current: current.presentation,
                changes: changes,
            ))

            XCTAssertEqual(coordinator.outlineItems.flatMap { $0.flattenEntries().map(\.0) }, [after.id, unaffected.id])
            XCTAssertIdentical(coordinator.entryItemById[unaffected.id], retainedItem)
        }
    }

    /// EVM-002-atomic_identity_swap: expanded List child rename/move는 parent batch에서 교체하고 sibling identity를 유지한다.
    /// - 검증 내용: applyStoreProjection 뒤 after child/selection과 unaffected child object identity를 확인한다.
    /// - 사전 조건: expanded folder가 before child와 unaffected child를 완전 snapshot으로 표시한다.
    /// - 기대 결과: after child만 남고 selected row가 after이며 unaffected OutlineItem은 `===`다.
    func testExpandedListIdentitySwapRetainsUnaffectedChildAndSelectsAfterPath() throws {
        let folder = EntryModel.temporaryFolder(id: "/root/folder", name: "folder")
        let before = makePresentationFile(id: "/root/folder/before.txt", name: "before.txt")
        let after = makePresentationFile(id: "/root/folder/after.txt", name: "after.txt")
        let unaffected = makePresentationFile(id: "/root/folder/unaffected.txt", name: "unaffected.txt")
        var oldHierarchy = EntryListHierarchyState(rootPath: "/root")
        oldHierarchy.nodesByID[folder.id] = .init(
            children: [before, unaffected],
            loadPhase: .loaded,
            generation: 1,
            expectedBatchIndex: 1,
            coreFinished: true,
        )
        oldHierarchy.setExpandedIDs([folder.id])
        var newHierarchy = oldHierarchy
        newHierarchy.nodesByID[folder.id]?.folder.children = [after, unaffected]
        let oldProjection = EntryListOutlineProjection(
            revision: 1,
            rootEntries: [folder],
            hierarchyState: oldHierarchy,
            context: .init(mode: .list, isNormalDirectoryPage: true, hasActiveGrouping: false),
            sortKey: .name,
            sortOrder: .ascending,
        )
        let newProjection = EntryListOutlineProjection(
            revision: 2,
            rootEntries: [folder],
            hierarchyState: newHierarchy,
            context: .init(mode: .list, isNormalDirectoryPage: true, hasActiveGrouping: false),
            sortKey: .name,
            sortOrder: .ascending,
        )
        var state = EntryViewLayoutState()
        state.mode = .list
        state.entries = [folder]
        state.hierarchy = newHierarchy
        state.selectedIds = [after.id]
        state.lastSelectedId = after.id
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: EntryListView(frame: .zero))
        coordinator.isRenderObservationEnabled = false

        coordinator.applyStoreProjection(oldProjection)
        let retainedItem = try XCTUnwrap(coordinator.entryItemById[unaffected.id])
        coordinator.applyStoreProjection(newProjection)

        XCTAssertEqual(newProjection.visibleSelectableEntryIDs, [folder.id, after.id, unaffected.id])
        XCTAssertIdentical(coordinator.entryItemById[unaffected.id], retainedItem)
        let selectedItem = try XCTUnwrap(coordinator.entryItemById[after.id])
        XCTAssertEqual(coordinator.tableView.selectedRow, coordinator.tableView.row(forItem: selectedItem))
    }

    /// EVM-002-atomic_identity_swap: expanded List child swap은 함께 바뀐 retained sibling row도 다시 그린다.
    /// retained OutlineItem payload만 교체하고 cell reload를 건너뛰는 회귀를 검증한다.
    /// - 검증 내용: child identity swap 뒤 retained sibling object identity와 표시 이름
    /// - 사전 조건: before→after 교체와 retained sibling old→new payload가 같은 projection에 들어온다.
    /// - 기대 결과: retained item은 `===`로 유지되고 보이는 name cell은 구조 batch 뒤 new를 표시한다.
    func testExpandedListIdentitySwapReloadsRetainedSiblingPayload() throws {
        let folder = EntryModel.temporaryFolder(id: "/root/folder", name: "folder")
        let before = makePresentationFile(id: "/root/folder/before.txt", name: "before.txt")
        let after = makePresentationFile(id: "/root/folder/after.txt", name: "after.txt")
        let retainedOld = makePresentationFile(id: "/root/folder/retained.txt", name: "old.txt")
        let retainedNew = makePresentationFile(id: retainedOld.id, name: "new.txt")
        let oldSnapshot = makeExpandedListProjection(revision: 1, folder: folder, children: [before, retainedOld])
        let newSnapshot = makeExpandedListProjection(revision: 2, folder: folder, children: [after, retainedNew])
        var state = EntryViewLayoutState()
        state.mode = .list
        state.entries = [folder]
        state.hierarchy = newSnapshot.hierarchy
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let view = EntryListView(frame: NSRect(x: 0, y: 0, width: 640, height: 320))
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: view)
        coordinator.isRenderObservationEnabled = false

        coordinator.applyStoreProjection(oldSnapshot.projection)
        view.layoutSubtreeIfNeeded()
        coordinator.tableView.layoutSubtreeIfNeeded()
        let retainedItem = try XCTUnwrap(coordinator.entryItemById[retainedOld.id])
        let retainedRow = coordinator.tableView.row(forItem: retainedItem)
        let nameColumn = try XCTUnwrap(coordinator.nameColumnIndex)
        let oldCell = try XCTUnwrap(coordinator.tableView.view(
            atColumn: nameColumn,
            row: retainedRow,
            makeIfNecessary: true,
        ) as? EntryListEntryCellView)
        XCTAssertEqual(oldCell.textField?.stringValue, "old.txt")

        coordinator.applyStoreProjection(newSnapshot.projection)

        let updatedItem = try XCTUnwrap(coordinator.entryItemById[retainedNew.id])
        XCTAssertIdentical(updatedItem, retainedItem)
        let updatedRow = coordinator.tableView.row(forItem: updatedItem)
        let updatedCell = try XCTUnwrap(coordinator.tableView.view(
            atColumn: nameColumn,
            row: updatedRow,
            makeIfNecessary: true,
        ) as? EntryListEntryCellView)
        XCTAssertEqual(updatedCell.textField?.stringValue, "new.txt")
    }

    /// EVM-002-atomic_identity_swap: retained preorder가 같아도 parent topology가 다르면 full rebuild한다.
    /// - 검증 내용: direct child swap과 B(C,D)→B(C(D)) 재배치를 같은 projection change로 적용한다.
    /// - 사전 조건: retained B subtree의 preorder IDs는 [B,C,D]로 같지만 C/D parent 경계가 다르다.
    /// - 기대 결과: incremental merge를 거부하고 rendered B children=[C], C children=[D]가 된다.
    func testExpandedListIdentitySwapRejectsRetainedTopologyChange() throws {
        let root = EntryModel.temporaryFolder(id: "/root/A", name: "A")
        let before = EntryModel.temporaryFolder(id: "/root/A/0-before", name: "0-before")
        let after = EntryModel.temporaryFolder(id: "/root/A/0-after", name: "0-after")
        let folderB = EntryModel.temporaryFolder(id: "/root/A/B", name: "B")
        let folderC = EntryModel.temporaryFolder(id: "/root/A/B/C", name: "C")
        let folderD = EntryModel.temporaryFolder(id: "/root/A/B/D", name: "D")
        var oldHierarchy = EntryListHierarchyState(rootPath: "/root")
        oldHierarchy.nodesByID[root.id] = .init(
            children: [before, folderB], loadPhase: .loaded, generation: 1, coreFinished: true,
        )
        oldHierarchy.nodesByID[folderB.id] = .init(
            children: [folderC, folderD], loadPhase: .loaded, generation: 1, coreFinished: true,
        )
        oldHierarchy.nodesByID[folderC.id] = .init(
            children: [], loadPhase: .loaded, generation: 1, coreFinished: true,
        )
        oldHierarchy.setExpandedIDs([root.id, folderB.id])
        var newHierarchy = oldHierarchy
        newHierarchy.nodesByID[root.id]?.folder.children = [after, folderB]
        newHierarchy.nodesByID[folderB.id]?.folder.children = [folderC]
        newHierarchy.nodesByID[folderC.id]?.folder.children = [folderD]
        newHierarchy.setExpandedIDs([root.id, folderB.id, folderC.id])
        let context = EntryListOutlineProjection.Context(
            mode: .list,
            isNormalDirectoryPage: true,
            hasActiveGrouping: false,
        )
        let oldProjection = EntryListOutlineProjection(
            revision: 1,
            rootEntries: [root],
            hierarchyState: oldHierarchy,
            context: context,
            sortKey: .name,
            sortOrder: .ascending,
        )
        let newProjection = EntryListOutlineProjection(
            revision: 2,
            rootEntries: [root],
            hierarchyState: newHierarchy,
            context: context,
            sortKey: .name,
            sortOrder: .ascending,
        )
        var state = EntryViewLayoutState()
        state.mode = .list
        state.entries = [root]
        state.hierarchy = newHierarchy
        let coordinator = EntryListCoordinator(store: Store(initialState: state) { EntryViewLayoutFeature() })
        coordinator.bind(to: EntryListView(frame: .zero))
        coordinator.isRenderObservationEnabled = false
        func entryIDs(_ items: [EntryListOutlineItem]) -> [EntryModel.ID] {
            items.compactMap { item in
                guard case let .entry(entry) = item.kind else { return nil }
                return entry.id
            }
        }
        func findItem(withID id: EntryModel.ID, in items: [EntryListOutlineItem]) -> EntryListOutlineItem? {
            for item in items {
                if entryIDs([item]) == [id] { return item }
                if let match = findItem(withID: id, in: item.children) { return match }
            }
            return nil
        }

        coordinator.applyStoreProjection(oldProjection)
        var incomingItems: [EntryListOutlineItem] = []
        EntryListCoordinatorProjectionSession().apply(newProjection) { _, items in
            incomingItems = items
        }
        let existingRoot = try XCTUnwrap(coordinator.entryItemById[root.id])
        let existingB = try XCTUnwrap(coordinator.entryItemById[folderB.id])
        let incomingRoot = try XCTUnwrap(findItem(withID: root.id, in: incomingItems))
        let incomingB = try XCTUnwrap(findItem(withID: folderB.id, in: incomingItems))
        XCTAssertEqual(entryIDs(existingRoot.children), [before.id, folderB.id])
        XCTAssertEqual(entryIDs(incomingRoot.children), [after.id, folderB.id])
        XCTAssertEqual(existingB.flattenEntries().map(\.0), [folderB.id, folderC.id, folderD.id])
        XCTAssertEqual(incomingB.flattenEntries().map(\.0), [folderB.id, folderC.id, folderD.id])
        XCTAssertFalse(coordinator.tryIncrementalHierarchyIdentitySwap(items: incomingItems))
        coordinator.applyStoreProjection(newProjection)

        let renderedB = try XCTUnwrap(coordinator.entryItemById[folderB.id])
        let renderedC = try XCTUnwrap(coordinator.entryItemById[folderC.id])
        XCTAssertEqual(entryIDs(renderedB.children), [folderC.id])
        XCTAssertEqual(entryIDs(renderedC.children), [folderD.id])
    }
}

private final class Task4Recorder: @unchecked Sendable {
    var updateCount = 0
    var events: [String] = []
}

@MainActor
private final class Task4Fixture {
    private static var retainedWindows: [NSWindow] = []

    let store: StoreOf<EntryViewLayoutFeature>
    let coordinator: EntryListCoordinator
    let view: EntryListView
    let recorder: Task4Recorder

    var tableView: EntryListView.EntryListTableView {
        view.tableView
    }

    init(
        entries: [EntryModel],
        groups: [(String, [EntryModel])],
        selected: EntryModel.ID? = nil,
        renaming: EntryModel.ID? = nil,
    ) {
        var state = EntryViewLayoutState()
        state.entries = entries
        state.entryArrangements.groupedItems = groups.map { .init(groupName: $0.0, items: $0.1) }
        state.selectedIds = selected.map { [$0] } ?? []
        state.lastSelectedId = selected
        state.rangeAnchorId = selected
        state.entryOperations.renamingItemId = renaming
        let recorder = Task4Recorder()
        self.recorder = recorder
        let store = Store(initialState: state) {
            Reduce<EntryViewLayoutState, EntryViewLayoutAction> { state, action in
                switch action {
                case let .view(.updateSelection(ids, focus, anchor, shouldScroll)):
                    state.selectedIds = ids
                    state.lastSelectedId = focus
                    state.rangeAnchorId = anchor
                    state.shouldScrollToSelection = shouldScroll
                    recorder.updateCount += 1
                    recorder.events.append("selection")
                case let .view(.preloadOpenWithApplications(entries)):
                    recorder.events.append("preload:\(entries.map(\.id).joined(separator: ","))")
                case let .view(.toggleGroup(name)):
                    state.entryArrangements.collapsedGroups.formSymmetricDifference([name])
                    recorder.events.append("toggle:\(name)")
                default:
                    break
                }
                return .none
            }
        }
        self.store = store
        coordinator = EntryListCoordinator(store: store)
        view = EntryListView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        coordinator.bind(to: view)
        view.layoutSubtreeIfNeeded()
        tableView.layoutSubtreeIfNeeded()
    }

    func groupRow(named name: String) throws -> Int {
        let item = try XCTUnwrap(coordinator.groupItemByName[name])
        let row = tableView.row(forItem: item)
        XCTAssertGreaterThanOrEqual(row, 0)
        return row
    }

    func renderCurrentState() {
        coordinator.processRender(EntryListCoordinatorRenderSnapshot(state: store.state))
    }

    func selectGroup(named name: String) throws {
        let item = try XCTUnwrap(coordinator.groupItemByName[name])
        _ = coordinator.applyGroupSelection(item, commandPressed: false)
    }

    func entryRow(id: EntryModel.ID) throws -> Int {
        let item = try XCTUnwrap(coordinator.entryItemsByID[id]?.first(where: { tableView.row(forItem: $0) >= 0 }))
        return tableView.row(forItem: item)
    }

    func appendDuplicate(_ entry: EntryModel, toGroupNamed name: String) throws {
        let group = try XCTUnwrap(coordinator.groupItemByName[name])
        group.children.append(EntryListOutlineItem(kind: .entry(entry), identityScope: name))
        tableView.reloadItem(group, reloadChildren: true)
        tableView.layoutSubtreeIfNeeded()
    }

    func prependRootEntry(_ entry: EntryModel) {
        coordinator.outlineItems.insert(EntryListOutlineItem(kind: .entry(entry)), at: 0)
        reloadInstalledRows()
    }

    func replaceProjectionWithFreshItems() {
        coordinator.outlineItems = coordinator.makeOutlineItems(state: store.state)
        reloadInstalledRows()
        coordinator.syncListSelectionFromStore()
    }

    func visibleRows(id: EntryModel.ID) -> [Int] {
        (0 ..< tableView.numberOfRows).filter { row in
            guard let item = tableView.item(atRow: row) as? EntryListOutlineItem,
                  case let .entry(entry) = item.kind
            else { return false }
            return entry.id == id
        }
    }

    private func reloadInstalledRows() {
        coordinator.rebuildItemIndexes()
        tableView.reloadData()
        coordinator.applyGroupExpansionState()
        tableView.layoutSubtreeIfNeeded()
    }

    func assertSelectedGroupRow(_ row: Int) throws {
        let rowView = try XCTUnwrap(tableView.rowView(atRow: row, makeIfNecessary: true))
        XCTAssertTrue(rowView.isSelected)
        XCTAssertTrue(rowView.isEmphasized)
        XCTAssertEqual(rowView.selectionHighlightStyle, .regular)
    }

    func groupRowIsSelected(_ row: Int) throws -> Bool {
        try XCTUnwrap(tableView.rowView(atRow: row, makeIfNecessary: true)).isSelected
    }

    func assertCanonical(_ ids: Set<EntryModel.ID>, focus: EntryModel.ID?, updates: Int) {
        XCTAssertEqual(store.state.selectedIds, ids)
        XCTAssertEqual(store.state.lastSelectedId, focus)
        XCTAssertEqual(store.state.rangeAnchorId, focus)
        XCTAssertEqual(recorder.updateCount, updates)
    }

    func setSelection(_ ids: Set<EntryModel.ID>, focus: EntryModel.ID) {
        store.send(.view(.updateSelection(
            ids: ids, lastSelectedId: focus, rangeAnchorId: focus, shouldScrollToSelection: false,
        )))
        coordinator.syncListSelectionFromStore()
    }

    func assertSelection(_ ids: Set<EntryModel.ID>, focus: EntryModel.ID?, rows: IndexSet, updates: Int) {
        assertCanonical(ids, focus: focus, updates: updates)
        XCTAssertEqual(tableView.selectedRowIndexes, rows)
    }

    func assertSelection(
        _ ids: Set<EntryModel.ID>,
        focus: EntryModel.ID?,
        anchor: EntryModel.ID?,
        rows: IndexSet,
        updates: Int,
    ) {
        XCTAssertEqual(store.state.selectedIds, ids)
        XCTAssertEqual(store.state.lastSelectedId, focus)
        XCTAssertEqual(store.state.rangeAnchorId, anchor)
        XCTAssertEqual(tableView.selectedRowIndexes, rows)
        XCTAssertEqual(recorder.updateCount, updates)
    }

    func keyDown(_ key: NSEvent.SpecialKey, modifiers: NSEvent.ModifierFlags = []) throws {
        let (scalar, keyCode): (Int, UInt16) = switch key {
        case .leftArrow: (NSLeftArrowFunctionKey, 123)
        case .rightArrow: (NSRightArrowFunctionKey, 124)
        case .upArrow: (NSUpArrowFunctionKey, 126)
        default: (NSDownArrowFunctionKey, 125)
        }
        let characters = try String(Character(XCTUnwrap(UnicodeScalar(scalar))))
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode,
        ))
        tableView.keyDown(with: event)
    }

    func mouseDownAndFlush(
        row: Int,
        modifiers: NSEvent.ModifierFlags = [],
        disclosure: Bool = false,
        outlineCellBody: Bool = false,
        dragOffset: CGFloat? = nil,
        beforeDrain: (() throws -> Void)? = nil,
    ) throws {
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        Self.retainedWindows.append(window)
        window.setFrameOrigin(NSPoint(x: -100_000, y: -100_000))
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(tableView)
        let windowNumber = window.windowNumber
        let mouseDown = try event(
            row: row,
            type: .leftMouseDown,
            modifiers: modifiers,
            disclosure: disclosure,
            outlineCellBody: outlineCellBody,
            windowNumber: windowNumber,
        )
        let mouseUp = try event(
            row: row,
            type: .leftMouseUp,
            modifiers: modifiers,
            disclosure: disclosure,
            outlineCellBody: outlineCellBody,
            windowNumber: windowNumber,
        )
        NSApp.postEvent(mouseUp, atStart: true)
        if let dragOffset {
            let dragged = try event(
                row: row,
                type: .leftMouseDragged,
                modifiers: modifiers,
                windowNumber: windowNumber,
                locationOffset: NSPoint(x: dragOffset, y: 0),
            )
            NSApp.postEvent(dragged, atStart: true)
        }
        if disclosure {
            NSApp.sendEvent(mouseDown)
        } else {
            tableView.mouseDown(with: mouseDown)
        }
        try beforeDrain?()
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        _ = RunLoop.current.run(mode: .default, before: Date())
        window.close()
    }

    func rightMouseDown(row: Int) throws {
        let provider = tableView.contextMenuProvider
        tableView.contextMenuProvider = nil
        defer { tableView.contextMenuProvider = provider }
        try tableView.rightMouseDown(with: event(row: row, type: .rightMouseDown))
    }

    func routeBody(
        row: Int,
        modifiers: NSEvent.ModifierFlags = [],
        clickCount: Int = 1,
    ) throws -> Bool {
        try tableView.handleCustomSelectionMouseDown(event(
            row: row,
            type: .leftMouseDown,
            modifiers: modifiers,
            clickCount: clickCount,
        )).boolValue
    }

    func routeBlank() throws -> Bool {
        try tableView.handleCustomSelectionMouseDown(event(row: nil, type: .leftMouseDown)).boolValue
    }

    func event(
        row: Int?,
        type: NSEvent.EventType,
        modifiers: NSEvent.ModifierFlags = [],
        clickCount: Int = 1,
        disclosure: Bool = false,
        outlineCellBody: Bool = false,
        windowNumber: Int = 0,
        locationOffset: NSPoint = .zero,
    ) throws -> NSEvent {
        let tablePoint: NSPoint
        if let row {
            let rowRect = tableView.rect(ofRow: row)
            let outlineRect = tableView.frameOfOutlineCell(atRow: row)
            let indentation = max(tableView.indentationPerLevel, 16)
            let disclosureX = outlineRect.minX
            tablePoint = if disclosure {
                NSPoint(x: disclosureX + indentation / 2, y: outlineRect.midY)
            } else if outlineCellBody {
                NSPoint(x: disclosureX + indentation + 8, y: outlineRect.midY)
            } else {
                NSPoint(x: max(rowRect.midX, outlineRect.maxX + 12), y: rowRect.midY)
            }
        } else {
            tablePoint = NSPoint(
                x: tableView.bounds.midX,
                y: tableView.rect(ofRow: tableView.numberOfRows - 1).maxY + 20,
            )
        }
        return try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: tableView.convert(
                NSPoint(x: tablePoint.x + locationOffset.x, y: tablePoint.y + locationOffset.y), to: nil,
            ),
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: 0,
        ))
    }
}

private extension EntryListOutlineItem {
    var groupName: String? {
        guard case let .group(name, _, _) = kind else { return nil }
        return name
    }
}

@MainActor
private func displayedNameOfItem(at indexPath: IndexPath, in view: EntryGridView) throws -> String {
    let item = try XCTUnwrap(view.collectionView.item(at: indexPath), "index path의 grid item이 materialized 되어 있어야 함")
    let nameField = try XCTUnwrap(
        descendantView(
            withIdentifier: NSUserInterfaceItemIdentifier("entryGrid.nameField"),
            in: item.view,
        ) as? NSTextField,
    )
    return nameField.stringValue
}

@MainActor
private func descendantView(withIdentifier identifier: NSUserInterfaceItemIdentifier, in root: NSView) -> NSView? {
    if root.identifier == identifier { return root }
    for subview in root.subviews {
        if let found = descendantView(withIdentifier: identifier, in: subview) { return found }
    }
    return nil
}

private func makePresentationFile(id: String, name: String) -> EntryModel {
    EntryModel(
        name: name,
        fullPath: id,
        isFolder: false,
        isHidden: false,
        size: 1,
        modifiedDate: Date(timeIntervalSince1970: 0),
        fileExtension: "txt",
        facets: .init(
            createdDate: Date(timeIntervalSince1970: 0),
            addedDate: Date(timeIntervalSince1970: 0),
            lastOpenedDate: nil,
            kind: "Text",
            creatorApplication: nil,
            tags: nil,
            supplementaryMetadata: nil,
        ),
    )
}

private func makeExpandedListProjection(
    revision: Int,
    folder: EntryModel,
    children: [EntryModel],
) -> (projection: EntryListOutlineProjection, hierarchy: EntryListHierarchyState) {
    var hierarchy = EntryListHierarchyState(rootPath: "/root")
    hierarchy.nodesByID[folder.id] = .init(
        children: children,
        loadPhase: .loaded,
        generation: 1,
        expectedBatchIndex: 1,
        coreFinished: true,
    )
    hierarchy.setExpandedIDs([folder.id])
    return (
        EntryListOutlineProjection(
            revision: revision,
            rootEntries: [folder],
            hierarchyState: hierarchy,
            context: .init(mode: .list, isNormalDirectoryPage: true, hasActiveGrouping: false),
            sortKey: .name,
            sortOrder: .ascending,
        ),
        hierarchy,
    )
}

private func outlineProjection(revision: Int, roots: [EntryModel]) -> EntryListOutlineProjection {
    var hierarchy = EntryListHierarchyState(rootPath: "/root")
    hierarchy.setExpandedIDs(Set(roots.filter(\.isFolder).map(\.id)))
    return EntryListOutlineProjection(
        revision: revision,
        rootEntries: roots,
        hierarchyState: hierarchy,
        context: .init(mode: .list, isNormalDirectoryPage: true, hasActiveGrouping: false),
        sortKey: .name,
        sortOrder: .ascending,
    )
}
