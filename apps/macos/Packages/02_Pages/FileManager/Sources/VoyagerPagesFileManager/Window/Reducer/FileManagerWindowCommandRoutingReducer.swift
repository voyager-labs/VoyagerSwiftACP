import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesAiChat
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import VoyagerShared

struct HomeAiChatOpenCancelID: Hashable {
    var tabID: ContentTabID
}

@Reducer
struct FileManagerWindowCommandRoutingReducer {
    typealias State = FileManagerWindowState
    typealias Action = FileManagerWindowAction

    nonisolated enum CancelID: Hashable {
        case loadFixedLocations
        case loadHomeFavorites
        case undoManagerEvents
    }

    @Dependency(\.aiConnectionsFileClient)
    var aiConnectionsFileClient
    @Dependency(\.aiChatDefaultSettingsClient)
    var aiChatDefaultSettingsClient
    @Dependency(\.searchClient)
    var searchClient
    @Dependency(\.collectionAlertClient)
    var collectionAlertClient
    @Dependency(\.fileManagerClient)
    var fileManagerClient
    @Dependency(\.fileManagerLocationsClient)
    var fileManagerLocationsClient
    @Dependency(\.fileManagerFavoritesClient)
    var fileManagerFavoritesClient
    @Dependency(\.fileManagerProductMetricsClient)
    var productMetricsClient
    @Dependency(\.entryLoadingClient)
    var entryLoadingClient
    @Dependency(\.userDefaultsClient)
    var userDefaultsClient
    @Dependency(\.uuid)
    var uuid
    @Dependency(\.undoManagerClient)
    var undoManagerClient
    @Dependency(\.workspaceClient)
    var workspaceClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.syncHomeFavoriteItems()
                guard state.fixedLocationsLoadPhase == .idle else { return .none }
                let storedHiddenLocationIDs = hiddenFixedLocationIDs()
                state.sidebar.hiddenFixedLocationItemIDs = storedHiddenLocationIDs
                if !state.sidebar.allFixedLocationItems.isEmpty {
                    state.applyFixedLocationItems(
                        state.sidebar.allFixedLocationItems,
                        hiddenLocationIDs: storedHiddenLocationIDs,
                    )
                }
                let requestID = uuid()
                state.fixedLocationsLoadPhase = .loading(requestID)
                let locationsClient = fileManagerLocationsClient
                let loadingClient = entryLoadingClient
                let favoritesClient = fileManagerFavoritesClient
                let defaultsClient = userDefaultsClient
                let workspaceClient = workspaceClient
                let fixedLocationsEffect: Effect<Action> = .run { send in
                    let items = FileManagerHomeDashboardProjection.makeFixedLocations(
                        from: locationsClient.loadLocations(loadingClient),
                    )
                    _ = await workspaceClient.prepareFileIcons(items.map(\.path))
                    guard !Task.isCancelled else { return }
                    await send(.internal(.fixedLocationsLoaded(
                        requestID: requestID,
                        items: items,
                    )))
                }
                .cancellable(id: CancelID.loadFixedLocations, cancelInFlight: true)
                let homeFavoritesEffect: Effect<Action> = .run { send in
                    let favorites = favoritesClient.loadFavorites(
                        loadingClient,
                        defaultsClient,
                    )
                    let items = FileManagerHomeDashboardProjection.homeFavorites(
                        from: favorites,
                        fileExistsWithIsDirectory: loadingClient.fileExistsAtPath,
                    )
                    await send(.internal(.homeFavoritesLoaded(items)))
                }
                .cancellable(id: CancelID.loadHomeFavorites, cancelInFlight: true)
                return .merge(fixedLocationsEffect, homeFavoritesEffect)

            case let .content(.entryViewLayout(.entryOperations(.lifecycle(.windowIDChanged(windowID))))):
                return .send(.internal(.undoManagerWindowIDChanged(windowID)))

            case let .internal(.undoManagerWindowIDChanged(windowID)):
                state.windowID = windowID
                state.undoRedoPhase = .idle
                return .merge(
                    .send(.internal(.sidebarEntryDrop(.lifecycle(.windowIDChanged(windowID))))),
                    undoManagerAvailabilityEffect(windowID: windowID),
                    undoManagerEventsEffect(windowID: windowID),
                )

