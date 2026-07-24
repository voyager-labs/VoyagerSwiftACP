import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesEntry
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

@MainActor
final class CTM001DuplicateContentTabTests: XCTestCase {
    // MARK: - CTM-001-duplicate_unpinned_source

    /// CTM-001-duplicate_unpinned_source: Unpinned Directory tab을 복제하면 sourceIndex+1에 삽입되고 활성화됨
    /// - 검증 내용: sourceIndex+1 위치에 duplicate 삽입, activeTabID = duplicateID, previousActiveTabID = sourceID
    /// - 사전 조건: Unpinned Directory tab이 active인 상태
    /// - 기대 결과: Duplicate Tab이 바로 다음 위치에 삽입되고 활성화됨
    func testDuplicate_unpinnedSource_insertsAfterAndActivates() {
        let sourceID = ContentTabID()
        let duplicateID = ContentTabID()
        var state = ContentTabState(
            tabs: [ContentTabItem(
                id: sourceID,
                page: .directory,
                anchor: .directory(path: "/test"),
                isPinned: false,
                title: "Test",
                iconName: "folder",
            )],
            activeTabID: sourceID,
        )

        let reducer = ContentTabFeature()
        _ = reducer.reduce(into: &state, action: .duplicate(sourceID: sourceID, duplicateID: duplicateID))

        XCTAssertEqual(state.tabs.count, 2)
        XCTAssertEqual(state.tabs[1].id, duplicateID)
        XCTAssertEqual(state.activeTabID, duplicateID)
        XCTAssertEqual(state.previousActiveTabID, sourceID)
    }

    /// CTM-001-duplicate_unpinned_source: selected source 복제는 기존 explicit selection을 보존함
    /// duplicate가 새 identity로 활성화되어도 selected identity와 anchor가 독립적으로 유지되는지 확인함
    /// - 검증 내용: duplicate 활성화 뒤 기존 selection/anchor와 runtime metadata 보존
    /// - 사전 조건: selected/anchored unpinned Directory source와 active sibling tab
    /// - 기대 결과: source만 선택되고 sibling/active duplicate는 선택되지 않으며 anchor가 보존됨
    func testDuplicate_selectedSourcePreservesSelectionWithoutSelectingActiveDuplicate() {
        let sourceID = ContentTabID(rawValue: "source")
        let siblingID = ContentTabID(rawValue: "sibling")
        let duplicateID = ContentTabID(rawValue: "duplicate")
        var state = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: sourceID,
                    page: .directory,
                    anchor: .directory(path: "/source"),
                    isPinned: false,
                    title: "Source",
                    iconName: "folder",
                ),
                ContentTabItem(
                    id: siblingID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: siblingID,
            previousActiveTabID: sourceID,
            pinnedRecordPersistenceError: "sentinel",
        )
        state.selectedTabIDs = [sourceID]
        state.selectionAnchorID = sourceID
        let pinnedErrorBefore = state.pinnedRecordPersistenceError

        _ = ContentTabFeature().reduce(
            into: &state,
            action: .duplicate(sourceID: sourceID, duplicateID: duplicateID),
        )

