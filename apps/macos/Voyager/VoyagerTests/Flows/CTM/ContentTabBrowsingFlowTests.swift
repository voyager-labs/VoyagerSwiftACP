import Carbon.HIToolbox

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

    /// CTM-004-aggregate_content_tab_browsing: keyboard switcher ownership follows its window across key transitions.
    /// Window resign must dismiss the old window's keyboard-owned presentation before another window receives a new
    /// one.
    /// - 검증 내용: owner-window targeted presentation, window resign dismissal, sibling isolation
    /// - 사전 조건: 서로 다른 Content Tab을 가진 두 ready window와 focused window A
    /// - 기대 결과: A의 keyboard presentation만 닫히고 B에 새 keyboard presentation을 표시한다.
    func testKeyboardSwitcherOwnershipFollowsWindowResignAcrossReadyWindows() async {
        let ownerWindowID = UUID()
        let nextWindowID = UUID()
        var initialState = AppRootState()
        initialState.windowManager.windows = [
            WindowSessionState(
                id: ownerWindowID,
                window: makeContentTabBrowsingWindow(
                    tabIDs: [ContentTabID(rawValue: "owner-tab")],
                    activeTabID: ContentTabID(rawValue: "owner-tab"),
                ),
            ),
            WindowSessionState(
                id: nextWindowID,
                window: makeContentTabBrowsingWindow(
                    tabIDs: [ContentTabID(rawValue: "next-tab")],
                    activeTabID: ContentTabID(rawValue: "next-tab"),
                ),
            ),
        ]
        initialState.windowManager.focusedWindowID = ownerWindowID

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryLoadingClient.loadItems = { _, _ in [] }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in continuation.finish() }
            }
        }
        // store.exhaustivity = .off: this flow asserts owner-window presentation locality, not internal reducer
        // effects.
        store.exhaustivity = .off

        await store.send(.windowManager(.file(.presentContentTabSwitcherInWindow(
            windowID: ownerWindowID,
            source: .keyboardShortcut,
        ))))
        await store.skipReceivedActions(strict: false)
        XCTAssertEqual(
            store.state.windowManager.windows[id: ownerWindowID]?.window.contentTabSwitcherPresentation?.source,
            .keyboardShortcut,
        )
        XCTAssertNil(store.state.windowManager.windows[id: nextWindowID]?.window.contentTabSwitcherPresentation)

        await store.send(.windowManager(.event(.windowResignedKey(ownerWindowID))))
        await store.skipReceivedActions(strict: false)
        XCTAssertNil(store.state.windowManager.windows[id: ownerWindowID]?.window.contentTabSwitcherPresentation)

        await store.send(.windowManager(.event(.windowBecameKey(nextWindowID))))
        await store.send(.windowManager(.file(.presentContentTabSwitcherInWindow(
            windowID: nextWindowID,
            source: .keyboardShortcut,
        ))))
        await store.skipReceivedActions(strict: false)
        XCTAssertNil(store.state.windowManager.windows[id: ownerWindowID]?.window.contentTabSwitcherPresentation)
        XCTAssertEqual(
            store.state.windowManager.windows[id: nextWindowID]?.window.contentTabSwitcherPresentation?.source,
            .keyboardShortcut,
        )
    }

    /// CTM-004-aggregate_content_tab_browsing: keyboard-owned switcher activation은 owner window의 focused 후보만 확정한다.
    /// Control release semantic command가 source-matched WindowManager 경계를 거쳐 canonical setCurrent를 한 번 실행하는지 검증한다.
    /// - 검증 내용: targeted activation, presentation close, focused active/MRU 갱신, sibling isolation, setCurrent 1회
    /// - 사전 조건: 서로 다른 두 탭을 가진 focused ready window와 별도 sibling, keyboardShortcut presentation의 non-current focus
    /// - 기대 결과: focused 후보가 active가 되고 overlay는 닫히며 sibling은 불변이고 setCurrent는 정확히 한 번 기록된다.
    @MainActor
    func testKeyboardSwitcherActivationTargetsFocusedCandidateAndCloses() async throws {
        let focusedWindowID = UUID()
        let siblingWindowID = UUID()
        let currentID = ContentTabID(rawValue: "activation-current")
        let focusedID = ContentTabID(rawValue: "activation-focused")
        let siblingID = ContentTabID(rawValue: "activation-sibling")
        var focusedWindow = makeContentTabBrowsingWindow(
            tabIDs: [currentID, focusedID],
            activeTabID: currentID,
            recentlyUsedTabIDs: [currentID, focusedID],
        )
        focusedWindow.contentTabSwitcherPresentation = .init(
            source: .keyboardShortcut,
            candidateIDs: [currentID, focusedID],
            focusedCandidateID: focusedID,
        )
        var initialState = AppRootState()
        initialState.windowManager.windows = [
            WindowSessionState(id: focusedWindowID, window: focusedWindow),
            WindowSessionState(
                id: siblingWindowID,
                window: makeContentTabBrowsingWindow(tabIDs: [siblingID], activeTabID: siblingID),
            ),
        ]
        initialState.windowManager.focusedWindowID = focusedWindowID
        let siblingSnapshot = try XCTUnwrap(initialState.windowManager.windows[id: siblingWindowID]?.window.contentTabs)
        let setCurrentDispatchCount = LockIsolated(0)
        let store = TestStore(initialState: initialState) {
            CombineReducers {
                AppRootFeature()
                SetCurrentDispatchRecorder(count: setCurrentDispatchCount)
            }
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryLoadingClient.loadItems = { _, _ in [] }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in continuation.finish() }
            }
        }
        store.exhaustivity = .off // production handoff 내부 action보다 focused/sibling 최종 semantic state를 검증한다.

        await store.send(.windowManager(.file(.activateContentTabSwitcherInWindow(
            windowID: focusedWindowID,
            source: .keyboardShortcut,
        ))))
        await store.skipReceivedActions(strict: false)
        await store.finish()

        XCTAssertNil(store.state.windowManager.windows[id: focusedWindowID]?.window.contentTabSwitcherPresentation)
        XCTAssertEqual(
            store.state.windowManager.windows[id: focusedWindowID]?.window.contentTabs.activeTabID,
            focusedID,
        )
        XCTAssertEqual(
            store.state.windowManager.windows[id: focusedWindowID]?.window.contentTabs.recentlyUsedTabIDs,
            [focusedID, currentID],
        )
        XCTAssertEqual(store.state.windowManager.windows[id: siblingWindowID]?.window.contentTabs, siblingSnapshot)
        XCTAssertEqual(setCurrentDispatchCount.value, 1)
    }

    /// CTM-004-aggregate_content_tab_browsing: stale keyboard ownership cannot activate or dismiss a menu-owned
    /// switcher.
    /// External dismissal followed by a menu presentation must replace ownership without inheriting monitor
    /// activation/dismissal.
    /// - 검증 내용: external dismiss, source replacement, matching targeted activation/dismiss rejection
    /// - 사전 조건: focused ready window에 keyboard-owned switcher를 표시한 뒤 외부 dismiss와 menu present를 수행한다.
    /// - 기대 결과: stale keyboard activation과 dismiss는 automatic menu presentation을 변경하지 않는다.
    func testStaleKeyboardOwnershipCannotActivateOrDismissMenuOwnedSwitcher() async {
        let windowID = UUID()
        let tabID = ContentTabID(rawValue: "ownership-tab")
        var initialState = AppRootState()
        initialState.windowManager.windows = [
            WindowSessionState(
                id: windowID,
                window: makeContentTabBrowsingWindow(tabIDs: [tabID], activeTabID: tabID),
            ),
        ]
        initialState.windowManager.focusedWindowID = windowID

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryLoadingClient.loadItems = { _, _ in [] }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in continuation.finish() }
            }
        }
        // store.exhaustivity = .off: this flow asserts source ownership at the presentation boundary.
        store.exhaustivity = .off

        await store.send(.windowManager(.file(.presentContentTabSwitcherInWindow(
            windowID: windowID,
            source: .keyboardShortcut,
        ))))
        await store.skipReceivedActions(strict: false)
        await store.send(.windowManager(.windows(.element(
            id: windowID,
            action: .window(.view(.dismissContentTabSwitcher)),
        ))))
        await store.send(.menuCommands(.view(.app(.presentContentTabSwitcher))))
        await store.skipReceivedActions(strict: false)
        XCTAssertEqual(
            store.state.windowManager.windows[id: windowID]?.window.contentTabSwitcherPresentation?.source,
            .automatic,
        )

        await store.send(.windowManager(.file(.presentContentTabSwitcherInWindow(
            windowID: windowID,
            source: .keyboardShortcut,
        ))))
        await store.skipReceivedActions(strict: false)
        XCTAssertEqual(
            store.state.windowManager.windows[id: windowID]?.window.contentTabSwitcherPresentation?.source,
            .automatic,
        )

        await store.send(.windowManager(.file(.activateContentTabSwitcherInWindow(
            windowID: windowID,
            source: .keyboardShortcut,
        ))))
        await store.skipReceivedActions(strict: false)
        XCTAssertEqual(
            store.state.windowManager.windows[id: windowID]?.window.contentTabSwitcherPresentation?.source,
            .automatic,
        )

        await store.send(.windowManager(.file(.dismissContentTabSwitcherInWindow(
            windowID: windowID,
            source: .keyboardShortcut,
        ))))
        await store.skipReceivedActions(strict: false)
        XCTAssertEqual(
            store.state.windowManager.windows[id: windowID]?.window.contentTabSwitcherPresentation?.source,
            .automatic,
        )
    }

    /// CTM-004-aggregate_content_tab_browsing: pending Control+Tab is rejected after focus transfers before hold.
    /// 최신 focused window이 pending owner와 달라지면 stale hold가 백그라운드 window에 switcher를 표시하지 않는지 검증한다.
    /// - 검증 내용: pending owner와 최신 focused window 불일치 시 present 차단
    /// - 사전 조건: window A에서 Control+Tab pending 후 hold 전 window B로 focus 이동
    /// - 기대 결과: stale hold가 어떤 command도 방출하지 않는다.
    func testPendingKeyboardHoldRejectsAfterFocusedWindowTransfer() {
        let probe = ContentTabCancellationProbe()
        probe.focusedWindowID = UUID()
        _ = probe.monitor.handleKeyDownEvent(
            probe.event(timestamp: 10),
            context: probe.context,
            firstResponder: nil,
            emit: probe.emit,
            latestContext: { probe.context },
        )

        probe.focusedWindowID = UUID()
        probe.callbacks[0]()

        XCTAssertTrue(probe.commands.isEmpty)
    }

    /// CTM-004-aggregate_content_tab_browsing: pending Control+Tab is rejected after menu presentation.
    /// hold 직전에 automatic menu switcher가 표시되면 keyboard-owned presentation으로 덮어쓰지 않는지 검증한다.
    /// - 검증 내용: 기존 presentation 및 source 존재 시 stale present 차단
    /// - 사전 조건: Control+Tab pending 후 automatic presentation이 표시됨
    /// - 기대 결과: stale hold가 어떤 command도 방출하지 않는다.
    func testPendingKeyboardHoldRejectsExistingAutomaticPresentation() {
        let probe = ContentTabCancellationProbe()
        probe.focusedWindowID = UUID()
        _ = probe.monitor.handleKeyDownEvent(
            probe.event(timestamp: 10),
            context: probe.context,
            firstResponder: nil,
            emit: probe.emit,
            latestContext: { probe.context },
        )

        probe.contentTabSwitcherSource = .automatic
        probe.callbacks[0]()

        XCTAssertTrue(probe.commands.isEmpty)
    }

    // MARK: - CTM-004-aggregate_content_tab_browsing

    // FLOW-PATH: ControlTab semantic command -> AppRoot -> focused ready FileManager window

    /// CTM-004-aggregate_content_tab_browsing: short release activates focused MRU, while hold navigates and dismisses
    /// only its overlay.
    /// 실제 AppRoot production composition에서 두 ready window의 command locality와 activation 경계를 검증한다.
    /// - 검증 내용: short MRU active change, long presentation/focused-candidate navigation, Control release dismissal,
    /// stale threshold cancellation, complete focused/sibling Content Tab snapshots, no activation on long path
    /// - 사전 조건: 서로 다른 Content Tab semantic state를 가진 두 ready window와 focused window identity
    /// - 기대 결과: short path만 focused active identity를 바꾸고, long path는 focused overlay/focusedCandidateID만 바꾸며, Control
    /// release는 overlay만 닫고 app resign/monitor stop/token replacement의 stale callback은 window command를 만들지 않는다.
    @MainActor
    func testReadyWindowControlTabAggregateKeepsCommandsFocusedAndNonActivating() async throws {
        let focusedWindowID = UUID()
        let siblingWindowID = UUID()
        let focusedTabIDs = [
            ContentTabID(rawValue: "aggregate-focused-first"),
            ContentTabID(rawValue: "aggregate-focused-second"),
            ContentTabID(rawValue: "aggregate-focused-third"),
        ]
        let siblingTabIDs = [
            ContentTabID(rawValue: "aggregate-sibling-first"),
            ContentTabID(rawValue: "aggregate-sibling-second"),
        ]

        var initialState = AppRootState()
        initialState.windowManager.windows = [
            WindowSessionState(
                id: focusedWindowID,
                window: makeContentTabBrowsingWindow(
                    tabIDs: focusedTabIDs,
                    activeTabID: focusedTabIDs[0],
                    recentlyUsedTabIDs: focusedTabIDs,
                ),
            ),
            WindowSessionState(
                id: siblingWindowID,
                window: makeContentTabBrowsingWindow(
                    tabIDs: siblingTabIDs,
                    activeTabID: siblingTabIDs[1],
                    recentlyUsedTabIDs: siblingTabIDs,
                ),
            ),
        ]
        initialState.windowManager.focusedWindowID = focusedWindowID

        let setCurrentDispatchCount = LockIsolated(0)
        let store = TestStore(initialState: initialState) {
            CombineReducers {
                AppRootFeature()
                SetCurrentDispatchRecorder(count: setCurrentDispatchCount)
            }
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryLoadingClient.loadItems = { _, _ in [] }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in continuation.finish() }
            }
        }
        // store.exhaustivity = .off: production composition 내부 action보다 focused/sibling aggregate semantic 결과를 검증한다.
        store.exhaustivity = .off

        let initialFocusedSnapshot = try XCTUnwrap(store.state.windowManager.windows[id: focusedWindowID]?.window
            .contentTabs)
        let initialSiblingSnapshot = try XCTUnwrap(store.state.windowManager.windows[id: siblingWindowID]?.window
            .contentTabs)

        await store.send(.menuCommands(.view(.app(.selectMostRecentlyUsedContentTab))))
        await store.skipReceivedActions(strict: false)

        XCTAssertEqual(
            store.state.windowManager.windows[id: focusedWindowID]?.window.contentTabs.activeTabID,
            focusedTabIDs[1],
        )
        XCTAssertEqual(
            store.state.windowManager.windows[id: siblingWindowID]?.window.contentTabs,
            initialSiblingSnapshot,
        )
        XCTAssertNil(
            store.state.windowManager.windows[id: focusedWindowID]?.window.contentTabSwitcherPresentation,
        )
        XCTAssertNotEqual(
            store.state.windowManager.windows[id: focusedWindowID]?.window.contentTabs,
            initialFocusedSnapshot,
        )
        let setCurrentDispatchCountAfterShortPath = setCurrentDispatchCount.value

        let longPathSnapshots = try [
            focusedWindowID: XCTUnwrap(store.state.windowManager.windows[id: focusedWindowID]?.window.contentTabs),
            siblingWindowID: XCTUnwrap(store.state.windowManager.windows[id: siblingWindowID]?.window.contentTabs),
        ]

        await store.send(.menuCommands(.view(.app(.presentContentTabSwitcher))))
        await store.skipReceivedActions(strict: false)

        XCTAssertEqual(
            store.state.windowManager.windows[id: focusedWindowID]?.window.contentTabSwitcherPresentation?.source,
            .automatic,
        )
        XCTAssertEqual(
            store.state.windowManager.windows[id: focusedWindowID]?.window.contentTabSwitcherPresentation?
                .focusedCandidateID,
            focusedTabIDs[1],
        )
        XCTAssertNil(store.state.windowManager.windows[id: siblingWindowID]?.window.contentTabSwitcherPresentation)
        XCTAssertEqual(
            store.state.windowManager.windows[id: focusedWindowID]?.window.contentTabs,
            longPathSnapshots[focusedWindowID],
        )
        XCTAssertEqual(
            store.state.windowManager.windows[id: siblingWindowID]?.window.contentTabs,
            longPathSnapshots[siblingWindowID],
        )

        await store.send(.menuCommands(.view(.app(.movePreviousContentTabSwitcher))))
        await store.skipReceivedActions(strict: false)

        XCTAssertEqual(
            store.state.windowManager.windows[id: focusedWindowID]?.window.contentTabSwitcherPresentation?
                .focusedCandidateID,
            focusedTabIDs[2],
        )
        XCTAssertEqual(
            store.state.windowManager.windows[id: focusedWindowID]?.window.contentTabs,
            longPathSnapshots[focusedWindowID],
        )
        XCTAssertEqual(
            store.state.windowManager.windows[id: siblingWindowID]?.window.contentTabs,
            longPathSnapshots[siblingWindowID],
        )

        await store.send(.menuCommands(.view(.app(.moveNextContentTabSwitcher))))
        await store.skipReceivedActions(strict: false)

        XCTAssertEqual(
            store.state.windowManager.windows[id: focusedWindowID]?.window.contentTabSwitcherPresentation?
                .focusedCandidateID,
            focusedTabIDs[1],
        )
        XCTAssertEqual(
            store.state.windowManager.windows[id: focusedWindowID]?.window.contentTabs,
            longPathSnapshots[focusedWindowID],
        )
        XCTAssertEqual(
            store.state.windowManager.windows[id: siblingWindowID]?.window.contentTabs,
            longPathSnapshots[siblingWindowID],
        )

        await store.send(.menuCommands(.view(.app(.dismissContentTabSwitcher))))
        await store.skipReceivedActions(strict: false)

        XCTAssertNil(store.state.windowManager.windows[id: focusedWindowID]?.window.contentTabSwitcherPresentation)
        XCTAssertNil(store.state.windowManager.windows[id: siblingWindowID]?.window.contentTabSwitcherPresentation)
        XCTAssertEqual(
            store.state.windowManager.windows[id: focusedWindowID]?.window.contentTabs,
            longPathSnapshots[focusedWindowID],
        )
        XCTAssertEqual(
            store.state.windowManager.windows[id: siblingWindowID]?.window.contentTabs,
            longPathSnapshots[siblingWindowID],
        )
        XCTAssertEqual(setCurrentDispatchCount.value, setCurrentDispatchCountAfterShortPath)

        for cancellation in [CancellationCase.resignActive, .stop] {
            let probe = ContentTabCancellationProbe()
            _ = probe.monitor.handleKeyDownEvent(
                probe.event(timestamp: 10),
                context: probe.context,
                firstResponder: nil,
                emit: probe.emit,
            )
            switch cancellation {
            case .resignActive:
                probe.monitor.applicationDidResignActive()
            case .stop:
                probe.monitor.stop()
            }
            probe.callbacks[0]()
            XCTAssertTrue(probe.commands.isEmpty, "stale threshold emitted a window command: \(cancellation)")
        }

        let replacementProbe = ContentTabCancellationProbe()
        _ = replacementProbe.monitor.handleKeyDownEvent(
            replacementProbe.event(timestamp: 10),
            context: replacementProbe.context,
            firstResponder: nil,
            emit: replacementProbe.emit,
        )
        _ = replacementProbe.monitor.handleKeyUpEvent(
            replacementProbe.event(timestamp: 10.1, type: .keyUp),
            context: replacementProbe.context,
            emit: replacementProbe.emit,
        )
        _ = replacementProbe.monitor.handleKeyDownEvent(
            replacementProbe.event(timestamp: 11),
            context: replacementProbe.context,
            firstResponder: nil,
            emit: replacementProbe.emit,
        )
        replacementProbe.callbacks[0]()
        XCTAssertEqual(replacementProbe.commands, [.immediateMostRecentlyUsed])

        replacementProbe.callbacks[1]()
        XCTAssertEqual(replacementProbe.commands, [.immediateMostRecentlyUsed, .presentSwitcher])
    }
}

