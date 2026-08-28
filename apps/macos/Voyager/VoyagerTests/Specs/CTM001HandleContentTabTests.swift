import ComposableArchitecture
import Foundation
@testable import Voyager
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

@MainActor
final class CTM001HandleContentTabTests: XCTestCase {
    private struct FocusedAppFixture {
        let appState: AppRootState
        let focusedID: UUID
        let activeTabID: ContentTabID
    }

    private enum ExpectedCloseRoute {
        case active
        case selected
    }

    // MARK: - CTM-001-close_selected_content_tabs

    /// CTM-001-close_selected_content_tabs: pinned active를 포함한 다중 선택은 하나의 Close 메뉴로 일괄 닫기를 요청한다.
    /// 사용자가 여러 Content Tab을 선택한 상태에서 File 메뉴 또는 Command-W를 실행하는 조합 계약을 검증한다.
    /// - 검증 내용: `Close N Tabs` label, 활성 availability, semantic `.closeTab`, bulk Window command
    /// - 사전 조건: focused Window에 유효한 tab 3개가 선택되어 있고 active tab은 pinned 상태다.
    /// - 기대 결과: 메뉴는 숨지 않고 `Close 3 Tabs`로 활성화되며 Window는 `closeSelectedContentTabs`를 받는다.
    func testFileMenuRoutesPinnedActiveMultiSelectionToBulkClose() async {
        let fixture = makeFocusedAppState(selectedCount: 3, activePinned: true)
        let menuState = MenuCommandsState(state: fixture.appState)

        XCTAssertEqual(menuState.closeTabTitle, "Close 3 Tabs")
        XCTAssertTrue(menuState.showsCloseTabCommand)
        XCTAssertTrue(menuState.canCloseTab)

        let menuStore = TestStore(initialState: menuState) {
            MenuCommandsFeature()
        }
        await menuStore.send(.view(.app(.closeTab)))
        await menuStore.receive {
            guard case .delegate(.windowManager(.file(.closeTab))) = $0 else { return false }
            return true
        }

        await assertCloseRoute(
            appState: fixture.appState,
            focusedID: fixture.focusedID,
            expectedRoute: .selected,
        )
    }

    /// CTM-001-close_selected_content_tabs: zero 또는 하나의 explicit selection은 active 단일 닫기를 유지한다.
    /// explicit selection과 active identity가 독립인 상태에서도 기존 Command-W 단일 닫기 의미가 보존되는지 검증한다.
    /// - 검증 내용: `Close Tab` label, active availability, `closeActiveContentTab` Window command
    /// - 사전 조건: focused Window의 active tab은 unpinned이고 explicit selection count가 각각 0과 1이다.
    /// - 기대 결과: 두 경우 모두 하나의 `Close Tab` command가 활성화되고 active tab 닫기로 라우팅된다.
    func testFileMenuPreservesActiveSingleCloseForZeroOrOneSelection() async {
        for selectedCount in [0, 1] {
            let fixture = makeFocusedAppState(selectedCount: selectedCount)
            let menuState = MenuCommandsState(state: fixture.appState)

            XCTAssertEqual(menuState.closeTabTitle, "Close Tab")
            XCTAssertTrue(menuState.showsCloseTabCommand)
            XCTAssertTrue(menuState.canCloseTab)

            await assertCloseRoute(
                appState: fixture.appState,
                focusedID: fixture.focusedID,
                expectedRoute: .active,
            )
        }
    }

    /// CTM-001-content_tab_action_metrics: File menu와 Cmd-W close는 menuCommand source terminal을 기록한다.
    /// SwiftUI의 단일 action 경계를 공유하는 메뉴 click과 shortcut을 동일한 유한 source로 취급하는지 검증한다.
    /// - 검증 내용: active tab 제거와 `.success/.close/.menuCommand` 메트릭 1건
    /// - 사전 조건: focused Window의 unpinned active tab과 sibling tab
    /// - 기대 결과: 레코더에 menuCommand source의 close success 메트릭 1건만 기록됨
    func testFileMenuClosePreservesMenuCommandMetricSource() async {
        let fixture = makeFocusedAppState(selectedCount: 0)
        var appState = fixture.appState
        let siblingID = ContentTabID(rawValue: "app-menu-close-sibling")
        appState.windowManager.windows[id: fixture.focusedID]?.window.contentTabs.tabs.append(
            ContentTabItem(
                id: siblingID,
                page: .home,
                anchor: .homeDefault,
                isPinned: false,
                title: "Sibling",
                iconName: "house",
            ),
        )
        let operationID = makeUUID("00000000-0000-0000-0000-000000000506")
        let metrics = LockIsolated<[FileManagerProductMetric]>([])
        let store = makeMetricStore(
            fixture: FocusedAppFixture(
                appState: appState,
                focusedID: fixture.focusedID,
                activeTabID: fixture.activeTabID,
            ),
            operationID: operationID,
            metrics: metrics,
        )

        await store.send(.file(.closeTab))
        await store.skipReceivedActions()

        XCTAssertEqual(metrics.value, [.contentTabAction(
            result: .success,
            identity: .closeContentTab,
            source: .menuCommand,
            operationID: operationID,
        )])
    }

