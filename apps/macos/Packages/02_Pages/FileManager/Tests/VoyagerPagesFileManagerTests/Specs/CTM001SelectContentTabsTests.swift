import ComposableArchitecture
import Foundation
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
final class CTM001SelectContentTabsTests: XCTestCase {
    // MARK: - CTM-001-select_content_tabs

    /// CTM-001-select_content_tabs: 기본 선택 상태와 selector 및 생성 경로의 runtime 초기값 검증
    /// - 검증 내용: 직접 초기화와 기존 factory가 빈 선택/anchor 및 정확한 computed selector를 제공함
    /// - 사전 조건: 기본 상태와 Home/bootstrap/pinned restore 생성 경로
    /// - 기대 결과: 모든 상태가 빈 선택과 nil anchor로 시작하고 count/bulk selector가 membership을 반영함
    func testSelectionDefaultsAndSelectors_reflectRuntimeSelection() {
        var state = ContentTabState()
        let factoryStates = [
            ContentTabState.withHomeTab(),
            ContentTabState.bootstrapping(),
            ContentTabState.restoringPinnedRecords(from: ContentTabPinnedRecordStore()).state,
        ]

        XCTAssertEqual(state.selectedTabIDs, [])
        XCTAssertNil(state.selectionAnchorID)
        XCTAssertEqual(state.selectedTabCount, 0)
        XCTAssertFalse(state.isBulkActionEnabled)
        for factoryState in factoryStates {
            XCTAssertEqual(factoryState.selectedTabIDs, [])
            XCTAssertNil(factoryState.selectionAnchorID)
            XCTAssertEqual(factoryState.selectedTabCount, 0)
            XCTAssertFalse(factoryState.isBulkActionEnabled)
        }

        state.selectedTabIDs = [ContentTabID(), ContentTabID()]

        XCTAssertEqual(state.selectedTabCount, 2)
        XCTAssertTrue(state.isBulkActionEnabled)
    }

    /// CTM-001-select_content_tabs: interleaved raw tabs의 selection 전용 pinned-first ordering 검증
    /// - 검증 내용: pinned 상대 순서 뒤 unpinned 상대 순서를 반환하면서 raw tabs를 변경하지 않음
    /// - 사전 조건: raw 순서가 U1, P1, U2, P2, U3인 다섯 탭
    /// - 기대 결과: selection 순서는 P1, P2, U1, U2, U3이고 tabs는 입력 순서와 동일함
    func testSelectionOrdering_interleavedTabsReturnsPinnedFirstWithoutMutatingRawTabs() {
        let unpinned1 = ContentTabID(rawValue: "U1")
        let pinned1 = ContentTabID(rawValue: "P1")
        let unpinned2 = ContentTabID(rawValue: "U2")
        let pinned2 = ContentTabID(rawValue: "P2")
        let unpinned3 = ContentTabID(rawValue: "U3")
        let rawTabs: IdentifiedArrayOf<ContentTabItem> = [
            tab(id: unpinned1, isPinned: false),
            tab(id: pinned1, isPinned: true),
            tab(id: unpinned2, isPinned: false),
            tab(id: pinned2, isPinned: true),
            tab(id: unpinned3, isPinned: false),
        ]
        let state = ContentTabState(tabs: rawTabs, activeTabID: unpinned1)

        XCTAssertEqual(state.selectionOrderedTabIDs, [pinned1, pinned2, unpinned1, unpinned2, unpinned3])
        XCTAssertEqual(state.tabs, rawTabs)
        XCTAssertEqual(Array(state.tabs.ids), [unpinned1, pinned1, unpinned2, pinned2, unpinned3])
    }

