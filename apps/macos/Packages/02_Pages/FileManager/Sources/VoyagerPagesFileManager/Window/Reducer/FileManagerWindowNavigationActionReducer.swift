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
    typealias State = FileManagerWindowState
    typealias Action = FileManagerWindowAction

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
    @Dependency(\.uuid)
    var uuid

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
        guard state.pendingContentTabClose == nil || !isUserNavigationRequest(action) else {
            return .none
        }

        return switch action {
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
             .showTag,
             .showAiChat,
             .showAiChatSessions:
            .concatenate(
                cancelPendingCollectionOpen(state: &state),
                handleDirectNavigationAction(action, state: &state),
            )

        case .goBack,
             .goForward,
             .goToHistoryIndex,
             .goToEnclosingDirectory:
            .concatenate(
                cancelPendingCollectionOpen(state: &state),
                handleHistoryNavigationAction(action, state: &state),
            )

        case let .openCollectionFile(url):
            handleOpenCollectionFile(
                url: url,
                state: &state,
                collectionFileClient: collectionFileClient,
                metricsClient: metricsClient,
                uuid: uuid,
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
            handleCollectionNavigationAction(action, state: &state)

        case .showUnsavedNavigationAlert,
             .unsavedNavigationAlertResponse,
             .performNavigation:
            handleUnsavedNavigationAction(action, state: &state)

        case .performNavigateToPath,
             .performShowRecents,
             .performShowComputer,
             .performShowTag,
             .performShowAiChat,
             .performShowAiChatSessions,
             .prepareCollectionFileOpen,
             .rollbackBackHistoryOnce,
             .restoreHistory,
             .appendBackHistory,
             .clearForwardHistory,
             .setNavigationState,
             .applyPinnedPeerNavigationState,
             .setPendingNavigation:
            .none
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

        case let .showAiChat(sessionID):
            return .send(.navigation(.internal(.performShowAiChat(sessionID))))

        case let .showAiChatSessions(sessionID):
            return .send(.navigation(.internal(.performShowAiChatSessions(sessionID))))

        default:
            return .none
        }
    }

    private func handleCollectionNavigationAction(
        _ action: ContentPageNavigationAction.Internal,
        state: inout State,
    ) -> Effect<Action> {
        switch action {
        case let .collectionFileLoaded(request, result):
            handleCollectionFileLoaded(
                request: request,
                result: result,
                state: &state,
                environment: .init(
                    collectionAlertClient: collectionAlertClient,
                    registryClient: registryClient,
                    collectionStalenessClient: collectionStalenessClient,
                    metricsClient: metricsClient,
                ),
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
        state.isCollectionMode && state.hasUnsavedCollectionChanges
    }
}

struct OpenCollectionFileCancelID: Hashable {
    let windowID: UUID?
}

private func handleOpenCollectionFile(
    url: URL,
    state: inout FileManagerWindowState,
    collectionFileClient: CollectionFileClient,
    metricsClient: MetricsClient,
    uuid: UUIDGenerator,
) -> Effect<FileManagerWindowAction> {
    if let pendingRequest = state.pendingCollectionOpenRequest {
        guard pendingRequest.url.standardizedFileURL != url.standardizedFileURL else {
            return .none
        }
        state.pendingCollectionOpenRequest = nil
        return .concatenate(
            .cancel(id: OpenCollectionFileCancelID(
                windowID: state.content.entryViewLayout.entryOperations.windowID,
            )),
            restoreCollectionOpenHistoryEffect(pendingRequest),
            .send(.navigation(.view(.openCollectionFile(url)))),
        )
    }
    let request = ContentPageCollectionOpenRequest(
        id: uuid(),
        url: url,
        sourceRoute: state.content.navigation.navigationState,
        prePrepareBackHistory: state.content.navigation.backHistory,
        prePrepareForwardHistory: state.content.navigation.forwardHistory,
    )
    if state.content.collection.collectionSession.document?.url.path != request.url.path {
        metricsClient.logDAUNavigation(.collection)
    }
    state.pendingCollectionOpenRequest = request

    let cancelExistingCollectionEffect: Effect<FileManagerWindowAction> = if state.content.isCollectionMode {
        cancelExistingCollectionEffects(state: state)
    } else {
        .none
    }
    let loadEffect = collectionFileLoadEffect(
        request: request,
        collectionFileClient: collectionFileClient,
        windowID: state.content.entryViewLayout.entryOperations.windowID,
    )

    return .concatenate(
        .send(.content(.entryViewLayout(.internal(.setCollectionContentLoading(true))))),
        cancelExistingCollectionEffect,
        .send(.navigation(.internal(.prepareCollectionFileOpen(request.url)))),
        loadEffect,
    )
}

private func cancelExistingCollectionEffects(
    state: FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    var effects: [Effect<FileManagerWindowAction>] = [
        .cancel(id: OpenCollectionFileCancelID(
            windowID: state.content.entryViewLayout.entryOperations.windowID,
        )),
    ]
    let composer = state.content.composer
    if composer.isLoadingSearch
        || composer.activeSearchRequestID != nil
        || composer.queryRenderPhase != .idle
    {
        effects.append(.send(.content(.composer(.cancelSearch))))
    }
    if composer.isLoadingFilters
        || composer.isFilteringInFlight
        || composer.activeFiltersRequestID != nil
        || composer.pendingSearchQuery != nil
    {
        effects.append(.send(.content(.composer(.cancelFilters))))
    }
    return .concatenate(effects)
}

private func collectionFileLoadEffect(
    request: ContentPageCollectionOpenRequest,
    collectionFileClient: CollectionFileClient,
    windowID: UUID?,
) -> Effect<FileManagerWindowAction> {
    .run { send in
        do {
            let result = try await collectionFileClient.load(request.url)
            try Task.checkCancellation()
            await send(.navigation(.internal(.collectionFileLoaded(
                request: request,
                result: .success(result),
            ))))
        } catch is CancellationError {
            return
        } catch {
            let category = collectionOpenErrorCategory(error)
            await send(.navigation(.internal(.collectionFileLoaded(
                request: request,
                result: .failure(ContentPageNavigationErrorFingerprint(error: error, category: category)),
            ))))
        }
    }
    .cancellable(id: OpenCollectionFileCancelID(windowID: windowID), cancelInFlight: true)
}

private func handleCollectionFileLoaded(
    request: ContentPageCollectionOpenRequest,
    result: ContentPageCollectionFileLoadResult,
    state: inout FileManagerWindowState,
    environment: CollectionOpenEnvironment,
) -> Effect<FileManagerWindowAction> {
    guard state.pendingCollectionOpenRequest?.id == request.id,
          state.pendingCollectionOpenRequest?.url == request.url,
          state.content.navigation.navigationState == request.sourceRoute
    else { return .none }
    state.pendingCollectionOpenRequest = nil

    switch result {
    case let .success(loadResult):
        let file = loadResult.file
        let resolved = file.resolveCollectionFilters(registryClient: environment.registryClient)
        let isStale = prepareLoadedCollectionOpenStaleness(
            request: request,
            file: file,
            state: &state,
            environment: environment,
        )
        return handleCollectionFileLoadedSuccess(
            loadResult,
            isStale: isStale,
            resolved: resolved,
            state: &state,
            environment: environment,
        )
    case let .failure(error):
        return handleCollectionFileLoadedFailure(
            error,
            request: request,
            state: &state,
            collectionAlertClient: environment.collectionAlertClient,
            metricsClient: environment.metricsClient,
        )
    }
}

private func prepareLoadedCollectionOpenStaleness(
    request: ContentPageCollectionOpenRequest,
    file: VoyagerCollectionFile,
    state: inout FileManagerWindowState,
    environment: CollectionOpenEnvironment,
) -> Bool {
    let canonicalPath = request.url.standardizedFileURL.path
    let hasPersistedInvalidation = environment.collectionStalenessClient.record(canonicalPath)?
        .lastInvalidatedAt != nil
    let hasScopeRootChangedSinceSnapshot = collectionScopeRootsChangedSinceSnapshot(file)
    state.content.collection.prepareOpenTransition(
        at: request.url,
        reopenContext: state.content.collection.collectionContext,
        isAlreadyStale: hasPersistedInvalidation,
    )
    environment.collectionStalenessClient.registerCollection(
        canonicalPath,
        file.scopes,
        file.excludedScopes,
        file.includeSubfolders,
    )
    if hasScopeRootChangedSinceSnapshot {
        environment.collectionStalenessClient.upsertRecord(
            canonicalPath,
            .init(
                definitionFingerprint: file.snapshotMeta?.definitionFingerprint ?? "",
                relevanceRoots: file.snapshotMeta?.relevanceRoots ?? file.scopes,
                excludedScopes: file.excludedScopes,
                includeSubfolders: file.includeSubfolders,
                lastInvalidatedAt: Date(),
            ),
        )
    }
    return hasPersistedInvalidation || hasScopeRootChangedSinceSnapshot
}

private func handleNavigateToCollection(
    _ navigation: ContentPageCollectionNavigation,
    state: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    guard let activeTabID = state.contentTabs.activeTabID else { return .none }
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
    let queryAction: FileManagerContentAction = trimmedQuery.isEmpty
        ? .composer(.applyFilters)
        : .composer(.submit)
    return .concatenate(
        .send(.tabContent(tabID: activeTabID, action: .collection(.navigationStateApplied(payload)))),
        .send(.tabContent(tabID: activeTabID, action: .composer(.applyCollectionNavigationComposer(payload)))),
        .send(.tabContent(
            tabID: activeTabID,
            action: .entryViewLayout(.internal(.setCollectionMode(true))),
        )),
        .send(.tabContent(tabID: activeTabID, action: .composer(.syncCollectionState(
            context: payload.context,
            url: payload.document?.url,
            compatibility: payload.document?.compatibility,
            isCollectionMode: true,
        )))),
        .send(.tabContent(tabID: activeTabID, action: .entryViewLayout(.entryArrangements(.reapply)))),
        .send(.tabContent(tabID: activeTabID, action: queryAction)),
    )
}

private func handleCollectionFileLoadedSuccess(
    _ loadResult: CollectionFileLoadResult,
    isStale: Bool,
    resolved: AppliedFilterResolver.ResolutionResult,
    state: inout FileManagerWindowState,
    environment: CollectionOpenEnvironment,
) -> Effect<FileManagerWindowAction> {
    let openPayload = state.content.collection.makeOpenRestorationPayload(
        file: loadResult.file,
        resolved: resolved,
        isStale: isStale,
        compatibility: loadResult.compatibility,
    )

    let dismissComposerEffect: Effect<FileManagerWindowAction> = .send(.content(.composer(.setPresented(false))))

    prepareLoadedCollectionOpenState(
        restorationPayload: openPayload,
        registryClient: environment.registryClient,
        state: &state,
    )
    state.content.composer.isPresented = false

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
        effects.append(collectionOpenMetricEffect(
            metricsClient: environment.metricsClient,
            resultStatus: .validEmpty,
        ))
    }

    if effects.isEmpty {
        return dismissComposerEffect
    }
    return .concatenate([dismissComposerEffect] + effects)
}

