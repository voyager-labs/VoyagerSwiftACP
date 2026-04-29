@testable import VoyagerEntitiesAi
import XCTest

final class ProviderConnectionStateTests: XCTestCase {
    // MARK: - SET-007 statuses

    func testAllSevenConnectionStatesExist() {
        let expected: Set<ProviderConnectionState> = [
            .notVerified,
            .connectInProgress,
            .connected,
            .connectionFailed,
            .disconnecting,
            .disconnected,
            .unavailable,
        ]
        XCTAssertEqual(Set(ProviderConnectionState.allCases), expected)
        XCTAssertEqual(ProviderConnectionState.allCases.count, 7)
    }

    // MARK: - Action mapping

    func testNotVerified_mapsToConnect() {
        XCTAssertEqual(ProviderConnectionState.notVerified.primaryAction, .connect)
    }

    func testConnectInProgress_mapsToCancel() {
        XCTAssertEqual(ProviderConnectionState.connectInProgress.primaryAction, .cancel)
    }

    func testConnected_mapsToDisconnect() {
        XCTAssertEqual(ProviderConnectionState.connected.primaryAction, .disconnect)
    }

    func testConnectionFailed_mapsToRetry() {
        XCTAssertEqual(ProviderConnectionState.connectionFailed.primaryAction, .retry)
    }

    func testDisconnecting_mapsToDisabled() {
        XCTAssertEqual(ProviderConnectionState.disconnecting.primaryAction, .disabled)
    }

    func testDisconnected_mapsToConnect() {
        XCTAssertEqual(ProviderConnectionState.disconnected.primaryAction, .connect)
    }

    func testUnavailable_mapsToDisabled() {
        XCTAssertEqual(ProviderConnectionState.unavailable.primaryAction, .disabled)
    }

    func testEveryState_hasActionMapping() {
        for state in ProviderConnectionState.allCases {
            let action = state.primaryAction
            XCTAssertTrue(
                [.connect, .retry, .disconnect, .cancel, .disabled].contains(action),
                "State \(state) returned unmapped action \(action)"
            )
        }
    }

    // MARK: - Status reasons

    func testProviderStatusReason_allCases() {
        XCTAssertGreaterThanOrEqual(ProviderStatusReason.allCases.count, 10)
    }

    // MARK: - Codable

    func testConnectionState_roundTrips() throws {
        for state in ProviderConnectionState.allCases {
            let encoded = try JSONEncoder().encode(state)
            let decoded = try JSONDecoder().decode(ProviderConnectionState.self, from: encoded)
            XCTAssertEqual(decoded, state)
        }
    }

    func testStatusReason_roundTrips() throws {
        for reason in ProviderStatusReason.allCases {
            let encoded = try JSONEncoder().encode(reason)
            let decoded = try JSONDecoder().decode(ProviderStatusReason.self, from: encoded)
            XCTAssertEqual(decoded, reason)
        }
    }
}
