import ComposableArchitecture
import Foundation

enum FileManagerContentComposerCoordinator {
    struct Dependencies: Sendable {
        let collectionAlertClient: CollectionAlertClient
        let computerName: String
    }

    static func reduce(
        _ action: ComposerFeature.Action,
        state: inout FileManagerContentState,
        dependencies: Dependencies,
    ) -> Effect<FileManagerContentAction> {
        if let effect = handleComposerLifecycleAction(action, state: &state, dependencies: dependencies) {
            return effect
        }

        if let effect = handleComposerCollectionAction(action, state: &state) {
            return effect
        }

        return .none
    }

    private static func handleComposerLifecycleAction(
        _ action: ComposerFeature.Action,
        state: inout FileManagerContentState,
        dependencies: Dependencies,
    ) -> Effect<FileManagerContentAction>? {
        if let effect = handleComposerSearchResponseAction(action, state: &state, dependencies: dependencies) {
            return effect
        }

        switch action {
        case let .view(.setPresented(isPresented)):
            return handleSetPresented(isPresented, state: &state)

        case .view(.applyFilters):
            state.composer.isLoadingFilters = true
            return .none

        case let .view(.setText(text)):
            return handleSetText(text, state: &state, dependencies: dependencies)

        case .view(.cancelSearch):
            state.composer.pendingSearchQuery = nil
            state.collectionSession.isOpening = false
            state.collectionSession.openedName = nil
            return .none

        case .view(.clearAll):
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
            return state.exitCollectionMode(computerName: dependencies.computerName)

        default:
            return nil
        }
    }

    private static func handleComposerSearchResponseAction(
        _ action: ComposerFeature.Action,
        state: inout FileManagerContentState,
        dependencies: Dependencies,
    ) -> Effect<FileManagerContentAction>? {
        switch action {
        case let .internal(.filtersResponse(.success(response))):
            let effect = handleSearchSuccess(
                items: response.items ?? [],
                query: state.composer.pendingSearchQuery ?? "",
                state: &state,
            )
            return .concatenate(
                effect,
                .send(.composerCollectionSearchSucceeded),
            )

        case let .internal(.searchResponse(.failure(error))):
            let effect = handleSearchFailure(
                error: error,
                title: "Unable to Run Collection Search",
                state: &state,
                dependencies: dependencies,
            )
            return .concatenate(
                effect,
                .send(.composerCollectionSearchFailed),
            )

        case let .internal(.filtersResponse(.failure(error))):
            let title = state.composer.pendingSearchQuery == nil
                ? "Unable to Apply Collection Filters"
                : "Unable to Run Collection Search"
            let effect = handleSearchFailure(
                error: error,
                title: title,
                state: &state,
                dependencies: dependencies,
            )
            return .concatenate(
                effect,
                .send(.composerCollectionSearchFailed),
            )

        default:
            return nil
        }
    }

    private static func handleComposerCollectionAction(
        _ action: ComposerFeature.Action,
        state: inout FileManagerContentState,
    ) -> Effect<FileManagerContentAction>? {
        guard case let ComposerAction.collection(collectionAction) = action else {
            return nil
        }
        return handleCollectionAction(collectionAction, state: &state)
    }

    private static func handleSetPresented(
        _ isPresented: Bool,
        state: inout FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
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

    private static func handleSetText(
        _ text: String,
        state: inout FileManagerContentState,
        dependencies: Dependencies,
    ) -> Effect<FileManagerContentAction> {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        state.composer.pendingSearchQuery = query.isEmpty ? nil : query
        if query.isEmpty, state.composer.conditions.isEmpty, state.composer.scopes.isEmpty {
            return state.exitCollectionMode(computerName: dependencies.computerName)
        }
        return .none
    }

    private static func handleSearchSuccess(
        items: [JSONValue],
        query: String,
        state: inout FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
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

        var navigationEffects: [Effect<FileManagerContentAction>] = []
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

    private static func handleSearchFailure(
        error: Error,
        title: String,
        state: inout FileManagerContentState,
        dependencies: Dependencies,
    ) -> Effect<FileManagerContentAction> {
        state.composer.pendingSearchQuery = nil
        guard state.collectionSession.isOpening else {
            return .none
        }
        state.collectionSession = .init()
        state.resetComposer()
        let exitEffect = state.exitCollectionMode(computerName: dependencies.computerName)
        let collectionAlertClient = dependencies.collectionAlertClient
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

    private static func handleCollectionAction(
        _ action: CollectionFeature.Action,
        state: inout FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        switch action {
        case .saveRequested, .saveToExisting, .savePanelResponse:
            .none

        case let .saveCompleted(.success(url)):
            handleCollectionSaveSuccess(url: url, state: &state)

        case .saveCompleted(.failure):
            .send(.requestNavigation(.internal(.setPendingNavigation(nil))))
        }
    }

    private static func handleCollectionSaveSuccess(
        url: URL,
        state: inout FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
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

        var navigationEffects: [Effect<FileManagerContentAction>] = [
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
                let entry = ContentPageNavigationHistorySnapshot(
                    navigationState: .collection(navigation),
                )
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
