import ComposableArchitecture
import SwiftUI

struct OnboardingView: View {
    let store: StoreOf<OnboardingFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Welcome to Voyager")
                        .font(.system(size: 28, weight: .semibold))
                    Text("Onboarding in progress")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }

                Text("Step \(viewStore.stepIndex)/\(viewStore.totalSteps)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)
            .onAppear {
                viewStore.send(.onAppear)
            }
        }
    }
}