private struct CollectionOpenEnvironment {
    let collectionAlertClient: CollectionAlertClient
    let registryClient: RegistryClient
    let collectionStalenessClient: CollectionStalenessClient
    let metricsClient: MetricsClient
}

nonisolated func collectionScopeRootsChangedSinceSnapshot(
    _ file: VoyagerCollectionFile,
    fileManager: FileManager = .default,
) -> Bool {
    guard let snapshotMeta = file.snapshotMeta else { return false }
    let relevanceRoots = snapshotMeta.relevanceRoots.isEmpty ? file.scopes : snapshotMeta.relevanceRoots
    return relevanceRoots.contains {
        collectionScopeRootModified(after: snapshotMeta.capturedAt, root: $0, fileManager: fileManager)
    }
}

nonisolated private func collectionScopeRootModified(
    after capturedAt: Date,
    root: String,
    fileManager: FileManager,
) -> Bool {
    guard !root.isEmpty, root.hasPrefix("/") else { return false }
    let url = URL(fileURLWithPath: root).standardizedFileURL
    guard fileManager.fileExists(atPath: url.path),
          let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
          let modifiedAt = values.contentModificationDate
    else { return false }
    return modifiedAt > capturedAt
}

private func handleCollectionFileLoadedFailure(
    _ error: ContentPageNavigationErrorFingerprint,
    request: ContentPageCollectionOpenRequest,
    state _: inout FileManagerWindowState,
    collectionAlertClient: CollectionAlertClient,
    metricsClient: MetricsClient,
) -> Effect<FileManagerWindowAction> {
    let metricEffect = collectionOpenMetricEffect(
        metricsClient: metricsClient,
        resultStatus: .loadFailure,
        errorCategory: error.category,
    )
    if case .collection = request.sourceRoute {
        return .concatenate(
            .send(.content(.entryViewLayout(.internal(.setCollectionContentLoading(false))))),
            restoreCollectionOpenHistoryEffect(request),
            .run { _ in
                await collectionAlertClient.showCollectionOpenErrorAlert(
                    "Unable to Open Collection",
                    error.message,
                )
            },
            metricEffect,
        )
    }

    var effects: [Effect<FileManagerWindowAction>] = [
        .send(.content(.entryViewLayout(.internal(.setCollectionContentLoading(false))))),
        restoreCollectionOpenHistoryEffect(request),
    ]
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
    effects.append(metricEffect)
    return .concatenate(effects)
}

