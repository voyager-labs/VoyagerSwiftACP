import ComposableArchitecture
import Foundation
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
final class CTM002SetCurrentContentTabTests: XCTestCase {
    // MARK: - CTM-002-set_current_content_tab_by_index

    /// CTM-002-set_current_content_tab_by_index: 현재 Content Tab 전환과 selection 독립성 검증
    /// Sidebar primary click이나 index 기반 선택이 공유할 reducer contract를 검증한다.
    /// - 검증 내용: setCurrent가 previous/active identity만 갱신하고 tab rows, selection, anchor를 보존함
    /// - 사전 조건: Home, Directory, Collection 세 탭과 Home active, 기존 previous/selection/anchor 상태
    /// - 기대 결과: 지정한 tab id가 active가 되고 직전 active가 previous가 되며 나머지 상태는 변경되지 않음
    func testSetCurrentContentTabByIndex_activatesTargetPreservingSelectionAndAnchor() async {
        let homeID = ContentTabID()
        let directoryID = ContentTabID()
        let collectionID = ContentTabID()
        let tabs: IdentifiedArrayOf<ContentTabItem> = [
            ContentTabItem(id: homeID, page: .home, anchor: .homeDefault, isPinned: false, title: nil, iconName: nil),
            ContentTabItem(
                id: directoryID,
                page: .directory,
                anchor: .directory(path: "/test1"),
                isPinned: false,
                title: nil,
                iconName: nil,
            ),
            ContentTabItem(
                id: collectionID,
                page: .collection,
                anchor: .collectionFile(url: URL(fileURLWithPath: "/test/file.collection")),
                isPinned: false,
                title: nil,
                iconName: nil,
            ),
        ]
        var state = ContentTabState(
            tabs: tabs,
            activeTabID: homeID,
            previousActiveTabID: directoryID,
            recentlyClosed: nil,
        )
        state.selectedTabIDs = [homeID, collectionID]
        state.selectionAnchorID = directoryID
        let expectedTabs = state.tabs
        let store = TestStore(initialState: state) {
            ContentTabFeature()
        }

        await store.send(.setCurrent(collectionID)) {
            $0.previousActiveTabID = homeID
            $0.activeTabID = collectionID
            $0.recentlyUsedTabIDs = [collectionID, homeID]
        }
        assertTabSelectionPreserved(
            store.state,
            tabs: expectedTabs,
            selected: [homeID, collectionID],
            anchor: directoryID,
        )

        await store.send(.setCurrent(directoryID)) {
            $0.previousActiveTabID = collectionID
            $0.activeTabID = directoryID
            $0.recentlyUsedTabIDs = [directoryID, collectionID, homeID]
        }
        assertTabSelectionPreserved(
            store.state,
            tabs: expectedTabs,
            selected: [homeID, collectionID],
            anchor: directoryID,
        )
    }

    /// CTM-002-set_current_content_tab_by_index: 존재하지 않는 Content Tab 선택은 전체 상태 no-op
    /// 사용자가 stale index에 해당하는 target을 선택해도 현재 tab 문맥이 손상되지 않는지 검증한다.
    /// - 검증 내용: setCurrent가 missing ID에서 ContentTabState의 어떤 필드도 변경하지 않음
    /// - 사전 조건: non-nil previousActiveTabID와 selection, anchor를 가진 Directory active 상태
    /// - 기대 결과: action 전후의 전체 ContentTabState가 동일함
    func testSetCurrentContentTabByIndex_missingTargetIsWholeStateNoOp() async {
        let homeID = ContentTabID()
        let directoryID = ContentTabID()
        let missingID = ContentTabID()
        let tabs: IdentifiedArrayOf<ContentTabItem> = [
            ContentTabItem(
                id: homeID,
                page: .home,
                anchor: .homeDefault,
                isPinned: true,
                title: "Pinned Home",
                iconName: "house",
            ),
            ContentTabItem(
                id: directoryID,
                page: .directory,
                anchor: .directory(path: "/missing-target"),
                isPinned: false,
                title: "Current Directory",
                iconName: "folder",
            ),
        ]
        var state = ContentTabState(
            tabs: tabs,
            activeTabID: directoryID,
            previousActiveTabID: homeID,
            recentlyClosed: nil,
        )
        state.selectedTabIDs = [homeID, directoryID]
        state.selectionAnchorID = homeID
        let expectedState = state
        let store = TestStore(initialState: state) {
            ContentTabFeature()
        }

        await store.send(.setCurrent(missingID))

        XCTAssertEqual(store.state, expectedState)
    }

