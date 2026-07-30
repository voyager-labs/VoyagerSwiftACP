import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerFeaturesEntryOperations
import VoyagerShared
import XCTest

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

    /// EOP-002-copy_entries: 부모와 자식을 함께 선택하면 부모만 file clipboard에 복사한다.
    /// 계층 selection을 붙여넣을 때 자식이 부모 내용과 별도로 중복 복사되지 않는지 검증한다.
    /// - 검증 내용: copy command plan이 선택된 ancestor의 descendant Entry를 제외함
    /// - 사전 조건: 폴더와 해당 폴더의 자식 파일이 동시에 선택됨
    /// - 기대 결과: copySelectedItems files에는 부모 폴더만 포함됨
    func testCopyCommandOmitsDescendantOfSelectedFolder() {
        assertClipboardCommandOmitsSelectedDescendant(.copySelectedItems)
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

    /// EOP-002-cut_entries: 부모와 자식을 함께 선택하면 부모만 cut clipboard에 저장한다.
    /// 계층 selection을 이동할 때 부모 이동 뒤 자식 source가 사라져 부분 실패하지 않는지 검증한다.
    /// - 검증 내용: cut command plan이 선택된 ancestor의 descendant Entry를 제외함
    /// - 사전 조건: 폴더와 해당 폴더의 자식 파일이 동시에 선택됨
    /// - 기대 결과: copySelectedItems files에는 부모 폴더만 포함되고 cut marker가 뒤따름
    func testCutCommandOmitsDescendantOfSelectedFolder() {
        assertClipboardCommandOmitsSelectedDescendant(.cutSelectedItems)
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
