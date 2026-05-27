import ComposableArchitecture
import VoyagerFeaturesAccess

@CasePathable
enum OnboardingAction: CasePathable {
    case onAppear
    case backTapped
    case nextTapped

    case welcome(WelcomeFeature.Action)
    case betaAccess(UnlockAccessFeature.Action)
    case permissions(PermissionsFeature.Action)
    case aiProviderSetup(AiProviderSetupFeature.Action)
    case complete(CompleteFeature.Action)
}