    /// CTM-002-set_current_content_tab_by_index: parent가 존재하지 않는 stale Content Tab 전환을 전체 window no-op으로 유지함
    /// child setCurrent가 거부한 target으로 parent runtime handoff가 진행되지 않는지 full FileManager reducer에서 검증한다.
    /// - 검증 내용: current/cache content, inspector, active/previous, selection, anchor, Sidebar projection 전체 불변
    /// - 사전 조건: active A, previous B, missing C와 서로 다른 live/cache content 및 inspector snapshot
    /// - 기대 결과: C를 setCurrent해도 전체 FileManagerFeature.State가 동일하고 후속 action/effect가 없음
    func testSetCurrentContentTabByIndex_missingStaleTargetIsWholeWindowStateNoOpAtParent() async {
        let activeID = ContentTabID(rawValue: "stale-active-A")
        let previousID = ContentTabID(rawValue: "stale-previous-B")
        let missingID = ContentTabID(rawValue: "stale-missing-C")
        let state = makeStaleTargetWindowState(
            activeID: activeID,
            previousID: previousID,
        )

        let expectedState = state
        let expectedSidebarProjection = state.sidebar.contentTabSidebarItems
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }

        await store.send(.contentTabs(.setCurrent(missingID)))

        XCTAssertEqual(store.state, expectedState)
        XCTAssertEqual(store.state.sidebar.contentTabSidebarItems, expectedSidebarProjection)
    }

    // MARK: - CTM-002-set_current_content_tab_by_number

    /// CTM-002-set_current_content_tab_by_number: 이미 active인 표시 위치 선택은 전체 window state no-op
    /// 사용자가 현재 Content Tab의 숫자 shortcut을 다시 입력해도 runtime snapshot과 history가 유지되는지 검증한다.
    /// - 검증 내용: command admission이 setCurrent child action과 parent handoff를 방출하지 않고 전체 state를 보존함
    /// - 사전 조건: non-nil previousActiveTabID와 서로 다른 runtime snapshot을 가진 첫 번째 tab active 상태
    /// - 기대 결과: 숫자 command 전후 FileManagerFeature.State가 동일하고 수신 action이 없음
    func testSelectContentTabByNumber_sameActivePositionIsWholeWindowStateNoOp() async {
        let activeID = ContentTabID(rawValue: "same-active")
        let previousID = ContentTabID(rawValue: "same-previous")
        var state = makePositionWindowState(
            tabs: [makePositionTab(id: activeID), makePositionTab(id: previousID)],
            activeTabID: activeID,
        )
        state.contentTabs.previousActiveTabID = previousID
        state.contentTabs.selectedTabIDs = [activeID, previousID]
        state.contentTabs.selectionAnchorID = previousID
        let expectedState = state
        let store = makePositionStore(initialState: state)

        await store.send(.request(.selectContentTab(position: 1)))

        XCTAssertEqual(store.state, expectedState)
    }

    /// CTM-002-set_current_content_tab_by_number: position 1...9가 현재 표시 ID와 정확히 대응함
    /// 사용자가 숫자 shortcut을 누를 때 현재 Content Tab 표시 위치의 tab으로 전환되는지 검증한다.
    /// - 검증 내용: projection의 1-based mapping과 command가 방출하는 setCurrent 및 runtime handoff identity
    /// - 사전 조건: 서로 다른 Directory runtime snapshot을 가진 unpinned tab 9개와 아홉 번째 active 상태
    /// - 기대 결과: position 1...9 각각이 같은 위치의 ID를 활성화하고 selection과 anchor를 보존함
    func testSelectContentTabByNumber_positionsOneThroughNineMapExactVisibleIDs() async {
        let ids = (1 ... 9).map { ContentTabID(rawValue: "position-\($0)") }
        var state = makePositionWindowState(
            tabs: IdentifiedArray(uniqueElements: ids.map { makePositionTab(id: $0) }),
            activeTabID: ids[8],
        )
        state.contentTabs.selectedTabIDs = [ids[1], ids[7]]
        state.contentTabs.selectionAnchorID = ids[7]
        let store = makePositionStore(initialState: state)
        // store.exhaustivity = .off: 기존 setCurrent runtime handoff의 광범위한 child action보다 position identity와 최종 snapshot을
        // 검증한다.
        store.exhaustivity = .off

        for (position, expectedID) in zip(1 ... 9, ids) {
            await assertPositionCommand(position, selects: expectedID, store: store)
        }

        await store.finish()
    }

    /// CTM-002-set_current_content_tab_by_number: mixed raw tabs는 pinned-first 표시 순서를 사용함
    /// raw storage가 pinned와 unpinned를 교차해도 숫자 shortcut은 Sidebar와 같은 표시 순서를 따라야 한다.
    /// - 검증 내용: raw tabs index가 아니라 selectionOrderedTabIDs를 매 command 시점에 position mapping으로 사용함
    /// - 사전 조건: raw U1/P1/U2/P2/U3/P3/U4/P4/U5와 U5 active, non-empty selection/anchor
    /// - 기대 결과: position 1...9가 P1/P2/P3/P4/U1/U2/U3/U4/U5 순서로 전환됨
    func testSelectContentTabByNumber_mixedRawTabsUsePinnedFirstVisibleOrder() async {
        let unpinned = (1 ... 5).map { ContentTabID(rawValue: "U\($0)") }
        let pinned = (1 ... 4).map { ContentTabID(rawValue: "P\($0)") }
        let rawTabs: IdentifiedArrayOf<ContentTabItem> = [
            makePositionTab(id: unpinned[0]),
            makePositionTab(id: pinned[0], isPinned: true),
            makePositionTab(id: unpinned[1]),
            makePositionTab(id: pinned[1], isPinned: true),
            makePositionTab(id: unpinned[2]),
            makePositionTab(id: pinned[2], isPinned: true),
            makePositionTab(id: unpinned[3]),
            makePositionTab(id: pinned[3], isPinned: true),
            makePositionTab(id: unpinned[4]),
        ]
        let expectedVisibleIDs = pinned + unpinned
        var state = makePositionWindowState(tabs: rawTabs, activeTabID: unpinned[4])
        state.contentTabs.selectedTabIDs = [pinned[1], unpinned[2]]
        state.contentTabs.selectionAnchorID = unpinned[2]
        let store = makePositionStore(initialState: state)
        // store.exhaustivity = .off: 기존 setCurrent runtime handoff의 광범위한 child action보다 pinned-first mapping과 최종
        // snapshot을 검증한다.
        store.exhaustivity = .off

        XCTAssertEqual(store.state.contentTabs.tabs.ids, rawTabs.ids)
        XCTAssertEqual(store.state.contentTabs.selectionOrderedTabIDs, expectedVisibleIDs)
        for (position, expectedID) in zip(1 ... 9, expectedVisibleIDs) {
            await assertPositionCommand(position, selects: expectedID, store: store)
        }

        await store.finish()
    }

    /// CTM-002-set_current_content_tab_by_number: 부족한 tab과 범위 밖 position은 전체 상태 no-op
    /// 표시 가능한 tab이 없는 position이나 내부 방어 범위를 벗어난 값은 어떤 command도 실행하지 않아야 한다.
    /// - 검증 내용: position 4...9 및 내부 방어 position 0/10에서 state/effect 완전 불변
    /// - 사전 조건: non-nil previous/selection/anchor와 서로 다른 runtime snapshot을 가진 tab 3개
    /// - 기대 결과: 모든 no-op position 전후 FileManagerWindowState와 runtime snapshot이 동일하고 수신 action이 없음
    func testSelectContentTabByNumber_insufficientAndOutOfRangePositionsAreWholeStateNoOps() async {
        let ids = (1 ... 3).map { ContentTabID(rawValue: "short-\($0)") }
        var state = makePositionWindowState(
            tabs: IdentifiedArray(uniqueElements: ids.map { makePositionTab(id: $0) }),
            activeTabID: ids[0],
        )
        state.contentTabs.previousActiveTabID = ids[2]
        state.contentTabs.selectedTabIDs = [ids[0], ids[2]]
        state.contentTabs.selectionAnchorID = ids[2]
        let expectedState = state
        let store = makePositionStore(initialState: state)

        for position in [0] + Array(4 ... 9) + [10] {
            XCTAssertNil(ContentTabProjection.tabID(atDisplayPosition: position, in: store.state.contentTabs))
            let command = FileManagerWindowAction.WindowCommand.selectContentTab(position: position)
            await store.send(.request(command))
            XCTAssertEqual(store.state, expectedState)
        }
    }

    /// CTM-002-set_current_content_tab_by_number: reorder와 close 직후 최신 표시 순서를 다시 계산함
    /// tab topology가 바뀐 뒤 숫자 shortcut이 이전 순서를 cache하지 않고 현재 state를 읽는지 검증한다.
    /// - 검증 내용: reorder 후 position 2, inactive close 후 position 3의 projection/command/runtime handoff
    /// - 사전 조건: A/B/C/D unpinned tabs, A active, A/C selection과 C anchor
    /// - 기대 결과: A/D/B/C에서 position 2는 D, B close 후 A/D/C에서 position 3은 C를 활성화함
    func testSelectContentTabByNumber_recomputesAfterReorderAndCloseUpdates() async {
        let ids = ["A", "B", "C", "D"].map(ContentTabID.init(rawValue:))
        var state = makePositionWindowState(
            tabs: IdentifiedArray(uniqueElements: ids.map { makePositionTab(id: $0) }),
            activeTabID: ids[0],
        )
        state.contentTabs.selectedTabIDs = [ids[0], ids[2]]
        state.contentTabs.selectionAnchorID = ids[2]
        let store = makePositionStore(initialState: state)
        // store.exhaustivity = .off: 기존 reorder/close와 setCurrent handoff의 child action보다 매 command 시점의 재계산 결과를 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.reorder(sourceID: ids[3], targetID: ids[1], placement: .before)))
        await store.skipReceivedActions(strict: false)
        XCTAssertEqual(store.state.contentTabs.selectionOrderedTabIDs, [ids[0], ids[3], ids[1], ids[2]])
        await assertPositionCommand(2, selects: ids[3], store: store)

        await store.send(.contentTabs(.close(ids[1])))
        await store.skipReceivedActions(strict: false)
        XCTAssertEqual(store.state.contentTabs.selectionOrderedTabIDs, [ids[0], ids[3], ids[2]])
        await assertPositionCommand(3, selects: ids[2], store: store)

        await store.finish()
    }

    /// CTM-002-set_current_content_tab_by_number: duplicate와 restore 직후 최신 표시 순서를 다시 계산함
    /// 새 identity가 추가된 뒤 숫자 shortcut이 별도 mapping cache 없이 현재 tabs를 사용하는지 검증한다.
    /// - 검증 내용: duplicate row와 restore row가 추가된 직후 projection/command가 새 position을 선택함
    /// - 사전 조건: A/B tabs, A active, B duplicate ID와 Directory recentlyClosed snapshot
    /// - 기대 결과: duplicate 후 position 3은 D, restore 후 position 4는 새 restored ID를 활성화함
    func testSelectContentTabByNumber_recomputesAfterDuplicateAndRestoreUpdates() async throws {
        let tabA = ContentTabID(rawValue: "duplicate-A")
        let tabB = ContentTabID(rawValue: "duplicate-B")
        let duplicateID = ContentTabID(rawValue: "duplicate-D")
        var state = makePositionWindowState(
            tabs: [makePositionTab(id: tabA), makePositionTab(id: tabB)],
            activeTabID: tabA,
        )
        state.contentTabs.selectedTabIDs = [tabA, tabB]
        state.contentTabs.selectionAnchorID = tabB
        state.contentTabs.recentlyClosed = ClosedContentTabSnapshot(
            page: .directory,
            anchor: .directory(path: "/position/restored"),
            wasPinned: false,
            closedAt: Date(timeIntervalSince1970: 1_234_567_890),
            title: "Restored",
            iconName: "folder",
        )
        let store = makePositionStore(initialState: state)
        // store.exhaustivity = .off: duplicate/restore가 생성하는 handoff child action보다 새 identity를 포함한 live mapping을 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.duplicate(sourceID: tabB, duplicateID: duplicateID)))
        await store.skipReceivedActions(strict: false)
        XCTAssertEqual(store.state.contentTabs.selectionOrderedTabIDs, [tabA, tabB, duplicateID])
        await assertPositionCommand(2, selects: tabB, store: store)
        await assertPositionCommand(3, selects: duplicateID, store: store)

        await store.send(.contentTabs(.restore))
        await store.skipReceivedActions(strict: false)
        let restoredID = try XCTUnwrap(store.state.contentTabs.tabs.last?.id)
        XCTAssertEqual(store.state.contentTabs.selectionOrderedTabIDs, [tabA, tabB, duplicateID, restoredID])
        await assertPositionCommand(1, selects: tabA, store: store)
        await assertPositionCommand(4, selects: restoredID, store: store)

        await store.finish()
    }

    /// CTM-002-set_current_content_tab_by_number: selected-tab close pending 중 command는 전체 상태 no-op
    /// batch close transaction 중 숫자 shortcut이 현재 close target과 runtime handoff를 우회하지 않는지 검증한다.
    /// - 검증 내용: 유효한 position mapping이 있어도 request admission에서 state/effect를 완전히 차단함
    /// - 사전 조건: A/B tabs, A active, A/B selected, A current인 PendingSelectedContentTabClose
    /// - 기대 결과: position 2 command 전후 FileManagerWindowState가 동일하고 수신 action이 없음
    func testSelectContentTabByNumber_pendingSelectedCloseIsWholeStateNoOp() async throws {
        let tabA = ContentTabID(rawValue: "pending-A")
        let tabB = ContentTabID(rawValue: "pending-B")
        var state = makePositionWindowState(
            tabs: [makePositionTab(id: tabA), makePositionTab(id: tabB)],
            activeTabID: tabA,
        )
        state.contentTabs.previousActiveTabID = tabB
        state.contentTabs.selectedTabIDs = [tabA, tabB]
        state.contentTabs.selectionAnchorID = tabB
        state.pendingSelectedContentTabClose = try PendingSelectedContentTabClose(
            operationID: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000634")),
            orderedTargetIDs: [tabA, tabB],
            currentTabID: tabA,
            originalActiveTabID: tabA,
            preferredFallbackIDs: [tabB],
        )
        let expectedState = state
        let store = makePositionStore(initialState: state)

        XCTAssertEqual(ContentTabProjection.tabID(atDisplayPosition: 2, in: state.contentTabs), tabB)
        let command = FileManagerWindowAction.WindowCommand.selectContentTab(position: 2)
        await store.send(.request(command))
        XCTAssertEqual(store.state, expectedState)
    }

    /// CTM-002-set_current_content_tab_by_number: 단일 tab teardown 중 command는 전체 상태 no-op
    /// Undo owner 무효화가 끝나기 전 숫자 shortcut이 active tab runtime handoff를 시작하지 않는지 검증한다.
    /// - 검증 내용: pending teardown 또는 tearingDownTab phase에서 유효한 position request의 state/effect 완전 차단
    /// - 사전 조건: A/B tabs, A active와 B target, 동일 request/owner identity를 가진 각 teardown lifecycle 상태
    /// - 기대 결과: position 2 command 전후 FileManagerWindowState가 동일하고 수신 action이 없음
    func testSelectContentTabByNumber_singleTabTeardownIsWholeStateNoOp() async throws {
        let tabA = ContentTabID(rawValue: "teardown-A")
        let tabB = ContentTabID(rawValue: "teardown-B")
        let requestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000635"))
        let ownerID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000636"))
        var baseState = makePositionWindowState(
            tabs: [makePositionTab(id: tabA), makePositionTab(id: tabB)],
            activeTabID: tabA,
        )
        baseState.contentTabs.previousActiveTabID = tabB
        baseState.contentTabs.selectedTabIDs = [tabA, tabB]
        baseState.contentTabs.selectionAnchorID = tabB

        var pendingTeardownState = baseState
        pendingTeardownState.pendingContentTabTeardown = PendingContentTabTeardown(
            requestID: requestID,
            tabID: tabA,
            ownerID: ownerID,
        )
        var tearingDownPhaseState = baseState
        tearingDownPhaseState.undoRedoPhase = .tearingDownTab(requestID: requestID, ownerID: ownerID)

        for state in [pendingTeardownState, tearingDownPhaseState] {
            let store = makePositionStore(initialState: state)

            XCTAssertEqual(ContentTabProjection.tabID(atDisplayPosition: 2, in: state.contentTabs), tabB)
            await store.send(.request(.selectContentTab(position: 2)))
            XCTAssertEqual(store.state, state)
        }
    }

    // MARK: - CTM-002-set_current_content_tab_to_last_used

    /// CTM-002-set_current_content_tab_to_last_used: 최근 사용 순서의 첫 유효 후보로 즉시 전환
    /// Ctrl-Tab 명령이 window-local MRU 순서를 사용하고 반복 입력 시 두 최근 탭을 왕복하는지 검증한다.
    /// - 검증 내용: C/B/A MRU에서 B 활성화 후 B/C/A로 갱신되고 다음 명령이 C를 활성화함
    /// - 사전 조건: A→B→C 사용 순서와 C active인 세 Directory Content Tab
    /// - 기대 결과: 첫 명령은 B, 다음 명령은 C를 활성화하며 기존 runtime handoff 경로를 재사용함
    func testSelectMostRecentlyUsedContentTab_togglesFirstValidCandidate() async {
        let tabA = ContentTabID(rawValue: "mru-A")
        let tabB = ContentTabID(rawValue: "mru-B")
        let tabC = ContentTabID(rawValue: "mru-C")
        var state = makePositionWindowState(
            tabs: [makePositionTab(id: tabA), makePositionTab(id: tabB), makePositionTab(id: tabC)],
            activeTabID: tabC,
        )
        state.contentTabs.recentlyUsedTabIDs = [tabC, tabB, tabA]
        let store = makePositionStore(initialState: state)
        // store.exhaustivity = .off: 기존 active Content Tab runtime handoff의 세부 action보다 MRU identity 전환을 검증한다.
        store.exhaustivity = .off

        await store.send(.request(.selectMostRecentlyUsedContentTab))
        await store.receive(\.contentTabs.setCurrent, tabB)
        await store.skipReceivedActions(strict: false)
        XCTAssertEqual(store.state.contentTabs.activeTabID, tabB)
        XCTAssertEqual(store.state.contentTabs.recentlyUsedTabIDs, [tabB, tabC, tabA])

        await store.send(.request(.selectMostRecentlyUsedContentTab))
        await store.receive(\.contentTabs.setCurrent, tabC)
        await store.skipReceivedActions(strict: false)
        XCTAssertEqual(store.state.contentTabs.activeTabID, tabC)
        XCTAssertEqual(store.state.contentTabs.recentlyUsedTabIDs, [tabC, tabB, tabA])
        await store.finish()
    }

    /// CTM-002-set_current_content_tab_to_last_used: stale 최근 후보를 제거하고 다음 유효 후보로 전환
    /// 닫히거나 이동된 identity가 MRU 선두에 남아도 명령 경계에서 정리하고 탐색을 계속하는지 검증한다.
    /// - 검증 내용: stale ID 제거와 다음 live B 후보의 setCurrent/runtime handoff
    /// - 사전 조건: C active, MRU C/stale/B, live tabs B/C
    /// - 기대 결과: stale ID가 MRU에서 제거되고 B가 active가 됨
    func testSelectMostRecentlyUsedContentTab_prunesStaleCandidateAndSelectsNextLiveTab() async {
        let tabB = ContentTabID(rawValue: "mru-live-B")
        let tabC = ContentTabID(rawValue: "mru-live-C")
        let staleID = ContentTabID(rawValue: "mru-stale")
        var state = makePositionWindowState(
            tabs: [makePositionTab(id: tabB), makePositionTab(id: tabC)],
            activeTabID: tabC,
        )
        state.contentTabs.recentlyUsedTabIDs = [tabC, staleID, tabB]
        let store = makePositionStore(initialState: state)
        // store.exhaustivity = .off: 기존 runtime handoff보다 stale prune와 선택된 identity를 검증한다.
        store.exhaustivity = .off

        await store.send(.request(.selectMostRecentlyUsedContentTab)) {
            $0.contentTabs.recentlyUsedTabIDs = [tabC, tabB]
        }
        await store.receive(\.contentTabs.setCurrent, tabB)
        await store.skipReceivedActions(strict: false)

        XCTAssertEqual(store.state.contentTabs.activeTabID, tabB)
        XCTAssertEqual(store.state.contentTabs.recentlyUsedTabIDs, [tabB, tabC])
        await store.finish()
    }

    /// CTM-002-set_current_content_tab_to_last_used: 유효한 최근 후보가 없으면 현재 탭을 유지하고 실패 피드백 표시
    /// 모든 MRU 후보가 stale일 때 조용히 실패하지 않고 사용자에게 전환 불가를 알리는지 검증한다.
    /// - 검증 내용: stale history 정리, active/runtime 불변, collectionAlertClient 피드백
    /// - 사전 조건: C만 열린 상태와 stale ID만 가진 MRU
    /// - 기대 결과: C가 계속 active이고 "Cannot Switch Tabs" 경고가 한 번 표시됨
    func testSelectMostRecentlyUsedContentTab_allCandidatesStalePreservesActiveAndShowsFeedback() async {
        let tabC = ContentTabID(rawValue: "mru-only-live-C")
        let staleID = ContentTabID(rawValue: "mru-only-stale")
        var state = makePositionWindowState(tabs: [makePositionTab(id: tabC)], activeTabID: tabC)
        state.contentTabs.recentlyUsedTabIDs = [staleID]
        let alerts = LockIsolated<[(title: String, message: String)]>([])
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { title, message in
                alerts.withValue { $0.append((title, message)) }
            }
        }

        await store.send(.request(.selectMostRecentlyUsedContentTab)) {
            $0.contentTabs.recentlyUsedTabIDs = []
        }
        await store.finish()

        XCTAssertEqual(store.state.contentTabs.activeTabID, tabC)
        XCTAssertEqual(alerts.value.map(\.title), ["Cannot Switch Tabs"])
        XCTAssertEqual(alerts.value.map(\.message), ["No recently used tab is available."])
    }

    /// CTM-002-set_current_content_tab_to_last_used: topology transaction busy 동안 최근 사용 전환 차단
    /// topology transaction이 identity ownership을 변경하는 동안 MRU 전환이 끼어들지 않는지 검증한다.
    /// - 검증 내용: teardown, move 준비/참여, pinned persistence, top navigation, window close의 whole-state no-op
    /// - 사전 조건: A/B live tabs, B active, B/A MRU와 각 busy sentinel
    /// - 기대 결과: 모든 busy 상태에서 active/MRU/runtime이 유지되고 수신 action이 없음
    func testSelectMostRecentlyUsedContentTab_topologyBusyStatesAreWholeStateNoOps() async throws {
        let tabA = ContentTabID(rawValue: "mru-busy-A")
        let tabB = ContentTabID(rawValue: "mru-busy-B")
        let requestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000464"))
        let ownerID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000465"))
        var baseState = makePositionWindowState(
            tabs: [makePositionTab(id: tabA), makePositionTab(id: tabB)],
            activeTabID: tabB,
        )
        baseState.contentTabs.recentlyUsedTabIDs = [tabB, tabA]

        var teardownState = baseState
        teardownState.pendingContentTabTeardown = PendingContentTabTeardown(
            requestID: requestID,
            tabID: tabB,
            ownerID: ownerID,
        )
        var transferState = baseState
        transferState.contentTabMoveParticipantRequestID = requestID
        let moveRequest = ContentTabMoveRequest(
            requestID: requestID,
            sourceWindowID: ownerID,
            tabID: tabB,
            targetWindowID: UUID(),
        )
        var pendingMoveState = baseState
        pendingMoveState.pendingContentTabMove = .init(request: moveRequest, lifecycle: .inFlight)
        var pinPersistenceState = baseState
        pinPersistenceState.contentTabs.pendingPinnedRecordIDs = [tabB]
        var topNavigationState = baseState
        topNavigationState.pendingTopNavigationIntents = [
            .init(
                token: FileManagerTopNavigationOperationToken(value: requestID),
                intent: .close(tabA),
            ),
        ]
        var closingState = baseState
        closingState.isClosing = true

        for state in [
            teardownState,
            transferState,
            pendingMoveState,
            pinPersistenceState,
            topNavigationState,
            closingState,
        ] {
            let store = makePositionStore(initialState: state)
            await store.send(.request(.selectMostRecentlyUsedContentTab))
            XCTAssertEqual(store.state, state)
        }
    }
}

