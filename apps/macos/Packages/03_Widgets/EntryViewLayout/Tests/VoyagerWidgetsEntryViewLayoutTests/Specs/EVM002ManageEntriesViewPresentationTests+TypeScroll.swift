import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

extension EVM002ManageEntriesViewPresentationTests {
    // MARK: - EVM-002-manage_entries_view_type_scroll

    /// EVM-002-manage_entries_view_type_scroll: setTypeScrollTarget은 pending target을 기록하고 selection은 바꾸지 않는다.
    ///
    /// - 검증 내용: `.view(.setTypeScrollTarget(id))`이 pendingTypeScrollTargetId를 설정하고
    ///   selectedIds/lastSelectedId/rangeAnchorId/shouldScrollToSelection은 그대로 유지된다.
    /// - 사전 조건: 초기 selection 상태(selectedIds, lastSelectedId, rangeAnchorId, shouldScrollToSelection)가 설정돼 있다.
    /// - 기대 결과: pendingTypeScrollTargetId == id이고 selection 4개 필드는 모두 불변이다.
    func testSetTypeScrollTargetRecordsTargetAndPreservesSelection() async {
        let id: EntryModel.ID = "/root/target"
        var state = EntryViewLayoutState()
        state.selectedIds = [id]
        state.lastSelectedId = id
        state.rangeAnchorId = id
        state.shouldScrollToSelection = true

        let store = TestStore(initialState: state) {
            EntryViewLayoutFeature()
        }

        await store.send(.view(.setTypeScrollTarget(id))) {
            $0.pendingTypeScrollTargetId = id
        }

        XCTAssertEqual(store.state.selectedIds, [id])
        XCTAssertEqual(store.state.lastSelectedId, id)
        XCTAssertEqual(store.state.rangeAnchorId, id)
        XCTAssertTrue(store.state.shouldScrollToSelection)
    }

    /// EVM-002-manage_entries_view_type_scroll: resetTypeScrollTarget은 pending target을 nil로 되돌린다.
    ///
    /// - 검증 내용: `.view(.resetTypeScrollTarget)`이 pendingTypeScrollTargetId를 nil로 만든다.
    /// - 사전 조건: pendingTypeScrollTargetId가 어떤 id로 설정돼 있다.
    /// - 기대 결과: pendingTypeScrollTargetId == nil.
    func testResetTypeScrollTargetClearsPendingTarget() async {
        let id: EntryModel.ID = "/root/target"
        var state = EntryViewLayoutState()
        state.pendingTypeScrollTargetId = id

        let store = TestStore(initialState: state) {
            EntryViewLayoutFeature()
        }

        await store.send(.view(.resetTypeScrollTarget)) {
            $0.pendingTypeScrollTargetId = nil
        }

        XCTAssertNil(store.state.pendingTypeScrollTargetId)
    }

    /// EVM-002-manage_entries_view_type_scroll: reset 후 같은 id를 다시 set하면 다시 설정된다.
    ///
    /// - 검증 내용: reset으로 소모된 후 동일 id를 재설정하면 pending target이 다시 채워진다(consume-once 재사용).
    /// - 사전 조건: 초기 상태의 pendingTypeScrollTargetId가 nil이다.
    /// - 기대 결과: set → reset → 동일 id 재set 순서로 nil → id → id를 순회한다.
    func testTypeScrollTargetIsReSettableAfterReset() async {
        let id: EntryModel.ID = "/root/target"
        let store = TestStore(initialState: EntryViewLayoutState()) {
            EntryViewLayoutFeature()
        }

        await store.send(.view(.setTypeScrollTarget(id))) {
            $0.pendingTypeScrollTargetId = id
        }
        await store.send(.view(.resetTypeScrollTarget)) {
            $0.pendingTypeScrollTargetId = nil
        }
        await store.send(.view(.setTypeScrollTarget(id))) {
            $0.pendingTypeScrollTargetId = id
        }

        XCTAssertEqual(store.state.pendingTypeScrollTargetId, id)
    }

    /// EVM-002-manage_entries_view_type_scroll: synchronizeEntries는 entries에 없는(stale) pending target을 소모한다.
    ///
    /// - 검증 내용: 동기화 대상 entries에 pending target id가 없으면(stale/제거됨) pendingTypeScrollTargetId를 nil로 만든다.
    /// - 사전 조건: pendingTypeScrollTargetId가 동기화 대상 entries에 없는 id로 설정돼 있다.
    /// - 기대 결과: synchronizeEntries 호출 후 pendingTypeScrollTargetId == nil.
    func testSynchronizeEntriesClearsPendingTypeScrollTarget() {
        let targetID: EntryModel.ID = "/root/target"
        let staleID: EntryModel.ID = "/root/removed"
        let entry = EntryModel.temporaryFolder(id: targetID, name: "target")
        var state = EntryViewLayoutState()
        state.entries = [entry]
        // stale id: 동기화되는 entries에 존재하지 않으므로 clear되어야 한다.
        state.pendingTypeScrollTargetId = staleID

        state.synchronizeEntries([entry])

        XCTAssertNil(state.pendingTypeScrollTargetId)
    }

    /// EVM-002-manage_entries_view_type_scroll: synchronizeEntries는 entries에 남아 있는 유효 pending target을 보존한다.
    ///
    /// - 검증 내용: collection follow-up batch/metadata 동기화가 throttle cooldown 동안 유효한 type-scroll target을
    ///   drop하지 않도록, target id가 여전히 동기화된 entries에 존재하면 pendingTypeScrollTargetId를 유지한다.
    /// - 사전 조건: pendingTypeScrollTargetId가 targetID로 설정돼 있고, 동기화 대상 entries에 targetID가 포함된다.
    /// - 기대 결과: synchronizeEntries 호출 후 pendingTypeScrollTargetId == targetID (보존).
    func testSynchronizeEntriesPreservesValidPendingTypeScrollTarget() {
        let targetID: EntryModel.ID = "/root/target"
        let otherID: EntryModel.ID = "/root/other"
        let targetEntry = EntryModel.temporaryFolder(id: targetID, name: "target")
        let otherEntry = EntryModel.temporaryFolder(id: otherID, name: "other")
        var state = EntryViewLayoutState()
        state.pendingTypeScrollTargetId = targetID

        state.synchronizeEntries([targetEntry, otherEntry])

        XCTAssertEqual(state.pendingTypeScrollTargetId, targetID)
    }

