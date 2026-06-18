import ComposableArchitecture
import Foundation
import VoyagerFeaturesAccountAccess

@CasePathable
enum UnlockSurfaceAction: CasePathable, Sendable {
    case onAppear
    case unlockAccess(AccountAccessFeature.Action)
    case delegate(Delegate)

    @CasePathable
    enum Delegate: CasePathable, Sendable {
        case unlocked(AccessStatusSnapshot)
    }
}
