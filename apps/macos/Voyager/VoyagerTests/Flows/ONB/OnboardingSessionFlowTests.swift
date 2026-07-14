// FLOW-ID: onb.onboarding_session
import ComposableArchitecture
import Dependencies
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesAccountAccess
@testable import VoyagerPagesOnboarding
import VoyagerShared
import XCTest

@MainActor
final class OnboardingSessionFlowTests: XCTestCase {
    // FLOW-PATH: happy_path

    /// ONB onboarding_session: happy_path
    /// 새 세션이 모든 production child scope를 거쳐 main window를 열고 온보딩을 닫는지 검증한다.
    /// - 검증 내용: child outcome과 각 Next 전환이 저장되고 마지막 요청이 save → open → close 순서를 따른다.
    /// - 사전 조건: 빈 progress, 활성 access projection, 승인된 권한, provider 연결 없는 상태다.
    /// - 기대 결과: Set up later 뒤 complete에 도달하고 default tab 요청 성공 후 온보딩이 닫힌다.
    func testFreshSessionCompletesAllStepsAndOpensMainWindow() async {
        let saves = LockIsolated<[OnboardingProgressSnapshot]>([])
        let events = LockIsolated<[String]>([])
        let openedRequests = LockIsolated<[OnboardingOpenMainWindowRequest]>([])
        let store = makeStore(
            progressClient: Self.progressClient(load: .empty, saves: saves, events: events),
            windowClient: Self.windowClient(
                openResults: LockIsolated([true]),
                openedRequests: openedRequests,
                events: events,
            ),
            fullDiskAccessStatus: LockIsolated(.granted),
        )
        // store.exhaustivity = .off: 각 child의 내부 bootstrap action이 아니라 aggregate 저장과 경계 순서를 검증한다.
        store.exhaustivity = .off

        await store.send(.onAppear) { $0.didBootstrapProgress = true }
        await store.send(.nextTapped) { $0.currentStep = .accessUnlock }
        await store
            .send(.accessProjectionUpdated(Self.activeAccessProjection)) { $0.access = Self.activeAccessProjection }
        await store.send(.nextTapped) { $0.currentStep = .permissions }
        await completePermissions(in: store)
        await store.send(.nextTapped) { $0.currentStep = .aiProviderSetup }
        await store.send(.aiProviderSetup(.setUpLaterTapped)) { state in
            state.aiProviderSetup.choice = .setUpLater
            state.aiProviderSetup.status = .skipped
        }
        await store.send(.nextTapped) { $0.currentStep = .complete }
        await store.send(.complete(.startUsingTapped)) { state in
            state.complete.isComplete = true
            state.complete.isOpeningWindow = true
            state.complete.openWindowError = nil
        }
        await store.receive(\.complete.openWindowResponse) { $0.complete.isOpeningWindow = false }
        await store.finish()

        XCTAssertEqual(openedRequests.value, [.defaultTabPath])
        XCTAssertTrue(saves.value.contains { $0.currentStep == .accessUnlock })
        XCTAssertTrue(saves.value.contains { $0.currentStep == .permissions })
        XCTAssertTrue(saves.value.contains { $0.currentStep == .aiProviderSetup })
        XCTAssertTrue(saves.value.contains { $0.currentStep == .complete })
        XCTAssertEqual(events.value.suffix(3), ["save", "open", "close"])
    }

    // FLOW-PATH: resume_existing_session

