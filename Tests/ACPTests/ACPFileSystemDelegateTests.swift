@testable import ACP
import XCTest

final class ACPFileSystemDelegateTests: XCTestCase {
    private var scratchFile: URL!

    override func setUpWithError() throws {
        scratchFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("voy-886-read-\(UUID().uuidString).txt")
        // No trailing newline: components(separatedBy:) would count a
        // trailing empty line, which is not what the window indices mean.
        try "alpha\nbravo\ncharlie".write(to: scratchFile, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        if let scratchFile {
            try? FileManager.default.removeItem(at: scratchFile)
        }
    }

    func testReadsWholeFileWithoutWindow() async throws {
        let delegate = FileSystemDelegate()
        let response = try await delegate.handleFileReadRequest(
            scratchFile.path,
            sessionId: "s1",
            line: nil,
            limit: nil,
        )
        XCTAssertEqual(response.totalLines, 3)
        XCTAssertTrue(response.content.hasPrefix("alpha"))
    }

    func testWindowedReadReturnsRequestedLines() async throws {
        let delegate = FileSystemDelegate()
        let response = try await delegate.handleFileReadRequest(
            scratchFile.path,
            sessionId: "s1",
            line: 2,
            limit: 1,
        )
        XCTAssertEqual(response.content, "bravo")
    }

    func testHostileWindowValuesDoNotTrap() async throws {
        let delegate = FileSystemDelegate()

        // Int.min would overflow `line - 1`; a negative limit would underflow
        // the end index; a line past EOF would slice out of bounds.
        for window in [
            (line: Int?.some(Int.min), limit: Int?.none),
            (line: Int?.some(1), limit: Int?.some(-5)),
            (line: Int?.some(1), limit: Int?.some(Int.max)),
            (line: Int?.some(99), limit: Int?.some(2)),
            (line: Int?.some(Int.max), limit: Int?.some(Int.max)),
        ] {
            let response = try await delegate.handleFileReadRequest(
                scratchFile.path,
                sessionId: "s1",
                line: window.line,
                limit: window.limit,
            )
            XCTAssertEqual(response.totalLines, 3)
        }
    }

    func testWindowPastEOFYieldsEmptyContent() async throws {
        let delegate = FileSystemDelegate()
        let response = try await delegate.handleFileReadRequest(
            scratchFile.path,
            sessionId: "s1",
            line: 99,
            limit: 2,
        )
        XCTAssertEqual(response.content, "")
        XCTAssertEqual(response.totalLines, 3)
    }

    /// An endless character device must terminate within the read cap instead
    /// of blocking the actor forever.
    func testUnboundedDeviceReadIsBounded() async throws {
        let delegate = FileSystemDelegate()
        let startedAt = Date()
        let response = try await delegate.handleFileReadRequest(
            "/dev/zero",
            sessionId: "s1",
            line: 1,
            limit: 8,
        )
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertLessThan(elapsed, 10.0, "the read must stop at the byte cap")
        XCTAssertLessThanOrEqual(response.content.utf8.count, 4_100_000, "the response must respect the byte budget")
        XCTAssertEqual(response.totalLines, 1, "NUL bytes contain no newline, so one giant line")
    }
}
