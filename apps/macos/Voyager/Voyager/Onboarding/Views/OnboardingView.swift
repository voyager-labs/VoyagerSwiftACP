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
                    Text("Step \(viewStore.currentStepIndex)/\(viewStore.totalSteps) · \(viewStore.currentStep.title)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    ProgressView(
                        value: Double(viewStore.currentStepIndex),
                        total: Double(viewStore.totalSteps),
                    )
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 320)
                }

                if viewStore.showResumeBanner {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.secondary)
                        Text("Resuming your onboarding from where you left off.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Dismiss") {
                            viewStore.send(.dismissResumeBanner)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                }

                stepContent(for: viewStore.currentStep)

                Spacer()

                HStack {
                    Button("Back") {
                        viewStore.send(.backTapped)
                    }
                    .disabled(!viewStore.canGoBack)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Button("Next") {
                            viewStore.send(.nextTapped)
                        }
                        .disabled(!viewStore.canGoNext)

                        if viewStore.currentStep == .permissions,
                           !viewStore.canGoNext,
                           let message = viewStore.permissions.nextDisabledMessage
                        {
                            Text(message)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)
            .onAppear {
                viewStore.send(.onAppear)
            }
        }
    }

    @ViewBuilder
    private func stepContent(for step: OnboardingStep) -> some View {
        switch step {
        case .welcome:
            WelcomeStepView(store: store.scope(state: \.welcome, action: \.welcome))
        case .betaAccess:
            BetaAccessStepView(store: store.scope(state: \.betaAccess, action: \.betaAccess))
        case .permissions:
            PermissionsStepView(store: store.scope(state: \.permissions, action: \.permissions))
        case .complete:
            CompleteStepView(store: store.scope(state: \.complete, action: \.complete))
        }
    }
}
