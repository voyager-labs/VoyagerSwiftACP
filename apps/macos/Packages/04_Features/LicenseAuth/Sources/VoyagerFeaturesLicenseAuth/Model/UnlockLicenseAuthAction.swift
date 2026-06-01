import ComposableArchitecture
import Foundation

@CasePathable
public enum UnlockLicenseAuthAction: CasePathable, Sendable {
    case onAppear
    case claimModeChanged(LicenseAuthClaimMode)
    case licenseKeyChanged(String)
    case betaCodeChanged(String)
    case submitTapped
    case retryTapped
    case loginTapped
    case signInHandoffCompleted(SignInHandoffResult)
    case loginCallbackReceived(URL)
    case _onAppearSessionRestored(Bool)
    case _loginSessionRestored(Bool)
    case claimResponse(Result<LicenseAuthStatusResponse, LicenseAuthError>)
    case licenseAuthStatusResponse(generation: Int, result: Result<LicenseAuthStatusResponse, LicenseAuthError>)
    case refreshAccessTapped
    case delegate(Delegate)

    @CasePathable
    public enum Delegate: CasePathable, Sendable {
        case unlocked(LicenseAuthStatusSnapshot)
    }
}
