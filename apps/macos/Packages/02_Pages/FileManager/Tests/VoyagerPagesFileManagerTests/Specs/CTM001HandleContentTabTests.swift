import ComposableArchitecture
import Foundation
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
final class CTM001HandleContentTabTests: XCTestCase {
    // MARK: - CTM-001-open_new_content_tab

    /// CTM-001-open_new_content_tab: 빈 상태와 FileManager window 초기 상태는 Home Content Tab을 활성화함
    /// 기능스펙의 새 Content Tab 기본 진입점이 `home_default` Page work unit인지 검증한다.
    /// - 검증 내용: 빈 CTM 상태에서 Home open, FileManagerWindowState 기본 Home tab, FileManagerFeature scope routing
    /// - 사전 조건: 빈 `ContentTabState`, 기본 `FileManagerWindowState`, 기본 `FileManagerFeature.State`
    /// - 기대 결과: Home tab이 생성되어 active가 되고 FileManager scope를 통해 Directory tab도 열 수 있음
    func testOpenNewContentTab_startsFromHomeAndRoutesThroughFileManagerScope() async throws {
        var state = ContentTabState(tabs: [], activeTabID: nil, recentlyClosed: nil)
        let reducer = ContentTabFeature()

        _ = reducer.reduce(into: &state, action: .open(.homeDefault))

        let openedHomeTab = try XCTUnwrap(state.tabs.first)
        XCTAssertEqual(state.tabs.count, 1)
        XCTAssertEqual(state.activeTabID, openedHomeTab.id)
        XCTAssertEqual(openedHomeTab.page, .home)
        XCTAssertEqual(openedHomeTab.anchor, .homeDefault)
        XCTAssertFalse(openedHomeTab.isPinned)

        let windowState = FileManagerWindowState()
        let initialHomeTab = try XCTUnwrap(windowState.contentTabs.tabs.first)
        XCTAssertEqual(windowState.contentTabs.tabs.count, 1)
        XCTAssertEqual(windowState.contentTabs.activeTabID, initialHomeTab.id)
        XCTAssertEqual(initialHomeTab.page, .home)
        XCTAssertEqual(initialHomeTab.anchor, .homeDefault)

        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action을 방출하므로
        // exhaustivity = .off로 전환 검증에 집중한다.
        store.exhaustivity = .off

        let initialCount = store.state.contentTabs.tabs.count
        await store.send(.contentTabs(.open(.directory(path: "/test"))))
        XCTAssertEqual(store.state.contentTabs.tabs.count, initialCount + 1)
        XCTAssertEqual(store.state.contentTabs.tabs.last?.page, .directory)
        XCTAssertEqual(store.state.contentTabs.activeTabID, store.state.contentTabs.tabs.last?.id)
    }

    /// CTM-001-open_new_content_tab: `FileManagerWindowState.makeInitial(path:)`가 정확히 하나의 활성 Home tab을 생성함
    /// AC1과 AC2의 makeInitial(path: nil) 진입점을 검증한다.
    /// - 검증 내용: makeInitial(path: nil) 결과 contentTabs.tabs.count == 1, activeTabID != nil, anchor == .homeDefault, page
    /// == .home
    /// - 사전 조건: FileManagerWindowState.makeInitial(path: nil)
    /// - 기대 결과: 정확히 하나의 Home tab이 active 상태로 생성됨
    func testOpenNewContentTab_bootstrapFromMakeInitial_hasExactlyOneActiveHomeTab() {
        let state = FileManagerWindowState.makeInitial(path: nil)

        XCTAssertEqual(state.contentTabs.tabs.count, 1)
        XCTAssertNotNil(state.contentTabs.activeTabID)
        XCTAssertEqual(state.contentTabs.tabs.first?.anchor, .homeDefault)
        XCTAssertEqual(state.contentTabs.tabs.first?.page, .home)
    }

