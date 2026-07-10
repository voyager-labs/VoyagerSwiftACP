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
    @Dependency(\.date)
    var date
    @Dependency(\.continuousClock)
    var clock
    @Dependency(\.notificationCenterClient)
    var notificationCenterClient
    @Dependency(\.deviceIdentityClient)
    var deviceIdentityClient

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
                let generation = state.beginAccessCheck()
                let authNetwork = authNetwork
                return .run { send in
                    do {
                        let response = try await authNetwork.fetchAccessStatus()
                        await send(.accountAccessGate(.accessStatusResponse(
                            generation: generation,
                            result: .success(response),
                        )))
                    } catch let error as AccessError {
                        await send(.accountAccessGate(.accessStatusResponse(
                            generation: generation,
                            result: .failure(error),
                        )))
                    } catch {
                        await send(.accountAccessGate(.accessStatusResponse(
                            generation: generation,
                            result: .failure(.networkFailure),
                        )))
                    }
                }
                .cancellable(id: CancelID.accessCheck, cancelInFlight: true)

            case let .accountAccessGate(.accessStatusResponse(generation: generation, result: .success(response))):
                guard state.isCurrentAccessGateGeneration(generation) else { return .none }
                let accessStatus = response.toAccessStatus()
                state.lastAccessStatus = accessStatus
                state.accountAccessGateResolved = false

                if accessStatus.isActive {
                    state.isCheckingAccountAccess = true
                    let accountSessionClient = accountSessionClient
                    let authNetwork = authNetwork
                    let deviceIdentityClient = deviceIdentityClient
                    let dateNow = date.now
                    return .run { send in
                        let sessionExpiresAt = await (try? accountSessionClient.read())?.expiresAt
                        let snapshot = AccessStatusSnapshot.fetchResult(
                            status: accessStatus,
                            currentPeriodEnd: response.currentPeriodEnd,
                            sessionExpiresAt: sessionExpiresAt,
                            fetchedAt: dateNow,
                        )
                        guard snapshot.hasSession else {
                            await send(.accountAccessGate(.accessUnlockRequired(
                                generation: generation,
                                snapshot: snapshot,
                            )))
                            return
                        }

                        let result: Result<DeviceBindingResponse, DeviceBindingError>
                        do {
                            let request = try DeviceBindingRequest(
                                deviceId: deviceIdentityClient.deviceId(),
                                deviceName: Host.current().localizedName,
                                appVersion: AppVersionInfo.shortVersion,
                                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                            )
                            let response = try await authNetwork.bindDevice(request)
                            result = .success(response)
                        } catch let error as DeviceBindingError {
                            result = .failure(error)
                        } catch {
                            result = .failure(.invalidDevicePayload)
                        }
                        await send(.accountAccessGate(.deviceBindingResponse(
                            generation: generation,
                            snapshot: snapshot,
                            result: result,
                        )))
                    }
                    .cancellable(id: CancelID.accessCheck, cancelInFlight: true)
                }

                state.isCheckingAccountAccess = false
                let accountSessionClient = accountSessionClient
                let dateNow = date.now
                return .run { send in
                    let sessionExpiresAt = await (try? accountSessionClient.read())?.expiresAt
                    let snapshot = AccessStatusSnapshot.fetchResult(
                        status: accessStatus,
                        currentPeriodEnd: response.currentPeriodEnd,
                        sessionExpiresAt: sessionExpiresAt,
                        fetchedAt: dateNow,
                    )
                    await send(.accountAccessGate(.accessUnlockRequired(
                        generation: generation,
                        snapshot: snapshot,
                    )))
                }

            case let .accountAccessGate(.accessStatusResponse(generation: generation, result: .failure(error))):
                guard state.isCurrentAccessGateGeneration(generation) else { return .none }
                guard error != .unauthorized else {
                    return .send(.sessionExpiredDetected(reason: .sessionExpired))
                }
                guard error == .networkFailure else {
                    let accountSessionClient = accountSessionClient
                    return .run { send in
                        let sessionExpiresAt = await (try? accountSessionClient.read())?.expiresAt
                        await send(.accountAccessGate(.accessStatusFailed(
                            generation: generation,
                            error: error,
                            sessionExpiresAt: sessionExpiresAt,
                        )))
                    }
                }
                let snapshotClient = snapshotClient
                let accountSessionClient = accountSessionClient
                let dateNow = date.now
                return .run { send in
                    guard let cached = await snapshotClient.load(),
                          cached.isActive,
                          cached.isDeviceBindingVerified,
                          dateNow.timeIntervalSince(cached.fetchedAt) <= 24 * 3600,
                          cached.currentPeriodEnd.map({ dateNow < $0 }) ?? true
                    else {
                        let sessionExpiresAt = await (try? accountSessionClient.read())?.expiresAt
                        let snapshot = AccessStatusSnapshot.fetchResult(
                            status: .networkFailure,
                            sessionExpiresAt: sessionExpiresAt,
                            fetchedAt: dateNow,
                        )
                        await send(.accountAccessGate(.accessUnlockRequired(
                            generation: generation,
                            snapshot: snapshot,
                        )))
                        return
                    }
                    // session은 token file 기반으로 access_status 캐시와 무관하게
                    // 변경될 수 있어 복원 시점에 다시 읽는다. status/currentPeriodEnd/
                    // fetchedAt은 캐시 값을 유지하고 sessionExpiresAt 축만 최신화.
                    // read 실패/미존재는 success path와 동일하게 nil로 흡수 → gate 정책은 그대로 유지.
                    let sessionExpiresAt = await (try? accountSessionClient.read())?.expiresAt
                    let restored = AccessStatusSnapshot.fetchResult(
                        status: cached.status,
                        currentPeriodEnd: cached.currentPeriodEnd,
                        sessionExpiresAt: sessionExpiresAt,
                        fetchedAt: cached.fetchedAt,
                        deviceBindingVerifiedAt: cached.deviceBindingVerifiedAt,
                    )
                    guard restored.hasSession else {
                        await send(.accountAccessGate(.accessUnlockRequired(
                            generation: generation,
                            snapshot: restored,
                        )))
                        return
                    }
                    await send(.accountAccessGate(.accountAccessGranted(
                        generation: generation,
                        snapshot: restored,
                    )))
                }

            case let .accountAccessGate(.deviceBindingResponse(
                generation: generation,
                snapshot: snapshot,
                result: result,
            )):
                guard state.isCurrentAccessGateGeneration(generation) else { return .none }
                switch result {
                case let .success(response):
                    guard response.ok else {
                        return deviceBindingFailureEffects(
                            state: &state,
                            snapshot: snapshot,
                            generation: generation,
                            error: .decodingFailure,
                        )
                    }
                    let verifiedSnapshot = AccessStatusSnapshot.fetchResult(
                        status: snapshot.status,
                        currentPeriodEnd: snapshot.currentPeriodEnd,
                        sessionExpiresAt: snapshot.sessionExpiresAt,
                        fetchedAt: snapshot.fetchedAt,
                        deviceBindingVerifiedAt: date.now,
                    )
                    return .send(.accountAccessGate(.accountAccessGranted(
                        generation: generation,
                        snapshot: verifiedSnapshot,
                    )))

                case .failure(.unauthorized):
                    return .send(.sessionExpiredDetected(reason: .sessionExpired))

                case let .failure(error):
                    return deviceBindingFailureEffects(
                        state: &state,
                        snapshot: snapshot,
                        generation: generation,
                        error: error,
                    )
                }

            case let .accountAccessGate(.accessUnlockRequired(generation: generation, snapshot: snapshot)):
                guard state.isCurrentAccessGateGeneration(generation) else { return .none }
                state.resolveAccessUnlockRequired(snapshot, generation: generation)
                var sessionLapseGuard = AccountAccessFeature.State()
                sessionLapseGuard.handoffContext = .paywall
                state.sessionLapseGuard = sessionLapseGuard
                return .merge(
                    .send(.sessionLapseGuard(.hydrateLaunchSnapshot(snapshot))),
                    .run { _ in
                        await snapshotClient.save(snapshot)
                    },
                    .send(.delegate(.openInitialWindowIfNeeded)),
                )

            case let .accountAccessGate(.accessStatusFailed(
                generation: generation,
                error: error,
                sessionExpiresAt: sessionExpiresAt,
            )):
                guard state.isCurrentAccessGateGeneration(generation) else { return .none }
                state.resolveAccessFailure(error, generation: generation)
                var sessionLapseGuard = AccountAccessFeature.State()
                sessionLapseGuard.handoffContext = .paywall
                sessionLapseGuard.hydrateAccessFailureState(
                    error: error,
                    sessionExpiresAt: sessionExpiresAt,
                )
                state.sessionLapseGuard = sessionLapseGuard
                return .merge(
                    .run { _ in
                        await snapshotClient.remove()
                    },
                    .send(.delegate(.openInitialWindowIfNeeded)),
                )

            case let .accountAccessGate(.accountAccessGranted(generation: generation, snapshot: snapshot)):
                guard state.isCurrentAccessGateGeneration(generation) else { return .none }
                guard snapshot.isActive, snapshot.hasSession, snapshot.isDeviceBindingVerified else {
                    return .send(.accountAccessGate(.accessUnlockRequired(
                        generation: generation,
                        snapshot: snapshot,
                    )))
                }
                return accountAccessGrantedEffects(
                    state: &state,
                    snapshot: snapshot,
                    generation: generation,
                    environment: AccountAccessGrantEnvironment(
                        snapshotClient: snapshotClient,
                        helperAppClient: helperAppClient,
                        helperStateClient: helperStateClient,
                    ),
                )

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
                // 두 원인이 같은 경로로 전달된다. reason은 phase에 보존하되 둘 다 guard를 표시한다.
                state.resolveSessionEnded(reason: reason)
                let cancelAccessCheck: Effect<Action> = .cancel(id: CancelID.accessCheck)
                guard state.sessionLapseGuard == nil else { return cancelAccessCheck }
                // ACC-003: 온보딩 윈도우가 활성 상태이면 세션 만료/로그아웃 보호를 스킵한다
                guard !onboardingWindowClient.isRequired() else { return cancelAccessCheck }
                var sessionLapseGuard = AccountAccessFeature.State()
                sessionLapseGuard.handoffContext = .paywall
                state.sessionLapseGuard = sessionLapseGuard
                return .merge(
                    cancelAccessCheck,
                    .send(.sessionLapseGuard(.onAppear)),
                    .send(.delegate(.openInitialWindowIfNeeded)),
                )

            case .termination(.willTerminate):
                state.invalidateAccessCheck()
                return .merge(
                    .cancel(id: CancelID.accessCheck),
                    .cancel(id: CancelID.helperMonitor),
                    .cancel(id: CancelID.sessionExpirationObserver),
                )

            case .delegate(.openInitialWindowIfNeeded):
                state.isCheckingAccountAccess = false
                if state.sessionLapseGuard == nil {
                    state.accountAccessGateResolved = true
                }
                return .none

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
                state.sessionLapseGuard = nil
                return accountAccessGrantedEffects(
                    state: &state,
                    snapshot: snapshot,
                    generation: state.accessGateGeneration + 1,
                    environment: AccountAccessGrantEnvironment(
                        snapshotClient: snapshotClient,
                        helperAppClient: helperAppClient,
                        helperStateClient: helperStateClient,
                    ),
                )
            default:
                return .none
            }
        }
    }
}

