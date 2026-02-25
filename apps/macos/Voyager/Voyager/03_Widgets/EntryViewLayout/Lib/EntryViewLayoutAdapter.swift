import Combine
import ComposableArchitecture
import CoreGraphics
import Foundation

@MainActor
struct EntryViewLayoutAdapter {
    struct PageState: Equatable {
        var selectedIds: Set<String>
        var lastSelectedId: String?
        var shouldScrollToSelection: Bool
        var gridColumnCount: Int
        var listVisibleColumns: [EntryListColumn]
        var renamingItemId: String?
        var renamingText: String
        var isDropTargeted: Bool
        var showHiddenFiles: Bool

        var entries: [EntryModel]

        var groupKey: GroupKey
        var groupedItems: [GroupedItems]
        var collapsedGroups: Set<String>
        var sortKey: SortKey
        var sortOrder: SortOrder

        var currentPath: String
        var savedScrollOffset: CGPoint?

        var listIconSize: CGFloat
        var listTextSize: CGFloat
        var gridIconSize: CGFloat
        var gridTextSize: CGFloat

        var thumbnailRenderVersion: Int

        var clipboardItems: Set<String>
        var clipboardOperation: ClipboardOperation

        var canPaste: Bool {
            !clipboardItems.isEmpty
        }
    }

    struct Actions {
        var requestThumbnails: @MainActor (_ paths: [String]) -> Void
        var saveScrollOffset: @MainActor (_ offset: CGPoint, _ path: String) -> Void

        var toggleCollapsedGroup: @MainActor (_ name: String) -> Void
        var setSortKey: @MainActor (_ key: SortKey) -> Void
        var setSortOrder: @MainActor (_ order: SortOrder) -> Void

        var resolveOpenWithMenuData: @MainActor (_ selectedEntries: [EntryModel]) -> (Bool, [ApplicationInfo])
        var openPathInNewTab: @MainActor (_ path: String) -> Void
        var openSelectedItem: @MainActor () -> Void
        var startRename: @MainActor (_ id: String) -> Void
        var commitRename: @MainActor () -> Void
        var startDrag: @MainActor (_ paths: [String]) -> Void
        var handleDrop: @MainActor (_ providers: [NSItemProvider], _ destinationPath: String) -> Void
        var dropItems: @MainActor (_ sourcePaths: [String], _ destinationPath: String, _ isOptionDrag: Bool)
            -> Void

        var quickLookSelectedItem: @MainActor () -> Void
        var getInfoForSelectedItems: @MainActor () -> Void
        var shareSelectedItems: @MainActor (_ anchor: CGPoint?) -> Void
        var revealSelectedItemsInFinder: @MainActor () -> Void
        var copySelectedItems: @MainActor () -> Void
        var copySelectedAbsolutePaths: @MainActor () -> Void
        var copySelectedURLs: @MainActor () -> Void
        var cutSelectedItems: @MainActor () -> Void
        var pasteItems: @MainActor (_ destinationPath: String) -> Void
        var duplicateSelectedItems: @MainActor () -> Void
        var createAliasForSelectedItems: @MainActor () -> Void
        var compressSelectedItems: @MainActor () -> Void
        var extractSelectedItem: @MainActor () -> Void
        var moveSelectedItemsToTrash: @MainActor () -> Void
        var deleteSelectedItemsImmediately: @MainActor () -> Void
        var putBackSelectedItems: @MainActor () -> Void
        var emptyTrash: @MainActor () -> Void
        var openWithSelectedItem: @MainActor (_ bundleID: String?, _ shouldSetAsDefault: Bool) -> Void
        var toggleTagForSelectedItem: @MainActor (_ tagName: String) -> Void
    }

    let entryViewLayoutStore: StoreOf<EntryViewLayoutFeature>
    let pageState: @MainActor () -> PageState
    let pageStatePublisher: AnyPublisher<PageState, Never>
    let actions: Actions
}
