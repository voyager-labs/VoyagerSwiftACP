import AppKit
import ComposableArchitecture
import Foundation
@testable import VoyagerFeaturesEntryOperations
import VoyagerShared
import XCTest

@MainActor
final class EOP006CopyEntryReferencesTests: XCTestCase {
    /// EOP-006-copy_absolute_paths_of_entries: 절대 경로 복사
    /// - 검증 내용: 절대 경로 복사 action이 선택 항목 경로를 pasteboard 문자열로 기록하는지 확인합니다.
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

        // 비-undo copyPath 명령도 pasteboard write 성공 aggregate를 담아 한 건 수신한다.
        await store.receive { action in
            guard case let .lifecycle(.entryActionCompleted(record)) = action else { return false }
            return record.operationKind == .copyPath
                && record.succeededCount == 1
                && record.failedCount == 0
        }

        XCTAssertEqual(capture.clearCount, 1)
        XCTAssertEqual(capture.strings, [sandbox.fileURL.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// EOP-006-copy_urls_of_entries: 파일 URL 복사
    /// - 검증 내용: URL 복사 action이 선택 항목 URL 문자열을 pasteboard에 기록하는지 확인합니다.
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

        // 비-undo copyPath 명령도 pasteboard write 성공 aggregate를 담아 한 건 수신한다.
        await store.receive { action in
            guard case let .lifecycle(.entryActionCompleted(record)) = action else { return false }
            return record.operationKind == .copyPath
                && record.succeededCount == 1
                && record.failedCount == 0
        }

        XCTAssertEqual(capture.clearCount, 1)
        XCTAssertEqual(capture.strings, [sandbox.fileURL.absoluteString])
        let copiedURL = try XCTUnwrap(URL(string: capture.strings[0]))
        XCTAssertEqual(copiedURL, sandbox.fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// EOP-006-copy_absolute_paths_of_entries: pasteboard write 실패는 실패 aggregate terminal로 마무리된다.
    /// setString Bool 결과가 그대로 succeeded/failed 집계로 반영되는지 검증한다.
    /// - 검증 내용: terminal record의 failedCount는 1이고 succeededCount는 0이다.
    /// - 사전 조건: setString이 false를 반환하는 pasteboard mock
    /// - 기대 결과: entryActionCompleted(.copyPath, failed: 1, succeeded: 0)가 한 번 수신된다.
    func testCopyAbsolutePathsOfEntries_setStringFailureEmitsFailureTerminal() async throws {
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
                return false
            },
            string: { _ in capture.lastString },
        )

        let store = EntryOperationsTestSupport.makeStore {
            $0.pasteboardClient = pasteboardClient
        }

        await store.send(.clipboard(.copyAbsolutePaths(paths: [sandbox.fileURL.path])))

        await store.receive { action in
            guard case let .lifecycle(.entryActionCompleted(record)) = action else { return false }
            return record.operationKind == .copyPath
                && record.succeededCount == 0
                && record.failedCount == 1
        }

        XCTAssertEqual(capture.clearCount, 1)
        XCTAssertEqual(capture.strings, [sandbox.fileURL.path])
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
