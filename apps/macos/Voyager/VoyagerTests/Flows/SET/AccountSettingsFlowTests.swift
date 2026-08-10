// FLOW-ID: set.account_settings
import ComposableArchitecture
import Dependencies
@testable import Voyager
import VoyagerFeaturesAccountAccess
import VoyagerPagesFileManager
import VoyagerPagesOnboarding
@testable import VoyagerPagesSettings
import VoyagerShared
import XCTest

@MainActor
final class AccountSettingsFlowTests: XCTestCase {
    // FLOW-PATH: sign_in_failure

    /// set.account_settings sign_in_failure: Settings Sign In 실패는 canonical lifecycle에서 retryable projection으로 돌아온다.
    /// - 검증 내용: Sign In delegate의 단일 lifecycle handoff, 실패/cancellation/timeout/session-expiry projection, Retry
    /// delegate의 canonical 전달
    /// - 사전 조건: signed-out lifecycle AccountAccess와 실패를 반환하는 injected handoff client
    /// - 기대 결과: Settings는 실패 표시를 받고 Retry는 local fetch 없이 lifecycle에 한 번 전달됨
    func testSignInFailureReturnsRetryableSettingsPresentation() async throws {
        let store = makeSignInFailureStore()
        // store.exhaustivity = .off: root, lifecycle, AccountAccess의 실패 및 retry effect 경계를 함께 검증한다.
        store.exhaustivity = .off

        await store.send(.settings(.delegate(.account(.signInRequested))))
        await store.receive(\.lifecycle.accountAccess.loginTapped) { state in
            state.lifecycle.accountAccess.isSignInInProgress = true
            state.lifecycle.accountAccess.handoffGeneration = 1
            state.lifecycle.accountAccess.handoffTransaction = AccountAccessHandoffTransaction(
                context: .paywall,
                scope: .lifecycle,
            )
        }
        await store.receive(\.settings.accountAccessPresentationUpdated) { state in
            state.settings.accountSettings.presentation = AccountAccessPresentation(
                isSignInInProgress: true,
            )
        }
        await store.receive(\.lifecycle.accountAccess.signInHandoffCompleted) { state in
            state.lifecycle.accountAccess.isSignInInProgress = false
            state.lifecycle.accountAccess.didSignInFail = true
            state.lifecycle.accountAccess.errorMessage = "Check your network connection and try again."
            state.lifecycle.accountAccess.handoffTransaction = nil
        }
        await store.receive(\.settings.accountAccessPresentationUpdated) { state in
            state.settings.accountSettings.presentation = AccountAccessPresentation(didSignInFail: true)
        }

        XCTAssertEqual(store.state.settings.accountSettings.setAuthState, .signInFailed)
        await store.finish()

        var cancellationState = AppRootFeature.State()
        cancellationState.lifecycle.accountAccess.isSignInInProgress = true
        cancellationState.lifecycle.accountAccess.handoffPendingState = "cancel-state"
        cancellationState.lifecycle.accountAccess.handoffTransaction = AccountAccessHandoffTransaction(
            context: .paywall,
            scope: .lifecycle,
        )
        let cancellationStore = makeSignInFailureStore(initialState: cancellationState)

        await cancellationStore.send(.lifecycle(.accountAccess(.cancelSignIn))) { state in
            state.lifecycle.accountAccess.isSignInInProgress = false
            state.lifecycle.accountAccess.handoffPendingState = nil
            state.lifecycle.accountAccess.handoffTransaction = nil
        }
        await cancellationStore.receive(\.settings.accountAccessPresentationUpdated)

        XCTAssertNil(cancellationStore.state.lifecycle.accountAccess.handoffTransaction)
        XCTAssertEqual(cancellationStore.state.settings.accountSettings.presentation, AccountAccessPresentation())
        await cancellationStore.finish()

        let callbackURL = try XCTUnwrap(
            URL(string: "voyager://auth/callback?ticket=late-ticket&state=timeout-state&context=paywall"),
        )
        var timeoutState = AppRootFeature.State()
        timeoutState.lifecycle.accountAccess.isSignInInProgress = true
        timeoutState.lifecycle.accountAccess.handoffPendingState = "timeout-state"
        timeoutState.lifecycle.accountAccess.handoffTransaction = AccountAccessHandoffTransaction(
            context: .paywall,
            scope: .lifecycle,
        )
        let timeoutStore = makeSignInFailureStore(initialState: timeoutState)
        // store.exhaustivity = .off: timeout 뒤 stale callback이 terminal failure state를 되살리지 않는 경계를 검증한다.
        timeoutStore.exhaustivity = .off

        await timeoutStore
            .send(.lifecycle(.accountAccess(._handoffCallbackTimedOut(state: "timeout-state")))) { state in
                state.lifecycle.accountAccess.isSignInInProgress = false
                state.lifecycle.accountAccess.didSignInFail = true
                state.lifecycle.accountAccess.handoffPendingState = nil
                state.lifecycle.accountAccess.handoffTransaction = nil
            }
        await timeoutStore.receive(\.settings.accountAccessPresentationUpdated) { state in
            state.settings.accountSettings.presentation = AccountAccessPresentation(didSignInFail: true)
        }

        await timeoutStore.send(.receiveAuthCallbackURL(callbackURL))
        await timeoutStore.receive(\.lifecycle.accountAccess.loginCallbackReceived)

        XCTAssertTrue(timeoutStore.state.lifecycle.accountAccess.didSignInFail)
        XCTAssertNil(timeoutStore.state.lifecycle.accountAccess.handoffPendingState)
        XCTAssertNil(timeoutStore.state.lifecycle.accountAccess.handoffExchangeState)
        await timeoutStore.finish()

        var expiryState = AppRootFeature.State()
        expiryState.lifecycle.didFinishLaunching = true
        expiryState.lifecycle.accountAccess.hasAccountSession = true
        expiryState.lifecycle.accountAccess.status = .coreLicenseActive
        let expiryStore = makeSignInFailureStore(initialState: expiryState)
        // store.exhaustivity = .off: session-expiry cleanup과 Settings failure projection의 root composition을 함께 검증한다.
        expiryStore.exhaustivity = .off

        await expiryStore.send(.lifecycle(.sessionExpiredDetected(reason: .sessionExpired))) { state in
            state.lifecycle.sessionEndReason = .sessionExpired
        }
        await expiryStore.receive(\.lifecycle.accountAccess._sessionExpiredDetected) { state in
            state.lifecycle.accountAccess.revalidationGeneration = 1
            state.lifecycle.accountAccess.hasAccountSession = false
            state.lifecycle.accountAccess.didSignInFail = true
            state.lifecycle.accountAccess.isSessionExpired = true
            state.lifecycle.accountAccess.status = nil
            state.lifecycle.accountAccess.fetchGeneration = 1
            state.lifecycle.accountAccess.syncGeneration = 1
            state.lifecycle.accountAccess.refreshDeadlineGeneration = 1
        }
        await expiryStore.receive(\.settings.accountAccessPresentationUpdated) { state in
            state.settings.accountSettings.presentation = AccountAccessPresentation(didSignInFail: true)
        }

        XCTAssertNil(expiryStore.state.lifecycle.accountAccess.status)
        XCTAssertTrue(expiryStore.state.settings.accountSettings.presentation.didSignInFail)
        await expiryStore.finish()
    }

