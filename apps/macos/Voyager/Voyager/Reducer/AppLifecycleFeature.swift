import AppKit
import ComposableArchitecture
import Foundation
import Logging
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesAccountAccess
import VoyagerPagesOnboarding
import VoyagerShared

@Reducer
struct AppLifecycleFeature {
    typealias State = AppLifecycleState
    typealias Action = AppLifecycleAction

    @Dependency(\.helperAppClient)
    var helperAppClient
    @Dependency(\.helperStateClient)
    var helperStateClient
    @Dependency(\.appearanceSettingsClient)
    var appearanceSettingsClient
    @Dependency(\.onboardingWindowClient)
    var onboardingWindowClient
    @Dependency(\.userDefaultsClient)
    var userDefaultsClient
    @Dependency(\.quitConfirmationClient)
    var quitConfirmationClient
    @Dependency(\.appTerminationReplyClient)
    var appTerminationReplyClient
    @Dependency(\.uuid)
    var uuid
    @Dependency(\.authNetworkClient)
    var authNetwork
    @Dependency(\.accountSessionClient)
    var accountSessionClient
    @Dependency(\.accessStatusSnapshotClient)
    var snapshotClient
    @Dependency(\.unlockSurfaceWindowClient)
    var unlockSurfaceWindowClient
    @Dependency(\.date)
    var date
    @Dependency(\.continuousClock)
    var clock
    @Dependency(\.notificationCenterClient)
    var notificationCenterClient

    private enum CancelID {
        static let helperMonitor = "helperMonitor"
        static let accessCheck = "accessCheck"
        static let terminationCleanupTimeout = "terminationCleanupTimeout"
        static let sessionExpirationObserver = "sessionExpirationObserver"
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            // MARK: - Launch

            case .launch(.willFinishLaunching):
                let theme = appearanceSettingsClient.loadTheme()
                appearanceSettingsClient.applyThemeSync(theme)

                let notificationCenterClient = notificationCenterClient

                if isRunningXCTest() {
                    return observeSessionExpirationEffect(notificationCenterClient: notificationCenterClient)
                }

                try? EnvironmentLoader.loadEnvFiles()
                let userId = DeviceIdentifierProvider.current()
                let appVersion = AppVersionInfo.shortVersion
                SentryBootstrap.startIfNeeded(
                    appVersion: appVersion,
                    userId: userId,
                    component: "app",
                )
                VoyagerSentryMetricLogger.setUserId(userId)
                return observeSessionExpirationEffect(notificationCenterClient: notificationCenterClient)

            case .launch(.didFinishLaunching):
                state.didFinishLaunching = true
                if isRunningXCTest() {
                    return .none
                }
                if onboardingWindowClient.showIfNeeded() {
                    return .none
                }
                return .send(.accountAccessGate(.checkAccessStatus))

            case let .launch(.appReopen(hasVisibleWindows: flag)):
                if onboardingWindowClient.showIfNeeded() {
                    return .none
                }
                // PR #295: sessionLapseGuard가 있으면 오버레이를 마운트할 FileManager 창이 필요하다.
                // accountAccessGateResolved=false 경로가 이를 차단하면 빈 창에서 가드가 보이지 않는다.
                if state.sessionLapseGuard != nil {
                    return .send(.delegate(.reopenWindowIfNeeded(hasVisibleWindows: flag)))
                }
                if !state.accountAccessGateResolved {
                    return .none
                }
                guard state.lastAccessStatus?.isActive == true else {
                    return .none
                }
                return .send(.delegate(.reopenWindowIfNeeded(hasVisibleWindows: flag)))

            // MARK: - Access Gate

            case .accountAccessGate(.checkAccessStatus):
                state.isCheckingAccountAccess = true
                let authNetwork = authNetwork
                return .run { send in
                    do {
                        let response = try await authNetwork.fetchAccessStatus()
                        await send(.accountAccessGate(.accessStatusResponse(.success(response))))
                    } catch let error as AccessError {
                        await send(.accountAccessGate(.accessStatusResponse(.failure(error))))
                    } catch {
                        await send(.accountAccessGate(.accessStatusResponse(.failure(.networkFailure))))
                    }
                }
                .cancellable(id: CancelID.accessCheck, cancelInFlight: true)