    /// CTM-001-content_tab_action_metrics: File menu duplicate는 menuCommand source terminal을 기록한다.
    /// app command에서 package synchronous wrapper까지 accepted source가 유지되는지 검증한다.
    /// - 검증 내용: duplicate tab 생성과 `.success/.duplicate/.menuCommand` 메트릭 1건
    /// - 사전 조건: focused Window의 단일 active tab
    /// - 기대 결과: 레코더에 menuCommand source의 duplicate success 메트릭 1건만 기록됨
    func testFileMenuDuplicatePreservesMenuCommandMetricSource() async {
        let fixture = makeFocusedAppState(selectedCount: 1)
        let operationID = makeUUID("00000000-0000-0000-0000-000000000507")
        let metrics = LockIsolated<[FileManagerProductMetric]>([])
        let store = makeMetricStore(fixture: fixture, operationID: operationID, metrics: metrics)

        await store.send(.file(.duplicateTab))
        await store.skipReceivedActions()

        XCTAssertEqual(metrics.value, [.contentTabAction(
            result: .success,
            identity: .duplicateContentTab,
            source: .menuCommand,
            operationID: operationID,
        )])
    }

    /// CTM-001-content_tab_action_metrics: File menu restore는 menuCommand source terminal을 기록한다.
    /// restore candidate 수용부터 synchronous restore terminal까지 source가 유지되는지 검증한다.
    /// - 검증 내용: recentlyClosed 소비와 `.success/.restore/.menuCommand` 메트릭 1건
    /// - 사전 조건: focused Window와 Home recently-closed snapshot
    /// - 기대 결과: 레코더에 menuCommand source의 restore success 메트릭 1건만 기록됨
    func testFileMenuRestorePreservesMenuCommandMetricSource() async {
        let fixture = makeFocusedAppState(selectedCount: 1)
        var appState = fixture.appState
        appState.windowManager.windows[id: fixture.focusedID]?.window.contentTabs.recentlyClosed =
            ClosedContentTabSnapshot(
                page: .home,
                anchor: .homeDefault,
                wasPinned: false,
                closedAt: Date(timeIntervalSince1970: 505),
            )
        let operationID = makeUUID("00000000-0000-0000-0000-000000000508")
        let metrics = LockIsolated<[FileManagerProductMetric]>([])
        let store = makeMetricStore(
            fixture: FocusedAppFixture(
                appState: appState,
                focusedID: fixture.focusedID,
                activeTabID: fixture.activeTabID,
            ),
            operationID: operationID,
            metrics: metrics,
        )

        await store.send(.file(.restoreLastClosedTab))
        await store.skipReceivedActions()

        XCTAssertEqual(metrics.value, [.contentTabAction(
            result: .success,
            identity: .restoreLastClosedTab,
            source: .menuCommand,
            operationID: operationID,
        )])
    }