    /// ONB onboarding_session: resume_existing_session
    /// 저장된 후속 단계가 현재 canonical access 결과로 재검증되어 안전한 마지막 미완료 단계로 돌아가는지 검증한다.
    /// - 검증 내용: 복원은 저장된 완료 flag만 신뢰하지 않고 blocked projection 뒤 access step과 저장 snapshot을 갱신한다.
    /// - 사전 조건: 저장 progress는 permissions까지 완료로 기록됐지만 재검증 access projection은 blocked다.
    /// - 기대 결과: Next가 닫히고 current step과 최신 저장 progress가 accessUnlock으로 되돌아간다.
    func testSavedSessionResumesAtLastIncompleteStepAndRevalidatesAccess() async {
        let saves = LockIsolated<[OnboardingProgressSnapshot]>([])
        let savedSnapshot = OnboardingProgressSnapshot(
            currentStep: .aiProviderSetup,
            stepState: OnboardingStepState(
                welcomeComplete: true,
                accessUnlockComplete: true,
                permissionsComplete: true,
                completeComplete: false,
            ),
        )
        var initialState = OnboardingFeature.State()
        initialState.access = Self.activeAccessProjection
        let store = makeStore(
            initialState: initialState,
            progressClient: Self.progressClient(load: .success(savedSnapshot), saves: saves),
        )

        await store.send(.onAppear) { state in
            state.didBootstrapProgress = true
            state.currentStep = .aiProviderSetup
            state.permissions.isComplete = true
        }
        await store.send(.accessProjectionUpdated(Self.blockedAccessProjection)) { state in
            state.access = Self.blockedAccessProjection
            state.currentStep = .accessUnlock
        }
        await store.finish()

        XCTAssertFalse(store.state.canGoNext)
        XCTAssertEqual(store.state.currentStep, .accessUnlock)
        XCTAssertEqual(saves.value.last?.currentStep, .accessUnlock)
        XCTAssertFalse(saves.value.last?.stepState.accessUnlockComplete ?? true)
    }

    /// ONB onboarding_session: bootstrap 전에 받은 projection은 저장 progress를 덮어쓰지 않고 복원 뒤 최신 값으로 재조정한다.
    /// - 검증 내용: onAppear 전 projection update가 save를 발생시키지 않고, saved step과 최신 blocked projection이 accessUnlock으로
    /// reconcile된다.
    /// - 사전 조건: 저장 progress는 permissions까지 완료이고 window observer가 bootstrap 전에 blocked projection을 전달한다.
    /// - 기대 결과: load 전 save는 없고 bootstrap 뒤 저장된 snapshot은 accessUnlock 및 incomplete access를 기록한다.
    func testProjectionBeforeProgressBootstrapDefersSaveAndReconcilesLatestAccess() async {
        let saves = LockIsolated<[OnboardingProgressSnapshot]>([])
        let savedSnapshot = OnboardingProgressSnapshot(
            currentStep: .aiProviderSetup,
            stepState: OnboardingStepState(
                welcomeComplete: true,
                accessUnlockComplete: true,
                permissionsComplete: true,
                completeComplete: false,
            ),
        )
        let store = makeStore(
            progressClient: Self.progressClient(load: .success(savedSnapshot), saves: saves),
        )

        await store
            .send(.accessProjectionUpdated(Self.blockedAccessProjection)) { $0.access = Self.blockedAccessProjection }
        XCTAssertTrue(saves.value.isEmpty)

        await store.send(.onAppear) { state in
            state.didBootstrapProgress = true
            state.currentStep = .accessUnlock
            state.permissions.isComplete = true
        }
        await store.finish()

        XCTAssertEqual(saves.value.count, 1)
        XCTAssertEqual(saves.value.first?.currentStep, .accessUnlock)
        XCTAssertFalse(saves.value.first?.stepState.accessUnlockComplete ?? true)
    }

    // FLOW-PATH: access_unlock_recovery

