// FLOW-ID: eop.manage_entry_lifecycle
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
@testable import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerShared
import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class ManageEntryLifecycleFlowTests: XCTestCase {
    // FLOW-PATH: happy_path.move_to_trash

    /// EOP-003-move_entries_to_trash: FileManagerContentFeature composition으로 moveSelectedItemsToTrash가
    /// 실제 trash 이동, undo record 생성, page identity 유지를 함께 완료한다.
    /// 사용자 키보드 명령이 bridge reducer를 거쳐 live trash effect, lifecycle completion, coordinator sync까지
    /// 도달하는 실제 사용자 경로를 검증한다.
    /// - 검증 내용: `.entryViewLayout(.delegate(.executeCommand("mutation.moveSelectedItemsToTrash")))`가
    ///   composed reducer를 지나 live trash effect와 undo record 생성을 완료한다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt` sandbox copy와 선택된 source entry가 있다.
    /// - 기대 결과: source 파일은 사라지고 trash 경로에 나타나며 undoRecords가 비어있지 않고
    ///   canUndoEntryAction이 true이며 page navigation identity는 유지된다.
    func testMoveSelectedItemsToTrashThroughProductionComposition() async throws {
        let sandbox = try EntryMutationFixtureSandbox.copyingFile(
            from: "fixtures/fixtures/texts/plain/11.txt",
        )
        defer { sandbox.cleanup() }

        let trashRoot = sandbox.root.appendingPathComponent(".Trash")
        try FileManager.default.createDirectory(at: trashRoot, withIntermediateDirectories: true)
        let sourceEntry = makeEntry(at: sandbox.fileURL, isFolder: false)
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(sandbox.root.path)
        state.entryViewLayout.entryOperations.items = [sourceEntry]
        state.entryViewLayout.entries = [sourceEntry]
        state.entryViewLayout.selectedIds = [sourceEntry.id]
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.entryFileOpsClient = makeLocalTrashClient(trashRoot: trashRoot)
            $0.trashMetadataStoreClient = .testValue
            $0.entryOperationSoundClient = .testValue
            $0.undoManagerClient = .init(
                registerUndo: { _, _, _ in },
                undo: { _, _ in .init(didInvoke: false, availability: .init()) },
                redo: { _, _ in .init(didInvoke: false, availability: .init()) },
            )
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(.coreFinished(batchCount: 0))
                    continuation.finish()
                }
            }
            $0.userDefaultsClient.setString = { _, _ in }
        }
        // store.exhaustivity = .off: flow는 내부 lifecycle action보다 실제 trash 이동과 page identity를 검증한다.
        store.exhaustivity = .off
        let initialRoute = store.state.navigation.navigationState
        let initialHistory = store.state.navigation.backHistory

        await store.send(.entryViewLayout(.delegate(.executeCommand("mutation.moveSelectedItemsToTrash"))))
        await store.finish()
        await store.skipReceivedActions()

        let trashPath = trashRoot.appendingPathComponent(sandbox.fileURL.lastPathComponent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashPath.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
        XCTAssertEqual(store.state.navigation.navigationState, initialRoute)
        XCTAssertEqual(store.state.navigation.backHistory, initialHistory)
        XCTAssertFalse(
            store.state.entryViewLayout.entryOperations.undoRecords.isEmpty,
            "move-to-trash must produce an undo record",
        )
        XCTAssertTrue(store.state.entryViewLayout.entryOperations.canUndoEntryAction)
        XCTAssertTrue(store.state.entryViewLayout.entryOperations.restorableTrashPaths.contains(trashPath.path))
    }

    // FLOW-PATH: happy_path.undo_restores_source

    /// EOP-003-undo_entry_action: parent undo가 trash 파일을 원래 위치로 복구한다.
    /// 사용자가 Cmd+Z로 trash 이동을 취소할 때 EntryOperationsFeature의 undoEntryAction이
    /// 실제 파일을 원래 경로로 되돌리고 undo/redo stack을 갱신하는지 검증한다.
    /// - 검증 내용: `.entryOperations(.undoRedo(.undoEntryAction(record)))`가 trash 파일을
    ///   원래 경로로 복구하고 undo stack을 pop하며 redo stack에 push한다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt` sandbox copy가 trash로 이동된 상태에서
    ///   matching undo record가 store state에 존재한다.
    /// - 기대 결과: trash 파일이 원래 경로로 복귀하고 undoRecords는 비워지며 redoRecords에 기록이 남는다.
    func testUndoRestoresTrashedEntryThroughEntryOperations() async throws {
        let sandbox = try EntryMutationFixtureSandbox.copyingFile(
            from: "fixtures/fixtures/texts/plain/11.txt",
        )
        defer { sandbox.cleanup() }

        let trashRoot = sandbox.root.appendingPathComponent(".Trash")
        try FileManager.default.createDirectory(at: trashRoot, withIntermediateDirectories: true)
        let sourceEntry = makeEntry(at: sandbox.fileURL, isFolder: false)
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(sandbox.root.path)
        state.entryViewLayout.entryOperations.items = [sourceEntry]
        state.entryViewLayout.entries = [sourceEntry]
        state.entryViewLayout.selectedIds = [sourceEntry.id]
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.entryFileOpsClient = makeLocalTrashClient(trashRoot: trashRoot)
            $0.trashMetadataStoreClient = .testValue
            $0.entryOperationSoundClient = .testValue
            $0.undoManagerClient = .init(
                registerUndo: { _, _, _ in },
                undo: { _, _ in .init(didInvoke: false, availability: .init()) },
                redo: { _, _ in .init(didInvoke: false, availability: .init()) },
            )
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(.coreFinished(batchCount: 0))
                    continuation.finish()
                }
            }
            $0.userDefaultsClient.setString = { _, _ in }
        }
        store.exhaustivity = .off

        // 1. Move to trash
        await store.send(.entryViewLayout(.delegate(.executeCommand("mutation.moveSelectedItemsToTrash"))))
        await store.finish()
        await store.skipReceivedActions()

        let trashPath = trashRoot.appendingPathComponent(sandbox.fileURL.lastPathComponent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashPath.path))

        let undoRecord = try XCTUnwrap(store.state.entryViewLayout.entryOperations.undoRecords.last)
        XCTAssertEqual(undoRecord.operationKind, .moveToTrash)

        // 2. Undo the trash operation
        await store.send(.entryViewLayout(.entryOperations(.undoRedo(.undoEntryAction(undoRecord)))))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: trashPath.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
        XCTAssertEqual(store.state.entryViewLayout.entryOperations.undoRecords.count, 0)
        XCTAssertEqual(store.state.entryViewLayout.entryOperations.redoRecords.count, 1)
        XCTAssertEqual(store.state.entryViewLayout.entryOperations.redoRecords.first?.id, undoRecord.id)
    }

    // FLOW-PATH: denial.move_to_trash_fails_preserves_file

    /// EOP-003-move_entries_to_trash: injected trash client failure는 source를 보존하고 undo를 생성하지 않는다.
    /// trash 이동이 OS 권한 문제나 disk 오류로 실패할 때 파일이 그대로 유지되고
    /// undo record가 생성되지 않으며 page identity가 유지되는지 검증한다.
    /// - 검증 내용: `moveToTrashAndReturnURL`이 throw할 때 source가 그대로 유지되고
    ///   undoRecords와 restorableTrashPaths가 비어있다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt` sandbox copy와
    ///   throw하는 moveToTrashAndReturnURL이 주입된 store.
    /// - 기대 결과: source 파일이 그대로 있고 undoRecords, restorableTrashPaths가 비어있다.
    func testTrashClientFailurePreservesSourceAndDoesNotCreateUndo() async throws {
        let sandbox = try EntryMutationFixtureSandbox.copyingFile(
            from: "fixtures/fixtures/texts/plain/11.txt",
        )
        defer { sandbox.cleanup() }

        let sourceEntry = makeEntry(at: sandbox.fileURL, isFolder: false)
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath(sandbox.root.path)
        state.entryViewLayout.entryOperations.items = [sourceEntry]
        state.entryViewLayout.entries = [sourceEntry]
        state.entryViewLayout.selectedIds = [sourceEntry.id]
        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.entryFileOpsClient = makeFailingTrashClient()
            $0.trashMetadataStoreClient = .testValue
            $0.entryOperationSoundClient = .testValue
            $0.undoManagerClient = .init(
                registerUndo: { _, _, _ in },
                undo: { _, _ in .init(didInvoke: false, availability: .init()) },
                redo: { _, _ in .init(didInvoke: false, availability: .init()) },
            )
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(.coreFinished(batchCount: 0))
                    continuation.finish()
                }
            }
            $0.userDefaultsClient.setString = { _, _ in }
        }
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.delegate(.executeCommand("mutation.moveSelectedItemsToTrash"))))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
        XCTAssertTrue(store.state.entryViewLayout.entryOperations.undoRecords.isEmpty)
        XCTAssertTrue(store.state.entryViewLayout.entryOperations.restorableTrashPaths.isEmpty)
    }

    // MARK: - Helpers

    private func makeEntry(at url: URL, isFolder: Bool) -> EntryModel {
        EntryModel(
            name: url.lastPathComponent,
            fullPath: url.path,
            isFolder: isFolder,
            isHidden: false,
            size: 0,
            modifiedDate: Date(timeIntervalSince1970: 0),
            fileExtension: url.pathExtension,
            facets: .init(
                createdDate: Date(timeIntervalSince1970: 0),
                addedDate: Date(timeIntervalSince1970: 0),
                lastOpenedDate: nil,
                kind: isFolder ? "Folder" : "Plain Text",
                creatorApplication: nil,
                tags: [],
                supplementaryMetadata: nil,
            ),
        )
    }
}