    /// EVM-002-manage_entries_view_type_scroll: synchronizeEntries는 entries에서 제거된(stale) pending target만 소모한다.
    ///
    /// - 검증 내용: target id가 동기화된 entries에서 사라지면(stale) 영구 target/반복 스크롤 루프 없이 안전하게 nil로 정리한다.
    /// - 사전 조건: pendingTypeScrollTargetId가 제거될 id로 설정돼 있고, 동기화 대상 entries에 그 id가 없다.
    /// - 기대 결과: synchronizeEntries 호출 후 pendingTypeScrollTargetId == nil (정리).
    func testSynchronizeEntriesClearsRemovedPendingTypeScrollTarget() {
        let removedID: EntryModel.ID = "/root/removed"
        let survivorID: EntryModel.ID = "/root/survivor"
        let survivorEntry = EntryModel.temporaryFolder(id: survivorID, name: "survivor")
        var state = EntryViewLayoutState()
        state.pendingTypeScrollTargetId = removedID

        state.synchronizeEntries([survivorEntry])

        XCTAssertNil(state.pendingTypeScrollTargetId)
    }

    /// EVM-002-manage_entries_view_type_scroll: clearCollectionPresentation은 pending target을 소모한다.
    ///
    /// - 검증 내용: collection presentation 정리가 pendingTypeScrollTargetId를 nil로 만든다.
    /// - 사전 조건: collection mode가 활성화돼 있고 pendingTypeScrollTargetId가 id로 설정돼 있다.
    /// - 기대 결과: clearCollectionPresentation 호출 후 pendingTypeScrollTargetId == nil.
    func testClearCollectionPresentationClearsPendingTypeScrollTarget() {
        let id: EntryModel.ID = "/root/target"
        var state = EntryViewLayoutState()
        state.isCollectionMode = true
        state.pendingTypeScrollTargetId = id

        state.clearCollectionPresentation()

        XCTAssertNil(state.pendingTypeScrollTargetId)
    }

    // MARK: - EVM-002-manage_entries_view_type_scroll_matcher

    /// EVM-002-manage_entries_view_type_scroll: '가'는 '가나다.txt' 이름의 첫 그래프와 일치해 해당 id를 반환한다.
    func testFirstMatchIDHangulPrecomposed() {
        let entry = EntryModel.temporaryFolder(id: "/a", name: "가나다.txt")
        let id = EntryViewLayoutTypeScrollMatcher.firstMatchID(in: [entry], inputText: "가")
        XCTAssertEqual(id, entry.id)
    }

    /// EVM-002-manage_entries_view_type_scroll: 'A'는 'apple' 이름의 첫 그래프와 대소문자 무시로 일치한다.
    func testFirstMatchIDCaseInsensitive() {
        let entry = EntryModel.temporaryFolder(id: "/b", name: "apple")
        let id = EntryViewLayoutTypeScrollMatcher.firstMatchID(in: [entry], inputText: "A")
        XCTAssertEqual(id, entry.id)
    }

    /// EVM-002-manage_entries_view_type_scroll: 'a'는 'Apple' 이름의 첫 그래프와 대소문자 무시로 일치한다.
    func testFirstMatchIDCaseInsensitiveReverse() {
        let entry = EntryModel.temporaryFolder(id: "/c", name: "Apple")
        let id = EntryViewLayoutTypeScrollMatcher.firstMatchID(in: [entry], inputText: "a")
        XCTAssertEqual(id, entry.id)
    }

    /// EVM-002-manage_entries_view_type_scroll: 'é'는 'Été' 이름의 첫 그래프와 발음구별부호 무시로 일치한다.
    func testFirstMatchIDDiacriticInsensitive() {
        let entry = EntryModel.temporaryFolder(id: "/d", name: "Été")
        let id = EntryViewLayoutTypeScrollMatcher.firstMatchID(in: [entry], inputText: "é")
        XCTAssertEqual(id, entry.id)
    }

    /// EVM-002-manage_entries_view_type_scroll: 전각 'Ａ'는 반각 'Apple' 이름의 첫 그래프와 폭 무시로 일치한다.
    func testFirstMatchIDWidthInsensitive() {
        let entry = EntryModel.temporaryFolder(id: "/e", name: "Apple")
        let id = EntryViewLayoutTypeScrollMatcher.firstMatchID(in: [entry], inputText: "Ａ")
        XCTAssertEqual(id, entry.id)
    }

    /// EVM-002-manage_entries_view_type_scroll: 'あ'는 'あさひ' 이름의 첫 그래프와 일치한다.
    func testFirstMatchIDHiragana() {
        let entry = EntryModel.temporaryFolder(id: "/f", name: "あさひ")
        let id = EntryViewLayoutTypeScrollMatcher.firstMatchID(in: [entry], inputText: "あ")
        XCTAssertEqual(id, entry.id)
    }

    /// EVM-002-manage_entries_view_type_scroll: '中'은 '中文字.txt' 이름의 첫 그래프와 일치한다 (한자).
    func testFirstMatchIDHan() {
        let entry = EntryModel.temporaryFolder(id: "/g", name: "中文字.txt")
        let id = EntryViewLayoutTypeScrollMatcher.firstMatchID(in: [entry], inputText: "中")
        XCTAssertEqual(id, entry.id)
    }

    /// EVM-002-manage_entries_view_type_scroll: NFD로 분해된 '가'(U+1100 U+1161)는 미리 조합된 '가'(U+AC00) 입력과 일치한다.
    func testFirstMatchIDHangulNFDEquivalence() {
        let entry = EntryModel.temporaryFolder(id: "/h", name: "\u{1100}\u{1161}나다.txt")
        let id = EntryViewLayoutTypeScrollMatcher.firstMatchID(in: [entry], inputText: "가")
        XCTAssertEqual(id, entry.id)
    }

    /// EVM-002-manage_entries_view_type_scroll: 'e\u{0301}'(e + 결합 악상)는 입력 'é'와 발음구별부호 무시로 일치한다.
    func testFirstMatchIDCombiningAcuteEquivalence() {
        let entry = EntryModel.temporaryFolder(id: "/i", name: "e\u{0301}té")
        let id = EntryViewLayoutTypeScrollMatcher.firstMatchID(in: [entry], inputText: "é")
        XCTAssertEqual(id, entry.id)
    }

