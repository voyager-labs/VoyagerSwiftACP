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
    case browserLoginCompleted(OAuthCredentialFile)
    case browserLoginFailed(CodexNativeAuthError)
    case startDeviceAuth
    case deviceAuthCompleted(OAuthCredentialFile)
    case deviceAuthFailed(CodexNativeAuthError)
    case submitAPIKey(String)
    case _verificationResponse(AiProviderVerificationResult)
    case _connectionResponse(AiProviderConnectionResult)
    case _disconnectResponse(AiProviderConnectionResult)
}
