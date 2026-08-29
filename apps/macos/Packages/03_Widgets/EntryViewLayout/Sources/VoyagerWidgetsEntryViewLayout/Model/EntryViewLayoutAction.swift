@preconcurrency import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import VoyagerFeaturesEntryThumbnail
import VoyagerShared

@CasePathable
public enum EntryViewLayoutAction: ViewAction, CasePathable, Sendable {
    case view(View)
    case delegate(Delegate)
    case `internal`(Internal)
    case hierarchy(EntryListHierarchyAction)
    case entryOperations(EntryOperationsFeature.Action)
    case entryThumbnail(EntryThumbnailFeature.Action)
    case entryArrangements(EntryArrangementsFeature.Action)

    public struct EntryViewLayoutPreferences: Sendable {
        public let listIconSize: CGFloat
        public let listTextSize: CGFloat
        public let gridIconSize: CGFloat
        public let gridTextSize: CGFloat
        public let showHiddenFiles: Bool

        public init(
            listIconSize: CGFloat,
            listTextSize: CGFloat,
            gridIconSize: CGFloat,
            gridTextSize: CGFloat,
            showHiddenFiles: Bool,
        ) {
            self.listIconSize = listIconSize
            self.listTextSize = listTextSize
            self.gridIconSize = gridIconSize
            self.gridTextSize = gridTextSize
            self.showHiddenFiles = showHiddenFiles
        }
    }

    @CasePathable
    public enum View: @unchecked Sendable {
        case updateSelection(
            ids: Set<EntryModel.ID>,
            lastSelectedId: EntryModel.ID?,
            rangeAnchorId: EntryModel.ID?,
            shouldScrollToSelection: Bool,
        )
        case selectAll(orderedItemIds: [EntryModel.ID])
        case selectNextItem(isShiftPressed: Bool)
        case selectPreviousItem(isShiftPressed: Bool)
        case selectByOffset(offset: Int, isShiftPressed: Bool)
        case updateGridColumnCount(Int)
        case updateListVisibleColumns([EntryListColumn])
        case updateListColumnVisibility(column: EntryListColumn, isVisible: Bool)
        case moveListColumn(from: Int, to: Int)
        case resetListVisibleColumns
        case resetScrollFlag
        case setTypeScrollTarget(EntryModel.ID)
        case resetTypeScrollTarget
        case setDropTargeted(Bool)
        case startDrag(paths: [String])
        case handleDrop(providers: [NSItemProvider], destinationPath: String)
        case dropItems(sourcePaths: [String], destinationPath: String, isOptionDrag: Bool)
        // 외부 drop 획득 세션의 semantic view action. coordinator가 child reducer에
        // 직접 주입하지 않고 이 경계를 통해 EntryViewLayoutFeature가 라우팅한다.
        case externalDropAccepted(request: ExternalDropAcceptedRequest)
        case externalDropCancelSession(ExternalDropSessionID)
        case openSelectedItem(source: EntryCommandSource)
        case executeCommand(String, source: EntryCommandSource)
        case openPathInNewWindow(String)
        case openInNewTab([String])
        case performService(serviceName: String)
        case startRename(item: EntryModel, text: String, source: EntryCommandSource)
        case updateRenamingText(String)
        case commitRename(itemID: EntryModel.ID, newName: String)
        case openEntry(EntryModel)
        case saveScrollOffset(CGPoint, forPath: String)
        case changeSort(EntryViewLayoutSortKey, VoyagerShared.SortOrder)
        case toggleGroup(String)
        case preloadOpenWithApplications([EntryModel])
        case openWithApp(bundleID: String?, source: EntryCommandSource)
        case toggleTag(String, source: EntryCommandSource)
        case mutateTag(name: String, mode: TagMutationMode, source: EntryCommandSource)
        case expandFolder(EntryModel.ID)
        case collapseFolder(EntryModel.ID)
        case retryFolder(EntryModel.ID)
        case toggleShowHiddenFiles
        case applyContentProjection(ContentProjection)
    }

    @CasePathable
    public enum Delegate: Sendable {
        case executeCommand(String, source: EntryCommandSource)
        case openPathInNewWindow(String)
        case openInNewTab([String])
        case performService(serviceName: String)
        case startRename(item: EntryModel, text: String, source: EntryCommandSource)
        case saveScrollOffset(CGPoint, forPath: String)
        case selectionChanged
        // Feature로 라우팅할 intent
        case expandRequested(EntryModel.ID)
        case collapseRequested(EntryModel.ID)
        case rootContextChanged(String)
        case retryRequested(EntryModel.ID)
        case openEntry(EntryModel)
        case renameCommitted(itemID: EntryModel.ID, newName: String)
        case renameCanceled
        case sortChanged(EntryViewLayoutSortKey, VoyagerShared.SortOrder)
        case groupChanged(EntryViewLayoutGroupKey)
        case toggleGroup(String)
        case preloadOpenWithApplications([EntryModel])
        case tagMutation(tagName: String, mode: TagMutationMode, source: EntryCommandSource)
        case toggleTag(tagName: String, source: EntryCommandSource)
        case openWithApp(bundleID: String?, source: EntryCommandSource)
        case dropItems(sourcePaths: [String], destinationPath: String, isOptionDrag: Bool)
    }

    @CasePathable
    public enum Internal: Sendable {
        case setSelectionState(
            ids: Set<EntryModel.ID>,
            lastSelectedId: EntryModel.ID?,
            rangeAnchorId: EntryModel.ID?,
            shouldScrollToSelection: Bool,
        )
        case applySelectAll(orderedItemIds: [EntryModel.ID])
        case applyClearSelection
        case applySelectionOffset(offset: Int, isShiftPressed: Bool, orderedItemIds: [EntryModel.ID])
        case updateGridColumnCount(Int)
        case setMode(EntryViewLayoutState.Mode)
        case setListVisibleColumns([EntryListColumn])
        case setListColumnVisibility(column: EntryListColumn, isVisible: Bool)
        case moveListColumn(from: Int, to: Int)
        case resetListVisibleColumns
        case resetScrollFlag
        case applyPreferences(EntryViewLayoutPreferences)
        case setShowHiddenFiles(Bool)
        case setCollectionMode(Bool)
        case setCollectionContentLoading(Bool)
        case setCollectionItems([EntryModel])
        case applyCollectionSearchPaths(
            paths: [String],
            showHidden: Bool,
            priority: EntryMetadataPriority,
        )
        case addCollectionPaths([String])
        case collectionReplaceEvent(epoch: Int, event: EntryLoadEvent)
        case collectionReplaceStreamCompleted(epoch: Int)
        case collectionReplaceFailed(epoch: Int, message: String)
        case collectionAppendEvent(epoch: Int, token: Int, event: EntryLoadEvent)
        case collectionAppendStreamCompleted(epoch: Int, token: Int)
        case collectionAppendFailed(epoch: Int, token: Int, message: String)
        case removeCollectionPaths([String])
        case cancelCollectionMaterialization
        case restartCollectionMaterialization
        case clearCollectionPresentation
        case reconcileHierarchySelection
    }
}
