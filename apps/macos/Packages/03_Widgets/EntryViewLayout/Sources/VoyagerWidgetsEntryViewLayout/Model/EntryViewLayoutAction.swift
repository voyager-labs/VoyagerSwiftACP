@preconcurrency import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import VoyagerFeaturesEntryThumbnail

@CasePathable
public enum EntryViewLayoutAction: ViewAction, CasePathable, Sendable {
    case view(View)
    case delegate(Delegate)
    case `internal`(Internal)

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
    public enum Delegate: Sendable {
        case executeCommand(EntryOperationsCommand)
        case openPathInNewWindow(String)
        case openPathInNewTab(String)
        case startRename(item: EntryModel, text: String)
        case saveScrollOffset(CGPoint, forPath: String)
        case selectionChanged
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
