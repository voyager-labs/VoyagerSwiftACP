import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
final class EOP005PackageEntriesTests: XCTestCase {
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

    /// EOP-005-compress_entries: 서로 다른 계층의 선택 항목을 원본 부모별로 압축함
    /// 계층 projection의 multi-parent 선택이 첫 번째 항목 부모 기준의 잘못된 archive 입력으로 합쳐지지 않는지 검증한다.
    /// - 검증 내용: compress command plan이 선택 path를 원본 부모별 action으로 분리함
    /// - 사전 조건: 서로 다른 부모를 가진 두 항목이 선택되고 currentPath는 상위 root임
    /// - 기대 결과: 각 compress action은 동일 부모의 source path만 포함함
    func testCompressCommandPlansEachSourceParentArchive() {
        let first = EntryModelFixtures.makeEntry(path: "/root/first.txt")
        let second = EntryModelFixtures.makeEntry(path: "/root/folder/second.txt")
        let context = EntryOperationsCommandContext(
            selectedIds: [first.id, second.id],
            displayItems: [first, second],
            currentPath: "/root",
        )

        let outputs = EntryOperationsCommandPlanner.plan(
            command: .mutation(.compressSelectedItems),
            context: context,
        )

        XCTAssertEqual(outputs.count, 2)
        guard outputs.count == 2,
              case let .entryOperations(.archive(.compressItems(firstPaths))) = outputs[0],
              case let .entryOperations(.archive(.compressItems(secondPaths))) = outputs[1]
        else {
            XCTFail("Expected compress plans grouped by source parent")
            return
        }
        XCTAssertEqual(firstPaths, [first.fullPath])
        XCTAssertEqual(secondPaths, [second.fullPath])
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
