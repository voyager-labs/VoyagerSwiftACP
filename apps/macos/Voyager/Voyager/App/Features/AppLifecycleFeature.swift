import ComposableArchitecture
import Foundation

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
    @Dependency(\.backendEndpointClient)
    var backendEndpointClient

    @Dependency(\.onboardingWindowClient)
    var onboardingWindowClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .willFinishLaunching:
                try? EnvironmentLoader.loadEnvFiles()

                if state.didStartHelper {
                    return .none
                }
                state.didStartHelper = true
                let helperClient = helperAppClient
                let endpointClient = backendEndpointClient
                return .run { _ in
                    async let monitor: Void = {
                        for await _ in helperClient.terminationEvents() {
                            await helperClient.start()
                            _ = await endpointClient.resolve()
                        }
                    }()

                    await helperClient.start()
                    _ = await endpointClient.resolve()
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
