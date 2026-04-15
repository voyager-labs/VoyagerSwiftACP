import ComposableArchitecture
import Foundation

import VoyagerFeaturesEntryOperations

@Reducer
struct FileManagerNavigationActionReducer {
    @Dependency(\.fileManagerClient)
    var fileManagerClient
    @Dependency(\.collectionFileClient)
    var collectionFileClient
    @Dependency(\.collectionAlertClient)
    var collectionAlertClient
    @Dependency(\.registryClient)
    var registryClient
    @Dependency(\.collectionStalenessClient)
    var collectionStalenessClient

    typealias State = FileManagerWindowState
    typealias Action = FileManagerWindowAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            guard case let .navigation(navigationAction) = action else {
                return .none
            }
            return handleNavigationAction(navigationAction, state: &state)
        }
    }

    private func handleNavigationAction(
        _ action: ContentPageNavigationAction,
        state: inout State,
    ) -> Effect<Action> {
        switch action {
        case let .view(viewAction):
            handleViewAction(viewAction, state: &state)

        case let .internal(internalAction):
            handleInternalAction(internalAction, state: &state)

        case let .delegate(delegateAction):
            handleNavigationDelegate(
                delegateAction,
                state: &state,
                computerName: fileManagerClient.displayName("/"),
            )
        }
    }

    private func handleViewAction(
        _ action: ContentPageNavigationAction.View,
        state: inout State,
    ) -> Effect<Action> {
        switch action {
        case .navigateToPath,
             .showRecents,
             .showComputer,
             .showTag:
            handleDirectNavigationAction(action, state: &state)

        case .goBack,
             .goForward,
             .goToHistoryIndex,
             .goToEnclosingDirectory:
            handleHistoryNavigationAction(action, state: &state)

        case let .openCollectionFile(url):
            handleOpenCollectionFile(
                url,
                state: &state,
                collectionFileClient: collectionFileClient,
                collectionStalenessClient: collectionStalenessClient,
            )
        }
    }

    private func handleInternalAction(
        _ action: ContentPageNavigationAction.Internal,
        state: inout State,
    ) -> Effect<Action> {
        switch action {
        case .collectionFileLoaded,
             .navigateToCollection:
            return handleCollectionNavigationAction(action, state: &state)

        case .showUnsavedNavigationAlert,
             .unsavedNavigationAlertResponse,
             .performNavigation:
            return handleUnsavedNavigationAction(action, state: &state)

        case .performNavigateToPath,
             .performShowRecents,
             .performShowComputer,
             .performShowTag,
             .prepareCollectionFileOpen,
             .rollbackBackHistoryOnce,
             .appendBackHistory,
             .clearForwardHistory,
             .setNavigationState,
             .setPendingNavigation:
            syncSidebarSelection(state: &state, computerName: fileManagerClient.displayName("/"))
            return .none
        }
    }

    private func handleDirectNavigationAction(
        _ action: ContentPageNavigationAction.View,
        state: inout State,
    ) -> Effect<Action> {
        switch action {
        case let .navigateToPath(path):
            let computerName = fileManagerClient.displayName("/")
            if path == computerName, state.content.navigation.currentPath == computerName {
                return .none
            }
            return .send(.navigation(.internal(.performNavigateToPath(path))))

        case .showRecents:
            return .send(.navigation(.internal(.performShowRecents)))

        case .showComputer:
            return .send(.navigation(.internal(.performShowComputer)))

        case let .showTag(tagName):
            return .send(.navigation(.internal(.performShowTag(tagName))))

        default:
            return .none
        }
    }

    private func handleCollectionNavigationAction(
        _ action: ContentPageNavigationAction.Internal,
        state: inout State,
    ) -> Effect<Action> {
        switch action {
        case let .collectionFileLoaded(result):
            handleCollectionFileLoaded(
                result,
                state: &state,
                collectionAlertClient: collectionAlertClient,
                registryClient: registryClient,
                collectionStalenessClient: collectionStalenessClient,
                computerName: fileManagerClient.displayName("/"),
            )

        case let .navigateToCollection(navigation):
            handleNavigateToCollection(navigation, state: &state)

        default:
            .none
        }
    }

    private func handleHistoryNavigationAction(
        _ action: ContentPageNavigationAction.View,
        state: inout State,
    ) -> Effect<Action> {
        switch action {
        case .goBack:
            handleNavigationRequest(.back, state: &state)

        case .goForward:
            handleNavigationRequest(.forward, state: &state)

        case let .goToHistoryIndex(index, isBackHistory):
            handleNavigationRequest(.history(index: index, isBackHistory: isBackHistory), state: &state)

        case .goToEnclosingDirectory:
            handleNavigationRequest(.enclosingDirectory, state: &state)

        default:
            .none
        }
    }

    private func handleNavigationRequest(
        _ pending: ContentPageNavigationPending,
        state: inout State,
    ) -> Effect<Action> {
        if shouldPromptForUnsavedNavigation(state.content) {
            return .send(.navigation(.internal(.showUnsavedNavigationAlert(pending))))
        }
        return .send(.navigation(.internal(.performNavigation(pending))))
    }

    private func handleUnsavedNavigationAction(
        _ action: ContentPageNavigationAction.Internal,
        state: inout State,
    ) -> Effect<Action> {
        switch action {
        case let .showUnsavedNavigationAlert(pending):
            return .run { send in
                let choice = await collectionAlertClient.showUnsavedNavigationAlert()
                await send(.navigation(.internal(.unsavedNavigationAlertResponse(pending, choice))))
            }
        case let .unsavedNavigationAlertResponse(pending, choice):
            return handleUnsavedNavigationAlertResponse(pending: pending, choice: choice, state: &state)
        case .performNavigation:
            if state.content.resetComposerOnNextDirectoryNavigation {
                state.content.resetComposer()
                state.content.resetComposerOnNextDirectoryNavigation = false
            }
            return .none
        default:
            return .none
        }
    }

    private func handleUnsavedNavigationAlertResponse(
        pending: ContentPageNavigationPending,
        choice: CollectionNavigationChoice,
        state: inout State,
    ) -> Effect<Action> {
        switch choice {
        case .cancel:
            return .none
        case .discard:
            state.content.resetComposerOnNextDirectoryNavigation = true
            return .send(.navigation(.internal(.performNavigation(pending))))
        case .save:
            state.content.resetComposerOnNextDirectoryNavigation = true
            return .concatenate(
                .send(.navigation(.internal(.setPendingNavigation(pending)))),
                .send(.content(.composer(.saveCollection))),
            )
        }
    }

    private func shouldPromptForUnsavedNavigation(_ state: FileManagerContentState) -> Bool {
        state.isCollectionMode && state.canSaveCollection
    }
}

