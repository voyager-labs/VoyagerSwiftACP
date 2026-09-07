import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesAiChat
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerShared

struct BatchDuplicateOwnerSnapshot {
    let request: ContentTabDuplicateRequest
    let sourceItem: ContentTabItem
    let duplicateAnchor: ContentTabPageAnchor
    let sourceContent: FileManagerContentFeature.State?
    let sourceAiChatLifecycleSessionIDs: [AiChatSessionID]
    let duplicatedContent: FileManagerContentFeature.State
}

func createdDuplicateRequests(
    _ requests: [ContentTabDuplicateRequest],
    preexistingTabIDs: Set<ContentTabID>,
    state: FileManagerWindowState,
) -> [ContentTabDuplicateRequest] {
    guard let activeDuplicateID = state.contentTabs.activeTabID,
          requests.contains(where: { $0.duplicateID == activeDuplicateID })
    else { return [] }

    var seenSourceIDs = Set<ContentTabID>()
    var seenDuplicateIDs = Set<ContentTabID>()
    var createdRequests: [ContentTabDuplicateRequest] = []
    for request in requests {
        guard request.sourceID != request.duplicateID,
              !seenSourceIDs.contains(request.sourceID),
              !seenDuplicateIDs.contains(request.duplicateID),
              !preexistingTabIDs.contains(request.duplicateID),
              let sourceItem = state.contentTabs.tabs[id: request.sourceID],
              let duplicateItem = state.contentTabs.tabs[id: request.duplicateID]
        else { continue }
        guard duplicateItem.page == sourceItem.page,
              duplicateItem.anchor == sourceItem.anchor,
              duplicateItem.title == sourceItem.title,
              duplicateItem.iconName == sourceItem.iconName,
              !duplicateItem.isPinned
        else { continue }
        seenSourceIDs.insert(request.sourceID)
        seenDuplicateIDs.insert(request.duplicateID)
        createdRequests.append(request)
    }
    return createdRequests
}

func duplicateSourceContentState(
    sourceID: ContentTabID,
    duplicateID: ContentTabID,
    state: FileManagerWindowState,
) -> FileManagerContentFeature.State? {
    if state.contentTabs.activeTabID == duplicateID {
        if state.contentTabs.previousActiveTabID == sourceID {
            return state.content
        }
        return state.tabContentStates[sourceID]
    }
    if state.contentTabs.activeTabID == sourceID {
        return state.content
    }
    return state.tabContentStates[sourceID]
}

func makeDuplicatedContentState(
    _ sourceContentState: FileManagerContentFeature.State?,
    anchor: ContentTabPageAnchor?,
    inheritingWindowContextFrom windowContentState: FileManagerContentFeature.State,
) -> FileManagerContentFeature.State {
    var duplicatedContentState = FileManagerContentFeature.State.initialContent(
        for: anchor,
        inheritingWindowContextFrom: sourceContentState ?? windowContentState,
    )
    guard let sourceContentState else {
        return duplicatedContentState
    }

    duplicatedContentState.navigation.backHistory = sourceContentState.navigation.backHistory
    duplicatedContentState.navigation.forwardHistory = sourceContentState.navigation.forwardHistory
    return duplicatedContentState
}

func restoreActiveAiChatSessionIfNeededEffect(
    state: FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    guard let activeTabID = state.contentTabs.activeTabID,
          case let .aiChat(sessionID) = state.contentTabs.tabs[id: activeTabID]?.anchor,
          let sessionUUID = UUID(uuidString: sessionID),
          state.content.aiChat.sessionID == nil,
          state.content.aiChat.restoreSessionID == nil
    else {
        return .none
    }

    let aiChatSessionID = AiChatSessionID(rawValue: sessionUUID)
    guard !hasBackgroundAiChatLifecycleOwner(sessionID: aiChatSessionID, state: state) else {
        return .none
    }
    if state.content.aiChat.deferredChatSessionRestoreID == aiChatSessionID {
        return .send(.content(.aiChat(.routeToChatSession(aiChatSessionID))))
    }

    return .send(.content(.aiChat(.setup(AiChatSetupState(
        restoreSessionID: aiChatSessionID,
        sessionID: nil,
        mode: .chat,
    )))))
}

func hasBackgroundAiChatLifecycleOwner(
    sessionID: AiChatSessionID,
    state: FileManagerWindowState,
) -> Bool {
    state.backgroundAiChatStates.values.contains {
        $0.aiChat.hasLifecycleOwner(sessionID: sessionID)
    } || state.backgroundInspectorAiChatStates.values.contains {
        $0.aiChat.hasLifecycleOwner(sessionID: sessionID)
    }
}

