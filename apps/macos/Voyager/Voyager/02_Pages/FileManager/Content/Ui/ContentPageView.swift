import AppKit
import Combine
import ComposableArchitecture
import SwiftUI

struct ContentPageView: View {
    let store: StoreOf<FileManagerContentFeature>
    let onNavigate: (String) -> Void

    @FocusState var isKeyCommandFocused: Bool
    static let undoSelector = Selector(("undo:"))
    static let redoSelector = Selector(("redo:"))

    var body: some View {
        mainContent
            .onChange(of: store.entryViewLayout.selectedIds) { _ in
                guard isGridLayout else { return }
                restoreKeyCommandFocus()
            }
            .onChange(of: store.entryViewLayout.isRenaming) { isRenaming in
                guard isGridLayout else { return }
                if !isRenaming {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        restoreKeyCommandFocus()
                    }
                }
            }
            .onAppear {
                guard isGridLayout else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    restoreKeyCommandFocus()
                }
            }
            .background(backgroundInteractionLayer)
    }

    private var mainContent: some View {
        ZStack {
            VStack(spacing: 0) {
                entryContainerView
                separatorView
                ContentPaneBreadcrumbBarView(
                    store: store,
                    onNavigate: onNavigate,
                )
            }

            keyCommandOverlay
        }
    }

    @ViewBuilder
    private var entryContainerView: some View {
        if isCollectionSearching {
            collectionLoadingView
        } else {
            switch store.viewLayout {
            case .list:
                EntryListViewRepresentable(adapter: entryViewLayoutAdapter)
            case .grid:
                EntryGridViewRepresentable(adapter: entryViewLayoutAdapter)
            }
        }
    }

    private var separatorView: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 1)
    }

    @ViewBuilder
    private var keyCommandOverlay: some View {
        if isGridLayout {
            KeyCommandView { event in
                handleKeyboardEvent(event)
            }
            .focusable()
            .focused($isKeyCommandFocused)
            .allowsHitTesting(false)
        }
    }

    private var backgroundInteractionLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .contextMenu {
                ContentPaneContextMenu(store: store)
            }
            .onTapGesture {
                guard isGridLayout else { return }
                restoreKeyCommandFocus()
            }
    }

    private func handleKeyboardEvent(_ event: NSEvent) {
        let command = KeyCommand(
            keyCode: event.keyCode,
            modifiers: KeyModifiers(event.modifierFlags),
            characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
        )
        store.send(.handleKeyCommand(command))
    }

    private var isCollectionSearching: Bool {
        store.composer.isCollectionSearching
    }

    private var isGridLayout: Bool {
        store.viewLayout == .grid
    }

    // TODO: 이름에서 Collection 내용 제외
    private var collectionLoadingView: some View {
        GeometryReader { _ in
            ZStack {
                Color.clear

                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
    }

    private func restoreKeyCommandFocus() {
        isKeyCommandFocused = true
        KeyCommandHostingView.restoreCurrentFocus()
    }

    private var entryViewLayoutAdapter: EntryViewLayoutAdapter {
        let pageStore = store
        return EntryViewLayoutAdapter(
            entryViewLayoutStore: store.scope(state: \.entryViewLayout, action: \.entryViewLayout),
            pageState: {
                Self.makeEntryViewLayoutPageState(from: pageStore.state)
            },
            pageStatePublisher: pageStore.publisher
                .map(Self.makeEntryViewLayoutPageState(from:))
                .eraseToAnyPublisher(),
            actions: .init(
                requestThumbnails: { paths in
                    pageStore.send(.entries(.requestThumbnails(paths: paths)))
                },
                saveScrollOffset: { offset, path in
                    pageStore.send(.saveScrollOffset(offset, forPath: path))
                },
                toggleCollapsedGroup: { name in
                    pageStore.send(.entryArrangements(.toggleCollapsedGroup(name)))
                },
                setSortKey: { key in
                    pageStore.send(.entryArrangements(.setSortKey(key)))
                },
                setSortOrder: { order in
                    pageStore.send(.entryArrangements(.setSortOrder(order)))
                },
                resolveOpenWithMenuData: { selectedEntries in
                    let selectedFiles = selectedEntries.filter { !$0.isDirectory }
                    if selectedFiles.isEmpty {
                        return (false, [])
                    }

                    if selectedFiles.count > 1 {
                        pageStore.send(.entryOperations(.loadCommonApplicationsForFiles(files: selectedFiles)))
                    } else if let file = selectedFiles.first,
                              pageStore.state.entryOperations.applicationsForItems[file.fullPath] == nil
                    {
                        pageStore.send(.entryOperations(.loadApplicationsForFile(file: file)))
                    }

                    let applications: [ApplicationInfo] = if selectedFiles.count > 1 {
                        pageStore.state.entryOperations.commonApplicationsForSelectedFiles
                    } else if let file = selectedFiles.first {
                        pageStore.state.entryOperations.applicationsForItems[file.fullPath] ?? []
                    } else {
                        []
                    }

                    return (true, applications)
                },
                openPathInNewTab: { path in
                    pageStore.send(.openPathInNewTab(path))
                },
                openSelectedItem: {
                    pageStore.send(.entries(.openSelectedItem))
                },
                startRename: { id in
                    pageStore.send(.entries(.startRename(id: id)))
                },
                commitRename: {
                    pageStore.send(.entries(.commitRename))
                },
                startDrag: { paths in
                    pageStore.send(.entries(.startDrag(paths: paths)))
                },
                handleDrop: { providers, destinationPath in
                    pageStore.send(.entries(.handleDrop(
                        providers: providers,
                        destinationPath: destinationPath,
                    )))
                },
                dropItems: { sourcePaths, destinationPath, isOptionDrag in
                    pageStore.send(.entries(.dropItems(
                        sourcePaths: sourcePaths,
                        destinationPath: destinationPath,
                        isOptionDrag: isOptionDrag,
                    )))
                },
                quickLookSelectedItem: {
                    pageStore.send(.entries(.quickLookSelectedItem))
                },
                getInfoForSelectedItems: {
                    pageStore.send(.entries(.getInfoForSelectedItems))
                },
                shareSelectedItems: { anchor in
                    pageStore.send(.entries(.shareSelectedItems(anchor: anchor)))
                },
                revealSelectedItemsInFinder: {
                    pageStore.send(.entries(.revealSelectedItemsInFinder))
                },
                copySelectedItems: {
                    pageStore.send(.entries(.copySelectedItems))
                },
                copySelectedAbsolutePaths: {
                    pageStore.send(.entries(.copySelectedAbsolutePaths))
                },
                copySelectedURLs: {
                    pageStore.send(.entries(.copySelectedURLs))
                },
                cutSelectedItems: {
                    pageStore.send(.entries(.cutSelectedItems))
                },
                pasteItems: { destinationPath in
                    pageStore.send(.entries(.pasteItems(destinationPath: destinationPath)))
                },
                duplicateSelectedItems: {
                    pageStore.send(.entries(.duplicateSelectedItems))
                },
                createAliasForSelectedItems: {
                    pageStore.send(.entries(.createAliasForSelectedItems))
                },
                compressSelectedItems: {
                    pageStore.send(.entries(.compressSelectedItems))
                },
                extractSelectedItem: {
                    pageStore.send(.entries(.extractSelectedItem))
                },
                moveSelectedItemsToTrash: {
                    pageStore.send(.entries(.moveSelectedItemsToTrash))
                },
                deleteSelectedItemsImmediately: {
                    pageStore.send(.entries(.deleteSelectedItemsImmediately))
                },
                putBackSelectedItems: {
                    pageStore.send(.entries(.putBackSelectedItems))
                },
                emptyTrash: {
                    pageStore.send(.entries(.emptyTrash))
                },
                openWithSelectedItem: { bundleID, shouldSetAsDefault in
                    pageStore.send(.entries(.openWithSelectedItem(
                        bundleID: bundleID,
                        shouldSetAsDefault: shouldSetAsDefault,
                    )))
                },
                toggleTagForSelectedItem: { tagName in
                    pageStore.send(.entries(.toggleTagForSelectedItem(tag: tagName)))
                },
            ),
        )
    }

    private static func makeEntryViewLayoutPageState(from state: FileManagerContentFeature
        .State) -> EntryViewLayoutAdapter.PageState
    {
        .init(
            selectedIds: state.entryViewLayout.selectedIds,
            lastSelectedId: state.entryViewLayout.lastSelectedId,
            shouldScrollToSelection: state.entryViewLayout.shouldScrollToSelection,
            gridColumnCount: state.entryViewLayout.gridColumnCount,
            listVisibleColumns: state.entryViewLayout.listVisibleColumns,
            renamingItemId: state.entryViewLayout.renamingItemId,
            renamingText: state.entryViewLayout.renamingText,
            isDropTargeted: state.entryViewLayout.isDropTargeted,
            showHiddenFiles: state.entryViewLayout.showHiddenFiles,
            entries: Array(state.entryOperations.displayItems),
            groupKey: state.entryArrangements.groupKey,
            groupedItems: state.entryArrangements.groupedItems,
            collapsedGroups: state.entryArrangements.collapsedGroups,
            sortKey: state.entryArrangements.sortKey,
            sortOrder: state.entryArrangements.sortOrder,
            currentPath: state.navigation.currentPath,
            savedScrollOffset: state.navigation.scrollPositions[state.navigation.currentPath],
            listIconSize: state.listIconSize,
            listTextSize: state.listTextSize,
            gridIconSize: state.gridIconSize,
            gridTextSize: state.gridTextSize,
            thumbnailsReady: state.entryThumbnails.thumbnailsReady,
            clipboardItems: Set(state.entryOperations.clipboardItems),
            clipboardOperation: state.entryOperations.clipboardOperation,
        )
    }
}
