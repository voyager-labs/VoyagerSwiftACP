import ComposableArchitecture
import Foundation

@Reducer
struct AppPreferencesFeature {
    typealias State = AppPreferencesState
    typealias Action = AppPreferencesAction

    @Dependency(\.userDefaultsClient)
    private var userDefaultsClient

    private let userDefaultsObserverCancelID = "AppPreferencesFeature.userDefaultsObserver"

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .load:
                let loaded = AppPreferencesState.load(from: userDefaultsClient)
                state = loaded
                return .merge(
                    .send(.delegate(.updated(loaded))),
                    .run { send in
                        for await _ in NotificationCenter.default
                            .notifications(named: UserDefaults.didChangeNotification)
                        {
                            await send(.reloadFromUserDefaults)
                        }
                    }
                    .cancellable(id: userDefaultsObserverCancelID, cancelInFlight: true),
                )

            case .reloadFromUserDefaults:
                let loaded = AppPreferencesState.load(from: userDefaultsClient)
                guard state != loaded else { return .none }
                state = loaded
                return .send(.delegate(.updated(loaded)))

            case .delegate:
                return .none
            }
        }
    }
}