            case let .accountAccessGate(.accessStatusResponse(.success(response))):
                state.isCheckingAccountAccess = false
                let accessStatus = response.toAccessStatus()
                state.lastAccessStatus = accessStatus
                state.accountAccessGateResolved = true

                if accessStatus.isActive {
                    // 활성 접근 권한: 스냅샷 생성 시 세션 만료 시점을 함께 반영한다.
                    // authNetwork가 반환한 accessStatus를 그대로 사용하며,
                    // 세션 읽기 실패/미존재는 access gate에 영향을 주지 않는다 (sessionExpiresAt == nil).
                    let accountSessionClient = accountSessionClient
                    let dateNow = date.now
                    return .run { send in
                        let sessionExpiresAt = await (try? accountSessionClient.read())?.expiresAt
                        let snapshot = AccessStatusSnapshot(
                            status: accessStatus,
                            currentPeriodEnd: response.currentPeriodEnd,
                            fetchedAt: dateNow,
                            sessionExpiresAt: sessionExpiresAt,
                        )
                        await send(.accountAccessGate(.accountAccessGranted(snapshot: snapshot)))
                    }
                } else {
                    return .send(.accountAccessGate(.showUnlockSurface))
                }

            case let .accountAccessGate(.accessStatusResponse(.failure(error))):
                guard error == .networkFailure else {
                    return .send(.accountAccessGate(.showUnlockSurface))
                }
                let snapshotClient = snapshotClient
                let accountSessionClient = accountSessionClient
                let dateNow = date.now
                return .run { send in
                    guard let cached = await snapshotClient.load(),
                          cached.isActive,
                          dateNow.timeIntervalSince(cached.fetchedAt) <= 24 * 3600,
                          cached.currentPeriodEnd.map({ dateNow < $0 }) ?? true
                    else {
                        await send(.accountAccessGate(.showUnlockSurface))
                        return
                    }
                    // session은 token file 기반으로 access_status 캐시와 무관하게
                    // 변경될 수 있어 복원 시점에 다시 읽는다. status/currentPeriodEnd/
                    // fetchedAt은 캐시 값을 유지하고 sessionExpiresAt 축만 최신화.
                    // read 실패/미존재는 success path와 동일하게 nil로 흡수 → gate 정책은 그대로 유지.
                    let sessionExpiresAt = await (try? accountSessionClient.read())?.expiresAt
                    let restored = AccessStatusSnapshot(
                        status: cached.status,
                        currentPeriodEnd: cached.currentPeriodEnd,
                        fetchedAt: cached.fetchedAt,
                        sessionExpiresAt: sessionExpiresAt,
                    )
                    await send(.accountAccessGate(.accountAccessGranted(snapshot: restored)))
                }

            case .accountAccessGate(.showUnlockSurface):
                state.isCheckingAccountAccess = false
                state.accountAccessGateResolved = true
                let unlockSurfaceClient = unlockSurfaceWindowClient
                return .run { _ in
                    await unlockSurfaceClient.showWindow()
                }

            case let .accountAccessGate(.accountAccessGranted(snapshot)):
                let snapshotClient = snapshotClient

                let saveEffect: Effect<Action> = .run { _ in
                    await snapshotClient.save(snapshot)
                }

                state.lastAccessStatus = snapshot.status
                state.accountAccessGateResolved = true
                state.isCheckingAccountAccess = false

                var effects: [Effect<Action>] = [saveEffect]

                if !state.didStartHelper {
                    state.didStartHelper = true
                    effects.append(helperMonitorEffect(
                        helperClient: helperAppClient,
                        stateClient: helperStateClient,
                    ))
                }

