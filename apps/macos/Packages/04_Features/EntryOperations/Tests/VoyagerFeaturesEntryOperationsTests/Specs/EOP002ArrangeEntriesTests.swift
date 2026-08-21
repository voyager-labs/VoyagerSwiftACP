import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers
import VoyagerEntitiesEntry
@testable import VoyagerFeaturesEntryOperations
import VoyagerShared
import XCTest

/// StagingDirectory가 provider에 공개되지 않은 보관 디렉터리 경로를 재현한다.
/// 세션 구현과 동일한 파생 규칙(`<parent>/.voyager-claimed-<rootName>`)을 쓴다.
private func claimedContainer(_ stagingRoot: URL) -> URL {
    stagingRoot.deletingLastPathComponent()
        .appendingPathComponent(".voyager-claimed-\(stagingRoot.lastPathComponent)", isDirectory: true)
}

@MainActor
final class EOP002ArrangeEntriesTests: XCTestCase {
    // MARK: - EOP-002-create_new_folder

    /// EOP-002-create_new_folder: 새 폴더 생성이 실제 샌드박스 디렉터리에 반영되는지 검증한다.
    /// 사용자가 `fixtures/fixtures/texts/plain/11.txt`를 복사한 샌드박스 루트에서 새 폴더를 만들 때의 성공 경로를 확인한다.
    /// - 검증 내용: `.edit(.createNewFolder)`가 폴더 생성, rename 상태, undo record를 갱신한다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`를 FixtureSandbox로 복사해 temp sandbox를 만들고, 부모 디렉터리는 쓰기 가능하다.
    /// - 기대 결과: `untitled folder`가 생성되고, reducer state와 filesystem이 일치하며, 원본 fixture 경로는 그대로 남는다.
    func testCreateNewFolder_success() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let recorder = FileOpsRecorder()
        let targetPath = sandbox.root.appendingPathComponent("untitled folder").path
        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder)
        }

        // store.exhaustivity = .off: createFolder는 내부 effect가 길어 최종 state와 filesystem만 검증한다.
        // skipReceivedActions로 수신된 action들을 소비해 store.state를 최종 상태로 갱신한다.
        store.exhaustivity = .off

        await store.send(.edit(.createNewFolder(
            parentPath: sandbox.root.path,
            siblingNames: [sandbox.fileURL.lastPathComponent],
        )))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertTrue(FileManager.default.fileExists(atPath: targetPath))
        XCTAssertEqual(store.state.renamingItemId, targetPath)
        XCTAssertEqual(store.state.renamingText, "untitled folder")
        XCTAssertEqual(store.state.undoRecords.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    // MARK: - EOP-002-copy_entries

    /// EOP-002-copy_entries: 선택한 Entry가 클립보드에 복사되는지 검증한다.
    /// 사용자가 `fixtures/fixtures/texts/plain/11.txt`를 선택해 복사할 때 clipboard payload와 pasteboard 기록이 일치하는지 확인한다.
    /// - 검증 내용: `.clipboard(.copySelectedItems)`가 clipboard state와 pasteboard write 호출을 갱신한다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`를 FixtureSandbox로 복사한 뒤 실제 파일 경로를 선택 상태로 사용한다.
    /// - 기대 결과: clipboard에는 실제 fixture path가 저장되고, pasteboard에는 동일한 file URL이 기록되며, 원본 fixture 경로는 유지된다.
    func testCopyEntries_success() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let recorder = ClipboardRecorder()
        let entry = EntryModelFixtures.makeFileEntry(
            id: sandbox.fileURL.path,
            name: sandbox.fileURL.lastPathComponent,
            fileExtension: sandbox.fileURL.pathExtension,
        )

        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.pasteboardClient = makeClipboardClient(recorder: recorder)
        }

        await store.send(.clipboard(.copySelectedItems(files: [entry]))) {
            $0.clipboardItems = [sandbox.fileURL.path]
            $0.clipboardOperation = .copy
            $0.cutClearSession = nil
        }

        await store.finish()

        XCTAssertEqual(recorder.writtenObjectPaths, [[sandbox.fileURL.path]])
        XCTAssertEqual(recorder.clearCount, 1)
        XCTAssertEqual(store.state.clipboardItems, [sandbox.fileURL.path])
        XCTAssertEqual(store.state.clipboardOperation, .copy)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// EOP-002-copy_entries: 선택된 부모와 하위 항목은 표시 순서와 무관하게 부모만 복사 payload로 계획한다.
    /// 사용자가 폴더, 그 하위 파일, 그리고 문자열 접두사만 같은 peer 파일을 함께 선택할 때 하위 파일은 제외하고 topmost source만 유지하는지 확인한다.
    /// - 검증 내용: `.clipboard(.copySelectedItems)`가 URL pathComponents의 엄격한 조상 관계로 하위 항목만 제거하고, 남은 source의 표시 순서와 원본
    /// fullPath를 보존한다.
    /// - 사전 조건: 동일한 폴더와 하위 파일을 선택하되 descendant-first 및 ancestor-first 표시 순서를 각각 구성하고, 경로 구성요소상 조상이 아닌 raw-prefix peer를
    /// 포함한다.
    /// - 기대 결과: 두 표시 순서 모두 parent와 raw-prefix peer만 copy payload에 포함되고, 하위 파일은 포함되지 않는다.
    func testCopyEntries_excludesSelectedDescendantsRegardlessOfDisplayOrder() throws {
        try assertCopyEntriesExcludingSelectedDescendant(isDescendantFirst: true)
        try assertCopyEntriesExcludingSelectedDescendant(isDescendantFirst: false)
    }

    // MARK: - EOP-002-cut_entries

    /// EOP-002-cut_entries: 선택한 Entry가 이동용 잘라내기 상태로 저장되는지 검증한다.
    /// 사용자가 `fixtures/fixtures/texts/plain/11.txt`를 선택한 뒤 cut으로 전환할 때 clipboard marker와 cut session이 설정되는지 확인한다.
    /// - 검증 내용: `.clipboard(.copySelectedItems)`와 `.clipboard(.setClipboardOperation(.cut))`가 clipboard state와 cut
    /// session을 갱신한다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`를 FixtureSandbox로 복사하고, clipboard recorder와 session recorder를
    /// 주입한다.
    /// - 기대 결과: clipboard는 cut 상태가 되고, cut session이 현재 선택 경로를 포함하며, 원본 fixture 경로는 그대로 유지된다.
    func testCutEntries_marksClipboardAsCut() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let recorder = ClipboardRecorder()
        let sessionRecorder = CutSessionRecorder()
        let entry = EntryModelFixtures.makeFileEntry(
            id: sandbox.fileURL.path,
            name: sandbox.fileURL.lastPathComponent,
            fileExtension: sandbox.fileURL.pathExtension,
        )

        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.pasteboardClient = makeClipboardClient(recorder: recorder)
            $0.entryFileOpsClient.clipboardChangeCount = { 0 }
            $0.entryFileOpsClient.saveClipboardCutSessionId = { sessionID in
                sessionRecorder.record(sessionID)
            }
            // @Dependency(\.uuid) 미구현 오류 방지: cutClearSession 생성 시 UUID 사용
            $0.uuid = .constant(UUID())
        }

        // store.exhaustivity = .off: setClipboardOperation이 cutClearSession을 내부 갱신하므로 최종 상태만 검증한다.
        store.exhaustivity = .off

        await store.send(.clipboard(.copySelectedItems(files: [entry])))
        await store.send(.clipboard(.setClipboardOperation(operation: .cut)))
        await store.finish()

        XCTAssertEqual(recorder.setStrings.map(\.value), ["cut"])
        XCTAssertEqual(sessionRecorder.savedSessionIDs.count, 2)
        XCTAssertNil(sessionRecorder.savedSessionIDs[0])
        XCTAssertNotNil(sessionRecorder.savedSessionIDs[1])
        XCTAssertEqual(store.state.clipboardItems, [sandbox.fileURL.path])
        XCTAssertEqual(store.state.clipboardOperation, .cut)
        XCTAssertEqual(store.state.cutClearSession?.sourcePaths, [sandbox.fileURL.path])
        XCTAssertEqual(store.state.cutClearSession?.pasteboard.changeCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// EOP-002-cut_entries: 선택된 부모와 하위 항목은 표시 순서와 무관하게 부모만 잘라내기 payload로 계획한다.
    /// 사용자가 폴더, 그 하위 파일, 그리고 문자열 접두사만 같은 peer 파일을 함께 선택할 때 하위 파일은 제외하고 topmost source만 유지하는지 확인한다.
    /// - 검증 내용: `.clipboard(.copySelectedItems)`가 URL pathComponents의 엄격한 조상 관계로 하위 항목만 제거하고, 뒤이어 cut operation을 설정하며
    /// 남은 source의 표시 순서와 원본 fullPath를 보존한다.
    /// - 사전 조건: 동일한 폴더와 하위 파일을 선택하되 descendant-first 및 ancestor-first 표시 순서를 각각 구성하고, 경로 구성요소상 조상이 아닌 raw-prefix peer를
    /// 포함한다.
    /// - 기대 결과: 두 표시 순서 모두 parent와 raw-prefix peer만 cut의 copy payload에 포함되고, 하위 파일은 포함되지 않으며 cut operation이 뒤따른다.
    func testCutEntries_excludesSelectedDescendantsRegardlessOfDisplayOrder() throws {
        try assertCutEntriesExcludingSelectedDescendant(isDescendantFirst: true)
        try assertCutEntriesExcludingSelectedDescendant(isDescendantFirst: false)
    }

    // MARK: - EOP-002-paste_entries

    /// EOP-002-paste_entries: 클립보드의 file-copy가 실제 파일 복사로 반영되는지 검증한다.
    /// 사용자가 `fixtures/fixtures/texts/plain/11.txt`를 다른 디렉터리에 붙여넣을 때 실제 복사본이 생성되는지 확인한다.
    /// - 검증 내용: `.clipboard(.pasteItems)`가 복사 대상 경로와 destination을 실제 파일 복사로 연결한다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`를 FixtureSandbox로 복사하고, 대상 destination 디렉터리를 샌드박스 내부에 준비한다.
    /// - 기대 결과: source는 유지되고 destination에 복사본이 생성되며, FileOpsRecorder와 reducer state가 함께 갱신된다.
    func testPasteEntries_success() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let recorder = FileOpsRecorder()
        let destinationFolder = sandbox.root.appendingPathComponent("Copies")
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let sourcePath = sandbox.fileURL.path
        let destinationPath = destinationFolder.appendingPathComponent(sandbox.fileURL.lastPathComponent).path

        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder)
        }

        // store.exhaustivity = .off: file copy effect emits internal lifecycle actions we validate through final state
        // and recorder.
        // skipReceivedActions로 수신된 action들을 소비해 store.state를 최종 상태로 갱신한다.
        store.exhaustivity = .off

        await store.send(.clipboard(.pasteItems(
            sourcePaths: [sourcePath],
            destinationPath: destinationFolder.path,
            operation: .copy,
            operationKind: .pasteFileCopy,
        )))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(recorder.copiedPaths.count, 1)
        XCTAssertEqual(recorder.copiedPaths.first?.source.path, sourcePath)
        XCTAssertEqual(recorder.copiedPaths.first?.destination.path, destinationPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourcePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationPath))
        XCTAssertEqual(store.state.undoRecords.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// EOP-002-paste_entries: 붙여넣기 권한 오류가 error state로 남는지 검증한다.
    /// 사용자가 `fixtures/fixtures/texts/plain/11.txt`를 권한이 없는 대상에 붙여넣을 때 실패 상태가 유지되는지 확인한다.
    /// - 검증 내용: `.clipboard(.pasteItems)`가 pasteFile 오류를 lifecycle failure로 변환한다.
    /// - 사전 조건: fixture를 FixtureSandbox로 복사하고, pasteFile client는 permission denied 오류를 던진다.
    /// - 기대 결과: source와 원본 fixture는 유지되고, destination은 생성되지 않으며, reducer state에는 실패가 반영된다.
    func testPasteEntries_permissionDeniedSetsLastError() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let destinationFolder = sandbox.root.appendingPathComponent("ReadOnlyDestination")
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let sourcePath = sandbox.fileURL.path
        let destinationPath = destinationFolder.appendingPathComponent(sandbox.fileURL.lastPathComponent).path
        let error = FileOpError.system(message: "permission denied")

        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            var client = EntryFileOpsClient.liveValue
            client.pasteFile = { _, _ in throw error }
            $0.entryFileOpsClient = client
        }

        await store.send(.clipboard(.pasteItems(
            sourcePaths: [sourcePath],
            destinationPath: destinationFolder.path,
            operation: .copy,
            operationKind: .pasteFileCopy,
        )))

        await store.receive(\.lifecycle.operationStarted) {
            $0.itemStates[sourcePath] = ItemOperationState(isBusy: true)
        }

        await store.receive(\.lifecycle.operationFinished) {
            $0.itemStates[sourcePath] = ItemOperationState(isBusy: false, lastError: error)
        }

        XCTAssertEqual(store.state.itemStates[sourcePath]?.lastError, error)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourcePath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    // MARK: - EOP-002-duplicate_entries

    /// EOP-002-duplicate_entries: 같은 디렉터리에서 중복 이름이 없는 복제본이 생성되는지 검증한다.
    /// 사용자가 `fixtures/fixtures/texts/plain/11.txt`를 같은 폴더에서 duplicate할 때 `copy` 접미사 복제본이 생성되는지 확인한다.
    /// - 검증 내용: `.clipboard(.pasteItems)`가 same-parent copy 충돌을 피해서 새 복제본을 만든다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`를 FixtureSandbox로 복사하고, destination은 source와 동일한 부모 디렉터리다.
    /// - 기대 결과: 원본은 유지되고 `hello copy.txt` 복제본이 생성되며, FileOpsRecorder와 reducer state가 함께 갱신된다.
    func testDuplicateEntries_success() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let recorder = FileOpsRecorder()
        let sourcePath = sandbox.fileURL.path
        let destinationPath = sandbox.root.appendingPathComponent("11 copy.txt").path

        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder)
        }

        // store.exhaustivity = .off: duplicate effect is asynchronous; final state and filesystem are enough here.
        // skipReceivedActions로 수신된 action들을 소비해 store.state를 최종 상태로 갱신한다.
        store.exhaustivity = .off

        await store.send(.clipboard(.pasteItems(
            sourcePaths: [sourcePath],
            destinationPath: sandbox.root.path,
            operation: .copy,
            operationKind: .pasteFileDuplicate,
        )))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(recorder.copiedPaths.count, 1)
        XCTAssertEqual(recorder.copiedPaths.first?.source.path, sourcePath)
        XCTAssertEqual(recorder.copiedPaths.first?.destination.path, destinationPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourcePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationPath))
        XCTAssertEqual(store.state.undoRecords.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// EOP-002-duplicate_entries: 서로 다른 계층의 선택 항목을 각 원본 부모에 복제한다.
    /// 계층 projection에서 선택된 중첩 항목이 현재 root로 이동하지 않고 원래 sibling 위치에 복제되는지 검증한다.
    /// - 검증 내용: duplicate command plan이 선택 path를 원본 부모별 paste action으로 분리함
    /// - 사전 조건: 서로 다른 부모를 가진 두 항목이 선택되고 currentPath는 상위 root임
    /// - 기대 결과: 각 paste destination은 해당 source의 deletingLastPathComponent 경로임
    func testDuplicateCommandPlansEachSourceParentDestination() {
        let first = EntryModelFixtures.makeEntry(path: "/root/folder/first.txt")
        let second = EntryModelFixtures.makeEntry(path: "/root/other/second.txt")
        let context = EntryOperationsCommandContext(
            selectedIds: [first.id, second.id],
            displayItems: [first, second],
            currentPath: "/root",
        )

        let outputs = EntryOperationsCommandPlanner.plan(
            command: .clipboard(.duplicateSelectedItems),
            context: context,
        )

        XCTAssertEqual(outputs.count, 2)
        guard outputs.count == 2,
              case let .entryOperations(.clipboard(.pasteItems(firstPaths, firstDestination, _, _))) = outputs[0],
              case let .entryOperations(.clipboard(.pasteItems(secondPaths, secondDestination, _, _))) = outputs[1]
        else {
            XCTFail("Expected duplicate paste plans grouped by source parent")
            return
        }
        XCTAssertEqual(firstPaths, [first.fullPath])
        XCTAssertEqual(firstDestination, "/root/folder")
        XCTAssertEqual(secondPaths, [second.fullPath])
        XCTAssertEqual(secondDestination, "/root/other")
    }

    /// EOP-002-duplicate_entries: 부모와 자식을 함께 선택하면 부모만 복제한다.
    /// 계층 projection에서 선택된 폴더의 하위 항목을 별도 복제해 중복 결과를 만들지 않는지 검증한다.
    /// - 검증 내용: duplicate command plan이 선택된 ancestor의 descendant path를 제외함
    /// - 사전 조건: 폴더와 해당 폴더의 자식 파일이 동시에 선택됨
    /// - 기대 결과: paste source에는 부모 폴더만 포함됨
    func testDuplicateCommandOmitsDescendantOfSelectedFolder() {
        let folder = EntryModelFixtures.makeEntry(path: "/root/folder")
        let child = EntryModelFixtures.makeEntry(path: "/root/folder/child.txt")
        let context = EntryOperationsCommandContext(
            selectedIds: [folder.id, child.id],
            displayItems: [folder, child],
            currentPath: "/root",
        )

        let outputs = EntryOperationsCommandPlanner.plan(
            command: .clipboard(.duplicateSelectedItems),
            context: context,
        )

        XCTAssertEqual(outputs.count, 1)
        guard case let .entryOperations(.clipboard(.pasteItems(paths, destination, _, _))) = outputs.first else {
            XCTFail("Expected one duplicate paste plan")
            return
        }
        XCTAssertEqual(paths, [folder.fullPath])
        XCTAssertEqual(destination, "/root")
    }

    /// EOP-002-duplicate_entries: 일부 선택 항목이 사라진 상태에서도 앞선 항목 복제는 유지되는지 검증한다.
    /// 사용자가 `fixtures/fixtures/images/jpeg/`에서 여러 항목을 duplicate할 때 중간 하나가 없어도 앞선 복제는 유지되는지 확인한다.
    /// - 검증 내용: `.clipboard(.pasteItems)`가 다중 선택을 순차 처리하면서 앞선 성공과 뒤늦은 실패를 분리한다.
    /// - 사전 조건: `fixtures/fixtures/images/jpeg/`를 FixtureSandbox로 복사하고, 하나의 source는 존재하지 않는 경로로 바꾼다.
    /// - 기대 결과: 존재하는 항목은 복제되고, 사라진 항목은 실패하며, 원본 fixture 디렉터리는 그대로 남는다.
    func testDuplicateEntries_partialMultiSelectionFailure() async throws {
        let sandbox = try FixtureSandbox.copyingDirectory(from: "fixtures/fixtures/images/jpeg")
        defer { sandbox.cleanup() }

        let recorder = FileOpsRecorder()
        let items = try FileManager.default.contentsOfDirectory(atPath: sandbox.fileURL.path).sorted()
        let existingFile = try sandbox.fileURL.appendingPathComponent(XCTUnwrap(items.first)).path
        let missingFile = sandbox.fileURL.appendingPathComponent("missing.jpg").path
        let destinationPath = sandbox.fileURL
            .appendingPathComponent((URL(fileURLWithPath: existingFile).deletingPathExtension().lastPathComponent) +
                " copy.jpg").path

        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder)
        }

        // store.exhaustivity = .off: partial multi-selection failure is integration-heavy and we assert only the final
        // contract.
        store.exhaustivity = .off

        await store.send(.clipboard(.pasteItems(
            sourcePaths: [existingFile, missingFile],
            destinationPath: sandbox.fileURL.path,
            operation: .copy,
            operationKind: .pasteFileDuplicate,
        )))
        await store.finish()

        XCTAssertEqual(recorder.copiedPaths.count, 1)
        XCTAssertEqual(recorder.copiedPaths.first?.source.path, existingFile)
        XCTAssertEqual(recorder.copiedPaths.first?.destination.path, destinationPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: existingFile))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingFile))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// EOP-002-duplicate_entries: 선택된 부모와 하위 항목은 표시 순서와 무관하게 부모만 복제하도록 계획한다.
    /// 사용자가 폴더, 그 하위 파일, 그리고 문자열 접두사만 같은 peer 파일을 함께 선택할 때 하위 파일은 제외하고 topmost source만 유지하는지 확인한다.
    /// - 검증 내용: `.routing(.executeCommand)`가 URL pathComponents의 엄격한 조상 관계로 하위 항목만 제거하고, 남은 source의 표시 순서와 원본 fullPath를
    /// 보존한다.
    /// - 사전 조건: 동일한 폴더와 하위 파일을 선택하되 descendant-first 및 ancestor-first 표시 순서를 각각 구성하고, 경로 구성요소상 조상이 아닌 raw-prefix peer를
    /// 포함한다.
    /// - 기대 결과: 두 표시 순서 모두 parent와 raw-prefix peer만 하나의 부모별 duplicate paste action으로 방출되며, 하위 파일은 sourcePaths에 포함되지
    /// 않는다.
    func testDuplicateEntries_excludesSelectedDescendantsRegardlessOfDisplayOrder() async throws {
        try await assertDuplicateEntriesExcludingSelectedDescendant(isDescendantFirst: true)
        try await assertDuplicateEntriesExcludingSelectedDescendant(isDescendantFirst: false)
    }

    /// EOP-002-duplicate_entries: 서로 다른 부모의 교차 선택은 부모별로 같은 디렉터리에 복제하도록 계획한다.
    /// 사용자가 root와 두 nested 폴더의 항목을 표시 순서대로 교차 선택해 duplicate할 때 각 항목이 원래 부모에 남는 경로를 확인한다.
    /// - 검증 내용: `.routing(.executeCommand)`가 display 순서로 선택을 필터링하고, 첫 등장 부모 순서 및 부모별 source 순서를 보존한
    /// `.clipboard(.pasteItems)`를 만든다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`를 FixtureSandbox로 복사하고, 샌드박스 root 및 두 nested 디렉터리에 실제 파일을 준비한다.
    /// - 기대 결과: root, 첫 번째 nested 부모, 두 번째 nested 부모 순서로 각각 하나의 duplicate paste action이 방출되고, root 항목의 destination은
    /// context.currentPath와 같다.
    func testDuplicateEntries_groupsInterleavedSelectionsByParentInDisplayOrder() async throws {
        let scenario = try makeInterleavedDuplicateScenario()
        defer { scenario.sandbox.cleanup() }
        let store = EntryOperationsTestSupport.makeStore()

        // store.exhaustivity = .off: duplicate 실행의 lifecycle effect 대신 planner가 방출한 부모별 paste action만 검증한다.
        store.exhaustivity = .off

        await store.send(.routing(.executeCommand(
            command: .clipboard(.duplicateSelectedItems),
            context: scenario.context,
        )))
        for group in scenario.expectedGroups {
            await store.receive { action in
                guard case let .clipboard(.pasteItems(sourcePaths, destinationPath, operation, operationKind)) = action
                else {
                    return false
                }
                return sourcePaths == group.sourcePaths
                    && destinationPath == group.destinationPath
                    && operation == .copy
                    && operationKind == .pasteFileDuplicate
            }
        }
        await store.finish()
    }

    // MARK: - EOP-002-move_entries

    /// EOP-002-move_entries: 선택한 Entry가 다른 디렉터리로 실제 이동되는지 검증한다.
    /// 사용자가 `fixtures/fixtures/texts/plain/11.txt`를 `Moved` 폴더로 이동할 때 source 삭제와 destination 생성이 함께 일어나는지 확인한다.
    /// - 검증 내용: `.clipboard(.pasteItems)`가 move operation을 실제 filesystem mutation으로 수행한다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`를 FixtureSandbox로 복사하고, destination 디렉터리를 샌드박스 내부에 준비한다.
    /// - 기대 결과: source는 사라지고 destination에 동일 파일명이 생성되며, FileOpsRecorder와 reducer state가 함께 갱신된다.
    func testMoveEntries_success() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let recorder = FileOpsRecorder()
        let destinationFolder = sandbox.root.appendingPathComponent("Moved")
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let sourcePath = sandbox.fileURL.path
        let destinationPath = destinationFolder.appendingPathComponent(sandbox.fileURL.lastPathComponent).path

        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder)
        }

        // store.exhaustivity = .off: move is an async filesystem mutation; final state and recorder prove the contract.
        // skipReceivedActions로 수신된 action들을 소비해 store.state를 최종 상태로 갱신한다.
        store.exhaustivity = .off

        await store.send(.clipboard(.pasteItems(
            sourcePaths: [sourcePath],
            destinationPath: destinationFolder.path,
            operation: .cut,
            operationKind: .pasteFileMove,
        )))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(recorder.movedPaths.count, 1)
        XCTAssertEqual(recorder.movedPaths.first?.source.path, sourcePath)
        XCTAssertEqual(recorder.movedPaths.first?.destination.path, destinationPath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourcePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationPath))
        XCTAssertEqual(store.state.undoRecords.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// EOP-002-move_entries: 대상 경로가 이미 존재하면 기존 파일을 덮어쓰지 않고 실패하는지 검증한다.
    /// 사용자가 `fixtures/fixtures/texts/plain/11.txt`를 이미 동일 이름이 있는 폴더로 이동할 때 replace를 중단하면 실패해야 한다.
    /// - 검증 내용: `.clipboard(.pasteItems)`가 destination 충돌에서 replace alert를 거친 뒤 cancel failure를 반환한다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`를 FixtureSandbox로 복사하고, destination에는 같은 이름의 파일을 미리 준비한다.
    /// - 기대 결과: source와 기존 destination이 유지되고, FileOpsRecorder에는 move 기록이 남지 않으며, reducer state에는 실패가 반영된다.
    func testMoveEntries_duplicateDestinationStops() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let recorder = FileOpsRecorder()
        let destinationFolder = sandbox.root.appendingPathComponent("Blocked")
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let sourcePath = sandbox.fileURL.path
        let destinationPath = destinationFolder.appendingPathComponent(sandbox.fileURL.lastPathComponent).path
        try FileManager.default.copyItem(at: sandbox.fileURL, to: URL(fileURLWithPath: destinationPath))

        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder)
            $0.entryOperationsAlertClient.showReplaceAlert = { _, _ in .stop }
        }

        // store.exhaustivity = .off: replace-cancel is an async integration path; final state and filesystem are
        // enough.
        store.exhaustivity = .off

        await store.send(.clipboard(.pasteItems(
            sourcePaths: [sourcePath],
            destinationPath: destinationFolder.path,
            operation: .cut,
            operationKind: .pasteFileMove,
        )))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertTrue(recorder.movedPaths.isEmpty)
        XCTAssertEqual(store.state.itemStates[sourcePath]?.lastError, .cancelled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourcePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    // MARK: - EOP-002-create_entry_alias

    /// EOP-002-create_entry_alias: 선택한 Entry에 실제 alias 파일이 생성되는지 검증한다.
    /// 사용자가 `fixtures/fixtures/texts/plain/11.txt`를 alias로 만들 때 동일한 원본을 가리키는 새 파일이 생성되는지 확인한다.
    /// - 검증 내용: `.edit(.createAliases)`가 alias 생성, state 갱신, undo record 생성을 수행한다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`를 FixtureSandbox로 복사하고, alias 충돌이 없는 상태다.
    /// - 기대 결과: alias 파일이 생성되고, reducer state가 갱신되며, 원본 fixture 경로는 그대로 남는다.
    func testCreateEntryAlias_success() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let sourcePath = sandbox.fileURL.path
        let aliasPath = sandbox.root.appendingPathComponent("11.txt alias").path

        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.entryFileOpsClient = makeAliasRecordingClient()
        }

        // store.exhaustivity = .off: alias creation is an async filesystem mutation; we validate end state only.
        // skipReceivedActions로 수신된 action들을 소비해 store.state를 최종 상태로 갱신한다.
        store.exhaustivity = .off

        await store.send(.edit(.createAliases(paths: [sourcePath])))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertTrue(FileManager.default.fileExists(atPath: sourcePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: aliasPath))
        XCTAssertEqual(store.state.undoRecords.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    // MARK: - EOP-002-move_entries

    /// EOP-002-move_entries: 같은 부모 directory에 드롭하면 resolveDropValidation이 none을 반환한다
    /// 내부 드래그(non-copy)에서 source와 destination의 부모가 같으면 no-op이어야 한다.
    /// - 검증 내용: `validateDrop`이 같은 부모 경로에서 `resolvedOperation = .none`을 반환한다.
    /// - 사전 조건: sourcePaths가 비어있지 않고 prefersCopy=false이며 source 부모가 destination과 동일하다.
    /// - 기대 결과: dropValidationResult의 resolvedOperation이 `.none`이고 isOptionDrag가 false다.
    func testDropValidation_sameParentReturnsNone() async {
        let sourcePath = "/Users/test/Documents/file.txt"
        let destinationPath = "/Users/test/Documents"

        let store = EntryOperationsTestSupport.makeStore()

        let context = EntryDropValidationContext(
            sourcePaths: [sourcePath],
            destinationPath: destinationPath,
            allowedOperationsRawValue: NSDragOperation.copy.rawValue | NSDragOperation.move.rawValue,
            prefersCopy: false,
        )

        await store.send(.routing(.validateDrop(context: context))) {
            $0.dropValidationResult = EntryDropValidationResult(
                destinationPath: destinationPath,
                resolvedOperation: .none,
                isOptionDrag: false,
            )
        }

        await store.finish()

        XCTAssertEqual(store.state.dropValidationResult.resolvedOperation, .none)
        XCTAssertFalse(store.state.dropValidationResult.isOptionDrag)
    }

    /// EOP-002-move_entries: 혼합 부모 드롭에서 같은-부모 항목만으로 전체를 거부하지 않는다
    /// 서로 다른 폴더의 항목을 함께 드롭할 때, 첫 항목만 같은-부모 no-op이라도 나머지 항목의 이동은 허용돼야 한다.
    /// - 검증 내용: [같은-부모 항목, 다른-부모 항목] 순서에서 resolvedOperation이 .move다.
    /// - 사전 조건: sourcePaths 중 첫 항목의 부모가 destination과 같고, 둘째 항목은 다른 부모다.
    /// - 기대 결과: 같은-부모 항목은 건너뛰고 둘째 항목의 move가 유지되어 .move로 판정된다.
    func testDropValidation_mixedParentSourcesAllowRemainingMove() async {
        let destinationPath = "/Users/test/Documents"
        let sameParentSource = "/Users/test/Documents/same.txt"
        let otherParentSource = "/Users/test/Downloads/other.txt"

        let store = EntryOperationsTestSupport.makeStore()

        let context = EntryDropValidationContext(
            sourcePaths: [sameParentSource, otherParentSource],
            destinationPath: destinationPath,
            allowedOperationsRawValue: NSDragOperation.copy.rawValue | NSDragOperation.move.rawValue,
            prefersCopy: false,
        )

        await store.send(.routing(.validateDrop(context: context))) {
            $0.dropValidationResult = EntryDropValidationResult(
                destinationPath: destinationPath,
                resolvedOperation: .move,
                isOptionDrag: false,
            )
        }

        await store.finish()

        XCTAssertEqual(store.state.dropValidationResult.resolvedOperation, .move)
        XCTAssertFalse(store.state.dropValidationResult.isOptionDrag)
    }

    /// EOP-002-move_entries: directory를 자기 하위에 드롭하면 순환 참조로 none을 반환한다
    /// destination이 source의 하위 경로이면 순환 참조가 감지되어 no-op이어야 한다.
    /// - 검증 내용: `validateDrop`이 하위 경로 드롭에서 `resolvedOperation = .none`을 반환한다.
    /// - 사전 조건: destination이 sourcePaths 중 하나의 하위 경로다.
    /// - 기대 결과: dropValidationResult의 resolvedOperation이 `.none`이다.
    func testDropValidation_descendantPathReturnsNone() async {
        let sourcePath = "/Users/test/Documents"
        let destinationPath = "/Users/test/Documents/Subfolder"

        let store = EntryOperationsTestSupport.makeStore()

        let context = EntryDropValidationContext(
            sourcePaths: [sourcePath],
            destinationPath: destinationPath,
            allowedOperationsRawValue: NSDragOperation.copy.rawValue | NSDragOperation.move.rawValue,
            prefersCopy: false,
        )

        await store.send(.routing(.validateDrop(context: context))) {
            $0.dropValidationResult = EntryDropValidationResult(
                destinationPath: destinationPath,
                resolvedOperation: .none,
                isOptionDrag: false,
            )
        }

        await store.finish()

        XCTAssertEqual(store.state.dropValidationResult.resolvedOperation, .none)
    }

    /// EOP-002-copy_entries: directory를 자기 하위에 copy drop하면 순환 참조로 none을 반환한다
    /// prefersCopy=true이더라도 destination이 source의 하위 경로이면 무한 재귀가 발생하므로 copy를 거부해야 한다.
    /// - 검증 내용: `validateDrop`이 prefersCopy=true이고 destination이 source 하위 경로인 경우 `resolvedOperation = .none`을 반환한다.
    /// - 사전 조건: sourcePaths가 directory이고 destination이 그 하위 경로이며 prefersCopy=true다.
    /// - 기대 결과: dropValidationResult의 resolvedOperation이 `.none`이고 isOptionDrag가 true다.
    func testDropValidation_descendantPathReturnsNoneForCopyDrop() async {
        let sourcePath = "/Users/test/Documents"
        let destinationPath = "/Users/test/Documents/Subfolder"

        let store = EntryOperationsTestSupport.makeStore()

        let context = EntryDropValidationContext(
            sourcePaths: [sourcePath],
            destinationPath: destinationPath,
            allowedOperationsRawValue: NSDragOperation.copy.rawValue | NSDragOperation.move.rawValue,
            prefersCopy: true,
        )

        await store.send(.routing(.validateDrop(context: context))) {
            $0.dropValidationResult = EntryDropValidationResult(
                destinationPath: destinationPath,
                resolvedOperation: .none,
                isOptionDrag: true,
            )
        }

        await store.finish()

        XCTAssertEqual(store.state.dropValidationResult.resolvedOperation, .none)
        XCTAssertTrue(store.state.dropValidationResult.isOptionDrag)
    }

    /// EOP-002-move_entries: Option 키를 누르면 copy operation이 우선 판정된다
    /// prefersCopy=true이면 resolvedOperation이 copy로 판정되고 isOptionDrag가 true로 설정된다.
    /// - 검증 내용: `validateDrop`이 prefersCopy=true에서 `.copy`를 반환하고 isOptionDrag=true다.
    /// - 사전 조건: sourcePaths가 비어있지 않고 allowedOperations에 copy가 포함된다.
    /// - 기대 결과: resolvedOperation이 `.copy`이고 isOptionDrag가 true다.
    func testDropValidation_optionDragPrefersCopy() async {
        let sourcePath = "/Users/test/Documents/file.txt"
        let destinationPath = "/Users/test/Desktop"

        let store = EntryOperationsTestSupport.makeStore()

        let context = EntryDropValidationContext(
            sourcePaths: [sourcePath],
            destinationPath: destinationPath,
            allowedOperationsRawValue: NSDragOperation.copy.rawValue | NSDragOperation.move.rawValue,
            prefersCopy: true,
        )

        await store.send(.routing(.validateDrop(context: context))) {
            $0.dropValidationResult = EntryDropValidationResult(
                destinationPath: destinationPath,
                resolvedOperation: .copy,
                isOptionDrag: true,
            )
        }

        await store.finish()

        XCTAssertEqual(store.state.dropValidationResult.resolvedOperation, .copy)
        XCTAssertTrue(store.state.dropValidationResult.isOptionDrag)
    }

    /// EOP-002-move_entries: Option 키 없이 드래그하면 move operation으로 판정된다
    /// prefersCopy=false이면 resolvedOperation이 move로 판정되고 isOptionDrag가 false다.
    /// - 검증 내용: `validateDrop`이 prefersCopy=false에서 `.move`를 반환한다.
    /// - 사전 조건: 다른 부모 디렉터리로 드래그, allowedOperations에 move가 포함된다.
    /// - 기대 결과: resolvedOperation이 `.move`이고 isOptionDrag가 false다.
    func testDropValidation_noOptionDragPrefersMove() async {
        let sourcePath = "/Users/test/Documents/file.txt"
        let destinationPath = "/Users/test/Desktop"

        let store = EntryOperationsTestSupport.makeStore()

        let context = EntryDropValidationContext(
            sourcePaths: [sourcePath],
            destinationPath: destinationPath,
            allowedOperationsRawValue: NSDragOperation.copy.rawValue | NSDragOperation.move.rawValue,
            prefersCopy: false,
        )

        await store.send(.routing(.validateDrop(context: context))) {
            $0.dropValidationResult = EntryDropValidationResult(
                destinationPath: destinationPath,
                resolvedOperation: .move,
                isOptionDrag: false,
            )
        }

        await store.finish()

        XCTAssertEqual(store.state.dropValidationResult.resolvedOperation, .move)
        XCTAssertFalse(store.state.dropValidationResult.isOptionDrag)
    }

    /// EOP-002-move_entries: 허용된 NSDragOperation에 해당 operation이 없으면 none을 반환한다
    /// allowedOperations에 move도 copy도 포함되지 않으면 드롭이 거절된다.
    /// - 검증 내용: `validateDrop`이 빈 allowedOperations에서 `.none`을 반환한다.
    /// - 사전 조건: allowedOperationsRawValue가 0이다.
    /// - 기대 결과: resolvedOperation이 `.none`이다.
    func testDropValidation_disallowedOperationReturnsNone() async {
        let sourcePath = "/Users/test/Documents/file.txt"
        let destinationPath = "/Users/test/Desktop"

        let store = EntryOperationsTestSupport.makeStore()

        let context = EntryDropValidationContext(
            sourcePaths: [sourcePath],
            destinationPath: destinationPath,
            allowedOperationsRawValue: 0,
            prefersCopy: false,
        )

        await store.send(.routing(.validateDrop(context: context))) {
            $0.dropValidationResult = EntryDropValidationResult(
                destinationPath: destinationPath,
                resolvedOperation: .none,
                isOptionDrag: false,
            )
        }

        await store.finish()

        XCTAssertEqual(store.state.dropValidationResult.resolvedOperation, .none)
    }

    /// EOP-002-move_entries: 내부 드래그의 부모와 하위 경로는 부모만 paste action으로 전달한다.
    /// 내부 드래그 저장소에 선택된 폴더와 그 하위 파일이 함께 있을 때, 드롭 라우팅 경계에서 중복 작업을 막는다.
    /// - 검증 내용: `.routing(.handleDrop)`가 `.clipboard(.pasteItems)`로 부모 경로만 전송한다.
    /// - 사전 조건: 저장된 내부 드래그 경로에 parent와 descendant가 함께 있고 Option 키를 눌렀다.
    /// - 기대 결과: pasteItems의 sourcePaths에는 parent만 남고 copy operation과 operationKind는 유지된다.
    func testHandleDrop_excludesParentSelectedDescendantFromPasteItems() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let sourceFolder = sandbox.root.appendingPathComponent("SelectedFolder")
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        let descendantFile = sourceFolder.appendingPathComponent("child.txt")
        try FileManager.default.copyItem(at: sandbox.fileURL, to: descendantFile)

        let destinationFolder = sandbox.root.appendingPathComponent("DropTarget")
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let recorder = FileOpsRecorder()
        let parentPath = sourceFolder.path
        let descendantPath = descendantFile.path
        var fileOpsClient = makeRecordedFileOpsClient(recorder: recorder)
        fileOpsClient.loadDragPaths = { [parentPath, descendantPath] }
        fileOpsClient.loadDragWithOption = { true }

        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.entryFileOpsClient = fileOpsClient
        }

        // store.exhaustivity = .off: 드롭 실행은 async filesystem mutation이므로 recorder의 라우팅 결과를 검증한다.
        store.exhaustivity = .off

        await store.send(.routing(.handleDrop(
            providers: [],
            destinationPath: destinationFolder.path,
            isOptionDrag: true,
        )))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(recorder.copiedPaths.map(\.source.path), [parentPath])
        XCTAssertEqual(recorder.copiedPaths.map(\.destination.path), [
            destinationFolder.appendingPathComponent(sourceFolder.lastPathComponent).path,
        ])
    }

    // MARK: - EOP-002-move_entries

    // AC: EOP-002-move_entries Edge Case #8
    /// EOP-002-move_entries: 사용자가 Entry를 유효한 대상 directory로 드롭하면 move가 수행된다.
    /// `dropItems` action이 전송되면 내부적으로 `clipboard(.pasteItems)`로 라우팅되어 실제 파일 이동이 발생한다.
    /// - 검증 내용: `.routing(.dropItems)`가 move operation을 수행하고 FileOpsRecorder에 이동 기록이 남는다.
    /// - 사전 조건: source 파일이 존재하고, target directory가 다른 경로에 존재한다.
    /// - 기대 결과: FileOpsRecorder의 movedPaths count == 1, source 파일이 이동되었다.
    func testDropExecution_validTarget_performsMoveOperation() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let recorder = FileOpsRecorder()
        let destinationFolder = sandbox.root.appendingPathComponent("DropTarget")
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let sourcePath = sandbox.fileURL.path
        let destinationPath = destinationFolder.appendingPathComponent(sandbox.fileURL.lastPathComponent).path

        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder)
        }

        // store.exhaustivity = .off: drop execution은 async filesystem mutation; 최종 state와 recorder로 contract 검증.
        store.exhaustivity = .off

        await store.send(.routing(.dropItems(
            sourcePaths: [sourcePath],
            destinationPath: destinationFolder.path,
            isOptionDrag: false,
        )))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(recorder.movedPaths.count, 1)
        XCTAssertEqual(recorder.movedPaths.first?.source.path, sourcePath)
        XCTAssertEqual(recorder.movedPaths.first?.destination.path, destinationPath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourcePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationPath))
        XCTAssertEqual(store.state.undoRecords.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// EOP-002-move_entries: Option-drop은 move 대신 copy operation을 수행한다.
    /// `dropItems` action이 isOptionDrag=true로 전송되면 내부적으로 copy paste가 수행된다.
    /// - 검증 내용: `.routing(.dropItems)`가 copy operation을 수행하고 FileOpsRecorder에 복사 기록이 남는다.
    /// - 사전 조건: source 파일이 존재하고, target directory가 다른 경로에 존재한다.
    /// - 기대 결과: FileOpsRecorder의 copiedPaths count == 1, source와 destination이 모두 존재한다.
    func testDropExecution_optionDragPerformsCopyOperation() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let recorder = FileOpsRecorder()
        let destinationFolder = sandbox.root.appendingPathComponent("DropTarget")
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let sourcePath = sandbox.fileURL.path
        let destinationPath = destinationFolder.appendingPathComponent(sandbox.fileURL.lastPathComponent).path

        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder)
        }

        // store.exhaustivity = .off: drop execution은 async filesystem mutation; 최종 state와 recorder로 contract 검증.
        store.exhaustivity = .off

        await store.send(.routing(.dropItems(
            sourcePaths: [sourcePath],
            destinationPath: destinationFolder.path,
            isOptionDrag: true,
        )))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(recorder.copiedPaths.count, 1)
        XCTAssertEqual(recorder.copiedPaths.first?.source.path, sourcePath)
        XCTAssertEqual(recorder.copiedPaths.first?.destination.path, destinationPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourcePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationPath))
        XCTAssertEqual(store.state.undoRecords.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// EOP-002-move_entries: 부모 folder와 중첩 child를 함께 Option-drag하면 부모만 복사한다.
    /// hierarchy selection의 중첩 source가 별도 child 복사본을 중복 생성하지 않는지 검증한다.
    /// - 검증 내용: `.routing(.dropItems)`가 source를 top-level path 하나로 축약함
    /// - 사전 조건: fixture folder와 그 안의 child를 함께 source로 전달함
    /// - 기대 결과: 부모 folder만 한 번 복사되고 destination 내부 hierarchy가 보존됨
    func testDropExecution_parentAndChildSourcesCopiesTopLevelFolderOnly() async throws {
        let sandbox = try FixtureSandbox.copyingDirectory(from: "fixtures/fixtures/texts/plain")
        defer { sandbox.cleanup() }

        let recorder = FileOpsRecorder()
        let destinationFolder = sandbox.root.appendingPathComponent("DropTarget")
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let childName = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(atPath: sandbox.fileURL.path).min(),
        )
        let childPath = sandbox.fileURL.appendingPathComponent(childName).path
        let copiedFolder = destinationFolder.appendingPathComponent(sandbox.fileURL.lastPathComponent)

        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder)
        }
        // store.exhaustivity = .off: drop execution은 async filesystem mutation이며 최종 recorder와 파일 구조를 검증한다.
        store.exhaustivity = .off

        await store.send(.routing(.dropItems(
            sourcePaths: [childPath, sandbox.fileURL.path],
            destinationPath: destinationFolder.path,
            isOptionDrag: true,
        )))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(recorder.copiedPaths.count, 1)
        XCTAssertEqual(recorder.copiedPaths.first?.source.path, sandbox.fileURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copiedFolder.appendingPathComponent(childName).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    // AC: EOP-002-move_entries Edge Case #13
    /// EOP-002-move_entries: 드롭 수행 중 이름 충돌이 발생하면 사용자에게 확인 후 거부 시 이동이 취소된다.
    /// 대상 directory에 동일 이름 파일이 존재하고, replace alert에서 사용자가 거부(.stop)하면 move가 수행되지 않는다.
    /// - 검증 내용: `.routing(.dropItems)`가 충돌 감지 후 replace alert → 거부 → FileOpsRecorder에 기록 없음.
    /// - 사전 조건: source 파일과 동일 이름의 파일이 대상 directory에 이미 존재한다.
    /// - 기대 결과: FileOpsRecorder의 movedPaths가 비어 있고, source와 기존 destination이 그대로 유지된다.
    func testDropExecution_nameConflict_userRejects_cancelsMove() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let recorder = FileOpsRecorder()
        let destinationFolder = sandbox.root.appendingPathComponent("ConflictTarget")
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let sourcePath = sandbox.fileURL.path
        let destinationPath = destinationFolder.appendingPathComponent(sandbox.fileURL.lastPathComponent).path
        try FileManager.default.copyItem(at: sandbox.fileURL, to: URL(fileURLWithPath: destinationPath))

        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder)
            $0.entryOperationsAlertClient.showReplaceAlert = { _, _ in .stop }
        }

        // store.exhaustivity = .off: replace-cancel은 async integration path; 최종 state와 filesystem으로 검증.
        store.exhaustivity = .off

        await store.send(.routing(.dropItems(
            sourcePaths: [sourcePath],
            destinationPath: destinationFolder.path,
            isOptionDrag: false,
        )))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertTrue(recorder.movedPaths.isEmpty)
        XCTAssertEqual(store.state.itemStates[sourcePath]?.lastError, .cancelled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourcePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// EOP-002-move_entries: 이름 충돌에서 Replace한 드롭은 source busy를 해제하고 undo할 수 있다.
    /// 사용자가 기존 destination을 Replace해 이동한 직후 생성된 undo record가 ownerBusy에 막히지 않는지 검증한다.
    /// - 검증 내용: `.routing(.dropItems)` Replace-success가 source lifecycle을 종료하고 생성한 record의 undo replay를 수행한다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`의 temp copy와 동일 이름 destination, Replace 응답을 사용한다.
    /// - 기대 결과: source item state의 busy가 해제되고 undo가 destination을 source로 되돌리며 redo record를 남긴다.
    func testDropExecution_nameConflict_userReplaces_clearsSourceBusyAndAllowsUndo() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let recorder = FileOpsRecorder()
        let destinationFolder = sandbox.root.appendingPathComponent("ConflictTarget")
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let sourcePath = sandbox.fileURL.path
        let destinationPath = destinationFolder.appendingPathComponent(sandbox.fileURL.lastPathComponent).path
        try FileManager.default.copyItem(at: sandbox.fileURL, to: URL(fileURLWithPath: destinationPath))

        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder)
            $0.entryOperationsAlertClient.showReplaceAlert = { _, _ in .replace }
        }

        // store.exhaustivity = .off: Replace와 undo의 내부 lifecycle보다 busy 해제와 replay 결과를 검증한다.
        store.exhaustivity = .off

        await store.send(.routing(.dropItems(
            sourcePaths: [sourcePath],
            destinationPath: destinationFolder.path,
            isOptionDrag: false,
        )))
        await store.receive(\.lifecycle.entryActionCompleted)

        XCTAssertFalse(store.state.itemStates[sourcePath]?.isBusy ?? true)
        XCTAssertEqual(store.state.undoRecords.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourcePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationPath))

        let record = try XCTUnwrap(store.state.undoRecords.last)
        await store.send(.undoRedo(.undoEntryAction(record)))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertTrue(FileManager.default.fileExists(atPath: sourcePath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationPath))
        XCTAssertTrue(store.state.undoRecords.isEmpty)
        XCTAssertEqual(store.state.redoRecords.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    // MARK: - EOP-002-cut_entries

    /// EOP-002-cut_entries: clipboard가 copy 상태에서 appDidBecomeActive 시 cut-clear를 수행하지 않는다
    /// clipboard operation이 cut이 아니면 appDidBecomeActive가 no-op이어야 한다.
    /// - 검증 내용: `appDidBecomeActive`가 clipboardOperation=copy 상태에서 상태를 변경하지 않는다.
    /// - 사전 조건: clipboardOperation이 copy이고 clipboardItems가 비어있지 않다.
    /// - 기대 결과: clipboard operation이 copy로 유지된다.
    func testCutClear_copyOperationIsNoop() async {
        var initialState = EntryOperationsState()
        initialState.clipboardOperation = .copy
        initialState.clipboardItems = ["/tmp/file.txt"]

        let store = EntryOperationsTestSupport.makeStore(initialState: initialState)

        await store.send(.lifecycle(.appDidBecomeActive))
        await store.finish()

        XCTAssertEqual(store.state.clipboardOperation, .copy)
    }

    /// EOP-002-cut_entries: cut 상태에서 파일이 존재하면 cut-clear가 유지된다
    /// clipboard operation이 cut이고 잘라내기 원본 파일이 존재하면 heuristic이 keep을 반환한다.
    /// - 검증 내용: `appDidBecomeActive`가 cut 상태에서 파일 존재 시 cutClearSession을 갱신한다.
    /// - 사전 조건: clipboardOperation=cut, clipboardItems에 존재하는 파일 경로, cutClearSession이 nil.
    /// - 기대 결과: cutClearSession이 생성되고 clipboardOperation이 cut으로 유지된다.
    func testCutClear_cutWithExistingFilesKeepsSession() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let filePath = sandbox.fileURL.path

        var initialState = EntryOperationsState()
        initialState.clipboardOperation = .cut
        initialState.clipboardItems = [filePath]

        let store = EntryOperationsTestSupport.makeStore(initialState: initialState) {
            $0.entryFileOpsClient.fileExists = { path in
                FileManager.default.fileExists(atPath: path)
            }
            $0.entryFileOpsClient.clipboardChangeCount = { 0 }
            $0.entryFileOpsClient.loadClipboardCutSessionId = { nil }
            $0.entryFileOpsClient.saveClipboardCutSessionId = { _ in }
            $0.uuid = .constant(UUID())
        }

        store.exhaustivity = .off

        await store.send(.lifecycle(.appDidBecomeActive))
        await store.finish()

        XCTAssertEqual(store.state.clipboardOperation, .cut)
        XCTAssertNotNil(store.state.cutClearSession)
    }

    /// EOP-002-cut_entries: cut 상태에서 파일이 사라지면 copy로 전환된다
    /// clipboard operation이 cut이고 잘라내기 원본 파일이 존재하지 않으면 copy로 자동 전환된다.
    /// - 검증 내용: `appDidBecomeActive`가 cut 상태에서 파일 부재 시 setClipboardOperation(.copy)를 발생시킨다.
    /// - 사전 조건: clipboardOperation=cut, clipboardItems에 존재하지 않는 파일 경로.
    /// - 기대 결과: clipboardOperation이 copy로 전환된다.
    func testCutClear_cutWithMissingFilesConvertsToCopy() async {
        let missingPath = "/tmp/nonexistent-file-\(UUID().uuidString).txt"

        var initialState = EntryOperationsState()
        initialState.clipboardOperation = .cut
        initialState.clipboardItems = [missingPath]
        initialState.cutClearSession = EntryOperationsCutClearHeuristic.CutSession(
            cutSessionId: UUID().uuidString,
            pasteboard: .init(changeCount: 0),
            sourcePaths: [missingPath],
            filePolling: .init(nextCheckAt: Date.distantPast, nextIntervalIndex: 0),
        )

        let store = EntryOperationsTestSupport.makeStore(initialState: initialState) {
            $0.entryFileOpsClient.fileExists = { path in
                FileManager.default.fileExists(atPath: path)
            }
            $0.entryFileOpsClient.clipboardChangeCount = { 0 }
            $0.entryFileOpsClient.loadClipboardCutSessionId = { nil }
            $0.entryFileOpsClient.saveClipboardCutSessionId = { _ in }
            $0.pasteboardClient = .noOp
        }

        store.exhaustivity = .off

        await store.send(.lifecycle(.appDidBecomeActive))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.clipboardOperation, .copy)
    }

    /// EOP-002-cut_entries: 외부 pasteboard 변경 시 session ID 불일치로 copy로 전환된다
    /// pasteboard changeCount가 변경되고 session ID가 불일치하면 cut 상태를 즉시 clear한다.
    /// - 검증 내용: `appDidBecomeActive`에서 pasteboard changeCount 변경 + session ID 불일치 감지 시 copy 전환.
    /// - 사전 조건: clipboardOperation=cut, cutClearSession 존재, changeCount가 변경됨, session ID가 다름.
    /// - 기대 결과: clipboardOperation이 copy로 전환된다.
    func testCutClear_externalPasteboardChangeConvertsToCopy() async {
        let filePath = "/tmp/file.txt"

        var initialState = EntryOperationsState()
        initialState.clipboardOperation = .cut
        initialState.clipboardItems = [filePath]
        initialState.cutClearSession = EntryOperationsCutClearHeuristic.CutSession(
            cutSessionId: "original-session-id",
            pasteboard: .init(changeCount: 0),
            sourcePaths: [filePath],
            filePolling: .init(nextCheckAt: Date.distantPast, nextIntervalIndex: 0),
        )

        let store = EntryOperationsTestSupport.makeStore(initialState: initialState) {
            $0.entryFileOpsClient.fileExists = { _ in true }
            $0.entryFileOpsClient.clipboardChangeCount = { 1 }
            $0.entryFileOpsClient.loadClipboardCutSessionId = { "different-session-id" }
            $0.entryFileOpsClient.saveClipboardCutSessionId = { _ in }
            $0.pasteboardClient = .noOp
        }

        store.exhaustivity = .off

        await store.send(.lifecycle(.appDidBecomeActive))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.clipboardOperation, .copy)
    }

    // AC: EOP-002-cut_entries Edge Case #1
    /// EOP-002-cut_entries: bg→fg 전환 시 만료된 cut session이 copy로 자동 전환된다
    /// clipboard operation이 cut 상태에서 앱이 bg→fg 전환되면, CutClearHeuristic이 session을 평가하고
    /// 만료 조건(polling 시간 경과 후 파일 부재 감지)이 충족되면 clipboard operation을 copy로 전환한다.
    /// - 검증 내용: `appDidBecomeActive`에서 cutClearSession이 존재하고 polling 기간이 도래했을 때,
    ///   파일이 존재하지 않으면 setClipboardOperation(.copy)를 발생시킨다.
    /// - 사전 조건: clipboardOperation=cut, cutClearSession 존재(filePolling.nextCheckAt이 과거),
    ///   sourcePaths의 파일이 존재하지 않음, pasteboard changeCount 동일, session ID 일치.
    /// - 기대 결과: clipboardOperation이 copy로 전환된다.
    func testCutClear_foregroundTransitionExpiredSessionConvertsToCopy() async {
        let sessionId = UUID().uuidString
        let missingPath = "/tmp/nonexistent-file-\(UUID().uuidString).txt"

        var initialState = EntryOperationsState()
        initialState.clipboardOperation = .cut
        initialState.clipboardItems = [missingPath]
        initialState.cutClearSession = EntryOperationsCutClearHeuristic.CutSession(
            cutSessionId: sessionId,
            pasteboard: .init(changeCount: 0),
            sourcePaths: [missingPath],
            filePolling: .init(nextCheckAt: Date.distantPast, nextIntervalIndex: 0),
        )

        let store = EntryOperationsTestSupport.makeStore(initialState: initialState) {
            $0.entryFileOpsClient.fileExists = { path in
                FileManager.default.fileExists(atPath: path)
            }
            $0.entryFileOpsClient.clipboardChangeCount = { 0 }
            $0.entryFileOpsClient.loadClipboardCutSessionId = { sessionId }
            $0.entryFileOpsClient.saveClipboardCutSessionId = { _ in }
            $0.pasteboardClient = .noOp
        }

        store.exhaustivity = .off

        await store.send(.lifecycle(.appDidBecomeActive))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.clipboardOperation, .copy)
    }

    // MARK: - EOP-002-drop_path_policy

    /// EOP-002-drop_path_policy: path equivalence는 raw String equality를 유지한다.
    /// - 사전 조건: 실제 fixture sandbox root와 동일 경로의 `/.` 표기를 비교한다.
    /// - 기대 결과: 완전히 같은 문자열만 equivalent이고 표기만 다른 경로는 equivalent가 아니다.
    func testDropPathPolicy_preservesRawPathEquivalence() throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let path = sandbox.root.path

        XCTAssertTrue(EntryDropPathPolicy.areEquivalent(path, path))
        XCTAssertFalse(EntryDropPathPolicy.areEquivalent(path, path + "/."))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// EOP-002-drop_path_policy: descendant 판정만 standardized path components를 사용한다.
    /// - 사전 조건: fixture sandbox 아래 실제 child directory와 `..`를 포함한 equivalent 표기를 준비한다.
    /// - 기대 결과: standardized candidate가 source 하위이면 descendant로 판정된다.
    func testDropPathPolicy_standardizesDescendantComponents() throws {
        let sandbox = try FixtureSandbox.copyingDirectory(from: "fixtures/fixtures/images/jpeg")
        defer { sandbox.cleanup() }
        let child = sandbox.fileURL.appendingPathComponent("Child")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let candidate = child.appendingPathComponent("..").appendingPathComponent("Child").path

        XCTAssertTrue(EntryDropPathPolicy.isDescendant(candidate, of: sandbox.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// EOP-002-drop_path_policy: copy intent는 same-parent/self/descendant move guard를 우회한다.
    /// - 사전 조건: 실제 fixture source와 같은 parent destination, prefersCopy=true를 사용한다.
    /// - 기대 결과: 기존 정책대로 copy가 선택되고 Option intent가 유지된다.
    func testDropValidation_copyBypassesMovePathGuards() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let store = EntryOperationsTestSupport.makeStore()
        let context = EntryDropValidationContext(
            sourcePaths: [sandbox.fileURL.path],
            destinationPath: sandbox.root.path,
            allowedOperationsRawValue: NSDragOperation.copy.rawValue | NSDragOperation.move.rawValue,
            prefersCopy: true,
        )

        await store.send(.routing(.validateDrop(context: context))) {
            $0.dropValidationResult = EntryDropValidationResult(
                destinationPath: sandbox.root.path,
                resolvedOperation: .copy,
                isOptionDrag: true,
            )
        }
        await store.finish()

        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// EOP-002-create_entry_alias: 원본이 사라진 상태에서는 alias 생성이 실패해야 한다.
    /// 사용자가 존재하지 않는 `fixtures/fixtures/texts/plain/missing.txt`를 alias로 만들면 실패가 정상이라는 점을 확인한다.
    /// - 검증 내용: `.edit(.createAliases)`가 소스 부재를 감지해 failure 상태를 반환한다.
    /// - 사전 조건: 실제 파일이 없는 경로를 source로 주고, alias 충돌은 없는 상태다.
    /// - 기대 결과: alias 파일이 생성되지 않고, reducer state에는 실패가 반영되며, 샌드박스 원본 fixture는 영향을 받지 않는다.
    func testCreateEntryAlias_missingSourceFailure() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let sourcePath = sandbox.root.appendingPathComponent("missing.txt").path
        let aliasPath = sandbox.root.appendingPathComponent("missing.txt alias").path

        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.entryFileOpsClient = makeAliasRecordingClient()
        }

        // store.exhaustivity = .off: source-missing failure is asynchronous; we only assert the final contract.
        store.exhaustivity = .off

        await store.send(.edit(.createAliases(paths: [sourcePath])))
        await store.finish()

        XCTAssertFalse(FileManager.default.fileExists(atPath: aliasPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    // MARK: - EOP-002-provider_drop_impact

    /// Provider decode가 지연되어도 perform-time move intent가 유지되고 한 번만 실행된다.
    func testProviderDrop_delayedMovePreservesIntentAndEmitsImpact() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let destinationFolder = sandbox.root.appendingPathComponent("DelayedMoveTarget")
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let provider = DelayedFileURLItemProvider(fileURL: sandbox.fileURL)
        let fileOpsRecorder = FileOpsRecorder()
        let actionRecorder = CallRecorder<EntryOperationsAction>()
        let reloadRecorder = CallRecorder<[String]>()
        let store = EntryOperationsTestSupport.makeObservedStore(observeAction: actionRecorder.record) {
            var client = makeRecordedFileOpsClient(recorder: fileOpsRecorder)
            client.postFileSystemChanged = reloadRecorder.record
            $0.entryFileOpsClient = client
        }
        store.exhaustivity = .off

        await store.send(.routing(.handleDrop(
            providers: [provider.provider],
            destinationPath: destinationFolder.path,
            isOptionDrag: false,
        )))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(provider.loadCount, 1)
        XCTAssertEqual(fileOpsRecorder.movedPaths.count, 1)
        XCTAssertTrue(fileOpsRecorder.copiedPaths.isEmpty)
        XCTAssertEqual(mutationImpacts(in: actionRecorder.recorded), [
            EntryOperationsMutationImpact(
                sourceParentPaths: [sandbox.root.path],
                destinationPath: destinationFolder.path,
            ),
        ])
        XCTAssertTrue(reloadRecorder.recorded.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// 여러 지연 provider의 copy intent가 유지되고 동일 source parent는 raw-equivalence로 dedup된다.
    func testProviderDrop_delayedCopyDeduplicatesSuccessfulSourceParents() async throws {
        let sandbox = try FixtureSandbox.copyingDirectory(from: "fixtures/fixtures/images/jpeg")
        defer { sandbox.cleanup() }
        let names = try FileManager.default.contentsOfDirectory(atPath: sandbox.fileURL.path).sorted()
        let sourceURLs = names.prefix(2).map { name in
            sandbox.fileURL.appendingPathComponent(name)
        }
        XCTAssertEqual(sourceURLs.count, 2)
        let destinationFolder = sandbox.root.appendingPathComponent("DelayedCopyTarget")
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let providers = sourceURLs.map { DelayedFileURLItemProvider(fileURL: $0) }
        let fileOpsRecorder = FileOpsRecorder()
        let actionRecorder = CallRecorder<EntryOperationsAction>()
        let store = EntryOperationsTestSupport.makeObservedStore(observeAction: actionRecorder.record) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: fileOpsRecorder)
        }
        store.exhaustivity = .off

        await store.send(.routing(.handleDrop(
            providers: providers.map(\.provider),
            destinationPath: destinationFolder.path,
            isOptionDrag: true,
        )))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(providers.map(\.loadCount), [1, 1])
        XCTAssertEqual(fileOpsRecorder.copiedPaths.count, 2)
        XCTAssertTrue(fileOpsRecorder.movedPaths.isEmpty)
        XCTAssertEqual(mutationImpacts(in: actionRecorder.recorded), [
            EntryOperationsMutationImpact(
                sourceParentPaths: [sandbox.fileURL.path],
                destinationPath: destinationFolder.path,
            ),
        ])
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// Batch 일부 실패 시 mutation impact에는 실제 성공한 source parent만 포함된다.
    func testProviderDrop_partialFailureReportsOnlySuccessfulSourceParent() async throws {
        let successfulSandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { successfulSandbox.cleanup() }
        let failedSandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { failedSandbox.cleanup() }
        let destinationFolder = successfulSandbox.root.appendingPathComponent("PartialTarget")
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let providers = [successfulSandbox.fileURL, failedSandbox.fileURL]
            .map { DelayedFileURLItemProvider(fileURL: $0) }
        let fileOpsRecorder = FileOpsRecorder()
        let actionRecorder = CallRecorder<EntryOperationsAction>()
        var fileOpsClient = makeRecordedFileOpsClient(recorder: fileOpsRecorder)
        fileOpsClient.pasteFile = { sourceURL, destinationURL in
            guard sourceURL.path != failedSandbox.fileURL.path else {
                throw FileOpError.system(message: "simulated provider failure")
            }
            try await EntryFileOpsClient.liveValue.pasteFile(sourceURL, destinationURL)
            fileOpsRecorder.recordCopy(source: sourceURL, destination: destinationURL)
        }
        let store = EntryOperationsTestSupport.makeObservedStore(observeAction: actionRecorder.record) {
            $0.entryFileOpsClient = fileOpsClient
            $0.entryOperationsAlertClient.showReplaceAlert = { _, _ in .stop }
        }
        store.exhaustivity = .off

        await store.send(.routing(.handleDrop(
            providers: providers.map(\.provider),
            destinationPath: destinationFolder.path,
            isOptionDrag: true,
        )))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(fileOpsRecorder.copiedPaths.count, 1)
        XCTAssertEqual(mutationImpacts(in: actionRecorder.recorded), [
            EntryOperationsMutationImpact(
                sourceParentPaths: [successfulSandbox.root.path],
                destinationPath: destinationFolder.path,
            ),
        ])
        XCTAssertTrue(FileManager.default.fileExists(atPath: successfulSandbox.originalFixture.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: failedSandbox.originalFixture.path))
    }

    /// 모든 provider mutation이 실패하면 outward success outcome을 내보내지 않는다.
    func testProviderDrop_allFailureEmitsNoMutationImpact() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let destinationFolder = sandbox.root.appendingPathComponent("BlockedTarget")
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: sandbox.fileURL,
            to: destinationFolder.appendingPathComponent(sandbox.fileURL.lastPathComponent),
        )

        let provider = DelayedFileURLItemProvider(fileURL: sandbox.fileURL)
        let fileOpsRecorder = FileOpsRecorder()
        let actionRecorder = CallRecorder<EntryOperationsAction>()
        let store = EntryOperationsTestSupport.makeObservedStore(observeAction: actionRecorder.record) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: fileOpsRecorder)
            $0.entryOperationsAlertClient.showReplaceAlert = { _, _ in .stop }
        }
        store.exhaustivity = .off

        await store.send(.routing(.handleDrop(
            providers: [provider.provider],
            destinationPath: destinationFolder.path,
            isOptionDrag: false,
        )))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertTrue(fileOpsRecorder.movedPaths.isEmpty)
        XCTAssertTrue(mutationImpacts(in: actionRecorder.recorded).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// 같은 parent로의 move no-op은 mutation impact를 내보내지 않는다.
    func testProviderDrop_sameParentNoOpEmitsNoMutationImpact() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let provider = DelayedFileURLItemProvider(fileURL: sandbox.fileURL)
        let fileOpsRecorder = FileOpsRecorder()
        let actionRecorder = CallRecorder<EntryOperationsAction>()
        let store = EntryOperationsTestSupport.makeObservedStore(observeAction: actionRecorder.record) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: fileOpsRecorder)
        }
        store.exhaustivity = .off

        await store.send(.routing(.handleDrop(
            providers: [provider.provider],
            destinationPath: sandbox.root.path,
            isOptionDrag: false,
        )))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertTrue(fileOpsRecorder.movedPaths.isEmpty)
        XCTAssertTrue(mutationImpacts(in: actionRecorder.recorded).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// Provider move가 source descendant를 대상으로 하면 Task 1 path guard에서 거절된다.
    func testProviderDrop_descendantMoveEmitsNoMutationImpact() async throws {
        let sandbox = try FixtureSandbox.copyingDirectory(from: "fixtures/fixtures/images/jpeg")
        defer { sandbox.cleanup() }
        let destinationFolder = sandbox.fileURL.appendingPathComponent("DescendantTarget")
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let provider = DelayedFileURLItemProvider(fileURL: sandbox.fileURL)
        let fileOpsRecorder = FileOpsRecorder()
        let actionRecorder = CallRecorder<EntryOperationsAction>()
        let store = EntryOperationsTestSupport.makeObservedStore(observeAction: actionRecorder.record) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: fileOpsRecorder)
        }
        store.exhaustivity = .off

        await store.send(.routing(.handleDrop(
            providers: [provider.provider],
            destinationPath: destinationFolder.path,
            isOptionDrag: false,
        )))
        await store.finish()
        await store.skipReceivedActions()
        XCTAssertTrue(fileOpsRecorder.movedPaths.isEmpty)
        XCTAssertTrue(mutationImpacts(in: actionRecorder.recorded).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// EOP-002-provider_drop_impact: 빈 provider request는 decode·filesystem mutation·outcome 없이 종료됨
    /// Sidebar 경계 이후에도 비어 있는 provider 배열이 EOP 실행 경로를 만들지 않는지 검증한다.
    /// - 검증 내용: provider decode 결과 없음, move/copy command 0회, mutation impact 0회
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`의 temp sandbox와 빈 provider 배열
    /// - 기대 결과: source와 repository fixture가 유지되고 filesystem recorder와 outward outcome이 비어 있음
    func testProviderDrop_emptyProvidersEmitNoMutationImpact() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let fileOpsRecorder = FileOpsRecorder()
        let actionRecorder = CallRecorder<EntryOperationsAction>()
        let store = EntryOperationsTestSupport.makeObservedStore(observeAction: actionRecorder.record) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: fileOpsRecorder)
        }
        // store.exhaustivity = .off: provider effect의 내부 action 대신 최종 command/outcome 부재를 검증한다.
        store.exhaustivity = .off

        await store.send(.routing(.handleDrop(
            providers: [],
            destinationPath: sandbox.root.path,
            isOptionDrag: false,
        )))
        await store.finish()

        XCTAssertTrue(fileOpsRecorder.movedPaths.isEmpty)
        XCTAssertTrue(fileOpsRecorder.copiedPaths.isEmpty)
        XCTAssertTrue(mutationImpacts(in: actionRecorder.recorded).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// EOP-002-provider_drop_impact: provider 하나라도 fileURL decode에 실패하면 전체 session을 거절함
    /// 유효한 fixture provider 뒤에 fileURL을 advertise하지만 invalid data를 반환하는 provider가 섞인 경로를 검증한다.
    /// - 검증 내용: 두 provider load 후 `dropItems`, move/copy command, mutation impact가 모두 0회
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`의 temp copy와 invalid fileURL data provider
    /// - 기대 결과: source와 repository fixture가 유지되고 batch 전체가 filesystem mutation 전에 종료됨
    func testProviderDrop_mixedDecodeFailureRejectsEntireSession() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let validProvider = DelayedFileURLItemProvider(fileURL: sandbox.fileURL, delay: 0)
        let failedLoadCount = LockIsolated(0)
        let failingProvider = NSItemProvider()
        failingProvider.registerDataRepresentation(
            forTypeIdentifier: UTType.fileURL.identifier,
            visibility: .all,
        ) { completionHandler in
            failedLoadCount.withValue { $0 += 1 }
            completionHandler(Data("not-a-file-url".utf8), nil)
            let progress = Progress(totalUnitCount: 1)
            progress.completedUnitCount = 1
            return progress
        }
        let fileOpsRecorder = FileOpsRecorder()
        let actionRecorder = CallRecorder<EntryOperationsAction>()
        let store = EntryOperationsTestSupport.makeObservedStore(observeAction: actionRecorder.record) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: fileOpsRecorder)
        }
        // store.exhaustivity = .off: provider decode batch의 downstream command/outcome 부재를 recorder로 검증한다.
        store.exhaustivity = .off

        await store.send(.routing(.handleDrop(
            providers: [validProvider.provider, failingProvider],
            destinationPath: sandbox.root.appendingPathComponent("RejectedTarget").path,
            isOptionDrag: false,
        )))
        await store.finish()

        XCTAssertEqual(validProvider.loadCount, 1)
        XCTAssertEqual(failedLoadCount.value, 1)
        XCTAssertFalse(actionRecorder.recorded.contains { action in
            if case .routing(.dropItems) = action { return true }
            return false
        })
        XCTAssertTrue(fileOpsRecorder.movedPaths.isEmpty)
        XCTAssertTrue(fileOpsRecorder.copiedPaths.isEmpty)
        XCTAssertTrue(mutationImpacts(in: actionRecorder.recorded).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// EOP-002-provider_drop_impact: directory를 자기 자신에 move-drop하면 path guard가 실행을 거절함
    /// 사용자가 source directory 자체를 destination으로 지정하는 self-drop 경로를 검증한다.
    /// - 검증 내용: decoded provider 1회, move/copy command 0회, mutation impact 0회
    /// - 사전 조건: `fixtures/fixtures/images/jpeg`의 temp directory copy를 source와 destination으로 함께 사용
    /// - 기대 결과: sandbox와 repository fixture가 유지되고 filesystem mutation과 outward outcome이 없음
    func testProviderDrop_selfMoveEmitsNoMutationImpact() async throws {
        let sandbox = try FixtureSandbox.copyingDirectory(from: "fixtures/fixtures/images/jpeg")
        defer { sandbox.cleanup() }
        let provider = DelayedFileURLItemProvider(fileURL: sandbox.fileURL)
        let fileOpsRecorder = FileOpsRecorder()
        let actionRecorder = CallRecorder<EntryOperationsAction>()
        let store = EntryOperationsTestSupport.makeObservedStore(observeAction: actionRecorder.record) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: fileOpsRecorder)
        }
        // store.exhaustivity = .off: provider decode 이후 path guard의 최종 mutation/outcome 부재를 검증한다.
        store.exhaustivity = .off

        await store.send(.routing(.handleDrop(
            providers: [provider.provider],
            destinationPath: sandbox.fileURL.path,
            isOptionDrag: false,
        )))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(provider.loadCount, 1)
        XCTAssertTrue(fileOpsRecorder.movedPaths.isEmpty)
        XCTAssertTrue(fileOpsRecorder.copiedPaths.isEmpty)
        XCTAssertTrue(mutationImpacts(in: actionRecorder.recorded).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// EOP-002-provider_drop_impact: missing destination 실패는 source와 outcome을 보존함
    /// 존재하지 않는 destination hierarchy로 move할 때의 실제 filesystem failure를 검증한다.
    /// - 검증 내용: missing destination의 실제 move 실패에서 성공 recorder와 mutation impact 0회
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`의 temp copy와 생성되지 않은 destination hierarchy
    /// - 기대 결과: source와 repository fixture가 유지되고 destination과 outward outcome이 생성되지 않음
    func testProviderDrop_missingDestinationEmitsNoMutationImpact() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let destination = sandbox.root
            .appendingPathComponent("MissingParent")
            .appendingPathComponent("Destination")
        let provider = DelayedFileURLItemProvider(fileURL: sandbox.fileURL)
        let fileOpsRecorder = FileOpsRecorder()
        let actionRecorder = CallRecorder<EntryOperationsAction>()
        let store = EntryOperationsTestSupport.makeObservedStore(observeAction: actionRecorder.record) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: fileOpsRecorder)
        }
        // store.exhaustivity = .off: 실제 missing destination 실패의 최종 filesystem/outcome contract를 검증한다.
        store.exhaustivity = .off

        await store.send(.routing(.handleDrop(
            providers: [provider.provider],
            destinationPath: destination.path,
            isOptionDrag: false,
        )))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(provider.loadCount, 1)
        XCTAssertTrue(fileOpsRecorder.movedPaths.isEmpty)
        XCTAssertTrue(mutationImpacts(in: actionRecorder.recorded).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// EOP-002-provider_drop_impact: unwritable destination 실패는 source와 outcome을 보존함
    /// destination write가 permission-denied를 반환하는 filesystem failure를 검증한다.
    /// - 검증 내용: move dependency permission-denied 실패에서 mutation impact 0회
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`의 temp copy와 permission-denied move client
    /// - 기대 결과: source와 repository fixture가 유지되고 destination file과 outward outcome이 생성되지 않음
    func testProviderDrop_unwritableDestinationEmitsNoMutationImpact() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let destination = sandbox.root.appendingPathComponent("UnwritableDestination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let provider = DelayedFileURLItemProvider(fileURL: sandbox.fileURL)
        let actionRecorder = CallRecorder<EntryOperationsAction>()
        let store = EntryOperationsTestSupport.makeObservedStore(observeAction: actionRecorder.record) {
            var client = makeRecordedFileOpsClient(recorder: FileOpsRecorder())
            client.moveFile = { _, _ in throw FileOpError.system(message: "permission denied") }
            $0.entryFileOpsClient = client
        }
        // store.exhaustivity = .off: permission-denied dependency 실패의 최종 source/outcome 보존만 검증한다.
        store.exhaustivity = .off

        await store.send(.routing(.handleDrop(
            providers: [provider.provider],
            destinationPath: destination.path,
            isOptionDrag: false,
        )))
        await store.finish()
        await store.skipReceivedActions()
        XCTAssertEqual(provider.loadCount, 1)
        XCTAssertTrue(mutationImpacts(in: actionRecorder.recorded).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: destination.appendingPathComponent(sandbox.fileURL.lastPathComponent).path,
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    // MARK: - EOP-002-drop_external_entries_on_directory_page

    /// EOP-002-drop_external_entries_on_directory_page: 빈 external source는 drop operation을 만들지 않는다.
    /// external payload가 비어 있으면 허용 operation mask가 남아 있어도 즉시 거절되어야 한다.
    /// - 검증 내용: `.routing(.validateDrop(context:))`가 빈 sourcePaths에서 `.none`과 `isOptionDrag=false`를 반환한다.
    /// - 사전 조건: sourcePaths가 비어 있고 destination과 copy 허용 mask가 존재한다.
    /// - 기대 결과: destination은 유지되고 operation은 `.none`으로 resolve된다.
    func testExternalDrop_emptySourceResolvesNone() async {
        let destinationPath = "/Users/test/Desktop"
        let store = EntryOperationsTestSupport.makeStore()
        let context = EntryDropValidationContext(
            sourcePaths: [],
            destinationPath: destinationPath,
            allowedOperationsRawValue: NSDragOperation.copy.rawValue | NSDragOperation.move.rawValue,
            prefersCopy: false,
        )

        await store.send(.routing(.validateDrop(context: context))) {
            $0.dropValidationResult = EntryDropValidationResult(
                destinationPath: destinationPath,
                resolvedOperation: .none,
                isOptionDrag: false,
            )
        }

        XCTAssertEqual(store.state.dropValidationResult.resolvedOperation, .none)
        XCTAssertFalse(store.state.dropValidationResult.isOptionDrag)
    }

    /// EOP-002-drop_external_entries_on_directory_page: copy-only external source는 copy로 resolve된다.
    /// source mask에 copy만 있으면 Option modifier가 없어도 move로 승격하지 않아야 한다.
    /// - 검증 내용: `.copy` mask와 `prefersCopy=false`가 `.copy` 및 `isOptionDrag=true`로 resolve되는지 확인한다.
    /// - 사전 조건: sourcePaths에 external file path가 있고 destination이 source parent와 다르며 copy만 허용된다.
    /// - 기대 결과: resolvedOperation이 `.copy`이고 `isOptionDrag`가 true다.
    func testExternalDrop_copyOnlySourceResolvesCopy() async {
        let store = EntryOperationsTestSupport.makeStore()
        let context = EntryDropValidationContext(
            sourcePaths: ["/Users/test/Documents/file.txt"],
            destinationPath: "/Users/test/Desktop",
            allowedOperationsRawValue: NSDragOperation.copy.rawValue,
            prefersCopy: false,
        )

        await store.send(.routing(.validateDrop(context: context))) {
            $0.dropValidationResult = EntryDropValidationResult(
                destinationPath: "/Users/test/Desktop",
                resolvedOperation: .copy,
                isOptionDrag: true,
            )
        }

        XCTAssertEqual(store.state.dropValidationResult.resolvedOperation, .copy)
        XCTAssertTrue(store.state.dropValidationResult.isOptionDrag)
    }

    /// EOP-002-drop_external_entries_on_directory_page: move-allowed external source는 move로 resolve된다.
    /// move가 허용된 source를 Option 없이 drop하면 기존 move semantics를 유지해야 한다.
    /// - 검증 내용: `.move` mask와 `prefersCopy=false`가 `.move` 및 `isOptionDrag=false`로 resolve되는지 확인한다.
    /// - 사전 조건: sourcePaths에 external file path가 있고 destination이 source parent와 다르며 move가 허용된다.
    /// - 기대 결과: resolvedOperation이 `.move`이고 `isOptionDrag`가 false다.
    func testExternalDrop_moveAllowedSourceResolvesMove() async {
        let store = EntryOperationsTestSupport.makeStore()
        let context = EntryDropValidationContext(
            sourcePaths: ["/Users/test/Documents/file.txt"],
            destinationPath: "/Users/test/Desktop",
            allowedOperationsRawValue: NSDragOperation.move.rawValue,
            prefersCopy: false,
        )

        await store.send(.routing(.validateDrop(context: context))) {
            $0.dropValidationResult = EntryDropValidationResult(
                destinationPath: "/Users/test/Desktop",
                resolvedOperation: .move,
                isOptionDrag: false,
            )
        }

        XCTAssertEqual(store.state.dropValidationResult.resolvedOperation, .move)
        XCTAssertFalse(store.state.dropValidationResult.isOptionDrag)
    }

    /// EOP-002-drop_external_entries_on_directory_page: dropItems는 stale named transport를 실행하지 않는다.
    /// 외부 drop의 active payload가 dropItems sourcePaths로 전달되면 저장된 internal path는 실행 source가 될 수 없다.
    /// - 검증 내용: move 실행 후 FileOpsRecorder에 active source만 기록되고 stale path의 copy/move/delete가 0건인지 확인한다.
    /// - 사전 조건: named transport에는 stale path를 seed하고, active external source와 별도 move destination을 준비한다.
    /// - 기대 결과: active source만 이동되고 stale path는 어떤 파일 operation에도 나타나지 않는다.
    func testExternalDropItems_ignoresStaleNamedTransportPath() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let staleURL = sandbox.root.appendingPathComponent("stale-internal.txt")
        try FileManager.default.copyItem(at: sandbox.fileURL, to: staleURL)
        let destinationFolder = sandbox.root.appendingPathComponent("ActiveMove")
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let recorder = FileOpsRecorder()
        var client = makeRecordedFileOpsClient(recorder: recorder)
        client.loadDragPaths = { [staleURL.path] }
        client.loadDragWithOption = { false }
        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.entryFileOpsClient = client
        }

        // store.exhaustivity = .off: drop 실행은 여러 lifecycle action을 내므로 recorder와 filesystem 결과를 검증한다.
        store.exhaustivity = .off
        await store.send(.routing(.dropItems(
            sourcePaths: [sandbox.fileURL.path],
            destinationPath: destinationFolder.path,
            isOptionDrag: false,
        )))
        await store.finish()
        await store.skipReceivedActions()
        XCTAssertEqual(recorder.movedPaths.map(\.source.path), [sandbox.fileURL.path])
        XCTAssertTrue(recorder.copiedPaths.isEmpty)
        XCTAssertTrue(recorder.deletedPaths.isEmpty)
        XCTAssertTrue(recorder.trashedPaths.allSatisfy { $0.path != staleURL.path })
        XCTAssertTrue(recorder.renamedPaths
            .allSatisfy { $0.source.path != staleURL.path && $0.destination.path != staleURL.path })
        XCTAssertTrue(FileManager.default.fileExists(atPath: staleURL.path))
    }

    /// EOP-002-drop_external_entries_on_directory_page: active external payload만 copy 실행 source로 사용한다.
    /// dropItems가 named transport를 읽지 않고 action payload의 sourcePaths만 downstream paste에 전달하는지 확인한다.
    /// - 검증 내용: stale internal path가 transport에 있어도 copy recorder에는 active source 하나만 남는지 검증한다.
    /// - 사전 조건: stale path와 active source가 모두 존재하고, named transport는 stale path를 반환하도록 주입한다.
    /// - 기대 결과: active source만 destination으로 복사되고 stale path에는 copy/move/delete가 발생하지 않는다.
    func testExternalDropItems_executesOnlyActiveSourcePaths() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let staleURL = sandbox.root.appendingPathComponent("stale-internal.txt")
        try FileManager.default.copyItem(at: sandbox.fileURL, to: staleURL)
        let destinationFolder = sandbox.root.appendingPathComponent("ActiveCopy")
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let recorder = FileOpsRecorder()
        var client = makeRecordedFileOpsClient(recorder: recorder)
        client.loadDragPaths = { [staleURL.path] }
        client.loadDragWithOption = { false }
        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.entryFileOpsClient = client
        }

        // store.exhaustivity = .off: copy 실행의 lifecycle action 대신 active source와 recorder 결과를 검증한다.
        store.exhaustivity = .off
        await store.send(.routing(.dropItems(
            sourcePaths: [sandbox.fileURL.path],
            destinationPath: destinationFolder.path,
            isOptionDrag: true,
        )))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(recorder.copiedPaths.map(\.source.path), [sandbox.fileURL.path])
        XCTAssertTrue(recorder.movedPaths.isEmpty)
        XCTAssertTrue(recorder.deletedPaths.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: staleURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationFolder.appendingPathComponent("11.txt").path))
    }

    /// EOP-002-drop_external_entries_on_directory_page: 취소된 drop 뒤 다음 source가 이전 source를 재사용하지 않는다.
    /// 이름 충돌로 취소된 move session이 다음 외부 drop의 active source를 오염시키지 않아야 한다.
    /// - 검증 내용: 첫 drop은 cancel failure가 되고 두 번째 drop은 새 source만 이동하는지 확인한다.
    /// - 사전 조건: 첫 destination에는 충돌 파일이 있고 replace alert는 `.stop`이며 두 번째 source/destination은 유효하다.
    /// - 기대 결과: 첫 source는 이동되지 않고 두 번째 source만 이동되며 recorder에 이전 source가 재사용되지 않는다.
    func testExternalDropItems_afterCancellationDoesNotReusePreviousSource() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let firstSource = sandbox.fileURL
        let secondSource = sandbox.root.appendingPathComponent("next-session.txt")
        try FileManager.default.copyItem(at: firstSource, to: secondSource)
        let firstDestinationFolder = sandbox.root.appendingPathComponent("CancelledDestination")
        let secondDestinationFolder = sandbox.root.appendingPathComponent("NextDestination")
        try FileManager.default.createDirectory(at: firstDestinationFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDestinationFolder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: firstSource,
            to: firstDestinationFolder.appendingPathComponent(firstSource.lastPathComponent),
        )

        let recorder = FileOpsRecorder()
        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder)
            $0.entryOperationsAlertClient.showReplaceAlert = { _, _ in .stop }
        }

        // store.exhaustivity = .off: cancel 후 새 drop의 source 격리를 recorder와 filesystem 결과로 검증한다.
        store.exhaustivity = .off
        await store.send(.routing(.dropItems(
            sourcePaths: [firstSource.path],
            destinationPath: firstDestinationFolder.path,
            isOptionDrag: false,
        )))
        await store.finish()
        await store.skipReceivedActions()
        await store.send(.routing(.dropItems(
            sourcePaths: [secondSource.path],
            destinationPath: secondDestinationFolder.path,
            isOptionDrag: false,
        )))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.itemStates[firstSource.path]?.lastError, .cancelled)
        XCTAssertEqual(recorder.movedPaths.map(\.source.path), [secondSource.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstSource.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondSource.path))
    }

    /// EOP-002-drop_external_entries_on_directory_page: 실패한 drop 뒤 다음 source가 이전 source를 재사용하지 않는다.
    /// source failure가 다음 외부 drop의 active payload와 실행 경로를 오염시키지 않아야 한다.
    /// - 검증 내용: 존재하지 않는 첫 source 실패 후 두 번째 유효 source만 move recorder에 남는지 확인한다.
    /// - 사전 조건: 첫 source는 missing path이고 두 번째 source와 destination은 실제 샌드박스 경로다.
    /// - 기대 결과: 첫 source operation은 없고 두 번째 source만 이동되어 session 간 source 재사용이 없다.
    func testExternalDropItems_afterFailureDoesNotReusePreviousSource() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let failedSourcePath = sandbox.root.appendingPathComponent("missing-source.txt").path
        let secondSource = sandbox.fileURL
        let destinationFolder = sandbox.root.appendingPathComponent("AfterFailure")
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let recorder = FileOpsRecorder()
        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder)
        }

        // store.exhaustivity = .off: 실패 lifecycle을 모두 열거하지 않고 source별 recorder 결과를 검증한다.
        store.exhaustivity = .off
        await store.send(.routing(.dropItems(
            sourcePaths: [failedSourcePath],
            destinationPath: destinationFolder.path,
            isOptionDrag: false,
        )))
        await store.finish()
        await store.skipReceivedActions()

        await store.send(.routing(.dropItems(
            sourcePaths: [secondSource.path],
            destinationPath: destinationFolder.path,
            isOptionDrag: false,
        )))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertNotNil(store.state.itemStates[failedSourcePath]?.lastError)
        XCTAssertEqual(recorder.movedPaths.map(\.source.path), [secondSource.path])
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondSource.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationFolder.appendingPathComponent("11.txt").path))
    }

    // MARK: - EOP-002-import_external_objects

    /// EOP-002-import_external_objects: 받아들인 외부 drop 요청은 종단 획득 이벤트를 낸다.
    /// accept 시점에 시작된 획득 세션은 receiver 콜백이 staging에 파일을 산출하면
    /// `.succeeded` 종단 이벤트를 emit해야 한다. (RED: 이 계약이 아직 모델링되지 않음)
    /// - 검증 내용: begin → staging에 파일 수신 → events 스트림이 `.succeeded`를 포함한다.
    /// - 사전 조건: 1개 receiver가 file.txt를 promise하고 staging 콜백이 성공을 보고한다.
    /// - 기대 결과: events가 `.succeeded(sessionID)` 종단 이벤트를 산출한다.
    func testExternalDropAcquisition_beginEmitsSucceededTerminalEvent() async throws {
        let fixture = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { fixture.cleanup() }
        let temporaryRoot = fixture.root.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)

        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))
        let receiver = FilePromiseReceiverSpy(names: ["file.txt"])

        let request = client.begin([receiver], [], "/dest", false, [])
        let stagingURL = URL(fileURLWithPath: request.stagingDirectory)
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        let stagedURL = stagingURL.appendingPathComponent("file.txt")
        try FileManager.default.copyItem(at: fixture.fileURL, to: stagedURL)
        receiver.invokeReader(url: stagedURL, error: nil)

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))

        // 수신 파일 1건의 `.received` 후 종단 `.succeeded` 이벤트가 온다 (stream은 종단 후 finish).
        XCTAssertEqual(events.last, .succeeded(request.sessionID))
    }

    /// EOP-002-import_external_objects (VOY-736 후속): provider가 receivePromisedFiles 도중
    /// reader를 동기적으로 호출해 콜백이 cardinality 확정보다 먼저 도착해도 세션이 성공한다.
    /// - 검증 내용: 동기 콜백이 받은 수를 채운 뒤 cardinality 확정 후 성공이 재평가된다.
    /// - 사전 조건: 이름이 확정된 receiver가 receive 중 동기적으로 첫 파일을 보고한다.
    /// - 기대 결과: `.succeeded` 종단 이벤트가 온다(스트림이 열린 채 남지 않는다).
    func testExternalDropAcquisition_synchronousCallbackBeforeFinalizeStillSucceeds() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("SyncBeforeFinalize")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let receiver = FilePromiseReceiverSpy(names: ["sync.eml"])
        receiver.deliverSynchronously = true
        let request = client.begin([receiver], [], "/dest", false, [])

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .succeeded(request.sessionID))
    }

    func testExternalDropAcquisition_synchronousEmptyFileNamesCallbackFailsAfterFinalize() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("SyncEmptyNamesBeforeFinalize")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let receiver = FilePromiseReceiverSpy(names: [])
        receiver.deliverSynchronously = true
        receiver.synchronousFilename = "message.eml"
        let request = client.begin([receiver], [], "/dest", false, [])

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .failed(request.sessionID, .emptyCardinality))
    }

    // MARK: - EOP-002-import_external_objects (universal data-flavor materialization)

    /// 검증 내용: data-flavor item의 바이트가 staging에 그대로(변환 없이) 쓰이고 UTI 기반 이름을 갖는다.
    /// 사전 조건: JSON UTI(public.json) data flavor를 begin으로 물리화한다.
    /// 기대 결과: staged 파일 이름이 `Clipping 1.json`이고 내용이 입력 바이트와 byte-for-byte 일치한다.
    func testExternalDropMaterialization_writesExactBytesWithUTIName() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("DataBytes")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let bytes = Data(#"{"k":"v","n":1}"#.utf8)
        let flavor = ExternalDropDataFlavor(uti: "public.json", bytes: bytes, filename: "Clipping 1.json")
        let request = client.begin([], [flavor], "/dest", false, [])

        let stagedURL = URL(fileURLWithPath: request.stagingDirectory).appendingPathComponent("Clipping 1.json")
        XCTAssertEqual(try Data(contentsOf: stagedURL), bytes)

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .succeeded(request.sessionID))
    }

    /// 검증 내용: text 계열 data flavor는 첫 줄을 정리한 base name을 사용한다.
    /// 사전 조건: public.utf8-plain-text data flavor가 여러 줄 텍스트를 담는다.
    /// 기대 결과: staged 파일 이름이 첫 줄(정리·길이 제한) 기반 `Quarterly Report.txt`가 된다.
    func testExternalDropMaterialization_textFlavorUsesFirstLineBaseName() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("DataTextName")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let flavor = ExternalDropDataFlavor(
            uti: "public.utf8-plain-text",
            bytes: Data("Quarterly Report\nrevenue up\n".utf8),
            filename: "Quarterly Report.txt",
        )
        let request = client.begin([], [flavor], "/dest", false, [])

        let stagedURL = URL(fileURLWithPath: request.stagingDirectory)
            .appendingPathComponent("Quarterly Report.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedURL.path))
        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .succeeded(request.sessionID))
    }

    /// 검증 내용: 동적 UTI처럼 preferred extension이 없는 경우 fallback 확장자를 쓴다.
    /// 사전 조건: `dyn.` 동적 UTI data flavor.
    /// 기대 결과: staged 파일 이름이 base name + 기본 확장자(`.data`)가 된다.
    func testExternalDropMaterialization_fallbackExtensionForDynamicUTI() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("DataFallbackExt")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let flavor = ExternalDropDataFlavor(
            uti: "dyn.a8f9b1c2d3e4f5a6b7c8d9e0",
            bytes: Data("raw".utf8),
            filename: "Clipping 1.data",
        )
        let request = client.begin([], [flavor], "/dest", false, [])

        let stagedURL = URL(fileURLWithPath: request.stagingDirectory)
            .appendingPathComponent("Clipping 1.data")
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedURL.path))
        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .succeeded(request.sessionID))
    }

    // MARK: - EOP-002-import_external_objects (extension supertype walk)

    /// 검증 내용: 같은 파일명을 가진 두 data flavor가 staging에서 서로 덮어쓰지 않고 고유 이름으로 물리화된다.
    /// 사전 조건: 동일한 filename("Clip 1.txt")을 가진 data flavor 2건.
    /// 기대 결과: 첫 flavor는 원래 이름, 둘째는 ` <n>` 접미 이름으로 각각 존재하고 `.received`가 2건이다.
    func testExternalDropMaterialization_sameFilenameDataFlavorsDeduplicate() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("DataDedup")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let flavorA = ExternalDropDataFlavor(
            uti: "public.utf8-plain-text",
            bytes: Data("first".utf8),
            filename: "Clip 1.txt",
        )
        let flavorB = ExternalDropDataFlavor(
            uti: "public.utf8-plain-text",
            bytes: Data("second".utf8),
            filename: "Clip 1.txt",
        )
        let request = client.begin([], [flavorA, flavorB], "/dest", false, [])

        let firstURL = URL(fileURLWithPath: request.stagingDirectory).appendingPathComponent("Clip 1.txt")
        let secondURL = URL(fileURLWithPath: request.stagingDirectory).appendingPathComponent("Clip 1 2.txt")
        XCTAssertEqual(try Data(contentsOf: firstURL), Data("first".utf8))
        XCTAssertEqual(try Data(contentsOf: secondURL), Data("second".utf8))

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        let received = events.filter {
            if case .received = $0 { return true }
            return false
        }
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(events.last, .succeeded(request.sessionID))
    }

    /// 검증 내용: data flavor가 확정된 promise 파일명과 같은 이름을 산출하면 promise 이름을
    /// 피해 다른 이름으로 물리화되고, promise 콜백도 충돌 없이 수용돼 세션이 성공한다.
    /// 사전 조건: fileNames ["Clip 1.txt"] receiver와 동일 filename의 data flavor 1건.
    /// 기대 결과: data는 `Clip 1 2.txt`로 staging에 쓰이고 promise 파일도 received로 등록된다.
    func testExternalDropMaterialization_dataFlavorAvoidsPromisedFilename() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("DataPromiseCollision")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let receiver = FilePromiseReceiverSpy(names: ["Clip 1.txt"])
        let flavor = ExternalDropDataFlavor(
            uti: "public.utf8-plain-text",
            bytes: Data("text".utf8),
            filename: "Clip 1.txt",
        )
        let request = client.begin([receiver], [flavor], "/dest", false, [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)

        // data flavor는 promise 이름을 피해 고유 이름으로 물리화된다.
        let dataStaged = staging.appendingPathComponent("Clip 1 2.txt")
        XCTAssertEqual(try Data(contentsOf: dataStaged), Data("text".utf8))

        // provider가 promise 파일을 쓰고 콜백을 보고한다 (data와 경로가 다르므로 충돌 없음).
        let promised = staging.appendingPathComponent("Clip 1.txt")
        try Data("promise".utf8).write(to: promised)
        receiver.invokeReader(url: promised, error: nil)

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        let received = events.compactMap { event -> ExternalDropReceivedFile? in
            guard case let .received(file) = event else { return nil }
            return file
        }
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(events.last, .succeeded(request.sessionID))
    }

    /// 검증 내용: preferredFilenameExtension이 없는 pasteboard 전용 UTI도 supertype 계층에서 확장자를 유도한다.
    /// 사전 조건: `public.utf8-plain-text`는 직접 확장자가 없지만 `public.plain-text`(txt)를 조상으로 갖는다.
    /// 기대 결과: `fileExtension(for:)`가 "txt"를 반환하고 `filename`이 `.txt` 확장자를 갖는다.
    func testExternalDropFileExtension_utf8PlainTextWalksSupertypeToTxt() {
        XCTAssertEqual(ExternalDropDataFlavorNaming.fileExtension(for: "public.utf8-plain-text"), "txt")
        let name = ExternalDropDataFlavorNaming.filename(
            uti: "public.utf8-plain-text",
            bytes: Data("Cell value".utf8),
            ordinal: 1,
        )
        XCTAssertEqual(name, "Cell value.txt")
    }

    /// 검증 내용: TSV 계열 UTI가 supertype 계층에서 탭-구분 확장자를 유도한다.
    /// 사전 조건: `public.utf8-tab-separated-values-text`의 조상 중 `public.tab-separated-values-text`가 tsv를 선언한다.
    /// 기대 결과: `fileExtension(for:)`가 "tsv"를 반환한다.
    func testExternalDropFileExtension_tsvWalksSupertypeToTsv() {
        XCTAssertEqual(
            ExternalDropDataFlavorNaming.fileExtension(for: "public.utf8-tab-separated-values-text"),
            "tsv",
        )
    }

    /// 검증 내용: 조상이 전혀 없는(미등록/사유) UTI는 기존 data fallback을 유지한다.
    /// 사전 조건: `com.apple.iWork.TSPNativeData`는 이 환경에서 미등록 동적 UTI다.
    /// 기대 결과: `fileExtension(for:)`가 `defaultExtension`("data")를 반환한다.
    func testExternalDropFileExtension_unknownUTIFallsBackToData() {
        XCTAssertEqual(
            ExternalDropDataFlavorNaming.fileExtension(for: "com.apple.iWork.TSPNativeData"),
            ExternalDropDataFlavorNaming.defaultExtension,
        )
    }

    /// 검증 내용 (VOY-736 리뷰 #3830824367): 결합 이모지처럼 바이트가 큰 문자열도
    /// 파일시스템 component 한도(APFS 255 UTF-8 bytes) 안으로 잘린다.
    /// 사전 조건: ZWJ 이모지 200개 제목의 Mail 메시지와 텍스트 첫 줄.
    /// 기대 결과: 두 생성 파일명 모두 255 bytes 이하다.
    func testExternalDropNamingTruncatesByFilesystemBytes() {
        let emojiText = String(repeating: "👨‍👩‍👧‍👦", count: 200)

        var usedFilenames = Set<String>()
        let mailName = ExternalDropDataFlavorNaming.mailMessageFilename(
            subject: emojiText,
            ordinal: 1,
            usedFilenames: &usedFilenames,
        )
        XCTAssertLessThanOrEqual(mailName.utf8.count, 255)

        let textName = ExternalDropDataFlavorNaming.filename(
            uti: "public.utf8-plain-text",
            bytes: Data(emojiText.utf8),
            ordinal: 1,
        )
        XCTAssertLessThanOrEqual(textName.utf8.count, 255)
    }

    /// 검증 내용: promise receiver와 data flavor가 섞인 drag가 둘 다 물리화되고 all-promises 배리어가 성립한다.
    /// 사전 조건: [data flavor, promise receiver]를 하나의 세션으로 begin한다.
    /// 기대 결과: data 파일과 promise 파일이 모두 staged되고 `.succeeded` 종단이 온다.
    func testExternalDropMaterialization_mixedPromiseAndDataBarrierHolds() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("DataMixed")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let receiver = FilePromiseReceiverSpy(names: ["promise.txt"])
        let flavor = ExternalDropDataFlavor(
            uti: "public.json",
            bytes: Data(#"{"k":1}"#.utf8),
            filename: "Clipping 1.json",
        )
        let request = client.begin([receiver], [flavor], "/dest", false, [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        let stagedData = staging.appendingPathComponent("Clipping 1.json")
        let stagedPromise = staging.appendingPathComponent("promise.txt")
        let claimedPromise = claimedContainer(staging).appendingPathComponent("promise.txt")
        try Data("promise".utf8).write(to: stagedPromise)
        receiver.invokeReader(url: stagedPromise, error: nil)

        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedData.path))
        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        let received = events.compactMap { event -> ExternalDropReceivedFile? in
            guard case let .received(file) = event else { return nil }
            return file
        }
        XCTAssertEqual(received.map(\.stagedPath), [stagedData.path, claimedPromise.path])
        XCTAssertEqual(events.last, .succeeded(request.sessionID))
    }

    /// 검증 내용: 레거시 폴백 beginLegacy가 staging에 이미 물리화된 파일들을 received-item으로 등록하고
    /// cardinality만큼 모두 등록되면 `.succeeded`를 emit한다.
    /// 사전 조건: staging에 존재하는 파일 2개 경로를 beginLegacy로 넘긴다.
    /// 기대 결과: `.received` 2건 후 `.succeeded(sessionID)` 종단 이벤트가 온다.
    func testExternalDropAcquisition_beginLegacyRegistersStagedFilesAndSucceeds() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("LegacyStaged")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let stagingDir = temporaryRoot.appendingPathComponent("ExternalDrop-LegacyFixture")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let firstURL = stagingDir.appendingPathComponent("a.eml")
        let secondURL = stagingDir.appendingPathComponent("b.eml")
        try Data("a".utf8).write(to: firstURL)
        try Data("b".utf8).write(to: secondURL)

        let request = client.beginLegacy([firstURL.path, secondURL.path], stagingDir.path, "/dest", true)

        XCTAssertEqual(request.stagingDirectory, stagingDir.path)
        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        let received = events.compactMap { event -> String? in
            guard case let .received(file) = event else { return nil }
            return file.stagedPath
        }
        XCTAssertEqual(Set(received), Set([firstURL.path, secondURL.path]))
        XCTAssertEqual(events.last, .succeeded(request.sessionID))
    }

    /// 검증 내용: beginLegacy에 staging 밖 경로를 넘기면 타입화 실패(outsideStaging)로 귀결된다.
    /// 사전 조건: staging 밖에 존재하는 파일 경로를 beginLegacy로 넘긴다.
    /// 기대 결과: `.failed(sessionID, .outsideStaging)` 종단 이벤트가 온다.
    func testExternalDropAcquisition_beginLegacyRejectsOutsideStaging() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("LegacyOutside")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let stagingDir = temporaryRoot.appendingPathComponent("ExternalDrop-LegacyOutside")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let outsideURL = temporaryRoot.appendingPathComponent("outside.eml")
        try Data("x".utf8).write(to: outsideURL)

        let request = client.beginLegacy([outsideURL.path], stagingDir.path, "/dest", true)

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .failed(request.sessionID, .outsideStaging))
    }

    /// EOP-002-import_external_objects: legacy staging 내부 symlink가 가리키는 외부 파일은 거절된다.
    /// legacy 경로의 lexical containment가 실제 symlink 대상까지 staging 안으로 허용하지 않는지 검증한다.
    /// - 검증 내용: staging 내부 symlink를 통한 legacy staged path가 `.outsideStaging`으로 실패한다.
    /// - 사전 조건: staging 내부 symlink가 staging 밖의 실제 파일을 가리킨다.
    /// - 기대 결과: `.failed(sessionID, .outsideStaging)`이 emit되고 외부 파일은 남는다.
    func testExternalDropAcquisition_beginLegacySymlinkOutsideStagingRejects() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("LegacySymlinkOutside")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let stagingDir = temporaryRoot.appendingPathComponent("ExternalDrop-LegacySymlinkOutside")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let outside = temporaryRoot.appendingPathComponent("outside.eml")
        let symlink = stagingDir.appendingPathComponent("escaped.eml")
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outside)

        let request = client.beginLegacy([symlink.path], stagingDir.path, "/dest", true)

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .failed(request.sessionID, .outsideStaging))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    /// EOP-002-import_external_objects (VOY-736 후속): provider cardinality 계약에 따라
    /// receive 이후에도 fileNames가 빈 receiver는 예상 cardinality를 알 수 없어
    /// 성공하지 않고 타입화 실패 `.emptyCardinality`로 종료한다.
    /// - 검증 내용: 빈 fileNames receiver 하나로 세션을 시작하고 staging에 파일을 쓴 뒤
    ///   성공 콜백을 호출해도 `.succeeded`가 오지 않고 `.failed(sessionID, .emptyCardinality)`가 온다.
    /// - 사전 조건: fileNames가 빈 receiver 하나로 세션을 시작한다.
    /// - 기대 결과: `.failed(sessionID, .emptyCardinality)`이 마지막 이벤트로 오고 `.succeeded`는 없다.
    func testExternalDropAcquisition_emptyFileNamesReceiverFailsWithEmptyCardinality() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("EmptyNames")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        // Mail처럼 receiver가 1개지만 fileNames가 비어 있다(기대 콜백 수 미정).
        let receiver = FilePromiseReceiverSpy(names: [])
        let request = client.begin([receiver], [], "/dest", false, [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let staged = staging.appendingPathComponent("message.eml")
        try Data("eml".utf8).write(to: staged)

        receiver.invokeReaderOnQueue(url: staged, error: nil)

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .failed(request.sessionID, .emptyCardinality))
        XCTAssertFalse(events.contains { event in
            if case .succeeded = event { return true }
            return false
        })
        XCTAssertFalse(receiver.readerExecutedOnMainThread ?? true)
    }

    /// EOP-002-import_external_objects (VOY-736 후속): provider cardinality 계약에 따라
    /// receive 이후 fileNames가 채워진 receiver들(결정적)은 예상 cardinality가 확정되고,
    /// 결정적 배리어는 모든 이름 지어진 콜백이 도착해야 완료한다.
    /// - 사전 조건: "a.txt" receiver와 "b.txt" receiver를 함께 begin하고 staging 파일을 쓴다.
    /// - 기대 결과: 한 receiver의 콜백만으로는 종단이 없고, 나머지 receiver 콜백 후 `.succeeded`가 온다.
    func testExternalDropAcquisition_determinateBarrierWaitsForAllNamedCallbacks() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("DeterminateBarrier")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let receiverA = FilePromiseReceiverSpy(names: ["a1.txt", "a2.txt"])
        let receiverB = FilePromiseReceiverSpy(names: ["b.txt"])
        let request = client.begin([receiverA, receiverB], [], "/dest", false, [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let a1 = staging.appendingPathComponent("a1.txt")
        let a2 = staging.appendingPathComponent("a2.txt")
        let b = staging.appendingPathComponent("b.txt")
        try Data("a1".utf8).write(to: a1)
        try Data("a2".utf8).write(to: a2)
        try Data("b".utf8).write(to: b)

        // receiverA의 cardinality만 충족: 아직 성공하면 안 된다(receiverB 미완료).
        receiverA.invokeReader(url: a1, error: nil)
        receiverA.invokeReader(url: a2, error: nil)
        var events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertNil(events.last, "한 receiver의 cardinality만으로 성공하면 안 된다")
        XCTAssertFalse(events.contains { event in
            if case .succeeded = event { return true }
            return false
        })

        // receiverB 콜백: 이제 모든 이름 지어진 기여가 완료돼 성공해야 한다.
        receiverB.invokeReader(url: b, error: nil)
        events = await collectEvents(from: client.events(request.sessionID))
        let received = events.compactMap { event -> ExternalDropReceivedFile? in
            guard case let .received(file) = event else { return nil }
            return file
        }
        XCTAssertEqual(received.count, 3)
        XCTAssertEqual(events.last, .succeeded(request.sessionID))
    }

    func testExternalDropAcquisition_excessCallbacksFailBeforeOtherReceiverCompletes() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("DeterminateOverflow")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let receiverA = FilePromiseReceiverSpy(names: ["a1.txt", "a2.txt"])
        let receiverB = FilePromiseReceiverSpy(names: ["b.txt"])
        let request = client.begin([receiverA, receiverB], [], "/dest", false, [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let a1 = staging.appendingPathComponent("a1.txt")
        let a2 = staging.appendingPathComponent("a2.txt")
        let a3 = staging.appendingPathComponent("a3.txt")
        try Data("a1".utf8).write(to: a1)
        try Data("a2".utf8).write(to: a2)
        try Data("a3".utf8).write(to: a3)

        receiverA.invokeReader(url: a1, error: nil)
        receiverA.invokeReader(url: a2, error: nil)
        receiverA.invokeReader(url: a3, error: nil)

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .failed(request.sessionID, .callbackError))
    }

    /// EOP-002-import_external_objects (VOY-736 후속): receive 이후 fileNames로 예상 cardinality가
    /// 확정된 receiver는 콜백 수가 cardinality에 도달하면 성공한다.
    /// 사전 조건: fileNames 2개 receiver가 staging에 파일 2개를 쓰고 콜백 2회 호출.
    /// 기대 결과: `.received` 2건이 모두 관측되고 `.succeeded`로 끝난다.
    func testExternalDropAcquisition_namedCardinalityMultipleFilesSucceeds() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("NamedMulti")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let receiver = FilePromiseReceiverSpy(names: ["first.eml", "second.eml"])
        let request = client.begin([receiver], [], "/dest", false, [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let first = staging.appendingPathComponent("first.eml")
        let second = staging.appendingPathComponent("second.eml")
        try Data("one".utf8).write(to: first)
        try Data("two".utf8).write(to: second)

        receiver.invokeReader(url: first, error: nil)
        receiver.invokeReader(url: second, error: nil)

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        let received = events.compactMap { event -> ExternalDropReceivedFile? in
            guard case let .received(file) = event else { return nil }
            return file
        }
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(
            received.map(\.stagedPath),
            [
                claimedContainer(staging).appendingPathComponent("first.eml").path,
                claimedContainer(staging).appendingPathComponent("second.eml").path,
            ],
        )
        XCTAssertEqual(events.last, .succeeded(request.sessionID))
    }

    /// EOP-002-import_external_objects (VOY-736 후속): provider cardinality가 확정되면
    /// 콜백 간격은 종료 판정에 무관하다. quiescence 임계값(250ms)을 넘는 간격이어도
    /// 콜백 수가 cardinality에 도달하면 `.succeeded`로 끝난다.
    /// 사전 조건: fileNames 2개 receiver가 staging에 파일 2개를 쓰고 콜백 2회를
    /// 600ms 간격으로 호출(250ms 초과, 1s 이내).
    /// 기대 결과: `.received` 2건이 모두 관측되고 `.succeeded`로 끝난다.
    func testExternalDropAcquisition_callbackTimingIrrelevantOnceCardinalityKnown() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("NamedGap")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let receiver = FilePromiseReceiverSpy(names: ["first.eml", "second.eml"])
        let request = client.begin([receiver], [], "/dest", false, [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let first = staging.appendingPathComponent("first.eml")
        let second = staging.appendingPathComponent("second.eml")
        try Data("one".utf8).write(to: first)
        try Data("two".utf8).write(to: second)

        receiver.invokeReader(url: first, error: nil)
        // cardinality(2)가 이미 확정됐으므로 quiescence를 넘는 간격도 종료 판정에 무관하다.
        try await Task.sleep(nanoseconds: 600_000_000)
        receiver.invokeReader(url: second, error: nil)

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(
            from: client.events(request.sessionID),
            timeoutNanoseconds: 5_000_000_000,
        )
        let received = events.compactMap { event -> ExternalDropReceivedFile? in
            guard case let .received(file) = event else { return nil }
            return file
        }
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(
            received.map(\.stagedPath),
            [
                claimedContainer(staging).appendingPathComponent("first.eml").path,
                claimedContainer(staging).appendingPathComponent("second.eml").path,
            ],
        )
        XCTAssertEqual(events.last, .succeeded(request.sessionID))
    }

    /// EOP-002-import_external_objects: 모든 receiver가 같은 destination(staging)을 사용한다.
    /// 여러 receiver는 반드시 동일한 destination location으로 receive를 호출해야 한다.
    /// - 검증 내용: 두 receiver의 `receivedDestination`이 같고 begin이 반환한 staging 경로와 일치한다.
    /// - 사전 조건: 2개 receiver를 하나의 세션으로 begin한다.
    /// - 기대 결과: 두 receiver 모두 같은 staging 디렉터리를 사용한다.
    func testExternalDropAcquisition_sameDestinationForAllReceivers() throws {
        let temporaryRoot = try makeAcquisitionTempRoot("SameDest")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let receiverA = FilePromiseReceiverSpy(names: ["a.txt"])
        let receiverB = FilePromiseReceiverSpy(names: ["b.txt"])
        let request = client.begin([receiverA, receiverB], [], "/dest", false, [])

        let expected = URL(fileURLWithPath: request.stagingDirectory)
        XCTAssertEqual(receiverA.receivedDestination?.path, expected.path)
        XCTAssertEqual(receiverB.receivedDestination?.path, expected.path)
        XCTAssertEqual(receiverA.receivedDestination?.path, receiverB.receivedDestination?.path)
    }

    /// EOP-002-import_external_objects: receiver 콜백은 non-main OperationQueue에서 실행된다.
    /// main actor를 막지 않도록 콜백이 main queue가 아닌 큐로 전달돼야 한다.
    /// - 검증 내용: receivePromisedFiles에 전달된 operationQueue가 main이 아니다.
    /// - 사전 조건: begin으로 receiver를 시작한다.
    /// - 기대 결과: `receivedOperationQueue != OperationQueue.main`.
    func testExternalDropAcquisition_callbackOnNonMainQueue() throws {
        let temporaryRoot = try makeAcquisitionTempRoot("NonMainQueue")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let receiver = FilePromiseReceiverSpy(names: ["a.txt"])
        _ = client.begin([receiver], [], "/dest", false, [])

        XCTAssertNotNil(receiver.receivedOperationQueue)
        XCTAssertFalse(receiver.receivedOperationQueue === OperationQueue.main)
    }

    /// EOP-002-import_external_objects (VOY-736 회귀): AppKit이 reader 콜백을 non-main
    /// OperationQueue에서 호출해도 세션이 main-thread 콜백과 동일한 종단 상태에 도달한다.
    /// begin은 @MainActor이므로 @Sendable이 없는 콜백 클로저는 MainActor로 추론되어
    /// Swift 6 런타임 executor 검사에서 SIGTRAP했다. 이 테스트는 spy로 실제 큐 경로를
    /// 재현해 크래시 없이 off-main 콜백이 성공함을 검증한다.
    /// - 사전 조건: receiver가 a.txt를 promise하고, staging에 파일을 쓰고, 콜백을 큐에서 호출.
    /// - 기대 결과: events에 `.succeeded` 종단이 오고, reader 콜백이 main이 아닌 스레드에서 실행됐다.
    func testExternalDropAcquisition_callbackFromNonMainQueueReachesTerminal() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("NonMainQueueTerminal")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let receiver = FilePromiseReceiverSpy(names: ["a.txt"])
        let request = client.begin([receiver], [], "/dest", false, [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let staged = staging.appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: staged)

        // 실제 AppKit 경로: 콜백을 non-main OperationQueue에서 실행한다.
        receiver.invokeReaderOnQueue(url: staged, error: nil)

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .succeeded(request.sessionID))
        // 콜백이 확실히 non-main 스레드에서 실행됐음을 보장한다. nil이면 큐 경로가
        // 실행되지 않았으므로 테스트가 실패해 크래시 경로 재현이 누락됨을 드러낸다.
        XCTAssertFalse(receiver.readerExecutedOnMainThread ?? true)
    }

    /// EOP-002-import_external_objects: 한 receiver가 여러 콜백을 산출하면 각각 수신된다.
    /// legacy promise는 한 pasteboard item에 여러 파일을 쓸 수 있다.
    /// - 검증 내용: 2개 파일 이름을 promise한 receiver에 콜백 2회를 호출하면 `.received`가 2건 온다.
    /// - 사전 조건: receiver가 a.txt, b.txt를 promise하고 staging에 두 파일을 모두 쓴다.
    /// - 기대 결과: events에 `.received` 2건 후 `.succeeded`가 온다.
    func testExternalDropAcquisition_multipleCallbacksPerReceiver() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("MultiCallback")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let receiver = FilePromiseReceiverSpy(names: ["a.txt", "b.txt"])
        let request = client.begin([receiver], [], "/dest", false, [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)

        let a = staging.appendingPathComponent("a.txt")
        let b = staging.appendingPathComponent("b.txt")
        try Data("a".utf8).write(to: a)
        try Data("b".utf8).write(to: b)
        receiver.invokeReader(url: a, error: nil)
        receiver.invokeReader(url: b, error: nil)

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        let received = events.compactMap { event -> ExternalDropReceivedFile? in
            guard case let .received(file) = event else { return nil }
            return file
        }
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received.map(\.itemOrdinal), [1, 2])
        XCTAssertEqual(received.map(\.callbackOrdinal), [1, 2])
        XCTAssertEqual(
            received.map(\.stagedPath),
            [
                claimedContainer(staging).appendingPathComponent("a.txt").path,
                claimedContainer(staging).appendingPathComponent("b.txt").path,
            ],
        )
        XCTAssertEqual(events.last, .succeeded(request.sessionID))
    }

    /// EOP-002-import_external_objects: 수신 결과는 순서 보장된 Sendable 값으로 산출된다.
    /// 여러 콜백의 `.received`가 item/callback ordinal과 staged 경로를 순서대로 보존한다.
    /// - 검증 내용: 3회 콜백의 received 순서와 ordinal이 입력 순서와 일치한다.
    /// - 사전 조건: receiver가 3개 파일을 promise하고 순서대로 콜백한다.
    /// - 기대 결과: ordinal 1,2,3이 입력 순서와 일치하고 stagedPath가 staging 안이다.
    func testExternalDropAcquisition_orderedSendableResults() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("Ordered")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let receiver = FilePromiseReceiverSpy(names: ["1.txt", "2.txt", "3.txt"])
        let request = client.begin([receiver], [], "/dest", false, [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)

        let urls = (1 ... 3).map { staging.appendingPathComponent("\($0).txt") }
        for url in urls {
            try Data("x".utf8).write(to: url)
        }
        for url in urls {
            receiver.invokeReader(url: url, error: nil)
        }

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        let received = events.compactMap { event -> ExternalDropReceivedFile? in
            guard case let .received(file) = event else { return nil }
            return file
        }
        XCTAssertEqual(received.map(\.itemOrdinal), [1, 2, 3])
        XCTAssertEqual(received.map(\.callbackOrdinal), [1, 2, 3])
        XCTAssertEqual(
            received.map(\.stagedPath),
            urls.map { claimedContainer(staging).appendingPathComponent("\($0.lastPathComponent)").path },
        )
        XCTAssertTrue(received.allSatisfy { $0.stagedPath.hasPrefix(claimedContainer(staging).path) })
    }

    /// EOP-002-import_external_objects: cardinality를 알 수 없는 receiver의 취소 재조정은
    /// 파일을 받았더라도 부분 수신을 성공으로 확정하지 않는다.
    /// - 검증 내용: callback URL 대신 staging의 유일한 미등록 파일을 찾더라도 실패한다.
    /// - 사전 조건: receiver가 파일을 staging에 쓴 뒤 외부의 존재하지 않는 URL과 취소 오류를 보고한다.
    /// - 기대 결과: `.received` 후 `.failed(.indeterminateCardinality)`가 emit된다.
    func testExternalDropAcquisition_callbackErrorWithStagedFileFailsClosed() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("CallbackError")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let receiver = FilePromiseReceiverSpy(names: [])
        let request = client.begin([receiver], [], "/dest", false, [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        let message = staging.appendingPathComponent("message.eml")
        try Data("message".utf8).write(to: message)
        receiver.invokeReader(
            url: URL(fileURLWithPath: "/message.eml"),
            error: NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.userCancelled.rawValue),
        )

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        let received = events.compactMap { event -> ExternalDropReceivedFile? in
            guard case let .received(file) = event else { return nil }
            return file
        }
        XCTAssertEqual(received.map { URL(fileURLWithPath: $0.stagedPath).lastPathComponent }, ["message.eml"])
        XCTAssertEqual(events.last, .failed(request.sessionID, .indeterminateCardinality))
    }

    /// EOP-002-import_external_objects: callback 시점에 확보한 staging identity는 이후 provider가
    /// 원래 경로를 symlink로 바꿔도 placement에서 외부 파일을 읽지 않는다.
    func testExternalDropAcquisition_claimsCallbackFileBeforePlacement() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("ClaimedCallbackFile")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let receiver = FilePromiseReceiverSpy(names: ["message.eml"])
        let request = client.begin([receiver], [], "/dest", false, [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        let source = staging.appendingPathComponent("message.eml")
        let outside = temporaryRoot.appendingPathComponent("outside.eml")
        try Data("safe".utf8).write(to: source)
        try Data("outside".utf8).write(to: outside)

        receiver.invokeReader(url: source)

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        let received = events.compactMap { event -> ExternalDropReceivedFile? in
            guard case let .received(file) = event else { return nil }
            return file
        }
        XCTAssertEqual(events.last, .succeeded(request.sessionID))
        XCTAssertEqual(received.count, 1)
        XCTAssertNotEqual(received[0].stagedPath, source.path)
        // claimed 파일은 provider에 전달된 staging root 밖 보관 디렉터리에 있어야 한다.
        XCTAssertFalse(received[0].stagedPath.hasPrefix(request.stagingDirectory))

        try FileManager.default.createSymbolicLink(at: source, withDestinationURL: outside)

        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: received[0].stagedPath)), Data("safe".utf8))
    }

    /// EOP-002-import_external_objects: mixed drop의 indeterminate receiver는 이름 있는 receiver가
    /// 남아 있어도 파일별 취소 callback을 receiver 완료로 확정하지 않는다.
    /// - 검증 내용: 미정 수신기 재조정은 부분 수신 성공이 아닌 indeterminate cardinality 실패가 된다.
    /// - 사전 조건: 빈 fileNames receiver와 "a.txt" receiver를 함께 begin한다.
    /// - 기대 결과: 첫 미정 재조정 callback 후 `.failed(.indeterminateCardinality)`가 온다.
    func testExternalDropAcquisition_mixedReceiverIndeterminateCallbackFailsClosed() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("MixedBarrier")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let emptyReceiver = FilePromiseReceiverSpy(names: [])
        let namedReceiver = FilePromiseReceiverSpy(names: ["a.txt"])
        let request = client.begin([emptyReceiver, namedReceiver], [], "/dest", false, [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        let message = staging.appendingPathComponent("message.eml")
        try Data("message".utf8).write(to: message)

        // 미정 receiver가 userCancelled + staged file을 보고하지만 receiver-level 완료는 알 수 없다.
        emptyReceiver.invokeReader(
            url: URL(fileURLWithPath: "/message.eml"),
            error: NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.userCancelled.rawValue),
        )

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .failed(request.sessionID, .indeterminateCardinality))
    }

    /// EOP-002-import_external_objects: 미정 receiver가 실제 오류와 staged URL을 함께 보고하면 성공으로 승격하지 않는다.
    /// - 검증 내용: staged 파일이 함께 와도 user-cancelled가 아닌 오류는 `.callbackError`로 종단한다.
    /// - 사전 조건: fileNames가 빈 receiver가 staging 파일과 provider 오류를 함께 보고한다.
    /// - 기대 결과: 파일은 `.received`로 기록되지만 세션은 실패하고 staging이 정리된다.
    func testExternalDropAcquisition_nonCancelledErrorWithStagedFileFails() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("ProviderCallbackError")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let receiver = FilePromiseReceiverSpy(names: [])
        let request = client.begin([receiver], [], "/dest", false, [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        let message = staging.appendingPathComponent("message.eml")
        try Data("message".utf8).write(to: message)
        receiver.invokeReader(
            url: message,
            error: NSError(domain: "ExternalProvider", code: 1),
        )

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        let received = events.compactMap { event -> ExternalDropReceivedFile? in
            guard case let .received(file) = event else { return nil }
            return file
        }
        XCTAssertEqual(
            received.map(\.stagedPath),
            [claimedContainer(staging).appendingPathComponent("message.eml").path],
        )
        XCTAssertEqual(events.last, .failed(request.sessionID, .callbackError))
        XCTAssertFalse(FileManager.default.fileExists(atPath: message.path))
    }

    /// EOP-002-import_external_objects (VOY-736 회귀): source가 취소 콜백을 먼저 보낸 뒤
    /// promise 파일을 staging에 써도 receiver cardinality를 알 수 없으면 성공하지 않는다.
    /// - 사전 조건: fileNames가 빈 receiver가 취소 오류를 보고한 다음 staging에 파일을 쓴다.
    /// - 기대 결과: 뒤늦게 생성된 source-owned 파일을 `.received`로 받고
    ///   `.failed(.indeterminateCardinality)`로 종단한다.
    func testExternalDropAcquisition_callbackErrorBeforeStagedFileFailsClosed() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("DelayedCallbackError")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let receiver = FilePromiseReceiverSpy(names: [])
        let request = client.begin([receiver], [], "/dest", false, [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        receiver.invokeReader(
            url: URL(fileURLWithPath: "/message.eml"),
            error: NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.userCancelled.rawValue),
        )

        let message = staging.appendingPathComponent("message.eml")
        try Data("message".utf8).write(to: message, options: .atomic)

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        let received = events.compactMap { event -> ExternalDropReceivedFile? in
            guard case let .received(file) = event else { return nil }
            return file
        }
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(events.last, .failed(request.sessionID, .indeterminateCardinality))
    }

    /// EOP-002-import_external_objects: 수신기 취소를 잔여 데이터 성공으로 강등하지 않는다.
    /// source-owned promise가 파일을 쓰지 못했으면 텍스트 플레이버가 수신기 기여를 대신할 수 없다.
    /// - 검증 내용: 데이터가 먼저 물리화돼도 수신기 취소가 `.callbackError` 실패로 끝난다.
    /// - 사전 조건: fileNames 빈(미정) 수신기 1개 + 데이터 플레이버 1개를 begin하고 취소 오류 콜백을 보고한다.
    /// - 기대 결과: `.failed(sessionID, .callbackError)`가 emit되고, 실패 후 staging(데이터 파일 포함)이 정리된다.
    func testExternalDropAcquisition_cancelledReceiverDoesNotDegradeToData() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("CancelDataFallback")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let receiver = FilePromiseReceiverSpy(names: [])
        let flavor = ExternalDropDataFlavor(
            uti: "public.utf8-plain-text",
            bytes: Data("Fwd: hello".utf8),
            filename: "Fwd hello.txt",
        )
        let request = client.begin([receiver], [flavor], "/dest", false, [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        let dataURL = staging.appendingPathComponent("Fwd hello.txt")

        receiver.invokeReader(
            url: dataURL,
            error: NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.userCancelled.rawValue),
        )

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        let received = events.compactMap { event -> ExternalDropReceivedFile? in
            guard case let .received(file) = event else { return nil }
            return file
        }
        XCTAssertEqual(received.count, 1, "데이터 플레이버 자체는 물리화돼야 한다")
        XCTAssertEqual(events.last, .failed(request.sessionID, .callbackError))
        // 코멘트 #3794881389: 실패 종단 후 staging은 반드시 제거되어 민감한 부분 수신 파일이 남지 않는다.
        XCTAssertFalse(FileManager.default.fileExists(atPath: dataURL.path))
    }

    /// EOP-002-import_external_objects: 여러 파일 promise가 일부만 쓴 뒤 오류 나도 세션은 종단한다.
    /// callback 오류는 추가 파일이 오지 않음을 뜻하므로 불완전 cardinality를 pending으로 남기지 않는다.
    /// - 검증 내용: 두 파일 중 하나만 staging에 쓰고 취소하면 수신 후 실패 종단 이벤트가 난다.
    /// - 사전 조건: 결정적 파일명 2개를 가진 receiver가 첫 파일과 취소 오류를 함께 보고한다.
    /// - 기대 결과: 첫 파일 `.received` 후 `.failed(sessionID, .callbackError)`가 emit된다.
    func testExternalDropAcquisition_callbackErrorWithPartialDeterminateOutputFails() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("PartialCallbackError")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let receiver = FilePromiseReceiverSpy(names: ["a.txt", "b.txt"])
        let request = client.begin([receiver], [], "/dest", false, [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        let a = staging.appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: a)

        receiver.invokeReader(
            url: a,
            error: NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.userCancelled.rawValue),
        )

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertEqual(events.compactMap { event -> ExternalDropReceivedFile? in
            guard case let .received(file) = event else { return nil }
            return file
        }.map(\.stagedPath), [claimedContainer(staging).appendingPathComponent("a.txt").path])
        XCTAssertEqual(events.last, .failed(request.sessionID, .callbackError))
    }

    /// EOP-002-import_external_objects: 결정적 receiver의 마지막 콜백이 URL과 error를 함께
    /// 전달하면 성공으로 승격하지 않고 `.callbackError`로 종단한다. cardinality 충족 시
    /// registerReceivedFile이 먼저 `.succeeded`를 내고 뒤의 error 검사가 무시되던 순서 버그
    /// (코멘트 #3826514658)를 재현한다.
    /// - 사전 조건: 단일 파일 결정적 receiver가 staging 파일과 취소 오류를 함께 보고한다.
    /// - 기대 결과: `.received` 후 `.failed(sessionID, .callbackError)`가 emit된다.
    func testExternalDropAcquisition_callbackErrorWithCompletingDeterminateOutputFails() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("CompletingCallbackError")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let receiver = FilePromiseReceiverSpy(names: ["a.txt"])
        let request = client.begin([receiver], [], "/dest", false, [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        let a = staging.appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: a)

        receiver.invokeReader(
            url: a,
            error: NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.userCancelled.rawValue),
        )

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        let received = events.compactMap { event -> ExternalDropReceivedFile? in
            guard case let .received(file) = event else { return nil }
            return file
        }
        XCTAssertEqual(
            received.map(\.stagedPath),
            [claimedContainer(URL(fileURLWithPath: request.stagingDirectory)).appendingPathComponent("a.txt").path],
        )
        XCTAssertEqual(events.last, .failed(request.sessionID, .callbackError))
    }

    /// EOP-002-import_external_objects: staging에 파일이 없으면 `.fileAbsent`로 거절된다.
    /// 콜백이 보고한 URL의 파일이 실제로 존재하지 않으면 성공으로 승격하지 않는다.
    /// - 검증 내용: 존재하지 않는 경로를 콜백하면 `.failed(.fileAbsent)`가 온다.
    /// - 사전 조건: receiver가 staging 안 경로를 보고하지만 파일이 없다.
    /// - 기대 결과: `.failed(sessionID, .fileAbsent)`가 emit된다.
    func testExternalDropAcquisition_fileAbsentRejects() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("FileAbsent")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let receiver = FilePromiseReceiverSpy(names: ["ghost.txt"])
        let request = client.begin([receiver], [], "/dest", false, [])
        let missing = URL(fileURLWithPath: request.stagingDirectory).appendingPathComponent("ghost.txt")
        receiver.invokeReader(url: missing, error: nil)

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .failed(request.sessionID, .fileAbsent))
    }

    /// EOP-002-import_external_objects: staging 밖 경로는 `.outsideStaging`으로 거절된다.
    /// 세션 staging 디렉터리 밖에 있는 출력은 절대 수용하지 않는다.
    /// - 검증 내용: staging 밖에 존재하는 파일을 콜백하면 `.failed(.outsideStaging)`가 온다.
    /// - 사전 조건: staging 밖 temp root에 파일이 존재하고 이를 콜백이 보고한다.
    /// - 기대 결과: `.failed(sessionID, .outsideStaging)`가 emit된다.
    func testExternalDropAcquisition_outsideStagingRejects() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("OutsideStaging")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let receiver = FilePromiseReceiverSpy(names: ["leak.txt"])
        let request = client.begin([receiver], [], "/dest", false, [])
        let outside = temporaryRoot.appendingPathComponent("leak.txt")
        try Data("leak".utf8).write(to: outside)
        receiver.invokeReader(url: outside, error: nil)

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .failed(request.sessionID, .outsideStaging))
    }

    /// EOP-002-import_external_objects: staging 내부 symlink가 가리키는 외부 파일은 거절된다.
    /// callback URL의 lexical 경로가 staging 하위여도 실제 파일시스템 대상이 staging 밖이면 수용하지 않는다.
    /// - 검증 내용: staging 내부 symlink를 통한 callback이 `.outsideStaging`으로 실패한다.
    /// - 사전 조건: staging 내부 symlink가 staging 밖의 실제 파일을 가리킨다.
    /// - 기대 결과: `.failed(sessionID, .outsideStaging)`이 emit되고 외부 파일은 남는다.
    func testExternalDropAcquisition_symlinkedCallbackOutsideStagingRejects() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("SymlinkCallbackOutside")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let receiver = FilePromiseReceiverSpy(names: ["escaped.txt"])
        let request = client.begin([receiver], [], "/dest", false, [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        let outside = temporaryRoot.appendingPathComponent("outside.txt")
        let symlink = staging.appendingPathComponent("escaped.txt")
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outside)

        receiver.invokeReader(url: symlink, error: nil)

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .failed(request.sessionID, .outsideStaging))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    /// EOP-002-import_external_objects: finish는 멱등하며 추가 이벤트를 내지 않는다.
    /// 정상 종료 후 다시 finish를 호출해도 세션 상태가 변하지 않아야 한다.
    /// - 검증 내용: begin 후 finish를 두 번 호출해도 crash 없이 종료되고 성공 이벤트가 없을 수 있다.
    /// - 사전 조건: receiver가 시작된 세션에 finish를 2회 호출한다.
    /// - 기대 결과: 두 번의 finish가 모두 성공하고 추가 종단 이벤트가 없다.
    func testExternalDropAcquisition_finishIsIdempotent() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("IdempotentFinish")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let receiver = FilePromiseReceiverSpy(names: ["a.txt"])
        let request = client.begin([receiver], [], "/dest", false, [])
        client.finish(request.sessionID)
        client.finish(request.sessionID)

        // finish 후 추가 이벤트가 emit되지 않는다 (세션이 이미 종료됨).
        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertTrue(events.isEmpty)
    }

    /// EOP-002-import_external_objects (F2 P1-2): 성공 종단 후 finish가 staging을 정확히 한 번 제거한다.
    /// 성공 경로에서 `<temp>/ExternalDrop-<uuid>`가 누수되지 않도록 finish가 staging을 정리해야 한다.
    /// - 검증 내용: `.succeeded` 종단 후 staging이 존재하다가, finish 호출 후 제거된다.
    /// - 사전 조건: receiver가 파일을 promise하고 staging에 실제 파일을 써서 성공 종단을 만든다.
    /// - 기대 결과: finish 후 staging 경로가 사라진다.
    func testExternalDropAcquisition_finishRemovesStagingAfterSuccess() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("FinishCleanupSuccess")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let receiver = FilePromiseReceiverSpy(names: ["a.txt"])
        let request = client.begin([receiver], [], "/dest", false, [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        try Data("a".utf8).write(to: staging.appendingPathComponent("a.txt"))
        receiver.invokeReader(url: staging.appendingPathComponent("a.txt"), error: nil)

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .succeeded(request.sessionID))
        // 성공 종단 직후 staging은 복사 대상이므로 아직 존재한다.
        XCTAssertTrue(FileManager.default.fileExists(atPath: request.stagingDirectory))

        client.finish(request.sessionID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: request.stagingDirectory))
    }

    /// EOP-002-import_external_objects (F2 P1-2): finish 후 지연 콜백은 staging을 재삭제하고 이벤트를 내지 않는다.
    /// - 검증 내용: finish 후 늦게 도착한 콜백의 reported output이 삭제되고 추가 이벤트가 없다.
    /// - 사전 조건: 세션을 finish한 뒤 늦은 콜백이 새 파일을 보고한다.
    /// - 기대 결과: finish 후에도 늦은 파일이 재삭제되고 이벤트는 없다.
    func testExternalDropAcquisition_lateCallbackAfterFinishIsCleanedUp() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("LateFinishCallback")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))
        let receiver = FilePromiseReceiverSpy(names: ["a.txt"])
        let request = client.begin([receiver], [], "/dest", false, [])
        client.finish(request.sessionID)

        // finish 후 늦은 콜백이 새 출력을 보고한다.
        let lateURL = URL(fileURLWithPath: request.stagingDirectory).appendingPathComponent("late.txt")
        try FileManager.default.createDirectory(
            at: lateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data("late".utf8).write(to: lateURL)
        receiver.invokeReader(url: lateURL, error: nil)

        XCTAssertFalse(FileManager.default.fileExists(atPath: lateURL.path))
        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertTrue(events.isEmpty)
    }

    func testExternalDropAcquisition_lateCallbackAfterTombstoneIsCleanedUp() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("LateTombstoneCallback")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient.live(
            fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot),
            sessionTombstoneSeconds: 0.01,
        )
        let receiver = FilePromiseReceiverSpy(names: ["a.txt"])
        let request = client.begin([receiver], [], "/dest", false, [])
        client.finish(request.sessionID)
        try await Task.sleep(nanoseconds: 50_000_000)

        let lateURL = URL(fileURLWithPath: request.stagingDirectory).appendingPathComponent("late.txt")
        try FileManager.default.createDirectory(
            at: lateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data("late".utf8).write(to: lateURL)
        receiver.invokeReader(url: lateURL, error: nil)

        XCTAssertFalse(FileManager.default.fileExists(atPath: lateURL.path))
    }

    /// 검증 내용: `.succeeded` emit 후(reducer가 placement 복사를 시작하기 전) 도착한 늦은
    /// 콜백은 staging을 제거하지 않는다. placement가 staging 파일을 읽는 중 삭제되면 복사가
    /// 실패하므로, staging 정리는 finish/cancel의 책임으로 남긴다.
    /// 사전 조건: 이름이 확정된(결정적) receiver가 성공 종단 후 늦은 콜백으로 staging에 새 파일을 쓴다.
    /// 기대 결과: staging 디렉터리가 보존되고 추가 이벤트는 없다.
    func testExternalDropAcquisition_lateCallbackAfterSuccessPreservesStaging() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("LateAfterSuccess")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))
        let receiver = FilePromiseReceiverSpy(names: ["first.eml"])
        let request = client.begin([receiver], [], "/dest", false, [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let first = staging.appendingPathComponent("first.eml")
        try Data("one".utf8).write(to: first)
        receiver.invokeReader(url: first, error: nil)

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .succeeded(request.sessionID))
        XCTAssertTrue(FileManager.default.fileExists(atPath: staging.path))

        // 성공 종단 후 늦은 콜백: staging이 보존돼야 한다.
        let late = staging.appendingPathComponent("late.eml")
        try Data("late".utf8).write(to: late)
        receiver.invokeReader(url: late, error: nil)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(FileManager.default.fileExists(atPath: staging.path), "성공 후 늦은 콜백은 staging을 보존해야 한다")
    }

    /// EOP-002-import_external_objects (F2 P1): 성공 종단 + finish 후 늦은 콜백이 재생성한 staging을 정리한다.
    /// placement 복사가 끝나 `finish()`가 staging을 제거한 뒤에도 provider가 staging 경로에
    /// 파일/디렉터리를 재생성하면 잔류한다. finish 이후 늦은 콜백은 containment-checked 재정리 대상이다.
    /// - 사전 조건: 세션이 성공 종단되고 finish로 staging이 제거된 뒤, 늦은 콜백이 staging에 새 파일을 쓴다.
    /// - 기대 결과: 늦은 파일이 삭제되고 추가 이벤트는 없다.
    func testExternalDropAcquisition_lateCallbackAfterFinishAfterSuccessCleansUp() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("LateFinishAfterSuccess")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))
        let receiver = FilePromiseReceiverSpy(names: ["a.txt"])
        let request = client.begin([receiver], [], "/dest", false, [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let staged = staging.appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: staged)
        receiver.invokeReader(url: staged, error: nil)

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .succeeded(request.sessionID))

        // placement 복사 완료로 finish가 staging을 제거한다.
        client.finish(request.sessionID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))

        // finish 후 늦은 콜백이 staging 경로에 파일/디렉터리를 재생성한다.
        let late = staging.appendingPathComponent("late.txt")
        try FileManager.default.createDirectory(at: late.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("late".utf8).write(to: late)
        receiver.invokeReader(url: late, error: nil)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: late.path),
            "finish 후 늦은 콜백이 재생성한 파일은 정리돼야 한다",
        )
    }

    /// EOP-002-import_external_objects (F2 P1): finish 후 늦은 콜백이 재생성한 staging 루트를 다시 제거한다.
    /// finish로 staging 루트가 제거된 뒤 provider가 staging 경로 자체를 재생성하면 `removeIfPresent`가
    /// isRemoved 플래그 때문에 no-op이 되어 잔류한다. 늦은 콜백이 재생성된 루트 안에서 보고되면
    /// 루트 디렉터리가 다시 제거돼야 한다.
    /// - 사전 조건: 세션이 성공 종단되고 finish로 staging 루트가 제거된 뒤, staging 루트를 재생성하고 늦은 콜백을 보고한다.
    /// - 기대 결과: 늦은 콜백 후 staging 루트 디렉터리가 다시 제거된다.
    func testExternalDropAcquisition_lateCallbackRecreatedStagingRootIsRemovedAgain() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("LateRecreatedRoot")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))
        let receiver = FilePromiseReceiverSpy(names: ["a.txt"])
        let request = client.begin([receiver], [], "/dest", false, [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let staged = staging.appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: staged)
        receiver.invokeReader(url: staged, error: nil)

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .succeeded(request.sessionID))

        // placement 복사 완료로 finish가 staging 루트를 제거한다.
        client.finish(request.sessionID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))

        // finish 후 provider가 staging 루트 디렉터리 자체를 재생성하고 늦은 콜백이 그 안에 파일을 보고한다.
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let late = staging.appendingPathComponent("late.txt")
        try Data("late".utf8).write(to: late)
        receiver.invokeReader(url: late, error: nil)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: staging.path),
            "finish 후 늦은 콜백이 재생성한 staging 루트는 다시 제거돼야 한다",
        )
    }

    /// 검증 내용: `.succeeded` emit 후(placement 시작 전) cancel이 와도 staging을 제거한다.
    /// 성공 종단 직후 finish 호출자가 사라질 수 있으므로 staging 영구 잔류를 막는다.
    /// 사전 조건: 세션이 성공 종단된 직후 cancel을 호출한다.
    /// 기대 결과: staging이 제거되고 `.cancelled` 재-emit은 없다(이미 성공 종단됨).
    func testExternalDropAcquisition_cancelAfterSuccessRemovesStaging() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("CancelAfterSuccess")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))
        let receiver = FilePromiseReceiverSpy(names: ["a.txt"])
        let request = client.begin([receiver], [], "/dest", false, [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let staged = staging.appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: staged)
        receiver.invokeReader(url: staged, error: nil)

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .succeeded(request.sessionID))

        client.cancel(request.sessionID)

        XCTAssertFalse(FileManager.default.fileExists(atPath: request.stagingDirectory))
    }

    /// 검증 내용: 종단된 세션은 tombstone 기간 후 registry에서 회수돼 장시간 실행에서
    /// sessions/queue/bufferedEvents가 무한 증가하지 않는다.
    /// 사전 조건: 짧은 tombstone(0.05s)의 live client로 세션을 성공 종료한다.
    /// 기대 결과: tombstone 경과 후 events 조회가 buffered 이벤트 없이 즉시 종료된다.
    func testExternalDropAcquisition_finishedSessionIsReclaimedAfterTombstone() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("Reclaim")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient.live(
            fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot),
            sessionTombstoneSeconds: 0.05,
        )

        let receiver = FilePromiseReceiverSpy(names: ["a.txt"])
        let request = client.begin([receiver], [], "/dest", false, [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let staged = staging.appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: staged)
        receiver.invokeReader(url: staged, error: nil)

        var events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .succeeded(request.sessionID))

        client.finish(request.sessionID)
        try? await Task.sleep(nanoseconds: 200_000_000)

        events = await collectEvents(from: client.events(request.sessionID))
        XCTAssertTrue(events.isEmpty, "tombstone 경과 후 세션이 회수돼 buffered 이벤트가 없어야 한다")
    }

    /// EOP-002-import_external_objects: cancel은 staging을 즉시 제거하고 `.cancelled`를 낸다.
    /// 취소 시 세션 무효화, 로컬 큐 취소, staging 제거가 일어나야 한다.
    /// - 검증 내용: staging 파일이 제거되고 `.cancelled` 종단 이벤트가 온다.
    /// - 사전 조건: staging에 파일이 존재하는 세션을 cancel한다.
    /// - 기대 결과: staging 경로가 사라지고 `.cancelled(sessionID)`가 emit된다.
    func testExternalDropAcquisition_cancelCleansUpStaging() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("CancelCleanup")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let receiver = FilePromiseReceiverSpy(names: ["a.txt"])
        let request = client.begin([receiver], [], "/dest", false, [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        try Data("a".utf8).write(to: staging.appendingPathComponent("a.txt"))

        client.cancel(request.sessionID)

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .cancelled(request.sessionID))
        XCTAssertFalse(FileManager.default.fileExists(atPath: request.stagingDirectory))
    }

    /// EOP-002-import_external_objects: 취소 후 지연 콜백은 이벤트를 내지 않고 출력을 재삭제한다.
    /// provider-side 취소를 주장하지 않고, 늦게 도착한 출력을 조용히 정리한다.
    /// - 검증 내용: cancel 후 콜백이 오면 추가 이벤트 없이 해당 파일이 삭제된다.
    /// - 사전 조건: 세션을 cancel한 뒤 늦은 콜백이 새 파일을 보고한다.
    /// - 기대 결과: events가 `.cancelled`만이고 늦은 파일이 삭제된다.
    func testExternalDropAcquisition_lateCallbackIsSuppressedAndCleanedUp() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("LateCallback")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let receiver = FilePromiseReceiverSpy(names: ["a.txt"])
        let request = client.begin([receiver], [], "/dest", false, [])
        client.cancel(request.sessionID)

        // 취소 후 늦은 콜백이 새 출력을 보고한다.
        let lateURL = URL(fileURLWithPath: request.stagingDirectory).appendingPathComponent("late.txt")
        try FileManager.default.createDirectory(
            at: lateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data("late".utf8).write(to: lateURL)
        receiver.invokeReader(url: lateURL, error: nil)

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertEqual(events, [.cancelled(request.sessionID)])
        XCTAssertFalse(FileManager.default.fileExists(atPath: lateURL.path))
    }

    /// 검증 내용: 종료 후 staging 밖의 지연 콜백 URL은 containment 검증 없이 삭제되지 않는다.
    /// 사전 조건: 세션을 cancel한 뒤 staging 밖의 소스 파일을 보고하는 늦은 콜백.
    /// 기대 결과: staging 밖 파일은 유지되고 staging만 제거된다.
    func testExternalDropAcquisition_lateCallbackOutsideStagingPreservesSource() throws {
        let temporaryRoot = try makeAcquisitionTempRoot("LateOutsideStaging")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let receiver = FilePromiseReceiverSpy(names: ["a.txt"])
        let request = client.begin([receiver], [], "/dest", false, [])
        client.cancel(request.sessionID)

        // 취소 후 늦은 콜백이 staging 밖의 source 파일을 보고한다.
        let outsideURL = temporaryRoot.appendingPathComponent("source-user-file.txt")
        try Data("precious".utf8).write(to: outsideURL)
        receiver.invokeReader(url: outsideURL, error: nil)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: request.stagingDirectory))
    }

    /// VOY-736: beginDeferred는 load 클로저를 세션 큐에서 실행해 main thread를 차단하지 않고,
    /// 로드가 끝난 뒤에야 `.received`/`.succeeded` 종단 이벤트를 낸다 (Mail 다중 MB source 대응).
    /// - 검증 내용: beginDeferred 반환 즉시 request가 나오고, 로드 완료 후 staging에 verbatim 바이트가 쓰이며 종단 `.succeeded`가 온다.
    /// - 사전 조건: load 클로저가 고정 바이트를 반환하는 deferred flavor 1건.
    /// - 기대 결과: staged 파일이 filename 그대로 생성되고 내용이 byte-for-byte 일치하며 events가 `.succeeded`로 끝난다.
    func testExternalDropAcquisition_beginDeferredMaterializesAndSucceeds() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("DeferredFlavor")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let bytes = Data("Message-ID: <deferred@example.com>\r\n\r\nBody".utf8)
        let flavor = ExternalDropDeferredFlavor(uti: "com.apple.mail.email", filename: "Fwd- hello.eml") {
            bytes
        }

        let request = client.beginDeferred([flavor], "/dest", true)

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .succeeded(request.sessionID))

        let stagedURL = URL(fileURLWithPath: request.stagingDirectory)
            .appendingPathComponent("Fwd- hello.eml")
        XCTAssertEqual(try Data(contentsOf: stagedURL), bytes)
    }

    /// VOY-736: beginDeferred의 load 실패는 타입화된 실패로 종단 처리된다.
    /// - 검증 내용: load가 nil을 반환하면 `.failed(dataMaterializationFailed)` 종단 이벤트만 나온다.
    /// - 사전 조건: nil을 반환하는 deferred flavor 1건.
    /// - 기대 결과: events가 `.failed(sessionID, .dataMaterializationFailed)`로 끝난다.
    func testExternalDropAcquisition_beginDeferredLoadFailureFails() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("DeferredFail")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let flavor = ExternalDropDeferredFlavor(uti: "com.apple.mail.email", filename: "unavailable.eml") {
            nil
        }

        let request = client.beginDeferred([flavor], "/dest", true)

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .failed(request.sessionID, .dataMaterializationFailed))
    }

    // MARK: - EOP-002-import_external_objects (all-promises barrier)

    /// EOP-002-import_external_objects: 받아들인 혼합 요청은 all-promises 성공 전까지 배치를 보류한다.
    /// `.accepted`가 active 세션을 저장하고 상태를 `pending`으로 유지하며, `.received` 이벤트만으로는
    /// 아직 `.applyImport`(placement)를 내지 않는다. (RED: 배리어/종단 상태가 아직 모델링되지 않음)
    /// - 검증 내용: accepted → pending 상태, received 후에도 applyImport 미발생.
    func testExternalDropBarrier_acceptedHoldsPlacementUntilSuccess() async {
        let (store, _) = makeExternalDropBarrierHarness()
        let request = makeMixedAcceptedRequest()
        let file = ExternalDropReceivedFile(
            sessionID: request.sessionID, itemOrdinal: 1, callbackOrdinal: 0, stagedPath: "/staging/a.txt",
        )

        await store.send(.externalDrop(.accepted(request: request))) {
            $0.activeExternalDrop = .init(request: request)
            $0.externalObjectImportStatus = .pending
        }
        await store.send(.externalDrop(.event(.received(file)))) {
            $0.activeExternalDrop?.receivedFiles = [file]
        }
        // exhaustivity(on) 하에서 미수신 applyImport가 emit되면 finish()가 실패한다 → "배치 없음" 증명.
        await store.finish()

        // 아직 pending: 어떤 placement도 시작하지 않는다.
        XCTAssertEqual(store.state.externalObjectImportStatus, .pending)
        XCTAssertEqual(store.state.activeExternalDrop?.sessionID, request.sessionID)
    }

    /// EOP-002-import_external_objects: 하나의 promise 실패가 전체 배치를 막는다.
    /// 어떤 promise가 실패하면 logical pending state를 지우고 client cleanup을 요청하며,
    /// promised/immediate 어느 쪽도 placement를 시작하지 않는다.
    /// - 검증 내용: failed → active 세션 해제, status `.failed`, applyImport 미발생, cancel 1회.
    func testExternalDropBarrier_singleFailureBlocksAllPlacement() async {
        let (store, recorder) = makeExternalDropBarrierHarness()
        let request = makeMixedAcceptedRequest()
        let file = ExternalDropReceivedFile(
            sessionID: request.sessionID, itemOrdinal: 1, callbackOrdinal: 0, stagedPath: "/staging/a.txt",
        )

        await store.send(.externalDrop(.accepted(request: request))) {
            $0.activeExternalDrop = .init(request: request)
            $0.externalObjectImportStatus = .pending
        }
        await store.send(.externalDrop(.event(.received(file)))) {
            $0.activeExternalDrop?.receivedFiles = [file]
        }
        await store.send(.externalDrop(.event(.failed(request.sessionID, .callbackError)))) {
            $0.activeExternalDrop = nil
            $0.externalObjectImportStatus = .failed
        }
        await store.finish()

        XCTAssertEqual(store.state.externalObjectImportStatus, .failed)
        XCTAssertNil(store.state.activeExternalDrop)
        XCTAssertEqual(recorder.cancels.count, 1)
        XCTAssertTrue(recorder.finishes.isEmpty)
    }

    /// EOP-002-import_external_objects: all-promises 성공 시 정확히 한 번의 순서 보장 applyImport를 낸다.
    /// 수신 파일을 item/callback ordinal 순서로 보존하고 destination/order 메타데이터와 함께
    /// 내부 import-placement action으로 emit한다. (Todo 7 이후 placement가 실제 복사를 수행한다)
    /// - 검증 내용: succeeded → active 해제, applyImport 정확히 1회.
    func testExternalDropBarrier_allSuccessEmitsSingleOrderedApplyImport() async {
        let (store, recorder) = makeExternalDropBarrierHarness()
        store.exhaustivity = .off
        let request = makeMixedAcceptedRequest()
        let fileA = ExternalDropReceivedFile(
            sessionID: request.sessionID, itemOrdinal: 1, callbackOrdinal: 0, stagedPath: "/staging/a.txt",
        )
        let fileB = ExternalDropReceivedFile(
            sessionID: request.sessionID, itemOrdinal: 2, callbackOrdinal: 1, stagedPath: "/staging/b.txt",
        )

        await store.send(.externalDrop(.accepted(request: request))) {
            $0.activeExternalDrop = .init(request: request)
            $0.externalObjectImportStatus = .pending
        }
        await store.send(.externalDrop(.event(.received(fileA)))) {
            $0.activeExternalDrop?.receivedFiles = [fileA]
        }
        await store.send(.externalDrop(.event(.received(fileB)))) {
            $0.activeExternalDrop?.receivedFiles = [fileA, fileB]
        }
        await store.send(.externalDrop(.event(.succeeded(request.sessionID)))) {
            $0.activeExternalDrop = nil
        }
        let expectedPlan = ExternalDropImportPlan(
            sessionID: request.sessionID,
            destination: request.destination,
            forcedCopy: request.forcedCopy,
            orderedPromisedNames: request.orderedPromisedNames,
            promisedOrdinals: request.promisedOrdinals,
            receivedFiles: [fileA, fileB],
        )
        await store.receive(\.externalDrop.applyImport, expectedPlan)
        await store.finish()
        await store.skipReceivedActions()

        // Todo 7 placement가 단일 applyImport를 소비해 staging cleanup(finish)을 정확히 한 번 한다.
        XCTAssertEqual(recorder.finishes.count, 1)
        XCTAssertTrue(recorder.cancels.isEmpty)
    }

    /// EOP-002-import_external_objects: stale/다른 세션의 이벤트와 cancel은 no-op이다.
    /// 세션 신선도: 현재 active 세션과 일치하지 않는 이벤트(received/succeeded/failed)와
    /// 다른 세션의 cancelSession은 무시되어 active 세션을 건드리지 않는다.
    /// - 검증 내용: 다른 세션 이벤트 후에도 active 세션/status 유지, cleanup 0회.
    func testExternalDropBarrier_staleAndDuplicateEventsAreNoops() async {
        let (store, recorder) = makeExternalDropBarrierHarness()
        let request = makeMixedAcceptedRequest()
        let otherSession = ExternalDropSessionID(rawValue: "other-session")

        await store.send(.externalDrop(.accepted(request: request))) {
            $0.activeExternalDrop = .init(request: request)
            $0.externalObjectImportStatus = .pending
        }
        await store.send(.externalDrop(.event(.received(ExternalDropReceivedFile(
            sessionID: otherSession, itemOrdinal: 1, callbackOrdinal: 0, stagedPath: "/staging/x.txt",
        )))))
        await store.send(.externalDrop(.event(.succeeded(otherSession))))
        await store.send(.externalDrop(.event(.failed(otherSession, .callbackError))))
        await store.send(.externalDrop(.cancelSession(otherSession)))
        await store.finish()

        XCTAssertEqual(store.state.activeExternalDrop?.sessionID, request.sessionID)
        XCTAssertEqual(store.state.externalObjectImportStatus, .pending)
        XCTAssertTrue(store.state.activeExternalDrop?.receivedFiles.isEmpty ?? true)
        XCTAssertTrue(recorder.cancels.isEmpty)
        XCTAssertTrue(recorder.finishes.isEmpty)
    }

    /// EOP-002-import_external_objects: 정확한 세션의 cancel은 pending을 지우고 cleanup을 정확히 한 번 한다.
    /// 반복 cancel은 멱등이다.
    /// - 검증 내용: cancelSession → active/status 해제, cancel 1회; 반복 cancel → 추가 cleanup 없음.
    func testExternalDropBarrier_exactSessionCancelClearsAndCleansUpOnce() async {
        let (store, recorder) = makeExternalDropBarrierHarness()
        let request = makeMixedAcceptedRequest()

        await store.send(.externalDrop(.accepted(request: request))) {
            $0.activeExternalDrop = .init(request: request)
            $0.externalObjectImportStatus = .pending
        }
        await store.send(.externalDrop(.cancelSession(request.sessionID))) {
            $0.activeExternalDrop = nil
            $0.externalObjectImportStatus = nil
        }
        await store.finish()

        XCTAssertEqual(recorder.cancels.count, 1)
        XCTAssertNil(store.state.activeExternalDrop)

        // 반복 cancel은 멱등: 추가 cleanup 없음.
        await store.send(.externalDrop(.cancelSession(request.sessionID)))
        await store.finish()
        XCTAssertEqual(recorder.cancels.count, 1)
    }

    /// EOP-002-import_external_objects: windowIDChanged가 active 세션을 취소한다.
    /// 라이프사이클 전환 시 정확한 active 세션을 취소하고 pending 상태를 해제한다.
    /// - 검증 내용: windowIDChanged → active 해제, cancel 1회.
    func testExternalDropBarrier_windowIDChangedCancelsActiveSession() async {
        let (store, recorder) = makeExternalDropBarrierHarness()
        let request = makeMixedAcceptedRequest()
        let newWindowID = UUID()

        await store.send(.externalDrop(.accepted(request: request))) {
            $0.activeExternalDrop = .init(request: request)
            $0.externalObjectImportStatus = .pending
        }
        await store.send(.lifecycle(.windowIDChanged(newWindowID))) {
            $0.windowID = newWindowID
            $0.activeExternalDrop = nil
            $0.externalObjectImportStatus = nil
        }
        await store.finish()

        XCTAssertNil(store.state.activeExternalDrop)
        XCTAssertNil(store.state.externalObjectImportStatus)
        XCTAssertEqual(recorder.cancels.count, 1)
    }

    /// EOP-002-import_external_objects: resetForDuplicate가 active 외부 세션을 취소한다.
    /// 코멘트 #3794881400: Lifecycle reducer가 reset으로 activeExternalDrop을 nil로 만들기
    /// 전에 정확한 세션을 취소해 staging cleanup을 보장한다.
    /// - 검증 내용: resetForDuplicate → active 해제, cancel 1회.
    func testExternalDropBarrier_resetForDuplicateCancelsActiveSession() async {
        let recorder = AcquisitionCleanupRecorder()
        let injectedUUID = UUID()
        let store = EntryOperationsTestSupport.makeStore {
            $0.uuid = .constant(injectedUUID)
            $0.externalDropAcquisitionClient = ExternalDropAcquisitionClient(
                begin: { _, _, _, _, _ in fatalError("begin is not used by barrier tests") },
                events: { _ in AsyncStream { $0.finish() } },
                cancel: { recorder.recordCancel($0) },
                finish: { recorder.recordFinish($0) },
                beginLegacy: { _, _, _, _ in fatalError("beginLegacy is not used by barrier tests") },
                prepareLegacyStaging: { _ in fatalError("prepareLegacyStaging not used") },
                finalizeLegacyStaging: { _, _ in fatalError("finalizeLegacyStaging not used") },
            )
        }
        let request = makeMixedAcceptedRequest()
        let newWindowID = UUID()

        await store.send(.externalDrop(.accepted(request: request))) {
            $0.activeExternalDrop = .init(request: request)
            $0.externalObjectImportStatus = .pending
        }
        await store.send(.lifecycle(.resetForDuplicate(windowID: newWindowID))) {
            $0 = .init()
            $0.windowID = newWindowID
            $0.loadingCancellationOwnerID = injectedUUID
            $0.undoOwnerID = injectedUUID
        }
        await store.finish()

        XCTAssertNil(store.state.activeExternalDrop)
        XCTAssertEqual(recorder.cancels.count, 1)
    }

    // MARK: - EOP-002-import_external_objects (placement)

    /// EOP-002-import_external_objects: applyImport가 staged source를 destination으로 복사하고 종합 완료를 낸다.
    /// 획득된 staged 파일을 item/callback ordinal 순서로 `.copy` + `.externalObjectImportItem`으로 복사하고,
    /// 모든 항목이 끝나면 정확히 한 번 종합 완료(importFinished)와 staging cleanup(finish)을 수행한다.
    /// - 검증 내용: source 복사, destination 생성, 원본 보존, undo 기록 없음, finish 1회, status `.applied`.
    func testExternalDropImport_applyImportCopiesAndAggregates() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let staging = sandbox.root.appendingPathComponent("staging")
        let dest = sandbox.root.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let a = staging.appendingPathComponent("a.txt")
        let b = staging.appendingPathComponent("b.txt")
        try Data("a".utf8).write(to: a)
        try Data("b".utf8).write(to: b)

        let recorder = FileOpsRecorder()
        let cleanup = AcquisitionCleanupRecorder()
        let sessionID = ExternalDropSessionID()
        let store = EntryOperationsTestSupport.makeStore {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder)
            $0.externalDropAcquisitionClient = ExternalDropAcquisitionClient(
                begin: { _, _, _, _, _ in fatalError("begin not used") },
                events: { _ in AsyncStream { $0.finish() } },
                cancel: { cleanup.recordCancel($0) },
                finish: { cleanup.recordFinish($0) },
                beginLegacy: { _, _, _, _ in fatalError("beginLegacy not used") },
                prepareLegacyStaging: { _ in fatalError("prepareLegacyStaging not used") },
                finalizeLegacyStaging: { _, _ in fatalError("finalizeLegacyStaging not used") },
            )
        }
        store.exhaustivity = .off

        let plan = ExternalDropImportPlan(
            sessionID: sessionID,
            destination: dest.path,
            forcedCopy: true,
            orderedPromisedNames: ["a.txt", "b.txt"],
            promisedOrdinals: [0, 1],
            receivedFiles: [
                .init(sessionID: sessionID, itemOrdinal: 1, callbackOrdinal: 1, stagedPath: a.path),
                .init(sessionID: sessionID, itemOrdinal: 2, callbackOrdinal: 1, stagedPath: b.path),
            ],
        )

        await store.send(.externalDrop(.applyImport(plan)))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(recorder.copiedPaths.map(\.source.path), [a.path, b.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("a.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("b.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path))
        XCTAssertEqual(store.state.externalObjectImportStatus, .applied)
        XCTAssertTrue(store.state.undoRecords.isEmpty)
        XCTAssertEqual(cleanup.finishes, [sessionID])
        XCTAssertTrue(cleanup.cancels.isEmpty)
    }

    /// EOP-002-import_external_objects (VOY-736 리뷰 #3830970670): 뒤쪽 receiver의 콜백이
    /// 먼저 도착해도 placement는 pasteboard 순서(receiverIndex)를 유지한다.
    /// - 검증 내용: B receiver 이벤트가 A보다 먼저 와도 복사 순서는 [a, b]다.
    func testExternalDropImport_parallelArrivalPreservesDragOrder() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let staging = sandbox.root.appendingPathComponent("staging")
        let dest = sandbox.root.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let a = staging.appendingPathComponent("a.txt")
        let b = staging.appendingPathComponent("b.txt")
        try Data("a".utf8).write(to: a)
        try Data("b".utf8).write(to: b)

        let recorder = FileOpsRecorder()
        let cleanup = AcquisitionCleanupRecorder()
        let sessionID = ExternalDropSessionID()
        let store = EntryOperationsTestSupport.makeStore {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder)
            $0.externalDropAcquisitionClient = ExternalDropAcquisitionClient(
                begin: { _, _, _, _, _ in fatalError("begin not used") },
                events: { _ in AsyncStream { $0.finish() } },
                cancel: { cleanup.recordCancel($0) },
                finish: { cleanup.recordFinish($0) },
                beginLegacy: { _, _, _, _ in fatalError("beginLegacy not used") },
                prepareLegacyStaging: { _ in fatalError("prepareLegacyStaging not used") },
                finalizeLegacyStaging: { _, _ in fatalError("finalizeLegacyStaging not used") },
            )
        }
        store.exhaustivity = .off

        // 도착 순서(itemOrdinal)는 B가 먼저지만 receiverIndex로 A가 먼저 정렬돼야 한다.
        let plan = ExternalDropImportPlan(
            sessionID: sessionID,
            destination: dest.path,
            forcedCopy: true,
            orderedPromisedNames: ["a.txt", "b.txt"],
            promisedOrdinals: [0, 1],
            receivedFiles: [
                .init(sessionID: sessionID, itemOrdinal: 1, callbackOrdinal: 1, stagedPath: b.path, receiverIndex: 1),
                .init(sessionID: sessionID, itemOrdinal: 2, callbackOrdinal: 1, stagedPath: a.path, receiverIndex: 0),
            ],
        )

        await store.send(.externalDrop(.applyImport(plan)))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(recorder.copiedPaths.map(\.source.path), [a.path, b.path])
        XCTAssertEqual(cleanup.finishes, [sessionID])
    }

    /// EOP-002-import_external_objects: mixed drop의 즉시 URL이 staged 복사 배치에 포함된다.
    /// promise와 함께 온 즉시 file URL이 조용히 누락되지 않도록 import plan에 합쳐져야 한다.
    /// - 검증 내용: staged 파일과 즉시 URL이 모두 destination에 복사되고 status가 `.applied`.
    func testExternalDropImport_applyImportIncludesImmediateURLs() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let staging = sandbox.root.appendingPathComponent("staging")
        let dest = sandbox.root.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let a = staging.appendingPathComponent("a.txt")
        let immediate = sandbox.root.appendingPathComponent("immediate.txt")
        try Data("a".utf8).write(to: a)
        try Data("immediate".utf8).write(to: immediate)

        let recorder = FileOpsRecorder()
        let cleanup = AcquisitionCleanupRecorder()
        let sessionID = ExternalDropSessionID()
        let store = EntryOperationsTestSupport.makeStore {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder)
            $0.externalDropAcquisitionClient = ExternalDropAcquisitionClient(
                begin: { _, _, _, _, _ in fatalError("begin not used") },
                events: { _ in AsyncStream { $0.finish() } },
                cancel: { cleanup.recordCancel($0) },
                finish: { cleanup.recordFinish($0) },
                beginLegacy: { _, _, _, _ in fatalError("beginLegacy not used") },
                prepareLegacyStaging: { _ in fatalError("prepareLegacyStaging not used") },
                finalizeLegacyStaging: { _, _ in fatalError("finalizeLegacyStaging not used") },
            )
        }
        store.exhaustivity = .off

        let plan = ExternalDropImportPlan(
            sessionID: sessionID,
            destination: dest.path,
            forcedCopy: true,
            orderedPromisedNames: ["a.txt"],
            promisedOrdinals: [0],
            receivedFiles: [
                .init(sessionID: sessionID, itemOrdinal: 1, callbackOrdinal: 1, stagedPath: a.path),
            ],
            immediateURLPaths: [immediate.path],
        )

        await store.send(.externalDrop(.applyImport(plan)))
        await store.finish()
        await store.skipReceivedActions()
        print(
            "DEBUG after-finish placement=\(String(describing: store.state.externalDropImportPlacement)) status=\(String(describing: store.state.externalObjectImportStatus))",
        )

        XCTAssertEqual(recorder.copiedPaths.map(\.source.path), [a.path, immediate.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("a.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("immediate.txt").path))
        XCTAssertEqual(store.state.externalObjectImportStatus, .applied)
        XCTAssertTrue(store.state.undoRecords.isEmpty)
        XCTAssertEqual(cleanup.finishes, [sessionID])
        XCTAssertTrue(cleanup.cancels.isEmpty)
    }

    /// 검증 내용: 외부 import 성공 결과의 `succeededPaths`에 staging이 아닌 실제 destination 경로가 담긴다.
    /// 사전 조건: staged 파일을 destination에 copy하는 import plan 1건.
    /// 기대 결과: `importFinished` result의 `succeededPaths`가 `dest/a.txt` 경로다.
    func testExternalDropImport_resultSucceededPathsContainDestination() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let staging = sandbox.root.appendingPathComponent("staging")
        let dest = sandbox.root.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let a = staging.appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: a)

        let recorder = FileOpsRecorder()
        let cleanup = AcquisitionCleanupRecorder()
        let sessionID = ExternalDropSessionID()
        let store = EntryOperationsTestSupport.makeStore {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder)
            $0.externalDropAcquisitionClient = ExternalDropAcquisitionClient(
                begin: { _, _, _, _, _ in fatalError("begin not used") },
                events: { _ in AsyncStream { $0.finish() } },
                cancel: { cleanup.recordCancel($0) },
                finish: { cleanup.recordFinish($0) },
                beginLegacy: { _, _, _, _ in fatalError("beginLegacy not used") },
                prepareLegacyStaging: { _ in fatalError("prepareLegacyStaging not used") },
                finalizeLegacyStaging: { _, _ in fatalError("finalizeLegacyStaging not used") },
            )
        }
        store.exhaustivity = .off

        let plan = ExternalDropImportPlan(
            sessionID: sessionID,
            destination: dest.path,
            forcedCopy: true,
            orderedPromisedNames: ["a.txt"],
            promisedOrdinals: [0],
            receivedFiles: [
                .init(sessionID: sessionID, itemOrdinal: 1, callbackOrdinal: 1, stagedPath: a.path),
            ],
        )

        await store.send(.externalDrop(.applyImport(plan)))

        await store.receive(\.externalDrop.importFinished, ExternalDropImportResult(
            sessionID: sessionID,
            succeededPaths: [dest.appendingPathComponent("a.txt").path],
            failedPaths: [],
            status: .applied,
        ))
        await store.finish()

        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("a.txt").path))
    }

    /// 검증 내용: 첫 placement가 진행 중인 동안 도착한 두 번째 applyImport는 첫 placement를
    /// 덮어쓰지 않고, 버려진 두 번째 세션도 staging이 남지 않도록 finish된다.
    /// 사전 조건: 세션 1의 복사가 게이트로 대기 중(placement 진행 중)에 세션 2가 도착한다.
    /// 기대 결과: placement는 세션 1을 유지하고 두 세션 모두 finish가 호출된다.
    func testExternalDropImport_secondPlacementWhileInProgressIsDiscardedAndFinished() async throws {
        final class PasteGate: @unchecked Sendable {
            private let lock = NSLock()
            private var continuations: [CheckedContinuation<Void, Never>] = []
            private var opened = false

            func wait() async {
                await withCheckedContinuation { continuation in
                    lock.lock()
                    if opened {
                        lock.unlock()
                        continuation.resume()
                        return
                    }
                    continuations.append(continuation)
                    lock.unlock()
                }
            }

            func open() {
                lock.lock()
                opened = true
                let pending = continuations
                continuations.removeAll()
                lock.unlock()
                pending.forEach { $0.resume() }
            }
        }

        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let staging = sandbox.root.appendingPathComponent("staging")
        let dest = sandbox.root.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let a = staging.appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: a)

        let recorder = FileOpsRecorder()
        let cleanup = AcquisitionCleanupRecorder()
        let gate = PasteGate()
        var fileOps = makeRecordedFileOpsClient(recorder: recorder)
        let ungatedPaste = fileOps.pasteFile
        fileOps.pasteFile = { sourceURL, destinationURL in
            await gate.wait()
            try await ungatedPaste(sourceURL, destinationURL)
        }
        let firstSession = ExternalDropSessionID()
        let secondSession = ExternalDropSessionID()
        let store = EntryOperationsTestSupport.makeStore {
            $0.entryFileOpsClient = fileOps
            $0.externalDropAcquisitionClient = ExternalDropAcquisitionClient(
                begin: { _, _, _, _, _ in fatalError("begin not used") },
                events: { _ in AsyncStream { $0.finish() } },
                cancel: { cleanup.recordCancel($0) },
                finish: { cleanup.recordFinish($0) },
                beginLegacy: { _, _, _, _ in fatalError("beginLegacy not used") },
                prepareLegacyStaging: { _ in fatalError("prepareLegacyStaging not used") },
                finalizeLegacyStaging: { _, _ in fatalError("finalizeLegacyStaging not used") },
            )
        }
        store.exhaustivity = .off

        func makePlan(sessionID: ExternalDropSessionID) -> ExternalDropImportPlan {
            ExternalDropImportPlan(
                sessionID: sessionID,
                destination: dest.path,
                forcedCopy: true,
                orderedPromisedNames: ["a.txt"],
                promisedOrdinals: [0],
                receivedFiles: [
                    .init(sessionID: sessionID, itemOrdinal: 1, callbackOrdinal: 1, stagedPath: a.path),
                ],
            )
        }

        await store.send(.externalDrop(.applyImport(makePlan(sessionID: firstSession))))
        XCTAssertEqual(store.state.externalDropImportPlacement?.sessionID, firstSession)

        // 세션 1의 복사가 게이트로 대기 중(placement 진행 중)에 세션 2가 도착한다.
        await store.send(.externalDrop(.applyImport(makePlan(sessionID: secondSession))))
        XCTAssertEqual(
            store.state.externalDropImportPlacement?.sessionID,
            firstSession,
            "진행 중 placement를 새 세션이 덮어쓰면 안 된다",
        )

        gate.open()
        await store.finish()

        XCTAssertEqual(Set(cleanup.finishes), Set([firstSession, secondSession]))
        XCTAssertTrue(cleanup.cancels.isEmpty)
    }

    /// EOP-002-import_external_objects (F2 P1): resetForDuplicate가 진행 중 placement 복사 effect를 취소한다.
    /// placement(.externalObjectImportItem) 복사 effect는 세션별 CancelID로 등록돼야 reset이 복사를
    /// 중단시킨다. 복사가 pasteFile gate에서 대기 중일 때 reset되면 취소로 gate가 풀리고,
    /// 남은 항목이 destination으로 복사되지 않는다.
    /// - 사전 조건: 복사가 gate에서 대기 중인 placement를 resetForDuplicate로 리셋한다.
    /// - 기대 결과: 복사 effect가 취소돼 어떤 파일도 destination으로 복사되지 않는다.
    func testExternalDropImport_resetForDuplicateCancelsPlacementCopy() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let staging = sandbox.root.appendingPathComponent("staging")
        let dest = sandbox.root.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let a = staging.appendingPathComponent("a.txt")
        let b = staging.appendingPathComponent("b.txt")
        try Data("a".utf8).write(to: a)
        try Data("b".utf8).write(to: b)

        let recorder = FileOpsRecorder()
        let cleanup = AcquisitionCleanupRecorder()
        let gate = PasteCancellationGate()
        var fileOps = makeRecordedFileOpsClient(recorder: recorder)
        let ungatedPaste = fileOps.pasteFile
        fileOps.pasteFile = { sourceURL, destinationURL in
            try await withTaskCancellationHandler {
                await gate.wait()
                try Task.checkCancellation()
            } onCancel: {
                gate.open()
            }
            try await ungatedPaste(sourceURL, destinationURL)
        }
        let sessionID = ExternalDropSessionID()
        let store = EntryOperationsTestSupport.makeStore {
            $0.uuid = .constant(UUID())
            $0.entryFileOpsClient = fileOps
            $0.externalDropAcquisitionClient = ExternalDropAcquisitionClient(
                begin: { _, _, _, _, _ in fatalError("begin not used") },
                events: { _ in AsyncStream { $0.finish() } },
                cancel: { cleanup.recordCancel($0) },
                finish: { cleanup.recordFinish($0) },
                beginLegacy: { _, _, _, _ in fatalError("beginLegacy not used") },
                prepareLegacyStaging: { _ in fatalError("prepareLegacyStaging not used") },
                finalizeLegacyStaging: { _, _ in fatalError("finalizeLegacyStaging not used") },
            )
        }
        store.exhaustivity = .off

        let plan = ExternalDropImportPlan(
            sessionID: sessionID,
            destination: dest.path,
            forcedCopy: true,
            orderedPromisedNames: ["a.txt", "b.txt"],
            promisedOrdinals: [0, 1],
            receivedFiles: [
                .init(sessionID: sessionID, itemOrdinal: 1, callbackOrdinal: 1, stagedPath: a.path),
                .init(sessionID: sessionID, itemOrdinal: 2, callbackOrdinal: 2, stagedPath: b.path),
            ],
        )

        await store.send(.externalDrop(.applyImport(plan)))
        XCTAssertEqual(store.state.externalDropImportPlacement?.sessionID, sessionID)

        // 복사 effect가 pasteFile gate에 도달할 때까지 대기한 뒤 reset을 보낸다.
        await gate.waitForStart()
        await store.send(.lifecycle(.resetForDuplicate(windowID: UUID())))
        XCTAssertNil(store.state.externalDropImportPlacement)

        // 취소가 gate를 풀었으므로 finish가 완료되고, 복사는 중단돼 있어야 한다.
        gate.open()
        await store.finish()

        XCTAssertTrue(
            cleanup.cancels.isEmpty,
            "placement reset은 동기 복사 중 acquisition cancel을 호출하면 안 된다",
        )
        XCTAssertEqual(cleanup.finishes, [sessionID])
        XCTAssertTrue(
            recorder.copiedPaths.isEmpty,
            "resetForDuplicate 후 placement 복사가 취소돼 destination으로 복사가 없어야 한다",
        )
    }

    /// EOP-002-import_external_objects (F2 P1): windowIDChanged가 진행 중 placement 상태를 정리한다.
    /// 창 전환(windowIDChanged)은 resetForDuplicate와 달리 activeExternalDrop만 취소하고
    /// externalDropImportPlacement는 남겨둔다. placement 복사가 gate로 대기 중일 때
    /// windowIDChanged가 오면 placement가 정리돼 다음 drop이 새 placement를 시작할 수 있어야 한다.
    /// - 사전 조건: 세션 1의 placement 복사가 gate로 대기 중(placement 진행 중)이다.
    /// - 기대 결과: windowIDChanged 후 placement가 nil이고, 세션 2의 applyImport가 새 placement를 시작한다.
    func testExternalDropImport_windowIDChangedClearsInProgressPlacement() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let staging = sandbox.root.appendingPathComponent("staging")
        let dest = sandbox.root.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let a = staging.appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: a)

        let recorder = FileOpsRecorder()
        let cleanup = AcquisitionCleanupRecorder()
        let gate = PasteCancellationGate()
        var fileOps = makeRecordedFileOpsClient(recorder: recorder)
        let ungatedPaste = fileOps.pasteFile
        fileOps.pasteFile = { sourceURL, destinationURL in
            try await withTaskCancellationHandler {
                await gate.wait()
                try Task.checkCancellation()
            } onCancel: {
                gate.open()
            }
            try await ungatedPaste(sourceURL, destinationURL)
        }
        let firstSession = ExternalDropSessionID()
        let secondSession = ExternalDropSessionID()
        let store = EntryOperationsTestSupport.makeStore {
            $0.entryFileOpsClient = fileOps
            $0.externalDropAcquisitionClient = ExternalDropAcquisitionClient(
                begin: { _, _, _, _, _ in fatalError("begin not used") },
                events: { _ in AsyncStream { $0.finish() } },
                cancel: { cleanup.recordCancel($0) },
                finish: { cleanup.recordFinish($0) },
                beginLegacy: { _, _, _, _ in fatalError("beginLegacy not used") },
                prepareLegacyStaging: { _ in fatalError("prepareLegacyStaging not used") },
                finalizeLegacyStaging: { _, _ in fatalError("finalizeLegacyStaging not used") },
            )
        }
        store.exhaustivity = .off

        func makePlan(sessionID: ExternalDropSessionID) -> ExternalDropImportPlan {
            ExternalDropImportPlan(
                sessionID: sessionID,
                destination: dest.path,
                forcedCopy: true,
                orderedPromisedNames: ["a.txt"],
                promisedOrdinals: [0],
                receivedFiles: [
                    .init(sessionID: sessionID, itemOrdinal: 1, callbackOrdinal: 1, stagedPath: a.path),
                ],
            )
        }

        // 세션 1의 placement 복사가 gate로 대기 중(placement 진행 중)이다.
        await store.send(.externalDrop(.applyImport(makePlan(sessionID: firstSession))))
        await gate.waitForStart()
        XCTAssertEqual(store.state.externalDropImportPlacement?.sessionID, firstSession)

        // windowIDChanged가 진행 중 placement 상태를 정리해야 한다.
        await store.send(.lifecycle(.windowIDChanged(UUID())))
        XCTAssertNil(
            store.state.externalDropImportPlacement,
            "windowIDChanged 후 진행 중 placement가 남아 있으면 다음 drop이 시작되지 않는다",
        )

        // placement가 정리됐다면 세션 2의 applyImport가 새 placement를 시작한다.
        await store.send(.externalDrop(.applyImport(makePlan(sessionID: secondSession))))
        XCTAssertEqual(
            store.state.externalDropImportPlacement?.sessionID,
            secondSession,
            "windowIDChanged로 정리된 뒤 두 번째 applyImport가 새 placement를 시작해야 한다",
        )

        gate.open()
        await store.finish()

        XCTAssertEqual(Set(cleanup.finishes), Set([firstSession, secondSession]))
        XCTAssertTrue(cleanup.cancels.isEmpty)
    }

    /// EOP-002-import_external_objects: 이름 충돌 stop은 해당 항목만 실패시키고 나머지는 유지한다.
    /// destination에 이미 같은 이름이 있으면 replace alert `.stop`에 따라 그 항목만 실패하고,
    /// 나머지 항목은 성공해 status가 `.partiallyApplied`가 된다.
    /// - 검증 내용: 충돌 항목만 실패, 성공 항목은 남음, 원본 보존, finish 1회, status `.partiallyApplied`.
    func testExternalDropImport_collisionStopFailsOnlyThatItem() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let staging = sandbox.root.appendingPathComponent("staging")
        let dest = sandbox.root.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let a = staging.appendingPathComponent("a.txt")
        let b = staging.appendingPathComponent("b.txt")
        try Data("a".utf8).write(to: a)
        try Data("b".utf8).write(to: b)
        // destination에 a.txt가 이미 존재해 충돌을 유발한다.
        try Data("existing".utf8).write(to: dest.appendingPathComponent("a.txt"))

        let recorder = FileOpsRecorder()
        let cleanup = AcquisitionCleanupRecorder()
        let sessionID = ExternalDropSessionID()
        let store = EntryOperationsTestSupport.makeStore {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder)
            $0.entryOperationsAlertClient.showReplaceAlert = { _, _ in .stop }
            $0.externalDropAcquisitionClient = ExternalDropAcquisitionClient(
                begin: { _, _, _, _, _ in fatalError("begin not used") },
                events: { _ in AsyncStream { $0.finish() } },
                cancel: { cleanup.recordCancel($0) },
                finish: { cleanup.recordFinish($0) },
                beginLegacy: { _, _, _, _ in fatalError("beginLegacy not used") },
                prepareLegacyStaging: { _ in fatalError("prepareLegacyStaging not used") },
                finalizeLegacyStaging: { _, _ in fatalError("finalizeLegacyStaging not used") },
            )
        }
        store.exhaustivity = .off

        let plan = ExternalDropImportPlan(
            sessionID: sessionID,
            destination: dest.path,
            forcedCopy: true,
            orderedPromisedNames: ["a.txt", "b.txt"],
            promisedOrdinals: [0, 1],
            receivedFiles: [
                .init(sessionID: sessionID, itemOrdinal: 1, callbackOrdinal: 1, stagedPath: a.path),
                .init(sessionID: sessionID, itemOrdinal: 2, callbackOrdinal: 1, stagedPath: b.path),
            ],
        )

        await store.send(.externalDrop(.applyImport(plan)))
        await store.finish()
        await store.skipReceivedActions()

        // 충돌 항목 a.txt만 실패, b.txt는 성공해 destination에 남는다.
        XCTAssertEqual(recorder.copiedPaths.map(\.source.path), [b.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("b.txt").path))
        // 원본 staged 파일은 그대로 남는다.
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path))
        XCTAssertEqual(store.state.externalObjectImportStatus, .partiallyApplied)
        XCTAssertTrue(store.state.undoRecords.isEmpty)
        XCTAssertEqual(cleanup.finishes, [sessionID])
        XCTAssertTrue(cleanup.cancels.isEmpty)
    }
}

