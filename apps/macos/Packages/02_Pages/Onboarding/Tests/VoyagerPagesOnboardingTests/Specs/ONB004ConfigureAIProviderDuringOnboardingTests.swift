import ComposableArchitecture
import VoyagerEntitiesAi
import VoyagerFeaturesAiProviderConnection
@testable import VoyagerPagesOnboarding
import XCTest

@MainActor
final class ONB004ConfigureAIProviderDuringOnboardingTests: XCTestCase {
    // MARK: - ONB-004-show_onboarding_ai_provider_setup

    /// ONB-004-show_onboarding_ai_provider_setup: provider catalog bootstrap이 row 순서와 연결 상태를 표시한다.
    /// 사용자가 AI Provider Setup 단계에 진입했을 때 지원 provider 목록과 기존 연결 상태가 onboarding surface에 반영되는지 검증한다.
    /// - 검증 내용: `.onAppear` bootstrap effect가 catalog row 상태를 갱신하고 verification 완료 후 step을 complete로 해석한다.
    /// - 사전 조건: OpenAI는 저장된 API key credential이 있고 Anthropic은 disconnected snapshot이며 ChatGPT Codex 기록은 없다.
    /// - 기대 결과: catalog row 순서가 유지되고 OpenAI 연결 확인 후 `providerConnected/complete` 상태가 된다.
    func testShowProviderCatalogRowsAfterBootstrapLoadsConnectionStatuses() async {
        let file = AIConnectionsFile.fixture(
            records: [
                .openai: .apiKeyRecord(provider: .openai, status: .connected),
                .anthropic: .apiKeyRecord(provider: .anthropic, status: .disconnected),
            ],
        )
        let store = TestStore(initialState: AiProviderSetupState()) {
            AiProviderSetupFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { file }
            $0.aiConnectionsFileClient.save = { .success($0) }
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .chatgptCodex]?.connectionState = .notVerified
            state.rows[id: .openai]?.connectionState = .checkingStatus
            state.rows[id: .anthropic]?.connectionState = .disconnected
            state.status = .pending
        }

