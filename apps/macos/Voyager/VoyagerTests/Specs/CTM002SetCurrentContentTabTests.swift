import AppKit
import Carbon.HIToolbox
import ComposableArchitecture
@testable import Voyager
import VoyagerPagesFileManager
import XCTest

@MainActor
final class CTM002SetCurrentContentTabTests: XCTestCase {
    // MARK: - CTM-002-set_current_content_tab_by_number

    /// CTM-002-set_current_content_tab_by_number: 물리 숫자열과 키패드는 키보드 레이아웃과 무관하게 위치를 분류한다.
    /// 사용자가 Command+1...9를 입력할 때 번역된 문자가 달라도 동일한 물리 키 위치로 해석되는지 검증한다.
    /// - 검증 내용: 숫자열·키패드 keyCode와 Shift·Caps Lock·numericPad flag를 1-based position으로 변환함
    /// - 사전 조건: 각 위치의 Carbon virtual key code에 Command와 허용 가능한 보조 flag를 조합함
    /// - 기대 결과: 숫자열과 키패드의 모든 1...9 입력이 정확한 position을 반환함
    func testShortcutClassifierUsesPhysicalDigitKeyCodesAcrossLayouts() {
        let keyCodes: [(UInt16, Int)] = [
            (UInt16(kVK_ANSI_1), 1), (UInt16(kVK_ANSI_Keypad1), 1),
            (UInt16(kVK_ANSI_2), 2), (UInt16(kVK_ANSI_Keypad2), 2),
            (UInt16(kVK_ANSI_3), 3), (UInt16(kVK_ANSI_Keypad3), 3),
            (UInt16(kVK_ANSI_4), 4), (UInt16(kVK_ANSI_Keypad4), 4),
            (UInt16(kVK_ANSI_5), 5), (UInt16(kVK_ANSI_Keypad5), 5),
            (UInt16(kVK_ANSI_6), 6), (UInt16(kVK_ANSI_Keypad6), 6),
            (UInt16(kVK_ANSI_7), 7), (UInt16(kVK_ANSI_Keypad7), 7),
            (UInt16(kVK_ANSI_8), 8), (UInt16(kVK_ANSI_Keypad8), 8),
            (UInt16(kVK_ANSI_9), 9), (UInt16(kVK_ANSI_Keypad9), 9),
        ]
        let allowedModifiers: [NSEvent.ModifierFlags] = [
            [.command],
            [.command, .shift],
            [.command, .capsLock],
            [.command, .numericPad],
            [.command, .shift, .capsLock, .numericPad],
        ]

        for (keyCode, position) in keyCodes {
            for modifiers in allowedModifiers {
                XCTAssertEqual(
                    AppKeyboardShortcutMonitor.contentTabPosition(
                        keyCode: keyCode,
                        modifierFlags: modifiers,
                    ),
                    position,
                )
            }
        }
    }

    /// CTM-002-set_current_content_tab_by_number: 범위 밖 물리 키와 금지 modifier 조합은 shortcut으로 소비하지 않는다.
    /// 입력이 정확한 Command+1...9 물리 키 조합이 아닐 때 기존 responder 경로로 통과할 수 있도록 검증한다.
    /// - 검증 내용: 0·문자 keyCode와 Command 없는 입력 및 Option·Control·Function 조합을 거부함
    /// - 사전 조건: 지원하지 않는 대표 keyCode와 modifier matrix를 사용함
    /// - 기대 결과: 모든 입력이 nil을 반환해 event 처리 대상에서 제외됨
    func testShortcutClassifierRejectsUnhandledKeyCodesAndModifiers() {
        let rejectedInputs: [(UInt16, NSEvent.ModifierFlags)] = [
            (UInt16(kVK_ANSI_0), [.command]),
            (UInt16(kVK_ANSI_Keypad0), [.command, .numericPad]),
            (UInt16(kVK_ANSI_A), [.command]),
            (UInt16(kVK_ANSI_1), []),
            (UInt16(kVK_ANSI_1), [.capsLock]),
            (UInt16(kVK_ANSI_1), [.command, .option]),
            (UInt16(kVK_ANSI_1), [.command, .control]),
            (UInt16(kVK_ANSI_1), [.command, .function]),
            (UInt16(kVK_ANSI_1), [.command, .shift, .option]),
            (UInt16(kVK_ANSI_Keypad1), [.command, .numericPad, .control]),
        ]

        for (keyCode, modifiers) in rejectedInputs {
            XCTAssertNil(
                AppKeyboardShortcutMonitor.contentTabPosition(
                    keyCode: keyCode,
                    modifierFlags: modifiers,
                ),
            )
        }
    }

