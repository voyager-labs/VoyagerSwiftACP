// FLOW-ID: ctm.content_tab_browsing
import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
final class ContentTabBrowsingFlowTests: XCTestCase {
    // FLOW-PATH: semantic_app_command -> AppRoot production composition -> focused_window_final_active_identity

    /// CTM-002-set_current_content_tab_by_number: semantic position 3은 focused window의 세 번째 visible Content Tab을 활성화한다.
    /// production reducer composition 전체의 aggregate 결과로 focused window의 최종 active identity를 검증한다.
    /// - 검증 내용: focused window의 최종 active Content Tab identity
    /// - 사전 조건: 서로 다른 directory anchor를 가진 visible tab 세 개와 첫 번째 active 상태
    /// - 기대 결과: position 3 명령 뒤 focused window의 active tab identity가 세 번째 tab을 가리킨다.
    func testSemanticThirdPositionSelectsThirdVisibleTabInFocusedWindow() async throws {
        let firstID = ContentTabID(rawValue: "flow-first")
        let secondID = ContentTabID(rawValue: "flow-second")
        let thirdID = ContentTabID(rawValue: "flow-third")
        let window = makeContentTabBrowsingWindow(
            tabIDs: [firstID, secondID, thirdID],
            activeTabID: firstID,
        )

        let focusedWindowID = UUID()
        var initialState = AppRootState()
        initialState.windowManager.windows = [
            WindowSessionState(id: focusedWindowID, window: window),
        ]
        initialState.windowManager.focusedWindowID = focusedWindowID

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryLoadingClient.loadItems = { _, _ in [] }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in continuation.finish() }
            }
        }
        // store.exhaustivity = .off: production composition 내부 전달 action보다 aggregate 최종 active identity를 검증한다.
        store.exhaustivity = .off

        await store.send(.menuCommands(.view(.app(.selectContentTab(position: 3)))))
        await store.skipReceivedActions(strict: false)
        await store.finish()

        let focusedWindow = try XCTUnwrap(store.state.windowManager.windows[id: focusedWindowID]?.window)
        XCTAssertEqual(focusedWindow.contentTabs.activeTabID, thirdID)
    }

    // FLOW-PATH: MenuCommandsFeature -> WindowManagerFeature -> focused WindowSessionFeature -> FileManagerWindowFeature

    /// CTM-004-present_content_tab_switcher: focused window에만 Content Tab 전환기를 표시하고 닫는다.
    /// main-app menu command를 포함한 production reducer composition 전체의 aggregate 결과를 검증한다.
    /// - 검증 내용: pending window의 기존 command 전달, switcher command no-op, menu command routing, focused window
    /// presentation locality, sibling presentation absence, 양쪽 Content Tab snapshot 불변
    /// - 사전 조건: 실제 MenuCommandsFeature와 WindowManagerFeature 아래 서로 다른 Content Tab을 가진 두 WindowSessionFeature,
    /// open 완료 전 focused window identity
    /// - 기대 결과: pending focused window에서도 기존 command는 전달하지만 switcher는 표시하지 않고, open 완료 후 main-app
    /// menu command는 focused window만 표시하며, focused view dismiss action은 양쪽 window snapshot을 보존한 채 표시를 해제한다.
    func testFocusedWindowContentTabSwitcherPresentationIsLocal() async throws {
        let focusedWindowID = UUID()
        let siblingWindowID = UUID()
        let focusedTabIDs = [
            ContentTabID(rawValue: "focused-first"),
            ContentTabID(rawValue: "focused-second"),
        ]
        let siblingTabIDs = [
            ContentTabID(rawValue: "sibling-first"),
            ContentTabID(rawValue: "sibling-second"),
        ]

        var initialState = AppRootState()
        initialState.windowManager.windows = [
            WindowSessionState(
                id: focusedWindowID,
                window: makeContentTabBrowsingWindow(
                    tabIDs: focusedTabIDs,
                    activeTabID: focusedTabIDs[0],
                ),
            ),
            WindowSessionState(
                id: siblingWindowID,
                window: makeContentTabBrowsingWindow(
                    tabIDs: siblingTabIDs,
                    activeTabID: siblingTabIDs[1],
                ),
            ),
        ]
        initialState.windowManager.focusedWindowID = focusedWindowID
        initialState.windowManager.pendingWindowOpenIDs = [focusedWindowID]

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryLoadingClient.loadItems = { _, _ in [] }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in continuation.finish() }
            }
        }
        // store.exhaustivity = .off: aggregate flow asserts scoped presentation and complete Content Tab snapshots, not
        // internal effects.
        store.exhaustivity = .off

        var initialSnapshots: [UUID: ContentTabState] = [:]
        for windowID in [focusedWindowID, siblingWindowID] {
            initialSnapshots[windowID] = try XCTUnwrap(
                store.state.windowManager.windows[id: windowID]?.window.contentTabs,
            )
        }

        await store.send(.windowManager(.event(.windowBecameKey(focusedWindowID))))
        await store.send(.windowManager(.file(.quickLook)))
        await store.receive {
            guard case let .windowManager(.windows(.element(
                id: id,
                action: .window(.request(.quickLookSelectedItem)),
            ))) = $0
            else { return false }
            return id == focusedWindowID
        }
        await store.send(.menuCommands(.view(.app(.presentContentTabSwitcher))))
        await store.skipReceivedActions(strict: false)

        XCTAssertNil(
            store.state.windowManager.windows[id: focusedWindowID]?.window.contentTabSwitcherPresentation,
        )
        XCTAssertNil(
            store.state.windowManager.windows[id: siblingWindowID]?.window.contentTabSwitcherPresentation,
        )

        await store.send(.windowManager(.windowOpenCompleted(
            id: focusedWindowID,
            shouldBootstrapDefaultWindow: false,
            isRegistered: true,
        ))) {
            $0.windowManager.pendingWindowOpenIDs.remove(focusedWindowID)
        }

        await store.send(.menuCommands(.view(.app(.presentContentTabSwitcher))))
        await store.skipReceivedActions(strict: false)

        XCTAssertEqual(
            store.state.windowManager.windows[id: focusedWindowID]?.window.contentTabSwitcherPresentation,
            .init(source: .automatic),
        )
        XCTAssertNil(
            store.state.windowManager.windows[id: siblingWindowID]?.window.contentTabSwitcherPresentation,
        )
        for windowID in [focusedWindowID, siblingWindowID] {
            XCTAssertEqual(
                store.state.windowManager.windows[id: windowID]?.window.contentTabs,
                initialSnapshots[windowID],
            )
        }

        await store.send(.windowManager(.windows(.element(
            id: focusedWindowID,
            action: .window(.view(.dismissContentTabSwitcher)),
        ))))

        XCTAssertNil(
            store.state.windowManager.windows[id: focusedWindowID]?.window.contentTabSwitcherPresentation,
        )
        XCTAssertNil(
            store.state.windowManager.windows[id: siblingWindowID]?.window.contentTabSwitcherPresentation,
        )
        for windowID in [focusedWindowID, siblingWindowID] {
            XCTAssertEqual(
                store.state.windowManager.windows[id: windowID]?.window.contentTabs,
                initialSnapshots[windowID],
            )
        }
    }
}

