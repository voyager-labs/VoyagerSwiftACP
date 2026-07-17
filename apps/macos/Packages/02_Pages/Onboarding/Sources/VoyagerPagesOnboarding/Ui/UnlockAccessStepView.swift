import ComposableArchitecture
import SwiftUI
import VoyagerFeaturesAccountAccess
import VoyagerShared

struct UnlockAccessStepView: View {
    let store: Store<OnboardingAccessProjection, OnboardingAccessIntent>

    var body: some View {
        WithViewStore(store, observe: { $0 }, content: { viewStore in
            VStack(alignment: .leading, spacing: 12) {
                authStatusBanner(viewStore: viewStore)

                HStack(spacing: 8) {
                    if let status = viewStore.status {
                        statusChip(
                            status.isActive ? "Active" : "Inactive",
                            tone: status.isActive ? .success : .error,
                        )
                    }
                    if let message = viewStore.errorMessage {
                        statusChip(message, tone: .neutral)
                    }
                    if let expiresAt = viewStore.trialExpiresAt {
                        statusChip("Expires \(formatDate(expiresAt))", tone: .neutral)
                    }
                }

                if viewStore.isSubmitting {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Activating...")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                actionCTAs(viewStore: viewStore)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        })
    }

    // MARK: - Auth status banner

    @ViewBuilder
    private func authStatusBanner(
        viewStore: ViewStore<OnboardingAccessProjection, OnboardingAccessIntent>,
    ) -> some View {
        if viewStore.isSignInInProgress {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Signing in...")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        } else if viewStore.didSignInFail {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text("Sign in failed. Please try again.")
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            }
        } else if viewStore.hasAccountSession {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Signed in")
                    .font(.system(size: 13))
                    .foregroundStyle(.green)
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.xmark")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Sign in to activate your license.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Action CTAs

    @ViewBuilder
    private func actionCTAs(
        viewStore: ViewStore<OnboardingAccessProjection, OnboardingAccessIntent>,
    ) -> some View {
        if let failure = viewStore.updateEligibilityFailure {
            updateEligibilityRecoveryCTAs(viewStore: viewStore, failure: failure)
        } else {
            if viewStore.canStartLogin {
                Button {
                    viewStore.send(.login)
                } label: {
                    Label("Sign In", systemImage: "person.crop.circle.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewStore.isSignInInProgress)
            }

            if viewStore.hasAccountSession, viewStore.hasDeviceBindingFailure {
                deviceBindingFailureCTAs(viewStore: viewStore)
            } else if viewStore.hasAccountSession,
                      viewStore.isBlocked,
                      let status = viewStore.status
            {
                blockedStatusCTAs(viewStore: viewStore, status: status)
            }

            if viewStore.canRefreshAccess, !viewStore.isComplete {
                Button {
                    viewStore.send(.refresh)
                } label: {
                    Label("Refresh Access", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(viewStore.isSubmitting || viewStore.isSignInInProgress)
            }
        }
    }

    private func updateEligibilityRecoveryCTAs(
        viewStore: ViewStore<OnboardingAccessProjection, OnboardingAccessIntent>,
        failure: UpdateEligibilityFailure,
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This version is not eligible for your update access.")
                .font(.system(size: 13, weight: .semibold))

            Text("Version: \(AppVersionInfo.displayText)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text(updatesThroughText(snapshot: viewStore.snapshot))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text(recoveryDescription(for: failure))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Button {
                viewStore.send(.retry)
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewStore.canRetry && !viewStore.canRefreshAccess)

            HStack {
                Button("Open Account") {
                    viewStore.send(.openAccount)
                }
                Button("Download Eligible Version") {
                    viewStore.send(.openEligibleDownload)
                }
                Button("Contact Support") {
                    viewStore.send(.openAccessHelp)
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private func updatesThroughText(snapshot: AccessStatusSnapshot?) -> String {
        guard let updatesThrough = snapshot?.updatesThrough else {
            return "Updates through: unavailable"
        }
        return "Updates through: \(formatDate(updatesThrough))"
    }

    private func recoveryDescription(for failure: UpdateEligibilityFailure) -> String {
        switch failure {
        case .missingReleaseIdentity, .invalidReleaseIdentity:
            "Voyager could not verify this build's release identity."
        case .missingUpdatesThrough, .invalidUpdatesThrough, .invalidAccessTuple:
            "Your account response did not include valid update eligibility."
        case .buildReleasedAfterUpdatesThrough:
            "This build was released after the date covered by your update access."
        }
    }

    private func deviceBindingFailureCTAs(
        viewStore: ViewStore<OnboardingAccessProjection, OnboardingAccessIntent>,
    ) -> some View {
        VStack(spacing: 10) {
            switch viewStore.primaryCTA {
            case .account:
                Button {
                    viewStore.send(.openAccount)
                } label: {
                    Label("Open Account", systemImage: "person.crop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    viewStore.send(.openAccessHelp)
                } label: {
                    Label("Contact Support", systemImage: "questionmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

            case .retry:
                Button {
                    viewStore.send(.retry)
                } label: {
                    Label("Retry Device Binding", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewStore.canRetry)

            case .login, .webPricing, .next, .pending, .eligibleDownload:
                EmptyView()
            }
        }
    }

    // MARK: - 차단 상태별 CTA 버튼

    private func blockedStatusCTAs(
        viewStore: ViewStore<OnboardingAccessProjection, OnboardingAccessIntent>,
        status: AccessStatus,
    ) -> some View {
        VStack(spacing: 10) {
            switch status {
            case .none, .trialExpired, .revoked, .refunded:
                Button {
                    viewStore.send(.openPricing)
                } label: {
                    Label("View Plans & Pricing", systemImage: "creditcard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            case .coreLicenseActive, .trialActive, .internalTestActive, .networkFailure:
                EmptyView()
            }
        }
    }

    // MARK: - Chip helpers

    private func statusChip(_ text: String, tone: ChipTone) -> some View {
        let colors = chipColors(for: tone)
        return Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(colors.foreground)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(colors.background),
            )
    }

    private enum ChipTone {
        case success
        case error
        case neutral
    }

    private func chipColors(for tone: ChipTone) -> (foreground: Color, background: Color) {
        switch tone {
        case .success:
            (foreground: .green, background: .green.opacity(0.18))
        case .error:
            (foreground: .red, background: .red.opacity(0.18))
        case .neutral:
            (foreground: .secondary, background: .primary.opacity(0.08))
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
