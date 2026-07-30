import Foundation
@testable import VoyagerFeaturesEntryOperations
import XCTest

extension EOP002ArrangeEntriesTests {
    struct InterleavedDuplicateScenario {
        let sandbox: FixtureSandbox
        let context: EntryOperationsCommandContext
        let expectedGroups: [(sourcePaths: [String], destinationPath: String)]
    }

    func assertCopyEntriesExcludingSelectedDescendant(
        isDescendantFirst: Bool,
    ) throws {
        let scenario = try makeDuplicateEntriesDescendantScenario(isDescendantFirst: isDescendantFirst)
        defer { scenario.sandbox.cleanup() }

        let outputs = EntryOperationsCommandPlanner.plan(
            command: .clipboard(.copySelectedItems),
            context: scenario.context,
        )

        XCTAssertEqual(outputs.count, 1)
        guard case let .entryOperations(.clipboard(.copySelectedItems(files))) = try XCTUnwrap(outputs.first) else {
            return XCTFail("복사 명령은 copySelectedItems payload를 계획해야 합니다.")
        }
        XCTAssertEqual(files.map(\.fullPath), scenario.expectedSourcePaths)
    }

    func assertCutEntriesExcludingSelectedDescendant(
        isDescendantFirst: Bool,
    ) throws {
        let scenario = try makeDuplicateEntriesDescendantScenario(isDescendantFirst: isDescendantFirst)
        defer { scenario.sandbox.cleanup() }

        let outputs = EntryOperationsCommandPlanner.plan(
            command: .clipboard(.cutSelectedItems),
            context: scenario.context,
        )

        XCTAssertEqual(outputs.count, 2)
        guard case let .entryOperations(.clipboard(.copySelectedItems(files))) = try XCTUnwrap(outputs.first) else {
            return XCTFail("잘라내기 명령은 먼저 copySelectedItems payload를 계획해야 합니다.")
        }
        guard case .entryOperations(.clipboard(.setClipboardOperation(operation: .cut))) = try XCTUnwrap(outputs.last)
        else {
            return XCTFail("잘라내기 명령은 copy payload 뒤에 cut operation을 계획해야 합니다.")
        }
        XCTAssertEqual(files.map(\.fullPath), scenario.expectedSourcePaths)
    }