                effects.append(.send(.delegate(.openInitialWindowIfNeeded)))

                return .merge(effects)

            // MARK: - Termination

            case .termination(.requestTermination):
                guard state.terminationAttemptID == nil else {
                    return .none
                }

                let attemptID = uuid()
                state.terminationAttemptID = attemptID

                let shouldAlert = userDefaultsClient.bool(SettingsKeys.alertBeforeQuit)
                guard shouldAlert else {
                    return .send(.termination(.startTerminationCleanup(attemptID: attemptID)))
                }

                let quitConfirmationClient = quitConfirmationClient
                return .run { send in
                    let result = await quitConfirmationClient.confirmQuit(false, shouldAlert)
                    await send(.termination(.quitConfirmationResponse(attemptID: attemptID, result: result)))
                }

            case let .termination(.quitConfirmationResponse(attemptID: attemptID, result: result)):
                guard state.terminationAttemptID == attemptID else {
                    return .none
                }

                userDefaultsClient.setBool(result.isAlertBeforeQuitEnabled, SettingsKeys.alertBeforeQuit)

                guard result.shouldQuit else {
                    state.terminationAttemptID = nil

                    let appTerminationReplyClient = appTerminationReplyClient
                    return .run { _ in
                        await VoyagerTerminationCoordinator.shared.end()
                        await appTerminationReplyClient.reply(false)
                    }
                }

                return .send(.termination(.startTerminationCleanup(attemptID: attemptID)))

            case let .termination(.startTerminationCleanup(attemptID: attemptID)):
                guard state.terminationAttemptID == attemptID else {
                    return .none
                }

                let clock = clock

                return .merge(
                    .run { send in
                        await VoyagerTerminationCoordinator.shared.begin(.userQuit)
                        await send(.termination(.willTerminate))
                        await send(.termination(.completeTerminationAttempt(
                            attemptID: attemptID,
                            shouldTerminate: true,
                        )))
                    },
                    .run { send in
                        try await clock.sleep(for: .seconds(5))
                        await send(.termination(.completeTerminationAttempt(
                            attemptID: attemptID,
                            shouldTerminate: true,
                        )))
                    }
                    .cancellable(id: CancelID.terminationCleanupTimeout, cancelInFlight: true),
                )

            case let .termination(.completeTerminationAttempt(attemptID: attemptID, shouldTerminate: shouldTerminate)):
                guard state.terminationAttemptID == attemptID else {
                    return .none
                }

                state.terminationAttemptID = nil

                let appTerminationReplyClient = appTerminationReplyClient
                return .merge(
                    .cancel(id: CancelID.terminationCleanupTimeout),
                    .run { _ in
                        await appTerminationReplyClient.reply(shouldTerminate)
                    },
                )

            case let .sessionExpiredDetected(reason):
                // accountSessionDidEnd notification 수신. 명시적 로그아웃(signOut → AccountSessionClient.delete)
                // 와 세션 만료(refresh/decoding 실패) 양쪽이 모두 이 notification을 post하므로
                // 두 원인이 같은 경로로 전달된다. T5에서 reason 구분이 추가되었으며,
                // 두 경우 모두 동일하게 guard를 표시한다 (PRESERVED 동작).
                state.lastAccessStatus = nil
                state.accountAccessGateResolved = false
                guard state.sessionLapseGuard == nil else { return .none }
                // ACC-003: 온보딩 윈도우가 활성 상태이면 세션 만료/로그아웃 보호를 스킵한다
                guard !onboardingWindowClient.isRequired() else { return .none }
                state.sessionEndReason = reason
                var sessionLapseGuard = AccountAccessFeature.State()
                sessionLapseGuard.handoffContext = .paywall
                state.sessionLapseGuard = sessionLapseGuard
                return .send(.sessionLapseGuard(.onAppear))

            case .termination(.willTerminate):
                return .merge(
                    .cancel(id: CancelID.helperMonitor),
                    .cancel(id: CancelID.sessionExpirationObserver),
                )