    /// ONB onboarding_session: access_unlock_recovery
    /// access failure가 Next와 main-window 진행을 막고 canonical recovery가 완료된 뒤에만 다음 단계로 이동하는지 검증한다.
    /// - 검증 내용: blocked projection에서는 Next가 no-op이며 active projection 뒤 permissions로 진행한다.
    /// - 사전 조건: welcome은 완료됐고 access projection은 처음에 blocked다.
    /// - 기대 결과: recovery 전에는 창 요청이 없고 recovery 뒤에만 permissions 단계가 열린다.
    func testAccessRecoveryBlocksProgressUntilCanonicalAccessCompletes() async {
        let openedRequests = LockIsolated<[OnboardingOpenMainWindowRequest]>([])
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .accessUnlock
        initialState.access = Self.blockedAccessProjection
        let store = makeStore(
            initialState: initialState,
            windowClient: Self.windowClient(
                openResults: LockIsolated([true]),
                openedRequests: openedRequests,
            ),
        )

        XCTAssertFalse(store.state.canGoNext)
        await store.send(.nextTapped)
        XCTAssertEqual(store.state.currentStep, .accessUnlock)
        XCTAssertTrue(openedRequests.value.isEmpty)

        await store
            .send(.accessProjectionUpdated(Self.activeAccessProjection)) { $0.access = Self.activeAccessProjection }
        XCTAssertTrue(store.state.canGoNext)
        await store.send(.nextTapped) { $0.currentStep = .permissions }
        await store.finish()

        XCTAssertEqual(store.state.currentStep, .permissions)
        XCTAssertTrue(openedRequests.value.isEmpty)
    }

    // FLOW-PATH: permissions_recovery

    /// ONB onboarding_session: permissions_recovery
    /// permission failure가 Next를 막고 live readiness refresh가 완료된 뒤에만 AI setup으로 진행하는지 검증한다.
    /// - 검증 내용: denied Full Disk Access에서는 Next가 no-op이고 app activation refresh가 granted를 반환하면 gate가 열린다.
    /// - 사전 조건: access는 완료됐고 helper folder access는 granted이며 Full Disk Access는 처음에 denied다.
    /// - 기대 결과: live refresh 전에는 main-window 요청이 없고 refresh 뒤 AI Provider Setup으로 진행한다.
    func testPermissionRecoveryBlocksProgressUntilLiveReadinessCompletes() async {
        let fullDiskAccessStatus = LockIsolated(FullDiskAccessStatus.denied)
        let openedRequests = LockIsolated<[OnboardingOpenMainWindowRequest]>([])
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .permissions
        initialState.access = Self.activeAccessProjection
        let store = makeStore(
            initialState: initialState,
            windowClient: Self.windowClient(
                openResults: LockIsolated([true]),
                openedRequests: openedRequests,
            ),
            fullDiskAccessStatus: fullDiskAccessStatus,
        )
        // store.exhaustivity = .off: permission child의 관찰 lifecycle이 아니라 parent Next gate의 live readiness 전환을 검증한다.
        store.exhaustivity = .off

        await store.send(.permissions(.onAppear))
        await store
            .receive(\.permissions.fullDiskAccessStatusResponse) { $0.permissions.fullDiskAccessStatus = .denied }
        await store.receive(\.permissions.helperFolderAccessStatusLoaded) { state in
            state.permissions.helperFolderAccess = Self.grantedHelperAccess
            state.permissions.helperFolderAccessError = nil
        }
        await store.receive(\.permissions.launchAtLoginStateLoaded)
        await store.send(.nextTapped)
        XCTAssertEqual(store.state.currentStep, .permissions)
        XCTAssertTrue(openedRequests.value.isEmpty)

        fullDiskAccessStatus.withValue { $0 = .granted }
        await store.send(.permissions(.appDidBecomeActive)) { $0.permissions.latestAppActiveRefreshGeneration = 1 }
        await store.receive(\.permissions.fullDiskAccessRefreshResponse) { state in
            state.permissions.fullDiskAccessStatus = .granted
            state.permissions.isComplete = true
        }
        await store.receive(\.permissions.helperFolderAccessRefreshLoaded) { state in
            state.permissions.helperFolderAccess = Self.grantedHelperAccess
            state.permissions.helperFolderAccessError = nil
        }
        await store.send(.nextTapped) { $0.currentStep = .aiProviderSetup }
        await store.finish()

        XCTAssertTrue(store.state.permissions.isComplete)
        XCTAssertEqual(store.state.currentStep, .aiProviderSetup)
        XCTAssertTrue(openedRequests.value.isEmpty)
    }

