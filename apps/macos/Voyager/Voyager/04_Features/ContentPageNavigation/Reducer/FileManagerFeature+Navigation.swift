// swiftlint:disable file_length type_body_length
import ComposableArchitecture
import Foundation

@Reducer
struct FileManagerWindowNavigationFeature {
    @Dependency(\.fileManagerComputerNameClient)
    var computerNameClient
    @Dependency(\.collectionFileClient)
    var collectionFileClient
    @Dependency(\.collectionAlertClient)
    var collectionAlertClient
    @Dependency(\.registryClient)
    var registryClient

    typealias State = FileManagerWindowState
    typealias Action = FileManagerWindowAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .sidebar(.favoritesLoaded),
                 .sidebar(.locationsLoaded),
                 .sidebar(.tagsLoaded):
                syncSidebarSelection(state: &state)
                return .none

            case let .sidebar(.openFavorite(favorite)):
                if favorite.url.pathExtension.lowercased() == "voycoll" {
                    state.sidebar.pendingSidebarSelectionRestore = state.sidebar.selectedSidebarItem
                    state.sidebar.selectedSidebarItem = favorite.displayName
                    return .send(.navigation(ContentPageNavigationAction.openCollectionFile(favorite.url)))
                }
                return .send(.navigation(ContentPageNavigationAction.navigateToPath(favorite.url.path)))

            case let .sidebar(.openLocation(location)):
                return .send(.navigation(ContentPageNavigationAction.navigateToPath(location.url.path)))

            case let .sidebar(.showTag(tag)):
                return .send(.navigation(ContentPageNavigationAction.showTag(tag.name)))

            case .sidebar(.showRecents):
                return .send(.navigation(ContentPageNavigationAction.showRecents))

            case .sidebar(.showComputer):
                return .send(.navigation(ContentPageNavigationAction.showComputer))

            case let .content(.entries(.navigateFolder(id: id))):
                guard let entry = state.content.entries.displayItems[id: id] else {
                    return .none
                }
                return .send(.navigation(ContentPageNavigationAction.navigateToPath(entry.fullPath)))

            case let .content(.entries(.openCollectionFile(url))):
                return .send(.navigation(ContentPageNavigationAction.openCollectionFile(url)))

            case let .content(.performPendingNavigation(pending)):
                return .send(.navigation(ContentPageNavigationAction.performNavigation(
                    pending,
                    currentSnapshot: state.content.navigation
                        .makeContentPageNavigationHistorySnapshot(composer: state.content.composer),
                )))

            case let .navigation(navigationAction):
                return handleNavigationAction(navigationAction, state: &state)

            case .content(.composer(.searchResponse(.success))),
                 .content(.composer(.filtersResponse(.success))),
                 .content(.discardCollectionChanges):
                syncSidebarSelection(state: &state)
                return .none

            case .content(.composer(.searchResponse(.failure))),
                 .content(.composer(.filtersResponse(.failure))):
                if state.sidebar.pendingSidebarSelectionRestore != nil {
                    return .send(.sidebar(.restoreSidebarSelection))
                }
                return .none

