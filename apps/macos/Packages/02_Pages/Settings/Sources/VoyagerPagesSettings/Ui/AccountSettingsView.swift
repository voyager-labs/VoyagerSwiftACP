import ComposableArchitecture
import SwiftUI

struct AccountSettingsView: View {
    let store: StoreOf<AccountSettingsFeature>

    var body: some View {
        Form {
            Section {
                accountStatusView
                if store.setAuthState == .signedIn {
                    entitlementStatusView
                }
            } header: {
                Text("Account")
            }

            if store.setAuthState == .signedIn {
                Section {
                    Button("Manage Account") {
                        store.send(.manageAccountTapped)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(NSColor.controlBackgroundColor))
        .confirmationDialog(
            "Sign Out?",
            isPresented: Binding(
                get: { store.isShowingSignOutConfirmation },
                set: { if !$0 { store.send(.signOutCancelled) } },
            ),
        ) {
            Button("Cancel", role: .cancel) {
                store.send(.signOutCancelled)
            }
            Button("Sign Out", role: .destructive) {
                store.send(.signOutConfirmed)
            }
        }
        .onAppear {
            store.send(.access(.onAppear))
        }
    }

    // MARK: - Account status

    @ViewBuilder private var accountStatusView: some View {
        switch store.setAuthState {
        case .signedOut:
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.xmark")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Not signed in")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Sign In") {
                    store.send(.access(.loginTapped))
                }
            }

        case .signInInProgress:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Signing in…")
                    .foregroundStyle(.secondary)
            }

        case .signedIn:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Signed in")
                    .foregroundStyle(.green)
                Spacer()
                Button("Sign Out") {
                    store.send(.signOutTapped)
                }
            }

        case .signInFailed:
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text("Sign in failed")
                    .foregroundStyle(.red)
                Spacer()
                Button("Retry") {
                    store.send(.access(.loginTapped))
                }
            }
        }
    }

    // MARK: - Entitlement status (signed-in 상태에서만 표시)

    @ViewBuilder private var entitlementStatusView: some View {
        switch store.setEntitlementState {
        case .entitlementActive:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("License Active")
                    .foregroundStyle(.green)
            }

        case .entitlementInactive:
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text("License Inactive")
                    .foregroundStyle(.red)
            }

        case .entitlementUnknown:
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("License status unavailable")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
