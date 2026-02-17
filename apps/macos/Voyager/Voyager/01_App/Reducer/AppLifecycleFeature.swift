import ComposableArchitecture
import Foundation
import Logging
import SwiftDotenv

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
                        var recentRestarts: [Date] = []

                        func recordRestartIfAllowed() -> Bool {
                            let now = Date()
                            recentRestarts = recentRestarts.filter { now.timeIntervalSince($0) <= 60 }
                            if recentRestarts.count >= 3 {
                                logger.error("helper_restart_rate_limited")
                                return false
                            }
                            recentRestarts.append(now)
                            return true
                        }

                        for await _ in helperClient.terminationEvents() {
                            if await VoyagerTerminationCoordinator.shared.isTerminating() {
                                logger.info("helper_monitor_skip_due_to_termination")
                                break
                            }

                            guard recordRestartIfAllowed() else {
                                break
                            }

                            await helperClient.start()
                            _ = await helperClient.resolveAlignedState(
                                stateClient: stateClient,
                                mainBundleVersion: currentBundleVersion,
                                logger: logger,
                            )
                        }
                    }()

                    let initialState = await helperClient.resolveAlignedState(
                        stateClient: stateClient,
                        mainBundleVersion: currentBundleVersion,
                        logger: logger,
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
                        let logger = Logger(label: "Voyager")

                        await VoyagerTerminationCoordinator.shared.begin(.userQuit)
                        await send(.willTerminate)

                        logger.info("app_terminate_cleanup_begin")

                        await helperAppClient.stop()

                        logger.info("app_terminate_cleanup_done")
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
