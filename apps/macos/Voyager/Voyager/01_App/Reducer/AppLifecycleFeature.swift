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
    @Dependency(\.accessStatusSnapshotClient)
    var snapshotClient
    @Dependency(\.unlockSurfaceWindowClient)
    var unlockSurfaceWindowClient
    @Dependency(\.date)
    var date
    @Dependency(\.continuousClock)
    var clock

    private enum CancelID {
        static let helperMonitor = "helperMonitor"
        static let accessCheck = "accessCheck"
        static let terminationCleanupTimeout = "terminationCleanupTimeout"
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            // MARK: - Launch

            case .launch(.willFinishLaunching):
                let theme = appearanceSettingsClient.loadTheme()
                appearanceSettingsClient.applyThemeSync(theme)

                if isRunningXCTest() {
                    return .none
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
                return .none

            case .launch(.didFinishLaunching):
                if onboardingWindowClient.showIfNeeded() {
                    return .none
                }
                return .send(.accountAccessGate(.checkAccessStatus))

            case let .launch(.appReopen(hasVisibleWindows: flag)):
                if onboardingWindowClient.showIfNeeded() {
                    return .none
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
                state.lastAccessStatus = response.status
                state.accountAccessGateResolved = true

                if response.status.isActive {
                    let now = date.now
                    let snapshot = AccessStatusSnapshot(
                        status: response.status,
                        expiresAt: response.expiresAt,
                        entitlements: response.entitlements,
                        fetchedAt: now,
                    )
                    return .send(.accountAccessGate(.accountAccessGranted(snapshot: snapshot)))
                } else {
                    return .send(.accountAccessGate(.showUnlockSurface))
                }

            case let .accountAccessGate(.accessStatusResponse(.failure(error))):
                guard error == .networkFailure else {
                    return .send(.accountAccessGate(.showUnlockSurface))
                }
                let snapshotClient = snapshotClient
                let dateNow = date.now
                return .run { send in
                    guard let cached = await snapshotClient.load(),
                          cached.isActive,
                          dateNow.timeIntervalSince(cached.fetchedAt) <= 24 * 3600,
                          cached.expiresAt.map({ dateNow < $0 }) ?? true
                    else {
                        await send(.accountAccessGate(.showUnlockSurface))
                        return
                    }
                    await send(.accountAccessGate(.accountAccessGranted(snapshot: cached)))
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

            case .termination(.willTerminate):
                return .cancel(id: CancelID.helperMonitor)

            case .delegate(.startHelperIfNeeded):
                return .none

            case .delegate:
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
