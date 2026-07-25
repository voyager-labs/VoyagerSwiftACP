import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesAiChat

struct FileManagerAiChatInspectorOpenCancelID: Hashable {}
struct FileManagerAiChatNewChatSeedCancelID: Hashable {}

extension FileManagerWindowCommandRoutingReducer {
    func handleAiChatInspectorRequest(
        destination: FileManagerAiChatInspectorDestination,
        state: inout State,
    ) -> Effect<Action> {
        if isInspectorChatPresented(state, destination: destination) {
            state.pendingAiChatInspectorOpen = nil
            state.pendingAiChatNewChat = nil
            return .concatenate(
                .cancel(id: FileManagerAiChatInspectorOpenCancelID()),
                .cancel(id: FileManagerAiChatNewChatSeedCancelID()),
                .send(.inspector(.closeChat)),
            )
        }

        if isInspectorChatPresented(state) {
            return switchPresentedAiChatInspectorDestination(destination, state: &state)
        }

        if let pendingOpen = state.pendingAiChatInspectorOpen,
           pendingOpen.destination == destination,
           pendingOpen.tabID == state.contentTabs.activeTabID
        {
            state.pendingAiChatInspectorOpen = nil
            state.pendingAiChatNewChat = nil
            return .cancel(id: FileManagerAiChatInspectorOpenCancelID())
        }

        return openAiChatInspectorEffect(state: &state, destination: destination)
    }

    private func switchPresentedAiChatInspectorDestination(
        _ destination: FileManagerAiChatInspectorDestination,
        state: inout State,
    ) -> Effect<Action> {
        state.pendingAiChatInspectorOpen = nil
        let destinationEffect: Effect<Action>
        switch destination {
        case .newChat:
            let snapshot = FileManagerAiChatContextAdapter.makeCurrentContextSnapshot(content: state.content)
            let preparationEffect = AiChatFeature().reduce(
                into: &state.inspector.aiChat,
                action: .prepareUnpersistedNewChatWithContext(snapshot),
            )
            state.syncActiveTabInspectorState()
            destinationEffect = .concatenate(
                preparationEffect.map { .inspector(.aiChat($0)) },
                beginAiChatNewChatSeedResolution(
                    target: .inspector(
                        snapshot: snapshot,
                        provenance: state.inspector.aiChat.newChatPreparationProvenance,
                    ),
                    state: &state,
                ),
            )
        case .chatHistory:
            state.pendingAiChatNewChat = nil
            destinationEffect = .send(.inspector(.showChatHistoryRequested))
        case .reopenChat:
            destinationEffect = .none
        }
        return .concatenate(
            .cancel(id: FileManagerAiChatInspectorOpenCancelID()),
            destination == .chatHistory
                ? .cancel(id: FileManagerAiChatNewChatSeedCancelID())
                : .none,
            destinationEffect,
        )
    }

    func handleAiChatInspectorOpenCompletion(
        requestID: UUID,
        destination: FileManagerAiChatInspectorDestination,
        setup: AiChatSetupState,
        connectionsFile: AIConnectionsFile,
        state: inout State,
    ) -> Effect<Action> {
        guard let pendingOpen = state.pendingAiChatInspectorOpen,
              pendingOpen.requestID == requestID,
              pendingOpen.destination == destination,
              pendingOpen.resumeSessionID == (setup.sessionID ?? setup.restoreSessionID)
        else { return .none }

        let resumeProvenanceMatches = pendingOpen.resumeProvenance.map { provenance in
            if pendingOpen.preservesLiveRuntime {
                return state.inspector.aiChat.matchesInspectorLiveRuntimeReopenProvenance(provenance)
            }
            return state.inspector.aiChat.matchesInspectorNewChatPreparationProvenance(provenance)
        } ?? true
        guard state.contentTabs.activeTabID == pendingOpen.tabID,
              state.supportsInspector(tabID: pendingOpen.tabID),
              resumeProvenanceMatches
        else {
            state.pendingAiChatInspectorOpen = nil
            return .none
        }

        let destinationEffect: Effect<Action>
        switch destination {
        case .newChat:
            destinationEffect = .send(.inspector(.openNewChat(setup, connectionsFile)))
        case .chatHistory:
            state.pendingAiChatInspectorOpen = nil
            destinationEffect = .send(.inspector(.openChatHistory(setup, connectionsFile)))
        case .reopenChat:
            state.pendingAiChatInspectorOpen = nil
            destinationEffect = .send(.inspector(.openChat(setup, connectionsFile)))
        }
        return destinationEffect
    }

