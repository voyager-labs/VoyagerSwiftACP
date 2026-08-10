import ComposableArchitecture
@testable import VoyagerPagesOnboarding

enum StateMutation {
    static func applyPersistedCompletedAccessStep(state: inout OnboardingFeature.State) {
        state.permissions.isComplete = true
    }
}
