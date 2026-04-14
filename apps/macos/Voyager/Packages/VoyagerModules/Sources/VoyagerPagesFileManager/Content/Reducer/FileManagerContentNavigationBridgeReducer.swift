import ComposableArchitecture
import Foundation

import VoyagerFeaturesEntryOperations
import VoyagerWidgetsEntryViewLayout

@Reducer
public struct FileManagerContentNavigationBridgeReducer {
    public typealias State = FileManagerContentState
    public typealias Action = FileManagerContentAction

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .internal(.applyNavigationState(navigationState)):
                state.entryViewLayout.currentPath = state.navigation.currentPath
                state.entryViewLayout.savedScrollOffset = state.navigation.scrollPositions[state.navigation.currentPath]
                return applyNavigationStateEffect(navigationState, state: state)

            case .view(.toggleShowHiddenFilesAndReload):
                let showHidden = !state.entryViewLayout.showHiddenFiles
                return .concatenate(
                    .send(.entryViewLayout(.view(.toggleShowHiddenFiles))),
                    reloadEntryItemsEffect(
                        navigationState: state.navigation.navigationState,
                        showHidden: showHidden,
                    ),
                )

            default:
                return .none
            }
        }
    }

    func applyNavigationStateEffect(
        _ navigationState: ContentPageNavigationRoute,
        state: State,
    ) -> Effect<Action> {
        switch navigationState {
        case let .folder(path):
            .concatenate(
                .send(.entryViewLayout(.internal(.clearCollectionPresentation))),
                sendEntryOperations(.loading(.loadItems(
                    path: path,
                    showHidden: state.entryViewLayout.showHiddenFiles,
                ))),
            )

        case .recents:
            .concatenate(
                .send(.entryViewLayout(.internal(.clearCollectionPresentation))),
                sendEntryOperations(.loading(.loadRecentItems(
                    showHidden: state.entryViewLayout.showHiddenFiles,
                ))),
            )

        case let .tags(tagName):
            .concatenate(
                .send(.entryViewLayout(.internal(.clearCollectionPresentation))),
                sendEntryOperations(.loading(.loadTagItems(
                    tagName: tagName,
                    showHidden: state.entryViewLayout.showHiddenFiles,
                ))),
            )

        case .computer:
            .concatenate(
                .send(.entryViewLayout(.internal(.clearCollectionPresentation))),
                sendEntryOperations(.loading(.loadComputerItems)),
            )

        case .collection:
            .send(.entryViewLayout(.internal(.setCollectionMode(true))))
        }
    }

    func reloadEntryItemsEffect(state: State) -> Effect<Action> {
        reloadEntryItemsEffect(
            navigationState: state.navigation.navigationState,
            showHidden: state.entryViewLayout.showHiddenFiles,
        )
    }

    func reloadEntryItemsEffect(
        navigationState: ContentPageNavigationRoute,
        showHidden: Bool,
    ) -> Effect<Action> {
        switch navigationState {
        case let .folder(path):
            sendEntryOperations(.loading(.loadItems(path: path, showHidden: showHidden)))
        case .recents:
            sendEntryOperations(.loading(.loadRecentItems(showHidden: showHidden)))
        case let .tags(tagName):
            sendEntryOperations(.loading(.loadTagItems(tagName: tagName, showHidden: showHidden)))
        case .computer:
            sendEntryOperations(.loading(.loadComputerItems))
        case .collection:
            .none
        }
    }

    func sendEntryOperations(_ action: EntryOperationsAction) -> Effect<Action> {
        let forwardedAction = FileManagerContentAction.entryViewLayout(.entryOperations(action))
        return .send(forwardedAction)
    }
}
