import ComposableArchitecture
import VoyagerEntitiesAi
import VoyagerFeaturesAiProviderConnection
@testable import VoyagerPagesOnboarding
import XCTest

@MainActor
final class ONB004ConfigureAIProviderDuringOnboardingTests: XCTestCase {
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
        XCTAssertEqual(saved?.stepState.aiProviderSetupSkipped, true)
        XCTAssertEqual(saved?.stepState.aiProviderSetupChoice, .setUpLater)
        XCTAssertEqual(saved?.stepState.aiProviderSetupStatus, .skipped)

        await store.finish()
    }

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

    func testCompleteStepSaveKeepsProviderSetupCompleteDuringReverification() async {
        let provider = AiProvider.openai
        let saveRecorder = LockIsolated<OnboardingProgressSnapshot?>(nil)
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .complete
        initialState.welcome.isComplete = true
        initialState.betaAccess.isComplete = true
        initialState.betaAccess.status = .active
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
    static func connectedAPIKeyFixture(provider: AiProvider) -> AIConnectionsFile {
        AIConnectionsFile(
            updatedAtMs: 1,
            providers: [
                provider.rawValue: ProviderRecordFile(
                    providerId: provider,
                    authMethod: .apiKey,
                    credential: .apiKey(APIKeyCredentialFile(secret: "test-key")),
                    snapshot: ProviderSnapshotFile(
                        lastKnownStatus: .connected,
                        lastVerifiedAtMs: 1,
                        lastErrorCode: .none,
                    ),
                ),
            ],
        )
    }
}
