import ComposableArchitecture
import VoyagerFeaturesLicenseAuth
@testable import VoyagerPagesOnboarding
import XCTest

@MainActor
final class ONB002PresentAccessUnlockStepTests: XCTestCase {
    // MARK: - ONB-002-apply_access_unlock_result

    /// ONB-002-apply_access_unlock_result: access 결과가 complete로 적용되면 snapshot을 저장하고 unlock surface completion delegate를
    /// 방출한다.
    /// 온보딩 밖 unlock surface에서도 child access 결과가 성공으로 정규화될 때 동일한 access snapshot이 저장되고 상위 완료 흐름으로 전달되는지 검증합니다.
    /// - 검증 내용: `.unlockAccess(.delegate(.unlocked(snapshot)))` 처리 후 snapshot 저장, surface 창 닫기, 상위 delegate 전파가 모두
    /// 실행됩니다.
    /// - 사전 조건: unlock surface가 표시되어 있고 child access reducer가 active access snapshot을 delegate로 전달합니다.
    /// - 기대 결과: snapshot 저장 recorder와 window callback이 각각 한 번 호출되고 `.delegate(.unlocked(snapshot))`이 수신됩니다.
    func testCompleteAccessResultSavesSnapshotAndEmitsSurfaceDelegate() async {
        let recorder = LicenseAuthSnapshotRecorder()
        let closedWindow = LockIsolated(false)
        let completedSnapshots = LockIsolated<[LicenseAuthStatusSnapshot]>([])
        let snapshot = LicenseAuthStatusSnapshot(
            status: .coreLicenseActive,
            entitlements: [.coreLicense],
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )

        let store = TestStore(initialState: UnlockSurfaceFeature.State()) {
            UnlockSurfaceFeature()
        } withDependencies: {
            $0.licenseAuthStatusSnapshotClient = LicenseAuthSnapshotClient.recording(recorder: recorder)
            $0.unlockSurfaceWindowClient = UnlockSurfaceWindowClient(
                showWindow: {},
                closeWindow: { closedWindow.setValue(true) },
                openMainWindow: { _ in true },
                onUnlocked: { snapshot in completedSnapshots.withValue { $0.append(snapshot) } },
            )
        }

        await store.send(.unlockAccess(.delegate(.unlocked(snapshot))))
        await store.receive(\.delegate.unlocked)

        let savedSnapshots = await recorder.snapshot()
        XCTAssertEqual(savedSnapshots, [snapshot])
        XCTAssertTrue(closedWindow.value)
        XCTAssertEqual(completedSnapshots.value, [snapshot])

        await store.finish()
    }

    /// ONB-002-apply_access_unlock_result: access 조회가 error로 적용되면 snapshot을 저장하지 않고 completion delegate를 방출하지 않는다.
    /// 네트워크 실패가 access step을 complete로 승격하지 않는지 unlock surface 경계에서 검증합니다.
    /// - 검증 내용: child access failure action은 error 상태를 표시하되 snapshot save나 surface completion delegate를 실행하지 않습니다.
    /// - 사전 조건: unlock surface가 표시되어 있고 child access 조회가 `.networkFailure`로 실패합니다.
    /// - 기대 결과: child state는 retry 가능한 오류 상태가 되고 저장된 access snapshot은 없습니다.
    func testErrorAccessResultDoesNotSaveSnapshotOrEmitSurfaceDelegate() async {
        let recorder = LicenseAuthSnapshotRecorder()

        let store = TestStore(initialState: UnlockSurfaceFeature.State()) {
            UnlockSurfaceFeature()
        } withDependencies: {
            $0.licenseAuthStatusSnapshotClient = LicenseAuthSnapshotClient.recording(recorder: recorder)
            $0.unlockSurfaceWindowClient = UnlockSurfaceWindowClient(
                showWindow: {},
                closeWindow: {},
                openMainWindow: { _ in true },
                onUnlocked: { _ in },
            )
        }

        await store.send(.unlockAccess(.licenseAuthStatusResponse(
            generation: 0,
            result: .failure(.networkFailure),
        ))) { state in
            state.unlockAccess.status = .networkFailure
            state.unlockAccess.isComplete = false
            state.unlockAccess.errorMessage = "Network error. Please check your connection and try again."
        }

        let savedSnapshots = await recorder.snapshot()
        XCTAssertEqual(savedSnapshots, [])

        await store.finish()
    }

    // MARK: - ONB-002 UI CTA affordance tests

