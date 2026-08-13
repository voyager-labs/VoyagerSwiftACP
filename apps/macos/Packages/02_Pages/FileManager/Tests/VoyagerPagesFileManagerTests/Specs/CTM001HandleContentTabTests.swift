import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
import VoyagerEntitiesCollection
import VoyagerFeaturesContentPageNavigation
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

@MainActor
final class CTM001HandleContentTabTests: XCTestCase {
    private func receiveDirectoryNavigation(
        _ store: TestStoreOf<FileManagerFeature>,
        path: String,
    ) async {
        await store.receive { action in
            guard case let .navigation(.view(.navigateToPath(receivedPath))) = action else { return false }
            return receivedPath == path
        }
        await store.receive { action in
            guard case let .navigation(.internal(.performNavigateToPath(receivedPath))) = action else { return false }
            return receivedPath == path
        }
        await store.receive { action in
            guard case let .navigation(.delegate(.navigateToState(.folder(receivedPath)))) = action
            else { return false }
            return receivedPath == path
        }
        await store.receive { action in
            guard case let .tabContent(_, .internal(.applyNavigationState(.folder(receivedPath)))) = action
            else { return false }
            return receivedPath == path
        }
    }

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
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
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

    /// CTM-001-open_new_content_tab: path seed가 initial tab을 directory anchor로 동기화함
    /// path 기반 FileManager window 생성 시 chrome/source-of-truth anchor가 folder route와 일치하는지 검증한다.
    /// - 검증 내용: path seed("/tmp")에서 contentTabs.tabs.first?.anchor == .directory(path: "/tmp"), count == 1
    /// - 사전 조건: FileManagerWindowState.makeInitial(path: "/tmp")
    /// - 기대 결과: path seed window가 Home tab metadata로 남지 않고 directory tab으로 표시됨
    func testOpenNewContentTab_pathSeed_syncsDirectoryAnchor() {
        let state = FileManagerWindowState.makeInitial(path: "/tmp")

        XCTAssertEqual(state.contentTabs.tabs.first?.anchor, .directory(path: "/tmp"))
        XCTAssertEqual(state.contentTabs.tabs.count, 1)
    }

