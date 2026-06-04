import ComposableArchitecture
import VoyagerFeaturesBetaAccess

@CasePathable
enum OnboardingAction: CasePathable {
    case onAppear
    case backTapped
    case nextTapped

    case welcome(WelcomeFeature.Action)
    case betaAccess(BetaAccessFeature.Action)
    case permissions(PermissionsFeature.Action)
    case complete(CompleteFeature.Action)
}
