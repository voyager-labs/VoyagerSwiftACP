import AppKit
import ComposableArchitecture
@testable import Voyager
import VoyagerFeaturesComposer
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerPagesOnboarding
import VoyagerShared
import VoyagerWidgetsEntryViewLayout
import XCTest

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
final class FileManagerWindowManagerTests: XCTestCase {
    private typealias Spec = WindowManagerTestSupport.Spec

    private func makeStore(
        initialState: WindowManagerFeature.State = WindowManagerFeature.State(),
        uuid: UUID? = nil,
        onboardingRequired: Bool = false,
        configureDependencies: ((inout DependencyValues) -> Void)? = nil,
    ) -> TestStore<WindowManagerFeature.State, WindowManagerFeature.Action> {
        WindowManagerTestSupport.makeStore(
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
        WindowManagerTestSupport.makeState(
            focusedID: focusedID,
            windows: windows,
        )
    }

    // MARK: - FMW-001-open_new_file_manager_window

    /// FMW-001-open_new_file_manager_window: 새 윈도우 생성 및 활성 윈도우 추적
    /// newWindow 액션이 새 윈도우 세션을 생성하고 focusedWindowID를 갱신하는지 검증.
    /// windowIDChanged 및 applyAppPreferences child action이 newID로 방출되는지,
    /// fileManagerWindowClient.open(newID)가 정확히 한 번 호출되는지도 함께 검증.
    /// (open_window_creates_new_workspace_session = true)
    /// - 검증 내용: newWindow 전송 후 windows 배열에 새 항목 추가, focusedWindowID 갱신,
    ///   windowIDChanged child action 수신, applyAppPreferences child action 수신,
    ///   client.open 호출 횟수 및 전달된 ID
    /// - 사전 조건: 빈 윈도우 상태, 온보딩 불필요, UUID 고정
    /// - 기대 결과: windows.count == 1, focusedWindowID == newID,
    ///   windowIDChanged 수신, applyAppPreferences 수신, openCallCount == 1, openedID == newID
    func test_openNewFileManagerWindow_createsWindowAndSetsActive() async {
        let newID = UUID()
        let openedIDs = LockIsolated<[UUID]>([])

        let store = makeStore(uuid: newID) {
            $0.fileManagerWindowClient.open = { id in
                openedIDs.withValue { $0.append(id) }
            }
        }

        // store.exhaustivity = .off: 새 윈도우 생성은 downstream 초기화 액션까지 이어져 핵심 app-scoped 수신만 검증한다.
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil))) {
            $0.windows.append(.init(id: newID, window: .makeInitial(path: nil)))
            $0.focusedWindowID = newID
        }

        // windowIDChanged child action이 newID로 방출되었는지 수신 확인
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.content(.entryViewLayout(.entryOperations(.lifecycle(.windowIDChanged(receivedID)))))),
            )) = action else {
                return false
            }
            return id == newID && receivedID == newID
        }

        // applyAppPreferences child action이 newID로 방출되었는지 수신 확인
        let defaultPackagePrefs = AppPreferencesState().toPackageState()
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.applyAppPreferences(preferences)),
            )) = action else {
                return false
            }
            return id == newID && preferences == defaultPackagePrefs
        }

        // 나머지 파생 이펙트(arrangements 정렬/그룹 갱신)는 package-scoped 테스트가 검증
        await store.finish()

        XCTAssertEqual(openedIDs.value.count, 1, "fileManagerWindowClient.open은 정확히 한 번 호출되어야 한다")
        XCTAssertEqual(openedIDs.value.first, newID, "open에 전달된 ID는 생성된 윈도우 ID와 일치해야 한다")
    }

    // MARK: - FMW-001-close_file_manager_window

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
            $0.closingWindowIDs.insert(firstID)
            $0.invalidatingWindowIDs.insert(firstID)
        }
        await store.receive(\.windowInvalidationFinished) {
            $0.windows.remove(id: firstID)
            $0.closingWindowIDs.remove(firstID)
            $0.invalidatingWindowIDs.remove(firstID)
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
        let closedIDs = LockIsolated<[UUID]>([])

        let store = makeStore(initialState: makeState(
            focusedID: focusedID,
            windows: [(focusedID, Spec.tempPath)],
        )) {
            $0.fileManagerWindowClient.close = { id in
                closedIDs.withValue { $0.append(id) }
            }
        }

        await store.send(.window(.closeFocusedWindow)) {
            $0.closingWindowIDs.insert(focusedID)
            $0.focusedWindowID = nil
        }

        XCTAssertEqual(closedIDs.value.count, 1, "fileManagerWindowClient.close는 정확히 한 번 호출되어야 한다")
        XCTAssertEqual(closedIDs.value.first, focusedID, "close에 전달된 ID는 focusedWindowID와 일치해야 한다")
    }

    /// FMW-001-close_file_manager_window: child close delegate는 발생시킨 owning window를 닫는다.
    /// - 검증 내용: background window의 delegate가 focused window로 재해석되지 않고 정확한 ID로 client.close를 호출한다.
    /// - 사전 조건: focused window와 background window가 모두 열려 있음
    /// - 기대 결과: background ID만 closing에 추가되고 focused ID와 focus는 유지됨
    func testWindowCloseDelegate_closesOwningWindowInsteadOfFocusedWindow() async {
        let focusedID = UUID()
        let backgroundID = UUID()
        let closedIDs = LockIsolated<[UUID]>([])
        let store = makeStore(initialState: makeState(
            focusedID: focusedID,
            windows: [(focusedID, Spec.focusedPath), (backgroundID, Spec.backgroundPath)],
        )) {
            $0.fileManagerWindowClient.close = { id in
                closedIDs.withValue { $0.append(id) }
            }
        }

        await store.send(.windows(.element(
            id: backgroundID,
            action: .window(.delegate(.closeWindow)),
        ))) {
            $0.closingWindowIDs.insert(backgroundID)
        }

        XCTAssertEqual(store.state.focusedWindowID, focusedID)
        XCTAssertEqual(closedIDs.value, [backgroundID])
        await store.finish()
    }

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
            $0.closingWindowIDs.insert(otherID)
            $0.invalidatingWindowIDs.insert(otherID)
        }
        await store.receive(\.windowInvalidationFinished) {
            $0.windows.remove(id: otherID)
            $0.closingWindowIDs.remove(otherID)
            $0.invalidatingWindowIDs.remove(otherID)
        }
    }

    /// FMW-001-close_file_manager_window: invalidateWindow 성공 전 registry finalize와 Window state 제거를 지연한다.
    /// - 검증 내용: delayed invalidation 동안 state identity를 보존하고 성공 후 finalizeClose 다음 state removal 순서를 지킨다.
    /// - 사전 조건: 단일 window와 controllable invalidation gate
    /// - 기대 결과: completion 전 state 보존, 호출 순서 invalidate→finalize, completion 후 state 제거
    func testWindowClose_preservesStateAndFinalizesRegistryAfterInvalidation() async {
        let windowID = UUID()
        let gate = WindowInvalidationGate()
        let calls = LockIsolated<[String]>([])
        let store = makeStore(initialState: makeState(
            focusedID: windowID,
            windows: [(windowID, Spec.tempPath)],
        )) {
            $0.undoManagerClient.invalidateWindow = { receivedID in
                XCTAssertEqual(receivedID, windowID)
                calls.withValue { $0.append("invalidate") }
                await gate.suspend()
                return .init(succeeded: true, availability: .init())
            }
            $0.fileManagerWindowClient.finalizeClose = { receivedID in
                XCTAssertEqual(receivedID, windowID)
                calls.withValue { $0.append("finalize") }
            }
        }

        await store.send(.event(.windowClosed(windowID))) {
            $0.closingWindowIDs.insert(windowID)
            $0.invalidatingWindowIDs.insert(windowID)
        }
        await gate.waitUntilSuspended()
        XCTAssertNotNil(store.state.windows[id: windowID])
        XCTAssertEqual(calls.value, ["invalidate"])

        await gate.resume()
        await store.receive(\.windowInvalidationFinished) {
            $0.windows.remove(id: windowID)
            $0.closingWindowIDs.remove(windowID)
            $0.invalidatingWindowIDs.remove(windowID)
            $0.focusedWindowID = nil
        }
        XCTAssertEqual(calls.value, ["invalidate", "finalize"])
        await store.finish()
    }

    /// FMW-001-close_file_manager_window: invalidateWindow 실패는 registry와 Window state를 보존한다.
    /// - 검증 내용: 실패 result에서 finalizeClose를 호출하지 않고 closing identity를 focus 후보에서 제외한다.
    /// - 사전 조건: 두 window 중 focused window의 invalidation resolver 실패
    /// - 기대 결과: 두 state 유지, closing window 미포커스, finalize 0회
    func testWindowClose_invalidationFailurePreservesRegistryStateAndExcludesFocus() async {
        let closingID = UUID()
        let otherID = UUID()
        let finalizeCalls = LockIsolated<[UUID]>([])
        let store = makeStore(initialState: makeState(
            focusedID: closingID,
            windows: [(closingID, Spec.focusedPath), (otherID, Spec.backgroundPath)],
        )) {
            $0.undoManagerClient.invalidateWindow = { _ in
                .init(succeeded: false, availability: .init())
            }
            $0.fileManagerWindowClient.close = { _ in }
            $0.fileManagerWindowClient.finalizeClose = { id in
                finalizeCalls.withValue { $0.append(id) }
            }
        }

        await store.send(.window(.closeFocusedWindow)) {
            $0.closingWindowIDs.insert(closingID)
            $0.focusedWindowID = otherID
        }
        await store.send(.event(.windowClosed(closingID))) {
            $0.invalidatingWindowIDs.insert(closingID)
        }
        await store.receive(\.windowInvalidationFinished)
        await store.send(.event(.windowBecameKey(closingID)))

        XCTAssertNotNil(store.state.windows[id: closingID])
        XCTAssertNotNil(store.state.windows[id: otherID])
        XCTAssertEqual(store.state.focusedWindowID, otherID)
        XCTAssertEqual(finalizeCalls.value, [])
        await store.finish()
    }

    // MARK: - FMW-001-quit_voyager

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
        let closeAllCallCount = LockIsolated(0)

        let store = makeStore(initialState: makeState(
            focusedID: secondID,
            windows: [(firstID, Spec.firstPath), (secondID, Spec.secondPath)],
        )) {
            $0.fileManagerWindowClient.closeAll = {
                closeAllCallCount.withValue { $0 += 1 }
            }
        }

        await store.send(.window(.closeAllWindows)) {
            $0.closingWindowIDs = [firstID, secondID]
            $0.focusedWindowID = nil
        }

        XCTAssertEqual(store.state.windows.ids, [firstID, secondID])
        XCTAssertEqual(closeAllCallCount.value, 1, "fileManagerWindowClient.closeAll은 정확히 한 번 호출되어야 한다")
    }

    /// CTM-001-open_new_content_tab: focused FileManager window로 새 Content Tab command 라우팅.
    /// File menu의 New Content Tab 입력은 native NSWindow tab이 아니라 focused FMW의 openNewContentTab request로 전달되어야 한다.
    func test_newTabCommand_routesToFocusedFileManagerWindow() async {
        let focusedID = UUID()
        let otherID = UUID()

        let store = makeStore(initialState: makeState(
            focusedID: focusedID,
            windows: [(focusedID, Spec.focusedPath), (otherID, Spec.backgroundPath)],
        ))
        store.exhaustivity = .off

        await store.send(.file(.newTab))
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.request(.openNewContentTab)))) = action else {
                return false
            }
            return id == focusedID
        }
    }

    /// CTM-001-open_new_content_tab: focused window가 없으면 새 Content Tab 입력은 no-op.
    func test_newTabCommand_noOpWhenNoFocusedWindow() async {
        let otherID = UUID()

        let store = makeStore(initialState: makeState(
            focusedID: nil,
            windows: [(otherID, Spec.backgroundPath)],
        ))

        await store.send(.file(.newTab))
    }

    // MARK: - FMW-001-request_undo

    /// FMW-001-request_undo: focused 윈도우로 명령 라우팅
    /// focused 윈도우가 있을 때 edit 명령이 focused 윈도우로만 라우팅되는지 검증.
    /// (window_commands_apply_to_active_window = true)
    /// - 검증 내용: edit(.requestUndo) 전송 시 focusedID로만 `.windows(.element(... .request(.requestUndo)))` 방출
    /// - 사전 조건: 2개 윈도우(focusedID, otherID) 존재
    /// - 기대 결과: 명령이 focusedID 윈도우로만 라우팅, otherID 상태 불변
    func test_focusedWindowCommandForwarding_routesToActiveWindow() async {
        let focusedID = UUID()
        let otherID = UUID()

        let store = makeStore(initialState: makeState(
            focusedID: focusedID,
            windows: [(focusedID, Spec.focusedPath), (otherID, Spec.backgroundPath)],
        ))

        // store.exhaustivity = .off: 라우팅 목적 테스트라 child reducer 내부 수신 체인은 package-scoped 테스트가 검증한다.
        store.exhaustivity = .off

        // edit(.requestUndo)는 sendCommandToFocusedWindow을 통해 focusedID로만 전달
        await store.send(.edit(.requestUndo))
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.request(.requestUndo)))) = action else {
                return false
            }
            return id == focusedID
        }
    }

    /// FMW-001-request_undo: focused 윈도우 없을 때 명령 no-op
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

    // MARK: - FMW-001-request_redo

    /// FMW-001-request_redo: 멀티 윈도우 명령 격리성
    /// 명령이 focused 윈도우에만 적용되고 다른 윈도우 상태는 불변인지 검증.
    /// - 검증 내용: edit(.requestRedo) 전송 시 `.windows(.element(... .request(.requestRedo)))` 방출
    /// - 사전 조건: 2개 윈도우(focusedID=focused, backgroundID=background) 존재
    /// - 기대 결과: focusedID로만 명령 전달, backgroundID 상태 변화 없음
    func test_multiWindowTargetIsolation_commandAffectsOnlyActiveWindow() async {
        let focusedID = UUID()
        let backgroundID = UUID()

        let store = makeStore(initialState: makeState(
            focusedID: focusedID,
            windows: [(focusedID, Spec.focusedPath), (backgroundID, Spec.backgroundPath)],
        ))

        // store.exhaustivity = .off: 라우팅 목적 테스트라 child reducer 내부 수신 체인은 package-scoped 테스트가 검증한다.
        store.exhaustivity = .off

        // 명령 전송 후 상태 변화 없음 (라우팅만 발생, 불변 상태)
        await store.send(.edit(.requestRedo))
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.request(.requestRedo)))) = action else {
                return false
            }
            return id == focusedID
        }
    }
}