    /// CTM-001-open_new_content_tab: path seed가 navigation currentPath를 설정함
    /// path 기반 FileManager window 생성이 기존 navigation seed 동작을 유지하는지 검증한다.
    /// - 검증 내용: makeInitial(path: "/tmp") 결과 content.navigation.currentPath가 존재함
    /// - 사전 조건: FileManagerWindowState.makeInitial(path: "/tmp")
    /// - 기대 결과: directory tab anchor와 navigation seed가 함께 적용됨
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
        XCTAssertEqual(state.content.navigation.currentPath, "/restored")
    }

    func testOpenNewContentTab_makeInitialWithRestoredCollectionState_seedsActiveContentFromAnchor() {
        let restoredID = ContentTabID()
        let collectionURL = URL(fileURLWithPath: "/tmp/restored.voycoll")
        let restoredState = ContentTabState(
            tabs: [ContentTabItem(
                id: restoredID,
                page: .collection,
                anchor: .collectionFile(url: collectionURL),
                isPinned: false,
                title: "restored",
                iconName: "rectangle.stack",
            )],
            activeTabID: restoredID,
            recentlyClosed: nil,
        )

        let state = FileManagerWindowState.makeInitial(path: nil, contentTabs: restoredState)

        XCTAssertEqual(state.contentTabs.tabs.first?.anchor, .collectionFile(url: collectionURL))
        if case let .collection(navigation) = state.content.navigation.navigationState {
            XCTAssertEqual(navigation.kind, .file(url: collectionURL, name: "restored"))
            XCTAssertEqual(navigation.context, CollectionContext(query: "", scopes: [], conditions: []))
        } else {
            XCTFail("restored collection tab should seed collection navigation")
        }
        XCTAssertEqual(
            state.tabContentStates[restoredID]?.navigation.navigationState,
            state.content.navigation.navigationState,
        )
    }

    func testOpenNewContentTab_makeInitialWithRestoredVirtualState_seedsActiveContentFromAnchor() {
        let restoredID = ContentTabID()
        let restoredState = ContentTabState(
            tabs: [ContentTabItem(
                id: restoredID,
                page: .collection,
                anchor: .virtualCollection(id: "Important"),
                isPinned: false,
                title: "Important",
                iconName: "tag",
            )],
            activeTabID: restoredID,
            recentlyClosed: nil,
        )

        let state = FileManagerWindowState.makeInitial(path: nil, contentTabs: restoredState)

        XCTAssertEqual(state.contentTabs.tabs.first?.anchor, .virtualCollection(id: "Important"))
        let expectedRoute = ContentPageNavigationRoute.tags("Important")
        XCTAssertEqual(state.content.navigation.navigationState, expectedRoute)
        XCTAssertEqual(state.tabContentStates[restoredID]?.navigation.navigationState, expectedRoute)
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

        // 마지막 tab은 새 ID의 Home tab으로 교체됨
        XCTAssertEqual(lastTabState.tabs.count, 1)
        XCTAssertEqual(lastTabState.tabs[0].page, .home)
        XCTAssertEqual(lastTabState.tabs[0].anchor, .homeDefault)
        XCTAssertEqual(lastTabState.tabs[0].title, "Home")
        XCTAssertEqual(lastTabState.tabs[0].iconName, "house")
        XCTAssertNotEqual(lastTabState.activeTabID, lastID)
        XCTAssertEqual(lastTabState.tabs[0].id, lastTabState.activeTabID)
        XCTAssertNil(lastTabState.recentlyClosed)
    }

    /// CTM-001-close_content_tab: pinned tab close는 restore snapshot을 생성하지 않음
    /// pinned tab close는 unpin transition이며 recentlyClosed 후보를 남기지 않음을 검증한다.
    /// - 검증 내용: close 후 recentlyClosed == nil, tab 유지, isPinned false 전환
    /// - 사전 조건: active pinned Home tab 하나
    /// - 기대 결과: pinned close가 unpin만 수행하고 snapshot 미생성
    func testCloseContentTab_pinnedCloseDoesNotCreateRestoreCandidate() {
        let pinnedID = ContentTabID()
        var state = ContentTabState(
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
        )
        let reducer = ContentTabFeature()

        _ = reducer.reduce(into: &state, action: .close(pinnedID))

        XCTAssertNil(state.recentlyClosed)
        XCTAssertEqual(state.tabs.count, 1)
        XCTAssertFalse(state.tabs.first?.isPinned ?? true)
    }

    func testCloseLastAiChatTabPreservesRecentlyClosedSnapshot() async {
        let sessionID = "chat-1"
        let aiChatTabID = ContentTabID()
        let store = TestStore(
            initialState: ContentTabState(
                tabs: [
                    ContentTabItem(
                        id: aiChatTabID,
                        page: .aiChat,
                        anchor: .aiChat(sessionID: sessionID),
                        isPinned: false,
                        title: nil,
                        iconName: nil,
                    ),
                ],
                activeTabID: aiChatTabID,
                recentlyClosed: nil,
            ),
        ) {
            ContentTabFeature()
        }
        store.exhaustivity = .off

        await store.send(.close(aiChatTabID))

        XCTAssertEqual(store.state.recentlyClosed?.anchor, .aiChat(sessionID: sessionID))
        XCTAssertNotNil(store.state.activeTabID)
        XCTAssertEqual(store.state.tabs.count, 1)
        guard let tab = store.state.tabs.first else {
            return XCTFail("Expected at least one tab after close")
        }
        XCTAssertEqual(tab.page, .home)
        XCTAssertEqual(tab.anchor, .homeDefault)
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

    /// CTM-001-restore_last_closed_tab: candidate가 없으면 restore는 no-op
    /// recentlyClosed가 nil일 때 restore가 tabs와 activeTabID를 변경하지 않음을 검증한다.
    /// - 검증 내용: restore 후 tabs.count, activeTabID, recentlyClosed 불변
    /// - 사전 조건: recentlyClosed == nil, Home tab 하나
    /// - 기대 결과: restore 호출 후 tabs와 activeTabID가 변경되지 않고 recentlyClosed == nil 유지
    func testRestoreLastClosedTab_noCandidateIsNoOp() {
        let homeID = ContentTabID()
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
            recentlyClosed: nil,
        )
        let reducer = ContentTabFeature()

        _ = reducer.reduce(into: &state, action: .restore)

        XCTAssertEqual(state.tabs.count, 1)
        XCTAssertEqual(state.activeTabID, homeID)
        XCTAssertNil(state.recentlyClosed)
    }

    /// CTM-001-restore_last_closed_tab: snapshot의 title/iconName metadata가 restore된 tab에 우선 사용됨
    /// close 시 저장된 title과 iconName이 restore에서 title(for:)/iconName(for:)보다 우선 적용됨을 검증한다.
    /// - 검증 내용: restore된 tab의 title == snapshot.title, iconName == snapshot.iconName
    /// - 사전 조건: recentlyClosed에 title과 iconName이 설정된 snapshot
    /// - 기대 결과: restore된 tab이 snapshot metadata를 그대로 사용함
    func testRestoreLastClosedTab_preservesSnapshotMetadata() throws {
        let homeID = ContentTabID()
        let snapshot = ClosedContentTabSnapshot(
            page: .directory,
            anchor: .directory(path: "/custom"),
            wasPinned: false,
            closedAt: Date(),
            title: "Custom Title",
            iconName: "custom.icon",
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
            recentlyClosed: snapshot,
        )
        let reducer = ContentTabFeature()

        _ = reducer.reduce(into: &state, action: .restore)

        let restoredTab = try XCTUnwrap(state.tabs.last)
        XCTAssertEqual(restoredTab.title, "Custom Title")
        XCTAssertEqual(restoredTab.iconName, "custom.icon")
    }

    /// CTM-001-restore_last_closed_tab: close A → close B → restore는 B만 복원함
    /// 연속 close 시 마지막 snapshot만 보존되고 restore가 가장 최근 snapshot을 소비함을 검증한다.
    /// - 검증 내용: close(A) → close(B) → restore 후 restored tab의 anchor == B의 anchor
    /// - 사전 조건: Home + A + B 세 tab, A와 B 순서로 close
    /// - 기대 결과: B의 snapshot만 restore되고 A는 복원되지 않음
    func testRestoreLastClosedTab_overwritesOnMultipleClose() throws {
        let homeID = ContentTabID()
        let tabA = ContentTabID()
        let tabB = ContentTabID()
        let anchorB = ContentTabPageAnchor.directory(path: "/b")
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
                    id: tabA,
                    page: .directory,
                    anchor: .directory(path: "/a"),
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
                ContentTabItem(id: tabB, page: .directory, anchor: anchorB, isPinned: false, title: nil, iconName: nil),
            ],
            activeTabID: homeID,
            recentlyClosed: nil,
        )
        let reducer = ContentTabFeature()

        _ = reducer.reduce(into: &state, action: .close(tabA))
        _ = reducer.reduce(into: &state, action: .close(tabB))
        _ = reducer.reduce(into: &state, action: .restore)

        XCTAssertEqual(state.tabs.count, 2)
        XCTAssertNil(state.recentlyClosed)
        let restoredTab = try XCTUnwrap(state.tabs.last)
        XCTAssertEqual(restoredTab.anchor, anchorB)
        XCTAssertEqual(restoredTab.page, .directory)
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
        } withDependencies: {
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
        }

        await store.send(.close(pinnedID)) {
            $0.tabs[id: pinnedID]?.isPinned = false
        }
        await store.receive(\.pinnedRecordSaveSucceeded)
        await store.finish()
    }

    // MARK: - CTM-001-restore_last_closed_tab_routing

    /// CTM-001-restore_last_closed_tab_routing: 유효한 Directory anchor restore는 recentlyClosed snapshot을 소비하고 tab을 복원함
    /// FileManagerWindowCommandRoutingReducer.handleRequestedCommand(.restoreLastClosedContentTab) 경로를 통해
    /// anchor 유효성 검증 → ContentTabFeature.restore() 전달까지의 command-level routing을 검증한다.
    /// - 검증 내용: tabs.count == 2 (기존 Home + 복원된 Directory), recentlyClosed == nil, 복원된 tab의 anchor와 page가 snapshot과 일치
    /// - 사전 조건: Home tab 하나, 최근 닫힌 Directory tab snapshot, fileManagerClient.fileExistsWithIsDirectory → (true,
    /// isDirectory=true)
    /// - 기대 결과: restore 후 새 Directory tab이 active로 추가되고 recentlyClosed가 비워짐
    func testRestoreLastClosedTabCommand_validDirectoryRestoresAndConsumesSnapshot() async throws {
        let directoryAnchor = ContentTabPageAnchor.directory(path: "/Users/test/Documents")
        var state = FileManagerFeature.State()
        state.contentTabs.recentlyClosed = ClosedContentTabSnapshot(
            page: .directory,
            anchor: directoryAnchor,
            wasPinned: false,
            closedAt: Date(),
        )
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.fileManagerClient.fileExistsWithIsDirectory = { _, isDirectory in
                isDirectory?.pointee = true
                return true
            }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action과 restore 후
        // handoff/navigation child effect를 방출하므로 최종 상태 검증에 집중한다.
        store.exhaustivity = .off

        let beforeCount = store.state.contentTabs.tabs.count

        await store.send(.request(.restoreLastClosedContentTab))
        await store.receive(\.contentTabs)

        XCTAssertEqual(store.state.contentTabs.tabs.count, beforeCount + 1)
        XCTAssertNil(store.state.contentTabs.recentlyClosed)
        let restoredTab = try XCTUnwrap(store.state.contentTabs.tabs.last)
        XCTAssertEqual(restoredTab.anchor, directoryAnchor)
        XCTAssertEqual(restoredTab.page, .directory)
    }

    /// CTM-001-restore_last_closed_tab_routing: 삭제된 Directory anchor restore는 snapshot을 소비하고 feedback alert을 표시함
    /// handleRestoreLastClosedContentTab에서 fileManagerClient.fileExistsWithIsDirectory가 false를 반환하면
    /// recentlyClosed를 초기화하고 collectionAlertClient로 사용자 피드백을 전송하는 경로를 검증한다.
    /// - 검증 내용: tabs.count 불변 (1), recentlyClosed == nil,
    ///   collectionAlertClient에 "Cannot Restore Tab" / "The recently closed tab is no longer available." alert 전송
    /// - 사전 조건: Home tab 하나, 삭제된 경로의 Directory snapshot, fileManagerClient.fileExistsWithIsDirectory → false
    /// - 기대 결과: recentlyClosed가 소비되고 alert이 표시되며 tab 목록은 변경되지 않음
    func testRestoreLastClosedTabCommand_invalidDirectoryConsumesSnapshotAndShowsFeedback() async {
        let collectionAlertRecorder = LockIsolated<[(title: String, message: String)]>([])
        var state = FileManagerFeature.State()
        state.contentTabs.recentlyClosed = ClosedContentTabSnapshot(
            page: .directory,
            anchor: .directory(path: "/Users/test/Deleted"),
            wasPinned: false,
            closedAt: Date(),
        )
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.fileManagerClient.fileExistsWithIsDirectory = { _, _ in false }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { title, message in
                collectionAlertRecorder.withValue { $0.append((title, message)) }
            }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: FileManagerFeature.onAppear 및 restore failure effect(.run)가
        // 여러 action을 방출하므로 snapshot 소비와 alert 전송 검증에 집중한다.
        store.exhaustivity = .off

        await store.send(.request(.restoreLastClosedContentTab))
        await store.finish()

        XCTAssertEqual(store.state.contentTabs.tabs.count, 1)
        XCTAssertNil(store.state.contentTabs.recentlyClosed)
        let alerts = collectionAlertRecorder.value
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts[0].title, "Cannot Restore Tab")
        XCTAssertEqual(alerts[0].message, "The recently closed tab is no longer available.")
    }

    /// CTM-001-restore_last_closed_tab_routing: 삭제된 CollectionFile anchor restore는 snapshot을 소비하고 feedback alert을 표시함
    /// Directory와 동일한 실패 경로를 collectionFile anchor(.collectionFile)에서 검증한다.
    /// - 검증 내용: tabs.count 불변, recentlyClosed == nil,
    ///   collectionAlertClient에 "Cannot Restore Tab" / "The recently closed tab is no longer available." alert 전송
    /// - 사전 조건: Home tab 하나, 존재하지 않는 collectionFile 경로의 snapshot, fileManagerClient.fileExistsWithIsDirectory → false
    /// - 기대 결과: recentlyClosed가 소비되고 "Cannot Restore Tab" alert이 표시됨
    func testRestoreLastClosedTabCommand_missingCollectionConsumesSnapshotAndShowsFeedback() async {
        let collectionAlertRecorder = LockIsolated<[(title: String, message: String)]>([])
        let collectionURL = URL(fileURLWithPath: "/Users/test/Deleted.voyagercollection")
        var state = FileManagerFeature.State()
        state.contentTabs.recentlyClosed = ClosedContentTabSnapshot(
            page: .collection,
            anchor: .collectionFile(url: collectionURL),
            wasPinned: false,
            closedAt: Date(),
        )
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.fileManagerClient.fileExistsWithIsDirectory = { _, _ in false }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { title, message in
                collectionAlertRecorder.withValue { $0.append((title, message)) }
            }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: FileManagerFeature.onAppear 및 restore failure effect 방출로 인해
        // collection anchor missing 경로 검증에 집중한다.
        store.exhaustivity = .off

        await store.send(.request(.restoreLastClosedContentTab))
        await store.finish()

        XCTAssertEqual(store.state.contentTabs.tabs.count, 1)
        XCTAssertNil(store.state.contentTabs.recentlyClosed)
        let alerts = collectionAlertRecorder.value
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts[0].title, "Cannot Restore Tab")
        XCTAssertEqual(alerts[0].message, "The recently closed tab is no longer available.")
    }

    /// CTM-001-restore_last_closed_tab_routing: Virtual Collection restore candidate는 소비하지 않고 복원됨
    /// Recents/Tags/Computer 계열 virtualCollection anchor는 기존 content 초기화 경로에서 `.tags(id)`로 복원 가능하므로 실패 feedback 대상이
    /// 아니다.
    /// - 검증 내용: restore command 실행 후 새 tab 생성, active 전환, recentlyClosed 소비
    /// - 사전 조건: Home tab 하나, virtualCollection("Important") snapshot 1개
    /// - 기대 결과: 새 tab이 `.virtualCollection(id: "Important")` anchor로 추가되고 alert 없이 복원됨
    func testRestoreLastClosedTabCommand_virtualCollectionRestoresAndConsumesSnapshot() async {
        let collectionAlertRecorder = LockIsolated<[(title: String, message: String)]>([])
        let anchor = ContentTabPageAnchor.virtualCollection(id: "Important")
        var state = FileManagerFeature.State()
        state.contentTabs.recentlyClosed = ClosedContentTabSnapshot(
            page: .collection,
            anchor: anchor,
            wasPinned: false,
            closedAt: Date(),
            title: "Important",
            iconName: "tag",
        )
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { title, message in
                collectionAlertRecorder.withValue { $0.append((title, message)) }
            }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: FileManagerFeature.onAppear와 restore 후 content handoff child action은
        // 기존 lifecycle 테스트가 담당하므로 command-level candidate 소비/복원만 검증한다.
        store.exhaustivity = .off

        await store.send(.request(.restoreLastClosedContentTab))
        await store.receive(\.contentTabs)
        await store.finish()

        XCTAssertEqual(store.state.contentTabs.tabs.count, 2)
        XCTAssertEqual(store.state.contentTabs.activeTabID, store.state.contentTabs.tabs.last?.id)
        XCTAssertEqual(store.state.contentTabs.tabs.last?.page, .collection)
        XCTAssertEqual(store.state.contentTabs.tabs.last?.anchor, anchor)
        XCTAssertEqual(store.state.contentTabs.tabs.last?.title, "Important")
        XCTAssertEqual(store.state.contentTabs.tabs.last?.iconName, "tag")
        XCTAssertNil(store.state.contentTabs.recentlyClosed)
        XCTAssertTrue(collectionAlertRecorder.value.isEmpty)
    }

    /// CTM-001-restore_last_closed_tab_routing: AI Chat anchor restore는 snapshot을 소비하고 feedback alert을 표시함
    /// AI Chat anchor(.aiChat)는 restoreFailureReason에서 .unsupportedAIChat으로 분류되어
    /// recentlyClosed가 소비되고 사용자에게 "AI Chat tabs cannot be restored yet." 피드백이 전달됨을 검증한다.
    /// - 검증 내용: tabs.count 불변, recentlyClosed == nil,
    ///   collectionAlertClient에 "Cannot Restore Tab" / "AI Chat tabs cannot be restored yet." alert 전송
    /// - 사전 조건: Home tab 하나, AI Chat session snapshot (sessionID: "chat-1")
    /// - 기대 결과: snapshot이 소비되고 비활성 anchor에 대한 alert이 표시됨
    func testRestoreLastClosedTabCommand_aiChatConsumesSnapshotAndShowsFeedback() async {
        let collectionAlertRecorder = LockIsolated<[(title: String, message: String)]>([])
        var state = FileManagerFeature.State()
        state.contentTabs.recentlyClosed = ClosedContentTabSnapshot(
            page: .aiChat,
            anchor: .aiChat(sessionID: "chat-1"),
            wasPinned: false,
            closedAt: Date(),
        )
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { title, message in
                collectionAlertRecorder.withValue { $0.append((title, message)) }
            }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: FileManagerFeature.onAppear 및 restore failure effect 방출로 인해
        // AI Chat anchor unsupported 경로 검증에 집중한다.
        store.exhaustivity = .off

        await store.send(.request(.restoreLastClosedContentTab))
        await store.finish()

        XCTAssertEqual(store.state.contentTabs.tabs.count, 1)
        XCTAssertNil(store.state.contentTabs.recentlyClosed)
        let alerts = collectionAlertRecorder.value
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts[0].title, "Cannot Restore Tab")
        XCTAssertEqual(alerts[0].message, "AI Chat tabs cannot be restored yet.")
    }

    // MARK: - CTM-001-close_restore_lifecycle

    /// CTM-001-close_restore_lifecycle: active close가 previousActiveTabID를 valid fallback으로 사용함
    /// close 시 previousActiveTabID가 closing tab이 아니고 tabs에 존재하면 해당 id가 active로 설정되는 정책을 검증한다.
    /// - 검증 내용: previousActiveTabID가 closing tab이 아니고 tabs에 존재하면 해당 id가 activeTabID로 설정됨
    /// - 사전 조건: [A(active), B, C] 상태, previousActiveTabID = C
    /// - 기대 결과: close(A) 후 activeTabID == C (C가 previous로서 우선)
    func testCloseContentTab_activeCloseWithPreviousActiveFallback() {
        let tabA = ContentTabID()
        let tabB = ContentTabID()
        let tabC = ContentTabID()
        var state = ContentTabState(
            tabs: [
                ContentTabItem(id: tabA, page: .home, anchor: .homeDefault, isPinned: false, title: nil, iconName: nil),
                ContentTabItem(
                    id: tabB,
                    page: .directory,
                    anchor: .directory(path: "/b"),
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
                ContentTabItem(
                    id: tabC,
                    page: .directory,
                    anchor: .directory(path: "/c"),
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
            ],
            activeTabID: tabA,
            previousActiveTabID: tabC,
            recentlyClosed: nil,
        )
        let reducer = ContentTabFeature()

        _ = reducer.reduce(into: &state, action: .close(tabA))

        XCTAssertEqual(state.tabs.count, 2)
        XCTAssertEqual(state.activeTabID, tabC)
    }

    /// CTM-001-close_restore_lifecycle: active close의 previous가 closing tab이면 nearest right이 fallback됨
    /// close 시 previousActiveTabID가 nil 또는 closing id일 때 nearest right tab이 active로 설정되는 정책을 검증한다.
    /// - 검증 내용: previousActiveTabID == closing id일 때 nearest right tab이 activeTabID로 설정됨
    /// - 사전 조건: [A(active), B, C] 상태, previousActiveTabID = A
    /// - 기대 결과: close(A) 후 activeTabID == B (nearest right)
    func testCloseContentTab_activeCloseNearestRight() {
        let tabA = ContentTabID()
        let tabB = ContentTabID()
        let tabC = ContentTabID()
        var state = ContentTabState(
            tabs: [
                ContentTabItem(id: tabA, page: .home, anchor: .homeDefault, isPinned: false, title: nil, iconName: nil),
                ContentTabItem(
                    id: tabB,
                    page: .directory,
                    anchor: .directory(path: "/b"),
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
                ContentTabItem(
                    id: tabC,
                    page: .directory,
                    anchor: .directory(path: "/c"),
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
            ],
            activeTabID: tabA,
            previousActiveTabID: tabA,
            recentlyClosed: nil,
        )
        let reducer = ContentTabFeature()

        _ = reducer.reduce(into: &state, action: .close(tabA))

        XCTAssertEqual(state.tabs.count, 2)
        XCTAssertEqual(state.activeTabID, tabB)
    }

    /// CTM-001-close_restore_lifecycle: active close의 previous가 closing tab이고 right이 out of bounds이면 left가 fallback됨
    /// close 시 previousActiveTabID가 nullish이고 right neighbor가 없으면 left neighbor가 active로 설정되는 정책을 검증한다.
    /// - 검증 내용: previousActiveTabID == closing id이고 right이 없으면 left neighbor tab이 activeTabID로 설정됨
    /// - 사전 조건: [A, B, C(active)] 상태, previousActiveTabID = C
    /// - 기대 결과: close(C) 후 activeTabID == B (left neighbor)
    func testCloseContentTab_activeCloseNearestLeft() {
        let tabA = ContentTabID()
        let tabB = ContentTabID()
        let tabC = ContentTabID()
        var state = ContentTabState(
            tabs: [
                ContentTabItem(id: tabA, page: .home, anchor: .homeDefault, isPinned: false, title: nil, iconName: nil),
                ContentTabItem(
                    id: tabB,
                    page: .directory,
                    anchor: .directory(path: "/b"),
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
                ContentTabItem(
                    id: tabC,
                    page: .directory,
                    anchor: .directory(path: "/c"),
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
            ],
            activeTabID: tabC,
            previousActiveTabID: tabC,
            recentlyClosed: nil,
        )
        let reducer = ContentTabFeature()

        _ = reducer.reduce(into: &state, action: .close(tabC))

        XCTAssertEqual(state.tabs.count, 2)
        XCTAssertEqual(state.activeTabID, tabB)
    }

    /// CTM-001-close_restore_lifecycle: inactive close는 activeTabID를 변경하지 않고 previousActiveTabID를 nil로 초기화함
    /// inactive tab close 시 active tab이 보존되고 previousActiveTabID가 초기화되는 정책을 검증한다.
    /// - 검증 내용: inactive tab close 후 activeTabID가 변경되지 않고 previousActiveTabID == nil
    /// - 사전 조건: [A(active), B] 상태
    /// - 기대 결과: close(B) 후 activeTabID == A (불변), previousActiveTabID == nil
    func testCloseContentTab_inactiveClosePreservesActive() {
        let tabA = ContentTabID()
        let tabB = ContentTabID()
        var state = ContentTabState(
            tabs: [
                ContentTabItem(id: tabA, page: .home, anchor: .homeDefault, isPinned: false, title: nil, iconName: nil),
                ContentTabItem(
                    id: tabB,
                    page: .directory,
                    anchor: .directory(path: "/b"),
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
            ],
            activeTabID: tabA,
            previousActiveTabID: tabA,
            recentlyClosed: nil,
        )
        let reducer = ContentTabFeature()

        _ = reducer.reduce(into: &state, action: .close(tabB))

        XCTAssertEqual(state.tabs.count, 1)
        XCTAssertEqual(state.activeTabID, tabA)
        XCTAssertNil(state.previousActiveTabID)
    }

    /// CTM-001-close_restore_lifecycle: 연속 close는 recentlyClosed를 마지막 close snapshot으로 overwrite함
    /// close 후보가 overwrite되는 single candidate 정책을 검증한다.
    /// - 검증 내용: close(B) 후 close(C)를 연속 수행하면 recentlyClosed가 C의 snapshot을 가리킴
    /// - 사전 조건: [A(active), B, C] 상태
    /// - 기대 결과: close(B) → close(C) 후 recentlyClosed의 anchor와 page가 C에 해당함
    func testCloseContentTab_singleCandidateOverwrite() {
        let tabA = ContentTabID()
        let tabB = ContentTabID()
        let tabC = ContentTabID()
        let anchorC = ContentTabPageAnchor.directory(path: "/c")
        var state = ContentTabState(
            tabs: [
                ContentTabItem(id: tabA, page: .home, anchor: .homeDefault, isPinned: false, title: nil, iconName: nil),
                ContentTabItem(
                    id: tabB,
                    page: .directory,
                    anchor: .directory(path: "/b"),
                    isPinned: false,
                    title: nil,
                    iconName: nil,
                ),
                ContentTabItem(id: tabC, page: .directory, anchor: anchorC, isPinned: false, title: nil, iconName: nil),
            ],
            activeTabID: tabA,
            previousActiveTabID: nil,
            recentlyClosed: nil,
        )
        let reducer = ContentTabFeature()

        _ = reducer.reduce(into: &state, action: .close(tabB))
        _ = reducer.reduce(into: &state, action: .close(tabC))

        XCTAssertEqual(state.recentlyClosed?.anchor, anchorC)
        XCTAssertEqual(state.recentlyClosed?.page, .directory)
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
        await store.send(.unpin(invalidID))
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

    /// CTM-001-content_tab_scope_integrity: 새 Content Tab은 별도 FileManager content session을 만들고 기존 session을 보존함
    /// CTM action이 sidebar/inspector shell state를 침범하지 않으면서 active content만 tab session으로 swap하는지 검증한다.
    /// - 검증 내용: contentTabs.open(.directory) 후 active content는 새 path로 전환되고 기존 content는 tabContentStates에 보존됨
    /// - 사전 조건: `FileManagerWindowState.makeInitial(path:)` 기반 FileManagerFeature TestStore
    /// - 기대 결과: 새 Directory tab이 active가 되고 sidebar visibility, inspector visibility는 유지됨
    func testFileManagerContentTabScope_swapsContentSessionAndPreservesShellState() async throws {
        let initialState = FileManagerWindowState.makeInitial(path: "/seed")
        let initialActiveID = try XCTUnwrap(initialState.contentTabs.activeTabID)
        let initialNavigationPath = initialState.content.navigation.currentPath
        let initialSidebarVisible = initialState.sidebar.sidebarVisible
        let initialInspectorVisible = initialState.inspector.inspectorVisible
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 새 tab id는 reducer 내부에서 생성되므로 최종 invariant만 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.open(.directory(path: "/different"))))

        XCTAssertEqual(store.state.content.navigation.currentPath, "/different")
        XCTAssertEqual(store.state.tabContentStates[initialActiveID]?.navigation.currentPath, initialNavigationPath)
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
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
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
        initialState.contentTabs.tabs[0].anchor = .directory(path: "/test")
        initialState.contentTabs.tabs[0].page = .directory
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action을 방출하므로
        // anchor 복제 방지 검증에 집중한다.
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
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action을 방출하므로
        // tab active 전환 검증에 집중한다.
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

    // MARK: - CTM-001-open_new_content_tab_invariants

    /// CTM-001-open_new_content_tab_invariants: ContentTabProjection.sidebarItems에 새 Home tab이 반영됨
    /// VOY-447 Sidebar projection refresh 정책을 검증한다.
    /// - 검증 내용: .request(.openNewContentTab) 후 ContentTabProjection.sidebarItems(from:) count +1 및 마지막 항목 pageType ==
    /// .home
    /// - 사전 조건: 기본 Home tab 하나가 있는 FileManagerFeature.State
    /// - 기대 결과: projection output에 새 tab이 마지막 항목으로 포함됨
    func testOpenNewContentTab_projection_sidebarItemsIncludesNewHomeTab() async throws {
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action 방출하므로 projection 검증에 집중한다.
        store.exhaustivity = .off

        let beforeCount = ContentTabProjection.sidebarItems(from: store.state.contentTabs).count

        await store.send(.request(.openNewContentTab))
        await store.receive(\.contentTabs)

        let sidebarItems = ContentTabProjection.sidebarItems(from: store.state.contentTabs)
        XCTAssertEqual(sidebarItems.count, beforeCount + 1, "projection must reflect new tab count")
        let lastItem = try XCTUnwrap(sidebarItems.last)
        XCTAssertEqual(lastItem.pageType, .home, "last projection item pageType must be home")
    }

    /// CTM-001-open_new_content_tab_invariants: maxTabs 상태에서 openNewContentTab은 no-op으로 기존 상태를 보존함
    /// VOY-447 AC4 failure 정책을 검증한다.
    /// - 검증 내용: maxTabs 도달 후 .request(.openNewContentTab) 전송 시 tabs.count와 activeTabID 불변
    /// - 사전 조건: ContentTabConstants.maxTabs만큼 채워진 tab list
    /// - 기대 결과: tabs.count와 activeTabID가 변경되지 않음
    func testOpenNewContentTab_maxTabsNoOp_preservesState() async {
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
        var state = FileManagerFeature.State()
        state.contentTabs.tabs = tabs
        state.contentTabs.activeTabID = firstID
        state.content.entryOperations.isLoading = true
        state.content.entryOperations.isReloading = true
        state.content.composer.isLoadingSearch = true

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: maxTabs guard로 인해 contentTabs action이 상태를 변경하지 않으므로 불변 검증에 집중한다.
        store.exhaustivity = .off

        await store.send(.request(.openNewContentTab))

        XCTAssertEqual(store.state.contentTabs.tabs.count, ContentTabConstants.maxTabs)
        XCTAssertEqual(store.state.contentTabs.activeTabID, firstID)
        XCTAssertTrue(store.state.content.entryOperations.isLoading)
        XCTAssertTrue(store.state.content.entryOperations.isReloading)
        XCTAssertTrue(store.state.content.composer.isLoadingSearch)
    }

    /// CTM-001-open_new_content_tab_invariants: 연속 openNewContentTab은 중복되지 않는 ID를 생성함
    /// VOY-447 repeated rapid creation 방지 정책을 검증한다.
    /// - 검증 내용: .request(.openNewContentTab) 2회 연속 후 모든 tab ID가 유일함
    /// - 사전 조건: 기본 Home tab 하나가 있는 FileManagerFeature.State
    /// - 기대 결과: 모든 tab의 id가 유일함 (Set count == count)
    func testOpenNewContentTab_repeatedCreation_usesUniqueIDs() async {
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action 방출하므로 ID uniqueness 검증에 집중한다.
        store.exhaustivity = .off

        await store.send(.request(.openNewContentTab))
        await store.receive(\.contentTabs)

        await store.send(.request(.openNewContentTab))
        await store.receive(\.contentTabs)

        let allIDs = store.state.contentTabs.tabs.map(\.id)
        let uniqueIDs = Set(allIDs)
        XCTAssertEqual(uniqueIDs.count, allIDs.count, "all tab IDs must be unique")
    }

    // MARK: - CTM-001-home_selection_page_conversion

    /// CTM-001-home_selection_page_conversion: 고정 Desktop 선택이 active Home tab을 Directory anchor로 변환함
    /// VOY-438 AC1의 고정 디렉터리 → ContentTabPageAnchor.directory(path:) 변환을 검증한다.
    /// - 검증 내용: tabs.count 불변, activeTabID 불변, tab.anchor가 Desktop 경로를 포함, tab.page == .directory
    /// - 사전 조건: FileManagerFeature.State 기본 Home tab 하나, fileManagerClient.urlsForDirectory → live FileManager
    /// - 기대 결과: Home tab의 anchor가 Desktop 파일시스템 경로로 변경되고 page가 directory로 전환됨
    func testHomeSelection_fixedDesktop_convertsToDirectoryAnchor() async throws {
        let desktopPath = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path ?? "/"
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.fileManagerClient.urlsForDirectory = { FileManager.default.urls(for: $0, in: $1) }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action 방출하므로 anchor 변환 검증에 집중한다.
        store.exhaustivity = .off

        let beforeCount = store.state.contentTabs.tabs.count
        let beforeActiveID = store.state.contentTabs.activeTabID

        await store.sendTabContent(.view(.homeSelectionTapped(.fixedDirectory(.desktop))))
        await store.receive(\.contentTabs)
        await receiveDirectoryNavigation(store, path: desktopPath)

        XCTAssertEqual(store.state.content.navigation.currentPath, desktopPath)
        XCTAssertEqual(store.state.content.navigation.backHistory.map(\.navigationState), [.home])
        XCTAssertEqual(store.state.content.entryViewLayout.currentPath, desktopPath)
        XCTAssertEqual(store.state.contentTabs.tabs.count, beforeCount)
        XCTAssertEqual(store.state.contentTabs.activeTabID, beforeActiveID)
        let tab = try XCTUnwrap(store.state.contentTabs.tabs.first)
        XCTAssertEqual(tab.anchor, .directory(path: desktopPath))
        XCTAssertEqual(tab.page, .directory)
    }

    /// CTM-001-home_selection_page_conversion: 고정 Documents 선택이 active Home tab을 Directory anchor로 변환함
    /// VOY-438 AC1의 Documents 고정 디렉터리 → ContentTabPageAnchor.directory(path:) 변환을 검증한다.
    /// - 검증 내용: tabs.count 불변, tab.anchor가 Documents 경로를 포함, tab.page == .directory
    /// - 사전 조건: FileManagerFeature.State 기본 Home tab 하나, fileManagerClient.urlsForDirectory → live FileManager
    /// - 기대 결과: Home tab의 anchor가 Documents 파일시스템 경로로 변경되고 page가 directory로 전환됨
    func testHomeSelection_fixedDocuments_convertsToDirectoryAnchor() async throws {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? "/"
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.fileManagerClient.urlsForDirectory = { FileManager.default.urls(for: $0, in: $1) }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action을 방출하므로
        // Documents anchor 변환 검증에 집중한다.
        store.exhaustivity = .off

        await store.sendTabContent(.view(.homeSelectionTapped(.fixedDirectory(.documents))))
        await store.receive(\.contentTabs)
        await receiveDirectoryNavigation(store, path: documentsPath)

        XCTAssertEqual(store.state.content.navigation.currentPath, documentsPath)
        XCTAssertEqual(store.state.content.navigation.backHistory.map(\.navigationState), [.home])
        XCTAssertEqual(store.state.content.entryViewLayout.currentPath, documentsPath)
        let tab = try XCTUnwrap(store.state.contentTabs.tabs.first)
        XCTAssertEqual(tab.anchor, .directory(path: documentsPath))
        XCTAssertEqual(tab.page, .directory)
    }

    /// CTM-001-home_selection_page_conversion: 디렉터리 피커 성공 시 active tab anchor가 변환됨
    /// VOY-438 AC2a의 openDirectory 피커 성공 → ContentTabPageAnchor.directory(path:) 변환을 검증한다.
    /// - 검증 내용: homePickerClient.pickDirectory mock이 .selected("/tmp/test") 반환 후 tab.anchor == .directory(path:
    /// "/tmp/test"),
    ///   tab.page == .directory
    /// - 사전 조건: homePickerClient.pickDirectory → .selected("/tmp/test")
    /// - 기대 결과: active tab의 anchor가 피커에서 선택한 경로로 변경되고 page가 directory로 전환됨
    func testHomeSelection_openDirectoryPickerSuccess_convertsAnchor() async throws {
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.homePickerClient.pickDirectory = { .selected("/tmp/test") }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action과
        // HomeSelectionReducer의 picker effect 결과를 방출하므로 최종 anchor 검증에 집중한다.
        store.exhaustivity = .off

        await store.sendTabContent(.view(.homeSelectionTapped(.openDirectory)))
        await store.receive(\.contentTabs)
        await receiveDirectoryNavigation(store, path: "/tmp/test")

        XCTAssertEqual(store.state.content.navigation.currentPath, "/tmp/test")
        XCTAssertEqual(store.state.content.navigation.backHistory.map(\.navigationState), [.home])
        XCTAssertEqual(store.state.content.entryViewLayout.currentPath, "/tmp/test")
        let tab = try XCTUnwrap(store.state.contentTabs.tabs.first)
        XCTAssertEqual(tab.anchor, .directory(path: "/tmp/test"))
        XCTAssertEqual(tab.page, .directory)
    }

    /// CTM-001-home_selection_page_conversion: 디렉터리 피커 취소 시 Home anchor가 유지됨
    /// VOY-438 AC2b의 openDirectory 피커 취소 → no-op을 검증한다.
    /// - 검증 내용: homePickerClient.pickDirectory → .cancelled 반환 후 tab.anchor == .homeDefault
    /// - 사전 조건: homePickerClient.pickDirectory → .cancelled
    /// - 기대 결과: 피커 취소 시 active tab의 anchor와 page가 변경되지 않고 Home 상태를 유지함
    func testHomeSelection_openDirectoryPickerCancel_preservesHome() async throws {
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.homePickerClient.pickDirectory = { .cancelled }
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action을 방출하므로
        // 피커 취소 no-op 검증에 집중한다.
        store.exhaustivity = .off

        await store.sendTabContent(.view(.homeSelectionTapped(.openDirectory)))
        await store.receiveTabContent(\.internal.homeDirectoryPickerFinished)

        let tab = try XCTUnwrap(store.state.contentTabs.tabs.first)
        XCTAssertEqual(tab.anchor, .homeDefault)
        XCTAssertEqual(tab.page, .home)
    }

    /// CTM-001-home_selection_page_conversion: 디렉터리 피커 실패 시 Home anchor가 유지됨
    /// VOY-438 AC2b의 openDirectory 피커 실패 → no-op을 검증한다.
    /// - 검증 내용: homePickerClient.pickDirectory → .failed("error") 반환 후 tab.anchor == .homeDefault
    /// - 사전 조건: homePickerClient.pickDirectory → .failed("error")
    /// - 기대 결과: 피커 실패 시 active tab의 anchor와 page가 변경되지 않고 Home 상태를 유지함
    func testHomeSelection_openDirectoryPickerFailure_preservesHome() async throws {
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.homePickerClient.pickDirectory = { .failed("error") }
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action을 방출하므로
        // 피커 실패 no-op 검증에 집중한다.
        store.exhaustivity = .off

        await store.sendTabContent(.view(.homeSelectionTapped(.openDirectory)))
        await store.receiveTabContent(\.internal.homeDirectoryPickerFinished)

        let tab = try XCTUnwrap(store.state.contentTabs.tabs.first)
        XCTAssertEqual(tab.anchor, .homeDefault)
        XCTAssertEqual(tab.page, .home)
    }

    /// CTM-001-home_selection_page_conversion: hydrated 컬렉션 열기 성공 시 anchor가 .collectionFile로 변환됨
    /// VOY-438 AC3a의 openCollection 피커 성공 → hydration 성공 후 ContentTabPageAnchor.collectionFile(url:) 변환을 검증한다.
    /// - 검증 내용: homePickerClient.pickCollectionFile → .selected(URL) 반환 후 hydrated navigation 적용 뒤 tab.anchor ==
    /// .collectionFile(url:)
    /// - 사전 조건: homePickerClient.pickCollectionFile → .selected(URL(fileURLWithPath: "/tmp/test.voycoll"))
    /// - 기대 결과: active tab의 anchor가 컬렉션 파일 URL로 변경되고 page가 collection으로 전환됨
    func testHomeSelection_openCollectionPickerSuccess_convertsAnchor() async throws {
        let collectionURL = URL(fileURLWithPath: "/tmp/test.voycoll")
        let loadedFile = VoyagerCollectionFile(
            id: "ctm-open-collection",
            name: "test",
            createdAt: .distantPast,
            updatedAt: .distantFuture,
            query: "kind:document",
            scopes: ["/tmp"],
            conditions: [],
            snapshot: CollectionPersistedSnapshot(items: [
                .string("/tmp/document.md"),
            ]),
            snapshotMeta: CollectionSnapshotMeta(
                definitionFingerprint: CollectionSnapshotHydration.definitionFingerprint(file: VoyagerCollectionFile(
                    id: "ctm-open-collection",
                    name: "test",
                    createdAt: .distantPast,
                    updatedAt: .distantFuture,
                    query: "kind:document",
                    scopes: ["/tmp"],
                    conditions: [],
                    snapshot: CollectionPersistedSnapshot(items: [
                        .string("/tmp/document.md"),
                    ]),
                    snapshotMeta: nil,
                    appVersion: nil,
                )),
                capturedAt: Date(timeIntervalSince1970: 1_234_567_890),
                itemCount: 1,
                relevanceRoots: ["/tmp"],
            ),
            appVersion: nil,
        )
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.homePickerClient.pickCollectionFile = { .selected(collectionURL) }
            $0.collectionFileClient.load = { _ in
                VoyagerCollectionFileCompatibilityOwner.makeLoadResult(
                    file: loadedFile,
                    containerFormat: .package,
                    sourceSchemaVersion: CollectionFileSchemaVersion.current,
                    warning: nil,
                    usedDefinitionFallback: false,
                )
            }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.continuousClock = ImmediateClock()
        }
        // 비포괄적: picker/load/open flow가 여러 child action을 방출하므로
        // 최종 anchor 확정 검증에 집중한다.
        store.exhaustivity = .off

        await store.sendTabContent(.view(.homeSelectionTapped(.openCollection)))
        await store.receiveTabContent(\.internal.homeCollectionPickerFinished)
        await store.receive(\.navigation.view.openCollectionFile)
        await store.receive(\.navigation.internal.collectionFileLoaded)
        await store.receiveTabContent(\.internal.applyNavigationState)
        await store.receive(\.contentTabs)

        let tab = try XCTUnwrap(store.state.contentTabs.tabs.first)
        XCTAssertEqual(tab.anchor, .collectionFile(url: collectionURL))
        XCTAssertEqual(tab.page, .collection)
    }

    /// CTM-001-home_selection_page_conversion: 컬렉션 피커 취소 시 Home anchor가 유지됨
    /// VOY-438 AC3b의 openCollection 피커 취소 → no-op을 검증한다.
    /// - 검증 내용: homePickerClient.pickCollectionFile → .cancelled 반환 후 tab.anchor == .homeDefault
    /// - 사전 조건: homePickerClient.pickCollectionFile → .cancelled
    /// - 기대 결과: 피커 취소 시 active tab의 anchor와 page가 변경되지 않고 Home 상태를 유지함
    func testHomeSelection_openCollectionPickerCancel_preservesHome() async throws {
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.homePickerClient.pickCollectionFile = { .cancelled }
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action을 방출하므로
        // 컬렉션 피커 취소 no-op 검증에 집중한다.
        store.exhaustivity = .off

        await store.sendTabContent(.view(.homeSelectionTapped(.openCollection)))
        await store.receiveTabContent(\.internal.homeCollectionPickerFinished)

        let tab = try XCTUnwrap(store.state.contentTabs.tabs.first)
        XCTAssertEqual(tab.anchor, .homeDefault)
        XCTAssertEqual(tab.page, .home)
    }

    /// CTM-001-home_selection_page_conversion: 컬렉션 파일 load 실패 시 Home anchor가 유지됨
    /// 컬렉션 anchor는 파일 open 성공 후 확정되어야 하며, load 실패만으로 tab metadata를 collection으로 바꾸지 않는다.
    /// - 검증 내용: picker는 URL을 반환하지만 collectionFileClient.load 실패 후 tab.anchor == .homeDefault
    /// - 사전 조건: homePickerClient.pickCollectionFile → .selected(URL), collectionFileClient.load throws
    /// - 기대 결과: open 실패 시 active tab의 anchor와 page가 변경되지 않고 Home 상태를 유지함
    func testHomeSelection_openCollectionLoadFailure_preservesHome() async throws {
        enum TestError: Error {
            case loadFailed
        }
        let collectionURL = URL(fileURLWithPath: "/tmp/missing.voycoll")
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.homePickerClient.pickCollectionFile = { .selected(collectionURL) }
            $0.collectionFileClient.load = { _ in throw TestError.loadFailed }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
        }
        // 비포괄적: 실패 경로의 alert/rollback child action보다 tab anchor 보존을 검증한다.
        store.exhaustivity = .off

        await store.sendTabContent(.view(.homeSelectionTapped(.openCollection)))
        await store.receiveTabContent(\.internal.homeCollectionPickerFinished)
        await store.receive(\.navigation.view.openCollectionFile)
        await store.receive(\.navigation.internal.collectionFileLoaded)

        let tab = try XCTUnwrap(store.state.contentTabs.tabs.first)
        XCTAssertEqual(tab.anchor, .homeDefault)
        XCTAssertEqual(tab.page, .home)
    }

    /// CTM-001-home_selection_page_conversion: 컬렉션 검색 실패 시 Home anchor가 유지됨
    /// 컬렉션 anchor는 파일 load 성공만으로 확정하지 않고 검색 성공 후 확정되어야 한다.
    /// - 검증 내용: collection load는 성공하지만 searchClient.search 실패 후 tab.anchor == .homeDefault
    /// - 사전 조건: homePickerClient.pickCollectionFile → .selected(URL), collectionFileClient.load success,
    /// searchClient.search throws
    /// - 기대 결과: 검색 실패 시 active tab의 anchor와 page가 변경되지 않고 Home 상태를 유지함
    func testHomeSelection_openCollectionSearchFailure_preservesHome() async throws {
        enum TestError: Error {
            case searchFailed
        }
        let collectionURL = URL(fileURLWithPath: "/tmp/search-fail.voycoll")
        let loadedFile = VoyagerCollectionFile(
            id: "ctm-open-collection-search-fail",
            name: "search-fail",
            createdAt: .distantPast,
            updatedAt: .distantFuture,
            query: "kind:document",
            scopes: ["/tmp"],
            conditions: [],
            snapshot: nil,
            snapshotMeta: nil,
            appVersion: nil,
        )
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.homePickerClient.pickCollectionFile = { .selected(collectionURL) }
            $0.collectionFileClient.load = { _ in
                VoyagerCollectionFileCompatibilityOwner.makeLoadResult(
                    file: loadedFile,
                    containerFormat: .package,
                    sourceSchemaVersion: CollectionFileSchemaVersion.current,
                    warning: nil,
                    usedDefinitionFallback: false,
                )
            }
            $0.searchClient.search = { _ in throw TestError.searchFailed }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.continuousClock = ImmediateClock()
        }
        // 비포괄적: 검색 실패 alert/rollback 세부 action보다 tab anchor 보존을 검증한다.
        store.exhaustivity = .off

        await store.sendTabContent(.view(.homeSelectionTapped(.openCollection)))
        await store.receiveTabContent(\.internal.homeCollectionPickerFinished)
        await store.receive(\.navigation.view.openCollectionFile)
        await store.receive(\.navigation.internal.collectionFileLoaded)
        await store.receiveTabContent(\.delegate.composerCollectionSearchFailed)

        let tab = try XCTUnwrap(store.state.contentTabs.tabs.first)
        XCTAssertEqual(tab.anchor, .homeDefault)
        XCTAssertEqual(tab.page, .home)
    }

    /// CTM-001-home_selection_page_conversion: 잘못된 AI Chat session 문자열은 Home을 유지함
    /// Home placeholder는 엄격한 UUID 파싱에 성공한 경우에만 Content AI Chat으로 전달되는지 검증한다.
    /// - 검증 내용: homeAiChatClient.createSession → invalid UUID 반환 후 anchor/page 불변
    /// - 사전 조건: homeAiChatClient.createSession → .selected("session-123")
    /// - 기대 결과: fallback UUID를 만들지 않고 active tab은 Home 상태를 유지함
    func testHomeSelection_startAiChatInvalidSessionID_preservesHome() async throws {
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.homeAiChatClient.createSession = { .selected("session-123") }
            $0.aiConnectionsFileClient.load = { .empty() }
            $0.aiChatSessionPersistenceClient.loadSession = { _ in nil }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action과
        // HomeSelectionReducer의 session 생성 effect 결과를 방출하므로 최종 anchor 검증에 집중한다.
        store.exhaustivity = .off

        await store.sendTabContent(.view(.homeSelectionTapped(.startAiChat)))

        let tab = try XCTUnwrap(store.state.contentTabs.tabs.first)
        XCTAssertEqual(tab.anchor, .homeDefault)
        XCTAssertEqual(tab.page, .home)
    }

    /// CTM-001-home_selection_page_conversion: Home New Chat은 placeholder에 seed를 적용하고 첫 제출까지 저장하지 않음
    /// VOY-638에서 Home same-tab 전환이 explicit-ID transient seed pipeline을 사용하는지 검증한다.
    /// - 검증 내용: provider catalog 완료 후에도 save 0회, anchor/session/transient ID 일치, 첫 submit request-start save 1회
    /// - 사전 조건: Home session placeholder, 유효한 OpenAI 기본 model/thinking, 지연된 deterministic model-list 응답
    /// - 기대 결과: seed가 placeholder draft에 적용되고 첫 submit이 같은 placeholder ID snapshot을 정확히 한 번 저장함
    func testHomeSelection_startAiChat_appliesDefaultSeedAndPersistsOnlyFinalSession() async throws {
        let fixture = CTM001HomeNewChatFixture()
        let store = fixture.makeStore()

        await store.sendTabContent(.view(.homeSelectionTapped(.startAiChat)))
        await store.receive(\.contentTabs)
        await store.receiveTabContent(\.aiChat.providerConnectionsUpdated)
        await fixture.modelLoadGate.waitUntilLoading()
        await store.receive(\.internal.homeAiChatNewChatSeedRequested)
        await store.receive(\.internal.aiChatNewChatDefaultsLoaded)

        XCTAssertTrue(fixture.savedSnapshots.value.isEmpty, "catalog 완료 전에는 placeholder나 최종 세션을 저장하지 않아야 함")
        XCTAssertTrue(fixture.loadedSessionIDs.value.isEmpty, "fresh placeholder는 restore/load 대상이 아니어야 함")

        await fixture.modelLoadGate.resume(returning: [fixture.defaultModel])
        await store.receiveTabContent(\.aiChat.modelListLoaded)
        await store.skipReceivedActions()

        let placeholderID = try XCTUnwrap(UUID(uuidString: fixture.placeholderSessionID))
        XCTAssertTrue(fixture.savedSnapshots.value.isEmpty, "seed 준비만으로 Home placeholder를 저장하면 안 됨")
        XCTAssertEqual(store.state.content.aiChat.sessionID?.rawValue, placeholderID)
        XCTAssertEqual(store.state.content.aiChat.preparedTransientSessionID?.rawValue, placeholderID)
        XCTAssertNil(store.state.content.aiChat.emptyDraftSessionID)
        XCTAssertEqual(store.state.content.aiChat.selectedModelHandle, fixture.defaultModel.id)
        XCTAssertEqual(store.state.content.aiChat.selectedThinking, .effort(.high))
        XCTAssertTrue(fixture.loadedSessionIDs.value.isEmpty)
        XCTAssertEqual(
            store.state.contentTabs.tabs.first?.anchor,
            .aiChat(sessionID: fixture.placeholderSessionID),
        )

        await store.sendTabContent(.aiChat(.draftTextChanged("Home question")))
        await store.sendTabContent(.aiChat(.submitTapped))
        await store.receiveTabContent(\.aiChat.requestContextResolved)
        await store.receiveTabContent(\.aiChat.sessionSnapshotUpdated)
        await store.finish()

        XCTAssertEqual(fixture.savedSnapshots.value.count, 1)
        let savedSnapshot = try XCTUnwrap(fixture.savedSnapshots.value.first)
        XCTAssertEqual(savedSnapshot.sessionID.rawValue, placeholderID)
        XCTAssertEqual(savedSnapshot.model, fixture.defaultModel.id)
        XCTAssertEqual(savedSnapshot.selectedThinking, .effort(.high))
    }

    /// CTM-001-home_selection_page_conversion: pending Home seed는 사용자 attachment 변경을 덮어쓰지 않음
    /// 지연된 catalog completion이 Home placeholder에 추가된 사용자 입력 provenance를 무효화하는지 검증한다.
    /// - 검증 내용: seed pending 중 attachment 추가 후 late completion 무시, save 0회
    /// - 사전 조건: valid Home placeholder와 지연된 model catalog가 있다.
    /// - 기대 결과: attachment와 placeholder identity가 유지되고 seed preparation/persistence는 실행되지 않음
    func testHomeSelection_pendingSeedIgnoresLateCompletionAfterAttachmentMutation() async throws {
        let fixture = CTM001HomeNewChatFixture()
        let store = fixture.makeStore()

        await store.sendTabContent(.view(.homeSelectionTapped(.startAiChat)))
        await store.receive(\.contentTabs)
        await store.receiveTabContent(\.aiChat.providerConnectionsUpdated)
        await fixture.modelLoadGate.waitUntilLoading()
        await store.receive(\.internal.homeAiChatNewChatSeedRequested)
        await store.receive(\.internal.aiChatNewChatDefaultsLoaded)

        let placeholderID = try XCTUnwrap(UUID(uuidString: fixture.placeholderSessionID))
        let attachmentURL = URL(fileURLWithPath: "/tmp/home-pending.txt")
        await store.sendTabContent(.aiChat(.attachmentPickerSelection(
            AiChatSessionID(rawValue: placeholderID),
            [attachmentURL],
        )))
        XCTAssertEqual(store.state.content.aiChat.addedAttachments.count, 1)

        await fixture.modelLoadGate.resume(returning: [fixture.defaultModel])
        await store.receiveTabContent(\.aiChat.modelListLoaded)

        XCTAssertEqual(store.state.content.aiChat.sessionID?.rawValue, placeholderID)
        XCTAssertEqual(store.state.content.aiChat.addedAttachments.count, 1)
        XCTAssertNil(store.state.content.aiChat.preparedTransientSessionID)
        XCTAssertNil(store.state.content.aiChat.selectedModelHandle)
        XCTAssertTrue(fixture.savedSnapshots.value.isEmpty)
    }

    /// CTM-001-home_selection_page_conversion: AI Chat 세션 생성 실패 시 Home anchor가 유지됨
    /// VOY-438 AC4b의 startAiChat 실패 → no-op을 검증한다.
    /// - 검증 내용: homeAiChatClient.createSession → .failed("error") 반환 후 tab.anchor == .homeDefault
    /// - 사전 조건: homeAiChatClient.createSession → .failed("error")
    /// - 기대 결과: 세션 생성 실패 시 active tab의 anchor와 page가 변경되지 않고 Home 상태를 유지함
    func testHomeSelection_startAiChatFailure_preservesHome() async throws {
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.homeAiChatClient.createSession = { .failed("error") }
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action을 방출하므로
        // 세션 생성 실패 no-op 검증에 집중한다.
        store.exhaustivity = .off

        await store.sendTabContent(.view(.homeSelectionTapped(.startAiChat)))
        await store.receiveTabContent(\.internal.homeAiChatSessionCreated)

        let tab = try XCTUnwrap(store.state.contentTabs.tabs.first)
        XCTAssertEqual(tab.anchor, .homeDefault)
        XCTAssertEqual(tab.page, .home)
    }

    /// CTM-001-home_selection_page_conversion: non-Home active tab에서 Home 선택은 no-op
    /// 사용자가 Directory tab에서 Home 선택 항목을 보낼 수 없지만(non-Home은 HomePageView 미표시),
    /// 안전장치로 anchor 변경이 발생하지 않음을 검증한다.
    /// - 검증 내용: active tab이 Directory("/tmp")인 상태에서 Desktop 선택 후 anchor, page 불변
    /// - 사전 조건: active tab anchor == .directory(path: "/tmp"), page == .directory
    /// - 기대 결과: routing guard가 active tab이 .homeDefault가 아님을 감지하여 no-op 처리
    func testHomeSelection_whenActiveTabIsNotHome_isNoOp() async throws {
        var state = FileManagerFeature.State()
        state.contentTabs.tabs[0].anchor = .directory(path: "/tmp")
        state.contentTabs.tabs[0].page = .directory
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.fileManagerClient.urlsForDirectory = { FileManager.default.urls(for: $0, in: $1) }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action을 방출하므로
        // routing guard no-op 검증에 집중한다.
        store.exhaustivity = .off

        let beforeCount = store.state.contentTabs.tabs.count
        let beforeActiveID = store.state.contentTabs.activeTabID

        await store.sendTabContent(.view(.homeSelectionTapped(.fixedDirectory(.desktop))))

        XCTAssertEqual(store.state.contentTabs.tabs.count, beforeCount)
        XCTAssertEqual(store.state.contentTabs.activeTabID, beforeActiveID)
        let tab = try XCTUnwrap(store.state.contentTabs.tabs.first)
        XCTAssertEqual(tab.anchor, .directory(path: "/tmp"))
        XCTAssertEqual(tab.page, .directory)
    }

    /// CTM-001-home_selection_page_conversion: activeTabID가 nil이면 Home 선택이 no-op임
    /// VOY-438 AC5의 edge case를 검증한다. activeTabID가 없으면 FileManagerWindowCommandRoutingReducer가
    /// delegate action을 무시하고 .none을 반환함.
    /// - 검증 내용: activeTabID == nil인 상태에서 Desktop 선택 후 tabs, anchor 불변
    /// - 사전 조건: contentTabs.activeTabID == nil, anchor == .homeDefault
    /// - 기대 결과: state가 전혀 변경되지 않음
    func testHomeSelection_whenNoActiveTabID_isNoOp() async throws {
        var state = FileManagerFeature.State()
        state.contentTabs.activeTabID = nil
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        // 비포괄적: FileManagerFeature.onAppear가 여러 child action을 방출하므로
        // activeTabID nil no-op 검증에 집중한다.
        store.exhaustivity = .off

        let beforeCount = store.state.contentTabs.tabs.count

        await store.send(.content(.view(.homeSelectionTapped(.fixedDirectory(.desktop)))))

        XCTAssertEqual(store.state.contentTabs.tabs.count, beforeCount)
        let tab = try XCTUnwrap(store.state.contentTabs.tabs.first)
        XCTAssertEqual(tab.anchor, .homeDefault)
        XCTAssertEqual(tab.page, .home)
    }

    // MARK: - CTM-001-home_selection_page_conversion: ContentPane AI Chat setup

    /// Home Start AI Chat 선택 시 ContentPane AI Chat이 sessionID로 초기화되고 Inspector Chat은 닫힘
    /// VOY-509 Task 2: 홈 화면 Start AI Chat 버튼 탭 시 ContentPane AI Chat state가 .setup과 .providerConnectionsUpdated를
    /// 수신하고, 기존 Inspector Chat은 닫히는지 검증한다.
    /// - 검증 내용: tab count 불변, active tab anchor/page가 .aiChat(sessionID:)로 전환,
    ///   content.aiChat.restoreSessionID가 sessionID로 설정됨,
    ///   열린 Inspector Chat을 닫고 inspector.aiChat 세션 상태는 오염시키지 않음
    /// - 사전 조건: homeAiChatClient.createSession → .selected("session-123"),
    ///   aiConnectionsFileClient.load → .empty()
    /// - 기대 결과: 새로운 tab 생성 없이 active tab이 AI Chat anchor로 변환되고 ContentPane AI Chat이 초기화되며 Inspector Chat은 닫힘
    func testHomeSelection_startAiChat_initializesContentPaneAiChat() async throws {
        let sessionID = "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
        var initialState = FileManagerFeature.State()
        initialState.inspector.inspectorVisible = true
        initialState.inspector.inspectorPaneExists = true
        initialState.inspector.activeMode = .chat

        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.homeAiChatClient.createSession = { .selected(sessionID) }
            $0.aiConnectionsFileClient.load = { .empty() }
            $0.aiChatSessionPersistenceClient.loadSession = { _ in nil }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
        }
        // 비포괄적: FileManagerFeature.onAppear 및 다중 async effect가 여러 action을 방출하므로
        // ContentPane AI Chat 초기화 검증에 집중한다.
        store.exhaustivity = .off

        let initialTabCount = store.state.contentTabs.tabs.count

        await store.sendTabContent(.view(.homeSelectionTapped(.startAiChat)))
        // Home AI Chat 전환은 same-tab handoff에서도 Inspector Chat을 먼저 닫고,
        // active tab anchor와 navigation route를 고정한 뒤 provider load만 tab-scoped async로 처리한다.
        await store.receive { action in
            guard case .inspector(.closeChat) = action else { return false }
            return true
        } assert: { state in
            state.inspector.inspectorVisible = false
        }
        await store.receive { action in
            guard case let .contentTabs(.updateActivePageAnchor(_, .aiChat(receivedSessionID))) = action else {
                return false
            }
            return receivedSessionID == sessionID
        }
        await store.receive { action in
            guard case let .internal(.aiChatTabTitleUpdated(receivedSessionID, title)) = action else {
                return false
            }
            return receivedSessionID.rawValue.uuidString == sessionID && title == "New Chat"
        }
        await store.receive { action in
            guard case let .navigation(.view(.showAiChat(receivedSessionID))) = action else { return false }
            return receivedSessionID == sessionID
        }
        await store.receive { action in
            guard case .tabContent(_, .aiChat(.setup)) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case let .navigation(.internal(.performShowAiChat(receivedSessionID))) = action else {
                return false
            }
            return receivedSessionID == sessionID
        }
        await store.receive { action in
            guard case let .navigation(.delegate(.navigateToState(.aiChat(receivedSessionID)))) = action
            else { return false }
            return receivedSessionID == sessionID
        }
        await store.receive { action in
            guard case let .tabContent(_, .internal(.applyNavigationState(.aiChat(receivedSessionID)))) = action
            else { return false }
            return receivedSessionID == sessionID
        }
        await store.receive { action in
            guard case .tabContent(_, .aiChat(.providerConnectionsUpdated)) = action else { return false }
            return true
        }

        let expectedSessionUUID = AiChatSessionID(rawValue: UUID(uuidString: sessionID) ?? UUID())

        // Tab count invariance — no new tab created
        XCTAssertEqual(store.state.contentTabs.tabs.count, initialTabCount, "tab count must not change")

        // Active tab anchor/page converted to .aiChat
        let tab = try XCTUnwrap(store.state.contentTabs.tabs.first)
        XCTAssertEqual(tab.anchor, .aiChat(sessionID: sessionID))
        XCTAssertEqual(tab.page, .aiChat)
        XCTAssertEqual(tab.title, "New Chat")
        XCTAssertEqual(store.state.sidebar.contentTabSidebarItems.first?.title, "New Chat")

        // ContentPane AI Chat은 .setup 수신 후 즉시 채팅 모드로 열리고 navigation history에 기록된다
        XCTAssertEqual(store.state.content.navigation.navigationState, .aiChat(sessionID))
        XCTAssertEqual(store.state.content.navigation.backHistory.map(\.navigationState), [.home])
        XCTAssertTrue(store.state.content.navigation.canGoBack)
        XCTAssertFalse(store.state.content.navigation.canGoForward)
        XCTAssertEqual(
            store.state.content.aiChat.mode,
            .chat,
            "Start AI Chat must open the chat input screen before history",
        )
        XCTAssertEqual(
            store.state.content.aiChat.sessionID,
            expectedSessionUUID,
            "ContentPane aiChat must keep the fresh Start AI Chat sessionID",
        )
        XCTAssertNil(
            store.state.content.aiChat.restoreSessionID,
            "Fresh ContentPane AI Chat must skip restore to avoid first-frame layout jump",
        )
        XCTAssertEqual(
            store.state.content.aiChat.sessionStatus,
            .idle,
            "Fresh ContentPane AI Chat must remain idle instead of entering restore",
        )

        // Inspector Chat은 ContentPane AI Chat과 동시에 남지 않도록 닫힌다.
        XCTAssertFalse(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.activeMode, .chat)
        XCTAssertNil(
            store.state.inspector.aiChat.restoreSessionID,
            "Inspector aiChat restoreSessionID must remain nil",
        )
        XCTAssertNil(
            store.state.inspector.aiChat.sessionID,
            "Inspector aiChat sessionID must remain nil",
        )
    }

    // MARK: - CTM-001-external_tab_reservation

    /// CTM-001-external_tab_reservation: 외부 file reservation은 caller가 제공한 identity와 pending selection을 사용한다.
    /// 시스템 open 배치가 일반 파일을 기존 window의 새 Content Tab으로 예약하는 계약의 RED 기준을 검증한다.
    /// - 검증 내용: 외부 예약 후 active tab ID와 active content pending selection이 caller 입력과 일치한다.
    /// - 사전 조건: seed Directory tab이 active이고 caller가 tab ID, parent Directory anchor, file selection ID를 제공한다.
    /// - 기대 결과: 새 tab은 caller ID로 active가 되고 파일 selection은 첫 load 전에 content snapshot에 존재한다.
    func testExternalTabReservation_usesCallerIdentityAndPendingSelection() async throws {
        let sandbox = try FileManagerFixtureSandbox.copyingFileWithDirectorySymlink(
            from: "fixtures/fixtures/texts/plain/11.txt",
        )
        defer { sandbox.cleanup() }
        let callerTabID = ContentTabID(rawValue: "external-file-tab")
        let pendingSelection = sandbox.fileURL.path
        let store = TestStore(initialState: FileManagerWindowState.makeInitial(path: "/seed")) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // store.exhaustivity = .off: 기존 open 경로의 내부 handoff보다 결여된 external reservation 계약 검증에 집중한다.
        store.exhaustivity = .off

        await store.send(.reserveExternalContentTabs([
            ExternalContentTabReservation(
                id: callerTabID,
                anchor: .directory(path: sandbox.fileURL.deletingLastPathComponent().path),
                pendingSelectEntryID: pendingSelection,
            ),
        ]))
        await store.receive(\.contentTabs.setCurrent, callerTabID)

        XCTAssertEqual(store.state.contentTabs.activeTabID, callerTabID)
        XCTAssertEqual(store.state.content.pendingSelectEntryID, pendingSelection)
        XCTAssertEqual(store.state.tabContentStates[callerTabID]?.pendingSelectEntryID, pendingSelection)
    }

    /// CTM-001-external_tab_reservation: 기존 window에 ordered reservation을 원자 적용한다.
    /// active Directory와 pinned inactive tab이 있는 window에 Directory, Collection, regular-file tab을 배치한다.
    /// - 검증 내용: 기존 active snapshot 저장, ordered append, active/previous ID, content/inspector snapshot 원자 갱신이다.
    /// - 사전 조건: 기존 active content/inspector와 pinned inactive metadata가 있고 Collection reservation은 inactive가 된다.
    /// - 기대 결과: 기존 metadata는 유지되고 모든 snapshot이 생성되며 regular-file pending selection은 active load 전에 존재한다.
    func testExternalTabReservation_appliesOrderedSnapshotsAtomically() async throws {
        let scenario = try ExternalTabReservationTestFixture.makeAtomicScenario()
        defer { scenario.sandbox.cleanup() }
        let store = TestStore(initialState: scenario.initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryLoadingClient.loadItems = { _, _ in [] }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { $0.finish() }
            }
        }
        // store.exhaustivity = .off: append 이후 canonical handoff의 navigation child action은 별도 owner가 검증한다.
        store.exhaustivity = .off

        await store.send(.reserveExternalContentTabs(scenario.reservations))
        await store.receive(\.contentTabs.setCurrent, scenario.fileID)
        await store.skipReceivedActions()
        await store.finish()

        scenario.assertResult(store.state)
    }

    /// CTM-001-external_tab_reservation: 기존 Directory load를 취소한 뒤 예약 Directory를 한 번 load한다.
    /// external reservation activation이 일반 tab handoff cancellation과 reload 경로를 재사용하는지 검증한다.
    /// - 검증 내용: 이전 load cancellation 1회와 destination loadItems 1회다.
    /// - 사전 조건: seed Directory load가 대기 중이고 새 Directory reservation 하나가 append된다.
    /// - 기대 결과: setCurrent handoff가 이전 load를 취소하고 새 경로만 한 번 load한다.
    func testExternalTabReservation_cancelsOutgoingLoadBeforeLoadingDestination() async {
        let tabID = ContentTabID(rawValue: "external-directory-cancellation")
        let oldLoadStarted = expectation(description: "outgoing load started")
        let oldLoadCancelled = expectation(description: "outgoing load cancelled")
        let oldLoadGate = AsyncStream<Void>.makeStream()
        let cancellationCount = LockIsolated(0)
        let loadPaths = LockIsolated<[String]>([])
        let store = TestStore(initialState: FileManagerWindowState.makeInitial(path: "/seed")) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryLoadingClient.loadItems = { url, _ in
                loadPaths.withValue { $0.append(url.path) }
                guard url.path == "/seed" else { return [] }
                oldLoadStarted.fulfill()
                return await withTaskCancellationHandler {
                    for await _ in oldLoadGate.stream {}
                    return []
                } onCancel: {
                    cancellationCount.withValue { $0 += 1 }
                    oldLoadGate.continuation.finish()
                    oldLoadCancelled.fulfill()
                }
            }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { $0.finish() }
            }
        }
        // store.exhaustivity = .off: cancellation과 경로별 load 호출 외 navigation child action은 별도 owner가 검증한다.
        store.exhaustivity = .off

        await store.sendTabContent(.entryOperations(.loading(
            .loadItems(path: "/seed", showHidden: false),
        )))
        await fulfillment(of: [oldLoadStarted], timeout: 1)
        await store.send(.reserveExternalContentTabs([
            .init(id: tabID, anchor: .directory(path: "/external")),
        ]))
        await store.receive(\.contentTabs.setCurrent, tabID)
        await fulfillment(of: [oldLoadCancelled], timeout: 1)
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertEqual(cancellationCount.value, 1)
        XCTAssertEqual(loadPaths.value, ["/seed", "/external"])
    }

    /// CTM-001-external_tab_reservation: 비활성 탭 reload는 활성 탭의 진행 중 load를 취소하지 않는다.
    /// 탭별 loading cancellation owner가 같은 window 안의 독립 content session을 격리하는지 검증한다.
    /// - 검증 내용: B load 대기 중 inactive A operation completion이 A reload를 시작해도 B cancellation은 0회다.
    /// - 사전 조건: 같은 window의 A와 B Directory tab이 있고 B load effect가 continuation gate에서 대기 중이다.
    /// - 기대 결과: A reload가 시작되며 B load는 독립적으로 계속 실행된다.
    func testInactiveTabReloadDoesNotCancelActiveTabLoad() async throws {
        let sandbox = try ExternalTabReservationTestFixture.copyingPlainTextFixture()
        defer { sandbox.cleanup() }
        let tabB = ContentTabID(rawValue: "B")
        let initialState = FileManagerWindowState.makeInitial(path: "/a")
        let tabA = try XCTUnwrap(initialState.contentTabs.activeTabID)

        let activeLoadStarted = expectation(description: "active B load started")
        let inactiveReloadStarted = expectation(description: "inactive A reload started")
        let activeLoadGate = AsyncStream<Void>.makeStream()
        let activeLoadCancellationCount = LockIsolated(0)
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryLoadingClient.loadItems = { url, _ in
                switch url.path {
                case "/b":
                    activeLoadStarted.fulfill()
                    return await withTaskCancellationHandler {
                        for await _ in activeLoadGate.stream {}
                        return []
                    } onCancel: {
                        activeLoadCancellationCount.withValue { $0 += 1 }
                        activeLoadGate.continuation.finish()
                    }
                case "/a":
                    inactiveReloadStarted.fulfill()
                    return []
                default:
                    return []
                }
            }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { $0.finish() }
            }
        }
        // store.exhaustivity = .off: navigation 부수 action보다 탭별 loading cancellation 격리를 검증한다.
        store.exhaustivity = .off

        await store.send(.reserveExternalContentTabs([
            .init(id: tabB, anchor: .directory(path: "/b")),
        ]))
        await store.receive(\.contentTabs.setCurrent, tabB)
        await fulfillment(of: [activeLoadStarted], timeout: 1)

        await store.send(ExternalTabReservationTestFixture.inactiveReloadAction(
            tabID: tabA,
            operationPath: sandbox.fileURL.path,
        ))
        await fulfillment(of: [inactiveReloadStarted], timeout: 1)

        XCTAssertEqual(activeLoadCancellationCount.value, 0)
        activeLoadGate.continuation.finish()
        await store.skipReceivedActions()
        await store.finish()
    }

    /// CTM-001-external_tab_reservation: Collection reservation은 canonical open 경로를 정확히 한 번 사용한다.
    /// Directory reload와 Collection open이 중복 실행되지 않는 handoff 분기를 검증한다.
    /// - 검증 내용: openCollectionFile load 1회와 directory loadItems 0회다.
    /// - 사전 조건: seed Directory가 active이고 Collection file reservation 하나가 append된다.
    /// - 기대 결과: setCurrent 후 Collection file open만 한 번 실행된다.
    func testExternalTabReservation_opensCollectionExactlyOnceWithoutDirectoryLoad() async {
        enum TestError: Error {
            case loadFailed
        }
        let tabID = ContentTabID(rawValue: "external-collection-open")
        let collectionURL = URL(fileURLWithPath: "/tmp/external-once.voycoll")
        let openedURLs = LockIsolated<[URL]>([])
        let directoryLoads = LockIsolated(0)
        let store = TestStore(initialState: FileManagerWindowState.makeInitial(path: "/seed")) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.collectionFileClient.load = { url in
                openedURLs.withValue { $0.append(url) }
                throw TestError.loadFailed
            }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in }
            $0.uuid = .incrementing
            $0.entryLoadingClient.loadItems = { _, _ in
                directoryLoads.withValue { $0 += 1 }
                return []
            }
        }
        // store.exhaustivity = .off: 실패 alert 세부 action보다 reservation의 canonical Collection open 횟수를 검증한다.
        store.exhaustivity = .off

        await store.send(.reserveExternalContentTabs([
            .init(id: tabID, anchor: .collectionFile(url: collectionURL)),
        ]))
        await store.receive(\.contentTabs.setCurrent, tabID)
        await store.receive(\.navigation.view.openCollectionFile, collectionURL)
        await store.receive(\.navigation.internal.collectionFileLoaded)
        await store.finish()

        XCTAssertEqual(openedURLs.value, [collectionURL])
        XCTAssertEqual(directoryLoads.value, 0)
    }

    /// CTM-001-external_tab_reservation: explicit Collection resync는 active Directory를 다시 load하지 않는다.
    /// live window onAppear가 이미 적용한 Directory navigation을 후속 resync가 중복 실행하지 않는지 검증한다.
    /// - 검증 내용: package-owned resync action 이후 directory loadItems 호출 0회다.
    /// - 사전 조건: Home 없는 external window에서 Directory reservation이 active다.
    /// - 기대 결과: Collection 전용 resync가 Directory navigation을 변경하거나 reload하지 않는다.
    func testExternalTabReservation_collectionResyncSkipsActiveDirectory() async throws {
        let windowID = UUID()
        let tabID = ContentTabID(rawValue: "external-directory-resync")
        let initialState = try XCTUnwrap(FileManagerWindowState.makeExternalInitial(
            reservations: [.init(id: tabID, anchor: .directory(path: "/external"))],
            windowID: windowID,
        ))
        let directoryLoads = LockIsolated(0)
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryLoadingClient.loadItems = { _, _ in
                directoryLoads.withValue { $0 += 1 }
                return []
            }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { $0.finish() }
            }
        }
        // store.exhaustivity = .off: child navigation action보다 Collection resync의 Directory no-op 경계를 검증한다.
        store.exhaustivity = .off

        await store.send(.resyncActiveCollectionNavigation)

        XCTAssertEqual(directoryLoads.value, 0)
    }

    /// CTM-001-external_tab_reservation: invalid reservation set은 전체를 fail-closed 처리한다.
    /// duplicate ID, capacity 초과, external-incompatible anchor가 기존 window를 부분 변경하지 않는지 검증한다.
    /// - 검증 내용: 각 invalid batch 처리 후 FileManagerWindowState 전체 equality가 유지된다.
    /// - 사전 조건: 기존 Directory window와 duplicate/capacity/home/Collection-pending invalid 입력이다.
    /// - 기대 결과: tabs, active/previous IDs, content, tab/inspector snapshots mutation이 모두 0회다.
    func testExternalTabReservation_invalidSetsDoNotMutateState() async {
        let initialState = FileManagerWindowState.makeInitial(path: "/seed")
        let existingID = initialState.contentTabs.activeTabID ?? ContentTabID(rawValue: "missing-active")
        let invalidSets = ExternalTabReservationTestFixture.makeInvalidSets(existingID: existingID)
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        }

        for reservations in invalidSets {
            await store.send(.reserveExternalContentTabs(reservations))
            XCTAssertEqual(store.state, initialState)
        }
        XCTAssertEqual(ContentTabConstants.maxTabs, 20)
    }

    /// CTM-001-external_tab_reservation: pending tab-close 중 external reservation은 fail-closed 처리된다.
    /// 미저장 Collection close transaction이 진행 중일 때 active content 교체를 막는 window invariant를 검증한다.
    /// - 검증 내용: valid reservation action 이후에도 전체 FileManagerWindowState가 동일하다.
    /// - 사전 조건: active Directory tab을 대상으로 pending close transaction이 설정되어 있다.
    /// - 기대 결과: reservation append와 active/content/snapshot mutation이 모두 0회다.
    func testExternalTabReservation_pendingCloseDoesNotMutateState() async throws {
        var initialState = FileManagerWindowState.makeInitial(path: "/seed")
        let activeID = try XCTUnwrap(initialState.contentTabs.activeTabID)
        initialState.pendingContentTabClose = PendingContentTabClose(
            tabID: activeID,
            previousActiveTabID: nil,
            previousActiveContent: nil,
            targetContent: initialState.content,
            previousActiveInspector: nil,
            targetInspector: initialState.inspector,
        )
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        }

        await store.send(.reserveExternalContentTabs([
            ExternalContentTabReservation(
                id: ContentTabID(rawValue: "blocked-by-pending-close"),
                anchor: .directory(path: "/blocked"),
            ),
        ]))
        XCTAssertEqual(store.state, initialState)
    }

    /// CTM-001-external_tab_reservation: external initial factory는 Home 없이 reservation만으로 window state를 만든다.
    /// overflow window가 bootstrap Home을 만들지 않고 첫 reservation부터 deterministic tab state를 소유하는지 검증한다.
    /// - 검증 내용: ordered tab IDs, active/previous ID, per-tab content/inspector snapshot과 Home 부재다.
    /// - 사전 조건: Directory regular-file reservation과 Collection reservation 두 개다.
    /// - 기대 결과: 정확히 두 reservation tab만 존재하고 마지막 Collection이 active이며 load effect 없이 snapshot만 생성된다.
    func testExternalTabReservation_makeInitialContainsReservationsWithoutHome() throws {
        let sandbox = try FileManagerFixtureSandbox.copyingFileWithDirectorySymlink(
            from: "fixtures/fixtures/texts/plain/11.txt",
        )
        defer { sandbox.cleanup() }
        let fileID = ContentTabID(rawValue: "overflow-file")
        let collectionID = ContentTabID(rawValue: "overflow-collection")
        let collectionURL = URL(fileURLWithPath: "/tmp/overflow.voycoll")
        let state = try XCTUnwrap(FileManagerWindowState.makeExternalInitial(
            reservations: [
                ExternalContentTabReservation(
                    id: fileID,
                    anchor: .directory(path: sandbox.fileURL.deletingLastPathComponent().path),
                    pendingSelectEntryID: sandbox.fileURL.path,
                ),
                ExternalContentTabReservation(id: collectionID, anchor: .collectionFile(url: collectionURL)),
            ],
        ))

        XCTAssertEqual(state.contentTabs.tabs.map(\.id), [fileID, collectionID])
        XCTAssertFalse(state.contentTabs.tabs.contains(where: { $0.anchor == .homeDefault }))
        XCTAssertEqual(state.contentTabs.activeTabID, collectionID)
        XCTAssertEqual(state.contentTabs.previousActiveTabID, fileID)
        XCTAssertEqual(state.tabContentStates[fileID]?.pendingSelectEntryID, sandbox.fileURL.path)
        XCTAssertEqual(state.content, state.tabContentStates[collectionID])
        XCTAssertEqual(Set(state.tabContentStates.keys), Set([fileID, collectionID]))
        XCTAssertEqual(Set(state.tabInspectorStates.keys), Set([fileID, collectionID]))
        XCTAssertNil(FileManagerWindowState.makeExternalInitial(reservations: []))
    }
}