        XCTAssertEqual(store.state.rows.map(\.provider), [.chatgptCodex, .openai, .anthropic])

        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .openai]?.connectionState = .connected
            state.rows[id: .openai]?.statusReason = .none
            state.choice = .providerConnected
            state.status = .complete
        }

        await store.finish()
    }

    /// ONB-004-show_onboarding_ai_provider_setup: 연결된 provider가 없으면 step 진행을 차단한다.
    /// 사용자가 연결된 AI provider 없이 setup 단계에 도달했을 때 Connect 또는 Set up later 선택 전까지 Next가 막히는지 검증한다.
    /// - 검증 내용: 빈 connection file bootstrap 결과가 blocked 상태와 disabled message를 유지한다.
    /// - 사전 조건: AI connection file에 provider record가 없다.
    /// - 기대 결과: 모든 row가 `notVerified`이고 `choice=.none`, `status=.blocked`, `isComplete=false` 상태다.
    func testShowNoConnectedProviderKeepsStepBlocked() async {
        let store = TestStore(initialState: AiProviderSetupState()) {
            AiProviderSetupFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { .empty(updatedAtMs: 1) }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .chatgptCodex]?.connectionState = .notVerified
            state.rows[id: .openai]?.connectionState = .notVerified
            state.rows[id: .anthropic]?.connectionState = .notVerified
        }

        XCTAssertEqual(store.state.choice, .none)
        XCTAssertEqual(store.state.status, .blocked)
        XCTAssertFalse(store.state.isComplete)
        XCTAssertEqual(
            store.state.nextDisabledMessage,
            "Connect a provider or choose Set up later to continue.",
        )

        await store.finish()
    }

    /// ONB-004-show_onboarding_ai_provider_setup: catalog load 실패 시 retry 가능한 error 상태를 유지한다.
    /// 사용자가 AI provider catalog/status를 불러오지 못한 상황에서도 onboarding session이 같은 단계에 머무르는지 검증한다.
    /// - 검증 내용: bootstrap load failure가 `.bootstrapFailed` action으로 라우팅되고 setup state를 error로 전환한다.
    /// - 사전 조건: `aiConnectionsFileClient.load`가 파일 시스템 오류를 throw한다.
    /// - 기대 결과: `bootstrapPhase=.failed`, load error, `status=.error`, `isComplete=false` 상태다.
    func testShowCatalogLoadFailureKeepsRetryableErrorState() async {
        let store = TestStore(initialState: AiProviderSetupState()) {
            AiProviderSetupFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { throw CancellationError() }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapFailed) { state in
            state.bootstrapPhase = .failed
            state.loadError = "Failed to load AI connections."
            state.status = .error
        }

        XCTAssertFalse(store.state.isComplete)
        await store.finish()
    }

    /// ONB-004-show_onboarding_ai_provider_setup: Retry bootstrap은 진행 중인 bootstrap을 취소하고 최신 결과만 반영한다.
    /// 사용자가 catalog/status reload를 다시 요청했을 때 이전 bootstrap 결과가 늦게 도착해 setup 상태를 덮지 않는지 검증한다.
    /// - 검증 내용: `.retryBootstrapTapped`가 in-flight bootstrap effect를 cancelInFlight하고 두 번째 load 결과만 complete 상태로 반영한다.
    /// - 사전 조건: 첫 번째 load는 취소 전까지 완료되지 않고 두 번째 load는 connected OpenAI file을 반환한다.
    /// - 기대 결과: 첫 번째 load cancellation이 관측되고 최신 bootstrap/reverification 결과만 `providerConnected/complete` 상태로 남는다.
    func testRetryBootstrapCancelsInFlightBootstrapBeforeApplyingLatestResult() async {
        let provider = AiProvider.openai
        let firstLoadStarted = LockIsolated(false)
        let firstLoadCancelled = LockIsolated(false)
        let latestFile = AIConnectionsFile.connectedAPIKeyFixture(provider: provider)
        let store = TestStore(initialState: AiProviderSetupState()) {
            AiProviderSetupFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = {
                if !firstLoadStarted.value {
                    firstLoadStarted.setValue(true)
                    try await withTaskCancellationHandler {
                        while true {
                            try Task.checkCancellation()
                            try await Task.sleep(nanoseconds: 1_000_000_000)
                        }
                    } onCancel: {
                        firstLoadCancelled.setValue(true)
                    }
                    return AIConnectionsFile.empty()
                }
                return latestFile
            }
            $0.aiConnectionsFileClient.save = { .success($0) }
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }
        await Self.waitUntil { firstLoadStarted.value }

        await store.send(.retryBootstrapTapped)
        await Self.waitUntil { firstLoadCancelled.value }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: provider]?.connectionState = .checkingStatus
            state.rows[id: provider]?.statusReason = .none
            state.status = .pending
        }
        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: provider]?.connectionState = .connected
            state.rows[id: provider]?.statusReason = .none
            state.choice = .providerConnected
            state.status = .complete
        }

        await store.finish()
    }

    // MARK: - ONB-004-start_ai_provider_connection_from_onboarding

    /// ONB-004-start_ai_provider_connection_from_onboarding: OAuth provider Connect가 SET-007 shared row flow로 라우팅된다.
    /// 사용자가 ChatGPT Codex row의 Connect를 누를 때 onboarding이 자체 연결 로직을 갖지 않고 shared row reducer를 실행하는지 검증한다.
    /// - 검증 내용: `.connectButtonTapped`가 child reducer의 `.startBrowserLogin` action을 emit하고 setup 상태를 pending으로 해석한다.
    /// - 사전 조건: ChatGPT Codex row는 `notVerified`이고 native browser login은 즉시 cancelled 실패를 반환한다.
    /// - 기대 결과: row가 `connectInProgress/browserLoginInProgress`로 전환된 뒤 취소 실패 상태를 row reducer가 보존하고 blocked 상태로 복귀한다.
    func testStartConnectionRoutesOAuthProviderThroughSharedRowReducer() async {
        let store = TestStore(initialState: AiProviderSetupState()) {
            AiProviderSetupFeature()
        } withDependencies: {
            $0.codexNativeAuthClient.startBrowserLogin = {
                AsyncThrowingStream { continuation in
                    continuation.yield(.failed(.cancelled))
                    continuation.finish()
                }
            }
        }

        await store.send(.row(.element(id: .chatgptCodex, action: .connectButtonTapped)))

        await store.receive(\.row[id: .chatgptCodex].startBrowserLogin) { state in
            state.rows[id: .chatgptCodex]?.connectionState = .connectInProgress
            state.rows[id: .chatgptCodex]?.flowState = .browserLoginInProgress
            state.status = .pending
        }

        await store.receive(\.row[id: .chatgptCodex].browserLoginFailed) { state in
            state.rows[id: .chatgptCodex]?.connectionState = .notVerified
            state.rows[id: .chatgptCodex]?.flowState = .idle
            state.rows[id: .chatgptCodex]?.statusReason = .none
            state.status = .blocked
        }

        await store.finish()
    }

    /// ONB-004-start_ai_provider_connection_from_onboarding: 실패-only row action은 bootstrap reload 없이 shared row 실패 상태를
    /// 보존한다.
    /// OAuth 로그인 실패나 검증 실패가 저장 파일을 바꾸지 않는 경우 onboarding이 stale file 상태로 row 실패 상태를 덮지 않는지 검증한다.
    /// - 검증 내용: `.browserLoginFailed` 처리 중 `aiConnectionsFileClient.load`가 호출되지 않고 row의 retry 가능한 실패 상태가 유지된다.
    /// - 사전 조건: ChatGPT Codex row는 browser login 진행 중이며 connection file은 변경되지 않는다.
    /// - 기대 결과: row는 `connectionFailed/idle`과 `.networkUnavailable` reason을 유지하고 setup은 blocked 상태다.
    func testBrowserLoginFailureKeepsSharedRowFailureStateWithoutReloadingBootstrap() async {
        var initialState = AiProviderSetupState()
        initialState.bootstrapPhase = .loaded
        initialState.rows[id: .chatgptCodex]?.connectionState = .connectInProgress
        initialState.rows[id: .chatgptCodex]?.flowState = .browserLoginInProgress

        let store = TestStore(initialState: initialState) {
            AiProviderSetupFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = {
                XCTFail("Failure-only row actions must not reload bootstrap state")
                return .empty(updatedAtMs: 1)
            }
        }

        await store.send(.row(.element(
            id: .chatgptCodex,
            action: .browserLoginFailed(.timeout),
        ))) { state in
            state.rows[id: .chatgptCodex]?.connectionState = .connectionFailed
            state.rows[id: .chatgptCodex]?.flowState = .idle
            state.rows[id: .chatgptCodex]?.statusReason = .networkUnavailable
            state.status = .blocked
        }

        await store.finish()
    }

    /// ONB-004-start_ai_provider_connection_from_onboarding: 연결 취소 후 AI Provider Setup 단계가 blocked로 복귀한다.
    /// 사용자가 진행 중인 연결 flow를 취소했을 때 onboarding surface가 Connect와 Set up later 선택 상태로 되돌아오는지 검증한다.
    /// - 검증 내용: shared row `.cancelButtonTapped`가 row transient state를 초기화하고 bootstrap reload 없이 parent setup status를
    /// 재계산한다.
    /// - 사전 조건: ChatGPT Codex row는 browser login 진행 중이며 setup status는 pending이다.
    /// - 기대 결과: row는 `notVerified/idle`, setup은 `choice=.none`, `status=.blocked`, `isComplete=false` 상태다.
    func testStartConnectionCancelReturnsToBlockedSetupState() async {
        var initialState = AiProviderSetupState()
        initialState.bootstrapPhase = .loaded
        initialState.status = .pending
        initialState.rows[id: .chatgptCodex]?.connectionState = .connectInProgress
        initialState.rows[id: .chatgptCodex]?.flowState = .browserLoginInProgress

        let cancelRecorder = LockIsolated(false)
        let store = TestStore(initialState: initialState) {
            AiProviderSetupFeature()
        } withDependencies: {
            $0.codexNativeAuthClient.cancelCurrentFlow = {
                cancelRecorder.setValue(true)
            }
        }

        await store.send(.row(.element(id: .chatgptCodex, action: .cancelButtonTapped))) { state in
            state.rows[id: .chatgptCodex]?.connectionState = .notVerified
            state.rows[id: .chatgptCodex]?.flowState = .idle
            state.status = .blocked
        }

        XCTAssertTrue(cancelRecorder.value)
        XCTAssertEqual(store.state.choice, .none)
        XCTAssertFalse(store.state.isComplete)
        await store.finish()
    }

    /// ONB-004-start_ai_provider_connection_from_onboarding: shared row connectionResponse 이후 setup 상태를 complete로 해석한다.
    /// SET-007 연결 flow가 성공 결과를 돌려준 뒤 onboarding이 row 결과를 step completion으로 변환하는 경계를 검증한다.
    /// - 검증 내용: child reducer가 `.connectionResponse`를 먼저 반영하고 parent setup reducer가 `providerConnected/complete` 상태로
    /// 재계산한다.
    /// - 사전 조건: OpenAI row는 API key 연결 진행 중이고 connection client는 connected file을 반환한다.
    /// - 기대 결과: row가 connected가 되고 bootstrap/reverification 이후에도 setup complete 상태가 유지된다.
    func testConnectionResponseRefreshesStatusAfterSharedRowReducerUpdatesRow() async {
        let provider = AiProvider.openai
        let updatedFile = AIConnectionsFile.connectedAPIKeyFixture(provider: provider)
        var initialState = AiProviderSetupState()
        initialState.bootstrapPhase = .loaded
        initialState.rows[id: provider]?.connectionState = .connectInProgress
        initialState.rows[id: provider]?.flowState = .connecting

        let store = TestStore(initialState: initialState) {
            AiProviderSetupFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { updatedFile }
            $0.aiConnectionsFileClient.save = { .success($0) }
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
        }

        await store.send(.row(.element(
            id: provider,
            action: .connectionResponse(AiProviderConnectionResult(
                provider: provider,
                state: .connected,
                reason: .none,
                updatedFile: updatedFile,
            )),
        ))) { state in
            state.rows[id: provider]?.connectionState = .connected
            state.rows[id: provider]?.statusReason = .none
            state.rows[id: provider]?.flowState = .idle
            state.choice = .providerConnected
            state.status = .complete
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.rows[id: provider]?.connectionState = .checkingStatus
            state.rows[id: provider]?.statusReason = .none
        }

        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: provider]?.connectionState = .connected
            state.rows[id: provider]?.statusReason = .none
            state.choice = .providerConnected
            state.status = .complete
        }

        await store.finish()
    }

    // MARK: - ONB-004-skip_ai_provider_setup_during_onboarding

    /// ONB-004-skip_ai_provider_setup_during_onboarding: Set up later 저장 성공 후 skipped를 확정한다.
    /// 사용자가 provider 연결 없이 나중에 설정하기를 선택할 때 progress snapshot 저장 성공 이후에만 step을 완료 처리하는지 검증한다.
    /// - 검증 내용: parent `OnboardingFeature`가 save 성공 결과를 기준으로 `choice/status`와 snapshot skipped 필드를 확정한다.
    /// - 사전 조건: 현재 step은 AI Provider Setup이고 progress save dependency는 성공과 snapshot recording을 수행한다.
    /// - 기대 결과: `choice=.setUpLater`, `status=.skipped`, `canGoNext=true`이고 저장 snapshot도 skipped 상태다.
    func testSetUpLaterConfirmsSkippedAfterProgressSaveSucceeds() async {
        let saveRecorder = LockIsolated<OnboardingProgressSnapshot?>(nil)
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .aiProviderSetup

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.recording(saveRecorder: saveRecorder)
        }

        await store.send(.aiProviderSetup(.setUpLaterTapped)) { state in
            state.aiProviderSetup.choice = .setUpLater
            state.aiProviderSetup.status = .skipped
        }

        let saved = saveRecorder.value
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.currentStep, .aiProviderSetup)
        XCTAssertEqual(saved?.stepState.aiProviderSetupSkipped, true)
        XCTAssertEqual(saved?.stepState.aiProviderSetupChoice, .setUpLater)
        XCTAssertEqual(saved?.stepState.aiProviderSetupStatus, .skipped)
        XCTAssertTrue(store.state.canGoNext)

        await store.finish()
    }

    /// ONB-004-skip_ai_provider_setup_during_onboarding: snapshot save 실패 시 skipped를 확정하지 않는다.
    /// 사용자가 Set up later를 눌렀지만 progress 저장이 실패한 경우 retry 가능한 오류로 남는지 검증한다.
    /// - 검증 내용: save failure가 `choice=.none`과 `status=.error`를 유지해 step completion을 막는다.
    /// - 사전 조건: 현재 step은 AI Provider Setup이고 progress save dependency는 `.failure`를 반환한다.
    /// - 기대 결과: skipped가 저장/확정되지 않고 Next disabled message가 유지된다.
    func testSetUpLaterSaveFailureDoesNotConfirmSkipped() async {
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .aiProviderSetup

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = OnboardingProgressClient(
                load: { .empty },
                save: { _ in .failure },
                reset: {},
            )
        }

        await store.send(.aiProviderSetup(.setUpLaterTapped)) { state in
            state.aiProviderSetup.choice = .none
            state.aiProviderSetup.loadError = "Failed to save onboarding progress."
            state.aiProviderSetup.status = .error
        }

        XCTAssertFalse(store.state.aiProviderSetup.isComplete)
        XCTAssertEqual(
            store.state.aiProviderSetup.nextDisabledMessage,
            "Connect a provider or choose Set up later to continue.",
        )

        await store.finish()
    }

    /// ONB-004-skip_ai_provider_setup_during_onboarding: 저장된 skipped choice를 재진입 시 복원한다.
    /// 사용자가 Back/Next 또는 앱 재진입으로 AI Provider Setup에 돌아왔을 때 이전 Set up later 선택이 유지되는지 검증한다.
    /// - 검증 내용: `OnboardingProgressClient.load` 성공 snapshot이 setup choice/status와 Next 가능 상태로 복원된다.
    /// - 사전 조건: prior required steps는 완료됐고 progress snapshot은 AI Provider Setup skipped 상태를 저장하고 있다.
    /// - 기대 결과: current step은 AI Provider Setup이며 `choice=.setUpLater`, `status=.skipped`, `canGoNext=true` 상태다.
    func testSetUpLaterRestoreKeepsSkippedChoiceAndAllowsNext() async {
        let saveRecorder = LockIsolated<OnboardingProgressSnapshot?>(nil)
        let snapshot = OnboardingProgressSnapshot(
            currentStep: .aiProviderSetup,
            stepState: OnboardingStepState(
                welcomeComplete: true,
                accessUnlockComplete: true,
                permissionsComplete: true,
                aiProviderSetupComplete: true,
                aiProviderSetupSkipped: true,
                aiProviderSetupChoice: .setUpLater,
                aiProviderSetupStatus: .skipped,
            ),
        )
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.resumingAndRecording(
                snapshot: snapshot,
                saveRecorder: saveRecorder,
            )
        }

        await store.send(.onAppear) { state in
            state.accessUnlock.isComplete = true
            state.accessUnlock.status = .coreLicenseActive
            state.permissions.isComplete = true
            state.aiProviderSetup.choice = .setUpLater
            state.aiProviderSetup.status = .skipped
            state.currentStep = .aiProviderSetup
        }

        XCTAssertTrue(store.state.canGoNext)
        XCTAssertEqual(saveRecorder.value?.stepState.aiProviderSetupChoice, .setUpLater)
        XCTAssertEqual(saveRecorder.value?.stepState.aiProviderSetupStatus, .skipped)

        await store.finish()
    }

    /// ONB-004-skip_ai_provider_setup_during_onboarding: connected provider가 Set up later보다 우선한다.
    /// 사용자가 이전에 Set up later를 선택했더라도 SET-007 연결 결과가 도착하면 onboarding step이 연결 완료를 우선하는지 검증한다.
    /// - 검증 내용: shared row `connectionResponse`와 bootstrap/reverification 결과가 `providerConnected/complete` 상태를 유지한다.
    /// - 사전 조건: setup choice는 `setUpLater`이고 OpenAI row는 API key 연결 진행 중이다.
    /// - 기대 결과: 연결 성공 직후부터 `choice=.providerConnected`, `status=.complete`가 되고 skipped 상태로 되돌아가지 않는다.
    func testConnectedProviderTakesPriorityOverSetUpLaterChoice() async {
        let provider = AiProvider.openai
        let updatedFile = AIConnectionsFile.connectedAPIKeyFixture(provider: provider)
        var initialState = AiProviderSetupState()
        initialState.choice = .setUpLater
        initialState.status = .skipped
        initialState.bootstrapPhase = .loaded
        initialState.rows[id: provider]?.connectionState = .connectInProgress
        initialState.rows[id: provider]?.flowState = .connecting

        let store = TestStore(initialState: initialState) {
            AiProviderSetupFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { updatedFile }
            $0.aiConnectionsFileClient.save = { .success($0) }
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
        }

        await store.send(.row(.element(
            id: provider,
            action: .connectionResponse(AiProviderConnectionResult(
                provider: provider,
                state: .connected,
                reason: .none,
                updatedFile: updatedFile,
            )),
        ))) { state in
            state.rows[id: provider]?.connectionState = .connected
            state.rows[id: provider]?.statusReason = .none
            state.rows[id: provider]?.flowState = .idle
            state.choice = .providerConnected
            state.status = .complete
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.rows[id: provider]?.connectionState = .checkingStatus
            state.rows[id: provider]?.statusReason = .none
        }

        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: provider]?.connectionState = .connected
            state.rows[id: provider]?.statusReason = .none
            state.choice = .providerConnected
            state.status = .complete
        }

        await store.finish()
    }

    /// ONB-004-skip_ai_provider_setup_during_onboarding: complete 단계 저장 중 re-verification은 완료 상태를 보존한다.
    /// 연결 완료로 onboarding을 지나간 사용자가 background status 확인을 받더라도 progress snapshot이 완료 상태를 잃지 않는지 검증한다.
    /// - 검증 내용: parent save path가 `checkingStatus` transient row를 durable incomplete 상태로 저장하지 않는다.
    /// - 사전 조건: current step은 complete이고 AI Provider Setup은 providerConnected complete 상태다.
    /// - 기대 결과: 저장 snapshot이 `aiProviderSetupComplete=true`, `providerConnected`, `complete` 값을 유지한다.
    func testCompleteStepSaveKeepsProviderSetupCompleteDuringReverification() async {
        let provider = AiProvider.openai
        let saveRecorder = LockIsolated<OnboardingProgressSnapshot?>(nil)
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .complete
        initialState.welcome.isComplete = true
        StateMutation.applyPersistedCompletedAccessStep(state: &initialState)
        initialState.permissions.isComplete = true
        initialState.aiProviderSetup.choice = .providerConnected
        initialState.aiProviderSetup.status = .complete
        initialState.aiProviderSetup.rows[id: provider]?.connectionState = .connected

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.recording(saveRecorder: saveRecorder)
        }

        await store.send(.aiProviderSetup(.bootstrapCompleted([
            AIProviderBootstrapResult(provider: provider, connectionState: .checkingStatus),
        ]))) { state in
            state.aiProviderSetup.bootstrapPhase = .loaded
            state.aiProviderSetup.rows[id: provider]?.connectionState = .checkingStatus
            state.aiProviderSetup.rows[id: provider]?.statusReason = .none
        }

        let saved = saveRecorder.value
        XCTAssertEqual(saved?.currentStep, .complete)
        XCTAssertEqual(saved?.stepState.aiProviderSetupComplete, true)
        XCTAssertEqual(saved?.stepState.aiProviderSetupChoice, .providerConnected)
        XCTAssertEqual(saved?.stepState.aiProviderSetupStatus, .complete)

        await store.finish()
    }
}

