import ComposableArchitecture
import Dependencies
import VoyagerFeaturesAccountAccess
@testable import VoyagerPagesOnboarding
import VoyagerShared
import XCTest

@MainActor
final class ONB001BackCancelsSignInTests: XCTestCase {
    // MARK: - ONB-001-back_cancels_sign_in

    /// ONB-001-back_cancels_sign_in: access step의 Back intent는 canonical sign-in cancellation으로 변환된다.
    /// wizard navigation은 core에 남기고 sign-in cancellation만 narrow access owner에 전달합니다.
    /// - 검증 내용: cancel intent가 canonical `AccountAccessAction.cancelSignIn`으로 매핑됩니다.
    /// - 사전 조건: access unlock 단계에서 sign-in handoff가 진행 중입니다.
    /// - 기대 결과: Onboarding core는 AccountAccess child action을 저장하거나 직접 전송하지 않습니다.
    func testBackCancelIntentRoutesToCanonicalAccessAction() {
        guard case .cancelSignIn = OnboardingAccessIntent.cancelSignIn.accountAccessAction else {
            XCTFail("cancel intent must route to AccountAccessAction.cancelSignIn")
            return
        }
    }

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
}
