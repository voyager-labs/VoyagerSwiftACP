import AppKit
import ComposableArchitecture
import Foundation
import SwiftUI

// swiftlint:disable type_body_length file_length
@Reducer
struct FileManagerFeature {
    static func makeWindowTitle(for path: String) -> String {
        if path == "/" {
            return FileManager.default.displayName(atPath: "/")
        }
        return FileManager.default.displayName(atPath: path)
    }

    @ObservableState
    struct State: Equatable {
        var navigationState: FileManagerNavigationUtils.NavigationState = .folder(SettingsFeature.getDefaultTabPath())
        var currentPath: String {
            switch navigationState {
            case let .folder(path): return path
            case .recents: return "Recents"
            case let .tags(tagName): return tagName
            }
        }

        var isTrashFolder: Bool {
            guard case let .folder(path) = navigationState else { return false }
            let trashPath = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first?.path ?? ""
            return path == trashPath || path.starts(with: trashPath + "/")
        }

        var titlePath: String = SettingsFeature.getDefaultTabPath()

        var scrollPositions: [String: CGPoint] = [:]

        var backHistory: [String] = []
        var forwardHistory: [String] = []
        var fsItems: FSItemsFeature.State = .init()
        var viewLayout: ViewLayout = .list
        var showHiddenFiles: Bool = false
        var sidebarVisible: Bool = true
        var selectedSidebarItem: String?
        var favorites: [SidebarUtils.FavoriteItem] = []
        var locations: [SidebarUtils.LocationItem] = []
        var tags: [SidebarUtils.TagItem] = []
        var isFavoritesCollapsed: Bool = false
        var isLocationsCollapsed: Bool = false
        var isTagsCollapsed: Bool = false
        var columnWidths: ListColumnWidths = .default

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
            return fsItems.items.contains { fsItems.selectedIds.contains($0.id) }
        }

        var canQuickLookSelectedItem: Bool {
            guard fsItems.selectedIds.count == 1 else {
                return false
            }
            guard let selectedId = fsItems.selectedIds.first else {
                return false
            }
            return fsItems.items.contains(where: { $0.id == selectedId })
        }

        var breadcrumbItems: [BreadcrumbUtils.Item] {
            switch navigationState {
            case .recents, .tags:
                return []
            case let .folder(path):
                if isTrashFolder {
                    guard let trashURL = FileManager.default.urls(
                        for: .trashDirectory,
                        in: .userDomainMask
                    ).first else {
                        return []
                    }

                    var result: [BreadcrumbUtils.Item] = []
                    result.append(BreadcrumbUtils.Item(path: trashURL.path))

                    if path != trashURL.path {
                        let relativePath = path.replacingOccurrences(of: trashURL.path + "/", with: "")
                        let components = relativePath.split(separator: "/").map(String.init)
                        var accumulated = trashURL.path

                        for component in components {
                            accumulated += "/" + component
                            result.append(BreadcrumbUtils.Item(path: accumulated))
                        }
                    }

                    return result
                }

                var result: [BreadcrumbUtils.Item] = []

                if path.hasPrefix("/") {
                    result.append(BreadcrumbUtils.Item(path: "/"))
                }

                let components = path.split(separator: "/").map(String.init)
                var accumulated = "/"

                for component in components {
                    accumulated += component
                    result.append(BreadcrumbUtils.Item(path: accumulated))
                    accumulated += "/"
                }

                return result
            }
        }

        var selectedBreadcrumbItem: BreadcrumbUtils.Item? {
            guard fsItems.selectedIds.count == 1,
                  let selectedItem = fsItems.items.first(where: { $0.id == fsItems.selectedIds.first })
            else { return nil }

            return BreadcrumbUtils.Item(fsItem: selectedItem)
        }

        var windowTitle: String {
            FileManagerFeature.makeWindowTitle(for: titlePath)
        }

        mutating func matchSidebarToPath(
            _ path: String,
            favorites: [SidebarUtils.FavoriteItem],
            locations: [SidebarUtils.LocationItem]
        ) {
            selectedSidebarItem = {
                if !path.hasPrefix("/") { return path }
                return favorites.first(where: { $0.url.path == path })?.name
                    ?? locations.first(where: { $0.url.path == path })?.name
            }()
        }

        mutating func navigateToFolder(_ path: String, sidebarItemName: String) {
            selectedSidebarItem = sidebarItemName
            backHistory.append(currentPath)
            forwardHistory = []
            navigationState = .folder(path)
        }

        mutating func navigate(
            to navigationState: FileManagerNavigationUtils.NavigationState,
            sidebarItemName: String
        ) {
            selectedSidebarItem = sidebarItemName
            backHistory.append(currentPath)
            forwardHistory = []
            self.navigationState = navigationState
        }

