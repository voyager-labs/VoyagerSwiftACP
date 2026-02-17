import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

@CasePathable
enum EntryOperationsAction: CasePathable, Sendable {
    case loadItems(path: String, showHidden: Bool)
    case loadRecentItems(showHidden: Bool)
    case loadTagItems(tagName: String, showHidden: Bool)
    case loadComputerItems
    case itemsLoaded([EntryModel])
    case collectionItemsLoadedFromSearch(items: [JSONValue], showHidden: Bool)
    case setCollectionMode(Bool)
    case clearCollectionItems

    case openFiles(files: [EntryModel])
    case quickLookFile(file: EntryModel)
    case quickLookFiles(files: [EntryModel])
    case openFinderInfo(items: [EntryModel])
    case shareItems(items: [EntryModel], anchor: CGPoint?)
    case performService(items: [EntryModel], name: String)
    case revealInFinder(items: [EntryModel])
    case openFileWithApp(file: EntryModel)
    case openFileWithAppBundleID(filePath: String, bundleID: String, url: URL)
    case setDefaultAppForFile(type: UTType?, bundleID: String, file: EntryModel)
    case setDefaultAppWithOther(file: EntryModel)
    case openFilesWithAppFromOther(files: [EntryModel], shouldSetAsDefault: Bool)
    case loadApplicationsForFile(file: EntryModel)
    case createNewFolder(name: String, parentPath: String)
    case createAliases(items: [EntryModel])
    case copySelectedItems(files: [EntryModel])
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
    case moveToTrash(items: [EntryModel])
    case deleteImmediately(items: [EntryModel])
    case deleteImmediatelyConfirmed(items: [EntryModel])
    case putBackFromTrash(items: [EntryModel])
    case emptyTrash(items: [EntryModel])
    case emptyTrashConfirmed(items: [EntryModel])
    case emptyTrashCancelled
    case compressItems(items: [EntryModel])
    case extractCompressedFile(file: EntryModel)
    case requestTagMutation(request: TagMutationRequest)
    case applicationsLoaded(String, [ApplicationInfo])
    case loadCommonApplicationsForFiles(files: [EntryModel])
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