    /// CTM-002-set_current_content_tab_by_number: 텍스트 편집 responder는 숫자 shortcut event를 그대로 받는다.
    /// Search·NSTextField field editor·AI Composer 입력 중 탭 전환 callback이 실행되지 않는지 검증한다.
    /// - 검증 내용: NSTextField와 NSTextView에서 event identity와 callback count를 보존함
    /// - 사전 조건: focused live window가 있고 유효한 Command+1 event가 text responder에 전달됨
    /// - 기대 결과: 원본 event가 반환되고 Content Tab 선택 callback은 호출되지 않음
    func testShortcutMonitorPassesThroughTextEditingResponders() {
        let responders: [NSResponder] = [NSTextField(), NSTextView()]

        for responder in responders {
            var selectedPositions: [Int] = []
            let handled = AppKeyboardShortcutMonitor.handleKeyDown(
                keyCode: UInt16(kVK_ANSI_1),
                modifierFlags: [.command],
                context: .init(hasFocusedWindow: true, isComposerPresented: false),
                firstResponder: responder,
                onSelectContentTab: { selectedPositions.append($0) },
            )

            XCTAssertFalse(handled)
            XCTAssertTrue(selectedPositions.isEmpty)
        }
    }

    /// CTM-002-set_current_content_tab_by_number: focused Composer 또는 focused window 부재 시 event를 소비하지 않는다.
    /// 앱 입력 문맥이 Content Tab 전환을 허용하지 않을 때 local monitor의 pass-through 결정을 검증한다.
    /// - 검증 내용: Composer 표시와 no-focus context에서 event identity와 callback count를 보존함
    /// - 사전 조건: 유효한 Command+1 event와 각각의 비허용 runtime context를 사용함
    /// - 기대 결과: 원본 event가 반환되고 Content Tab 선택 callback은 호출되지 않음
    func testShortcutMonitorPassesThroughUnavailableRuntimeContexts() {
        let contexts: [AppKeyboardShortcutMonitor.ContentTabShortcutContext] = [
            .init(hasFocusedWindow: true, isComposerPresented: true),
            .unavailable,
        ]

        for context in contexts {
            var selectedPositions: [Int] = []
            let handled = AppKeyboardShortcutMonitor.handleKeyDown(
                keyCode: UInt16(kVK_ANSI_1),
                modifierFlags: [.command],
                context: context,
                firstResponder: nil,
                onSelectContentTab: { selectedPositions.append($0) },
            )

            XCTAssertFalse(handled)
            XCTAssertTrue(selectedPositions.isEmpty)
        }
    }

    /// CTM-002-set_current_content_tab_by_number: 허용된 Shift 필요 레이아웃 입력은 한 번 처리하고 event를 소비한다.
    /// AZERTY처럼 번역 문자가 숫자가 아니어도 물리 keyCode와 runtime context로 탭 위치를 선택하는지 검증한다.
    /// - 검증 내용: Command+Shift 물리 1 key가 position 1 callback을 한 번 호출하고 nil을 반환함
    /// - 사전 조건: focused live window, 닫힌 Composer, 비텍스트 responder와 번역 문자 `&`를 사용함
    /// - 기대 결과: position 1만 전달되고 event는 이후 responder로 전파되지 않음
    func testShortcutMonitorHandlesAllowedPhysicalKeyExactlyOnce() {
        var selectedPositions: [Int] = []

        let handled = AppKeyboardShortcutMonitor.handleKeyDown(
            keyCode: UInt16(kVK_ANSI_1),
            modifierFlags: [.command, .shift],
            context: .init(hasFocusedWindow: true, isComposerPresented: false),
            firstResponder: nil,
            onSelectContentTab: { selectedPositions.append($0) },
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(selectedPositions, [1])
    }

    /// CTM-002-set_current_content_tab_by_number: monitor adapter는 미처리 event를 보존하고 처리 event만 소비한다.
    /// 실제 local monitor closure의 반환 계약과 callback 단일 실행을 함께 검증한다.
    /// - 검증 내용: text responder에서는 동일 NSEvent identity를 반환하고 허용 context에서는 nil과 position 1을 반환함
    /// - 사전 조건: 물리 Command+1 NSEvent, focused live window, text/non-text responder를 사용함
    /// - 기대 결과: pass-through event는 그대로 전달되고 처리 event만 한 번 소비됨
    func testShortcutMonitorAdapterPreservesOrConsumesEvent() throws {
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "1",
                charactersIgnoringModifiers: "1",
                isARepeat: false,
                keyCode: UInt16(kVK_ANSI_1),
            ),
        )
        let context = AppKeyboardShortcutMonitor.ContentTabShortcutContext(
            hasFocusedWindow: true,
            isComposerPresented: false,
        )
        var selectedPositions: [Int] = []

