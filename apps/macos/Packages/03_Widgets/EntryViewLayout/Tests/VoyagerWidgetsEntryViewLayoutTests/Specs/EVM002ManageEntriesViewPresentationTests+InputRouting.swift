import AppKit
import ComposableArchitecture
import VoyagerEntitiesEntry
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

extension EVM002ManageEntriesViewPresentationTests {
    // MARK: - EVM-002-update_entry_selection

    /// EVM-002-update_entry_selection: group selection consumes plain Return before global rename routing.
    /// 그룹 선택이 숨겨진 child를 canonical single selection으로 보유해도 EntryListView의 Return 입력이 전역 rename command로 내려가지 않는지 검증한다.
    /// - 검증 내용: active group cursor의 plain Return이 EntryListView 입력 라우팅에서 소비되는지 확인한다.
    /// - 사전 조건: Alpha 그룹 하나를 선택한 EntryListView와 plain Return key event가 준비되어 있다.
    /// - 기대 결과: 입력이 소비되고 선택/rename 상태가 변경되지 않는다.
    func testGroupedSelectionConsumesPlainReturnBeforeGlobalRename() throws {
        let entry = EntryModel.temporaryFolder(id: "/root/child.txt", name: "child.txt")
        let fixture = EntryListInputRoutingFixture(entry: entry)
        let groupItem = try XCTUnwrap(fixture.coordinator.groupItemByName["Alpha"])
        _ = fixture.coordinator.applyGroupSelection(groupItem, commandPressed: false)

        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36,
        ))

        XCTAssertTrue(fixture.view.handleListKeyDown(with: event))
        XCTAssertEqual(fixture.store.state.selectedIds, [entry.id])
        XCTAssertNil(fixture.store.state.entryOperations.renamingItemId)
    }

    /// EVM-002-update_entry_selection: empty selection arrows use the existing selectable-row coordinator path.
    /// 빈 선택에서 AppKit native group 정규화로 우회하지 않고 group cursor 경로를 사용하는지 검증한다.
    /// - 검증 내용: Up/Down 입력이 빈 선택에서도 coordinator의 selectable row 처리로 전달되는지 확인한다.
    /// - 사전 조건: Alpha 그룹이 있고 canonical selection이 비어 있는 EntryListView가 준비되어 있다.
    /// - 기대 결과: 방향에 맞는 group row가 cursor로 선택되고 child Entry selection은 생성되지 않는다.
    func testEmptySelectionArrowNavigationUsesSelectableGroupCursorPath() throws {
        let entry = EntryModel.temporaryFolder(id: "/root/child.txt", name: "child.txt")

        for keyCode: UInt16 in [125, 126] {
            let fixture = EntryListInputRoutingFixture(entry: entry)
            let groupItem = try XCTUnwrap(fixture.coordinator.groupItemByName["Alpha"])
            if keyCode == 126 {
                fixture.view.tableView.collapseItem(groupItem)
            }
            let groupRow = fixture.view.tableView.row(forItem: groupItem)
            let scalar = keyCode == 125 ? NSDownArrowFunctionKey : NSUpArrowFunctionKey
            let characters = try String(Character(XCTUnwrap(UnicodeScalar(scalar))))
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: keyCode,
            ))

            fixture.view.tableView.keyDown(with: event)

            XCTAssertEqual(fixture.store.state.selectedIds, [])
            XCTAssertNil(fixture.store.state.lastSelectedId)
            XCTAssertEqual(fixture.view.tableView.selectedRowIndexes, IndexSet(integer: groupRow))
            XCTAssertIdentical(fixture.view.tableView.activeSelectionOccurrence, groupItem)
        }
    }
}

@MainActor
private final class EntryListInputRoutingFixture {
    let store: StoreOf<EntryViewLayoutFeature>
    let coordinator: EntryListCoordinator
    let view: EntryListView

    init(entry: EntryModel) {
        var state = EntryViewLayoutState()
        state.entries = [entry]
        state.entryArrangements.groupedItems = [
            .init(groupName: "Alpha", items: [entry]),
        ]
        let store = Store(initialState: state) {
            EntryViewLayoutFeature()
        }
        let coordinator = EntryListCoordinator(store: store)
        let view = EntryListView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        self.store = store
        self.coordinator = coordinator
        self.view = view
        coordinator.bind(to: view)
        view.layoutSubtreeIfNeeded()
        view.tableView.layoutSubtreeIfNeeded()
    }
}
