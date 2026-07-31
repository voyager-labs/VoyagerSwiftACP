import ComposableArchitecture
import Foundation
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerWidgetsEntryViewLayout

@Reducer
public struct FileManagerFeature {
    public typealias State = FileManagerWindowState
    public typealias Action = FileManagerWindowAction

    public init() {}

    @Dependency(\.fileOperationUndoManagerClient)
    private var fileOperationUndoManagerClient

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .content(contentAction):
                guard let activeTabID = state.contentTabs.activeTabID,
                      state.contentTabs.tabs[id: activeTabID] != nil
                else { return .none }
                return .send(.tabContent(tabID: activeTabID, action: contentAction))

            case let .tabContent(tabID, contentAction):
                guard state.contentTabs.tabs[id: tabID] != nil else { return .none }

                let generation = undoManagerGeneration(tabID: tabID, state: state)
                let isActiveTab = state.contentTabs.activeTabID == tabID
                guard var contentState = isActiveTab ? state.content : state.tabContentStates[tabID] else {
                    return .none
                }
                let effect = FileManagerContentFeature().reduce(
                    into: &contentState,
                    action: contentAction,
                )
                if isActiveTab {
                    state.content = contentState
                }
                state.tabContentStates[tabID] = contentState
                return effect.map {
                    Self.routeContentEffectAction(
                        $0,
                        tabID: tabID,
                        undoManagerGeneration: generation,
                    )
                }

            case let .contentTabs(.setCurrent(targetTabID)):
                guard let activeTabID = state.contentTabs.activeTabID,
                      state.contentTabs.tabs[id: targetTabID] != nil,
                      targetTabID != activeTabID
                else { return .none }
                return .merge(
                    .send(.tabContent(
                        tabID: activeTabID,
                        action: .entryOperations(.loading(.cancelAllFolderItems)),
                    )),
                    .send(.tabContent(
                        tabID: activeTabID,
                        action: .entryViewLayout(.internal(.cancelCollectionMaterialization)),
                    )),
                )

            case let .contentTabs(.close(tabID)):
                guard let content = fileManagerContentState(for: tabID, state: state) else { return .none }
                let entryOperations = content.entryOperations
                let folderCancellationEffects = entryOperations.folderLoadingContexts.keys.map { requestID in
                    Effect<Action>.cancel(id: EntryOperationsFolderLoadingCancelID.loadFolderItems(
                        requestID: requestID,
                        windowID: entryOperations.windowID,
                        ownerID: entryOperations.loadingCancellationOwnerID,
                    ))
                }
                let appendCancellationEffects = content.entryViewLayout
                    .activeCollectionAppendExpectedBatchIndices.keys.map { token in
                        Effect<Action>.cancel(id: EntryViewLayoutCollectionCancelID.append(
                            token: token,
                            windowID: entryOperations.windowID,
                            ownerID: entryOperations.loadingCancellationOwnerID,
                        ))
                    }
                return .merge(folderCancellationEffects + appendCancellationEffects + [
                    .cancel(id: EntryViewLayoutCollectionCancelID.replace(
                        windowID: entryOperations.windowID,
                        ownerID: entryOperations.loadingCancellationOwnerID,
                    )),
                ])

            case let .internal(.entryActionCompleted(tabID, record, expectedGeneration)):
                guard record.operationKind.isUndoable,
                      let expectedGeneration,
                      undoManagerGeneration(tabID: tabID, state: state) == expectedGeneration,
                      state.contentTabs.tabs[id: tabID] != nil,
                      let windowID = state.windowID
                else { return .none }

                let scope = UndoManagerScope(windowID: windowID, contentTabID: tabID.rawValue)
                guard fileOperationUndoManagerClient.registerUndo(scope, expectedGeneration, record) else {
                    clearLogicalUndoHistory(tabID: tabID, state: &state)
                    return .none
                }

                let isActiveTab = state.contentTabs.activeTabID == tabID
                guard var contentState = isActiveTab ? state.content : state.tabContentStates[tabID] else {
                    return .none
                }
                let effect = FileManagerContentFeature().reduce(
                    into: &contentState,
                    action: .entryOperations(.lifecycle(.entryActionCompleted(record))),
                )
                if isActiveTab {
                    state.content = contentState
                }
                state.tabContentStates[tabID] = contentState
                return effect.map { .tabContent(tabID: tabID, action: $0) }

            default:
                return .none
            }
        }

        Scope(state: \.content.navigation, action: \.navigation) {
            ContentPageNavigationFeature()
        }

        Scope(state: \.sidebar, action: \.sidebar) {
            FileManagerSidebarFeature()
        }

        Scope(state: \.inspector, action: \.inspector) {
            FileManagerInspectorFeature()
        }

        Scope(state: \.contentTabs, action: \.contentTabs) {
            ContentTabFeature()
        }

        FileManagerWindowAiChatSelectionReducer()

        FileManagerWindowNavigationReducer()
        FileManagerWindowLifecycleReducer()
        FileManagerWindowPreferencesReducer()
        FileManagerWindowRoutingReducer()
        FileManagerWindowUndoRoutingReducer()
        FileManagerWindowCommandRoutingReducer()
    }

    private func clearLogicalUndoHistory(tabID: ContentTabID, state: inout State) {
        let isActiveTab = state.contentTabs.activeTabID == tabID
        guard var contentState = isActiveTab ? state.content : state.tabContentStates[tabID] else { return }
        contentState.entryOperations.undoRecords.removeAll()
        contentState.entryOperations.redoRecords.removeAll()
        if isActiveTab {
            state.content = contentState
        }
        state.tabContentStates[tabID] = contentState
    }

    private func undoManagerGeneration(
        tabID: ContentTabID,
        state: State,
    ) -> FileOperationUndoManagerClient.Generation? {
        guard let windowID = state.windowID else { return nil }
        return fileOperationUndoManagerClient.generation(UndoManagerScope(
            windowID: windowID,
            contentTabID: tabID.rawValue,
        ))
    }

    private static func completedEntryActionRecord(
        from action: FileManagerContentAction,
    ) -> EntryActionRecord? {
        guard case let .entryOperations(.lifecycle(.entryActionCompleted(record))) = action else { return nil }
        return record
    }

    private static func routeContentEffectAction(
        _ action: FileManagerContentAction,
        tabID: ContentTabID,
        undoManagerGeneration: FileOperationUndoManagerClient.Generation?,
    ) -> Action {
        guard let record = completedEntryActionRecord(from: action) else {
            return .tabContent(tabID: tabID, action: action)
        }
        return .internal(.entryActionCompleted(
            tabID: tabID,
            record: record,
            undoManagerGeneration: undoManagerGeneration,
        ))
    }
}

func fileManagerContentState(
    for tabID: ContentTabID,
    state: FileManagerWindowState,
) -> FileManagerContentFeature.State? {
    state.contentTabs.activeTabID == tabID ? state.content : state.tabContentStates[tabID]
}
