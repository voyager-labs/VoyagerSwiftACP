import ComposableArchitecture
import VoyagerEntitiesAi
import VoyagerFeaturesAiProviderConnection
@testable import VoyagerPagesSettings
import XCTest

@MainActor
final class AiConnectionDisconnectTests: XCTestCase {
    // MARK: - Disconnect Confirmation Dialog

    // MARK: - Cancel Confirmation

    // MARK: - Confirm Disconnect → Success

    // MARK: - Confirm Disconnect → Failure

    // MARK: - Guard: Non-Connected State

    func testDisconnectButton_nonConnectedState_isIgnored() async {
        let store = TestStore(
            initialState: AiConnectionRowState(
                provider: .openai,
                connectionState: .notVerified,
            ),
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
                flowState: .disconnecting,
            ),
        ) {
            AiConnectionRowReducer()
        }

        await store.send(.disconnectButtonTapped)
        await store.finish()

        XCTAssertEqual(store.state.connectionState, .disconnecting)
        XCTAssertEqual(store.state.flowState, .disconnecting)
    }
}