    /// CTM-001-open_new_content_tab: path seed가 ContentTab anchor를 변경하지 않고 Home anchor를 유지함
    /// AC3의 path seed가 anchor를 override하지 않는 정책을 검증한다.
    /// - 검증 내용: path seed("/tmp")에서도 contentTabs.tabs.first?.anchor == .homeDefault, contentTabs.tabs.count == 1
    /// - 사전 조건: FileManagerWindowState.makeInitial(path: "/tmp")
    /// - 기대 결과: path seed와 무관하게 Home anchor와 단일 tab이 유지됨
    func testOpenNewContentTab_pathSeed_keepsHomeAnchorNotDefaultTabPath() {
        let state = FileManagerWindowState.makeInitial(path: "/tmp")

        XCTAssertEqual(state.contentTabs.tabs.first?.anchor, .homeDefault)
        XCTAssertEqual(state.contentTabs.tabs.count, 1)
    }

    /// CTM-001-open_new_content_tab: path seed가 navigation currentPath를 설정함
    /// path 기반 FileManager window 생성이 기존 navigation seed 동작을 유지하는지 검증한다.
    /// - 검증 내용: makeInitial(path: "/tmp") 결과 content.navigation.currentPath가 존재함
    /// - 사전 조건: FileManagerWindowState.makeInitial(path: "/tmp")
    /// - 기대 결과: ContentTab anchor는 Home 정책을 유지하면서 navigation seed가 적용됨
    func testOpenNewContentTab_pathSeed_appliesNavigationSeed() {
        let state = FileManagerWindowState.makeInitial(path: "/tmp")

        XCTAssertNotNil(state.content.navigation.currentPath)
    }

    /// CTM-001-open_new_content_tab: makeInitial restored state는 Home tab을 중복 추가하지 않음
    /// 복원된 ContentTabState가 주어질 때 새 window bootstrap seam이 복원 상태를 우선하는지 검증한다.
    /// - 검증 내용: Directory tab 복원 상태를 makeInitial(path:contentTabs:)에 전달하면 count == 1, directory anchor 유지, activeTabID
    /// 존재
    /// - 사전 조건: Directory tab 하나를 가진 restored ContentTabState
    /// - 기대 결과: Home tab 추가 없이 restored tab이 유지되고 active id가 설정됨
    func testOpenNewContentTab_makeInitialWithRestoredState_usesRestoredTabsNoDuplicateHome() {
        let restoredID = ContentTabID()
        let restoredState = ContentTabState(
            tabs: [ContentTabItem(
                id: restoredID,
                page: .directory,
                anchor: .directory(path: "/restored"),
                isPinned: false,
                title: nil,
                iconName: nil,
            )],
            activeTabID: restoredID,
            recentlyClosed: nil,
        )

        let state = FileManagerWindowState.makeInitial(path: nil, contentTabs: restoredState)

        XCTAssertEqual(state.contentTabs.tabs.count, 1)
        XCTAssertEqual(state.contentTabs.tabs.first?.anchor, .directory(path: "/restored"))
        XCTAssertNotNil(state.contentTabs.activeTabID)
    }

    /// CTM-001-open_new_content_tab: makeInitial empty restored state는 Home tab으로 fallback함
    /// 빈 ContentTabState가 주어질 때 새 window bootstrap seam이 Home fallback invariant를 유지하는지 검증한다.
    /// - 검증 내용: 빈 state를 makeInitial(path:contentTabs:)에 전달하면 Home tab 1개와 activeTabID가 생성됨
    /// - 사전 조건: tabs == [], activeTabID == nil인 ContentTabState
    /// - 기대 결과: active Home .homeDefault ContentTab 하나로 fallback됨
    func testOpenNewContentTab_makeInitialWithEmptyState_fallsBackToHomeTab() {
        let state = FileManagerWindowState.makeInitial(
            path: nil,
            contentTabs: ContentTabState(tabs: [], activeTabID: nil, recentlyClosed: nil),
        )

        XCTAssertEqual(state.contentTabs.tabs.count, 1)
        XCTAssertEqual(state.contentTabs.tabs.first?.anchor, .homeDefault)
        XCTAssertNotNil(state.contentTabs.activeTabID)
    }

