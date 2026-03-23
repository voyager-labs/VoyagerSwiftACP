import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

@CasePathable
enum EntryOperationsAction: CasePathable, Sendable {
    case delegate(Delegate)
    case routing(Routing)
    case loading(Loading)
    case lifecycle(Lifecycle)
    case open(Open)
    case openWith(OpenWith)
    case edit(Edit)
    case clipboard(Clipboard)
    case trash(Trash)
    case archive(Archive)
    case tagging(Tagging)
    case undoRedo(UndoRedo)
    case thumbnail(Thumbnail)

    @CasePathable
    enum Delegate: CasePathable, Sendable {
        case navigateFolder(id: EntryModel.ID)
    }

    @CasePathable
    enum Routing: CasePathable, Sendable {
        case executeCommand(command: EntryOperationsCommand, context: EntryOperationsCommandContext)
        case validateDrop(context: EntryDropValidationContext)
        case saveDragPaths([String])
        case handleDrop(providers: [NSItemProvider], destinationPath: String)
        case dropItems(sourcePaths: [String], destinationPath: String, isOptionDrag: Bool)
        case handleDropToTag(providers: [NSItemProvider], tagName: String)
    }

    @CasePathable
    enum Loading: CasePathable, Sendable {
        case loadItems(path: String, showHidden: Bool)
        case loadRecentItems(showHidden: Bool)
        case loadTagItems(tagName: String, showHidden: Bool)
        case loadComputerItems
        case itemsLoaded([EntryModel])
        case collectionItemsLoadedFromSearch(items: [JSONValue], showHidden: Bool)
        case setCollectionMode(Bool)
        case clearCollectionItems
    }

    @CasePathable
    enum Lifecycle: CasePathable, Sendable {
        case syncSelectedEntryIDs(Set<EntryModel.ID>)
        case clearError(String)
        case operationStarted(String, OperationKind)
        case operationFinished(String, OperationKind, Result<Void, FileOpError>)
        case entryActionCompleted(EntryActionRecord)
        case emptyTrashCompleted
        case loadClipboardState
        case appDidBecomeActive
        case syncClipboardState(paths: [String], operation: ClipboardOperation)
    }

    @CasePathable
    enum Open: CasePathable, Sendable {
        case openFiles(paths: [String])
        case quickLookFiles(paths: [String])
        case openFinderInfo(paths: [String])
        case shareItems(paths: [String], anchor: CGPoint?)
        case performService(paths: [String], name: String)
        case revealInFinder(paths: [String])
    }

    @CasePathable
    enum OpenWith: CasePathable, Sendable {
        case openFileWithApp(file: EntryModel)
        case openFileWithAppBundleID(filePath: String, bundleID: String, url: URL)
        case setDefaultAppForFile(type: UTType?, bundleID: String, file: EntryModel)
        case setDefaultAppWithOther(file: EntryModel)
        case openFilesWithAppFromOther(files: [EntryModel], shouldSetAsDefault: Bool)
        case loadApplicationsForFile(file: EntryModel)
        case applicationsLoaded(String, [ApplicationInfo])
        case loadCommonApplicationsForFiles(files: [EntryModel])
        case commonApplicationsLoaded([ApplicationInfo])
    }

    @CasePathable
    enum Edit: CasePathable, Sendable {
        case createNewFolder(name: String, parentPath: String)
        case createAliases(paths: [String])
        case renameItem(oldPath: String, newPath: String)
        case startRename(id: EntryModel.ID, text: String)
        case updateRenamingText(String)
        case commitRename
        case cancelRename
    }

    @CasePathable
    enum Clipboard: CasePathable, Sendable {
        case copySelectedItems(files: [EntryModel])
        case copyAbsolutePaths(paths: [String])
        case copyURLs(paths: [String])
        case setClipboardOperation(operation: ClipboardOperation)
        case pasteItemsFromClipboard(destinationPath: String)
        case pasteItems(
            sourcePaths: [String],
            destinationPath: String,
            operation: ClipboardOperation,
            operationKind: OperationKind,
        )
    }

    @CasePathable
    enum Trash: CasePathable, Sendable {
        case moveToTrash(paths: [String])
        case deleteImmediately(paths: [String])
        case deleteImmediatelyConfirmed(paths: [String])
        case putBackFromTrash(paths: [String])
        case emptyTrash(paths: [String])
        case emptyTrashConfirmed(paths: [String])
        case emptyTrashCancelled
    }

    @CasePathable
    enum Archive: CasePathable, Sendable {
        case compressItems(paths: [String])
        case extractCompressedFile(path: String)
    }

    @CasePathable
    enum Tagging: CasePathable, Sendable {
        case requestTagMutation(request: TagMutationRequest)
    }

    @CasePathable
    enum UndoRedo: CasePathable, Sendable {
        case requestUndo
        case requestRedo
        case undoEntryAction(EntryActionRecord)
        case redoEntryAction(EntryActionRecord)
        case replayEntryAction(direction: EntryActionDirection, record: EntryActionRecord)
        case entryActionApplied(direction: EntryActionDirection, record: EntryActionRecord)
    }

    @CasePathable
    enum Thumbnail: CasePathable, Sendable {
        case requestThumbnails(paths: [String])
        case thumbnailsReady(paths: [String])
        case thumbnailRequestFailed(paths: [String])
    }
}

struct TagMutationRequest: Equatable, Sendable {
    let mode: Mode
    let tagName: String
    let paths: [String]

    enum Mode: Equatable, Sendable {
        case toggle
        case add
        case remove
    }
}

enum EntryActionDirection: Sendable {
    case undo
    case redo
}

struct EntryDropValidationContext: Equatable, Sendable {
    let sourcePaths: [String]
    let destinationPath: String
    let allowedOperationsRawValue: UInt
    let prefersCopy: Bool
}

enum EntryDropResolvedOperation: Equatable, Sendable {
    case none
    case copy
    case move
}

struct EntryDropValidationResult: Equatable, Sendable {
    var destinationPath: String
    var resolvedOperation: EntryDropResolvedOperation
    var isOptionDrag: Bool

    static let empty = EntryDropValidationResult(
        destinationPath: "",
        resolvedOperation: .none,
        isOptionDrag: false,
    )
}
