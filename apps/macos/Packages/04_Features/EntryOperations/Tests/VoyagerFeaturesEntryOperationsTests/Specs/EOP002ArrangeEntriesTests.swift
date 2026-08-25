import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers
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

        // 전체 실패 paste 배치도 실패 aggregate를 담은 command-level terminal을 한 건 수신한다.
        await store.receive(\.lifecycle.entryActionCompleted)

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
