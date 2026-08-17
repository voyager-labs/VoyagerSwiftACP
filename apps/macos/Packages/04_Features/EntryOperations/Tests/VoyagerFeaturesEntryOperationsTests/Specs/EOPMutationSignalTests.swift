import ComposableArchitecture
import Foundation
@testable import VoyagerFeaturesEntryOperations
import XCTest

extension EOP002ArrangeEntriesTests {
    /// EOP-002-create_new_folder: 생성 성공은 새 target path를 유일한 mutation signal로 보낸다.
    func testCreateFolderEmitsAffectedPathSignal() async {
        let store = EntryOperationsTestSupport.makeStore {
            $0.entryFileOpsClient.createFolder = { _, _ in }
        }
        store.exhaustivity = .off

        await store.send(.edit(.createNewFolder(parentPath: "/root", siblingNames: [])))
        await store.receive { action in
            guard case .lifecycle(.operationStarted) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case let .lifecycle(.pathsMutated(paths)) = action else { return false }
            return paths == ["/root/untitled folder"]
        }
        await store.receive { action in
            guard case .lifecycle(.operationFinished) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case .lifecycle(.entryActionCompleted) = action else { return false }
            return true
        }
        await store.finish()
    }

    /// EOP-002-paste_entries: copy와 move는 source/destination pair를 한 번만 signal로 보낸다.
    func testCopyAndMoveEmitSourceAndDestinationSignals() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }
        let destination = sandbox.root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let copySource = sandbox.root.appendingPathComponent("copy.txt")
        let moveSource = sandbox.root.appendingPathComponent("move.txt")
        try FileManager.default.copyItem(at: sandbox.fileURL, to: copySource)
        try FileManager.default.copyItem(at: sandbox.fileURL, to: moveSource)

        for (source, operation, operationKind) in [
            (copySource, ClipboardOperation.copy, OperationKind.pasteFileCopy),
            (moveSource, ClipboardOperation.cut, OperationKind.pasteFileMove),
        ] {
            let target = destination.appendingPathComponent(source.lastPathComponent)
            let store = EntryOperationsTestSupport.makeStore {
                $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: FileOpsRecorder())
            }
            store.exhaustivity = .off

            await store.send(.clipboard(.pasteItems(
                sourcePaths: [source.path],
                destinationPath: target.deletingLastPathComponent().path,
                operation: operation,
                operationKind: operationKind,
            )))
            await store.receive { action in
                guard case .lifecycle(.operationStarted) = action else { return false }
                return true
            }
            await store.receive { action in
                guard case let .lifecycle(.pathsMutated(paths)) = action else { return false }
                return paths == [source.path, target.path]
            }
            await store.receive { action in
                guard case .lifecycle(.operationFinished) = action else { return false }
                return true
            }
            await store.receive { action in
                guard case .lifecycle(.entryActionCompleted) = action else { return false }
                return true
            }
            await store.finish()
        }
    }
}

extension EOP003ManageEntryLifecycleTests {
    /// EOP-003-delete_entries_immediately: 삭제 성공은 삭제된 source path를 mutation signal로 보낸다.
    func testDeleteEmitsAffectedPathSignal() async {
        let store = EntryOperationsTestSupport.makeStore {
            $0.entryFileOpsClient.deleteImmediately = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.trash(.deleteImmediatelyConfirmed(paths: ["/root/deleted"])))
        await store.receive { action in
            guard case .lifecycle(.operationStarted) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case let .lifecycle(.pathsMutated(paths)) = action else { return false }
            return paths == ["/root/deleted"]
        }
        await store.receive { action in
            guard case .lifecycle(.operationFinished) = action else { return false }
            return true
        }
        await store.finish()
    }

    /// EOP-003-move_entries_to_trash: trash 이동은 original/trash pair를 signal로 보낸다.
    func testTrashEmitsOriginalAndTrashAffectedPathSignal() async {
        let store = EntryOperationsTestSupport.makeStore {
            $0.entryFileOpsClient.moveToTrashAndReturnURL = { _ in URL(fileURLWithPath: "/trash/deleted") }
        }
        store.exhaustivity = .off

        await store.send(.trash(.moveToTrash(paths: ["/root/deleted"])))
        await store.receive { action in
            guard case .lifecycle(.operationStarted) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case let .lifecycle(.pathsMutated(paths)) = action else { return false }
            return paths == ["/root/deleted", "/trash/deleted"]
        }
        await store.receive { action in
            guard case .lifecycle(.operationFinished) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case .lifecycle(.entryActionCompleted) = action else { return false }
            return true
        }
        await store.finish()
    }

    /// EOP-003-undo_entry_action: undo와 redo replay는 before/after pair를 signal로 보낸다.
    func testTrashUndoAndRedoEmitAffectedPathSignals() async {
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/root/old", afterPath: "/root/new")],
        )

        for direction in [EntryActionDirection.undo, .redo] {
            let store = EntryOperationsTestSupport.makeStore {
                $0.entryFileOpsClient.renameFile = { _, _ in }
            }
            store.exhaustivity = .off

            await store.send(.undoRedo(.replayEntryAction(direction: direction, record: record)))
            await store.receive { action in
                guard case .lifecycle(.operationStarted) = action else { return false }
                return true
            }
            await store.receive { action in
                guard case let .lifecycle(.pathsMutated(paths)) = action else { return false }
                return paths == ["/root/old", "/root/new"]
            }
            await store.receive { action in
                guard case .lifecycle(.operationFinished) = action else { return false }
                return true
            }
            await store.receive { action in
                guard case let .undoRedo(.replaySucceeded(
                    replayDirection,
                    sourceRecordID,
                    updatedRecord,
                )) = action else { return false }
                return replayDirection == direction
                    && sourceRecordID == record.id
                    && updatedRecord.targets == record.targets
            }
            await store.receive { action in
                guard case let .outcome(.entryActionReplayFinished(
                    replayDirection,
                    terminal: .failure(reason: reason, appliedTargets: appliedTargets),
                )) = action else { return false }
                return replayDirection == direction
                    && reason == .ownerRecordMismatch
                    && appliedTargets.isEmpty
            }
            await store.finish()
        }
    }
}

extension EOP004EditEntryMetadataTests {
    /// EOP-004-rename_entry: rename 성공은 old/new path를 하나의 mutation signal로 보낸다.
    func testRenameEmitsOldAndNewAffectedPathSignal() async {
        let store = EntryOperationsTestSupport.makeStore {
            $0.entryFileOpsClient.renameFile = { _, _ in }
        }
        store.exhaustivity = .off

        await store.send(.edit(.renameItem(oldPath: "/root/old", newPath: "/root/new")))
        await store.receive { action in
            guard case .lifecycle(.operationStarted) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case let .lifecycle(.pathsMutated(paths)) = action else { return false }
            return paths == ["/root/old", "/root/new"]
        }
        await store.receive { action in
            guard case .lifecycle(.operationFinished) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case .lifecycle(.entryActionCompleted) = action else { return false }
            return true
        }
        await store.finish()
    }
}
