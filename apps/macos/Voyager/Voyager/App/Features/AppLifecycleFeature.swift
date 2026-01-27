import ComposableArchitecture
import Foundation
import Logging
import SwiftDotenv

@Reducer
struct AppLifecycleFeature {
    private enum CancelID {
        static let helperMonitor = "helperMonitor"
    }

    @ObservableState
    struct State: Equatable {
        var didStartHelper = false
    }

    enum Action: Sendable {
        case willFinishLaunching
        case didFinishLaunching
        case willTerminate
    }

    @Dependency(\.helperAppClient)
    var helperAppClient
    @Dependency(\.helperStateClient)
    var helperStateClient

    @Dependency(\.onboardingWindowClient)
    var onboardingWindowClient
    @Dependency(\.onboardingProgressStore)
    var onboardingProgressStore
    @Dependency(\.indexingClient)
    var indexingClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .willFinishLaunching:
                try? EnvironmentLoader.loadEnvFiles()
                let userId = DeviceIdentifierProvider.current()
                let appVersion = AppVersionInfo.shortVersion
                SentryBootstrap.startIfNeeded(
                    appVersion: appVersion,
                    userId: userId,
                    component: "app",
                )
                VoyagerSentryMetricLogger.userIdProvider = { DeviceIdentifierProvider.current() }

                if state.didStartHelper {
                    return .none
                }
                state.didStartHelper = true
                let helperClient = helperAppClient
                let stateClient = helperStateClient
                let onboardingProgressStore = onboardingProgressStore
                let indexingClient = indexingClient
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
                    let onboardingComplete: Bool = switch onboardingProgressStore.load() {
                    case let .success(snapshot):
                        snapshot.stepState.completeComplete
                    case .empty, .resetRequired:
                        false
                    }
                    if onboardingComplete {
                        logger.info("Onboarding complete; requesting initial indexing on launch")
                        await indexingClient.start()
                    } else {
                        logger.info("Onboarding incomplete; skip initial indexing request on launch")
                    }
                    _ = await monitor
                }
                .cancellable(id: CancelID.helperMonitor, cancelInFlight: true)
            case .didFinishLaunching:
                return .run { [onboardingWindowClient] _ in
                    _ = onboardingWindowClient.showIfNeeded()
                }
            case .willTerminate:
                return .cancel(id: CancelID.helperMonitor)
            }
        }
    }
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