private func makeContentTabBrowsingWindow(
    tabIDs: [ContentTabID],
    activeTabID: ContentTabID,
    recentlyUsedTabIDs: [ContentTabID] = [],
) -> FileManagerFeature.State {
    let tabs = IdentifiedArray(uniqueElements: tabIDs.map(makeContentTabBrowsingTab))
    var state = FileManagerFeature.State()
    state.contentTabs = ContentTabState(
        tabs: tabs,
        activeTabID: activeTabID,
        recentlyUsedTabIDs: recentlyUsedTabIDs,
    )
    state.tabContentStates = Dictionary(uniqueKeysWithValues: tabIDs.map { id in
        (id, makeContentTabBrowsingContent(id: id))
    })
    state.content = makeContentTabBrowsingContent(id: activeTabID)
    state.syncContentTabSidebarItems()
    return state
}

private enum CancellationCase: CustomStringConvertible {
    case resignActive
    case stop

    var description: String {
        switch self {
        case .resignActive: "resign-active"
        case .stop: "monitor-stop"
        }
    }
}

private struct SetCurrentDispatchRecorder: Reducer {
    typealias State = AppRootState
    typealias Action = AppRootAction

    let count: LockIsolated<Int>

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            if case let .windowManager(.windows(.element(
                id: windowID,
                action: .window(.contentTabs(.setCurrent)),
            ))) = action {
                _ = windowID
                count.withValue { $0 += 1 }
            }
            return .none
        }
    }
}

