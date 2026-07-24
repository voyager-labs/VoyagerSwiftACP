import ComposableArchitecture
import Foundation
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
final class CTM002SetCurrentContentTabTests: XCTestCase {
    // MARK: - CTM-002-set_current_content_tab_by_index

    /// CTM-002-set_current_content_tab_by_index: 현재 Content Tab 전환과 selection 독립성 검증
    /// Sidebar primary click이나 index 기반 선택이 공유할 reducer contract를 검증한다.
    /// - 검증 내용: setCurrent가 activeTabID만 변경하고 기존 selection과 anchor를 보존함
    /// - 사전 조건: Home, Directory, Collection 세 탭과 Home active 상태
    /// - 기대 결과: 지정한 tab id가 순서대로 active가 되며 selection과 anchor는 변경되지 않음
    func testSetCurrentContentTabByIndex_activatesTargetWithoutChangingSelection() async {
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
        var state = ContentTabState(tabs: tabs, activeTabID: homeID, recentlyClosed: nil)
        state.selectedTabIDs = [homeID, collectionID]
        state.selectionAnchorID = directoryID
        let store = TestStore(initialState: state) {
            ContentTabFeature()
        }

        await store.send(.setCurrent(collectionID)) {
            $0.previousActiveTabID = homeID
            $0.activeTabID = collectionID
        }
        await store.send(.setCurrent(directoryID)) {
            $0.previousActiveTabID = collectionID
            $0.activeTabID = directoryID
        }

        XCTAssertEqual(store.state.selectedTabIDs, [homeID, collectionID])
        XCTAssertEqual(store.state.selectionAnchorID, directoryID)
        await store.finish()
    }
}
