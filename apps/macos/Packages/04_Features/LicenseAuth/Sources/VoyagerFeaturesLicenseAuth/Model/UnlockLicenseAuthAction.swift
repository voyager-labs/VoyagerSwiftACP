import ComposableArchitecture
import Foundation

// swiftlint:disable identifier_name

@CasePathable
public enum UnlockLicenseAuthAction: CasePathable, Sendable {
    case onAppear
    case retryTapped
    case loginTapped
    case signInHandoffCompleted(SignInHandoffResult)
    case loginCallbackReceived(URL)
    case _onAppearSessionRestored(Bool)
    case _loginSessionRestored(Bool)
    case licenseAuthStatusResponse(generation: Int, result: Result<LicenseAuthStatusResponse, LicenseAuthError>)
    case refreshAccessTapped
    case appDidBecomeActive
    case openCheckoutTapped
    case openPricingTapped
    case openAccessHelpTapped
    case openBetaCodeHelpTapped
    case delegate(Delegate)

    @CasePathable
    public enum Delegate: CasePathable, Sendable {
        case unlocked(LicenseAuthStatusSnapshot)
    }
}

// swiftlint:enable identifier_name
