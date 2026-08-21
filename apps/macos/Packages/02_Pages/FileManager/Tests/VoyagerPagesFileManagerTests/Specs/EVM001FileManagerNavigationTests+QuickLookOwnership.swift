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
    // MARK: - AC2: 윈도우는 key callback 전까지 포커스되지 않는다

    /// AC2: 기본, 복원, 외부 예약 윈도우 state는 모두 비포커스 상태로 생성된다.
    func testWindowStateFactoriesStartUnfocused() throws {
        let restoredTabs = ContentTabState.withHomeTab()
        let externalState = try XCTUnwrap(FileManagerFeature.State.makeExternalInitial(reservations: [
            ExternalContentTabReservation(
                id: ContentTabID(rawValue: "external"),
                anchor: .directory(path: "/external"),
            ),
        ]))

        XCTAssertFalse(FileManagerFeature.State().isFocused)
        XCTAssertFalse(FileManagerFeature.State.makeInitial(path: nil).isFocused)
        XCTAssertFalse(FileManagerFeature.State.makeInitial(path: nil, contentTabs: restoredTabs).isFocused)
        XCTAssertFalse(externalState.isFocused)
    }

    // MARK: - helpers

    private func contentWithSelection(id: String = "/root/a") -> FileManagerContentFeature.State {
        let entry = EntryModel.temporaryFolder(id: id, name: (id as NSString).lastPathComponent)
        var content = FileManagerContentFeature.State()
        content.navigation.navigationState = .folder("/root")
        content.entryViewLayout.entries = [entry]
        content.entryViewLayout.selectedIds = [entry.id]
        content.entryViewLayout.lastSelectedId = entry.id
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

    /// AC2: 닫기 시작 후 큐에 남은 selectionChanged는 전역 Quick Look 패널을 동기화하지 않는다.
    func testClosingWindowQueuedSelectionDoesNotSyncQuickLook() async {
        let activeID = ContentTabID(rawValue: "closing")
        let syncCalls = LockIsolated<[[String]]>([])
        var state = makeWindowState(
            activeTabID: activeID,
            inactiveTabID: nil,
            focused: false,
            activeContent: contentWithSelection(),
        )
        state.isClosing = true
        let store = TestStore(initialState: state) {
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

    // MARK: - EVM-001-quick_look_selection_sync

    /// VOY-618: 활성 탭 전환(`setCurrent`) 후 새 활성 탭의 ordered 선택 경로를
    /// 정확히 한 번 Quick Look 패널에 동기화한다.
    /// - 검증 내용: `.syncQuickLookSelection` client가 새 활성 탭(B)의 선택 경로로 정확히 1회 호출된다.
    /// - 사전 조건: 포커스된 윈도우, A(활성)/B(비활성) 두 탭, B가 `/root/b` 선택을 보유.
    /// - 기대 결과: `.contentTabs(.setCurrent(B))` 후 B의 ordered 선택 경로로 정확히 1회 동기화.
    func testActiveTabSwitchSyncsNewActiveTabQuickLookSelection() async {
        let activeID = ContentTabID(rawValue: "active")
        let targetID = ContentTabID(rawValue: "target")
        let syncCalls = LockIsolated<[[String]]>([])
        let syncCalled = expectation(description: "new active tab Quick Look selection synchronized")
        let store = TestStore(
            initialState: makeWindowState(
                activeTabID: activeID,
                inactiveTabID: targetID,
                focused: true,
                activeContent: contentWithSelection(),
                inactiveContent: contentWithSelection(id: "/root/b"),
            ),
        ) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.entryQuickLookClient = .init(
                quickLook: { _, _ in },
                syncQuickLookSelection: { urls, _ in
                    syncCalls.withValue { $0.append(urls.map(\.path)) }
                    syncCalled.fulfill()
                },
            )
        }
        // handoff 효과는 .merge로 결합된 비결정적 효과를 남기므로 미소비 효과를 허용한다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(targetID)))
        await fulfillment(of: [syncCalled], timeout: 2)

        XCTAssertEqual(syncCalls.value, [["/root/b"]])
    }
}
