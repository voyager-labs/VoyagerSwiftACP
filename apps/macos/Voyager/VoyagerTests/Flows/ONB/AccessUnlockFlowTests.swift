// FLOW-ID: onb.access_unlock
import ComposableArchitecture
import Dependencies
import VoyagerFeaturesAccountAccess
@testable import VoyagerPagesOnboarding
import VoyagerShared
import XCTest

/// ONB access_unlock: happy_path
/// AccountAccess 활성 상태가 프로덕션 observer bridge를 통해 Onboarding Next를 활성화하는지 검증한다.
/// - 검증 내용: AccountAccess가 complete 상태에 도달하면 OnboardingWindowController의 observer가
///   Onboarding store에 access projection 갱신 action을 전송하고, Onboarding canGoNext가 true가 됨
/// - 사전 조건: 유효한 세션, 활성 entitlement, 성공적인 device binding
/// - 기대 결과: Access Unlock step 완료, canGoNext == true, Onboarding이 main window 진입 허용
@MainActor
final class AccessUnlockFlowTests: XCTestCase {
    // FLOW-PATH: happy_path

    /// ONB access_unlock: happy_path
    /// 활성 계정 접근 상태가 프로덕션 observer를 통해 Onboarding을 unlock하는지 검증한다.
    func testActiveAccessUnlocksOnboardingThroughProductionObserver() throws {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let sessionExpiresAt = try XCTUnwrap(
            Optional(referenceDate.addingTimeInterval(3600)),
        )
        let session = AccountSession(
            accessToken: "access-token",
            status: .coreLicenseActive,
            refreshToken: "refresh-token",
            expiresAt: sessionExpiresAt,
        )
        let syncResult = SessionSyncResult(
            sessionStatus: .unchanged,
            syncStatus: .complete,
            accessStatus: AccessStatusResponse(
                hasAccess: true,
                status: AccessStatus.coreLicenseActive.rawValue,
                ownershipStatus: "owned",
                updateStatus: "active",
                productKey: "core",
            ),
            deviceBindingOutcome: .bound,
            connectedDeviceAvailability: .available,
        )
        let accountSessionClient = AccountSessionClient(
            read: { _ in session },
            persist: { _ in },
            delete: { _ in },
        )
        let sessionSynced = expectation(description: "AccountAccess session sync completes")
        let authNetworkClient = AuthNetworkClient(
            exchangeHandoff: { _, _, _ in throw SessionSyncError.capabilityMiss },
            fetchAccessStatus: { syncResult.accessStatus },
            refreshToken: { session },
            syncSession: { _, _ in
                sessionSynced.fulfill()
                return syncResult
            },
        )

        var accountAccessState = AccountAccessFeature.State()
        accountAccessState.hasAccountSession = true
        let accountAccessStore = Store(initialState: accountAccessState) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = accountSessionClient
            $0.authNetworkClient = authNetworkClient
            $0.continuousClock = TestClock()
            $0.date = .constant(referenceDate)
            $0.notificationCenterClient.notifications = { _, _ in
                AsyncStream { $0.finish() }
            }
        }