extension CTM002SetCurrentContentTabTests {
    /// CTM-002-set_current_content_tab_to_last_used: 외부 overflow Window 생성 직후 최근 탭 전환
    /// 외부 항목 reservation 순서가 새 Window의 초기 MRU로 이어지는지 검증한다.
    /// - 검증 내용: makeExternalInitial의 newest-first MRU와 첫 Ctrl-Tab의 setCurrent/runtime handoff
    /// - 사전 조건: A, B 외부 항목이 순서대로 예약되고 B가 active인 새 Window
    /// - 기대 결과: 초기 MRU가 B/A이며 첫 최근 사용 전환이 A를 활성화함
    func testSelectMostRecentlyUsedContentTab_externalInitialWindowSwitchesOnFirstCommand() async throws {
        try await assertExternalRecentlyUsedWindowStateAndCommand()
    }
}

private struct ExternalRecentlyUsedWindowScenario {
    let state: FileManagerWindowState
    let firstTabID: ContentTabID
    let activeTabID: ContentTabID
}

private func assertTabSelectionPreserved(
    _ state: ContentTabState,
    tabs: IdentifiedArrayOf<ContentTabItem>,
    selected: Set<ContentTabID>,
    anchor: ContentTabID,
) {
    XCTAssertEqual(state.tabs, tabs)
    XCTAssertEqual(state.selectedTabIDs, selected)
    XCTAssertEqual(state.selectionAnchorID, anchor)
}