// WindowManagerTests 공용 테스트 서포트.

enum WindowManagerTestSupport {
    enum Spec {
        static let focusedPath = "/focused"
        static let backgroundPath = "/background"
        static let firstPath = "/a"
        static let secondPath = "/b"
        static let tempPath = "/tmp"
    }

    @MainActor
    static func makeStore(
        initialState: WindowManagerFeature.State = WindowManagerFeature.State(),
        uuid: UUID? = nil,
        onboardingRequired: Bool = false,
        configureDependencies: ((inout DependencyValues) -> Void)? = nil,
    ) -> TestStore<WindowManagerFeature.State, WindowManagerFeature.Action> {
        TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            if let uuid {
                $0.uuid = .constant(uuid)
            }
            $0.onboardingWindowClient.showIfNeeded = { onboardingRequired }
            configureDependencies?(&$0)
        }
    }

    @MainActor
    static func makeState(
        focusedID: UUID?,
        windows: [(UUID, String?)],
    ) -> WindowManagerFeature.State {
        var state = WindowManagerFeature.State()
        state.windows = .init(uniqueElements: windows.map { id, path in
            WindowSessionState(id: id, window: .makeInitial(path: path))
        })
        state.focusedWindowID = focusedID
        return state
    }
}

private actor WindowInvalidationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            waiters.forEach { $0.resume() }
            waiters.removeAll()
        }
    }

    func waitUntilSuspended() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