@MainActor
private final class ContentTabCancellationProbe {
    var callbacks: [() -> Void] = []
    var commands: [AppKeyboardShortcutMonitor.ControlTabGestureCommand] = []
    var focusedWindowID: WindowManagerState.WindowID? = UUID()
    var contentTabSwitcherSource: FileManagerContentTabSwitcherPresentation.Source?
    var context: AppKeyboardShortcutMonitor.ContentTabShortcutContext {
        .init(
            hasFocusedWindow: focusedWindowID != nil,
            isComposerPresented: false,
            isContentTabSwitcherPresented: contentTabSwitcherSource != nil,
            focusedWindowID: focusedWindowID,
            contentTabSwitcherSource: contentTabSwitcherSource,
        )
    }

    lazy var monitor = AppKeyboardShortcutMonitor(
        holdScheduler: .init { [weak self] _, callback in
            self?.callbacks.append(callback)
        },
    )

    func emit(_ command: AppKeyboardShortcutMonitor.ControlTabGestureCommand) {
        commands.append(command)
    }

    func event(
        timestamp: TimeInterval,
        type: NSEvent.EventType = .keyDown,
    ) -> NSEvent {
        guard let event = NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: [.control],
            timestamp: timestamp,
            windowNumber: 0,
            context: nil,
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            isARepeat: false,
            keyCode: UInt16(kVK_Tab),
        ) else {
            preconditionFailure("Control+Tab test event must be constructible")
        }
        return event
    }
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