    func beginAiChatNewChatAfterInspectorOpen(
        state: inout State,
        requiresCatalogRefresh: Bool,
    ) -> Effect<Action> {
        guard let pendingOpen = state.pendingAiChatInspectorOpen,
              pendingOpen.destination == .newChat,
              pendingOpen.tabID == state.contentTabs.activeTabID
        else { return .none }

        return beginAiChatNewChatSeedResolution(
            target: .inspector(
                snapshot: FileManagerAiChatContextAdapter.makeCurrentContextSnapshot(content: state.content),
                provenance: state.inspector.aiChat.newChatPreparationProvenance,
            ),
            state: &state,
            requestID: pendingOpen.requestID,
            requiresCatalogRefresh: requiresCatalogRefresh,
        )
    }

    func beginContentAiChatNewChatSeedResolution(state: inout State) -> Effect<Action> {
        guard let tabID = state.contentTabs.activeTabID,
              let anchor = state.contentTabs.tabs[id: tabID]?.anchor
        else { return .none }
        return beginAiChatNewChatSeedResolution(
            target: .content(
                expectedAnchor: anchor,
                provenance: state.content.aiChat.newChatPreparationProvenance,
            ),
            state: &state,
        )
    }

    func beginHomeContentAiChatNewChatSeedResolution(
        sessionID: AiChatSessionID,
        state: inout State,
    ) -> Effect<Action> {
        guard let tabID = state.contentTabs.activeTabID,
              let anchor = state.contentTabs.tabs[id: tabID]?.anchor
        else { return .none }
        return beginAiChatNewChatSeedResolution(
            target: .homeContent(
                expectedSessionID: sessionID,
                expectedAnchor: anchor,
                provenance: state.content.aiChat.newChatPreparationProvenance,
            ),
            state: &state,
        )
    }

    func handleAiChatNewChatDefaultsLoaded(
        requestID: UUID,
        candidate: AiChatPersistedSelectionCandidate?,
        state: inout State,
    ) -> Effect<Action> {
        guard var pending = validatedPendingAiChatNewChat(state: &state, requestID: requestID) else {
            return .none
        }
        pending.persistedDefault = candidate
        pending.didLoadPersistedDefault = true
        state.pendingAiChatNewChat = pending
        return finishAiChatNewChatSeedResolutionIfReady(state: &state)
    }

    func handleAiChatNewChatCatalogRefresh(
        targetKind: FileManagerAiChatNewChatTargetKind,
        state: inout State,
        requestID: UUID? = nil,
    ) -> Effect<Action> {
        guard var pending = validatedPendingAiChatNewChat(state: &state),
              pending.target.kind == targetKind
        else { return .none }

        if let requestID {
            guard pending.expectedModelListRequestID == requestID else { return .none }
        } else {
            pending.didObserveCatalogRefresh = true
            pending.expectedModelListRequestID = aiChatState(for: pending.target, state: state).modelListRequestID
            state.pendingAiChatNewChat = pending
        }
        return finishAiChatNewChatSeedResolutionIfReady(state: &state)
    }

    func cancelAiChatNewChatSeedResolution(state: inout State) -> Effect<Action> {
        state.pendingAiChatNewChat = nil
        return .cancel(id: FileManagerAiChatNewChatSeedCancelID())
    }

    private func beginAiChatNewChatSeedResolution(
        target: FileManagerAiChatNewChatTarget,
        state: inout State,
        requestID: UUID? = nil,
        requiresCatalogRefresh: Bool = false,
    ) -> Effect<Action> {
        guard let tabID = state.contentTabs.activeTabID,
              isValid(target: target, tabID: tabID, state: state)
        else { return .none }

        let requestID = requestID ?? uuid()
        let targetState = aiChatState(for: target, state: state)
        state.pendingAiChatNewChat = FileManagerPendingAiChatNewChat(
            requestID: requestID,
            tabID: tabID,
            target: target,
            windowLast: state.lastExplicitAiChatSelection.map {
                AiChatNewChatSelectionCandidate(
                    modelHandle: $0.modelHandle,
                    selectedThinking: $0.thinking,
                )
            },
            persistedDefault: nil,
            didLoadPersistedDefault: false,
            requiresCatalogRefresh: requiresCatalogRefresh,
            didObserveCatalogRefresh: !requiresCatalogRefresh,
            expectedModelListRequestID: targetState.modelListRequestID,
        )
        return .run { [aiChatDefaultSettingsClient] send in
            let candidate = persistedCandidate(from: aiChatDefaultSettingsClient.load())
            await send(.internal(.aiChatNewChatDefaultsLoaded(
                requestID: requestID,
                candidate: candidate,
            )))
        }
        .cancellable(id: FileManagerAiChatNewChatSeedCancelID(), cancelInFlight: true)
    }

