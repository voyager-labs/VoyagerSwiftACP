import AppKit
import ComposableArchitecture
import Foundation
import SwiftUI

// swiftlint:disable type_body_length file_length
@Reducer
struct FileManagerFeature {
    struct HistoryEntry: Equatable {
        let navigationState: FileManagerNavigationUtils.NavigationState
        let sidebarItemName: String?
        let composerState: ComposerFeature.State
    }

    struct CollectionContext: Equatable {
        var query: String
        var scopes: [String]
        var conditions: [Condition]
    }

    static func makeWindowTitle(for path: String) -> String {
        if path == "/" {
            return FileManager.default.displayName(atPath: "/")
        }
        if path == SidebarUtils.computerName {
            return path
        }
        return FileManager.default.displayName(atPath: path)
    }

    @ObservableState
    struct State: Equatable {
        var navigationState: FileManagerNavigationUtils.NavigationState = .folder(SettingsFeature.getDefaultTabPath())
        var currentPath: String {
            switch navigationState {
            case let .folder(path): path
            case .recents: "Recents"
            case let .tags(tagName): tagName
            case .computer: SidebarUtils.computerName
            }
        }

        var isTrashFolder: Bool {
            guard case let .folder(path) = navigationState else { return false }
            let trashPath = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first?.path ?? ""
            return path == trashPath || path.starts(with: trashPath + "/")
        }

        var titlePath: String = SettingsFeature.getDefaultTabPath()

        var scrollPositions: [String: CGPoint] = [:]

        var backHistory: [HistoryEntry] = []
        var forwardHistory: [HistoryEntry] = []
        var fsItems: FSItemsFeature.State = .init()
        var viewLayout: ViewLayout = .list
        var showHiddenFiles: Bool = false
        var sidebarVisible: Bool = true
        var inspectorVisible: Bool = false
        var inspectorPaneExists: Bool = false
        var selectedSidebarItem: String?
        var favorites: [SidebarUtils.FavoriteItem] = []
        var locations: [SidebarUtils.LocationItem] = []
        var tags: [SidebarUtils.TagItem] = []
        var isFavoritesCollapsed: Bool = false
        var isLocationsCollapsed: Bool = false
        var isTagsCollapsed: Bool = false
        var columnWidths: ListColumnWidths = .default

        var composer: ComposerFeature.State = .init()
        var pendingSearchQuery: String?
        var collectionContext: CollectionContext?

        var sortKey: SortKey = .name
        var sortOrder: SortOrder = .ascending

        var listIconSize: CGFloat = 20
        var gridIconSize: CGFloat = 64
        var listTextSize: CGFloat = 13
        var gridTextSize: CGFloat = 12

        var canGoBack: Bool {
            !backHistory.isEmpty
        }

        var canGoForward: Bool {
            !forwardHistory.isEmpty
        }

        var canGoToEnclosingDirectory: Bool {
            let url = URL(fileURLWithPath: currentPath)
            let parent = url.deletingLastPathComponent()
            return parent.path != currentPath && currentPath != "/"
        }

        var canOpenSelectedItem: Bool {
            guard !fsItems.selectedIds.isEmpty else {
                return false
            }
            return fsItems.displayItems.contains { fsItems.selectedIds.contains($0.id) }
        }

        var canQuickLookSelectedItem: Bool {
            guard fsItems.selectedIds.count == 1 else {
                return false
            }
            guard let selectedId = fsItems.selectedIds.first else {
                return false
            }
            return fsItems.displayItems.contains(where: { $0.id == selectedId })
        }

        var hasSelectedItems: Bool {
            !fsItems.selectedIds.isEmpty
        }

        var hasClipboardItems: Bool {
            !fsItems.clipboardItems.isEmpty
        }

