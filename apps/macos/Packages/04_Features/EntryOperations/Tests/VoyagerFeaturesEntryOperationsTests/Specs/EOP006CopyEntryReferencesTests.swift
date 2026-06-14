import AppKit
import ComposableArchitecture
import Foundation
@testable import VoyagerFeaturesEntryOperations
import VoyagerShared
import XCTest

@MainActor
final class EOP006CopyEntryReferencesTests: XCTestCase {
    /// EOP-006-copy_absolute_paths_of_entries: 절대 경로 복사
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`를 FixtureSandbox로 복사
    /// - 기대 결과: 절대 경로 문자열이 정확히 pasteboard에 기록됨
    func testCopyAbsolutePathsOfEntries_success() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let capture = PasteboardCapture()
        let pasteboardClient = PasteboardClient(
            changeCount: { 0 },
            clearContents: { capture.recordClear() },
            writeObjects: { _ in true },
            readObjects: { _, _ in nil },
            setString: { string, _ in
                capture.record(string)
                return true
            },
            string: { _ in capture.lastString },
        )

        let store = EntryOperationsTestSupport.makeStore {
            $0.pasteboardClient = pasteboardClient
        }

        await store.send(.clipboard(.copyAbsolutePaths(paths: [sandbox.fileURL.path])))

        XCTAssertEqual(capture.clearCount, 1)
        XCTAssertEqual(capture.strings, [sandbox.fileURL.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// EOP-006-copy_urls_of_entries: 파일 URL 복사
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`를 FixtureSandbox로 복사
    /// - 기대 결과: file:// URL 문자열이 정확히 pasteboard에 기록됨
    func testCopyURLsOfEntries_success() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let capture = PasteboardCapture()
        let pasteboardClient = PasteboardClient(
            changeCount: { 0 },
            clearContents: { capture.recordClear() },
            writeObjects: { _ in true },
            readObjects: { _, _ in nil },
            setString: { string, _ in
                capture.record(string)
                return true
            },
            string: { _ in capture.lastString },
        )

        let store = EntryOperationsTestSupport.makeStore {
            $0.pasteboardClient = pasteboardClient
        }

        await store.send(.clipboard(.copyURLs(paths: [sandbox.fileURL.path])))

        XCTAssertEqual(capture.clearCount, 1)
        XCTAssertEqual(capture.strings, [sandbox.fileURL.absoluteString])
        let copiedURL = try XCTUnwrap(URL(string: capture.strings[0]))
        XCTAssertEqual(copiedURL, sandbox.fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }
}

private final class PasteboardCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var _clearCount = 0
    private var _strings: [String] = []

    func recordClear() {
        lock.lock()
        defer { lock.unlock() }
        _clearCount += 1
    }

    func record(_ string: String) {
        lock.lock()
        defer { lock.unlock() }
        _strings.append(string)
    }

    var clearCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _clearCount
    }

    var strings: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _strings
    }

    var lastString: String? {
        lock.lock()
        defer { lock.unlock() }
        return _strings.last
    }
}
