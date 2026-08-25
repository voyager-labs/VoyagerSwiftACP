import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesAiChat
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import VoyagerPagesFileManager
import VoyagerPagesOnboarding
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

typealias FileManagerWindowFeature = FileManagerFeature

@Reducer
struct WindowManagerFeature {
    typealias State = WindowManagerState
    typealias Action = WindowManagerAction

    nonisolated enum CancelID: Hashable {
        case defaultWindowBootstrap
        case windowOpen(State.WindowID)
        case externalOpenBatch(UUID)
        case trackedSingletonNativeOpen(UUID)
    }

    let pickAttachments: @Sendable () async -> [URL]

    init(
        pickAttachments: @escaping @Sendable () async -> [URL] = {
            await MainActor.run {
                AttachmentPickerPresenter.pickAttachments()
            }
        },
    ) {
        self.pickAttachments = pickAttachments
    }

    @Dependency(\.onboardingWindowClient)
    var onboardingWindowClient

    @Dependency(\.fileManagerWindowClient)
    var fileManagerWindowClient
    @Dependency(\.attachmentPickerClient)
    var attachmentPickerClient

    @Dependency(\.fileManagerBuiltInCollectionClient)
    var fileManagerBuiltInCollectionClient
    @Dependency(\.contentTabPinnedRecordClient)
    var contentTabPinnedRecordClient
    @Dependency(\.fileManagerClient)
    var fileManagerClient
    @Dependency(\.fileManagerLocationsClient)
    var fileManagerLocationsClient
    @Dependency(\.fileManagerFavoritesClient)
    var fileManagerFavoritesClient
    @Dependency(\.entryLoadingClient)
    var entryLoadingClient
    @Dependency(\.fileOperationUndoManagerClient)
    var fileOperationUndoManagerClient
    @Dependency(\.undoManagerClient)
    var undoManagerClient
    @Dependency(\.userDefaultsClient)
    var userDefaultsClient
    @Dependency(\.metricsClient)
    var metricsClient
    @Dependency(\.workspaceClient)
    var workspaceClient

    @Dependency(\.date)
    var date

    @Dependency(\.uuid)
    var uuid

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .lifecycle:
                if let effect = handleLifecycleAction(action, state: &state) { return effect }
                return .none

            case .file(.newWindow),
                 .file(.openCollectionFile),
                 .file(.newTab),
                 .window(.closeFocusedWindow),
                 .window(.closeAllWindows):
                return handleWindowCommand(action, state: &state)

            case .file(.closeTab):
                return sendCloseTabCommandToFocusedWindow(state)

            case .file(.togglePinTab):
                return sendPinTabCommandToFocusedWindow(state)

            case .file(.restoreLastClosedTab):
                return sendContentTabCommandToFocusedWindow(
                    state,
                    .restoreLastClosedContentTab,
                    capability: \.canRestoreLastClosedTab,
                )

            case .file(.duplicateTab):
                return sendDuplicateTabCommandToFocusedWindow(state)

            case let .file(.selectContentTab(position: position)):
                return sendCommandToFocusedWindow(state, .selectContentTab(position: position))

            case .file(.presentContentTabSwitcher):
                guard let id = state.focusedWindowID, isWindowReady(id, state: state) else { return .none }
                return sendCommandToFocusedWindow(state, .presentContentTabSwitcher(source: .automatic))

            case let .file(.presentContentTabSwitcherInWindow(windowID: id, source: source)):
                guard state.focusedWindowID == id,
                      state.windows[id: id]?.window.contentTabSwitcherPresentation == nil,
                      isWindowReady(id, state: state)
                else { return .none }
                return sendCommandToWindow(state, id: id, command: .presentContentTabSwitcher(source: source))

            case .file(.selectMostRecentlyUsedContentTab):
                guard let id = state.focusedWindowID, isWindowReady(id, state: state) else { return .none }
                return sendCommandToFocusedWindow(state, .selectMostRecentlyUsedContentTab)