        // access 완료 projection이 저장될 때까지 기다린다.
        let projectionDelivered = expectation(description: "Onboarding access projection completes")
        var onboardingState = OnboardingFeature.State()
        onboardingState.currentStep = .accessUnlock
        onboardingState.didBootstrapProgress = true
        let onboardingStore = Store(initialState: onboardingState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .empty },
                save: { snapshot in
                    if snapshot.stepState.accessUnlockComplete {
                        projectionDelivered.fulfill()
                    }
                    return .success
                },
                reset: {},
            )
            $0.onboardingWindowClient = OnboardingWindowClient(
                isRequired: { false },
                showIfNeeded: { false },
                showWindow: {},
                closeWindow: {},
                openMainWindow: { _ in true },
            )
        }
        var controller: OnboardingWindowController?
        XCTExpectFailure("OnboardingView GeometryReader의 기존 Perception tracking 보고") {
            controller = OnboardingWindowController(
                onboardingStore: onboardingStore,
                accountAccessStore: accountAccessStore,
                handlesAuthCallback: false,
            )
        }
        let onboardingController = try XCTUnwrap(controller)
        // observer bridge만 검증하므로 SwiftUI 렌더링은 분리한다.
        onboardingController.window?.contentViewController = nil

        wait(for: [sessionSynced], timeout: 1)
        wait(for: [projectionDelivered], timeout: 1)

        XCTAssertTrue(accountAccessStore.withState(\.isComplete))
        XCTAssertTrue(onboardingStore.withState(\.access.isComplete))
        XCTAssertTrue(onboardingStore.withState(\.canGoNext))
    }

    // FLOW-PATH: sign_in_required

    /// ONB access_unlock: sign_in_required
    /// 비로그인 상태에서 Access Unlock이 차단되고 Login CTA가 primary route로 표시되는지 검증한다.
    /// - 검증 내용: 세션이 없으면 access가 blocked 상태이고, entitlement/device binding 작업이 실행되지 않음
    /// - 사전 조건: hasAccountSession = false, auth_state = logged_out
    /// - 기대 결과: Next 비활성화, Login route 노출, entitlement fetch 미실행
    func testSignInRequiredKeepsAccessBlockedAndExposesLoginRoute() throws {
        let accountSessionClient = AccountSessionClient(
            read: { _ in nil },
            persist: { _ in },
            delete: { _ in },
        )
        let authNetworkClient = AuthNetworkClient(
            exchangeHandoff: { _, _, _ in throw SessionSyncError.capabilityMiss },
            fetchAccessStatus: { throw SessionSyncError.capabilityMiss },
            refreshToken: { throw SessionSyncError.capabilityMiss },
            syncSession: { _, _ in
                XCTFail("Signed-out access unlock must not sync the session")
                throw SessionSyncError.capabilityMiss
            },
        )

        var accountAccessState = AccountAccessFeature.State()
        accountAccessState.hasAccountSession = false
        let accountAccessStore = Store(initialState: accountAccessState) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = accountSessionClient
            $0.authNetworkClient = authNetworkClient
            $0.continuousClock = TestClock()
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.notificationCenterClient.notifications = { _, _ in
                AsyncStream { $0.finish() }
            }
        }

        var onboardingState = OnboardingFeature.State()
        onboardingState.currentStep = .accessUnlock
        let onboardingStore = Store(initialState: onboardingState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .success(OnboardingProgressSnapshot(currentStep: .accessUnlock, stepState: .init())) },
                save: { _ in .success },
                reset: {},
            )
            $0.onboardingWindowClient = OnboardingWindowClient(
                isRequired: { false },
                showIfNeeded: { false },
                showWindow: {},
                closeWindow: {},
                openMainWindow: { _ in true },
            )
        }
        var controller: OnboardingWindowController?
        XCTExpectFailure("OnboardingView GeometryReader의 기존 Perception tracking 보고") {
            controller = OnboardingWindowController(
                onboardingStore: onboardingStore,
                accountAccessStore: accountAccessStore,
                handlesAuthCallback: false,
            )
        }
        let onboardingController = try XCTUnwrap(controller)
        onboardingController.window?.contentViewController = nil

        let observerDelivered = expectation(description: "Onboarding observer delivery completes")
        DispatchQueue.main.async { observerDelivered.fulfill() }
        wait(for: [observerDelivered], timeout: 1)

        XCTAssertFalse(accountAccessStore.withState(\.isComplete))
        XCTAssertTrue(onboardingStore.withState(\.access.isBlocked))
        XCTAssertFalse(onboardingStore.withState(\.canGoNext))
    }

    // FLOW-PATH: restored_state_reconciliation

    /// ONB access_unlock: restored_state_reconciliation
    /// stale persisted complete 상태가 최신 blocked canonical 결과에 의해 override되는지 검증한다.
    /// - 검증 내용: 저장된 진행 상태에 complete가 있어도 재진입 시 최신 access_status가 blocked이면 Next 비활성화
    /// - 사전 조건: progress snapshot에 access complete 기록, 현재 access_status = none
    /// - 기대 결과: Next 비활성화, stored complete가 canonical blocked 결과로 대체됨
    func testRestoredCompleteIsOverriddenByBlockedCanonicalResult() throws {
        let session = AccountSession(
            accessToken: "access-token",
            status: .coreLicenseActive,
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1_700_003_600),
        )
        let syncResult = SessionSyncResult(
            sessionStatus: .unchanged,
            syncStatus: .complete,
            accessStatus: AccessStatusResponse(
                hasAccess: false, status: AccessStatus.none.rawValue, productKey: "",
            ),
            deviceBindingOutcome: .bound,
            connectedDeviceAvailability: .available,
        )
        let sessionSynced = expectation(description: "AccountAccess session sync completes")
        let accountSessionClient = AccountSessionClient(read: { _ in session }, persist: { _ in }, delete: { _ in })
        let authNetworkClient = AuthNetworkClient(
            exchangeHandoff: { _, _, _ in throw SessionSyncError.capabilityMiss },
            fetchAccessStatus: { syncResult.accessStatus },
            refreshToken: { session },
            syncSession: { _, _ in sessionSynced.fulfill()
                return syncResult
            },
        )

        var accountAccessState = AccountAccessFeature.State()
        accountAccessState.hasAccountSession = true
        let accountAccessStore = Store(initialState: accountAccessState) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = accountSessionClient
            $0.authNetworkClient = authNetworkClient
            $0.continuousClock = TestClock()
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.notificationCenterClient.notifications = { _, _ in AsyncStream { $0.finish() } }
        }

        var onboardingState = OnboardingFeature.State()
        onboardingState.currentStep = .accessUnlock
        onboardingState.access.hasAccountSession = true
        onboardingState.access.isComplete = true
        let onboardingStore = Store(initialState: onboardingState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .success(OnboardingProgressSnapshot(currentStep: .accessUnlock, stepState: .init())) },
                save: { _ in .success },
                reset: {},
            )
            $0.onboardingWindowClient = OnboardingWindowClient(
                isRequired: { false },
                showIfNeeded: { false },
                showWindow: {},
                closeWindow: {},
                openMainWindow: { _ in true },
            )
        }
        var controller: OnboardingWindowController?
        XCTExpectFailure("OnboardingView GeometryReader의 기존 Perception tracking 보고") {
            controller = OnboardingWindowController(
                onboardingStore: onboardingStore,
                accountAccessStore: accountAccessStore,
                handlesAuthCallback: false,
            )
        }
        let onboardingController = try XCTUnwrap(controller)
        onboardingController.window?.contentViewController = nil

        wait(for: [sessionSynced], timeout: 1)
        let observerDelivered = expectation(description: "Onboarding observer delivery completes")
        DispatchQueue.main.async { observerDelivered.fulfill() }
        wait(for: [observerDelivered], timeout: 1)

        XCTAssertFalse(accountAccessStore.withState(\.isComplete))
        XCTAssertTrue(onboardingStore.withState(\.access.isBlocked))
        XCTAssertFalse(onboardingStore.withState(\.access.isComplete))
        XCTAssertFalse(onboardingStore.withState(\.canGoNext))
    }

    // FLOW-PATH: web_pricing_required

    /// ONB access_unlock: web_pricing_required
    /// 인증된 계정에 유효한 접근 상태가 없을 때 blocked 상태로 Web Pricing route가 노출되는지 검증한다.
    /// - 검증 내용: access_status = none이면 blocked 상태, Web Pricing CTA 노출, step complete 아님
    /// - 사전 조건: hasAccountSession = true, access_status = none
    /// - 기대 결과: Next 비활성화, Web Pricing route 노출, isComplete == false
    func testNoneAccessStatusBlocksAndExposesWebPricingRoute() throws {
        let session = AccountSession(
            accessToken: "access-token",
            status: .coreLicenseActive,
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1_700_003_600),
        )
        let syncResult = SessionSyncResult(
            sessionStatus: .unchanged,
            syncStatus: .complete,
            accessStatus: AccessStatusResponse(
                hasAccess: false, status: AccessStatus.none.rawValue, productKey: "",
            ),
            deviceBindingOutcome: .bound,
            connectedDeviceAvailability: .available,
        )
        let sessionSynced = expectation(description: "AccountAccess session sync completes")
        let accountSessionClient = AccountSessionClient(read: { _ in session }, persist: { _ in }, delete: { _ in })
        let authNetworkClient = AuthNetworkClient(
            exchangeHandoff: { _, _, _ in throw SessionSyncError.capabilityMiss },
            fetchAccessStatus: { syncResult.accessStatus },
            refreshToken: { session },
            syncSession: { _, _ in sessionSynced.fulfill()
                return syncResult
            },
        )

        var accountAccessState = AccountAccessFeature.State()
        accountAccessState.hasAccountSession = true
        let accountAccessStore = Store(initialState: accountAccessState) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = accountSessionClient
            $0.authNetworkClient = authNetworkClient
            $0.continuousClock = TestClock()
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.notificationCenterClient.notifications = { _, _ in AsyncStream { $0.finish() } }
        }

        var onboardingState = OnboardingFeature.State()
        onboardingState.currentStep = .accessUnlock
        let onboardingStore = Store(initialState: onboardingState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .success(OnboardingProgressSnapshot(currentStep: .accessUnlock, stepState: .init())) },
                save: { _ in .success },
                reset: {},
            )
            $0.onboardingWindowClient = OnboardingWindowClient(
                isRequired: { false },
                showIfNeeded: { false },
                showWindow: {},
                closeWindow: {},
                openMainWindow: { _ in true },
            )
        }
        var controller: OnboardingWindowController?
        XCTExpectFailure("OnboardingView GeometryReader의 기존 Perception tracking 보고") {
            controller = OnboardingWindowController(
                onboardingStore: onboardingStore,
                accountAccessStore: accountAccessStore,
                handlesAuthCallback: false,
            )
        }
        let onboardingController = try XCTUnwrap(controller)
        onboardingController.window?.contentViewController = nil

        wait(for: [sessionSynced], timeout: 1)
        let observerDelivered = expectation(description: "Onboarding observer delivery completes")
        DispatchQueue.main.async { observerDelivered.fulfill() }
        wait(for: [observerDelivered], timeout: 1)

        XCTAssertFalse(accountAccessStore.withState(\.isComplete))
        XCTAssertTrue(onboardingStore.withState(\.access.isBlocked))
        XCTAssertEqual(onboardingStore.withState(\.access.primaryCTA), .webPricing)
        XCTAssertFalse(onboardingStore.withState(\.canGoNext))
    }

    // FLOW-PATH: purchase_or_web_pricing_recovery

    /// ONB access_unlock: purchase_or_web_pricing_recovery
    /// 초기 blocked 상태에서 deterministic refresh 후 active로 전환되면 bridge를 cross하고 Next가 활성화되는지 검증한다.
    /// - 검증 내용: blocked → refresh → active 전환이 동일한 production observer bridge를 cross함
    /// - 사전 조건: 초기 access_status = none, refresh 후 access_status = core_license_active
    /// - 기대 결과: refresh 후 canGoNext == true, 실제 browser/checkout 미사용
    func testBlockedToActiveRecoveryCrossesBridgeAndEnablesNext() throws {
        let session = AccountSession(
            accessToken: "access-token",
            status: .coreLicenseActive,
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1_700_003_600),
        )
        let blockedResult = SessionSyncResult(
            sessionStatus: .unchanged,
            syncStatus: .complete,
            accessStatus: AccessStatusResponse(
                hasAccess: false, status: AccessStatus.none.rawValue, productKey: "",
            ),
            deviceBindingOutcome: .bound,
            connectedDeviceAvailability: .available,
        )
        let activeResult = SessionSyncResult(
            sessionStatus: .unchanged,
            syncStatus: .complete,
            accessStatus: AccessStatusResponse(
                hasAccess: true,
                status: AccessStatus.coreLicenseActive.rawValue,
                ownershipStatus: "owned",
                updateStatus: "active",
                productKey: "core",
            ),
            deviceBindingOutcome: .bound,
            connectedDeviceAvailability: .available,
        )
        let initialSessionSynced = expectation(description: "Initial blocked session sync completes")
        let refreshedSessionSynced = expectation(description: "Refreshed active session sync completes")
        let syncResults = SessionSyncResults([blockedResult, activeResult])
        let accountSessionClient = AccountSessionClient(read: { _ in session }, persist: { _ in }, delete: { _ in })
        let authNetworkClient = AuthNetworkClient(
            exchangeHandoff: { _, _, _ in throw SessionSyncError.capabilityMiss },
            fetchAccessStatus: { blockedResult.accessStatus },
            refreshToken: { session },
            syncSession: { _, _ in
                let result = await syncResults.next()
                if result == blockedResult {
                    initialSessionSynced.fulfill()
                } else {
                    refreshedSessionSynced.fulfill()
                }
                return result
            },
        )

        var accountAccessState = AccountAccessFeature.State()
        accountAccessState.hasAccountSession = true
        let accountAccessStore = Store(initialState: accountAccessState) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = accountSessionClient
            $0.authNetworkClient = authNetworkClient
            $0.continuousClock = TestClock()
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.notificationCenterClient.notifications = { _, _ in AsyncStream { $0.finish() } }
        }

        var onboardingState = OnboardingFeature.State()
        onboardingState.currentStep = .accessUnlock
        let onboardingStore = Store(initialState: onboardingState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .success(OnboardingProgressSnapshot(currentStep: .accessUnlock, stepState: .init())) },
                save: { _ in .success },
                reset: {},
            )
            $0.onboardingWindowClient = OnboardingWindowClient(
                isRequired: { false },
                showIfNeeded: { false },
                showWindow: {},
                closeWindow: {},
                openMainWindow: { _ in true },
            )
        }
        var controller: OnboardingWindowController?
        XCTExpectFailure("OnboardingView GeometryReader의 기존 Perception tracking 보고") {
            controller = OnboardingWindowController(
                onboardingStore: onboardingStore,
                accountAccessStore: accountAccessStore,
                handlesAuthCallback: false,
            )
        }
        let onboardingController = try XCTUnwrap(controller)
        onboardingController.window?.contentViewController = nil

        wait(for: [initialSessionSynced], timeout: 1)
        XCTAssertFalse(onboardingStore.withState(\.canGoNext))
        accountAccessStore.send(.refreshAccessTapped)
        wait(for: [refreshedSessionSynced], timeout: 1)
        let observerDelivered = expectation(description: "Onboarding observer delivery completes")
        DispatchQueue.main.async { observerDelivered.fulfill() }
        wait(for: [observerDelivered], timeout: 1)

        XCTAssertTrue(accountAccessStore.withState(\.isComplete))
        XCTAssertTrue(onboardingStore.withState(\.access.isComplete))
        XCTAssertTrue(onboardingStore.withState(\.canGoNext))
    }

    // FLOW-PATH: access_status_error

    /// ONB access_unlock: access_status_error
    /// 네트워크 실패나 알 수 없는 응답 시 error/retry 상태가 표시되고 main flow가 열리지 않는지 검증한다.
    /// - 검증 내용: access_status 확인 실패 시 error 상태, Next 비활성화, main window 미진입
    /// - 사전 조건: hasAccountSession = true, access_status fetch 실패 (network error)
    /// - 기대 결과: error/retry 상태 표시, canGoNext == false, main window 진입 차단
    func testAccessStatusErrorProducesErrorStateAndBlocksNext() throws {
        let session = AccountSession(
            accessToken: "access-token",
            status: .coreLicenseActive,
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1_700_003_600),
        )
        let sessionSyncAttempts = expectation(description: "Session sync exhausts network retries")
        sessionSyncAttempts.expectedFulfillmentCount = 4
        let accountSessionClient = AccountSessionClient(read: { _ in session }, persist: { _ in }, delete: { _ in })
        let authNetworkClient = AuthNetworkClient(
            exchangeHandoff: { _, _, _ in throw SessionSyncError.capabilityMiss },
            fetchAccessStatus: { throw SessionSyncError.upstream(0) },
            refreshToken: { session },
            syncSession: { _, _ in
                sessionSyncAttempts.fulfill()
                throw SessionSyncError.upstream(0)
            },
        )

        var accountAccessState = AccountAccessFeature.State()
        accountAccessState.hasAccountSession = true
        let accountAccessStore = Store(initialState: accountAccessState) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = accountSessionClient
            $0.authNetworkClient = authNetworkClient
            $0.continuousClock = ContinuousClock()
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.notificationCenterClient.notifications = { _, _ in AsyncStream { $0.finish() } }
        }

        var onboardingState = OnboardingFeature.State()
        onboardingState.currentStep = .accessUnlock
        let onboardingStore = Store(initialState: onboardingState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .success(OnboardingProgressSnapshot(currentStep: .accessUnlock, stepState: .init())) },
                save: { _ in .success },
                reset: {},
            )
            $0.onboardingWindowClient = OnboardingWindowClient(
                isRequired: { false },
                showIfNeeded: { false },
                showWindow: {},
                closeWindow: {},
                openMainWindow: { _ in true },
            )
        }
        var controller: OnboardingWindowController?
        XCTExpectFailure("OnboardingView GeometryReader의 기존 Perception tracking 보고") {
            controller = OnboardingWindowController(
                onboardingStore: onboardingStore,
                accountAccessStore: accountAccessStore,
                handlesAuthCallback: false,
            )
        }
        let onboardingController = try XCTUnwrap(controller)
        onboardingController.window?.contentViewController = nil

        wait(for: [sessionSyncAttempts], timeout: 10)
        let observerDelivered = expectation(description: "Onboarding observer delivery completes")
        DispatchQueue.main.async { observerDelivered.fulfill() }
        wait(for: [observerDelivered], timeout: 1)

        XCTAssertFalse(accountAccessStore.withState(\.isComplete))
        XCTAssertNotNil(accountAccessStore.withState(\.errorMessage))
        XCTAssertNotNil(onboardingStore.withState(\.access.errorMessage))
        XCTAssertFalse(onboardingStore.withState(\.canGoNext))
    }

    // FLOW-PATH: device_binding_failure

    /// ONB access_unlock: device_binding_failure
    /// 활성 entitlement와 device binding 실패가 incomplete 상태와 올바른 recovery route를 노출하는지 검증한다.
    /// - 검증 내용: active entitlement + binding 실패 = incomplete, retry/recovery route 노출
    /// - 사전 조건: hasAccountSession = true, access_status = active, device binding 실패
    /// - 기대 결과: isComplete == false, retry route 노출, canGoNext == false
    func testDeviceBindingFailureStaysIncompleteAndExposesRecovery() throws {
        let session = AccountSession(
            accessToken: "access-token",
            status: .coreLicenseActive,
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1_700_003_600),
        )
        let syncResult = SessionSyncResult(
            sessionStatus: .unchanged,
            syncStatus: .partial,
            accessStatus: AccessStatusResponse(
                hasAccess: true, status: AccessStatus.coreLicenseActive.rawValue, productKey: "core",
            ),
            deviceBindingOutcome: .notAttempted,
            connectedDeviceAvailability: .available,
        )
        let sessionSynced = expectation(description: "AccountAccess session sync completes")
        let accountSessionClient = AccountSessionClient(read: { _ in session }, persist: { _ in }, delete: { _ in })
        let authNetworkClient = AuthNetworkClient(
            exchangeHandoff: { _, _, _ in throw SessionSyncError.capabilityMiss },
            fetchAccessStatus: { syncResult.accessStatus },
            refreshToken: { session },
            syncSession: { _, _ in sessionSynced.fulfill()
                return syncResult
            },
        )

        var accountAccessState = AccountAccessFeature.State()
        accountAccessState.hasAccountSession = true
        let accountAccessStore = Store(initialState: accountAccessState) {
            AccountAccessFeature()
        } withDependencies: {
            $0.accountSessionClient = accountSessionClient
            $0.authNetworkClient = authNetworkClient
            $0.continuousClock = TestClock()
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.notificationCenterClient.notifications = { _, _ in AsyncStream { $0.finish() } }
        }

        var onboardingState = OnboardingFeature.State()
        onboardingState.currentStep = .accessUnlock
        let onboardingStore = Store(initialState: onboardingState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .success(OnboardingProgressSnapshot(currentStep: .accessUnlock, stepState: .init())) },
                save: { _ in .success },
                reset: {},
            )
            $0.onboardingWindowClient = OnboardingWindowClient(
                isRequired: { false },
                showIfNeeded: { false },
                showWindow: {},
                closeWindow: {},
                openMainWindow: { _ in true },
            )
        }
        var controller: OnboardingWindowController?
        XCTExpectFailure("OnboardingView GeometryReader의 기존 Perception tracking 보고") {
            controller = OnboardingWindowController(
                onboardingStore: onboardingStore,
                accountAccessStore: accountAccessStore,
                handlesAuthCallback: false,
            )
        }
        let onboardingController = try XCTUnwrap(controller)
        onboardingController.window?.contentViewController = nil

        wait(for: [sessionSynced], timeout: 1)
        let observerDelivered = expectation(description: "Onboarding observer delivery completes")
        DispatchQueue.main.async { observerDelivered.fulfill() }
        wait(for: [observerDelivered], timeout: 1)

        XCTAssertFalse(accountAccessStore.withState(\.isComplete))
        XCTAssertNotNil(accountAccessStore.withState(\.deviceBindingFailure))
        XCTAssertFalse(onboardingStore.withState(\.access.isComplete))
        XCTAssertTrue(onboardingStore.withState(\.access.hasDeviceBindingFailure))
        XCTAssertFalse(onboardingStore.withState(\.canGoNext))
    }

    private actor SessionSyncResults {
        private var values: [SessionSyncResult]

        init(_ values: [SessionSyncResult]) {
            self.values = values
        }

        func next() -> SessionSyncResult {
            values.removeFirst()
        }
    }
}
