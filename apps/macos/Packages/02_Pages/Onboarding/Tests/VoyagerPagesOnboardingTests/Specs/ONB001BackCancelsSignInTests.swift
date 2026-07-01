import ComposableArchitecture
import Dependencies
@testable import VoyagerPagesOnboarding
import VoyagerShared
import XCTest

@MainActor
final class ONB001BackCancelsSignInTests: XCTestCase {
    /// ONB-001-update_onboarding_step_state: access snapshot 없이 후속 진행 상태를 저장해도 기존 access snapshot을 지우지 않는다.
    /// 후속 step 저장이 `accessSnapshot=nil`인 스냅샷을 전달해도 이전 access unlock 근거를 보존하는지 검증합니다.
    /// - 검증 내용: access snapshot 저장 후 nil snapshot 저장 → load 시 accessSnapshot 보존
    /// - 사전 조건: live progress client와 in-memory UserDefaultsClient 사용
    /// - 기대 결과: currentStep/stepState는 최신 저장값으로 갱신되고 accessSnapshot은 기존 값을 유지합니다.
    func testProgressSaveWithNilAccessSnapshotPreservesStoredAccessSnapshot() {
        let userDefaultsClient = UserDefaultsClient.testValue

        let loadResult = withDependencies {
            $0.userDefaultsClient = userDefaultsClient
        } operation: {
            let client = OnboardingProgressClient.liveValue
            let completedAccessSnapshot = OnboardingProgressSnapshot(
                currentStep: .accessUnlock,
                stepState: OnboardingStepState(accessUnlockComplete: true),
                accessSnapshot: StateMutation.activeAccessSnapshot,
            )
            XCTAssertEqual(client.save(completedAccessSnapshot), .success)

            let laterSnapshot = OnboardingProgressSnapshot(
                currentStep: .permissions,
                stepState: OnboardingStepState(
                    accessUnlockComplete: true,
                    permissionsComplete: true,
                ),
                accessSnapshot: nil,
            )
            XCTAssertEqual(client.save(laterSnapshot), .success)

            return client.load()
        }

        guard case let .success(loadedSnapshot) = loadResult else {
            XCTFail("저장된 progress snapshot을 다시 읽을 수 있어야 함")
            return
        }

        XCTAssertEqual(loadedSnapshot.currentStep, .permissions)
        XCTAssertTrue(loadedSnapshot.stepState.accessUnlockComplete)
        XCTAssertTrue(loadedSnapshot.stepState.permissionsComplete)
        XCTAssertEqual(loadedSnapshot.accessSnapshot, StateMutation.activeAccessSnapshot)
    }

    func testGoBackFromAccessUnlockCancelsPendingSignIn() async {
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .accessUnlock
        initialState.welcome.isComplete = true
        initialState.accessUnlock.isSignInInProgress = true
        initialState.accessUnlock.handoffPendingState = "pending-state-abc"

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.noOp
        }

        await store.send(.backTapped) { state in
            state.currentStep = .welcome
        }

        await store.receive(\.accessUnlock.cancelSignIn) { state in
            state.accessUnlock.isSignInInProgress = false
            state.accessUnlock.didSignInFail = false
            state.accessUnlock.handoffPendingState = nil
        }

        await store.finish()
    }
}
