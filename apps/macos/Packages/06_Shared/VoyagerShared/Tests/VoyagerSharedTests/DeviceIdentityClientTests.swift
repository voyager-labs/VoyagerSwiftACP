import Dependencies
@testable import VoyagerShared
import XCTest

final class DeviceIdentityClientTests: XCTestCase {
    func testTestDoubleReturnsExpectedDeviceId() throws {
        let id = try withDependencies {
            $0.deviceIdentityClient = .testValue
        } operation: {
            @Dependency(\.deviceIdentityClient)
            var client
            return try client.deviceId()
        }
        XCTAssertEqual(id, "test-device-id")
    }

    func testLiveValueCompiles() {
        _ = DeviceIdentityClient.liveValue
    }
}
