import AppKit
import ComposableArchitecture
import Foundation
import Logging
import VoyagerEntitiesAppPreferences
import VoyagerEntryCoreClient
import VoyagerFeaturesAccountAccess
import VoyagerPagesOnboarding
import VoyagerShared

struct AppTechnicalSentryClient {
    var startIfNeeded: @Sendable (String?, String?, String) -> Void
    var updateUser: @Sendable (String) -> Void
}

extension AppTechnicalSentryClient: DependencyKey {
    nonisolated static let liveValue = AppTechnicalSentryClient(
        startIfNeeded: { appVersion, userId, component in
            guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
                  NSClassFromString("XCTestCase") == nil
            else { return }
            SentryBootstrap.startIfNeeded(
                appVersion: appVersion,
                userId: userId,
                component: component,
            )
        },
        updateUser: { userId in
            guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
                  NSClassFromString("XCTestCase") == nil
            else { return }
            SentryBootstrap.updateUser(userId: userId)
        },
    )

    nonisolated static let testValue = AppTechnicalSentryClient(
        startIfNeeded: { _, _, _ in },
        updateUser: { _ in },
    )
    nonisolated static let previewValue = testValue
}

extension DependencyValues {
    nonisolated var appTechnicalSentryClient: AppTechnicalSentryClient {
        get { self[AppTechnicalSentryClient.self] }
        set { self[AppTechnicalSentryClient.self] = newValue }
    }
}

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
    @Dependency(\.deviceIdentityClient)
    var deviceIdentityClient
    @Dependency(\.productAnalyticsClient)
    var productAnalyticsClient
    @Dependency(\.appTechnicalSentryClient)
    var appTechnicalSentryClient
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

                let isRunningXCTest = isRunningXCTest()
                if !isRunningXCTest {
                    try? EnvironmentLoader.loadEnvFiles()
                    EnvironmentLoader.requireAppEnv()
                }
                let appVersion = AppVersionInfo.shortVersion
                let deviceIdentityClient = deviceIdentityClient
                let productAnalyticsClient = productAnalyticsClient
                let appTechnicalSentryClient = appTechnicalSentryClient
                appTechnicalSentryClient.startIfNeeded(appVersion, nil, "app")
                let identityEffect = Effect<Action>.run { _ in
                    let userId: String? = await Task.detached(priority: .utility) {
                        guard let rawValue = try? deviceIdentityClient.deviceId() else { return nil }
                        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        return normalized.isEmpty ? nil : normalized
                    }.value

                    await withTaskGroup(of: Void.self) { group in
                        group.addTask {
                            await productAnalyticsClient.setDeviceIdentity(userId)
                        }
                        if let userId {
                            group.addTask {
                                await MainActor.run {
                                    appTechnicalSentryClient.updateUser(userId)
                                }
                            }
                        }
                        await group.waitForAll()
                    }
                }
                return .merge(
                    identityEffect,
                    observeSessionExpirationEffect(notificationCenterClient: notificationCenterClient),
                )

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
                guard state.isShellRuntimeReady else { return .none }
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
            effects.append(helperMonitorEffect())
        }
        if !state.didStartEntryCoreHealthProbe {
            state.didStartEntryCoreHealthProbe = true
            effects.append(entryCoreHealthProbeEffect())
        }
        return .merge(effects)
    }

    private func entryCoreHealthProbeEffect() -> Effect<Action> {
        let date = date
        let endpointClient = entryCoreEndpointClient
        let entryCoreClient = entryCoreClient

        return .run { send in
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
        .cancellable(id: CancelID.entryCoreHealthProbe, cancelInFlight: true)
    }

    private func helperMonitorEffect() -> Effect<Action> {
        let date = date
        let monitor = HelperMonitor(
            helperClient: helperAppClient,
            stateClient: helperStateClient,
            clock: clock,
            now: { date.now },
            canRestart: { !VoyagerTerminationCoordinator.shared.isTerminating() },
        )

        return .run { _ in
            await monitor.run(
                mainBundleVersion: Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
            )
        }
        .cancellable(id: CancelID.helperMonitor, cancelInFlight: true)
    }
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

@MainActor
final class VoyagerTerminationCoordinator {
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
