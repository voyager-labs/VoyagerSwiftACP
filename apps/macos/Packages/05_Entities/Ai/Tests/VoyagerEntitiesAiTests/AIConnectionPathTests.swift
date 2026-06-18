@testable import VoyagerEntitiesAi
import XCTest

final class AIConnectionPathTests: XCTestCase {
    func testPayloadFileURL() {
        let home = URL(fileURLWithPath: "/Users/test")
        let url = AIConnectionFSLocation.payloadFileURL(homeDirectoryURL: home)
        XCTAssertEqual(url.path, "/Users/test/.voyager/auth.json")
    }

    func testLockFileURL() {
        let home = URL(fileURLWithPath: "/Users/test")
        let url = AIConnectionFSLocation.lockFileURL(homeDirectoryURL: home)
        XCTAssertEqual(url.path, "/Users/test/.voyager/auth.lock")
    }

    func testDirectoryURL() {
        let home = URL(fileURLWithPath: "/Users/test")
        let url = AIConnectionFSLocation.directoryURL(homeDirectoryURL: home)
        XCTAssertEqual(url.path, "/Users/test/.voyager")
    }

    func testQuarantineFileURLContainsPrefix() {
        let dir = URL(fileURLWithPath: "/Users/test/.voyager")
        let url = AIConnectionFSLocation.quarantineFileURL(directoryURL: dir)
        XCTAssertTrue(url.lastPathComponent.hasPrefix("auth.corrupted-"))
        XCTAssertTrue(url.lastPathComponent.hasSuffix(".json"))
    }

    func testQuarantineFileURLWithExplicitDate() {
        let dir = URL(fileURLWithPath: "/tmp")
        let date = Date(timeIntervalSince1970: 0)
        let url = AIConnectionFSLocation.quarantineFileURL(
            directoryURL: dir,
            generatedAt: date,
        )
        XCTAssertTrue(url.lastPathComponent.contains("auth.corrupted-"))
    }
}
