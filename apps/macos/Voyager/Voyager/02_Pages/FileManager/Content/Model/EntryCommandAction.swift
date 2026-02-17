import AppKit
import ComposableArchitecture
import Foundation
import UniformTypeIdentifiers

@CasePathable
enum EntryCommandAction: CasePathable, Sendable {
    case onAppear
    case reloadCurrentFolder
    case loadItems(path: String)
    case reloadItems
    case loadRecentItems(showHidden: Bool)
    case loadTagItems(tagName: String, showHidden: Bool)
    case loadComputerItems
    case itemsLoaded([EntryModel])
    case collectionItemsLoadedFromSearch([JSONValue])
    case fileSystemChanged([String])
    case toggleShowHiddenFiles
    case applyShowHiddenFiles(Bool)
    case setShowHidden(Bool)
    case setCollectionMode(Bool)
    case clearCollectionItems
    case setDropTargeted(Bool)
    case setSelectedIds(ids: Set<String>, lastSelectedId: String?)
    case setSelectedIdsFromLasso(ids: Set<String>, lastSelectedId: String?)
    case selectItem(id: String, isCommandPressed: Bool, isShiftPressed: Bool)
    case selectAll
    case clearSelection
    case selectNextItem(isShiftPressed: Bool)
    case selectPreviousItem(isShiftPressed: Bool)
    case selectByOffset(offset: Int, isShiftPressed: Bool)
    case resetScrollFlag

    case openSelectedItem
    case quickLookSelectedItem
    case getInfoForSelectedItems
    case shareSelectedItems(anchor: CGPoint?)
    case revealSelectedItemsInFinder
    case performService(serviceName: String)
    case openWithSelectedItem(bundleID: String?, shouldSetAsDefault: Bool)
    case openCollectionFile(URL)
    case navigateFolder(id: String)
    case copySelectedItems
    case copySelectedAbsolutePaths
    case copySelectedURLs
    case cutSelectedItems
    case pasteItems(destinationPath: String)
    case duplicateSelectedItems
    case createAliasForSelectedItems
    case startDrag(paths: [String])
    case dropToFolder(destinationPath: String)
    case handleDrop(providers: [NSItemProvider], destinationPath: String)
    case handleDropToTag(providers: [NSItemProvider], tagName: String)
    case dropItems(sourcePaths: [String], destinationPath: String, isOptionDrag: Bool)
    case createNewFolder(currentPath: String)
    case confirmNewFolder(name: String, path: String, originalName: String)
    case moveSelectedItemsToTrash
    case deleteSelectedItemsImmediately
    case putBackSelectedItems
    case compressSelectedItems
    case extractSelectedItem
    case toggleTagForSelectedItem(tag: String)
    case emptyTrash
    case setSelectAfterLoad(fileNames: [String])

    case requestThumbnails(paths: [String])
    case thumbnailsReady(paths: [String])
    case thumbnailRequestFailed(paths: [String])
    case startRename(id: String)
    case updateRenamingText(String)
    case commitRename
    case cancelRename

    case setListIconSize(CGFloat)
    case setGridIconSize(CGFloat)
    case setListTextSize(CGFloat)
    case setGridTextSize(CGFloat)
}
