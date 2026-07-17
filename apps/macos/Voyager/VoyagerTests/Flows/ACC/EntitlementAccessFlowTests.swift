// FLOW-ID: acc.entitlement_access
import ComposableArchitecture
import Dependencies
@testable import Voyager
import VoyagerFeaturesAccountAccess
import VoyagerFeaturesExternalFileRouter
import VoyagerPagesFileManager
import VoyagerPagesOnboarding
@testable import VoyagerPagesSettings
import VoyagerShared
import XCTest

@MainActor
final class EntitlementAccessFlowTests: XCTestCase {
    // FLOW-PATH: happy_path

    /// ACC-002-check_entitlement_status: 활성 entitlement가 canonical gate를 해제한다.
    /// 유효한 entitlement 확인 결과가 lifecycle, Settings projection, 초기 window 경로로 전파되는지를 검증한다.
    /// - 검증 내용: unlocked delegate가 granted gate와 Settings entitlement projection을 만들고 initial window delegate를 한 번
    /// 생성한다.
    /// - 사전 조건: access gate는 checking이고 verified core license snapshot이 존재한다.
    /// - 기대 결과: gate는 granted, Settings entitlement axis는 active, initial window delegate는 한 번이다.
    func testActiveEntitlementUnlocksGateUpdatesSettingsAndOpensWindowOnce() async {
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            sessionExpiresAt: AccountAccessFlowTestSupport.validSession.expiresAt,
            deviceBindingVerifiedAt: AccountAccessFlowTestSupport.referenceDate,
        )
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accessGatePhase = .checking
        initialState.lifecycle.accountAccess.hasAccountSession = true
        initialState.lifecycle.accountAccess.status = .coreLicenseActive
        let store = AccountAccessFlowTestSupport.makeRootStore(initialState: initialState)
        // store.exhaustivity = .off: root, lifecycle, Settings, window manager의 조합 effect를 한 경로로 검증함.
        store.exhaustivity = .off

        await store.send(.lifecycle(.accountAccess(.delegate(.unlocked(snapshot)))))
        await store.receive(\.settings.accountAccessPresentationUpdated)

