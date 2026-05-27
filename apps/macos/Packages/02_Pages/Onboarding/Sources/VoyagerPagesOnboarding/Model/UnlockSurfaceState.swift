import ComposableArchitecture
import Foundation
import VoyagerFeaturesAccess

@ObservableState
struct UnlockSurfaceState: Equatable {
    var unlockAccess: UnlockAccessFeature.State = .init()
}
