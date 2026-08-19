import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
final class EOP005PackageEntriesTests: XCTestCase {
    // MARK: - EOP-005-compress_entries

    /// EOP-005-compress_entries: 엔트리 압축 생성
    /// - 검증 내용: 선택 항목 압축 action이 archive 생성 의존성을 호출하고 작업 상태를 완료하는지 확인합니다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`를 FixtureSandbox로 복사
    /// - 기대 결과: 아카이브가 생성되고, 압축 목록이 원본 Entry를 포함하며, FileOpsRecorder에 기록됨
    func testCompressEntries_success() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let sourceURL = sandbox.fileURL
        let expectedArchiveURL = sandbox.root.appendingPathComponent("\(sourceURL.lastPathComponent).zip")

        let recorder = FileOpsRecorder()
        let liveClient = EntryFileOpsClient.liveValue
        var entryFileOpsClient = liveClient
        entryFileOpsClient.compressItems = { itemURLs in
            let archiveURL = try await liveClient.compressItems(itemURLs)
            if let first = itemURLs.first {
                recorder.recordCopy(source: first, destination: archiveURL)
            }
            return archiveURL
        }

        let store = EntryOperationsTestSupport.makeStore {
            $0.entryFileOpsClient = entryFileOpsClient
            $0.entryThumbnailCacheClient = .testValue
        }

        await store.send(.archive(.compressItems(paths: [sourceURL.path])))

        await store.receive { action in
            if case .lifecycle(.operationStarted(sandbox.root.path, .compress)) = action { return true }
            return false
        } assert: { state in
            state.itemStates[sandbox.root.path] = ItemOperationState(isBusy: true, lastError: nil)
        }