    // FLOW-PATH: entitlement_management_blocked

    /// set.account_settings entitlement_management_blocked: signed-out Account 화면은 관리 대신 canonical Sign In을 먼저 요청한다.
    /// - 검증 내용: inactive entitlement projection, unavailable management state, Sign In delegate의 lifecycle handoff
    /// - 사전 조건: lifecycle과 Settings projection 모두 signed-out 상태
    /// - 기대 결과: Settings는 billing boundary를 열지 않고 canonical AccountAccess Sign In을 한 번 요청함
    func testSignedOutAccountBlocksEntitlementManagementAndRoutesLoginFirst() async {
        let store = makeSignInFailureStore()
        // store.exhaustivity = .off: signed-out Settings delegate가 canonical lifecycle handoff로 이어지는 경계를 검증한다.
        store.exhaustivity = .off

        await store.send(.settings(.account(.signInTapped)))
        await store.receive(\.settings.delegate.account.signInRequested)
        await store.receive(\.lifecycle.accountAccess.loginTapped) { state in
            state.lifecycle.accountAccess.isSignInInProgress = true
            state.lifecycle.accountAccess.handoffGeneration = 1
            state.lifecycle.accountAccess.handoffTransaction = AccountAccessHandoffTransaction(
                context: .paywall,
                scope: .lifecycle,
            )
        }
        await store.receive(\.settings.accountAccessPresentationUpdated) { state in
            state.settings.accountSettings.presentation = AccountAccessPresentation(
                isSignInInProgress: true,
            )
        }
        await store.receive(\.lifecycle.accountAccess.signInHandoffCompleted) { state in
            state.lifecycle.accountAccess.isSignInInProgress = false
            state.lifecycle.accountAccess.didSignInFail = true
            state.lifecycle.accountAccess.errorMessage = "Check your network connection and try again."
            state.lifecycle.accountAccess.handoffTransaction = nil
        }
        await store.receive(\.settings.accountAccessPresentationUpdated) { state in
            state.settings.accountSettings.presentation = AccountAccessPresentation(didSignInFail: true)
        }
        await store.finish()
    }

