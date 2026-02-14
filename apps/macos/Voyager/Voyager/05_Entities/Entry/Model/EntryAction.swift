import AppKit
import ComposableArchitecture
import Foundation

@CasePathable
enum EntryAction: CasePathable, Sendable {
    case onAppear
    case reloadCurrentFolder
    case loadItems(path: String)
    case reloadItems
    case loadRecentItems(showHidden: Bool)
    case loadTagItems(tagName: String, showHidden: Bool)
    case loadComputerItems
    case itemsLoaded([Entry])
    case collectionItemsLoadedFromSearch([JSONValue])
    case fileSystemChanged([String])
    case toggleShowHiddenFiles
    case applyShowHiddenFiles(Bool)
    case setShowHidden(Bool)
    case setCollectionMode(Bool)
    case setDropTargeted(Bool)
    case setSelectedIds(ids: Set<String>, lastSelectedId: String?)
    /// 러버밴드(드래그 박스) 선택 중 실시간 선택 업데이트 (비용 큰 side effect는 defer)
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

    /// visible 영역 기반 썸네일 요청 (UI에서 스크롤/레이아웃 변화에 따라 호출)
    case requestThumbnails(paths: [String])
    case thumbnailsReady(paths: [String])

    /// QuickLook에서 썸네일을 만들 수 없었던 항목(negative cache)
    case thumbnailRequestFailed(paths: [String])
    case startRename(id: String)
    case updateRenamingText(String)
    case commitRename
    case cancelRename

    case updateGridColumnCount(Int)
    case setListIconSize(CGFloat)
    case setGridIconSize(CGFloat)
    case setListTextSize(CGFloat)
    case setGridTextSize(CGFloat)

    case operationFinished(String, OperationKind, Result<Void, FileOpError>)
    case delegate(Delegate)

    enum Delegate: Sendable {
        case intent(EntryIntent)
        case openFoldersInNewWindows(paths: [String])
        case focusWindow(path: String)
    }
}
