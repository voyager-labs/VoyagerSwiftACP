import ComposableArchitecture
import VoyagerEntitiesAi
@testable import VoyagerPagesSettings
import XCTest

/// Regression tests for the "unavailable in build" provider connection behavior.
///
/// Two scenarios:
/// 1. **API key providers** (openai, anthropic): `handleConnect` returns `.none` for non-OAuth
///    providers, so unavailable rows correctly block connect/retry.
/// 2. **OAuth providers** (chatgptCodex): `handleConnect` does NOT guard against
///    `.unavailable` `connectionState`. If the provider has a valid descriptor, the connect
///    flow proceeds. These tests document this as a known gap.
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

    // MARK: - Row-level: OAuth provider gap documentation

    // GAP: `handleConnect` does NOT guard against `.unavailable` connectionState.
    // For OAuth providers that have a valid `ProviderDescriptor`, the connect flow
    // proceeds even when the row is in `.unavailable` state.
    // Expected fix: add `guard state.connectionState != .unavailable else { return .none }`
    // before the descriptor lookup in `handleConnect`.
    func testConnectButton_unavailable_oAuthProvider_proceedsToLogin_DOCUMENTED_GAP() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex, connectionState: .unavailable)
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.codexNativeAuthClient.startBrowserLogin = {
                AsyncThrowingStream { continuation in
                    continuation.yield(.failed(.loginUnavailable))
                    continuation.finish()
                }
            }
        }

        // Despite `.unavailable`, handleConnect proceeds to startBrowserLogin for OAuth providers
        await store.send(.connectButtonTapped)

        await store.receive(\.startBrowserLogin) { state in
            state.flowState = .browserLoginInProgress
            state.connectionState = .connectInProgress
        }

        await store.receive(\.browserLoginFailed) { state in
            state.flowState = .idle
            state.connectionState = .connectionFailed
            state.statusReason = .providerUnsupportedInBuild
        }

        await store.finish()
    }

    func testRetryButton_unavailable_oAuthProvider_proceedsToLogin_DOCUMENTED_GAP() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .chatgptCodex, connectionState: .unavailable)
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.codexNativeAuthClient.startBrowserLogin = {
                AsyncThrowingStream { continuation in
                    continuation.yield(.failed(.loginUnavailable))
                    continuation.finish()
                }
            }
        }

        await store.send(.retryButtonTapped)

        await store.receive(\.startBrowserLogin) { state in
            state.flowState = .browserLoginInProgress
            state.connectionState = .connectInProgress
        }

        await store.receive(\.browserLoginFailed) { state in
            state.flowState = .idle
            state.connectionState = .connectionFailed
            state.statusReason = .providerUnsupportedInBuild
        }

        await store.finish()
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
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
        }

        await store.receive(\.bootstrapCompleted) { state in
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
        }

        await store.send(.onAppear) { state in
            state.didBootstrap = true
        }

        await store.receive(\.bootstrapCompleted) { state in
            state.rows[id: .openai]?.connectionState = .unavailable
            state.rows[id: .openai]?.statusReason = .providerUnsupportedInBuild
        }

        await store.finish()

        let openaiRow = store.state.rows[id: .openai]
        XCTAssertEqual(openaiRow?.connectionState, .unavailable)
        XCTAssertEqual(openaiRow?.primaryAction, .disabled)
    }
}