    // FLOW-PATH: ai_provider_setup_later

    /// ONB onboarding_session: ai_provider_setup_later
    /// provider connection 없이 Set up later를 선택해 AI setup을 완료하고 complete 단계로 진행하는지 검증한다.
    /// - 검증 내용: 연결 client를 호출하지 않고 skipped choice를 저장한 뒤 parent Next gate를 연다.
    /// - 사전 조건: access와 permissions는 완료됐고 AI provider는 연결되지 않았다.
    /// - 기대 결과: provider connection 없이 complete 단계로 이동하고 saved choice는 setUpLater다.
    func testSetUpLaterCompletesAiStepWithoutProviderConnection() async {
        let saves = LockIsolated<[OnboardingProgressSnapshot]>([])
        var initialState = OnboardingFeature.State()
        initialState.currentStep = .aiProviderSetup
        initialState.access = Self.activeAccessProjection
        initialState.permissions.isComplete = true
        let store = makeStore(
            initialState: initialState,
            progressClient: Self.progressClient(load: .empty, saves: saves),
        )

        await store.send(.aiProviderSetup(.setUpLaterTapped)) { state in
            state.aiProviderSetup.choice = .setUpLater
            state.aiProviderSetup.status = .skipped
        }
        XCTAssertTrue(store.state.canGoNext)
        await store.send(.nextTapped) { $0.currentStep = .complete }
        await store.finish()

        XCTAssertEqual(saves.value.first?.stepState.aiProviderSetupChoice, .setUpLater)
        XCTAssertEqual(store.state.currentStep, .complete)
    }

    // FLOW-PATH: complete_failure

    /// ONB onboarding_session: complete_failure
    /// main window open 실패가 온보딩을 닫지 않고 deterministic retry가 성공 시에만 닫는지 검증한다.
    /// - 검증 내용: 첫 open false 뒤 close가 없고 retry의 true 응답 뒤 save → open → close가 기록된다.
    /// - 사전 조건: 모든 onboarding step은 완료됐고 window boundary는 false, true를 순서대로 반환한다.
    /// - 기대 결과: 실패 뒤 onboarding은 열린 채 오류를 보이며 retry 성공 후 한 번만 닫힌다.
    func testMainWindowOpenFailureKeepsOnboardingOpenAndAllowsRetry() async {
        let events = LockIsolated<[String]>([])
        let openedRequests = LockIsolated<[OnboardingOpenMainWindowRequest]>([])
        let openResults = LockIsolated([false, true])
        var initialState = Self.completedState()
        initialState.complete.openWindowError = nil
        let store = makeStore(
            initialState: initialState,
            progressClient: Self.progressClient(load: .empty, events: events),
            windowClient: Self.windowClient(
                openResults: openResults,
                openedRequests: openedRequests,
                events: events,
            ),
        )

        await store.send(.complete(.startUsingTapped)) { state in
            state.complete.isComplete = true
            state.complete.isOpeningWindow = true
            state.complete.openWindowError = nil
        }
        await store.receive(\.complete.openWindowResponse) { state in
            state.complete.isOpeningWindow = false
            state.complete.openWindowError = "We couldn't open a file manager window. Please try again."
        }
        XCTAssertFalse(events.value.contains("close"))
        XCTAssertNotNil(store.state.complete.openWindowError)

        await store.send(.complete(.retryTapped)) { state in
            state.complete.isOpeningWindow = true
            state.complete.openWindowError = nil
        }
        await store.receive(\.complete.openWindowResponse) { $0.complete.isOpeningWindow = false }
        await store.finish()

        XCTAssertEqual(openedRequests.value, [.defaultTabPath, .defaultTabPath])
        XCTAssertEqual(events.value, ["save", "open", "save", "open", "close"])
        XCTAssertNil(store.state.complete.openWindowError)
    }
}

