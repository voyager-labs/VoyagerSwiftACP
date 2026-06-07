import ComposableArchitecture
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiProviderConnection
import XCTest

/// Regression tests for the "unavailable in build" provider connection behavior.
///
/// These tests prove unavailable rows stay inert across connect/retry/start-flow paths
/// and never reach browser login, verification, or persistence clients.
@MainActor
final class AiProviderConnectionUnavailableTests: XCTestCase {
    func testConnectButton_unavailable_apiKeyProvider_isIgnored() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .openai, connectionState: .unavailable),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.codexNativeAuthClient.startBrowserLogin = {
                XCTFail("startBrowserLogin must not be invoked for unavailable API key provider")
                return AsyncThrowingStream { $0.finish() }
            }
        }

        await store.send(.connectButtonTapped)
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .unavailable)
        XCTAssertEqual(store.state.flowState, .idle)
    }

    func testRetryButton_unavailable_apiKeyProvider_isIgnored() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .anthropic, connectionState: .unavailable),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.codexNativeAuthClient.startBrowserLogin = {
                XCTFail("startBrowserLogin must not be invoked for unavailable API key provider")
                return AsyncThrowingStream { $0.finish() }
            }
        }

        await store.send(.retryButtonTapped)
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .unavailable)
        XCTAssertEqual(store.state.flowState, .idle)
    }

    func testPrimaryAction_unavailable_isDisabled() {
        XCTAssertEqual(
            ProviderConnectionState.unavailable.primaryAction,
            .disabled,
        )

        let row = AiConnectionRowState(provider: .chatgptCodex, connectionState: .unavailable)
        XCTAssertEqual(row.primaryAction, .disabled)
    }

    func testConnectButton_unavailable_oAuthProvider_isIgnored() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex, connectionState: .unavailable),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.codexNativeAuthClient.startBrowserLogin = {
                XCTFail("startBrowserLogin must not be invoked for unavailable OAuth provider")
                return AsyncThrowingStream { $0.finish() }
            }
            $0.codexNativeAuthClient.startDeviceAuth = {
                XCTFail("startDeviceAuth must not be invoked for unavailable OAuth provider")
                throw CodexNativeAuthError.loginUnavailable
            }
            $0.aiProviderVerificationClient.verify = { _, _ in
                XCTFail("verify must not be invoked for unavailable OAuth provider")
                return .valid
            }
            $0.aiProviderConnectionClient.connectOAuth = { _, _, _ in
                XCTFail("connectOAuth must not be invoked for unavailable OAuth provider")
                return .init(provider: .chatgptCodex, state: .connected, reason: .none, updatedFile: .empty())
            }
        }

        await store.send(.connectButtonTapped)
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .unavailable)
        XCTAssertEqual(store.state.flowState, .idle)
    }

    func testRetryButton_unavailable_oAuthProvider_isIgnored() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex, connectionState: .unavailable),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.codexNativeAuthClient.startBrowserLogin = {
                XCTFail("startBrowserLogin must not be invoked for unavailable OAuth provider")
                return AsyncThrowingStream { $0.finish() }
            }
            $0.codexNativeAuthClient.startDeviceAuth = {
                XCTFail("startDeviceAuth must not be invoked for unavailable OAuth provider")
                throw CodexNativeAuthError.loginUnavailable
            }
            $0.aiProviderVerificationClient.verify = { _, _ in
                XCTFail("verify must not be invoked for unavailable OAuth provider")
                return .valid
            }
            $0.aiProviderConnectionClient.connectOAuth = { _, _, _ in
                XCTFail("connectOAuth must not be invoked for unavailable OAuth provider")
                return .init(provider: .chatgptCodex, state: .connected, reason: .none, updatedFile: .empty())
            }
        }

        await store.send(.retryButtonTapped)
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .unavailable)
        XCTAssertEqual(store.state.flowState, .idle)
    }

    func testUnavailableOAuthRow_directStartActions_areIgnored() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex, connectionState: .unavailable),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.codexNativeAuthClient.startBrowserLogin = {
                XCTFail("startBrowserLogin must not be invoked for unavailable OAuth provider")
                return AsyncThrowingStream { $0.finish() }
            }
            $0.codexNativeAuthClient.startDeviceAuth = {
                XCTFail("startDeviceAuth must not be invoked for unavailable OAuth provider")
                throw CodexNativeAuthError.loginUnavailable
            }
            $0.aiProviderVerificationClient.verify = { _, _ in
                XCTFail("verify must not be invoked for unavailable OAuth provider")
                return .valid
            }
            $0.aiProviderConnectionClient.connectOAuth = { _, _, _ in
                XCTFail("connectOAuth must not be invoked for unavailable OAuth provider")
                return .init(provider: .chatgptCodex, state: .connected, reason: .none, updatedFile: .empty())
            }
        }

        await store.send(.startBrowserLogin)
        await store.send(.startDeviceAuth)
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .unavailable)
        XCTAssertEqual(store.state.flowState, .idle)
    }

    func testUnavailableRow_apiKeyProvider_doesNotInvokeBrowserLogin() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .openai, connectionState: .unavailable),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.codexNativeAuthClient.startBrowserLogin = {
                XCTFail("startBrowserLogin must not be called for unavailable API key provider")
                return AsyncThrowingStream { $0.finish() }
            }
            $0.aiProviderVerificationClient.verify = { _, _ in
                XCTFail("verify must not be called from connectButtonTapped for unavailable row")
                return .valid
            }
            $0.aiProviderConnectionClient.connectAPIKey = { _, _, _ in
                XCTFail("connectAPIKey must not be called from connectButtonTapped for unavailable row")
                return .init(provider: .openai, state: .connected, reason: .none, updatedFile: .empty())
            }
            $0.aiProviderConnectionClient.connectOAuth = { _, _, _ in
                XCTFail("connectOAuth must not be called from connectButtonTapped for unavailable row")
                return .init(provider: .openai, state: .connected, reason: .none, updatedFile: .empty())
            }
        }

        await store.send(.connectButtonTapped)
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .unavailable)
        XCTAssertEqual(store.state.flowState, .idle)
    }

    func testUnavailableRow_apiKeySubmit_isIgnored() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .openai, connectionState: .unavailable),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.aiProviderVerificationClient.verify = { _, _ in
                XCTFail("verify must not be invoked for unavailable API key provider")
                return .valid
            }
            $0.aiProviderConnectionClient.connectAPIKey = { _, _, _ in
                XCTFail("connectAPIKey must not be invoked for unavailable API key provider")
                return .init(provider: .openai, state: .connected, reason: .none, updatedFile: .empty())
            }
        }

        await store.send(.submitAPIKey("test-key"))
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .unavailable)
        XCTAssertEqual(store.state.flowState, .idle)
    }
}
