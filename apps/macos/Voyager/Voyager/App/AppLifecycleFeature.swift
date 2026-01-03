import ComposableArchitecture
import Foundation

@Reducer
struct AppLifecycleFeature {
    @ObservableState
    struct State: Equatable {
        var didStartUpdateCheck = false
    }

    enum Action: Sendable {
        case didFinishLaunching
    }

    @Dependency(\.updateCheckClient)
    var updateCheckClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .didFinishLaunching:
                if state.didStartUpdateCheck {
                    return .none
                }
                state.didStartUpdateCheck = true
                return .run { _ in
                    await updateCheckClient.startAtLaunch()
                }
            }
        }
    }
}
