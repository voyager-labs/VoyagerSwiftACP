import ComposableArchitecture

@CasePathable
enum OnboardingAction: CasePathable {
    case onAppear
    case backTapped
    case nextTapped
    case accessProjectionUpdated(OnboardingAccessProjection)

    case welcome(WelcomeFeature.Action)
    case permissions(PermissionsFeature.Action)
    case aiProviderSetup(AiProviderSetupFeature.Action)
    case complete(CompleteFeature.Action)
}