        let passedThrough = AppKeyboardShortcutMonitor.processKeyDownEvent(
            event,
            context: context,
            firstResponder: NSTextField(),
            onSelectContentTab: { selectedPositions.append($0) },
        )
        XCTAssertIdentical(passedThrough, event)
        XCTAssertTrue(selectedPositions.isEmpty)

        let consumed = AppKeyboardShortcutMonitor.processKeyDownEvent(
            event,
            context: context,
            firstResponder: nil,
            onSelectContentTab: { selectedPositions.append($0) },
        )
        XCTAssertNil(consumed)
        XCTAssertEqual(selectedPositions, [1])
    }

    /// CTM-002-set_current_content_tab_by_number: 첫 번째 위치 명령은 semantic position 1을 AppRoot까지 전달한다.
    /// 사용자가 첫 번째 Content Tab 단축키를 실행할 때 위치 값이 app command 경로에서 보존되는지 검증한다.
    /// - 검증 내용: MenuCommands delegate와 AppRoot의 WindowManager file command가 position 1을 유지함
    /// - 사전 조건: 기본 AppRoot 상태에서 semantic `selectContentTab(position: 1)` app command를 전송함
    /// - 기대 결과: position 1의 WindowManager file command가 AppRoot에서 한 번 전달됨
    func testFirstPositionCommandForwardsSemanticPositionThroughAppRoot() async {
        let store = TestStore(initialState: AppRootState()) {
            AppRootFeature()
        }

        await store.send(.menuCommands(.view(.app(.selectContentTab(position: 1)))))
        await store.receive {
            guard case .menuCommands(.delegate(.windowManager(.file(.selectContentTab(position: 1))))) = $0 else {
                return false
            }
            return true
        }
        await store.receive {
            guard case .windowManager(.file(.selectContentTab(position: 1))) = $0 else { return false }
            return true
        }
    }

    /// CTM-002-set_current_content_tab_by_number: 아홉 번째 위치 명령은 semantic position 9를 AppRoot까지 전달한다.
    /// 사용자가 아홉 번째 Content Tab 단축키를 실행할 때 위치 값이 app command 경로에서 보존되는지 검증한다.
    /// - 검증 내용: MenuCommands delegate와 AppRoot의 WindowManager file command가 position 9를 유지함
    /// - 사전 조건: 기본 AppRoot 상태에서 semantic `selectContentTab(position: 9)` app command를 전송함
    /// - 기대 결과: position 9의 WindowManager file command가 AppRoot에서 한 번 전달됨
    func testNinthPositionCommandForwardsSemanticPositionThroughAppRoot() async {
        let store = TestStore(initialState: AppRootState()) {
            AppRootFeature()
        }

        await store.send(.menuCommands(.view(.app(.selectContentTab(position: 9)))))
        await store.receive {
            guard case .menuCommands(.delegate(.windowManager(.file(.selectContentTab(position: 9))))) = $0 else {
                return false
            }
            return true
        }
        await store.receive {
            guard case .windowManager(.file(.selectContentTab(position: 9))) = $0 else { return false }
            return true
        }
    }

    /// CTM-002-set_current_content_tab_by_number: 위치 명령은 focused live File Manager window 한 곳으로 전달한다.
    /// 사용자가 Content Tab 위치 단축키를 실행할 때 현재 focused session이 semantic request를 받는지 검증한다.
    /// - 검증 내용: `.file(.selectContentTab(position: 4))`가 focused session의 exact window request를 방출함
    /// - 사전 조건: focused live File Manager window 한 개가 존재함
    /// - 기대 결과: focused session이 `.window(.request(.selectContentTab(position: 4)))`를 한 번 수신함
    func testPositionCommandRoutesToFocusedLiveWindow() async {
        let focusedID = UUID()
        let store = makeWindowManagerStore(initialState: makeWindowManagerState(
            focusedID: focusedID,
            windows: [(focusedID, "/focused")],
        ))

        // store.exhaustivity = .off: app 라우팅 이후 package reducer의 상태 변경은 package spec suite가 검증한다.
        store.exhaustivity = .off

        await store.send(.file(.selectContentTab(position: 4)))
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.request(command)))) = action,
                  case let .selectContentTab(position: position) = command
            else {
                return false
            }
            return id == focusedID && position == 4
        }
    }

    /// CTM-002-set_current_content_tab_by_number: focus가 없거나 focused session이 없으면 위치 명령을 전달하지 않는다.
    /// 유효한 focused File Manager session이 없는 상태에서 다른 window로 fallback하지 않는지 검증한다.
    /// - 검증 내용: nil focus와 누락된 focused ID 모두 semantic window request를 방출하지 않음
    /// - 사전 조건: background window만 존재하고 focus는 nil이거나 존재하지 않는 session ID를 가리킴
    /// - 기대 결과: background window가 위치 명령을 받지 않고 두 입력 모두 no-op으로 종료됨
    func testPositionCommandDoesNotFallbackWithoutFocusedSession() async {
        let backgroundID = UUID()
        let noFocusStore = makeWindowManagerStore(initialState: makeWindowManagerState(
            focusedID: nil,
            windows: [(backgroundID, "/background")],
        ))

        await noFocusStore.send(.file(.selectContentTab(position: 2)))

        let missingFocusedID = UUID()
        let missingSessionStore = makeWindowManagerStore(initialState: makeWindowManagerState(
            focusedID: missingFocusedID,
            windows: [(backgroundID, "/background")],
        ))

        await missingSessionStore.send(.file(.selectContentTab(position: 3)))
    }

    /// CTM-002-set_current_content_tab_by_number: closing focused window에는 위치 명령을 전달하지 않는다.
    /// focused session이 닫히는 동안 사용자가 위치 단축키를 실행해도 다른 live window로 fallback하지 않는지 검증한다.
    /// - 검증 내용: closing focused ID를 차단하고 background session에 semantic request를 보내지 않음
    /// - 사전 조건: focused window는 closing 집합에 있고 별도의 live background window가 존재함
    /// - 기대 결과: 두 window 모두 위치 명령을 받지 않고 입력이 no-op으로 종료됨
    func testPositionCommandDoesNotRouteWhileFocusedWindowIsClosing() async {
        let focusedID = UUID()
        let backgroundID = UUID()
        let store = makeWindowManagerStore(initialState: makeWindowManagerState(
            focusedID: focusedID,
            windows: [(focusedID, "/focused"), (backgroundID, "/background")],
            closingWindowIDs: [focusedID],
        ))

        await store.send(.file(.selectContentTab(position: 6)))
    }

    /// CTM-002-set_current_content_tab_by_number: focused window close 전환 중에는 후속 window로 추측 라우팅하지 않는다.
    /// focused A를 닫고 B가 실제 key window가 되기 전에 숫자 shortcut이 no-op인지 검증한다.
    /// - 검증 내용: close 시작은 focus를 nil로 만들고 MRU를 보존하며 pre-key 숫자 명령은 action을 방출하지 않음
    /// - 사전 조건: A가 focused, B가 background이고 MRU가 A, B 순서인 live window 두 개가 존재함
    /// - 기대 결과: close 호출 후 focus가 nil이고 became-key 전 숫자 명령이 B에 전달되지 않음
    func testPositionCommandWaitsForActualBecameKeyAfterClosingFocusedWindow() async {
        let focusedID = UUID()
        let backgroundID = UUID()
        let closedIDs = LockIsolated<[UUID]>([])
        var initialState = makeWindowManagerState(
            focusedID: focusedID,
            windows: [(focusedID, "/focused"), (backgroundID, "/background")],
        )
        initialState.lastUsedWindowIDs = [focusedID, backgroundID]
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.fileManagerWindowClient.close = { id in
                closedIDs.withValue { $0.append(id) }
            }
        }

        await store.send(.window(.closeFocusedWindow)) {
            $0.closingWindowIDs.insert(focusedID)
            $0.focusedWindowID = nil
            $0.refreshContentTabMoveTargets()
        }
        XCTAssertEqual(store.state.lastUsedWindowIDs, [focusedID, backgroundID])
        XCTAssertEqual(closedIDs.value, [focusedID])

        await store.send(.file(.selectContentTab(position: 6)))
        await store.finish()
    }

    /// CTM-002-set_current_content_tab_by_number: 두 window 중 focused A만 위치 명령을 받는다.
    /// 여러 File Manager window가 열린 상태에서 위치 단축키가 focused session 경계를 넘지 않는지 검증한다.
    /// - 검증 내용: exact semantic request의 대상 ID가 A이고 background B의 app-owned session state는 불변임
    /// - 사전 조건: A가 focused이고 B가 background인 live window 두 개가 존재함
    /// - 기대 결과: A만 `.selectContentTab(position: 8)` request를 받고 B 상태는 변경되지 않음
    func testPositionCommandIsolatedToFocusedWindowAmongTwoWindows() async {
        let focusedID = UUID()
        let backgroundID = UUID()
        let store = makeWindowManagerStore(initialState: makeWindowManagerState(
            focusedID: focusedID,
            windows: [(focusedID, "/focused"), (backgroundID, "/background")],
        ))
        let backgroundBefore = store.state.windows[id: backgroundID]

        // store.exhaustivity = .off: app 라우팅 이후 focused child의 package-owned 상태 변경은 이 suite의 소유 범위가 아니다.
        store.exhaustivity = .off

        await store.send(.file(.selectContentTab(position: 8)))
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.request(command)))) = action,
                  case let .selectContentTab(position: position) = command
            else {
                return false
            }
            return id == focusedID && position == 8
        }

        XCTAssertEqual(store.state.windows[id: backgroundID], backgroundBefore)
    }

    // MARK: - CTM-002-set_current_content_tab_to_last_used

    /// CTM-002-set_current_content_tab_to_last_used: 최근 사용 전환 명령을 AppRoot와 focused window로 전달
    /// Go 메뉴의 Ctrl-Tab 의미 명령이 숫자 위치 없이 focused File Manager session까지 보존되는지 검증한다.
    /// - 검증 내용: MenuCommands delegate, WindowManager file command, exact window request의 연속 라우팅
    /// - 사전 조건: focused live File Manager window 한 개와 semantic recently-used app command
    /// - 기대 결과: focused session이 `.selectMostRecentlyUsedContentTab` request를 한 번 수신함
    func testMostRecentlyUsedCommandRoutesThroughAppRootToFocusedWindow() async {
        let appStore = TestStore(initialState: AppRootState()) {
            AppRootFeature()
        }

        await appStore.send(.menuCommands(.view(.app(.selectMostRecentlyUsedContentTab))))
        await appStore.receive {
            guard case .menuCommands(.delegate(.windowManager(.file(.selectMostRecentlyUsedContentTab)))) = $0 else {
                return false
            }
            return true
        }
        await appStore.receive {
            guard case .windowManager(.file(.selectMostRecentlyUsedContentTab)) = $0 else { return false }
            return true
        }

        let focusedID = UUID()
        let windowStore = makeWindowManagerStore(initialState: makeWindowManagerState(
            focusedID: focusedID,
            windows: [(focusedID, "/focused")],
        ))
        // store.exhaustivity = .off: app 라우팅 이후 package reducer의 MRU 상태 변경은 package spec suite가 검증한다.
        windowStore.exhaustivity = .off

        await windowStore.send(.file(.selectMostRecentlyUsedContentTab))
        await windowStore.receive { action in
            guard case let .windows(.element(id: id, action: .window(.request(command)))) = action,
                  case .selectMostRecentlyUsedContentTab = command
            else {
                return false
            }
            return id == focusedID
        }
    }

    private func makeWindowManagerStore(
        initialState: WindowManagerFeature.State,
    ) -> TestStore<WindowManagerFeature.State, WindowManagerFeature.Action> {
        TestStore(initialState: initialState) {
            WindowManagerFeature()
        }
    }

    private func makeWindowManagerState(
        focusedID: UUID?,
        windows: [(UUID, String?)],
        closingWindowIDs: Set<UUID> = [],
    ) -> WindowManagerFeature.State {
        var state = WindowManagerFeature.State()
        state.windows = .init(uniqueElements: windows.map { id, path in
            WindowSessionState(id: id, window: .makeInitial(path: path))
        })
        state.focusedWindowID = focusedID
        state.closingWindowIDs = closingWindowIDs
        return state
    }
}
