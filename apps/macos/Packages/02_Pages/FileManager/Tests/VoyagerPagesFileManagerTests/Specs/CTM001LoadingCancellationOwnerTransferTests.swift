import Foundation
import IdentifiedCollections
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
final class CTM001LoadingCancellationOwnerTransferTests: XCTestCase {
    /// CTM-001-move_content_tab_to_another_file_manager_window: bulk move 후 loading scope는 tab별로 격리한다.
    /// target window context를 적용해도 각 moved tab의 loading cancellation owner가 유지되는지 검증한다.
    /// - 검증 내용: target window rebinding과 tab별 loading cancellation owner identity 보존
    /// - 사전 조건: 서로 다른 loading owner를 가진 두 tab을 같은 target window로 함께 이동한다.
    /// - 기대 결과: 두 tab은 target window를 공유하지만 cancellation key는 서로 다르다.
    func testBatchMovePreservesDistinctLoadingCancellationOwnersInTargetWindow() throws {
        let firstID = ContentTabID(rawValue: "batch-loading-first")
        let secondID = ContentTabID(rawValue: "batch-loading-second")
        let firstOwnerID = UUID(uuid: (18, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
        let secondOwnerID = UUID(uuid: (18, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2))
        var source = Self.window(
            windowID: Self.sourceWindowID,
            tabs: [
                Self.tab(firstID, path: "/batch/loading-first"),
                Self.tab(secondID, path: "/batch/loading-second"),
            ],
            active: firstID,
        )
        source.content.entryViewLayout.entryOperations.loadingCancellationOwnerID = firstOwnerID
        source.tabContentStates[firstID] = source.content
        source.tabContentStates[secondID]?.entryViewLayout.entryOperations.loadingCancellationOwnerID = secondOwnerID
        let target = Self.window(windowID: Self.targetWindowID, tabs: [], active: nil)

        let preflight = ContentTabTransfer.preflight(
            source: source,
            target: target,
            orderedTabIDs: [firstID, secondID],
            primaryTabID: firstID,
        )
        guard case let .success(token) = preflight else {
            return XCTFail("Expected Content Tab transfer preflight success: \(preflight)")
        }
        let firstEntryOperations = try XCTUnwrap(
            token.projectedTarget.tabContentStates[firstID]?.entryViewLayout.entryOperations,
        )
        let secondEntryOperations = try XCTUnwrap(
            token.projectedTarget.tabContentStates[secondID]?.entryViewLayout.entryOperations,
        )

        XCTAssertEqual(firstEntryOperations.windowID, Self.targetWindowID)
        XCTAssertEqual(secondEntryOperations.windowID, Self.targetWindowID)
        XCTAssertEqual(firstEntryOperations.loadingCancellationOwnerID, firstOwnerID)
        XCTAssertEqual(secondEntryOperations.loadingCancellationOwnerID, secondOwnerID)
        XCTAssertNotEqual(
            firstEntryOperations.loadingCancellationOwnerID,
            secondEntryOperations.loadingCancellationOwnerID,
        )
    }

    private static let sourceWindowID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 17),
    )
    private static let targetWindowID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 18),
    )

    private static func tab(_ id: ContentTabID, path: String) -> ContentTabItem {
        ContentTabItem(
            id: id,
            page: .directory,
            anchor: .directory(path: path),
            isPinned: false,
            title: path,
            iconName: "folder",
        )
    }

    private static func window(
        windowID: UUID,
        tabs: [ContentTabItem],
        active: ContentTabID?,
    ) -> FileManagerWindowState {
        var state = FileManagerWindowState()
        state.contentTabs = ContentTabState(
            tabs: IdentifiedArrayOf(uniqueElements: tabs),
            activeTabID: active,
        )
        state.tabContentStates = [:]
        state.tabInspectorStates = [:]
        for tab in tabs {
            var content = FileManagerContentState.initialContent(for: tab.anchor)
            content.applyWindowContext(windowID: windowID)
            state.tabContentStates[tab.id] = content
            state.tabInspectorStates[tab.id] = FileManagerInspectorFeature.State().tabSnapshot()
        }
        if let active, let content = state.tabContentStates[active] {
            state.content = content
            state.inspector = state.tabInspectorStates[active] ?? .init()
        } else {
            state.content.applyWindowContext(windowID: windowID)
            state.inspector = .init()
        }
        state.syncContentTabSidebarItems()
        return state
    }
}
