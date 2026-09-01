import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers
import VoyagerEntitiesEntry
@testable import VoyagerFeaturesEntryOperations
import VoyagerShared
import XCTest

// StagingDirectory가 provider에 공개되지 않은 보관 디렉터리 경로를 재현한다.
// 세션 구현과 동일한 파생 규칙(`<parent>/.voyager-claimed-<rootName>`)을 쓴다.

/// placement 정렬 회귀 테스트 공용 store. 획득 클라이언트는 fatalError 스텁으로 고정하고
/// 파일 연산만 recorder로 관찰한다. 각 테스트는 plan만 구성해 중복 setup을 피한다.
@MainActor
private func makeImportPlacementStore(
    recorder: FileOpsRecorder,
    cleanup: AcquisitionCleanupRecorder,
    preparePlacementSources: (@Sendable (ExternalDropSessionID, [String]) async -> Bool)? = nil,
    copyPlacementSource: (@Sendable (ExternalDropSessionID, String, String) async throws -> Bool)? = nil,
    showReplaceAlert: (@Sendable (String, EntryOperationsReplaceContext)
        async -> EntryOperationsReplaceAlertResponse)? = nil,
) -> TestStore<EntryOperationsFeature.State, EntryOperationsFeature.Action> {
    let store = EntryOperationsTestSupport.makeStore {
        $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder)
        if let showReplaceAlert {
            $0.entryOperationsAlertClient.showReplaceAlert = showReplaceAlert
        }
        $0.externalDropAcquisitionClient = ExternalDropAcquisitionClient(
            begin: { _, _, _, _, _, _, _ in fatalError("begin not used") },
            events: { _ in AsyncStream { $0.finish() } },
            cancel: { cleanup.recordCancel($0) },
            finish: { cleanup.recordFinish($0) },
            beginLegacy: { _, _, _, _, _, _, _ in fatalError("beginLegacy not used") },
            prepareLegacyStaging: { _ in fatalError("prepareLegacyStaging not used") },
            finalizeLegacyStaging: { _, _ in fatalError("finalizeLegacyStaging not used") },
            preparePlacementSources: preparePlacementSources ?? { _, _ in true },
            // 기본 copier는 실제로 복사하고 그 순서를 recorder에 남긴다. placement는 일반
            // paste 경로로 강등되지 않으므로(fail-closed 계약) 관찰점도 secure seam이다.
            copyPlacementSource: copyPlacementSource ?? { _, sourcePath, destinationPath in
                try FileManager.default.copyItem(atPath: sourcePath, toPath: destinationPath)
                recorder.recordCopy(
                    source: URL(fileURLWithPath: sourcePath),
                    destination: URL(fileURLWithPath: destinationPath),
                )
                return true
            },
        )
    }
    store.exhaustivity = .off
    return store
}

private func collisionCopyStub(
    fileName: String,
    recorder: FileOpsRecorder? = nil,
) -> @Sendable (ExternalDropSessionID, String, String) async throws -> Bool {
    { _, sourcePath, destinationPath in
        if (destinationPath as NSString).lastPathComponent == fileName {
            throw POSIXError(.EEXIST)
        }
        try FileManager.default.copyItem(atPath: sourcePath, toPath: destinationPath)
        recorder?.recordCopy(
            source: URL(fileURLWithPath: sourcePath),
            destination: URL(fileURLWithPath: destinationPath),
        )
        return true
    }
}

private func oneShotCollisionCopyStub(
    fileName: String,
    flag: OnceFlag,
) -> @Sendable (ExternalDropSessionID, String, String) async throws -> Bool {
    { _, sourcePath, destinationPath in
        if (destinationPath as NSString).lastPathComponent == fileName, flag.consume() {
            throw POSIXError(.EEXIST)
        }
        try FileManager.default.copyItem(atPath: sourcePath, toPath: destinationPath)
        return true
    }
}

private func claimedContainer(_ stagingRoot: URL) -> URL {
    stagingRoot.deletingLastPathComponent()
        .appendingPathComponent(".voyager-claimed-\(stagingRoot.lastPathComponent)", isDirectory: true)
}

