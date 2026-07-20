@preconcurrency import AppKit
import ComposableArchitecture
import Foundation
@preconcurrency import UniformTypeIdentifiers
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import VoyagerShared

@CasePathable
public enum EntryOperationsAction: CasePathable, Sendable {
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

    @CasePathable
    public enum Delegate: CasePathable, Sendable {
        case navigateToPath(String)
        case openCollectionFile(URL)
    }

    @CasePathable
    public enum Routing: CasePathable, @unchecked Sendable {
        case executeCommand(command: EntryOperationsCommand, context: EntryOperationsCommandContext)
        case validateDrop(context: EntryDropValidationContext)
        case saveDragPaths([String])
        case handleDrop(providers: [NSItemProvider], destinationPath: String)
        case dropItems(sourcePaths: [String], destinationPath: String, isOptionDrag: Bool)
        case handleDropToTag(providers: [NSItemProvider], tagName: String)
    }

    @CasePathable
    public enum Loading: CasePathable, Sendable {
        case loadItems(path: String, showHidden: Bool)
        case loadRecentItems(showHidden: Bool)
        case loadTagItems(tagName: String, showHidden: Bool)
        case loadComputerItems
        case itemsLoaded([EntryModel])
        case itemsLoadFailed
    }

    @CasePathable
    public enum Lifecycle: CasePathable, Sendable {
        case windowIDChanged(UUID)
        case resetForDuplicate(windowID: UUID)
        case syncSelectedEntryIDs(Set<EntryModel.ID>)
        case clearError(String)
        case operationStarted(String, OperationKind)
        case operationFinished(String, OperationKind, Result<Void, FileOpError>)
        case entryActionCompleted(EntryActionRecord)
        case emptyTrashCompleted
        case loadClipboardState
        case appDidBecomeActive
        case syncClipboardState(paths: [String], operation: ClipboardOperation)
        case pathsMutated([String])
        case restorableTrashPathsLoaded(Set<String>)
    }

    @CasePathable
    public enum Open: CasePathable, Sendable {
        case openFiles(paths: [String])
        case quickLookFiles(paths: [String])
        case openFinderInfo(paths: [String])
        case shareItems(paths: [String], anchor: CGPoint?)
        case performService(paths: [String], name: String)
        case revealInFinder(paths: [String])
    }

    @CasePathable
    public enum OpenWith: CasePathable, Sendable {
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
    public enum Edit: CasePathable, Sendable {
        case createNewFolder(parentPath: String, siblingNames: [String])
        case createAliases(paths: [String])
        case renameItem(oldPath: String, newPath: String)
        case startRename(item: EntryModel, text: String)
        case updateRenamingText(String)
        case commitRename
        case cancelRename
    }

    @CasePathable
    public enum Clipboard: CasePathable, Sendable {
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
    public enum Trash: CasePathable, Sendable {
        case moveToTrash(paths: [String])
        case deleteImmediately(paths: [String])
        case deleteImmediatelyConfirmed(paths: [String])
        case putBackFromTrash(paths: [String])
        case emptyTrash(paths: [String])
        case emptyTrashConfirmed(paths: [String])
        case emptyTrashCancelled
    }

    @CasePathable
    public enum Archive: CasePathable, Sendable {
        case compressItems(paths: [String])
        case extractCompressedFile(path: String)
    }

    @CasePathable
    public enum Tagging: CasePathable, Sendable {
        case requestTagMutation(request: TagMutationRequest)
    }

    @CasePathable
    public enum UndoRedo: CasePathable, Sendable {
        case requestUndo
        case requestRedo
        case undoEntryAction(EntryActionRecord)
        case redoEntryAction(EntryActionRecord)
        case replayEntryAction(direction: EntryActionDirection, record: EntryActionRecord)
        case entryActionApplied(direction: EntryActionDirection, record: EntryActionRecord)
    }
}

public struct TagMutationRequest: Equatable, Sendable {
    public let mode: Mode
    public let tagName: String
    public let paths: [String]

    public init(mode: Mode, tagName: String, paths: [String]) {
        self.mode = mode
        self.tagName = tagName
        self.paths = paths
    }

    public enum Mode: Equatable, Sendable {
        case toggle
        case add
        case remove
    }
}

public struct TagMutationFailure: Equatable, Sendable {
    public let fileName: String
    public let reason: String

    public init(fileName: String, reason: String) {
        self.fileName = fileName
        self.reason = reason
    }
}

public enum EntryActionDirection: Sendable {
    case undo
    case redo
}

public struct EntryDropValidationContext: Equatable, Sendable {
    public let sourcePaths: [String]
    public let destinationPath: String
    public let allowedOperationsRawValue: UInt
    public let prefersCopy: Bool

    public init(
        sourcePaths: [String],
        destinationPath: String,
        allowedOperationsRawValue: UInt,
        prefersCopy: Bool,
    ) {
        self.sourcePaths = sourcePaths
        self.destinationPath = destinationPath
        self.allowedOperationsRawValue = allowedOperationsRawValue
        self.prefersCopy = prefersCopy
    }
}

public enum EntryDropResolvedOperation: Equatable, Sendable {
    case none
    case copy
    case move
}

public struct EntryDropValidationResult: Equatable, Sendable {
    public var destinationPath: String
    public var resolvedOperation: EntryDropResolvedOperation
    public var isOptionDrag: Bool

    public init(
        destinationPath: String,
        resolvedOperation: EntryDropResolvedOperation,
        isOptionDrag: Bool,
    ) {
        self.destinationPath = destinationPath
        self.resolvedOperation = resolvedOperation
        self.isOptionDrag = isOptionDrag
    }

    public static let empty = EntryDropValidationResult(
        destinationPath: "",
        resolvedOperation: .none,
        isOptionDrag: false,
    )
}
