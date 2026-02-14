import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

// TODO(voy-142): 타입명과 맞추기 위해 파일명을 EntryOperationsAction.swift로 변경 필요.
@CasePathable
enum EntryOperationsAction: CasePathable, Sendable {
    case openFiles(files: [Entry])
    case quickLookFile(file: Entry)
    case quickLookFiles(files: [Entry])
    case openFinderInfo(items: [Entry])
    case shareItems(items: [Entry], anchor: CGPoint?)
    case performService(items: [Entry], name: String)
    case revealInFinder(items: [Entry])
    case openFileWithApp(file: Entry)
    case openFileWithAppBundleID(filePath: String, bundleID: String, url: URL)
    case setDefaultAppForFile(type: UTType?, bundleID: String, file: Entry)
    case setDefaultAppWithOther(file: Entry)
    case openFilesWithAppFromOther(files: [Entry], shouldSetAsDefault: Bool)
    case loadApplicationsForFile(file: Entry)
    case createNewFolder(name: String, parentPath: String)
    case createAliases(items: [Entry])
    case copySelectedItems(files: [Entry])
    case loadClipboardState
    case copyAbsolutePaths(paths: [String])
    case copyURLs(paths: [String])
    case setClipboardOperation(operation: ClipboardOperation)
    case pasteItemsFromClipboard(destinationPath: String)
    case pasteItems(
        sourcePaths: [String],
        destinationPath: String,
        operation: ClipboardOperation,
        actionKind: EntryActionRecord.ActionKind,
    )
    case syncClipboardState(paths: [String], operation: ClipboardOperation)
    case renameItem(oldPath: String, newPath: String)
    case moveToTrash(items: [Entry])
    case deleteImmediately(items: [Entry])
    case deleteImmediatelyConfirmed(items: [Entry])
    case putBackFromTrash(items: [Entry])
    case emptyTrash(items: [Entry])
    case emptyTrashConfirmed(items: [Entry])
    case emptyTrashCancelled
    case compressItems(items: [Entry])
    case extractCompressedFile(file: Entry)
    case setTagsForItems(targets: [TagChangeTarget])
    case toggleTagForDroppedPaths(paths: [String], tagName: String)
    case applicationsLoaded(String, [ApplicationInfo])
    case loadCommonApplicationsForFiles(files: [Entry])
    case commonApplicationsLoaded([ApplicationInfo])
    case requestUndo
    case requestRedo
    case undoEntryAction(EntryActionRecord)
    case redoEntryAction(EntryActionRecord)
    case replayEntryAction(direction: EntryActionDirection, record: EntryActionRecord)
    case entryActionApplied(direction: EntryActionDirection, record: EntryActionRecord)
    case operationStarted(String, OperationKind)
    case operationFinished(String, OperationKind, Result<Void, FileOpError>)
    case entryActionCompleted(EntryActionRecord)
    case emptyTrashCompleted
    case clearError(String)
}
