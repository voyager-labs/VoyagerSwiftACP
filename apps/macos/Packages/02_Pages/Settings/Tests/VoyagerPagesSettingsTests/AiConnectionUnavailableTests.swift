import ComposableArchitecture
import VoyagerEntitiesAi
@testable import VoyagerPagesSettings
import XCTest

/// Regression tests for the "unavailable in build" provider connection behavior.
///
/// These tests prove unavailable rows stay inert across connect/retry/start-flow paths
/// and never reach browser login, verification, or persistence clients.
@MainActor
final class AiConnectionUnavailableTests: XCTestCase {
    // MARK: - Row-level: API key provider correctly blocks connect from unavailable

    func testConnectButton_unavailable_apiKeyProvider_isIgnored() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .openai, connectionState: .unavailable)
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
            initialState: AiConnectionRowState(provider: .anthropic, connectionState: .unavailable)
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

    // MARK: - Row-level: primary action assertion

    func testPrimaryAction_unavailable_isDisabled() {
        XCTAssertEqual(
            ProviderConnectionState.unavailable.primaryAction,
            .disabled
        )

        let row = AiConnectionRowState(provider: .chatgptCodex, connectionState: .unavailable)
        XCTAssertEqual(row.primaryAction, .disabled)
    }

    // MARK: - Row-level: OAuth provider unavailable guard

    func testConnectButton_unavailable_oAuthProvider_isIgnored() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex, connectionState: .unavailable)
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
            initialState: AiConnectionRowState(provider: .chatgptCodex, connectionState: .unavailable)
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

    // MARK: - Dependency trap: unavailable row blocks direct start actions

    func testUnavailableOAuthRow_directStartActions_areIgnored() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex, connectionState: .unavailable)
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

    // MARK: - Dependency trap: API key provider never invokes OAuth

    func testUnavailableRow_apiKeyProvider_doesNotInvokeBrowserLogin() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .openai, connectionState: .unavailable)
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
            initialState: AiConnectionRowState(provider: .openai, connectionState: .unavailable)
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

    // MARK: - Feature-level: Restore from persisted unavailable snapshot

    func testRestore_unavailableProvider_remainsUnavailable() async {
        let unavailableFile = AIConnectionsFile.singleProvider(
            .chatgptCodex,
            state: .unavailable,
            errorCode: .providerUnsupportedInBuild
        )

        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { unavailableFile }
            $0.aiProviderVerificationClient.verify = { _, _ in .unsupportedProvider }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .chatgptCodex]?.connectionState = .checkingStatus
            state.rows[id: .chatgptCodex]?.statusReason = .none
        }

        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .chatgptCodex]?.connectionState = .unavailable
            state.rows[id: .chatgptCodex]?.statusReason = .providerUnsupportedInBuild
        }

        await store.finish()

        let codexRow = store.state.rows[id: .chatgptCodex]
        XCTAssertEqual(codexRow?.connectionState, .unavailable)
        XCTAssertEqual(codexRow?.statusReason, .providerUnsupportedInBuild)
    }

    func testRestore_unavailableProvider_hasDisabledPrimaryAction() async {
        let unavailableFile = AIConnectionsFile.singleProvider(
            .openai,
            state: .unavailable,
            errorCode: .providerUnsupportedInBuild
        )

        let store = TestStore(initialState: AiSettingsState()) {
            AiSettingsFeature()
        } withDependencies: {
            $0.aiConnectionsFileClient.load = { unavailableFile }
            $0.aiProviderVerificationClient.verify = { _, _ in .unsupportedProvider }
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
            state.bootstrapPhase = .loading
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.bootstrapPhase = .loaded
            state.rows[id: .openai]?.connectionState = .checkingStatus
            state.rows[id: .openai]?.statusReason = .none
        }

        await store.receive(\.bootstrapVerificationCompleted) { state in
            state.rows[id: .openai]?.connectionState = .unavailable
            state.rows[id: .openai]?.statusReason = .providerUnsupportedInBuild
        }

        await store.finish()

        let openaiRow = store.state.rows[id: .openai]
        XCTAssertEqual(openaiRow?.connectionState, .unavailable)
        XCTAssertEqual(openaiRow?.primaryAction, .disabled)
    }
}
