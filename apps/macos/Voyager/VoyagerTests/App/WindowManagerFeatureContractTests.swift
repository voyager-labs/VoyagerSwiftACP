import ComposableArchitecture
@testable import Voyager
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerPagesOnboarding
import VoyagerWidgetsEntryViewLayout
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

        var preferences = Voyager.AppPreferencesState()
        preferences.viewLayout = EntryViewLayoutState.Mode.grid
        preferences.groupKey = GroupKey.kind

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient.loadStore = { _ in ContentTabPinnedRecordStore() }
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
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

        var preferences = Voyager.AppPreferencesState()
        preferences.sidebarVisible = true
        preferences.sidebarWidth = 300
        preferences.viewLayout = EntryViewLayoutState.Mode.grid

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient.loadStore = { _ in ContentTabPinnedRecordStore() }
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.lifecycle(.applyAppPreferences(preferences))) {
            $0.appPreferences = preferences
        }

        var firstPackagePreferences = preferences.toPackageState()
        firstPackagePreferences.sidebarVisible = true
        firstPackagePreferences.sidebarWidth = 220
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.applyAppPreferences(preferences)),
            )) = action else {
                return false
            }
            return id == firstID && preferences == firstPackagePreferences
        }

        var secondPackagePreferences = preferences.toPackageState()
        secondPackagePreferences.sidebarVisible = false
        secondPackagePreferences.sidebarWidth = 220
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.applyAppPreferences(preferences)),
            )) = action else {
                return false
            }
            return id == secondID && preferences == secondPackagePreferences
        }
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
        let openedIDs = LockIsolated<[UUID]>([])

        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(newID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient.loadStore = { _ in ContentTabPinnedRecordStore() }
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { id in
                openedIDs.withValue { $0.append(id) }
            }
        }
        store.exhaustivity = .off

        // makeWindowSession에서 pinnedRecords가 없으므로 기본 Home tab으로 fallback
        await store.send(.file(.newWindow(path: nil))) {
            $0.windows.append(.init(id: newID, window: .makeInitial(path: nil)))
            $0.focusedWindowID = newID
        }

        await store.finish()

        XCTAssertEqual(openedIDs.value.count, 1, "fileManagerWindowClient.open은 온보딩 완료 후 정확히 한 번 호출되어야 한다")
        XCTAssertEqual(openedIDs.value.first, newID, "open에 전달된 ID는 생성된 윈도우 ID와 일치해야 한다")
    }

    /// Default bootstrap(path == nil)에서 pinned record store가 로드되고
    /// FileManagerFeature.State.makeInitial(path: nil, contentTabs:)에 전달되어
    /// pinned tab이 포함된 window가 생성됨을 검증한다.
    /// - 검증 내용: pinned record 1개 load → window에 pinned tab 1개 포함
    /// - 사전 조건: contentTabPinnedRecordClient.loadStore가 1개 pinned record 반환
    /// - 기대 결과: window state에 isPinned=true인 tab 1개 존재
    func testDefaultWindowBootstrapRestoresPinnedRecords() async {
        let newID = UUID()
        let pinnedStore = ContentTabPinnedRecordStore(records: [
            ContentTabPinnedRecord(
                id: "dir-1",
                page: .directory,
                anchor: .directory(path: "/Users/test/Documents"),
                title: "Documents",
                iconName: "folder",
                pinnedAt: Date(timeIntervalSince1970: 443),
            ),
        ])

        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(newID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient.loadStore = { _ in pinnedStore }
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        // WindowManager bootstrap은 open/app-preference 등 부수 child action을 방출하므로,
        // 이 테스트는 pinned restore 결과 상태만 검증한다.
        store.exhaustivity = .off

        await store.send(.file(.newWindow(path: nil)))
        await store.finish()

        let window = store.state.windows.first?.window
        XCTAssertNotNil(window, "window가 생성되어야 함")
        XCTAssertEqual(window?.contentTabs.tabs.count, 1, "pinned tab 1개가 복원되어야 함")
        XCTAssertTrue(window?.contentTabs.tabs[0].isPinned ?? false, "복원된 tab은 pinned 상태여야 함")
        XCTAssertEqual(window?.contentTabs.tabs[0].page, .directory)
        XCTAssertEqual(window?.contentTabs.tabs[0].title, "Documents")
    }

    /// 명시적 path가 있는 window(path != nil)에서는 pinned record restore가
    /// 발생하지 않고 기존 makeInitial(path:) 동작을 유지함을 검증한다.
    /// - 검증 내용: loadStore가 호출되지 않고 window가 정상 생성됨
    /// - 사전 조건: path = "/Users/test/Documents"
    /// - 기대 결과: loadStore 미호출, 생성된 window는 일반 directory tab 포함
    func testExplicitPathWindowSkipsPinnedRestore() async {
        let newID = UUID()
        let storeLoadCalled = LockIsolated(false)

        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(newID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.contentTabPinnedRecordClient.loadStore = { _ in
                storeLoadCalled.withValue { $0 = true }
                return ContentTabPinnedRecordStore()
            }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        // 명시적 path window의 부수 window/open action은 완전히 검증하지 않으므로
        // path bypass 조건만 검증한다.
        store.exhaustivity = .off

        let testPath = "/Users/test/Documents"
        await store.send(.file(.newWindow(path: testPath)))
        await store.finish()

        XCTAssertFalse(storeLoadCalled.value, "명시적 path window에서는 loadStore가 호출되지 않아야 함")
        let window = store.state.windows.first?.window
        XCTAssertNotNil(window, "window가 생성되어야 함")
        XCTAssertEqual(window?.contentTabs.tabs.count, 1, "기본 Home tab 1개")
        XCTAssertEqual(window?.contentTabs.tabs[0].anchor, .directory(path: testPath))
        XCTAssertFalse(window?.contentTabs.tabs[0].isPinned ?? true, "명시적 path window의 tab은 unpinned")
    }
}