    /// ONB-002 UI: signed-out 상태에서 Login CTA만 활성화되고 Next/Submit/Retry/Refresh는 비활성화된다.
    /// 계정 세션이 없을 때 UI에 Login 버튼이 primary CTA로 표시되어야 함을 상태 affordance로 검증합니다.
    /// - 검증 내용: hasAccountSession=false일 때 canStartLogin만 true입니다.
    /// - 사전 조건: 세션 없음, 로그인 진행 중 아님, 로그인 실패 아님.
    /// - 기대 결과: canStartLogin=true, canRefreshAccess=false, canRetry=false.
    func testSignedOutStateShowsLoginCTADisablesAllOthers() {
        var state = UnlockLicenseAuthFeature.State()
        state.hasAccountSession = false

        XCTAssertTrue(state.canStartLogin, "signed-out 상태에서 canStartLogin이 true여야 함")
        XCTAssertFalse(state.canRefreshAccess, "signed-out 상태에서 canRefreshAccess가 false여야 함")
        XCTAssertFalse(state.canRetry, "signed-out 상태에서 canRetry가 false여야 함")
        XCTAssertEqual(state.onb002AuthAxis, .signedOut)
        XCTAssertEqual(state.onb002AccessStepState, .blocked)
    }

    /// ONB-002 UI: sign-in-failed 상태에서 Login CTA가 primary로 표시된다.
    /// 로그인 실패 후 재시도가 가능한지 상태 affordance로 검증합니다.
    /// - 검증 내용: didSignInFail=true일 때 canStartLogin=true입니다.
    /// - 사전 조건: hasAccountSession=false, didSignInFail=true.
    /// - 기대 결과: canStartLogin=true, canRefreshAccess=false.
    func testSignInFailedStateShowsLoginCTA() {
        var state = UnlockLicenseAuthFeature.State()
        state.hasAccountSession = false
        state.didSignInFail = true

        XCTAssertTrue(state.canStartLogin, "sign-in-failed 상태에서 canStartLogin이 true여야 함")
        XCTAssertFalse(state.canRefreshAccess, "sign-in-failed 상태에서 canRefreshAccess가 false여야 함")
        XCTAssertEqual(state.onb002AuthAxis, .signInFailed)
    }

    /// ONB-002 UI: sign-in 진행 중에는 모든 액션 버튼이 비활성화된다.
    /// 로그인 pending 상태에서 UI가 모든 CTA를 disable하는지 검증합니다.
    /// - 검증 내용: isSignInInProgress=true일 때 모든 affordance가 false입니다.
    /// - 사전 조건: isSignInInProgress=true.
    /// - 기대 결과: canStartLogin=false, canRefreshAccess=false.
    func testSignInInProgressDisablesAllActions() {
        var state = UnlockLicenseAuthFeature.State()
        state.isSignInInProgress = true

        XCTAssertFalse(state.canStartLogin, "sign-in 진행 중 canStartLogin이 false여야 함")
        XCTAssertFalse(state.canRefreshAccess, "sign-in 진행 중 canRefreshAccess가 false여야 함")
        XCTAssertFalse(state.canRetry, "sign-in 진행 중 canRetry가 false여야 함")
        XCTAssertEqual(state.onb002AuthAxis, .signInInProgress)
        XCTAssertEqual(state.onb002AccessStepState, .pending)
    }

    /// ONB-002 UI: signed-in blocked 상태에서 Refresh Access CTA가 활성화된다.
    /// 라이선스가 revoked/trialExpired 등 blocked 상태일 때 Refresh Access가 available한지 검증합니다.
    /// - 검증 내용: hasAccountSession=true, status=revoked → canRefreshAccess=true.
    /// - 사전 조건: 세션 있음, 라이선스 revoked.
    /// - 기대 결과: canRefreshAccess=true, canStartLogin=false, onb002AccessStepState=blocked.
    func testSignedInBlockedShowsRefreshAccessCTA() {
        var state = UnlockLicenseAuthFeature.State()
        state.hasAccountSession = true
        state.status = .revoked

        XCTAssertTrue(state.canRefreshAccess, "signed-in blocked 상태에서 canRefreshAccess가 true여야 함")
        XCTAssertFalse(state.canStartLogin, "signed-in 상태에서 canStartLogin이 false여야 함")
        XCTAssertFalse(state.canRetry, "blocked(비에러)에서 canRetry가 false여야 함")
        XCTAssertEqual(state.onb002AccessStepState, .blocked)
    }