    /// CTM-001-select_content_tabs: stale selected ID와 stale anchor reconciliation 및 상태 격리 검증
    /// - 검증 내용: 현재 identity와 selected IDs를 교집합하고 stale anchor만 제거하며 비선택 상태를 보존함
    /// - 사전 조건: A/B는 현재 탭, X는 stale이며 selected가 A/X이고 anchor가 X인 metadata 포함 상태
    /// - 기대 결과: A 선택은 생존하고 X 선택/anchor만 제거되며 active/previous/tabs/pinned/recent/runtime metadata는 동일함
    func testReconcileSelection_removesStaleSelectionAndAnchorWithoutChangingOtherState() {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let staleTab = ContentTabID(rawValue: "X")
        let pinnedAt = Date(timeIntervalSince1970: 451)
        let recentlyClosed = ClosedContentTabSnapshot(
            page: .directory,
            anchor: .directory(path: "/closed"),
            wasPinned: false,
            closedAt: pinnedAt,
            title: "Closed",
            iconName: "folder",
        )
        let pinnedRecord = ContentTabPinnedRecord(
            id: tabB.rawValue,
            page: .directory,
            anchor: .directory(path: "/B"),
            title: "B",
            iconName: "folder",
            pinnedAt: pinnedAt,
        )
        var state = ContentTabState(
            tabs: [tab(id: tabA, isPinned: false), tab(id: tabB, isPinned: true)],
            activeTabID: tabB,
            previousActiveTabID: tabA,
            recentlyClosed: recentlyClosed,
            pinnedRecords: [tabB: pinnedRecord],
            pendingPinnedRecordIDs: [tabB],
            pinnedRecordPersistenceError: "sentinel",
        )
        state.selectedTabIDs = [tabA, staleTab]
        state.selectionAnchorID = staleTab
        let tabsBefore = state.tabs
        let activeBefore = state.activeTabID
        let previousBefore = state.previousActiveTabID
        let recentlyClosedBefore = state.recentlyClosed
        let pinnedRecordsBefore = state.pinnedRecords
        let pendingPinnedRecordIDsBefore = state.pendingPinnedRecordIDs
        let persistenceErrorBefore = state.pinnedRecordPersistenceError

        state.reconcileSelection()

        XCTAssertEqual(state.selectedTabIDs, [tabA])
        XCTAssertNil(state.selectionAnchorID)
        XCTAssertEqual(state.tabs, tabsBefore)
        XCTAssertEqual(state.activeTabID, activeBefore)
        XCTAssertEqual(state.previousActiveTabID, previousBefore)
        XCTAssertEqual(state.recentlyClosed, recentlyClosedBefore)
        XCTAssertEqual(state.pinnedRecords, pinnedRecordsBefore)
        XCTAssertEqual(state.pendingPinnedRecordIDs, pendingPinnedRecordIDsBefore)
        XCTAssertEqual(state.pinnedRecordPersistenceError, persistenceErrorBefore)
    }

    /// CTM-001-select_content_tabs: 선택 집합에 없는 유효 anchor의 reconciliation 보존 검증
    /// - 검증 내용: anchor identity가 현재 tabs에 존재하면 selected membership과 무관하게 유지함
    /// - 사전 조건: 현재 A/B 탭, selected는 A 하나이고 anchor는 선택되지 않은 B
    /// - 기대 결과: reconcile 후 selected A와 valid-unselected anchor B가 모두 유지됨
    func testReconcileSelection_preservesValidUnselectedAnchor() {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        var state = ContentTabState(
            tabs: [tab(id: tabA, isPinned: false), tab(id: tabB, isPinned: false)],
            activeTabID: tabA,
        )
        state.selectedTabIDs = [tabA]
        state.selectionAnchorID = tabB

        state.reconcileSelection()

        XCTAssertEqual(state.selectedTabIDs, [tabA])
        XCTAssertEqual(state.selectionAnchorID, tabB)
    }