private enum ExternalTabReservationTestFixture {
    struct AtomicScenario {
        let initialState: FileManagerWindowState
        let reservations: [ExternalContentTabReservation]
        let originalActiveID: ContentTabID
        let pinnedID: ContentTabID
        let pinnedTab: ContentTabItem
        let pinnedContent: FileManagerContentState
        let pinnedRecord: ContentTabPinnedRecord
        let directoryID: ContentTabID
        let collectionID: ContentTabID
        let fileID: ContentTabID
        let collectionURL: URL
        let pendingSelection: String
        let sandbox: FileManagerFixtureSandbox
        let expectedOriginalContent: FileManagerContentState
        let expectedOriginalInspector: FileManagerInspectorFeature.State

        func assertResult(_ state: FileManagerWindowState) {
            XCTAssertEqual(
                state.contentTabs.tabs.map(\.id),
                [pinnedID, originalActiveID, directoryID, collectionID, fileID],
            )
            XCTAssertEqual(state.contentTabs.activeTabID, fileID)
            XCTAssertEqual(state.contentTabs.previousActiveTabID, originalActiveID)
            let savedOriginalContent = state.tabContentStates[originalActiveID]
            XCTAssertEqual(savedOriginalContent?.navigation, expectedOriginalContent.navigation)
            XCTAssertEqual(savedOriginalContent?.pendingSelectEntryID, expectedOriginalContent.pendingSelectEntryID)
            XCTAssertEqual(savedOriginalContent?.entryViewLayout.showHiddenFiles, true)
            XCTAssertEqual(savedOriginalContent?.entryViewLayout.gridIconSize, 73)
            XCTAssertEqual(state.tabInspectorStates[originalActiveID], expectedOriginalInspector)
            XCTAssertEqual(state.contentTabs.tabs[id: pinnedID], pinnedTab)
            XCTAssertEqual(state.contentTabs.pinnedRecords[pinnedID], pinnedRecord)
            XCTAssertEqual(state.tabContentStates[pinnedID], pinnedContent)
            XCTAssertEqual(state.tabContentStates[fileID]?.pendingSelectEntryID, pendingSelection)
            XCTAssertEqual(state.content.pendingSelectEntryID, pendingSelection)
            XCTAssertEqual(state.content.navigation.currentPath, sandbox.fileURL.deletingLastPathComponent().path)
            XCTAssertNotNil(state.tabInspectorStates[directoryID])
            XCTAssertNotNil(state.tabInspectorStates[collectionID])
            XCTAssertNotNil(state.tabInspectorStates[fileID])
            for reservation in reservations {
                XCTAssertTrue(state.tabContentStates[reservation.id]?.entryViewLayout.showHiddenFiles ?? false)
                XCTAssertEqual(state.tabContentStates[reservation.id]?.entryViewLayout.gridIconSize, 73)
            }
            guard case let .collection(navigation) = state.tabContentStates[collectionID]?.navigation.navigationState
            else {
                return XCTFail("inactive Collection reservation must own an effect-free collection snapshot")
            }
            XCTAssertEqual(navigation.kind, .file(url: collectionURL, name: "ordered"))
        }
    }

