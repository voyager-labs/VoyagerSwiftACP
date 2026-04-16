import Foundation
@testable import VoyagerEntitiesAI
import XCTest

final class AIConnectionPathHelperTests: XCTestCase {
    // MARK: - Path determinism from injected home directory

    func testPayloadURL_isDeterministic() {
        let home = URL(fileURLWithPath: "/tmp/fake_home")
        let url = AIConnectionFSLocation.payloadFileURL(homeDirectoryURL: home)

        XCTAssertEqual(
            url.path,
            "/tmp/fake_home/.voyager/config/ai_connections.json",
        )
    }

    func testLockURL_isSiblingOfPayload() {
        let home = URL(fileURLWithPath: "/tmp/fake_home")
        let url = AIConnectionFSLocation.lockFileURL(homeDirectoryURL: home)

        XCTAssertEqual(
            url.path,
            "/tmp/fake_home/.voyager/config/ai_connections.lock",
        )
    }

    func testDirectoryURL_pointsToConfigDir() {
        let home = URL(fileURLWithPath: "/tmp/fake_home")
        let url = AIConnectionFSLocation.directoryURL(homeDirectoryURL: home)

        XCTAssertEqual(
            url.path,
            "/tmp/fake_home/.voyager/config",
        )
    }

    func testQuarantineURL_containsTimestamp() {
        let home = URL(fileURLWithPath: "/tmp/fake_home")
        let dir = AIConnectionFSLocation.directoryURL(homeDirectoryURL: home)
        let timestamp = Date(timeIntervalSince1970: 1_760_000_000)
        let url = AIConnectionFSLocation.quarantineFileURL(
            directoryURL: dir,
            generatedAt: timestamp,
        )

        XCTAssertTrue(url.path.hasPrefix("/tmp/fake_home/.voyager/config/ai_connections.corrupted-"))
        XCTAssertTrue(url.path.hasSuffix(".json"))
    }

    func testQuarantineURL_replacesColonsInTimestamp() {
        let home = URL(fileURLWithPath: "/tmp/fake_home")
        let dir = AIConnectionFSLocation.directoryURL(homeDirectoryURL: home)
        let url = AIConnectionFSLocation.quarantineFileURL(directoryURL: dir)

        // ISO8601 timestamps contain colons which are invalid in macOS filenames
        XCTAssertFalse(url.lastPathComponent.contains(":"))
    }

    // MARK: - Different home directories produce different paths

    func testDifferentHomeDirectories_produceDifferentPayloadPaths() {
        let home1 = URL(fileURLWithPath: "/Users/alice")
        let home2 = URL(fileURLWithPath: "/Users/bob")

        let url1 = AIConnectionFSLocation.payloadFileURL(homeDirectoryURL: home1)
        let url2 = AIConnectionFSLocation.payloadFileURL(homeDirectoryURL: home2)

        XCTAssertNotEqual(url1.path, url2.path)
        XCTAssertTrue(url1.path.hasPrefix("/Users/alice/"))
        XCTAssertTrue(url2.path.hasPrefix("/Users/bob/"))
    }
}