private func makeExternalRecentlyUsedWindowState() throws -> ExternalRecentlyUsedWindowScenario {
    let firstTabID = ContentTabID(rawValue: "external-mru-A")
    let activeTabID = ContentTabID(rawValue: "external-mru-B")
    let state = try XCTUnwrap(FileManagerWindowState.makeExternalInitial(reservations: [
        ExternalContentTabReservation(id: firstTabID, anchor: .directory(path: "/external/A")),
        ExternalContentTabReservation(id: activeTabID, anchor: .directory(path: "/external/B")),
    ]))
    return ExternalRecentlyUsedWindowScenario(
        state: state,
        firstTabID: firstTabID,
        activeTabID: activeTabID,
    )
}

@MainActor
private func assertExternalRecentlyUsedWindowStateAndCommand() async throws {
    let scenario = try makeExternalRecentlyUsedWindowState()
    XCTAssertEqual(scenario.state.contentTabs.activeTabID, scenario.activeTabID)
    XCTAssertEqual(scenario.state.contentTabs.previousActiveTabID, scenario.firstTabID)
    XCTAssertEqual(
        scenario.state.contentTabs.recentlyUsedTabIDs,
        [scenario.activeTabID, scenario.firstTabID],
    )
    guard scenario.state.contentTabs.recentlyUsedTabIDs == [scenario.activeTabID, scenario.firstTabID] else { return }

    let store = makePositionStore(initialState: scenario.state)
    // store.exhaustivity = .off: 외부 Window 초기 MRU가 기존 runtime handoff로 연결되는 identity를 검증한다.
    store.exhaustivity = .off

    await store.send(.request(.selectMostRecentlyUsedContentTab))
    await store.receive(\.contentTabs.setCurrent, scenario.firstTabID)
    await store.skipReceivedActions(strict: false)

    XCTAssertEqual(store.state.contentTabs.activeTabID, scenario.firstTabID)
    XCTAssertEqual(store.state.contentTabs.recentlyUsedTabIDs, [scenario.firstTabID, scenario.activeTabID])
    await store.finish()
}

