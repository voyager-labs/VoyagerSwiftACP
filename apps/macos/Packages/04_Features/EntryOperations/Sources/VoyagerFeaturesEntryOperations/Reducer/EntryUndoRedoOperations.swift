// swiftlint:disable file_length
import ComposableArchitecture
import Foundation
import OSLog
import VoyagerEntitiesEntry
import VoyagerEntitiesTag

@Reducer
struct EntryUndoRedoOperationsReducer { // swiftlint:disable:this type_body_length
    typealias State = EntryOperationsState
    typealias Action = EntryOperationsAction

    @Dependency(\.entryFileOpsClient)
    var entryFileOpsClient
    @Dependency(\.undoManagerClient)
    var undoManagerClient
    @Dependency(\.trashMetadataStoreClient)
    var trashMetadataStoreClient

    private struct EntryActionOperation {
        let operationPath: String
        let operationKind: OperationKind
        let perform: @Sendable () async throws -> EntryActionRecord.Target
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .lifecycle(.entryActionCompleted(record: record)):
                guard record.operationKind.isUndoable else {
                    return .none
                }
                state.appendUndoRecord(record)

                let windowID = state.windowID
                return .run { [record] send in
                    await undoManagerClient.registerUndo(
                        windowID,
                        record,
                        { record in
                            await send(.undoRedo(.undoEntryAction(record)))
                        },
                        { record in
                            await send(.undoRedo(.redoEntryAction(record)))
                        },
                    )
                }

            case .undoRedo(.requestUndo):
                guard let record = state.latestUndoRecord else {
                    Self.logger.error("Undo unavailable: no record")
                    return .none
                }
                guard !state.isEntryActionBusy(record) else {
                    Self.logger.error("Undo unavailable: target is busy")
                    return .none
                }

                let windowID = state.windowID
                return .run { _ in
                    await undoManagerClient.undo(windowID)
                }

            case .undoRedo(.requestRedo):
                guard let record = state.latestRedoRecord else {
                    Self.logger.error("Redo unavailable: no record")
                    return .none
                }
                guard !state.isEntryActionBusy(record) else {
                    Self.logger.error("Redo unavailable: target is busy")
                    return .none
                }

                let windowID = state.windowID
                return .run { _ in
                    await undoManagerClient.redo(windowID)
                }

            case let .undoRedo(.undoEntryAction(record: record)):
                guard let latestRecord = state.latestUndoRecord, latestRecord.id == record.id else {
                    Self.logger.error("Undo unavailable: latest record mismatch")
                    return .none
                }
                guard !state.isEntryActionBusy(record) else {
                    Self.logger.error("Undo unavailable: target is busy")
                    return .none
                }

                _ = state.undoRecords.popLast()
                state.redoRecords.append(latestRecord)
                return .send(.undoRedo(.replayEntryAction(direction: .undo, record: latestRecord)))

            case let .undoRedo(.redoEntryAction(record: record)):
                guard let latestRecord = state.latestRedoRecord, latestRecord.id == record.id else {
                    Self.logger.error("Redo unavailable: latest record mismatch")
                    return .none
                }
                guard !state.isEntryActionBusy(record) else {
                    Self.logger.error("Redo unavailable: target is busy")
                    return .none
                }

                _ = state.redoRecords.popLast()
                state.undoRecords.append(latestRecord)
                return .send(.undoRedo(.replayEntryAction(direction: .redo, record: latestRecord)))

            case let .undoRedo(.replayEntryAction(direction: direction, record: record)):
                return replayEntryAction(record, direction: direction)

            case let .undoRedo(.entryActionApplied(direction: direction, record: record)):
                switch direction {
                case .undo:
                    guard let recordIndex = state.redoRecords.firstIndex(where: { $0.id == record.id }) else {
                        Self.logger.error("Undo unavailable: failed to update stack")
                        return .none
                    }
                    state.redoRecords[recordIndex] = record
                    return .none

                case .redo:
                    guard let recordIndex = state.undoRecords.firstIndex(where: { $0.id == record.id }) else {
                        Self.logger.error("Redo unavailable: failed to update stack")
                        return .none
                    }
                    state.undoRecords[recordIndex] = record
                    return .none
                }