            case .file(.moveNextContentTabSwitcher):
                guard let id = state.focusedWindowID, isWindowReady(id, state: state) else { return .none }
                return sendCommandToFocusedWindow(
                    state,
                    .moveNextContentTabSwitcher,
                )

            case let .file(.moveNextContentTabSwitcherInWindow(windowID: id, source: source)):
                guard isWindowReady(id, state: state) else { return .none }
                return sendCommandToWindowIfPresentationMatches(
                    state,
                    id: id,
                    source: source,
                    command: .moveNextContentTabSwitcher,
                )

            case .file(.movePreviousContentTabSwitcher):
                guard let id = state.focusedWindowID, isWindowReady(id, state: state) else { return .none }
                return sendCommandToFocusedWindow(
                    state,
                    .movePreviousContentTabSwitcher,
                )

            case let .file(.movePreviousContentTabSwitcherInWindow(windowID: id, source: source)):
                guard isWindowReady(id, state: state) else { return .none }
                return sendCommandToWindowIfPresentationMatches(
                    state,
                    id: id,
                    source: source,
                    command: .movePreviousContentTabSwitcher,
                )

            case .file(.dismissContentTabSwitcher):
                guard let id = state.focusedWindowID,
                      !state.closingWindowIDs.contains(id),
                      isWindowReady(id, state: state)
                else { return .none }
                return sendCommandToFocusedWindow(state, .dismissContentTabSwitcher)

            case let .file(.dismissContentTabSwitcherInWindow(windowID: id, source: source)):
                guard isWindowReady(id, state: state) else { return .none }
                return sendCommandToWindowIfPresentationMatches(
                    state,
                    id: id,
                    source: source,
                    command: .dismissContentTabSwitcher,
                )

            case .file(.newFolder):
                return sendCommandToFocusedWindow(state, .newFolder)

            case .file(.open):
                return sendCommandToFocusedWindow(state, .openSelectedItem)

            case .file(.quickLook):
                return sendCommandToFocusedWindow(state, .quickLookSelectedItem)

            case .file(.saveCollection):
                return sendCommandToFocusedWindow(state, .saveCollection)

            case .file(.saveCollectionAs):
                return sendCommandToFocusedWindow(state, .saveCollectionAs)

            case .window, .view, .edit:
                return handleMenuCommandAction(action, state: state)

            case let .event(.windowBecameKey(id)):
                guard state.windows[id: id] != nil,
                      !state.closingWindowIDs.contains(id)
                else { return .none }
                state.focusedWindowID = id
                state.moveWindowToMRUFront(id)
                state.refreshContentTabMoveTargets()
                // 포커스 소유권을 각 윈도우 reducer의 isFocused에 반영한다.
                // 프로세스 전역 Quick Look 동기화는 포커스된 윈도우의 활성 탭만 수행하도록 백그라운드 윈도우는 unfocus 처리한다.
                let windowIDs = Array(state.windows.ids)
                let closingWindowIDs = state.closingWindowIDs
                for windowID in windowIDs {
                    let isFocused = windowID == id && !closingWindowIDs.contains(windowID)
                    state.windows[id: windowID]?.window.isFocused = isFocused
                }
                guard state.windows[id: id]?.window.content.entryViewLayout.selectedIds.isEmpty == false
                else {
                    return .none
                }
                return .send(.windows(.element(
                    id: id,
                    action: .window(.content(.entryViewLayout(.delegate(.selectionChanged)))),
                )))

            case let .event(.windowResignedKey(id)):
                let dismissEffect = state.windows[id: id]?.window.contentTabSwitcherPresentation == nil
                    ? Effect<Action>.none
                    : sendCommandToWindow(state, id: id, command: .dismissContentTabSwitcher)
                if state.focusedWindowID == id {
                    state.focusedWindowID = nil
                }
                state.windows[id: id]?.window.isFocused = false
                return dismissEffect

