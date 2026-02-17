import ComposableArchitecture
import Foundation

@Reducer
struct FileManagerNavigationActionReducer {
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
        case .navigateToPath,
             .showRecents,
             .showComputer,
             .showTag:
            return handleDirectNavigationAction(action, state: &state)

        case .openCollectionFile,
             .collectionFileLoaded,
             .navigateToCollection:
            return handleCollectionNavigationAction(action, state: &state)

        case .goBack,
             .goForward,
             .goToHistoryIndex,
             .goToEnclosingDirectory:
            return handleHistoryNavigationAction(action, state: &state)

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
            syncSidebarSelection(state: &state, computerName: computerNameClient.computerName())
            return .none

        case let .delegate(delegateAction):
            return handleNavigationDelegate(
                delegateAction,
                state: &state,
                computerName: computerNameClient.computerName(),
            )
        }
    }

    private func handleDirectNavigationAction(
        _ action: ContentPageNavigationAction,
        state: inout State,
    ) -> Effect<Action> {
        switch action {
        case let .navigateToPath(path):
            let computerName = computerNameClient.computerName()
            if path == computerName, state.content.navigation.currentPath == computerName {
                return .none
            }
            return .send(.navigation(.performNavigateToPath(path, currentSnapshot: currentNavigationSnapshot(state))))

        case .showRecents:
            return .send(.navigation(.performShowRecents(currentSnapshot: currentNavigationSnapshot(state))))

        case .showComputer:
            return .send(.navigation(.performShowComputer(currentSnapshot: currentNavigationSnapshot(state))))

        case let .showTag(tagName):
            return .send(.navigation(.performShowTag(tagName, currentSnapshot: currentNavigationSnapshot(state))))

        default:
            return .none
        }
    }

    private func handleCollectionNavigationAction(
        _ action: ContentPageNavigationAction,
        state: inout State,
    ) -> Effect<Action> {
        switch action {
        case let .openCollectionFile(url):
            handleOpenCollectionFile(
                url,
                state: &state,
                collectionFileClient: collectionFileClient,
            )
        case let .collectionFileLoaded(result):
            handleCollectionFileLoaded(
                result,
                state: &state,
                collectionAlertClient: collectionAlertClient,
                registryClient: registryClient,
                computerName: computerNameClient.computerName(),
            )
        case let .navigateToCollection(navigation):
            handleNavigateToCollection(navigation, state: &state)
        default:
            .none
        }
    }

    private func handleHistoryNavigationAction(
        _ action: ContentPageNavigationAction,
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
            return .send(.navigation(.showUnsavedNavigationAlert(pending)))
        }
        return .send(.navigation(.performNavigation(pending, currentSnapshot: currentNavigationSnapshot(state))))
    }

    private func handleUnsavedNavigationAction(
        _ action: ContentPageNavigationAction,
        state: inout State,
    ) -> Effect<Action> {
        switch action {
        case let .showUnsavedNavigationAlert(pending):
            return .run { send in
                let choice = await collectionAlertClient.showUnsavedNavigationAlert()
                await send(.navigation(.unsavedNavigationAlertResponse(pending, choice)))
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
            return .send(.navigation(.performNavigation(pending, currentSnapshot: currentNavigationSnapshot(state))))
        case .save:
            state.content.resetComposerOnNextDirectoryNavigation = true
            return .concatenate(
                .send(.navigation(.setPendingNavigation(pending))),
                .send(.content(.composer(.saveCollection))),
            )
        }
    }

    private func currentNavigationSnapshot(_ state: State) -> ContentPageNavigationHistorySnapshot {
        state.content.navigation.makeContentPageNavigationHistorySnapshot(composer: state.content.composer)
    }

    private func shouldPromptForUnsavedNavigation(_ state: FileManagerContentState) -> Bool {
        state.entryOperations.loadingContext.isCollectionMode && state.canSaveCollection
    }
}

