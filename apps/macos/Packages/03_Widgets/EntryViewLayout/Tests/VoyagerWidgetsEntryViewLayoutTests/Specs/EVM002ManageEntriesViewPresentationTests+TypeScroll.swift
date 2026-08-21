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

    /// EVM-002-manage_entries_view_type_scroll: synchronizeEntries는 pending target을 소모한다.
    ///
    /// - 검증 내용: entries 동기화가 pendingTypeScrollTargetId를 nil로 만든다.
    /// - 사전 조건: pendingTypeScrollTargetId가 id로 설정돼 있고 entries가 동기화된다.
    /// - 기대 결과: synchronizeEntries 호출 후 pendingTypeScrollTargetId == nil.
    func testSynchronizeEntriesClearsPendingTypeScrollTarget() {
        let id: EntryModel.ID = "/root/target"
        let entry = EntryModel.temporaryFolder(id: id, name: "target")
        var state = EntryViewLayoutState()
        state.entries = [entry]
        state.pendingTypeScrollTargetId = id

        state.synchronizeEntries([entry])

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
}
