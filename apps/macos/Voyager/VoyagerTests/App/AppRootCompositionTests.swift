import ComposableArchitecture
import Dependencies
@testable import Voyager
import VoyagerFeaturesAccountAccess
import VoyagerFeaturesUpdateVersion
import VoyagerPagesFileManager
import VoyagerPagesOnboarding
@testable import VoyagerPagesSettings
import VoyagerShared
import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class AppRootCompositionTests: XCTestCase {
    func testAppPreferencesUpdatedRoutesToWindowManager() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }
        store.exhaustivity = .off

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

    func testMenuCommandRoutesToUpdater() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }
        store.exhaustivity = .off

        await store.send(.menuCommands(.delegate(.updater(.checkForUpdates))))
        await store.receive(\.updater.checkForUpdates)
    }

    // MARK: - T2a/T2c GREEN: AppRoot launch/access-gate lifecycle → Settings bootstrap/hydration forwarding

    /// T2b GREEN: AppRoot가 `.lifecycle(.launch(.willFinishLaunching))`를 관찰해
    /// `.settings(.bootstrapLocalPreferences)`와 `.settings(.ai(.onAppear))`를 1회씩 전송한다.
    /// General/Appearance load와 AI bootstrap을 launch에서 함께 시작한다.
    func testAppRootLaunchWillFinishLaunchingForwardsSettingsBootstrapLocalPreferences() async {
        let store = TestStore(initialState: AppRootFeature.State()) {
            AppRootFeature()
        }
        store.exhaustivity = .off

        await store.send(.lifecycle(.launch(.willFinishLaunching)))
        await store.receive(\.settings.bootstrapLocalPreferences)
        await store.receive(\.settings.ai.onAppear)
    }

    /// T2c/T2d GREEN: AppRoot가 `.lifecycle(.accountAccessGate(.accountAccessGranted(snapshot)))`를 관찰해
    /// Settings-owned access snapshot hydration action만 1회 전송한다.
    /// AppLifecycle이 fetch한 snapshot을 Settings/Account가 재 fetch 없이 반영하고 (T2c),
    /// AI bootstrap은 launch에서 이미 시작되었으므로 여기서는 중복 전송하지 않는다.
    ///
    /// T11: `OnboardingWindowClient.testValue`가 모든 closure에서 fatalError를 호출하므로
    /// `accountAccessGranted → .delegate(.openInitialWindowIfNeeded) → WindowManager` 경로가 crash.
    /// 테스트-로컬 `withDependencies` override로 helperAppClient.start/stop no-op,
    /// onboardingWindowClient.showIfNeeded={false} 처리. 글로벌 testValue는 미변경.
    func testAppRootAccountAccessGrantedForwardsSettingsAccessSnapshotHydration() async {
        let snapshot = AccessStatusSnapshot(status: .coreLicenseActive)
        let store = makeAccountAccessGrantedStore()

        await store.send(.lifecycle(.accountAccessGate(.accountAccessGranted(snapshot: snapshot))))

        await store.receive(\.settings.appLifecycleAccessSnapshotReady) { state in
            state.settings.accessStatus = snapshot.status
        }
        await store.receive(\.settings.account.access.hydrateLaunchSnapshot) { state in
            state.settings.accountSettings.access.sessionExpiresAt = nil
            state.settings.accountSettings.access.hasAccountSession = false
            state.settings.accountSettings.access.didBootstrap = true
        }

        XCTAssertNil(store.state.settings.accountSettings.access.sessionExpiresAt)
        XCTAssertFalse(store.state.settings.accountSettings.access.hasAccountSession)
        await store.finish()
    }

    // MARK: - T11: sessionExpiresAt receive 검증

    /// T11: `sessionExpiresAt`가 non-nil인 snapshot이 AppRoot passthrough → Settings → AccountAccess
    /// 경로로 그대로 전달됨을 state 기반으로 검증.
    /// AppRootAction이 Equatable이 아니라 receive는 key path form 사용,
    /// payload 보존은 Settings/AccountAccess state delta(`sessionExpiresAt`, `hasAccountSession`)로 단언.
    func testAppRootAccountAccessGrantedForwardsSnapshotWithNonNilSessionExpiry() async {
        let expiry = Date(timeIntervalSince1970: 4_102_444_800)
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            sessionExpiresAt: expiry,
        )
        let store = makeAccountAccessGrantedStore()

        await store.send(.lifecycle(.accountAccessGate(.accountAccessGranted(snapshot: snapshot))))

        await store.receive(\.settings.appLifecycleAccessSnapshotReady) { state in
            state.settings.accessStatus = snapshot.status
        }
        await store.receive(\.settings.account.access.hydrateLaunchSnapshot) { state in
            state.settings.accountSettings.access.sessionExpiresAt = expiry
            state.settings.accountSettings.access.hasAccountSession = true
            state.settings.accountSettings.access.didBootstrap = true
        }

        XCTAssertEqual(
            store.state.settings.accountSettings.access.sessionExpiresAt,
            expiry,
            "non-nil sessionExpiresAt 보존",
        )
        XCTAssertTrue(
            store.state.settings.accountSettings.access.hasAccountSession,
            "session 존재 → hasAccountSession=true",
        )
        await store.finish()
    }

    /// T11: `sessionExpiresAt == nil`인 snapshot도 AppRoot passthrough → Settings → AccountAccess
    /// 경로가 정상 동작함을 검증. backward compat 시나리오 (세션 없이 access granted).
    func testAppRootAccountAccessGrantedForwardsSnapshotWithNilSessionExpiry() async {
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            sessionExpiresAt: nil,
        )
        let store = makeAccountAccessGrantedStore()

        await store.send(.lifecycle(.accountAccessGate(.accountAccessGranted(snapshot: snapshot))))

        await store.receive(\.settings.appLifecycleAccessSnapshotReady) { state in
            state.settings.accessStatus = snapshot.status
        }
        await store.receive(\.settings.account.access.hydrateLaunchSnapshot) { state in
            state.settings.accountSettings.access.sessionExpiresAt = nil
            state.settings.accountSettings.access.hasAccountSession = false
            state.settings.accountSettings.access.didBootstrap = true
        }

        XCTAssertNil(
            store.state.settings.accountSettings.access.sessionExpiresAt,
            "nil sessionExpiresAt 보존",
        )
        XCTAssertFalse(
            store.state.settings.accountSettings.access.hasAccountSession,
            "session 없음 → hasAccountSession=false",
        )
        await store.finish()
    }

    /// session 만료 감지 시 Settings top-level accessStatus와 Account 탭 child access 상태를 함께 정리한다.
    /// AccountSettingsView는 child access를 렌더링하므로 top-level만 비우면 stale Signed in UI가 남는다.
    func testSessionExpiredDetectedClearsSettingsAccountChildAccessState() async {
        let expiry = Date(timeIntervalSince1970: 4_102_444_800)
        var initialState = AppRootFeature.State()
        initialState.settings.accessStatus = .coreLicenseActive
        initialState.settings.accountSettings.access.status = .coreLicenseActive
        initialState.settings.accountSettings.access.snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            sessionExpiresAt: expiry,
        )
        initialState.settings.accountSettings.access.isComplete = true
        initialState.settings.accountSettings.access.hasAccountSession = true
        initialState.settings.accountSettings.access.sessionExpiresAt = expiry

        let store = makeAccountAccessGrantedStore(initialState: initialState)

        await store.send(.lifecycle(.sessionExpiredDetected(reason: .sessionExpired)))

        await store.receive(\.settings.accessStatusLoaded) { state in
            state.settings.accessStatus = .none
        }
        await store.receive(\.settings.account.access._sessionExpiredDetected) { state in
            state.settings.accountSettings.access.status = nil
            state.settings.accountSettings.access.snapshot = nil
            state.settings.accountSettings.access.isComplete = false
            state.settings.accountSettings.access.hasAccountSession = false
            state.settings.accountSettings.access.didSignInFail = true
            state.settings.accountSettings.access.isSessionExpired = true
            state.settings.accountSettings.access.sessionExpiresAt = nil
        }

        XCTAssertEqual(store.state.settings.accessStatus, .none)
        XCTAssertEqual(store.state.settings.accountSettings.setAuthState, .signInFailed)
        XCTAssertEqual(store.state.settings.accountSettings.setEntitlementState, .entitlementUnknown)
        XCTAssertFalse(store.state.settings.accountSettings.isManageAccountAvailable)
    }

    /// 사용자 명시적 로그아웃(reason == .explicitSignOut)은 Settings top-level만 clear 한다.
    /// Account child는 이미 `.delegate(.signedOut)`로 처리되므로 만료 액션으로 덮어쓰지 않는다.
    func testExplicitSignOutOnlyClearsSettingsTopLevel() async {
        var initialState = AppRootFeature.State()
        initialState.settings.accessStatus = .coreLicenseActive
        initialState.settings.accountSettings.access.hasAccountSession = true

        let store = makeAccountAccessGrantedStore(initialState: initialState)

        await store.send(.lifecycle(.sessionExpiredDetected(reason: .explicitSignOut)))

        await store.receive(\.settings.accessStatusLoaded) { state in
            state.settings.accessStatus = .none
        }

        // Account child는 만료 액션을 받지 않아 signed-in 상태가 유지된다.
        XCTAssertTrue(store.state.settings.accountSettings.access.hasAccountSession)
        XCTAssertFalse(store.state.settings.accountSettings.access.didSignInFail)
        await store.finish()
    }

    /// guard 재로그인 성공 시 Settings top-level accessStatus와 Account 탭 child access 상태를 함께 복원한다.
    /// AccountSettingsView는 child state로 렌더링되므로 top-level만 갱신하면 재로그인 후에도 signed-out으로 남는다.
    func testSessionLapseGuardUnlockedHydratesSettingsAccountChild() async {
        let expiry = Date(timeIntervalSince1970: 4_102_444_800)
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            sessionExpiresAt: expiry,
        )
        var initialState = AppRootFeature.State()
        // AppLifecycleFeature가 unlocked delegate를 정상 처리하려면 sessionLapseGuard
        // child state가 non-nil이어야 한다 (ifLet reducer가 action을 받을 수 있게).
        initialState.lifecycle.sessionLapseGuard = AccountAccessFeature.State()
        let store = makeAccountAccessGrantedStore(initialState: initialState)

        await store.send(.lifecycle(.sessionLapseGuard(.delegate(.unlocked(snapshot))))) { state in
            state.lifecycle.lastAccessStatus = .coreLicenseActive
            state.lifecycle.accountAccessGateResolved = true
            state.lifecycle.sessionLapseGuard = nil
        }

        await store.receive(\.settings.accessStatusLoaded) { state in
            state.settings.accessStatus = .coreLicenseActive
        }
        await store.receive(\.settings.account.access.hydrateLaunchSnapshot) { state in
            state.settings.accountSettings.access.status = .coreLicenseActive
            state.settings.accountSettings.access.snapshot = snapshot
            state.settings.accountSettings.access.sessionExpiresAt = expiry
            state.settings.accountSettings.access.hasAccountSession = true
            state.settings.accountSettings.access.didBootstrap = true
        }

        XCTAssertEqual(store.state.settings.accessStatus, .coreLicenseActive)
        XCTAssertEqual(store.state.settings.accountSettings.setAuthState, .signedIn)
        XCTAssertEqual(store.state.settings.accountSettings.setEntitlementState, .entitlementActive)
        await store.finish()
    }

    /// T2c GREEN: openAISettings gate는 accessStatusSnapshotClient.load() 없이
    /// `state.settings.accessStatus.isActive`를 읽어 AI tab 딥링크를 결정한다.
    /// - active 상태: `.settings(.selectSection(.ai))` 전송.
    func testOpenAISettingsSelectsAISectionWhenAccessStatusIsActive() async {
        var initialState = AppRootFeature.State()
        initialState.settings.accessStatus = .coreLicenseActive
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        }
        store.exhaustivity = .off

        await store.send(.openAISettings)
        await store.receive(\.settings.selectSection) { state in
            state.settings.selectedSection = .ai
        }
    }

    /// T2c GREEN: openAISettings gate는 inactive 상태일 때 AI tab 딥링크를 보내지 않는다.
    /// - inactive 상태: `.settings(.selectSection(.ai))` 미전송. native Settings scene은 동일하게 오픈.
    func testOpenAISettingsDoesNotSelectAISectionWhenAccessStatusIsInactive() async {
        var initialState = AppRootFeature.State()
        initialState.settings.accessStatus = .none
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        }
        store.exhaustivity = .off

        await store.send(.openAISettings)
        await store.finish()
    }

    // MARK: - T11 test support

    /// `accountAccessGranted` 경로 테스트용 TestStore.
    /// `OnboardingWindowClient.testValue`/`HelperAppClient.testValue.start`가 fatalError라
    /// 테스트-로컬 `withDependencies` override로만 우회. 글로벌 testValue는 미변경.
    private func makeAccountAccessGrantedStore(
        initialState: AppRootFeature.State = AppRootFeature.State(),
    ) -> TestStore<AppRootFeature.State, AppRootFeature.Action> {
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.helperAppClient.start = {}
            $0.helperAppClient.stop = {}
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.onboardingWindowClient.isRequired = { false }
            $0.accountSessionClient.delete = { _ in }
            $0.accessStatusSnapshotClient.remove = {}
            // T11: 직접 XCTest 실행 시 도달하는 전이 의존성의 testValue가 fatalError라
            // 테스트-로컬 deterministic override로만 우회. 글로벌 testValue는 미변경.
            // - WindowManagerFeature: @Dependency(\.uuid)
            // - EntryArrangementsApplyReducer: @Dependency(\.date)
            // - FileManagerWindowClient.open test dependency 미구성
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.fileManagerWindowClient.open = { _ in }
        }
        store.exhaustivity = .off
        return store
    }

    // MARK: - AppLifecycle access session hydration

    /// active access + session 존재: read가 반환한 session.expiresAt가 snapshot에 그대로 주입된다.
    func testAccessStatusSuccessPopulatesSessionExpiryWhenSessionExists() async {
        let expiry = Date(timeIntervalSince1970: 100)
        let session = AccountSession(
            accessToken: "access-token",
            status: .coreLicenseActive,
            refreshToken: "refresh",
            expiresAt: expiry,
        )
        let response = AccessStatusResponse(
            hasAccess: true,
            status: "active",
            productKey: "core",
        )
        let saved = SnapshotCaptureBox()

        let store = TestStore(initialState: AppLifecycleFeature.State()) {
            AppLifecycleFeature()
        } withDependencies: {
            // reducer가 date.now를 읽어 snapshot.fetchedAt에 넣는다. deterministic 고정.
            $0.date = DateGenerator { Date(timeIntervalSince1970: 0) }
            $0.accountSessionClient.read = { session }
            $0.helperAppClient.start = {}
            $0.helperAppClient.stop = {}
            $0.accessStatusSnapshotClient.save = { snapshot in
                saved.value = snapshot
            }
        }
        store.exhaustivity = .off

        await store.send(.accountAccessGate(.accessStatusResponse(.success(response))))

        await store.receive(\.accountAccessGate.accountAccessGranted)
        await store.receive(\.delegate.openInitialWindowIfNeeded)

        // sessionExpiresAt == session.expiresAt, status는 access gate 결과 유지.
        XCTAssertEqual(saved.value?.sessionExpiresAt, expiry)
        XCTAssertEqual(saved.value?.status, .coreLicenseActive)
        XCTAssertNotNil(saved.value)
        await store.finish()
    }

    /// active access + session 미존재: read가 nil을 반환해도 access gate는 succeed하며,
    /// snapshot.sessionExpiresAt는 nil이다.
    func testAccessStatusSuccessLeavesSessionExpiryNilWhenNoSession() async {
        let response = AccessStatusResponse(
            hasAccess: true,
            status: "active",
            productKey: "core",
        )
        let saved = SnapshotCaptureBox()

        let store = TestStore(initialState: AppLifecycleFeature.State()) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.date = DateGenerator { Date(timeIntervalSince1970: 0) }
            $0.accountSessionClient.read = { nil }
            $0.helperAppClient.start = {}
            $0.helperAppClient.stop = {}
            $0.accessStatusSnapshotClient.save = { snapshot in
                saved.value = snapshot
            }
        }
        store.exhaustivity = .off

        await store.send(.accountAccessGate(.accessStatusResponse(.success(response))))

        await store.receive(\.accountAccessGate.accountAccessGranted)
        await store.receive(\.delegate.openInitialWindowIfNeeded)

        // session read nil → sessionExpiresAt nil. access gate는 여전히 succeed (snapshot.status active).
        XCTAssertNotNil(saved.value, "access gate should still grant access without a session")
        XCTAssertNil(saved.value?.sessionExpiresAt, "no session → sessionExpiresAt must be nil")
        XCTAssertEqual(saved.value?.status, .coreLicenseActive)
        await store.finish()
    }

    // MARK: - T5: cache restore path sessionExpiresAt

    /// networkFailure + 유효 캐시 복원 시, cached snapshot이 가진 sessionExpiresAt를 그대로
    /// 쓰지 않고 `accountSessionClient.read()`로 다시 읽어 최신화한다.
    /// status/currentPeriodEnd/fetchedAt은 캐시 값을 유지.
    func testCacheRestoreReReadsSessionExpiryOnNetworkFailure() async {
        // cached.sessionExpiresAt(과거값)와 fresh session.expiresAt(미래값)을 다르게 설정해서
        // 캐시 값을 그대로 쓰는지, 다시 읽은 값으로 덮는지 구분한다.
        let cachedSessionExpiry = Date(timeIntervalSince1970: 50)
        let freshSessionExpiry = Date(timeIntervalSince1970: 5000)
        let cachedCurrentPeriodEnd = Date(timeIntervalSince1970: 100_000)
        let cachedFetchedAt = Date(timeIntervalSince1970: 0)
        let cached = AccessStatusSnapshot(
            status: .coreLicenseActive,
            currentPeriodEnd: cachedCurrentPeriodEnd,
            fetchedAt: cachedFetchedAt,
            sessionExpiresAt: cachedSessionExpiry,
        )
        let session = AccountSession(
            accessToken: "access-token",
            status: .coreLicenseActive,
            refreshToken: "refresh",
            expiresAt: freshSessionExpiry,
        )
        let saved = SnapshotCaptureBox()

        let store = TestStore(initialState: AppLifecycleFeature.State()) {
            AppLifecycleFeature()
        } withDependencies: {
            // dateNow == cachedFetchedAt → 24h TTL 통과, currentPeriodEnd > now 통과.
            $0.date = DateGenerator { cachedFetchedAt }
            $0.accessStatusSnapshotClient.load = { cached }
            $0.accountSessionClient.read = { session }
            $0.helperAppClient.start = {}
            $0.helperAppClient.stop = {}
            $0.accessStatusSnapshotClient.save = { snapshot in
                saved.value = snapshot
            }
        }
        store.exhaustivity = .off

        await store.send(.accountAccessGate(.accessStatusResponse(.failure(.networkFailure))))

        await store.receive(\.accountAccessGate.accountAccessGranted)
        await store.receive(\.delegate.openInitialWindowIfNeeded)

        // sessionExpiresAt는 fresh read 결과로 덮임 (cached 값 아님).
        XCTAssertEqual(saved.value?.sessionExpiresAt, freshSessionExpiry)
        // status/currentPeriodEnd/fetchedAt는 캐시 값 유지.
        XCTAssertEqual(saved.value?.status, .coreLicenseActive)
        XCTAssertEqual(saved.value?.currentPeriodEnd, cachedCurrentPeriodEnd)
        XCTAssertEqual(saved.value?.fetchedAt, cachedFetchedAt)
        await store.finish()
    }

    /// networkFailure + 유효 캐시 복원 시, session read가 nil을 반환하면
    /// success path와 동일하게 sessionExpiresAt=nil로 복원된다.
    /// gate policy는 그대로 granted (캐시 isActive/TTL/currentPeriodEnd 통과).
    func testCacheRestoreLeavesSessionExpiryNilWhenSessionMissingOnNetworkFailure() async {
        let cachedSessionExpiry = Date(timeIntervalSince1970: 50)
        let cachedCurrentPeriodEnd = Date(timeIntervalSince1970: 100_000)
        let cachedFetchedAt = Date(timeIntervalSince1970: 0)
        let cached = AccessStatusSnapshot(
            status: .coreLicenseActive,
            currentPeriodEnd: cachedCurrentPeriodEnd,
            fetchedAt: cachedFetchedAt,
            sessionExpiresAt: cachedSessionExpiry,
        )
        let saved = SnapshotCaptureBox()

        let store = TestStore(initialState: AppLifecycleFeature.State()) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.date = DateGenerator { cachedFetchedAt }
            $0.accessStatusSnapshotClient.load = { cached }
            $0.accountSessionClient.read = { nil }
            $0.helperAppClient.start = {}
            $0.helperAppClient.stop = {}
            $0.accessStatusSnapshotClient.save = { snapshot in
                saved.value = snapshot
            }
        }
        store.exhaustivity = .off

        await store.send(.accountAccessGate(.accessStatusResponse(.failure(.networkFailure))))

        await store.receive(\.accountAccessGate.accountAccessGranted)
        await store.receive(\.delegate.openInitialWindowIfNeeded)

        // session read nil → fresh sessionExpiresAt == nil. cached 값은 무시.
        XCTAssertNotNil(saved.value, "cache restore should still grant access")
        XCTAssertNil(saved.value?.sessionExpiresAt, "missing session → sessionExpiresAt nil (re-read result)")
        XCTAssertEqual(saved.value?.status, .coreLicenseActive)
        XCTAssertEqual(saved.value?.currentPeriodEnd, cachedCurrentPeriodEnd)
        XCTAssertEqual(saved.value?.fetchedAt, cachedFetchedAt)
        await store.finish()
    }

    /// auth_session_flow.md:111-115, ACC-003-guard_session_lapse.md:26-31
    /// sessionExpiredDetected(reason:)는 reason과 무관하게 lastAccessStatus/accountAccessGateResolved를
    /// 즉시 지우고, 이후 appReopen이 reopen delegate를 다시 보내지 못하게 막는다.
    func testSessionExpiredDetectedInvalidatesAppLifecycleAndBlocksAppReopenForAllReasons() async {
        let reasons: [AccountSessionEndReason?] = [
            .explicitSignOut,
            .sessionExpired,
            nil,
        ]

        for reason in reasons {
            var initialState = AppLifecycleFeature.State()
            initialState.lastAccessStatus = .coreLicenseActive
            initialState.accountAccessGateResolved = true

            let store = TestStore(initialState: initialState) {
                AppLifecycleFeature()
            } withDependencies: {
                $0.accountSessionClient.read = { nil }
                $0.helperAppClient.start = {}
                $0.helperAppClient.stop = {}
                $0.onboardingWindowClient.showIfNeeded = { false }
                $0.onboardingWindowClient.isRequired = { true }
                $0.notificationCenterClient.notifications = { _, _ in
                    AsyncStream { continuation in
                        continuation.finish()
                    }
                }
            }

            await store.send(.sessionExpiredDetected(reason: reason)) { state in
                state.lastAccessStatus = nil
                state.accountAccessGateResolved = false
            }

            await store.send(.launch(.appReopen(hasVisibleWindows: false)))
            await store.finish()
        }
    }

    /// auth_session_flow.md:111-115, ACC-003-guard_session_lapse.md:26-31
    /// sessionLapseGuard가 이미 존재해도 sessionExpiredDetected(reason:)는 먼저
    /// lastAccessStatus/accountAccessGateResolved를 무효화해야 stale active access가 남지 않는다.
    func testSessionExpiredDetectedInvalidatesEvenWhenSessionLapseGuardAlreadyExists() async {
        var initialState = AppLifecycleFeature.State()
        initialState.lastAccessStatus = .coreLicenseActive
        initialState.accountAccessGateResolved = true
        initialState.sessionLapseGuard = AccountAccessFeature.State()

        let store = TestStore(initialState: initialState) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.accountSessionClient.read = { nil }
            $0.helperAppClient.start = {}
            $0.helperAppClient.stop = {}
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.onboardingWindowClient.isRequired = { false }
            $0.notificationCenterClient.notifications = { _, _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }

        await store.send(.sessionExpiredDetected(reason: .sessionExpired)) { state in
            state.lastAccessStatus = nil
            state.accountAccessGateResolved = false
        }

        await store.finish()
    }

    // MARK: - PR #295 Codex P1: sessionLapseGuard appReopen 복구

    /// sessionLapseGuard가 있고 accountAccessGateResolved=false여도 appReopen이
    /// reopen delegate를 보내 FileManager 창을 띄워 가드 오버레이를 마운트한다.
    /// 빈 창 상태에서 세션 만료/로그아웃 후 Dock 재활성화로 가드가 보여야 한다.
    func testAppReopenReopensWindowWhenSessionLapseGuardPresentAndGateUnresolved() async {
        var initialState = AppLifecycleFeature.State()
        initialState.accountAccessGateResolved = false
        initialState.sessionLapseGuard = AccountAccessFeature.State()

        let store = TestStore(initialState: initialState) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.onboardingWindowClient.showIfNeeded = { false }
        }

        await store.send(.launch(.appReopen(hasVisibleWindows: false)))
        await store.receive(\.delegate.reopenWindowIfNeeded)
        await store.finish()
    }

    /// sessionLapseGuard가 없고 accountAccessGateResolved=false면 appReopen은
    /// reopen delegate를 보내지 않고 그대로 차단된다. (locked/no-session/no-active-access)
    func testAppReopenStaysBlockedWhenNoSessionLapseGuardAndGateUnresolved() async {
        var initialState = AppLifecycleFeature.State()
        initialState.accountAccessGateResolved = false

        let store = TestStore(initialState: initialState) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.onboardingWindowClient.showIfNeeded = { false }
        }

        await store.send(.launch(.appReopen(hasVisibleWindows: false)))
        await store.finish()
    }
}

/// snapshot capture용 reference box. `accessStatusSnapshotClient.save` 클로저가
/// `@Sendable`이므로 box도 Sendable이어야 함. 테스트는 직렬 실행되므로
/// data race는 없고 `@unchecked Sendable`로 표시.
private final class SnapshotCaptureBox: @unchecked Sendable {
    var value: AccessStatusSnapshot?
}