    func assertDuplicateEntriesExcludingSelectedDescendant(
        isDescendantFirst: Bool,
    ) async throws {
        let scenario = try makeDuplicateEntriesDescendantScenario(isDescendantFirst: isDescendantFirst)
        defer { scenario.sandbox.cleanup() }

        let recorder = FileOpsRecorder()
        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder)
        }

        // store.exhaustivity = .off: duplicate 실행의 lifecycle effect 대신 실행된 source path만 검증한다.
        store.exhaustivity = .off

        await store.send(.routing(.executeCommand(
            command: .clipboard(.duplicateSelectedItems),
            context: scenario.context,
        )))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(recorder.copiedPaths.map(\.source.path), scenario.expectedSourcePaths)
        XCTAssertFalse(FileManager.default
            .fileExists(atPath: scenario.nestedURL.appendingPathComponent("file copy.txt").path))
    }

    /// EOP-002-move_entries: batch fallback 이름은 destination의 기존 파일과도 충돌하지 않는다.
    /// 서로 다른 parent의 같은 basename 파일을 함께 이동할 때 기존 fallback 파일을 보존한다.
    /// - 검증 내용: 두 번째 move destination이 이미 존재하는 `11 copy.txt`를 건너뛴다.
    /// - 사전 조건: 같은 이름의 source 두 개와 destination의 `11 copy.txt`가 존재한다.
    /// - 기대 결과: 기존 fallback은 유지되고 두 번째 source는 `11 copy 2.txt`로 이동한다.
    func testMoveEntries_batchFallbackAvoidsExistingDestination() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let firstParent = sandbox.root.appendingPathComponent("First")
        let secondParent = sandbox.root.appendingPathComponent("Second")
        let destinationFolder = sandbox.root.appendingPathComponent("Destination")
        for directory in [firstParent, secondParent, destinationFolder] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let firstSource = firstParent.appendingPathComponent("11.txt")
        let secondSource = secondParent.appendingPathComponent("11.txt")
        let existingFallback = destinationFolder.appendingPathComponent("11 copy.txt")
        try FileManager.default.copyItem(at: sandbox.fileURL, to: firstSource)
        try FileManager.default.copyItem(at: sandbox.fileURL, to: secondSource)
        try FileManager.default.copyItem(at: sandbox.fileURL, to: existingFallback)

        let recorder = FileOpsRecorder()
        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder)
        }
        // store.exhaustivity = .off: batch move의 async filesystem 결과와 recorder destination을 검증한다.
        store.exhaustivity = .off

        await store.send(.clipboard(.pasteItems(
            sourcePaths: [firstSource.path, secondSource.path],
            destinationPath: destinationFolder.path,
            operation: .cut,
            operationKind: .pasteFileMove,
        )))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(recorder.movedPaths.map(\.destination.lastPathComponent), ["11.txt", "11 copy 2.txt"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: existingFallback.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destinationFolder.appendingPathComponent("11 copy 2.txt").path,
        ))
    }

    /// EOP-002-move_entries: 외부 drop 실행도 source의 descendant destination을 거부한다.
    /// validation 결과를 우회해 들어온 실행 action에도 동일한 순환 참조 규칙을 적용한다.
    /// - 검증 내용: `.routing(.dropItems)`가 move와 copy 모두 descendant destination에서 paste action을 만들지 않는다.
    /// - 사전 조건: source directory를 자기 하위 directory로 외부 drop한다.
    /// - 기대 결과: 두 operation 모두 filesystem mutation effect 없이 종료한다.
    func testExternalDrop_descendantPathDoesNotCreatePasteAction() async {
        let sourcePath = "/Users/test/Documents"
        let destinationPath = "/Users/test/Documents/Archive"
        let store = EntryOperationsTestSupport.makeStore()

        await store.send(.routing(.dropItems(
            sourcePaths: [sourcePath],
            destinationPath: destinationPath,
            isOptionDrag: false,
        )))
        await store.send(.routing(.dropItems(
            sourcePaths: [sourcePath],
            destinationPath: destinationPath,
            isOptionDrag: true,
        )))
    }

    private struct DuplicateEntriesDescendantScenario {
        let sandbox: FixtureSandbox
        let nestedURL: URL
        let context: EntryOperationsCommandContext
        let expectedSourcePaths: [String]
    }

    private func makeDuplicateEntriesDescendantScenario(
        isDescendantFirst: Bool,
    ) throws -> DuplicateEntriesDescendantScenario {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        let ancestorURL = sandbox.root.appendingPathComponent("Selected Folder", isDirectory: true)
        let nestedURL = ancestorURL.appendingPathComponent("nested", isDirectory: true)
        let descendantURL = nestedURL.appendingPathComponent("file.txt")
        let rawPrefixPeerURL = sandbox.root.appendingPathComponent("Selected Folder Copy.txt")
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: sandbox.fileURL, to: descendantURL)
        try FileManager.default.copyItem(at: sandbox.fileURL, to: rawPrefixPeerURL)

        let ancestor = EntryModelFixtures.makeEntry(path: ancestorURL.path, isFolder: true)
        let descendant = EntryModelFixtures.makeEntry(path: descendantURL.path)
        let rawPrefixPeer = EntryModelFixtures.makeEntry(path: rawPrefixPeerURL.path)
        let displayItems = isDescendantFirst
            ? [descendant, rawPrefixPeer, ancestor]
            : [ancestor, rawPrefixPeer, descendant]
        let expectedSourcePaths = isDescendantFirst
            ? [rawPrefixPeerURL.path, ancestorURL.path]
            : [ancestorURL.path, rawPrefixPeerURL.path]
        let context = EntryOperationsCommandContext(
            selectedIds: Set(displayItems.map(\.id)),
            displayItems: displayItems,
            currentPath: sandbox.root.path,
        )
        return DuplicateEntriesDescendantScenario(
            sandbox: sandbox,
            nestedURL: nestedURL,
            context: context,
            expectedSourcePaths: expectedSourcePaths,
        )
    }

    func makeInterleavedDuplicateScenario() throws -> InterleavedDuplicateScenario {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        let firstFolder = sandbox.root.appendingPathComponent("First")
        let secondFolder = sandbox.root.appendingPathComponent("Second")
        try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)

        let rootFirst = sandbox.root.appendingPathComponent("root-first.txt")
        let firstFolderFirst = firstFolder.appendingPathComponent("first-folder-first.txt")
        let rootSecond = sandbox.root.appendingPathComponent("root-second.txt")
        let secondFolderFirst = secondFolder.appendingPathComponent("second-folder-first.txt")
        let firstFolderSecond = firstFolder.appendingPathComponent("first-folder-second.txt")
        let itemURLs = [rootFirst, firstFolderFirst, rootSecond, secondFolderFirst, firstFolderSecond]
        for destination in itemURLs {
            try FileManager.default.copyItem(at: sandbox.fileURL, to: destination)
        }

        let displayItems = itemURLs.map {
            EntryModelFixtures.makeFileEntry(
                id: $0.path,
                name: $0.lastPathComponent,
                fileExtension: $0.pathExtension,
            )
        }
        return InterleavedDuplicateScenario(
            sandbox: sandbox,
            context: EntryOperationsCommandContext(
                selectedIds: Set(displayItems.map(\.id)),
                displayItems: displayItems,
                currentPath: sandbox.root.path,
            ),
            expectedGroups: [
                ([rootFirst.path, rootSecond.path], sandbox.root.path),
                ([firstFolderFirst.path, firstFolderSecond.path], firstFolder.path),
                ([secondFolderFirst.path], secondFolder.path),
            ],
        )
    }
}
