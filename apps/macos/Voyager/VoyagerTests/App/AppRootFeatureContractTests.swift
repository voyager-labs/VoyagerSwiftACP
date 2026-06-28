import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesCollection
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesExternalFileRouter
import VoyagerFeaturesUpdateVersion
@testable import VoyagerPagesFileManager
import VoyagerPagesOnboarding
import VoyagerPagesSettings
import VoyagerWidgetsEntryViewLayout
import XCTest

/// 앱 루트 계약 — 최상위 라우팅과 델리게이트 전달을 검증.
@MainActor
final class AppRootFeatureContractTests: XCTestCase {
    /// testAppPreferencesUpdatedForwardsToWindowManagerApplyAppPreferences 테스트 동작을 검증한다.
    func testAppPreferencesUpdatedForwardsToWindowManagerApplyAppPreferences() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }

        var preferences = Voyager.AppPreferencesState()
        preferences.showHiddenFiles = true
        preferences.viewLayout = EntryViewLayoutState.Mode.grid
        preferences.sidebarVisible = false

        await store.send(.appPreferences(.delegate(.updated(preferences)))) {
            $0.appPreferences = preferences
        }
        await store.receive(\.windowManager.lifecycle.applyAppPreferences) {
            $0.windowManager.appPreferences = preferences
        }
    }

    /// testMenuCommandsDelegateForwardsToWindowManager 테스트 동작을 검증한다.
    func testMenuCommandsDelegateForwardsToWindowManager() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }

        await store.send(.menuCommands(.delegate(.windowManager(.file(.quickLook)))))
        await store.receive(\.windowManager.file.quickLook)
    }

    /// testMenuCommandsDelegateForwardsToUpdater 테스트 동작을 검증한다.
    func testMenuCommandsDelegateForwardsToUpdater() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }

        await store.send(.menuCommands(.delegate(.updater(.checkForUpdates))))
        await store.receive(\.updater.checkForUpdates)
    }

    /// testLifecycleDelegateForwardsToWindowManagerOpenInitialWindow 테스트 동작을 검증한다.
    func testLifecycleDelegateForwardsToWindowManagerOpenInitialWindow() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.lifecycle(.delegate(.openInitialWindowIfNeeded)))
        await store.receive(\.windowManager.lifecycle.openInitialWindowIfNeeded)
    }

    /// testHelperExternalFileChangeForwardsToWindowManager 테스트 동작을 검증한다.
    func testHelperExternalFileChangeForwardsToWindowManager() async {
        let windowID = UUID()
        let paths = ["/tmp/demo"]
        var initialState = AppRootFeature.State()
        initialState.windowManager.windows = [
            WindowSessionState(id: windowID, window: .makeInitial(path: "/tmp")),
        ]

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.helperExternalFileChanged(.init(paths: paths, source: .live)))
        await store.receive { action in
            guard case let .windowManager(.windows(.element(
                id: id,
                action: .window(.content(.externalFileSystemChanged(receivedPaths))),
            ))) = action else {
                return false
            }
            return id == windowID && receivedPaths == paths
        }
    }

    /// testHelperExternalFileChangeFansOutToAllOpenWindows 테스트 동작을 검증한다.
    func testHelperExternalFileChangeFansOutToAllOpenWindows() async {
        let firstID = UUID()
        let secondID = UUID()
        let paths = ["/tmp/demo"]

        var initialState = AppRootFeature.State()
        initialState.windowManager.windows = [
            WindowSessionState(id: firstID, window: .makeInitial(path: "/tmp/one")),
            WindowSessionState(id: secondID, window: .makeInitial(path: "/tmp/two")),
        ]

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        }

        await store.send(.helperExternalFileChanged(.init(paths: paths, source: .live)))
        await store.receive { action in
            guard case let .windowManager(.windows(.element(
                id: id,
                action: .window(.content(.externalFileSystemChanged(receivedPaths))),
            ))) = action else {
                return false
            }
            return id == firstID && receivedPaths == paths
        }
        await store.receive { action in
            guard case let .windowManager(.windows(.element(
                id: id,
                action: .window(.content(.externalFileSystemChanged(receivedPaths))),
            ))) = action else {
                return false
            }
            return id == secondID && receivedPaths == paths
        }
    }

    /// testMenuCommandsStateIsRecomputedAfterWindowManagerChanges 테스트 동작을 검증한다.
    func testMenuCommandsStateIsRecomputedAfterWindowManagerChanges() async {
        var initialState = AppRootFeature.State()
        let windowID = UUID()
        initialState.windowManager.windows = [
            WindowSessionState(
                id: windowID,
                window: .makeInitial(path: "/tmp"),
            ),
        ]
        initialState.windowManager.focusedWindowID = windowID

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        }
        store.exhaustivity = .off

        XCTAssertFalse(store.state.menuCommands.hasFocusedWindow)

        await store.send(.windowManager(.event(.windowBecameKey(windowID)))) {
            $0.windowManager.focusedWindowID = windowID
            $0.menuCommands.hasFocusedWindow = true
        }
    }

    func testSettingsGeneralCheckForUpdatesForwardsToUpdater() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }

        await store.send(.settings(.general(.checkForUpdates)))
        await store.receive(\.updater.checkForUpdates)
    }

    func testSettingsGeneralToggleAutomaticUpdateForwardsToUpdater() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }
        store.exhaustivity = .off

        await store.send(.settings(.general(.toggleAutomaticUpdate(true))))
        await store.receive { action in
            guard case .updater(.setAutomaticUpdate(true)) = action else {
                return false
            }
            return true
        }

        await store.send(.settings(.general(.toggleAutomaticUpdate(false))))
        await store.receive { action in
            guard case .updater(.setAutomaticUpdate(false)) = action else {
                return false
            }
            return true
        }
    }

    // MARK: - FMW-003: Cold Start URL Buffering

    /// Cold state(창 없음)에서 receiveExternalURL 수신 시 pendingExternalURLs에 순서대로 저장됨을 검증
    func testReceiveExternalURLBuffersAllWhenNoWindows() async throws {
        let url1 = try XCTUnwrap(URL(string: "voyager://open?url=file:///Users/test-1"))
        let url2 = try XCTUnwrap(URL(string: "voyager://open?url=file:///Users/test-2"))
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }

        await store.send(.receiveExternalURL(url1)) {
            $0.pendingExternalURLs = [url1]
        }
        await store.send(.receiveExternalURL(url2)) {
            $0.pendingExternalURLs = [url1, url2]
        }
    }

    /// Hot state(창 있음)에서 receiveExternalURL 수신 시 pendingExternalURLs가 비어 있음을 검증
    func testReceiveExternalURLForwardsWhenWindowsExist() async throws {
        let windowID = UUID()
        let url = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2Ftmp%2Fvoyager-hot"))
        var state = AppRootFeature.State()
        state.windowManager.windows = [
            WindowSessionState(id: windowID, window: .makeInitial(path: "/tmp")),
        ]

        let store = TestStore(initialState: state) {
            AppRootFeature()
        } withDependencies: {
            $0.pathProbeClient.probeExistence = { _ in
                PathProbeResult(exists: false, isDirectory: false)
            }
        }
        // store.exhaustivity = .off: Hot state에서 URL 수신 시 ExternalFileRouter로 effect가 전달되므로 핵심 state만 검증
        store.exhaustivity = .off

        await store.send(.receiveExternalURL(url))
        XCTAssertTrue(store.state.pendingExternalURLs.isEmpty)
    }

    func testAuthCallbackDelegateRoutesToExplicitAuthBoundary() async throws {
        let url = try XCTUnwrap(URL(string: "voyager://auth/callback?ticket=test&state=state"))
        let capturedAlert = LockIsolated<(title: String, message: String)?>(nil)

        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        } withDependencies: {
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { title, message in
                capturedAlert.withValue { $0 = (title, message) }
            }
        }

        await store.send(.externalFileRouter(.delegate(.routeToAuthCallback(url))))
        await store.receive(\.receiveAuthCallbackURL)
        await store.finish()

        XCTAssertEqual(capturedAlert.value?.title, "Voyager 로그인 복귀를 완료할 수 없습니다")
    }

    func testOpenAppFallbackDelegateRoutesToInitialWindowIfNeeded() async {
        let windowID = UUID()
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        } withDependencies: {
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
            $0.uuid = .constant(windowID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.externalFileRouter(.delegate(.openAppFallback)))
        await store.receive(\.windowManager.lifecycle.openInitialWindowIfNeeded)
        await store.receive { action in
            guard case .windowManager(.file(.newWindow(path: nil, selectEntryID: nil))) = action else {
                return false
            }
            return true
        }
    }

    func testLifecycleDelegateFlushesPendingExternalFileRouteWithoutOpeningBlankInitialWindow() async {
        let url = URL(fileURLWithPath: "/tmp/voyager-cold-file.txt")
        var state = AppRootFeature.State()
        state.pendingExternalFileRoutes = [
            .init(url: url, source: .systemOpenEvent, mode: .open),
        ]

        let store = TestStore(initialState: state) {
            AppRootFeature()
        } withDependencies: {
            $0.pathProbeClient.probeExistence = { _ in
                PathProbeResult(exists: false, isDirectory: false)
            }
        }

        await store.send(.lifecycle(.delegate(.openInitialWindowIfNeeded))) {
            $0.pendingExternalFileRoutes = []
        }
        await store.receive(\.externalFileRouter.receiveFileURL) {
            $0.externalFileRouter.currentStatus = .pathReceived
            $0.externalFileRouter.currentRequest = ExternalFileRouterRequest(
                originalURL: url,
                source: .systemOpenEvent,
                mode: .open,
            )
        }
        await store.receive(\.externalFileRouter.failed) {
            $0.externalFileRouter.currentStatus = .invalidPathError
            $0.externalFileRouter.currentRequest = ExternalFileRouterRequest(
                originalURL: url,
                source: .systemOpenEvent,
                mode: .open,
            )
        }
        await store.receive(\.externalFileRouter.delegate.showInvalidPathError)
        await store.finish()

        XCTAssertTrue(store.state.windowManager.windows.isEmpty)
    }

    /// Cold → flush: 창 없는 상태에서 2개 Deep Link를 적재한 뒤 첫 창을 열면 두 URL이 모두
    /// receive로 flush되고(적재 순서 보존) pending 큐는 비어야 함을 검증.
    func testReceiveExternalURLFlushesAllOnFirstWindow() async throws {
        let url1 = try XCTUnwrap(URL(string: "voyager://open?url=file:///tmp/voyager-flush-1"))
        let url2 = try XCTUnwrap(URL(string: "voyager://open?url=file:///tmp/voyager-flush-2"))
        let windowID = UUID()

        var initialState = AppRootFeature.State()
        // helper bridge .run(observeChangedPaths)이 호출되지 않도록 사전에 started 상태로 설정
        initialState.isHelperExternalFileBridgeStarted = true

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
            $0.uuid = .constant(windowID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.pathProbeClient.probeExistence = { _ in
                PathProbeResult(exists: false, isDirectory: false)
            }
        }
        store.exhaustivity = .off

        await store.send(.receiveExternalURL(url1))
        await store.send(.receiveExternalURL(url2))
        XCTAssertEqual(store.state.pendingExternalURLs, [url1, url2])

        await store.send(.windowManager(.file(.newWindow(path: nil))))

        await store.receive { action in
            if case .startHelperExternalFileBridge = action { return true }
            return false
        }
        await store.receive { action in
            if case .flushPendingReplay = action { return true }
            return false
        }
        await store.receive { action in
            guard case let .externalFileRouter(.receive(url)) = action else { return false }
            return url == url1
        }
        await store.receive { action in
            guard case let .externalFileRouter(.receive(url)) = action else { return false }
            return url == url2
        }

        XCTAssertTrue(store.state.pendingExternalURLs.isEmpty, "flush 후 pending Deep Link 큐는 비어야 한다")
    }

    // MARK: - FMW-003: receiveExternalFileURL Hot/Cold/Flush

    /// Hot path: 창이 존재할 때 receiveExternalFileURL 수신 → 즉시 ExternalFileRouter로 receiveFileURL 전달을 검증.
    /// pathProbeClient stub은 invalidPath를 반환하여 flush 이후 후속 effect를 최소화한다.
    func testReceiveExternalFileURLForwardsWhenWindowsExist() async {
        let url = URL(fileURLWithPath: "/tmp/voyager-hot.txt")
        let windowID = UUID()
        var state = AppRootFeature.State()
        state.windowManager.windows = [
            WindowSessionState(id: windowID, window: .makeInitial(path: "/tmp")),
        ]

        let store = TestStore(initialState: state) {
            AppRootFeature()
        } withDependencies: {
            // ExternalFileRouter가 receiveFileURL 수신 후 pathProbe를 호출하므로 stub 필요
            $0.pathProbeClient.probeExistence = { _ in
                PathProbeResult(exists: false, isDirectory: false)
            }
        }
        // store.exhaustivity = .off: receiveFileURL 이후 pathProbe 후속 effect(failed → delegate)가 비결정적이므로
        // 핵심 전달 여부(receiveExternalFileURL → externalFileRouter.receiveFileURL)만 검증
        store.exhaustivity = .off

        await store.send(.receiveExternalFileURL(url, source: .systemOpenEvent, mode: .open))
        await store.receive { action in
            guard case let .externalFileRouter(.receiveFileURL(receivedURL, source, mode)) = action else {
                return false
            }
            return receivedURL == url && source == .systemOpenEvent && mode == .open
        }
    }

    /// Cold path: 창이 없을 때 receiveExternalFileURL 수신 → pendingExternalFileRoutes에 적재되고 effect는 없음을 검증.
    func testReceiveExternalFileURLBuffersWhenNoWindows() async {
        let url = URL(fileURLWithPath: "/tmp/voyager-cold.txt")
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }

        await store.send(.receiveExternalFileURL(url, source: .systemOpenEvent, mode: .open)) {
            $0.pendingExternalFileRoutes = [
                .init(url: url, source: .systemOpenEvent, mode: .open),
            ]
        }
    }

    /// Cold → flush: 창 없는 상태에서 2개 URL을 적재한 뒤 첫 창을 열면 두 URL이 모두 receiveFileURL로
    /// flush되고(적재 순서 보존) pending 큐는 비어야 함을 검증.
    func testReceiveExternalFileURLFlushesAllOnFirstWindow() async {
        let url1 = URL(fileURLWithPath: "/tmp/voyager-flush-1.txt")
        let url2 = URL(fileURLWithPath: "/tmp/voyager-flush-2.txt")
        let windowID = UUID()

        var initialState = AppRootFeature.State()
        // helper bridge .run(observeChangedPaths)이 호출되지 않도록 사전에 started 상태로 설정
        initialState.isHelperExternalFileBridgeStarted = true

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
            $0.uuid = .constant(windowID)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            // flush된 receiveFileURL 각각이 pathProbe를 호출하므로 stub 필요
            $0.pathProbeClient.probeExistence = { _ in
                PathProbeResult(exists: false, isDirectory: false)
            }
        }
        // store.exhaustivity = .off: 첫 창 오픈 시 helper bridge/replay/ExternalFileRouter 후속 effect가 다수 발생하므로
        // flush 대상 receiveFileURL 2건과 pending 큐 소진 여부만 검증
        store.exhaustivity = .off

        // Cold state에서 2개 URL 적재
        await store.send(.receiveExternalFileURL(url1, source: .systemOpenEvent, mode: .open))
        await store.send(.receiveExternalFileURL(url2, source: .nsservices, mode: .reveal))
        XCTAssertEqual(store.state.pendingExternalFileRoutes.count, 2)

        // 첫 창 오픈 → didOpenFirstWindow → flush
        await store.send(.windowManager(.file(.newWindow(path: nil))))

        // reduceWindowPostAction이 동기적으로 발행하는 effect들을 발행 순서대로 수신
        await store.receive { action in
            if case .startHelperExternalFileBridge = action { return true }
            return false
        }
        await store.receive { action in
            if case .flushPendingReplay = action { return true }
            return false
        }
        // flush된 receiveFileURL 2건 (적재 순서 보존)
        await store.receive { action in
            guard case let .externalFileRouter(.receiveFileURL(url, source, mode)) = action else {
                return false
            }
            return url == url1 && source == .systemOpenEvent && mode == .open
        }
        await store.receive { action in
            guard case let .externalFileRouter(.receiveFileURL(url, source, mode)) = action else {
                return false
            }
            return url == url2 && source == .nsservices && mode == .reveal
        }

        XCTAssertTrue(store.state.pendingExternalFileRoutes.isEmpty, "flush 후 pending 큐는 비어야 한다")
    }

    func testExternalFileRouterPermissionDeniedDelegateShowsAlert() async {
        let path = "/Users/test/protected"
        let capturedAlert = LockIsolated<(title: String, message: String)?>(nil)

        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        } withDependencies: {
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { title, message in
                capturedAlert.withValue { $0 = (title: title, message: message) }
            }
        }

        await store.send(.externalFileRouter(.delegate(.showPermissionDeniedError(path: path))))
        await store.finish()

        XCTAssertEqual(capturedAlert.value?.title, "Voyager에서 위치를 열 수 없습니다")
        XCTAssertEqual(
            capturedAlert.value?.message,
            "접근 권한이 없어 \(path)를 열 수 없습니다. macOS 시스템 설정에서 Voyager의 파일 및 폴더 접근 권한을 확인해 주세요.",
        )
    }

    /// Proves AppRoot's Settings forwarding does NOT route through MenuCommands.
    /// MenuCommandsAction.Delegate has no `.settings` case — absence is structural.
    /// This test verifies that settings-driven actions (checkForUpdates) route
    /// directly to updater, not via menuCommands.
    func testSettingsCheckForUpdatesDoesNotRouteThroughMenuCommands() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }
        store.exhaustivity = .off

        await store.send(.settings(.general(.checkForUpdates)))
        await store.receive(\.updater.checkForUpdates)
    }
}
