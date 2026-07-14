import ComposableArchitecture
import VoyagerFeaturesAccountAccess
@testable import VoyagerPagesOnboarding
import XCTest

@MainActor
extension ONB001RunUserOnboardingTests {
    // MARK: - ONB-001-reconcile_canonical_access_restoration

    // ONB-001-reconcile_canonical_access_restoration: 저장된 authenticated 완료 정보는 현재 canonical locked fact를 덮어쓰지 않는다.
    // 복원 중 콜백 또는 lifecycle refresh가 더 최신 locked 사실을 제공한 경우 오래된 snapshot 완료를 신뢰하지 않는지 검증합니다.
    // - 검증 내용: stale authenticated snapshot을 복원해도 현재 locked access fact에서는 unlock 단계가 유지됩니다.
    // - 사전 조건: permissions를 가리키는 completed snapshot과 현재 locked AccountAccess 상태가 있습니다.
    // - 기대 결과: `currentStep`은 `.accessUnlock`이고 completed progress를 저장하지 않습니다.

    /// ONB-001-reconcile_canonical_access_restoration: 현재 locked projection은 저장된 access completion보다 우선한다.
    /// 저장된 완료 정보가 있어도 현재 canonical access가 locked이면 후속 wizard 단계를 다시 열지 않습니다.
    /// - 검증 내용: `.permissions` snapshot은 `.accessUnlock`으로 보정되고 저장됩니다.
    /// - 사전 조건: persisted snapshot은 access 완료지만 현재 projection은 locked입니다.
    /// - 기대 결과: access completion은 false로 저장되고 다음 단계는 잠긴 상태로 유지됩니다.
    func testCurrentLockedProjectionOverridesPersistedAccessCompletion() async {
        let saveRecorder = LockIsolated<OnboardingProgressSnapshot?>(nil)
        let snapshot = OnboardingProgressSnapshot(
            currentStep: .permissions,
            stepState: OnboardingStepState(
                welcomeComplete: true,
                accessUnlockComplete: true,
                permissionsComplete: false,
                completeComplete: false,
            ),
            accessSnapshot: StateMutation.activeAccessSnapshot,
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
            state.didBootstrapProgress = true
            state.welcome.isComplete = true
            state.currentStep = .accessUnlock
        }
        await store.finish()

        XCTAssertFalse(store.state.access.isComplete)
        XCTAssertEqual(store.state.currentStep, .accessUnlock)
        XCTAssertFalse(saveRecorder.value?.stepState.accessUnlockComplete ?? true)
    }

    /// ONB-001-reconcile_canonical_access_restoration: 현재 authenticated projection은 저장된 incomplete flag를 덮어쓴다.
    /// canonical lifecycle access가 이미 인증되었으면 이전 progress가 unlock 미완료여도 저장된 다음 단계를 복원합니다.
    /// - 검증 내용: `.permissions`가 reachable하고 access completion이 true로 다시 저장됩니다.
    /// - 사전 조건: persisted snapshot은 access 미완료지만 현재 projection은 authenticated입니다.
    /// - 기대 결과: wizard가 `.permissions`를 복원하고 canonical access fact를 저장합니다.
    func testCurrentAuthenticatedProjectionSatisfiesPersistedAccessGate() async {
        let saveRecorder = LockIsolated<OnboardingProgressSnapshot?>(nil)
        let snapshot = OnboardingProgressSnapshot(
            currentStep: .permissions,
            stepState: OnboardingStepState(
                welcomeComplete: true,
                accessUnlockComplete: false,
                permissionsComplete: false,
                completeComplete: false,
            ),
        )
        var initialState = OnboardingFeature.State()
        initialState.access = StateMutation.activeAccessProjection
        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.resumingAndRecording(
                snapshot: snapshot,
                saveRecorder: saveRecorder,
            )
        }

        await store.send(.onAppear) { state in
            state.didBootstrapProgress = true
            state.welcome.isComplete = true
            state.currentStep = .permissions
        }
        await store.finish()

