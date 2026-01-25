import ComposableArchitecture
import Foundation
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
                return .run { _ in
                    // Helper 상태 요청 및 fallback 처리
                    @Sendable
                    func requestHelperState() async {
                        let state = await stateClient.resolve()
                        if state != nil {
                            return
                        }

                        let isRunning = await helperClient.isRunning()
                        if !isRunning {
                            await helperClient.start()
                            _ = await stateClient.resolve()
                        }
                    }

                    async let monitor: Void = {
                        for await _ in helperClient.terminationEvents() {
                            await helperClient.start()
                            await requestHelperState()
                        }
                    }()

                    await helperClient.start()
                    await requestHelperState()
                    _ = await monitor
                }
                .cancellable(id: CancelID.helperMonitor, cancelInFlight: true)
            case .didFinishLaunching:
                return .run { [onboardingWindowClient] _ in
                    _ = onboardingWindowClient.showIfNeeded()
                }
            case .willTerminate:
                let helperClient = helperAppClient
                return .merge(
                    .run { _ in
                        await helperClient.stop()
                    },
                    .cancel(id: CancelID.helperMonitor),
                )
            }
        }
    }
}