    /// EVM-002-manage_entries_view_type_scroll: folding으로 확장되는 입력 그래프는 이름의 다른 원본 그래프와 일치하지 않는다.
    func testFirstMatchIDDoesNotMatchExpandedInputGraphemeToLatinInitial() {
        let entry = EntryModel.temporaryFolder(id: "/song", name: "Song")
        let id = EntryViewLayoutTypeScrollMatcher.firstMatchID(in: [entry], inputText: "ß")
        XCTAssertNil(id)
    }

    /// EVM-002-manage_entries_view_type_scroll: 이름의 첫 원본 그래프가 folding으로 확장돼도 입력의 일부와 일치하지 않는다.
    func testFirstMatchIDDoesNotMatchLatinInputToExpandedNameGrapheme() {
        let entry = EntryModel.temporaryFolder(id: "/beta", name: "ßeta")
        let id = EntryViewLayoutTypeScrollMatcher.firstMatchID(in: [entry], inputText: "s")
        XCTAssertNil(id)
    }

    /// EVM-002-manage_entries_view_type_scroll: 전달된 entries 순서에서 첫 매칭 항목의 id를 반환한다.
    func testFirstMatchIDReturnsFirstInGivenOrder() {
        let beta = EntryModel.temporaryFolder(id: "/B", name: "Beta")
        let alpha = EntryModel.temporaryFolder(id: "/A", name: "Alpha")
        let charlie = EntryModel.temporaryFolder(id: "/C", name: "Charlie")
        let id = EntryViewLayoutTypeScrollMatcher.firstMatchID(in: [beta, alpha, charlie], inputText: "a")
        XCTAssertEqual(id, alpha.id)
    }

    /// EVM-002-manage_entries_view_type_scroll: 빈 entries는 nil을 반환한다.
    func testFirstMatchIDEmptyEntries() {
        let id = EntryViewLayoutTypeScrollMatcher.firstMatchID(in: [], inputText: "a")
        XCTAssertNil(id)
    }

    /// EVM-002-manage_entries_view_type_scroll: 매칭이 없으면 nil을 반환한다.
    func testFirstMatchIDNoMatch() {
        let entry = EntryModel.temporaryFolder(id: "/z", name: "beta")
        let id = EntryViewLayoutTypeScrollMatcher.firstMatchID(in: [entry], inputText: "a")
        XCTAssertNil(id)
    }

    /// EVM-002-manage_entries_view_type_scroll: 다중 그래프 입력 'ab'는 nil을 반환한다.
    func testFirstMatchIDMultiGraphemeInput() {
        let entry = EntryModel.temporaryFolder(id: "/m", name: "alpha")
        let id = EntryViewLayoutTypeScrollMatcher.firstMatchID(in: [entry], inputText: "ab")
        XCTAssertNil(id)
    }

    /// EVM-002-manage_entries_view_type_scroll: 빈 입력은 nil을 반환한다.
    func testFirstMatchIDEmptyInput() {
        let entry = EntryModel.temporaryFolder(id: "/n", name: "alpha")
        let id = EntryViewLayoutTypeScrollMatcher.firstMatchID(in: [entry], inputText: "")
        XCTAssertNil(id)
    }

    /// EVM-002-manage_entries_view_type_scroll: 다중 그래프 입력 '가나'는 nil을 반환한다.
    func testFirstMatchIDMultiGraphemeHangulInput() {
        let entry = EntryModel.temporaryFolder(id: "/o", name: "가나다.txt")
        let id = EntryViewLayoutTypeScrollMatcher.firstMatchID(in: [entry], inputText: "가나")
        XCTAssertNil(id)
    }

    // MARK: - EVM-002-manage_entries_view_type_scroll_list_consume

    /// EVM-002-manage_entries_view_type_scroll: list는 pending target을 첫 유효 row로 소비해 offscreen 항목을 visible로 스크롤하고
    /// reset한다.
    /// - 검증 내용: pendingTypeScrollTargetId가 설정된 snapshot edge에서 scrollRowToVisible이 첫 매칭 row를 visible로 만들고
    ///   resetTypeScrollTarget이 발행되어 pending이 nil로 소비된다. selection은 불변이다.
    /// - 사전 조건: 좁은 list view에 많은 entry가 있어 target row가 화면 밖에 있고, pending target이 그 row의 id다.
    /// - 기대 결과: consume 후 target row가 visible rect에 포함되고 pendingTypeScrollTargetId == nil, selectedIds 불변.
    func testListConsumesTypeScrollTargetScrollingOffscreenMatchIntoView() throws {
        let entries = (0 ..< 60).map { index in
            EntryModel.temporaryFolder(id: "/root/\(index)", name: "file\(index)")
        }
        let target = entries[40]
        var state = EntryViewLayoutState()
        state.entries = entries
        state.selectedIds = [entries[0].id]
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        let view = EntryListView(frame: NSRect(x: 0, y: 0, width: 400, height: 40))

        coordinator.bind(to: view)
        view.layoutSubtreeIfNeeded()
        let targetItem = try XCTUnwrap(coordinator.entryItemById[target.id])
        let targetRow = coordinator.tableView.row(forItem: targetItem)
        XCTAssertGreaterThanOrEqual(targetRow, 0)
        let beforeVisible = coordinator.tableView.rows(in: coordinator.tableView.visibleRect)
        XCTAssertFalse(NSLocationInRange(targetRow, beforeVisible), "target row must start offscreen")

        var previousState = state
        previousState.pendingTypeScrollTargetId = nil
        var currentState = state
        currentState.pendingTypeScrollTargetId = target.id
        coordinator.handleSnapshotChanges(
            previous: EntryListCoordinatorRenderSnapshot(state: previousState),
            snapshot: EntryListCoordinatorRenderSnapshot(state: currentState),
        )

        let afterVisible = coordinator.tableView.rows(in: coordinator.tableView.visibleRect)
        XCTAssertTrue(NSLocationInRange(targetRow, afterVisible), "target row must become visible after consume")
        XCTAssertNil(store.state.pendingTypeScrollTargetId, "pending target must be reset after consume")
        XCTAssertEqual(store.state.selectedIds, [entries[0].id], "selection must be unchanged")
    }