    /// ONB-002 UI: signed-in error 상태에서 Refresh Access와 Retry CTA가 모두 활성화된다.
    /// 네트워크 오류 등 error 상태에서 refresh와 retry가 모두 가능한지 검증합니다.
    /// - 검증 내용: hasAccountSession=true, status=networkFailure → canRefreshAccess=true, canRetry=true.
    /// - 사전 조건: 세션 있음, 네트워크 실패.
    /// - 기대 결과: canRefreshAccess=true, canRetry=true, onb002AccessStepState=error.
    func testSignedInErrorShowsRefreshAndRetryCTA() {
        var state = UnlockLicenseAuthFeature.State()
        state.hasAccountSession = true
        state.status = .networkFailure

        XCTAssertTrue(state.canRefreshAccess, "signed-in error 상태에서 canRefreshAccess가 true여야 함")
        XCTAssertTrue(state.canRetry, "signed-in error 상태에서 canRetry가 true여야 함")
        XCTAssertFalse(state.canStartLogin, "signed-in 상태에서 canStartLogin이 false여야 함")
        XCTAssertEqual(state.onb002AccessStepState, .error)
    }

    /// ONB-002 UI: complete 상태에서 Next가 활성화된다.
    /// 라이선스가 active로 확인되면 onboarding 다음 단계로 진행 가능한지 검증합니다.
    /// - 검증 내용: status=coreLicenseActive, isComplete=true → onboarding canGoNext=true.
    /// - 사전 조건: 세션 있음, 라이선스 active, isComplete=true.
    /// - 기대 결과: isComplete=true, onb002AccessStepState=complete.
    func testCompleteStateEnablesNext() {
        var state = UnlockLicenseAuthFeature.State()
        state.hasAccountSession = true
        state.status = .coreLicenseActive
        state.isComplete = true

        XCTAssertTrue(state.isComplete)
        XCTAssertEqual(state.onb002AccessStepState, .complete)

        // Onboarding 수준에서 canGoNext 검증
        var onboardingState = OnboardingFeature.State()
        onboardingState.currentStep = .betaAccess
        onboardingState.betaAccess = state

        XCTAssertTrue(onboardingState.canGoNext, "complete 상태에서 canGoNext가 true여야 함")
    }

    /// ONB-002 UI: signed-in + empty input → Refresh Access는 활성.
    /// 입력 유무와 관계없이 Refresh Access가 가능해야 함을 검증합니다.
    /// - 검증 내용: hasAccountSession=true → canRefreshAccess=true.
    /// - 사전 조건: 세션 있음.
    /// - 기대 결과: canRefreshAccess=true.
    func testSignedInEnablesRefreshAccess() {
        var state = UnlockLicenseAuthFeature.State()
        state.hasAccountSession = true

        XCTAssertTrue(state.canRefreshAccess, "signed-in에서 canRefreshAccess가 true여야 함")
    }

    // MARK: - ONB-002 Login CTA action dispatch

    /// ONB-002-mock_sign_in_handoff UI: Login CTA가 signInHandoffClient를 통해 sign-in을 시작하고 진행 상태로 전환한다.
    /// onboarding scope를 통해 loginTapped가 전달될 때 signInHandoffClient를 사용하면 sign-in 진행 상태가 올바르게 반영되는지 검증한다.
    /// - 검증 내용: `.betaAccess(.loginTapped)` 전송 → isSignInInProgress=true, loginURLClient 미호출.
    /// - 사전 조건: signed-out 상태 (hasAccountSession=false), signInHandoffClient가 failure 반환.
    /// - 기대 결과: isSignInInProgress=true, loginURLClient.openLoginURL 미호출.
    func testLoginCTADispatchesLoginTappedThroughOnboardingScope() async {
        nonisolated(unsafe) var openURLCallCount = 0

        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.noOp
            $0.signInHandoffClient = SignInHandoffClient { .failure }
            $0.loginURLClient = LoginURLClient(openLoginURL: { _ in
                openURLCallCount += 1
            })
        }

        // betaAccess step으로 이동
        await store.send(.onAppear)
        await store.send(.nextTapped) { state in
            state.currentStep = .betaAccess
        }

        XCTAssertFalse(store.state.betaAccess.hasAccountSession)
        XCTAssertTrue(store.state.betaAccess.canStartLogin)

        // Login CTA dispatch → signInHandoffClient 사용
        await store.send(.betaAccess(.loginTapped)) { state in
            state.betaAccess.isSignInInProgress = true
            state.betaAccess.didSignInFail = false
        }

        XCTAssertTrue(store.state.betaAccess.isSignInInProgress)
        XCTAssertEqual(openURLCallCount, 0, "signInHandoffClient를 사용하면 loginURLClient를 호출하지 않아야 함")

