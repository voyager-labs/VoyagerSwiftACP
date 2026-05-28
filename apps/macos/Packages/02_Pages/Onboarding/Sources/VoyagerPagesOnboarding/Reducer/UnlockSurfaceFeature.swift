import ComposableArchitecture
import VoyagerFeaturesLicenseAuth

@Reducer
struct UnlockSurfaceFeature {
    typealias State = UnlockSurfaceState
    typealias Action = UnlockSurfaceAction

    @Dependency(\.licenseAuthStatusSnapshotClient)
    var snapshotClient
    @Dependency(\.unlockSurfaceWindowClient)
    var windowClient

    var body: some Reducer<State, Action> {
        Scope(state: \.unlockAccess, action: \.unlockAccess) {
            UnlockLicenseAuthFeature()
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