            case .delegate(.startHelperIfNeeded):
                return .none

            case .delegate:
                return .none

            default:
                return .none
            }
        }
        .ifLet(\.sessionLapseGuard, action: \.sessionLapseGuard) {
            AccountAccessFeature()
        }

        Reduce { state, action in
            switch action {
            case let .sessionLapseGuard(.delegate(.unlocked(snapshot))):
                state.lastAccessStatus = snapshot.status
                state.accountAccessGateResolved = true
                state.sessionLapseGuard = nil
                return .none
            default:
                return .none
            }
        }
    }
}

private func helperMonitorEffect(
    helperClient: HelperAppClient,
    stateClient: HelperStateClient,
) -> Effect<AppLifecycleAction> {
    .run { _ in
        let currentBundleVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String

        async let monitor: Void = {
            var policy = HelperSupervisionPolicy()

            for await _ in helperClient.terminationEvents() {
                if await VoyagerTerminationCoordinator.shared.isTerminating() {
                    continue
                }

                let decision = policy.recordRestartAttempt()

                switch decision {
                case .allowed:
                    await helperClient.ensureRunning()

                case let .cooldown(activeUntil):
                    policy = await waitAndRetryIfNeeded(
                        policy: policy,
                        helperClient: helperClient,
                        activeUntil: activeUntil,
                    )

                case let .graceWindow(activeUntil):
                    policy = await waitAndRetryIfNeeded(
                        policy: policy,
                        helperClient: helperClient,
                        activeUntil: activeUntil,
                    )
                }
            }
        }()

        let initialState = await helperClient.resolveAlignedState(
            stateClient: stateClient,
            mainBundleVersion: currentBundleVersion,
        )
        _ = initialState
        _ = await monitor
    }
    .cancellable(id: "helperMonitor", cancelInFlight: true)
}

private func waitAndRetryIfNeeded(
    policy: HelperSupervisionPolicy,
    helperClient: HelperAppClient,
    activeUntil: Date,
) async -> HelperSupervisionPolicy {
    var policy = policy
    let delay = activeUntil.timeIntervalSinceNow
    if delay > 0 {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        let isRunning = await helperClient.isRunning()
        if !isRunning {
            let newDecision = policy.recordRestartAttempt()
            if case .allowed = newDecision {
                await helperClient.ensureRunning()
            }
        }
    }
    return policy
}

private func isRunningXCTest() -> Bool {
    // TODO(VOY-432): ProcessInfo 대신 Dotenv 사용 검토 — https://linear.app/voyager-fm/issue/VOY-432
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}

/// accountSessionDidEnd notification을 관찰한다. 이 notification은 명시적 로그아웃과
/// 세션 만료 양쪽에서 post되므로, effect 이름(sessionExpiration)과 무관하게 두 경우를 모두 수신한다.
/// notification userInfo에서 AccountSessionEndReason을 추출하여 action에 전달한다.
private func observeSessionExpirationEffect(
    notificationCenterClient: NotificationCenterClient,
) -> Effect<AppLifecycleAction> {
    .run { send in
        for await notification in notificationCenterClient.notifications(
            .accountSessionDidEnd,
            nil,
        ) {
            let reasonRaw = notification.userInfo?[AccountSessionClient.sessionEndReasonUserInfoKey] as? String
            let reason = reasonRaw.flatMap(AccountSessionEndReason.init(rawValue:))
            await send(.sessionExpiredDetected(reason: reason))
        }
    }
    .cancellable(id: "sessionExpirationObserver", cancelInFlight: true)
}

actor VoyagerTerminationCoordinator {
    static let shared = VoyagerTerminationCoordinator()

    enum Reason {
        case userQuit
        case sparkleRelaunch
    }

    private var reason: Reason?

    func begin(_ reason: Reason) {
        self.reason = reason
    }

    func end() {
        reason = nil
    }

    func isTerminating() -> Bool {
        reason != nil
    }
}
