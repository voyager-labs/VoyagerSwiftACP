import ComposableArchitecture
import Foundation

@Reducer
struct FileManagerContentComposerFeature {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    @Dependency(\.collectionAlertClient)
    private var collectionAlertClient
    @Dependency(\.fileManagerComputerNameClient)
    private var computerNameClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            guard case let .composer(composerAction) = action else {
                return .none
            }

            return handleComposerAction(composerAction, state: &state)
        }
    }

    private func handleComposerAction(
        _ action: ComposerFeature.Action,
        state: inout State,
    ) -> Effect<Action> {
        if let effect = handleComposerLifecycleAction(action, state: &state) {
            return effect
        }

        if let effect = handleComposerCollectionAction(action, state: &state) {
            return effect
        }

        return .none
    }

    private func handleComposerLifecycleAction(
        _ action: ComposerFeature.Action,
        state: inout State,
    ) -> Effect<Action>? {
        if let effect = handleComposerSearchResponseAction(action, state: &state) {
            return effect
        }

        switch action {
        case let .setPresented(isPresented):
            return handleSetPresented(isPresented, state: &state)

        case .applyFilters:
            state.composer.isLoadingFilters = true
            return .none

        case let .setText(text):
            return handleSetText(text, state: &state)

        case .cancelSearch:
            state.composer.pendingSearchQuery = nil
            state.collectionSession.isOpening = false
            state.collectionSession.openedName = nil
            return .none

        case .clearAll:
            if state.entryOperations.loadingContext.isCollectionMode {
                state.composer.pendingSearchQuery = nil
                state.collectionContext = CollectionContext(
                    query: "",
                    scopes: [ComposerScopeUtils.rootScopePath],
                    conditions: [],
                )
                state.syncComposerCollectionState()
                return .none
            }
            return state.exitCollectionMode(computerName: computerNameClient.computerName())

        default:
            return nil
        }
    }

    private func handleComposerSearchResponseAction(
        _ action: ComposerFeature.Action,
        state: inout State,
    ) -> Effect<Action>? {
        switch action {
        case let .searchResponse(.success(response)):
            handleSearchSuccess(
                items: response.items ?? [],
                query: state.composer.pendingSearchQuery ?? "",
                state: &state,
            )

        case let .filtersResponse(.success(response)):
            handleSearchSuccess(
                items: response.items ?? [],
                query: "",
                state: &state,
            )

        case let .searchResponse(.failure(error)):
            handleSearchFailure(
                error: error,
                title: "Unable to Run Collection Search",
                state: &state,
            )

        case let .filtersResponse(.failure(error)):
            handleSearchFailure(
                error: error,
                title: "Unable to Apply Collection Filters",
                state: &state,
            )

        default:
            nil
        }
    }

    private func handleComposerCollectionAction(
        _ action: ComposerFeature.Action,
        state: inout State,
    ) -> Effect<Action>? {
        guard case let ComposerAction.collection(collectionAction) = action else {
            return nil
        }
        return handleCollectionAction(collectionAction, state: &state)
    }

    private func handleSetPresented(_ isPresented: Bool, state: inout State) -> Effect<Action> {
        guard isPresented else {
            return .none
        }

        if state.composer.scopes.isEmpty,
           state.composer.conditions.isEmpty,
           state.composer.text.isEmpty
        {
            state.composer.scopes = [state.navigation.currentPath]
        }

        VoyagerSentryMetricLogger.logMetric(
            "voyager_composer_open",
            value: 1,
        )
        return .none
    }

    private func handleSetText(_ text: String, state: inout State) -> Effect<Action> {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        state.composer.pendingSearchQuery = query.isEmpty ? nil : query
        if query.isEmpty, state.composer.conditions.isEmpty, state.composer.scopes.isEmpty {
            return state.exitCollectionMode(computerName: computerNameClient.computerName())
        }
        return .none
    }

    private func handleSearchSuccess(
        items: [JSONValue],
        query: String,
        state: inout State,
    ) -> Effect<Action> {
        let wasOpeningCollectionFile = state.collectionSession.isOpening
        state.collectionSession.isOpening = false
        let previousSnapshot = state.navigation.makeContentPageNavigationHistorySnapshot()
        let previousNavigationState = state.navigation.navigationState
        state.composer.pendingSearchQuery = nil
        state.collectionContext = CollectionContext(
            query: query,
            scopes: state.composer.scopes,
            conditions: state.composer.conditions,
        )
        state.syncComposerCollectionState()
        if wasOpeningCollectionFile, state.collectionSession.openedURL != nil {
            state.collectionSession.baseline = CollectionBaseline(
                context: state.collectionContext ?? .init(query: "", scopes: [], conditions: []),
            )
        }
        let nextNavigationState = ContentPageNavigationRoute.collection(state.makeCollectionNavigation())
        let shouldAppendHistory = !wasOpeningCollectionFile
            && previousNavigationState != nextNavigationState
            && !(previousNavigationState.isCollection && nextNavigationState.isCollection)

        var navigationEffects: [Effect<Action>] = []
        if shouldAppendHistory {
            navigationEffects.append(.send(.requestNavigation(.internal(.appendBackHistory(previousSnapshot)))))
            navigationEffects.append(.send(.requestNavigation(.internal(.clearForwardHistory))))
        }
        navigationEffects.append(.send(.requestNavigation(.internal(.setNavigationState(nextNavigationState)))))

        if !wasOpeningCollectionFile, !previousNavigationState.isCollection {
            logContentPageNavigationDAUIfNeeded(previous: previousNavigationState, next: nextNavigationState)
        }
        return .concatenate(
            .concatenate(navigationEffects),
            .send(.entries(.setCollectionMode(true))),
            .run { send in
                await Task.yield()
                await send(.entries(.collectionItemsLoadedFromSearch(items)))
                await send(.composer(.searchListApplied))
            },
        )
    }

    private func handleSearchFailure(
        error: Error,
        title: String,
        state: inout State,
    ) -> Effect<Action> {
        state.composer.pendingSearchQuery = nil
        guard state.collectionSession.isOpening else {
            return .none
        }
        state.collectionSession = .init()
        state.resetComposer()
        let exitEffect = state.exitCollectionMode(computerName: computerNameClient.computerName())
        return .concatenate(
            .send(.requestNavigation(.internal(.rollbackBackHistoryOnce))),
            .merge(
                exitEffect,
                .run { _ in
                    await collectionAlertClient.showCollectionOpenErrorAlert(
                        title,
                        """
                        \(error.localizedDescription)

                        Check Gateway/Helper status and try again.
                        """,
                    )
                },
            ),
        )
    }

    private func handleCollectionAction(
        _ action: CollectionFeature.Action,
        state: inout State,
    ) -> Effect<Action> {
        switch action {
        case .saveRequested, .saveToExisting, .savePanelResponse:
            .none

        case let .saveCompleted(.success(url)):
            handleCollectionSaveSuccess(url: url, state: &state)

        case .saveCompleted(.failure):
            .send(.requestNavigation(.internal(.setPendingNavigation(nil))))
        }
    }

    private func handleCollectionSaveSuccess(url: URL, state: inout State) -> Effect<Action> {
        let previousSnapshot = state.navigation.makeContentPageNavigationHistorySnapshot()
        let previousCollectionURL = state.collectionSession.openedURL
        let previousCollectionName = state.collectionSession.openedName
        let previousBaseline = state.collectionSession.baseline
        let shouldAppendHistory = previousCollectionURL?.path != url.path

        state.collectionSession.openedURL = url
        state.collectionSession.openedName = url.deletingPathExtension().lastPathComponent
        state.collectionSession.originURL = url

        if let context = state.collectionContext {
            state.collectionSession.baseline = CollectionBaseline(
                context: context,
            )
        } else {
            state.collectionSession.baseline = nil
        }

        var navigationEffects: [Effect<Action>] = [
            .send(.requestNavigation(.internal(.setNavigationState(.collection(state.makeCollectionNavigation()))))),
        ]

        if shouldAppendHistory {
            if let baseline = previousBaseline,
               let previousURL = previousCollectionURL
            {
                let name = previousCollectionName
                    ?? previousURL.deletingPathExtension().lastPathComponent
                let navigation = ContentPageCollectionNavigation(
                    kind: .file(url: previousURL, name: name),
                    context: baseline.context,
                    sortKey: state.entryArrangements.sortKey,
                    sortOrder: state.entryArrangements.sortOrder,
                    viewLayout: state.viewLayout,
                )
                let entry = ContentPageNavigationHistorySnapshot(navigationState: .collection(navigation))
                navigationEffects.append(.send(.requestNavigation(.internal(.appendBackHistory(entry)))))
            } else {
                navigationEffects.append(.send(.requestNavigation(.internal(.appendBackHistory(previousSnapshot)))))
            }
            navigationEffects.append(.send(.requestNavigation(.internal(.clearForwardHistory))))
        }

        state.syncComposerCollectionState()

        if let pending = state.navigation.pendingNavigation {
            return .concatenate(
                .concatenate(navigationEffects),
                .send(.requestNavigation(.internal(.setPendingNavigation(nil)))),
                .send(.performPendingNavigation(pending)),
            )
        }

        return .concatenate(navigationEffects)
    }
}
