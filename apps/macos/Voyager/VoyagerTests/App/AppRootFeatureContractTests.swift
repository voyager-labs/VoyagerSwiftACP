import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesCollection
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesExternalFileRouter
import VoyagerFeaturesUpdateVersion
@testable import VoyagerPagesFileManager
import VoyagerPagesOnboarding
import VoyagerPagesSettings
import VoyagerShared
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
        var initialState = AppRootFeature.State()
        initialState.windowManager.windows = [
            WindowSessionState(
                id: UUID(),
                window: .makeInitial(path: "/tmp"),
            ),
        ]

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
            $0.uuid = .incrementing
        }

        await store.send(.lifecycle(.delegate(.openInitialWindowIfNeeded)))
        await store.receive(\.windowManager.lifecycle.openInitialWindowIfNeeded)
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
        } withDependencies: {
            $0.userDefaultsClient.setBool = { _, _ in }
            $0.updaterClient.setAutomaticUpdate = { _ in }
        }
        store.exhaustivity = .off

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

    /// Launch 완료 전 cold state에서 receiveExternalURL 수신 시 pending만 유지함을 검증.
    func testReceiveExternalURLBuffersWhenNoWindowsBeforeLaunchFinishes() async throws {
        let url = try XCTUnwrap(URL(string: "voyager://open?url=file:///Users/test-1"))
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }

        await store.send(.receiveExternalURL(url)) {
            $0.pendingExternalURLs = [url]
            $0.isExternalURLRouteInFlightWithoutWindow = true
        }
    }

    /// Launch 완료 후 no-window 상태에서 receiveExternalURL 수신 시 initial window 경로를 요청함을 검증.
    func testReceiveExternalURLRequestsLifecycleFlushWhenNoWindowsAfterLaunchFinishes() async throws {
        let url = try XCTUnwrap(URL(string: "voyager://open?url=file:///Users/test-1"))
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.pathProbeClient.probeExistence = { _ in
                PathProbeResult(exists: false, isDirectory: false)
            }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in }
        }
        store.exhaustivity = .off

        await store.send(.receiveExternalURL(url)) {
            $0.pendingExternalURLs = [url]
            $0.isExternalURLFlushDelegateScheduled = true
            $0.isExternalURLRouteInFlightWithoutWindow = true
        }
        await store.receive { action in
            guard case .lifecycle(.delegate(.openInitialWindowIfNeeded)) = action else { return false }
            return true
        }
        XCTAssertTrue(store.state.pendingExternalURLs.isEmpty)
        await store.receive { action in
            guard case let .externalFileRouter(.receive(receivedURL)) = action else { return false }
            return receivedURL == url
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

    func testLifecycleDelegateFlushesPendingExternalURLWithoutOpeningBlankInitialWindow() async throws {
        let url = try XCTUnwrap(URL(string: "voyager://open?url=file:///tmp/voyager-cold-url"))
        var state = AppRootFeature.State()
        state.pendingExternalURLs = [url]

        let store = TestStore(initialState: state) {
            AppRootFeature()
        } withDependencies: {
            $0.pathProbeClient.probeExistence = { _ in
                PathProbeResult(exists: false, isDirectory: false)
            }
        }
        store.exhaustivity = .off

        await store.send(.lifecycle(.delegate(.openInitialWindowIfNeeded))) {
            $0.pendingExternalURLs = []
        }
        await store.receive { action in
            guard case let .externalFileRouter(.receive(receivedURL)) = action else { return false }
            return receivedURL == url
        }
    }

    func testReceiveExternalURLDoesNotScheduleDuplicateFlushDelegate() async throws {
        let url = try XCTUnwrap(URL(string: "voyager://open?url=file:///tmp/voyager-duplicate-schedule"))
        var state = AppRootFeature.State()
        state.lifecycle.didFinishLaunching = true
        state.isExternalURLFlushDelegateScheduled = true
        state.isExternalURLRouteInFlightWithoutWindow = true

        let store = TestStore(initialState: state) {
            AppRootFeature()
        }

        await store.send(.receiveExternalURL(url)) {
            $0.pendingExternalURLs = [url]
        }
    }

    func testLifecycleDelegateDuringExternalURLRouteInFlightDoesNotOpenBlankInitialWindow() async {
        var state = AppRootFeature.State()
        state.isExternalURLFlushDelegateScheduled = true
        state.isExternalURLRouteInFlightWithoutWindow = true

        let store = TestStore(initialState: state) {
            AppRootFeature()
        }

        await store.send(.lifecycle(.delegate(.openInitialWindowIfNeeded))) {
            $0.isExternalURLFlushDelegateScheduled = false
        }
        XCTAssertTrue(store.state.windowManager.windows.isEmpty)
    }

    func testExternalURLValidationErrorClearsNoWindowRouteInFlight() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/not-a-file"))
        var state = AppRootFeature.State()
        state.isExternalURLFlushDelegateScheduled = true
        state.isExternalURLRouteInFlightWithoutWindow = true

        let store = TestStore(initialState: state) {
            AppRootFeature()
        }

        await store.send(.externalFileRouter(.failed(.urlValidationError(url)))) {
            $0.externalFileRouter.currentStatus = .urlValidationError
            $0.isExternalURLFlushDelegateScheduled = false
            $0.isExternalURLRouteInFlightWithoutWindow = false
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
        initialState.pendingExternalURLs = [url1, url2]
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

        XCTAssertEqual(store.state.pendingExternalURLs, [url1, url2])

        await store.send(.windowManager(.file(.newWindow(path: nil))))

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

    /// No-window hot path: 열린 FMW 창이 없어도 receiveExternalFileURL 수신 → ExternalFileRouter로 즉시 전달을 검증.
    func testReceiveExternalFileURLForwardsWhenNoWindows() async {
        let url = URL(fileURLWithPath: "/tmp/voyager-no-window.txt")
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        } withDependencies: {
            $0.pathProbeClient.probeExistence = { _ in
                PathProbeResult(exists: false, isDirectory: false)
            }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in }
        }
        store.exhaustivity = .off

        await store.send(.receiveExternalFileURL(url, source: .systemOpenEvent, mode: .open))
        await store.receive { action in
            guard case let .externalFileRouter(.receiveFileURL(receivedURL, source, mode)) = action else {
                return false
            }
            return receivedURL == url && source == .systemOpenEvent && mode == .open
        }
    }

    /// RCL-002: 외부 `.voycoll` 문서는 generic ExternalFileRouter가 아니라 collection open window command로 전달된다.
    func testReceiveCollectionFileURLRoutesToCollectionWindowCommand() async {
        let url = URL(fileURLWithPath: "/tmp/saved.voycoll")
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        } withDependencies: {
            $0.uuid = .constant(UUID())
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.receiveCollectionFileURL(url))
        await store.receive { action in
            guard case let .windowManager(.file(.openCollectionFile(receivedURL))) = action else {
                return false
            }
            return receivedURL == url
        }
    }

    /// Cold → flush: 앱 준비 전 2개 URL이 pending에 적재된 뒤 첫 창을 열면 두 URL이 모두 receiveFileURL로
    /// flush되고(적재 순서 보존) pending 큐는 비어야 함을 검증.
    func testReceiveExternalFileURLFlushesAllOnFirstWindow() async {
        let url1 = URL(fileURLWithPath: "/tmp/voyager-flush-1.txt")
        let url2 = URL(fileURLWithPath: "/tmp/voyager-flush-2.txt")
        let windowID = UUID()

        var initialState = AppRootFeature.State()
        initialState.pendingExternalFileRoutes = [
            .init(url: url1, source: .systemOpenEvent, mode: .open),
            .init(url: url2, source: .nsservices, mode: .reveal),
        ]

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

        // 첫 창 오픈 → didOpenFirstWindow → flush
        await store.send(.windowManager(.file(.newWindow(path: nil))))

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
