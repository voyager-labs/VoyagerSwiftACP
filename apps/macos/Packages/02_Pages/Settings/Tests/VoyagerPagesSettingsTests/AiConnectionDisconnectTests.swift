import ComposableArchitecture
import VoyagerEntitiesAi
@testable import VoyagerPagesSettings
import XCTest

@MainActor
final class AiConnectionDisconnectTests: XCTestCase {
    // MARK: - Disconnect Confirmation Dialog

    func testDisconnectButton_showsConfirmation() async {
        let store = TestStore(
            initialState: AiConnectionRowState(
                provider: .openai,
                connectionState: .connected
            )
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.aiProviderConnectionClient.disconnect = { provider in
                .disconnectSuccess(provider: provider)
            }
        }

        await store.send(.disconnectButtonTapped) { state in
            state.isShowingDisconnectConfirmation = true
        }

        await store.finish()

        XCTAssertEqual(store.state.connectionState, .connected)
        XCTAssertTrue(store.state.isShowingDisconnectConfirmation)
    }

    // MARK: - Cancel Confirmation

    func testDisconnectCancel_hidesConfirmation_staysConnected() async {
        let store = TestStore(
            initialState: AiConnectionRowState(
                provider: .openai,
                connectionState: .connected,
                isShowingDisconnectConfirmation: true
            )
        ) {
            AiConnectionRowReducer()
        }

        await store.send(.disconnectCancel) { state in
            state.isShowingDisconnectConfirmation = false
        }

        await store.finish()

        XCTAssertEqual(store.state.connectionState, .connected)
        XCTAssertFalse(store.state.isShowingDisconnectConfirmation)
    }

    // MARK: - Confirm Disconnect → Success

    func testDisconnectConfirm_success_transitionsToNotVerified() async {
        let store = TestStore(
            initialState: AiConnectionRowState(
                provider: .openai,
                connectionState: .connected,
                isShowingDisconnectConfirmation: true
            )
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.aiProviderConnectionClient.disconnect = { provider in
                .disconnectSuccess(provider: provider)
            }
        }

        await store.send(.disconnectConfirm) { state in
            state.isShowingDisconnectConfirmation = false
            state.flowState = .disconnecting
            state.connectionState = .disconnecting
        }

        await store.receive(\._disconnectResponse) { state in
            state.flowState = .idle
            state.connectionState = .notVerified
            state.statusReason = .none
        }

        await store.finish()

        XCTAssertEqual(store.state.connectionState, .notVerified)
        XCTAssertEqual(store.state.flowState, .idle)
        XCTAssertEqual(store.state.primaryAction, .connect)
    }

    // MARK: - Confirm Disconnect → Failure

    func testDisconnectConfirm_failure_preservesConnected() async {
        let store = TestStore(
            initialState: AiConnectionRowState(
                provider: .openai,
                connectionState: .connected,
                isShowingDisconnectConfirmation: true
            )
        ) {
            AiConnectionRowReducer()
        } withDependencies: {
            $0.aiProviderConnectionClient.disconnect = { provider in
                AiProviderConnectionResult(
                    provider: provider,
                    state: .connected,
                    reason: .none,
                    updatedFile: .empty()
                )
            }
        }

        await store.send(.disconnectConfirm) { state in
            state.isShowingDisconnectConfirmation = false
            state.flowState = .disconnecting
            state.connectionState = .disconnecting
        }

        await store.receive(\._disconnectResponse) { state in
            state.flowState = .idle
            state.connectionState = .connected
            state.statusReason = .none
        }

        await store.finish()

        XCTAssertEqual(store.state.connectionState, .connected)
        XCTAssertNotEqual(store.state.connectionState, .notVerified)
    }

    // MARK: - Guard: Non-Connected State

    func testDisconnectButton_nonConnectedState_isIgnored() async {
        let store = TestStore(
            initialState: AiConnectionRowState(
                provider: .openai,
                connectionState: .notVerified
            )
        ) {
            AiConnectionRowReducer()
        }

        await store.send(.disconnectButtonTapped)
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .notVerified)
        XCTAssertFalse(store.state.isShowingDisconnectConfirmation)
    }

    // MARK: - Guard: Already Disconnecting

    func testDisconnectWhileDisconnecting_noDuplicateEffect() async {
        let store = TestStore(
            initialState: AiConnectionRowState(
                provider: .openai,
                connectionState: .disconnecting,
                flowState: .disconnecting
            )
        ) {
            AiConnectionRowReducer()
        }

        await store.send(.disconnectButtonTapped)
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .disconnecting)
        XCTAssertEqual(store.state.flowState, .disconnecting)
    }
}