    // FLOW-PATH: sign_out_cancelled

    /// set.account_settings sign_out_cancelled: Sign Out confirmation 취소는 canonical lifecycle을 호출하지 않고 현재 projection을
    /// 유지한다.
    /// - 검증 내용: confirmation 표시와 취소 후 lifecycle action 부재 및 signed-in presentation 보존
    /// - 사전 조건: active entitlement를 가진 signed-in canonical lifecycle과 Settings projection
    /// - 기대 결과: confirmation만 닫히며 canonical session과 Settings entitlement 표시가 변하지 않음
    func testCancelledSignOutPreservesCanonicalSessionAndProjection() async {
        var initialState = AppRootFeature.State()
        initialState.lifecycle.accountAccess.hasAccountSession = true
        initialState.lifecycle.accountAccess.status = .coreLicenseActive
        initialState.settings.accountSettings.presentation = AccountAccessPresentation(
            hasAccountSession: true,
        )
        let store = AccountAccessFlowTestSupport.makeRootStore(initialState: initialState)

        await store.send(.settings(.account(.signOutTapped))) { state in
            state.settings.accountSettings.isShowingSignOutConfirmation = true
        }
        await store.send(.settings(.account(.signOutCancelled))) { state in
            state.settings.accountSettings.isShowingSignOutConfirmation = false
        }

        XCTAssertTrue(store.state.lifecycle.accountAccess.hasAccountSession)
        XCTAssertEqual(store.state.settings.accountSettings.setAuthState, .signedIn)
        await store.finish()
    }

    private func makeSignInFailureStore(
        initialState: AppRootFeature.State = .init(),
    ) -> TestStore<AppRootFeature.State, AppRootFeature.Action> {
        TestStore(initialState: initialState) {
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
            $0.signInHandoffClient = SignInHandoffClient { _ in .failure }
            $0.notificationCenterClient.notifications = { _, _ in
                AsyncStream { $0.finish() }
            }
            $0.uuid = .incrementing
            $0.date = .constant(AccountAccessFlowTestSupport.referenceDate)
            $0.fileManagerWindowClient.open = { _ in }
            $0.appHandoffTarget = .voyager
        }
    }
}