    /// CTM-001-select_content_tabs: toggle add/remove와 deselection anchor 정책 검증
    /// - 검증 내용: 유효 target membership을 두 번 반전하고 두 경우 모두 target을 anchor로 설정함
    /// - 사전 조건: A/B 탭과 B active, A는 최초 미선택 상태
    /// - 기대 결과: 첫 toggle은 A를 추가하고 두 번째는 제거하지만 anchor A와 비선택 상태는 보존함
    func testToggleSelection_addsAndRemovesMembershipWhileAlwaysAnchoringTarget() async {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let store = TestStore(initialState: ContentTabState(
            tabs: [tab(id: tabA, isPinned: false), tab(id: tabB, isPinned: true)],
            activeTabID: tabB,
            previousActiveTabID: tabA,
        )) {
            ContentTabFeature()
        }

        await store.send(.toggleSelection(tabA)) {
            $0.selectedTabIDs = [tabA]
            $0.selectionAnchorID = tabA
        }
        await store.send(.toggleSelection(tabA)) {
            $0.selectedTabIDs = []
        }

        XCTAssertEqual(store.state.selectionAnchorID, tabA)
        XCTAssertEqual(store.state.activeTabID, tabB)
        XCTAssertEqual(store.state.previousActiveTabID, tabA)
    }

    /// CTM-001-select_content_tabs: clear와 already-empty idempotency 검증
    /// - 검증 내용: selected set/anchor만 비운 뒤 같은 clear를 다시 보내 whole-state no-op인지 확인함
    /// - 사전 조건: A/B가 선택되고 anchor B이며 active/previous identity가 설정된 상태
    /// - 기대 결과: 첫 clear 뒤 selection runtime state만 비고 두 번째 clear 전후 전체 상태가 동일함
    func testClearSelection_clearsOnlySelectionAndIsIdempotentWhenAlreadyEmpty() async {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        var state = ContentTabState(
            tabs: [tab(id: tabA, isPinned: false), tab(id: tabB, isPinned: true)],
            activeTabID: tabA,
            previousActiveTabID: tabB,
        )
        state.selectedTabIDs = [tabA, tabB]
        state.selectionAnchorID = tabB
        let store = TestStore(initialState: state) { ContentTabFeature() }

        await store.send(.clearSelection) {
            $0.selectedTabIDs = []
            $0.selectionAnchorID = nil
        }
        let emptyState = store.state
        await store.send(.clearSelection)

        XCTAssertEqual(store.state, emptyState)
    }

    /// CTM-001-select_content_tabs: forward/reverse/cross-divider range의 inclusive replace 검증
    /// - 검증 내용: pinned-first 순서에서 양방향 interval이 prior disjoint selection을 union하지 않고 교체함
    /// - 사전 조건: raw U1/P1/U2/P2/U3, anchor P1과 disjoint U3 selection
    /// - 기대 결과: U2 forward는 P1/P2/U1/U2, U3 anchor의 P2 reverse는 P2/U1/U2/U3만 선택함
    func testSelectRange_forwardReverseAndCrossDividerReplacePriorSelection() async {
        let unpinned1 = ContentTabID(rawValue: "U1")
        let pinned1 = ContentTabID(rawValue: "P1")
        let unpinned2 = ContentTabID(rawValue: "U2")
        let pinned2 = ContentTabID(rawValue: "P2")
        let unpinned3 = ContentTabID(rawValue: "U3")
        var state = ContentTabState(
            tabs: [
                tab(id: unpinned1, isPinned: false),
                tab(id: pinned1, isPinned: true),
                tab(id: unpinned2, isPinned: false),
                tab(id: pinned2, isPinned: true),
                tab(id: unpinned3, isPinned: false),
            ],
            activeTabID: unpinned1,
        )
        state.selectedTabIDs = [unpinned3]
        state.selectionAnchorID = pinned1
        let store = TestStore(initialState: state) { ContentTabFeature() }

        await store.send(.selectRange(to: unpinned2)) {
            $0.selectedTabIDs = [pinned1, pinned2, unpinned1, unpinned2]
        }
        await store.send(.toggleSelection(unpinned3)) {
            $0.selectedTabIDs.insert(unpinned3)
            $0.selectionAnchorID = unpinned3
        }
        await store.send(.selectRange(to: pinned2)) {
            $0.selectedTabIDs = [pinned2, unpinned1, unpinned2, unpinned3]
        }

        XCTAssertEqual(store.state.selectionAnchorID, unpinned3)
        XCTAssertFalse(store.state.selectedTabIDs.contains(pinned1))
    }