private extension ONB004ConfigureAIProviderDuringOnboardingTests {
    static func waitUntil(
        _ condition: @escaping @Sendable () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) async {
        for _ in 0 ..< 100 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Condition was not met in time", file: file, line: line)
    }
}

private extension AIConnectionsFile {
    static func fixture(records: [AiProvider: ProviderRecordFile]) -> AIConnectionsFile {
        AIConnectionsFile(
            updatedAtMs: 1,
            providers: Dictionary(uniqueKeysWithValues: records.map { provider, record in
                (provider.rawValue, record)
            }),
        )
    }

    static func connectedAPIKeyFixture(provider: AiProvider) -> AIConnectionsFile {
        fixture(records: [
            provider: .apiKeyRecord(provider: provider, status: .connected),
        ])
    }
}

private extension ProviderRecordFile {
    static func apiKeyRecord(
        provider: AiProvider,
        status: ProviderConnectionState,
    ) -> ProviderRecordFile {
        ProviderRecordFile(
            providerId: provider,
            authMethod: .apiKey,
            credential: .apiKey(APIKeyCredentialFile(secret: "test-key")),
            snapshot: ProviderSnapshotFile(
                lastKnownStatus: status,
                lastVerifiedAtMs: 1,
                lastErrorCode: .none,
            ),
        )
    }
}