    /// EVM-002-manage_entries_view_type_scroll: list는 stale/unknown target이면 스크롤하지 않고 reset만 한다.
    /// - 검증 내용: pending target이 table에 없는 id면 scroll은 불변이고 resetTypeScrollTarget이 발행된다.
    /// - 사전 조건: pending target id가 table에 없는 id다.
    /// - 기대 결과: consume 후 visible rect가 변하지 않고 pendingTypeScrollTargetId == nil.
    func testListConsumesTypeScrollTargetForStaleUnknownIDWithoutScrolling() {
        let entries = (0 ..< 20).map { index in
            EntryModel.temporaryFolder(id: "/root/\(index)", name: "file\(index)")
        }
        var state = EntryViewLayoutState()
        state.entries = entries
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: EntryListView(frame: NSRect(x: 0, y: 0, width: 400, height: 40)))

        let beforeVisible = coordinator.tableView.rows(in: coordinator.tableView.visibleRect)
        var previousState = state
        previousState.pendingTypeScrollTargetId = nil
        var currentState = state
        currentState.pendingTypeScrollTargetId = "/root/does-not-exist"
        coordinator.handleSnapshotChanges(
            previous: EntryListCoordinatorRenderSnapshot(state: previousState),
            snapshot: EntryListCoordinatorRenderSnapshot(state: currentState),
        )

