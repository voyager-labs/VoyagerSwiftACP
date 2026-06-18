import ComposableArchitecture
import VoyagerFeaturesAccountAccess

@Reducer
struct UnlockSurfaceFeature {
    typealias State = UnlockSurfaceState
    typealias Action = UnlockSurfaceAction

    @Dependency(\.accessStatusSnapshotClient)
    var snapshotClient
    @Dependency(\.unlockSurfaceWindowClient)
    var windowClient

    var body: some Reducer<State, Action> {
        Scope(state: \.unlockAccess, action: \.unlockAccess) {
            AccountAccessFeature()
        }
        Reduce { _, action in
            switch action {
            case .onAppear:
                return .send(.unlockAccess(.onAppear))

            case let .unlockAccess(.delegate(.unlocked(snapshot))):
                let client = snapshotClient
                let windowClient = windowClient
                return .run { send in
                    await client.save(snapshot)
                    await windowClient.closeWindow()
                    await windowClient.onUnlocked(snapshot)
                    await send(.delegate(.unlocked(snapshot)))
                }

            case .unlockAccess:
                return .none

            case .delegate:
                return .none
            }
        }
    }
}
