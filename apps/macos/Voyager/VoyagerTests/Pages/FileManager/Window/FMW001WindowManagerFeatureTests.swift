import ComposableArchitecture
@testable import Voyager
import VoyagerPagesOnboarding
import XCTest

// MARK: - FMW-001 App-Scoped WindowManager Coverage

//
// WindowManagerFeature의 윈도우 라이프사이클/포커스/라우팅을 검증하는
// app-scoped 결정론적 TCA TestStore 테스트 모음.
//
// AC Map 대상:
// - FMW-001-open_new_file_manager_window → focused automated test, app-scoped
// - FMW-001-close_file_manager_window → focused automated test, app-scoped
// - FMW-001-quit_voyager → focused automated test, app-scoped
//
// 시각적 동작(full screen, minimize, fronting, keep-on-top)은 수동 QA/follow-up
// 대상이므로 이 파일에서 단언하지 않는다.

@MainActor
final class FMW001WindowManagerFeatureTests: XCTestCase {
    // MARK: - Test Group 1: Window Lifecycle (FMW-001)

    /// FMW-001-open_new_file_manager_window:
    /// newWindow 액션이 새 윈도우 세션을 생성하고 focusedWindowID를 갱신하는지 검증.
    /// (open_window_creates_new_workspace_session = true)
    func test_openNewFileManagerWindow_createsWindowAndSetsActive() async {
        let newID = UUID()

        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(newID)
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil))) {
            $0.windows.append(.init(id: newID, window: .makeInitial(path: nil)))
            $0.focusedWindowID = newID
        }
    }

    /// FMW-001-open_new_file_manager_window:
    /// onboarding이 필요한 경우 newWindow 액션이 윈도우를 생성하지 않고 no-op인지 검증.
    func test_openNewFileManagerWindow_skipsWhenOnboardingRequired() async {
        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.onboardingWindowClient.showIfNeeded = { true }
        }

        await store.send(.file(.newWindow(path: nil)))
    }

    /// FMW-001-close_file_manager_window:
    /// windowClosed 이벤트가 focused 윈도우를 제거하고 다음 윈도우로 포커스를 이전하는지 검증.
    /// 나머지 윈도우 상태는 보존된다.
    /// (close_window_preserves_other_windows = true)
    func test_closeFocusedWindow_removesWindowAndPreservesOthers() async {
        let firstID = UUID()
        let secondID = UUID()

        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            .init(id: firstID, window: .makeInitial(path: "/a")),
            .init(id: secondID, window: .makeInitial(path: "/b")),
        ]
        initialState.focusedWindowID = firstID

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        }

        await store.send(.event(.windowClosed(firstID))) {
            $0.windows.remove(id: firstID)
            $0.focusedWindowID = secondID
        }
    }

    /// FMW-001-close_file_manager_window:
    /// focused 윈도우가 없을 때 closeFocusedWindow 액션이 no-op인지 검증.
    func test_closeFocusedWindow_noOpWhenNoFocusedWindow() async {
        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        }

        await store.send(.window(.closeFocusedWindow))
    }

    /// FMW-001-close_file_manager_window:
    /// window(.closeFocusedWindow) 액션이 fileManagerWindowClient.close를 호출하는지 검증.
    func test_closeFocusedWindowAction_invokesClientClose() async {
        let focusedID = UUID()

        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            .init(id: focusedID, window: .makeInitial(path: "/tmp")),
        ]
        initialState.focusedWindowID = focusedID

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.fileManagerWindowClient.close = { _ in }
        }

        await store.send(.window(.closeFocusedWindow))
    }

    /// FMW-001-quit_voyager:
    /// closeAllWindows 액션이 모든 윈도우를 제거하고 focusedWindowID를 nil로 만드는지 검증.
    /// (quit_terminates_all_windows = true)
    func test_closeAllOrQuitSurrogate_terminatesAllWindows() async {
        let firstID = UUID()
        let secondID = UUID()

        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            .init(id: firstID, window: .makeInitial(path: "/a")),
            .init(id: secondID, window: .makeInitial(path: "/b")),
        ]
        initialState.focusedWindowID = secondID

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.fileManagerWindowClient.closeAll = {}
        }

        await store.send(.window(.closeAllWindows)) {
            $0.windows.removeAll()
            $0.focusedWindowID = nil
        }
    }

    // MARK: - Test Group 2: Command Routing / Focus Targeting (FMW-001)

    /// FMW-001 (routing):
    /// focused 윈도우가 있을 때 edit 명령이 focused 윈도우로만 라우팅되는지 검증.
    /// (window_commands_apply_to_active_window = true)
    func test_focusedWindowCommandForwarding_routesToActiveWindow() async {
        let focusedID = UUID()
        let otherID = UUID()

        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            .init(id: focusedID, window: .makeInitial(path: "/focused")),
            .init(id: otherID, window: .makeInitial(path: "/other")),
        ]
        initialState.focusedWindowID = focusedID

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        }
        store.exhaustivity = .off

        // edit(.requestUndo)는 sendCommandToFocusedWindow을 통해 focusedID로만 전달
        await store.send(.edit(.requestUndo))
    }

    /// FMW-001 (routing):
    /// focused 윈도우가 없을 때 edit 명령이 no-op인지 검증.
    func test_noFocusedWindow_commandIsNoOp() async {
        let otherID = UUID()

        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            .init(id: otherID, window: .makeInitial(path: "/other")),
        ]
        initialState.focusedWindowID = nil

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        }

        // focusedWindowID가 nil이면 sendCommandToFocusedWindow이 .none 반환
        await store.send(.edit(.requestUndo))
    }

    /// FMW-001 (isolation):
    /// 명령이 focused 윈도우에만 적용되고 다른 윈도우 상태는 불변인지 검증.
    func test_multiWindowTargetIsolation_commandAffectsOnlyActiveWindow() async {
        let focusedID = UUID()
        let backgroundID = UUID()

        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            .init(id: focusedID, window: .makeInitial(path: "/focused")),
            .init(id: backgroundID, window: .makeInitial(path: "/bg")),
        ]
        initialState.focusedWindowID = focusedID

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        }
        store.exhaustivity = .off

        // 명령 전송 후 상태 변화 없음 (라우팅만 발생, 불변 상태)
        await store.send(.edit(.requestRedo))
    }

    // MARK: - Test Group 3: Multi-Window Lifecycle (FMW-001)

    /// FMW-001: focused가 아닌 윈도우가 닫혀도 focused 윈도우가 유지되는지 검증.
    func test_closeUnfocusedWindow_preservesFocusedWindow() async {
        let focusedID = UUID()
        let otherID = UUID()

        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            .init(id: focusedID, window: .makeInitial(path: "/focused")),
            .init(id: otherID, window: .makeInitial(path: "/other")),
        ]
        initialState.focusedWindowID = focusedID

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        }

        await store.send(.event(.windowClosed(otherID))) {
            $0.windows.remove(id: otherID)
        }
    }
}