    private struct PinnedState {
        let id: ContentTabID
        let tab: ContentTabItem
        let content: FileManagerContentState
        let record: ContentTabPinnedRecord
    }

    static func copyingPlainTextFixture() throws -> FileManagerFixtureSandbox {
        try FileManagerFixtureSandbox.copyingFileWithDirectorySymlink(
            from: "fixtures/fixtures/texts/plain/11.txt",
        )
    }

    static func inactiveReloadAction(tabID: ContentTabID, operationPath: String) -> FileManagerWindowAction {
        .tabContent(
            tabID: tabID,
            action: .entryOperations(.lifecycle(.operationFinished(
                operationPath,
                .rename,
                .success(()),
            ))),
        )
    }

    static func makeInvalidSets(existingID: ContentTabID) -> [[ExternalContentTabReservation]] {
        [
            [ExternalContentTabReservation(id: existingID, anchor: .directory(path: "/existing"))],
            duplicateReservationSet(),
            overCapacityReservationSet(),
            [ExternalContentTabReservation(id: ContentTabID(rawValue: "home"), anchor: .homeDefault)],
            [relativeDirectoryReservation()],
            [relativeSelectionReservation()],
            [foreignSelectionReservation()],
            [collectionSelectionReservation()],
        ]
    }

    static func makeAtomicScenario() throws -> AtomicScenario {
        let sandbox = try FileManagerFixtureSandbox.copyingFileWithDirectorySymlink(
            from: "fixtures/fixtures/texts/plain/98.txt",
        )
        var initialState = FileManagerWindowState.makeInitial(path: "/seed")
        let originalActiveID = try XCTUnwrap(initialState.contentTabs.activeTabID)
        initialState.content.pendingSelectEntryID = "/seed/current.txt"
        initialState.content.entryViewLayout.showHiddenFiles = true
        initialState.content.entryViewLayout.gridIconSize = 73
        initialState.inspector.inspectorVisible = true
        initialState.inspector.inspectorPaneExists = true
        let expectedOriginalContent = initialState.content
        let expectedOriginalInspector = initialState.inspector.tabSnapshot()
        let pinned = makePinnedTabState()
        initialState.contentTabs.tabs.insert(pinned.tab, at: 0)
        initialState.tabContentStates[pinned.id] = pinned.content
        initialState.contentTabs.pinnedRecords[pinned.id] = pinned.record

        let directoryID = ContentTabID(rawValue: "external-directory")
        let collectionID = ContentTabID(rawValue: "external-collection")
        let fileID = ContentTabID(rawValue: "external-file")
        let collectionURL = URL(fileURLWithPath: "/tmp/ordered.voycoll")
        let pendingSelection = sandbox.fileURL.path
        let reservations = [
            ExternalContentTabReservation(id: directoryID, anchor: .directory(path: "/external")),
            ExternalContentTabReservation(id: collectionID, anchor: .collectionFile(url: collectionURL)),
            ExternalContentTabReservation(
                id: fileID,
                anchor: .directory(path: sandbox.fileURL.deletingLastPathComponent().path),
                pendingSelectEntryID: pendingSelection,
            ),
        ]
        return AtomicScenario(
            initialState: initialState,
            reservations: reservations,
            originalActiveID: originalActiveID,
            pinnedID: pinned.id,
            pinnedTab: pinned.tab,
            pinnedContent: pinned.content,
            pinnedRecord: pinned.record,
            directoryID: directoryID,
            collectionID: collectionID,
            fileID: fileID,
            collectionURL: collectionURL,
            pendingSelection: pendingSelection,
            sandbox: sandbox,
            expectedOriginalContent: expectedOriginalContent,
            expectedOriginalInspector: expectedOriginalInspector,
        )
    }