private func makeStaleTargetWindowState(
    activeID: ContentTabID,
    previousID: ContentTabID,
) -> FileManagerFeature.State {
    var state = FileManagerFeature.State()
    state.contentTabs = ContentTabState(
        tabs: [makePositionTab(id: activeID), makePositionTab(id: previousID)],
        activeTabID: activeID,
        previousActiveTabID: previousID,
    )
    state.contentTabs.selectedTabIDs = [activeID, previousID]
    state.contentTabs.selectionAnchorID = previousID
    state.content = makeStaleContent(path: "/live/A", pendingEntryID: "live-A")
    state.tabContentStates = [
        activeID: makeStaleContent(path: "/cached/A", pendingEntryID: "cached-A"),
        previousID: makeStaleContent(path: "/cached/B", pendingEntryID: "cached-B"),
    ]
    state.inspector = makeStaleInspector(isVisible: true, paneExists: true, width: 321)
    state.tabInspectorStates = [
        activeID: makeStaleInspector(isVisible: false, paneExists: false, width: 432).tabSnapshot(),
        previousID: makeStaleInspector(isVisible: true, paneExists: false, width: 543).tabSnapshot(),
    ]
    state.syncContentTabSidebarItems()
    return state
}

private func makeStaleContent(
    path: String,
    pendingEntryID: String,
) -> FileManagerContentFeature.State {
    var content = FileManagerContentFeature.State()
    content.navigation.seedInitialFolderPath(path)
    content.pendingSelectEntryID = pendingEntryID
    return content
}