        XCTAssertEqual(state.selectedTabIDs, [sourceID])
        XCTAssertEqual(state.selectionAnchorID, sourceID)
        XCTAssertFalse(state.selectedTabIDs.contains(duplicateID))
        XCTAssertEqual(state.activeTabID, duplicateID)
        XCTAssertEqual(state.previousActiveTabID, siblingID)
        XCTAssertEqual(state.pinnedRecordPersistenceError, pinnedErrorBefore)
    }

    /// CTM-001-duplicate_unpinned_source: Inactive unpinned tab을 복제해도 같은 삽입/활성화 동작
    /// - 검증 내용: 중간 위치 tab 복제 시 sourceIndex+1에 삽입, 활성화
    /// - 사전 조건: 3개 tab 중 2번째가 inactive unpinned Directory
    /// - 기대 결과: Inactive tab도 동일한 복제 위치와 활성화 동작
    func testDuplicate_unpinnedSource_inactiveTab() {
        let homeID = ContentTabID()
        let dirID = ContentTabID()
        let collID = ContentTabID()
        let duplicateID = ContentTabID()

        var state = ContentTabState(
            tabs: [
                ContentTabItem(id: homeID, page: .home, anchor: .homeDefault, isPinned: false, title: "Home",
                               iconName: "house"),
                ContentTabItem(id: dirID, page: .directory, anchor: .directory(path: "/test"), isPinned: false,
                               title: "Test", iconName: "folder"),
                ContentTabItem(
                    id: collID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/test.voycoll")),
                    isPinned: false,
                    title: "Collection",
                    iconName: "rectangle.stack",
                ),
            ],
            activeTabID: homeID,
        )

        let reducer = ContentTabFeature()
        _ = reducer.reduce(into: &state, action: .duplicate(sourceID: dirID, duplicateID: duplicateID))

        XCTAssertEqual(state.tabs.count, 4)
        XCTAssertEqual(state.tabs[2].id, duplicateID)
        XCTAssertEqual(state.activeTabID, duplicateID)
        XCTAssertEqual(state.previousActiveTabID, homeID)
    }

    // MARK: - CTM-001-duplicate_pinned_source

    /// CTM-001-duplicate_pinned_source: Pinned source tab 복제 시 pinned 경계에 삽입하고 activeTabID 변경 없음
    /// - 검증 내용: Pinned source가 active가 아닐 때 첫 unpinned 앞에 삽입, activeTabID 유지
    /// - 사전 조건: Pinned Directory tab과 unpinned Home tab, Home이 active
    /// - 기대 결과: Duplicate가 pinned 경계에 삽입되고 activeTabID는 Home 유지
    func testDuplicate_pinnedSource_doesNotChangeActive() {
        let pinID = ContentTabID()
        let homeID = ContentTabID()
        let duplicateID = ContentTabID()

        var state = ContentTabState(
            tabs: [
                ContentTabItem(id: pinID, page: .directory, anchor: .directory(path: "/pinned"), isPinned: true,
                               title: "Pinned", iconName: "folder"),
                ContentTabItem(id: homeID, page: .home, anchor: .homeDefault, isPinned: false, title: "Home",
                               iconName: "house"),
            ],
            activeTabID: homeID,
        )

        let reducer = ContentTabFeature()
        _ = reducer.reduce(into: &state, action: .duplicate(sourceID: pinID, duplicateID: duplicateID))

        XCTAssertEqual(state.tabs.count, 3)
        XCTAssertEqual(state.tabs.map(\.id), [pinID, duplicateID, homeID])
        XCTAssertEqual(state.activeTabID, homeID)
        XCTAssertNil(state.previousActiveTabID)
    }

    /// CTM-001-duplicate_pinned_source: Pinned source가 active일 때도 경계 삽입, activeTabID source 유지
    /// - 검증 내용: Pinned source가 active일 때 pinned 경계 삽입, activeTabID source 그대로
    /// - 사전 조건: Pinned Directory tab이 active
    /// - 기대 결과: Duplicate가 pinned 경계에 삽입되고 activeTabID는 source 유지
    func testDuplicate_pinnedSource_whenActive() throws {
        let pinID = ContentTabID()
        let duplicateID = ContentTabID()

        var state = ContentTabState(
            tabs: [ContentTabItem(
                id: pinID, page: .directory, anchor: .directory(path: "/pinned"),
                isPinned: true, title: "Pinned", iconName: "folder",
            )],
            activeTabID: pinID,
        )

        let reducer = ContentTabFeature()
        _ = reducer.reduce(into: &state, action: .duplicate(sourceID: pinID, duplicateID: duplicateID))

        XCTAssertEqual(state.tabs.count, 2)
        let lastTab = try XCTUnwrap(state.tabs.last)
        XCTAssertEqual(lastTab.id, duplicateID)
        XCTAssertEqual(state.activeTabID, pinID)
        XCTAssertNil(state.previousActiveTabID)
    }

    // MARK: - CTM-001-duplicate_always_unpinned

    /// CTM-001-duplicate_always_unpinned: Pinned tab을 복제해도 duplicate의 isPinned는 false
    /// - 검증 내용: isPinned 속성만 false로 복사
    /// - 사전 조건: Pinned tab source
    /// - 기대 결과: Duplicate의 isPinned == false
    func testDuplicate_alwaysUnpinned() throws {
        let sourceID = ContentTabID()
        let duplicateID = ContentTabID()

        var state = ContentTabState(
            tabs: [ContentTabItem(
                id: sourceID, page: .directory, anchor: .directory(path: "/test"),
                isPinned: true, title: "Pinned", iconName: "folder",
            )],
            activeTabID: sourceID,
        )

        let reducer = ContentTabFeature()
        _ = reducer.reduce(into: &state, action: .duplicate(sourceID: sourceID, duplicateID: duplicateID))

        let duplicate = try XCTUnwrap(state.tabs[id: duplicateID])
        XCTAssertFalse(duplicate.isPinned)
    }

    // MARK: - CTM-001-duplicate_copies_metadata

    /// CTM-001-duplicate_copies_metadata: source의 title, iconName, anchor, page가 duplicate에 동일하게 복사됨
    /// - 검증 내용: isPinned 제외 모든 속성 동일
    /// - 사전 조건: Directory tab
    /// - 기대 결과: Page, anchor, title, iconName 모두 동일, isPinned만 false
    func testDuplicate_copiesMetadata() throws {
        let sourceID = ContentTabID()
        let duplicateID = ContentTabID()

        var state = ContentTabState(
            tabs: [ContentTabItem(
                id: sourceID, page: .directory, anchor: .directory(path: "/test"),
                isPinned: false, title: "Test Title", iconName: "folder",
            )],
            activeTabID: sourceID,
        )

        let reducer = ContentTabFeature()
        _ = reducer.reduce(into: &state, action: .duplicate(sourceID: sourceID, duplicateID: duplicateID))

        let duplicate = try XCTUnwrap(state.tabs[id: duplicateID])
        XCTAssertEqual(duplicate.page, .directory)
        XCTAssertEqual(duplicate.anchor, .directory(path: "/test"))
        XCTAssertEqual(duplicate.title, "Test Title")
        XCTAssertEqual(duplicate.iconName, "folder")
        XCTAssertFalse(duplicate.isPinned)
    }

    // MARK: - CTM-001-duplicate_anchor_types

    /// CTM-001-duplicate_anchor_types: Home anchor (.homeDefault) 복제
    /// - 검증 내용: page == .home, anchor == .homeDefault
    /// - 사전 조건: Home tab
    /// - 기대 결과: 복제된 tab도 home anchor 유지
    func testDuplicate_homeAnchor() throws {
        let sourceID = ContentTabID()
        let duplicateID = ContentTabID()

        var state = ContentTabState(
            tabs: [ContentTabItem(
                id: sourceID, page: .home, anchor: .homeDefault,
                isPinned: false, title: "Home", iconName: "house",
            )],
            activeTabID: sourceID,
        )

        let reducer = ContentTabFeature()
        _ = reducer.reduce(into: &state, action: .duplicate(sourceID: sourceID, duplicateID: duplicateID))

        let duplicate = try XCTUnwrap(state.tabs[id: duplicateID])
        XCTAssertEqual(duplicate.page, .home)
        XCTAssertEqual(duplicate.anchor, .homeDefault)
    }

    /// CTM-001-duplicate_anchor_types: CollectionFile anchor 복제
    /// - 검증 내용: 동일한 collectionFile anchor 유지
    /// - 사전 조건: CollectionFile tab
    /// - 기대 결과: 복제된 tab도 collectionFile anchor 유지
    func testDuplicate_collectionFileAnchor() throws {
        let sourceID = ContentTabID()
        let duplicateID = ContentTabID()
        let url = URL(fileURLWithPath: "/tmp/test.voycoll")

        var state = ContentTabState(
            tabs: [ContentTabItem(
                id: sourceID, page: .collection, anchor: .collectionFile(url: url),
                isPinned: false, title: "Collection", iconName: "rectangle.stack",
            )],
            activeTabID: sourceID,
        )

        let reducer = ContentTabFeature()
        _ = reducer.reduce(into: &state, action: .duplicate(sourceID: sourceID, duplicateID: duplicateID))

        let duplicate = try XCTUnwrap(state.tabs[id: duplicateID])
        XCTAssertEqual(duplicate.anchor, .collectionFile(url: url))
    }

    /// CTM-001-duplicate_anchor_types: VirtualCollection anchor 복제
    /// - 검증 내용: 동일한 virtualCollection anchor 유지
    /// - 사전 조건: VirtualCollection tab
    /// - 기대 결과: 복제된 tab도 virtualCollection anchor 유지
    func testDuplicate_virtualCollectionAnchor() throws {
        let sourceID = ContentTabID()
        let duplicateID = ContentTabID()

        var state = ContentTabState(
            tabs: [ContentTabItem(
                id: sourceID, page: .collection, anchor: .virtualCollection(id: "Recents"),
                isPinned: false, title: "Recents", iconName: "clock",
            )],
            activeTabID: sourceID,
        )

        let reducer = ContentTabFeature()
        _ = reducer.reduce(into: &state, action: .duplicate(sourceID: sourceID, duplicateID: duplicateID))

        let duplicate = try XCTUnwrap(state.tabs[id: duplicateID])
        XCTAssertEqual(duplicate.anchor, .virtualCollection(id: "Recents"))
    }

    /// CTM-001-duplicate_anchor_types: AIChat anchor (valid UUID sessionID) 복제
    /// - 검증 내용: 동일한 aiChat anchor 유지
    /// - 사전 조건: 유효한 UUID sessionID를 가진 AIChat tab
    /// - 기대 결과: 복제된 tab도 aiChat anchor 유지
    func testDuplicate_aiChatAnchor() throws {
        let sessionID = UUID().uuidString
        let sourceID = ContentTabID()
        let duplicateID = ContentTabID()

        var state = ContentTabState(
            tabs: [ContentTabItem(
                id: sourceID, page: .aiChat, anchor: .aiChat(sessionID: sessionID),
                isPinned: false, title: "AI Chat", iconName: "sparkles",
            )],
            activeTabID: sourceID,
        )

        let reducer = ContentTabFeature()
        _ = reducer.reduce(into: &state, action: .duplicate(sourceID: sourceID, duplicateID: duplicateID))

        let duplicate = try XCTUnwrap(state.tabs[id: duplicateID])
        XCTAssertEqual(duplicate.anchor, .aiChat(sessionID: sessionID))
    }

    // MARK: - CTM-001-duplicate_noop_guards

    /// CTM-001-duplicate_noop_guards: 존재하지 않는 sourceID → state 변경 없음
    /// - 검증 내용: state가 완전히 동일하게 유지
    /// - 사전 조건: sourceID가 tabs에 없음
    /// - 기대 결과: No-op, state unchanged
    func testDuplicate_sourceNotFound_noop() {
        let sourceID = ContentTabID()
        let invalidID = ContentTabID()
        let duplicateID = ContentTabID()

        let originalState = ContentTabState(
            tabs: [ContentTabItem(
                id: sourceID, page: .home, anchor: .homeDefault,
                isPinned: false, title: "Home", iconName: "house",
            )],
            activeTabID: sourceID,
        )
        var state = originalState

        let reducer = ContentTabFeature()
        _ = reducer.reduce(into: &state, action: .duplicate(sourceID: invalidID, duplicateID: duplicateID))

        XCTAssertEqual(state, originalState)
    }

    /// CTM-001-duplicate_noop_guards: duplicateID가 이미 존재하면 no-op
    /// - 검증 내용: state가 완전히 동일하게 유지
    /// - 사전 조건: duplicateID가 이미 tabs에 있음
    /// - 기대 결과: No-op, state unchanged
    func testDuplicate_duplicateIDCollision_noop() {
        let existingID = ContentTabID()
        var state = ContentTabState(
            tabs: [ContentTabItem(
                id: existingID, page: .home, anchor: .homeDefault,
                isPinned: false, title: "Home", iconName: "house",
            )],
            activeTabID: existingID,
        )
        let originalState = state

        let reducer = ContentTabFeature()
        _ = reducer.reduce(into: &state, action: .duplicate(sourceID: existingID, duplicateID: existingID))

        XCTAssertEqual(state, originalState)
    }

    /// CTM-001-duplicate_noop_guards: composed reducer도 기존 duplicate ID를 성공으로 오인하지 않음
    /// - 검증 내용: selection/anchor와 기존 duplicate ID의 owner cache가 모두 보존됨
    /// - 사전 조건: source와 별도 existing tab이 있고 existing ID로 duplicate action을 직접 전송함
    /// - 기대 결과: core no-op 이후 Window routing도 selection collapse나 owner handoff를 수행하지 않음
    func testDuplicate_duplicateIDCollision_composedReducerPreservesSelectionAndOwnerCache() async {
        let sourceID = ContentTabID(rawValue: "collision-source")
        let existingID = ContentTabID(rawValue: "collision-existing")
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: sourceID,
                    page: .collection,
                    anchor: .virtualCollection(id: "Recents"),
                    isPinned: false,
                    title: "Source",
                    iconName: "clock",
                ),
                ContentTabItem(
                    id: existingID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Existing",
                    iconName: "house",
                ),
            ],
            activeTabID: sourceID,
        )
        state.contentTabs.selectedTabIDs = [sourceID, existingID]
        state.contentTabs.selectionAnchorID = existingID
        state.content.navigation.navigationState = .recents
        var existingContent = FileManagerContentFeature.State()
        existingContent.navigation.navigationState = .home
        state.tabContentStates[existingID] = existingContent
        let originalContentTabs = state.contentTabs
        let originalExistingContent = state.tabContentStates[existingID]
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.duplicate(sourceID: sourceID, duplicateID: existingID)))
        await store.skipReceivedActions(strict: false)

        XCTAssertEqual(store.state.contentTabs, originalContentTabs)
        XCTAssertEqual(store.state.tabContentStates[existingID], originalExistingContent)
        await store.finish()
    }

    /// CTM-001-duplicate_noop_guards: maxTabs에 도달하면 no-op
    /// - 검증 내용: state가 완전히 동일하게 유지
    /// - 사전 조건: tabs.count == maxTabs (20)
    /// - 기대 결과: No-op, state unchanged
    func testDuplicate_maxTabs_noop() {
        let sourceID = ContentTabID()
        let duplicateID = ContentTabID()

        var tabs: IdentifiedArrayOf<ContentTabItem> = []
        for i in 0 ..< ContentTabConstants.maxTabs {
            let id = i == 0 ? sourceID : ContentTabID()
            tabs.append(ContentTabItem(
                id: id, page: .directory, anchor: .directory(path: "/test/\(i)"),
                isPinned: false, title: nil, iconName: nil,
            ))
        }

        var state = ContentTabState(tabs: tabs, activeTabID: sourceID)
        let originalState = state

        let reducer = ContentTabFeature()
        _ = reducer.reduce(into: &state, action: .duplicate(sourceID: sourceID, duplicateID: duplicateID))

        XCTAssertEqual(state, originalState)
    }

    /// CTM-001-duplicate_noop_guards: 유효하지 않은 anchor (aiChat with non-UUID sessionID) → no-op
    /// - 검증 내용: state가 완전히 동일하게 유지
    /// - 사전 조건: AIChat anchor에 non-UUID sessionID 문자열
    /// - 기대 결과: No-op, state unchanged
    func testDuplicate_invalidAnchor_noop() {
        let sourceID = ContentTabID()
        let duplicateID = ContentTabID()

        var state = ContentTabState(
            tabs: [ContentTabItem(
                id: sourceID, page: .aiChat, anchor: .aiChat(sessionID: "not-a-uuid"),
                isPinned: false, title: "AI Chat", iconName: "sparkles",
            )],
            activeTabID: sourceID,
        )
        let originalState = state

        let reducer = ContentTabFeature()
        _ = reducer.reduce(into: &state, action: .duplicate(sourceID: sourceID, duplicateID: duplicateID))

        XCTAssertEqual(state, originalState)
    }

    /// CTM-001-duplicate_noop_guards: (page, anchor) 조합 불일치 → no-op
    /// - 검증 내용: .home page + .directory(path) anchor처럼 호환되지 않는 조합은 복제되지 않음
    /// - 사전 조건: home page에 directory anchor가 설정된 tab
    /// - 기대 결과: No-op, state unchanged
    func testDuplicate_pageAnchorMismatch_noop() {
        let sourceID = ContentTabID()
        let duplicateID = ContentTabID()

        var state = ContentTabState(
            tabs: [ContentTabItem(
                id: sourceID, page: .home, anchor: .directory(path: "/test"),
                isPinned: false, title: "Home", iconName: "house",
            )],
            activeTabID: sourceID,
        )
        let originalState = state

        let reducer = ContentTabFeature()
        _ = reducer.reduce(into: &state, action: .duplicate(sourceID: sourceID, duplicateID: duplicateID))

        XCTAssertEqual(state, originalState)
    }

    // MARK: - CTM-001-duplicate_pinned_records_unchanged

    /// CTM-001-duplicate_pinned_records_unchanged: pinnedRecords, pendingPinnedRecordIDs, recentlyClosed가 duplicate
    /// 이후에도 유지됨
    /// - 검증 내용: 세 필드 모두 변경되지 않음
    /// - 사전 조건: pinned record, pending ID, recentlyClosed가 설정된 상태
    /// - 기대 결과: Duplicate 이후에도 pinnedRecords, pendingPinnedRecordIDs, recentlyClosed가 이전과 동일
    func testDuplicate_pinnedRecordsUnchanged() {
        let sourceID = ContentTabID()
        let duplicateID = ContentTabID()
        let pinnedID = ContentTabID()
        let pinnedRecord = ContentTabPinnedRecord(
            id: pinnedID.rawValue, page: .directory, anchor: .directory(path: "/pinned"),
            title: "Pinned", iconName: "folder", pinnedAt: Date(timeIntervalSince1970: 1000),
        )

        var state = ContentTabState(
            tabs: [
                ContentTabItem(id: pinnedID, page: .directory, anchor: .directory(path: "/pinned"),
                               isPinned: true, title: "Pinned", iconName: "folder"),
                ContentTabItem(id: sourceID, page: .home, anchor: .homeDefault, isPinned: false,
                               title: "Home", iconName: "house"),
            ],
            activeTabID: sourceID,
            recentlyClosed: ClosedContentTabSnapshot(
                page: .home, anchor: .homeDefault, wasPinned: false,
                closedAt: Date(timeIntervalSince1970: 2000), title: nil, iconName: nil,
            ),
            pinnedRecords: [pinnedID: pinnedRecord],
            pendingPinnedRecordIDs: [pinnedID],
        )

        let originalPinnedRecords = state.pinnedRecords
        let originalPendingIDs = state.pendingPinnedRecordIDs
        let originalRecentlyClosed = state.recentlyClosed

        let reducer = ContentTabFeature()
        _ = reducer.reduce(into: &state, action: .duplicate(sourceID: sourceID, duplicateID: duplicateID))

        XCTAssertEqual(state.pinnedRecords, originalPinnedRecords)
        XCTAssertEqual(state.pendingPinnedRecordIDs, originalPendingIDs)
        XCTAssertEqual(state.recentlyClosed, originalRecentlyClosed)
    }
}

