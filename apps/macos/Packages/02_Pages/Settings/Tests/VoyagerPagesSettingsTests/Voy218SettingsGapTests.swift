import ComposableArchitecture
import VoyagerEntitiesAi
@testable import VoyagerPagesSettings
import XCTest

/// Recovered from old Voy218SettingsGapTests (9d3be186).
/// Adapted from parent-feature scoping to direct row-reducer testing.
@MainActor
final class Voy218SettingsGapTests: XCTestCase {
    private func makeCredential(
        accessToken: String = "mock-access-token",
        refreshToken: String? = "mock-refresh-token"
    ) -> OAuthCredentialFile {
        OAuthCredentialFile(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: "Bearer",
            scopes: ["openid", "profile"],
            expiresAtMs: nil
        )
    }

    // MARK: - Retry re-triggers browser login

    func testRetryForOAuth_retriggersBrowserLogin() async {
        let credential = makeCredential()

        let store = TestStore(
            initialState: AiConnectionRowState(
                provider: .chatgptCodex,
                connectionState: .connectionFailed,
                statusReason: .missingCredential,
                flowState: .idle,
                enteredKey: "",
                isVerifying: false,
                isShowingDisconnectConfirmation: false
            )
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.codexNativeAuthClient.startBrowserLogin = {
                AsyncThrowingStream { continuation in
                    continuation.yield(.inProgress)
                    continuation.yield(.completed(credential))
                    continuation.finish()
                }
            }
            $0.aiProviderConnectionClient.connectOAuth = { provider, _, connectionState in
                AiProviderConnectionResult(
                    provider: provider,
                    state: connectionState,
                    reason: .none,
                    updatedFile: AIConnectionsFile.empty()
                )
            }
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
        }

        await store.send(.retryButtonTapped)

        await store.receive(\.startBrowserLogin) { state in
            state.flowState = .browserLoginInProgress
            state.connectionState = .connectInProgress
        }

        await store.receive(\.browserLoginCompleted) { state in
            state.connectionState = .connected
            state.flowState = .idle
            state.statusReason = .none
        }

        await store.finish()

        XCTAssertEqual(store.state.connectionState, .connected)
    }
}