private func makeStaleInspector(
    isVisible: Bool,
    paneExists: Bool,
    width: CGFloat,
) -> FileManagerInspectorFeature.State {
    var inspector = FileManagerInspectorFeature.State()
    inspector.inspectorVisible = isVisible
    inspector.inspectorPaneExists = paneExists
    inspector.inspectorWidth = width
    return inspector
}

private func makePositionTab(id: ContentTabID, isPinned: Bool = false) -> ContentTabItem {
    ContentTabItem(
        id: id,
        page: .directory,
        anchor: .directory(path: "/position/\(id.rawValue)"),
        isPinned: isPinned,
        title: id.rawValue,
        iconName: "folder",
    )
}

private func makePositionWindowState(
    tabs: IdentifiedArrayOf<ContentTabItem>,
    activeTabID: ContentTabID,
) -> FileManagerFeature.State {
    var state = FileManagerFeature.State()
    state.contentTabs = ContentTabState(tabs: tabs, activeTabID: activeTabID)
    state.tabContentStates = Dictionary(uniqueKeysWithValues: tabs.map { tab in
        var content = FileManagerContentFeature.State()
        if case let .directory(path) = tab.anchor {
            content.navigation.seedInitialFolderPath(path)
        }
        return (tab.id, content)
    })
    if let activeContent = state.tabContentStates[activeTabID] {
        state.content = activeContent
    }
    state.syncContentTabSidebarItems()
    return state
}

