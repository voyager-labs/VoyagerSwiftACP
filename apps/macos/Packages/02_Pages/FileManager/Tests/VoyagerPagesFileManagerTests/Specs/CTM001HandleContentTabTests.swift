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

    // MARK: - CTM-001-close_content_tab

    /// CTM-001-close_content_tab: 일반 close는 restore snapshot을 남기고 마지막 탭 close는 Home fallback을 유지함
    /// 기능스펙의 surface close 정책과 window당 active tab invariant를 함께 검증한다.
    /// - 검증 내용: unpinned close snapshot 저장, active fallback, 마지막 active close의 Home fallback 생성
    /// - 사전 조건: Home+Directory 두 탭 상태와 Directory 단일 active 상태
    /// - 기대 결과: 닫힌 탭은 snapshot으로 보존되고 active tab은 항상 존재함
    func testCloseContentTab_savesRestoreSnapshotAndKeepsActiveTabInvariant() throws {
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

        let fallbackTab = try XCTUnwrap(lastTabState.tabs.first)
        XCTAssertEqual(lastTabState.tabs.count, 1)
        XCTAssertNotEqual(fallbackTab.id, lastID)
        XCTAssertEqual(lastTabState.activeTabID, fallbackTab.id)
        XCTAssertEqual(fallbackTab.page, .home)
        XCTAssertEqual(fallbackTab.anchor, .homeDefault)
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
    /// - 검증 내용: unknown id actions no-op, maxTabs 도달 후 open no-op
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
}
