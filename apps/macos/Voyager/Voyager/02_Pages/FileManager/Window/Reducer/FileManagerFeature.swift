import AppKit
import ComposableArchitecture
import Foundation
import SwiftUI

// swiftlint:disable type_body_length file_length
@Reducer
struct FileManagerFeature {
    @Dependency(\.entryClient)
    var entryClient
    @Dependency(\.collectionFileClient)
    var collectionFileClient
    @Dependency(\.collectionAlertClient)
    var collectionAlertClient
    @Dependency(\.userDefaultsClient)
    var userDefaultsClient
    @Dependency(\.fileManagerNavigationClient)
    var navigationClient
    @Dependency(\.registryClient)
    var registryClient

    struct HistoryEntry: Equatable {
        let navigationState: FileManagerNavigationUtils.NavigationState
        let sidebarItemName: String?
        let composerState: ComposerFeature.State
    }

    struct CollectionBaseline: Equatable, Sendable {
        var context: CollectionContext
        var sortKey: SortKey
        var sortOrder: SortOrder
        var viewLayout: ViewLayout
    }

    func makeWindowTitle(for path: String) -> String {
        if path == "/" {
            return navigationClient.computerName()
        }
        if path == navigationClient.computerName() {
            return path
        }
        return entryClient.displayName(path)
    }

    static func makeWindowTitle(for path: String) -> String {
        let navigationClient = FileManagerNavigationClient.liveValue
        if path == "/" {
            return navigationClient.computerName()
        }
        if path == navigationClient.computerName() {
            return path
        }
        return EntryClient.liveValue.displayName(path)
    }

    @ObservableState
    struct State: Equatable {
        var navigationState: FileManagerNavigationUtils.NavigationState = .folder(SettingsDefaults.defaultTabPath())
        var currentPath: String {
            switch navigationState {
            case let .folder(path): path
            case .recents: "Recents"
            case let .tags(tagName): tagName
            case .computer: "" // Will be computed in View using navigationClient
            case let .collection(navigation):
                switch navigation.kind {
                case .temporary:
                    "New Collection"
                case let .file(_, name):
                    name
                }
            }
        }

        var titlePath: String = SettingsDefaults.defaultTabPath()

        var scrollPositions: [String: CGPoint] = [:]

        var backHistory: [HistoryEntry] = []
        var forwardHistory: [HistoryEntry] = []
        var entries: EntriesFeature.State = .init()
        var viewLayout: ViewLayout = .list
        var showHiddenFiles: Bool = false
        var sidebarVisible: Bool = true
        var inspectorVisible: Bool = false
        var inspectorPaneExists: Bool = false
        var selectedSidebarItem: String?
        var favorites: [SidebarItems.FavoriteItem] = []
        var locations: [SidebarItems.LocationItem] = []
        var tags: [SidebarItems.TagItem] = []
        var isFavoritesCollapsed: Bool = false
        var isLocationsCollapsed: Bool = false
        var isTagsCollapsed: Bool = false
        var columnWidths: ListColumnWidthsUtils = .default
        var pendingSidebarSelectionRestore: String?

        var composer: ComposerFeature.State = .init()
        var pendingSearchQuery: String?
        var collectionContext: CollectionContext?
        var isOpeningCollectionFile: Bool = false
        var openedCollectionName: String?
        var openedCollectionURL: URL?
        var openedCollectionBaseline: CollectionBaseline?
        var collectionOriginURL: URL?
        var isSaveAsPendingFromCollection: Bool = false
        var pendingNavigation: PendingNavigation?
        var resetComposerOnNextDirectoryNavigation: Bool = false
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
            guard !entries.selectedIds.isEmpty else {
                return false
            }
            return entries.displayItems.contains { entries.selectedIds.contains($0.id) }
        }

        var canQuickLookSelectedItem: Bool {
            guard !entries.selectedIds.isEmpty else {
                return false
            }
            return entries.displayItems.contains { entries.selectedIds.contains($0.id) }
        }

        var hasSelectedItems: Bool {
            !entries.selectedIds.isEmpty
        }

        var hasClipboardItems: Bool {
            !entries.clipboardItems.isEmpty
        }

        var canSaveCollection: Bool {
            guard entries.isCollectionMode, collectionContext != nil else { return false }
            if openedCollectionBaseline == nil {
                return true
            }
            return isOpenedCollectionDirty
        }

