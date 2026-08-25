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
    case outcome(Outcome)
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
    case externalDrop(ExternalDrop)

    @CasePathable
    public enum ExternalDrop: CasePathable, Sendable {
        /// Grid/List `acceptDrop`이 동기적으로 받아들인 획득 요청. 배리어 세션을 연다.
        case accepted(request: ExternalDropAcceptedRequest)
        /// reducer가 구독한 획득 이벤트 스트림에서 온 이벤트.
        case event(ExternalDropAcquisitionEvent)
        /// 정확한 세션을 취소한다 (멱등).
        case cancelSession(ExternalDropSessionID)
        /// 정확한 세션을 정상 종료한다 (멱등).
        case finishSession(ExternalDropSessionID)
        /// internal: all-promises 성공 시 reducer가 emit하는 import-placement action.
        /// 실제 복사 배치는 Todo 7 seam이 이 action을 소비해 수행한다.
        case applyImport(ExternalDropImportPlan)
        /// internal: placement 진입 직전 source descriptor 고정 결과.
        case placementSourcesPrepared(plan: ExternalDropImportPlan, isValid: Bool)
        /// internal: placement의 모든 항목이 종료된 뒤 reducer가 emit하는 종합 완료 action.
        /// 성공 목적지 경로/실패와 종단 상태를 담으며, FileManager가 정확히 한 번 reload한다.
        case importFinished(ExternalDropImportResult)
    }

    @CasePathable
    public enum Delegate: CasePathable, Sendable {
        case navigateToPath(String)
        case openCollectionFile(URL)
        case folderLoadEvent(request: EntryFolderLoadRequest, event: EntryLoadEvent)
        case folderLoadFinished(request: EntryFolderLoadRequest)
        case folderLoadFailed(request: EntryFolderLoadRequest, failure: EntryFolderLoadFailure)
        case openInNewTab([String])
    }

    @CasePathable
    public enum Outcome: CasePathable, Sendable {
        case entriesMutated(EntryOperationsMutationImpact)
        case undoManagerAvailabilityChanged(UndoManagerAvailability)
        case entryActionReplayFinished(direction: EntryActionDirection, terminal: EntryActionReplayTerminal)
    }

    @CasePathable
    public enum Routing: CasePathable, @unchecked Sendable {
        case executeCommand(command: EntryOperationsCommand, context: EntryOperationsCommandContext)
        case validateDrop(context: EntryDropValidationContext)
        case saveDragPaths([String])
        case handleDrop(providers: [NSItemProvider], destinationPath: String, isOptionDrag: Bool)
        case handleDropToTrash(providers: [NSItemProvider])
        case dropItems(sourcePaths: [String], destinationPath: String, isOptionDrag: Bool)
        case handleDropToTag(providers: [NSItemProvider], tagName: String)
    }

    @CasePathable
    public enum Loading: CasePathable, Sendable {
        case loadItems(path: String, showHidden: Bool, priority: EntryMetadataPriority = .none)
        case loadRecentItems(showHidden: Bool, priority: EntryMetadataPriority = .none)
        case loadTagItems(tagName: String, showHidden: Bool, priority: EntryMetadataPriority = .none)
        case loadComputerItems
        case cancelAndClearItems
        case itemsLoaded([EntryModel])
        case itemsLoadFailed
        case streamEvent(EntryLoadingStreamEvent)
        case streamFinished(generation: Int)
        case streamFailed(generation: Int)
        case loadFolderItems(EntryFolderLoadRequest)
        case cancelFolderItems(EntryFolderLoadRequest.RequestID)
        case cancelAllFolderItems
        case folderStreamEvent(request: EntryFolderLoadRequest, event: EntryLoadEvent)
        case folderStreamFinished(request: EntryFolderLoadRequest)
        case folderStreamFailed(request: EntryFolderLoadRequest, failure: EntryFolderLoadFailure)
    }

    @CasePathable
    public enum Lifecycle: CasePathable, Sendable {
        case windowIDChanged(UUID)
        case resetForDuplicate(windowID: UUID)
        case syncSelectedEntryIDs(Set<EntryModel.ID>)
        case clearError(String)
        case operationStarted(String, OperationKind)
        case operationFinished(String, OperationKind, Result<Void, FileOpError>)
        case dropOperationFinished(String, OperationKind, Result<Void, FileOpError>)
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
        case syncQuickLookSelection(paths: [String], selectedIndex: Int)
    }

    @CasePathable
    public enum OpenWith: CasePathable, Sendable {
        case openFileWithApp(file: EntryModel)
        case openFileWithAppBundleID(filePath: String, bundleID: String, url: URL)
        case setDefaultAppForFile(type: UTType?, bundleID: String, file: EntryModel)
        case setDefaultAppWithOther(file: EntryModel)
        case openFilesWithAppFromOther(files: [EntryModel], shouldSetAsDefault: Bool)
        case loadApplicationsForFile(file: EntryModel)
        case applicationsLoaded(typeID: String, generation: Int, [ApplicationInfo])
        case loadCommonApplicationsForFiles(files: [EntryModel])
        case commonApplicationsLoaded(
            generation: Int,
            typeIDs: Set<String>,
            applicationsByType: [String: [ApplicationInfo]],
            [ApplicationInfo],
        )
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
        case performDrop(sourcePaths: [String], destinationPath: String, isOptionDrag: Bool)
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
        case replaySucceeded(
            direction: EntryActionDirection,
            sourceRecordID: UUID,
            updatedRecord: EntryActionRecord,
        )
        case replayFailed(direction: EntryActionDirection, appliedTargets: [EntryActionRecord.Target])
    }
}

public enum EntryFolderLoadFailure: Equatable, Sendable {
    case permissionDenied
    case unavailable(description: String)
}

public struct EntryLoadingStreamEvent: Equatable, Sendable {
    public let generation: Int
    public let event: EntryLoadEvent

    public init(generation: Int, event: EntryLoadEvent) {
        self.generation = generation
        self.event = event
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

public enum EntryActionDirection: Equatable, Sendable {
    case undo
    case redo
}

public enum EntryActionReplayTerminal: Equatable, Sendable {
    case success(EntryActionRecord)
    case failure(reason: EntryActionReplayFailureReason, appliedTargets: [EntryActionRecord.Target])
}

public enum EntryActionReplayFailureReason: Equatable, Sendable {
    case ownerRecordMismatch
    case ownerBusy
    case operationFailed
}

public struct EntryOperationsMutationImpact: Equatable, Sendable {
    public let sourceParentPaths: [String]
    public let destinationPath: String

    public init(sourceParentPaths: [String], destinationPath: String) {
        self.sourceParentPaths = sourceParentPaths
        self.destinationPath = destinationPath
    }
}
