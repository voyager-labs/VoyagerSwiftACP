import ComposableArchitecture
import Foundation
import VoyagerFeaturesAccess

@CasePathable
enum UnlockSurfaceAction: CasePathable, Sendable {
    case onAppear
    case unlockAccess(UnlockAccessFeature.Action)
    case delegate(Delegate)

    @CasePathable
    enum Delegate: CasePathable, Sendable {
        case unlocked(AccessStatusSnapshot)
    }
}