// MARK: - CTM-001-duplicate_pending_close_rollback

@MainActor
extension CTM001DuplicateContentTabTests {
    /// CTM-001-duplicate_pending_close_rollback: pending close 중 direct duplicate action이 exact row/cache를
    /// 제거하고 pending state로 복원한다
    /// ContentTabFeature.duplicate가 unpinned source duplicate에서 previousActiveTabID를 sourceID로 덮어쓰므로,
    /// keepPendingDuplicateContentTabCloseFocused는 pendingClose에 보관된 원본 previousActiveTabID를 사용해야 한다.
    /// - 검증 내용:
    ///   - duplicateID row/cache 제거
    ///   - activeTabID가 pendingClose.tabID로 복원
    ///   - previousActiveTabID가 pendingClose.previousActiveTabID로 복원
    ///   - source/target row와 Content/Inspector cache는 유지
    /// - 사전 조건: 3 tab 상태, pendingContentTabClose에 nil이 아닌 previousActiveTabID 설정
    /// - 기대 결과: pending close 보존, 정확한 activeTabID/previousActiveTabID 복원
    func testDuplicate_pendingCloseRollback_restoresBothIds() async {
        let activeBeforePendingID = ContentTabID()
        let pendingTabID = ContentTabID()
        let sourceID = ContentTabID()
        let duplicateID = ContentTabID()
        let directoryPath = "/Users/test/Desktop"

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(id: activeBeforePendingID, page: .home, anchor: .homeDefault, isPinned: false,
                               title: "Home", iconName: "house"),
                ContentTabItem(id: pendingTabID, page: .directory, anchor: .directory(path: directoryPath),
                               isPinned: false, title: "Desktop", iconName: "folder"),
                ContentTabItem(id: sourceID, page: .home, anchor: .homeDefault, isPinned: false,
                               title: "Work", iconName: "folder"),
            ],
            activeTabID: activeBeforePendingID,
            recentlyClosed: nil,
        )
        var directoryContent = FileManagerContentFeature.State()
        directoryContent.navigation.seedInitialFolderPath(directoryPath)
        state.tabContentStates = [
            activeBeforePendingID: FileManagerContentFeature.State(),
            pendingTabID: directoryContent,
            sourceID: FileManagerContentFeature.State(),
        ]
        state.pendingContentTabClose = PendingContentTabClose(
            tabID: pendingTabID,
            previousActiveTabID: activeBeforePendingID,
        )
        state.contentTabs.selectedTabIDs = [sourceID, duplicateID]
        state.contentTabs.selectionAnchorID = duplicateID
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in continuation.finish() }
            }
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.duplicate(sourceID: sourceID, duplicateID: duplicateID)))
        await store.skipReceivedActions(strict: false)

        // Pending close state는 그대로 유지
        XCTAssertNotNil(store.state.pendingContentTabClose)
        XCTAssertEqual(store.state.pendingContentTabClose?.tabID, pendingTabID)
        XCTAssertEqual(store.state.pendingContentTabClose?.previousActiveTabID, activeBeforePendingID)

        // Exact duplicateID row/cache 제거
        XCTAssertNil(store.state.contentTabs.tabs[id: duplicateID])
        XCTAssertNil(store.state.tabContentStates[duplicateID])
        XCTAssertNil(store.state.tabInspectorStates[duplicateID])
        XCTAssertEqual(store.state.contentTabs.selectedTabIDs, [sourceID])
        XCTAssertNil(store.state.contentTabs.selectionAnchorID)

        // Source/target row 유지
        XCTAssertNotNil(store.state.contentTabs.tabs[id: sourceID])
        XCTAssertNotNil(store.state.contentTabs.tabs[id: pendingTabID])
        XCTAssertNotNil(store.state.contentTabs.tabs[id: activeBeforePendingID])

        // activeTabID/previousActiveTabID가 pendingClose 원본 값으로 복원
        XCTAssertEqual(store.state.contentTabs.activeTabID, pendingTabID)
        XCTAssertEqual(store.state.contentTabs.previousActiveTabID, activeBeforePendingID)

        // Duplicate row만 제거되었으므로 총 tab 수는 3 유지
        XCTAssertEqual(store.state.contentTabs.tabs.count, 3)
        XCTAssertEqual(store.state.tabContentStates.count, 3)
        await store.finish()
    }

    /// CTM-001-duplicate_pending_close_rollback: pending close 없을 때는 post-reduce duplicate가 정상 동작
    /// keepPendingDuplicateContentTabCloseFocused의 guard가 false를 반환하면 일반 duplicate handoff로 이어진다.
    /// CTM-001-duplicate_via_contentTabs: ContentTabFeature.duplicate 직접 전송 시 row 생성
    /// Scope 수준에서 .contentTabs(.duplicate) action이 올바르게 row를 생성하는지 검증한다.
    func testDuplicate_viaDirectContentTabsAction() async {
        let sourceID = ContentTabID()
        let duplicateID = ContentTabID()
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: sourceID,
                page: .collection,
                anchor: .virtualCollection(id: "Recents"),
                isPinned: false,
                title: "Recents",
                iconName: "clock",
            )],
            activeTabID: sourceID,
            recentlyClosed: nil,
        )
        state.syncActiveTabContentState()
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in continuation.finish() }
            }
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.duplicate(sourceID: sourceID, duplicateID: duplicateID)))
        await store.skipReceivedActions(strict: false)

        XCTAssertEqual(store.state.contentTabs.tabs.count, 2)
        XCTAssertEqual(store.state.contentTabs.selectedTabIDs, [])
        XCTAssertNil(store.state.contentTabs.selectionAnchorID)
        await store.finish()
    }

    /// CTM-001-duplicate_via_request: .request(.duplicateContentTab)을 거쳐 command reducer가 ContentTabFeature에 전달
    func testDuplicate_viaRequestAction() async {
        let sourceID = ContentTabID()
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: sourceID,
                page: .collection,
                anchor: .virtualCollection(id: "Recents"),
                isPinned: false,
                title: "Recents",
                iconName: "clock",
            )],
            activeTabID: sourceID,
            recentlyClosed: nil,
        )
        state.syncActiveTabContentState()
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in continuation.finish() }
            }
        }
        store.exhaustivity = .off

        await store.send(.request(.duplicateContentTab(sourceID)))
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.contentTabs.tabs.count, 2)
        XCTAssertNil(store.state.pendingContentTabClose)
        await store.finish()
    }

    /// CTM-001-duplicate_pending_teardown_guard: Sidebar single duplicate는 owner teardown 중 no-op임
    /// - 검증 내용: Sidebar delegate부터 command/core routing까지 row/cache/active/selection을 전혀 변경하지 않음
    /// - 사전 조건: 다른 unpinned tab close의 `pendingContentTabTeardown`이 있고 Home row가 active/selected
    /// - 기대 결과: duplicate row/internal handoff가 생성되지 않고 teardown transaction state가 byte-for-byte 보존됨
    func testDuplicate_sidebarSingleDuringPendingTeardown_isWholeStateNoOp() async throws {
        let sourceID = ContentTabID(rawValue: "teardown-source")
        let closingID = ContentTabID(rawValue: "teardown-closing")
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: sourceID,
                page: .home,
                anchor: .homeDefault,
                isPinned: false,
                title: "Home",
                iconName: "house",
            )],
            activeTabID: sourceID,
        )
        state.contentTabs.selectionAnchorID = sourceID
        state.pendingContentTabTeardown = try PendingContentTabTeardown(
            requestID: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000901")),
            tabID: closingID,
            ownerID: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000902")),
        )
        let originalState = state
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in continuation.finish() }
            }
        }
        store.exhaustivity = .off

        await store.send(.sidebar(.delegate(.duplicateContentTab(sourceID))))
        await store.skipReceivedActions(strict: false)

        XCTAssertEqual(store.state, originalState)
        await store.finish()
    }

    /// CTM-001-duplicate_temporary_collection_guard: Directory anchor에서 열린 임시 Collection은 복제를 차단한다.
    /// - 검증 내용: 경고 표시, 원본 row/active state 유지, duplicate row 미생성
    /// - 사전 조건: active Directory tab, navigationState=.collection(.temporary), collection mode=true
    /// - 기대 결과: tab 수 1 유지, temporary Collection state 유지, 저장 안내 경고 표시
    func testDuplicate_temporaryCollectionInDirectoryTab_showsFeedbackAndPreservesSource() async {
        let sourceID = ContentTabID()
        let state = makeTemporaryCollectionDuplicateState(sourceID: sourceID)
        let originalSource = state.contentTabs.tabs[id: sourceID]
        let alerts = LockIsolated<[(title: String, message: String)]>([])
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.fileManagerClient.fileExistsWithIsDirectory = { _, isDirectory in
                isDirectory?.pointee = true
                return true
            }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { title, message in
                alerts.withValue { $0.append((title, message)) }
            }
        }
        store.exhaustivity = .off

        await store.send(.request(.duplicateContentTab(sourceID)))
        await store.finish()

        XCTAssertEqual(store.state.contentTabs.tabs.count, 1)
        XCTAssertEqual(store.state.contentTabs.tabs[id: sourceID], originalSource)
        XCTAssertEqual(store.state.contentTabs.activeTabID, sourceID)
        if case let .collection(navigation) = store.state.content.navigation.navigationState {
            XCTAssertEqual(navigation.kind, .temporary)
        } else {
            XCTFail("Temporary Collection navigation state should be preserved")
        }
        XCTAssertEqual(alerts.value.count, 1)
        XCTAssertEqual(alerts.value[0].title, "Cannot Duplicate Tab")
        XCTAssertEqual(
            alerts.value[0].message,
            "Cannot duplicate a temporary collection. Save the collection first.",
        )
    }
}

private extension CTM001DuplicateContentTabTests {
    func makeTemporaryCollectionDuplicateState(sourceID: ContentTabID) -> FileManagerFeature.State {
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: sourceID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Desktop"),
                    isPinned: false,
                    title: "Desktop",
                    iconName: "folder",
                ),
            ],
            activeTabID: sourceID,
            recentlyClosed: nil,
        )
        state.content.entryViewLayout.isCollectionMode = true
        state.content.navigation.navigationState = .collection(.init(
            kind: .temporary,
            context: .init(),
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .grid,
        ))
        state.syncActiveTabContentState()
        state.syncContentTabSidebarItems()
        return state
    }
}