    /// CTM-001-open_new_content_tab: restored bootstrap의 invalid active id는 첫 tab을 active로 사용함
    /// 복원된 tab 목록이 있으나 activeTabID가 nil 또는 유효하지 않을 때 fallback active 선택을 검증한다.
    /// - 검증 내용: non-empty restoredTabs에서 Home 추가 없이 첫 tab id가 activeTabID가 됨
    /// - 사전 조건: Directory tab과 Collection tab 복원 목록, invalid activeTabID 또는 nil activeTabID
    /// - 기대 결과: tabs count는 유지되고 첫 restored tab이 active 상태가 됨
    func testOpenNewContentTab_restoredBootstrap_invalidActiveIdUsesFirstTab() {
        let firstID = ContentTabID()
        let secondID = ContentTabID()
        let directoryTab = ContentTabItem(
            id: firstID,
            page: .directory,
            anchor: .directory(path: "/first"),
            isPinned: false,
            title: nil,
            iconName: nil,
        )
        let collectionTab = ContentTabItem(
            id: secondID,
            page: .collection,
            anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/restored.voycoll")),
            isPinned: false,
            title: nil,
            iconName: nil,
        )

        let invalidActiveState = ContentTabState.bootstrapping(
            restoredTabs: [directoryTab, collectionTab],
            activeTabID: ContentTabID(),
        )

        XCTAssertEqual(invalidActiveState.tabs.count, 2)
        XCTAssertEqual(invalidActiveState.activeTabID, firstID)

        let nilActiveState = ContentTabState.bootstrapping(
            restoredTabs: [directoryTab],
            activeTabID: nil,
        )

        XCTAssertEqual(nilActiveState.activeTabID, firstID)
    }

    /// CTM-001-open_new_content_tab: bootstrapping으로 복원된 tab list에 중복 Home tab이 추가되지 않음
    /// AC4의 restored bootstrap이 중복 Home을 방지하는 정책을 검증한다.
    /// - 검증 내용: Directory tab 복원 시 count == 1, anchor == .directory(path: "/restored"), activeTabID == restored tab id;
    /// 빈 목록 시 count == 1, .homeDefault fallback
    /// - 사전 조건: ContentTabState.bootstrapping(restoredTabs:activeTabID:)로 복원된 상태와 빈 상태
    /// - 기대 결과: Non-empty 복원은 그대로 사용되고 empty는 Home fallback을 생성함
    func testOpenNewContentTab_restoredBootstrap_doesNotAppendDuplicateHomeTab() {
        let restoredID = ContentTabID()
        let restoredTabs: IdentifiedArrayOf<ContentTabItem> = [ContentTabItem(
            id: restoredID,
            page: .directory,
            anchor: .directory(path: "/restored"),
            isPinned: false,
            title: nil,
            iconName: nil,
        )]

        let nonEmptyState = ContentTabState.bootstrapping(
            restoredTabs: restoredTabs,
            activeTabID: restoredID,
        )

        XCTAssertEqual(nonEmptyState.tabs.count, 1)
        XCTAssertEqual(nonEmptyState.tabs.first?.anchor, .directory(path: "/restored"))
        XCTAssertEqual(nonEmptyState.activeTabID, restoredID)

        let emptyState = ContentTabState.bootstrapping(restoredTabs: [], activeTabID: nil)

        XCTAssertEqual(emptyState.tabs.count, 1)
        XCTAssertEqual(emptyState.tabs.first?.anchor, .homeDefault)
        XCTAssertNotNil(emptyState.activeTabID)
    }

    // MARK: - CTM-001-close_content_tab

    /// CTM-001-close_content_tab: 일반 close는 restore snapshot을 남기고 마지막 탭 close는 Window handoff 상태로 비워둠
    /// 기능스펙의 surface close 정책과 window lifecycle handoff 경계를 함께 검증한다.
    /// - 검증 내용: unpinned close snapshot 저장, active fallback, 마지막 active close의 빈 tab list 전이
    /// - 사전 조건: Home+Directory 두 탭 상태와 Directory 단일 active 상태
    /// - 기대 결과: 닫힌 탭은 snapshot으로 보존되고 마지막 탭 close는 replacement Home을 만들지 않음
    func testCloseContentTab_savesRestoreSnapshotAndLeavesLastCloseForWindowHandoff() throws {
        let homeID = ContentTabID()
        let directoryID = ContentTabID()
        let directoryAnchor = ContentTabPageAnchor.directory(path: "/test1")
        var state = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
                ContentTabItem(
                    id: directoryID,
                    page: .directory,
                    anchor: directoryAnchor,
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
            ],
            activeTabID: homeID,
            recentlyClosed: nil,
        )
        let reducer = ContentTabFeature()

        _ = reducer.reduce(into: &state, action: .close(directoryID))

