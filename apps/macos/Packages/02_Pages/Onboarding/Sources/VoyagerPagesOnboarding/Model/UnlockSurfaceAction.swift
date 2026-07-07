import ComposableArchitecture
import Foundation
import VoyagerFeaturesAccountAccess

@CasePathable
enum UnlockSurfaceAction: CasePathable {
    case onAppear
    case unlockAccess(AccountAccessFeature.Action)
    case delegate(Delegate)

    @CasePathable
    enum Delegate: CasePathable {
        case unlocked(AccessStatusSnapshot)
    }
}