        mutating func navigateFromHistory(
            to path: String,
            addToForward: Bool,
            locations: [SidebarUtils.LocationItem]
        ) {
            if addToForward {
                forwardHistory.append(currentPath)
            } else {
                backHistory.append(currentPath)
            }
            navigationState = FileManagerNavigationUtils.navigationStateFromPath(path)
            matchSidebarToPath(path, favorites: favorites, locations: locations)
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
        case saveScrollOffset(CGPoint, forPath: String)
        case showRecents
        case loadFavorites
        case favoritesLoaded([SidebarUtils.FavoriteItem])
        case openFavorite(SidebarUtils.FavoriteItem)

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
    }

    @Dependency(\.fsItemClient)
    var fsItemClient

    var body: some Reducer<State, Action> {
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
                        kind: CGFloat(UserDefaults.standard.double(forKey: "columnWidthKind"))
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
                            named: UserDefaults.didChangeNotification
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
                    }
                )

            case let .navigateTo(path):
                if path != state.currentPath {
                    state.backHistory.append(state.currentPath)
                    state.forwardHistory = []
                }
                state.navigationState = .folder(path)
                state.matchSidebarToPath(path, favorites: state.favorites, locations: state.locations)
                return .send(.fsItems(.loadItems(path: path)))

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
                guard let previousPath = state.backHistory.popLast() else { return .none }
                state.navigateFromHistory(to: previousPath, addToForward: true, locations: state.locations)
                return FileManagerNavigationUtils.navigateToState(state.navigationState)

            case .goForward:
                guard let nextPath = state.forwardHistory.popLast() else { return .none }
                state.navigateFromHistory(to: nextPath, addToForward: false, locations: state.locations)
                return FileManagerNavigationUtils.navigateToState(state.navigationState)

            case let .goToHistoryIndex(index, isBackHistory):
                if isBackHistory {
                    guard index < state.backHistory.count else { return .none }
                    let targetPath = state.backHistory[state.backHistory.count - 1 - index]

                    for idx in (state.backHistory.count - index) ..< state.backHistory.count {
                        state.forwardHistory.append(state.backHistory[idx])
                    }
                    state.forwardHistory.append(state.currentPath)

                    state.backHistory.removeLast(index + 1)

                    state.navigationState = FileManagerNavigationUtils.navigationStateFromPath(targetPath)
                    state.matchSidebarToPath(targetPath, favorites: state.favorites, locations: state.locations)
                    return FileManagerNavigationUtils.navigateToState(state.navigationState)
                } else {
                    guard index < state.forwardHistory.count else { return .none }
                    let targetPath = state.forwardHistory[state.forwardHistory.count - 1 - index]

                    for idx in (state.forwardHistory.count - index) ..< state.forwardHistory.count {
                        state.backHistory.append(state.forwardHistory[idx])
                    }
                    state.backHistory.append(state.currentPath)

                    state.forwardHistory.removeLast(index + 1)

                    state.navigationState = FileManagerNavigationUtils.navigationStateFromPath(targetPath)
                    state.matchSidebarToPath(targetPath, favorites: state.favorites, locations: state.locations)
                    return FileManagerNavigationUtils.navigateToState(state.navigationState)
                }

            case .goToEnclosingDirectory:
                let url = URL(fileURLWithPath: state.currentPath)
                let parentURL = url.deletingLastPathComponent()

                guard parentURL.path != state.currentPath else { return .none }

                state.navigateToFolder(parentURL.path, sidebarItemName: parentURL.lastPathComponent)
                return .send(.fsItems(.loadItems(path: parentURL.path)))

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
                    .send(.fsItems(.loadItems(path: state.currentPath)))
                )

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

            case let .updateColumnWidth(ctx):
                state.columnWidths = state.columnWidths.updated(
                    column: ctx.column,
                    delta: ctx.delta,
                    totalWidth: ctx.totalWidth,
                    padding: ctx.padding,
                    spacing: ctx.spacing
                )
                UserDefaults.standard.set(state.columnWidths.name, forKey: "columnWidthName")
                UserDefaults.standard.set(state.columnWidths.date, forKey: "columnWidthDate")
                UserDefaults.standard.set(state.columnWidths.size, forKey: "columnWidthSize")
                UserDefaults.standard.set(state.columnWidths.kind, forKey: "columnWidthKind")
                return .none

            case .showRecents:
                state.navigate(to: .recents, sidebarItemName: "Recents")
                return .send(.fsItems(.loadRecentItems))

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
                return .send(.fsItems(.loadItems(path: favorite.url.path)))

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
                return .send(.fsItems(.loadItems(path: location.url.path)))

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
                return .send(.fsItems(.loadTagItems(tagName: tagItem.name)))

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
                    destinationPath: targetURL.path
                )))

            case let .dropItemsToTag(providers, tagName):
                return .send(.fsItems(.handleDropToTag(
                    providers: providers,
                    tagName: tagName
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
                    guard let item = state.fsItems.items.first(where: { $0.id == id }) else {
                        return .none
                    }
                    state.navigateToFolder(item.fullPath, sidebarItemName: item.name)
                    return .send(.fsItems(.loadItems(path: item.fullPath)))

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
            }
        }
    }
}

// swiftlint:enable type_body_length
