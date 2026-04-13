import ComposableArchitecture
import Foundation
import VoyagerShared

import VoyagerFeaturesEntryOperations
import VoyagerWidgetsEntryViewLayout

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
            if state.isCollectionMode {
                state.composer.pendingSearchQuery = nil
                state.collectionContext = CollectionContext(
                    query: "",
                    scopes: [ComposerScopeUtils.rootScopePath],
                    conditions: [],
                )
                state.syncComposerCollectionState()
                return .none
            }
            return exitCollectionMode(state: &state, computerName: dependencies.computerName)

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
        case let .internal(.filtersResponse(requestID, .success(response))):
            guard state.composer.lastAcceptedFiltersRequestID == requestID else {
                return .none
            }
            let effect = handleSearchSuccess(
                items: response.items ?? [],
                query: state.composer.pendingSearchQuery ?? "",
                state: &state,
            )
            return .concatenate(
                effect,
                .send(.delegate(.composerCollectionSearchSucceeded)),
            )

        case let .internal(.searchResponse(requestID, .failure(error))):
            guard state.composer.lastAcceptedSearchRequestID == requestID else {
                return .none
            }
            let effect = handleSearchFailure(
                error: error,
                title: "Unable to Run Collection Search",
                state: &state,
                dependencies: dependencies,
            )
            return .concatenate(
                effect,
                .send(.delegate(.composerCollectionSearchFailed)),
            )

        case let .internal(.filtersResponse(requestID, .failure(error))):
            guard state.composer.lastAcceptedFiltersRequestID == requestID else {
                return .none
            }
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
                .send(.delegate(.composerCollectionSearchFailed)),
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
            state.composer.pendingSearchQuery = nil
            state.collectionSession.isOpening = false
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
            return exitCollectionMode(state: &state, computerName: dependencies.computerName)
        }
        return .none
    }

    private static func handleSearchSuccess(
        items: [VoyagerShared.JSONValue],
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
        if wasOpeningCollectionFile, state.collectionSession.openedURL != nil {
            state.collectionSession.baseline = CollectionBaseline(
                context: state.collectionContext ?? .init(query: "", scopes: [], conditions: []),
            )
        }
        let nextNavigationState = ContentPageNavigationRoute.collection(makeCollectionNavigation(state: state))
        let shouldAppendHistory = !wasOpeningCollectionFile
            && previousNavigationState != nextNavigationState
            && !(previousNavigationState.isCollection && nextNavigationState.isCollection)

        var navigationEffects: [Effect<FileManagerContentAction>] = []
        if shouldAppendHistory {
            navigationEffects
                .append(.send(.internal(.requestNavigation(.internal(.appendBackHistory(previousSnapshot))))))
            navigationEffects.append(.send(.internal(.requestNavigation(.internal(.clearForwardHistory)))))
        }
        navigationEffects
            .append(.send(.internal(.requestNavigation(.internal(.setNavigationState(nextNavigationState))))))

        if !wasOpeningCollectionFile, !previousNavigationState.isCollection {
            logContentPageNavigationDAUIfNeeded(previous: previousNavigationState, next: nextNavigationState)
        }
        let showHidden = state.entryViewLayout.showHiddenFiles
        let paths = items.compactMap { item -> String? in
            guard case let .object(dict) = item,
                  case let .string(path) = dict["fullPath"]
            else { return nil }
            return path
        }

        return .concatenate(
            .concatenate(navigationEffects),
            .send(.entryViewLayout(.internal(.setCollectionMode(true)))),
            .send(.entryViewLayout(.internal(.applyCollectionSearchPaths(paths: paths, showHidden: showHidden)))),
            .send(.internal(.syncComposerCollectionState)),
            .send(.composer(.searchListApplied)),
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
        let exitEffect = exitCollectionMode(state: &state, computerName: dependencies.computerName)
        let collectionAlertClient = dependencies.collectionAlertClient
        return .concatenate(
            .send(.internal(.requestNavigation(.internal(.rollbackBackHistoryOnce)))),
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
        _ action: CollectionAction,
        state: inout FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        switch action {
        case .saveRequested, .saveToExisting, .savePanelResponse:
            .none

        case let .saveCompleted(.success(url)):
            handleCollectionSaveSuccess(url: url, state: &state)

        case .saveCompleted(.failure):
            .send(.internal(.requestNavigation(.internal(.setPendingNavigation(nil)))))
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
            .send(.internal(.requestNavigation(.internal(.setNavigationState(.collection(
                makeCollectionNavigation(state: state),
            )))))),
        ]

        if shouldAppendHistory {
            if let historyEntry = previousCollectionHistoryEntry(
                baseline: previousBaseline,
                previousURL: previousCollectionURL,
                previousCollectionName: previousCollectionName,
                state: state,
            ) {
                navigationEffects
                    .append(.send(.internal(.requestNavigation(.internal(.appendBackHistory(historyEntry))))))
            } else {
                navigationEffects
                    .append(.send(.internal(.requestNavigation(.internal(.appendBackHistory(previousSnapshot))))))
            }
            navigationEffects.append(.send(.internal(.requestNavigation(.internal(.clearForwardHistory)))))
        }

        state.syncComposerCollectionState()

        if let pending = state.navigation.pendingNavigation {
            return .concatenate(
                .concatenate(navigationEffects),
                .send(.internal(.requestNavigation(.internal(.setPendingNavigation(nil))))),
                .send(.internal(.performPendingNavigation(pending))),
            )
        }

        return .concatenate(navigationEffects)
    }
}

private func previousCollectionHistoryEntry(
    baseline: CollectionBaseline?,
    previousURL: URL?,
    previousCollectionName: String?,
    state: FileManagerContentState,
) -> ContentPageNavigationHistorySnapshot? {
    guard let baseline,
          let previousURL
    else {
        return nil
    }

    let name = previousCollectionName
        ?? previousURL.deletingPathExtension().lastPathComponent
    let navigation = ContentPageCollectionNavigation(
        kind: .file(url: previousURL, name: name),
        context: baseline.context,
        sortKey: state.entryViewLayout.entryArrangements.sortKey,
        sortOrder: state.entryViewLayout.entryArrangements.sortOrder,
        viewLayout: state.entryViewLayout.mode,
    )
    return ContentPageNavigationHistorySnapshot(
        navigationState: .collection(navigation),
    )
}

func makeCollectionNavigation(state: FileManagerContentState) -> ContentPageCollectionNavigation {
    let kind: ContentPageCollectionKind
    if let url = state.collectionSession.openedURL {
        let name = state.collectionSession.openedName ?? url.deletingPathExtension().lastPathComponent
        kind = .file(url: url, name: name)
    } else {
        kind = .temporary
    }

    let context = state.collectionContext
        ?? CollectionContext(query: "", scopes: [], conditions: [])

    return ContentPageCollectionNavigation(
        kind: kind,
        context: context,
        sortKey: state.entryViewLayout.entryArrangements.sortKey,
        sortOrder: state.entryViewLayout.entryArrangements.sortOrder,
        viewLayout: state.entryViewLayout.mode,
    )
}

func clearCollectionMode(state: inout FileManagerContentState) -> Effect<FileManagerContentAction> {
    state.collectionContext = nil
    state.composer.pendingSearchQuery = nil
    state.collectionSession = .init()

    return .concatenate(
        .send(.internal(.requestNavigation(.internal(.setPendingNavigation(nil))))),
        .cancel(id: "openCollectionFile"),
        .cancel(id: ComposerFeature.CancelID.search),
        .cancel(id: ComposerFeature.CancelID.filters),
        .send(.entryViewLayout(.internal(.clearCollectionPresentation))),
        .send(.internal(.syncComposerCollectionState)),
    )
}

func exitCollectionMode(
    state: inout FileManagerContentState,
    computerName: String,
) -> Effect<FileManagerContentAction> {
    let wasCollection = if case .collection = state.navigation.navigationState { true } else { false }
    let clearEffect = clearCollectionMode(state: &state)

    guard wasCollection else {
        return clearEffect
    }

    let navigationState = ContentPageNavigationRoute.fromPath(
        state.navigation.titlePath,
        computerName: computerName,
    )

    return .concatenate(
        .send(.internal(.requestNavigation(.internal(.setNavigationState(navigationState))))),
        clearEffect,
    )
}