private extension OnboardingSessionFlowTests {
    nonisolated static let grantedHelperAccess = FolderAccessResult(
        desktop: .granted,
        documents: .granted,
        downloads: .granted,
    )

    static let activeAccessProjection = OnboardingAccessProjection(
        hasAccountSession: true,
        isComplete: true,
        status: .coreLicenseActive,
        isBlocked: false,
        primaryCTA: .next,
    )

    static let blockedAccessProjection = OnboardingAccessProjection(
        hasAccountSession: true,
        isComplete: false,
        status: AccessStatus.none,
        isBlocked: true,
        primaryCTA: .webPricing,
    )

    static func completedState() -> OnboardingFeature.State {
        var state = OnboardingFeature.State()
        state.currentStep = .complete
        state.access = activeAccessProjection
        state.permissions.isComplete = true
        state.aiProviderSetup.choice = .setUpLater
        state.aiProviderSetup.status = .skipped
        return state
    }

    func makeStore(
        initialState: OnboardingFeature.State = OnboardingFeature.State(),
        progressClient: OnboardingProgressClient? = nil,
        windowClient: OnboardingWindowClient? = nil,
        fullDiskAccessStatus: LockIsolated<FullDiskAccessStatus> = LockIsolated(.granted),
    ) -> TestStore<OnboardingFeature.State, OnboardingFeature.Action> {
        TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.onboardingProgressClient = progressClient ?? Self.progressClient(load: .empty)
            $0.onboardingWindowClient = windowClient ?? Self.windowClient(openResults: LockIsolated([true]))
            $0.fullDiskAccessClient = FullDiskAccessClient(status: { fullDiskAccessStatus.value })
            $0.helperFolderAccessClient = HelperFolderAccessClient(
                checkAccess: { Self.grantedHelperAccess },
                requestAccess: { Self.grantedHelperAccess },
            )
            $0.notificationCenterClient.notifications = { _, _ in AsyncStream { $0.finish() } }
            $0.systemSettingsClient = SystemSettingsClient(openFullDiskAccess: { true })
            $0.launchAtLoginClient = LaunchAtLoginClient(isEnabled: { false }, setEnabled: { _ in })
        }
    }

    func completePermissions(in store: TestStore<OnboardingFeature.State, OnboardingFeature.Action>) async {
        await store.send(.permissions(.onAppear))
        await store.receive(\.permissions.fullDiskAccessStatusResponse) { state in
            state.permissions.fullDiskAccessStatus = .granted
            state.permissions.isComplete = false
        }
        await store.receive(\.permissions.helperFolderAccessStatusLoaded) { state in
            state.permissions.helperFolderAccess = Self.grantedHelperAccess
            state.permissions.helperFolderAccessError = nil
            state.permissions.isComplete = true
        }
        await store.receive(\.permissions.launchAtLoginStateLoaded)
    }

    static func progressClient(
        load: OnboardingProgressClient.LoadResult,
        saves: LockIsolated<[OnboardingProgressSnapshot]>? = nil,
        events: LockIsolated<[String]>? = nil,
    ) -> OnboardingProgressClient {
        OnboardingProgressClient(
            load: { load },
            save: { snapshot in
                saves?.withValue { $0.append(snapshot) }
                events?.withValue { $0.append("save") }
                return .success
            },
            reset: {},
        )
    }

    static func windowClient(
        openResults: LockIsolated<[Bool]>,
        openedRequests: LockIsolated<[OnboardingOpenMainWindowRequest]>? = nil,
        events: LockIsolated<[String]>? = nil,
    ) -> OnboardingWindowClient {
        OnboardingWindowClient(
            isRequired: { false },
            showIfNeeded: { false },
            showWindow: {},
            closeWindow: {
                events?.withValue { $0.append("close") }
            },
            openMainWindow: { request in
                openedRequests?.withValue { $0.append(request) }
                events?.withValue { $0.append("open") }
                return openResults.withValue { $0.removeFirst() }
            },
        )
    }
}