func navigationRouteForClosingTab(
    _ tabID: ContentTabID,
    state: FileManagerWindowState,
) -> ContentPageNavigationRoute? {
    if state.contentTabs.previousActiveTabID == tabID {
        return state.content.navigation.navigationState
    }
    return state.tabContentStates[tabID]?.navigation.navigationState
}

func prepareContentForActiveTabHandoff(
    state: inout FileManagerContentFeature.State,
    skipAiChatCleanup: Bool = false,
) -> Effect<FileManagerWindowAction> {
    let composerCleanupEffect = ComposerFeature()
        .reduce(into: &state.composer, action: .internal(.cleanupCollectionWork))
        .map { FileManagerWindowAction.content(.composer($0)) }
    let aiChatCleanupEffect: Effect<FileManagerWindowAction>
    if skipAiChatCleanup {
        aiChatCleanupEffect = .none
    } else {
        aiChatCleanupEffect = AiChatFeature()
            .reduce(into: &state.aiChat, action: .cancelInFlightWork)
            .map { FileManagerWindowAction.content(.aiChat($0)) }
        clearInFlightAiChatStateOnTabSwitch(state: &state.aiChat)
    }
    state.entryViewLayout.entryOperations.isLoading = false
    state.entryViewLayout.entryOperations.isReloading = false
    state.entryViewLayout.isCollectionContentLoading = false
    return .merge(composerCleanupEffect, aiChatCleanupEffect)
}

func clearInFlightAiChatStateOnTabSwitch(state: inout AiChatState) {
    state.pendingRequestStart = nil
    state.streamingAssistantDraft = nil
    state.lockedModelHandle = nil
    state.executionPhase = .idle
    state.restoreSessionID = nil
    state.restoreOutcome = nil
    state.restoreFailure = nil
    if state.modelListState == .loading {
        state.modelListState = .idle
        state.modelListRequestID = nil
        state.modelListProvider = nil
        state.modelListProviderOrder = []
        state.modelListPendingProviders = []
        state.modelListLoadedModelsByProvider = [:]
        state.modelListFailedProviders = [:]
    }
    if state.sessionStatus == .restoring {
        state.sessionStatus = state.sessionID == nil ? .idle : .active
    }
}

func cancelLoadingEffectForClosedTab(
    tabID: ContentTabID,
    wasActive: Bool,
    state: FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    let closedContent = wasActive ? state.content : state.tabContentStates[tabID]
    guard let closedContent else { return .none }
    let entryOperations = closedContent.entryViewLayout.entryOperations
    return .cancel(id: EntryOperationsLoadingCancelID.loadItems(
        windowID: entryOperations.windowID,
        ownerID: entryOperations.loadingCancellationOwnerID,
    ))
}

func activeTabHandoffEffect(
    _ shouldResyncContentNavigation: Bool,
    state: inout FileManagerWindowState,
    aiConnectionsFileClient: AIConnectionsFileClient,
    skipAiChatCancel: Bool = false,
    restorePendingCollectionHistory: Bool = false,
) -> Effect<FileManagerWindowAction> {
    guard shouldResyncContentNavigation else {
        return .none
    }
    let restoreHistoryEffect: Effect<FileManagerWindowAction> = if restorePendingCollectionHistory,
                                                                   let request = state
                                                                   .pendingCollectionOpenRequest
    {
        .send(.navigation(.internal(.restoreHistory(
            back: request.prePrepareBackHistory,
            forward: request.prePrepareForwardHistory,
        ))))
    } else {
        .none
    }
    let failedPinnedReturnTabID = state.pendingPinnedCollectionReturnTabID(
        for: state.contentTabs.previousActiveTabID,
    )
    let failedPinnedReturnEffect: Effect<FileManagerWindowAction> = failedPinnedReturnTabID.map { tabID in
        .send(.delegate(.pinnedContentTabRuntimeNavigationFailed(tabID: tabID)))
    } ?? .none
    state.pendingCollectionOpenRequest = nil
    let navigationEffect = resyncContentNavigationEffect(state: state)
    // navigation/content 복원 이후에만 포커스된 활성 탭의 selectionChanged를 발행해
    // 전역 Quick Look 패널이 새 활성 탭 선택으로 동기화되게 한다.
    let quickLookResyncEffect: Effect<FileManagerWindowAction> = if state.isFocused,
                                                                    !state.isClosing,
                                                                    let activeTabID = state.contentTabs.activeTabID
    {
        .send(.tabContent(
            tabID: activeTabID,
            action: .entryViewLayout(.delegate(.selectionChanged)),
        ))
    } else {
        .none
    }
    return .concatenate(
        cancelInFlightContentEffectsOnTabSwitch(state: state, skipAiChatCancel: skipAiChatCancel),
        restoreHistoryEffect,
        failedPinnedReturnEffect,
        .merge(
            navigationEffect,
            restartAiChatProviderLoadOnTabRestoreEffect(
                state: state,
                aiConnectionsFileClient: aiConnectionsFileClient,
            ),
        ),
        quickLookResyncEffect,
    )
}

