import ComposableArchitecture
import Foundation
@testable import VoyagerPagesFileManager
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

    /// CTM-001-duplicate_pinned_source: Pinned source tab 복제 시 append하고 activeTabID 변경 없음
    /// - 검증 내용: Pinned source가 active가 아닐 때 append, activeTabID 유지
    /// - 사전 조건: Pinned Directory tab과 unpinned Home tab, Home이 active
    /// - 기대 결과: Duplicate가 append되고 activeTabID는 Home 유지
    func testDuplicate_pinnedSource_doesNotChangeActive() throws {
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
        let lastTab = try XCTUnwrap(state.tabs.last)
        XCTAssertEqual(lastTab.id, duplicateID)
        XCTAssertEqual(state.activeTabID, homeID)
        XCTAssertNil(state.previousActiveTabID)
    }

    /// CTM-001-duplicate_pinned_source: Pinned source가 active일 때도 append, activeTabID source 유지
    /// - 검증 내용: Pinned source가 active일 때 append, activeTabID source 그대로
    /// - 사전 조건: Pinned Directory tab이 active
    /// - 기대 결과: Duplicate가 append되고 activeTabID는 source 유지
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
