import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

/// Entries의 파일 시스템 작업 관리
@Reducer
struct EntriesOperationsFeature {
    struct TagChangeTarget: Equatable, Sendable {
        let file: Entry
        let beforeTags: [String]
        let afterTags: [String]
    }

    @ObservableState
    struct State: Equatable {
        var itemStates: [String: ItemOperationState] = [:]
        var applicationsForItems: [String: [ApplicationInfo]] = [:]
        var commonApplicationsForSelectedFiles: [ApplicationInfo] = []
    }

    struct ItemOperationState: Equatable {
        var isBusy: Bool
        var lastError: FileOpError?

        init(isBusy: Bool = false, lastError: FileOpError? = nil) {
            self.isBusy = isBusy
            self.lastError = lastError
        }
    }

    enum Action: Sendable {
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
        case pasteItems(
            sourcePaths: [String],
            destinationPath: String,
            operation: ClipboardOperation,
            actionKind: EntryActionRecord.ActionKind,
        )
        case renameItem(oldPath: String, newPath: String)
        case moveToTrash(items: [Entry])
        case deleteImmediately(items: [Entry])
        case putBackFromTrash(items: [Entry])
        case emptyTrash(items: [Entry])
        case compressItems(items: [Entry])
        case extractCompressedFile(file: Entry)
        case setTagsForItems(targets: [TagChangeTarget])
        case applicationsLoaded(String, [ApplicationInfo])
        case loadCommonApplicationsForFiles(files: [Entry])
        case commonApplicationsLoaded([ApplicationInfo])
        case operationStarted(String, OperationKind)
        case operationFinished(String, OperationKind, Result<Void, FileOpError>)
        case entryActionCompleted(EntryActionRecord)
        case clearError(String)
    }

    enum OperationKind: Equatable, Hashable, Sendable {
        case openDefault
        case openWithApp(String)
        case setDefaultApp(String)
        case quickLook
        case getInfo
        case share
        case performService(String)
        case revealInFinder
        case createFolder
        case createAlias
        case pasteFile
        case rename
        case moveToTrash
        case deleteImmediately
        case putBack
        case compress
        case extract
        case setTags
    }

    @Dependency(\.entryClient)
    var entryClient
    @Dependency(\.workspaceClient)
    var workspaceClient
    @Dependency(\.entryCapabilities)
    var capabilities

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            reduceEntriesOperations(state: &state, action: action)
        }
    }
}
