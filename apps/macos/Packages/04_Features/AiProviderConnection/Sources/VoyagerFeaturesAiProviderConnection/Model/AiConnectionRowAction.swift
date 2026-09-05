import ComposableArchitecture
import VoyagerEntitiesAi

@CasePathable
public enum AiConnectionRowAction: CasePathable, Equatable, Sendable {
    case connectButtonTapped
    case disconnectButtonTapped
    case disconnectConfirm
    case disconnectCancel
    case retryButtonTapped
    case cancelButtonTapped
    case startBrowserLogin
    case startProviderLogin
    case browserLoginCompleted(OAuthCredentialFile)
    case browserLoginFailed(CodexNativeAuthError)
    case verificationFailed(ProviderStatusReason)
    case startDeviceAuth
    case deviceAuthCompleted(OAuthCredentialFile)
    case deviceAuthFailed(CodexNativeAuthError)
    case enteredKeyChanged(String)
    case submitAPIKey(String)
    case verificationResponse(AiProviderVerificationResult)
    case connectionResponse(AiProviderConnectionResult)
    case disconnectResponse(AiProviderConnectionResult)
}
