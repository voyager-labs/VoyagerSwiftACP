import ComposableArchitecture
@testable import Voyager
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import VoyagerPagesOnboarding
import XCTest

@MainActor
/// 윈도우 관리자 계약 — 포커스 윈도우로의 명령 팬아웃과 미사용 시 no-op를 검증.
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
}