@MainActor
private func makePositionStore(
    initialState: FileManagerFeature.State,
) -> TestStoreOf<FileManagerFeature> {
    TestStore(initialState: initialState) {
        FileManagerFeature()
    } withDependencies: {
        $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        $0.entryLoadingClient.loadItems = { _, _ in [] }
        $0.fileChangeGatewayClient.observeEvents = {
            AsyncStream { continuation in continuation.finish() }
        }
    }
}

@MainActor
private func assertPositionCommand(
    _ position: Int,
    selects expectedID: ContentTabID,
    store: TestStoreOf<FileManagerFeature>,
    file: StaticString = #filePath,
    line: UInt = #line,
) async {
    let previousActiveID = store.state.contentTabs.activeTabID
    let selectedTabIDs = store.state.contentTabs.selectedTabIDs
    let selectionAnchorID = store.state.contentTabs.selectionAnchorID
    XCTAssertEqual(
        ContentTabProjection.tabID(atDisplayPosition: position, in: store.state.contentTabs),
        expectedID,
        file: file,
        line: line,
    )

    let command = FileManagerWindowAction.WindowCommand.selectContentTab(position: position)
    await store.send(.request(command))
    await store.receive(\.contentTabs.setCurrent, expectedID)
    await store.skipReceivedActions(strict: false)

    XCTAssertEqual(store.state.contentTabs.previousActiveTabID, previousActiveID, file: file, line: line)
    XCTAssertEqual(store.state.contentTabs.selectedTabIDs, selectedTabIDs, file: file, line: line)
    XCTAssertEqual(store.state.contentTabs.selectionAnchorID, selectionAnchorID, file: file, line: line)
    XCTAssertEqual(
        store.state.sidebar.contentTabSidebarItems.first(where: { $0.isActive })?.id,
        expectedID,
        file: file,
        line: line,
    )
    if case let .directory(path) = store.state.contentTabs.tabs[id: expectedID]?.anchor {
        XCTAssertEqual(store.state.content.navigation.currentPath, path, file: file, line: line)
    } else {
        XCTFail("expected a directory position fixture", file: file, line: line)
    }
}