private func mutationImpacts(in actions: [EntryOperationsAction]) -> [EntryOperationsMutationImpact] {
    actions.compactMap { action in
        guard case let .outcome(.entriesMutated(impact)) = action else { return nil }
        return impact
    }
}

private func assertClipboardCommandOmitsSelectedDescendant(
    _ command: EntryOperationsClipboardCommand,
) {
    let folder = EntryModelFixtures.makeEntry(path: "/root/folder")
    let child = EntryModelFixtures.makeEntry(path: "/root/folder/./child.txt")
    let context = EntryOperationsCommandContext(
        selectedIds: [folder.id, child.id],
        displayItems: [folder, child],
        currentPath: "/root",
    )

    let outputs = EntryOperationsCommandPlanner.plan(command: .clipboard(command), context: context)

    guard case let .entryOperations(.clipboard(.copySelectedItems(files))) = outputs.first else {
        XCTFail("Expected clipboard files plan")
        return
    }
    XCTAssertEqual(files.map(\.fullPath), [folder.fullPath])
}

private final class ClipboardRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _writtenObjectPaths: [[String]] = []
    private var _setStrings: [(value: String, type: String)] = []
    private var _clearCount = 0

    func recordWriteObjects(_ objects: [any NSPasteboardWriting]) {
        lock.lock()
        defer { lock.unlock() }
        _writtenObjectPaths.append(objects.compactMap { ($0 as? NSURL)?.path })
    }

    func recordSetString(_ value: String, type: NSPasteboard.PasteboardType) {
        lock.lock()
        defer { lock.unlock() }
        _setStrings.append((value, type.rawValue))
    }

    func recordClear() {
        lock.lock()
        defer { lock.unlock() }
        _clearCount += 1
    }

    var writtenObjectPaths: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return _writtenObjectPaths
    }

    var setStrings: [(value: String, type: String)] {
        lock.lock()
        defer { lock.unlock() }
        return _setStrings
    }

    var clearCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _clearCount
    }
}

