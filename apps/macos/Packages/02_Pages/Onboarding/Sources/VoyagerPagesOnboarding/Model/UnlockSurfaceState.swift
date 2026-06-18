import ComposableArchitecture
import Foundation
import VoyagerFeaturesAccountAccess

@ObservableState
struct UnlockSurfaceState: Equatable {
    var unlockAccess: AccountAccessFeature.State = .init()
}