private func collectionOpenErrorCategory(_ error: Error) -> ContentPageNavigationErrorCategory {
    if let compatibilityError = error as? CollectionFileCompatibilityError {
        return switch compatibilityError {
        case .unsupportedFutureSchemaVersion:
            .unsupportedSchema
        case .invalidDefinitionPayload:
            .invalidDefinition
        case .missingSchemaVersion,
             .invalidSchemaVersionType,
             .missingPackagePayload,
             .unrecoverableDocumentCorruption,
             .invalidPropertyListPayload:
            .malformed
        }
    }
    if let cocoaError = error as? CocoaError {
        return switch cocoaError.code {
        case .fileReadNoPermission,
             .fileReadNoSuchFile,
             .fileReadInvalidFileName,
             .fileReadCorruptFile,
             .fileReadUnknown:
            .access
        default:
            .unknown
        }
    }
    return .unknown
}

private func restoreCollectionOpenHistoryEffect(
    _ request: ContentPageCollectionOpenRequest,
) -> Effect<FileManagerWindowAction> {
    .send(.navigation(.internal(.restoreHistory(
        back: request.prePrepareBackHistory,
        forward: request.prePrepareForwardHistory,
    ))))
}

func cancelPendingCollectionOpen(
    state: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    guard let request = state.pendingCollectionOpenRequest else { return .none }
    state.pendingCollectionOpenRequest = nil
    let clearLoadingEffect: Effect<FileManagerWindowAction> = if let activeTabID = state.contentTabs.activeTabID {
        .send(.tabContent(
            tabID: activeTabID,
            action: .entryViewLayout(.internal(.setCollectionContentLoading(false))),
        ))
    } else {
        .none
    }
    return .concatenate(
        .cancel(id: OpenCollectionFileCancelID(
            windowID: state.content.entryViewLayout.entryOperations.windowID,
        )),
        clearLoadingEffect,
        restoreCollectionOpenHistoryEffect(request),
    )
}

private func isUserNavigationRequest(_ action: ContentPageNavigationAction) -> Bool {
    if case .view = action {
        return true
    }
    return false
}
