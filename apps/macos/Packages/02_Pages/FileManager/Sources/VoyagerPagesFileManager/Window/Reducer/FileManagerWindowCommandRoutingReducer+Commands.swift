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

extension FileManagerWindowCommandRoutingReducer {
    func sidebarEntryDropDestinationPath(
        for target: FileManagerSidebarEntryDropTarget,
        state: State,
    ) -> String? {
        switch target {
        case let .fixedLocation(id):
            return state.sidebar.fixedLocationItems.first(where: { $0.id == id })?.path

        case let .contentTab(id):
            guard let tab = state.contentTabs.tabs[id: id], tab.page == .directory else { return nil }

            if id == state.contentTabs.activeTabID {
                guard case let .folder(path) = state.content.navigation.navigationState else { return nil }
                return path
            }

            if let contentState = state.tabContentStates[id] {
                guard case let .folder(path) = contentState.navigation.navigationState else { return nil }
                return path
            }

            guard case let .directory(path) = tab.anchor else { return nil }
            return path
        }
    }

    func hiddenFixedLocationIDs() -> Set<FileManagerFixedLocationItem.ID> {
        guard let storedIDs = userDefaultsClient.object(SettingsKeys.hiddenFixedLocationIDs) as? [String] else {
            return []
        }
        return Set(storedIDs)
    }

    func persistHiddenFixedLocationIDs(_ ids: Set<FileManagerFixedLocationItem.ID>) {
        userDefaultsClient.setObject(Array(ids).sorted(), SettingsKeys.hiddenFixedLocationIDs)
    }

    func routeAiChatTab(
        _ tabID: ContentTabID,
        to sessionID: AiChatSessionID,
        state: State,
        title: String? = nil,
    ) -> Effect<Action> {
        guard case .aiChat = state.contentTabs.tabs[id: tabID]?.anchor else { return .none }
        let sessionIDString = sessionID.rawValue.uuidString
        let updateAnchorEffect = updateContentTabPageAnchorEffect(
            tabID: tabID,
            anchor: .aiChat(sessionID: sessionIDString),
            state: state,
        )
        let routingEffect: Effect<Action> = if tabID == state.contentTabs.activeTabID {
            .merge(
                .send(.navigation(.view(.showAiChat(sessionIDString)))),
                updateAnchorEffect,
            )
        } else {
            updateAnchorEffect
        }
        guard let title else { return routingEffect }
        return .concatenate(
            routingEffect,
            .send(.internal(.aiChatTabTitleUpdated(sessionID: sessionID, title: title))),
        )
    }

    func handleHomeChatHistorySessionSelected(
        _ sessionID: AiChatSessionID,
        activeTabID: ContentTabID,
        state: State,
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
            await send(.tabContent(
                tabID: activeTabID,
                action: .aiChat(.providerConnectionsUpdated(connectionsFile)),
            ))
        }
        .cancellable(id: HomeAiChatOpenCancelID(tabID: activeTabID), cancelInFlight: true)