func cancelInFlightContentEffectsOnTabSwitch(
    state: FileManagerWindowState,
    skipAiChatCancel: Bool = false,
) -> Effect<FileManagerWindowAction> {
    let loadingCancellationEffect: Effect<FileManagerWindowAction> = state.contentTabs.previousActiveTabID
        .flatMap { state.tabContentStates[$0] }
        .map { previousContent in
            .cancel(id: EntryOperationsLoadingCancelID.loadItems(
                windowID: previousContent.entryViewLayout.entryOperations.windowID,
                ownerID: previousContent.entryViewLayout.entryOperations.loadingCancellationOwnerID,
            ))
        } ?? .none
    let previousTabContentCancellationEffect: Effect<FileManagerWindowAction> = state.contentTabs.previousActiveTabID
        .flatMap { previousTabID in
            state.tabContentStates[previousTabID].map { _ in
                .merge(
                    .send(.tabContent(
                        tabID: previousTabID,
                        action: .entryViewLayout(.entryOperations(.loading(.cancelAllFolderItems))),
                    )),
                    .send(.tabContent(
                        tabID: previousTabID,
                        action: .entryViewLayout(.internal(.cancelCollectionMaterialization)),
                    )),
                )
            }
        } ?? .none

    return .merge(
        .cancel(id: OpenCollectionFileCancelID(
            windowID: state.content.entryViewLayout.entryOperations.windowID,
        )),
        loadingCancellationEffect,
        previousTabContentCancellationEffect,
        state.contentTabs.previousActiveTabID
            .map { .cancel(id: HomeAiChatOpenCancelID(tabID: $0)) }
            ?? .none,
        skipAiChatCancel ? .none : contentPaneAiChatCancelEffect(state: state),
    )
}

func contentPaneAiChatCancelEffect(state: FileManagerWindowState) -> Effect<FileManagerWindowAction> {
    guard !state.inspector.inspectorVisible || state.inspector.activeMode != .chat else {
        return .none
    }
    return .send(.content(.aiChat(.cancelInFlightWork)))
}