            case let .internal(.undoManagerInvocationFinished(requestID, direction, result)):
                guard case let .invoking(currentRequestID, currentDirection) = state.undoRedoPhase,
                      currentRequestID == requestID,
                      currentDirection == direction
                else { return .none }
                state.undoManagerAvailability = result.availability
                state.undoRedoPhase = result.didInvoke
                    ? .replaying(requestID: requestID, direction: direction)
                    : .idle
                return .none

            case let .internal(.undoManagerAvailabilityChanged(availability)):
                guard state.undoRedoPhase == .idle else { return .none }
                state.undoManagerAvailability = availability
                return .none

            case let .internal(.undoManagerReplayAvailabilityChanged(requestID, availability)):
                guard case let .refreshing(currentRequestID) = state.undoRedoPhase,
                      currentRequestID == requestID
                else { return .none }
                state.undoRedoPhase = .idle
                state.undoManagerAvailability = availability
                return .none

            case .onDisappear:
                state.fixedLocationsLoadPhase = .idle
                return .merge(
                    .cancel(id: CancelID.loadFixedLocations),
                    .cancel(id: CancelID.loadHomeFavorites),
                    .cancel(id: CancelID.undoManagerEvents),
                )

            case let .internal(.homeFavoritesLoaded(items)):
                state.applyHomeFavoriteItems(items)
                return .none

            case let .internal(.aiChatTabTitleUpdated(sessionID, title)):
                state.updateAiChatTabTitle(sessionID: sessionID, title: title)
                return .none

            case let .applyHiddenFixedLocationIDs(hiddenIDs):
                state.sidebar.setFixedLocationItems(
                    state.sidebar.allFixedLocationItems,
                    hiddenIDs: hiddenIDs,
                )
                return .none

            case .request(.reopenChat):
                return handleAiChatReopenRequest(state: &state)

            case .view(.dismissContentTabSwitcher):
                state.contentTabSwitcherPresentation = nil
                return .none

            case let .view(.activateContentTabSwitcherCandidate(id)):
                return handleActivateContentTabSwitcherCandidate(id, state: &state)

            case let .request(command):
                return handleRequestedCommand(command, state: &state)

            case let .tabContent(tabID, .delegate(.openPathInNewWindow(path))):
                guard tabID == state.contentTabs.activeTabID else { return .none }
                return .send(.delegate(.openPathInNewWindow(path)))

            case let .tabContent(tabID, .delegate(.openInNewTab(paths))):
                return routeOpenInNewTab(tabID: tabID, paths: paths, activeTabID: state.contentTabs.activeTabID)

            case let .tabContent(tabID, .delegate(.currentContextChanged(snapshot))):
                guard tabID == state.contentTabs.activeTabID else { return .none }
                return .send(.inspector(.aiChat(.currentContextChanged(snapshot))))

            case let .tabContent(tabID, .delegate(.homePageAnchorSelected(anchor))):
                guard tabID == state.contentTabs.activeTabID,
                      state.contentTabs.tabs[id: tabID]?.anchor == .homeDefault
                else { return .none }
                return handleHomePageAnchorSelected(anchor, activeTabID: tabID, state: state)

            case let .tabContent(tabID, .delegate(.homeChatHistorySessionSelected(sessionID))):
                guard tabID == state.contentTabs.activeTabID,
                      state.contentTabs.tabs[id: tabID]?.anchor == .homeDefault
                else { return .none }
                return handleHomeChatHistorySessionSelected(sessionID, activeTabID: tabID, state: state)

            case let .sidebar(.delegate(.selectFixedLocation(id))):
                guard let activeTabID = state.contentTabs.activeTabID,
                      let location = state.sidebar.fixedLocationItems.first(where: { $0.id == id })
                else { return .none }
                let anchor = ContentTabPageAnchor.directory(path: location.path)
                return .concatenate(
                    updateContentTabPageAnchorEffect(
                        tabID: activeTabID,
                        anchor: anchor,
                        state: state,
                    ),
                    .send(.navigation(.view(.navigateToPath(location.path)))),
                )