        return .concatenate(
            .send(.inspector(.closeChat)),
            updateContentTabPageAnchorEffect(tabID: activeTabID, anchor: anchor, state: state),
            .send(.navigation(.view(.showAiChat(sessionString)))),
            .send(.tabContent(tabID: activeTabID, action: .aiChat(.setup(setup)))),
            providerLoadEffect,
        )
    }

    func handleHomePageAnchorSelected(
        _ anchor: ContentTabPageAnchor,
        activeTabID: ContentTabID,
        state: State,
    ) -> Effect<Action> {
        switch anchor {
        case let .directory(path):
            return .concatenate(
                updateContentTabPageAnchorEffect(tabID: activeTabID, anchor: anchor, state: state),
                .send(.navigation(.view(.navigateToPath(path)))),
            )

        case let .collectionFile(url):
            return .send(.navigation(.view(.openCollectionFile(url))))

        case .homeDefault,
             .virtualCollection:
            return updateContentTabPageAnchorEffect(tabID: activeTabID, anchor: anchor, state: state)

        case let .aiChat(sessionID):
            guard let rawSessionID = UUID(uuidString: sessionID) else { return .none }
            let sessionUUID = AiChatSessionID(rawValue: rawSessionID)
            let setup = AiChatSetupState(
                restoreSessionID: nil,
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
                await send(.tabContent(
                    tabID: activeTabID,
                    action: .aiChat(.providerConnectionsUpdated(connectionsFile)),
                ))
            }
            .cancellable(id: HomeAiChatOpenCancelID(tabID: activeTabID), cancelInFlight: true)

            return .concatenate(
                .send(.inspector(.closeChat)),
                updateContentTabPageAnchorEffect(tabID: activeTabID, anchor: anchor, state: state),
                .send(.internal(.aiChatTabTitleUpdated(sessionID: sessionUUID, title: "New Chat"))),
                .send(.navigation(.view(.showAiChat(sessionID)))),
                .send(.tabContent(tabID: activeTabID, action: .aiChat(.setup(setup)))),
                providerLoadEffect,
                .send(.internal(.homeAiChatNewChatSeedRequested(sessionID: sessionUUID))),
            )
        }
    }

    func handleRequestedCommand(_ command: Action.WindowCommand, state: inout State) -> Effect<Action> {
        if state.pendingSelectedContentTabPinMutation != nil,
           case .toggleActiveContentTabPin = command
        {
            return .none
        }
        if state.pendingSelectedContentTabClose != nil,
           shouldSuppressWhilePendingClose(command)
        {
            return .none
        }
        return routeWindowCommand(command, state: &state)
    }

    func shouldSuppressWhilePendingClose(_ command: Action.WindowCommand) -> Bool {
        switch command {
        case .openNewContentTab,
             .closeActiveContentTab,
             .closeSelectedContentTabs,
             .toggleActiveContentTabPin,
             .restoreLastClosedContentTab,
             .duplicateContentTab,
             .duplicateActiveContentTab,
             .duplicateSelectedContentTabs,
             .saveCollection,
             .saveCollectionAs:
            true
        default:
            false
        }
    }

    func routeWindowCommand(_ command: Action.WindowCommand, state: inout State) -> Effect<Action> {
        if let effect = routeContentTabCommand(command, state: &state) { return effect }
        if let effect = routeEntryCommand(command, state: &state) { return effect }
        if let effect = routeComposerCommand(command, state: &state) { return effect }
        if let effect = routeNavigationCommand(command, state: state) { return effect }
        if let effect = routeLayoutCommand(command, state: &state) { return effect }
        if let effect = routeUndoCommand(command, state: &state) { return effect }
        return .none
    }

    private func handleDuplicateActiveContentTab(state: inout State) -> Effect<Action> {
        guard let activeTabID = state.contentTabs.activeTabID else { return .none }
        return handleDuplicateContentTabRequested(sourceID: activeTabID, state: &state)
    }

    func routeContentTabCommand(
        _ command: Action.WindowCommand,
        state: inout State,
    ) -> Effect<Action>? {
        switch command {
        case .openNewContentTab,
             .selectContentTab:
            handleContentTabCommand(command, state: state)

        case .closeActiveContentTab:
            state.contentTabs.activeTabID
                .map { Effect<Action>.send(.closeContentTabRequested($0)) }
                ?? Effect<Action>.none

        case .closeSelectedContentTabs:
            .send(.requestCloseSelectedContentTabs)

        case .toggleActiveContentTabPin:
            toggleActiveContentTabPin(state: state)

        case .restoreLastClosedContentTab:
            handleRestoreLastClosedContentTab(state: &state)

        case let .duplicateContentTab(sourceID):
            handleDuplicateContentTabRequested(sourceID: sourceID, state: &state)

        case .duplicateActiveContentTab:
            handleDuplicateActiveContentTab(state: &state)

        case .duplicateSelectedContentTabs:
            handleDuplicateSelectedContentTabsRequested(state: &state)

        case .selectMostRecentlyUsedContentTab:
            handleSelectMostRecentlyUsedContentTab(state: &state)

        case let .presentContentTabSwitcher(source):
            handlePresentContentTabSwitcher(source: source, state: &state)

        case let .moveContentTabSwitcherFocus(direction):
            handleMoveContentTabSwitcherFocus(direction: direction, state: &state)

        case .dismissContentTabSwitcher:
            handleDismissContentTabSwitcher(state: &state)

        default:
            nil
        }
    }

    func routeEntryCommand(
        _ command: Action.WindowCommand,
        state: inout State,
    ) -> Effect<Action>? {
        switch command {
        case .newFolder,
             .openSelectedItem,
             .quickLookSelectedItem,
             .cut,
             .copy,
             .paste,
             .duplicate,
             .makeAlias,
             .selectAll,
             .copyAbsolutePaths,
             .copyURLs:
            handleEntryRequestIfAllowed(command, state: &state)

        case .toggleShowHiddenFiles:
            handleEntryRequest(command, state: &state)

        default:
            nil
        }
    }

    func routeComposerCommand(
        _ command: Action.WindowCommand,
        state: inout State,
    ) -> Effect<Action>? {
        switch command {
        case .saveCollection,
             .saveCollectionAs,
             .find,
             .toggleComposer,
             .newChat,
             .showChatHistory:
            handleComposerRequest(command, state: &state)

        default:
            nil
        }
    }

    func routeNavigationCommand(
        _ command: Action.WindowCommand,
        state: State,
    ) -> Effect<Action>? {
        switch command {
        case .goBack,
             .goForward,
             .goToEnclosingDirectory:
            handleNavigationRequestIfAllowed(command, state: state)

        default:
            nil
        }
    }

    func routeLayoutCommand(
        _ command: Action.WindowCommand,
        state: inout State,
    ) -> Effect<Action>? {
        switch command {
        case .toggleSidebar,
             .setViewLayout,
             .setGroupKey,
             .setSortKey,
             .setSortOrder:
            handleLayoutRequest(command, state: &state)

        default:
            nil
        }
    }

    func routeUndoCommand(
        _ command: Action.WindowCommand,
        state: inout State,
    ) -> Effect<Action>? {
        switch command {
        case .requestUndo,
             .requestRedo:
            handleUndoRedoRequest(command, state: &state)

        case .reopenChat:
            .none

        default:
            nil
        }
    }

    func handleContentTabCommand(
        _ command: Action.WindowCommand,
        state: State,
    ) -> Effect<Action> {
        switch command {
        case .openNewContentTab:
            guard state.contentTabs.tabs.count < ContentTabConstants.maxTabs else { return .none }
            return .send(.contentTabs(.open(.homeDefault)))

        case let .selectContentTab(position):
            guard state.pendingSelectedContentTabClose == nil,
                  state.pendingContentTabTeardown == nil,
                  let targetID = ContentTabProjection.tabID(
                      atDisplayPosition: position,
                      in: state.contentTabs,
                  ),
                  targetID != state.contentTabs.activeTabID
            else { return .none }
            if case .tearingDownTab = state.undoRedoPhase { return .none }
            return .send(.contentTabs(.setCurrent(targetID)))

        default:
            return .none
        }
    }

    func handleEntryRequestIfAllowed(
        _ command: Action.WindowCommand,
        state: inout State,
    ) -> Effect<Action> {
        guard !state.content.isOrdinaryDirectoryLoading else { return .none }
        return handleEntryRequest(command, state: &state)
    }

    func toggleActiveContentTabPin(state: State) -> Effect<Action> {
        guard state.pendingSelectedContentTabPinMutation == nil,
              state.pendingContentTabClose == nil,
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

    func cannotPinCollectionFeedbackEffect() -> Effect<Action> {
        let collectionAlertClient = collectionAlertClient
        return .run { _ in
            await collectionAlertClient.showCollectionOpenErrorAlert(
                "Cannot Pin Collection",
                "Save the collection before pinning it as a tab.",
            )
        }
    }

    func handleSelectMostRecentlyUsedContentTab(state: inout State) -> Effect<Action> {
        guard canRouteRecentContentTabInteraction(state) else { return .none }

        guard let targetID = state.contentTabs.takeMostRecentlyUsedInactiveTabID() else {
            return unavailableRecentlyUsedContentTabFeedbackEffect()
        }
        return .send(.contentTabs(.setCurrent(targetID)))
    }

    func unavailableRecentlyUsedContentTabFeedbackEffect() -> Effect<Action> {
        let collectionAlertClient = collectionAlertClient
        return .run { _ in
            await collectionAlertClient.showCollectionOpenErrorAlert(
                "Cannot Switch Tabs",
                "No recently used tab is available.",
            )
        }
    }

    func handleEntryRequest(_ command: Action.WindowCommand, state: inout State) -> Effect<Action> {
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

    func handleEntryRequestPathDependent(
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
            return .send(.content(.entryViewLayout(.delegate(.executeCommand("clipboard.pasteItems")))))

        default:
            return nil
        }
    }

    func handleEntryRequestSelection(_ command: Action.WindowCommand, state: State) -> Effect<Action>? {
        switch command {
        case .openSelectedItem:
            guard !state.content.isOrdinaryDirectoryLoading,
                  !state.content.entryViewLayout.selectedIds.isEmpty
            else { return .none }
            return .send(.content(.entryViewLayout(.delegate(.executeCommand("navigation.openSelectedItem")))))

        case .quickLookSelectedItem:
            guard !state.content.isOrdinaryDirectoryLoading,
                  !state.content.entryViewLayout.selectedIds.isEmpty
            else { return .none }
            return .send(.content(.entryViewLayout(.delegate(.executeCommand("navigation.quickLookSelectedItem")))))

        case .selectAll:
            return .send(.content(.view(.selectAllEntries)))

        default:
            return nil
        }
    }

    func handleEntryRequestEditing(_ command: Action.WindowCommand) -> Effect<Action>? {
        switch command {
        case .cut:
            .send(.content(.entryViewLayout(.delegate(.executeCommand("clipboard.cutSelectedItems")))))

        case .copy:
            .send(.content(.entryViewLayout(.delegate(.executeCommand("clipboard.copySelectedItems")))))

        case .duplicate:
            .send(.content(.entryViewLayout(.delegate(.executeCommand("clipboard.duplicateSelectedItems")))))

        case .makeAlias:
            .send(.content(.entryViewLayout(.delegate(.executeCommand("mutation.createAliasForSelectedItems")))))

        default:
            nil
        }
    }

    func handleEntryRequestCopying(_ command: Action.WindowCommand) -> Effect<Action>? {
        switch command {
        case .copyAbsolutePaths:
            .send(.content(.entryViewLayout(.delegate(.executeCommand("clipboard.copySelectedAbsolutePaths")))))

        case .copyURLs:
            .send(.content(.entryViewLayout(.delegate(.executeCommand("clipboard.copySelectedURLs")))))

        default:
            nil
        }
    }

    func handleEntryRequestViewOptions(_ command: Action.WindowCommand) -> Effect<Action>? {
        switch command {
        case .toggleShowHiddenFiles:
            .send(.content(.view(.toggleShowHiddenFilesAndReload)))

        default:
            nil
        }
    }

    func handleFindRequest(state: State) -> Effect<Action> {
        if state.inspector.inspectorVisible,
           state.inspector.activeMode == .chat,
           state.inspector.aiChat.mode == .chat
        {
            return .send(.inspector(.aiChat(.transcriptSearchOpened)))
        }

        if let activeTabID = state.contentTabs.activeTabID,
           case .aiChat = state.contentTabs.tabs[id: activeTabID]?.anchor,
           state.content.aiChat.mode == .chat
        {
            return .send(.tabContent(tabID: activeTabID, action: .aiChat(.transcriptSearchOpened)))
        }

        return .send(.request(.toggleComposer))
    }

    func handleComposerRequest(_ command: Action.WindowCommand, state: inout State) -> Effect<Action> {
        switch command {
        case .saveCollection:
            .send(.content(.composer(.saveCollection)))

        case .saveCollectionAs:
            .send(.content(.composer(.saveCollectionAs)))

        case .find:
            handleFindRequest(state: state)

        case .toggleComposer:
            .send(.content(.composer(.setPresented(!state.content.composer.isPresented))))

        case .newChat:
            handleAiChatInspectorRequest(destination: .newChat, state: &state)

        case .showChatHistory:
            handleAiChatInspectorRequest(destination: .chatHistory, state: &state)

        default:
            .none
        }
    }

    func warmUpAIModelCatalogEffect() -> Effect<Action> {
        .run { [searchClient] _ in
            try? await searchClient.warmUpAIModelCatalog()
        }
    }

    func forwardProviderConnectionsToOpenAiChat(
        file: AIConnectionsFile,
        state: inout State,
    ) -> Effect<Action> {
        let connectedProviders = file.providers.values
            .filter { $0.snapshot.lastKnownStatus == .connected }
            .map(\.providerId)
            .sorted { $0.rawValue < $1.rawValue }
        refreshPendingAiChatProviderAuthority(
            connectedProviders: connectedProviders,
            state: &state,
        )

        var effects: [Effect<Action>] = []

        // ContentPane AI Chat forwarding: active tab이 .aiChat일 때 전송
        if let activeTabID = state.contentTabs.activeTabID,
           case .aiChat = state.contentTabs.tabs[id: activeTabID]?.anchor
        {
            effects.append(.send(.tabContent(tabID: activeTabID, action: .aiChat(.providerConnectionsUpdated(file)))))
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

    func handleNavigationRequestIfAllowed(
        _ command: Action.WindowCommand,
        state: State,
    ) -> Effect<Action> {
        guard state.pendingContentTabClose == nil else { return .none }
        return handleNavigationRequest(command)
    }

    func refreshPendingAiChatProviderAuthority(
        connectedProviders: [AiProvider],
        state: inout State,
    ) {
        if refreshPendingAiChatProviderAuthority(
            connectedProviders: connectedProviders,
            aiChat: &state.content.aiChat,
        ) {
            state.syncActiveTabContentState()
        }
        if refreshPendingAiChatProviderAuthority(
            connectedProviders: connectedProviders,
            aiChat: &state.inspector.aiChat,
        ) {
            state.syncActiveTabInspectorState()
        }

        for tabID in state.tabContentStates.keys {
            guard var content = state.tabContentStates[tabID] else { continue }
            _ = refreshPendingAiChatProviderAuthority(
                connectedProviders: connectedProviders,
                aiChat: &content.aiChat,
            )
            state.tabContentStates[tabID] = content
        }
        for tabID in state.tabInspectorStates.keys {
            guard var inspector = state.tabInspectorStates[tabID] else { continue }
            _ = refreshPendingAiChatProviderAuthority(
                connectedProviders: connectedProviders,
                aiChat: &inspector.aiChat,
            )
            state.tabInspectorStates[tabID] = inspector
        }
        for sessionID in state.backgroundAiChatStates.keys {
            guard var content = state.backgroundAiChatStates[sessionID] else { continue }
            _ = refreshPendingAiChatProviderAuthority(
                connectedProviders: connectedProviders,
                aiChat: &content.aiChat,
            )
            state.backgroundAiChatStates[sessionID] = content
        }
        for sessionID in state.backgroundInspectorAiChatStates.keys {
            guard var inspector = state.backgroundInspectorAiChatStates[sessionID] else { continue }
            _ = refreshPendingAiChatProviderAuthority(
                connectedProviders: connectedProviders,
                aiChat: &inspector.aiChat,
            )
            state.backgroundInspectorAiChatStates[sessionID] = inspector
        }
    }

    @discardableResult
    func refreshPendingAiChatProviderAuthority(
        connectedProviders: [AiProvider],
        aiChat: inout AiChatFeature.State,
    ) -> Bool {
        guard aiChat.pendingRequestStart != nil || !aiChat.backgroundPendingRequestStarts.isEmpty else { return false }
        _ = AiChatFeature().reduce(
            into: &aiChat,
            action: .providerConnectionAuthorityUpdated(connectedProviders),
        )
        return true
    }

    func handleNavigationRequest(_ command: Action.WindowCommand) -> Effect<Action> {
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

    func handleLayoutRequest(_ command: Action.WindowCommand, state: inout State) -> Effect<Action> {
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

    func handleUndoRedoRequest(_ command: Action.WindowCommand, state: inout State) -> Effect<Action> {
        let direction: EntryActionDirection
        switch command {
        case .requestUndo:
            direction = .undo
        case .requestRedo:
            direction = .redo
        default:
            return .none
        }
        guard let expectedTarget = state.validatedUndoRedoTarget(for: direction) else { return .none }

        let requestID = uuid()
        let windowID = state.windowID
        state.undoRedoPhase = .invoking(requestID: requestID, direction: direction)
        return .run { send in
            let result = switch direction {
            case .undo:
                await undoManagerClient.undo(windowID, expectedTarget: expectedTarget)
            case .redo:
                await undoManagerClient.redo(windowID, expectedTarget: expectedTarget)
            }
            await send(.internal(.undoManagerInvocationFinished(
                requestID: requestID,
                direction: direction,
                result: result,
            )))
        }
    }

    func undoManagerAvailabilityEffect(windowID: UUID?) -> Effect<Action> {
        .run { send in
            let availability = await undoManagerClient.availability(windowID)
            await send(.internal(.undoManagerAvailabilityChanged(availability)))
        }
    }

    func undoManagerEventsEffect(windowID: UUID) -> Effect<Action> {
        .run { send in
            for await event in undoManagerClient.events(windowID) {
                await send(.internal(.undoManagerEventReceived(event)))
            }
        }
        .cancellable(id: CancelID.undoManagerEvents, cancelInFlight: true)
    }
}
