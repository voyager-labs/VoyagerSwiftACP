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

        await store.send(.unlockAccess(.claimResponse(.failure(.networkFailure)))) { state in
            state.unlockAccess.status = .networkFailure
            state.unlockAccess.isComplete = false
            state.unlockAccess.errorMessage = "Network error. Please check your connection and try again."
        }

        let savedSnapshots = await recorder.snapshot()
        XCTAssertEqual(savedSnapshots, [])

        await store.finish()
    }
}