            case let .windowOpenCompleted(id, shouldBootstrapDefaultWindow, isRegistered):
                guard state.pendingWindowOpenIDs.contains(id),
                      state.windows[id: id] != nil,
                      !state.closingWindowIDs.contains(id)
                else { return .none }
                guard isRegistered else {
                    state.closingWindowIDs.insert(id)
                    return finalizePendingWindowClose(
                        id,
                        state: &state,
                        preservingTrackedNativeOpen: state.trackedSingletonWindow?.windowID == id,
                    )
                }
                state.pendingWindowOpenIDs.remove(id)
                state.refreshContentTabMoveTargets()
                guard shouldBootstrapDefaultWindow else { return .none }
                return defaultWindowBootstrapEffectIfNeeded(for: id, state: &state)

            case let .defaultWindowBootstrapRequested(id):
                return handleDefaultWindowBootstrapRequested(id, state: &state)

            case let .windowReadyToOpen(id):
                return readyToOpenWindow(id, state: &state)

            case let .pendingWindowCloseFinalized(id):
                return finalizePendingWindowClose(id, state: &state)

            case let .windowInvalidationFinished(id, result):
                guard state.closingWindowIDs.contains(id) else { return .none }
                guard result.succeeded else {
                    state.invalidatingWindowIDs.remove(id)
                    return .none
                }
                return finalizeWindowRemoval(id, state: &state)

            case .finalizeDeferredWindowClosures:
                return finalizeDeferredWindowClosuresWithoutPendingPersistence(state: &state)

            case let .event(.windowClosed(id)):
                if topNavigationPersistenceParticipantWindowIDs(in: state).contains(id) {
                    return deferWindowRemovalUntilTopNavigationPersistenceCompletes(id, state: &state)
                }
                guard state.windows[id: id] != nil else {
                    return .run { [fileManagerWindowClient] _ in
                        await fileManagerWindowClient.finalizeClose(id)
                    }
                }
                return invalidateWindowBeforeFinalization(id, state: &state)

            case let .event(.focusWindow(path)):
                return .run { _ in
                    await fileManagerWindowClient.focusPath(path)
                }

            case let .trackedSingleton(command):
                return handleTrackedSingletonCommand(command, state: &state)

            case let .trackedSingletonNativeOpenCompleted(requestID):
                guard state.authorizedTrackedSingletonRequestID == requestID else { return .none }
                state.authorizedTrackedSingletonRequestID = nil
                return trackedSingletonCompletionEffect(requestID)

            case let .placement(.plan(request)):
                return .send(.delegate(.externalOpenPlacementCompleted(.init(
                    batchID: request.batchID,
                    result: ExternalOpenPlacementPlanner.make(request, state: state, generateUUID: uuid()),
                ))))

            case let .placement(.apply(plan, reservationsByItemID)):
                guard state.authorizedExternalOpenBatchID == plan.batchID else { return .none }
                return applyExternalOpenPlacement(
                    plan,
                    reservationsByItemID: reservationsByItemID,
                    state: &state,
                )
                .cancellable(id: CancelID.externalOpenBatch(plan.batchID), cancelInFlight: true)

            case let .placement(.activate(plan)):
                guard state.authorizedExternalOpenBatchID == plan.batchID else { return .none }
                return startExternalOpenActivation(
                    plan: plan,
                    excluding: [],
                    state: &state,
                )

            case let .placement(.cancel(batchID)):
                return cancelExternalOpenPlacement(batchID: batchID, state: &state)

            case let .externalOpenActivationResult(attempt, result):
                guard state.authorizedExternalOpenBatchID == attempt.batchID,
                      state.externalOpenActivationAttempt == attempt
                else { return .none }
                switch result {
                case .discarded:
                    return retryExternalOpenActivation(after: attempt, state: &state)

                case .becameKey:
                    let survivingWindowID = ExternalOpenPlacementApplication.lastSurvivingWindowID(
                        for: attempt.plan,
                        state: state,
                        excluding: attempt.excludedWindowIDs,
                    )
                    guard survivingWindowID == attempt.windowID else {
                        return retryExternalOpenActivation(after: attempt, state: &state)
                    }
                    state.authorizedExternalOpenBatchID = nil
                    state.externalOpenActivationAttempt = nil
                    return .send(.delegate(.externalOpenActivationCompleted(batchID: attempt.batchID)))
                }