    /// CTM-001-select_content_tabs: nil/stale anchor의 target-only fallback 검증
    /// - 검증 내용: anchor를 ordering에서 찾을 수 없으면 기존 selection을 target 하나로 교체하고 anchor를 갱신함
    /// - 사전 조건: A/B 현재 탭과 stale X, nil anchor state 및 stale anchor state
    /// - 기대 결과: 두 state 모두 B 하나만 선택하고 anchor B로 수렴함
    func testSelectRange_nilOrStaleAnchorFallsBackToTargetOnlySelection() async {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let staleTab = ContentTabID(rawValue: "X")
        let tabs: IdentifiedArrayOf<ContentTabItem> = [
            tab(id: tabA, isPinned: false),
            tab(id: tabB, isPinned: true),
        ]
        var nilAnchorState = ContentTabState(tabs: tabs, activeTabID: tabA)
        nilAnchorState.selectedTabIDs = [tabA]
        let nilAnchorStore = TestStore(initialState: nilAnchorState) { ContentTabFeature() }

        await nilAnchorStore.send(.selectRange(to: tabB)) {
            $0.selectedTabIDs = [tabB]
            $0.selectionAnchorID = tabB
        }

        var staleAnchorState = ContentTabState(tabs: tabs, activeTabID: tabA)
        staleAnchorState.selectedTabIDs = [tabA]
        staleAnchorState.selectionAnchorID = staleTab
        let staleAnchorStore = TestStore(initialState: staleAnchorState) { ContentTabFeature() }

        await staleAnchorStore.send(.selectRange(to: tabB)) {
            $0.selectedTabIDs = [tabB]
            $0.selectionAnchorID = tabB
        }
    }

    /// CTM-001-select_content_tabs: valid-unselected anchor 기반 range 검증
    /// - 검증 내용: toggle deselection으로 selected set에서 빠진 유효 anchor도 range 시작점으로 사용함
    /// - 사전 조건: U1/U2/U3 중 U1 selected이며 toggle로 deselect 예정
    /// - 기대 결과: anchor U1은 유지되고 U3 range가 U1/U2/U3 interval을 선택함
    func testSelectRange_usesValidAnchorEvenWhenAnchorIsNotSelected() async {
        let tab1 = ContentTabID(rawValue: "U1")
        let tab2 = ContentTabID(rawValue: "U2")
        let tab3 = ContentTabID(rawValue: "U3")
        var state = ContentTabState(
            tabs: [
                tab(id: tab1, isPinned: false),
                tab(id: tab2, isPinned: false),
                tab(id: tab3, isPinned: false),
            ],
            activeTabID: tab2,
        )
        state.selectedTabIDs = [tab1]
        let store = TestStore(initialState: state) { ContentTabFeature() }

        await store.send(.toggleSelection(tab1)) {
            $0.selectedTabIDs = []
            $0.selectionAnchorID = tab1
        }
        await store.send(.selectRange(to: tab3)) {
            $0.selectedTabIDs = [tab1, tab2, tab3]
        }

        XCTAssertEqual(store.state.selectionAnchorID, tab1)
    }

