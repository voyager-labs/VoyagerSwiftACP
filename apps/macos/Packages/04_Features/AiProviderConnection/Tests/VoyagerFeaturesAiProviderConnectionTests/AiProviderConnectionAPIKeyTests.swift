import ComposableArchitecture
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiProviderConnection
import XCTest

private actor APIKeyConnectionController {
    private var continuation: CheckedContinuation<AiProviderConnectionResult, Never>?

    func connect(
        provider _: AiProvider,
        connectionState _: ProviderConnectionState,
    ) async -> AiProviderConnectionResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(with result: AiProviderConnectionResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

@MainActor
final class AiProviderConnectionAPIKeyTests: XCTestCase {
    func testOpenAIAPIKeyConnectSuccessMovesRowToConnected() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .openai),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
            $0.aiProviderConnectionClient.connectAPIKey = { provider, _, connectionState in
                .connectSuccess(provider: provider, state: connectionState)
            }
        }

        await store.send(.submitAPIKey("  sk-valid  ")) { state in
            state.enteredKey = "sk-valid"
            state.connectionState = .connectInProgress
            state.flowState = .connecting
            state.isVerifying = true
        }
        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
        }
        await store.receive(\.connectionResponse) { state in
            state.connectionState = .connected
            state.statusReason = .none
            state.flowState = .idle
            state.enteredKey = ""
        }
        await store.finish()
    }

    func testAnthropicAPIKeyInvalidCredentialShowsConnectionFailed() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .anthropic),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.aiProviderVerificationClient.verify = { _, _ in .invalid(.invalidAPIKey) }
        }

        await store.send(.submitAPIKey("bad-key")) { state in
            state.enteredKey = "bad-key"
            state.connectionState = .connectInProgress
            state.flowState = .connecting
            state.isVerifying = true
        }
        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.connectionState = .connectionFailed
            state.statusReason = .invalidAPIKey
            state.flowState = .idle
        }
        await store.finish()

        XCTAssertEqual(store.state.primaryAction, .retry)
    }

    func testSubmitAPIKey_cancelAfterVerificationPreventsConnectionCompletion() async {
        let controller = APIKeyConnectionController()
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .openai),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
            $0.aiProviderConnectionClient.connectAPIKey = { provider, _, connectionState in
                await controller.connect(provider: provider, connectionState: connectionState)
            }
        }

        await store.send(.submitAPIKey("sk-test-valid-key")) { state in
            state.enteredKey = "sk-test-valid-key"
            state.connectionState = .connectInProgress
            state.flowState = .connecting
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
        }

        await store.send(.cancelButtonTapped) { state in
            state.flowState = .idle
            state.isVerifying = false
            state.connectionState = .notVerified
        }

        await controller.resume(with: AiProviderConnectionResult(
            provider: .openai,
            state: .connected,
            reason: .none,
            updatedFile: AIConnectionsFile.empty(),
        ))

        await Task.yield()
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .notVerified)
        XCTAssertEqual(store.state.flowState, .idle)
    }

    func testSubmitAPIKey_networkError_showsConnectionFailed() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .openai),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.aiProviderVerificationClient.verify = { _, _ in .networkError }
        }

        await store.send(.submitAPIKey("sk-test")) { state in
            state.enteredKey = "sk-test"
            state.connectionState = .connectInProgress
            state.flowState = .connecting
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
            state.connectionState = .connectionFailed
            state.statusReason = .networkUnavailable
            state.flowState = .idle
        }

        await store.finish()
    }

    func testSubmitAPIKey_emptyKey_isIgnored() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .openai),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
        }

        await store.send(.submitAPIKey(""))
        await store.finish()
    }

    func testSubmitAPIKey_whitespaceOnlyKey_isIgnored() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .openai),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
        }

        await store.send(.submitAPIKey("   "))
        await store.finish()
    }

    func testCancelDuringConnect_resetsToIdle() async {
        let store = TestStore(
            initialState: AiConnectionRowState(
                provider: .openai,
                connectionState: .connectInProgress,
                flowState: .connecting,
                isVerifying: true,
            ),
        ) {
            AiConnectionRowReducer()
        }

        await store.send(.cancelButtonTapped) { state in
            state.flowState = .idle
            state.isVerifying = false
            state.connectionState = .notVerified
        }

        await store.finish()
    }

    func testSubmitAPIKey_trimWhitespace() async {
        let store = TestStore(
            initialState: AiConnectionRowState(provider: .openai),
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.aiProviderVerificationClient.verify = { _, _ in .valid }
            $0.aiProviderConnectionClient.connectAPIKey = { provider, _, connectionState in
                AiProviderConnectionResult(
                    provider: provider,
                    state: connectionState,
                    reason: .none,
                    updatedFile: AIConnectionsFile.empty(),
                )
            }
        }

        await store.send(.submitAPIKey("  sk-trimmed  ")) { state in
            state.enteredKey = "sk-trimmed"
            state.connectionState = .connectInProgress
            state.flowState = .connecting
            state.isVerifying = true
        }

        await store.receive(\.verificationResponse) { state in
            state.isVerifying = false
        }

        await store.receive(\.connectionResponse) { state in
            state.connectionState = .connected
            state.statusReason = .none
            state.flowState = .idle
            state.enteredKey = ""
        }

        await store.finish()
    }
}