            case let .contentTabMoveRequest(request):
                return handleContentTabMoveRequest(request, state: &state)

            case let .contentTabMoveLifecycleCompleted(request):
                guard state.contentTabMoveTransactions[request.requestID]?.request == request else {
                    return .none
                }
                guard state.contentTabMoveActivationAttempts[request.requestID]?.request != request else {
                    return .none
                }
                state.contentTabMoveTransactions[request.requestID] = nil
                clearContentTabMoveParticipant(request, state: &state)
                return finalizeDeferredWindowClosuresWithoutPendingPersistence(state: &state)

            case let .contentTabMoveWindowActionRequested(request, windowID, action):
                guard state.contentTabMoveTransactions[request.requestID]?.request == request,
                      isWindowReady(windowID, state: state)
                else { return .none }
                return .send(.windows(.element(id: windowID, action: .window(action))))

            case let .contentTabMoveNativeEffectsRequested(request):
                return startContentTabMoveNativeEffects(request, state: &state)

            case let .contentTabMoveActivationResult(attempt, _):
                guard state.contentTabMoveActivationAttempts[attempt.requestID] == attempt else {
                    return .none
                }
                state.contentTabMoveActivationAttempts[attempt.requestID] = nil
                state.contentTabMoveTransactions[attempt.requestID] = nil
                clearContentTabMoveParticipant(attempt.request, state: &state)
                return finalizeDeferredWindowClosuresWithoutPendingPersistence(state: &state)

            case .refreshContentTabMoveTargets:
                state.refreshContentTabMoveTargets()
                return .none

            case let .windows(.element(
                id: targetWindowID,
                action: .window(.delegate(.receiveContentTabDrag(payload))),
            )):
                guard ContentTabDragPayload.isSupported(schemaVersion: payload.schemaVersion),
                      payload.sourceWindowID != targetWindowID,
                      isWindowReady(payload.sourceWindowID, state: state),
                      isWindowReady(targetWindowID, state: state)
                else { return .none }
                return .send(.windows(.element(
                    id: payload.sourceWindowID,
                    action: .window(.sidebar(.view(.moveContentTabs(
                        payload: payload,
                        targetWindowID: targetWindowID,
                    )))),
                )))

            case let .windows(.element(
                id: targetWindowID,
                action: .window(.delegate(.receiveContentTabExplicitDomainDrag(payload, targetDomain, placement))),
            )):
                // 외부 창 explicit same/opposite-domain 경계 drop도 preserve-domain transfer와 동일하게
                // source 창의 canonical moveContentTabs로 route한다. target domain/placement만 추가로 실어
                // 동일한 ContentTabMoveRequest lifecycle/coordinator를 재사용한다.
                guard ContentTabDragPayload.isSupported(schemaVersion: payload.schemaVersion),
                      payload.sourceWindowID != targetWindowID,
                      isWindowReady(payload.sourceWindowID, state: state),
                      isWindowReady(targetWindowID, state: state)
                else { return .none }
                return .send(.windows(.element(
                    id: payload.sourceWindowID,
                    action: .window(.sidebar(.view(.moveContentTabs(
                        payload: payload,
                        targetWindowID: targetWindowID,
                        targetDomain: targetDomain,
                        placement: placement,
                    )))),
                )))

            case let .windows(.element(
                id: _,
                action: .window(.delegate(.requestContentTabMove(request))),
            )):
                return .send(.contentTabMoveRequest(request))

            case let .windows(.element(id: _, action: .window(.delegate(.openPathInNewWindow(path))))):
                return .send(.file(.newWindow(path: path)))

            case let .windows(.element(id: id, action: .window(.delegate(.closeWindow)))):
                return closeWindow(id, state: &state)