    /// CTM-001-select_content_tabs: reorder 직후 range가 갱신된 pinned-first 표시 순서를 사용함
    /// - 검증 내용: reorder가 selection/anchor를 보존하고 이어진 range가 새 unpinned 상대 순서의 interval을 선택함
    /// - 사전 조건: raw U1/P1/U2/P2/U3, anchor U3에서 U3를 U1 앞으로 reorder
    /// - 기대 결과: 새 표시 순서 P1/P2/U3/U1/U2 기준 U3...U2인 U3/U1/U2만 선택됨
    func testReorderThenSelectRange_usesUpdatedPinnedFirstDisplayedOrder() async {
        let unpinned1 = ContentTabID(rawValue: "U1")
        let pinned1 = ContentTabID(rawValue: "P1")
        let unpinned2 = ContentTabID(rawValue: "U2")
        let pinned2 = ContentTabID(rawValue: "P2")
        let unpinned3 = ContentTabID(rawValue: "U3")
        var state = ContentTabState(
            tabs: [
                tab(id: unpinned1, isPinned: false),
                tab(id: pinned1, isPinned: true),
                tab(id: unpinned2, isPinned: false),
                tab(id: pinned2, isPinned: true),
                tab(id: unpinned3, isPinned: false),
            ],
            activeTabID: unpinned2,
            previousActiveTabID: unpinned1,
        )
        state.selectedTabIDs = [unpinned3]
        state.selectionAnchorID = unpinned3
        let store = TestStore(initialState: state) { ContentTabFeature() }

        await store.send(.reorder(sourceID: unpinned3, targetID: unpinned1, placement: .before)) {
            $0.tabs = [
                self.tab(id: unpinned3, isPinned: false),
                self.tab(id: pinned1, isPinned: true),
                self.tab(id: unpinned1, isPinned: false),
                self.tab(id: pinned2, isPinned: true),
                self.tab(id: unpinned2, isPinned: false),
            ]
        }
        XCTAssertEqual(store.state.selectionOrderedTabIDs, [pinned1, pinned2, unpinned3, unpinned1, unpinned2])
        XCTAssertEqual(store.state.selectedTabIDs, [unpinned3])
        XCTAssertEqual(store.state.selectionAnchorID, unpinned3)

        await store.send(.selectRange(to: unpinned2)) {
            $0.selectedTabIDs = [unpinned3, unpinned1, unpinned2]
        }

        XCTAssertEqual(store.state.activeTabID, unpinned2)
        XCTAssertEqual(store.state.previousActiveTabID, unpinned1)
        XCTAssertEqual(store.state.selectionAnchorID, unpinned3)
    }

    /// CTM-001-select_content_tabs: invalid toggle/range의 whole ContentTabState no-op 검증
    /// - 검증 내용: 존재하지 않는 target을 identity validation에서 거부하고 reconciliation도 실행하지 않음
    /// - 사전 조건: A/B 현재 탭, stale X가 selected와 anchor에 남은 상태, invalid Z target
    /// - 기대 결과: invalid toggle과 range 각각 전후 전체 상태가 byte-semantic equality를 유지함
    func testInvalidToggleAndRange_leaveWholeContentTabStateUnchanged() async {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let staleTab = ContentTabID(rawValue: "X")
        let invalidTab = ContentTabID(rawValue: "Z")
        var state = ContentTabState(
            tabs: [tab(id: tabA, isPinned: false), tab(id: tabB, isPinned: true)],
            activeTabID: tabB,
            previousActiveTabID: tabA,
        )
        state.selectedTabIDs = [tabA, staleTab]
        state.selectionAnchorID = staleTab
        let store = TestStore(initialState: state) { ContentTabFeature() }

        await store.send(.toggleSelection(invalidTab))
        XCTAssertEqual(store.state, state)
        await store.send(.selectRange(to: invalidTab))
        XCTAssertEqual(store.state, state)
    }