        await store.receive { action in
            if case .lifecycle(.operationFinished(sandbox.root.path, .compress, .success(()))) = action { return true }
            return false
        } assert: { state in
            state.itemStates[sandbox.root.path]?.isBusy = false
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedArchiveURL.path))
        XCTAssertEqual(try archiveEntryNames(at: expectedArchiveURL), [sourceURL.lastPathComponent])
        XCTAssertEqual(recorder.copiedPaths.count, 1)
        XCTAssertEqual(recorder.copiedPaths.first?.source.path, sourceURL.path)
        XCTAssertEqual(recorder.copiedPaths.first?.destination.path, expectedArchiveURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// EOP-005-compress_entries: 서로 다른 부모의 엔트리를 단일 아카이브로 압축
    /// - 검증 내용: zip 실행이 성공하고 공통 조상에 생성된 아카이브 목록이 두 상대 경로를 포함하는지 확인합니다.
    /// - 사전 조건: 임시 샌드박스 아래에 `A` 디렉터리와 `B/file.txt` 파일을 생성합니다.
    /// - 기대 결과: `Archive.zip` 하나가 공통 조상에 생성되고 `A/` 및 `B/file.txt`가 포함됩니다.
    func testCompressEntries_crossParentItemsCreatesSingleArchiveWithRelativePaths() async throws {
        let sandboxRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: sandboxRoot) }

        let directoryURL = sandboxRoot.appendingPathComponent("A", isDirectory: true)
        let nestedParentURL = sandboxRoot.appendingPathComponent("B", isDirectory: true)
        let nestedFileURL = nestedParentURL.appendingPathComponent("file.txt")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nestedParentURL, withIntermediateDirectories: true)
        try "contents".write(to: nestedFileURL, atomically: true, encoding: .utf8)

        let archiveURL = try await EntryFileOpsClient.liveValue.compressItems([directoryURL, nestedFileURL])

        XCTAssertEqual(archiveURL, sandboxRoot.appendingPathComponent("Archive.zip"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))

        let entryNames = try archiveEntryNames(at: archiveURL)
        XCTAssertTrue(entryNames.contains("A/"))
        XCTAssertTrue(entryNames.contains("B/file.txt"))
    }

    /// EOP-005-compress_entries: 선택된 부모와 하위 항목은 부모만 압축으로 계획한다.
    /// 하위 항목, 같은 raw-prefix peer, 부모를 표시 순서대로 함께 선택할 때 archive planner가 부모와 peer만 유지하는지 확인한다.
    /// - 검증 내용: `.mutation(.compressSelectedItems)` planner가 선택된 조상 관계를 pathComponents로 판별하고 원본 fullPath 및 남은 표시 순서를
    /// 보존한다.
    /// - 사전 조건: 선택 목록에 descendant-first 부모-하위 항목 쌍과 조상이 아닌 raw-prefix peer를 구성한다.
    /// - 기대 결과: `.archive(.compressItems)`는 하위 항목을 제외한 peer와 부모 경로만 방출한다.
    func testCompressEntries_plansTopmostSelectedPaths() throws {
        let parent = EntryModelFixtures.makeEntry(path: "/tmp/Selected Folder", isFolder: true)
        let descendant = EntryModelFixtures.makeEntry(path: "/tmp/Selected Folder/nested/file.txt")
        let rawPrefixPeer = EntryModelFixtures.makeEntry(path: "/tmp/Selected Folder Copy.txt")
        let displayItems = [descendant, rawPrefixPeer, parent]
        let context = EntryOperationsCommandContext(
            selectedIds: Set(displayItems.map(\.id)),
            displayItems: displayItems,
            currentPath: "/tmp",
        )

        let outputs = EntryOperationsCommandPlanner.plan(
            command: .mutation(.compressSelectedItems),
            context: context,
        )

        XCTAssertEqual(outputs.count, 1)
        guard case let .entryOperations(.archive(.compressItems(paths))) = try XCTUnwrap(outputs.first) else {
            return XCTFail("압축 명령은 compressItems payload를 계획해야 합니다.")
        }
        XCTAssertEqual(paths, [rawPrefixPeer.fullPath, parent.fullPath])
    }

    /// EOP-005-extract_compressed_files: 압축 파일 해제
    /// - 검증 내용: 압축 해제 action이 archive 추출 의존성을 호출하고 작업 상태를 완료하는지 확인합니다.
    /// - 사전 조건: `fixtures/fixtures/archives/COMPRESS-264.zip`를 FixtureSandbox로 복사
    /// - 기대 결과: `test.txt`가 추출되고 내용이 `data`와 일치함
    func testExtractCompressedFiles_success() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/archives/COMPRESS-264.zip")
        defer { sandbox.cleanup() }

        let archiveURL = sandbox.fileURL
        let extractedURL = sandbox.root.appendingPathComponent("test.txt")

        let recorder = FileOpsRecorder()
        let liveClient = EntryFileOpsClient.liveValue
        var entryFileOpsClient = liveClient
        entryFileOpsClient.extractCompressedFile = { url in
            try await liveClient.extractCompressedFile(url)
            recorder.recordCopy(source: url, destination: extractedURL)
        }

        let store = EntryOperationsTestSupport.makeStore {
            $0.entryFileOpsClient = entryFileOpsClient
            $0.entryThumbnailCacheClient = .testValue
        }

        await store.send(.archive(.extractCompressedFile(path: archiveURL.path)))

        await store.receive { action in
            if case .lifecycle(.operationStarted(sandbox.root.path, .extract)) = action { return true }
            return false
        } assert: { state in
            state.itemStates[sandbox.root.path] = ItemOperationState(isBusy: true, lastError: nil)
        }

        await store.receive { action in
            if case .lifecycle(.operationFinished(sandbox.root.path, .extract, .success(()))) = action { return true }
            return false
        } assert: { state in
            state.itemStates[sandbox.root.path]?.isBusy = false
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: extractedURL.path))
        XCTAssertEqual(
            try String(contentsOf: extractedURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
            "data",
        )
        XCTAssertEqual(recorder.copiedPaths.count, 1)
        XCTAssertEqual(recorder.copiedPaths.first?.source.path, archiveURL.path)
        XCTAssertEqual(recorder.copiedPaths.first?.destination.path, extractedURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    private func archiveEntryNames(at url: URL) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", url.path]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "EOP005PackageEntriesTests", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: message,
            ])
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let outputString = String(data: data, encoding: .utf8) ?? ""
        return outputString
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}
