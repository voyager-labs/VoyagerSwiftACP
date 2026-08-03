// FLOW-ID: fmw.control_file_manager_window
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

/// FMW-001 control_file_manager_window의 app-scoped 생산 조합을 검증하는 flow suite.
///
/// 이 suite는 WindowManagerFeature의 윈도우 생성/포커스 전이/전체 종료 등
/// app-root 수준의 생산 조합을 검증한다.
/// package-scoped Detail(close client 호출, no-op focused, unfocused 윈도우 보존, CTM 라우팅,
/// 명령 격리, activation tracker)은 FileManagerWindowManagerTests 소유이다.
@MainActor
final class ControlFileManagerWindowFlowTests: XCTestCase {
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
    ///
    /// newWindow 액션이 새 윈도우 세션을 생성하고 focusedWindowID를 갱신하는지 검증.
    /// windowIDChanged 및 applyAppPreferences child action이 newID로 방출되는지,
    /// fileManagerWindowClient.open(newID)가 정확히 한 번 호출되는지도 함께 검증.
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
                action: .window(.content(.entryOperations(.lifecycle(.windowIDChanged(receivedID))))),
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
    ///
    /// windowClosed 이벤트가 focused 윈도우를 제거하고 다음 윈도우로 포커스를 이전하는지 검증.
    /// 나머지 윈도우 상태는 보존된다.
    /// - 검증 내용: focused 윈도우 제거 후 나머지 윈도우 보존, focusedWindowID 이전
    /// - 사전 조건: 2개 윈도우(first=focused, second=background) 존재
    /// - 기대 결과: windows에서 firstID 제거, focusedWindowID == secondID
    func test_closeFocusedWindow_removesWindowAndPreservesOthers() async {
        let firstID = UUID()
        let secondID = UUID()

        var initialState = makeState(
            focusedID: firstID,
            windows: [(firstID, Spec.firstPath), (secondID, Spec.secondPath)],
        )
        initialState.lastUsedWindowIDs = [firstID, secondID]
        let store = makeStore(initialState: initialState)

        await store.send(.event(.windowClosed(firstID))) {
            $0.windows.remove(id: firstID)
            $0.focusedWindowID = secondID
            $0.lastUsedWindowIDs = [secondID]
        }
    }

    // MARK: - FMW-001-quit_voyager

    /// FMW-001-quit_voyager: 모든 윈도우 종료
    ///
    /// closeAllWindows 액션이 모든 윈도우를 제거하고 focusedWindowID를 nil로 만드는지 검증.
    /// fileManagerWindowClient.closeAll이 정확히 한 번 호출되는지도 함께 검증.
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
            $0.windows.removeAll()
            $0.focusedWindowID = nil
        }

        XCTAssertEqual(closeAllCallCount.value, 1, "fileManagerWindowClient.closeAll은 정확히 한 번 호출되어야 한다")
    }
}