private struct AccountAccessGrantEnvironment {
    var snapshotClient: AccessStatusSnapshotClient
    var helperAppClient: HelperAppClient
    var helperStateClient: HelperStateClient
}

private func accountAccessGrantedEffects(
    state: inout AppLifecycleState,
    snapshot: AccessStatusSnapshot,
    generation: Int,
    environment: AccountAccessGrantEnvironment,
) -> Effect<AppLifecycleAction> {
    let saveEffect: Effect<AppLifecycleAction> = .run { _ in
        await environment.snapshotClient.save(snapshot)
    }

    state.accessGateGeneration = max(state.accessGateGeneration, generation)
    state.resolveAccessGranted(snapshot, generation: state.accessGateGeneration)

    var effects: [Effect<AppLifecycleAction>] = [saveEffect]

    if !state.didStartHelper {
        state.didStartHelper = true
        effects.append(helperMonitorEffect(
            helperClient: environment.helperAppClient,
            stateClient: environment.helperStateClient,
        ))
    }

    effects.append(.send(.delegate(.openInitialWindowIfNeeded)))

    return .merge(effects)
}

private func deviceBindingFailureEffects(
    state: inout AppLifecycleState,
    snapshot: AccessStatusSnapshot,
    generation: Int,
    error: DeviceBindingError,
) -> Effect<AppLifecycleAction> {
    state.resolveAccessUnlockRequired(snapshot, generation: generation)
    var sessionLapseGuard = AccountAccessFeature.State()
    sessionLapseGuard.handoffContext = .paywall
    sessionLapseGuard.fetchGeneration = generation
    sessionLapseGuard.status = snapshot.status
    sessionLapseGuard.trialExpiresAt = snapshot.currentPeriodEnd
    sessionLapseGuard.snapshot = snapshot
    sessionLapseGuard.hasAccountSession = snapshot.hasSession
    sessionLapseGuard.sessionExpiresAt = snapshot.sessionExpiresAt
    sessionLapseGuard.isSubmitting = true
    sessionLapseGuard.didBootstrap = true
    state.sessionLapseGuard = sessionLapseGuard

    return .merge(
        .send(.sessionLapseGuard(.deviceBindingResponse(
            generation: generation,
            snapshot: snapshot,
            result: .failure(error),
        ))),
        .send(.delegate(.openInitialWindowIfNeeded)),
    )
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