private final class CutSessionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _savedSessionIDs: [String?] = []

    func record(_ sessionID: String?) {
        lock.lock()
        defer { lock.unlock() }
        _savedSessionIDs.append(sessionID)
    }

    var savedSessionIDs: [String?] {
        lock.lock()
        defer { lock.unlock() }
        return _savedSessionIDs
    }
}

private func makeClipboardClient(recorder: ClipboardRecorder) -> PasteboardClient {
    .init(
        changeCount: { 0 },
        clearContents: {
            recorder.recordClear()
        },
        writeObjects: { objects in
            recorder.recordWriteObjects(objects)
            return true
        },
        readObjects: { _, _ in nil },
        setString: { string, type in
            recorder.recordSetString(string, type: type)
            return true
        },
        string: { _ in nil },
    )
}

private func makeAliasRecordingClient() -> EntryFileOpsClient {
    let live = EntryFileOpsClient.liveValue
    return EntryFileOpsClient(
        createFolder: { parentURL, folderName in try await live.createFolder(parentURL, folderName) },
        pasteFile: { sourceURL, destinationURL in try await live.pasteFile(sourceURL, destinationURL) },
        moveFile: { sourceURL, destinationURL in try await live.moveFile(sourceURL, destinationURL) },
        renameFile: { sourceURL, destinationURL in try await live.renameFile(sourceURL, destinationURL) },
        createAlias: { sourceURL, aliasURL in
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                throw FileOpError.notFound
            }
            try await live.createAlias(sourceURL, aliasURL)
        },
        moveToTrashAndReturnURL: { url in try await live.moveToTrashAndReturnURL(url) },
        deleteImmediately: { url in try await live.deleteImmediately(url) },
        putBackFromTrash: { trashURL, originalPath in try await live.putBackFromTrash(trashURL, originalPath) },
        compressItems: { urls in try await live.compressItems(urls) },
        extractCompressedFile: { url in try await live.extractCompressedFile(url) },
        getTags: { url in try await live.getTags(url) },
        setTags: { url, tags in try await live.setTags(url, tags) },
        toggleTag: { url, tag in try await live.toggleTag(url, tag) },
        fileExists: { path in live.fileExists(path) },
        saveDragPaths: { _ in },
        loadDragPaths: { [] },
        saveDragWithOption: { _ in },
        loadDragWithOption: { false },
        clipboardChangeCount: { 0 },
        loadClipboardCutSessionId: { nil },
        saveClipboardCutSessionId: { _ in },
        loadClipboardPaths: { ([], .copy) },
        postFileSystemChanged: { _ in },
    )
}