            case let .lifecycle(.operationFinished(path, kind, result)):
                switch (kind, result) {
                case (.pasteFileMove, .success):
                    guard state.clipboardOperation == .cut else {
                        return .none
                    }

                    state.clipboardItems.removeAll { $0 == path }
                    if var session = state.cutClearSession {
                        session.sourcePaths.removeAll { $0 == path }
                        state.cutClearSession = session.sourcePaths.isEmpty ? nil : session
                    }

                    guard state.clipboardItems.isEmpty else {
                        return .none
                    }

                    state.clipboardOperation = .copy
                    state.cutClearSession = nil
                    return .send(.clipboard(.setClipboardOperation(operation: .copy)))

                case (.deleteImmediately, .success):
                    guard state.pendingEmptyTrashItemCount > 0 else {
                        return .none
                    }

                    state.emptyTrashCompletedCount += 1
                    guard state.emptyTrashCompletedCount >= state.pendingEmptyTrashItemCount else {
                        return .none
                    }

                    state.pendingEmptyTrashItemCount = 0
                    state.emptyTrashCompletedCount = 0
                    return .send(.lifecycle(.emptyTrashCompleted))

                default:
                    return .none
                }

            default:
                return .none
            }
        }
    }

    private func replayEntryAction(
        _ record: EntryActionRecord,
        direction: EntryActionDirection,
    ) -> Effect<Action> {
        .run { send in
            do {
                let targets = try await applyEntryActionTargets(
                    record: record,
                    direction: direction,
                    send: send,
                )
                let updatedRecord = EntryActionRecord(
                    operationKind: record.operationKind,
                    targets: targets,
                    id: record.id,
                    timestamp: record.timestamp,
                )
                await send(.undoRedo(.entryActionApplied(direction: direction, record: updatedRecord)))
            } catch {
                Self.logger.error("Replay entry action failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func applyEntryActionTargets(
        record: EntryActionRecord,
        direction: EntryActionDirection,
        send: Send<Action>,
    ) async throws -> [EntryActionRecord.Target] {
        guard !record.targets.isEmpty else {
            throw FileOpError.system(message: "Entry action targets missing")
        }

        var updatedTargets: [EntryActionRecord.Target] = []

        for target in record.targets {
            let operation = try makeEntryActionOperation(
                record: record,
                target: target,
                direction: direction,
            )

            await send(.lifecycle(.operationStarted(operation.operationPath, operation.operationKind)))
            do {
                let updatedTarget = try await operation.perform()
                await send(.lifecycle(.pathsMutated([target.beforePath, target.afterPath].compactMap(\.self))))
                await send(.lifecycle(.operationFinished(
                    operation.operationPath,
                    operation.operationKind,
                    .success(()),
                )))
                updatedTargets.append(updatedTarget)
            } catch {
                let fileError = error.fileOpError
                await send(.lifecycle(.operationFinished(
                    operation.operationPath,
                    operation.operationKind,
                    .failure(fileError),
                )))
                throw fileError
            }
        }

        return updatedTargets
    }

    private func makeEntryActionOperation(
        record: EntryActionRecord,
        target: EntryActionRecord.Target,
        direction: EntryActionDirection,
    ) throws -> EntryActionOperation {
        switch record.operationKind {
        case .rename:
            try makeRenameOperation(target: target, direction: direction)

        case .pasteFileMove:
            try makeMoveOperation(target: target, direction: direction)

        case .pasteFileCopy, .pasteFileDuplicate:
            try makeCopyOperation(
                target: target,
                direction: direction,
                operationKind: record.operationKind,
            )

        case .createFolder:
            try makeCreateFolderOperation(target: target, direction: direction)

        case .createAlias:
            try makeCreateAliasOperation(target: target, direction: direction)

        case .moveToTrash:
            try makeMoveToTrashOperation(target: target, direction: direction)

        case .putBack:
            try makePutBackOperation(target: target, direction: direction)

        case .setTags:
            try makeSetTagsOperation(target: target, direction: direction)

        case .openDefault,
             .openWithApp,
             .setDefaultApp,
             .quickLook,
             .getInfo,
             .share,
             .performService,
             .revealInFinder,
             .deleteImmediately,
             .compress,
             .extract:
            throw FileOpError.system(message: "Unsupported undo operation kind")
        }
    }

    private func makeCreateAliasOperation(
        target: EntryActionRecord.Target,
        direction: EntryActionDirection,
    ) throws -> EntryActionOperation {
        switch direction {
        case .undo:
            let targetPath = try Self.requiredPath(target.afterPath, context: "undo create alias")
            return EntryActionOperation(
                operationPath: targetPath,
                operationKind: OperationKind.deleteImmediately,
                perform: {
                    try await entryFileOpsClient.deleteImmediately(URL(fileURLWithPath: targetPath))
                    return target
                },
            )
        case .redo:
            let sourcePath = try Self.requiredPath(target.beforePath, context: "redo create alias source")
            let aliasPath = try Self.requiredPath(target.afterPath, context: "redo create alias destination")
            return EntryActionOperation(
                operationPath: sourcePath,
                operationKind: OperationKind.createAlias,
                perform: {
                    try await entryFileOpsClient.createAlias(
                        URL(fileURLWithPath: sourcePath),
                        URL(fileURLWithPath: aliasPath),
                    )
                    return target
                },
            )
        }
    }

    private func makeRenameOperation(
        target: EntryActionRecord.Target,
        direction: EntryActionDirection,
    ) throws -> EntryActionOperation {
        let fromPath = try Self.requiredPath(
            direction == .undo ? target.afterPath : target.beforePath,
            context: "rename source",
        )
        let toPath = try Self.requiredPath(
            direction == .undo ? target.beforePath : target.afterPath,
            context: "rename destination",
        )
        return EntryActionOperation(
            operationPath: fromPath,
            operationKind: OperationKind.rename,
            perform: {
                try await entryFileOpsClient.renameFile(
                    URL(fileURLWithPath: fromPath),
                    URL(fileURLWithPath: toPath),
                )
                return target
            },
        )
    }

    private func makeMoveOperation(
        target: EntryActionRecord.Target,
        direction: EntryActionDirection,
    ) throws -> EntryActionOperation {
        let fromPath = try Self.requiredPath(
            direction == .undo ? target.afterPath : target.beforePath,
            context: "move source",
        )
        let toPath = try Self.requiredPath(
            direction == .undo ? target.beforePath : target.afterPath,
            context: "move destination",
        )
        return EntryActionOperation(
            operationPath: fromPath,
            operationKind: .pasteFileMove,
            perform: {
                try await entryFileOpsClient.moveFile(
                    URL(fileURLWithPath: fromPath),
                    URL(fileURLWithPath: toPath),
                )
                return target
            },
        )
    }

    private func makeCopyOperation(
        target: EntryActionRecord.Target,
        direction: EntryActionDirection,
        operationKind: OperationKind,
    ) throws -> EntryActionOperation {
        switch direction {
        case .undo:
            let targetPath = try Self.requiredPath(target.afterPath, context: "undo copy target")
            return EntryActionOperation(
                operationPath: targetPath,
                operationKind: OperationKind.deleteImmediately,
                perform: {
                    try await entryFileOpsClient.deleteImmediately(URL(fileURLWithPath: targetPath))
                    return target
                },
            )
        case .redo:
            let sourcePath = try Self.requiredPath(target.beforePath, context: "redo copy source")
            let targetPath = try Self.requiredPath(target.afterPath, context: "redo copy target")
            return EntryActionOperation(
                operationPath: sourcePath,
                operationKind: operationKind,
                perform: {
                    try await entryFileOpsClient.pasteFile(
                        URL(fileURLWithPath: sourcePath),
                        URL(fileURLWithPath: targetPath),
                    )
                    return target
                },
            )
        }
    }

    private func makeCreateFolderOperation(
        target: EntryActionRecord.Target,
        direction: EntryActionDirection,
    ) throws -> EntryActionOperation {
        switch direction {
        case .undo:
            let targetPath = try Self.requiredPath(target.afterPath, context: "undo create folder")
            return EntryActionOperation(
                operationPath: targetPath,
                operationKind: OperationKind.deleteImmediately,
                perform: {
                    try await entryFileOpsClient.deleteImmediately(URL(fileURLWithPath: targetPath))
                    return target
                },
            )
        case .redo:
            let targetPath = try Self.requiredPath(target.afterPath, context: "redo create folder")
            let targetURL = URL(fileURLWithPath: targetPath)
            let parentURL = targetURL.deletingLastPathComponent()
            let folderName = targetURL.lastPathComponent
            return EntryActionOperation(
                operationPath: parentURL.path,
                operationKind: OperationKind.createFolder,
                perform: {
                    try await entryFileOpsClient.createFolder(parentURL, folderName)
                    return target
                },
            )
        }
    }

    private func makeMoveToTrashOperation(
        target: EntryActionRecord.Target,
        direction: EntryActionDirection,
    ) throws -> EntryActionOperation {
        switch direction {
        case .undo:
            let trashPath = try Self.requiredPath(target.afterPath, context: "undo moveToTrash source")
            let originalPath = try Self.requiredPath(target.beforePath, context: "undo moveToTrash destination")
            return EntryActionOperation(
                operationPath: trashPath,
                operationKind: OperationKind.putBack,
                perform: {
                    try await entryFileOpsClient.putBackFromTrash(
                        URL(fileURLWithPath: trashPath),
                        originalPath,
                    )
                    return target
                },
            )
        case .redo:
            let originalPath = try Self.requiredPath(target.beforePath, context: "redo moveToTrash source")
            return EntryActionOperation(
                operationPath: originalPath,
                operationKind: OperationKind.moveToTrash,
                perform: {
                    let trashPath = try await moveItemToTrash(
                        path: originalPath,
                    )
                    return EntryActionRecord.Target(beforePath: originalPath, afterPath: trashPath)
                },
            )
        }
    }

    private func makePutBackOperation(
        target: EntryActionRecord.Target,
        direction: EntryActionDirection,
    ) throws -> EntryActionOperation {
        switch direction {
        case .undo:
            let originalPath = try Self.requiredPath(target.afterPath, context: "undo putBack source")
            return EntryActionOperation(
                operationPath: originalPath,
                operationKind: OperationKind.moveToTrash,
                perform: {
                    let trashPath = try await moveItemToTrash(
                        path: originalPath,
                    )
                    return EntryActionRecord.Target(beforePath: trashPath, afterPath: originalPath)
                },
            )
        case .redo:
            let trashPath = try Self.requiredPath(target.beforePath, context: "redo putBack source")
            let originalPath = try Self.requiredPath(target.afterPath, context: "redo putBack destination")
            return EntryActionOperation(
                operationPath: trashPath,
                operationKind: OperationKind.putBack,
                perform: {
                    try await entryFileOpsClient.putBackFromTrash(
                        URL(fileURLWithPath: trashPath),
                        originalPath,
                    )
                    return target
                },
            )
        }
    }

    private func makeSetTagsOperation(
        target: EntryActionRecord.Target,
        direction: EntryActionDirection,
    ) throws -> EntryActionOperation {
        let filePath = try Self.requiredPath(target.beforePath, context: "setTags target")
        let tags = try Self.requiredTags(
            direction == .undo ? target.beforeTags : target.afterTags,
            context: "setTags tags",
        )
        return EntryActionOperation(
            operationPath: filePath,
            operationKind: OperationKind.setTags,
            perform: {
                let url = URL(fileURLWithPath: filePath)
                try await entryFileOpsClient.setTags(url, tags)
                return target
            },
        )
    }

    private func moveItemToTrash(path: String) async throws -> String {
        let sourceURL = URL(fileURLWithPath: path)
        let trashURL = try await entryFileOpsClient.moveToTrashAndReturnURL(sourceURL)
        let metadata = TrashMetadata(
            trashPath: trashURL.path,
            originalPath: path,
            deletedDate: Date(),
        )
        await trashMetadataStoreClient.save(metadata)
        return trashURL.path
    }

    nonisolated private static let logger = Logger(
        subsystem: "fm.voyager",
        category: "entry-undo-redo-operations",
    )

    private static func requiredPath(_ path: String?, context: String) throws -> String {
        guard let path else {
            throw FileOpError.system(message: "Entry action path missing (\(context))")
        }
        return path
    }

    private static func requiredTags(_ tags: [String]?, context: String) throws -> [String] {
        guard let tags else {
            throw FileOpError.system(message: "Entry action tags missing (\(context))")
        }
        return tags
    }
}
