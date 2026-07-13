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
import VoyagerShared

struct HomeAiChatOpenCancelID: Hashable {
    var tabID: ContentTabID
}

@Reducer
struct FileManagerWindowCommandRoutingReducer {
    nonisolated private enum CancelID: Hashable {
        case contextualAiChatOpen
        case loadFixedLocations
        case loadHomeFavorites
    }

    typealias State = FileManagerWindowState
    typealias Action = FileManagerWindowAction

    @Dependency(\.aiConnectionsFileClient)
    private var aiConnectionsFileClient
    @Dependency(\.searchClient)
    private var searchClient
    @Dependency(\.collectionAlertClient)
    private var collectionAlertClient
    @Dependency(\.fileManagerClient)
    private var fileManagerClient
    @Dependency(\.fileManagerLocationsClient)
    private var fileManagerLocationsClient
    @Dependency(\.fileManagerFavoritesClient)
    private var fileManagerFavoritesClient
    @Dependency(\.entryLoadingClient)
    private var entryLoadingClient
    @Dependency(\.userDefaultsClient)
    private var userDefaultsClient
    @Dependency(\.uuid)
    private var uuid

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
                let fixedLocationsEffect: Effect<Action> = .run { send in
                    let items = FileManagerHomeDashboardProjection.makeFixedLocations(
                        from: locationsClient.loadLocations(loadingClient),
                    )
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

            case .onDisappear:
                state.fixedLocationsLoadPhase = .idle
                return .merge(
                    .cancel(id: CancelID.loadFixedLocations),
                    .cancel(id: CancelID.loadHomeFavorites),
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

            case let .request(command):
                return handleRequestedCommand(command, state: &state)

            case let .content(.delegate(.openPathInNewWindow(path))):
                return .send(.delegate(.openPathInNewWindow(path)))

            case let .content(.delegate(.currentContextChanged(snapshot))):
                return .send(.inspector(.aiChat(.currentContextChanged(snapshot))))

            case let .content(.delegate(.homePageAnchorSelected(anchor))):
                guard let activeTabID = state.contentTabs.activeTabID,
                      state.contentTabs.tabs[id: activeTabID]?.anchor == .homeDefault
                else { return .none }
                return handleHomePageAnchorSelected(anchor, activeTabID: activeTabID)

            case let .content(.delegate(.homeChatHistorySessionSelected(sessionID))):
                guard let activeTabID = state.contentTabs.activeTabID,
                      state.contentTabs.tabs[id: activeTabID]?.anchor == .homeDefault
                else { return .none }
                return handleHomeChatHistorySessionSelected(sessionID, activeTabID: activeTabID)

            case let .sidebar(.delegate(.selectFixedLocation(id))):
                guard let activeTabID = state.contentTabs.activeTabID,
                      let location = state.sidebar.fixedLocationItems.first(where: { $0.id == id })
                else { return .none }
                let anchor = ContentTabPageAnchor.directory(path: location.path)
                return .concatenate(
                    .send(.contentTabs(.updateActivePageAnchor(activeTabID, anchor))),
                    .send(.navigation(.view(.navigateToPath(location.path)))),
                )

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

            case let .content(.delegate(.aiChatSessionCreated(sessionID))):
                return routeActiveAiChatTab(to: sessionID, title: "New Chat", state: state)

            case let .content(.delegate(.aiChatSessionRestored(sessionID, title))):
                return routeActiveAiChatTab(to: sessionID, title: title, state: state)

            case .content(.delegate(.openContextualAiChat)):
                return .send(.request(.openContextualAiChat))

            case .content(.delegate(.openAISettings)):
                return .send(.delegate(.openAISettings))

            case .inspector(.closeChat):
                return .cancel(id: CancelID.contextualAiChatOpen)

            case .inspector(.delegate(.openAISettings)):
                return .send(.delegate(.openAISettings))

            case .inspector(.delegate(.requestAttachmentPicker)):
                return .send(.delegate(.requestAttachmentPicker))

            case .inspector(.delegate(.clearCurrentContextSelection)):
                return .send(.content(.entryViewLayout(.internal(.applyClearSelection))))

            case let .aiConnectionsFileUpdated(file):
                return .merge(
                    forwardProviderConnectionsToOpenAiChat(file: file, state: state),
                    warmUpAIModelCatalogEffect(),
                )

            case let .internal(.fixedLocationsLoaded(requestID, items)):
                guard state.fixedLocationsLoadPhase == .loading(requestID) else { return .none }
                state.fixedLocationsLoadPhase = .loaded
                state.applyFixedLocationItems(items, hiddenLocationIDs: state.sidebar.hiddenFixedLocationItemIDs)
                return .none

            default:
                return .none
            }
        }
    }

    private func hiddenFixedLocationIDs() -> Set<FileManagerFixedLocationItem.ID> {
        guard let storedIDs = userDefaultsClient.object(SettingsKeys.hiddenFixedLocationIDs) as? [String] else {
            return []
        }
        return Set(storedIDs)
    }

    private func persistHiddenFixedLocationIDs(_ ids: Set<FileManagerFixedLocationItem.ID>) {
        userDefaultsClient.setObject(Array(ids).sorted(), SettingsKeys.hiddenFixedLocationIDs)
    }

    private func routeActiveAiChatTab(
        to sessionID: AiChatSessionID,
        title: String? = nil,
        state: State,
    ) -> Effect<Action> {
        guard let activeTabID = state.contentTabs.activeTabID,
              case .aiChat = state.contentTabs.tabs[id: activeTabID]?.anchor
        else { return .none }
        let sessionIDString = sessionID.rawValue.uuidString
        let routingEffect: Effect<Action> = .merge(
            .send(.navigation(.view(.showAiChat(sessionIDString)))),
            .send(.contentTabs(.updateActivePageAnchor(activeTabID, .aiChat(sessionID: sessionIDString)))),
        )
        guard let title else { return routingEffect }
        return .concatenate(
            routingEffect,
            .send(.internal(.aiChatTabTitleUpdated(sessionID: sessionID, title: title))),
        )
    }

    private func handleHomeChatHistorySessionSelected(
        _ sessionID: AiChatSessionID,
        activeTabID: ContentTabID,
    ) -> Effect<Action> {
        let sessionString = sessionID.rawValue.uuidString
        let anchor = ContentTabPageAnchor.aiChat(sessionID: sessionString)
        let setup = AiChatSetupState(
            restoreSessionID: sessionID,
            sessionID: nil,
            mode: .chat,
        )
        let providerLoadEffect: Effect<Action> = .run { [aiConnectionsFileClient] send in
            let connectionsFile: AIConnectionsFile
            do {
                connectionsFile = try await aiConnectionsFileClient.load()
            } catch {
                connectionsFile = .empty()
            }
            await send(.content(.aiChat(.providerConnectionsUpdated(connectionsFile))))
        }
        .cancellable(id: HomeAiChatOpenCancelID(tabID: activeTabID), cancelInFlight: true)

        return .concatenate(
            .send(.inspector(.closeChat)),
            .send(.contentTabs(.updateActivePageAnchor(activeTabID, anchor))),
            .send(.navigation(.view(.showAiChat(sessionString)))),
            .send(.content(.aiChat(.setup(setup)))),
            providerLoadEffect,
        )
    }

    private func handleHomePageAnchorSelected(
        _ anchor: ContentTabPageAnchor,
        activeTabID: ContentTabID,
    ) -> Effect<Action> {
        switch anchor {
        case let .directory(path):
            return .concatenate(
                .send(.contentTabs(.updateActivePageAnchor(activeTabID, anchor))),
                .send(.navigation(.view(.navigateToPath(path)))),
            )

        case let .collectionFile(url):
            return .send(.navigation(.view(.openCollectionFile(url))))

        case .homeDefault,
             .virtualCollection:
            return .send(.contentTabs(.updateActivePageAnchor(activeTabID, anchor)))

        case let .aiChat(sessionID):
            let sessionUUID = AiChatSessionID(rawValue: UUID(uuidString: sessionID) ?? UUID())
            let setup = AiChatSetupState(
                restoreSessionID: sessionUUID,
                sessionID: sessionUUID,
                mode: .chat,
            )
            let providerLoadEffect: Effect<Action> = .run { [aiConnectionsFileClient] send in
                let connectionsFile: AIConnectionsFile
                do {
                    connectionsFile = try await aiConnectionsFileClient.load()
                } catch {
                    connectionsFile = .empty()
                }
                await send(.content(.aiChat(.providerConnectionsUpdated(connectionsFile))))
            }
            .cancellable(id: HomeAiChatOpenCancelID(tabID: activeTabID), cancelInFlight: true)

            return .concatenate(
                .send(.inspector(.closeChat)),
                .send(.contentTabs(.updateActivePageAnchor(activeTabID, anchor))),
                .send(.internal(.aiChatTabTitleUpdated(sessionID: sessionUUID, title: "New Chat"))),
                .send(.navigation(.view(.showAiChat(sessionID)))),
                .send(.content(.aiChat(.setup(setup)))),
                providerLoadEffect,
            )
        }
    }

    private func handleRequestedCommand(_ command: Action.WindowCommand, state: inout State) -> Effect<Action> {
        switch command {
        case .openNewContentTab:
            return Effect<Action>.send(.contentTabs(.open(.homeDefault)))

        case .closeActiveContentTab:
            return state.contentTabs.activeTabID
                .map { Effect<Action>.send(.closeContentTabRequested($0)) }
                ?? Effect<Action>.none

        case .toggleActiveContentTabPin:
            return toggleActiveContentTabPin(state: state)

        case .restoreLastClosedContentTab:
            return handleRestoreLastClosedContentTab(state: &state)

        case let .duplicateContentTab(sourceID):
            return handleDuplicateContentTabRequested(sourceID: sourceID, state: &state)

        case .duplicateActiveContentTab:
            guard let activeTabID = state.contentTabs.activeTabID else { return .none }
            return handleDuplicateContentTabRequested(sourceID: activeTabID, state: &state)

        case .newFolder,
             .openSelectedItem,
             .quickLookSelectedItem,
             .toggleShowHiddenFiles,
             .cut,
             .copy,
             .paste,
             .duplicate,
             .makeAlias,
             .selectAll,
             .copyAbsolutePaths,
             .copyURLs:
            return handleEntryRequest(command, state: &state)

        case .saveCollection,
             .saveCollectionAs,
             .toggleComposer,
             .openContextualAiChat,
             .presentContextualAiChat:
            return handleComposerRequest(command, state: &state)

        case .goBack,
             .goForward,
             .goToEnclosingDirectory:
            if state.pendingContentTabClose != nil {
                return Effect<Action>.none
            } else {
                return handleNavigationRequest(command)
            }

        case .toggleSidebar,
             .setViewLayout,
             .setGroupKey,
             .setSortKey,
             .setSortOrder:
            return handleLayoutRequest(command, state: &state)

        case .requestUndo,
             .requestRedo:
            return handleUndoRedoRequest(command)
        }
    }

    private func toggleActiveContentTabPin(state: State) -> Effect<Action> {
        guard state.pendingContentTabClose == nil,
              let activeTabID = state.contentTabs.activeTabID,
              let activeTab = state.contentTabs.tabs[id: activeTabID]
        else { return .none }

        if activeTab.isPinned {
            return .send(.contentTabs(.unpin(activeTabID)))
        }

        guard state.canPinContentTab(activeTabID) else {
            return cannotPinCollectionFeedbackEffect()
        }

        return .send(.contentTabs(.pin(activeTabID)))
    }

    private func cannotPinCollectionFeedbackEffect() -> Effect<Action> {
        let collectionAlertClient = collectionAlertClient
        return .run { _ in
            await collectionAlertClient.showCollectionOpenErrorAlert(
                "Cannot Pin Collection",
                "Save the collection before pinning it as a tab.",
            )
        }
    }

    private func handleEntryRequest(_ command: Action.WindowCommand, state: inout State) -> Effect<Action> {
        if let effect = handleEntryRequestPathDependent(command, state: state) {
            return effect
        }

        if let effect = handleEntryRequestSelection(command, state: state) {
            return effect
        }

        if let effect = handleEntryRequestEditing(command) {
            return effect
        }

        if let effect = handleEntryRequestCopying(command) {
            return effect
        }

        if let effect = handleEntryRequestViewOptions(command) {
            return effect
        }

        return .none
    }

    private func handleEntryRequestPathDependent(
        _ command: Action.WindowCommand,
        state: State,
    ) -> Effect<Action>? {
        guard case let .folder(currentPath) = state.content.navigation.navigationState else { return nil }

        switch command {
        case .newFolder:
            return .send(.content(.entryViewLayout(.entryOperations(
                .edit(.createNewFolder(
                    parentPath: currentPath,
                    siblingNames: state.content.entryViewLayout.entries.map(\.name),
                )),
            ))))

        case .paste:
            return .send(.content(.entryViewLayout(.delegate(.executeCommand(.clipboard(
                .pasteItems(destinationPath: currentPath),
            ))))))

        default:
            return nil
        }
    }

    private func handleEntryRequestSelection(_ command: Action.WindowCommand, state: State) -> Effect<Action>? {
        switch command {
        case .openSelectedItem:
            guard !state.content.entryViewLayout.selectedIds.isEmpty else { return .none }
            return .send(.content(.entryViewLayout(.delegate(.executeCommand(.navigation(.openSelectedItem))))))

        case .quickLookSelectedItem:
            guard !state.content.entryViewLayout.selectedIds.isEmpty else { return .none }
            return .send(.content(.entryViewLayout(.delegate(.executeCommand(.navigation(.quickLookSelectedItem))))))

        case .selectAll:
            return .send(.content(.view(.selectAllEntries)))

        default:
            return nil
        }
    }

    private func handleEntryRequestEditing(_ command: Action.WindowCommand) -> Effect<Action>? {
        switch command {
        case .cut:
            .send(.content(.entryViewLayout(.delegate(.executeCommand(.clipboard(.cutSelectedItems))))))

        case .copy:
            .send(.content(.entryViewLayout(.delegate(.executeCommand(.clipboard(.copySelectedItems))))))

        case .duplicate:
            .send(.content(.entryViewLayout(.delegate(.executeCommand(.clipboard(.duplicateSelectedItems))))))

        case .makeAlias:
            .send(.content(.entryViewLayout(.delegate(.executeCommand(.mutation(
                .createAliasForSelectedItems,
            ))))))

        default:
            nil
        }
    }

    private func handleEntryRequestCopying(_ command: Action.WindowCommand) -> Effect<Action>? {
        switch command {
        case .copyAbsolutePaths:
            .send(.content(.entryViewLayout(.delegate(.executeCommand(.clipboard(
                .copySelectedAbsolutePaths,
            ))))))

        case .copyURLs:
            .send(.content(.entryViewLayout(.delegate(.executeCommand(.clipboard(.copySelectedURLs))))))

        default:
            nil
        }
    }

    private func handleEntryRequestViewOptions(_ command: Action.WindowCommand) -> Effect<Action>? {
        switch command {
        case .toggleShowHiddenFiles:
            .send(.content(.view(.toggleShowHiddenFilesAndReload)))

        default:
            nil
        }
    }

    private func handleComposerRequest(_ command: Action.WindowCommand, state: inout State) -> Effect<Action> {
        switch command {
        case .saveCollection:
            return .send(.content(.composer(.saveCollection)))

        case .saveCollectionAs:
            return .send(.content(.composer(.saveCollectionAs)))

        case .toggleComposer:
            return .send(.content(.composer(.setPresented(!state.content.composer.isPresented))))

        case .openContextualAiChat:
            if state.inspector.inspectorVisible,
               state.inspector.inspectorPaneExists,
               state.inspector.activeMode == .chat
            {
                return .merge(
                    .send(.inspector(.closeChat)),
                    .cancel(id: CancelID.contextualAiChatOpen),
                )
            }
            return openContextualAiChatEffect(state: state)

        case .presentContextualAiChat:
            return openContextualAiChatEffect(state: state)

        default:
            return .none
        }
    }

    private func warmUpAIModelCatalogEffect() -> Effect<Action> {
        .run { [searchClient] _ in
            try? await searchClient.warmUpAIModelCatalog()
        }
    }

    private func forwardProviderConnectionsToOpenAiChat(
        file: AIConnectionsFile,
        state: State,
    ) -> Effect<Action> {
        var effects: [Effect<Action>] = []

        // ContentPane AI Chat forwarding: active tab이 .aiChat일 때 전송
        if let activeTabID = state.contentTabs.activeTabID,
           case .aiChat = state.contentTabs.tabs[id: activeTabID]?.anchor
        {
            effects.append(.send(.content(.aiChat(.providerConnectionsUpdated(file)))))
        }

        // Inspector AI Chat forwarding (기존 동작 유지)
        if state.inspector.inspectorVisible,
           state.inspector.inspectorPaneExists,
           state.inspector.activeMode == .chat
        {
            effects.append(.send(.inspector(.aiChat(.providerConnectionsUpdated(file)))))
        }

        return .merge(effects)
    }

    private func openContextualAiChatEffect(state: State) -> Effect<Action> {
        guard let activeTabID = state.contentTabs.activeTabID,
              state.supportsInspector(tabID: activeTabID)
        else { return .none }

        let content = state.content
        // Entry opens the inspector with seeded context only so AiChat starts on Sessions.
        // Session creation/restoration stays inside AiChat via New Chat or explicit restoreSessionID.
        let setup = FileManagerAiChatContextAdapter.makeAiChatSetupState(content: content)
        return .run { [aiConnectionsFileClient, setup] send in
            let connectionsFile: AIConnectionsFile
            do {
                connectionsFile = try await aiConnectionsFileClient.load()
            } catch {
                connectionsFile = .empty()
            }
            await send(.inspector(.openChat(setup, connectionsFile)))
        }
        .cancellable(id: CancelID.contextualAiChatOpen, cancelInFlight: true)
    }

    private func handleNavigationRequest(_ command: Action.WindowCommand) -> Effect<Action> {
        switch command {
        case .goBack:
            .send(.navigation(.view(.goBack)))

        case .goForward:
            .send(.navigation(.view(.goForward)))

        case .goToEnclosingDirectory:
            .send(.navigation(.view(.goToEnclosingDirectory)))

        default:
            .none
        }
    }

    private func handleLayoutRequest(_ command: Action.WindowCommand, state: inout State) -> Effect<Action> {
        switch command {
        case .toggleSidebar:
            .send(.sidebar(.view(.setSidebarVisible(!state.sidebar.sidebarVisible))))

        case let .setViewLayout(layout):
            .send(.content(.view(.changeLayout(layout))))

        case let .setGroupKey(key):
            .send(.content(.entryViewLayout(.entryArrangements(.setGroupKey(key)))))

        case let .setSortKey(key):
            .send(.content(.entryViewLayout(.entryArrangements(.setSortKey(key)))))

        case let .setSortOrder(order):
            .send(.content(.entryViewLayout(.entryArrangements(.setSortOrder(order)))))

        default:
            .none
        }
    }

    private func handleUndoRedoRequest(_ command: Action.WindowCommand) -> Effect<Action> {
        switch command {
        case .requestUndo:
            .send(.content(.entryViewLayout(.entryOperations(.undoRedo(.requestUndo)))))

        case .requestRedo:
            .send(.content(.entryViewLayout(.entryOperations(.undoRedo(.requestRedo)))))

        default:
            .none
        }
    }

    // MARK: - Restore Last Closed Content Tab

    private enum RestoreFailureReason {
        case missingDirectory
        case missingCollection
        case unsupportedAIChat
    }

    private func handleRestoreLastClosedContentTab(state: inout State) -> Effect<Action> {
        guard state.pendingContentTabClose == nil else { return .none }

        guard let snapshot = state.contentTabs.recentlyClosed else { return .none }

        guard state.contentTabs.tabs.count < ContentTabConstants.maxTabs else { return .none }

        if let reason = restoreFailureReason(for: snapshot, state: state) {
            state.contentTabs.recentlyClosed = nil
            return restoreFailureFeedbackEffect(reason)
        }

        return .send(.contentTabs(.restore))
    }

    private func restoreFailureReason(
        for snapshot: ClosedContentTabSnapshot,
        state _: State,
    ) -> RestoreFailureReason? {
        switch snapshot.anchor {
        case .homeDefault:
            return nil

        case let .directory(path):
            var isDirectory = ObjCBool(false)
            guard fileManagerClient.fileExistsWithIsDirectory(path, &isDirectory),
                  isDirectory.boolValue
            else { return .missingDirectory }
            return nil

        case let .collectionFile(url):
            guard fileManagerClient.fileExistsWithIsDirectory(url.path, nil)
            else { return .missingCollection }
            return nil

        case .virtualCollection:
            return nil

        case .aiChat:
            return .unsupportedAIChat
        }
    }

    private func restoreFailureFeedbackEffect(_ reason: RestoreFailureReason) -> Effect<Action> {
        let collectionAlertClient = collectionAlertClient
        let message = switch reason {
        case .missingDirectory, .missingCollection:
            "The recently closed tab is no longer available."
        case .unsupportedAIChat:
            "AI Chat tabs cannot be restored yet."
        }
        return .run { _ in
            await collectionAlertClient.showCollectionOpenErrorAlert(
                "Cannot Restore Tab",
                message,
            )
        }
    }

    // MARK: - Duplicate Content Tab

    private enum DuplicateFailureReason {
        case missingDirectory
        case missingCollectionFile
        case invalidAiChatSession
        case temporaryCollection
    }

    private func handleDuplicateContentTabRequested(
        sourceID: ContentTabID,
        state: inout State,
    ) -> Effect<Action> {
        guard state.pendingContentTabClose == nil else { return .none }
        guard let source = state.contentTabs.tabs[id: sourceID] else { return .none }
        guard state.contentTabs.tabs.count < ContentTabConstants.maxTabs else { return .none }

        // source Content state 결정: active면 state.content, inactive면 tabContentStates[sourceID]
        let isActiveSource = sourceID == state.contentTabs.activeTabID
        let sourceContentState: FileManagerContentFeature.State? = isActiveSource
            ? state.content
            : state.tabContentStates[sourceID]

        // anchor 기반 검증
        if let failureReason = duplicateFailureReason(
            for: source.anchor,
            contentState: sourceContentState,
        ) {
            return duplicateFailureFeedbackEffect(failureReason)
        }

        // cached Content state가 있을 때만 temporary/unsaved Collection mode mismatch 거부
        if let contentState = sourceContentState {
            if contentState.isCollectionMode, !contentState.canSaveCollection {
                return .none
            }
        }

        let duplicateID = ContentTabID()
        return .send(.contentTabs(.duplicate(sourceID: sourceID, duplicateID: duplicateID)))
    }

    private func duplicateFailureReason(
        for anchor: ContentTabPageAnchor,
        contentState _: FileManagerContentFeature.State?,
    ) -> DuplicateFailureReason? {
        switch anchor {
        case .homeDefault, .virtualCollection:
            return nil

        case let .directory(path):
            var isDirectory = ObjCBool(false)
            guard fileManagerClient.fileExistsWithIsDirectory(path, &isDirectory),
                  isDirectory.boolValue
            else { return .missingDirectory }
            return nil

        case let .collectionFile(url):
            guard fileManagerClient.fileExistsWithIsDirectory(url.path, nil)
            else { return .missingCollectionFile }
            return nil

        case let .aiChat(sessionID):
            guard UUID(uuidString: sessionID) != nil
            else { return .invalidAiChatSession }
            return nil
        }
    }

    private func duplicateFailureFeedbackEffect(_ reason: DuplicateFailureReason) -> Effect<Action> {
        let collectionAlertClient = collectionAlertClient
        let message = switch reason {
        case .missingDirectory:
            "The directory no longer exists."
        case .missingCollectionFile:
            "The collection file no longer exists."
        case .invalidAiChatSession:
            "The AI Chat session is no longer valid."
        case .temporaryCollection:
            "Cannot duplicate a temporary collection. Save the collection first."
        }
        return .run { _ in
            await collectionAlertClient.showCollectionOpenErrorAlert(
                "Cannot Duplicate Tab",
                message,
            )
        }
    }
}