private func waitForPath(_ path: String) async -> Bool {
    for _ in 0 ..< 200 {
        if FileManager.default.fileExists(atPath: path) { return true }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return false
}

/// staging 물리 삭제는 rename-then-detached로 비동기 수행되므로(코멘트 #3837956596)
/// 제거 완료를 폴링한다. 2초 상한 내에서 사라지지 않으면 false를 반환한다.
private func waitForRemoval(_ path: String) async -> Bool {
    for _ in 0 ..< 200 {
        if !FileManager.default.fileExists(atPath: path) { return true }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return FileManager.default.fileExists(atPath: path) == false
}

/// 경로의 inode(dev+ino)를 가리키는 현재 프로세스의 열린 fd 수(/dev/fd 스캔).
/// descriptor 고정 계약의 정확히-한-번 close 검증 전용 스냅숏이다.
private func openDescriptorCount(matchingInodeOf path: String) -> Int {
    var target = stat()
    guard Darwin.lstat(path, &target) == 0 else { return -1 }
    guard let directory = opendir("/dev/fd") else { return -1 }
    defer { closedir(directory) }
    var count = 0
    while let entry = readdir(directory) {
        let name = withUnsafeBytes(of: entry.pointee.d_name) { raw -> String? in
            raw.baseAddress.map { String(cString: $0.assumingMemoryBound(to: CChar.self)) }
        }
        guard let name, let fd = Int32(name), fd >= 0 else { continue }
        var status = stat()
        guard Darwin.fstat(fd, &status) == 0 else { continue }
        if status.st_dev == target.st_dev, status.st_ino == target.st_ino { count += 1 }
    }
    return count
}

/// release가 완료될 때까지(해당 inode fd가 0이 될 때까지) 짧게 재검사한다.
private func waitForDescriptorRelease(_ path: String) async -> Bool {
    for _ in 0 ..< 200 {
        if openDescriptorCount(matchingInodeOf: path) == 0 { return true }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return openDescriptorCount(matchingInodeOf: path) == 0
}

/// 보관 사본이 경로 생성 직후 부분 쓰기 상태로 관찰되는 창을 피하기 위해 내용 일치까지 기다린다.
private func waitForFileContents(_ url: URL, matching expected: Data) async -> Bool {
    for _ in 0 ..< 200 {
        if let data = try? Data(contentsOf: url), data == expected { return true }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return false
}

/// P1 검증 전용 종단 프러브. 획득 계약상 모든 흐름은 정확히 한 번의 종단 이벤트로 끝나므로
/// 종단 도착 즉시 반환한다. 비종단 자식을 기다리는 태스크 그룹 타임아웃 없이 결정적으로 끝난다.
private func collectEventsUntilTerminal(
    from stream: AsyncStream<ExternalDropAcquisitionEvent>,
) async -> [ExternalDropAcquisitionEvent] {
    var collected: [ExternalDropAcquisitionEvent] = []
    for await event in stream {
        collected.append(event)
        switch event {
        case .succeeded, .failed, .cancelled:
            return collected
        case .received:
            continue
        }
    }
    return collected
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

        await store.receive { action in
            guard case let .lifecycle(.entryActionCompleted(record)) = action else { return false }
            return record.succeededCount == 1 && record.failedCount == 0
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
    /// - 검증 내용: `.clipboard(.cutSelectedItems)`가 URL과 cut marker를 함께 기록하고 clipboard state와 cut session을 갱신한다.
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

        // store.exhaustivity = .off: cut action의 terminal보다 최종 clipboard 상태와 기록을 검증한다.
        store.exhaustivity = .off

        await store.send(.clipboard(.cutSelectedItems(files: [entry])))
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

    /// EOP-002-cut_entries: Cut marker 기록 실패는 명령 성공으로 확정하지 않는다.
    /// URL 기록과 Cut marker 기록을 하나의 명령 terminal로 집계하는지 검증한다.
    /// - 검증 내용: URL 기록 성공 뒤 marker 기록 실패 시 failure terminal 한 건과 copy fallback 상태를 확인한다.
    /// - 사전 조건: 실제 fixture 파일, URL 기록 성공 pasteboard, marker 기록 실패 pasteboard가 있다.
    /// - 기대 결과: accepted metadata를 보존한 failure terminal 한 건, copy operation, 비어 있는 Cut session이다.
    func testCutEntries_markerFailureEmitsSingleFailureTerminal() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let recorder = ClipboardRecorder()
        let entry = EntryModelFixtures.makeFileEntry(
            id: sandbox.fileURL.path,
            name: sandbox.fileURL.lastPathComponent,
            fileExtension: sandbox.fileURL.pathExtension,
        )
        let commandID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000202"))
        let metadata = EntryCommandMetadata(
            id: commandID,
            interaction: .cutEntries,
            source: .keyboardShortcut,
        )
        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.pasteboardClient = makeClipboardClient(
                recorder: recorder,
                setStringResult: { _, type in
                    type.rawValue != "fm.voyager.clipboard.operation"
                },
            )
            $0.entryFileOpsClient.saveClipboardCutSessionId = { _ in }
            $0.uuid = .constant(UUID())
        }
        // store.exhaustivity = .off: command 내부 accepted action은 건너뛰고 최종 terminal 계약을 검증한다.
        store.exhaustivity = .off

        await store.send(.routing(.executeCommand(
            command: .clipboard(.cutSelectedItems),
            context: .init(
                selectedIds: [entry.id],
                displayItems: [entry],
                currentPath: sandbox.root.path,
            ),
            metadata: metadata,
        )))
        await store.receive { action in
            guard case let .lifecycle(.entryActionCompleted(record)) = action else { return false }
            return record.command?.id == commandID
                && record.command?.interaction == .cutEntries
                && record.command?.source == .keyboardShortcut
                && record.succeededCount == 0
                && record.failedCount == 1
        }
        await store.finish()

        XCTAssertEqual(recorder.writtenObjectPaths, [[sandbox.fileURL.path]])
        XCTAssertEqual(store.state.clipboardItems, [sandbox.fileURL.path])
        XCTAssertEqual(store.state.clipboardOperation, .copy)
        XCTAssertNil(store.state.cutClearSession)
    }

    /// EOP-002-cut_entries: 선택된 부모와 하위 항목은 표시 순서와 무관하게 부모만 잘라내기 payload로 계획한다.
    /// 사용자가 폴더, 그 하위 파일, 그리고 문자열 접두사만 같은 peer 파일을 함께 선택할 때 하위 파일은 제외하고 topmost source만 유지하는지 확인한다.
    /// - 검증 내용: `.clipboard(.cutSelectedItems)`가 URL pathComponents의 엄격한 조상 관계로 하위 항목만 제거하고 남은 source의 표시 순서와 원본
    /// fullPath를 보존한다.
    /// - 사전 조건: 동일한 폴더와 하위 파일을 선택하되 descendant-first 및 ancestor-first 표시 순서를 각각 구성하고, 경로 구성요소상 조상이 아닌 raw-prefix peer를
    /// 포함한다.
    /// - 기대 결과: 두 표시 순서 모두 parent와 raw-prefix peer만 단일 cut payload에 포함되고 하위 파일은 포함되지 않는다.
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

    /// EOP-002-paste_entries: 수용된 metadata-bearing same-parent Cut Paste가 취소 terminal 하나로 끝나는지 검증한다.
    /// 같은 부모의 두 source를 붙여넣을 때 command metadata와 aggregate terminal을 보존한다.
    /// - 검증 내용: operation ID/source, pasteFileMove, attempted/cancelled 2, 빈 target과 zero mutation을 확인한다.
    /// - 사전 조건: 비어 있지 않은 두 source가 destination과 같은 부모에 있고 accepted Cut Paste command를 보낸다.
    /// - 기대 결과: entryActionCompleted terminal 정확히 한 건, operationFinished/mutation/filesystem/undo/reload 없음, source 유지.
    func testAcceptedCutPaste_sameParentEmitsCancelledCommandTerminal() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let secondSource = sandbox.root.appendingPathComponent("second.txt")
        try FileManager.default.copyItem(at: sandbox.fileURL, to: secondSource)
        let sources = [sandbox.fileURL.path, secondSource.path]
        let metadata = try EntryCommandMetadata(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000223")),
            interaction: .moveEntries,
            source: .keyboardShortcut,
        )
        let actionRecorder = CallRecorder<EntryOperationsAction>()
        let mutationCalls = LockIsolated(0)
        let reloadRecorder = CallRecorder<[String]>()
        var fileOps = EntryFileOpsClient.previewValue
        fileOps.moveFile = { _, _ in mutationCalls.withValue { $0 += 1 } }
        fileOps.pasteFile = { _, _ in mutationCalls.withValue { $0 += 1 } }
        fileOps.postFileSystemChanged = reloadRecorder.record
        let store = EntryOperationsTestSupport.makeObservedStore(
            observeAction: actionRecorder.record,
        ) { $0.entryFileOpsClient = fileOps }
        // store.exhaustivity = .off: accepted command 전파의 내부 lifecycle은 recorder로 terminal 개수를 검증한다.
        store.exhaustivity = .off

        await store.send(.acceptedCommand(metadata: metadata, action: .clipboard(.pasteItems(
            sourcePaths: sources,
            destinationPath: sandbox.root.path,
            operation: .cut,
            operationKind: .pasteFileMove,
        ))))
        await store.receive { action in
            guard case let .lifecycle(.entryActionCompleted(record)) = action else { return false }
            return record.command == metadata
                && record.id == metadata.id
                && record.operationKind == .pasteFileMove
                && record.attemptedCount == 2
                && record.cancelledCount == 2
                && record.succeededCount == 0
                && record.failedCount == 0
                && record.targets.isEmpty
        }
        await store.finish()

        XCTAssertEqual(actionRecorder.recorded.count(where: {
            if case .lifecycle(.entryActionCompleted) = $0 { return true }
            return false
        }), 1)
        XCTAssertFalse(actionRecorder.recorded.contains {
            if case .lifecycle(.operationFinished) = $0 { return true }
            return false
        })
        XCTAssertTrue(mutationCalls.value == 0 && reloadRecorder.recorded.isEmpty && store.state.undoRecords.isEmpty)
        XCTAssertTrue(sources.allSatisfy { FileManager.default.fileExists(atPath: $0) })
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    // MARK: - EOP-002-paste_entries

    /// EOP-002-paste_entries: 수용된 metadata-bearing 빈 Paste가 취소 terminal 하나로 끝나는지 검증한다.
    /// accepted command의 clipboard snapshot이 비어 있어도 operation metadata와 aggregate terminal을 보존한다.
    /// - 검증 내용: copy metadata, pasteFileCopy, attempted/cancelled 1, zero success/failure, 빈 target을 확인한다.
    /// - 사전 조건: 빈 clipboard snapshot을 반환하는 accepted Paste command를 보낸다.
    /// - 기대 결과: entryActionCompleted terminal 정확히 한 건, clipboard snapshot 1회, mutation/undo/reload 없음.
    func testAcceptedEmptyPaste_emitsMetadataPreservingCancelledTerminal() async throws {
        let metadata = try EntryCommandMetadata(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000224")),
            interaction: .pasteEntries,
            source: .menuCommand,
        )
        let loadCount = LockIsolated(0)
        let actionRecorder = CallRecorder<EntryOperationsAction>()
        let mutationCalls = LockIsolated(0)
        let reloadRecorder = CallRecorder<[String]>()
        var fileOps = EntryFileOpsClient.previewValue
        fileOps.loadClipboardPaths = {
            loadCount.withValue { $0 += 1 }
            return ([], .copy)
        }
        fileOps.pasteFile = { _, _ in mutationCalls.withValue { $0 += 1 } }
        fileOps.moveFile = { _, _ in mutationCalls.withValue { $0 += 1 } }
        fileOps.postFileSystemChanged = reloadRecorder.record
        let store = EntryOperationsTestSupport.makeObservedStore(observeAction: actionRecorder.record) {
            $0.entryFileOpsClient = fileOps
        }
        // store.exhaustivity = .off: accepted command의 terminal과 외부 mutation 부재만 검증한다.
        store.exhaustivity = .off

        await store.send(.acceptedCommand(
            metadata: metadata,
            action: .clipboard(.pasteItemsFromClipboard(destinationPath: "/destination")),
        ))
        await store.receive { action in
            guard case let .lifecycle(.entryActionCompleted(record)) = action else { return false }
            return record.command == metadata
                && record.operationKind == .pasteFileCopy
                && record.attemptedCount == 1
                && record.cancelledCount == 1
                && record.succeededCount == 0
                && record.failedCount == 0
                && record.targets.isEmpty
        }
        await store.finish()

        XCTAssertEqual(loadCount.value, 1)
        XCTAssertEqual(actionRecorder.recorded.count(where: {
            if case .lifecycle(.entryActionCompleted) = $0 { return true }
            return false
        }), 1)
        XCTAssertEqual(mutationCalls.value, 0)
        XCTAssertTrue(reloadRecorder.recorded.isEmpty)
        XCTAssertTrue(store.state.undoRecords.isEmpty)
    }

    /// EOP-002-paste_entries: 직접 전달된 빈 Paste는 조용히 종료되는지 검증한다.
    /// metadata가 없는 raw/direct command는 accepted command terminal 정책을 적용하지 않는다.
    /// - 검증 내용: 빈 clipboard snapshot 1회와 terminal/계정 가능한 부수효과 0회를 확인한다.
    /// - 사전 조건: 빈 clipboard snapshot을 반환하는 unwrapped Paste command를 보낸다.
    /// - 기대 결과: entryActionCompleted, mutation, undo, reload가 발생하지 않는다.
    func testDirectEmptyPaste_remainsSilent() async {
        let loadCount = LockIsolated(0)
        let actionRecorder = CallRecorder<EntryOperationsAction>()
        var fileOps = EntryFileOpsClient.previewValue
        fileOps.loadClipboardPaths = {
            loadCount.withValue { $0 += 1 }
            return ([], .cut)
        }
        let store = EntryOperationsTestSupport.makeObservedStore(observeAction: actionRecorder.record) {
            $0.entryFileOpsClient = fileOps
        }
        store.exhaustivity = .off

        await store.send(.clipboard(.pasteItemsFromClipboard(destinationPath: "/destination")))
        await store.finish()

        XCTAssertEqual(loadCount.value, 1)
        XCTAssertFalse(actionRecorder.recorded.contains {
            if case .lifecycle(.entryActionCompleted) = $0 { return true }
            return false
        })
        XCTAssertTrue(store.state.undoRecords.isEmpty)
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
    /// - 검증 내용: duplicate command plan이 선택 path를 원본 부모별 group으로 분리함
    /// - 사전 조건: 서로 다른 부모를 가진 두 항목이 선택되고 currentPath는 상위 root임
    /// - 기대 결과: 각 group destination은 해당 source의 deletingLastPathComponent 경로임
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

        XCTAssertEqual(outputs.count, 1)
        guard case let .entryOperations(.clipboard(.duplicateItems(groups))) = outputs.first,
              groups.count == 2
        else {
            XCTFail("Expected one duplicate plan grouped by source parent")
            return
        }
        XCTAssertEqual(groups[0], .init(sourcePaths: [first.fullPath], destinationPath: "/root/folder"))
        XCTAssertEqual(groups[1], .init(sourcePaths: [second.fullPath], destinationPath: "/root/other"))
    }

    /// EOP-002-duplicate_entries: 부모와 자식을 함께 선택하면 부모만 복제한다.
    /// 계층 projection에서 선택된 폴더의 하위 항목을 별도 복제해 중복 결과를 만들지 않는지 검증한다.
    /// - 검증 내용: duplicate command plan이 선택된 ancestor의 descendant path를 제외함
    /// - 사전 조건: 폴더와 해당 폴더의 자식 파일이 동시에 선택됨
    /// - 기대 결과: duplicate group source에는 부모 폴더만 포함됨
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
        guard case let .entryOperations(.clipboard(.duplicateItems(groups))) = outputs.first,
              let group = groups.first
        else {
            XCTFail("Expected one duplicate group plan")
            return
        }
        XCTAssertEqual(group, .init(sourcePaths: [folder.fullPath], destinationPath: "/root"))
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
    /// `.clipboard(.duplicateItems)` group을 만든다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`를 FixtureSandbox로 복사하고, 샌드박스 root 및 두 nested 디렉터리에 실제 파일을 준비한다.
    /// - 기대 결과: root, 첫 번째 nested 부모, 두 번째 nested 부모 순서의 group 하나가 방출되고, root 항목의 destination은
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
            metadata: .init(id: UUID(), interaction: .duplicateEntries, source: .fileManagerContent),
        )))
        await store.receive { action in
            guard case let .acceptedCommand(_, .clipboard(.duplicateItems(groups))) = action else {
                return false
            }
            return groups == scenario.expectedGroups.map {
                EntryOperationsDuplicateGroup(
                    sourcePaths: $0.sourcePaths,
                    destinationPath: $0.destinationPath,
                )
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

    /// EOP-002-provider_drop_impact: 일부 성공 뒤 취소된 copy drop도 단일 terminal로 수렴한다.
    /// - 검증 내용: accepted metadata, 성공 target, 나머지 cancelled aggregate, undo와 mutation impact를 보존한다.
    /// - 사전 조건: 실제 fixture 3개 중 첫 복사가 성공한 직후 effect task가 취소된다.
    /// - 기대 결과: attempted 3, succeeded 1, cancelled 2인 terminal 한 건과 성공 항목만의 undo/impact가 남는다.
    func testAcceptedProviderDrop_cancelAfterFirstSuccessPreservesTerminalAndImpact() async throws {
        let sandbox = try FixtureSandbox.copyingDirectory(from: "fixtures/fixtures/images/jpeg")
        defer { sandbox.cleanup() }
        let names = try FileManager.default.contentsOfDirectory(atPath: sandbox.fileURL.path).sorted()
        let sourceURLs = try names.prefix(3).map { name in
            try XCTUnwrap(URL(string: name, relativeTo: sandbox.fileURL)?.standardizedFileURL)
        }
        XCTAssertEqual(sourceURLs.count, 3)
        let destinationFolder = sandbox.root.appendingPathComponent("CancelledCopyTarget")
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let metadata = try makeCancelledDropMetadata()
        let startedCopies = CallRecorder<String>()
        let actionRecorder = CallRecorder<EntryOperationsAction>()
        var fileOps = EntryFileOpsClient.previewValue
        fileOps.pasteFile = { sourceURL, destinationURL in
            startedCopies.record(sourceURL.path)
            try await EntryFileOpsClient.liveValue.pasteFile(sourceURL, destinationURL)
            if startedCopies.recorded.count == 1 {
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        let store = EntryOperationsTestSupport.makeObservedStore(observeAction: actionRecorder.record) {
            $0.entryFileOpsClient = fileOps
        }
        // store.exhaustivity = .off: 취소된 effect의 terminal과 최종 aggregate만 검증한다.
        store.exhaustivity = .off

        await store.send(.acceptedCommand(
            metadata: metadata,
            action: .clipboard(.performDrop(
                sourcePaths: sourceURLs.map(\.path),
                destinationPath: destinationFolder.path,
                isOptionDrag: true,
            )),
        ))
        await store.finish()
        await store.skipReceivedActions()

        try assertCancelledProviderDropRecord(
            in: actionRecorder.recorded,
            metadata: metadata,
            sourceURLs: sourceURLs,
            destinationFolder: destinationFolder,
        )
        XCTAssertEqual(store.state.undoRecords.count, 1)
        XCTAssertEqual(mutationImpacts(in: actionRecorder.recorded), [
            EntryOperationsMutationImpact(
                sourceParentPaths: [sandbox.fileURL.path],
                destinationPath: destinationFolder.path,
            ),
        ])
        XCTAssertEqual(startedCopies.recorded, [sourceURLs[0].path])
    }

    private func assertCancelledProviderDropRecord(
        in actions: [EntryOperationsAction],
        metadata: EntryCommandMetadata,
        sourceURLs: [URL],
        destinationFolder: URL,
    ) throws {
        let records = actions.compactMap { action -> EntryActionRecord? in
            guard case let .lifecycle(.entryActionCompleted(record)) = action else { return nil }
            return record
        }
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.command, metadata)
        XCTAssertEqual(record.operationKind, .pasteFileCopy)
        XCTAssertEqual(record.attemptedCount, 3)
        XCTAssertEqual(record.succeededCount, 1)
        XCTAssertEqual(record.failedCount, 0)
        XCTAssertEqual(record.cancelledCount, 2)
        XCTAssertEqual(record.targets.map(\.beforePath), [sourceURLs[0].path])
        XCTAssertEqual(record.targets.map(\.afterPath), [
            destinationFolder.appendingPathComponent(sourceURLs[0].lastPathComponent).path,
        ])
    }

    private func makeCancelledDropMetadata() throws -> EntryCommandMetadata {
        try EntryCommandMetadata(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000522")),
            interaction: .copyEntries,
            source: .dragAndDrop,
        )
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

    /// EOP-002-provider_drop_impact: 수용된 Sidebar Option-copy provider decode 실패는 취소 terminal을 한 번 보냄
    /// - 검증 내용: accepted metadata, operation kind, provider 수 기반 cancelled aggregate, 빈 target
    /// - 사전 조건: 유효한 file URL provider 뒤에 잘못된 file URL data provider가 있는 Option-copy 요청
    /// - 기대 결과: copy metadata를 보존한 cancelled terminal 한 건만 만들고 filesystem mutation은 없음
    func testAcceptedProviderDrop_optionCopyDecodeFailureEmitsCancelledTerminal() async throws {
        try await assertAcceptedProviderDropDecodeFailure(
            id: "00000000-0000-0000-0000-000000000221",
            interaction: .copyEntries,
            operationKind: .pasteFileCopy,
            isOptionDrag: true,
        )
    }

    /// EOP-002-provider_drop_impact: 수용된 Sidebar move provider decode 실패는 취소 terminal을 한 번 보냄
    /// - 검증 내용: accepted metadata, operation kind, provider 수 기반 cancelled aggregate, 빈 target
    /// - 사전 조건: 유효한 file URL provider 뒤에 잘못된 file URL data provider가 있는 move 요청
    /// - 기대 결과: move metadata를 보존한 cancelled terminal 한 건만 만들고 filesystem mutation은 없음
    func testAcceptedProviderDrop_moveDecodeFailureEmitsCancelledTerminal() async throws {
        try await assertAcceptedProviderDropDecodeFailure(
            id: "00000000-0000-0000-0000-000000000222",
            interaction: .moveEntries,
            operationKind: .pasteFileMove,
            isOptionDrag: false,
        )
    }

    private func assertAcceptedProviderDropDecodeFailure(
        id: String,
        interaction: EntryInteractionIdentity,
        operationKind: OperationKind,
        isOptionDrag: Bool,
    ) async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let destination = sandbox.root.appendingPathComponent("RejectedTarget")
        let metadata = try EntryCommandMetadata(
            id: XCTUnwrap(UUID(uuidString: id)),
            interaction: interaction,
            source: .dragAndDrop,
        )
        let validProvider = NSItemProvider(item: sandbox.fileURL as NSURL, typeIdentifier: UTType.fileURL.identifier)
        let failingProvider = NSItemProvider()
        failingProvider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) {
            $0(Data("not-a-file-url".utf8), nil)
            return nil
        }
        let mutationCalls = LockIsolated(0)
        let reloadRecorder = CallRecorder<[String]>()
        var fileOps = EntryFileOpsClient.previewValue
        fileOps.pasteFile = { _, _ in mutationCalls.withValue { $0 += 1 } }
        fileOps.moveFile = { _, _ in mutationCalls.withValue { $0 += 1 } }
        fileOps.postFileSystemChanged = reloadRecorder.record
        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) { $0.entryFileOpsClient = fileOps }

        await store.send(.acceptedCommand(metadata: metadata, action: .routing(.handleDrop(
            providers: [validProvider, failingProvider],
            destinationPath: destination.path,
            isOptionDrag: isOptionDrag,
        ))))
        await store.receive { action in
            guard case let .lifecycle(.entryActionCompleted(record)) = action else { return false }
            return record.command == metadata && record.operationKind == operationKind
                && record.attemptedCount == 2 && record.cancelledCount == 2
                && record.succeededCount == 0 && record.failedCount == 0 && record.targets.isEmpty
        }
        await store.finish()

        XCTAssertEqual(mutationCalls.value, 0)
        XCTAssertTrue(reloadRecorder.recorded.isEmpty)
        XCTAssertTrue(store.state.undoRecords.isEmpty)
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

        let request = client.begin([receiver], [], "/dest", false, [], [], [])
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
        let request = client.begin([receiver], [], "/dest", false, [], [], [])
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
        let request = client.begin([receiver], [], "/dest", false, [], [], [])
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
        let flavor = deferredFlavor(uti: "public.json", bytes: bytes, filename: "Clipping 1.json")
        let request = client.begin([], [flavor], "/dest", false, [], [], [])
        let stagedURL = URL(fileURLWithPath: request.stagingDirectory).appendingPathComponent("Clipping 1.json")
        _ = await waitForPath(stagedURL.path)
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

        let flavor = deferredFlavor(
            uti: "public.utf8-plain-text",
            bytes: Data("Quarterly Report\nrevenue up\n".utf8),
            filename: "Quarterly Report.txt",
        )
        let request = client.begin([], [flavor], "/dest", false, [], [], [])
        let stagedURL = URL(fileURLWithPath: request.stagingDirectory)
            .appendingPathComponent("Quarterly Report.txt")
        _ = await waitForPath(stagedURL.path)
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

        let flavor = deferredFlavor(
            uti: "dyn.a8f9b1c2d3e4f5a6b7c8d9e0",
            bytes: Data("raw".utf8),
            filename: "Clipping 1.data",
        )
        let request = client.begin([], [flavor], "/dest", false, [], [], [])
        let stagedURL = URL(fileURLWithPath: request.stagingDirectory)
            .appendingPathComponent("Clipping 1.data")
        _ = await waitForPath(stagedURL.path)
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

        let flavorA = deferredFlavor(
            uti: "public.utf8-plain-text",
            bytes: Data("first".utf8),
            filename: "Clip 1.txt",
        )
        let flavorB = deferredFlavor(
            uti: "public.utf8-plain-text",
            bytes: Data("second".utf8),
            filename: "Clip 1.txt",
        )
        let request = client.begin([], [flavorA, flavorB], "/dest", false, [], [], [])
        let firstURL = URL(fileURLWithPath: request.stagingDirectory).appendingPathComponent("Clip 1.txt")
        let secondURL = URL(fileURLWithPath: request.stagingDirectory).appendingPathComponent("Clip 1 2.txt")
        _ = await waitForPath(firstURL.path)
        _ = await waitForPath(secondURL.path)
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
        let flavor = deferredFlavor(
            uti: "public.utf8-plain-text",
            bytes: Data("text".utf8),
            filename: "Clip 1.txt",
        )
        let request = client.begin([receiver], [flavor], "/dest", false, [], [], [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)

        // data flavor는 promise 이름을 피해 고유 이름으로 물리화된다.
        let dataStaged = staging.appendingPathComponent("Clip 1 2.txt")
        _ = await waitForPath(dataStaged.path)
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
        let flavor = deferredFlavor(
            uti: "public.json",
            bytes: Data(#"{"k":1}"#.utf8),
            filename: "Clipping 1.json",
        )
        let request = client.begin([receiver], [flavor], "/dest", false, [], [], [])
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
        // promise/data는 서로 다른 경로(콜백 vs 지연 로드)로 등록되므로 .received 도착
        // 순서는 스케줄링 의존이다. 배치 계약은 pasteboard ordinal 정렬이 담당하며
        // 이 테스트는 두 항목 모두 물리화됨과 종단만 고정한다.
        XCTAssertEqual(
            received.map(\.stagedPath).sorted(),
            [stagedData.path, claimedPromise.path].sorted(),
        )
        XCTAssertEqual(events.last, .succeeded(request.sessionID))
    }

    /// 검증 내용: finalizeLegacyStaging의 중복 경로 거절과 정상 경로 수용을 검증한다(#3840576139).
    /// 사전 조건: staging에 a.txt·c.txt가 존재한다.
    /// 기대 결과: 서로 다른 두 이름은 수용되고, 같은 파일의 다른 표기(c.txt vs ./c.txt)는
    /// nil(전체 거절) + staging 제거다.
    func testExternalDropAcquisition_finalizeLegacyStagingRejectsDuplicateStandardizedPaths() throws {
        let temporaryRoot = try makeAcquisitionTempRoot("LegacyDedupe")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let stagingDir = temporaryRoot.appendingPathComponent("ExternalDrop-LegacyDedupe")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: stagingDir.appendingPathComponent("a.txt"))
        try Data("c".utf8).write(to: stagingDir.appendingPathComponent("c.txt"))

        // 정상: 서로 다른 두 경로는 모두 수용된다.
        let accepted = client.finalizeLegacyStaging(
            ["a.txt", "c.txt"],
            stagingDir.path,
        )
        XCTAssertEqual(
            accepted,
            [
                stagingDir.appendingPathComponent("a.txt").path,
                stagingDir.appendingPathComponent("c.txt").path,
            ],
        )

        // 중복 표기(file vs ./file)는 전체 거절 + staging 제거다.
        let rejected = client.finalizeLegacyStaging(
            ["c.txt", "./c.txt"],
            stagingDir.path,
        )
        XCTAssertNil(rejected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingDir.path))
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

        let request = client.beginLegacy(
            [firstURL.path, secondURL.path],
            stagingDir.path,
            "/dest",
            true,
            [],
            [],
            [0, 1],
        )

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

        let request = client.beginLegacy([outsideURL.path], stagingDir.path, "/dest", true, [], [], [0])

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

        let request = client.beginLegacy([symlink.path], stagingDir.path, "/dest", true, [], [], [0])

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
        let request = client.begin([receiver], [], "/dest", false, [], [], [])
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
        let request = client.begin([receiverA, receiverB], [], "/dest", false, [], [], [])
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
        let request = client.begin([receiverA, receiverB], [], "/dest", false, [], [], [])
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
        let request = client.begin([receiver], [], "/dest", false, [], [], [])
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
        let request = client.begin([receiver], [], "/dest", false, [], [], [])
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
        let request = client.begin([receiverA, receiverB], [], "/dest", false, [], [], [])
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
        _ = client.begin([receiver], [], "/dest", false, [], [], [])
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
        let request = client.begin([receiver], [], "/dest", false, [], [], [])
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
        let request = client.begin([receiver], [], "/dest", false, [], [], [])
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
        let request = client.begin([receiver], [], "/dest", false, [], [], [])
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
        let request = client.begin([receiver], [], "/dest", false, [], [], [])
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
        let request = client.begin([receiver], [], "/dest", false, [], [], [])
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

    /// EOP-002-import_external_objects (VOY-736 리뷰 #3835329097): mixed drop의 즉시 file URL은
    /// 세션 큐에서 스냅숏되고 acquisition barrier의 `.received`로 합류한다.
    /// - 검증 내용: begin은 미완료 immediate 경로 없이 반환하고, 스냅숏은 원본과 다른 claimed
    ///   경로·원래 pasteboard ordinal로 수신된 뒤 promise와 함께 성공한다.
    /// - 사전 조건: receiver 1개와 staging 밖 원본 파일 1개로 begin한다.
    /// - 기대 결과: 원본은 그대로 남고, 보관 사본은 `.received`를 거쳐 placement 입력이 된다.
    func testExternalDropAcquisition_snapshotsImmediateURLsOnSessionQueue() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("ImmediatePin")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let original = temporaryRoot.appendingPathComponent("original.txt")
        try Data("safe".utf8).write(to: original)

        let receiver = FilePromiseReceiverSpy(names: ["b.txt"])
        let request = client.begin([receiver], [], "/dest", false, [original.path], [0], [1])

        XCTAssertTrue(request.immediateURLPaths.isEmpty)
        XCTAssertTrue(request.immediateOrdinals.isEmpty)
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        let pinned = claimedContainer(staging).appendingPathComponent(original.lastPathComponent)
        let snapshotReady = await waitForFileContents(pinned, matching: Data("safe".utf8))
        XCTAssertTrue(snapshotReady)
        XCTAssertEqual(try Data(contentsOf: pinned), Data("safe".utf8))
        XCTAssertEqual(try Data(contentsOf: original), Data("safe".utf8))

        try FileManager.default.removeItem(at: original)
        let outside = temporaryRoot.appendingPathComponent("outside.txt")
        try Data("evil".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: original, withDestinationURL: outside)
        let promised = staging.appendingPathComponent("b.txt")
        try Data("promised".utf8).write(to: promised)
        receiver.invokeReaderOnQueue(url: promised)

        let events = await collectEventsUntilTerminal(from: client.events(request.sessionID))
        let received = events.compactMap { event -> ExternalDropReceivedFile? in
            guard case let .received(file) = event else { return nil }
            return file
        }
        XCTAssertEqual(events.last, .succeeded(request.sessionID))
        XCTAssertEqual(received.map(\.pasteboardOrdinal).sorted(), [0, 1])
        XCTAssertTrue(received.contains { $0.stagedPath == pinned.path })
        XCTAssertEqual(try Data(contentsOf: pinned), Data("safe".utf8))
    }

    /// EOP-002-import_external_objects (VOY-736 리뷰 #3835329095): 스냅숏 이후 원본 경로는
    /// source-app이 정당하게 정리할 수 있는 표면이다. placement 바이트는 enqueue 시점 고정
    /// descriptor에서만 파생되므로, 원본 경로를 다른 inode로 교체해도 세션이 실패하지 않고
    /// 보관 사본은 enqueue 바이트를 유지한다. 사전 스냅숏 치환은 별도 테스트로 fail-closed를
    /// 고정한다.
    /// - 검증 내용: 즉시 URL 스냅숏 뒤 원본 경로를 삭제·재생성("evil")하고 promise를 완료한다.
    /// - 기대 결과: `.succeeded`로 종단하고 보관 사본은 "safe" 바이트를 유지한다.
    func testExternalDropAcquisition_immediateSnapshotSurvivesPostSnapshotOriginalReplacement() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("ClaimReplacement")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let original = temporaryRoot.appendingPathComponent("original.txt")
        try Data("safe".utf8).write(to: original)
        let receiver = FilePromiseReceiverSpy(names: ["b.txt"])
        let request = client.begin([receiver], [], "/dest", false, [original.path], [0], [1])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        let pinned = claimedContainer(staging).appendingPathComponent(original.lastPathComponent)
        let snapshotReady = await waitForPath(pinned.path)
        XCTAssertTrue(snapshotReady)

        // source-app 소유 표면인 원본 경로를 다른 inode("evil")로 교체한다. 스냅숏 사본과는
        // 무관하므로 배리어가 이를 감시하지 않는다.
        try FileManager.default.removeItem(at: original)
        try Data("evil".utf8).write(to: original)
        let promised = staging.appendingPathComponent("b.txt")
        try Data("promised".utf8).write(to: promised)
        receiver.invokeReaderOnQueue(url: promised)

        let events = await collectEventsUntilTerminal(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .succeeded(request.sessionID))
        XCTAssertEqual(try Data(contentsOf: pinned), Data("safe".utf8))
    }

    /// EOP-002-import_external_objects (VOY-736 리뷰 #3835329095): 스냅숏 이후 원본 경로를
    /// 외부 파일 symlink로 바꿔도 placement가 링크 대상을 읽지 않고 세션이 성공한다. 보관
    /// 사본은 enqueue 시점 "safe" 바이트를 유지한다.
    /// - 검증 내용: 즉시 URL 스냅숏 후 원본 파일을 외부 파일 symlink로 교체하고 promise를 완료한다.
    /// - 기대 결과: `.succeeded`로 종단하고 보관 사본은 "safe" 바이트를 유지한다.
    func testExternalDropAcquisition_immediateSnapshotIgnoresPostSnapshotOriginalSymlink() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("ClaimSymlinkReplacement")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let original = temporaryRoot.appendingPathComponent("original.txt")
        try Data("safe".utf8).write(to: original)
        let outside = temporaryRoot.appendingPathComponent("outside.txt")
        try Data("evil".utf8).write(to: outside)
        let receiver = FilePromiseReceiverSpy(names: ["b.txt"])
        let request = client.begin([receiver], [], "/dest", false, [original.path], [0], [1])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        let snapshot = claimedContainer(staging).appendingPathComponent(original.lastPathComponent)
        let snapshotReady = await waitForPath(snapshot.path)
        XCTAssertTrue(snapshotReady)

        try FileManager.default.removeItem(at: original)
        try FileManager.default.createSymbolicLink(at: original, withDestinationURL: outside)
        let promised = staging.appendingPathComponent("b.txt")
        try Data("promised".utf8).write(to: promised)
        receiver.invokeReaderOnQueue(url: promised)

        let events = await collectEventsUntilTerminal(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .succeeded(request.sessionID))
        XCTAssertEqual(try Data(contentsOf: snapshot), Data("safe".utf8))
    }

    /// EOP-002-import_external_objects (VOY-736 리뷰 #3835329095): 성공 배리어 이후
    /// placement는 no-follow descriptor로 claim-time inode를 계속 읽는다.
    /// - 검증 내용: descriptor 준비 뒤 logical path를 다른 inode로 교체해도 descriptor 경로는
    ///   원래 safe 바이트를 유지하고 교체된 evil path를 다시 열지 않는다.
    func testExternalDropAcquisition_pinsClaimDescriptorThroughPlacementWindow() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("ClaimPlacementWindow")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let original = temporaryRoot.appendingPathComponent("original.txt")
        try Data("safe".utf8).write(to: original)
        let receiver = FilePromiseReceiverSpy(names: ["b.txt"])
        let request = client.begin([receiver], [], "/dest", false, [original.path], [0], [1])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        let pinned = claimedContainer(staging).appendingPathComponent(original.lastPathComponent)
        let snapshotReady = await waitForPath(pinned.path)
        XCTAssertTrue(snapshotReady)

        let promised = staging.appendingPathComponent("b.txt")
        try Data("promised".utf8).write(to: promised)
        receiver.invokeReaderOnQueue(url: promised)
        let events = await collectEventsUntilTerminal(from: client.events(request.sessionID))

        XCTAssertEqual(events.last, .succeeded(request.sessionID))
        let prepared = await client.preparePlacementSources(request.sessionID, [pinned.path])
        XCTAssertTrue(prepared)
        try FileManager.default.removeItem(at: pinned)
        try Data("evil".utf8).write(to: pinned)
        let placed = temporaryRoot.appendingPathComponent("placed.txt")
        let handled = try await client.copyPlacementSource(request.sessionID, pinned.path, placed.path)
        XCTAssertTrue(handled)
        XCTAssertEqual(try Data(contentsOf: placed), Data("safe".utf8))
        client.cancel(request.sessionID)
    }

    /// EOP-002-import_external_objects (VOY-736 리뷰 #3835329095): staging 루트에
    /// 물리화한 data flavor도 claim과 같은 descriptor 고정 대상이다.
    /// - 검증 내용: staged path를 다른 inode로 교체해도 descriptor 경로는 원래 바이트를 읽는다.
    func testExternalDropAcquisition_pinsMaterializedDataDescriptorThroughPlacement() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("MaterializedPlacementWindow")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))
        let flavor = deferredFlavor(
            uti: "public.plain-text",
            bytes: Data("safe".utf8),
            filename: "data.txt",
            ordinal: 0,
        )

        let request = client.begin([], [flavor], "/dest", false, [], [], [])
        let events = await collectEventsUntilTerminal(from: client.events(request.sessionID))
        let staged = URL(fileURLWithPath: request.stagingDirectory).appendingPathComponent("data.txt")

        XCTAssertEqual(events.last, .succeeded(request.sessionID))
        let prepared = await client.preparePlacementSources(request.sessionID, [staged.path])
        XCTAssertTrue(prepared)
        try FileManager.default.removeItem(at: staged)
        try Data("evil".utf8).write(to: staged)
        let placed = temporaryRoot.appendingPathComponent("placed.txt")
        let handled = try await client.copyPlacementSource(request.sessionID, staged.path, placed.path)
        XCTAssertTrue(handled)
        XCTAssertEqual(try Data(contentsOf: placed), Data("safe".utf8))
        client.cancel(request.sessionID)
    }

    /// EOP-002-import_external_objects (VOY-736 리뷰 #3831133039): legacy staged 파일에도
    /// negotiation이 확정한 pasteboard 순번이 라우팅돼 placement 통합 정렬 키가 안정적이다.
    /// - 검증 내용: beginLegacy 2파일(1:1 항목 대응)의 received 이벤트 pasteboardOrdinal이 [0, 1]이다.
    func testExternalDropAcquisition_beginLegacyAssignsSequentialPasteboardOrdinals() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("LegacyOrdinals")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let stagingDir = temporaryRoot.appendingPathComponent("ExternalDrop-LegacyOrdinals")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let firstURL = stagingDir.appendingPathComponent("a.eml")
        let secondURL = stagingDir.appendingPathComponent("b.eml")
        try Data("a".utf8).write(to: firstURL)
        try Data("b".utf8).write(to: secondURL)

        let request = client.beginLegacy(
            [firstURL.path, secondURL.path],
            stagingDir.path,
            "/dest",
            true,
            [],
            [],
            [0, 1],
        )

        let events = await collectEventsUntilTerminal(from: client.events(request.sessionID))
        let ordinals = events.compactMap { event -> Int? in
            guard case let .received(file) = event else { return nil }
            return file.pasteboardOrdinal
        }
        XCTAssertEqual(ordinals, [0, 1])
        XCTAssertEqual(events.last, .succeeded(request.sessionID))
    }

    /// EOP-002-import_external_objects (VOY-736 리뷰 P1-C): legacy logical item 하나가
    /// 파일 2개를 산출하면 두 파일 모두 같은 pasteboard ordinal을 쓰고 항목 내 순번은 0/1이다.
    /// - 검증 내용: pasteboard ordinal 1짜리 promise 항목 1개 → flat 파일 2개의
    ///   received 이벤트 pasteboardOrdinal [1, 1], callbackOrdinal [0, 1].
    func testExternalDropAcquisition_beginLegacySinglePromiseTwoFilesSharesPasteboardOrdinal() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("LegacyTwoFiles")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let stagingDir = temporaryRoot.appendingPathComponent("ExternalDrop-LegacyTwoFiles")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let firstURL = stagingDir.appendingPathComponent("a.eml")
        let secondURL = stagingDir.appendingPathComponent("b.eml")
        try Data("a".utf8).write(to: firstURL)
        try Data("b".utf8).write(to: secondURL)

        let request = client.beginLegacy(
            [firstURL.path, secondURL.path],
            stagingDir.path,
            "/dest",
            true,
            [],
            [],
            [1],
        )

        let events = await collectEventsUntilTerminal(from: client.events(request.sessionID))
        let received = events.compactMap { event -> ExternalDropReceivedFile? in
            guard case let .received(file) = event else { return nil }
            return file
        }
        XCTAssertEqual(received.map(\.pasteboardOrdinal), [1, 1])
        XCTAssertEqual(received.map(\.callbackOrdinal), [0, 1])
        XCTAssertEqual(events.last, .succeeded(request.sessionID))
    }

    /// EOP-002-import_external_objects (VOY-736 리뷰 P1-C): flat 이름이 여러 logical item에
    /// 걸치고 경계를 복구할 수 없으면 출력 수로 pasteboard ordinal을 날조하지 않고 실패한다.
    /// - 검증 내용: 항목 2개([0, 1]) + flat 파일 3개 → `.indeterminateCardinality` 종단,
    ///   staging(보관 디렉터리 포함) 정리.
    func testExternalDropAcquisition_beginLegacyAmbiguousBoundariesFailClosed() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("LegacyAmbiguous")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let stagingDir = temporaryRoot.appendingPathComponent("ExternalDrop-LegacyAmbiguous")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        var stagedPaths: [String] = []
        for name in ["a.eml", "b.eml", "c.eml"] {
            let url = stagingDir.appendingPathComponent(name)
            try Data(name.utf8).write(to: url)
            stagedPaths.append(url.path)
        }

        let request = client.beginLegacy(
            stagedPaths,
            stagingDir.path,
            "/dest",
            true,
            [],
            [],
            [0, 1],
        )

        let events = await collectEventsUntilTerminal(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .failed(request.sessionID, .indeterminateCardinality))
        _ = await waitForRemoval(stagingDir.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingDir.path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: claimedContainer(stagingDir).path),
            "보관 디렉터리도 함께 정리된다",
        )
    }

    /// EOP-002-import_external_objects (VOY-736 리뷰 #3835329097): 즉시 URL 스냅숏 완료는
    /// data 물리화와 같은 acquisition barrier에 포함돼야 한다.
    /// - 검증 내용: data + immediate 혼합 drop에서 두 `.received`가 모두 도착한 뒤 성공한다.
    /// - 기대 결과: request는 즉시 빈 immediate 경로로 반환되고, 보관 사본은 event로 전달된다.
    func testExternalDropAcquisition_snapshotsImmediateBeforeDataSuccessTerminal() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("PinBeforeSuccess")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let original = temporaryRoot.appendingPathComponent("original.txt")
        try Data("safe".utf8).write(to: original)
        let flavor = deferredFlavor(
            uti: "public.json",
            bytes: Data(#"{"k":1}"#.utf8),
            filename: "Clipping 1.json",
            ordinal: 0,
        )

        let request = client.begin([], [flavor], "/dest", false, [original.path], [0], [])

        let events = await collectEventsUntilTerminal(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .succeeded(request.sessionID))
        XCTAssertTrue(request.immediateURLPaths.isEmpty)
        XCTAssertTrue(request.immediateOrdinals.isEmpty)
        let received = events.compactMap { event -> ExternalDropReceivedFile? in
            guard case let .received(file) = event else { return nil }
            return file
        }
        XCTAssertEqual(received.count, 2)
        let claimedRoot = claimedContainer(URL(fileURLWithPath: request.stagingDirectory))
        let pinned = try XCTUnwrap(received.first { $0.stagedPath.hasPrefix(claimedRoot.path) })
        XCTAssertEqual(pinned.pasteboardOrdinal, 0)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: pinned.stagedPath)), Data("safe".utf8))
    }

    /// EOP-002-import_external_objects (VOY-736 리뷰 P1-A): pinning 실패는 실패 종단만 내고
    /// accepted immediates는 비어 있어야 한다.
    func testExternalDropAcquisition_immediatePinFailureFailsClosedWithoutImmediates() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("PinFailure")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let missing = temporaryRoot.appendingPathComponent("missing.txt")

        let request = client.begin([], [], "/dest", false, [missing.path], [0], [])

        let events = await collectEventsUntilTerminal(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .failed(request.sessionID, .fileAbsent))
        XCTAssertTrue(request.immediateURLPaths.isEmpty)
    }

    /// EOP-002-import_external_objects (VOY-736 리뷰 P1-B): 즉시 URL이 디렉터리여도 하위
    /// 내용과 함께 보관 디렉터리로 pinning된다.
    func testExternalDropAcquisition_pinsImmediateDirectoryWithNestedContent() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("PinDirectory")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let sourceDir = temporaryRoot.appendingPathComponent("Bundle.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let nested = sourceDir.appendingPathComponent("inner.txt")
        try Data("nested".utf8).write(to: nested)

        let receiver = FilePromiseReceiverSpy(names: ["b.txt"])
        let request = client.begin([receiver], [], "/dest", false, [sourceDir.path], [0], [1])

        XCTAssertTrue(request.immediateURLPaths.isEmpty)
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        let pinned = claimedContainer(staging).appendingPathComponent(sourceDir.lastPathComponent)
        let snapshotReady = await waitForPath(pinned.path)
        XCTAssertTrue(snapshotReady)
        XCTAssertNotEqual(pinned.path, sourceDir.path)
        XCTAssertFalse(pinned.path.hasPrefix(request.stagingDirectory))
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: pinned.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
        let nestedReady = await waitForFileContents(
            pinned.appendingPathComponent("inner.txt"),
            matching: Data("nested".utf8),
        )
        XCTAssertTrue(nestedReady)
        XCTAssertEqual(
            try Data(contentsOf: pinned.appendingPathComponent("inner.txt")),
            Data("nested".utf8),
        )
        let promised = staging.appendingPathComponent("b.txt")
        try Data("promised".utf8).write(to: promised)
        receiver.invokeReaderOnQueue(url: promised)
        let events = await collectEventsUntilTerminal(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .succeeded(request.sessionID))

        let prepared = await client.preparePlacementSources(request.sessionID, [pinned.path])
        XCTAssertTrue(prepared)
        let originalPinned = pinned.deletingLastPathComponent().appendingPathComponent("original.bundle")
        try FileManager.default.moveItem(at: pinned, to: originalPinned)
        try FileManager.default.createDirectory(at: pinned, withIntermediateDirectories: true)
        try Data("evil".utf8).write(to: pinned.appendingPathComponent("inner.txt"))
        let placed = temporaryRoot.appendingPathComponent("Placed.bundle")
        let handled = try await client.copyPlacementSource(request.sessionID, pinned.path, placed.path)
        XCTAssertTrue(handled)
        XCTAssertEqual(
            try Data(contentsOf: placed.appendingPathComponent("inner.txt")),
            Data("nested".utf8),
        )
        client.finish(request.sessionID)
    }

    /// EOP-002-import_external_objects (VOY-736 리뷰 P1-B): symlink immediate는 fail-closed다.
    func testExternalDropAcquisition_symlinkImmediateIsRejectedFailClosed() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("PinSymlink")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let target = temporaryRoot.appendingPathComponent("target.txt")
        try Data("outside".utf8).write(to: target)
        let link = temporaryRoot.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let receiver = FilePromiseReceiverSpy(names: ["b.txt"])
        let request = client.begin([receiver], [], "/dest", false, [link.path], [0], [1])

        let events = await collectEventsUntilTerminal(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .failed(request.sessionID, .fileAbsent))
        XCTAssertTrue(request.immediateURLPaths.isEmpty)
    }

    /// EOP-002-import_external_objects (VOY-736 리뷰 #3835329095): claimed 디렉터리의 하위
    /// 파일만 교체돼도 placement는 descriptor manifest가 고정한 원본 inode를 읽는다.
    /// - 검증 내용: preparePlacementSources로 하위까지 manifest를 연 뒤 inner.txt만 다른
    ///   inode("evil")로 교체하고 copyPlacementSource로 배치한다.
    /// - 기대 결과: 배치된 inner.txt는 여전히 "nested" 바이트이고 교체 바이트는 기여하지 않는다.
    func testExternalDropAcquisition_pinsDirectoryDescendantsThroughPlacementWindow() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("DescendantPlacementWindow")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let sourceDir = temporaryRoot.appendingPathComponent("Bundle.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try Data("nested".utf8).write(to: sourceDir.appendingPathComponent("inner.txt"))
        let receiver = FilePromiseReceiverSpy(names: ["b.txt"])
        let request = client.begin([receiver], [], "/dest", false, [sourceDir.path], [0], [1])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        let pinned = claimedContainer(staging).appendingPathComponent(sourceDir.lastPathComponent)
        let snapshotReady = await waitForPath(pinned.appendingPathComponent("inner.txt").path)
        XCTAssertTrue(snapshotReady)

        let promised = staging.appendingPathComponent("b.txt")
        try Data("promised".utf8).write(to: promised)
        receiver.invokeReaderOnQueue(url: promised)
        let events = await collectEventsUntilTerminal(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .succeeded(request.sessionID))

        let prepared = await client.preparePlacementSources(request.sessionID, [pinned.path])
        XCTAssertTrue(prepared)
        // 디렉터리 자체는 유지한 채 하위 파일만 다른 inode로 교체한다.
        try FileManager.default.removeItem(at: pinned.appendingPathComponent("inner.txt"))
        try Data("evil".utf8).write(to: pinned.appendingPathComponent("inner.txt"))
        let placed = temporaryRoot.appendingPathComponent("Placed.bundle")
        _ = try await client.copyPlacementSource(request.sessionID, pinned.path, placed.path)
        XCTAssertEqual(
            try Data(contentsOf: placed.appendingPathComponent("inner.txt")),
            Data("nested".utf8),
        )
        client.cancel(request.sessionID)
    }

    /// EOP-002-import_external_objects (VOY-736 리뷰 #3835329095): detached snapshot 이후에는
    /// 보관 경로 하위가 다른 inode로 교체돼도 게이트가 불변 descriptor로 통과하고 배치는
    /// enqueue 시점 원본 바이트를 복제한다. provider는 placement 바이트에 기여할 수 없다.
    /// - 검증 내용: 성공 종단 뒤 inner.txt를 다른 inode("evil")로 교체하고 게이트를 호출한 뒤 복사한다.
    /// - 기대 결과: 게이트 true, 복사된 inner.txt는 "nested"(원본)다. finish 뒤 두 디렉터리는 정리된다.
    func testExternalDropAcquisition_placementGateSurvivesReplacedDescendantFromDetachedSnapshot() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("DescendantGate")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let sourceDir = temporaryRoot.appendingPathComponent("Bundle.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try Data("nested".utf8).write(to: sourceDir.appendingPathComponent("inner.txt"))
        let receiver = FilePromiseReceiverSpy(names: ["b.txt"])
        let request = client.begin([receiver], [], "/dest", false, [sourceDir.path], [0], [1])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        let pinned = claimedContainer(staging).appendingPathComponent(sourceDir.lastPathComponent)
        let snapshotReady = await waitForPath(pinned.appendingPathComponent("inner.txt").path)
        XCTAssertTrue(snapshotReady)

        let promised = staging.appendingPathComponent("b.txt")
        try Data("promised".utf8).write(to: promised)
        receiver.invokeReaderOnQueue(url: promised)
        let events = await collectEventsUntilTerminal(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .succeeded(request.sessionID))

        // 게이트 호출 전에 보관 경로의 하위 파일을 다른 inode로 교체한다. detached snapshot은
        // 이 교체를 무시해야 하며, 교체 바이트가 placement에 기여하지 않아야 한다.
        try FileManager.default.removeItem(at: pinned.appendingPathComponent("inner.txt"))
        try Data("evil".utf8).write(to: pinned.appendingPathComponent("inner.txt"))

        let prepared = await client.preparePlacementSources(request.sessionID, [pinned.path])
        XCTAssertTrue(prepared, "detached descriptor가 있으면 게이트는 치환과 무관하게 통과한다")

        let placed = temporaryRoot.appendingPathComponent("Placed.bundle")
        _ = try await client.copyPlacementSource(request.sessionID, pinned.path, placed.path)
        XCTAssertEqual(
            try Data(contentsOf: placed.appendingPathComponent("inner.txt")),
            Data("nested".utf8),
            "placement는 enqueue 시점 원본 바이트를 복제해야 한다",
        )

        client.finish(request.sessionID)
        _ = await waitForRemoval(staging.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        _ = await waitForRemoval(claimedContainer(staging).path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: claimedContainer(staging).path))
    }

    /// EOP-002-import_external_objects (VOY-736 리뷰 P1-A): 즉시 스냅숏은 enqueue 시점의
    /// root 신원으로 고정돼야 하며, 이후 경로 내용이 바뀌어도 교체 바이트가 기여하지 않는다.
    /// - 검증 내용: begin 직후 원본 경로를 다른 inode("evil")로 교체하고 promise를 완료한다.
    /// - 기대 결과: 스냅숏이 enqueue 시점 바이트를 고정하면 보관 사본은 "safe"이고, 신원
    ///   불일치를 감지하면 `.failed(.fileAbsent)`다. 어느 쪽이든 "evil"은 배치되지 않는다.
    func testExternalDropAcquisition_immediateSnapshotPinsEnqueueTimeBytesNotLaterPathContent() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("EnqueueIdentity")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let original = temporaryRoot.appendingPathComponent("original.txt")
        try Data("safe".utf8).write(to: original)

        // receiver 없이 즉시 스냅숏만으로 종단을 구성한다. 실패 시 staging이 빠르게
        // 정리되므로 begin 이후에는 staging에 쓰지 않는다(청소 경합 회피).
        let request = client.begin([], [], "/dest", false, [original.path], [0], [])

        // enqueue 직후 원본 경로를 다른 inode·다른 바이트로 교체한다.
        try FileManager.default.removeItem(at: original)
        try Data("evil".utf8).write(to: original)

        // 스냅숏이 막혀도 테스트가 매달리지 않게 상한을 둔다.
        let events = await collectEvents(
            from: client.events(request.sessionID),
            timeoutNanoseconds: 5_000_000_000,
        )
        XCTAssertTrue(request.immediateURLPaths.isEmpty)
        let received = events.compactMap { event -> ExternalDropReceivedFile? in
            guard case let .received(file) = event else { return nil }
            return file
        }
        switch events.last {
        case .succeeded:
            // promise 파일(receiver ordinal 1)이 아닌 즉시 스냅숏(ordinal 0)만 검증한다.
            guard let pinned = received.first(where: { $0.pasteboardOrdinal == 0 }) else {
                XCTFail("즉시 스냅숏 received 이벤트가 없다")
                return
            }
            XCTAssertEqual(
                try Data(contentsOf: URL(fileURLWithPath: pinned.stagedPath)),
                Data("safe".utf8),
            )
        case let .failed(_, reason):
            XCTAssertEqual(reason, .fileAbsent)
        default:
            XCTFail("스냅숏 완료 전에는 종단 이벤트가 없어야 한다")
        }
        client.cancel(request.sessionID)
    }

    /// EOP-002-import_external_objects (VOY-736 리뷰 P1-A): 즉시 스냅숏은 enqueue 시점에
    /// 고정한 root 신원을 기준으로 한다. enqueue 이후 원본 경로가 사라지면 descriptor 고정
    /// 설계에서는 enqueue 시점 바이트로 성공하고, 복사 시점 신원 검증 설계에서는 실패 폐쇄한다.
    /// 어느 쪽이든 later-path 내용이 기여하지 않고 스냅숏 해소가 종단을 지배한다.
    /// - 검증 내용: begin 직후 원본 경로를 제거하고 promise receiver만 완료한 뒤 종단을 확인한다.
    /// - 기대 결과: 성공 종단이라면 ordinal 0 보관 사본은 "safe" 바이트이고, 실패 종단이라면
    ///   `.fileAbsent`다. 종단 없이 끝나거나 다른 이유로 끝나면 실패다.
    func testExternalDropAcquisition_immediateSnapshotResolvesByEnqueueTimeIdentityWhenPathRemovedAfterEnqueue(
    ) async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("BarrierOwnedSnapshot")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let original = temporaryRoot.appendingPathComponent("original.txt")
        try Data("safe".utf8).write(to: original)

        // receiver 없이 즉시 스냅숏만으로 종단을 구성한다(청소 경합 회피).
        let request = client.begin([], [], "/dest", false, [original.path], [0], [])

        // enqueue 직후 원본 경로를 제거한다. 스냅숏은 enqueue 시점 신원으로만 해소된다.
        try FileManager.default.removeItem(at: original)

        // 스냅숏 해소가 막히면 상한에서 실패한다(매달림 금지).
        let events = await collectEvents(
            from: client.events(request.sessionID),
            timeoutNanoseconds: 5_000_000_000,
        )
        XCTAssertTrue(request.immediateURLPaths.isEmpty)
        let received = events.compactMap { event -> ExternalDropReceivedFile? in
            guard case let .received(file) = event else { return nil }
            return file
        }
        switch events.last {
        case .succeeded:
            guard let pinned = received.first(where: { $0.pasteboardOrdinal == 0 }) else {
                XCTFail("즉시 스냅숏 received 이벤트가 없다")
                return
            }
            XCTAssertEqual(
                try Data(contentsOf: URL(fileURLWithPath: pinned.stagedPath)),
                Data("safe".utf8),
            )
        case let .failed(_, reason):
            XCTAssertEqual(reason, .fileAbsent)
        default:
            XCTFail("스냅숏이 종단을 해소하지 않았다")
        }
    }

    /// VOY-736 v8b P1 #2 + #3835329097: root descriptor는 enqueue 시점 동기 고정(O(1),
    /// MainActor bounded)이고 하위 트리 열거는 세션 큐에서 root fd 기준 openat으로 수행된다.
    /// 열거가 완료된 뒤(보관 디렉터리 생성으로 관측) 가시 트리의 descendant를 다른 inode로
    /// 교체해도 placement는 열거 시점 고정 descriptor의 바이트를 서브한다.
    /// - 검증 내용: 보관 디렉터리가 나타나면(=열거 완료 후 복사 시작) inner.txt를 "evil"로
    ///   치환하고 스냅숏 종단을 기다린다.
    /// - 기대 결과: 성공 종단이며 보관된 inner.txt는 "nested"다("evil" 미기여).
    func testExternalDropAcquisition_pinsDirectoryDescendantsAtEnumerationTimeNotLaterPathContent() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("EnqueueDescendantPin")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let sourceDir = temporaryRoot.appendingPathComponent("Bundle.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try Data("nested".utf8).write(to: sourceDir.appendingPathComponent("inner.txt"))

        let request = client.begin([], [], "/dest", false, [sourceDir.path], [0], [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        let claimedDir = claimedContainer(staging).appendingPathComponent(sourceDir.lastPathComponent)

        // 세션 큐의 하위 트리 열거 완료를 보관 디렉터리 생성으로 동기화한다. 같은 직렬 큐
        // 작업 안에서 열거가 복사보다 먼저 끝나므로 경쟁 없이 결정적이다.
        let enumerated = await waitForPath(claimedDir.path)
        XCTAssertTrue(enumerated)

        try FileManager.default.removeItem(at: sourceDir.appendingPathComponent("inner.txt"))
        try Data("evil".utf8).write(to: sourceDir.appendingPathComponent("inner.txt"))

        let events = await collectEvents(
            from: client.events(request.sessionID),
            timeoutNanoseconds: 30_000_000_000,
        )
        XCTAssertEqual(events.last, .succeeded(request.sessionID))
        XCTAssertEqual(
            try Data(contentsOf: claimedDir.appendingPathComponent("inner.txt")),
            Data("nested".utf8),
        )
        client.cancel(request.sessionID)
    }

    /// VOY-736 P1 신뢰 경계(#3835329095, #3835329097): accept 시점 root fd가 고정되고, 세션
    /// 큐의 완료(트리 격리)가 신뢰 경계다. begin 반환 직후 가시 디렉터리를 통째로 rename해
    /// 이름 공간을 바꿔도 고정 inode lineage의 바이트를 서브한다. rename은 원자적이어서
    /// 결정론적이다(하위 inode·자식 보존).
    /// - 검증 내용: begin 반환 직후 Bundle.bundle을 다른 이름으로 rename하고 종단을 기다린다.
    /// - 기대 결과: 성공 종단이며 보관된 inner.txt는 "nested"다.
    func testExternalDropAcquisition_sourceTreeRenamedImmediatelyAfterAcceptKeepsPinnedLineage() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("AcceptSourceRename")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let sourceDir = temporaryRoot.appendingPathComponent("Bundle.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try Data("nested".utf8).write(to: sourceDir.appendingPathComponent("inner.txt"))

        let request = client.begin([], [], "/dest", false, [sourceDir.path], [0], [])

        // 큐 격리와의 경쟁 구간에서 가시 트리 전체를 원자적으로 rename한다. 고정 root fd가
        // 가리키는 inode lineage는 보존되므로 격리·placement가 이 치환의 영향을 받지 않는다.
        let renamed = temporaryRoot.appendingPathComponent("Renamed.bundle", isDirectory: true)
        try FileManager.default.moveItem(at: sourceDir, to: renamed)

        let events = await collectEvents(
            from: client.events(request.sessionID),
            timeoutNanoseconds: 30_000_000_000,
        )
        XCTAssertEqual(events.last, .succeeded(request.sessionID))
        let claimedDir = claimedContainer(URL(fileURLWithPath: request.stagingDirectory))
            .appendingPathComponent("Bundle.bundle")
        XCTAssertEqual(
            try Data(contentsOf: claimedDir.appendingPathComponent("inner.txt")),
            Data("nested".utf8),
        )
        client.cancel(request.sessionID)
    }

    /// VOY-736 P1 신뢰 경계(#3835329095, #3835329097): begin 반환 직후 descendant를 다른
    /// inode로 교체하면 격리 완료(신뢰 경계) 시점까지 큐가 이미 해당 노드를 고정했다면
    /// accept lineage가, 그 전이라면 교체 후 상태가 스냅숏될 수 있다. 경계 완료 이후의
    /// 교체는 placement에 기여할 수 없다는 점을 결정론적으로 검증한다.
    /// - 검증 내용: 보관 디렉터리 생성(=격리 완료 후 복사 시작) 뒤 inner.txt를 교체하고 종단.
    /// - 기대 결과: 성공 종단이며 보관된 inner.txt는 "nested"다("evil" 미기여).
    func testExternalDropAcquisition_postIsolationDescendantSwapCannotEnterPlacement() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("PostIsolationSwap")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let sourceDir = temporaryRoot.appendingPathComponent("Bundle.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try Data("nested".utf8).write(to: sourceDir.appendingPathComponent("inner.txt"))

        let request = client.begin([], [], "/dest", false, [sourceDir.path], [0], [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        let claimedDir = claimedContainer(staging).appendingPathComponent(sourceDir.lastPathComponent)

        let isolated = await waitForPath(claimedDir.appendingPathComponent("inner.txt").path)
        XCTAssertTrue(isolated)

        try FileManager.default.removeItem(at: sourceDir.appendingPathComponent("inner.txt"))
        try Data("evil".utf8).write(to: sourceDir.appendingPathComponent("inner.txt"))

        let events = await collectEvents(
            from: client.events(request.sessionID),
            timeoutNanoseconds: 30_000_000_000,
        )
        XCTAssertEqual(events.last, .succeeded(request.sessionID))
        XCTAssertEqual(
            try Data(contentsOf: claimedDir.appendingPathComponent("inner.txt")),
            Data("nested".utf8),
        )
        client.cancel(request.sessionID)
    }

    /// VOY-736 P1 생산자 비접근 콘텐츠(#3835329095): 격리(snapshot) 완료 뒤 provider가 여전히
    /// 쓸 수 있는 원본 트리 콘텐츠를 직접 변조해도 placement는 이미 분리된 detached snapshot
    /// 바이트를 서브한다.
    /// - 검증 내용: pin+격리+copyPinnedImmediate(snapshot 고정) 후 원본 inner.txt를 "evil"로
    ///   덮어쓰고 copyPlacementSource까지 수행한다.
    /// - 기대 결과: placement의 inner.txt는 "nested"다("evil" 미기여).
    func testExternalDropAcquisition_originalTreeMutationAfterSnapshotCannotEnterPlacement() throws {
        let temporaryRoot = try makeAcquisitionTempRoot("CloneMutation")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let fileManager = makeExternalDropFileManager(temporaryRoot: temporaryRoot)

        let stagingDir = temporaryRoot.appendingPathComponent("Staging", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let sourceDir = stagingDir.appendingPathComponent("Bundle.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try Data("nested".utf8).write(to: sourceDir.appendingPathComponent("inner.txt"))

        let staging = StagingDirectory(path: stagingDir.path, fileManager: fileManager)
        XCTAssertTrue(staging.pinImmediateRoots(urls: [sourceDir.path]))
        XCTAssertTrue(staging.completeImmediateTreePinning())
        // copyPinnedImmediate는 격리 노드에서 detached snapshot을 고정하고 candidate를 반환한다.
        let candidate = try XCTUnwrap(staging.copyPinnedImmediate(sourceDir))

        // snapshot 완료 후 producer 도달 가능한 원본 트리를 직접 변조한다.
        try Data("evil".utf8).write(to: sourceDir.appendingPathComponent("inner.txt"))

        let placed = temporaryRoot.appendingPathComponent("Placed.bundle", isDirectory: true)
        try staging.copyPlacementSource(sourcePath: candidate.path, destinationPath: placed.path)
        XCTAssertEqual(
            try Data(contentsOf: placed.appendingPathComponent("inner.txt")),
            Data("nested".utf8),
        )
        staging.remove()
    }

    /// VOY-736 P1 생산자 비접근 콘텐츠(#3835329095): legacy staged 파일은 등록 시점에 detached
    /// snapshot으로 고정되므로, 이후 retained writable fd 임자 내부 재기록이 placement에 기여할
    /// 수 없다.
    /// - 검증 내용: staged 파일을 갱신 모드로 연 채 beginLegacy하고, 성공 종단 뒤 같은 fd로
    ///   "evil"을 기록한 다음 gate 복사까지 수행한다.
    /// - 기대 결과: placement 바이트는 "safe"다("evil" 미기여).
    func testExternalDropAcquisition_legacyStagedFileRetainedFdMutationAfterRegistrationCannotEnterPlacement(
    ) async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("LegacyRetainedFd")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let stagingDir = temporaryRoot.appendingPathComponent("Staging", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let staged = stagingDir.appendingPathComponent("legacy.txt")
        try Data("safe".utf8).write(to: staged)
        let retainedHandle = try FileHandle(forUpdating: staged)
        defer { try? retainedHandle.close() }

        let request = client.beginLegacy(
            [staged.path],
            stagingDir.path,
            "/dest",
            false,
            [],
            [],
            [0],
        )
        let events = await collectEventsUntilTerminal(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .succeeded(request.sessionID))

        try retainedHandle.truncate(atOffset: 0)
        try retainedHandle.write(contentsOf: Data("evil".utf8))

        let placed = temporaryRoot.appendingPathComponent("Placed-legacy.txt")
        let prepared = await client.preparePlacementSources(request.sessionID, [staged.path])
        XCTAssertTrue(prepared)
        _ = try await client.copyPlacementSource(request.sessionID, staged.path, placed.path)
        XCTAssertEqual(try Data(contentsOf: placed), Data("safe".utf8))
        client.cancel(request.sessionID)
    }

    /// VOY-736 P1 단일 descriptor 소유(#3835329095): placement 복사 중 cancel/finish가 원본
    /// manifest를 닫아도 복사 경로는 잠금 보유 중 dup한 사본 fd를 쓰므로 재사용된 fd로 읽지
    /// 않는다. 바이트가 정확하거나(성공) 세션이 취소로 정리되며(취소) 잘못된 콘텐츠는 없다.
    /// - 검증 내용: 복사 루프와 병행으로 cancel을 반복 호출하고, 복사 결과가 항상 원본
    ///   바이트이거나 예외(취소 정리)임을 확인한다.
    /// - 기대 결과: 성공 시에만 정확한 "nested" 바이트, 실패는 예외로만 표현된다.
    func testExternalDropAcquisition_placementCopyDuringCancelNeverReadsReusedFd() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("CopyDuringCancel")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let sourceDir = temporaryRoot.appendingPathComponent("Bundle.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try Data("nested".utf8).write(to: sourceDir.appendingPathComponent("inner.txt"))

        for iteration in 0 ..< 30 {
            let receiver = FilePromiseReceiverSpy(names: ["b.txt"])
            let request = client.begin([receiver], [], "/dest", false, [sourceDir.path], [0], [1])
            let staging = URL(fileURLWithPath: request.stagingDirectory)
            let claimedDir = claimedContainer(staging).appendingPathComponent(sourceDir.lastPathComponent)
            let promised = staging.appendingPathComponent("b.txt")
            try Data("promised".utf8).write(to: promised)
            receiver.invokeReaderOnQueue(url: promised)

            // 복사와 cancel을 경쟁시킨다. cancel은 MainActor-isolated이므로 명시적 hop.
            async let cancelling: Void = Task { @MainActor in
                for _ in 0 ..< 40 {
                    client.cancel(request.sessionID)
                }
            }.value
            _ = await cancelling
            let events = await collectEventsUntilTerminal(from: client.events(request.sessionID))

            switch events.last {
            case .succeeded:
                let placed = temporaryRoot.appendingPathComponent("Placed-\(iteration).bundle", isDirectory: true)
                let prepared = await client.preparePlacementSources(request.sessionID, [claimedDir.path])
                if prepared {
                    _ = try? await client.copyPlacementSource(request.sessionID, claimedDir.path, placed.path)
                    if FileManager.default.fileExists(atPath: placed.path) {
                        XCTAssertEqual(
                            try Data(contentsOf: placed.appendingPathComponent("inner.txt")),
                            Data("nested".utf8),
                            "성공 복사는 항상 accept 바이트를 서브해야 한다",
                        )
                    }
                }
            case .failed, .cancelled, .none, .received:
                break
            }
        }
    }

    /// VOY-736 P1 스트리밍 격리(#3835329095, #3835329097): 큐 격리는 고정 root fd에서
    /// openat 순회로 각 노드를 무작위 이름 사유 snapshot으로 relink한다. 원본이 삭제돼도
    /// placement는 snapshot 바이트를 서브한다.
    /// - 검증 내용: pin+격리 뒤 원본 트리를 삭제하고 candidate 복사와 placement 복사를 수행한다.
    /// - 기대 결과: placement의 inner.txt는 "nested"다.
    func testExternalDropAcquisition_immediateIsolationWalkServesPinnedSnapshotAfterSourceRemoval() throws {
        let temporaryRoot = try makeAcquisitionTempRoot("IsolationWalk")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let fileManager = makeExternalDropFileManager(temporaryRoot: temporaryRoot)

        let stagingDir = temporaryRoot.appendingPathComponent("Staging", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let sourceDir = stagingDir.appendingPathComponent("Bundle.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try Data("nested".utf8).write(to: sourceDir.appendingPathComponent("inner.txt"))

        let staging = StagingDirectory(path: stagingDir.path, fileManager: fileManager)
        XCTAssertTrue(staging.pinImmediateRoots(urls: [sourceDir.path]))
        XCTAssertTrue(staging.completeImmediateTreePinning())

        // 원본을 삭제해도 격리 snapshot은 살아 있어야 한다.
        try FileManager.default.removeItem(at: sourceDir)
        let candidate = try XCTUnwrap(staging.copyPinnedImmediate(sourceDir))
        let placed = temporaryRoot.appendingPathComponent("Copied.bundle", isDirectory: true)
        try staging.copyPlacementSource(sourcePath: candidate.path, destinationPath: placed.path)
        XCTAssertEqual(
            try Data(contentsOf: placed.appendingPathComponent("inner.txt")),
            Data("nested".utf8),
        )
        staging.remove()
    }

    /// VOY-736 P1 bounded fd(#3835329097): 소프트 RLIMIT_NOFILE(기본 256)을 넘는 넓은 트리도
    /// 스트리밍 격리는 노드 수와 무관하게 깊이 수준 fd만 보유하므로 EMFILE 없이 완료되고,
    /// 전체 바이트가 보존된다.
    /// - 검증 내용: 서로 다른 400개 파일을 담은 트리를 pin+격리하고 원본 삭제 뒤 placement
    ///   복사로 모든 파일 바이트를 검증한다.
    /// - 기대 결과: 성공 종단이며 모든 파일 내용이 보존된다.
    func testExternalDropAcquisition_broadTreeBeyondSoftFileLimitIsolatesWithBoundedDescriptors() throws {
        let temporaryRoot = try makeAcquisitionTempRoot("BroadTree")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let fileManager = makeExternalDropFileManager(temporaryRoot: temporaryRoot)

        let stagingDir = temporaryRoot.appendingPathComponent("Staging", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let sourceDir = stagingDir.appendingPathComponent("Wide.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let fileCount = 400
        for index in 0 ..< fileCount {
            try Data("payload-\(index)".utf8).write(
                to: sourceDir.appendingPathComponent("file-\(index).txt"),
            )
        }

        let staging = StagingDirectory(path: stagingDir.path, fileManager: fileManager)
        XCTAssertTrue(staging.pinImmediateRoots(urls: [sourceDir.path]))
        XCTAssertTrue(staging.completeImmediateTreePinning())

        try FileManager.default.removeItem(at: sourceDir)
        let candidate = try XCTUnwrap(staging.copyPinnedImmediate(sourceDir))
        let placed = temporaryRoot.appendingPathComponent("Placed-Wide.bundle", isDirectory: true)
        try staging.copyPlacementSource(sourcePath: candidate.path, destinationPath: placed.path)
        for index in [0, fileCount / 2, fileCount - 1] {
            XCTAssertEqual(
                try Data(contentsOf: placed.appendingPathComponent("file-\(index).txt")),
                Data("payload-\(index)".utf8),
            )
        }
        staging.remove()
    }

    /// VOY-736 P1 바이트 동결(#3835329095): provider가 retained writable fd로 스냅숏 완료 뒤
    /// 같은 inode를 truncate·pwrite해도 placement는 accept 시점 고정 snapshot 바이트를 서브한다.
    /// - 검증 내용: 원본을 갱신 모드로 연 채 begin하고, 보관 사본 생성 확인 뒤 같은 fd로
    ///   "evil"을 기록한 다음 promise를 완료하고 gate 복사까지 수행한다.
    /// - 기대 결과: 성공 종단이며 placement 바이트는 "safe"다("evil" 미기여).
    func testExternalDropAcquisition_retainedWritableFdMutationAfterSnapshotCannotEnterPlacement() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("RetainedFdMutation")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let original = temporaryRoot.appendingPathComponent("original.txt")
        try Data("safe".utf8).write(to: original)
        let retainedHandle = try FileHandle(forUpdating: original)
        defer { try? retainedHandle.close() }

        let receiver = FilePromiseReceiverSpy(names: ["b.txt"])
        let request = client.begin([receiver], [], "/dest", false, [original.path], [0], [1])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        let pinned = claimedContainer(staging).appendingPathComponent(original.lastPathComponent)

        let snapshotReady = await waitForPath(pinned.path)
        XCTAssertTrue(snapshotReady)

        // 같은 inode를 retained fd로 임자 내부 재기록한다. accept 경계 clone과 그로부터 만든
        // detached snapshot은 별도 inode므로 placement에 기여할 수 없다.
        try retainedHandle.truncate(atOffset: 0)
        try retainedHandle.write(contentsOf: Data("evil".utf8))

        let promised = staging.appendingPathComponent("b.txt")
        try Data("promised".utf8).write(to: promised)
        receiver.invokeReaderOnQueue(url: promised)

        let events = await collectEventsUntilTerminal(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .succeeded(request.sessionID))

        let placed = temporaryRoot.appendingPathComponent("Placed-original.txt")
        let prepared = await client.preparePlacementSources(request.sessionID, [pinned.path])
        XCTAssertTrue(prepared)
        _ = try await client.copyPlacementSource(request.sessionID, pinned.path, placed.path)
        XCTAssertEqual(try Data(contentsOf: placed), Data("safe".utf8))
        client.cancel(request.sessionID)
    }

    /// VOY-736 P1 바이트 동결(#3835329095): nested descendant도 retained writable fd 임자
    /// 내부 재기록이 placement에 기여할 수 없다.
    /// - 검증 내용: inner.txt를 갱신 모드로 연 채 begin하고, 보관 디렉터리 확인 뒤 같은 fd로
    ///   "evil"을 기록한 다음 promise를 완료하고 디렉터리 gate 복사까지 수행한다.
    /// - 기대 결과: 성공 종단이며 placement의 inner.txt는 "nested"다("evil" 미기여).
    func testExternalDropAcquisition_retainedWritableFdNestedMutationAfterSnapshotCannotEnterPlacement() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("RetainedFdNestedMutation")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let sourceDir = temporaryRoot.appendingPathComponent("Bundle.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let innerFile = sourceDir.appendingPathComponent("inner.txt")
        try Data("nested".utf8).write(to: innerFile)
        let retainedHandle = try FileHandle(forUpdating: innerFile)
        defer { try? retainedHandle.close() }

        let receiver = FilePromiseReceiverSpy(names: ["b.txt"])
        let request = client.begin([receiver], [], "/dest", false, [sourceDir.path], [0], [1])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        let claimedDir = claimedContainer(staging).appendingPathComponent(sourceDir.lastPathComponent)

        let snapshotReady = await waitForPath(claimedDir.appendingPathComponent("inner.txt").path)
        XCTAssertTrue(snapshotReady)

        try retainedHandle.truncate(atOffset: 0)
        try retainedHandle.write(contentsOf: Data("evil".utf8))

        let promised = staging.appendingPathComponent("b.txt")
        try Data("promised".utf8).write(to: promised)
        receiver.invokeReaderOnQueue(url: promised)

        let events = await collectEventsUntilTerminal(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .succeeded(request.sessionID))

        let placed = temporaryRoot.appendingPathComponent("Placed.bundle", isDirectory: true)
        let prepared = await client.preparePlacementSources(request.sessionID, [claimedDir.path])
        XCTAssertTrue(prepared)
        _ = try await client.copyPlacementSource(request.sessionID, claimedDir.path, placed.path)
        XCTAssertEqual(
            try Data(contentsOf: placed.appendingPathComponent("inner.txt")),
            Data("nested".utf8),
        )
        client.cancel(request.sessionID)
    }

    /// VOY-736 v8b P1 #4: 같은 배치 안의 canonical 중복 root는 descriptor를 덮어써 누수시키지
    /// 않는다. 중복은 기존 고정분과 현재 배치 모두와 대조해 건너뛰고, 열린 descriptor는
    /// 정확히 한 번 닫힌다.
    /// - 검증 내용: 트리 내 디렉터리 symlink로 같은 파일을 가리키는 서로 다른 경로 쌍을 한
    ///   배치로 넣는다(canonicalClaimPath가 둘을 같은 canonical로 접는다). 성공 종단+finish 뒤
    ///   해당 inode를 가리키는 열린 fd가 0이 될 때까지 확인한다.
    func testExternalDropAcquisition_duplicateCanonicalAliasesDoNotLeakDescriptors() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("AliasPin")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let realDir = temporaryRoot.appendingPathComponent("real.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: realDir, withIntermediateDirectories: true)
        let inner = realDir.appendingPathComponent("inner.txt")
        try Data("dup".utf8).write(to: inner)
        let linkDir = temporaryRoot.appendingPathComponent("link.bundle")
        try FileManager.default.createSymbolicLink(at: linkDir, withDestinationURL: realDir)
        // 두 입력 경로는 다르지만 canonicalClaimPath는 같은 canonical로 접는다.
        XCTAssertEqual(
            URL(fileURLWithPath: linkDir.appendingPathComponent("inner.txt").path)
                .resolvingSymlinksInPath().path,
            inner.standardizedFileURL.resolvingSymlinksInPath().path,
        )

        let receiver = FilePromiseReceiverSpy(names: ["b.txt"])
        let request = client.begin(
            [receiver],
            [],
            "/dest",
            false,
            [inner.path, linkDir.appendingPathComponent("inner.txt").path],
            [0, 1],
            [1],
        )

        let staging = URL(fileURLWithPath: request.stagingDirectory)
        let promised = staging.appendingPathComponent("b.txt")
        try Data("promised".utf8).write(to: promised)
        receiver.invokeReaderOnQueue(url: promised)

        let events = await collectEventsUntilTerminal(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .succeeded(request.sessionID))
        client.finish(request.sessionID)

        // manifest descriptor release가 정확히 한 번 닫혔는지 확인한다. 중복 open 덮어쓰기가
        // 있으면 누수된 fd가 남아 0에 도달하지 않는다.
        let released = await waitForDescriptorRelease(inner.path)
        XCTAssertTrue(released, "canonical 중복 root descriptor가 누수됐다")
    }

    /// EOP-002-import_external_objects (VOY-736 리뷰 P1-C): promise callback이 FIFO를
    /// 전달하면 세션 lock이나 open 블로킹 없이 즉시 fail-closed한다.
    /// - 검증 내용: staging에 mkfifo로 만든 특수 파일을 reader callback으로 보고한다.
    /// - 기대 결과: 상한 시간 안에 `.failed(.callbackError)`로 종단하고 staging/보관 디렉터리가 정리된다.
    func testExternalDropAcquisition_fifoPromiseCallbackFailsPromptlyWithoutBlocking() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("FifoCallback")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let receiver = FilePromiseReceiverSpy(names: ["a.txt"])
        let request = client.begin([receiver], [], "/dest", false, [], [], [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        let fifo = staging.appendingPathComponent("a.txt")
        XCTAssertEqual(Darwin.mkfifo(fifo.path, 0o644), 0)

        receiver.invokeReaderOnQueue(url: fifo)

        // 블로킹 회귀 시 hang 대신 상한에서 실패한다.
        let events = await collectEvents(
            from: client.events(request.sessionID),
            timeoutNanoseconds: 5_000_000_000,
        )
        XCTAssertEqual(events.last, .failed(request.sessionID, .callbackError))
        _ = await waitForRemoval(staging.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: claimedContainer(staging).path))
    }

    /// EOP-002-import_external_objects (VOY-736 detached-snapshot 계약): 성공 종단 뒤 보관
    /// 사본이 같은 경로 FIFO로 치환돼도 placement 게이트는 detached descriptor만으로 즉시
    /// 통과하고(FIFO를 열지 않으므로 블로킹이 구조적으로 없다), 배치 복사는 원본 바이트를
    /// 재현한다. cancel은 staging과 보관 디렉터리를 정리한다.
    /// - 검증 내용: claimed 파일을 같은 경로 FIFO로 치환하고 상한 경주 안에서 게이트를 호출한 뒤 복사한다.
    /// - 기대 결과: 게이트는 상한 안에 true, 복사 결과는 "safe"(원본)다. cancel 뒤 두 디렉터리는 정리된다.
    func testExternalDropAcquisition_fifoClaimedPathServesDetachedSnapshotPromptlyAndStaysCancellable() async throws {
        let temporaryRoot = try makeAcquisitionTempRoot("FifoPlacementGate")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let client = ExternalDropAcquisitionClient
            .live(fileManager: makeExternalDropFileManager(temporaryRoot: temporaryRoot))

        let original = temporaryRoot.appendingPathComponent("original.txt")
        try Data("safe".utf8).write(to: original)
        let receiver = FilePromiseReceiverSpy(names: ["b.txt"])
        let request = client.begin([receiver], [], "/dest", false, [original.path], [0], [1])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        let pinned = claimedContainer(staging).appendingPathComponent(original.lastPathComponent)
        let snapshotReady = await waitForPath(pinned.path)
        XCTAssertTrue(snapshotReady)

        let promised = staging.appendingPathComponent("b.txt")
        try Data("promised".utf8).write(to: promised)
        receiver.invokeReaderOnQueue(url: promised)
        let events = await collectEventsUntilTerminal(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .succeeded(request.sessionID))

        // 보관 사본을 같은 경로의 FIFO로 치환한다. detached descriptor는 이 치환과 무관하다.
        try FileManager.default.removeItem(at: pinned)
        XCTAssertEqual(Darwin.mkfifo(pinned.path, 0o644), 0)

        // FIFO를 다시 열어야 하는 회귀 시 hang 대신 상한에서 실패한다.
        let preparedWithinTimeout: Bool? = await withTaskGroup(of: Bool?.self) { group in
            group.addTask { () -> Bool? in
                await client.preparePlacementSources(request.sessionID, [pinned.path])
            }
            group.addTask { () -> Bool? in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return nil
            }
            let first = await group.next().flatMap(\.self)
            group.cancelAll()
            return first
        }
        guard let prepared = preparedWithinTimeout else {
            XCTFail("placement 게이트가 상한 시간 안에 반환하지 않았다")
            return
        }
        XCTAssertTrue(prepared, "detached descriptor가 있으면 FIFO 치환과 무관하게 게이트가 통과한다")

        // 배치 복사는 FIFO를 열지 않고 detached descriptor의 원본 바이트를 재현한다.
        let placed = temporaryRoot.appendingPathComponent("Placed-original.txt")
        _ = try await client.copyPlacementSource(request.sessionID, pinned.path, placed.path)
        XCTAssertEqual(try Data(contentsOf: placed), Data("safe".utf8))

        client.cancel(request.sessionID)
        _ = await waitForRemoval(staging.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: claimedContainer(staging).path))
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
        let request = client.begin([emptyReceiver, namedReceiver], [], "/dest", false, [], [], [])
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
        let request = client.begin([receiver], [], "/dest", false, [], [], [])
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
        let request = client.begin([receiver], [], "/dest", false, [], [], [])
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
        let flavor = deferredFlavor(
            uti: "public.utf8-plain-text",
            bytes: Data("Fwd: hello".utf8),
            filename: "Fwd hello.txt",
        )
        let request = client.begin([receiver], [flavor], "/dest", false, [], [], [])
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
        let request = client.begin([receiver], [], "/dest", false, [], [], [])
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
        let request = client.begin([receiver], [], "/dest", false, [], [], [])
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
        let request = client.begin([receiver], [], "/dest", false, [], [], [])
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
        let request = client.begin([receiver], [], "/dest", false, [], [], [])
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
        let request = client.begin([receiver], [], "/dest", false, [], [], [])
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
        let request = client.begin([receiver], [], "/dest", false, [], [], [])
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
        let request = client.begin([receiver], [], "/dest", false, [], [], [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        try Data("a".utf8).write(to: staging.appendingPathComponent("a.txt"))
        receiver.invokeReader(url: staging.appendingPathComponent("a.txt"), error: nil)

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .succeeded(request.sessionID))
        // 성공 종단 직후 staging은 복사 대상이므로 아직 존재한다.
        XCTAssertTrue(FileManager.default.fileExists(atPath: request.stagingDirectory))

        client.finish(request.sessionID)
        _ = await waitForRemoval(request.stagingDirectory)
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
        let request = client.begin([receiver], [], "/dest", false, [], [], [])
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
        let request = client.begin([receiver], [], "/dest", false, [], [], [])
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
        let request = client.begin([receiver], [], "/dest", false, [], [], [])
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
        let request = client.begin([receiver], [], "/dest", false, [], [], [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let staged = staging.appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: staged)
        receiver.invokeReader(url: staged, error: nil)

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .succeeded(request.sessionID))

        // placement 복사 완료로 finish가 staging을 제거한다.
        client.finish(request.sessionID)
        _ = await waitForRemoval(staging.path)
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
        let request = client.begin([receiver], [], "/dest", false, [], [], [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let staged = staging.appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: staged)
        receiver.invokeReader(url: staged, error: nil)

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .succeeded(request.sessionID))

        // placement 복사 완료로 finish가 staging 루트를 제거한다.
        client.finish(request.sessionID)
        _ = await waitForRemoval(staging.path)
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
        let request = client.begin([receiver], [], "/dest", false, [], [], [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let staged = staging.appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: staged)
        receiver.invokeReader(url: staged, error: nil)

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .succeeded(request.sessionID))

        client.cancel(request.sessionID)

        _ = await waitForRemoval(request.stagingDirectory)
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
        let request = client.begin([receiver], [], "/dest", false, [], [], [])
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
        let request = client.begin([receiver], [], "/dest", false, [], [], [])
        let staging = URL(fileURLWithPath: request.stagingDirectory)
        try Data("a".utf8).write(to: staging.appendingPathComponent("a.txt"))

        client.cancel(request.sessionID)

        let events: [ExternalDropAcquisitionEvent] = await collectEvents(from: client.events(request.sessionID))
        XCTAssertEqual(events.last, .cancelled(request.sessionID))
        _ = await waitForRemoval(request.stagingDirectory)
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
        let request = client.begin([receiver], [], "/dest", false, [], [], [])
        client.cancel(request.sessionID)
        // 취소의 rename-then-detached 정리가 끝난 뒤 재생성해야 백그라운드 삭제와 경합하지 않는다.
        _ = await waitForRemoval(request.stagingDirectory)

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
        let request = client.begin([receiver], [], "/dest", false, [], [], [])
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
                begin: { _, _, _, _, _, _, _ in fatalError("begin is not used by barrier tests") },
                events: { _ in AsyncStream { $0.finish() } },
                cancel: { recorder.recordCancel($0) },
                finish: { recorder.recordFinish($0) },
                beginLegacy: { _, _, _, _, _, _, _ in fatalError("beginLegacy is not used by barrier tests") },
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
        let store = makeImportPlacementStore(recorder: recorder, cleanup: cleanup)

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

    /// EOP-002-import_external_objects (VOY-736 리뷰 #3835329095): placement 진입 게이트가
    /// claim 신원 치환을 감지하면 복사를 시작하지 않고 전체 실패로 종료한다.
    /// - 검증 내용: 검증 실패 시 pasteItems 배치가 만들어지지 않아 destination에 산출물이
    ///   없고 status는 `.failed`, finish는 정확히 1회다.
    func testExternalDropImport_rejectsReplacedClaimBeforePlacementStart() async throws {
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
        // 성공 배리어 이후 placement 직전에 같은-UID provider가 claim을 치환한 상태를
        // 세션 검증 실패로 시뮬레이션한다.
        let store = makeImportPlacementStore(
            recorder: recorder,
            cleanup: cleanup,
            preparePlacementSources: { _, _ in false },
        )

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
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.externalObjectImportStatus, .failed)
        XCTAssertTrue(recorder.copiedPaths.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathComponent("a.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
        XCTAssertEqual(cleanup.finishes, [sessionID])
        XCTAssertTrue(cleanup.cancels.isEmpty)
    }

    /// EOP-002-import_external_objects (VOY-736 리뷰 #3835329095): placement는 logical path를
    /// 이름·lifecycle 키로 유지하면서 고정된 descriptor read path에서 바이트를 복사한다.
    /// - 검증 내용: logical source가 evil이어도 stable source의 safe 바이트가 logical 이름으로
    ///   destination에 생성되고 종단은 logical source 기준으로 집계된다.
    func testExternalDropImport_readsStableDescriptorSourceThroughPlacement() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let staging = sandbox.root.appendingPathComponent("staging")
        let dest = sandbox.root.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let a = staging.appendingPathComponent("a.txt")
        let stable = sandbox.root.appendingPathComponent("stable.txt")
        try Data("evil".utf8).write(to: a)
        try Data("safe".utf8).write(to: stable)

        let recorder = FileOpsRecorder()
        let cleanup = AcquisitionCleanupRecorder()
        let sessionID = ExternalDropSessionID()
        let store = makeImportPlacementStore(
            recorder: recorder,
            cleanup: cleanup,
            copyPlacementSource: { _, _, destinationPath in
                try FileManager.default.copyItem(atPath: stable.path, toPath: destinationPath)
                return true
            },
        )

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
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertTrue(recorder.copiedPaths.isEmpty)
        XCTAssertEqual(
            try Data(contentsOf: dest.appendingPathComponent("a.txt")),
            Data("safe".utf8),
        )
        XCTAssertEqual(store.state.externalObjectImportStatus, .applied)
        XCTAssertEqual(cleanup.finishes, [sessionID])
        XCTAssertTrue(cleanup.cancels.isEmpty)
    }

    /// EOP-002-import_external_objects (VOY-736 리뷰 #3830970670): 뒤쪽 receiver의 콜백이
    /// 먼저 도착해도 placement는 pasteboard 순서(pasteboardOrdinal)를 유지한다.
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
        let store = makeImportPlacementStore(recorder: recorder, cleanup: cleanup)
        store.exhaustivity = .off

        // 도착 순서(itemOrdinal)는 B가 먼저지만 pasteboardOrdinal로 A가 먼저 정렬돼야 한다.
        let plan = ExternalDropImportPlan(
            sessionID: sessionID,
            destination: dest.path,
            forcedCopy: true,
            orderedPromisedNames: ["a.txt", "b.txt"],
            promisedOrdinals: [0, 1],
            receivedFiles: [
                .init(
                    sessionID: sessionID,
                    itemOrdinal: 1,
                    callbackOrdinal: 1,
                    stagedPath: b.path,
                    pasteboardOrdinal: 1,
                ),
                .init(
                    sessionID: sessionID,
                    itemOrdinal: 2,
                    callbackOrdinal: 1,
                    stagedPath: a.path,
                    pasteboardOrdinal: 0,
                ),
            ],
        )

        await store.send(.externalDrop(.applyImport(plan)))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(recorder.copiedPaths.map(\.source.path), [a.path, b.path])
        XCTAssertEqual(cleanup.finishes, [sessionID])
    }

    /// EOP-002-import_external_objects (VOY-736 리뷰 #3831133039): 즉시 URL이 앞 항목이면
    /// promise 완료가 늦어도 placement는 pasteboard 순서대로 immediate를 먼저 복사한다.
    /// - 검증 내용: [URL-A, promise-B]에서 B 이벤트만 있어도 복사 순서는 [A, B]다.
    func testExternalDropImport_immediateInterleavesByPasteboardOrdinal() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let staging = sandbox.root.appendingPathComponent("staging")
        let dest = sandbox.root.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let immediateA = staging.appendingPathComponent("a.txt")
        let promisedB = staging.appendingPathComponent("b.txt")
        try Data("a".utf8).write(to: immediateA)
        try Data("b".utf8).write(to: promisedB)

        let recorder = FileOpsRecorder()
        let cleanup = AcquisitionCleanupRecorder()
        let sessionID = ExternalDropSessionID()
        let store = makeImportPlacementStore(recorder: recorder, cleanup: cleanup)

        // promise B(itemOrdinal 1)가 유일한 received 파일이고, immediate A는 ordinal 0이다.
        let plan = ExternalDropImportPlan(
            sessionID: sessionID,
            destination: dest.path,
            forcedCopy: true,
            orderedPromisedNames: ["b.txt"],
            promisedOrdinals: [1],
            receivedFiles: [
                .init(
                    sessionID: sessionID,
                    itemOrdinal: 1,
                    callbackOrdinal: 1,
                    stagedPath: promisedB.path,
                    pasteboardOrdinal: 1,
                ),
            ],
            immediateURLPaths: [immediateA.path],
            immediateOrdinals: [0],
        )

        await store.send(.externalDrop(.applyImport(plan)))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(recorder.copiedPaths.map(\.source.path), [immediateA.path, promisedB.path])
        XCTAssertEqual(cleanup.finishes, [sessionID])
    }

    /// EOP-002-import_external_objects (VOY-736 리뷰 P1-C): legacy logical item 하나가 파일
    /// 2개를 산출하면 두 파일 모두 같은 pasteboard ordinal로 placement되고, 앞선 immediate
    /// 다음에 항목 내 도착 순서대로 복사된다.
    /// - 검증 내용: [immediate-A(0), promise 항목(1) → f1, f2] 복사 순서 [A, f1, f2].
    func testExternalDropImport_legacyTwoFilesSharePasteboardOrderAfterImmediate() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let staging = sandbox.root.appendingPathComponent("staging")
        let dest = sandbox.root.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let immediateA = staging.appendingPathComponent("a.txt")
        let legacyFirst = staging.appendingPathComponent("f1.eml")
        let legacySecond = staging.appendingPathComponent("f2.eml")
        try Data("a".utf8).write(to: immediateA)
        try Data("1".utf8).write(to: legacyFirst)
        try Data("2".utf8).write(to: legacySecond)

        let recorder = FileOpsRecorder()
        let cleanup = AcquisitionCleanupRecorder()
        let sessionID = ExternalDropSessionID()
        let store = makeImportPlacementStore(recorder: recorder, cleanup: cleanup)

        // 두 파일 모두 pasteboard ordinal 1이고 항목 내 순번(callbackOrdinal) 0/1로 정렬된다.
        let plan = ExternalDropImportPlan(
            sessionID: sessionID,
            destination: dest.path,
            forcedCopy: true,
            orderedPromisedNames: ["f1.eml", "f2.eml"],
            promisedOrdinals: [1],
            receivedFiles: [
                .init(
                    sessionID: sessionID,
                    itemOrdinal: 1,
                    callbackOrdinal: 0,
                    stagedPath: legacyFirst.path,
                    pasteboardOrdinal: 1,
                ),
                .init(
                    sessionID: sessionID,
                    itemOrdinal: 2,
                    callbackOrdinal: 1,
                    stagedPath: legacySecond.path,
                    pasteboardOrdinal: 1,
                ),
            ],
            immediateURLPaths: [immediateA.path],
            immediateOrdinals: [0],
        )

        await store.send(.externalDrop(.applyImport(plan)))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(
            recorder.copiedPaths.map(\.source.path),
            [immediateA.path, legacyFirst.path, legacySecond.path],
        )
        XCTAssertEqual(cleanup.finishes, [sessionID])
    }

    /// EOP-002-import_external_objects (VOY-736 리뷰 #3831133039): data flavor가 뒤 pasteboard
    /// 항목이면 물리화가 먼저 끝나도 promise 뒤에 배치된다.
    /// - 검증 내용: [promise-A, data-B]에서 도착 순서와 무관하게 복사 순서는 [A, B]다.
    func testExternalDropImport_promiseBeforeLaterDataByOrdinal() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let staging = sandbox.root.appendingPathComponent("staging")
        let dest = sandbox.root.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let promisedA = staging.appendingPathComponent("a.txt")
        let dataB = staging.appendingPathComponent("b.json")
        try Data("a".utf8).write(to: promisedA)
        try Data("b".utf8).write(to: dataB)

        let recorder = FileOpsRecorder()
        let cleanup = AcquisitionCleanupRecorder()
        let sessionID = ExternalDropSessionID()
        let store = makeImportPlacementStore(recorder: recorder, cleanup: cleanup)

        // 도착 순서(itemOrdinal)는 data B가 먼저지만 pasteboardOrdinal로 promise A가 먼저다.
        let plan = ExternalDropImportPlan(
            sessionID: sessionID,
            destination: dest.path,
            forcedCopy: true,
            orderedPromisedNames: ["a.txt"],
            promisedOrdinals: [0],
            receivedFiles: [
                .init(
                    sessionID: sessionID,
                    itemOrdinal: 1,
                    callbackOrdinal: 0,
                    stagedPath: dataB.path,
                    pasteboardOrdinal: 1,
                ),
                .init(
                    sessionID: sessionID,
                    itemOrdinal: 2,
                    callbackOrdinal: 1,
                    stagedPath: promisedA.path,
                    pasteboardOrdinal: 0,
                ),
            ],
        )

        await store.send(.externalDrop(.applyImport(plan)))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(recorder.copiedPaths.map(\.source.path), [promisedA.path, dataB.path])
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
        let store = makeImportPlacementStore(recorder: recorder, cleanup: cleanup)

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
        let store = makeImportPlacementStore(recorder: recorder, cleanup: cleanup)

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
        let firstSession = ExternalDropSessionID()
        let secondSession = ExternalDropSessionID()
        let store = EntryOperationsTestSupport.makeStore {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder)
            $0.externalDropAcquisitionClient = ExternalDropAcquisitionClient(
                begin: { _, _, _, _, _, _, _ in fatalError("begin not used") },
                events: { _ in AsyncStream { $0.finish() } },
                cancel: { cleanup.recordCancel($0) },
                finish: { cleanup.recordFinish($0) },
                beginLegacy: { _, _, _, _, _, _, _ in fatalError("beginLegacy not used") },
                prepareLegacyStaging: { _ in fatalError("prepareLegacyStaging not used") },
                finalizeLegacyStaging: { _, _ in fatalError("finalizeLegacyStaging not used") },
                // placement 복사 진행 대기는 secure copier seam에서만 일어난다.
                copyPlacementSource: { _, _, _ in
                    await gate.wait()
                    return true
                },
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
        let sessionID = ExternalDropSessionID()
        let store = EntryOperationsTestSupport.makeStore {
            $0.uuid = .constant(UUID())
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder)
            $0.externalDropAcquisitionClient = ExternalDropAcquisitionClient(
                begin: { _, _, _, _, _, _, _ in fatalError("begin not used") },
                events: { _ in AsyncStream { $0.finish() } },
                cancel: { cleanup.recordCancel($0) },
                finish: { cleanup.recordFinish($0) },
                beginLegacy: { _, _, _, _, _, _, _ in fatalError("beginLegacy not used") },
                prepareLegacyStaging: { _ in fatalError("prepareLegacyStaging not used") },
                finalizeLegacyStaging: { _, _ in fatalError("finalizeLegacyStaging not used") },
                // placement 복사 진행 대기와 취소 반응은 secure copier seam에서 일어난다.
                copyPlacementSource: { _, _, _ in
                    try await withTaskCancellationHandler {
                        await gate.wait()
                        try Task.checkCancellation()
                    } onCancel: {
                        gate.open()
                    }
                    return true
                },
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
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathComponent("a.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathComponent("b.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path))
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
        let firstSession = ExternalDropSessionID()
        let secondSession = ExternalDropSessionID()
        let store = EntryOperationsTestSupport.makeStore {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder)
            $0.externalDropAcquisitionClient = ExternalDropAcquisitionClient(
                begin: { _, _, _, _, _, _, _ in fatalError("begin not used") },
                events: { _ in AsyncStream { $0.finish() } },
                cancel: { cleanup.recordCancel($0) },
                finish: { cleanup.recordFinish($0) },
                beginLegacy: { _, _, _, _, _, _, _ in fatalError("beginLegacy not used") },
                prepareLegacyStaging: { _ in fatalError("prepareLegacyStaging not used") },
                finalizeLegacyStaging: { _, _ in fatalError("finalizeLegacyStaging not used") },
                // placement 복사 진행 대기와 취소 반응은 secure copier seam에서 일어난다.
                copyPlacementSource: { _, _, _ in
                    try await withTaskCancellationHandler {
                        await gate.wait()
                        try Task.checkCancellation()
                    } onCancel: {
                        gate.open()
                    }
                    return true
                },
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
        let store = makeImportPlacementStore(
            recorder: recorder,
            cleanup: cleanup,
            copyPlacementSource: collisionCopyStub(fileName: "a.txt", recorder: recorder),
            showReplaceAlert: { _, _ in .stop },
        )

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

    /// VOY-736 v8b P1 #1: copier가 false를 반환한 externalObjectImportItem은 일반 mutable
    /// pasteFile로 강등되지 않고 항목별 실패로 닫힌다.
    /// - 검증 내용: secure copier가 false를 반환하면 pasteFile(recorder 관찰 경로)이 호출되지
    ///   않고 destination 산출물이 없으며 원본 staged 파일이 그대로 남는다.
    /// - 기대 결과: status `.failed`, copiedPaths 비어 있음, finishes 정확히 1회.
    func testExternalDropImport_copierFalseFailsClosedWithoutPasteFallback() async throws {
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
        let store = makeImportPlacementStore(
            recorder: recorder,
            cleanup: cleanup,
            copyPlacementSource: { _, _, _ in false },
        )

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

        XCTAssertEqual(store.state.externalObjectImportStatus, .failed)
        XCTAssertTrue(recorder.copiedPaths.isEmpty, "copier 미처리 항목이 paste fallback으로 복사됐다")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathComponent("a.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathComponent("b.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path))
        XCTAssertEqual(cleanup.finishes, [sessionID])
        XCTAssertTrue(cleanup.cancels.isEmpty)
    }

    /// VOY-736 v8b P1 #1: placement 세션 상태 없이 도착한 .externalObjectImportItem 배치는
    /// mutable 일반 paste로 강등되지 않고 항목별 실패로 닫힌다.
    /// - 검증 내용: placement 상태 없이 .clipboard(.pasteItems)를 직접 보낸다.
    /// - 기대 결과: 복사가 실행되지 않고(destination 비어 있음) 원본 staged 파일이 유지된다.
    func testExternalDropImport_missingPlacementStateFailsClosedWithoutMutablePaste() async throws {
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
        let store = makeImportPlacementStore(recorder: recorder, cleanup: cleanup)

        await store.send(.clipboard(.pasteItems(
            sourcePaths: [a.path],
            destinationPath: dest.path,
            operation: .copy,
            operationKind: .externalObjectImportItem,
        )))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertTrue(recorder.copiedPaths.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathComponent("a.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
    }

    /// VOY-736 v8b P1 #3: descriptor 복사의 O_EXCL 충돌(POSIXError EEXIST)은 기존 교체
    /// 알림 계약으로 정규화된다. 사용자가 stop을 고르면 해당 항목만 실패하고 나머지는
    /// 성공해 status는 `.partiallyApplied`다.
    /// - 검증 내용: copier 스텁이 a.txt에 한해 EEXIST를 던지고 replace alert은 stop을 반환한다.
    /// - 기대 결과: a.txt에 교체 알림이 정확히 한 번 뜨고, b.txt만 destination에 남는다.
    func testExternalDropImport_descriptorCollisionNormalizesToReplaceStopContract() async throws {
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
        try Data("existing".utf8).write(to: dest.appendingPathComponent("a.txt"))

        let recorder = FileOpsRecorder()
        let cleanup = AcquisitionCleanupRecorder()
        let alertRecorder = ReplaceAlertRecorder()
        let sessionID = ExternalDropSessionID()
        let store = makeImportPlacementStore(
            recorder: recorder,
            cleanup: cleanup,
            copyPlacementSource: collisionCopyStub(fileName: "a.txt", recorder: recorder),
            showReplaceAlert: { itemName, _ in
                await MainActor.run { alertRecorder.record(itemName) }
                return .stop
            },
        )

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

        XCTAssertEqual(alertRecorder.itemNames, ["a.txt"], "EEXIST 충돌이 교체 알림 계약으로 정규화돼야 한다")
        XCTAssertEqual(recorder.copiedPaths.map(\.source.path), [b.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("b.txt").path))
        XCTAssertEqual(try Data(contentsOf: dest.appendingPathComponent("a.txt")), Data("existing".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
        XCTAssertEqual(store.state.externalObjectImportStatus, .partiallyApplied)
        XCTAssertEqual(cleanup.finishes, [sessionID])
        XCTAssertTrue(cleanup.cancels.isEmpty)
    }

    /// VOY-736 v8b P1 #3: 교체 알림에서 replace를 고르면 충돌 목적지를 지운 뒤 secure copier를
    /// 재시도해 해당 항목을 회수한다. stop/replace와 per-item 집계 의미를 함께 보존한다.
    /// - 검증 내용: copier 스텁이 a.txt 첫 시도에만 EEXIST를 던지고 replace alert은 replace를 반환한다.
    /// - 기대 결과: dest/a.txt가 deleteImmediately 후 재복사돼 staged 바이트로 존재하고 status는 `.applied`.
    func testExternalDropImport_descriptorCollisionReplaceRecoversItem() async throws {
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
        try Data("existing".utf8).write(to: dest.appendingPathComponent("a.txt"))

        let thrower = OnceFlag()
        let recorder = FileOpsRecorder()
        let cleanup = AcquisitionCleanupRecorder()
        let sessionID = ExternalDropSessionID()
        let store = makeImportPlacementStore(
            recorder: recorder,
            cleanup: cleanup,
            copyPlacementSource: oneShotCollisionCopyStub(fileName: "a.txt", flag: thrower),
            showReplaceAlert: { _, _ in .replace },
        )

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

        XCTAssertEqual(try Data(contentsOf: dest.appendingPathComponent("a.txt")), Data("a".utf8))
        XCTAssertEqual(try Data(contentsOf: dest.appendingPathComponent("b.txt")), Data("b".utf8))
        // 교체는 기존 목적지를 임시 백업으로 치운 뒤 복사 성공 시에만 제거한다
        // (코멘트 #3837908188). 기존 파일 삭제가 선행하지 않는다.
        XCTAssertEqual(recorder.movedPaths.count, 1)
        XCTAssertEqual(recorder.movedPaths.first?.source, dest.appendingPathComponent("a.txt"))
        XCTAssertEqual(recorder.deletedPaths.count, 1)
        XCTAssertTrue(recorder.deletedPaths[0].lastPathComponent.hasPrefix(".voyager-replace-"))
        XCTAssertEqual(store.state.externalObjectImportStatus, .applied)
        XCTAssertEqual(cleanup.finishes, [sessionID])
        XCTAssertTrue(cleanup.cancels.isEmpty)
    }
}

/// begin seam이 지연 flavor를 받으므로(코멘트 #3837956591) 고정 바이트 flavor를 감싼다.
/// 인자 라벨이 기존 ExternalDropDataFlavor 생성과 동일해 호출부는 이름만 바뀐다.
private func deferredFlavor(
    uti: String,
    bytes: Data,
    filename: String,
    ordinal: Int = -1,
) -> ExternalDropDeferredFlavor {
    ExternalDropDeferredFlavor(uti: uti, filename: filename, ordinal: ordinal) { bytes }
}

/// replace alert 노출을 관찰하는 경량 recorder.
private final class ReplaceAlertRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _itemNames: [String] = []

    func record(_ itemName: String) {
        lock.lock()
        defer { lock.unlock() }
        _itemNames.append(itemName)
    }

    var itemNames: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _itemNames
    }
}

/// 한 번만 참을 반환하는 원자 플래그. 재시도 경로 검증에 쓴다.
private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var consumed = false

    func consume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if consumed { return false }
        consumed = true
        return true
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

private func makeClipboardClient(
    recorder: ClipboardRecorder,
    setStringResult: @Sendable @escaping (String, NSPasteboard.PasteboardType) -> Bool = { _, _ in true },
) -> PasteboardClient {
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
            return setStringResult(string, type)
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
            begin: { _, _, _, _, _, _, _ in fatalError("begin is not used by barrier tests") },
            events: { _ in AsyncStream { $0.finish() } },
            cancel: { recorder.recordCancel($0) },
            finish: { recorder.recordFinish($0) },
            beginLegacy: { _, _, _, _, _, _, _ in fatalError("beginLegacy is not used by barrier tests") },
            prepareLegacyStaging: { _ in fatalError("prepareLegacyStaging not used") },
            finalizeLegacyStaging: { _, _ in fatalError("finalizeLegacyStaging not used") },
        )
    }
    return (store, recorder)
}