        var isOpenedCollectionDirty: Bool {
            guard let baseline = openedCollectionBaseline, let context = collectionContext else { return false }
            if baseline.context != context { return true }
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

        mutating func resetComposer() {
            composer = .init()
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

    struct ColumnUpdate: Equatable, Sendable {
        let column: ListColumnWidthsUtils.Column
        let delta: CGFloat
        let totalWidth: CGFloat
        let padding: CGFloat
        let spacing: CGFloat
    }

    enum PendingNavigation: Equatable, Sendable {
        case back
        case forward
        case history(index: Int, isBackHistory: Bool)
        case enclosingDirectory
    }

    enum UnsavedNavigationChoice: Equatable, Sendable {
        case save
        case discard
        case cancel
    }

    enum Action: Sendable {
        case onAppear
        case navigateTo(String)
        case openCollectionFile(URL)
        case collectionFileLoaded(Result<VoyagerCollectionFile, Error>)
        case restoreSidebarSelection
        case navigateToCollection(FileManagerNavigationUtils.CollectionNavigation)
        case emptyTrashCompleted
        case closeWindow
        case goBack
        case goForward
        case goToHistoryIndex(Int, isBackHistory: Bool)
        case goToEnclosingDirectory
        case performNavigation(PendingNavigation)
        case showUnsavedNavigationAlert(PendingNavigation)
        case unsavedNavigationAlertResponse(PendingNavigation, UnsavedNavigationChoice)
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
        case favoritesLoaded([SidebarItems.FavoriteItem])
        case openFavorite(SidebarItems.FavoriteItem)
        case insertFavorite(url: URL, at: Int)
        case removeFavorite(SidebarItems.FavoriteItem)
        case reorderFavorites(from: IndexSet, to: Int)

        case loadLocations
        case locationsLoaded([SidebarItems.LocationItem])
        case openLocation(SidebarItems.LocationItem)

        case loadTags
        case tagsLoaded([SidebarItems.TagItem])
        case showTag(SidebarItems.TagItem)

        case changeSortKey(SortKey)
        case changeSortOrder(SortOrder)
        case changeGroupKey(GroupKey)

        case dropItemsToSidebarFolder(providers: [NSItemProvider], targetURL: URL)
        case dropItemsToTag(providers: [NSItemProvider], tagName: String)

        case entries(EntriesFeature.Action)
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

        Scope(state: \.entries, action: \.entries) {
            EntriesFeature()
        }

        Reduce { state, action in
            switch action {
            case .onAppear:
                if shouldLogDailyFileManagerOpen(userDefaultsClient) {
                    VoyagerSentryMetricLogger.logMetric(
                        "voyager_file_manager_first_open",
                        value: 1,
                        tags: ["date": currentDateKey()],
                    )
                }
                state.showHiddenFiles = userDefaultsClient.bool(SettingsKeys.showHiddenFiles)
                state.sidebarVisible = userDefaultsClient.object(SettingsKeys.sidebarVisible) as? Bool ?? true
                state.sortKey = SortKey(rawValue: userDefaultsClient.string("sortKey") ?? "") ?? .name
                state
                    .sortOrder = SortOrder(rawValue: userDefaultsClient.string("sortOrder") ?? "") ??
                    .ascending
                state.entries.groupKey = GroupKey(rawValue: userDefaultsClient.string("groupKey") ?? "") ?? .none

                if let viewLayoutRaw = userDefaultsClient.string(SettingsKeys.viewLayout),
                   let savedLayout = ViewLayout(rawValue: viewLayoutRaw)
                {
                    state.viewLayout = savedLayout
                } else {
                    state.viewLayout = .list
                }
                state.entries.isListView = state.viewLayout == .list

                if userDefaultsClient.object("columnWidthName") != nil {
                    state.columnWidths = ListColumnWidthsUtils(
                        name: CGFloat(userDefaultsClient.double("columnWidthName")),
                        date: CGFloat(userDefaultsClient.double("columnWidthDate")),
                        size: CGFloat(userDefaultsClient.double("columnWidthSize")),
                        kind: CGFloat(userDefaultsClient.double("columnWidthKind")),
                    )
                }

                if let listIconSize = userDefaultsClient.object(SettingsKeys.listIconSize) as? CGFloat {
                    state.listIconSize = listIconSize
                }
                if let gridIconSize = userDefaultsClient.object(SettingsKeys.gridIconSize) as? CGFloat {
                    state.gridIconSize = gridIconSize
                }

                if let listTextSize = userDefaultsClient.object(SettingsKeys.listTextSize) as? CGFloat {
                    state.listTextSize = listTextSize
                }
                if let gridTextSize = userDefaultsClient.object(SettingsKeys.gridTextSize) as? CGFloat {
                    state.gridTextSize = gridTextSize
                }

                let userDefaultsClient = userDefaultsClient
                return .merge(
                    .send(.entries(.setShowHidden(state.showHiddenFiles))),
                    .send(.entries(.setSortKey(state.sortKey))),
                    .send(.entries(.setSortOrder(state.sortOrder))),
                    .send(.entries(.onAppear)),
                    .send(.entries(.loadItems(path: state.currentPath))),
                    .send(.loadFavorites),
                    .send(.loadLocations),
                    .send(.loadTags),
                    .run { [userDefaultsClient] send in
                        let listIconSizeKey = "listIconSize"
                        let gridIconSizeKey = "gridIconSize"
                        let listTextSizeKey = "listTextSize"
                        let gridTextSizeKey = "gridTextSize"
                        let showHiddenFilesKey = "showHiddenFiles"
                        for await _ in NotificationCenter.default.notifications(
                            named: UserDefaults.didChangeNotification,
                        ) {
                            if let listIconSize = userDefaultsClient.object(listIconSizeKey) as? CGFloat {
                                await send(.updateListIconSize(listIconSize))
                            }
                            if let gridIconSize = userDefaultsClient.object(gridIconSizeKey) as? CGFloat {
                                await send(.updateGridIconSize(gridIconSize))
                            }
                            if let listTextSize = userDefaultsClient.object(listTextSizeKey) as? CGFloat {
                                await send(.updateListTextSize(listTextSize))
                            }
                            if let gridTextSize = userDefaultsClient.object(gridTextSizeKey) as? CGFloat {
                                await send(.updateGridTextSize(gridTextSize))
                            }
                            let showHiddenFiles = userDefaultsClient.bool(showHiddenFilesKey)
                            await send(.setShowHiddenFiles(showHiddenFiles))
                        }
                    },
                )

            case let .navigateTo(path):
                let previousNavigationState = state.navigationState
                let computerName = navigationClient.computerName()
                if path == computerName, state.currentPath == computerName {
                    return .none
                }
                if path != state.currentPath {
                    let previousSnapshot = state.makeHistoryEntry()
                    state.resetComposer()
                    state.appendBackHistory(previousSnapshot)
                    state.forwardHistory = []
                }
                state.navigationState = .folder(path)
                logDAUNavigationIfNeeded(previous: previousNavigationState, next: state.navigationState)
                matchSidebarToPath(
                    state: &state,
                    path: path,
                    favorites: state.favorites,
                    locations: state.locations,
                )
                let exitEffect = exitCollectionMode(state: &state)
                return .concatenate(
                    exitEffect,
                    .send(.entries(.loadItems(path: path))),
                )

            case let .openCollectionFile(url):
                if state.openedCollectionURL?.path != url.path {
                    VoyagerSentryMetricLogger.logDAUNavigation(kind: .collection)
                }
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
                state.collectionOriginURL = url
                state.openedCollectionBaseline = nil
                state.selectedSidebarItem = state.favorites
                    .first(where: { $0.url.path == url.path })
                    .map(\.displayName)
                let loadEffect: Effect<Action> = .run { [url] send in
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
                state.entries.isListView = navigation.viewLayout == .list

                switch navigation.kind {
                case .temporary:
                    state.openedCollectionName = nil
                    state.openedCollectionURL = nil
                    state.selectedSidebarItem = nil
                    state.openedCollectionBaseline = nil
                case let .file(url, name):
                    state.openedCollectionName = name
                    state.openedCollectionURL = url
                    state.collectionOriginURL = url
                    state.selectedSidebarItem = state.favorites
                        .first(where: { $0.url.path == url.path })
                        .map(\.displayName) ?? name
                    state.openedCollectionBaseline = CollectionBaseline(
                        context: navigation.context,
                        sortKey: navigation.sortKey,
                        sortOrder: navigation.sortOrder,
                        viewLayout: navigation.viewLayout,
                    )
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

                    let resolved = resolveCollectionFilters(from: file, registryClient: registryClient)
                    if trimmedQuery.isEmpty, resolved.scopes.isEmpty, resolved.conditions.isEmpty {
                        if !state.backHistory.isEmpty {
                            state.backHistory.removeLast()
                        }
                        state.isOpeningCollectionFile = false
                        state.openedCollectionName = nil
                        state.openedCollectionURL = nil
                        state.openedCollectionBaseline = nil
                        state.resetComposer()
                        let exitEffect = exitCollectionMode(state: &state)
                        return .merge(
                            exitEffect,
                            .run { send in
                                await collectionAlertClient.showCollectionOpenErrorAlert(
                                    "Empty Collection",
                                    "This collection file has no query, scope, or filters.",
                                )
                                await send(.restoreSidebarSelection)
                            },
                        )
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

                    var mergedEffects: [Effect<Action>] = [.concatenate(effects)]
                    if !resolved.unknownKeys.isEmpty {
                        let unknownKeys = resolved.unknownKeys.joined(separator: ", ")
                        let warningMessage = [
                            "Some filters in this collection are no longer supported and were disabled:",
                            "\(unknownKeys).",
                        ].joined(separator: " ")
                        mergedEffects.append(.run { _ in
                            await collectionAlertClient.showCollectionOpenErrorAlert(
                                "Unsupported Filters",
                                warningMessage,
                            )
                        })
                    }

                    return .merge(mergedEffects)

                case let .failure(error):
                    if !state.backHistory.isEmpty {
                        state.backHistory.removeLast()
                    }
                    state.isOpeningCollectionFile = false
                    state.openedCollectionName = nil
                    state.openedCollectionURL = nil
                    state.openedCollectionBaseline = nil
                    state.resetComposer()
                    let exitEffect = exitCollectionMode(state: &state)
                    return .merge(
                        exitEffect,
                        .run { send in
                            await collectionAlertClient.showCollectionOpenErrorAlert(
                                "Unable to Open Collection",
                                error.localizedDescription,
                            )
                            await send(.restoreSidebarSelection)
                        },
                    )
                }

            case .emptyTrashCompleted:
                return .send(.closeWindow)

            case .closeWindow:
                return .run { _ in
                    await MainActor.run {
                        NSApp.keyWindow?.close()
                    }
                }

            case .restoreSidebarSelection:
                if let restoreSelection = state.pendingSidebarSelectionRestore {
                    state.selectedSidebarItem = restoreSelection
                }
                state.pendingSidebarSelectionRestore = nil
                return .none

            case .goBack:
                if Self.shouldPromptForUnsavedNavigation(state: state) {
                    return .send(.showUnsavedNavigationAlert(.back))
                }
                return .send(.performNavigation(.back))

            case .goForward:
                if Self.shouldPromptForUnsavedNavigation(state: state) {
                    return .send(.showUnsavedNavigationAlert(.forward))
                }
                return .send(.performNavigation(.forward))

            case let .goToHistoryIndex(index, isBackHistory):
                if Self.shouldPromptForUnsavedNavigation(state: state) {
                    return .send(.showUnsavedNavigationAlert(.history(index: index, isBackHistory: isBackHistory)))
                }
                return .send(.performNavigation(.history(index: index, isBackHistory: isBackHistory)))

            case .goToEnclosingDirectory:
                if Self.shouldPromptForUnsavedNavigation(state: state) {
                    return .send(.showUnsavedNavigationAlert(.enclosingDirectory))
                }
                return .send(.performNavigation(.enclosingDirectory))

            case let .performNavigation(pending):
                return performNavigation(pending, state: &state)

            case let .showUnsavedNavigationAlert(pending):
                return .run { send in
                    let choice = await collectionAlertClient.showUnsavedNavigationAlert()
                    await send(.unsavedNavigationAlertResponse(pending, mapCollectionChoice(choice)))
                }

            case let .unsavedNavigationAlertResponse(pending, choice):
                switch choice {
                case .cancel:
                    return .none
                case .discard:
                    state.resetComposerOnNextDirectoryNavigation = true
                    return performNavigation(pending, state: &state)
                case .save:
                    state.resetComposerOnNextDirectoryNavigation = true
                    state.pendingNavigation = pending
                    let payload = CollectionFeature.SaveRequestPayload(
                        context: state.collectionContext,
                        sortKey: state.sortKey.rawValue,
                        sortOrder: state.sortOrder.rawValue,
                        viewLayout: state.viewLayout.rawValue,
                        isSearchLoading: state.composer.isLoadingSearch,
                        isFiltersLoading: state.composer.isLoadingFilters,
                    )
                    if let url = state.collectionOriginURL {
                        return .send(.collection(.saveToExisting(payload, url)))
                    }
                    return .send(.collection(.saveRequested(payload)))
                }

            case let .changeLayout(layout):
                state.viewLayout = layout
                state.entries.isListView = layout == .list
                userDefaultsClient.setString(layout.rawValue, SettingsKeys.viewLayout)
                return .none

            case .toggleShowHiddenFiles:
                state.showHiddenFiles.toggle()
                userDefaultsClient.setBool(state.showHiddenFiles, SettingsKeys.showHiddenFiles)
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
                userDefaultsClient.setObject(visible, SettingsKeys.sidebarVisible)
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
                userDefaultsClient.setDouble(clampedWidth, SettingsKeys.sidebarWidth)
                return .none

            case let .updateColumnWidth(ctx):
                state.columnWidths = state.columnWidths.updated(
                    column: ctx.column,
                    delta: ctx.delta,
                    totalWidth: ctx.totalWidth,
                    padding: ctx.padding,
                    spacing: ctx.spacing,
                )
                userDefaultsClient.setDouble(state.columnWidths.name, "columnWidthName")
                userDefaultsClient.setDouble(state.columnWidths.date, "columnWidthDate")
                userDefaultsClient.setDouble(state.columnWidths.size, "columnWidthSize")
                userDefaultsClient.setDouble(state.columnWidths.kind, "columnWidthKind")
                return .none

            case .showRecents:
                state.navigate(to: .recents, sidebarItemName: "Recents")
                state.resetComposer()
                let exitEffect = exitCollectionMode(state: &state)
                return .concatenate(
                    exitEffect,
                    .send(.entries(.loadRecentItems(showHidden: state.showHiddenFiles))),
                )

            case .showComputer:
                state.navigate(to: .computer, sidebarItemName: navigationClient.computerName())
                state.resetComposer()
                let exitEffect = exitCollectionMode(state: &state)
                return .concatenate(
                    exitEffect,
                    .send(.entries(.loadComputerItems)),
                )

            case .loadFavorites:
                return .run { send in
                    let favorites = await navigationClient.loadFavorites(entryClient, userDefaultsClient)
                    await send(.favoritesLoaded(favorites))
                }

            case let .favoritesLoaded(favorites):
                state.favorites = favorites
                matchSidebarToPath(
                    state: &state,
                    path: state.currentPath,
                    favorites: favorites,
                    locations: state.locations,
                )
                return .none

            case let .openFavorite(favorite):
                if favorite.url.pathExtension.lowercased() == "voycoll" {
                    if state.openedCollectionURL?.path == favorite.url.path {
                        return .none
                    }
                    state.pendingSidebarSelectionRestore = state.selectedSidebarItem
                    state.selectedSidebarItem = favorite.displayName
                    return .send(.openCollectionFile(favorite.url))
                }
                guard state.currentPath != favorite.url.path else { return .none }
                let previousNavigationState = state.navigationState
                state.navigateToFolder(favorite.url.path, sidebarItemName: favorite.name)
                logDAUNavigationIfNeeded(previous: previousNavigationState, next: state.navigationState)
                state.resetComposer()
                let exitEffect = exitCollectionMode(state: &state)
                return .concatenate(
                    exitEffect,
                    .send(.entries(.loadItems(path: favorite.url.path))),
                )

            case let .insertFavorite(url, index):
                if state.favorites.contains(where: { $0.url.path == url.path }) {
                    return .none
                }

                var isDirectory: ObjCBool = false
                guard entryClient.fileExistsAtPath(url.path, &isDirectory) else {
                    return .none
                }
                let isVoycoll = url.pathExtension.lowercased() == "voycoll"
                guard isDirectory.boolValue || isVoycoll else {
                    return .none
                }

                let name = isVoycoll
                    ? url.deletingPathExtension().lastPathComponent
                    : entryClient.displayName(url.path)
                let iconName = navigationClient.iconNameForURL(url, isDirectory.boolValue, entryClient)
                let newFavorite = SidebarItems.FavoriteItem(name: name, url: url, iconName: iconName)

                let insertIndex = max(0, min(index, state.favorites.count))
                state.favorites.insert(newFavorite, at: insertIndex)
                navigationClient.saveFavorites(state.favorites, userDefaultsClient)
                return .none

            case let .removeFavorite(favorite):
                state.favorites.removeAll { $0.url.path == favorite.url.path }
                navigationClient.saveFavorites(state.favorites, userDefaultsClient)
                return .none

            case let .reorderFavorites(source, destination):
                var reordered = state.favorites
                let sortedIndices = source.sorted(by: >)
                var itemsToMove: [SidebarItems.FavoriteItem] = []
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
                navigationClient.saveFavorites(state.favorites, userDefaultsClient)
                return .none

            case .loadLocations:
                return .run { send in
                    let locations = await navigationClient.loadLocations(entryClient)
                    await send(.locationsLoaded(locations))
                }

            case let .locationsLoaded(locations):
                state.locations = locations
                matchSidebarToPath(
                    state: &state,
                    path: state.currentPath,
                    favorites: state.favorites,
                    locations: locations,
                )
                return .none

            case let .openLocation(location):
                guard state.currentPath != location.url.path else { return .none }
                let previousNavigationState = state.navigationState
                state.navigateToFolder(location.url.path, sidebarItemName: location.name)
                logDAUNavigationIfNeeded(previous: previousNavigationState, next: state.navigationState)
                state.resetComposer()
                let exitEffect = exitCollectionMode(state: &state)
                return .concatenate(
                    exitEffect,
                    .send(.entries(.loadItems(path: location.url.path))),
                )

            case .loadTags:
                return .run { send in
                    let tags = await navigationClient.loadTags()
                    await send(.tagsLoaded(tags))
                }

            case let .tagsLoaded(tags):
                state.tags = tags
                return .none

            case let .showTag(tagItem):
                state.navigate(to: .tags(tagItem.name), sidebarItemName: tagItem.name)
                state.resetComposer()
                let exitEffect = exitCollectionMode(state: &state)
                return .concatenate(
                    exitEffect,
                    .send(.entries(.loadTagItems(tagName: tagItem.name, showHidden: state.showHiddenFiles))),
                )

            case let .changeSortKey(key):
                state.sortKey = key
                userDefaultsClient.setString(key.rawValue, "sortKey")
                return .send(.entries(.setSortKey(key)))

            case let .changeSortOrder(order):
                state.sortOrder = order
                userDefaultsClient.setString(order.rawValue, "sortOrder")
                return .send(.entries(.setSortOrder(order)))

            case let .changeGroupKey(key):
                state.entries.groupKey = key
                userDefaultsClient.setString(key.rawValue, "groupKey")
                return .send(.entries(.setGroupKey(key)))

            case let .dropItemsToSidebarFolder(providers, targetURL):
                return .send(.entries(.handleDrop(
                    providers: providers,
                    destinationPath: targetURL.path,
                )))

            case let .dropItemsToTag(providers, tagName):
                return .send(.entries(.handleDropToTag(
                    providers: providers,
                    tagName: tagName,
                )))

            case let .entries(action):
                switch action {
                case .itemsLoaded:
                    state.titlePath = state.currentPath
                    return .none

                case .operations(.operationFinished(_, .deleteImmediately, .success)):
                    return .none

                case let .navigateFolder(id):
                    guard let item = state.entries.displayItems.first(where: { $0.id == id }) else {
                        return .none
                    }
                    let previousNavigationState = state.navigationState
                    state.navigateToFolder(item.fullPath, sidebarItemName: item.name)
                    logDAUNavigationIfNeeded(previous: previousNavigationState, next: state.navigationState)
                    state.resetComposer()
                    let exitEffect = exitCollectionMode(state: &state)
                    return .concatenate(
                        exitEffect,
                        .send(.entries(.loadItems(path: item.fullPath))),
                    )

                case let .openCollectionFile(url):
                    return .send(.openCollectionFile(url))

                case .emptyTrashCompleted:
                    return .send(.emptyTrashCompleted)

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
                      state.entries.isCollectionMode,
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
                state.entries.isListView = baseline.viewLayout == .list

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
                case .applyFilters:
                    state.composer.isLoadingFilters = true
                    return .none

                case let .setText(text):
                    let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    state.pendingSearchQuery = query.isEmpty ? nil : query
                    if query.isEmpty, state.composer.conditions.isEmpty, state.composer.scopes.isEmpty {
                        return exitCollectionMode(state: &state)
                    }
                    return .none

                case let .searchResponse(.success(response)):
                    let wasOpeningCollectionFile = state.isOpeningCollectionFile
                    state.isOpeningCollectionFile = false
                    state.pendingSidebarSelectionRestore = nil
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
                    if !wasOpeningCollectionFile,
                       previousNavigationState != nextNavigationState,
                       !(previousNavigationState.isCollection && nextNavigationState.isCollection)
                    {
                        state.appendBackHistory(previousSnapshot)
                        state.forwardHistory = []
                    }
                    state.navigationState = nextNavigationState
                    if !wasOpeningCollectionFile, !previousNavigationState.isCollection {
                        logDAUNavigationIfNeeded(previous: previousNavigationState, next: nextNavigationState)
                    }
                    return .concatenate(
                        .send(.entries(.setCollectionMode(true))),
                        .send(.entries(.collectionItemsLoadedFromSearch(items))),
                    )

                case let .filtersResponse(.success(response)):
                    let wasOpeningCollectionFile = state.isOpeningCollectionFile
                    state.isOpeningCollectionFile = false
                    state.pendingSidebarSelectionRestore = nil
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
                    if !wasOpeningCollectionFile,
                       previousNavigationState != nextNavigationState,
                       !(previousNavigationState.isCollection && nextNavigationState.isCollection)
                    {
                        state.appendBackHistory(previousSnapshot)
                        state.forwardHistory = []
                    }
                    state.navigationState = nextNavigationState
                    if !wasOpeningCollectionFile, !previousNavigationState.isCollection {
                        logDAUNavigationIfNeeded(previous: previousNavigationState, next: nextNavigationState)
                    }
                    return .concatenate(
                        .send(.entries(.setCollectionMode(true))),
                        .send(.entries(.collectionItemsLoadedFromSearch(items))),
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
                        let exitEffect = exitCollectionMode(state: &state)
                        return .merge(
                            exitEffect,
                            .run { send in
                                await collectionAlertClient.showCollectionOpenErrorAlert(
                                    "Unable to Run Collection Search",
                                    """
                                    \(error.localizedDescription)

                                    Make sure the backend is running and try again.
                                    """,
                                )
                                await send(.restoreSidebarSelection)
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
                        let exitEffect = exitCollectionMode(state: &state)
                        return .merge(
                            exitEffect,
                            .run { send in
                                await collectionAlertClient.showCollectionOpenErrorAlert(
                                    "Unable to Apply Collection Filters",
                                    """
                                    \(error.localizedDescription)

                                    Make sure the backend is running and try again.
                                    """,
                                )
                                await send(.restoreSidebarSelection)
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
                    if state.entries.isCollectionMode {
                        state.pendingSearchQuery = nil
                        state.collectionContext = CollectionContext(
                            query: "",
                            scopes: [ComposerScopeUtils.rootScopePath],
                            conditions: [],
                        )
                        return .none
                    }
                    return exitCollectionMode(state: &state)

                case .saveCollection:
                    guard state.canSaveCollection else {
                        return .none
                    }
                    state.isSaveAsPendingFromCollection = false
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
                    state.isSaveAsPendingFromCollection = state.openedCollectionURL != nil
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
                case .saveRequested, .saveToExisting, .savePanelResponse:
                    return .none

                case let .saveCompleted(.success(url)):
                    let previousSnapshot = state.makeHistoryEntry()
                    let shouldAppendHistory = state.isSaveAsPendingFromCollection
                    let previousCollectionURL = state.openedCollectionURL
                    let previousCollectionName = state.openedCollectionName
                    let previousBaseline = state.openedCollectionBaseline
                    state.isSaveAsPendingFromCollection = false
                    state.openedCollectionURL = url
                    state.openedCollectionName = url.deletingPathExtension().lastPathComponent
                    state.collectionOriginURL = url

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
                    if shouldAppendHistory {
                        if let baseline = previousBaseline,
                           let previousURL = previousCollectionURL
                        {
                            let name = previousCollectionName
                                ?? previousURL.deletingPathExtension().lastPathComponent
                            let navigation = FileManagerNavigationUtils.CollectionNavigation(
                                kind: .file(url: previousURL, name: name),
                                context: baseline.context,
                                sortKey: baseline.sortKey,
                                sortOrder: baseline.sortOrder,
                                viewLayout: baseline.viewLayout,
                            )
                            let entry = HistoryEntry(
                                navigationState: .collection(navigation),
                                sidebarItemName: nil,
                                composerState: state.composer,
                            )
                            state.appendBackHistory(entry)
                        } else {
                            state.appendBackHistory(previousSnapshot)
                        }
                        state.forwardHistory = []
                    }
                    if let pending = state.pendingNavigation {
                        state.pendingNavigation = nil
                        return performNavigation(pending, state: &state)
                    }
                    return .none

                case .saveCompleted(.failure):
                    state.isSaveAsPendingFromCollection = false
                    state.pendingNavigation = nil
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
                VoyagerSentryMetricLogger.logMetric(
                    "voyager_composer_open",
                    value: 1,
                )
                return .none

            case .exitComposer:
                state.composer.isPresented = false
                return .none
            }
        }
    }

    private func exitCollectionMode(state: inout State) -> Effect<Action> {
        let wasCollection = if case .collection = state.navigationState { true } else { false }
        let clearEffect = Self.clearCollectionMode(state: &state)

        guard wasCollection else {
            return clearEffect
        }

        state.navigationState = FileManagerNavigationUtils.navigationStateFromPath(
            state.titlePath,
            computerName: navigationClient.computerName(),
        )
        matchSidebarToPath(
            state: &state,
            path: state.currentPath,
            favorites: state.favorites,
            locations: state.locations,
        )
        return clearEffect
    }

    private static func applyShowHiddenFilesChange(state: inout State) -> Effect<Action> {
        switch state.navigationState {
        case .recents:
            .merge(
                .send(.entries(.setShowHidden(state.showHiddenFiles))),
                .send(.entries(.loadRecentItems(showHidden: state.showHiddenFiles))),
            )
        case let .tags(tagName):
            .merge(
                .send(.entries(.setShowHidden(state.showHiddenFiles))),
                .send(.entries(.loadTagItems(tagName: tagName, showHidden: state.showHiddenFiles))),
            )
        case .computer:
            .merge(
                .send(.entries(.setShowHidden(state.showHiddenFiles))),
                .send(.entries(.loadComputerItems)),
            )
        case .folder, .collection:
            .merge(
                .send(.entries(.setShowHidden(state.showHiddenFiles))),
                .send(.entries(.loadItems(path: state.currentPath))),
            )
        }
    }

    private static func shouldPromptForUnsavedNavigation(state: State) -> Bool {
        state.entries.isCollectionMode && state.canSaveCollection
    }

    private func mapCollectionChoice(
        _ choice: CollectionNavigationChoice,
    ) -> UnsavedNavigationChoice {
        switch choice {
        case .save:
            .save
        case .discard:
            .discard
        case .cancel:
            .cancel
        }
    }

    private func performNavigation(
        _ pending: PendingNavigation,
        state: inout State,
    ) -> Effect<Action> {
        switch pending {
        case .back:
            performBackNavigation(state: &state)

        case .forward:
            performForwardNavigation(state: &state)

        case let .history(index, isBackHistory):
            performHistoryNavigation(
                index: index,
                isBackHistory: isBackHistory,
                state: &state,
            )

        case .enclosingDirectory:
            performEnclosingDirectoryNavigation(state: &state)
        }
    }

    private func performBackNavigation(state: inout State) -> Effect<Action> {
        guard let entry = state.backHistory.popLast() else { return .none }
        let currentSnapshot = state.makeHistoryEntry()
        state.appendForwardHistory(currentSnapshot)
        applyHistoryEntry(
            state: &state,
            entry: entry,
            favorites: state.favorites,
            locations: state.locations,
        )
        Self.resetComposerAfterAlertNavigation(state: &state)
        let exitEffect = Self.clearCollectionMode(state: &state)
        return .concatenate(
            exitEffect,
            navigateToState(
                state.navigationState,
                showHidden: state.showHiddenFiles,
            ),
        )
    }

    private func performForwardNavigation(state: inout State) -> Effect<Action> {
        guard let entry = state.forwardHistory.popLast() else { return .none }
        let currentSnapshot = state.makeHistoryEntry()
        state.appendBackHistory(currentSnapshot)
        applyHistoryEntry(
            state: &state,
            entry: entry,
            favorites: state.favorites,
            locations: state.locations,
        )
        Self.resetComposerAfterAlertNavigation(state: &state)
        let exitEffect = Self.clearCollectionMode(state: &state)
        return .concatenate(
            exitEffect,
            navigateToState(
                state.navigationState,
                showHidden: state.showHiddenFiles,
            ),
        )
    }

    private func performHistoryNavigation(
        index: Int,
        isBackHistory: Bool,
        state: inout State,
    ) -> Effect<Action> {
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

            applyHistoryEntry(
                state: &state,
                entry: targetEntry,
                favorites: state.favorites,
                locations: state.locations,
            )
            Self.resetComposerAfterAlertNavigation(state: &state)
            let exitEffect = Self.clearCollectionMode(state: &state)
            return .concatenate(
                exitEffect,
                navigateToState(
                    state.navigationState,
                    showHidden: state.showHiddenFiles,
                ),
            )
        }

        guard index < state.forwardHistory.count else { return .none }
        let targetIndex = state.forwardHistory.count - 1 - index
        let targetEntry = state.forwardHistory[targetIndex]
        let trailing = Array(state.forwardHistory[(targetIndex + 1)...])

        state.forwardHistory.removeLast(state.forwardHistory.count - targetIndex)

        let currentSnapshot = state.makeHistoryEntry()
        state.appendBackHistory(currentSnapshot)
        state.backHistory.append(contentsOf: trailing.reversed())
        state.trimHistory()

        applyHistoryEntry(
            state: &state,
            entry: targetEntry,
            favorites: state.favorites,
            locations: state.locations,
        )
        Self.resetComposerAfterAlertNavigation(state: &state)
        let exitEffect = Self.clearCollectionMode(state: &state)
        return .concatenate(
            exitEffect,
            navigateToState(
                state.navigationState,
                showHidden: state.showHiddenFiles,
            ),
        )
    }

    private func performEnclosingDirectoryNavigation(state: inout State) -> Effect<Action> {
        guard let parentPath = state.enclosingDirectoryPath else { return .none }
        let parentURL = URL(fileURLWithPath: parentPath)
        let childName = URL(fileURLWithPath: state.currentPath).lastPathComponent
        if !childName.isEmpty {
            state.entries.selectAfterLoadFileNames = [childName]
        }
        let previousNavigationState = state.navigationState
        state.navigateToFolder(parentURL.path, sidebarItemName: parentURL.lastPathComponent)
        logDAUNavigationIfNeeded(previous: previousNavigationState, next: state.navigationState)
        state.resetComposer()
        state.resetComposerOnNextDirectoryNavigation = false
        let exitEffect = exitCollectionMode(state: &state)
        return .concatenate(
            exitEffect,
            .send(.entries(.loadItems(path: parentURL.path))),
        )
    }

    private static func resetComposerAfterAlertNavigation(state: inout State) {
        if state.resetComposerOnNextDirectoryNavigation,
           !state.navigationState.isCollection
        {
            state.resetComposer()
            state.resetComposerOnNextDirectoryNavigation = false
        }
    }

    private func navigateToState(
        _ navigationState: FileManagerNavigationUtils.NavigationState,
        showHidden: Bool = false,
    ) -> Effect<Action> {
        switch navigationState {
        case .recents:
            .send(.entries(.loadRecentItems(showHidden: showHidden)))
        case let .folder(path):
            .send(.entries(.loadItems(path: path)))
        case let .tags(tagName):
            .run { send in
                let taggedItems = await navigationClient.loadFilesWithTag(
                    tagName,
                    showHidden,
                    entryClient,
                    WorkspaceClient.liveValue,
                )
                await send(.entries(.itemsLoaded(taggedItems)))
            }
        case .computer:
            .send(.entries(.loadComputerItems))
        case let .collection(navigation):
            .send(.navigateToCollection(navigation))
        }
    }

    private func logDAUNavigationIfNeeded(
        previous: FileManagerNavigationUtils.NavigationState,
        next: FileManagerNavigationUtils.NavigationState,
    ) {
        guard previous != next else { return }
        guard let kind = dauNavigationKind(for: next) else { return }
        VoyagerSentryMetricLogger.logDAUNavigation(kind: kind)
    }

    private func dauNavigationKind(
        for navigationState: FileManagerNavigationUtils.NavigationState,
    ) -> DAUNavigationKind? {
        switch navigationState {
        case .folder:
            .folder
        case .collection:
            .collection
        default:
            nil
        }
    }

    private static func clearCollectionMode(state: inout State) -> Effect<Action> {
        state.collectionContext = nil
        state.pendingSearchQuery = nil
        state.isOpeningCollectionFile = false
        state.openedCollectionName = nil
        state.openedCollectionURL = nil
        state.openedCollectionBaseline = nil
        state.collectionOriginURL = nil
        state.pendingNavigation = nil
        state.entries.collectionItems = []
        return .merge(
            .cancel(id: CancelID.openCollectionFile),
            .cancel(id: ComposerFeature.CancelID.search),
            .cancel(id: ComposerFeature.CancelID.filters),
            .send(.entries(.setCollectionMode(false))),
        )
    }

    private func applyHistoryEntry(
        state: inout State,
        entry: HistoryEntry,
        favorites: [SidebarItems.FavoriteItem],
        locations: [SidebarItems.LocationItem],
    ) {
        let previousNavigationState = state.navigationState
        state.navigationState = entry.navigationState
        logDAUNavigationIfNeeded(previous: previousNavigationState, next: state.navigationState)
        switch entry.navigationState {
        case .collection:
            state.selectedSidebarItem = nil
        default:
            state.selectedSidebarItem = entry.sidebarItemName
            matchSidebarToPath(
                state: &state,
                path: state.currentPath,
                favorites: favorites,
                locations: locations,
            )
        }
        state.composer = entry.composerState
        state.composer.isPresented = false
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

private func resolveCollectionFilters(
    from file: VoyagerCollectionFile,
    registryClient: RegistryClient,
) -> AppliedFiltersUtils.ResolutionResult {
    let conditionPayloads = file.conditions.map { condition in
        SearchConditionPayload(
            propertyKey: condition.propertyKey,
            operator: condition.operatorCode,
            value: condition.value,
        )
    }
    let appliedFilters = AppliedFiltersPayload(scopes: file.scopes, conditions: conditionPayloads)
    return AppliedFiltersUtils.resolveDetailed(
        appliedFilters,
        fallbackScopes: file.scopes,
        fallbackConditions: [],
        registryClient: registryClient,
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

private func shouldLogDailyFileManagerOpen(_ userDefaultsClient: UserDefaultsClient) -> Bool {
    let key = "voyager.file_manager.first_open_date"
    let today = currentDateKey()
    let lastValue = userDefaultsClient.string(key)
    if lastValue == today {
        return false
    }
    userDefaultsClient.setString(today, key)
    return true
}

private func currentDateKey() -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date())
}

// swiftlint:enable type_body_length
