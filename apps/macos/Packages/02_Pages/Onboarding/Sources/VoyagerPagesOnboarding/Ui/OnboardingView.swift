import AppKit
import ComposableArchitecture
import SwiftUI
import VoyagerShared

struct OnboardingView: View {
    let store: StoreOf<OnboardingFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }, content: { viewStore in
            GeometryReader { proxy in
                // NOTE: 상태로 뺴는게 맞을지?
                let isWideLayout = proxy.size.width >= 900
                let horizontalPadding: CGFloat = 24
                let availableWidth = proxy.size.width - horizontalPadding * 2
                let contentWidth = min(availableWidth, 1040)
                let columnSpacing: CGFloat = 24
                let availableColumnWidth = max(contentWidth - columnSpacing, 0)
                let leftColumnWidth = availableColumnWidth * 0.4
                let rightColumnWidth = availableColumnWidth * 0.6
                let centeredContentWidth = min(max(contentWidth * 0.7, 560), min(contentWidth, 720))
                let topInsetPadding: CGFloat = 26
                let topBarWidth = contentWidth

                ZStack {
                    ZStack {
                        VisualEffectBackgroundView(material: .hudWindow, blendingMode: .behindWindow)
                        LinearGradient(
                            colors: [
                                accentColor.opacity(0.18),
                                Color(nsColor: .windowBackgroundColor).opacity(0.18),
                                Color.clear,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing,
                        )
                    }

                    VStack(spacing: 12) {
                        topInsetBar(viewStore: viewStore)
                            .frame(width: topBarWidth)

                        if let message = nextDisabledMessage(from: viewStore) {
                            HStack {
                                Spacer()
                                Text(message)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: contentWidth)
                        }

                        Group {
                            if isWideLayout {
                                HStack(alignment: .center, spacing: columnSpacing) {
                                    stepSummaryView(viewStore: viewStore, isCentered: false)
                                        .frame(width: leftColumnWidth, alignment: .leading)
                                    stepContent(for: viewStore.currentStep, isCentered: false)
                                        .frame(width: rightColumnWidth, alignment: .leading)
                                }
                                .frame(width: contentWidth, alignment: .center)
                                .frame(maxHeight: .infinity, alignment: .center)
                            } else {
                                VStack(spacing: 0) {
                                    Spacer(minLength: 0)
                                    VStack(spacing: 16) {
                                        stepSummaryView(viewStore: viewStore, isCentered: true)
                                        stepContent(for: viewStore.currentStep, isCentered: true)
                                            .frame(maxWidth: .infinity, alignment: .center)
                                            .multilineTextAlignment(.center)
                                    }
                                    .frame(width: centeredContentWidth, alignment: .center)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    Spacer(minLength: 0)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, topInsetPadding)
                    .padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(.container, edges: .top)
            }
            .onAppear {
                viewStore.send(.onAppear)
            }
        })
    }

    // TODO(DS): 디자인시스템 적용
    private let accentColor = Color(
        red: 252 / 255,
        green: 154 / 255,
        blue: 48 / 255,
    )

    private func topInsetBar(viewStore: ViewStore<OnboardingFeature.State, OnboardingFeature.Action>) -> some View {
        let sideSlotWidth: CGFloat = 200

        return HStack(spacing: 0) {
            Button {
                viewStore.send(.backTapped)
            } label: {
                topBarLabel("Back")
            }
            .buttonStyle(.plain)
            .disabled(!viewStore.canGoBack)
            .frame(width: sideSlotWidth, alignment: .leading)

            stepDots(viewStore: viewStore)
                .frame(maxWidth: .infinity, alignment: .center)

            trailingActionButton(viewStore: viewStore)
                .frame(width: sideSlotWidth, alignment: .trailing)
        }
        .frame(height: 40)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.9),
        )
    }

    @ViewBuilder
    private func trailingActionButton(
        viewStore: ViewStore<OnboardingFeature.State, OnboardingFeature.Action>,
    ) -> some View {
        switch viewStore.currentStep {
        case .accessUnlock:
            if viewStore.accessUnlock.isComplete {
                nextButton(viewStore: viewStore)
            } else if viewStore.accessUnlock.canStartLogin {
                Button {
                    viewStore.send(.accessUnlock(.loginTapped))
                } label: {
                    topBarLabel("Sign In (Enter)")
                }
                .buttonStyle(.borderedProminent)
                .tint(accentColor)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(viewStore.accessUnlock.isSignInInProgress)
            } else if viewStore.accessUnlock.canRetry {
                Button {
                    viewStore.send(.accessUnlock(.retryTapped))
                } label: {
                    topBarLabel("Retry (Enter)")
                }
                .buttonStyle(.borderedProminent)
                .tint(accentColor)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!viewStore.accessUnlock.canRetry || viewStore.accessUnlock.isSubmitting)
            } else if viewStore.accessUnlock.canRefreshAccess {
                Button {
                    viewStore.send(.accessUnlock(.refreshAccessTapped))
                } label: {
                    topBarLabel("Refresh (Enter)")
                }
                .buttonStyle(.borderedProminent)
                .tint(accentColor)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(viewStore.accessUnlock.isSubmitting || viewStore.accessUnlock.isSignInInProgress)
            }
        case .complete:
            Button {
                viewStore.send(.complete(.startUsingTapped))
            } label: {
                topBarLabel("Complete (Enter)")
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(viewStore.complete.isOpeningWindow)
        case .welcome, .permissions, .aiProviderSetup:
            nextButton(viewStore: viewStore)
        }
    }

    private func nextButton(viewStore: ViewStore<OnboardingFeature.State, OnboardingFeature.Action>) -> some View {
        Button {
            viewStore.send(.nextTapped)
        } label: {
            topBarLabel("Next (Enter)")
        }
        .buttonStyle(.borderedProminent)
        .tint(accentColor)
        .keyboardShortcut(.return, modifiers: [])
        .disabled(!viewStore.canGoNext)
    }

    private func topBarLabel(_ text: String) -> some View {
        Text(text)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }

    private func stepDots(viewStore: ViewStore<OnboardingFeature.State, OnboardingFeature.Action>) -> some View {
        HStack(spacing: 8) {
            ForEach(0 ..< viewStore.totalSteps, id: \.self) { index in
                let isActive = index == viewStore.currentStepIndex - 1
                Circle()
                    .fill(isActive ? accentColor : accentColor.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityLabel("Onboarding progress")
    }

    private func stepSummaryView(
        viewStore: ViewStore<OnboardingFeature.State, OnboardingFeature.Action>,
        isCentered: Bool,
    ) -> some View {
        let alignment: Alignment = isCentered ? .center : .leading
        let textAlignment: TextAlignment = isCentered ? .center : .leading
        let titleSize: CGFloat = isCentered ? 40 : 30
        let subtitleSize: CGFloat = isCentered ? 17 : 13

        return VStack(alignment: isCentered ? .center : .leading, spacing: 12) {
            Text("Voyager")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: alignment)
                .multilineTextAlignment(textAlignment)

            Text(viewStore.currentStep.title)
                .font(.system(size: titleSize, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: alignment)
                .multilineTextAlignment(textAlignment)

            Text(viewStore.currentStep.subtitle)
                .font(.system(size: subtitleSize))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: alignment)
                .multilineTextAlignment(textAlignment)
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }

    @ViewBuilder
    private func stepContent(for step: OnboardingStep, isCentered _: Bool) -> some View {
        switch step {
        case .welcome:
            WelcomeStepView(store: store.scope(state: \.welcome, action: \.welcome))
        case .accessUnlock:
            UnlockAccessStepView(store: store.scope(state: \.accessUnlock, action: \.accessUnlock))
        case .permissions:
            PermissionsStepView(store: store.scope(state: \.permissions, action: \.permissions))
        case .aiProviderSetup:
            AiProviderSetupStepView(store: store.scope(state: \.aiProviderSetup, action: \.aiProviderSetup))
        case .complete:
            CompleteStepView(store: store.scope(state: \.complete, action: \.complete))
        }
    }

    private func nextDisabledMessage(
        from viewStore: ViewStore<OnboardingFeature.State, OnboardingFeature.Action>,
    ) -> String? {
        switch viewStore.currentStep {
        case .permissions:
            guard !viewStore.canGoNext else { return nil }
            return viewStore.permissions.nextDisabledMessage
        case .aiProviderSetup:
            guard !viewStore.canGoNext else { return nil }
            return viewStore.aiProviderSetup.nextDisabledMessage
        default:
            return nil
        }
    }
}