    private static func relativeDirectoryReservation() -> ExternalContentTabReservation {
        ExternalContentTabReservation(
            id: ContentTabID(rawValue: "relative-directory"),
            anchor: .directory(path: "relative"),
        )
    }

    private static func relativeSelectionReservation() -> ExternalContentTabReservation {
        ExternalContentTabReservation(
            id: ContentTabID(rawValue: "relative-selection"),
            anchor: .directory(path: "/tmp"),
            pendingSelectEntryID: "relative.txt",
        )
    }

    private static func foreignSelectionReservation() -> ExternalContentTabReservation {
        ExternalContentTabReservation(
            id: ContentTabID(rawValue: "foreign-selection"),
            anchor: .directory(path: "/tmp"),
            pendingSelectEntryID: "/other/report.txt",
        )
    }

    private static func collectionSelectionReservation() -> ExternalContentTabReservation {
        ExternalContentTabReservation(
            id: ContentTabID(rawValue: "collection-selection"),
            anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/a.voycoll")),
            pendingSelectEntryID: "/tmp/a.voycoll",
        )
    }

    private static func duplicateReservationSet() -> [ExternalContentTabReservation] {
        let id = ContentTabID(rawValue: "duplicate")
        return [
            ExternalContentTabReservation(id: id, anchor: .directory(path: "/one")),
            ExternalContentTabReservation(id: id, anchor: .directory(path: "/two")),
        ]
    }