        XCTAssertEqual(store.state.lifecycle.accessGatePhase, .granted)
        XCTAssertTrue(store.state.lifecycle.didStartHelper)
        XCTAssertEqual(store.state.settings.accountSettings.setEntitlementState, .entitlementActive)
        await store.finish()
    }

    // FLOW-PATH: no_entitlement_paywall

    /// ACC-002-show_paywall_cta: entitlement가 없으면 gate는 잠긴 채 pricing 경계를 요청한다.
    /// 실제 브라우저를 열지 않고 pricing URL boundary가 기록되는지만 검증한다.
    /// - 검증 내용: none entitlement가 blocked projection을 만들고 openPricingTapped가 recorded URL boundary를 호출한다.
    /// - 사전 조건: signed-in session과 AccessStatus.none 상태, in-memory pricing URL recorder가 있다.
    /// - 기대 결과: gate는 recoveryRequired이고 pricing URL만 기록되며 외부 브라우저는 열리지 않는다.
    func testNoEntitlementKeepsGateLockedAndRoutesPricingRequest() async throws {
        let pricingURL = try XCTUnwrap(URL(string: "https://example.test/pricing"))
        let openedURLs = LockIsolated<[URL]>([])
        var accessState = AccountAccessFeature.State()
        accessState.hasAccountSession = true
        accessState.status = AccessStatus.none
        let accessStore = TestStore(initialState: accessState) {
            AccountAccessFeature()
        } withDependencies: {
            $0.checkoutURLClient.pricingURL = { pricingURL }
            $0.checkoutURLClient.openURL = { url in
                openedURLs.withValue { $0.append(url) }
            }
        }
        // store.exhaustivity = .off: URL boundary effect만 flow에서 기록하고 local web-result details는 ACC-002 suite가 소유함.
        accessStore.exhaustivity = .off
        let lifecycleStore = TestStore(initialState: AppLifecycleFeature.State()) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.onboardingWindowClient.isRequired = { false }
        }
        // store.exhaustivity = .off: lifecycle guard route는 parent delegate forwarding을 함께 발생시킴.
        lifecycleStore.exhaustivity = .off

        await lifecycleStore.send(.accountAccess(.delegate(.recoveryRequired(.sessionRequired))))
        await lifecycleStore.receive(\.delegate.openInitialWindowIfNeeded)
        await accessStore.send(.openPricingTapped)
        await accessStore.receive(\._webURLResult)

        XCTAssertEqual(lifecycleStore.state.accessGatePhase, .recoveryRequired)
        XCTAssertEqual(accessStore.state.accountAccessStepState, .blocked)
        XCTAssertEqual(openedURLs.value, [pricingURL])
        await lifecycleStore.finish()
        await accessStore.finish()
    }

    // FLOW-PATH: trial_access

    /// ACC-002-handle_entitlement_change: trial 만료는 이미 열린 gate를 다시 잠근다.
    /// 활성 trial 결과 뒤 만료 entitlement snapshot이 lifecycle guard로 재투영되는지를 검증한다.
    /// - 검증 내용: trial active는 granted를 유지하고 trial expired sync 결과는 recoveryRequired와 expired projection으로 전환한다.
    /// - 사전 조건: verified trial snapshot으로 granted 상태이며 다음 sync generation은 1이다.
    /// - 기대 결과: access status는 trialExpired, gate는 recoveryRequired, Settings entitlement axis는 entitlementExpired다.
    func testTrialUnlocksThenExpiryRelocksCanonicalGate() async {
        let activeSnapshot = AccessStatusSnapshot(
            status: .trialActive,
            fetchedAt: AccountAccessFlowTestSupport.referenceDate,
            sessionExpiresAt: AccountAccessFlowTestSupport.validSession.expiresAt,
            deviceBindingVerifiedAt: AccountAccessFlowTestSupport.referenceDate,
        )
        let expiredSyncResult = makeSyncResult(status: "trial_expired", hasAccess: false)
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accessGatePhase = .granted
        initialState.lifecycle.accountAccess.hasAccountSession = true
        initialState.lifecycle.accountAccess.status = .trialActive
        initialState.lifecycle.accountAccess.snapshot = activeSnapshot
        initialState.lifecycle.accountAccess.syncGeneration = 1
        let store = AccountAccessFlowTestSupport.makeRootStore(initialState: initialState)
        // store.exhaustivity = .off: sync persistence와 root presentation effect가 함께 발생하는 cross-feature flow임.
        store.exhaustivity = .off

        await store.send(.lifecycle(.accountAccess(._sessionSyncCompleted(
            generation: 1,
            result: .success(expiredSyncResult),
        ))))
        await store.receive(\.settings.accountAccessPresentationUpdated)
        await store.receive(\.lifecycle.accountAccess.delegate)
        await store.receive(\.settings.accountAccessPresentationUpdated)

        XCTAssertEqual(store.state.lifecycle.accountAccess.status, .trialExpired)
        XCTAssertEqual(store.state.lifecycle.accessGatePhase, .recoveryRequired)
        XCTAssertEqual(store.state.settings.accountSettings.setEntitlementState, .entitlementExpired)
        await store.finish()
    }

    // FLOW-PATH: entitlement_change

    /// ACC-002-handle_entitlement_change: entitlement 변경은 gate와 Settings 상태를 같은 canonical child에서 다시 계산한다.
    /// active entitlement가 revoked 상태로 바뀔 때 surface projection이 stale active로 남지 않는지 검증한다.
    /// - 검증 내용: revoked sync completion이 lifecycle recovery delegate와 Settings revoked projection을 발행한다.
    /// - 사전 조건: core license가 granted 상태이고 entitlement refresh generation은 1이다.
    /// - 기대 결과: gate는 recoveryRequired이며 Settings entitlement axis는 entitlementRevoked다.
    func testEntitlementChangeReprojectsGateAndSettingsState() async {
        let revokedSyncResult = makeSyncResult(status: "revoked", hasAccess: false)
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accessGatePhase = .granted
        initialState.lifecycle.accountAccess.hasAccountSession = true
        initialState.lifecycle.accountAccess.status = .coreLicenseActive
        initialState.lifecycle.accountAccess.syncGeneration = 1
        let store = AccountAccessFlowTestSupport.makeRootStore(initialState: initialState)
        // store.exhaustivity = .off: entitlement persistence, child delegate, Settings projection을 함께 검증함.
        store.exhaustivity = .off

        await store.send(.lifecycle(.accountAccess(._sessionSyncCompleted(
            generation: 1,
            result: .success(revokedSyncResult),
        ))))
        await store.receive(\.settings.accountAccessPresentationUpdated)
        await store.receive(\.lifecycle.accountAccess.delegate)
        await store.receive(\.settings.accountAccessPresentationUpdated)

        XCTAssertEqual(store.state.lifecycle.accessGatePhase, .recoveryRequired)
        XCTAssertEqual(store.state.lifecycle.accountAccess.status, .revoked)
        XCTAssertEqual(store.state.settings.accountSettings.setEntitlementState, .entitlementRevoked)
        await store.finish()
    }

    // FLOW-PATH: session_expired_fallback

    /// ACC-001-session_expiry: 만료된 session은 entitlement 재조회 없이 session lapse guard를 표시한다.
    /// 이전 active entitlement가 있어도 session expiration이 canonical child teardown을 우선하는지 검증한다.
    /// - 검증 내용: sessionExpiredDetected가 stale access facts를 제거하고 recoveryRequired guard delegate를 만든다.
    /// - 사전 조건: active session과 core license 상태가 lifecycle child에 있다.
    /// - 기대 결과: session은 logged out, access status는 비어 있고 entitlement sync는 시작되지 않는다.
    func testSessionExpiredSkipsEntitlementAndShowsSessionLapseGuard() async {
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accessGatePhase = .granted
        initialState.lifecycle.accountAccess.hasAccountSession = true
        initialState.lifecycle.accountAccess.status = .coreLicenseActive
        let store = AccountAccessFlowTestSupport.makeRootStore(initialState: initialState)
        // store.exhaustivity = .off: session teardown은 cancellation과 Settings projection effect를 함께 발생시킴.
        store.exhaustivity = .off

        await store.send(.lifecycle(.sessionExpiredDetected(reason: .sessionExpired)))
        await store.receive(\.lifecycle.accountAccess._sessionExpiredDetected)
        await store.receive(\.lifecycle.accountAccess.delegate)

        XCTAssertFalse(store.state.lifecycle.accountAccess.hasAccountSession)
        XCTAssertNil(store.state.lifecycle.accountAccess.status)
        XCTAssertEqual(store.state.lifecycle.accessGatePhase, .recoveryRequired)
        XCTAssertNotNil(store.state.lifecycle.presentedAccountAccess)
        await store.finish()
    }

    // FLOW-PATH: logged_out_entitlement_skip

    /// ACC-002-check_entitlement_status: logged out 상태는 성공적인 로그인 전까지 entitlement sync를 생략한다.
    /// session이 없는 상태의 sync request가 no-op이고 login completion 뒤에만 sync가 시작되는지를 검증한다.
    /// - 검증 내용: logged out sessionSyncRequested는 generation을 바꾸지 않고, handoff success는 login sync action을 보낸다.
    /// - 사전 조건: lifecycle AccountAccess는 session이 없고 handoff exchange state가 준비되어 있다.
    /// - 기대 결과: 첫 요청은 no-op이며 로그인 완료 후 sessionSyncRequested가 한 번 발생한다.
    func testLoggedOutSkipsEntitlementUntilSuccessfulLogin() async {
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accountAccess.isSignInInProgress = true
        initialState.lifecycle.accountAccess.handoffExchangeState = "login-state"
        let store = AccountAccessFlowTestSupport.makeRootStore(initialState: initialState)
        // store.exhaustivity = .off: login completion은 refresh deadline과 canonical Settings projection을 함께 생성함.
        store.exhaustivity = .off

        await store.send(.lifecycle(.accountAccess(.sessionSyncRequested(intent: .validate, reason: .manual))))
        XCTAssertEqual(store.state.lifecycle.accountAccess.syncGeneration, 0)
        XCTAssertFalse(store.state.lifecycle.accountAccess.hasAccountSession)

        await store.send(.lifecycle(.accountAccess(._handoffExchangeCompleted(
            state: "login-state",
            generation: 0,
            result: .success(AccountAccessHandoffCompletion(
                expiresAt: AccountAccessFlowTestSupport.validSession.expiresAt,
                sessionBindingID: AccountAccessFlowTestSupport.validSession.sessionBindingID,
            )),
        ))))
        await store.receive(\.lifecycle.accountAccess.sessionSyncRequested)

        XCTAssertTrue(store.state.lifecycle.accountAccess.hasAccountSession)
        XCTAssertEqual(store.state.lifecycle.accountAccess.syncGeneration, 2)
        await store.skipInFlightEffects()
    }

    // MARK: - Lifecycle access gate regressions

    func testLifecycleLaunchDelegatesAccessToCanonicalChild() async {
        let directFetchCount = LockIsolated(0)
        let store = TestStore(initialState: AppLifecycleFeature.State()) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.authNetworkClient.fetchAccessStatus = {
                directFetchCount.withValue { $0 += 1 }
                return AccessStatusResponse(hasAccess: false, status: "trial_expired", productKey: "trial")
            }
            $0.accountSessionClient.read = { _ in nil }
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.onboardingWindowClient.isRequired = { true }
        }
        // store.exhaustivity = .off: launch bootstrap은 AccountAccess child의 restoration effect를 포함함.
        store.exhaustivity = .off

        await store.send(.launch(.didFinishLaunching)) {
            $0.didFinishLaunching = true
            $0.accessGatePhase = .checking
        }

        await store.receive(\.accountAccess.onAppear)
        await store.receive(\.accountAccess._onAppearSessionRestored)
        await store.receive(\.accountAccess.delegate) {
            $0.accessGatePhase = .recoveryRequired
        }

        XCTAssertEqual(directFetchCount.value, 0)
        await store.skipInFlightEffects()
        await store.finish()
    }

    func testLifecycleUnlockedStartsHelperAndOpensWindowOnce() async {
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            sessionExpiresAt: Date(timeIntervalSince1970: 4_102_444_800),
            deviceBindingVerifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )
        var initialState = AppLifecycleFeature.State()
        initialState.accessGatePhase = .checking
        let store = TestStore(initialState: initialState) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.helperAppClient.start = {}
            $0.helperAppClient.stop = {}
            $0.helperAppClient.terminationEvents = {
                AsyncStream { $0.finish() }
            }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.onboardingWindowClient.isRequired = { false }
            $0.notificationCenterClient.notifications = { _, _ in
                AsyncStream { $0.finish() }
            }
        }
        // store.exhaustivity = .off: helper monitor는 장기 관찰 effect이며 이 test는 access gate 결과를 소유함.
        store.exhaustivity = .off

        await store.send(.accountAccess(.delegate(.unlocked(snapshot))))

        XCTAssertEqual(store.state.accessGatePhase, .granted)
        XCTAssertTrue(store.state.didStartHelper)
        await store.finish()
    }

    func testLifecycleRecoveryRequiredDoesNotStartHelper() async {
        let store = TestStore(initialState: AppLifecycleFeature.State()) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.helperAppClient.start = {}
            $0.onboardingWindowClient.isRequired = { false }
            $0.notificationCenterClient.notifications = { _, _ in
                AsyncStream { $0.finish() }
            }
        }
        // store.exhaustivity = .off: recovery route는 parent delegate effect만 검증하면 충분함.
        store.exhaustivity = .off

        await store.send(.accountAccess(.delegate(.recoveryRequired(.sessionRequired)))) {
            $0.accessGatePhase = .recoveryRequired
        }

        await store.receive(\.delegate.openInitialWindowIfNeeded)

        XCTAssertEqual(store.state.accessGatePhase, .recoveryRequired)
        XCTAssertFalse(store.state.didStartHelper)
        await store.finish()
    }

    func testPresentedAccountAccessNilOutsideGuardPhases() {
        let phases: [AppLifecycleAccessGatePhase] = [
            .unresolved,
            .checking,
            .granted,
            .terminating,
        ]
        for phase in phases {
            var state = AppLifecycleFeature.State()
            state.accessGatePhase = phase
            XCTAssertNil(
                state.presentedAccountAccess,
                "\(phase) should not present guard overlay",
            )
        }
    }

    func testPresentedAccountAccessReturnsCanonicalChildDuringRecovery() {
        var state = AppLifecycleFeature.State()
        state.accessGatePhase = .recoveryRequired
        state.accountAccess.status = .trialExpired
        state.accountAccess.hasAccountSession = true

        let presented = state.presentedAccountAccess
        XCTAssertNotNil(presented)
        XCTAssertEqual(presented, state.accountAccess)
        XCTAssertEqual(presented?.status, .trialExpired)
        XCTAssertEqual(presented?.hasAccountSession, true)
    }

    func testOpenInitialWindowDefersPendingExternalRoutesWhenRecoveryRequired() async throws {
        let deepLink = try XCTUnwrap(URL(string: "voyager://open"))
        var initialState = AppRootFeature.State()
        initialState.pendingExternalURLs = [deepLink]
        initialState.lifecycle.accessGatePhase = .recoveryRequired

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.onboardingWindowClient.isRequired = { false }
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.continuousClock = ImmediateClock()
            $0.fileManagerWindowClient.open = { _ in }
        }
        // store.exhaustivity = .off: deferred route의 window manager downstream은 별도 flow가 소유함.
        store.exhaustivity = .off

        await store.send(.lifecycle(.delegate(.openInitialWindowIfNeeded)))
        await store.receive(\.windowManager.lifecycle.openInitialWindowIfNeeded)

        XCTAssertEqual(store.state.pendingExternalURLs, [deepLink])
        await store.finish()
    }

    /// ACC-002-check_entitlement_status: 복구 단계는 외부 파일 batch를 보존하며 account 복구 창을 연다.
    /// 외부 파일 cold-launch 중 복구가 필요해도 queue를 소비하지 않고 복구 UI 진입점을 보장한다.
    /// - 검증 내용: recoveryRequired의 초기 창 delegate 전달과 external-open queue 불변성을 함께 확인한다.
    /// - 사전 조건: pending external-open batch가 있고 access gate는 recoveryRequired다.
    /// - 기대 결과: 초기 창 요청은 전달되고 queue와 active batch 상태는 그대로 유지된다.
    func testOpenInitialWindowPreservesExternalBatchQueueDuringRecovery() async throws {
        let batchID = UUID(400)
        let itemID = UUID(401)
        let url = try XCTUnwrap(URL(string: "file:///tmp/recovery-item"))
        let request = ExternalFileRouterBatchRequest(
            batchID: batchID,
            items: [
                .init(itemID: itemID, index: 0, url: url, source: .systemOpenEvent, mode: .open),
            ],
        )
        var initialState = AppRootFeature.State()
        initialState.externalOpenBatchQueue = [
            .init(request: request, requiresInitialWindowFallback: true),
        ]
        initialState.lifecycle.accessGatePhase = .recoveryRequired

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.onboardingWindowClient.isRequired = { false }
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.continuousClock = ImmediateClock()
            $0.fileManagerWindowClient.open = { _ in }
        }
        // store.exhaustivity = .off: recovery 창 생성 mechanics는 WindowManager owner가 검증함.
        store.exhaustivity = .off

        await store.send(.lifecycle(.delegate(.openInitialWindowIfNeeded)))
        await store.receive(\.windowManager.lifecycle.openInitialWindowIfNeeded)

        XCTAssertEqual(store.state.externalOpenBatchQueue.map(\.request.batchID), [batchID])
        XCTAssertNil(store.state.activeExternalOpenBatch)
        await store.finish()
    }

    func testOpenInitialWindowDefersPendingExternalRoutesWhenSignedOut() async throws {
        let deepLink = try XCTUnwrap(URL(string: "voyager://open"))
        var initialState = AppRootFeature.State()
        initialState.pendingExternalURLs = [deepLink]
        initialState.lifecycle.accessGatePhase = .signedOut

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.onboardingWindowClient.isRequired = { false }
        }
        // store.exhaustivity = .off: signed-out defer path는 root routing만 검증함.
        store.exhaustivity = .off

        await store.send(.lifecycle(.delegate(.openInitialWindowIfNeeded)))

        XCTAssertEqual(store.state.pendingExternalURLs, [deepLink])
        XCTAssertTrue(store.state.windowManager.windows.isEmpty)
        await store.finish()
    }

    func testOpenInitialWindowDoesNotOpenEmptyWindowWhileChecking() async throws {
        let deepLink = try XCTUnwrap(URL(string: "voyager://open"))
        var initialState = AppRootFeature.State()
        initialState.pendingExternalURLs = [deepLink]
        initialState.isExternalURLFlushDelegateScheduled = true
        initialState.lifecycle.accessGatePhase = .checking

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.onboardingWindowClient.isRequired = { false }
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.fileManagerWindowClient.open = { _ in }
        }
        // store.exhaustivity = .off: checking phase는 route flush를 차단하는 state gate만 검증함.
        store.exhaustivity = .off

        await store.send(.lifecycle(.delegate(.openInitialWindowIfNeeded))) {
            $0.isExternalURLFlushDelegateScheduled = false
        }

        XCTAssertEqual(store.state.pendingExternalURLs, [deepLink])
        XCTAssertTrue(store.state.windowManager.windows.isEmpty)
        await store.finish()
    }

    func testAccountAccessUnlockFlushesQueuedRoutes() async throws {
        let deepLink = try XCTUnwrap(URL(string: "voyager://open"))
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            sessionExpiresAt: Date(timeIntervalSince1970: 4_102_444_800),
        )
        var initialState = AppRootFeature.State()
        initialState.pendingExternalURLs = [deepLink]

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.helperAppClient.start = {}
            $0.helperAppClient.stop = {}
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.onboardingWindowClient.isRequired = { false }
            $0.accountSessionClient.delete = { _ in }
            $0.accessStatusSnapshotClient = AccessStatusSnapshotClient(
                load: { nil },
                save: { _ in },
                remove: {},
            )
            $0.notificationCenterClient.notifications = { _, _ in
                AsyncStream { $0.finish() }
            }
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.fileManagerWindowClient.open = { _ in }
        }
        // store.exhaustivity = .off: unlock은 helper, Settings, external route reducers를 함께 통과함.
        store.exhaustivity = .off

        await store.send(.lifecycle(.accountAccess(.delegate(.unlocked(snapshot))))) {
            $0.lifecycle.accessGatePhase = .granted
        }
        await store.receive(\.externalFileRouter.receive)

        XCTAssertTrue(store.state.pendingExternalURLs.isEmpty)
        await store.finish()
    }

    private func makeSyncResult(status: String, hasAccess: Bool) -> SessionSyncResult {
        SessionSyncResult(
            sessionStatus: .unchanged,
            syncStatus: .complete,
            accessStatus: AccessStatusResponse(
                hasAccess: hasAccess,
                status: status,
                productKey: "test",
            ),
            deviceBindingOutcome: .bound,
            connectedDeviceAvailability: .available,
        )
    }
}
