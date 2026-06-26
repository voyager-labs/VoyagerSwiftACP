import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import VoyagerShared

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
    @Dependency(\.metricsClient)
    var metricsClient

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
                metricsClient: metricsClient,
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
                metricsClient: metricsClient,
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
            guard state.content.resetComposerOnNextDirectoryNavigation else {
                return .none
            }
            return .send(.content(.internal(.resetComposerAfterDirectoryNavigation)))
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
            return .concatenate(
                .send(.content(.view(.discardCollectionChanges))),
                .send(.navigation(.internal(.performNavigation(pending)))),
            )
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

struct OpenCollectionFileCancelID: Hashable {
    let windowID: UUID?
}

private func handleOpenCollectionFile(
    _ url: URL,
    state: inout FileManagerWindowState,
    collectionFileClient: CollectionFileClient,
    collectionStalenessClient: CollectionStalenessClient,
    metricsClient: MetricsClient,
) -> Effect<FileManagerWindowAction> {
    if state.content.collection.collectionSession.document?.url.path != url.path {
        metricsClient.logDAUNavigation(.collection)
    }

    let canonicalPath = url.standardizedFileURL.path
    let isAlreadyStale = collectionStalenessClient.record(canonicalPath)?.lastInvalidatedAt != nil
    let reopenContext = state.content.collection.collectionContext
    let clearExistingCollectionEffect: Effect<FileManagerWindowAction> = if state.content.isCollectionMode {
        .send(.content(.internal(.clearCollectionMode)))
    } else {
        .none
    }

    let loadEffect: Effect<FileManagerWindowAction> = .run { [url] send in
        do {
            let result = try await collectionFileClient.load(url)
            try Task.checkCancellation()
            await send(.navigation(.internal(.collectionFileLoaded(.success(result)))))
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
    .cancellable(
        id: OpenCollectionFileCancelID(windowID: state.content.entryViewLayout.entryOperations.windowID),
        cancelInFlight: true,
    )

    return .concatenate(
        .send(.content(.entryViewLayout(.internal(.setCollectionContentLoading(true))))),
        clearExistingCollectionEffect,
        .send(.content(.collection(.openRequested(
            url,
            reopenContext: reopenContext,
            isAlreadyStale: isAlreadyStale,
        )))),
        .send(.navigation(.internal(.prepareCollectionFileOpen(url)))),
        loadEffect,
    )
}

private func handleCollectionFileLoaded(
    _ result: ContentPageCollectionFileLoadResult,
    state: inout FileManagerWindowState,
    collectionAlertClient: CollectionAlertClient,
    registryClient: RegistryClient,
    collectionStalenessClient: CollectionStalenessClient,
) -> Effect<FileManagerWindowAction> {
    switch result {
    case let .success(loadResult):
        let file = loadResult.file
        var isStale = false
        if let url = state.content.collection.collectionSession.document?.url {
            let canonicalPath = url.standardizedFileURL.path
            isStale = collectionStalenessClient.record(canonicalPath)?.lastInvalidatedAt != nil
            collectionStalenessClient.registerCollection(
                canonicalPath,
                file.scopes,
                file.excludedScopes,
                file.includeSubfolders,
            )
        }
        return handleCollectionFileLoadedSuccess(
            file,
            compatibility: loadResult.compatibility,
            isStale: isStale,
            state: &state,
            environment: .init(
                collectionAlertClient: collectionAlertClient,
                registryClient: registryClient,
            ),
        )
    case let .failure(error):
        return handleCollectionFileLoadedFailure(
            error,
            state: &state,
            collectionAlertClient: collectionAlertClient,
        )
    }
}

private func handleNavigateToCollection(
    _ navigation: ContentPageCollectionNavigation,
    state _: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    let (openedURL, openedName): (URL?, String?) = switch navigation.kind {
    case .temporary:
        (nil, nil)
    case let .file(url, name):
        (url, name)
    }
    let payload = CollectionNavigationStatePayload(
        context: navigation.context,
        includeSubfolders: navigation.context.includeSubfolders,
        document: openedURL.map {
            CollectionOpenedDocumentState(
                url: $0,
                name: openedName ?? $0.deletingPathExtension().lastPathComponent,
                compatibility: navigation.compatibility,
            )
        },
        baseline: openedURL.map { _ in CollectionBaseline(context: navigation.context) },
        composerText: navigation.context.query,
        scopes: navigation.context.scopes,
        excludedScopes: navigation.context.excludedScopes,
        conditions: navigation.context.conditions,
    )

    let trimmedQuery = navigation.context.query.trimmingCharacters(in: .whitespacesAndNewlines)
    let queryEffect: Effect<FileManagerWindowAction> = trimmedQuery.isEmpty
        ? .send(.content(.composer(.applyFilters)))
        : .send(.content(.composer(.submit)))
    return .concatenate(
        .send(.content(.collection(.navigationStateApplied(payload)))),
        .send(.content(.composer(.applyCollectionNavigationComposer(payload)))),
        .send(.content(.entryViewLayout(.internal(.setCollectionMode(true))))),
        .send(.content(.composer(.syncCollectionState(
            context: payload.context,
            url: payload.document?.url,
            compatibility: payload.document?.compatibility,
            isCollectionMode: true,
        )))),
        .send(.content(.entryViewLayout(.entryArrangements(.reapply)))),
        queryEffect,
    )
}

private func handleCollectionFileLoadedSuccess(
    _ file: VoyagerCollectionFile,
    compatibility: CollectionFileCompatibilityMetadata,
    isStale: Bool,
    state: inout FileManagerWindowState,
    environment: CollectionOpenEnvironment,
) -> Effect<FileManagerWindowAction> {
    state.content.composer.isPresented = false
    let resolved = file.resolveCollectionFilters(registryClient: environment.registryClient)
    let openPayload = state.content.collection.makeOpenRestorationPayload(
        file: file,
        resolved: resolved,
        isStale: isStale,
        compatibility: compatibility,
    )

    let dismissComposerEffect: Effect<FileManagerWindowAction> = .send(.content(.composer(.setPresented(false))))

    if openPayload.isEmptyDefinition {
        return .concatenate(
            dismissComposerEffect,
            handleEmptyCollectionFile(
                state: &state,
                collectionAlertClient: environment.collectionAlertClient,
            ),
        )
    }

    prepareLoadedCollectionOpenState(
        restorationPayload: openPayload,
        registryClient: environment.registryClient,
        state: &state,
    )

    if let effects = makeHydratedCollectionOpenEffects(
        payload: openPayload,
        collectionAlertClient: environment.collectionAlertClient,
        state: &state,
    ) {
        return .concatenate(dismissComposerEffect, .concatenate(effects))
    }

    var effects = makeCollectionOpenFollowupEffects(
        payload: openPayload,
        collectionAlertClient: environment.collectionAlertClient,
        state: state,
    )

    if openPayload.queryTrigger == nil {
        effects.append(.send(.content(.entryViewLayout(.internal(.setCollectionContentLoading(false))))))
    }

    if effects.isEmpty {
        return dismissComposerEffect
    }
    return .concatenate([dismissComposerEffect] + effects)
}

private struct CollectionOpenEnvironment {
    let collectionAlertClient: CollectionAlertClient
    let registryClient: RegistryClient
}

private func handleCollectionFileLoadedFailure(
    _ error: ContentPageNavigationErrorFingerprint,
    state: inout FileManagerWindowState,
    collectionAlertClient: CollectionAlertClient,
) -> Effect<FileManagerWindowAction> {
    var effects: [Effect<FileManagerWindowAction>] = [
        .send(.content(.entryViewLayout(.internal(.setCollectionContentLoading(false))))),
        .send(.navigation(.internal(.rollbackBackHistoryOnce))),
    ]
    if state.sidebar.pendingSidebarSelectionRestore != nil {
        effects.append(.send(.sidebar(.internal(.restoreSidebarSelection))))
    }
    effects.append(.send(.content(.collection(.sessionResetRequested))))
    effects.append(.send(.content(.internal(.exitCollectionMode))))
    effects.append(.send(.content(.composer(.resetComposerAndSync(
        context: nil,
        url: nil,
        compatibility: nil,
        isCollectionMode: false,
    )))))
    effects.append(.run { _ in
        await collectionAlertClient.showCollectionOpenErrorAlert("Unable to Open Collection", error.message)
    })
    return .concatenate(effects)
}

private func handleEmptyCollectionFile(
    state _: inout FileManagerWindowState,
    collectionAlertClient: CollectionAlertClient,
) -> Effect<FileManagerWindowAction> {
    .concatenate(
        .send(.content(.entryViewLayout(.internal(.setCollectionContentLoading(false))))),
        .send(.content(.collection(.sessionResetRequested))),
        .send(.content(.internal(.exitCollectionMode))),
        .send(.navigation(.internal(.rollbackBackHistoryOnce))),
        .send(.content(.composer(.resetComposerAndSync(
            context: nil,
            url: nil,
            compatibility: nil,
            isCollectionMode: false,
        )))),
        .run { _ in
            await collectionAlertClient.showCollectionOpenErrorAlert(
                "Empty Collection",
                "This collection file has no query, scope, or filters.",
            )
        },
    )
}