    private static func overCapacityReservationSet() -> [ExternalContentTabReservation] {
        (0 ..< ContentTabConstants.maxTabs).map {
            ExternalContentTabReservation(
                id: ContentTabID(rawValue: "capacity-\($0)"),
                anchor: .directory(path: "/capacity/\($0)"),
            )
        }
    }

    private static func makePinnedTabState() -> PinnedState {
        let id = ContentTabID(rawValue: "existing-pinned")
        let tab = ContentTabItem(
            id: id,
            page: .directory,
            anchor: .directory(path: "/pinned"),
            isPinned: true,
            title: "Pinned",
            iconName: "pin",
        )
        var content = FileManagerContentState.initialContent(for: tab.anchor)
        content.pendingSelectEntryID = "/pinned/keep.txt"
        let record = ContentTabPinnedRecord(
            id: id.rawValue,
            page: tab.page,
            anchor: tab.anchor,
            title: tab.title,
            iconName: tab.iconName,
            pinnedAt: Date(timeIntervalSince1970: 100),
        )
        return PinnedState(id: id, tab: tab, content: content, record: record)
    }
}

private struct CTM001HomeNewChatFixture {
    let placeholderSessionID = "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
    let defaultModel: AiProviderModel
    let connectionsFile: AIConnectionsFile
    let defaultSettings: AiChatDefaultSettings
    let modelLoadGate = CTM001ModelLoadGate()
    let loadedSessionIDs = LockIsolated<[AiChatSessionID]>([])
    let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])

    init() {
        let model = AiProviderModel(
            id: AiModelHandle(provider: .openai, rawValue: "gpt-5"),
            provider: .openai,
            rawModelID: "gpt-5",
            displayName: "GPT-5",
            providerDisplayName: "OpenAI",
            thinkingCapability: .effort(values: [.minimal, .high], defaultValue: .minimal),
            supportsThinkingNone: true,
        )
        let providerRecord = ProviderRecordFile(
            providerId: .openai,
            authMethod: .apiKey,
            credential: .apiKey(APIKeyCredentialFile(secret: "sk-test-valid")),
            snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
        )
        defaultModel = model
        connectionsFile = AIConnectionsFile(
            updatedAtMs: 1,
            lastUsedProviderId: .openai,
            providers: [AiProvider.openai.rawValue: providerRecord],
        )
        defaultSettings = AiChatDefaultSettings(
            provider: PersistedAIProviderSelection(rawValue: AiProvider.openai.rawValue),
            model: PersistedAIModelSelection(
                providerRawValue: AiProvider.openai.rawValue,
                modelRawValue: model.rawModelID,
            ),
            thinking: .effort("high"),
        )
    }

    @MainActor
    func makeStore() -> TestStoreOf<FileManagerFeature> {
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.homeAiChatClient.createSession = { .selected(placeholderSessionID) }
            $0.aiConnectionsFileClient.load = { connectionsFile }
            $0.aiProviderModelListClient = AiProviderModelListClient(loadModels: { _, _ in
                await modelLoadGate.load()
            })
            $0.aiChatDefaultSettingsClient.load = { defaultSettings }
            $0.aiChatSessionPersistenceClient.loadSession = { sessionID in
                loadedSessionIDs.withValue { $0.append(sessionID) }
                return nil
            }
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                savedSnapshots.withValue { $0.append(snapshot) }
                return snapshot
            }
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.uuid = .incrementing
        }
        // store.exhaustivity = .off: Home부터 model catalog와 AiChat persistence까지의 통합 action 중 durable 경계만 선별 검증한다.
        store.exhaustivity = .off
        return store
    }
}

private actor CTM001ModelLoadGate {
    private var continuation: CheckedContinuation<[AiProviderModel], Never>?

    func load() async -> [AiProviderModel] {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilLoading() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func resume(returning models: [AiProviderModel]) {
        continuation?.resume(returning: models)
        continuation = nil
    }
}