func restartAiChatProviderLoadOnTabRestoreEffect(
    state: FileManagerWindowState,
    aiConnectionsFileClient: AIConnectionsFileClient,
) -> Effect<FileManagerWindowAction> {
    guard let activeTabID = state.contentTabs.activeTabID,
          case .aiChat = state.contentTabs.tabs[id: activeTabID]?.anchor
    else { return .none }
    if case .loaded = state.content.aiChat.modelListState {
        return .none
    }

    return .run { send in
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
}

func resyncContentNavigationEffect(state: FileManagerWindowState) -> Effect<FileManagerWindowAction> {
    guard let activeTabID = state.contentTabs.activeTabID else { return .none }
    if let collectionURL = collectionFileURLRequiringOpen(state: state) {
        return .send(.navigation(.view(.openCollectionFile(collectionURL))))
    }
    guard let navigationState = resyncNavigationStateForActiveContentTab(state: state) else {
        return .none
    }
    if case let .collection(navigation) = navigationState {
        return .concatenate(
            .send(.tabContent(tabID: activeTabID, action: .internal(.applyNavigationState(.collection(navigation))))),
            .send(.navigation(.internal(.navigateToCollection(navigation)))),
        )
    }
    return .send(.tabContent(tabID: activeTabID, action: .internal(.applyNavigationState(navigationState))))
}

func collectionFileURLRequiringOpen(state: FileManagerWindowState) -> URL? {
    guard let activeTabID = state.contentTabs.activeTabID,
          case let .collectionFile(url) = state.contentTabs.tabs[id: activeTabID]?.anchor
    else { return nil }
    guard state.content.collection.collectionSession.document?.url.standardizedFileURL != url.standardizedFileURL else {
        return nil
    }
    if case let .collection(navigation) = state.content.navigation.navigationState,
       case let .file(navigationURL, _) = navigation.kind,
       navigationURL.standardizedFileURL == url.standardizedFileURL,
       !isEmptyCollectionContext(navigation.context)
    {
        return nil
    }
    return url
}

func isEmptyCollectionContext(_ context: CollectionContext) -> Bool {
    context.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && context.scopes.isEmpty
        && context.excludedScopes.isEmpty
        && context.conditions.isEmpty
}

func resyncNavigationStateForActiveContentTab(
    state: FileManagerWindowState,
) -> ContentPageNavigationRoute? {
    guard let activeTabID = state.contentTabs.activeTabID,
          let activeAnchor = state.contentTabs.tabs[id: activeTabID]?.anchor
    else { return nil }

    switch activeAnchor {
    case .homeDefault:
        return .home
    case let .aiChat(sessionID):
        if case let .aiChatSessions(restoredSessionID) = state.content.navigation.navigationState,
           restoredSessionID == sessionID
        {
            return .aiChatSessions(sessionID)
        }
        return .aiChat(sessionID)
    case let .directory(path):
        return .folder(path)
    case .collectionFile:
        if case let .collection(navigation) = state.content.navigation.navigationState {
            return .collection(navigation)
        }
        return nil
    case .virtualCollection:
        switch state.content.navigation.navigationState {
        case .recents,
             .tags,
             .computer:
            return state.content.navigation.navigationState
        default:
            return nil
        }
    }
}

func closeInspectorForActiveAiChatEffect(state: FileManagerWindowState) -> Effect<FileManagerWindowAction> {
    guard state.inspector.inspectorVisible,
          let activeTabID = state.contentTabs.activeTabID,
          case .aiChat = state.contentTabs.tabs[id: activeTabID]?.anchor
    else {
        return .none
    }
    return .send(.inspector(.closeChat))
}

func syncSidebarSelectionForActiveContentTab(state _: inout FileManagerWindowState) {}

func contentState(
    for anchor: ContentTabPageAnchor?,
    inheritingWindowContextFrom source: FileManagerContentFeature.State,
) -> FileManagerContentFeature.State {
    var content = FileManagerContentFeature.State()
    content.applyWindowContext(from: source)

    switch anchor {
    case let .directory(path):
        content.navigation.seedInitialFolderPath(path)
    case let .collectionFile(url):
        content.navigation.navigationState = .collection(.init(
            kind: .file(url: url, name: url.deletingPathExtension().lastPathComponent),
            context: CollectionContext(query: "", scopes: [], conditions: []),
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        ))
    case let .virtualCollection(id):
        content.navigation.navigationState = .tags(id)
    case let .aiChat(sessionID):
        content.navigation.navigationState = .aiChat(sessionID)
        content.aiChat.mode = .chat
    case .homeDefault,
         .none:
        break
    }

    return content
}

extension ContentTabPageAnchor {
    var isCollectionFileAnchor: Bool {
        if case .collectionFile = self {
            true
        } else {
            false
        }
    }
}

private extension AiChatExecutionPhase {
    var shouldPreserveLifecycleOwner: Bool {
        switch self {
        case let .completed(lock):
            lock.finalSnapshot != nil
        case .persistenceRecovery:
            true
        default:
            false
        }
    }
}

func aiChatLifecycleSessionIDsToPreserve(_ state: AiChatFeature.State) -> [AiChatSessionID] {
    var sessionIDs: [AiChatSessionID] = []
    func append(_ sessionID: AiChatSessionID?) {
        guard let sessionID, !sessionIDs.contains(sessionID) else { return }
        sessionIDs.append(sessionID)
    }

    if state.executionPhase.isProcessing
        || state.executionPhase.shouldPreserveLifecycleOwner
    {
        append(state.executionPhase.lock?.context.sessionID)
    }
    append(state.pendingRequestStart?.sessionID)
    for pendingRequestStart in state.backgroundPendingRequestStarts.values {
        append(pendingRequestStart.sessionID)
    }
    for phase in state.backgroundExecutionPhases.values where phase.isProcessing || phase.shouldPreserveLifecycleOwner {
        append(phase.lock?.context.sessionID)
    }
    return sessionIDs
}

func cancelAndRemoveBackgroundAiChatOwners(
    sessionID: AiChatSessionID,
    state: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    var effects: [Effect<FileManagerWindowAction>] = []
    if let backgroundContent = state.removeBackgroundAiChatState(sessionID: sessionID) {
        effects.append(cancelBackgroundAiChatWork(sessionID: sessionID, aiChat: backgroundContent.aiChat))
    }
    if let backgroundInspector = state.removeBackgroundInspectorAiChatState(sessionID: sessionID) {
        effects.append(cancelBackgroundInspectorAiChatWork(sessionID: sessionID, aiChat: backgroundInspector.aiChat))
    }

    for backgroundSessionID in state.backgroundAiChatStates.keys {
        guard var backgroundContent = state.backgroundAiChatStates[backgroundSessionID],
              backgroundContent.aiChat.hasLifecycleOwner(sessionID: sessionID)
        else { continue }
        effects.append(cancelBackgroundAiChatWork(sessionID: sessionID, aiChat: backgroundContent.aiChat))
        backgroundContent.aiChat.removeLifecycleOwners(sessionID: sessionID)
        if backgroundContent.aiChat.hasRemainingBackgroundLifecycleOwner {
            state.backgroundAiChatStates[backgroundSessionID] = backgroundContent
        } else {
            state.removeBackgroundAiChatState(sessionID: backgroundSessionID)
        }
    }

    for backgroundSessionID in state.backgroundInspectorAiChatStates.keys {
        guard var backgroundInspector = state.backgroundInspectorAiChatStates[backgroundSessionID],
              backgroundInspector.aiChat.hasLifecycleOwner(sessionID: sessionID)
        else { continue }
        effects.append(cancelBackgroundInspectorAiChatWork(sessionID: sessionID, aiChat: backgroundInspector.aiChat))
        backgroundInspector.aiChat.removeLifecycleOwners(sessionID: sessionID)
        if backgroundInspector.aiChat.hasRemainingBackgroundLifecycleOwner {
            state.backgroundInspectorAiChatStates[backgroundSessionID] = backgroundInspector.tabSnapshot()
        } else {
            state.removeBackgroundInspectorAiChatState(sessionID: backgroundSessionID)
        }
    }
    return .merge(effects)
}

func cancelBackgroundAiChatWork(
    sessionID: AiChatSessionID,
    aiChat: AiChatFeature.State,
) -> Effect<FileManagerWindowAction> {
    var scopedAiChat = aiChat.cancellationScope(sessionID: sessionID)
    return AiChatFeature()
        .reduce(into: &scopedAiChat, action: .cancelRequestLifecycle(sessionID))
        .map { FileManagerWindowAction.backgroundAiChat($0) }
}

func cancelBackgroundInspectorAiChatWork(
    sessionID: AiChatSessionID,
    aiChat: AiChatFeature.State,
) -> Effect<FileManagerWindowAction> {
    var scopedAiChat = aiChat.cancellationScope(sessionID: sessionID)
    return AiChatFeature()
        .reduce(into: &scopedAiChat, action: .cancelRequestLifecycle(sessionID))
        .map { FileManagerWindowAction.backgroundInspectorAiChat($0) }
}

func propagateAiChatSessionDeleteSucceeded(
    sessionID: AiChatSessionID,
    state: inout FileManagerWindowState,
) {
    state.content.aiChat.applySessionDeleteSucceeded(sessionID: sessionID)
    state.syncActiveTabContentState()

    for tabID in state.tabContentStates.keys {
        state.tabContentStates[tabID]?.aiChat.applySessionDeleteSucceeded(sessionID: sessionID)
    }

    state.inspector.aiChat.applySessionDeleteSucceeded(sessionID: sessionID)
    state.syncActiveTabInspectorState()

    for tabID in state.tabInspectorStates.keys {
        state.tabInspectorStates[tabID]?.aiChat.applySessionDeleteSucceeded(sessionID: sessionID)
    }

    state.removeBackgroundAiChatState(sessionID: sessionID)
    state.removeBackgroundInspectorAiChatState(sessionID: sessionID)

    for sessionKey in Array(state.backgroundAiChatStates.keys) {
        state.backgroundAiChatStates[sessionKey]?.aiChat.applySessionDeleteSucceeded(sessionID: sessionID)
    }
    for sessionKey in Array(state.backgroundInspectorAiChatStates.keys) {
        if var backgroundInspector = state.backgroundInspectorAiChatStates[sessionKey] {
            backgroundInspector.aiChat.applySessionDeleteSucceeded(sessionID: sessionID)
            state.backgroundInspectorAiChatStates[sessionKey] = backgroundInspector.tabSnapshot()
        }
    }
}

func refreshAiChatCustomTitle(
    summary: AiChatSessionSummary,
    customTitle: String?,
    state: inout FileManagerWindowState,
) {
    let sessionID = summary.sessionID
    state.content.aiChat.refreshCustomTitle(summary: summary, customTitle: customTitle)
    state.syncActiveTabContentState()

    for tabID in state.tabContentStates.keys {
        state.tabContentStates[tabID]?.aiChat.refreshCustomTitle(summary: summary, customTitle: customTitle)
    }

    state.inspector.aiChat.refreshCustomTitle(summary: summary, customTitle: customTitle)
    state.syncActiveTabInspectorState()

    for tabID in state.tabInspectorStates.keys {
        state.tabInspectorStates[tabID]?.aiChat.refreshCustomTitle(summary: summary, customTitle: customTitle)
    }

    if var backgroundContent = state.backgroundAiChatStates[sessionID] {
        backgroundContent.aiChat.refreshCustomTitle(summary: summary, customTitle: customTitle)
        state.backgroundAiChatStates[sessionID] = backgroundContent
    }
    if var backgroundInspector = state.backgroundInspectorAiChatStates[sessionID] {
        backgroundInspector.aiChat.refreshCustomTitle(summary: summary, customTitle: customTitle)
        state.backgroundInspectorAiChatStates[sessionID] = backgroundInspector.tabSnapshot()
    }
}

func routeBackgroundAiChatAction(
    _ aiChatAction: AiChatAction,
    state: inout FileManagerWindowState,
) -> Effect<FileManagerWindowAction> {
    guard let sessionID = backgroundAiChatSessionID(for: aiChatAction, state: state),
          var backgroundContent = state.backgroundAiChatStates[sessionID]
    else { return .none }

    if case let .requestContextResolved(resolutionID, _) = aiChatAction {
        backgroundContent.aiChat.activateBackgroundPendingRequestStart(resolutionID: resolutionID)
        removeAiChatPendingRequestStart(resolutionID: resolutionID, state: &state)
    }

    let backgroundOwnerRemoval = backgroundAiChatOwnerRemoval(
        after: aiChatAction,
        backgroundAiChat: backgroundContent.aiChat,
    )
    let finalSnapshotContext = backgroundFinalSnapshotContext(
        from: aiChatAction,
        backgroundAiChat: backgroundContent.aiChat,
    )
    let effect = reduceBackgroundAiChatAction(
        aiChatAction,
        into: &backgroundContent,
        finalSnapshotContext: finalSnapshotContext,
    )

    if let payload = sessionSnapshotRefreshPayload(from: aiChatAction) {
        refreshAiChatSnapshotsFromBackgroundIfNeeded(
            summary: payload.summary,
            backgroundAiChat: backgroundContent.aiChat,
            state: &state,
            snapshot: payload.snapshot,
        )
    } else if let failedContext = failedAiChatContext(from: aiChatAction) {
        refreshAiChatFailureFromBackgroundIfNeeded(
            context: failedContext,
            backgroundAiChat: backgroundContent.aiChat,
            state: &state,
        )
    } else if let recoveryLock = persistenceRecoveryLock(from: aiChatAction) {
        refreshAiChatRecoveryFromBackgroundIfNeeded(
            lock: recoveryLock,
            backgroundAiChat: backgroundContent.aiChat,
            state: &state,
        )
    }

    backgroundContent.aiChat.removeBackgroundOwner(backgroundOwnerRemoval)
    if backgroundContent.aiChat.hasRemainingBackgroundLifecycleOwner {
        state.backgroundAiChatStates[sessionID] = backgroundContent
    } else {
        state.removeBackgroundAiChatState(sessionID: sessionID)
    }

    return effect
}

private func reduceBackgroundAiChatAction(
    _ aiChatAction: AiChatAction,
    into backgroundContent: inout FileManagerContentFeature.State,
    finalSnapshotContext: BackgroundFinalSnapshotContext?,
) -> Effect<FileManagerWindowAction> {
    AiChatFeature()
        .reduce(into: &backgroundContent.aiChat, action: aiChatAction)
        .map { action in
            if case let .sessionSnapshotSaved(summary, persistedSnapshot, _, _) = action,
               let context = finalSnapshotContext,
               let snapshot = persistedSnapshot ?? makeOffscreenFinalSnapshot(summary: summary, context: context)
            {
                return FileManagerWindowAction.backgroundAiChatSnapshotPersisted(snapshot)
            }
            return FileManagerWindowAction.backgroundAiChat(action)
        }
}