private func handleOpenCollectionFile(
    _ url: URL,
    state: inout FileManagerWindowState,
    collectionFileClient: CollectionFileClient,
) -> Effect<FileManagerWindowAction> {
    if state.content.collectionSession.openedURL?.path != url.path {
        VoyagerSentryMetricLogger.logDAUNavigation(kind: .collection)
    }

    let prepareHistoryEffect: Effect<FileManagerWindowAction> = .send(
        .navigation(.prepareCollectionFileOpen(
            url,
            currentSnapshot: state.content.navigation.makeContentPageNavigationHistorySnapshot(composer: state.content
                .composer),
        )),
    )

    let clearEffect = state.content.clearCollectionMode()
    state.content.collectionSession.isOpening = true
    state.content.collectionSession.openedName = url.deletingPathExtension().lastPathComponent
    state.content.collectionSession.openedURL = url
    state.content.collectionSession.originURL = url
    state.content.collectionSession.baseline = nil
    state.content.syncComposerCollectionState()

    let loadEffect: Effect<FileManagerWindowAction> = .run { [url] send in
        do {
            let file = try await collectionFileClient.load(url)
            try Task.checkCancellation()
            await send(.navigation(.collectionFileLoaded(.success(file))))
        } catch is CancellationError {
            return
        } catch {
            await send(
                .navigation(.collectionFileLoaded(.failure(ContentPageNavigationErrorFingerprint(error: error)))),
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
    computerName: String,
) -> Effect<FileManagerWindowAction> {
    switch result {
    case let .success(file):
        handleCollectionFileLoadedSuccess(
            file,
            state: &state,
            collectionAlertClient: collectionAlertClient,
            registryClient: registryClient,
            computerName: computerName,
        )
    case let .failure(error):
        handleCollectionFileLoadedFailure(
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
        .send(.content(.entryArrangements(.reapply))),
        trimmedQuery.isEmpty ? .send(.content(.composer(.applyFilters))) : .send(.content(.composer(.submit))),
    )
}

private func handleCollectionFileLoadedSuccess(
    _ file: VoyagerCollectionFile,
    state: inout FileManagerWindowState,
    collectionAlertClient: CollectionAlertClient,
    registryClient: RegistryClient,
    computerName: String,
) -> Effect<FileManagerWindowAction> {
    state.content.composer.isPresented = false
    let trimmedQuery = file.query.trimmingCharacters(in: .whitespacesAndNewlines)
    state.content.composer.pendingSearchQuery = trimmedQuery.isEmpty ? nil : trimmedQuery

    let resolved = file.resolveCollectionFilters(registryClient: registryClient)
    if trimmedQuery.isEmpty, resolved.scopes.isEmpty, resolved.conditions.isEmpty {
        return handleEmptyCollectionFile(
            state: &state,
            collectionAlertClient: collectionAlertClient,
            computerName: computerName,
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

    var effects: [Effect<FileManagerWindowAction>] = [
        state.content.collectionSession.isOpening
            ? .send(.content(.composer(.applyFilters)))
            : (trimmedQuery.isEmpty ? .send(.content(.composer(.applyFilters))) : .send(.content(.composer(.submit)))),
    ]

    if !resolved.unknownKeys.isEmpty {
        let joinedKeys = resolved.unknownKeys.joined(separator: ", ")
        let warningMessage = [
            "Some filters in this collection are no longer supported and were disabled:",
            "\(joinedKeys).",
        ].joined(separator: " ")
        effects.append(.run { _ in
            await collectionAlertClient.showCollectionOpenErrorAlert("Unsupported Filters", warningMessage)
        })
    }

    return .merge(effects)
}

private func handleCollectionFileLoadedFailure(
    _ error: ContentPageNavigationErrorFingerprint,
    state: inout FileManagerWindowState,
    collectionAlertClient: CollectionAlertClient,
    computerName: String,
) -> Effect<FileManagerWindowAction> {
    state.content.collectionSession = .init()
    state.content.resetComposer()

    let exitEffect = state.content.exitCollectionMode(computerName: computerName)
    var effects: [Effect<FileManagerWindowAction>] = [.send(.navigation(.rollbackBackHistoryOnce))]
    if state.sidebar.pendingSidebarSelectionRestore != nil {
        effects.append(.send(.sidebar(.restoreSidebarSelection)))
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

    let exitEffect = state.content.exitCollectionMode(computerName: computerName)
    return .concatenate(
        .send(.navigation(.rollbackBackHistoryOnce)),
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

private func applyCollectionNavigationState(
    _ navigation: ContentPageCollectionNavigation,
    state: inout FileManagerWindowState,
) {
    state.content.composer.isPresented = false
    state.content.collectionContext = navigation.context
    state.content.composer.pendingSearchQuery = navigation.context.query.isEmpty ? nil : navigation.context.query
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
}

private func configureCollectionNavigationComposer(
    _ navigation: ContentPageCollectionNavigation,
    state: inout FileManagerWindowState,
) {
    state.content.composer.text = {
        if case .file = navigation.kind { return "" }
        return navigation.context.query
    }()
    state.content.composer.scopes = navigation.context.scopes
    state.content.composer.conditions = navigation.context.conditions
    state.content.composer.propertyPicker = ConditionPropertyPickerFeature.State()
    state.content.composer.operatorPicker = OperatorPickerFeature.State()
    state.content.composer.valuePicker = ValuePickerFeature.State()
    state.content.composer.clearHistory()
}

private func handleNavigationDelegate(
    _ delegateAction: ContentPageNavigationDelegate,
    state: inout FileManagerWindowState,
    computerName: String,
) -> Effect<FileManagerWindowAction> {
    switch delegateAction {
    case let .applyContentPageNavigationHistorySnapshot(entry):
        applyContentPageNavigationHistorySnapshot(entry, state: &state)
        syncSidebarSelection(state: &state, computerName: computerName)
        return .send(.content(.entryArrangements(.reapply)))

    case let .navigateToState(navigationState):
        return handleNavigateToState(navigationState, state: &state)

    case let .logDAUNavigation(previous, next):
        logContentPageNavigationDAUIfNeeded(previous: previous, next: next)
        return .none

    case .resetComposer:
        let exitEffect = state.content.exitCollectionMode(computerName: computerName)
        state.content.resetComposer()
        return exitEffect.map(FileManagerWindowAction.content)
    }
}