    private func finishAiChatNewChatSeedResolutionIfReady(state: inout State) -> Effect<Action> {
        guard let pending = validatedPendingAiChatNewChat(state: &state),
              pending.didLoadPersistedDefault,
              !pending.requiresCatalogRefresh || pending.didObserveCatalogRefresh,
              let catalog = resolvedCatalog(for: pending, state: state)
        else { return .none }

        let seed = AiChatNewChatSelectionSeedResolver.resolve(
            windowLast: pending.windowLast,
            persistedDefault: pending.persistedDefault,
            catalog: catalog,
        )
        state.pendingAiChatNewChat = nil

        switch pending.target {
        case let .inspector(snapshot, provenance):
            if state.pendingAiChatInspectorOpen?.requestID == pending.requestID {
                state.pendingAiChatInspectorOpen = nil
            }
            return .send(.internal(.applyInspectorNewChatSeed(.init(
                tabID: pending.tabID,
                snapshot: snapshot,
                provenance: provenance,
                applicationProvenance: state.inspector.aiChat.newChatPreparationProvenance,
                seed: seed,
            ))))

        case let .content(expectedAnchor, provenance):
            return .send(.internal(.applyContentNewChatSeed(.init(
                tabID: pending.tabID,
                expectedAnchor: expectedAnchor,
                sessionID: nil,
                provenance: provenance,
                seed: seed,
            ))))

        case let .homeContent(expectedSessionID, expectedAnchor, provenance):
            return .send(.internal(.applyContentNewChatSeed(.init(
                tabID: pending.tabID,
                expectedAnchor: expectedAnchor,
                sessionID: expectedSessionID,
                provenance: provenance,
                seed: seed,
            ))))
        }
    }

    func applyContentNewChatSeed(
        _ application: FileManagerContentNewChatSeedApplication,
        state: inout State,
    ) -> Effect<Action> {
        let target: FileManagerAiChatNewChatTarget
        let childAction: AiChatAction
        if let sessionID = application.sessionID {
            target = .homeContent(
                expectedSessionID: sessionID,
                expectedAnchor: application.expectedAnchor,
                provenance: application.provenance,
            )
            childAction = .prepareTransientNewChatIfCurrent(
                sessionID: sessionID,
                provenance: application.provenance,
                seed: application.seed,
            )
        } else {
            target = .content(
                expectedAnchor: application.expectedAnchor,
                provenance: application.provenance,
            )
            childAction = .newChatTappedIfCurrent(
                provenance: application.provenance,
                seed: application.seed,
            )
        }
        guard state.contentTabs.activeTabID == application.tabID,
              isValid(target: target, tabID: application.tabID, state: state)
        else { return .none }
        return reduceContentAiChat(action: childAction, state: &state)
    }

    func applyInspectorNewChatSeed(
        _ application: FileManagerInspectorNewChatSeedApplication,
        state: inout State,
    ) -> Effect<Action> {
        let target = FileManagerAiChatNewChatTarget.inspector(
            snapshot: application.snapshot,
            provenance: application.provenance,
        )
        guard state.contentTabs.activeTabID == application.tabID,
              isValid(target: target, tabID: application.tabID, state: state)
        else { return .none }
        let childAction = AiChatAction.applyNewChatSelectionSeedIfCurrent(
            provenance: application.applicationProvenance,
            seed: application.seed,
        )
        let effect = AiChatFeature().reduce(into: &state.inspector.aiChat, action: childAction)
        state.syncActiveTabInspectorState()
        return effect.map { .inspector(.aiChat($0)) }
    }

    private func reduceContentAiChat(
        action: AiChatAction,
        state: inout State,
    ) -> Effect<Action> {
        let effect = AiChatFeature().reduce(into: &state.content.aiChat, action: action)
        state.syncActiveTabContentState()
        return effect.map { .content(.aiChat($0)) }
    }

    private func validatedPendingAiChatNewChat(
        state: inout State,
        requestID: UUID? = nil,
    ) -> FileManagerPendingAiChatNewChat? {
        guard let pending = state.pendingAiChatNewChat,
              requestID == nil || pending.requestID == requestID,
              state.contentTabs.activeTabID == pending.tabID,
              isValid(target: pending.target, tabID: pending.tabID, state: state)
        else {
            if requestID == nil || state.pendingAiChatNewChat?.requestID == requestID {
                let invalidRequestID = state.pendingAiChatNewChat?.requestID
                state.pendingAiChatNewChat = nil
                if state.pendingAiChatInspectorOpen?.requestID == invalidRequestID {
                    state.pendingAiChatInspectorOpen = nil
                }
            }
            return nil
        }
        return pending
    }

