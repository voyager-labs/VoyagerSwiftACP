import ComposableArchitecture
import VoyagerFeaturesAccountAccess

@CasePathable
enum OnboardingAction: CasePathable {
    case onAppear
    case backTapped
    case nextTapped

    case welcome(WelcomeFeature.Action)
    case accessUnlock(AccountAccessFeature.Action)
    case permissions(PermissionsFeature.Action)
    case aiProviderSetup(AiProviderSetupFeature.Action)
    case complete(CompleteFeature.Action)
}