            case let .windows(.element(
                id: sourceWindowID,
                action: .window(.delegate(.fixedLocationVisibilityChanged(hiddenIDs))),
            )):
                return .merge(
                    state.windows.ids
                        .filter { $0 != sourceWindowID }
                        .map { windowID in
                            .send(.windows(.element(
                                id: windowID,
                                action: .window(.applyHiddenFixedLocationIDs(hiddenIDs)),
                            )))
                        },
                )

            case let .windows(.element(
                id: sourceWindowID,
                action: .window(.delegate(.persistTopNavigationMove(
                    token: token,
                    source: source,
                    destination: destination,
                    discoveredLocationIDs: discoveredLocationIDs,
                ))),
            )):
                return .send(.topNavigationPersistenceRequested(.init(
                    sourceWindowID: sourceWindowID,
                    token: token,
                    operation: .move(
                        source: source,
                        destination: destination,
                        discoveredLocationIDs: discoveredLocationIDs,
                    ),
                )))

            case let .windows(.element(
                id: sourceWindowID,
                action: .window(.delegate(.persistTopNavigationPinnedGroupMove(
                    token: token,
                    orderedIDs: orderedIDs,
                    destination: destination,
                    discoveredLocationIDs: discoveredLocationIDs,
                ))),
            )):
                return .send(.topNavigationPersistenceRequested(.init(
                    sourceWindowID: sourceWindowID,
                    token: token,
                    operation: .movePinnedGroup(
                        orderedIDs: orderedIDs,
                        destination: destination,
                        discoveredLocationIDs: discoveredLocationIDs,
                    ),
                )))

            case let .windows(.element(
                id: sourceWindowID,
                action: .window(.delegate(.persistPinnedRecordMutation(
                    token: token,
                    source: source,
                    request: request,
                    discoveredLocationIDs: discoveredLocationIDs,
                ))),
            )):
                return .send(.topNavigationPersistenceRequested(.init(
                    sourceWindowID: sourceWindowID,
                    token: token,
                    operation: .pinnedRecord(
                        source: source,
                        request: request,
                        discoveredLocationIDs: discoveredLocationIDs,
                    ),
                )))

            case let .topNavigationPersistenceRequested(request):
                return enqueueTopNavigationPersistence(request, state: &state)

            case let .topNavigationMovePersistenceCompleted(sourceWindowID, token, terminal):
                return completeTopNavigationMovePersistence(
                    sourceWindowID: sourceWindowID,
                    token: token,
                    terminal: terminal,
                    state: state,
                )

            case let .topNavigationPersistenceCompleted(result):
                return completeTopNavigationPersistence(result, state: &state)

            case .pinnedContentTabsStoreChanged:
                return handlePinnedContentTabsStoreChanged(state: &state)

            case let .defaultWindowBootstrapCompleted(requestID, result):
                return handleDefaultWindowBootstrapCompleted(requestID, result: result, state: &state)

            case let .defaultWindowBootstrapFailed(requestID):
                return handleDefaultWindowBootstrapFailed(requestID, state: &state)

            case let .windows(.element(id: _, action: .window(.inspector(.setInspectorWidth(width))))):
                state.appPreferences.inspectorWidth = max(FileManagerInspectorLayoutMetrics.minWidth, width)
                return .none

            case let .windows(.element(
                id: id,
                action: .window(.delegate(.requestAttachmentPicker(originSessionID))),
            )):
                return requestAttachmentPicker(for: id, originSessionID: originSessionID)

            case .windows(.element(id: _, action: .window(.delegate(.openAISettings)))):
                return .send(.delegate(.openAISettings))

            case let .windows(.element(id: _, action: action)):
                switch action {
                case .window(.contentTabs),
                     .window(.internal(.aiChatTabTitleUpdated)),
                     .window(.tabContent(tabID: _, action: .aiChat)),
                     .window(.inspector(.aiChat)):
                    return .send(.refreshContentTabMoveTargets)
                default:
                    return .none
                }

            case .delegate, .windows:
                return .none
            }
        }
        .forEach(\.windows, action: \.windows) {
            WindowSessionFeature()
        }
    }
}