            default:
                return .none
            }
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    func handleNavigationAction(
        _ action: ContentPageNavigationAction,
        state: inout State,
    ) -> Effect<Action> {
        if let effect = handleDirectNavigationAction(action, state: &state) {
            return effect
        }

        switch action {
        case .goBack:
            return handleNavigationRequest(.back, state: &state)

        case .goForward:
            return handleNavigationRequest(.forward, state: &state)

        case let .goToHistoryIndex(index, isBackHistory):
            return handleNavigationRequest(
                .history(index: index, isBackHistory: isBackHistory),
                state: &state,
            )

        case .goToEnclosingDirectory:
            return handleNavigationRequest(.enclosingDirectory, state: &state)

        case let .showUnsavedNavigationAlert(pending):
            return .run { send in
                let choice = await collectionAlertClient.showUnsavedNavigationAlert()
                await send(.navigation(ContentPageNavigationAction.unsavedNavigationAlertResponse(
                    pending,
                    choice,
                )))
            }

        case let .unsavedNavigationAlertResponse(pending, choice):
            switch choice {
            case .cancel:
                return .none
            case .discard:
                state.content.resetComposerOnNextDirectoryNavigation = true
                return .send(.navigation(ContentPageNavigationAction.performNavigation(
                    pending,
                    currentSnapshot: state.content.navigation
                        .makeContentPageNavigationHistorySnapshot(composer: state.content.composer),
                )))
            case .save:
                state.content.resetComposerOnNextDirectoryNavigation = true
                state.content.navigation.pendingNavigation = pending
                return .send(.content(.composer(.saveCollection)))
            }

        case .performNavigation:
            if state.content.resetComposerOnNextDirectoryNavigation {
                state.content.resetComposer()
                state.content.resetComposerOnNextDirectoryNavigation = false
            }
            return .none

        case .navigateToPath,
             .showRecents,
             .showComputer,
             .showTag,
             .openCollectionFile,
             .collectionFileLoaded,
             .navigateToCollection:
            return .none

        case let .delegate(delegateAction):
            return handleNavigationDelegate(delegateAction, state: &state)
        }
    }

    func handleDirectNavigationAction(
        _ action: ContentPageNavigationAction,
        state: inout State,
    ) -> Effect<Action>? {
        switch action {
        case let .navigateToPath(path):
            let effect = handleNavigateTo(path, state: &state)
            syncSidebarSelection(state: &state)
            return effect

        case .showRecents:
            let effect = handleShowRecents(state: &state)
            syncSidebarSelection(state: &state)
            return effect

        case .showComputer:
            let effect = handleShowComputer(state: &state)
            syncSidebarSelection(state: &state)
            return effect

        case let .showTag(tagName):
            let effect = handleShowTag(tagName, state: &state)
            syncSidebarSelection(state: &state)
            return effect

        case let .openCollectionFile(url):
            return handleOpenCollectionFile(url, state: &state)

        case let .collectionFileLoaded(result):
            return handleCollectionFileLoaded(result, state: &state)

        case let .navigateToCollection(navigation):
            return handleNavigateToCollection(navigation, state: &state)

        default:
            return nil
        }
    }

    func handleNavigationRequest(
        _ pending: ContentPageNavigationPending,
        state: inout State,
    ) -> Effect<Action> {
        if shouldPromptForUnsavedNavigation(state.content) {
            return .send(.navigation(ContentPageNavigationAction.showUnsavedNavigationAlert(pending)))
        }
        return .send(.navigation(ContentPageNavigationAction.performNavigation(
            pending,
            currentSnapshot: state.content.navigation
                .makeContentPageNavigationHistorySnapshot(composer: state.content.composer),
        )))
    }

    func handleNavigationDelegate(
        _ delegateAction: ContentPageNavigationDelegate,
        state: inout State,
    ) -> Effect<Action> {
        switch delegateAction {
        case let .applyContentPageNavigationHistorySnapshot(entry):
            applyContentPageNavigationHistorySnapshot(entry, state: &state)
            syncSidebarSelection(state: &state)
            return .send(.content(.entryArrangements(.reapply)))

        case let .navigateToState(navigationState):
            return handleNavigateToState(navigationState, state: &state)

        case let .logDAUNavigation(previous, next):
            logContentPageNavigationDAUIfNeeded(previous: previous, next: next)
            return .none

        case .resetComposer:
            let exitEffect = exitCollectionMode(
                state: &state.content,
                computerName: computerNameClient.computerName(),
            )
            state.content.resetComposer()
            return exitEffect.map(Action.content)
        }
    }

    func applyContentPageNavigationHistorySnapshot(
        _ entry: ContentPageNavigationHistorySnapshot,
        state: inout State,
    ) {
        state.content.composer = entry.composerSnapshot
        state.content.composer.isPresented = false
        switch entry.navigationState {
        case let .collection(navigation):
            state.content.collectionContext = navigation.context
            state.content.entryArrangements.updateSortKey(navigation.sortKey)
            state.content.entryArrangements.updateSortOrder(navigation.sortOrder)
            state.content.viewLayout = navigation.viewLayout

            switch navigation.kind {
            case .temporary:
                state.content.collectionSession.openedName = nil
                state.content.collectionSession.openedURL = nil
                state.content.collectionSession.originURL = nil
                state.content.collectionSession.baseline = nil
            case let .file(url, name):
                state.content.collectionSession.openedName = name
                state.content.collectionSession.openedURL = url
                state.content.collectionSession.originURL = url
                state.content.collectionSession.baseline = CollectionBaseline(context: navigation.context)
            }
            state.content.syncComposerCollectionState()

        default:
            state.content.collectionContext = nil
            state.content.pendingSearchQuery = nil
            state.content.collectionSession = .init()
            state.content.syncComposerCollectionState()
        }
    }

    func handleNavigateToState(
        _ navigationState: ContentPageNavigationUtils.NavigationState,
        state: inout State,
    ) -> Effect<Action> {
        switch navigationState {
        case let .folder(path):
            return .send(.content(.entries(.loadItems(path: path))))
        case .recents:
            return .send(.content(.entries(.loadRecentItems(showHidden: state.content.entries.showHiddenFiles))))
        case let .tags(tagName):
            return .send(.content(.entries(.loadTagItems(
                tagName: tagName,
                showHidden: state.content.entries.showHiddenFiles,
            ))))
        case .computer:
            return .send(.content(.entries(.loadComputerItems)))
        case let .collection(navigation):
            let trimmedQuery = navigation
                .context
                .query
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedQuery.isEmpty
                ? .send(.content(.composer(.applyFilters)))
                : .send(.content(.composer(.submit)))
        }
    }

    func handleNavigateTo(
        _ path: String,
        state: inout State,
    ) -> Effect<Action> {
        let previousNavigationState = state.content.navigation.navigationState
        let computerName = computerNameClient.computerName()
        if path == computerName, state.content.navigation.currentPath == computerName {
            return .none
        }
        if path != state.content.navigation.currentPath {
            let previousSnapshot = state.content.navigation
                .makeContentPageNavigationHistorySnapshot(composer: state.content.composer)
            state.content.resetComposer()
            state.content.navigation.appendBackHistory(previousSnapshot)
            state.content.navigation.forwardHistory = []
        }
        state.content.navigation.navigationState = ContentPageNavigationUtils.NavigationState.folder(path)
        logContentPageNavigationDAUIfNeeded(
            previous: previousNavigationState,
            next: state.content.navigation.navigationState,
        )
        let exitEffect = exitCollectionMode(
            state: &state.content,
            computerName: computerName,
        )
        return .concatenate(
            exitEffect.map(Action.content),
            .send(.content(.entries(.loadItems(path: path)))),
        )
    }

    func handleShowRecents(state: inout State) -> Effect<Action> {
        let previousNavigationState = state.content.navigation.navigationState
        if case .recents = state.content.navigation.navigationState {
            return .none
        }
        let previousSnapshot = state.content.navigation
            .makeContentPageNavigationHistorySnapshot(composer: state.content.composer)
        state.content.resetComposer()
        state.content.navigation.appendBackHistory(previousSnapshot)
        state.content.navigation.forwardHistory = []
        state.content.navigation.navigationState = .recents
        logContentPageNavigationDAUIfNeeded(
            previous: previousNavigationState,
            next: state.content.navigation.navigationState,
        )
        let exitEffect = exitCollectionMode(
            state: &state.content,
            computerName: computerNameClient.computerName(),
        )
        return .concatenate(
            exitEffect.map(Action.content),
            .send(.content(.entries(.loadRecentItems(showHidden: state.content.entries.showHiddenFiles)))),
        )
    }

    func handleShowComputer(state: inout State) -> Effect<Action> {
        let previousNavigationState = state.content.navigation.navigationState
        if case .computer = state.content.navigation.navigationState {
            return .none
        }
        let previousSnapshot = state.content.navigation
            .makeContentPageNavigationHistorySnapshot(composer: state.content.composer)
        state.content.resetComposer()
        state.content.navigation.appendBackHistory(previousSnapshot)
        state.content.navigation.forwardHistory = []
        state.content.navigation.navigationState = .computer
        logContentPageNavigationDAUIfNeeded(
            previous: previousNavigationState,
            next: state.content.navigation.navigationState,
        )
        let exitEffect = exitCollectionMode(
            state: &state.content,
            computerName: computerNameClient.computerName(),
        )
        return .concatenate(
            exitEffect.map(Action.content),
            .send(.content(.entries(.loadComputerItems))),
        )
    }

    func handleShowTag(
        _ tagName: String,
        state: inout State,
    ) -> Effect<Action> {
        let previousNavigationState = state.content.navigation.navigationState
        if case let .tags(currentTagName) = state.content.navigation.navigationState, currentTagName == tagName {
            return .none
        }
        let previousSnapshot = state.content.navigation
            .makeContentPageNavigationHistorySnapshot(composer: state.content.composer)
        state.content.resetComposer()
        state.content.navigation.appendBackHistory(previousSnapshot)
        state.content.navigation.forwardHistory = []
        state.content.navigation.navigationState = .tags(tagName)
        logContentPageNavigationDAUIfNeeded(
            previous: previousNavigationState,
            next: state.content.navigation.navigationState,
        )
        let exitEffect = exitCollectionMode(
            state: &state.content,
            computerName: computerNameClient.computerName(),
        )
        return .concatenate(
            exitEffect.map(Action.content),
            .send(.content(.entries(.loadTagItems(
                tagName: tagName,
                showHidden: state.content.entries.showHiddenFiles,
            )))),
        )
    }

    func handleOpenCollectionFile(
        _ url: URL,
        state: inout State,
    ) -> Effect<Action> {
        if state.content.collectionSession.openedURL?.path != url.path {
            VoyagerSentryMetricLogger.logDAUNavigation(kind: .collection)
        }
        let clearEffect = clearCollectionMode(state: &state.content)
        if case .collection = state.content.navigation.navigationState {
            // 이미 콜렉션 상태면 히스토리에는 중복 추가하지 않음
        } else {
            let directoryPath = url.deletingLastPathComponent().path
            var previousSnapshot = state.content.navigation
                .makeContentPageNavigationHistorySnapshot(composer: state.content.composer)
            previousSnapshot = ContentPageNavigationHistorySnapshot(
                navigationState: ContentPageNavigationUtils.NavigationState.folder(directoryPath),
                composerSnapshot: previousSnapshot.composerSnapshot,
            )
            state.content.navigation.appendBackHistory(previousSnapshot)
            state.content.navigation.forwardHistory = []
        }
        state.content.collectionSession.isOpening = true
        state.content.collectionSession.openedName = url.deletingPathExtension().lastPathComponent
        state.content.collectionSession.openedURL = url
        state.content.collectionSession.originURL = url
        state.content.collectionSession.baseline = nil
        state.content.syncComposerCollectionState()
        let loadEffect: Effect<Action> = .run { [url] send in
            do {
                let file = try await collectionFileClient.load(url)
                try Task.checkCancellation()
                await send(.navigation(ContentPageNavigationAction.collectionFileLoaded(.success(file))))
            } catch is CancellationError {
                return
            } catch {
                await send(.navigation(ContentPageNavigationAction.collectionFileLoaded(.failure(error))))
            }
        }
        .cancellable(id: "openCollectionFile", cancelInFlight: true)

        return .concatenate(
            clearEffect.map(Action.content),
            loadEffect,
        )
    }

    func handleCollectionFileLoaded(
        _ result: Result<VoyagerCollectionFile, Error>,
        state: inout State,
    ) -> Effect<Action> {
        switch result {
        case let .success(file):
            handleCollectionFileLoadedSuccess(file, state: &state)
        case let .failure(error):
            handleCollectionFileLoadedFailure(error, state: &state)
        }
    }

    func handleNavigateToCollection(
        _ navigation: ContentPageNavigationUtils.CollectionNavigation,
        state: inout State,
    ) -> Effect<Action> {
        state.content.composer.isPresented = false
        state.content.collectionContext = navigation.context
        state.content.pendingSearchQuery = navigation.context.query.isEmpty ? nil : navigation.context.query
        state.content.entryArrangements.updateSortKey(navigation.sortKey)
        state.content.entryArrangements.updateSortOrder(navigation.sortOrder)
        state.content.viewLayout = navigation.viewLayout

        switch navigation.kind {
        case .temporary:
            state.content.collectionSession.openedName = nil
            state.content.collectionSession.openedURL = nil
            state.content.collectionSession.originURL = nil
            state.content.collectionSession.baseline = nil
        case let .file(url, name):
            state.content.collectionSession.openedName = name
            state.content.collectionSession.openedURL = url
            state.content.collectionSession.originURL = url
            state.content.collectionSession.baseline = CollectionBaseline(context: navigation.context)
        }

        state.content.syncComposerCollectionState()

        if case .file = navigation.kind {
            state.content.composer.text = ""
        } else {
            state.content.composer.text = navigation.context.query
        }
        state.content.composer.scopes = navigation.context.scopes
        state.content.composer.conditions = navigation.context.conditions
        state.content.composer.propertyPicker = ConditionPropertyPickerFeature.State()
        state.content.composer.operatorPicker = OperatorPickerFeature.State()
        state.content.composer.valuePicker = ValuePickerFeature.State()
        state.content.composer.clearHistory()

        let trimmedQuery = navigation.context.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchEffect: Effect<Action> = trimmedQuery.isEmpty
            ? .send(.content(.composer(.applyFilters)))
            : .send(.content(.composer(.submit)))

        return .merge(
            .send(.content(.entryArrangements(.reapply))),
            searchEffect,
        )
    }

    func shouldPromptForUnsavedNavigation(_ state: FileManagerContentState) -> Bool {
        state.entries.isCollectionMode && state.canSaveCollection
    }

    func syncSidebarSelection(state: inout State) {
        switch state.content.navigation.navigationState {
        case .collection:
            if let url = state.content.collectionSession.openedURL {
                state.sidebar.selectedSidebarItem = state.sidebar.favorites
                    .first(where: { $0.url.path == url.path })
                    .map(\.displayName) ?? state.content.collectionSession.openedName
            } else {
                state.sidebar.selectedSidebarItem = nil
            }
        case .recents:
            state.sidebar.selectedSidebarItem = "Recents"
        case let .tags(tagName):
            state.sidebar.selectedSidebarItem = tagName
        case .computer:
            state.sidebar.selectedSidebarItem = state.sidebar.locations
                .first(where: { $0.isComputer })?.name
                ?? computerNameClient.computerName()
        case .folder:
            state.sidebar.selectedSidebarItem = matchedSidebarItemName(
                path: state.content.navigation.currentPath,
                favorites: state.sidebar.favorites,
                locations: state.sidebar.locations,
                computerName: computerNameClient.computerName(),
            )
        }
    }

    func matchedSidebarItemName(
        path: String,
        favorites: [SidebarItems.FavoriteItem],
        locations: [SidebarItems.LocationItem],
        computerName: String,
    ) -> String? {
        if path == computerName {
            return locations.first(where: { $0.isComputer })?.name ?? path
        }
        if !path.hasPrefix("/") {
            return path
        }
        return favorites.first(where: { $0.url.path == path })?.name
            ?? locations.first(where: { $0.url.path == path })?.name
    }

    // swiftlint:disable:next function_body_length
    private func handleCollectionFileLoadedSuccess(
        _ file: VoyagerCollectionFile,
        state: inout State,
    ) -> Effect<Action> {
        state.content.composer.isPresented = false
        let trimmedQuery = file.query.trimmingCharacters(in: .whitespacesAndNewlines)
        state.content.pendingSearchQuery = trimmedQuery.isEmpty ? nil : trimmedQuery

        let resolved = file.resolveCollectionFilters(registryClient: registryClient)
        if trimmedQuery.isEmpty, resolved.scopes.isEmpty, resolved.conditions.isEmpty {
            if !state.content.navigation.backHistory.isEmpty {
                state.content.navigation.backHistory.removeLast()
            }
            state.content.collectionSession = .init()
            state.content.resetComposer()
            let exitEffect = exitCollectionMode(
                state: &state.content,
                computerName: computerNameClient.computerName(),
            )
            return .merge(
                exitEffect.map(Action.content),
                .run { _ in
                    await collectionAlertClient.showCollectionOpenErrorAlert(
                        "Empty Collection",
                        "This collection file has no query, scope, or filters.",
                    )
                },
            )
        }

        state.content.composer.text = ""
        state.content.composer.scopes = resolved.scopes
        state.content.composer.conditions = resolved.conditions
        state.content.composer.propertyPicker = ConditionPropertyPickerFeature.State()
        state.content.composer.operatorPicker = OperatorPickerFeature.State()
        state.content.composer.valuePicker = ValuePickerFeature.State()
        state.content.composer.clearHistory()

        state.content.collectionSession.baseline = CollectionBaseline(
            context: CollectionContext(
                query: trimmedQuery,
                scopes: resolved.scopes,
                conditions: resolved.conditions,
            ),
        )

        var effects: [Effect<Action>] = []

        let searchEffect: Effect<Action> = state.content.collectionSession.isOpening
            ? .send(.content(.composer(.applyFilters)))
            : (trimmedQuery.isEmpty
                ? .send(.content(.composer(.applyFilters)))
                : .send(.content(.composer(.submit))))
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
    }

    private func handleCollectionFileLoadedFailure(
        _ error: Error,
        state: inout State,
    ) -> Effect<Action> {
        if !state.content.navigation.backHistory.isEmpty {
            state.content.navigation.backHistory.removeLast()
        }
        state.content.collectionSession = .init()
        state.content.resetComposer()
        let exitEffect = exitCollectionMode(
            state: &state.content,
            computerName: computerNameClient.computerName(),
        )
        var effects: [Effect<Action>] = []
        if state.sidebar.pendingSidebarSelectionRestore != nil {
            effects.append(.send(.sidebar(.restoreSidebarSelection)))
        }
        effects.append(exitEffect.map(Action.content))
        effects.append(.run { _ in
            await collectionAlertClient.showCollectionOpenErrorAlert(
                "Unable to Open Collection",
                error.localizedDescription,
            )
        })
        return .merge(effects)
    }
}

// swiftlint:enable type_body_length
