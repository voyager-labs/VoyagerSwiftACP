import ComposableArchitecture

@CasePathable
enum BetaAccessAction: CasePathable, Sendable {
    case onAppear
    case emailChanged(String)
    case tokenChanged(String)
    case checkTapped
    case retryTapped
    case verificationResponse(BetaAccessVerificationResult)
}