        XCTAssertEqual(state.tabs.count, 1)
        XCTAssertEqual(state.tabs[0].id, homeID)
        XCTAssertEqual(state.activeTabID, homeID)
        XCTAssertEqual(state.recentlyClosed?.page, .directory)
        XCTAssertEqual(state.recentlyClosed?.anchor, directoryAnchor)
        XCTAssertFalse(try XCTUnwrap(state.recentlyClosed?.wasPinned))
        XCTAssertNotNil(state.recentlyClosed?.closedAt)

        let lastID = ContentTabID()
        var lastTabState = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: lastID,
                    page: .directory,
                    anchor: directoryAnchor,
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
            ],
            activeTabID: lastID,
            recentlyClosed: nil,
        )

        _ = reducer.reduce(into: &lastTabState, action: .close(lastID))

        XCTAssertTrue(lastTabState.tabs.isEmpty)
        XCTAssertNil(lastTabState.activeTabID)
        XCTAssertEqual(lastTabState.recentlyClosed?.page, .directory)
        XCTAssertEqual(lastTabState.recentlyClosed?.anchor, directoryAnchor)
    }

    // MARK: - CTM-001-restore_last_closed_tab

    /// CTM-001-restore_last_closed_tab: 단일 recently closed snapshot을 fresh identity로 복원함
    /// 기능스펙의 Restore Last Closed가 lightweight snapshot 후보 하나만 소비하는지 검증한다.
    /// - 검증 내용: restore 후 새 tab ID 생성, page/anchor 복원, recentlyClosed 초기화, 재호출 no-op
    /// - 사전 조건: Home tab 하나와 Directory recentlyClosed snapshot 하나
    /// - 기대 결과: Directory tab이 새 identity로 active 복원되고 후보는 비워짐
    func testRestoreLastClosedTab_consumesSingleSnapshotWithFreshIdentity() throws {
        let homeID = ContentTabID()
        let directoryAnchor = ContentTabPageAnchor.directory(path: "/test1")
        let closedSnapshot = ClosedContentTabSnapshot(
            page: .directory,
            anchor: directoryAnchor,
            wasPinned: false,
            closedAt: Date(),
        )
        var state = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
            ],
            activeTabID: homeID,
            recentlyClosed: closedSnapshot,
        )
        let reducer = ContentTabFeature()

        _ = reducer.reduce(into: &state, action: .restore)

        XCTAssertEqual(state.tabs.count, 2)
        XCTAssertNil(state.recentlyClosed)
        XCTAssertEqual(state.activeTabID, state.tabs.last?.id)
        XCTAssertNotEqual(state.tabs.last?.id, homeID)
        XCTAssertEqual(state.tabs.last?.page, .directory)
        XCTAssertEqual(state.tabs.last?.anchor, directoryAnchor)
        XCTAssertFalse(try XCTUnwrap(state.tabs.last?.isPinned))

        _ = reducer.reduce(into: &state, action: .restore)
        XCTAssertEqual(state.tabs.count, 2)
        XCTAssertNil(state.recentlyClosed)
    }

    // MARK: - CTM-001-pin_content_tab_s

    /// CTM-001-pin_content_tab_s: pinned tab close는 제거가 아니라 unpin transition임
    /// 기능스펙과 lifecycle contract의 `pinned_tab_close_means_unpin` 정책을 검증한다.
    /// - 검증 내용: close(pinnedID) 후 tab 유지, isPinned=false, recentlyClosed 미생성
    /// - 사전 조건: active pinned Home tab 하나
    /// - 기대 결과: 탭은 남고 pinned 상태만 해제됨
    func testPinContentTabs_pinnedCloseOnlyUnpins() async {
        let pinnedID = ContentTabID()
        let store = TestStore(
            initialState: ContentTabState(
                tabs: [
                    ContentTabItem(
                        id: pinnedID,
                        page: .home,
                        anchor: .homeDefault,
                        isPinned: true,
                        title: nil,
                        iconName: nil,
                    ),
                ],
                activeTabID: pinnedID,
                recentlyClosed: nil,
            ),
        ) {
            ContentTabFeature()
        }

        await store.send(.close(pinnedID)) {
            $0.tabs[id: pinnedID]?.isPinned = false
        }
        await store.finish()
    }

    // MARK: - CTM-001-handle_content_tab_invariants

    /// CTM-001-handle_content_tab_invariants: invalid id와 max tab limit은 상태 invariant를 깨지 않는 no-op임
    /// 기능스펙의 invalid tab id 보존 요구와 Phase 1 max tab guardrail을 검증한다.
    /// - 검증 내용: unknown id actions no-op, maxTabs 도달 후 open/restore no-op
    /// - 사전 조건: active Home tab 하나, 또는 maxTabs만큼 채워진 tab list
    /// - 기대 결과: activeTabID와 tabs list가 기존 invariant를 유지함
    func testHandleContentTabInvariants_invalidIDAndMaxLimitAreNoOps() async {
        let activeID = ContentTabID()
        let invalidID = ContentTabID()
        let store = TestStore(
            initialState: ContentTabState(
                tabs: [
                    ContentTabItem(
                        id: activeID,
                        page: .home,
                        anchor: .homeDefault,
                        isPinned: false,
                        title: nil,
                        iconName: nil,
                    ),
                ],
                activeTabID: activeID,
                recentlyClosed: nil,
            ),
        ) {
            ContentTabFeature()
        }

        await store.send(.setCurrent(invalidID))
        await store.send(.close(invalidID))
        await store.send(.pin(invalidID))
        await store.finish()

        var tabs = IdentifiedArrayOf<ContentTabItem>()
        for _ in 0 ..< ContentTabConstants.maxTabs {
            tabs.append(ContentTabItem(
                id: ContentTabID(),
                page: .home,
                anchor: .homeDefault,
                isPinned: false,
                title: nil,
                iconName: nil,
            ))
        }
        let firstID = tabs[0].id
        let maxLimitStore = TestStore(
            initialState: ContentTabState(tabs: tabs, activeTabID: firstID, recentlyClosed: nil),
        ) {
            ContentTabFeature()
        }

        await maxLimitStore.send(.open(.homeDefault))
        XCTAssertEqual(maxLimitStore.state.tabs.count, ContentTabConstants.maxTabs)
        XCTAssertEqual(maxLimitStore.state.activeTabID, firstID)
        await maxLimitStore.finish()

        let restoreSnapshot = ClosedContentTabSnapshot(
            page: .directory,
            anchor: .directory(path: "/restore"),
            wasPinned: false,
            closedAt: Date(),
        )
        let restoreMaxLimitStore = TestStore(
            initialState: ContentTabState(tabs: tabs, activeTabID: firstID, recentlyClosed: restoreSnapshot),
        ) {
            ContentTabFeature()
        }

        await restoreMaxLimitStore.send(.restore)
        XCTAssertEqual(restoreMaxLimitStore.state.tabs.count, ContentTabConstants.maxTabs)
        XCTAssertEqual(restoreMaxLimitStore.state.activeTabID, firstID)
        XCTAssertEqual(restoreMaxLimitStore.state.recentlyClosed, restoreSnapshot)
        await restoreMaxLimitStore.finish()
    }

    // MARK: - CTM-001-content_tab_scope_integrity

    /// CTM-001-content_tab_scope_integrity: CTM action이 기존 FileManager scope를 침범하지 않는 wiring 검증
    /// VOY-446 wiring이 FileManager page-owned CTM slice로만 라우팅되는지 검증한다.
    /// - 검증 내용: contentTabs.open 전후 기존 content navigation, sidebar visibility, inspector visibility 불변
    /// - 사전 조건: `FileManagerWindowState.makeInitial(path:)` 기반 FileManagerFeature TestStore
    /// - 기대 결과: CTM action은 contentTabs state만 변경하고 기존 scope state를 유지함
    func testFileManagerContentTabScope_doesNotMutateExistingContentSidebarInspectorState() async {
        let initialState = FileManagerWindowState.makeInitial(path: "/seed")
        let initialNavigationPath = initialState.content.navigation.currentPath
        let initialSidebarVisible = initialState.sidebar.sidebarVisible
        let initialInspectorVisible = initialState.inspector.inspectorVisible
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action 방출하므로
        // scope 독립성에 집중한다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.open(.directory(path: "/different"))))

        XCTAssertEqual(store.state.content.navigation.currentPath, initialNavigationPath)
        XCTAssertEqual(store.state.sidebar.sidebarVisible, initialSidebarVisible)
        XCTAssertEqual(store.state.inspector.inspectorVisible, initialInspectorVisible)
    }

    // MARK: - CTM-001-open_new_content_tab_routing

    /// CTM-001-open_new_content_tab_routing: WindowCommand.openNewContentTab 라우팅이 Home tab을 append하고 active로 설정함
    /// - 검증 내용: .request(.openNewContentTab) 전송 후 tabs.count +1, last.anchor == .homeDefault, activeTabID == last.id
    /// - 사전 조건: 기본 Home tab 하나가 있는 FileManagerFeature.State
    /// - 기대 결과: 새 Home tab이 list 끝에 추가되고 active가 됨
    func testOpenNewContentTab_commandRouting_createsHomeTabAppendedActive() async throws {
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action 방출하므로
        // routing layer의 최종 상태 검증에 집중한다.
        store.exhaustivity = .off

        let beforeCount = store.state.contentTabs.tabs.count
        let beforeActiveID = store.state.contentTabs.activeTabID

        await store.send(.request(.openNewContentTab))
        await store.receive(\.contentTabs)

        let afterCount = store.state.contentTabs.tabs.count
        XCTAssertEqual(afterCount, beforeCount + 1, "tabs count must increment by 1")
        let lastTab = try XCTUnwrap(store.state.contentTabs.tabs.last)
        XCTAssertEqual(lastTab.anchor, .homeDefault, "new tab must have homeDefault anchor")
        XCTAssertEqual(lastTab.page, .home, "new tab must have home page")
        XCTAssertEqual(store.state.contentTabs.activeTabID, lastTab.id, "new tab must be active")
        XCTAssertNotEqual(store.state.contentTabs.activeTabID, beforeActiveID, "active tab ID must change to new tab")
    }

    /// CTM-001-open_new_content_tab_routing: 기존 active Directory/Collection anchor가 새 tab에 복제되지 않음
    /// VOY-447 AC3와 CTM contract의 "copy 방지" 정책을 검증한다.
    /// - 검증 내용: Directory tab이 active인 상태에서 openNewContentTab 전송 시 last.anchor == .homeDefault
    /// - 사전 조건: Directory anchor를 가진 active tab (makeInitial(path:)로 ContentTab과 별도로 navigation path만 설정)
    /// - 기대 결과: 새 tab anchor는 .homeDefault이며 기존 anchor를 복사하지 않음
    func testOpenNewContentTab_commandRouting_doesNotCloneExistingAnchor() async throws {
        var initialState = FileManagerFeature.State()
        // 기존 Home tab을 Directory tab으로 변경하여 active tab이 Home이 아닌 상태를 만듦
        initialState.contentTabs.tabs[0].anchor = .directory(path: "/test")
        initialState.contentTabs.tabs[0].page = .directory
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.request(.openNewContentTab))
        await store.receive(\.contentTabs)

        let lastTab = try XCTUnwrap(store.state.contentTabs.tabs.last)
        XCTAssertEqual(lastTab.anchor, .homeDefault, "new tab must NOT clone existing Directory anchor")
        XCTAssertEqual(lastTab.page, .home, "new tab must start as Home, not Directory")
    }

    /// CTM-001-open_new_content_tab_routing: 기존 active tab은 새 tab 생성 후 inactive로 전환됨
    /// 새 tab이 active가 되면 이전 active tab이 더 이상 active가 아님을 검증한다.
    /// - 검증 내용: openNewContentTab 전후 이전 activeTabID가 tabs에 존재하지만 activeTabID와 다름
    /// - 사전 조건: 기본 Home tab 하나가 있는 FileManagerFeature.State
    /// - 기대 결과: 이전 active tab은 tabs에 남아있고 activeTabID는 새 tab을 가리킴
    func testOpenNewContentTab_commandRouting_existingTabTransitionsInactive() async throws {
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        let previousActiveID = try XCTUnwrap(store.state.contentTabs.activeTabID)

        await store.send(.request(.openNewContentTab))
        await store.receive(\.contentTabs)

        let newActiveID = try XCTUnwrap(store.state.contentTabs.activeTabID)
        XCTAssertNotNil(
            store.state.contentTabs.tabs[id: previousActiveID],
            "previous active tab must still exist in tabs",
        )
        XCTAssertNotEqual(newActiveID, previousActiveID, "active tab ID must change")
    }
}