private func makeContentTabBrowsingWindow(
    tabIDs: [ContentTabID],
    activeTabID: ContentTabID,
) -> FileManagerFeature.State {
    let tabs = IdentifiedArray(uniqueElements: tabIDs.map(makeContentTabBrowsingTab))
    var state = FileManagerFeature.State()
    state.contentTabs = ContentTabState(tabs: tabs, activeTabID: activeTabID)
    state.tabContentStates = Dictionary(uniqueKeysWithValues: tabIDs.map { id in
        (id, makeContentTabBrowsingContent(id: id))
    })
    state.content = makeContentTabBrowsingContent(id: activeTabID)
    state.syncContentTabSidebarItems()
    return state
}

private func makeContentTabBrowsingTab(id: ContentTabID) -> ContentTabItem {
    ContentTabItem(
        id: id,
        page: .directory,
        anchor: .directory(path: contentTabBrowsingPath(id: id)),
        isPinned: false,
        title: id.rawValue,
        iconName: "folder",
    )
}

private func makeContentTabBrowsingContent(id: ContentTabID) -> FileManagerContentFeature.State {
    var content = FileManagerContentFeature.State()
    content.navigation.seedInitialFolderPath(contentTabBrowsingPath(id: id))
    return content
}

private func contentTabBrowsingPath(id: ContentTabID) -> String {
    "/flow/content-tab/\(id.rawValue)"
}