private func makeMixedAcceptedRequest() -> ExternalDropAcceptedRequest {
    ExternalDropAcceptedRequest(
        sessionID: ExternalDropSessionID(),
        destination: "/Users/test/Desktop",
        orderedPromisedNames: ["a.txt", "b.txt"],
        promisedOrdinals: [0, 1],
        forcedCopy: false,
        stagingDirectory: "/staging",
    )
}

private final class AcquisitionCleanupRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancels: [ExternalDropSessionID] = []
    private var _finishes: [ExternalDropSessionID] = []

    func recordCancel(_ id: ExternalDropSessionID) {
        lock.lock()
        defer { lock.unlock() }
        _cancels.append(id)
    }

    func recordFinish(_ id: ExternalDropSessionID) {
        lock.lock()
        defer { lock.unlock() }
        _finishes.append(id)
    }

    var cancels: [ExternalDropSessionID] {
        lock.lock()
        defer { lock.unlock() }
        return _cancels
    }

    var finishes: [ExternalDropSessionID] {
        lock.lock()
        defer { lock.unlock() }
        return _finishes
    }
}

@MainActor
private func makeExternalDropBarrierHarness() -> (
    store: TestStore<EntryOperationsFeature.State, EntryOperationsFeature.Action>,
    recorder: AcquisitionCleanupRecorder,
) {
    let recorder = AcquisitionCleanupRecorder()
    let store = EntryOperationsTestSupport.makeStore {
        $0.externalDropAcquisitionClient = ExternalDropAcquisitionClient(
            begin: { _, _, _, _, _ in fatalError("begin is not used by barrier tests") },
            events: { _ in AsyncStream { $0.finish() } },
            cancel: { recorder.recordCancel($0) },
            finish: { recorder.recordFinish($0) },
            beginLegacy: { _, _, _, _ in fatalError("beginLegacy is not used by barrier tests") },
            prepareLegacyStaging: { _ in fatalError("prepareLegacyStaging not used") },
            finalizeLegacyStaging: { _, _ in fatalError("finalizeLegacyStaging not used") },
        )
    }
    return (store, recorder)
}
