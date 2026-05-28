import ComposableArchitecture
import Foundation
import VoyagerFeaturesLicenseAuth

@ObservableState
struct UnlockSurfaceState: Equatable {
    var unlockAccess: UnlockLicenseAuthFeature.State = .init()
}