    private func isValid(
        target: FileManagerAiChatNewChatTarget,
        tabID: ContentTabID,
        state: State,
    ) -> Bool {
        switch target {
        case let .inspector(_, provenance):
            state.supportsInspector(tabID: tabID)
                && state.inspector.activeMode == .chat
                && state.inspector.aiChat.matchesInspectorNewChatPreparationProvenance(provenance)
        case let .content(expectedAnchor, provenance):
            state.contentTabs.tabs[id: tabID]?.anchor == expectedAnchor
                && state.content.aiChat.newChatPreparationProvenance == provenance
        case let .homeContent(expectedSessionID, expectedAnchor, provenance):
            isValidHomeContentTarget(
                expectedSessionID: expectedSessionID,
                expectedAnchor: expectedAnchor,
                provenance: provenance,
                tabID: tabID,
                state: state,
            )
        }
    }

    private func isValidHomeContentTarget(
        expectedSessionID: AiChatSessionID,
        expectedAnchor: ContentTabPageAnchor,
        provenance: AiChatNewChatPreparationProvenance,
        tabID: ContentTabID,
        state: State,
    ) -> Bool {
        guard state.contentTabs.tabs[id: tabID]?.anchor == expectedAnchor,
              case let .aiChat(anchorSessionID) = expectedAnchor,
              let anchorUUID = UUID(uuidString: anchorSessionID),
              anchorUUID == expectedSessionID.rawValue
        else { return false }

        let aiChat = state.content.aiChat
        return aiChat.newChatPreparationProvenance == provenance
            && aiChat.sessionID == expectedSessionID
            && aiChat.mode == .chat
            && aiChat.sessionStatus == .idle
            && aiChat.restoreSessionID == nil
            && aiChat.restoreOutcome == nil
            && aiChat.restoreFailure == nil
            && aiChat.transcriptHistory.isEmpty
            && aiChat.draftText.isEmpty
            && aiChat.addedAttachments.isEmpty
            && aiChat.streamingAssistantDraft == nil
            && aiChat.selectedModelHandle == nil
            && aiChat.selectedThinking == nil
            && aiChat.pendingRequestStart == nil
            && aiChat.emptyDraftSessionID == nil
            && (aiChat.preparedTransientSessionID == nil
                || aiChat.preparedTransientSessionID == expectedSessionID)
            && aiChat.executionPhase == .idle
    }

    private func aiChatState(
        for target: FileManagerAiChatNewChatTarget,
        state: State,
    ) -> AiChatFeature.State {
        switch target {
        case .inspector:
            state.inspector.aiChat
        case .content:
            state.content.aiChat
        case .homeContent:
            state.content.aiChat
        }
    }

    private func resolvedCatalog(
        for pending: FileManagerPendingAiChatNewChat,
        state: State,
    ) -> [AiProviderModel]? {
        switch aiChatState(for: pending.target, state: state).modelListState {
        case let .loaded(models):
            models
        case .empty, .failed:
            []
        case .idle, .loading:
            nil
        }
    }

    private func isInspectorChatPresented(_ state: State) -> Bool {
        state.inspector.inspectorVisible && state.inspector.activeMode == .chat
    }

    private func isInspectorChatPresented(
        _ state: State,
        destination: FileManagerAiChatInspectorDestination,
    ) -> Bool {
        guard isInspectorChatPresented(state) else { return false }
        switch destination {
        case .newChat:
            return state.inspector.aiChat.mode == .chat
        case .chatHistory:
            return state.inspector.aiChat.mode == .sessions
        case .reopenChat:
            return state.inspector.aiChat.mode == .chat
        }
    }

    func handleAiChatReopenRequest(state: inout State) -> Effect<Action> {
        if isInspectorChatPresented(state, destination: .reopenChat)
            || state.pendingAiChatInspectorOpen.map({
                $0.destination == .reopenChat && $0.tabID == state.contentTabs.activeTabID
            }) == true
        {
            return handleAiChatInspectorRequest(destination: .reopenChat, state: &state)
        }
        guard let sessionID = reopenCandidate(in: state.inspector.aiChat) else {
            return handleAiChatInspectorRequest(destination: .newChat, state: &state)
        }
        return openAiChatInspectorEffect(
            state: &state,
            destination: .reopenChat,
            resumeSessionID: sessionID,
        )
    }

