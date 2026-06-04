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
            state.status = .blocked
        }

        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: provider]?.connectionState = .connected
            state.rows[id: provider]?.statusReason = .none
            state.choice = .providerConnected
            state.status = .complete
        }

        await store.finish()
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
