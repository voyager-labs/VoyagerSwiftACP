// FLOW-ID: onb.ai_provider_setup
import ComposableArchitecture
import Dependencies
import VoyagerEntitiesAi
@testable import VoyagerPagesOnboarding
import VoyagerShared
import XCTest

@MainActor
final class AiProviderSetupFlowTests: XCTestCase {
    // FLOW-PATH: happy_path

    /// ONB AI Provider Setup: happy_path
    /// 연결 완료 결과가 child reducer에서 parent onboarding progress까지 전파되는지 검증한다.
    /// - 검증 내용: connected provider 결과가 setup step을 complete로 승격하고 progress snapshot을 한 번 저장한다.
    /// - 사전 조건: 현재 step은 AI Provider Setup이며 OpenAI 연결 검증 결과가 connected다.
    /// - 기대 결과: provider choice/status가 complete로 바뀌고 저장 snapshot도 연결 완료 상태를 보존한다.
    func testConnectedProviderPromotesOnboardingStepAndPersistsProgress() async {
        let saveRecorder = LockIsolated<[OnboardingProgressSnapshot]>([])
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .aiProviderSetup
        initialState.aiProviderSetup.bootstrapPhase = .loaded

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = Self.progressClient(saveRecorder: saveRecorder)
        }
        // store.exhaustivity = .off: child bootstrap과 parent 저장 effect를 함께 거치는 flow 결과만 검증한다.
        store.exhaustivity = .off

        await store.send(.aiProviderSetup(.bootstrapVerificationCompleted([
            AIProviderBootstrapResult(provider: .openai, connectionState: .connected),
        ])))
        await store.finish()

        let saves = saveRecorder.value
        XCTAssertEqual(saves.count, 1)
        XCTAssertEqual(saves.first?.stepState.aiProviderSetupChoice, .providerConnected)
        XCTAssertEqual(saves.first?.stepState.aiProviderSetupStatus, .complete)
        XCTAssertTrue(saves.first?.stepState.aiProviderSetupComplete ?? false)
        XCTAssertEqual(store.state.aiProviderSetup.choice, .providerConnected)
        XCTAssertEqual(store.state.aiProviderSetup.status, .complete)
        XCTAssertTrue(store.state.canGoNext)
    }

    // FLOW-PATH: set_up_later

    /// ONB AI Provider Setup: set_up_later
    /// provider 연결 없이 나중에 설정하기를 선택한 사용자가 다음 단계로 진행할 수 있는지 검증한다.
    /// - 검증 내용: Set up later가 choice와 skipped 상태를 저장하고 parent Next gate를 연다.
    /// - 사전 조건: 현재 step은 AI Provider Setup이고 연결된 provider가 없다.
    /// - 기대 결과: 저장 snapshot이 setUpLater/skipped를 보존하며 Next가 활성화된다.
    func testSetUpLaterPersistsChoiceAndAllowsNextWithoutConnection() async {
        let saveRecorder = LockIsolated<[OnboardingProgressSnapshot]>([])
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .aiProviderSetup

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = Self.progressClient(saveRecorder: saveRecorder)
        }

        await store.send(.aiProviderSetup(.setUpLaterTapped)) { state in
            state.aiProviderSetup.choice = .setUpLater
            state.aiProviderSetup.status = .skipped
        }

        let saves = saveRecorder.value
        XCTAssertEqual(saves.count, 1)
        XCTAssertEqual(saves.first?.stepState.aiProviderSetupChoice, .setUpLater)
        XCTAssertEqual(saves.first?.stepState.aiProviderSetupStatus, .skipped)
        XCTAssertTrue(saves.first?.stepState.aiProviderSetupSkipped ?? false)
        XCTAssertTrue(store.state.canGoNext)
    }

    // FLOW-PATH: provider_catalog_or_connection_error

    /// ONB AI Provider Setup: provider_catalog_or_connection_error
    /// catalog 재시도 실패 뒤에도 사용자가 Set up later를 선택해 온보딩을 계속할 수 있는지 검증한다.
    /// - 검증 내용: retry가 error 상태를 다시 만들더라도 Set up later 저장이 skipped 완료 상태로 전환한다.
    /// - 사전 조건: AI connection catalog load가 실패하고 progress 저장은 성공한다.
    /// - 기대 결과: error는 retry 가능하게 남고 Set up later 선택 후 Next가 활성화된다.
    func testCatalogOrConnectionFailureRemainsRetryableWithoutHardBlockingLaterChoice() async {
        let saveRecorder = LockIsolated<[OnboardingProgressSnapshot]>([])
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .aiProviderSetup
        initialState.aiProviderSetup.bootstrapPhase = .loading

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = Self.progressClient(saveRecorder: saveRecorder)
            $0.aiConnectionsFileClient.load = { throw CancellationError() }
        }
        // store.exhaustivity = .off: retry bootstrap의 내부 effect와 parent progress 저장보다 오류 후 선택 가능성을 검증한다.
        store.exhaustivity = .off

        await store.send(.aiProviderSetup(.bootstrapFailed)) { state in
            state.aiProviderSetup.bootstrapPhase = .failed
            state.aiProviderSetup.loadError = "Failed to load AI connections."
            state.aiProviderSetup.status = .error
        }
        XCTAssertFalse(store.state.aiProviderSetup.isComplete)

        await store.send(.aiProviderSetup(.retryBootstrapTapped)) { state in
            state.aiProviderSetup.bootstrapPhase = .loading
            state.aiProviderSetup.loadError = nil
        }
        await store.receive(\.aiProviderSetup.bootstrapFailed) { state in
            state.aiProviderSetup.bootstrapPhase = .failed
            state.aiProviderSetup.loadError = "Failed to load AI connections."
            state.aiProviderSetup.status = .error
        }

        await store.send(.aiProviderSetup(.setUpLaterTapped)) { state in
            state.aiProviderSetup.choice = .setUpLater
            state.aiProviderSetup.loadError = nil
            state.aiProviderSetup.status = .skipped
        }
        await store.finish()

        XCTAssertTrue(saveRecorder.value.contains {
            $0.stepState.aiProviderSetupChoice == .setUpLater
                && $0.stepState.aiProviderSetupStatus == .skipped
        })
        XCTAssertTrue(store.state.canGoNext)
    }
}

private extension AiProviderSetupFlowTests {
    static func progressClient(
        saveRecorder: LockIsolated<[OnboardingProgressSnapshot]>,
    ) -> OnboardingProgressClient {
        OnboardingProgressClient(
            load: { .empty },
            save: { snapshot in
                saveRecorder.withValue { $0.append(snapshot) }
                return .success
            },
            reset: {},
        )
    }
}
