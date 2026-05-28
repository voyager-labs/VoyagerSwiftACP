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
    case claimResponse(Result<LicenseAuthStatusResponse, LicenseAuthError>)
    case licenseAuthStatusResponse(Result<LicenseAuthStatusResponse, LicenseAuthError>)
    case delegate(Delegate)

    @CasePathable
    public enum Delegate: CasePathable, Sendable {
        case unlocked(LicenseAuthStatusSnapshot)
    }
}