private func handleOpenCollectionFile(
    _ url: URL,
    state: inout FileManagerWindowState,
    collectionFileClient: CollectionFileClient,
    collectionStalenessClient _: CollectionStalenessClient,
) -> Effect<FileManagerWindowAction> {
    if state.content.collectionSession.openedURL?.path != url.path {
        VoyagerSentryMetricLogger.logDAUNavigation(kind: .collection)
    }

    let prepareHistoryEffect: Effect<FileManagerWindowAction> = .send(
        .navigation(.internal(.prepareCollectionFileOpen(url))),
    )

    let clearEffect: Effect<FileManagerContentAction> = clearCollectionMode(state: &state.content)
    state.content.collectionSession.isOpening = true
    state.content.collectionSession.isStale = false
    state.content.collectionSession.staleReason = nil
    state.content.collectionSession.lastRefreshAt = nil
    state.content.collectionSession.didHydrateSnapshotOnOpen = false
    state.content.collectionSession.isRefreshingHydratedSnapshot = false
    state.content.collectionSession.isWritingBackRefreshedSnapshot = false
    state.content.collectionSession.openedName = url.deletingPathExtension().lastPathComponent
    state.content.collectionSession.openedURL = url
    state.content.collectionSession.originURL = url
    state.content.collectionSession.baseline = nil
    state.content.syncComposerCollectionState()

    let loadEffect: Effect<FileManagerWindowAction> = .run { [url] send in
        do {
            let file = try await collectionFileClient.load(url)
            try Task.checkCancellation()
            await send(.navigation(.internal(.collectionFileLoaded(.success(file)))))
        } catch is CancellationError {
            return
        } catch {
            await send(
                .navigation(
                    .internal(.collectionFileLoaded(.failure(ContentPageNavigationErrorFingerprint(error: error)))),
                ),
            )
        }
    }
    .cancellable(id: "openCollectionFile", cancelInFlight: true)

    return .concatenate(
        prepareHistoryEffect,
        clearEffect.map(FileManagerWindowAction.content),
        loadEffect,
    )
}

private func handleCollectionFileLoaded(
    _ result: ContentPageCollectionFileLoadResult,
    state: inout FileManagerWindowState,
    collectionAlertClient: CollectionAlertClient,
    registryClient: RegistryClient,
    collectionStalenessClient: CollectionStalenessClient,
    computerName: String,
) -> Effect<FileManagerWindowAction> {
    switch result {
    case let .success(file):
        if let url = state.content.collectionSession.openedURL {
            let isStale = collectionStalenessClient.consumeInvalidation(url.path)
            state.content.collectionSession.isStale = isStale
            collectionStalenessClient.registerCollection(url.path, file.scopes)
        }
        return handleCollectionFileLoadedSuccess(
            file,
            isStale: state.content.collectionSession.isStale,
            state: &state,
            collectionAlertClient: collectionAlertClient,
            registryClient: registryClient,
            computerName: computerName,
        )
    case let .failure(error):
        return handleCollectionFileLoadedFailure(
            error,
            state: &state,
            collectionAlertClient: collectionAlertClient,
            computerName: computerName,
        )
    }
}