    /// CTM-001-close_selected_content_tabs: focus 또는 close lifecycle이 유효하지 않으면 메뉴와 direct action을 차단한다.
    /// 사용자가 실행할 수 없는 Window 상태에서 UI projection과 reducer 직접 주입이 같은 no-op 정책을 따르는지 검증한다.
    /// - 검증 내용: disabled availability와 MenuCommands/WindowManager direct `.closeTab` no-op
    /// - 사전 조건: no focus, closing Window, pending batch, pending single close, pending teardown 상태다.
    /// - 기대 결과: 모든 상태에서 close command가 비활성화되고 child Window close action이 발생하지 않는다.
    func testFileMenuCloseIsDisabledAndNoOpForUnavailableWindowLifecycle() async {
        let fixture = makeFocusedAppState(selectedCount: 2)
        let activeTabID = fixture.activeTabID

        var noFocus = fixture.appState
        noFocus.windowManager.focusedWindowID = nil

        var closing = fixture.appState
        closing.windowManager.closingWindowIDs.insert(fixture.focusedID)

        var pendingBatch = fixture.appState
        let orderedTargetIDs = pendingBatch.windowManager.windows[id: fixture.focusedID]?.window.contentTabs.tabs
            .map(\.id) ?? []
        pendingBatch.windowManager.windows[id: fixture.focusedID]?.window.pendingSelectedContentTabClose =
            PendingSelectedContentTabClose(
                operationID: makeUUID("00000000-0000-0000-0000-000000000501"),
                orderedTargetIDs: orderedTargetIDs,
                originalActiveTabID: activeTabID,
                preferredFallbackIDs: [],
            )

        var pendingSingle = fixture.appState
        pendingSingle.windowManager.windows[id: fixture.focusedID]?.window.pendingContentTabClose =
            PendingContentTabClose(tabID: activeTabID)

        var pendingTeardown = fixture.appState
        pendingTeardown.windowManager.windows[id: fixture.focusedID]?.window.pendingContentTabTeardown =
            PendingContentTabTeardown(
                requestID: makeUUID("00000000-0000-0000-0000-000000000502"),
                tabID: activeTabID,
                ownerID: makeUUID("00000000-0000-0000-0000-000000000503"),
            )

        let scenarios: [(String, AppRootState)] = [
            ("no focus", noFocus),
            ("closing Window", closing),
            ("pending batch", pendingBatch),
            ("pending single close", pendingSingle),
            ("pending teardown", pendingTeardown),
        ]

        for (scenario, appState) in scenarios {
            let menuState = MenuCommandsState(state: appState)
            XCTAssertFalse(menuState.canCloseTab, scenario)

            let menuStore = TestStore(initialState: menuState) {
                MenuCommandsFeature()
            }
            await menuStore.send(.view(.app(.closeTab)))
            await menuStore.finish()

            let windowStore = TestStore(initialState: appState.windowManager) {
                WindowManagerFeature()
            }
            await windowStore.send(.file(.closeTab))
            await windowStore.finish()
        }
    }

    /// CTM-001-close_selected_content_tabs: batch lifetime 동안 topology app menu와 direct action은 모두 no-op임
    /// current item과 inter-item gap에서 UI capability와 MenuCommands/WindowManager reducer guard가 일치하는지 검증한다.
    /// - 검증 내용: New Tab, Pin/Unpin, Duplicate, Restore disabled와 direct action no-op
    /// - 사전 조건: focused Window에 선택 탭 2개와 restore candidate가 있고 batch current 또는 current nil gap 상태
    /// - 기대 결과: 두 상태 모두 네 command가 비활성화되고 child Window action을 방출하지 않음
    func testTopologyMenuCommandsAreDisabledAndNoOpForBatchCurrentAndGap() async {
        let fixture = makeFocusedAppState(selectedCount: 2)
        let operationID = makeUUID("00000000-0000-0000-0000-000000000504")
        let targetIDs = fixture.appState.windowManager.windows[id: fixture.focusedID]?.window.contentTabs.tabs
            .map(\.id) ?? []

        for currentTabID in [fixture.activeTabID, nil] {
            var appState = fixture.appState
            appState.windowManager.windows[id: fixture.focusedID]?.window.contentTabs.recentlyClosed =
                ClosedContentTabSnapshot(
                    page: .home,
                    anchor: .homeDefault,
                    wasPinned: false,
                    closedAt: Date(timeIntervalSince1970: 504),
                )
            appState.windowManager.windows[id: fixture.focusedID]?.window.pendingSelectedContentTabClose =
                PendingSelectedContentTabClose(
                    operationID: operationID,
                    orderedTargetIDs: targetIDs,
                    cursor: currentTabID == nil ? 1 : 0,
                    currentTabID: currentTabID,
                    originalActiveTabID: fixture.activeTabID,
                    preferredFallbackIDs: [],
                )
            if let currentTabID {
                appState.windowManager.windows[id: fixture.focusedID]?.window.pendingContentTabClose =
                    PendingContentTabClose(tabID: currentTabID, batchOperationID: operationID)
            }

            let menuState = MenuCommandsState(state: appState)
            XCTAssertFalse(menuState.canOpenNewContentTab)
            XCTAssertFalse(menuState.canToggleActiveContentTabPin)
            XCTAssertFalse(menuState.canDuplicateSelectedContentTabs)
            XCTAssertFalse(menuState.canDuplicateActiveContentTab)
            XCTAssertFalse(menuState.canRestoreLastClosedTab)

            let menuStore = TestStore(initialState: menuState) { MenuCommandsFeature() }
            for command in [
                MenuCommandItem.AppCommand.newTab,
                .togglePinTab,
                .duplicateTab,
                .restoreLastClosedTab,
            ] {
                await menuStore.send(.view(.app(command)))
            }
            await menuStore.finish()

            let windowStore = TestStore(initialState: appState.windowManager) { WindowManagerFeature() }
            for action in [
                WindowManagerAction.file(.newTab),
                .file(.togglePinTab),
                .file(.duplicateTab),
                .file(.restoreLastClosedTab),
            ] {
                await windowStore.send(action)
            }
            await windowStore.finish()
        }
    }