    private func openAiChatInspectorEffect(
        state: inout State,
        destination: FileManagerAiChatInspectorDestination,
        resumeSessionID: AiChatSessionID? = nil,
    ) -> Effect<Action> {
        guard let activeTabID = state.contentTabs.activeTabID,
              state.supportsInspector(tabID: activeTabID)
        else {
            state.pendingAiChatInspectorOpen = nil
            return .cancel(id: FileManagerAiChatInspectorOpenCancelID())
        }

        let requestID = uuid()
        let resumeProvenance = resumeSessionID.map { _ in state.inspector.aiChat.newChatPreparationProvenance }
        let preservesLiveRuntime = resumeSessionID.map {
            state.inspector.aiChat.lifecycleSessionIDsToPreserve.contains($0)
        } ?? false
        state.pendingAiChatInspectorOpen = FileManagerPendingAiChatInspectorOpen(
            requestID: requestID,
            tabID: activeTabID,
            destination: destination,
            resumeSessionID: resumeSessionID,
            resumeProvenance: resumeProvenance,
            preservesLiveRuntime: preservesLiveRuntime,
        )
        var setup = FileManagerAiChatContextAdapter.makeAiChatSetupState(content: state.content)
        switch destination {
        case .newChat:
            setup.mode = .chat
        case .chatHistory:
            setup.mode = .sessions
        case .reopenChat:
            setup.mode = .chat
            if preservesLiveRuntime {
                setup.sessionID = resumeSessionID
                setup.restoreSessionID = nil
            } else {
                setup.sessionID = nil
                setup.restoreSessionID = resumeSessionID
            }
        }
        return loadAiChatInspectorEffect(
            requestID: requestID,
            destination: destination,
            setup: setup,
        )
    }

    private func loadAiChatInspectorEffect(
        requestID: UUID,
        destination: FileManagerAiChatInspectorDestination,
        setup: AiChatSetupState,
    ) -> Effect<Action> {
        .run { [aiConnectionsFileClient, setup] send in
            let connectionsFile: AIConnectionsFile
            do {
                connectionsFile = try await aiConnectionsFileClient.load()
            } catch {
                connectionsFile = .empty()
            }

            switch destination {
            case .newChat:
                await send(.internal(.aiChatNewChatInspectorOpenLoaded(
                    requestID: requestID,
                    setup: setup,
                    connectionsFile: connectionsFile,
                )))
            case .chatHistory:
                await send(.internal(.aiChatHistoryInspectorOpenLoaded(
                    requestID: requestID,
                    setup: setup,
                    connectionsFile: connectionsFile,
                )))
            case .reopenChat:
                await send(.internal(.aiChatReopenInspectorOpenLoaded(
                    requestID: requestID,
                    setup: setup,
                    connectionsFile: connectionsFile,
                )))
            }
        }
        .cancellable(id: FileManagerAiChatInspectorOpenCancelID(), cancelInFlight: true)
    }

    private func reopenCandidate(in aiChat: AiChatFeature.State) -> AiChatSessionID? {
        guard aiChat.mode == .chat,
              let sessionID = aiChat.sessionID,
              aiChat.sessionStatus == .active,
              aiChat.restoreSessionID == nil || aiChat.restoreSessionID == sessionID,
              aiChat.deferredChatSessionRestoreID == nil,
              aiChat.preparedTransientSessionID != sessionID,
              aiChat.emptyDraftSessionID != sessionID,
              !aiChat.isUntouchedPreparedTransientNewChat,
              !aiChat.hiddenEmptyDraftSessionIDs.contains(sessionID),
              !aiChat.sessionList.deletedSessionIDs.contains(sessionID)
        else { return nil }
        return sessionID
    }
}

private extension FileManagerAiChatNewChatTarget {
    var kind: FileManagerAiChatNewChatTargetKind {
        switch self {
        case .inspector:
            .inspector
        case .content, .homeContent:
            .content
        }
    }
}

private func persistedCandidate(from settings: AiChatDefaultSettings) -> AiChatPersistedSelectionCandidate? {
    guard settings.provider != nil || settings.model != nil else { return nil }
    let thinking: AiChatPersistedThinkingSelection = switch settings.thinking {
    case .providerDefault:
        .providerDefault
    case .none:
        .none
    case let .effort(value):
        .effort(value)
    case let .tokenBudget(value):
        .tokenBudget(value)
    }
    return AiChatPersistedSelectionCandidate(
        providerRawValue: settings.provider?.rawValue,
        modelProviderRawValue: settings.model?.providerRawValue,
        modelRawValue: settings.model?.modelRawValue,
        thinking: thinking,
    )
}
