import ComposableArchitecture
import Foundation
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
final class CTM002SetCurrentContentTabTests: XCTestCase {
    // MARK: - CTM-002-set_current_content_tab_by_index

    /// CTM-002-set_current_content_tab_by_index: 현재 Content Tab 선택은 대상 tab identity만 active로 만듦
    /// Sidebar primary click이나 index 기반 선택이 공유할 reducer contract를 검증한다.
    /// - 검증 내용: setCurrent가 activeTabID만 target id로 변경하고 tab 목록을 유지함
    /// - 사전 조건: Home, Directory, Collection 세 탭과 Home active 상태
    /// - 기대 결과: 지정한 tab id가 순서대로 active가 되고 다른 상태는 유지됨
    func testSetCurrentContentTabByIndex_activatesOnlyTargetIdentity() async {
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
        let store = TestStore(
            initialState: ContentTabState(tabs: tabs, activeTabID: homeID, recentlyClosed: nil),
        ) {
            ContentTabFeature()
        }

        await store.send(.setCurrent(collectionID)) {
            $0.activeTabID = collectionID
        }
        await store.send(.setCurrent(directoryID)) {
            $0.activeTabID = directoryID
        }
        await store.finish()
    }
}