        let afterVisible = coordinator.tableView.rows(in: coordinator.tableView.visibleRect)
        XCTAssertEqual(afterVisible, beforeVisible, "stale target must not change scroll")
        XCTAssertNil(store.state.pendingTypeScrollTargetId, "stale target must still reset")
    }

    /// EVM-002-manage_entries_view_type_scroll: list는 같은 문자 재입력(nil→id 전환)을 다시 소비한다.
    /// - 검증 내용: 첫 소비로 reset된 뒤 같은 id를 다시 설정하면 nil→id 엣지가 다시 소비된다.
    /// - 사전 조건: 같은 pending target id가 reset 후 다시 설정된다.
    /// - 기대 결과: 재소비 시 다시 스크롤되고 pending이 nil로 소비된다.
    func testListReconsumesSameTypeScrollTargetAfterReset() throws {
        let entries = (0 ..< 60).map { index in
            EntryModel.temporaryFolder(id: "/root/\(index)", name: "file\(index)")
        }
        let target = entries[50]
        var state = EntryViewLayoutState()
        state.entries = entries
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: EntryListView(frame: NSRect(x: 0, y: 0, width: 400, height: 40)))

        func consume() throws -> Int {
            let targetItem = try XCTUnwrap(coordinator.entryItemById[target.id])
            let targetRow = coordinator.tableView.row(forItem: targetItem)
            var previousState = state
            previousState.pendingTypeScrollTargetId = nil
            var currentState = state
            currentState.pendingTypeScrollTargetId = target.id
            coordinator.handleSnapshotChanges(
                previous: EntryListCoordinatorRenderSnapshot(state: previousState),
                snapshot: EntryListCoordinatorRenderSnapshot(state: currentState),
            )
            return targetRow
        }

        let firstRow = try consume()
        XCTAssertNil(store.state.pendingTypeScrollTargetId)
        let secondRow = try consume()
        XCTAssertEqual(secondRow, firstRow)
        XCTAssertNil(store.state.pendingTypeScrollTargetId, "same id must be re-consumable after reset")
    }

    /// EVM-002-manage_entries_view_type_scroll: list는 pending target이 설정되지 않으면 스크롤하지 않는다.
    /// - 검증 내용: nil→nil 엣지에서는 consume이 발생하지 않는다.
    /// - 사전 조건: pendingTypeScrollTargetId가 처음부터 끝까지 nil이다.
    /// - 기대 결과: visible rect 불변.
    func testListNoScrollWhenPendingTargetNeverSet() {
        let entries = (0 ..< 30).map { index in
            EntryModel.temporaryFolder(id: "/root/\(index)", name: "file\(index)")
        }
        var state = EntryViewLayoutState()
        state.entries = entries
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        coordinator.bind(to: EntryListView(frame: NSRect(x: 0, y: 0, width: 400, height: 40)))

        let beforeVisible = coordinator.tableView.rows(in: coordinator.tableView.visibleRect)
        coordinator.handleSnapshotChanges(
            previous: EntryListCoordinatorRenderSnapshot(state: state),
            snapshot: EntryListCoordinatorRenderSnapshot(state: state),
        )
        let afterVisible = coordinator.tableView.rows(in: coordinator.tableView.visibleRect)

        XCTAssertEqual(afterVisible, beforeVisible, "nil→nil must not scroll")
        XCTAssertNil(store.state.pendingTypeScrollTargetId)
    }

    // MARK: - EVM-002-manage_entries_view_type_scroll_list_initial_bind_consume

    /// EVM-002-manage_entries_view_type_scroll: list는 첫 bind 전에 이미 설정된 유효 pending target을
    /// 첫 렌더 기준으로 소비해 offscreen 항목을 visible로 스크롤하고 reset한다.
    ///
    /// - 검증 내용: view가 unmount된 동안 생성된 target(id→ nil 엣지가 처음 baseline에 흡수돼 기존
    ///   consume 로직이 못 잡는 경우)도 첫 bind의 row 존재 이후 소비되어 target row가 visible이 되고
    ///   pendingTypeScrollTargetId가 nil로 reset된다. selection은 불변이다.
    /// - 사전 조건: 좁은 list view에 많은 entry가 있어 target row가 화면 밖에 있고, pending target이
    ///   bind 이전부터 그 row의 id로 설정돼 있다.
    /// - 기대 결과: consume 후 target row가 visible rect에 포함되고 pendingTypeScrollTargetId == nil, selection 불변.
    func testListConsumesPendingTypeScrollTargetPresentBeforeFirstBind() throws {
        let entries = (0 ..< 60).map { index in
            EntryModel.temporaryFolder(id: "/root/\(index)", name: "file\(index)")
        }
        let target = entries[40]
        var state = EntryViewLayoutState()
        state.entries = entries
        state.selectedIds = [entries[0].id]
        // bind 이전부터 pending target이 설정돼 있다 (unmount 중 생성 시나리오).
        state.pendingTypeScrollTargetId = target.id
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        let view = EntryListView(frame: NSRect(x: 0, y: 0, width: 400, height: 40))

        coordinator.bind(to: view)
        view.layoutSubtreeIfNeeded()

        let targetItem = try XCTUnwrap(coordinator.entryItemById[target.id])
        let targetRow = coordinator.tableView.row(forItem: targetItem)
        let visible = coordinator.tableView.rows(in: coordinator.tableView.visibleRect)
        XCTAssertTrue(
            NSLocationInRange(targetRow, visible),
            "target row must become visible after initial-bind consume",
        )
        XCTAssertNil(store.state.pendingTypeScrollTargetId, "pending target must be reset after initial-bind consume")
        XCTAssertEqual(store.state.selectedIds, [entries[0].id], "selection must be unchanged")
    }

    /// EVM-002-manage_entries_view_type_scroll: list는 첫 bind 전에 설정된 stale/unknown pending target이면
    /// 스크롤하지 않고 reset만 한다.
    ///
    /// - 검증 내용: pending target id가 첫 렌더 row에 없어도 resetTypeScrollTarget이 발행돼 일회성 소비가 보장된다.
    /// - 사전 조건: pending target id가 bind 이전부터 table에 없는 id다.
    /// - 기대 결과: consume 후 visible rect가 불변이고 pendingTypeScrollTargetId == nil.
    func testListConsumesStalePendingTypeScrollTargetBeforeFirstBind() {
        let entries = (0 ..< 20).map { index in
            EntryModel.temporaryFolder(id: "/root/\(index)", name: "file\(index)")
        }
        var state = EntryViewLayoutState()
        state.entries = entries
        state.pendingTypeScrollTargetId = "/root/does-not-exist"
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        let view = EntryListView(frame: NSRect(x: 0, y: 0, width: 400, height: 40))

        coordinator.bind(to: view)
        view.layoutSubtreeIfNeeded()

        let beforeVisible = coordinator.tableView.rows(in: coordinator.tableView.visibleRect)
        coordinator.handleSnapshotChanges(
            previous: EntryListCoordinatorRenderSnapshot(state: state),
            snapshot: EntryListCoordinatorRenderSnapshot(state: state),
        )
        let afterVisible = coordinator.tableView.rows(in: coordinator.tableView.visibleRect)
        XCTAssertEqual(afterVisible, beforeVisible, "stale target must not change scroll")
        XCTAssertNil(store.state.pendingTypeScrollTargetId, "stale target must still reset after initial-bind consume")
    }

    /// EVM-002-manage_entries_view_type_scroll: list는 첫 bind 소비 직후 관찰되는 동일 snapshot 엣지에서
    /// 이중 소비하지 않는다.
    ///
    /// - 검증 내용: bind에서 수동 소비(reset) 후 비동기 관찰이 previous(pending=set)/snapshot(nil) 엣지를
    ///   처리할 때 targetId가 nil이라 consume이 발생하지 않아 visible rect가 그대로다.
    /// - 사전 조건: 첫 bind 전에 pending target이 설정돼 있고, bind에서 이미 소비·reset됐다.
    /// - 기대 결과: post-consume 관찰 엣지에서 visible rect 불변, pendingTypeScrollTargetId == nil.
    func testListInitialBindConsumeDoesNotDoubleConsumeOnFollowingObservation() {
        let entries = (0 ..< 60).map { index in
            EntryModel.temporaryFolder(id: "/root/\(index)", name: "file\(index)")
        }
        let target = entries[40]
        var state = EntryViewLayoutState()
        state.entries = entries
        state.pendingTypeScrollTargetId = target.id
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryListCoordinator(store: store)
        let view = EntryListView(frame: NSRect(x: 0, y: 0, width: 400, height: 40))

        coordinator.bind(to: view)
        view.layoutSubtreeIfNeeded()
        // bind에서 수동 소비로 pending은 이미 nil이 됐다.
        XCTAssertNil(store.state.pendingTypeScrollTargetId)

        let afterBindVisible = coordinator.tableView.rows(in: coordinator.tableView.visibleRect)
        // 첫 관찰: previous(bind 시점, pending=set) vs snapshot(현재, pending=nil) 엣지.
        var previousState = state
        previousState.pendingTypeScrollTargetId = target.id
        var currentState = state
        currentState.pendingTypeScrollTargetId = nil
        coordinator.handleSnapshotChanges(
            previous: EntryListCoordinatorRenderSnapshot(state: previousState),
            snapshot: EntryListCoordinatorRenderSnapshot(state: currentState),
        )
        let afterObservation = coordinator.tableView.rows(in: coordinator.tableView.visibleRect)
        XCTAssertEqual(afterObservation, afterBindVisible, "post-consume observation must not double-scroll")
        XCTAssertNil(store.state.pendingTypeScrollTargetId, "pending must stay nil after post-consume observation")
    }

    // MARK: - EVM-002-manage_entries_view_type_scroll_grid_consume

    /// grid 스크롤 검증 헬퍼: clip view의 scroll offset이 바뀌면 scrollToItems가 clip bounds를 이동했음을 뜻한다.
    /// unmounted NSCollectionView에서는 indexPathsForVisibleItems가 scroll 후 갱신되지 않으므로
    /// 기존 저장 scroll 복원 테스트(testHierarchyProjectionRestoresSavedScrollPosition)와 동일하게
    /// `scrollView.contentView.bounds.origin`을 결정적 관찰값으로 사용한다.
    private func gridClipOrigin(_ view: EntryGridView) -> CGPoint {
        view.scrollView.contentView.bounds.origin
    }

    /// EVM-002-manage_entries_view_type_scroll: grid는 pending target을 소비해 reset하고 selection은 유지한다.
    /// - 검증 내용: 실제 대상 id가 index 경로로 매핑 가능하고 consume 후 reset이 발행된다. unmounted NSCollectionView에서는
    ///   scrollToItems가 layout 없이는 clip offset을 이동시키지 않아 scroll geometry는 단위 테스트로 검증할 수 없으므로
    ///   저장 scroll 복원 테스트와 동일하게 offset은 관찰하지 않고 consume 계약(reset + selection 불변)만 단언한다.
    /// - 사전 조건: 작은 grid view에 많은 entry가 있고 pending target이 실제 entry의 id다.
    /// - 기대 결과: target이 매핑 가능하고 pendingTypeScrollTargetId == nil, selectedIds 불변.
    func testGridConsumesTypeScrollTargetScrollingOffscreenMatchIntoView() {
        let entries = (0 ..< 80).map { index in
            EntryModel.temporaryFolder(id: "/root/\(index)", name: "file\(index)")
        }
        let target = entries[70]
        var state = EntryViewLayoutState()
        state.entries = entries
        state.selectedIds = [entries[0].id]
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryGridCoordinator(store: store)
        coordinator.bind(to: EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240)))

        // 실제 대상 id가 scrollToTypeScrollTarget에서 소비될 수 있도록 index 경로로 매핑 가능해야 한다.
        XCTAssertNotNil(coordinator.indexPathByEntryId[target.id], "target must be mappable to an indexPath")
        var previousState = state
        previousState.pendingTypeScrollTargetId = nil
        var currentState = state
        currentState.pendingTypeScrollTargetId = target.id
        coordinator.handleSnapshotChanges(
            previous: EntryGridRenderSnapshot(state: previousState),
            snapshot: EntryGridRenderSnapshot(state: currentState),
        )

        XCTAssertNil(store.state.pendingTypeScrollTargetId, "pending target must be reset after consume")
        XCTAssertEqual(store.state.selectedIds, [entries[0].id], "selection must be unchanged")
    }

    /// EVM-002-manage_entries_view_type_scroll: grid는 stale/unknown target이면 스크롤하지 않고 reset만 한다.
    /// - 검증 내용: pending target id가 없으면 scroll offset 불변이고 reset이 발행된다.
    /// - 사전 조건: pending target id가 grid에 없는 id다.
    /// - 기대 결과: consume 후 clip offset이 불변이고 pendingTypeScrollTargetId == nil.
    func testGridConsumesTypeScrollTargetForStaleUnknownIDWithoutScrolling() {
        let entries = (0 ..< 20).map { index in
            EntryModel.temporaryFolder(id: "/root/\(index)", name: "file\(index)")
        }
        var state = EntryViewLayoutState()
        state.entries = entries
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryGridCoordinator(store: store)
        let view = EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        coordinator.bind(to: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
        )
        window.contentView = view
        view.layoutSubtreeIfNeeded()

        let beforeOrigin = gridClipOrigin(view)
        var previousState = state
        previousState.pendingTypeScrollTargetId = nil
        var currentState = state
        currentState.pendingTypeScrollTargetId = "/root/does-not-exist"
        coordinator.handleSnapshotChanges(
            previous: EntryGridRenderSnapshot(state: previousState),
            snapshot: EntryGridRenderSnapshot(state: currentState),
        )

        XCTAssertEqual(gridClipOrigin(view), beforeOrigin, "stale target must not change scroll")
        XCTAssertNil(store.state.pendingTypeScrollTargetId, "stale target must still reset")
    }

    /// EVM-002-manage_entries_view_type_scroll: grid는 같은 문자 재입력(nil→id 전환)을 다시 소비한다.
    /// - 검증 내용: reset 후 같은 id를 다시 설정하면 nil→id 엣지가 다시 소비된다.
    /// - 사전 조건: 같은 pending target id가 reset 후 다시 설정된다.
    /// - 기대 결과: 재소비 시 다시 스크롤되고 pending이 nil로 소비된다.
    func testGridReconsumesSameTypeScrollTargetAfterReset() throws {
        let entries = (0 ..< 80).map { index in
            EntryModel.temporaryFolder(id: "/root/\(index)", name: "file\(index)")
        }
        let target = entries[70]
        var state = EntryViewLayoutState()
        state.entries = entries
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryGridCoordinator(store: store)
        let view = EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        coordinator.bind(to: view)
        view.layoutSubtreeIfNeeded()

        func consume() throws -> IndexPath {
            let indexPath = try XCTUnwrap(coordinator.indexPathByEntryId[target.id])
            var previousState = state
            previousState.pendingTypeScrollTargetId = nil
            var currentState = state
            currentState.pendingTypeScrollTargetId = target.id
            coordinator.handleSnapshotChanges(
                previous: EntryGridRenderSnapshot(state: previousState),
                snapshot: EntryGridRenderSnapshot(state: currentState),
            )
            return indexPath
        }

        let first = try consume()
        XCTAssertNil(store.state.pendingTypeScrollTargetId)
        let second = try consume()
        XCTAssertEqual(second, first)
        XCTAssertNil(store.state.pendingTypeScrollTargetId, "same id must be re-consumable after reset")
    }

    /// EVM-002-manage_entries_view_type_scroll: grid는 pending target이 설정되지 않으면 스크롤하지 않는다.
    /// - 검증 내용: nil→nil 엣지에서는 consume이 발생하지 않는다.
    /// - 사전 조건: pendingTypeScrollTargetId가 처음부터 끝까지 nil이다.
    /// - 기대 결과: clip offset 불변.
    func testGridNoScrollWhenPendingTargetNeverSet() {
        let entries = (0 ..< 30).map { index in
            EntryModel.temporaryFolder(id: "/root/\(index)", name: "file\(index)")
        }
        var state = EntryViewLayoutState()
        state.entries = entries
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryGridCoordinator(store: store)
        let view = EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        coordinator.bind(to: view)
        view.layoutSubtreeIfNeeded()

        let beforeOrigin = gridClipOrigin(view)
        coordinator.handleSnapshotChanges(
            previous: EntryGridRenderSnapshot(state: state),
            snapshot: EntryGridRenderSnapshot(state: state),
        )

        XCTAssertEqual(gridClipOrigin(view), beforeOrigin, "nil→nil must not scroll")
        XCTAssertNil(store.state.pendingTypeScrollTargetId)
    }

    // MARK: - EVM-002-manage_entries_view_type_scroll_grid_selection_precedence

    /// selection scroll 우선순위 회귀 테스트 공통 fixture 컨텍스트.
    private struct GridSelectionScrollFixture {
        let entries: [EntryModel]
        let target: EntryModel
        let store: StoreOf<EntryViewLayoutFeature>
        let coordinator: EntryGridCoordinator
        let view: EntryGridView
    }

    /// saved offset을 가진 grid를 window에 mount하고, bind 이후 키보드 선택 액션으로 scroll flag를 arm한다.
    private func makeGridSelectionScrollFixture() -> GridSelectionScrollFixture {
        let entries = (0 ..< 80).map { index in
            EntryModel.temporaryFolder(id: "/root/\(index)", name: "file\(index)")
        }
        // offset -1 fallback은 마지막 entry를 선택하므로 target도 마지막 entry다.
        let target = entries[79]
        var state = EntryViewLayoutState()
        state.entries = entries
        state.savedScrollOffset = CGPoint(x: 0, y: 37)
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryGridCoordinator(store: store)
        let view = EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        coordinator.bind(to: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
        )
        window.contentView = view
        view.layoutSubtreeIfNeeded()

        // bind 시점의 초기 복원 소비를 무시하고, rebuild 시점에 entry 수 변화로 인한
        // saved offset 복원 자격이 새로 생긴 상태를 재현한다.
        coordinator.hasRestoredScrollPosition = false

        // bind가 초기 flag를 소비하지 않도록 flag는 bind 이후 키보드 선택 액션으로 설정한다.
        store.send(.internal(.applySelectionOffset(
            offset: -1,
            isShiftPressed: false,
            orderedItemIds: entries.map(\.id),
        )))
        XCTAssertTrue(store.state.shouldScrollToSelection, "precondition: scroll flag armed")
        return GridSelectionScrollFixture(
            entries: entries,
            target: target,
            store: store,
            coordinator: coordinator,
            view: view,
        )
    }

    /// 선택 의도 없는 이후 entry 수 변화(80→100, rebuild 경로)에서도 selection scroll 결과가
    /// 유지되고 stale saved offset 복원이 발생하지 않음을 단언한다.
    private func assertDeferredCountChangePreservesSelectionScroll(
        fixture: GridSelectionScrollFixture,
        originAfterSelectionScroll: CGPoint,
    ) throws {
        var laterState = fixture.store.state
        laterState.entries = fixture.entries + (80 ..< 100).map { index in
            EntryModel.temporaryFolder(id: "/root/\(index)", name: "file\(index)")
        }
        fixture.coordinator.handleSnapshotChanges(
            previous: EntryGridRenderSnapshot(state: fixture.store.state),
            snapshot: EntryGridRenderSnapshot(state: laterState),
        )

        XCTAssertNotEqual(
            gridClipOrigin(fixture.view),
            CGPoint(x: 0, y: 37),
            "deferred stale offset must not be restored on later entry-count change",
        )
        XCTAssertEqual(
            gridClipOrigin(fixture.view),
            originAfterSelectionScroll,
            "later structural change without selection intent must not move the clip origin",
        )
        let laterIndexPath = try XCTUnwrap(fixture.coordinator.indexPathByEntryId[fixture.target.id])
        let laterFrame = try XCTUnwrap(
            fixture.view.collectionView.collectionViewLayout?
                .layoutAttributesForItem(at: laterIndexPath)?.frame,
            "target must keep valid layout attributes after later change",
        )
        XCTAssertTrue(
            fixture.view.scrollView.contentView.bounds.intersects(laterFrame),
            "selection target must remain visible after later entry-count change",
        )
    }

    /// EVM-002-manage_entries_view_type_scroll-grid_selection_scroll_wins_over_saved_offset:
    /// snapshot rebuild 중 selection scroll이 saved offset 복원보다 우선하고, 성공한 selection scroll은
    /// 이후 복원 기회를 소비해 뒤늦은 stale offset 점프도 차단한다.
    /// rebuild로 section이 재구성되고 entry 수가 변해 복원 자격이 생겨도, selection scroll이 성공했다면
    /// saved offset이 그 결과를 덮어쓰지 않아야 하고, 이후 선택 의도 없는 구조 변화에서도
    /// stale saved offset으로 복원되지 않아야 한다.
    /// - 검증 내용: rebuild + entry count 변화 + shouldScrollToSelection false→true 엣지에서 최종 clip origin이
    ///   saved offset이 아니고, target이 visible로 유지되며, selection 불변과 scroll flag reset 계약이 유지된다.
    ///   이어지는 선택 의도 없는 entry 수 변화 snapshot에서 clip origin이 saved offset으로 이동하지 않고
    ///   selection scroll 결과 위치에 유지되며 target 가시성도 보존된다.
    /// - 사전 조건: window에 mount된 grid에 80개 entry가 있고 savedScrollOffset(y=37)이 target center와
    ///   다른 값으로 저장돼 있으며, 이전 snapshot은 40개 entry와 shouldScrollToSelection == false다.
    /// - 기대 결과: selection scroll 후 saved offset 복원이 건너뛰어져 origin != savedOffset,
    ///   target indexPath가 visible 목록에 남고, selectedIds 불변, shouldScrollToSelection == false.
    ///   이후 80→100 entry 변화에서도 origin 불변(savedOffset 아님), target visible 유지.
    func testGridSelectionScrollWinsOverSavedOffsetDuringSnapshotRebuild() throws {
        let fixture = makeGridSelectionScrollFixture()

        var previousState = EntryViewLayoutState()
        previousState.entries = Array(fixture.entries.prefix(40))
        previousState.savedScrollOffset = CGPoint(x: 0, y: 37)
        previousState.shouldScrollToSelection = false

        fixture.coordinator.handleSnapshotChanges(
            previous: EntryGridRenderSnapshot(state: previousState),
            snapshot: EntryGridRenderSnapshot(state: fixture.store.state),
        )

        XCTAssertNotEqual(
            gridClipOrigin(fixture.view),
            CGPoint(x: 0, y: 37),
            "saved offset must not overwrite selection scroll during snapshot rebuild",
        )
        let targetIndexPath = try XCTUnwrap(fixture.coordinator.indexPathByEntryId[fixture.target.id])
        // 프로그램 스크롤 직후에는 indexPathsForVisibleItems 캐시가 갱신되지 않으므로
        // layout attribute frame과 clip bounds의 교차로 가시성을 결정적으로 검증한다.
        let targetFrame = try XCTUnwrap(
            fixture.view.collectionView.collectionViewLayout?
                .layoutAttributesForItem(at: targetIndexPath)?.frame,
            "target must have valid layout attributes",
        )
        XCTAssertTrue(
            fixture.view.scrollView.contentView.bounds.intersects(targetFrame),
            "selection target must remain visible after snapshot rebuild",
        )
        XCTAssertEqual(fixture.store.state.selectedIds, [fixture.target.id], "selection must be unchanged")
        XCTAssertFalse(fixture.store.state.shouldScrollToSelection, "scroll flag must be reset after consume")

        // 이후 선택 의도 없는 entry 수 변화에서 stale saved offset 복원이 발생하지 않는다.
        // selection scroll이 복원 기회를 소비했음을 검증한다.
        try assertDeferredCountChangePreservesSelectionScroll(
            fixture: fixture,
            originAfterSelectionScroll: gridClipOrigin(fixture.view),
        )
    }

    // MARK: - EVM-002-manage_entries_view_type_scroll_grid_initial_bind_consume

    /// EVM-002-manage_entries_view_type_scroll: grid는 첫 bind 전에 설정된 유효 pending target을 첫 layout까지
    /// 보존했다가, layout 이후 scroll이 가능한 시점에 소비해 실제로 스크롤하고 reset한다.
    ///
    /// - 검증 내용: bind는 layout 전이라 scrollToItems가 유효하지 않으므로 pending target이 아직 reset되지 않고
    ///   보존돼야 한다. 첫 layout 이후 소비되어 clip offset이 실제로 이동하고 pending이 nil로 reset된다.
    /// - 사전 조건: pending target id가 bind 이전부터 실제 entry의 id로 설정돼 있다.
    /// - 기대 결과: bind 직후에는 pending이 보존되고, layout 후 clip offset 이동 + pendingTypeScrollTargetId == nil,
    ///   selectedIds 불변.
    func testGridConsumesPendingTypeScrollTargetPresentBeforeFirstBind() {
        let entries = (0 ..< 80).map { index in
            EntryModel.temporaryFolder(id: "/root/\(index)", name: "file\(index)")
        }
        let target = entries[70]
        var state = EntryViewLayoutState()
        state.entries = entries
        state.selectedIds = [entries[0].id]
        // bind 이전부터 pending target이 설정돼 있다 (unmount 중 생성 시나리오).
        state.pendingTypeScrollTargetId = target.id
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryGridCoordinator(store: store)
        let view = EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        coordinator.bind(to: view)

        // bind는 layout 전이라 유효 스크롤이 불가능 → pending target은 아직 reset되지 않고 보존돼야 한다.
        XCTAssertNotNil(coordinator.indexPathByEntryId[target.id], "target must be mappable to an indexPath")
        XCTAssertEqual(
            store.state.pendingTypeScrollTargetId,
            target.id,
            "pending target must survive bind until first layout",
        )
        XCTAssertEqual(store.state.selectedIds, [entries[0].id], "selection must be unchanged at bind")

        // mounted/laid-out 상태에서 scrollToItems가 실제로 clip offset을 이동시킬 수 있어야 한다.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
        )
        window.contentView = view
        view.layoutSubtreeIfNeeded()

        XCTAssertNil(store.state.pendingTypeScrollTargetId, "pending target must be reset after first layout consume")
        XCTAssertNotEqual(gridClipOrigin(view), .zero, "grid must actually scroll to the target after layout")
        XCTAssertEqual(store.state.selectedIds, [entries[0].id], "selection must be unchanged")
    }

    /// EVM-002-manage_entries_view_type_scroll: grid는 bind 후 첫 physical layout 전에 도착한 target도 보존한다.
    ///
    /// - 검증 내용: nil→id snapshot edge가 첫 layout 전에는 scroll/reset되지 않고, mounted 첫 layout에서 실제 scroll 후
    ///   reset되며 후속 layout에서는 중복 소비하지 않는다.
    /// - 사전 조건: pending target 없이 bind한 뒤 첫 layout 전에 offscreen target을 설정한다.
    /// - 기대 결과: layout 전 pending/offset 유지, 첫 layout 후 offset 이동 + pending nil, 재-layout 후 offset 불변.
    func testGridDefersPostBindTypeScrollTargetUntilFirstPhysicalLayout() {
        let entries = (0 ..< 80).map { index in
            EntryModel.temporaryFolder(id: "/root/\(index)", name: "file\(index)")
        }
        let target = entries[70]
        var state = EntryViewLayoutState()
        state.entries = entries
        state.selectedIds = [entries[0].id]
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryGridCoordinator(store: store)
        let view = EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        coordinator.bind(to: view)
        coordinator.isRenderObservationEnabled = false

        let beforeOrigin = gridClipOrigin(view)
        store.send(.view(.setTypeScrollTarget(target.id)))
        var currentState = state
        currentState.pendingTypeScrollTargetId = target.id
        coordinator.handleSnapshotChanges(
            previous: EntryGridRenderSnapshot(state: state),
            snapshot: EntryGridRenderSnapshot(state: currentState),
        )

        XCTAssertEqual(store.state.pendingTypeScrollTargetId, target.id, "pending target must survive before layout")
        XCTAssertEqual(gridClipOrigin(view), beforeOrigin, "pre-layout target must not move the grid")
        XCTAssertEqual(store.state.selectedIds, [entries[0].id], "selection must stay unchanged before layout")

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
        )
        window.contentView = view
        view.layoutSubtreeIfNeeded()

        let consumedOrigin = gridClipOrigin(view)
        XCTAssertNil(store.state.pendingTypeScrollTargetId, "first physical layout must reset after scrolling")
        XCTAssertNotEqual(consumedOrigin, beforeOrigin, "first physical layout must scroll to the target")
        XCTAssertEqual(store.state.selectedIds, [entries[0].id], "selection must stay unchanged after consume")

        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(gridClipOrigin(view), consumedOrigin, "later layouts must not consume the same target twice")
        XCTAssertNil(store.state.pendingTypeScrollTargetId)
    }

    /// EVM-002-manage_entries_view_type_scroll: grid는 첫 bind 전에 설정된 stale/unknown pending target이면
    /// 스크롤하지 않고 reset만 한다.
    ///
    /// - 검증 내용: pending target id가 grid에 없어도 reset이 발행돼 일회성 소비가 보장된다.
    /// - 사전 조건: pending target id가 bind 이전부터 grid에 없는 id다.
    /// - 기대 결과: consume 후 clip offset이 불변이고 pendingTypeScrollTargetId == nil.
    func testGridConsumesStalePendingTypeScrollTargetBeforeFirstBind() {
        let entries = (0 ..< 20).map { index in
            EntryModel.temporaryFolder(id: "/root/\(index)", name: "file\(index)")
        }
        var state = EntryViewLayoutState()
        state.entries = entries
        state.pendingTypeScrollTargetId = "/root/does-not-exist"
        let store = Store(initialState: state) { EntryViewLayoutFeature() }
        let coordinator = EntryGridCoordinator(store: store)
        let view = EntryGridView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        coordinator.bind(to: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
        )
        window.contentView = view
        view.layoutSubtreeIfNeeded()

        let beforeOrigin = gridClipOrigin(view)
        coordinator.handleSnapshotChanges(
            previous: EntryGridRenderSnapshot(state: state),
            snapshot: EntryGridRenderSnapshot(state: state),
        )
        XCTAssertEqual(gridClipOrigin(view), beforeOrigin, "stale target must not change scroll")
        XCTAssertNil(store.state.pendingTypeScrollTargetId, "stale target must still reset after initial-bind consume")
    }
}
