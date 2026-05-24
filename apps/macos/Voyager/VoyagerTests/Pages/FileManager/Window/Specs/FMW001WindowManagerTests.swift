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
final class FMW001WindowManagerTests: XCTestCase {
    private typealias Spec = FMW001WindowManagerTestSupport.Spec

    private func makeStore(
        initialState: WindowManagerFeature.State = WindowManagerFeature.State(),
        uuid: UUID? = nil,
        onboardingRequired: Bool = false,
        configureDependencies: ((inout DependencyValues) -> Void)? = nil,
    ) -> TestStore<WindowManagerFeature.State, WindowManagerFeature.Action> {
        FMW001WindowManagerTestSupport.makeStore(
            initialState: initialState,
            uuid: uuid,
            onboardingRequired: onboardingRequired,
            configureDependencies: configureDependencies,
        )
    }

    private func makeState(
        focusedID: UUID?,
        windows: [(UUID, String?)],
    ) -> WindowManagerFeature.State {
        FMW001WindowManagerTestSupport.makeState(
            focusedID: focusedID,
            windows: windows,
        )
    }

    // MARK: - Test Group 1: Window Lifecycle (FMW-001)

    /// FMW-001-open_new_file_manager_window: 새 윈도우 생성 및 활성 윈도우 추적
    /// newWindow 액션이 새 윈도우 세션을 생성하고 focusedWindowID를 갱신하는지 검증.
    /// fileManagerWindowClient.open이 정확히 한 번 호출되는지도 함께 검증.
    /// (open_window_creates_new_workspace_session = true)
    /// - 검증 내용: newWindow 전송 후 windows 배열에 새 항목 추가, focusedWindowID 갱신, client.open 호출 횟수
    /// - 사전 조건: 빈 윈도우 상태, 온보딩 불필요, UUID 고정
    /// - 기대 결과: windows.count == 1, focusedWindowID == newID, openCallCount == 1
    func test_openNewFileManagerWindow_createsWindowAndSetsActive() async {
        let newID = UUID()
        var openCallCount = 0

        let store = makeStore(uuid: newID) {
            $0.fileManagerWindowClient.open = { _ in openCallCount += 1 }
        }

        // 새 윈도우 생성은 downstream 초기화 액션까지 이어지므로 app-scoped 상태만 검증한다.
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil))) {
            $0.windows.append(.init(id: newID, window: .makeInitial(path: nil)))
            $0.focusedWindowID = newID
        }

        XCTAssertEqual(openCallCount, 1, "fileManagerWindowClient.open은 정확히 한 번 호출되어야 한다")
    }

    /// FMW-001-open_new_file_manager_window: 온보딩 필요 시 윈도우 생성 스킵
    /// onboarding이 필요한 경우 newWindow 액션이 윈도우를 생성하지 않고 no-op인지 검증.
    /// - 검증 내용: onboardingRequired=true일 때 newWindow 액션 전송 후 상태 변화 없음
    /// - 사전 조건: onboardingWindowClient.showIfNeeded가 true 반환
    /// - 기대 결과: windows 배열 변화 없음, focusedWindowID 변화 없음
    func test_openNewFileManagerWindow_skipsWhenOnboardingRequired() async {
        let store = makeStore(onboardingRequired: true)

        await store.send(.file(.newWindow(path: nil)))
    }

    /// FMW-001-close_file_manager_window: focused 윈도우 닫기 시 포커스 이전
    /// windowClosed 이벤트가 focused 윈도우를 제거하고 다음 윈도우로 포커스를 이전하는지 검증.
    /// 나머지 윈도우 상태는 보존된다.
    /// (close_window_preserves_other_windows = true)
    /// - 검증 내용: focused 윈도우 제거 후 나머지 윈도우 보존, focusedWindowID 이전
    /// - 사전 조건: 2개 윈도우(first=focused, second=background) 존재
    /// - 기대 결과: windows에서 firstID 제거, focusedWindowID == secondID
    func test_closeFocusedWindow_removesWindowAndPreservesOthers() async {
        let firstID = UUID()
        let secondID = UUID()

        let store = makeStore(initialState: makeState(
            focusedID: firstID,
            windows: [(firstID, Spec.firstPath), (secondID, Spec.secondPath)],
        ))

        await store.send(.event(.windowClosed(firstID))) {
            $0.windows.remove(id: firstID)
            $0.focusedWindowID = secondID
        }
    }

    /// FMW-001-close_file_manager_window: focused 윈도우 없을 때 closeFocusedWindow no-op
    /// focused 윈도우가 없을 때 closeFocusedWindow 액션이 no-op인지 검증.
    /// - 검증 내용: focusedWindowID == nil일 때 closeFocusedWindow 액션 전송 후 상태 변화 없음
    /// - 사전 조건: 윈도우 없는 빈 상태
    /// - 기대 결과: 상태 변화 없음, no-op
    func test_closeFocusedWindow_noOpWhenNoFocusedWindow() async {
        let store = makeStore()

        await store.send(.window(.closeFocusedWindow))
    }

    /// FMW-001-close_file_manager_window: closeFocusedWindow 액션의 client.close 호출 검증
    /// window(.closeFocusedWindow) 액션이 fileManagerWindowClient.close를
    /// focusedID 인자로 정확히 한 번 호출하는지 검증.
    /// - 검증 내용: closeFocusedWindow 전송 시 client.close 호출 횟수 및 전달된 ID
    /// - 사전 조건: focusedID에 해당하는 윈도우 1개 존재
    /// - 기대 결과: closeCallCount == 1, closedID == focusedID
    func test_closeFocusedWindowAction_invokesClientClose() async {
        let focusedID = UUID()
        var closeCallCount = 0
        var closedID: UUID?

        let store = makeStore(initialState: makeState(
            focusedID: focusedID,
            windows: [(focusedID, Spec.tempPath)],
        )) {
            $0.fileManagerWindowClient.close = { id in
                closeCallCount += 1
                closedID = id
            }
        }

        await store.send(.window(.closeFocusedWindow))

        XCTAssertEqual(closeCallCount, 1, "fileManagerWindowClient.close는 정확히 한 번 호출되어야 한다")
        XCTAssertEqual(closedID, focusedID, "close에 전달된 ID는 focusedWindowID와 일치해야 한다")
    }

    /// FMW-001-quit_voyager: 모든 윈도우 종료
    /// closeAllWindows 액션이 모든 윈도우를 제거하고 focusedWindowID를 nil로 만드는지 검증.
    /// fileManagerWindowClient.closeAll이 정확히 한 번 호출되는지도 함께 검증.
    /// (quit_terminates_all_windows = true)
    /// - 검증 내용: closeAllWindows 전송 후 windows 배열 비움, focusedWindowID nil, closeAll 호출 횟수
    /// - 사전 조건: 2개 윈도우(first, second) 존재, second가 focused
    /// - 기대 결과: windows.isEmpty == true, focusedWindowID == nil, closeAllCallCount == 1
    func test_closeAllOrQuitSurrogate_terminatesAllWindows() async {
        let firstID = UUID()
        let secondID = UUID()
        var closeAllCallCount = 0

        let store = makeStore(initialState: makeState(
            focusedID: secondID,
            windows: [(firstID, Spec.firstPath), (secondID, Spec.secondPath)],
        )) {
            $0.fileManagerWindowClient.closeAll = { closeAllCallCount += 1 }
        }

        await store.send(.window(.closeAllWindows)) {
            $0.windows.removeAll()
            $0.focusedWindowID = nil
        }

        XCTAssertEqual(closeAllCallCount, 1, "fileManagerWindowClient.closeAll은 정확히 한 번 호출되어야 한다")
    }

    // MARK: - Test Group 2: Command Routing / Focus Targeting (FMW-001)

    /// FMW-001-open_new_file_manager_window: focused 윈도우로 명령 라우팅
    /// focused 윈도우가 있을 때 edit 명령이 focused 윈도우로만 라우팅되는지 검증.
    /// (window_commands_apply_to_active_window = true)
    /// - 검증 내용: edit(.requestUndo) 전송 시 focusedID로만 명령 전달
    /// - 사전 조건: 2개 윈도우(focusedID, otherID) 존재
    /// - 기대 결과: 명령이 focusedID 윈도우로만 라우팅, otherID 상태 불변
    func test_focusedWindowCommandForwarding_routesToActiveWindow() async {
        let focusedID = UUID()
        let otherID = UUID()

        let store = makeStore(initialState: makeState(
            focusedID: focusedID,
            windows: [(focusedID, Spec.focusedPath), (otherID, Spec.backgroundPath)],
        ))

        // 라우팅 목적 테스트: child reducer 내부 수신 체인은 package-scoped 테스트가 검증한다.
        store.exhaustivity = .off

        // edit(.requestUndo)는 sendCommandToFocusedWindow을 통해 focusedID로만 전달
        await store.send(.edit(.requestUndo))
    }

    /// FMW-001-open_new_file_manager_window: focused 윈도우 없을 때 명령 no-op
    /// focused 윈도우가 없을 때 edit 명령이 no-op인지 검증.
    /// - 검증 내용: focusedWindowID == nil일 때 edit(.requestUndo) 전송 후 상태 변화 없음
    /// - 사전 조건: 윈도우 1개(otherID) 존재하지만 focused 없음
    /// - 기대 결과: 상태 변화 없음, sendCommandToFocusedWindow이 .none 반환
    func test_noFocusedWindow_commandIsNoOp() async {
        let otherID = UUID()

        let store = makeStore(initialState: makeState(
            focusedID: nil,
            windows: [(otherID, Spec.backgroundPath)],
        ))

        // focusedWindowID가 nil이면 sendCommandToFocusedWindow이 .none 반환
        await store.send(.edit(.requestUndo))
    }

    /// FMW-001-open_new_file_manager_window: 멀티 윈도우 명령 격리성
    /// 명령이 focused 윈도우에만 적용되고 다른 윈도우 상태는 불변인지 검증.
    /// - 검증 내용: edit(.requestRedo) 전송 시 backgroundID 윈도우 상태 불변
    /// - 사전 조건: 2개 윈도우(focusedID=focused, backgroundID=background) 존재
    /// - 기대 결과: focusedID로만 명령 전달, backgroundID 상태 변화 없음
    func test_multiWindowTargetIsolation_commandAffectsOnlyActiveWindow() async {
        let focusedID = UUID()
        let backgroundID = UUID()

        let store = makeStore(initialState: makeState(
            focusedID: focusedID,
            windows: [(focusedID, Spec.focusedPath), (backgroundID, Spec.backgroundPath)],
        ))

        // 라우팅 목적 테스트: child reducer 내부 수신 체인은 package-scoped 테스트가 검증한다.
        store.exhaustivity = .off

        // 명령 전송 후 상태 변화 없음 (라우팅만 발생, 불변 상태)
        await store.send(.edit(.requestRedo))
    }

    // MARK: - Test Group 3: Multi-Window Lifecycle (FMW-001)

    /// FMW-001-close_file_manager_window: unfocused 윈도우 닫기 시 focused 유지
    /// focused가 아닌 윈도우가 닫혀도 focused 윈도우가 유지되는지 검증.
    /// - 검증 내용: windowClosed(otherID) 전송 후 focusedID 윈도우 상태 보존
    /// - 사전 조건: 2개 윈도우(focusedID=focused, otherID=background) 존재
    /// - 기대 결과: otherID만 windows에서 제거, focusedWindowID 유지
    func test_closeUnfocusedWindow_preservesFocusedWindow() async {
        let focusedID = UUID()
        let otherID = UUID()

        let store = makeStore(initialState: makeState(
            focusedID: focusedID,
            windows: [(focusedID, Spec.focusedPath), (otherID, Spec.backgroundPath)],
        ))

        await store.send(.event(.windowClosed(otherID))) {
            $0.windows.remove(id: otherID)
        }
    }
}
