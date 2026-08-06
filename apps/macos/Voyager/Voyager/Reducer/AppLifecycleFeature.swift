import AppKit
import ComposableArchitecture
import Foundation
import Logging
import VoyagerEntitiesAppPreferences
import VoyagerEntryCoreClient
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
    @Dependency(\.continuousClock)
    var clock
    @Dependency(\.date)
    var date
    @Dependency(\.notificationCenterClient)
    var notificationCenterClient
    @Dependency(\.entryCoreEndpointClient)
    var entryCoreEndpointClient
    @Dependency(\.entryCoreClient)
    var entryCoreClient

    private enum CancelID {
        static let helperMonitor = "helperMonitor"
        static let entryCoreHealthProbe = "entryCoreHealthProbe"
        static let terminationCleanupTimeout = "terminationCleanupTimeout"
        static let sessionExpirationObserver = "sessionExpirationObserver"
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.accountAccess, action: \.accountAccess) {
            AccountAccessFeature()
        }

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
                EnvironmentLoader.requireAppEnv()
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
                let shouldPresentOnboarding = onboardingWindowClient.showIfNeeded()
                return .merge(
                    startShellRuntime(into: &state),
                    shouldPresentOnboarding ? .none : .send(.accountAccess(.onAppear)),
                )

            case let .launch(.appReopen(hasVisibleWindows: flag)):
                if onboardingWindowClient.showIfNeeded() {
                    return .none
                }
                if state.isShellRuntimeReady {
                    return .send(.delegate(.reopenWindowIfNeeded(hasVisibleWindows: flag)))
                }
                return .none

            case .accountAccess:
                return .none

            // MARK: - Session expiry adapter

            case let .sessionExpiredDetected(reason):
                // Task 4: app-level reason 저장 후 child teardown 라우팅
                state.sessionEndReason = reason
                return .send(.accountAccess(._sessionExpiredDetected))

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
                return .merge(
                    .cancel(id: CancelID.helperMonitor),
                    .cancel(id: CancelID.entryCoreHealthProbe),
                    .cancel(id: CancelID.sessionExpirationObserver),
                    .send(.accountAccess(.appWillTerminate)),
                )

            case let .entryCoreHealthProbeCompleted(result):
                state.didCompleteEntryCoreHealthProbe = true
                appLifecycleLogger.info(
                    "Entry Core health probe completed",
                    metadata: [
                        "outcome": .string(result.outcome.rawValue),
                        "phase": .string(result.phase.rawValue),
                        "duration": .string(String(describing: result.duration)),
                    ],
                )
                guard state.isShellRuntimeReady, !onboardingWindowClient.isRequired() else { return .none }
                return .send(.delegate(.openInitialWindowIfNeeded))

            case .delegate(.openInitialWindowIfNeeded):
                return .none

            case .delegate(.startHelperIfNeeded):
                return .none

            case .delegate:
                return .none
            }
        }
    }

    private func startShellRuntime(into state: inout State) -> Effect<Action> {
        var effects: [Effect<Action>] = []
        if !state.didStartHelper {
            state.didStartHelper = true
            effects.append(helperMonitorEffect(
                helperClient: helperAppClient,
                stateClient: helperStateClient,
            ))
        }
        if !state.didStartEntryCoreHealthProbe {
            state.didStartEntryCoreHealthProbe = true
            let endpointClient = entryCoreEndpointClient
            let entryCoreClient = entryCoreClient
            let date = date
            effects.append(
                .run { send in
                    let startedAt = date.now
                    let endpoint: EntryCoreEndpoint
                    do {
                        endpoint = try endpointClient.resolve()
                    } catch {
                        await send(.entryCoreHealthProbeCompleted(.init(
                            outcome: .unavailable,
                            phase: .endpointResolution,
                            duration: entryCoreHealthProbeDuration(from: startedAt, to: date.now),
                        )))
                        return
                    }
                    do {
                        _ = try await entryCoreClient.health(endpoint)
                        await send(.entryCoreHealthProbeCompleted(.init(
                            outcome: .healthy,
                            phase: .response,
                            duration: entryCoreHealthProbeDuration(from: startedAt, to: date.now),
                        )))
                    } catch is CancellationError {
                        return
                    } catch let error as EntryCoreClientError {
                        guard error != .cancelled else { return }
                        await send(.entryCoreHealthProbeCompleted(
                            entryCoreHealthProbeResult(
                                for: error,
                                duration: entryCoreHealthProbeDuration(from: startedAt, to: date.now),
                            ),
                        ))
                    } catch {
                        await send(.entryCoreHealthProbeCompleted(.init(
                            outcome: .failed,
                            phase: .response,
                            duration: entryCoreHealthProbeDuration(from: startedAt, to: date.now),
                        )))
                    }
                }
                .cancellable(id: CancelID.entryCoreHealthProbe, cancelInFlight: true),
            )
        }
        return .merge(effects)
    }
}

// MARK: - Helper effects

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
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}

/// accountSessionDidEnd notification을 관찰한다.
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

private let appLifecycleLogger = Logger(label: "Voyager.AppLifecycle")

private func entryCoreHealthProbeResult(
    for error: EntryCoreClientError,
    duration: Duration,
) -> EntryCoreHealthProbeResult {
    switch error {
    case .invalidEndpoint:
        .init(outcome: .unavailable, phase: .endpointResolution, duration: duration)
    case .daemonUnavailable:
        .init(outcome: .unavailable, phase: .connect, duration: duration)
    case let .timedOut(phase), let .transport(phase):
        .init(outcome: .failed, phase: entryCoreHealthProbePhase(phase), duration: duration)
    case .cancelled:
        .init(outcome: .failed, phase: .response, duration: duration)
    case .responseTooLarge, .malformedResponse, .protocolMismatch, .requestIDMismatch, .server:
        .init(outcome: .failed, phase: .response, duration: duration)
    }
}

private func entryCoreHealthProbePhase(
    _ phase: EntryCoreTransportPhase,
) -> EntryCoreHealthProbeResult.Phase {
    switch phase {
    case .connect:
        .connect
    case .write:
        .write
    case .read:
        .read
    }
}

private func entryCoreHealthProbeDuration(from start: Date, to end: Date) -> Duration {
    .seconds(max(0, end.timeIntervalSince(start)))
}
