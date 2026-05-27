import ComposableArchitecture
import Foundation

@CasePathable
public enum UnlockAccessAction: CasePathable, Sendable {
    case onAppear
    case claimModeChanged(AccessClaimMode)
    case licenseKeyChanged(String)
    case betaCodeChanged(String)
    case submitTapped
    case retryTapped
    case claimResponse(Result<AccessStatusResponse, AccessError>)
    case accessStatusResponse(Result<AccessStatusResponse, AccessError>)
    case delegate(Delegate)

    @CasePathable
    public enum Delegate: CasePathable, Sendable {
        case unlocked(AccessStatusSnapshot)
    }
}
