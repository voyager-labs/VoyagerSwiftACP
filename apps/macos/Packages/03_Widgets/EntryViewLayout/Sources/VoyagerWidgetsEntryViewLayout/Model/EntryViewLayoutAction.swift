@preconcurrency import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import VoyagerFeaturesEntryThumbnail
import VoyagerShared

/// The immutable identity mapping supplied by the page that owns the filesystem
/// operation. The view-layout feature never re-derives these paths from a later
/// callback, which keeps lexical row identity separate from canonical scope matching.
public struct EntryIdentityReplacementPair: Equatable, Sendable {
    public let beforePath: String
    public let beforeLexicalPath: String
    public let afterPath: String
    public let afterLexicalPath: String

    public init(
        beforePath: String,
        afterPath: String,
        beforeLexicalPath: String = "",
        afterLexicalPath: String = "",
    ) {
        self.beforePath = beforePath
        self.beforeLexicalPath = beforeLexicalPath
        self.afterPath = afterPath
        self.afterLexicalPath = afterLexicalPath
    }
}

public struct EntryIdentityReplacementPlan: Equatable, Sendable {
    public let transactionID: UUID
    public let rootPath: String
    public let pairs: [EntryIdentityReplacementPair]

    public init(
        transactionID: UUID,
        rootPath: String,
        pairs: [EntryIdentityReplacementPair],
    ) {
        self.transactionID = transactionID
        self.rootPath = rootPath
        self.pairs = pairs
    }
}

public enum EntryIdentityReplacementCancelReason: Equatable, Sendable {
    case navigationChanged
    case superseded
    case userCollapsedSource
    case destinationCollapsed
    case failed
}

public enum EntryIdentityReplacementOutcome: Equatable, Sendable {
    case completed
    case failed
    case cancelled(EntryIdentityReplacementCancelReason)
}

@CasePathable
public enum EntryIdentityReplacementAction: CasePathable, Sendable {
    case begin(EntryIdentityReplacementPlan)
    case cancel(id: UUID, reason: EntryIdentityReplacementCancelReason)
    case settle(id: UUID, outcome: EntryIdentityReplacementOutcome)
}

@CasePathable
public enum EntryViewLayoutAction: ViewAction, CasePathable, Sendable {
    case view(View)
    case delegate(Delegate)
    case `internal`(Internal)
    case identityReplacement(EntryIdentityReplacementAction)
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
        /// UI adapter가 확정한 사용자 제스처 clear(빈 영역 클릭, 마지막 항목 Command 해제, 빈 lasso 종료).
        /// `updateSelection`의 authoritative setter 의미와 달리 “선택을 비운다”는 의도만 전달한다.
        case clearSelection
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
        case resetTypeScrollTarget
        case setDropTargeted(Bool)
        case startDrag(paths: [String])
        case handleDrop(providers: [NSItemProvider], destinationPath: String)
        case dropItems(sourcePaths: [String], destinationPath: String, isOptionDrag: Bool)
        // 외부 drop 획득 세션의 semantic view action. coordinator가 child reducer에
        // 직접 주입하지 않고 이 경계를 통해 EntryViewLayoutFeature가 라우팅한다.
        case externalDropAccepted(request: ExternalDropAcceptedRequest)
        case externalDropCancelSession(ExternalDropSessionID)
        case openSelectedItem
        case executeCommand(String)
        case openPathInNewWindow(String)
        case openInNewTab([String])
        case performService(serviceName: String)
        case startRename(item: EntryModel, text: String)
        case commitRename(itemID: EntryModel.ID, newName: String)
        case openEntry(EntryModel)
        case saveScrollOffset(CGPoint, forPath: String)
        case changeSort(EntryViewLayoutSortKey, VoyagerShared.SortOrder)
        case toggleGroup(String)
        case preloadOpenWithApplications([EntryModel])
        case openWithApp(bundleID: String?)
        case toggleTag(String)
        case mutateTag(name: String, mode: TagMutationMode)
        case expandFolder(EntryModel.ID)
        case collapseFolder(EntryModel.ID)
        case retryFolder(EntryModel.ID)
        case toggleShowHiddenFiles
        case applyContentProjection(ContentProjection)
    }

    @CasePathable
    public enum Delegate: Sendable {
        case executeCommand(String)
        case openPathInNewWindow(String)
        case openInNewTab([String])
        case performService(serviceName: String)
        case startRename(item: EntryModel, text: String)
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
        case tagMutation(tagName: String, mode: TagMutationMode)
        case toggleTag(tagName: String)
        case openWithApp(bundleID: String?)
        case dropItems(sourcePaths: [String], destinationPath: String, isOptionDrag: Bool)
        case identityReplacementSettled(
            id: UUID,
            outcome: EntryIdentityReplacementOutcome,
        )
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
        case selectTypeScrollTarget(EntryModel.ID)
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