    private func makeFocusedAppState(
        selectedCount: Int,
        activePinned: Bool = false,
    ) -> FocusedAppFixture {
        let focusedID = makeUUID("00000000-0000-0000-0000-000000000500")
        var window = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        guard let activeTabID = window.contentTabs.activeTabID else {
            preconditionFailure("Expected initial active content tab")
        }
        window.contentTabs.tabs[id: activeTabID]?.isPinned = activePinned

        while window.contentTabs.tabs.count < max(selectedCount, 1) {
            let index = window.contentTabs.tabs.count
            window.contentTabs.tabs.append(ContentTabItem(
                id: ContentTabID(rawValue: "selected-content-tab-\(index)"),
                page: .home,
                anchor: .homeDefault,
                isPinned: false,
                title: "Tab \(index + 1)",
                iconName: "house",
            ))
        }
        window.contentTabs.selectedTabIDs = Set(window.contentTabs.tabs.prefix(selectedCount).map(\.id))

        var appState = AppRootState()
        appState.windowManager.windows = [
            WindowSessionState(id: focusedID, window: window),
        ]
        appState.windowManager.focusedWindowID = focusedID
        return FocusedAppFixture(
            appState: appState,
            focusedID: focusedID,
            activeTabID: activeTabID,
        )
    }

    private func makeUUID(_ rawValue: String) -> UUID {
        guard let value = UUID(uuidString: rawValue) else {
            preconditionFailure("Invalid test UUID: \(rawValue)")
        }
        return value
    }

    private func makeMetricStore(
        fixture: FocusedAppFixture,
        operationID: UUID,
        metrics: LockIsolated<[FileManagerProductMetric]>,
    ) -> TestStoreOf<WindowManagerFeature> {
        let store = TestStore(initialState: fixture.appState.windowManager) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(makeUUID("00000000-0000-0000-0000-000000000509"))
            $0.date = .constant(Date(timeIntervalSince1970: 505))
            $0.fileManagerProductMetricsClient = FileManagerProductMetricsClient(
                record: { metric in metrics.withValue { $0.append(metric) } },
                makeOperationID: { operationID },
            )
            $0.fileManagerClient.fileExistsWithIsDirectory = { _, isDirectory in
                isDirectory?.pointee = true
                return true
            }
        }
        // store.exhaustivity = .off: app-to-package route의 terminal metric만 검증함
        store.exhaustivity = .off
        return store
    }

    private func assertCloseRoute(
        appState: AppRootState,
        focusedID: UUID,
        expectedRoute: ExpectedCloseRoute,
    ) async {
        let store = TestStore<WindowManagerFeature.State, WindowManagerFeature.Action>(
            initialState: appState.windowManager,
        ) {
            Reduce { (state: inout WindowManagerFeature.State, action: WindowManagerFeature.Action) in
                guard case .file(.closeTab) = action else { return .none }
                return WindowManagerFeature().reduce(into: &state, action: action)
            }
        }

        await store.send(.file(.closeTab))
        switch expectedRoute {
        case .active:
            await store.receive { action in
                guard case let .windows(.element(
                    id: id,
                    action: .window(.request(.contentTabAction(.closeActive, source: .menuCommand))),
                )) = action else {
                    return false
                }
                return id == focusedID
            }

        case .selected:
            await store.receive { action in
                guard case let .windows(.element(
                    id: id,
                    action: .window(.request(.contentTabAction(.closeSelected, source: .menuCommand))),
                )) = action else {
                    return false
                }
                return id == focusedID
            }
        }
        await store.finish()
    }
}
