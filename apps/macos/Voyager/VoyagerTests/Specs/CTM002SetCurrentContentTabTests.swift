import AppKit
import ComposableArchitecture
@testable import Voyager
import VoyagerPagesFileManager
import XCTest

@MainActor
final class CTM002SetCurrentContentTabTests: XCTestCase {
    // MARK: - CTM-002-set_current_content_tab_by_number

    /// CTM-002-set_current_content_tab_by_number: Command와 허용 가능한 보조 flag가 숫자 위치를 분류한다.
    /// 사용자가 Command+1...9를 입력할 때 Caps Lock과 숫자 키패드 상태가 있어도 같은 위치로 해석되는지 검증한다.
    /// - 검증 내용: key 문자와 modifier flag를 순수 분류기가 1-based position으로 변환함
    /// - 사전 조건: 각 숫자에 Command를 포함하고 Caps Lock 또는 numericPad flag를 선택적으로 조합함
    /// - 기대 결과: 모든 1...9 입력이 정확히 대응하는 position을 반환함
    func testShortcutClassifierAcceptsCommandDigitsWithHarmlessFlags() {
        let harmlessModifiers: [NSEvent.ModifierFlags] = [
            [.command],
            [.command, .capsLock],
            [.command, .numericPad],
            [.command, .capsLock, .numericPad],
        ]

        for position in 1 ... 9 {
            for modifiers in harmlessModifiers {
                XCTAssertEqual(
                    AppKeyboardShortcutMonitor.contentTabPosition(
                        charactersIgnoringModifiers: String(position),
                        modifierFlags: modifiers,
                    ),
                    position,
                )
            }
        }
    }

    /// CTM-002-set_current_content_tab_by_number: 범위 밖 문자와 금지 modifier 조합은 shortcut으로 소비하지 않는다.
    /// 숫자 입력이 정확한 Command+1...9 chord가 아닐 때 기존 responder 경로로 통과할 수 있도록 분류 결과를 검증한다.
    /// - 검증 내용: nil·다문자·비숫자·0·plain digit와 Shift/Option/Control/Function 조합을 거부함
    /// - 사전 조건: Command가 없거나 금지 modifier가 섞인 대표 key 입력 matrix를 사용함
    /// - 기대 결과: 모든 입력이 nil을 반환해 event 처리 대상에서 제외됨
    func testShortcutClassifierRejectsUnhandledKeysAndModifiers() {
        let rejectedInputs: [(String?, NSEvent.ModifierFlags)] = [
            (nil, [.command]),
            ("", [.command]),
            ("0", [.command]),
            ("10", [.command]),
            ("a", [.command]),
            ("1", []),
            ("1", [.capsLock]),
            ("1", [.command, .shift]),
            ("1", [.command, .option]),
            ("1", [.command, .control]),
            ("1", [.command, .function]),
            ("1", [.command, .capsLock, .shift]),
            ("1", [.command, .numericPad, .option]),
        ]

        for (characters, modifiers) in rejectedInputs {
            XCTAssertNil(
                AppKeyboardShortcutMonitor.contentTabPosition(
                    charactersIgnoringModifiers: characters,
                    modifierFlags: modifiers,
                ),
            )
        }
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
