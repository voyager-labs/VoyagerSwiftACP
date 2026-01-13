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

    struct CollectionContext: Equatable, Sendable {
        var query: String
        var scopes: [String]
        var conditions: [Condition]
    }

    struct CollectionBaseline: Equatable, Sendable {
        var context: CollectionContext
        var sortKey: SortKey
        var sortOrder: SortOrder
        var viewLayout: ViewLayout
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
            case let .collection(navigation):
                switch navigation.kind {
                case .temporary:
                    "New Collection"
                case let .file(_, name):
                    name
                }
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
        var isOpeningCollectionFile: Bool = false
        var openedCollectionName: String?
        var openedCollectionURL: URL?
        var openedCollectionBaseline: CollectionBaseline?
        var collection: CollectionFeature.State = .init()

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
            enclosingDirectoryPath != nil
        }

        var enclosingDirectoryPath: String? {
            switch navigationState {
            case let .folder(path):
                let url = URL(fileURLWithPath: path)
                let parent = url.deletingLastPathComponent()
                guard parent.path != path, path != "/" else { return nil }
                return parent.path

            case let .collection(navigation):
                guard case let .file(url, _) = navigation.kind else { return nil }
                return url.deletingLastPathComponent().path

            case .recents, .tags, .computer:
                return nil
            }
        }

        var canOpenSelectedItem: Bool {
            guard !fsItems.selectedIds.isEmpty else {
                return false
            }
            return fsItems.displayItems.contains { fsItems.selectedIds.contains($0.id) }
        }

        var canQuickLookSelectedItem: Bool {
            guard !fsItems.selectedIds.isEmpty else {
                return false
            }
            return fsItems.displayItems.contains { fsItems.selectedIds.contains($0.id) }
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
            case .collection:
                return []
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

        var canSaveCollection: Bool {
            guard fsItems.isCollectionMode, collectionContext != nil else { return false }
            if openedCollectionBaseline == nil {
                return true
            }
            return isOpenedCollectionDirty
        }

        var isOpenedCollectionDirty: Bool {
            guard let baseline = openedCollectionBaseline, let context = collectionContext else { return false }
            if baseline.context != context { return true }
            if baseline.sortKey != sortKey { return true }
            if baseline.sortOrder != sortOrder { return true }
            if baseline.viewLayout != viewLayout { return true }
            return false
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
            switch entry.navigationState {
            case .collection:
                selectedSidebarItem = nil
            default:
                selectedSidebarItem = entry.sidebarItemName
                matchSidebarToPath(currentPath, favorites: favorites, locations: locations)
            }
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
            appendBackHistory(snapshot)
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
            appendBackHistory(snapshot)
            forwardHistory = []
            self.navigationState = navigationState
        }

        mutating func appendBackHistory(_ entry: HistoryEntry) {
            backHistory.append(entry)
            trimHistory()
        }

        mutating func appendForwardHistory(_ entry: HistoryEntry) {
            forwardHistory.append(entry)
            trimHistory()
        }

        mutating func trimHistory() {
            if backHistory.count > 10 {
                backHistory.removeFirst(backHistory.count - 10)
            }
            if forwardHistory.count > 10 {
                forwardHistory.removeFirst(forwardHistory.count - 10)
            }
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
        case openCollectionFile(URL)
        case collectionFileLoaded(Result<VoyagerCollectionFile, Error>)
        case navigateToCollection(FileManagerNavigationUtils.CollectionNavigation)
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
        case setShowHiddenFiles(Bool)
        case setSidebarVisible(Bool)
        case discardCollectionChanges
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
        case collection(CollectionFeature.Action)
    }

    @Dependency(\.fsItemClient)
    var fsItemClient

    @Dependency(\.collectionFileClient)
    var collectionFileClient

    private nonisolated enum CancelID: Hashable, Sendable {
        case openCollectionFile
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.composer, action: \.composer) {
            ComposerFeature()
        }

        Scope(state: \.collection, action: \.collection) {
            CollectionFeature()
        }

        Scope(state: \.fsItems, action: \.fsItems) {
            FSItemsFeature()
        }

        Reduce { state, action in
            switch action {
            case .onAppear:
                state.showHiddenFiles = UserDefaults.standard.bool(forKey: SettingsKeys.showHiddenFiles)
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
                        let showHiddenFilesKey = "showHiddenFiles"
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
                            let showHiddenFiles = UserDefaults.standard.bool(forKey: showHiddenFilesKey)
                            await send(.setShowHiddenFiles(showHiddenFiles))
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
                    state.appendBackHistory(previousSnapshot)
                    state.forwardHistory = []
                }
                state.navigationState = .folder(path)
                state.matchSidebarToPath(path, favorites: state.favorites, locations: state.locations)
                let exitEffect = Self.exitCollectionMode(state: &state)
                return .concatenate(
                    exitEffect,
                    .send(.fsItems(.loadItems(path: path))),
                )

            case let .openCollectionFile(url):
                let exitEffect = Self.clearCollectionMode(state: &state)
                if case .collection = state.navigationState {
                    // 이미 콜렉션 상태면 히스토리에는 중복 추가하지 않음
                } else {
                    let directoryPath = url.deletingLastPathComponent().path
                    var previousSnapshot = state.makeHistoryEntry()
                    previousSnapshot = HistoryEntry(
                        navigationState: .folder(directoryPath),
                        sidebarItemName: nil,
                        composerState: previousSnapshot.composerState,
                    )
                    state.appendBackHistory(previousSnapshot)
                    state.forwardHistory = []
                }
                state.isOpeningCollectionFile = true
                state.openedCollectionName = url.deletingPathExtension().lastPathComponent
                state.openedCollectionURL = url
                state.openedCollectionBaseline = nil
                state.selectedSidebarItem = state.favorites
                    .first(where: { $0.url.path == url.path })
                    .map(\.displayName)
                let loadEffect: Effect<Action> = .run { [collectionFileClient, url] send in
                    do {
                        let file = try await collectionFileClient.load(url)
                        try Task.checkCancellation()
                        await send(.collectionFileLoaded(.success(file)))
                    } catch is CancellationError {
                        return
                    } catch {
                        await send(.collectionFileLoaded(.failure(error)))
                    }
                }
                .cancellable(id: CancelID.openCollectionFile, cancelInFlight: true)

                return .concatenate(
                    exitEffect,
                    loadEffect,
                )

            case let .navigateToCollection(navigation):
                state.composer.isPresented = false
                state.collectionContext = navigation.context
                state.pendingSearchQuery = navigation.context.query.isEmpty ? nil : navigation.context.query
                state.sortKey = navigation.sortKey
                state.sortOrder = navigation.sortOrder
                state.viewLayout = navigation.viewLayout
                state.fsItems.isListView = navigation.viewLayout == .list

                switch navigation.kind {
                case .temporary:
                    state.openedCollectionName = nil
                    state.openedCollectionURL = nil
                    state.selectedSidebarItem = nil
                case let .file(url, name):
                    state.openedCollectionName = name
                    state.openedCollectionURL = url
                    state.selectedSidebarItem = state.favorites
                        .first(where: { $0.url.path == url.path })
                        .map(\.displayName) ?? name
                }

                if case .file = navigation.kind {
                    state.composer.text = ""
                } else {
                    state.composer.text = navigation.context.query
                }
                state.composer.scopes = navigation.context.scopes
                state.composer.conditions = navigation.context.conditions
                state.composer.propertyPicker = .init()
                state.composer.operatorPicker = .init()
                state.composer.valuePicker = .init()
                state.composer.clearHistory()

                let trimmedQuery = navigation.context.query.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmedQuery.isEmpty
                    ? .send(.composer(.applyFilters))
                    : .send(.composer(.submit))

            case let .collectionFileLoaded(result):
                switch result {
                case let .success(file):
                    state.composer.isPresented = false
                    let trimmedQuery = file.query.trimmingCharacters(in: .whitespacesAndNewlines)
                    state.pendingSearchQuery = trimmedQuery.isEmpty ? nil : trimmedQuery

                    let resolved = resolveCollectionFilters(from: file)
                    if trimmedQuery.isEmpty, resolved.scopes.isEmpty, resolved.conditions.isEmpty {
                        state.isOpeningCollectionFile = false
                        state.openedCollectionName = nil
                        state.openedCollectionBaseline = nil
                        return .run { _ in
                            await showCollectionOpenErrorAlert(
                                title: "Empty Collection",
                                message: "This collection file has no query, scope, or filters.",
                            )
                        }
                    }

                    state.composer.text = ""
                    state.composer.scopes = resolved.scopes
                    state.composer.conditions = resolved.conditions
                    state.composer.propertyPicker = .init()
                    state.composer.operatorPicker = .init()
                    state.composer.valuePicker = .init()
                    state.composer.clearHistory()

                    let baselineSortKey = sortKey(from: file) ?? state.sortKey
                    let baselineSortOrder = sortOrder(from: file) ?? state.sortOrder
                    let baselineViewLayout = viewLayout(from: file) ?? state.viewLayout
                    state.openedCollectionBaseline = CollectionBaseline(
                        context: CollectionContext(
                            query: trimmedQuery,
                            scopes: resolved.scopes,
                            conditions: resolved.conditions,
                        ),
                        sortKey: baselineSortKey,
                        sortOrder: baselineSortOrder,
                        viewLayout: baselineViewLayout,
                    )

                    var effects: [Effect<Action>] = []
                    if let sortKey = sortKey(from: file), sortKey != state.sortKey {
                        effects.append(.send(.changeSortKey(sortKey)))
                    }
                    if let sortOrder = sortOrder(from: file), sortOrder != state.sortOrder {
                        effects.append(.send(.changeSortOrder(sortOrder)))
                    }
                    if let viewLayout = viewLayout(from: file), viewLayout != state.viewLayout {
                        effects.append(.send(.changeLayout(viewLayout)))
                    }

                    let searchEffect: Effect<Action> = state.isOpeningCollectionFile
                        ? .send(.composer(.applyFilters))
                        : (trimmedQuery.isEmpty
                            ? .send(.composer(.applyFilters))
                            : .send(.composer(.submit)))
                    effects.append(searchEffect)

                    return .concatenate(effects)

                case let .failure(error):
                    if !state.backHistory.isEmpty {
                        state.backHistory.removeLast()
                    }
                    state.isOpeningCollectionFile = false
                    state.openedCollectionName = nil
                    state.openedCollectionURL = nil
                    state.openedCollectionBaseline = nil
                    state.resetComposer()
                    let exitEffect = Self.exitCollectionMode(state: &state)
                    return .merge(
                        exitEffect,
                        .run { _ in
                            await showCollectionOpenErrorAlert(
                                title: "Unable to Open Collection",
                                message: error.localizedDescription,
                            )
                        },
                    )
                }

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
                state.appendForwardHistory(currentSnapshot)
                state.applyHistoryEntry(entry, favorites: state.favorites, locations: state.locations)
                let exitEffect = Self.clearCollectionMode(state: &state)
                return .concatenate(
                    exitEffect,
                    FileManagerNavigationUtils.navigateToState(state.navigationState),
                )

            case .goForward:
                guard let entry = state.forwardHistory.popLast() else { return .none }
                let currentSnapshot = state.makeHistoryEntry()
                state.appendBackHistory(currentSnapshot)
                state.applyHistoryEntry(entry, favorites: state.favorites, locations: state.locations)
                let exitEffect = Self.clearCollectionMode(state: &state)
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
                    state.appendForwardHistory(currentSnapshot)
                    state.forwardHistory.append(contentsOf: trailing.reversed())
                    state.trimHistory()

                    state.applyHistoryEntry(targetEntry, favorites: state.favorites, locations: state.locations)
                    let exitEffect = Self.clearCollectionMode(state: &state)
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
                    state.appendBackHistory(currentSnapshot)
                    state.backHistory.append(contentsOf: trailing.reversed())
                    state.trimHistory()

                    state.applyHistoryEntry(targetEntry, favorites: state.favorites, locations: state.locations)
                    let exitEffect = Self.clearCollectionMode(state: &state)
                    return .concatenate(
                        exitEffect,
                        FileManagerNavigationUtils.navigateToState(state.navigationState),
                    )
                }

            case .goToEnclosingDirectory:
                guard let parentPath = state.enclosingDirectoryPath else { return .none }
                let parentURL = URL(fileURLWithPath: parentPath)
                let childName = URL(fileURLWithPath: state.currentPath).lastPathComponent
                if !childName.isEmpty {
                    state.fsItems.selectAfterLoadFileNames = [childName]
                }
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
                UserDefaults.standard.set(state.showHiddenFiles, forKey: SettingsKeys.showHiddenFiles)
                return Self.applyShowHiddenFilesChange(state: &state)

            case let .setShowHiddenFiles(isEnabled):
                guard state.showHiddenFiles != isEnabled else { return .none }
                state.showHiddenFiles = isEnabled
                return Self.applyShowHiddenFilesChange(state: &state)

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
                    .send(.fsItems(.loadRecentItems(showHidden: state.showHiddenFiles))),
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
                if favorite.url.pathExtension.lowercased() == "voycoll" {
                    if state.openedCollectionURL?.path == favorite.url.path {
                        return .none
                    }
                    state.selectedSidebarItem = favorite.displayName
                    return .send(.openCollectionFile(favorite.url))
                }
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
                let isVoycoll = url.pathExtension.lowercased() == "voycoll"
                guard isDirectory.boolValue || isVoycoll else {
                    return .none
                }

                let name = isVoycoll
                    ? url.deletingPathExtension().lastPathComponent
                    : FileManager.default.displayName(atPath: url.path)
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
                    .send(.fsItems(.loadTagItems(tagName: tagItem.name, showHidden: state.showHiddenFiles))),
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

                case let .openCollectionFile(url):
                    return .send(.openCollectionFile(url))

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

            case .discardCollectionChanges:
                guard let baseline = state.openedCollectionBaseline,
                      state.fsItems.isCollectionMode,
                      state.isOpenedCollectionDirty
                else {
                    return .none
                }

                let trimmedQuery = baseline.context.query.trimmingCharacters(in: .whitespacesAndNewlines)
                state.pendingSearchQuery = trimmedQuery.isEmpty ? nil : trimmedQuery
                state.collectionContext = baseline.context
                state.sortKey = baseline.sortKey
                state.sortOrder = baseline.sortOrder
                state.viewLayout = baseline.viewLayout
                state.fsItems.isListView = baseline.viewLayout == .list

                if state.openedCollectionURL == nil {
                    state.composer.text = baseline.context.query
                } else {
                    state.composer.text = ""
                }
                state.composer.scopes = baseline.context.scopes
                state.composer.conditions = baseline.context.conditions
                state.composer.propertyPicker = .init()
                state.composer.operatorPicker = .init()
                state.composer.valuePicker = .init()
                state.composer.clearHistory()

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
                    let wasOpeningCollectionFile = state.isOpeningCollectionFile
                    state.isOpeningCollectionFile = false
                    let previousSnapshot = state.makeHistoryEntry()
                    let previousNavigationState = state.navigationState
                    let items = response.items ?? []
                    let query = state.pendingSearchQuery ?? ""
                    state.pendingSearchQuery = nil
                    state.collectionContext = CollectionContext(
                        query: query,
                        scopes: state.composer.scopes,
                        conditions: state.composer.conditions,
                    )
                    if wasOpeningCollectionFile, state.openedCollectionURL != nil {
                        state.openedCollectionBaseline = CollectionBaseline(
                            context: state.collectionContext ?? .init(query: "", scopes: [], conditions: []),
                            sortKey: state.sortKey,
                            sortOrder: state.sortOrder,
                            viewLayout: state.viewLayout,
                        )
                    }
                    state.selectedSidebarItem = state.openedCollectionURL.flatMap { url in
                        state.favorites
                            .first(where: { $0.url.path == url.path })
                            .map(\.displayName) ?? state.openedCollectionName
                    }
                    let nextNavigationState = FileManagerNavigationUtils.NavigationState.collection(
                        makeCollectionNavigation(state: state),
                    )
                    if !wasOpeningCollectionFile, previousNavigationState != nextNavigationState {
                        state.appendBackHistory(previousSnapshot)
                        state.forwardHistory = []
                    }
                    state.navigationState = nextNavigationState
                    return .concatenate(
                        .send(.fsItems(.setCollectionMode(true))),
                        .send(.fsItems(.collectionItemsLoadedFromSearch(items))),
                    )

                case let .filtersResponse(.success(response)):
                    let wasOpeningCollectionFile = state.isOpeningCollectionFile
                    state.isOpeningCollectionFile = false
                    let previousSnapshot = state.makeHistoryEntry()
                    let previousNavigationState = state.navigationState
                    let items = response.items ?? []
                    state.pendingSearchQuery = nil
                    state.collectionContext = CollectionContext(
                        query: "",
                        scopes: state.composer.scopes,
                        conditions: state.composer.conditions,
                    )
                    if wasOpeningCollectionFile, state.openedCollectionURL != nil {
                        state.openedCollectionBaseline = CollectionBaseline(
                            context: state.collectionContext ?? .init(query: "", scopes: [], conditions: []),
                            sortKey: state.sortKey,
                            sortOrder: state.sortOrder,
                            viewLayout: state.viewLayout,
                        )
                    }
                    state.selectedSidebarItem = state.openedCollectionURL.flatMap { url in
                        state.favorites
                            .first(where: { $0.url.path == url.path })
                            .map(\.displayName) ?? state.openedCollectionName
                    }
                    let nextNavigationState = FileManagerNavigationUtils.NavigationState.collection(
                        makeCollectionNavigation(state: state),
                    )
                    if !wasOpeningCollectionFile, previousNavigationState != nextNavigationState {
                        state.appendBackHistory(previousSnapshot)
                        state.forwardHistory = []
                    }
                    state.navigationState = nextNavigationState
                    return .concatenate(
                        .send(.fsItems(.setCollectionMode(true))),
                        .send(.fsItems(.collectionItemsLoadedFromSearch(items))),
                    )

                case let .searchResponse(.failure(error)):
                    state.pendingSearchQuery = nil
                    if state.isOpeningCollectionFile {
                        if !state.backHistory.isEmpty {
                            state.backHistory.removeLast()
                        }
                        state.isOpeningCollectionFile = false
                        state.openedCollectionName = nil
                        state.openedCollectionURL = nil
                        state.openedCollectionBaseline = nil
                        state.resetComposer()
                        let exitEffect = Self.exitCollectionMode(state: &state)
                        return .merge(
                            exitEffect,
                            .run { _ in
                                await showCollectionOpenErrorAlert(
                                    title: "Unable to Run Collection Search",
                                    message: """
                                    \(error.localizedDescription)

                                    Make sure the backend is running and try again.
                                    """,
                                )
                            },
                        )
                    }
                    return .none

                case let .filtersResponse(.failure(error)):
                    if state.isOpeningCollectionFile {
                        if !state.backHistory.isEmpty {
                            state.backHistory.removeLast()
                        }
                        state.isOpeningCollectionFile = false
                        state.openedCollectionName = nil
                        state.openedCollectionURL = nil
                        state.openedCollectionBaseline = nil
                        state.resetComposer()
                        let exitEffect = Self.exitCollectionMode(state: &state)
                        return .merge(
                            exitEffect,
                            .run { _ in
                                await showCollectionOpenErrorAlert(
                                    title: "Unable to Apply Collection Filters",
                                    message: """
                                    \(error.localizedDescription)

                                    Make sure the backend is running and try again.
                                    """,
                                )
                            },
                        )
                    }
                    return .none

                case .cancelSearch:
                    state.pendingSearchQuery = nil
                    state.isOpeningCollectionFile = false
                    state.openedCollectionName = nil
                    return .none

                case .clearAll:
                    if state.fsItems.isCollectionMode {
                        state.pendingSearchQuery = nil
                        state.collectionContext = CollectionContext(
                            query: "",
                            scopes: [ComposerScopeUtils.rootScopePath],
                            conditions: [],
                        )
                        return .none
                    }
                    return Self.exitCollectionMode(state: &state)

                case .saveCollection:
                    guard state.canSaveCollection else {
                        return .none
                    }
                    let payload = CollectionFeature.SaveRequestPayload(
                        context: state.collectionContext,
                        sortKey: state.sortKey.rawValue,
                        sortOrder: state.sortOrder.rawValue,
                        viewLayout: state.viewLayout.rawValue,
                        isSearchLoading: state.composer.isLoadingSearch,
                        isFiltersLoading: state.composer.isLoadingFilters,
                    )
                    if let url = state.openedCollectionURL {
                        return .send(.collection(.saveToExisting(payload, url)))
                    }
                    return .send(.collection(.saveRequested(payload)))

                case .saveCollectionAs:
                    guard state.canSaveCollection else {
                        return .none
                    }
                    return .send(.collection(.saveRequested(.init(
                        context: state.collectionContext,
                        sortKey: state.sortKey.rawValue,
                        sortOrder: state.sortOrder.rawValue,
                        viewLayout: state.viewLayout.rawValue,
                        isSearchLoading: state.composer.isLoadingSearch,
                        isFiltersLoading: state.composer.isLoadingFilters,
                    ))))

                default:
                    return .none
                }

            case let .collection(action):
                switch action {
                case let .saveCompleted(.success(url)):
                    state.openedCollectionURL = url
                    state.openedCollectionName = url.deletingPathExtension().lastPathComponent

                    if let context = state.collectionContext {
                        state.openedCollectionBaseline = CollectionBaseline(
                            context: context,
                            sortKey: state.sortKey,
                            sortOrder: state.sortOrder,
                            viewLayout: state.viewLayout,
                        )
                    } else {
                        state.openedCollectionBaseline = nil
                    }

                    state.navigationState = .collection(makeCollectionNavigation(state: state))
                    return .none

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
        let wasCollection = if case .collection = state.navigationState { true } else { false }
        let clearEffect = clearCollectionMode(state: &state)

        guard wasCollection else {
            return clearEffect
        }

        state.navigationState = FileManagerNavigationUtils.navigationStateFromPath(state.titlePath)
        state.matchSidebarToPath(state.currentPath, favorites: state.favorites, locations: state.locations)
        return clearEffect
    }

    private static func applyShowHiddenFilesChange(state: inout State) -> Effect<Action> {
        switch state.navigationState {
        case .recents:
            .merge(
                .send(.fsItems(.setShowHidden(state.showHiddenFiles))),
                .send(.fsItems(.loadRecentItems(showHidden: state.showHiddenFiles))),
            )
        case let .tags(tagName):
            .merge(
                .send(.fsItems(.setShowHidden(state.showHiddenFiles))),
                .send(.fsItems(.loadTagItems(tagName: tagName, showHidden: state.showHiddenFiles))),
            )
        case .computer:
            .merge(
                .send(.fsItems(.setShowHidden(state.showHiddenFiles))),
                .send(.fsItems(.loadComputerItems)),
            )
        case .folder, .collection:
            .merge(
                .send(.fsItems(.setShowHidden(state.showHiddenFiles))),
                .send(.fsItems(.loadItems(path: state.currentPath))),
            )
        }
    }

    private static func clearCollectionMode(state: inout State) -> Effect<Action> {
        state.collectionContext = nil
        state.pendingSearchQuery = nil
        state.isOpeningCollectionFile = false
        state.openedCollectionName = nil
        state.openedCollectionURL = nil
        state.openedCollectionBaseline = nil
        state.fsItems.collectionItems = []
        return .merge(
            .cancel(id: CancelID.openCollectionFile),
            .cancel(id: ComposerFeature.CancelID.search),
            .cancel(id: ComposerFeature.CancelID.filters),
            .send(.fsItems(.setCollectionMode(false))),
        )
    }
}