            case let .sidebar(.delegate(.entryDropRequested(request))):
                if case let .fixedLocation(id) = request.target {
                    guard let location = state.sidebar.fixedLocationItems.first(where: { $0.id == id })
                    else { return .none }
                    if location.kind == .trash {
                        let metadata = EntryCommandMetadata(
                            id: productMetricsClient.makeOperationID(),
                            interaction: .moveEntriesToTrash,
                            source: .dragAndDrop,
                        )
                        return .send(.internal(.sidebarEntryDrop(.acceptedCommand(
                            metadata: metadata,
                            action: .routing(.handleDropToTrash(providers: request.providers)),
                        ))))
                    }
                }
                guard let destinationPath = sidebarEntryDropDestinationPath(
                    for: request.target,
                    state: state,
                ) else { return .none }
                let metadata = EntryCommandMetadata(
                    id: productMetricsClient.makeOperationID(),
                    interaction: request.isOptionDrag ? .copyEntries : .moveEntries,
                    source: .dragAndDrop,
                )
                return .send(.internal(.sidebarEntryDrop(.acceptedCommand(
                    metadata: metadata,
                    action: .routing(.handleDrop(
                        providers: request.providers,
                        destinationPath: destinationPath,
                        isOptionDrag: request.isOptionDrag,
                    )),
                ))))

            case let .sidebar(.view(.setFixedLocationVisibility(id, isVisible))):
                state.sidebar.setFixedLocationVisibility(id: id, isVisible: isVisible)
                state.syncHomeLocationItems()
                persistHiddenFixedLocationIDs(state.sidebar.hiddenFixedLocationItemIDs)
                return .send(.delegate(.fixedLocationVisibilityChanged(
                    state.sidebar.hiddenFixedLocationItemIDs,
                )))

            case let .sidebar(.view(.setAllFixedLocationVisibility(isVisible))):
                state.sidebar.setAllFixedLocationVisibility(isVisible)
                state.syncHomeLocationItems()
                persistHiddenFixedLocationIDs(state.sidebar.hiddenFixedLocationItemIDs)
                return .send(.delegate(.fixedLocationVisibilityChanged(
                    state.sidebar.hiddenFixedLocationItemIDs,
                )))

            case let .tabContent(tabID, .delegate(.aiChatSessionCreated(sessionID))):
                return routeAiChatTab(tabID, to: sessionID, state: state, title: "New Chat")

            case let .tabContent(tabID, .delegate(.aiChatSessionRestored(sessionID, title))):
                return routeAiChatTab(tabID, to: sessionID, state: state, title: title)

            case let .tabContent(tabID, .delegate(.newChatRequested)):
                guard tabID == state.contentTabs.activeTabID else { return .none }
                return .send(.request(.newChat))

            case let .tabContent(tabID, .delegate(.durableNewChatRequested)):
                guard tabID == state.contentTabs.activeTabID else { return .none }
                return beginContentAiChatNewChatSeedResolution(state: &state)

            case let .tabContent(tabID, .delegate(.showChatHistoryRequested)):
                guard tabID == state.contentTabs.activeTabID else { return .none }
                return .send(.request(.showChatHistory))

            case let .tabContent(tabID, .delegate(.openAISettings)):
                guard tabID == state.contentTabs.activeTabID else { return .none }
                return .send(.delegate(.openAISettings))

            case let .content(.delegate(.requestUndoRedo(direction))):
                return .send(.request(direction == .undo ? .requestUndo : .requestRedo))

            case .inspector(.closeChat):
                state.pendingAiChatInspectorOpen = nil
                return .merge(
                    .cancel(id: FileManagerAiChatInspectorOpenCancelID()),
                    cancelAiChatNewChatSeedResolution(state: &state),
                )

            case .inspector(.openNewChat):
                return .none

            case .inspector(.delegate(.newChatRequested)):
                return .send(.request(.newChat))

            case .inspector(.delegate(.openAISettings)):
                return .send(.delegate(.openAISettings))

            case let .inspector(.delegate(.requestAttachmentPicker(originSessionID))):
                return .send(.delegate(.requestAttachmentPicker(originSessionID)))

            case .inspector(.delegate(.clearCurrentContextSelection)):
                guard let activeTabID = state.contentTabs.activeTabID else { return .none }
                return .send(.tabContent(
                    tabID: activeTabID,
                    action: .entryViewLayout(.internal(.applyClearSelection)),
                ))

            case let .aiConnectionsFileUpdated(file):
                return .merge(
                    forwardProviderConnectionsToOpenAiChat(file: file, state: &state),
                    warmUpAIModelCatalogEffect(),
                )