    /// CTM-001-select_content_tabs: Window post-reduce selection action 격리 검증
    /// - 검증 내용: valid selection은 child selection만 변경하고 pending/Sidebar/Home projection sentinel을 보존함
    /// - 사전 조건: 서로 어긋난 source/cached projection과 stale pending ID를 가진 FileManagerFeature state
    /// - 기대 결과: valid toggle은 selection만 변경하고 invalid toggle/range는 whole Window state no-op임
    func testWindowSelectionActions_preserveProjectionSentinelsAndInvalidActionsAreWholeStateNoOps() async {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let invalidTab = ContentTabID(rawValue: "invalid")
        let stalePendingTab = ContentTabID(rawValue: "stale-pending")
        let state = makeWindowSelectionSentinelState(
            tabA: tabA,
            tabB: tabB,
            stalePendingTab: stalePendingTab,
        )
        let pendingSentinel = state.pendingDirectoryReloadTabIDs
        let sidebarProjectionSentinel = state.sidebar.contentTabSidebarItems
        let homeLocationSentinel = state.content.homeLocationItems
        let homeFavoriteSentinel = state.content.homeFavoriteItems
        let store = TestStore(initialState: state) { FileManagerFeature() }

        await store.send(.contentTabs(.toggleSelection(tabB))) {
            $0.contentTabs.selectedTabIDs = [tabB]
            $0.contentTabs.selectionAnchorID = tabB
        }

        XCTAssertEqual(store.state.pendingDirectoryReloadTabIDs, pendingSentinel)
        XCTAssertEqual(store.state.sidebar.contentTabSidebarItems, sidebarProjectionSentinel)
        XCTAssertEqual(store.state.content.homeLocationItems, homeLocationSentinel)
        XCTAssertEqual(store.state.content.homeFavoriteItems, homeFavoriteSentinel)

        let validSelectionState = store.state
        await store.send(.contentTabs(.toggleSelection(invalidTab)))
        XCTAssertEqual(store.state, validSelectionState)
        await store.send(.contentTabs(.selectRange(to: invalidTab)))
        XCTAssertEqual(store.state, validSelectionState)
    }

    private func makeWindowSelectionSentinelState(
        tabA: ContentTabID,
        tabB: ContentTabID,
        stalePendingTab: ContentTabID,
    ) -> FileManagerFeature.State {
        let sourceLocation = FileManagerFixedLocationItem(
            id: "source-location",
            title: "Source Location",
            path: "/source/location",
            iconName: "folder",
            accessibilityLabel: "Source Location",
        )
        let preservedLocation = FileManagerFixedLocationItem(
            id: "preserved-location",
            title: "Preserved Location",
            path: "/preserved/location",
            iconName: "folder",
            accessibilityLabel: "Preserved Location",
        )
        let sourceFavorite = FileManagerHomeFavoriteItem(
            id: ContentTabID(rawValue: "source-favorite"),
            title: "Source Favorite",
            iconName: "folder",
            filePath: "/source/favorite",
            anchor: .directory(path: "/source/favorite"),
            page: .directory,
        )
        let preservedFavorite = FileManagerHomeFavoriteItem(
            id: ContentTabID(rawValue: "preserved-favorite"),
            title: "Preserved Favorite",
            iconName: "folder",
            filePath: "/preserved/favorite",
            anchor: .directory(path: "/preserved/favorite"),
            page: .directory,
        )
        let sidebarSentinel = Self.sidebarSentinel()
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [tab(id: tabA, isPinned: false), tab(id: tabB, isPinned: true)],
            activeTabID: tabA,
            previousActiveTabID: tabB,
        )
        state.pendingDirectoryReloadTabIDs = [tabB, stalePendingTab]
        state.applyFixedLocationItems([sourceLocation])
        state.content.homeLocationItems = [preservedLocation]
        state.applyHomeFavoriteItems([sourceFavorite])
        state.content.homeFavoriteItems = [preservedFavorite]
        state.sidebar.contentTabSidebarItems = [sidebarSentinel]
        return state
    }

    private static func sidebarSentinel() -> ContentTabProjection.ContentTabSidebarItem {
        ContentTabProjection.ContentTabSidebarItem(
            id: ContentTabID(rawValue: "sidebar-sentinel"),
            title: "Sidebar Sentinel",
            iconName: "star",
            targetURL: nil,
            tagColorCode: 451,
            pageType: .home,
            isActive: false,
            isPinned: true,
        )
    }

    private func tab(id: ContentTabID, isPinned: Bool) -> ContentTabItem {
        ContentTabItem(
            id: id,
            page: .directory,
            anchor: .directory(path: "/\(id.rawValue)"),
            isPinned: isPinned,
            title: id.rawValue,
            iconName: "folder",
        )
    }
}
