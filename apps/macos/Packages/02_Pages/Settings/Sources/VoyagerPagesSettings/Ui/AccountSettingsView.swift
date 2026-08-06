import ComposableArchitecture
import SwiftUI

struct AccountSettingsView: View {
    let store: StoreOf<AccountSettingsFeature>

    static let signInButtonTitle = "Sign In"
    static var signInButtonAction: AccountSettingsAction {
        .signInTapped
    }

    var body: some View {
        Form {
            Section {
                accountStatusView
            } header: {
                Text("Account")
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
                Button(Self.signInButtonTitle) {
                    store.send(Self.signInButtonAction)
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
                Button(Self.signInButtonTitle) {
                    store.send(Self.signInButtonAction)
                }
            }
        }
    }
}