private extension WindowManagerFeature {
    func requestAttachmentPicker(
        for windowID: WindowManagerState.WindowID,
        originSessionID: AiChatSessionID,
    ) -> Effect<Action> {
        .run { [attachmentPickerClient] send in
            let urls = await attachmentPickerClient.pickAttachments()
            guard !urls.isEmpty else { return }
            let action = await MainActor.run {
                Action.windows(.element(
                    id: windowID,
                    action: .window(.inspector(.aiChat(.attachmentPickerSelection(originSessionID, urls)))),
                ))
            }
            await send(action)
        }
    }
}

extension WindowManagerFeature {
    func handleMenuCommandAction(_ action: Action, state: State) -> Effect<Action> {
        switch action {
        case .window:
            handleWindowMenuCommand(action, state: state)
        case .view:
            handleViewMenuCommand(action, state: state)
        case .edit(.cut), .edit(.copy), .edit(.paste), .edit(.duplicate),
             .edit(.makeAlias), .edit(.selectAll), .edit(.copyAbsolutePaths), .edit(.copyURLs):
            handleEditClipboardMenuCommand(action, state: state)
        case .edit:
            handleEditMenuCommand(action, state: state)
        default:
            .none
        }
    }

    func handleWindowMenuCommand(_ action: Action, state: State) -> Effect<Action> {
        switch action {
        case .window(.goBack):
            sendCommandToFocusedWindow(state, .goBack)

        case .window(.goForward):
            sendCommandToFocusedWindow(state, .goForward)

        case .window(.goToEnclosingDirectory):
            sendCommandToFocusedWindow(state, .goToEnclosingDirectory)

        case .window(.toggleSidebar):
            sendCommandToFocusedWindow(state, .toggleSidebar)

        case .window(.toggleShowHiddenFiles):
            sendCommandToFocusedWindow(state, .toggleShowHiddenFiles)

        default:
            .none
        }
    }

    func handleViewMenuCommand(_ action: Action, state: State) -> Effect<Action> {
        switch action {
        case let .view(.setViewLayout(layout)):
            sendCommandToFocusedWindow(state, .setViewLayout(layout))

        case let .view(.setGroupKey(key)):
            sendCommandToFocusedWindow(state, .setGroupKey(key))

        case let .view(.setSortKey(key)):
            sendCommandToFocusedWindow(state, .setSortKey(key))

        case let .view(.setSortOrder(order)):
            sendCommandToFocusedWindow(state, .setSortOrder(order))

        default:
            .none
        }
    }

    func handleEditMenuCommand(_ action: Action, state: State) -> Effect<Action> {
        switch action {
        case .edit(.requestUndo):
            sendCommandToFocusedWindow(state, .requestUndo)

        case .edit(.requestRedo):
            sendCommandToFocusedWindow(state, .requestRedo)

        case .edit(.find):
            routeFindCommand(state)

        case .edit(.toggleComposer):
            sendCommandToFocusedWindow(state, .toggleComposer)

        case .edit(.openChat):
            sendCommandToFocusedWindow(state, .reopenChat)

        case .edit(.showChatHistory):
            sendCommandToFocusedWindow(state, .showChatHistory)

        default:
            .none
        }
    }

    func handleEditClipboardMenuCommand(_ action: Action, state: State) -> Effect<Action> {
        switch action {
        case .edit(.cut):
            sendCommandToFocusedWindow(state, .cut)

        case .edit(.copy):
            sendCommandToFocusedWindow(state, .copy)

        case .edit(.paste):
            sendCommandToFocusedWindow(state, .paste)

        case .edit(.duplicate):
            sendCommandToFocusedWindow(state, .duplicate)

        case .edit(.makeAlias):
            sendCommandToFocusedWindow(state, .makeAlias)

        case .edit(.selectAll):
            sendCommandToFocusedWindow(state, .selectAll)

        case .edit(.copyAbsolutePaths):
            sendCommandToFocusedWindow(state, .copyAbsolutePaths)

        case .edit(.copyURLs):
            sendCommandToFocusedWindow(state, .copyURLs)

        default:
            .none
        }
    }
}
