import ComposableArchitecture
import SwiftUI
import VoyagerFeaturesLicenseAuth

struct UnlockLicenseAuthStepView: View {
    let store: StoreOf<UnlockLicenseAuthFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }, content: { viewStore in
            VStack(alignment: .leading, spacing: 12) {
                authStatusBanner(viewStore: viewStore)

                if viewStore.hasAccountSession {
                    claimInputSection(viewStore: viewStore)
                }

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
    private func authStatusBanner(viewStore: ViewStoreOf<UnlockLicenseAuthFeature>) -> some View {
        switch viewStore.onb002AuthAxis {
        case .signedOut:
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.xmark")
                    .foregroundStyle(.secondary)
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
                Text("Sign in failed. Please try again.")
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            }
        case .signedIn:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Signed in")
                    .font(.system(size: 13))
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Claim input section

    @ViewBuilder
    private func claimInputSection(viewStore: ViewStoreOf<UnlockLicenseAuthFeature>) -> some View {
        Picker("Method", selection: viewStore.binding(
            get: \.claimMode,
            send: { .claimModeChanged($0) },
        )) {
            Text("License Key").tag(LicenseAuthClaimMode.licenseKey)
            Text("Beta Code").tag(LicenseAuthClaimMode.betaCode)
        }
        .pickerStyle(.segmented)

        switch viewStore.claimMode {
        case .licenseKey:
            VStack(alignment: .leading, spacing: 4) {
                Text("License Key")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField(
                    "VOYAGER-CORE-VALID",
                    text: viewStore.binding(
                        get: \.licenseKey,
                        send: { .licenseKeyChanged($0) },
                    ),
                )
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                .controlSize(.large)
            }
        case .betaCode:
            VStack(alignment: .leading, spacing: 4) {
                Text("Beta Code")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField(
                    "VOYAGER-BETA-TRIAL",
                    text: viewStore.binding(
                        get: \.betaCode,
                        send: { .betaCodeChanged($0) },
                    ),
                )
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                .controlSize(.large)
            }
        }

        Text("Enter your license key or beta code to activate Voyager.")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
    }

    // MARK: - Action CTAs

    @ViewBuilder
    private func actionCTAs(viewStore: ViewStoreOf<UnlockLicenseAuthFeature>) -> some View {
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
