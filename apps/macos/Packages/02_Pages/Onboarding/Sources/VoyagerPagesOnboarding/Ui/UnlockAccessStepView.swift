import ComposableArchitecture
import SwiftUI
import VoyagerFeaturesAccountAccess

struct UnlockAccessStepView: View {
    let store: StoreOf<AccountAccessFeature>

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
            .onAppear {
                viewStore.send(.onAppear)
            }
        })
    }

    // MARK: - Auth status banner

    @ViewBuilder
    private func authStatusBanner(viewStore: ViewStoreOf<AccountAccessFeature>) -> some View {
        switch viewStore.accountAccessAuthAxis {
        case .signedOut:
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.xmark")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Sign in to activate your license.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        case .signInInProgress:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Signing in...")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        case .signInFailed:
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text("Sign in failed. Please try again.")
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            }
        case .signedIn:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Signed in")
                    .font(.system(size: 13))
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Action CTAs

    @ViewBuilder
    private func actionCTAs(viewStore: ViewStoreOf<AccountAccessFeature>) -> some View {
        if viewStore.canStartLogin {
            Button {
                viewStore.send(.loginTapped)
            } label: {
                Label("Sign In", systemImage: "person.crop.circle.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewStore.isSignInInProgress)
        }

        if viewStore.accountAccessAuthAxis == .signedIn,
           let failure = viewStore.deviceBindingFailure
        {
            deviceBindingFailureCTAs(viewStore: viewStore, failure: failure)
        } else if viewStore.accountAccessAuthAxis == .signedIn,
                  viewStore.accountAccessStepState == .blocked,
                  let status = viewStore.status
        {
            blockedStatusCTAs(viewStore: viewStore, status: status)
        }

        if viewStore.canRefreshAccess, !viewStore.isComplete {
            Button {
                viewStore.send(.refreshAccessTapped)
            } label: {
                Label("Refresh Access", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(viewStore.isSubmitting || viewStore.isSignInInProgress)
        }
    }

    private func deviceBindingFailureCTAs(
        viewStore: ViewStoreOf<AccountAccessFeature>,
        failure _: DeviceBindingFailure,
    ) -> some View {
        VStack(spacing: 10) {
            switch viewStore.accessUnlockPrimaryCTA {
            case .account:
                Button {
                    viewStore.send(.openAccountTapped)
                } label: {
                    Label("Open Account", systemImage: "person.crop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    viewStore.send(.openAccessHelpTapped)
                } label: {
                    Label("Contact Support", systemImage: "questionmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

            case .retry:
                Button {
                    viewStore.send(.retryTapped)
                } label: {
                    Label("Retry Device Binding", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewStore.canRetry)

            case .login, .webPricing, .next, .pending:
                EmptyView()
            }
        }
    }

    // MARK: - 차단 상태별 CTA 버튼

    private func blockedStatusCTAs(
        viewStore: ViewStoreOf<AccountAccessFeature>,
        status: AccessStatus,
    ) -> some View {
        VStack(spacing: 10) {
            switch status {
            case .none, .trialExpired, .revoked, .refunded:
                Button {
                    viewStore.send(.openPricingTapped)
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
