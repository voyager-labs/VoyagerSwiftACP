import AppKit
import ComposableArchitecture
import Foundation
import VoyagerFeaturesEntryOperations

@CasePathable
enum EntryViewLayoutAction: ViewAction, CasePathable, Sendable {
    case view(View)
    case delegate(Delegate)
    case `internal`(Internal)

    case entryOperations(EntryOperationsFeature.Action)
    case entryThumbnail(EntryThumbnailFeature.Action)
    case entryArrangements(EntryArrangementsFeature.Action)

    struct EntryViewLayoutPreferences: Sendable {
        let listIconSize: CGFloat
        let listTextSize: CGFloat
        let gridIconSize: CGFloat
        let gridTextSize: CGFloat
        let showHiddenFiles: Bool
    }

    @CasePathable
    enum View: Sendable {
        case selectNextItem(isShiftPressed: Bool)
        case selectPreviousItem(isShiftPressed: Bool)
        case selectByOffset(offset: Int, isShiftPressed: Bool)
        case setDropTargeted(Bool)
        case startDrag(paths: [String])
        case handleDrop(providers: [NSItemProvider], destinationPath: String)
        case dropItems(sourcePaths: [String], destinationPath: String, isOptionDrag: Bool)
        case openSelectedItem
        case toggleShowHiddenFiles
    }

    @CasePathable
    enum Delegate: Sendable {
        case executeCommand(EntryOperationsCommand)
        case openPathInNewTab(String)
        case startRename(item: EntryModel, text: String)
        case saveScrollOffset(CGPoint, forPath: String)
    }

    @CasePathable
    enum Internal: Sendable {
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
        case setListVisibleColumns([EntryListColumn])
        case setListColumnVisibility(column: EntryListColumn, isVisible: Bool)
        case moveListColumn(from: Int, to: Int)
        case resetListVisibleColumns
        case resetScrollFlag
        case applyPreferences(EntryViewLayoutPreferences)
        case setShowHiddenFiles(Bool)
        case setCollectionMode(Bool)
        case setCollectionItems([EntryModel])
        case applyCollectionSearchPaths(paths: [String], showHidden: Bool)
        case addCollectionPaths([String])
        case removeCollectionPaths([String])
        case clearCollectionPresentation
    }
}
