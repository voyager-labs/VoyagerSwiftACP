import ComposableArchitecture
import Foundation
import Logging
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

    private enum CancelID {
        static let helperMonitor = "helperMonitor"
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .willFinishLaunching:
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

                if state.didStartHelper {
                    return .none
                }
                state.didStartHelper = true
                let helperClient = helperAppClient
                let stateClient = helperStateClient

                return .run { _ in
                    let logger = Logger(label: "Voyager")
                    let currentBundleVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String

                    async let monitor: Void = {
                        var policy = HelperSupervisionPolicy()

                        for await _ in helperClient.terminationEvents() {
                            logger.info("[VOY-122] helper_termination_event_received")

                            if await VoyagerTerminationCoordinator.shared.isTerminating() {
                                logger.info("[VOY-122] helper_restart_skip -- reason=app_terminating")
                                continue
                            }

                            let decision = policy.recordRestartAttempt()
                            logger.info("[VOY-122] helper_restart_decision -- \(decision)")

                            switch decision {
                            case .allowed:
                                logger.info("[VOY-122] helper_ensure_invoked")
                                await helperClient.ensureRunning()

                            case let .cooldown(activeUntil):
                                let delay = activeUntil.timeIntervalSinceNow
                                logger.info("[VOY-122] helper_restart_skip -- reason=cooldown until=\(activeUntil)")
                                if delay > 0 {
                                    logger.info("[VOY-122] helper_restart_scheduled -- delay=\(delay)s")
                                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                                    logger.info("[VOY-122] helper_restart_sleep_completed")
                                    let isRunning = await helperClient.isRunning()
                                    logger.info("[VOY-122] helper_is_running_check -- result=\(isRunning)")
                                    if !isRunning {
                                        logger.info("[VOY-122] helper_restart_after_cooldown")
                                        let newDecision = policy.recordRestartAttempt()
                                        logger.info("[VOY-122] helper_restart_new_decision -- \(newDecision)")
                                        switch newDecision {
                                        case .allowed:
                                            await helperClient.ensureRunning()
                                        default:
                                            break
                                        }
                                    }
                                }

                            case let .graceWindow(activeUntil):
                                let delay = activeUntil.timeIntervalSinceNow
                                logger.info("[VOY-122] helper_restart_skip -- reason=grace_window until=\(activeUntil)")
                                if delay > 0 {
                                    logger.info("[VOY-122] helper_restart_scheduled -- delay=\(delay)s")
                                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                                    logger.info("[VOY-122] helper_restart_sleep_completed")
                                    let isRunning = await helperClient.isRunning()
                                    logger.info("[VOY-122] helper_is_running_check -- result=\(isRunning)")
                                    if !isRunning {
                                        logger.info("[VOY-122] helper_restart_after_grace_window")
                                        let newDecision = policy.recordRestartAttempt()
                                        logger.info("[VOY-122] helper_restart_new_decision -- \(newDecision)")
                                        switch newDecision {
                                        case .allowed:
                                            await helperClient.ensureRunning()
                                        default:
                                            break
                                        }
                                    }
                                }
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
                .cancellable(id: CancelID.helperMonitor, cancelInFlight: true)

            case .didFinishLaunching:
                if isRunningXCTest() {
                    return .none
                }
                if onboardingWindowClient.showIfNeeded() {
                    return .none
                }
                return .send(.delegate(.openInitialWindowIfNeeded))

            case let .appReopen(hasVisibleWindows: flag):
                if isRunningXCTest() {
                    return .none
                }
                if onboardingWindowClient.showIfNeeded() {
                    return .none
                }
                return .send(.delegate(.reopenWindowIfNeeded(hasVisibleWindows: flag)))

            case .requestTermination:
                guard state.terminationAttemptID == nil else {
                    return .none
                }

                let attemptID = uuid()
                state.terminationAttemptID = attemptID

                let shouldAlert = userDefaultsClient.bool(SettingsKeys.alertBeforeQuit)
                guard shouldAlert else {
                    return .send(.startTerminationCleanup(attemptID: attemptID))
                }

                let quitConfirmationClient = quitConfirmationClient
                return .run { send in
                    let result = await quitConfirmationClient.confirmQuit(false, shouldAlert)
                    await send(.quitConfirmationResponse(attemptID: attemptID, result: result))
                }

            case let .quitConfirmationResponse(attemptID: attemptID, result: result):
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

                return .send(.startTerminationCleanup(attemptID: attemptID))

            case let .startTerminationCleanup(attemptID: attemptID):
                guard state.terminationAttemptID == attemptID else {
                    return .none
                }

                let helperAppClient = helperAppClient
                return .merge(
                    .run { send in
                        print("[VOY-122] app_terminate_cleanup_begin")

                        await VoyagerTerminationCoordinator.shared.begin(.userQuit)
                        await send(.willTerminate)

                        await helperAppClient.stop()

                        print("[VOY-122] app_terminate_cleanup_done")
                        await send(.completeTerminationAttempt(attemptID: attemptID, shouldTerminate: true))
                    },
                    .run { send in
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        await send(.completeTerminationAttempt(attemptID: attemptID, shouldTerminate: true))
                    },
                )

            case let .completeTerminationAttempt(attemptID: attemptID, shouldTerminate: shouldTerminate):
                guard state.terminationAttemptID == attemptID else {
                    return .none
                }

                state.terminationAttemptID = nil

                let appTerminationReplyClient = appTerminationReplyClient
                return .run { _ in
                    await appTerminationReplyClient.reply(shouldTerminate)
                }

            case .willTerminate:
                return .cancel(id: CancelID.helperMonitor)

            case .delegate:
                return .none
            }
        }
    }
}

private func isRunningXCTest() -> Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}

actor VoyagerTerminationCoordinator {
    static let shared = VoyagerTerminationCoordinator()

    enum Reason: Sendable {
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