        XCTAssertTrue(store.state.canGoBack)
        XCTAssertTrue(saveRecorder.value?.stepState.accessUnlockComplete ?? false)
    }

    /// ONB-001-reconcile_canonical_access_restoration: restoration 중 callback projection이 마지막 canonical fact가 된다.
    /// persistence reconciliation 뒤 도착한 authenticated callback은 unlock gate를 열고 stale locked result를 다시 쓰지 못하게 합니다.
    /// - 검증 내용: authenticated projection update 뒤 access step은 next를 허용하고 완료 fact를 저장합니다.
    /// - 사전 조건: restored snapshot은 access 완료지만 초기 canonical projection은 locked입니다.
    /// - 기대 결과: callback projection이 최종 access state이며 `canGoNext`가 true입니다.
    func testCallbackProjectionWinsDuringRestoration() async {
        let snapshot = OnboardingProgressSnapshot(
            currentStep: .permissions,
            stepState: OnboardingStepState(
                welcomeComplete: true,
                accessUnlockComplete: true,
                permissionsComplete: false,
                completeComplete: false,
            ),
            accessSnapshot: StateMutation.activeAccessSnapshot,
        )
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.resuming(from: snapshot)
        }

        await store.send(.onAppear) { state in
            state.didBootstrapProgress = true
            state.welcome.isComplete = true
            state.currentStep = .accessUnlock
        }
        await store.send(.accessProjectionUpdated(StateMutation.activeAccessProjection)) { state in
            state.access = StateMutation.activeAccessProjection
        }

        XCTAssertTrue(store.state.canGoNext)
        await store.finish()
    }

    // ONB-001-resume_onboarding_session: 완료로 저장된 Access step에 access snapshot이 없으면 Access step으로 되돌려 재확인을 요구한다.
    // 과거 진행 상태가 완료 flag만 갖고 외부 access source of truth를 복원할 수 없을 때 stale completion을 신뢰하지 않는지 검증합니다.
    // - 검증 내용: `accessUnlockComplete = true`이지만 `accessSnapshot = nil`인 snapshot을 복원하면 accessUnlock를 미완료로 보정하고 저장합니다.
    // - 사전 조건: snapshot은 permissions 진입 직전 상태이나 access 결과 snapshot은 저장되어 있지 않습니다.
    // - 기대 결과: `currentStep = .accessUnlock`, `accessUnlockComplete = false`, 저장된 snapshot의 `accessSnapshot`은
    // `nil`입니다.

    // ONB-001-resume_onboarding_session: permissions 단계로 복원된 완료 access가 device binding 실패를 알리면 Access 단계로 되돌린다.
    // AccountAccess가 binding 오류 상태를 소유한 채 semantic recovery delegate만 부모에 전달할 때, 부모가 이후 단계 재개를 막는지 검증합니다.
    // - 검증 내용: `currentStep`을 accessUnlock으로 되돌리고, 미완료 access progress를 저장하며 main window를 열지 않습니다.
    // - 사전 조건: permissions 단계로 복원되어 access/permissions가 완료되었고, AccountAccess가 device binding 실패 후 미완료 상태입니다.
    // - 기대 결과: `currentStep = .accessUnlock`, `accessUnlock.isComplete = false`, 저장된 `accessUnlockComplete = false`,
    // 열린 main window가 없습니다.

    // ONB-001-resume_onboarding_session: complete 단계로 복원된 완료 access가 device binding 실패를 알리면 완료 우회를 취소한다.
    // 완료 화면이 이미 복원되었어도 AccountAccess의 device binding recovery delegate가 access 재확인을 강제하는지 검증합니다.
    // - 검증 내용: `currentStep`을 accessUnlock으로 되돌리고, 미완료 access progress를 저장하며 main window를 열지 않습니다.
    // - 사전 조건: complete 단계로 복원되어 모든 단계가 완료되었고, AccountAccess가 device binding 실패 후 미완료 상태입니다.
    // - 기대 결과: `currentStep = .accessUnlock`, `accessUnlock.isComplete = false`, 저장된 `accessUnlockComplete = false`,
    // 열린 main window가 없습니다.

    // ONB-001-resume_onboarding_session: permissions 단계로 복원된 완료 access가 access 확인 실패를 알리면 Access 단계로 되돌린다.
    // AccountAccess가 access failure 상태를 소유한 채 semantic recovery delegate만 부모에 전달할 때, 부모가 이후 단계 재개를 막는지 검증합니다.
    // - 검증 내용: `currentStep`을 accessUnlock으로 되돌리고, 미완료 access progress를 저장하며 main window를 열지 않습니다.
    // - 사전 조건: permissions 단계로 복원되어 access/permissions가 완료되었고, AccountAccess가 access failure 후 미완료 상태입니다.
    // - 기대 결과: `currentStep = .accessUnlock`, `accessUnlock.isComplete = false`, 저장된 `accessUnlockComplete = false`,
    //   저장된 `accessSnapshot = nil`, 열린 main window가 없습니다.

    // ONB-001-resume_onboarding_session: complete 단계로 복원된 완료 access가 access 확인 실패를 알리면 완료 우회를 취소한다.
    // 완료 화면이 이미 복원되었어도 AccountAccess의 access failure recovery delegate가 access 재확인을 강제하는지 검증합니다.
    // - 검증 내용: `currentStep`을 accessUnlock으로 되돌리고, 미완료 access progress를 저장하며 main window를 열지 않습니다.
    // - 사전 조건: complete 단계로 복원되어 모든 단계가 완료되었고, AccountAccess가 access failure 후 미완료 상태입니다.
    // - 기대 결과: `currentStep = .accessUnlock`, `accessUnlock.isComplete = false`, 저장된 `accessUnlockComplete = false`,
    //   저장된 `accessSnapshot = nil`, 열린 main window가 없습니다.

    // ONB-001-resume_onboarding_session: legacy access snapshot이 있어도 저장된 미완료 Access step은 완료로 덮어쓰지 않는다.
    // legacy snapshot의 복원 컨텍스트를 유지하면서도 persisted completion flag를 정본으로 처리하는지 검증합니다.
    // - 검증 내용: `accessUnlockComplete = false`이면 active legacy snapshot이 있어도 accessUnlock에 머물고 fresh revoked 결과로 교체합니다.
    // - 사전 조건: permissions 단계가 저장되었지만 Access step은 미완료이며 active legacy access snapshot이 함께 저장되어 있습니다.
    // - 기대 결과: `currentStep = .accessUnlock`, `accessUnlockComplete = false`, canonical revoked snapshot이 저장됩니다.

    private func makeIncompleteAccessRestoreFixture(
        testDate: Date,
        saveRecorder: LockIsolated<OnboardingProgressSnapshot?>,
        accessSnapshotRecorder: AccessSnapshotRecorder,
    ) -> (
        store: TestStore<OnboardingFeature.State, OnboardingFeature.Action>,
        revokedSnapshot: AccessStatusSnapshot,
    ) {
        let snapshot = OnboardingProgressSnapshot(
            currentStep: .permissions,
            stepState: OnboardingStepState(
                welcomeComplete: true,
                accessUnlockComplete: false,
                permissionsComplete: false,
                completeComplete: false,
            ),
            accessSnapshot: StateMutation.activeAccessSnapshot,
        )
        let revokedResponse = AccessStatusResponse(
            hasAccess: false,
            status: "revoked",
            reason: "revoked_entitlement",
            source: "polar",
        )
        let revokedSnapshot = AccessStatusSnapshot(status: .revoked, fetchedAt: testDate)
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.resumingAndRecording(
                snapshot: snapshot,
                saveRecorder: saveRecorder,
            )
            $0.accountSessionClient = AccountSessionClient(
                read: { AccountSession(accessToken: "test-token", status: .coreLicenseActive) },
                persist: { _ in },
                delete: { _ in },
            )
            $0.authNetworkClient = AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { revokedResponse },
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
                refreshToken: { throw AccessError.notConfigured },
            )
            $0.accessStatusSnapshotClient = AccessSnapshotClient.recording(
                recorder: accessSnapshotRecorder,
                load: StateMutation.activeAccessSnapshot,
            )
            $0.date = .constant(testDate)
        }
        return (store, revokedSnapshot)
    }

    // ONB-001-resume_onboarding_session: active snapshot이 있어도 세션이 없으면 후속 step에 머물지 않고 Access step으로 되돌린다.
    // 저장된 access completion만으로 후속 단계 진행을 허용하지 않는 VOY-299 계약을 검증합니다.
    // - 검증 내용: `currentStep=.aiProviderSetup`, active access snapshot 복원 후 session=nil이면 accessUnlock로 rollback 저장.
    // - 사전 조건: 저장 snapshot은 access/permissions 완료와 active access snapshot을 포함하지만 계정 세션은 없습니다.
    // - 기대 결과: `currentStep=.accessUnlock`, `accessUnlockComplete=false`, 저장 snapshot도 accessUnlock입니다.

    // ONB-001-resume_onboarding_session: 신선한 session 및 device-binding 증명이 있는 복원 snapshot은 live access 확인 없이 AI
    // Provider 단계로 재개한다.
    // 개발 host의 restored-access fixture가 이미 검증된 access를 다시 조회하거나 bind하지 않고 온보딩 진행 상태를 복원하는지 검증합니다.
    // - 검증 내용: 검증된 snapshot은 `hydrateLaunchSnapshot`으로 전달되고 fetch/bind dependency를 호출하지 않습니다.
    // - 사전 조건: active 상태, 미래 session 만료, 고정 fetchedAt 및 같은 시각의 device-binding 증명을 가진 AI Provider 단계 snapshot입니다.
    // - 기대 결과: access 완료와 AI Provider 단계가 보존되며 fetch/bind 호출 수는 모두 0입니다.

    // ONB-001-resume_onboarding_session: 만료된 session 증명이 있는 access snapshot은 완료된 온보딩 상태를 복원하지 않는다.
    // 오래된 session expiry가 저장된 access 완료 flag보다 우선하여 안전한 Access 단계로 되돌아가는지 검증합니다.
    // - 검증 내용: 과거 `sessionExpiresAt`를 가진 active snapshot은 access completion을 unlock하지 않습니다.
    // - 사전 조건: active 상태와 binding proof는 있지만 session expiry가 현재 시각보다 과거인 AI Provider 단계 snapshot입니다.
    // - 기대 결과: currentStep은 accessUnlock이고 accessUnlockComplete는 false입니다.

    // ONB-001-resume_onboarding_session: 만료된 currentPeriodEnd를 가진 access snapshot은 완료된 온보딩 상태를 복원하지 않는다.
    // entitlement period가 이미 지난 snapshot이 trusted hydration으로 live 재검증을 건너뛰는 것을 방지하는지 검증합니다.
    // - 검증 내용: 과거 `currentPeriodEnd`를 가진 active snapshot은 access completion을 unlock하지 않습니다.
    // - 사전 조건: active 상태, 미래 session 만료, 일치하는 binding proof를 가지지만 `currentPeriodEnd`가 현재 시각보다 과거인 AI Provider 단계
    // snapshot입니다.
    // - 기대 결과: currentStep은 accessUnlock이고 accessUnlockComplete는 false입니다.

    // ONB-001-resume_onboarding_session: fetchedAt와 다른 binding proof 시각의 access snapshot은 완료된 온보딩 상태를 복원하지 않는다.
    // 저장 시점과 binding 검증 시점이 일치하지 않는 proof가 access 완료를 다시 열지 않는지 검증합니다.
    // - 검증 내용: `deviceBindingVerifiedAt != fetchedAt`인 active snapshot은 access completion을 unlock하지 않습니다.
    // - 사전 조건: session expiry는 미래지만 binding proof가 fetchedAt보다 오래된 AI Provider 단계 snapshot입니다.
    // - 기대 결과: currentStep은 accessUnlock이고 accessUnlockComplete는 false입니다.

    // ONB-001-resume_onboarding_session: stale access snapshot과 server-canonical blocked 결과가 충돌하면 blocked 결과를 세션에
    // 반영한다.
    // 재진입 중 저장된 완료 snapshot만으로 진행하지 않고 ONB-002가 다시 확인한 server-canonical access status를 우선하는지 검증합니다.
    // - 검증 내용: resume 후 child access refresh가 `revoked`를 반환하면 current step과 progress snapshot을 accessUnlock 미완료 상태로
    // 되돌립니다.
    // - 사전 조건: snapshot은 active access 결과를 포함하지만 access client는 `revoked` server-canonical 응답을 반환합니다.
    // - 기대 결과: `currentStep = .accessUnlock`, `accessUnlockComplete = false`, 저장된 access snapshot은 `revoked`입니다.

    // ONB-001-resume_onboarding_session: 손상된 stepState가 저장되어 있을 때 resume하면 welcome fallback으로 안전하게 복구한다.
    // `load`가 `.resetRequired`를 반환하면 상태가 welcome으로 초기화되고 새 스냅샷이 저장됨을 검증합니다.
    // - 검증 내용: 손상되거나 호환되지 않는 진행 상태를 감지하면 세션을 완전히 리셋합니다.
    // - 사전 조건: `load`가 `.resetRequired`를 반환합니다. `snapshotRecorder`로 저장된 스냅샷을 캡처합니다.
    // - 기대 결과: `currentStep = .welcome`, welcome만 완료, 저장된 스냅샷도 동일한 초기 상태를 반영합니다.

    /// ONB-001-resume_onboarding_session: 알 수 없는 currentStep이 저장되어 있을 때 resume하면 마지막 유효 step으로 fallback한다.
    /// 스냅샷에 유효한 단계(`.complete`)가 있지만 선행 조건이 미완료면
    /// 마지막 유효 단계로 대체됨을 검증합니다.
    /// - 검증 내용: complete/accessUnlock/permissions가 모두 미완료이면 welcome으로 fallback합니다.
    /// - 사전 조건: snapshot에 `currentStep = .complete`, welcome만 완료, 나머지 미완료가 저장되어 있습니다.
    /// - 기대 결과: `onAppear` 후 `currentStep = .accessUnlock`, welcome만 완료, accessUnlock 미완료입니다.
    func testResumeFromUnknownStepFallsBackToLastValidStep() async {
        let snapshot = OnboardingProgressSnapshot(
            currentStep: .complete,
            stepState: OnboardingStepState(
                welcomeComplete: true,
                accessUnlockComplete: false,
                permissionsComplete: false,
                completeComplete: false,
            ),
        )

        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.resuming(from: snapshot)
        }

        // complete ✗ → permissions ✗ → accessUnlock: prior chain (welcome) complete → .accessUnlock
        await store.send(.onAppear) { state in
            state.didBootstrapProgress = true
            state.currentStep = .accessUnlock
        }

        XCTAssertEqual(store.state.currentStep, .accessUnlock)
        XCTAssertTrue(store.state.isStepComplete(.welcome))
        XCTAssertFalse(store.state.isStepComplete(.accessUnlock))

        await store.finish()
    }

    // MARK: - ONB-001-complete_onboarding_session

    // 세션 완료: startUsingTapped를 통한 완료 처리, 메인 창 열기, 진행 상태 저장,
    // 재진입 시 세션 스킵, 실패/재시도/멱등성을 검증합니다.

    /// ONB-001-complete_onboarding_session: 모든 필수 step이 완료되었을 때 완료 액션을 실행하면 progress를 completed로 저장하고 main window open
    /// contract를 호출한다.
    /// 세션 완료 시 메인 창이 열리고 진행 상태가 저장되는지 검증합니다.
    /// - 검증 내용: `startUsingTapped`가 `isComplete`, `isOpeningWindow`를 설정하고
    ///   `openWindowResponse` 수신 후 메인 창 경로가 기록되며 `completeComplete`이 저장됩니다.
    /// - 사전 조건: `currentStep = .complete` 상태입니다. `snapshotRecorder`와 `pathRecorder`로
    ///   저장/열기 호출을 캡처합니다.
    /// - 기대 결과: 창이 `.defaultTabPath`로 1회 열리고, 저장된 스냅샷의 `completeComplete`이 `true`입니다.
    func testCompleteOpensWindowAndSavesProgress() async {
        let saveRecorder = LockIsolated<OnboardingProgressSnapshot?>(nil)
        let pathRecorder = PathRecorder()
        let closeRecorder = CloseRecorder()

        var initialState = OnboardingFeature.State()
        initialState.currentStep = .complete

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.recording(saveRecorder: saveRecorder)
            $0.onboardingWindowClient = WindowClient.recording(
                pathRecorder: pathRecorder,
                closeRecorder: closeRecorder,
            )
        }

        await store.send(.complete(.startUsingTapped)) { state in
            state.complete.isComplete = true
            state.complete.isOpeningWindow = true
            state.complete.openWindowError = nil
        }

        await store.receive(\.complete.openWindowResponse) { state in
            state.complete.isOpeningWindow = false
        }

        let openedPaths = await pathRecorder.snapshot()
        XCTAssertEqual(openedPaths.count, 1)
        XCTAssertEqual(openedPaths[0], .defaultTabPath)
        let savedSnapshot = saveRecorder.value
        XCTAssertEqual(savedSnapshot?.stepState.completeComplete, true)
        let closeCount = await closeRecorder.snapshot()
        XCTAssertEqual(closeCount, 1, "closeWindow should be called once after successful open")
        await store.finish()
    }

    // ONB-001-resume_onboarding_session: 이미 completed snapshot이 있을 때 앱이 시작되면 온보딩 표시를 건너뛰는 completed state를 복원한다.
    // 세션 완료 후 재진입 시 이어서 진행 세션이 완료된 상태로 건너뜀을 검증합니다.
    // - 검증 내용: 모든 단계가 완료된 스냅샷이 저장되어 있으면 `onAppear` 시 바로 complete 상태로 복원됩니다.
    // - 사전 조건: snapshot에 모든 단계가 완료(`completeComplete = true`)로 저장되어 있습니다.
    // - 기대 결과: `onAppear` 후 모든 단계가 완료 상태, `currentStep = .complete`로 복원됩니다.

    /// ONB-001-complete_onboarding_session: complete step에서 완료할 때 progress를 저장하면 completeComplete flag와 completed 상태가
    /// snapshot에 반영된다.
    /// 완료 시 모든 단계가 완료로 표시된 스냅샷이 저장되는지 검증합니다.
    /// - 검증 내용: `startUsingTapped` 후 `save()`가 호출되고 `completeComplete`과 `currentStep`이 올바르게 저장됩니다.
    /// - 사전 조건: `currentStep = .complete` 상태입니다. `snapshotRecorder`로 저장된 스냅샷을 캡처합니다.
    /// - 기대 결과: 저장된 스냅샷의 `completeComplete = true`, `currentStep = .complete`입니다.
    func testCompletionSavesCompleteStepState() async {
        let saveRecorder = LockIsolated<OnboardingProgressSnapshot?>(nil)
        let closeRecorder = CloseRecorder()

        var initialState = OnboardingFeature.State()
        initialState.currentStep = .complete

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.recording(saveRecorder: saveRecorder)
            $0.onboardingWindowClient = WindowClient.recording(
                pathRecorder: PathRecorder(),
                closeRecorder: closeRecorder,
            )
        }

        await store.send(.complete(.startUsingTapped)) { state in
            state.complete.isComplete = true
            state.complete.isOpeningWindow = true
            state.complete.openWindowError = nil
        }

        await store.receive(\.complete.openWindowResponse) { state in
            state.complete.isOpeningWindow = false
        }

        let saved = saveRecorder.value
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.stepState.completeComplete, true)
        XCTAssertEqual(saved?.currentStep, .complete)
        let closeCount = await closeRecorder.snapshot()
        XCTAssertEqual(closeCount, 1, "closeWindow should be called after successful completion")

        await store.finish()
    }

    /// ONB-001-complete_onboarding_session: main window open이 실패할 때 완료 액션을 실행하면 완료로 위장하지 않고 retry 가능한 error state를
    /// 표시한다.
    /// `openMainWindow`가 `false`를 반환하면 에러 상태가 설정됨을 검증합니다.
    /// - 검증 내용: 창 열기 실패 시 `openWindowError`에 사용자 친화적 메시지가 설정됩니다.
    /// - 사전 조건: `currentStep = .complete` 상태입니다. `openMainWindow`가 항상 `false`를 반환합니다.
    /// - 기대 결과: `openWindowResponse` 수신 후 `isOpeningWindow = false`,
    ///   `openWindowError`에 에러 메시지가 설정됩니다.
    func testCompletionOpenWindowFailureShowsError() async {
        let closeRecorder = CloseRecorder()
        let pathRecorder = PathRecorder()

        var initialState = OnboardingFeature.State()
        initialState.currentStep = .complete

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.noOp
            $0.onboardingWindowClient = WindowClient.recordingFailure(
                pathRecorder: pathRecorder,
                closeRecorder: closeRecorder,
            )
        }

        await store.send(.complete(.startUsingTapped)) { state in
            state.complete.isComplete = true
            state.complete.isOpeningWindow = true
            state.complete.openWindowError = nil
        }

        await store.receive(\.complete.openWindowResponse) { state in
            state.complete.isOpeningWindow = false
            state.complete.openWindowError = "We couldn't open a file manager window. Please try again."
        }

        XCTAssertNotNil(store.state.complete.openWindowError)
        XCTAssertFalse(store.state.complete.isOpeningWindow)
        let closeCount = await closeRecorder.snapshot()
        XCTAssertEqual(closeCount, 0, "closeWindow should NOT be called when openMainWindow fails")

        await store.finish()
    }

    /// ONB-001-complete_onboarding_session: 이전 completion이 실패했을 때 사용자가 재시도하면 성공 시 completed snapshot과 window open
    /// contract를 회복한다.
    /// 완료 실패 후 `retryTapped`가 창 열기를 재시도하는지 검증합니다.
    /// - 검증 내용: 에러 상태에서 재시도 시 `openWindowError`가 초기화되고 창이 다시 열립니다.
    /// - 사전 조건: `currentStep = .complete`, `isComplete = true`,
    ///   `openWindowError`에 기존 에러 메시지가 설정되어 있습니다.
    /// - 기대 결과: 재시도 성공 후 `openWindowError = nil`, `pathRecorder`에 1개의 경로가 기록됩니다.
    func testCompletionRetryAfterFailure() async {
        let pathRecorder = PathRecorder()
        let closeRecorder = CloseRecorder()
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .complete
        initialState.complete.isComplete = true
        initialState.complete.openWindowError = "We couldn't open a file manager window. Please try again."

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.noOp
            $0.onboardingWindowClient = WindowClient.recording(
                pathRecorder: pathRecorder,
                closeRecorder: closeRecorder,
            )
        }

        await store.send(.complete(.retryTapped)) { state in
            state.complete.isOpeningWindow = true
            state.complete.openWindowError = nil
        }

        await store.receive(\.complete.openWindowResponse) { state in
            state.complete.isOpeningWindow = false
        }

        XCTAssertNil(store.state.complete.openWindowError)
        let paths = await pathRecorder.snapshot()
        XCTAssertEqual(paths.count, 1)
        let closeCount = await closeRecorder.snapshot()
        XCTAssertEqual(closeCount, 1, "closeWindow should be called after successful retry")

        await store.finish()
    }

    /// ONB-001-complete_onboarding_session: 이미 완료된 상태일 때 completion을 다시 처리하면 completed state를 안정적으로 유지한다.
    /// 멱등적 완료 — `startUsingTapped`를 두 번 호출해도 `isComplete`가 일관되게 유지됨을 검증합니다.
    /// - 검증 내용: 두 번째 호출 시에도 동일한 상태 변화(`isOpeningWindow`, `openWindowError = nil`)가 발생합니다.
    /// - 사전 조건: `currentStep = .complete` 상태입니다. `pathRecorder`로 창 열기 호출을 캡처합니다.
    /// - 기대 결과: 두 시도 모두 창을 열어(`paths.count = 2`), 최종적으로 `isComplete = true`입니다.
    func testIdempotentCompletion() async {
        let pathRecorder = PathRecorder()
        let closeRecorder = CloseRecorder()

        var initialState = OnboardingFeature.State()
        initialState.currentStep = .complete

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.noOp
            $0.onboardingWindowClient = WindowClient.recording(
                pathRecorder: pathRecorder,
                closeRecorder: closeRecorder,
            )
        }

        await store.send(.complete(.startUsingTapped)) { state in
            state.complete.isComplete = true
            state.complete.isOpeningWindow = true
            state.complete.openWindowError = nil
        }
        await store.receive(\.complete.openWindowResponse) { state in
            state.complete.isOpeningWindow = false
        }

        await store.send(.complete(.startUsingTapped)) { state in
            state.complete.isOpeningWindow = true
            state.complete.openWindowError = nil
        }
        await store.receive(\.complete.openWindowResponse) { state in
            state.complete.isOpeningWindow = false
        }

        let paths = await pathRecorder.snapshot()
        XCTAssertEqual(paths.count, 2)
        XCTAssertTrue(store.state.complete.isComplete)
        let closeCount = await closeRecorder.snapshot()
        XCTAssertEqual(closeCount, 2, "closeWindow should be called for each successful completion")

        await store.finish()
    }

    /// ONB-001-complete_onboarding_session: 완료 시 save → openMainWindow → closeWindow 순서로 호출된다.
    /// Parent reducer가 save, openMainWindow, closeWindow를 올바른 순서로 실행하는지 검증합니다.
    /// - 검증 내용: `startUsingTapped` 후 save가 먼저 실행되고, openMainWindow가 호출된 뒤 closeWindow가 호출됩니다.
    /// - 사전 조건: `currentStep = .complete` 상태입니다.
    /// - 기대 결과: saveRecorder에 `completeComplete = true` 스냅샷, pathRecorder에 `.defaultTabPath`,
    ///   closeRecorder에 1회 close가 순서대로 기록됩니다.
    func testOrderedSequenceSaveOpenClose() async {
        let saveRecorder = LockIsolated<OnboardingProgressSnapshot?>(nil)
        let pathRecorder = PathRecorder()
        let closeRecorder = CloseRecorder()
        let eventLog = EventLogSyncBox()

        var initialState = OnboardingFeature.State()
        initialState.currentStep = .complete

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.recording(
                saveRecorder: saveRecorder,
                eventLog: eventLog,
            )
            $0.onboardingWindowClient = WindowClient.recording(
                pathRecorder: pathRecorder,
                closeRecorder: closeRecorder,
                eventLog: eventLog,
            )
        }

        await store.send(.complete(.startUsingTapped)) { state in
            state.complete.isComplete = true
            state.complete.isOpeningWindow = true
            state.complete.openWindowError = nil
        }

        await store.receive(\.complete.openWindowResponse) { state in
            state.complete.isOpeningWindow = false
        }

        let savedSnapshot = saveRecorder.value
        XCTAssertNotNil(savedSnapshot, "Snapshot should be saved before opening main window")
        XCTAssertEqual(savedSnapshot?.stepState.completeComplete, true)

        let openedPaths = await pathRecorder.snapshot()
        XCTAssertEqual(openedPaths.count, 1, "openMainWindow should be called once")
        XCTAssertEqual(openedPaths[0], .defaultTabPath)

        let closeCount = await closeRecorder.snapshot()
        XCTAssertEqual(closeCount, 1, "closeWindow should be called after successful openMainWindow")

        XCTAssertEqual(
            eventLog.snapshot(),
            ["save", "open", "close"],
            "save → openMainWindow → closeWindow 순서로 실행되어야 합니다",
        )

        await store.finish()
    }

    /// ONB-001-complete_onboarding_session: openMainWindow가 실패하면 closeWindow가 호출되지 않는다.
    /// 실패 시 온보딩 창이 닫히지 않음을 검증합니다.
    /// - 검증 내용: `openMainWindow`가 `false`를 반환하면 `closeWindow`가 호출되지 않습니다.
    /// - 사전 조건: `currentStep = .complete` 상태입니다. `openMainWindow`가 `false`를 반환합니다.
    /// - 기대 결과: `closeRecorder.snapshot() == 0`, 에러 상태가 설정됩니다.
    func testFailureDoesNotCloseOnboardingWindow() async {
        let closeRecorder = CloseRecorder()
        let pathRecorder = PathRecorder()

        var initialState = OnboardingFeature.State()
        initialState.currentStep = .complete

        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = ProgressClient.noOp
            $0.onboardingWindowClient = WindowClient.recordingFailure(
                pathRecorder: pathRecorder,
                closeRecorder: closeRecorder,
            )
        }

        await store.send(.complete(.startUsingTapped)) { state in
            state.complete.isComplete = true
            state.complete.isOpeningWindow = true
            state.complete.openWindowError = nil
        }

        await store.receive(\.complete.openWindowResponse) { state in
            state.complete.isOpeningWindow = false
            state.complete.openWindowError = "We couldn't open a file manager window. Please try again."
        }

        let closeCount = await closeRecorder.snapshot()
        XCTAssertEqual(closeCount, 0, "closeWindow must NOT be called when openMainWindow returns false")
        XCTAssertNotNil(store.state.complete.openWindowError)

        await store.finish()
    }

    // ONB-001-complete_onboarding_session: ONB-001:resume_onboarding_session — completed session으로 재진입할 때 state를 복원하면
    // completion 상태와 complete step 표시가 일치한다.
    // 재진입: 이미 온보딩을 완료한 사용자가 다시 실행하면
    // 세션이 완전히 완료된 상태로 로드되고 `isSessionComplete`이 `true`임을 검증합니다.
    // - 검증 내용: 모든 단계 완료 스냅샷 복원 후 `isSessionComplete`이 올바르게 설정됩니다.
    // - 사전 조건: snapshot에 모든 단계가 완료로 저장되어 있습니다.
    // - 기대 결과: `isSessionComplete = true`, `currentStep = .complete`, 모든 단계 완료 상태입니다.

    // MARK: - ONB-001-access_snapshot_persistence

    // Access 완료 상태의 스냅샷 저장 및 복원을 검증합니다.
    // 민감 입력값은 onboarding progress에 저장하지 않고 server-canonical access snapshot만 저장합니다.

    /// ONB-001:access_snapshot_persistence — access가 완료된 상태에서 snapshot을 생성하면 access snapshot이 포함된다.
    func testProgressSnapshotIncludesAccessSnapshotWhenAccessComplete() {
        var state = OnboardingFeature.State()
        StateMutation.applyPersistedCompletedAccessStep(state: &state)

        let snapshot = state.progressSnapshot

        XCTAssertEqual(snapshot.accessSnapshot, StateMutation.activeAccessSnapshot)
        XCTAssertTrue(snapshot.stepState.accessUnlockComplete)
    }

    // ONB-001:access_snapshot_persistence — access snapshot이 없는 완료 flag는 복원 시 accessUnlock 단계로 되돌린다.

    /// ONB-001:access_snapshot_persistence — legacy credential 필드가 남은 JSON도 안전하게 디코딩된다.
    func testLegacyCredentialFieldsDecodeSafely() throws {
        let json = """
        {
            "welcomeComplete": true,
            "betaAccessComplete": true,
            "permissionsComplete": false,
            "completeComplete": false,
            "betaAccessEmail": "user@test.com",
            "betaAccessToken": "valid-token"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let stepState = try JSONDecoder().decode(OnboardingStepState.self, from: data)

        XCTAssertTrue(stepState.welcomeComplete)
        XCTAssertTrue(stepState.accessUnlockComplete)
        XCTAssertFalse(stepState.permissionsComplete)
        XCTAssertFalse(stepState.completeComplete)
    }
}