        // signInHandoffClient가 .failure 반환 → signInHandoffCompleted(.failure)
        await store.receive(\.betaAccess.signInHandoffCompleted) { state in
            state.betaAccess.isSignInInProgress = false
            state.betaAccess.didSignInFail = true
        }

        await store.finish()
    }

    // MARK: - ONB-002 Refresh Access CTA action dispatch

    /// ONB-002 UI: Refresh Access CTA가 refreshAccessTapped 액션을 디스패치하면 access status fetch가 시작된다.
    /// onboarding scope를 통해 refreshAccessTapped가 전달될 때 fetch effect가 실행되는지 검증합니다.
    /// - 검증 내용: `.betaAccess(.refreshAccessTapped)` 전송 → fetchGeneration 증가, status fetch effect 실행.
    /// - 사전 조건: signed-in, status=revoked (blocked), canRefreshAccess=true.
    /// - 기대 결과: fetchGeneration이 1 증가하고 licenseAuthStatusResponse 수신.
    func testRefreshAccessCTADispatchesRefreshAccessTappedThroughOnboardingScope() async {
        let testDate = Date(timeIntervalSince1970: 1_700_000_000)
        let revokedResponse = LicenseAuthStatusResponse(status: .revoked, entitlements: [])

        var initialState = OnboardingFeature.State()
        initialState.currentStep = .betaAccess
        initialState.betaAccess.hasAccountSession = true
        initialState.betaAccess.status = .revoked
        initialState.betaAccess.errorMessage = "This license has been revoked."

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.noOp
            $0.licenseAuthClient = LicenseAuthClient(
                restoreSession: { nil },
                fetchAccessStatus: { revokedResponse },
                signOut: {},
            )
            $0.date = .constant(testDate)
        }

        XCTAssertTrue(store.state.betaAccess.canRefreshAccess)

        let expectedGeneration = store.state.betaAccess.fetchGeneration + 1
        await store.send(.betaAccess(.refreshAccessTapped)) { state in
            state.betaAccess.fetchGeneration = expectedGeneration
        }

        let expectedSnapshot = LicenseAuthStatusSnapshot(
            status: .revoked,
            entitlements: [],
            fetchedAt: testDate,
        )

        await store.receive(\.betaAccess.licenseAuthStatusResponse) { state in
            state.betaAccess.status = .revoked
            state.betaAccess.snapshot = expectedSnapshot
            state.betaAccess.isComplete = false
            state.betaAccess.errorMessage = "This license has been revoked."
            // OnboardingFeature redirects back to betaAccess on non-active
            state.currentStep = .betaAccess
        }

        await store.finish()
    }

    // MARK: - ONB-002 Onboarding trailing action integration

    /// ONB-002 UI: onboarding betaAccess step에서 signed-out 상태이면 Next/Activate/Retry가 모두 비활성화된다.
    /// 세션이 없을 때 trailing action이 Next를 disable하는지 onboarding 상태로 검증합니다.
    /// - 검증 내용: betaAccess signed-out → canGoNext=false.
    /// - 사전 조건: currentStep=betaAccess, hasAccountSession=false.
    /// - 기대 결과: canGoNext=false, showsRetry=false.
    func testOnboardingBetaAccessSignedOutCannotGoNext() {
        var state = OnboardingFeature.State()
        state.currentStep = .betaAccess

        XCTAssertFalse(state.canGoNext, "signed-out에서 canGoNext가 false여야 함")
        XCTAssertFalse(state.betaAccess.isComplete)
        XCTAssertFalse(state.betaAccess.showsRetry)
    }

    /// ONB-002 UI: onboarding betaAccess step에서 complete 상태이면 Next가 활성화된다.
    /// 라이선스가 active로 확인되면 trailing action이 Next를 enable하는지 검증합니다.
    /// - 검증 내용: betaAccess complete → canGoNext=true.
    /// - 사전 조건: currentStep=betaAccess, isComplete=true, status=active.
    /// - 기대 결과: canGoNext=true.
    func testOnboardingBetaAccessCompleteCanGoNext() {
        var state = OnboardingFeature.State()
        state.currentStep = .betaAccess
        state.betaAccess.hasAccountSession = true
        state.betaAccess.status = .coreLicenseActive
        state.betaAccess.isComplete = true

        XCTAssertTrue(state.canGoNext, "complete 상태에서 canGoNext가 true여야 함")
        XCTAssertTrue(state.betaAccess.isComplete)
    }

    /// ONB-002 UI: loginTapped는 직접 entitlement 상태를 변경하지 않고 sign-in 진행 상태만 설정한다.
    /// - 검증 내용: loginTapped 후 status/snapshot/isComplete가 변경되지 않음.
    /// - 사전 조건: signed-out 상태.
    /// - 기대 결과: isSignInInProgress=true, status/snapshot/isComplete는 초기 상태 유지.
    func testLoginTappedDoesNotMutateEntitlementState() async {
        let store = TestStore(initialState: UnlockLicenseAuthFeature.State()) {
            UnlockLicenseAuthFeature()
        } withDependencies: {
            $0.signInHandoffClient = SignInHandoffClient { .failure }
        }

        let originalStatus = store.state.status
        let originalSnapshot = store.state.snapshot
        let originalIsComplete = store.state.isComplete

        await store.send(.loginTapped) { state in
            state.isSignInInProgress = true
            state.didSignInFail = false
        }

        XCTAssertEqual(store.state.status, originalStatus)
        XCTAssertEqual(store.state.snapshot, originalSnapshot)
        XCTAssertEqual(store.state.isComplete, originalIsComplete)

        await store.receive(\.signInHandoffCompleted) { state in
            state.isSignInInProgress = false
            state.didSignInFail = true
        }

        await store.finish()
    }

    /// ONB-002 UI: refreshAccessTapped는 signed-in 상태에서만 동작한다.
    /// signed-out 상태에서 refreshAccessTapped가 no-op인지 검증합니다.
    /// - 검증 내용: signed-out에서 refreshAccessTapped → 상태 변경 없음.
    /// - 사전 조건: hasAccountSession=false.
    /// - 기대 결과: 상태 변화 없음.
    func testRefreshAccessTappedNoopWhenSignedOut() async {
        let store = TestStore(initialState: UnlockLicenseAuthFeature.State()) {
            UnlockLicenseAuthFeature()
        } withDependencies: {
            $0.licenseAuthClient = LicenseAuthClient(
                restoreSession: { nil },
                fetchAccessStatus: { StateMutation.activeAccessResponse },
                signOut: {},
            )
        }

        XCTAssertFalse(store.state.canRefreshAccess)

        // no-op: 상태 변화 없음
        await store.send(.refreshAccessTapped)

        await store.finish()
    }

    // MARK: - ONB-002-mock_sign_in_handoff

    /// ONB-002-mock_sign_in_handoff: Login CTA가 mock handoff 진행 중에 isSignInInProgress와 pending 상태를 표시한다.
    /// onboarding scope를 통해 loginTapped가 전달될 때 signInHandoffClient를 사용하면 sign-in 진행 상태가 올바르게 반영되는지 검증한다.
    /// - 검증 내용: `.betaAccess(.loginTapped)` 전송 → isSignInInProgress=true, onb002AuthAxis=signInInProgress,
    /// onb002AccessStepState=pending
    /// - 사전 조건: signed-out 상태 (hasAccountSession=false), signInHandoffClient가 지연 후 success 반환
    /// - 기대 결과: isSignInInProgress=true, onb002AuthAxis==.signInInProgress, onb002AccessStepState==.pending
    func testLoginCTAShowsPendingDuringMockSignInHandoff() async {
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.noOp
            $0.signInHandoffClient = SignInHandoffClient {
                // swiftlint:disable:next force_unwrapping
                .success(callbackURL: URL(string: "voyager://auth/callback")!)
            }
            $0.loginURLClient = LoginURLClient(openLoginURL: { _ in })
        }

        // betaAccess step으로 이동
        await store.send(.onAppear)
        await store.send(.nextTapped) { state in
            state.currentStep = .betaAccess
        }

        XCTAssertFalse(store.state.betaAccess.hasAccountSession)
        XCTAssertTrue(store.state.betaAccess.canStartLogin)

        // Login CTA dispatch → mock handoff 시작
        await store.send(.betaAccess(.loginTapped)) { state in
            state.betaAccess.isSignInInProgress = true
            state.betaAccess.didSignInFail = false
        }

        // mock handoff 진행 중 상태 검증
        XCTAssertTrue(store.state.betaAccess.isSignInInProgress)
        XCTAssertEqual(store.state.betaAccess.onb002AuthAxis, .signInInProgress)
        XCTAssertEqual(store.state.betaAccess.onb002AccessStepState, .pending)

        // signInHandoffClient가 success 반환 → callback chain
        await store.receive(\.betaAccess.signInHandoffCompleted)
        await store.receive(\.betaAccess.loginCallbackReceived)
        await store.receive(\.betaAccess._loginSessionRestored) { state in
            state.betaAccess.isSignInInProgress = false
            state.betaAccess.didSignInFail = true
        }

        await store.finish()
    }
}