// MARK: - Local Trash Client

/// EntryFileOpsClient를 live client에 위임하되, `moveToTrashAndReturnURL`과 `putBackFromTrash`를
/// 지정된 `trashRoot` 경로로 라우팅한다.
private func makeLocalTrashClient(trashRoot: URL) -> EntryFileOpsClient {
    let live = EntryFileOpsClient.liveValue
    return EntryFileOpsClient(
        createFolder: { parentURL, folderName in try await live.createFolder(parentURL, folderName) },
        pasteFile: { sourceURL, destinationURL in try await live.pasteFile(sourceURL, destinationURL) },
        moveFile: { sourceURL, destinationURL in try await live.moveFile(sourceURL, destinationURL) },
        renameFile: { sourceURL, destinationURL in try await live.renameFile(sourceURL, destinationURL) },
        createAlias: { sourceURL, aliasURL in try await live.createAlias(sourceURL, aliasURL) },
        moveToTrashAndReturnURL: { sourceURL in
            try FileManager.default.createDirectory(at: trashRoot, withIntermediateDirectories: true)
            let trashURL = trashRoot.appendingPathComponent(sourceURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: trashURL.path) {
                try FileManager.default.removeItem(at: trashURL)
            }
            try FileManager.default.moveItem(at: sourceURL, to: trashURL)
            return trashURL
        },
        deleteImmediately: { url in try await live.deleteImmediately(url) },
        putBackFromTrash: { trashURL, originalPath in
            let originalURL = URL(fileURLWithPath: originalPath)
            try FileManager.default.moveItem(at: trashURL, to: originalURL)
        },
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
        clipboardChangeCount: { live.clipboardChangeCount() },
        loadClipboardCutSessionId: { live.loadClipboardCutSessionId() },
        saveClipboardCutSessionId: { sessionID in live.saveClipboardCutSessionId(sessionID) },
        loadClipboardPaths: { live.loadClipboardPaths() },
        postFileSystemChanged: { _ in },
    )
}

/// EntryFileOpsClient를 live client에 위임하되, `moveToTrashAndReturnURL`만 throw하는 client.
private func makeFailingTrashClient() -> EntryFileOpsClient {
    let live = EntryFileOpsClient.liveValue
    return EntryFileOpsClient(
        createFolder: { parentURL, folderName in try await live.createFolder(parentURL, folderName) },
        pasteFile: { sourceURL, destinationURL in try await live.pasteFile(sourceURL, destinationURL) },
        moveFile: { sourceURL, destinationURL in try await live.moveFile(sourceURL, destinationURL) },
        renameFile: { sourceURL, destinationURL in try await live.renameFile(sourceURL, destinationURL) },
        createAlias: { sourceURL, aliasURL in try await live.createAlias(sourceURL, aliasURL) },
        moveToTrashAndReturnURL: { _ in throw FileOpError.system(message: "trash unavailable") },
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
        clipboardChangeCount: { live.clipboardChangeCount() },
        loadClipboardCutSessionId: { live.loadClipboardCutSessionId() },
        saveClipboardCutSessionId: { sessionID in live.saveClipboardCutSessionId(sessionID) },
        loadClipboardPaths: { live.loadClipboardPaths() },
        postFileSystemChanged: { _ in },
    )
}