            case let .internal(.fixedLocationsLoaded(requestID, items)):
                guard state.fixedLocationsLoadPhase == .loading(requestID) else { return .none }
                state.fixedLocationsLoadPhase = .loaded
                state.applyFixedLocationItems(items, hiddenLocationIDs: state.sidebar.hiddenFixedLocationItemIDs)
                return .none

            case let .internal(.aiChatNewChatInspectorOpenLoaded(requestID, setup, connectionsFile)):
                return handleAiChatInspectorOpenCompletion(
                    requestID: requestID,
                    destination: .newChat,
                    setup: setup,
                    connectionsFile: connectionsFile,
                    state: &state,
                )

            case let .internal(.aiChatHistoryInspectorOpenLoaded(requestID, setup, connectionsFile)):
                return handleAiChatInspectorOpenCompletion(
                    requestID: requestID,
                    destination: .chatHistory,
                    setup: setup,
                    connectionsFile: connectionsFile,
                    state: &state,
                )

            case let .internal(.aiChatReopenInspectorOpenLoaded(requestID, setup, connectionsFile)):
                return handleAiChatInspectorOpenCompletion(
                    requestID: requestID,
                    destination: .reopenChat,
                    setup: setup,
                    connectionsFile: connectionsFile,
                    state: &state,
                )

            case let .internal(.aiChatNewChatDefaultsLoaded(requestID, candidate)):
                return handleAiChatNewChatDefaultsLoaded(
                    requestID: requestID,
                    candidate: candidate,
                    state: &state,
                )

            case let .internal(.homeAiChatNewChatSeedRequested(sessionID)):
                return beginHomeContentAiChatNewChatSeedResolution(
                    sessionID: sessionID,
                    state: &state,
                )

            case let .internal(.applyContentNewChatSeed(application)):
                return applyContentNewChatSeed(application, state: &state)

            case let .internal(.applyInspectorNewChatSeed(application)):
                return applyInspectorNewChatSeed(application, state: &state)

            case let .internal(.defaultStartPageResolved(startPage)):
                let anchor: ContentTabPageAnchor = switch startPage {
                case .home:
                    .homeDefault
                case let .directory(path):
                    .directory(path: path)
                }
                return .send(.contentTabs(.open(anchor)))

            case .inspector(.aiChat(.providerConnectionsUpdated)):
                if state.pendingAiChatInspectorOpen?.destination == .newChat {
                    if case let .known(providers) = state.inspector.aiChat.providerConnectionSnapshot,
                       !providers.isEmpty
                    {
                        return .none
                    }
                    return beginAiChatNewChatAfterInspectorOpen(
                        state: &state,
                        requiresCatalogRefresh: false,
                    )
                }
                return handleAiChatNewChatCatalogRefresh(
                    targetKind: .inspector,
                    state: &state,
                )

            case let .tabContent(tabID, .aiChat(.providerConnectionsUpdated)):
                guard tabID == state.contentTabs.activeTabID else { return .none }
                return handleAiChatNewChatCatalogRefresh(targetKind: .content, state: &state)

            case let .inspector(.aiChat(.modelListLoaded(requestID, _, _))),
                 let .inspector(.aiChat(.modelListLoadFailed(requestID, _, _))):
                if state.pendingAiChatInspectorOpen?.destination == .newChat,
                   state.pendingAiChatNewChat == nil
                {
                    return beginAiChatNewChatAfterInspectorOpen(
                        state: &state,
                        requiresCatalogRefresh: false,
                    )
                }
                return handleAiChatNewChatCatalogRefresh(
                    targetKind: .inspector,
                    state: &state,
                    requestID: requestID,
                )

            case let .tabContent(tabID, .aiChat(.modelListLoaded(requestID, _, _))),
                 let .tabContent(tabID, .aiChat(.modelListLoadFailed(requestID, _, _))):
                guard tabID == state.contentTabs.activeTabID else { return .none }
                return handleAiChatNewChatCatalogRefresh(
                    targetKind: .content,
                    state: &state,
                    requestID: requestID,
                )

            default:
                return .none
            }
        }
    }
}

private func routeOpenInNewTab(
    tabID: ContentTabID,
    paths: [String],
    activeTabID: ContentTabID?,
) -> Effect<FileManagerWindowAction> {
    guard tabID == activeTabID, !paths.isEmpty else { return .none }
    let openEffects = paths.map { path -> Effect<FileManagerWindowAction> in
        .send(.contentTabs(.open(.directory(path: path))))
    }
    return .concatenate(openEffects)
}
