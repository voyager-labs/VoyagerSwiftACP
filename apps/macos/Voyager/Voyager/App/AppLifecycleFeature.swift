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
        case willTerminate
    }

    @Dependency(\.helperAppClient)
    var helperAppClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .willFinishLaunching:
                if state.didStartHelper {
                    return .none
                }
                state.didStartHelper = true
                let helperClient = helperAppClient
                return .run { _ in
                    async let monitor: Void = {
                        for await _ in helperClient.terminationEvents() {
                            await helperClient.start()
                        }
                    }()

                    await helperClient.start()
                    _ = await monitor
                }
                .cancellable(id: CancelID.helperMonitor, cancelInFlight: true)
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
