import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

/// VOY-618: 프로세스 전역 Quick Look 패널 동기화의 window/tab 소유권 회귀 테스트.
/// selectionChanged bridge는 모든 탭에서 syncQuickLookSelection을 발행하지만,
/// window reducer(`FileManagerFeature`)는 포커스된 윈도우의 활성 탭에서만
/// 전역 Quick Look 패널 동기화가 실제 client에 도달하도록 gate한다.
@MainActor
extension EVM001FileManagerNavigationTests {
    // MARK: - helpers

    private func contentWithSelection() -> FileManagerContentFeature.State {
        let a = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        var content = FileManagerContentFeature.State()
        content.navigation.navigationState = .folder("/root")
        content.entryViewLayout.entries = [a]
        content.entryViewLayout.selectedIds = [a.id]
        content.entryViewLayout.lastSelectedId = a.id
        return content
    }

    private func makeWindowState(
        activeTabID: ContentTabID,
        inactiveTabID: ContentTabID?,
        focused: Bool,
        activeContent: FileManagerContentFeature.State,
        inactiveContent: FileManagerContentFeature.State? = nil,
    ) -> FileManagerFeature.State {
        var tabs = [
            ContentTabItem(
                id: activeTabID,
                page: .directory,
                anchor: .directory(path: "/root"),
                isPinned: false,
                title: "Active",
                iconName: "folder",
            ),
        ]
        if let inactiveTabID {
            tabs.append(ContentTabItem(
                id: inactiveTabID,
                page: .directory,
                anchor: .directory(path: "/other"),
                isPinned: false,
                title: "Inactive",
                iconName: "folder",
            ))
        }
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(tabs: .init(uniqueElements: tabs), activeTabID: activeTabID)
        state.content = activeContent
        state.tabContentStates[activeTabID] = activeContent
        if let inactiveTabID, let inactiveContent {
            state.tabContentStates[inactiveTabID] = inactiveContent
        }
        state.isFocused = focused
        return state
    }

    // MARK: - AC3: 활성 탭은 동기화한다

    /// AC3: 포커스된 윈도우의 활성 탭 selectionChanged는 전역 Quick Look 패널을 동기화한다.
    func testActiveTabInFocusedWindowSyncsQuickLook() async {
        let activeID = ContentTabID(rawValue: "active")
        let syncCalls = LockIsolated<[[String]]>([])
        let syncCalled = expectation(description: "quick look sync called")
        let store = TestStore(
            initialState: makeWindowState(
                activeTabID: activeID,
                inactiveTabID: nil,
                focused: true,
                activeContent: contentWithSelection(),
            ),
        ) {
            FileManagerFeature()
        } withDependencies: {
            $0.entryQuickLookClient = .init(
                quickLook: { _, _ in },
                syncQuickLookSelection: { urls, _ in
                    syncCalls.withValue { $0.append(urls.map(\.path)) }
                    syncCalled.fulfill()
                },
            )
        }
        store.exhaustivity = .off

        await store.send(.tabContent(tabID: activeID, action: .entryViewLayout(.delegate(.selectionChanged))))
        await fulfillment(of: [syncCalled], timeout: 2)

        XCTAssertEqual(syncCalls.value, [["/root/a"]])
    }

    // MARK: - AC2: 비활성 탭 / 백그라운드 윈도우는 동기화하지 않는다

    /// AC2: 비활성 탭의 selectionChanged는 전역 Quick Look 패널을 동기화하지 않는다.
    func testInactiveTabDoesNotSyncQuickLook() async {
        let activeID = ContentTabID(rawValue: "active")
        let inactiveID = ContentTabID(rawValue: "inactive")
        let syncCalls = LockIsolated<[[String]]>([])
        let store = TestStore(
            initialState: makeWindowState(
                activeTabID: activeID,
                inactiveTabID: inactiveID,
                focused: true,
                activeContent: contentWithSelection(),
                inactiveContent: contentWithSelection(),
            ),
        ) {
            FileManagerFeature()
        } withDependencies: {
            $0.entryQuickLookClient = .init(
                quickLook: { _, _ in },
                syncQuickLookSelection: { urls, _ in
                    syncCalls.withValue { $0.append(urls.map(\.path)) }
                },
            )
        }
        store.exhaustivity = .off

        await store.send(.tabContent(tabID: inactiveID, action: .entryViewLayout(.delegate(.selectionChanged))))
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertTrue(syncCalls.value.isEmpty)
    }

    /// AC2: 백그라운드(비포커스) 윈도우의 활성 탭 selectionChanged는 전역 Quick Look 패널을 동기화하지 않는다.
    func testBackgroundWindowActiveTabDoesNotSyncQuickLook() async {
        let activeID = ContentTabID(rawValue: "active")
        let syncCalls = LockIsolated<[[String]]>([])
        let store = TestStore(
            initialState: makeWindowState(
                activeTabID: activeID,
                inactiveTabID: nil,
                focused: false,
                activeContent: contentWithSelection(),
            ),
        ) {
            FileManagerFeature()
        } withDependencies: {
            $0.entryQuickLookClient = .init(
                quickLook: { _, _ in },
                syncQuickLookSelection: { urls, _ in
                    syncCalls.withValue { $0.append(urls.map(\.path)) }
                },
            )
        }
        store.exhaustivity = .off

        await store.send(.tabContent(tabID: activeID, action: .entryViewLayout(.delegate(.selectionChanged))))
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertTrue(syncCalls.value.isEmpty)
    }
}
