import ComposableArchitecture
@testable import Voyager
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import VoyagerPagesOnboarding
import XCTest

/// 윈도우 관리자 계약 — 포커스 윈도우로의 명령 팬아웃과 미사용 시 no-op를 검증.
@MainActor
final class WindowManagerFeatureContractTests: XCTestCase {
    /// testApplyAppPreferencesFansOutToAllWindows 테스트 동작을 검증한다.
    func testApplyAppPreferencesFansOutToAllWindows() async {
        let firstID = UUID()
        let secondID = UUID()

        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(id: firstID, window: .makeInitial(path: "/a")),
            WindowSessionState(id: secondID, window: .makeInitial(path: "/b")),
        ]

        var preferences = AppPreferencesState()
        preferences.viewLayout = .grid
        preferences.groupKey = .kind

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.lifecycle(.applyAppPreferences(preferences))) {
            $0.appPreferences = preferences
        }
    }

    /// app preference 갱신은 기존 열린 창의 Sidebar 크기/표시 상태를 덮어쓰지 않는다.
    /// 새 창은 생성 시 app preference를 적용하지만, 이미 열린 창은 window-local Sidebar 상태를 유지해야 한다.
    func testApplyAppPreferencesPreservesExistingWindowSidebarState() async {
        let firstID = UUID()
        let secondID = UUID()

        var firstWindow = WindowSessionState(id: firstID, window: .makeInitial(path: "/a"))
        firstWindow.window.sidebar.sidebarVisible = true

        var secondWindow = WindowSessionState(id: secondID, window: .makeInitial(path: "/b"))
        secondWindow.window.sidebar.sidebarVisible = false

        var initialState = WindowManagerFeature.State()
        initialState.windows = [firstWindow, secondWindow]

        var preferences = AppPreferencesState()
        preferences.sidebarVisible = true
        preferences.sidebarWidth = 300
        preferences.viewLayout = .grid

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.lifecycle(.applyAppPreferences(preferences))) {
            $0.appPreferences = preferences
        }

        var firstPackagePreferences = preferences.toPackageState()
        firstPackagePreferences.sidebarVisible = true
        firstPackagePreferences.sidebarWidth = 220
        await store.receive(.windows(.element(
            id: firstID,
            action: .window(.applyAppPreferences(firstPackagePreferences)),
        )))

        var secondPackagePreferences = preferences.toPackageState()
        secondPackagePreferences.sidebarVisible = false
        secondPackagePreferences.sidebarWidth = 220
        await store.receive(.windows(.element(
            id: secondID,
            action: .window(.applyAppPreferences(secondPackagePreferences)),
        )))
    }

    /// testQuickLookRoutesToFocusedWindowCommandBus 테스트 동작을 검증한다.
    func testQuickLookRoutesToFocusedWindowCommandBus() async {
        let focusedID = UUID()

        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(id: focusedID, window: .makeInitial(path: "/tmp")),
        ]
        initialState.focusedWindowID = focusedID

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.file(.quickLook))
    }

    /// testNewFolderRoutesToFocusedWindow 테스트 동작을 검증한다.
    func testNewFolderRoutesToFocusedWindow() async {
        let focusedID = UUID()

        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(id: focusedID, window: .makeInitial(path: "/tmp")),
        ]
        initialState.focusedWindowID = focusedID

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.entryFileOpsClient.createFolder = { _, _ in }
        }
        store.exhaustivity = .off

        await store.send(.file(.newFolder))
    }

    /// testCopyRoutesToFocusedWindow 테스트 동작을 검증한다.
    func testCopyRoutesToFocusedWindow() async {
        let focusedID = UUID()

        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(id: focusedID, window: .makeInitial(path: "/tmp")),
        ]
        initialState.focusedWindowID = focusedID

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.edit(.copy))
    }

    /// testToggleSidebarRoutesToFocusedWindow 테스트 동작을 검증한다.
    func testToggleSidebarRoutesToFocusedWindow() async {
        let focusedID = UUID()

        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(id: focusedID, window: .makeInitial(path: "/tmp")),
        ]
        initialState.focusedWindowID = focusedID

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.window(.toggleSidebar))
    }

    /// testNoCommandSentWhenNoFocusedWindow 테스트 동작을 검증한다.
    func testNoCommandSentWhenNoFocusedWindow() async {
        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        }

        await store.send(.file(.quickLook))
    }

    // MARK: - Onboarding Gate Preservation

    /// 온보딩이 완료되지 않은 경우 newWindow(⌘N) 액션이 윈도우를 생성하지 않는지 검증.
    /// showIfNeeded가 true(온보딩 필요)를 반환하면 openWindowSession이 .none을 반환하여
    /// FMW 생성이 차단되어야 한다.
    /// - 검증 내용: onboardingRequired=true일 때 newWindow 액션 전송 후 상태 변화 없음
    /// - 사전 조건: 빈 윈도우 상태, onboardingWindowClient.showIfNeeded = true
    /// - 기대 결과: windows 배열 변화 없음, focusedWindowID 변화 없음
    func testNewWindowBlockedWhileOnboardingRequired() async {
        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.onboardingWindowClient.showIfNeeded = { true }
        }

        await store.send(.file(.newWindow(path: nil)))
    }

    /// 온보딩 완료 후 completion handoff 경로에서 newWindow가 정상적으로 FMW를 생성하는지 검증.
    /// showIfNeeded가 false(온보딩 불필요/완료)를 반환하면 openWindowSession이 윈도우를 생성하고
    /// fileManagerWindowClient.open을 호출해야 한다.
    /// 이 테스트는 Task 1의 save→open→close 시퀀싱 이후, 라이브 앱/윈도우 경로를 통해
    /// FMW가 성공적으로 열리는지 증명한다.
    /// - 검증 내용: onboardingRequired=false일 때 newWindow 액션으로 윈도우 생성 및 client.open 호출
    /// - 사전 조건: 빈 윈도우 상태, onboardingWindowClient.showIfNeeded = false
    /// - 기대 결과: windows.count == 1, focusedWindowID == newID, openCallCount == 1
    func testNewWindowSucceedsAfterOnboardingComplete() async {
        let newID = UUID()
        var openCallCount = 0
        var openedID: UUID?

        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(newID)
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { id in
                openCallCount += 1
                openedID = id
            }
        }
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil))) {
            $0.windows.append(.init(id: newID, window: .makeInitial(path: nil)))
            $0.focusedWindowID = newID
        }

        await store.finish()

        XCTAssertEqual(openCallCount, 1, "fileManagerWindowClient.open은 온보딩 완료 후 정확히 한 번 호출되어야 한다")
        XCTAssertEqual(openedID, newID, "open에 전달된 ID는 생성된 윈도우 ID와 일치해야 한다")
    }
}
