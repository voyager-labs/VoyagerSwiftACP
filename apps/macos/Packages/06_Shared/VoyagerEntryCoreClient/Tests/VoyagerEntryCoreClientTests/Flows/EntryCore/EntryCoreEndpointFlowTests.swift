import Darwin
import VoyagerEntryCoreClient
import XCTest

final class EntryCoreEndpointFlowTests: XCTestCase {
    func testAcceptsAbsolutePathWithoutChangingItsRepresentation() throws {
        let path = "/tmp/../voyager-entry-core.sock"

        let endpoint = try EntryCoreEndpoint(path: path)

        XCTAssertEqual(endpoint.path, path)
    }

    func testRejectsEmptyPath() {
        XCTAssertThrowsError(try EntryCoreEndpoint(path: "")) { error in
            XCTAssertEqual(error as? EntryCoreClientError, .invalidEndpoint)
        }
    }

    func testRejectsRelativePath() {
        XCTAssertThrowsError(try EntryCoreEndpoint(path: "tmp/entry-core.sock")) { error in
            XCTAssertEqual(error as? EntryCoreClientError, .invalidEndpoint)
        }
    }

    func testRejectsEmbeddedNUL() {
        let path = "/tmp/entry" + String(UnicodeScalar(0)) + "core.sock"

        XCTAssertThrowsError(try EntryCoreEndpoint(path: path)) { error in
            XCTAssertEqual(error as? EntryCoreClientError, .invalidEndpoint)
        }
    }

    func testAcceptsMaximumASCIIPathThatLeavesRoomForTrailingNUL() throws {
        let path = byteSizedPath(count: sunPathCapacity - 1, multibyte: false)

        let endpoint = try EntryCoreEndpoint(path: path)

        XCTAssertEqual(endpoint.path.utf8.count, sunPathCapacity - 1)
    }

    func testRejectsASCIIPathThatFillsSunPathWithoutTrailingNULRoom() {
        let path = byteSizedPath(count: sunPathCapacity, multibyte: false)

        XCTAssertThrowsError(try EntryCoreEndpoint(path: path)) { error in
            XCTAssertEqual(error as? EntryCoreClientError, .invalidEndpoint)
        }
    }

    func testAcceptsMaximumMultibytePathThatLeavesRoomForTrailingNUL() throws {
        let path = byteSizedPath(count: sunPathCapacity - 1, multibyte: true)

        let endpoint = try EntryCoreEndpoint(path: path)

        XCTAssertEqual(endpoint.path, path)
        XCTAssertEqual(endpoint.path.utf8.count, sunPathCapacity - 1)
    }

    func testRejectsMultibytePathThatFillsSunPathWithoutTrailingNULRoom() {
        let path = byteSizedPath(count: sunPathCapacity, multibyte: true)

        XCTAssertThrowsError(try EntryCoreEndpoint(path: path)) { error in
            XCTAssertEqual(error as? EntryCoreClientError, .invalidEndpoint)
        }
    }

    private var sunPathCapacity: Int {
        MemoryLayout.size(ofValue: sockaddr_un().sun_path)
    }

    private func byteSizedPath(count: Int, multibyte: Bool) -> String {
        var path = "/"
        if multibyte {
            while path.utf8.count + "한".utf8.count <= count {
                path += "한"
            }
        }
        path += String(repeating: "a", count: count - path.utf8.count)
        return path
    }
}