private func handleNavigateToCollection(
    _ navigation: ContentPageCollectionNavigation,
    state: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    applyCollectionNavigationState(navigation, state: &state)
    configureCollectionNavigationComposer(navigation, state: &state)

    let trimmedQuery = navigation.context.query.trimmingCharacters(in: .whitespacesAndNewlines)
    return .merge(
        .send(.content(.entryViewLayout(.entryArrangements(.reapply)))),
        trimmedQuery.isEmpty ? .send(.content(.composer(.applyFilters))) : .send(.content(.composer(.submit))),
    )
}

private func handleCollectionFileLoadedSuccess(
    _ file: VoyagerCollectionFile,
    isStale: Bool,
    state: inout FileManagerWindowState,
    collectionAlertClient: CollectionAlertClient,
    registryClient: RegistryClient,
    computerName: String,
) -> Effect<FileManagerWindowAction> {
    state.content.collectionSession.isOpening = false
    state.content.composer.isPresented = false
    state.content.collectionSession.isStale = isStale
    state.content.collectionSession.staleReason = isStale ? .invalidatedLocally : nil
    let resolved = file.resolveCollectionFilters(registryClient: registryClient)
    if isEmptyCollectionDefinition(file: file, resolved: resolved) {
        return handleEmptyCollectionFile(
            state: &state,
            collectionAlertClient: collectionAlertClient,
            computerName: computerName,
        )
    }

    let openContext = prepareLoadedCollectionOpenState(
        file: file,
        resolved: resolved,
        isStale: isStale,
        registryClient: registryClient,
        state: &state,
    )

    if let effects = makeHydratedCollectionOpenEffects(
        file: file,
        openContext: openContext,
        resolved: resolved,
        isStale: isStale,
        collectionAlertClient: collectionAlertClient,
        state: &state,
    ) {
        return .concatenate(effects)
    }

    var effects: [Effect<FileManagerWindowAction>] = []

    if !isStale {
        effects.append(
            openContext.trimmedQuery
                .isEmpty ? .send(.content(.composer(.applyFilters))) : .send(.content(.composer(.submit))),
        )
    }

    if !resolved.unknownKeys.isEmpty {
        effects.append(contentsOf: unsupportedFilterWarningEffects(
            unknownKeys: resolved.unknownKeys,
            collectionAlertClient: collectionAlertClient,
        ))
    }

    return effects.isEmpty ? .none : .merge(effects)
}

private func handleCollectionFileLoadedFailure(
    _ error: ContentPageNavigationErrorFingerprint,
    state: inout FileManagerWindowState,
    collectionAlertClient: CollectionAlertClient,
    computerName: String,
) -> Effect<FileManagerWindowAction> {
    state.content.collectionSession = .init()
    state.content.resetComposer()

    let exitEffect = exitCollectionMode(
        state: &state.content,
        computerName: computerName,
    )
    var effects: [Effect<FileManagerWindowAction>] = [.send(.navigation(.internal(.rollbackBackHistoryOnce)))]
    if state.sidebar.pendingSidebarSelectionRestore != nil {
        effects.append(.send(.sidebar(.internal(.restoreSidebarSelection))))
    }
    effects.append(exitEffect.map(FileManagerWindowAction.content))
    effects.append(.run { _ in
        await collectionAlertClient.showCollectionOpenErrorAlert("Unable to Open Collection", error.message)
    })
    return .merge(effects)
}

private func handleEmptyCollectionFile(
    state: inout FileManagerWindowState,
    collectionAlertClient: CollectionAlertClient,
    computerName: String,
) -> Effect<FileManagerWindowAction> {
    state.content.collectionSession = .init()
    state.content.resetComposer()

    let exitEffect = exitCollectionMode(
        state: &state.content,
        computerName: computerName,
    )
    return .concatenate(
        .send(.navigation(.internal(.rollbackBackHistoryOnce))),
        .merge(
            exitEffect.map(FileManagerWindowAction.content),
            .run { _ in
                await collectionAlertClient.showCollectionOpenErrorAlert(
                    "Empty Collection",
                    "This collection file has no query, scope, or filters.",
                )
            },
        ),
    )
}