        var breadcrumbItems: [BreadcrumbUtils.Item] {
            switch navigationState {
            case .recents, .tags:
                return []
            case .computer:
                if fsItems.selectedIds.count == 1,
                   let selectedItem = fsItems.displayItems.first(where: { $0.id == fsItems.selectedIds.first }),
                   selectedItem.fullPath == "/"
                {
                    return []
                }
                return [BreadcrumbUtils.Item(path: SidebarUtils.computerName)]
            case let .folder(path):
                if let rootPath = BreadcrumbUtils.findSpecialRootPath(for: path, isTrashFolder: isTrashFolder) {
                    return BreadcrumbUtils.buildBreadcrumbs(from: rootPath, to: path)
                }
                return BreadcrumbUtils.buildBreadcrumbsForStandardPath(path)
            }
        }

        var selectedBreadcrumbItem: BreadcrumbUtils.Item? {
            guard fsItems.selectedIds.count == 1,
                  let selectedItem = fsItems.displayItems.first(where: { $0.id == fsItems.selectedIds.first })
            else { return nil }

            let selectedBreadcrumb = BreadcrumbUtils.Item(fsItem: selectedItem)

            if selectedBreadcrumb.fullPath == currentPath {
                return nil
            }

            return selectedBreadcrumb
        }

        var windowTitle: String {
            FileManagerFeature.makeWindowTitle(for: titlePath)
        }

        func makeHistoryEntry() -> HistoryEntry {
            HistoryEntry(
                navigationState: navigationState,
                sidebarItemName: selectedSidebarItem,
                composerState: composer,
            )
        }

        mutating func applyHistoryEntry(
            _ entry: HistoryEntry,
            favorites: [SidebarUtils.FavoriteItem],
            locations: [SidebarUtils.LocationItem],
        ) {
            navigationState = entry.navigationState
            selectedSidebarItem = entry.sidebarItemName
            matchSidebarToPath(currentPath, favorites: favorites, locations: locations)
            composer = entry.composerState
            composer.isPresented = false
        }

        mutating func resetComposer() {
            composer = .init()
        }

        mutating func matchSidebarToPath(
            _ path: String,
            favorites: [SidebarUtils.FavoriteItem],
            locations: [SidebarUtils.LocationItem],
        ) {
            selectedSidebarItem = {
                if path == SidebarUtils.computerName {
                    return locations.first(where: { $0.isComputer })?.name ?? path
                }
                if !path.hasPrefix("/") { return path }
                return favorites.first(where: { $0.url.path == path })?.name
                    ?? locations.first(where: { $0.url.path == path })?.name
            }()
        }

        mutating func navigateToFolder(_ path: String, sidebarItemName: String) {
            let previousPath = currentPath
            selectedSidebarItem = sidebarItemName
            let snapshot = makeHistoryEntry()
            resetComposer()
            backHistory.append(snapshot)
            forwardHistory = []
            navigationState = .folder(path)

            if composer.isPresented,
               !composer.scopes.isEmpty,
               composer.scopes[0] == previousPath
            {
                composer.scopes[0] = path
            }
        }

        mutating func navigate(
            to navigationState: FileManagerNavigationUtils.NavigationState,
            sidebarItemName: String,
        ) {
            selectedSidebarItem = sidebarItemName
            let snapshot = makeHistoryEntry()
            resetComposer()
            backHistory.append(snapshot)
            forwardHistory = []
            self.navigationState = navigationState
        }
    }

    enum ViewLayout: String, Equatable, Codable {
        case list
        case grid
    }

    struct ColumnUpdate: Equatable, Sendable {
        let column: ListColumnWidths.Column
        let delta: CGFloat
        let totalWidth: CGFloat
        let padding: CGFloat
        let spacing: CGFloat
    }

    enum Action: Sendable {
        case onAppear
        case navigateTo(String)
        case openSelectedItem
        case quickLookSelectedItem
        case duplicateSelectedItems
        case moveSelectedItemsToTrash
        case deleteSelectedItemsImmediately
        case putBackSelectedItems
        case emptyTrash
        case emptyTrashCompleted
        case closeWindow
        case goBack
        case goForward
        case goToHistoryIndex(Int, isBackHistory: Bool)
        case goToEnclosingDirectory
        case changeLayout(ViewLayout)
        case toggleShowHiddenFiles
        case setSidebarVisible(Bool)
        case toggleInspector
        case setInspectorPaneExists(Bool)
        case saveScrollOffset(CGPoint, forPath: String)
        case showRecents
        case showComputer
        case loadFavorites
        case favoritesLoaded([SidebarUtils.FavoriteItem])
        case openFavorite(SidebarUtils.FavoriteItem)
        case insertFavorite(url: URL, at: Int)
        case removeFavorite(SidebarUtils.FavoriteItem)
        case reorderFavorites(from: IndexSet, to: Int)

