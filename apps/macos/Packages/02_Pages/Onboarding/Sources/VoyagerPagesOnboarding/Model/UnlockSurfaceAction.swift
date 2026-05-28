import ComposableArchitecture
import Foundation
import VoyagerFeaturesLicenseAuth

@CasePathable
enum UnlockSurfaceAction: CasePathable, Sendable {
    case onAppear
    case unlockAccess(UnlockLicenseAuthFeature.Action)
    case delegate(Delegate)

    @CasePathable
    enum Delegate: CasePathable, Sendable {
        case unlocked(LicenseAuthStatusSnapshot)
    }
}