private func makeCollectionNavigation(
    state: FileManagerFeature.State,
) -> FileManagerNavigationUtils.CollectionNavigation {
    let context = state.collectionContext ?? .init(query: "", scopes: [], conditions: [])
    let kind: FileManagerNavigationUtils.CollectionKind = if let url = state.openedCollectionURL,
                                                             let name = state.openedCollectionName
    {
        .file(url: url, name: name)
    } else {
        .temporary
    }
    return .init(
        kind: kind,
        context: context,
        sortKey: state.sortKey,
        sortOrder: state.sortOrder,
        viewLayout: state.viewLayout,
    )
}

private func resolveCollectionFilters(from file: VoyagerCollectionFile) -> (scopes: [String], conditions: [Condition]) {
    let conditionPayloads = file.conditions.map { condition in
        SearchConditionPayload(
            propertyKey: condition.propertyKey,
            operator: condition.operatorCode,
            value: condition.value,
        )
    }
    let appliedFilters = AppliedFiltersPayload(scopes: file.scopes, conditions: conditionPayloads)
    return AppliedFiltersUtils.resolve(
        appliedFilters,
        fallbackScopes: file.scopes,
        fallbackConditions: [],
    )
}

private func sortKey(from file: VoyagerCollectionFile) -> SortKey? {
    guard let rawValue = file.sortKey else { return nil }
    return SortKey(rawValue: rawValue)
}

private func sortOrder(from file: VoyagerCollectionFile) -> SortOrder? {
    guard let rawValue = file.sortOrder else { return nil }
    return SortOrder(rawValue: rawValue)
}

private func viewLayout(from file: VoyagerCollectionFile) -> FileManagerFeature.ViewLayout? {
    guard let rawValue = file.viewLayout else { return nil }
    return FileManagerFeature.ViewLayout(rawValue: rawValue)
}

@MainActor
private func showCollectionOpenErrorAlert(title: String, message: String) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: "OK")
    alert.runModal()
}

// swiftlint:enable type_body_length
