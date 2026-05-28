import ComposableArchitecture
import VoyagerFeaturesLicenseAuth

@CasePathable
enum OnboardingAction: CasePathable {
    case onAppear
    case backTapped
    case nextTapped

    case welcome(WelcomeFeature.Action)
    case betaAccess(UnlockLicenseAuthFeature.Action)
    case permissions(PermissionsFeature.Action)
    case aiProviderSetup(AiProviderSetupFeature.Action)
    case complete(CompleteFeature.Action)
}