        case loadLocations
        case locationsLoaded([SidebarUtils.LocationItem])
        case openLocation(SidebarUtils.LocationItem)

        case loadTags
        case tagsLoaded([SidebarUtils.TagItem])
        case showTag(SidebarUtils.TagItem)

        case changeSortKey(SortKey)
        case changeSortOrder(SortOrder)
        case changeGroupKey(GroupKey)

        case dropItemsToSidebarFolder(providers: [NSItemProvider], targetURL: URL)
        case dropItemsToTag(providers: [NSItemProvider], tagName: String)

        case fsItems(FSItemsFeature.Action)
        case toggleFavoritesSection
        case toggleLocationsSection
        case toggleTagsSection
        case updateColumnWidth(ColumnUpdate)
        case updateListIconSize(CGFloat)
        case updateGridIconSize(CGFloat)
        case updateListTextSize(CGFloat)
        case updateGridTextSize(CGFloat)
        case setSidebarWidth(CGFloat)

        case enterComposer
        case exitComposer
        case composer(ComposerFeature.Action)
    }

    @Dependency(\.fsItemClient)
    var fsItemClient

    var body: some Reducer<State, Action> {
        Scope(state: \.composer, action: \.composer) {
            ComposerFeature()
        }

        Scope(state: \.fsItems, action: \.fsItems) {
            FSItemsFeature()
        }

        Reduce { state, action in
            switch action {
            case .onAppear:
                state.showHiddenFiles = UserDefaults.standard.bool(forKey: "showHiddenFiles")
                state.sidebarVisible = UserDefaults.standard.object(forKey: "sidebarVisible") as? Bool ?? true
                state.sortKey = SortKey(rawValue: UserDefaults.standard.string(forKey: "sortKey") ?? "") ?? .name
                state
                    .sortOrder = SortOrder(rawValue: UserDefaults.standard.string(forKey: "sortOrder") ?? "") ??
                    .ascending

                if let viewLayoutRaw = UserDefaults.standard.string(forKey: "viewLayout"),
                   let savedLayout = ViewLayout(rawValue: viewLayoutRaw)
                {
                    state.viewLayout = savedLayout
                } else {
                    state.viewLayout = .list
                }
                state.fsItems.isListView = state.viewLayout == .list

                if UserDefaults.standard.object(forKey: "columnWidthName") != nil {
                    state.columnWidths = ListColumnWidths(
                        name: CGFloat(UserDefaults.standard.double(forKey: "columnWidthName")),
                        date: CGFloat(UserDefaults.standard.double(forKey: "columnWidthDate")),
                        size: CGFloat(UserDefaults.standard.double(forKey: "columnWidthSize")),
                        kind: CGFloat(UserDefaults.standard.double(forKey: "columnWidthKind")),
                    )
                }

                if let listIconSize = UserDefaults.standard.object(forKey: SettingsKeys.listIconSize) as? CGFloat {
                    state.listIconSize = listIconSize
                }
                if let gridIconSize = UserDefaults.standard.object(forKey: SettingsKeys.gridIconSize) as? CGFloat {
                    state.gridIconSize = gridIconSize
                }

                if let listTextSize = UserDefaults.standard.object(forKey: SettingsKeys.listTextSize) as? CGFloat {
                    state.listTextSize = listTextSize
                }
                if let gridTextSize = UserDefaults.standard.object(forKey: SettingsKeys.gridTextSize) as? CGFloat {
                    state.gridTextSize = gridTextSize
                }

                return .merge(
                    .send(.fsItems(.setShowHidden(state.showHiddenFiles))),
                    .send(.fsItems(.setSortKey(state.sortKey))),
                    .send(.fsItems(.setSortOrder(state.sortOrder))),
                    .send(.fsItems(.loadItems(path: state.currentPath))),
                    .send(.loadFavorites),
                    .send(.loadLocations),
                    .send(.loadTags),
                    .run { send in
                        let listIconSizeKey = "listIconSize"
                        let gridIconSizeKey = "gridIconSize"
                        let listTextSizeKey = "listTextSize"
                        let gridTextSizeKey = "gridTextSize"
                        for await _ in NotificationCenter.default.notifications(
                            named: UserDefaults.didChangeNotification,
                        ) {
                            if let listIconSize = UserDefaults.standard.object(forKey: listIconSizeKey) as? CGFloat {
                                await send(.updateListIconSize(listIconSize))
                            }
                            if let gridIconSize = UserDefaults.standard.object(forKey: gridIconSizeKey) as? CGFloat {
                                await send(.updateGridIconSize(gridIconSize))
                            }
                            if let listTextSize = UserDefaults.standard.object(forKey: listTextSizeKey) as? CGFloat {
                                await send(.updateListTextSize(listTextSize))
                            }
                            if let gridTextSize = UserDefaults.standard.object(forKey: gridTextSizeKey) as? CGFloat {
                                await send(.updateGridTextSize(gridTextSize))
                            }
                        }
                    },
                )

            case let .navigateTo(path):
                if path == SidebarUtils.computerName, state.currentPath == SidebarUtils.computerName {
                    return .none
                }
                if path != state.currentPath {
                    let previousSnapshot = state.makeHistoryEntry()
                    state.resetComposer()
                    state.backHistory.append(previousSnapshot)
                    state.forwardHistory = []
                }
                state.navigationState = .folder(path)
                state.matchSidebarToPath(path, favorites: state.favorites, locations: state.locations)
                let exitEffect = Self.exitCollectionMode(state: &state)
                return .concatenate(
                    exitEffect,
                    .send(.fsItems(.loadItems(path: path))),
                )

            case .openSelectedItem:
                return .send(.fsItems(.openSelectedItem))

            case .quickLookSelectedItem:
                return .send(.fsItems(.quickLookSelectedItem))

            case .duplicateSelectedItems:
                return .send(.fsItems(.duplicateSelectedItems))

            case .moveSelectedItemsToTrash:
                return .send(.fsItems(.moveSelectedItemsToTrash))

            case .deleteSelectedItemsImmediately:
                return .send(.fsItems(.deleteSelectedItemsImmediately))

            case .putBackSelectedItems:
                return .send(.fsItems(.putBackSelectedItems))

            case .emptyTrash:
                return .send(.fsItems(.emptyTrash))

            case .emptyTrashCompleted:
                return .send(.closeWindow)

            case .closeWindow:
                return .run { _ in
                    await MainActor.run {
                        NSApp.keyWindow?.close()
                    }
                }

            case .goBack:
                guard let entry = state.backHistory.popLast() else { return .none }
                let currentSnapshot = state.makeHistoryEntry()
                state.forwardHistory.append(currentSnapshot)
                state.applyHistoryEntry(entry, favorites: state.favorites, locations: state.locations)
                let exitEffect = Self.exitCollectionMode(state: &state)
                return .concatenate(
                    exitEffect,
                    FileManagerNavigationUtils.navigateToState(state.navigationState),
                )

            case .goForward:
                guard let entry = state.forwardHistory.popLast() else { return .none }
                let currentSnapshot = state.makeHistoryEntry()
                state.backHistory.append(currentSnapshot)
                state.applyHistoryEntry(entry, favorites: state.favorites, locations: state.locations)
                let exitEffect = Self.exitCollectionMode(state: &state)
                return .concatenate(
                    exitEffect,
                    FileManagerNavigationUtils.navigateToState(state.navigationState),
                )

            case let .goToHistoryIndex(index, isBackHistory):
                if isBackHistory {
                    guard index < state.backHistory.count else { return .none }
                    let targetIndex = state.backHistory.count - 1 - index
                    let targetEntry = state.backHistory[targetIndex]
                    let trailing = Array(state.backHistory[(targetIndex + 1)...])

                    state.backHistory.removeLast(state.backHistory.count - targetIndex)

                    let currentSnapshot = state.makeHistoryEntry()
                    state.forwardHistory.append(currentSnapshot)
                    state.forwardHistory.append(contentsOf: trailing.reversed())

                    state.applyHistoryEntry(targetEntry, favorites: state.favorites, locations: state.locations)
                    let exitEffect = Self.exitCollectionMode(state: &state)
                    return .concatenate(
                        exitEffect,
                        FileManagerNavigationUtils.navigateToState(state.navigationState),
                    )
                } else {
                    guard index < state.forwardHistory.count else { return .none }
                    let targetIndex = state.forwardHistory.count - 1 - index
                    let targetEntry = state.forwardHistory[targetIndex]
                    let trailing = Array(state.forwardHistory[(targetIndex + 1)...])

                    state.forwardHistory.removeLast(state.forwardHistory.count - targetIndex)

                    let currentSnapshot = state.makeHistoryEntry()
                    state.backHistory.append(currentSnapshot)
                    state.backHistory.append(contentsOf: trailing.reversed())

                    state.applyHistoryEntry(targetEntry, favorites: state.favorites, locations: state.locations)
                    let exitEffect = Self.exitCollectionMode(state: &state)
                    return .concatenate(
                        exitEffect,
                        FileManagerNavigationUtils.navigateToState(state.navigationState),
                    )
                }

            case .goToEnclosingDirectory:
                let url = URL(fileURLWithPath: state.currentPath)
                let parentURL = url.deletingLastPathComponent()

                guard parentURL.path != state.currentPath else { return .none }

                state.navigateToFolder(parentURL.path, sidebarItemName: parentURL.lastPathComponent)
                state.resetComposer()
                let exitEffect = Self.exitCollectionMode(state: &state)
                return .concatenate(
                    exitEffect,
                    .send(.fsItems(.loadItems(path: parentURL.path))),
                )

            case let .changeLayout(layout):
                state.viewLayout = layout
                state.fsItems.isListView = layout == .list
                UserDefaults.standard.set(layout.rawValue, forKey: "viewLayout")
                return .none

            case .toggleShowHiddenFiles:
                state.showHiddenFiles.toggle()
                UserDefaults.standard.set(state.showHiddenFiles, forKey: "showHiddenFiles")
                return .merge(
                    .send(.fsItems(.setShowHidden(state.showHiddenFiles))),
                    .send(.fsItems(.loadItems(path: state.currentPath))),
                )

            case .toggleInspector:
                state.inspectorVisible.toggle()
                return .none

            case let .setInspectorPaneExists(exists):
                state.inspectorPaneExists = exists
                return .none

            case let .saveScrollOffset(offset, forPath: path):
                state.scrollPositions[path] = offset
                return .none

            case let .setSidebarVisible(visible):
                state.sidebarVisible = visible
                UserDefaults.standard.set(visible, forKey: "sidebarVisible")
                return .none

            case .toggleFavoritesSection:
                state.isFavoritesCollapsed.toggle()
                return .none

            case .toggleLocationsSection:
                state.isLocationsCollapsed.toggle()
                return .none

            case .toggleTagsSection:
                state.isTagsCollapsed.toggle()
                return .none

            case let .setSidebarWidth(width):
                let clampedWidth = max(150, min(400, width))
                UserDefaults.standard.set(clampedWidth, forKey: "sidebarWidth")
                return .none

            case let .updateColumnWidth(ctx):
                state.columnWidths = state.columnWidths.updated(
                    column: ctx.column,
                    delta: ctx.delta,
                    totalWidth: ctx.totalWidth,
                    padding: ctx.padding,
                    spacing: ctx.spacing,
                )
                UserDefaults.standard.set(state.columnWidths.name, forKey: "columnWidthName")
                UserDefaults.standard.set(state.columnWidths.date, forKey: "columnWidthDate")
                UserDefaults.standard.set(state.columnWidths.size, forKey: "columnWidthSize")
                UserDefaults.standard.set(state.columnWidths.kind, forKey: "columnWidthKind")
                return .none

            case .showRecents:
                state.navigate(to: .recents, sidebarItemName: "Recents")
                state.resetComposer()
                let exitEffect = Self.exitCollectionMode(state: &state)
                return .concatenate(
                    exitEffect,
                    .send(.fsItems(.loadRecentItems)),
                )

            case .showComputer:
                state.navigate(to: .computer, sidebarItemName: SidebarUtils.computerName)
                state.resetComposer()
                let exitEffect = Self.exitCollectionMode(state: &state)
                return .concatenate(
                    exitEffect,
                    .send(.fsItems(.loadComputerItems)),
                )

            case .loadFavorites:
                return .run { send in
                    let favorites = await SidebarUtils.loadFavorites()
                    await send(.favoritesLoaded(favorites))
                }

            case let .favoritesLoaded(favorites):
                state.favorites = favorites
                return .none

            case let .openFavorite(favorite):
                guard state.currentPath != favorite.url.path else { return .none }
                state.navigateToFolder(favorite.url.path, sidebarItemName: favorite.name)
                state.resetComposer()
                let exitEffect = Self.exitCollectionMode(state: &state)
                return .concatenate(
                    exitEffect,
                    .send(.fsItems(.loadItems(path: favorite.url.path))),
                )

            case let .insertFavorite(url, index):
                if state.favorites.contains(where: { $0.url.path == url.path }) {
                    return .none
                }

                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                    return .none
                }

                let name = FileManager.default.displayName(atPath: url.path)
                let iconName = SidebarUtils.iconNameForURL(url, isDirectory: isDirectory.boolValue)
                let newFavorite = SidebarUtils.FavoriteItem(name: name, url: url, iconName: iconName)

                let insertIndex = max(0, min(index, state.favorites.count))
                state.favorites.insert(newFavorite, at: insertIndex)
                SidebarUtils.saveFavorites(state.favorites)
                return .none

            case let .removeFavorite(favorite):
                state.favorites.removeAll { $0.url.path == favorite.url.path }
                SidebarUtils.saveFavorites(state.favorites)
                return .none

            case let .reorderFavorites(source, destination):
                var reordered = state.favorites
                let sortedIndices = source.sorted(by: >)
                var itemsToMove: [SidebarUtils.FavoriteItem] = []
                for index in sortedIndices {
                    itemsToMove.insert(reordered.remove(at: index), at: 0)
                }
                let maxSourceIndex = source.max() ?? 0
                let adjustedDestination = destination > maxSourceIndex
                    ? destination - itemsToMove.count
                    : destination
                let insertIndex = max(0, min(adjustedDestination, reordered.count))
                reordered.insert(contentsOf: itemsToMove, at: insertIndex)
                state.favorites = reordered
                SidebarUtils.saveFavorites(state.favorites)
                return .none

            case .loadLocations:
                return .run { send in
                    let locations = await SidebarUtils.loadLocations()
                    await send(.locationsLoaded(locations))
                }

            case let .locationsLoaded(locations):
                state.locations = locations
                state.matchSidebarToPath(state.currentPath, favorites: state.favorites, locations: locations)
                return .none

            case let .openLocation(location):
                guard state.currentPath != location.url.path else { return .none }
                state.navigateToFolder(location.url.path, sidebarItemName: location.name)
                state.resetComposer()
                let exitEffect = Self.exitCollectionMode(state: &state)
                return .concatenate(
                    exitEffect,
                    .send(.fsItems(.loadItems(path: location.url.path))),
                )

            case .loadTags:
                return .run { send in
                    let tags = await SidebarUtils.loadTags()
                    await send(.tagsLoaded(tags))
                }

            case let .tagsLoaded(tags):
                state.tags = tags
                return .none

            case let .showTag(tagItem):
                state.navigate(to: .tags(tagItem.name), sidebarItemName: tagItem.name)
                state.resetComposer()
                let exitEffect = Self.exitCollectionMode(state: &state)
                return .concatenate(
                    exitEffect,
                    .send(.fsItems(.loadTagItems(tagName: tagItem.name))),
                )

            case let .changeSortKey(key):
                state.sortKey = key
                UserDefaults.standard.set(key.rawValue, forKey: "sortKey")
                return .send(.fsItems(.setSortKey(key)))

            case let .changeSortOrder(order):
                state.sortOrder = order
                UserDefaults.standard.set(order.rawValue, forKey: "sortOrder")
                return .send(.fsItems(.setSortOrder(order)))

            case let .changeGroupKey(key):
                return .send(.fsItems(.setGroupKey(key)))

            case let .dropItemsToSidebarFolder(providers, targetURL):
                return .send(.fsItems(.handleDrop(
                    providers: providers,
                    destinationPath: targetURL.path,
                )))

            case let .dropItemsToTag(providers, tagName):
                return .send(.fsItems(.handleDropToTag(
                    providers: providers,
                    tagName: tagName,
                )))

            case let .fsItems(action):
                switch action {
                case .itemsLoaded:
                    state.titlePath = state.currentPath
                    return .none

                case .operations(.operationFinished(_, .deleteImmediately, .success)):
                    // emptyTrash 완료 감지
                    if state.isTrashFolder {
                        return .send(.emptyTrashCompleted)
                    }
                    return .none

                case let .navigateFolder(id):
                    guard let item = state.fsItems.displayItems.first(where: { $0.id == id }) else {
                        return .none
                    }
                    state.navigateToFolder(item.fullPath, sidebarItemName: item.name)
                    state.resetComposer()
                    let exitEffect = Self.exitCollectionMode(state: &state)
                    return .concatenate(
                        exitEffect,
                        .send(.fsItems(.loadItems(path: item.fullPath))),
                    )

                default:
                    return .none
                }

            case let .updateListIconSize(size):
                state.listIconSize = size
                return .none

            case let .updateGridIconSize(size):
                state.gridIconSize = size
                return .none

            case let .updateListTextSize(size):
                state.listTextSize = size
                return .none

            case let .updateGridTextSize(size):
                state.gridTextSize = size
                return .none

            case let .composer(action):
                switch action {
                case let .setText(text):
                    let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    state.pendingSearchQuery = query.isEmpty ? nil : query
                    if query.isEmpty, state.composer.conditions.isEmpty, state.composer.scopes.isEmpty {
                        return Self.exitCollectionMode(state: &state)
                    }
                    return .none

                case let .searchResponse(.success(response)):
                    let items = response.items ?? []
                    let query = state.pendingSearchQuery ?? ""
                    state.pendingSearchQuery = nil
                    state.collectionContext = CollectionContext(
                        query: query,
                        scopes: state.composer.scopes,
                        conditions: state.composer.conditions,
                    )
                    return .concatenate(
                        .send(.fsItems(.setCollectionMode(true))),
                        .send(.fsItems(.collectionItemsLoadedFromSearch(items))),
                    )

                case let .filtersResponse(.success(response)):
                    let items = response.items ?? []
                    state.pendingSearchQuery = nil
                    state.collectionContext = CollectionContext(
                        query: "",
                        scopes: state.composer.scopes,
                        conditions: state.composer.conditions,
                    )
                    return .concatenate(
                        .send(.fsItems(.setCollectionMode(true))),
                        .send(.fsItems(.collectionItemsLoadedFromSearch(items))),
                    )

                case .searchResponse(.failure):
                    state.pendingSearchQuery = nil
                    return .none

                case .filtersResponse(.failure):
                    return .none

                case .cancelSearch:
                    state.pendingSearchQuery = nil
                    return .none

                case .clearAll:
                    return Self.exitCollectionMode(state: &state)

                default:
                    return .none
                }

            case .enterComposer:
                let isFirstOpen = state.composer.isPresented == false
                    && state.composer.scopes.isEmpty
                    && state.composer.conditions.isEmpty
                    && state.composer.text.isEmpty

                if isFirstOpen {
                    state.composer.scopes = [state.currentPath]
                }
                state.composer.isPresented = true
                return .none

            case .exitComposer:
                state.composer.isPresented = false
                return .none
            }
        }
    }

    private static func exitCollectionMode(state: inout State) -> Effect<Action> {
        state.collectionContext = nil
        state.pendingSearchQuery = nil
        state.fsItems.collectionItems = []
        return .send(.fsItems(.setCollectionMode(false)))
    }
}

// swiftlint:enable type_body_length
