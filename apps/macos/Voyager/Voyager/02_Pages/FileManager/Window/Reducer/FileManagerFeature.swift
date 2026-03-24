import ComposableArchitecture
import Foundation

@Reducer
struct FileManagerFeature {
    typealias State = FileManagerWindowState
    typealias Action = FileManagerWindowAction

    var body: some Reducer<State, Action> {
        Scope(state: \.content, action: \.content) {
            FileManagerContentFeature()
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

        FileManagerWindowNavigationReducer()

        FileManagerWindowLifecycleReducer()
        FileManagerWindowPreferencesReducer()
        FileManagerWindowRoutingReducer()

        Reduce { state, action in
            switch action {
            case let .request(command):
                handleRequestedCommand(command, state: &state)

            case let .content(.openPathInNewWindow(path)):
                .send(.delegate(.openPathInNewWindow(path)))

            case let .content(.openPathInNewTab(path)):
                .send(.delegate(.openPathInNewTab(path)))

            default:
                .none
            }
        }
    }

    private func handleRequestedCommand(_ command: Action.WindowCommand, state: inout State) -> Effect<Action> {
        switch command {
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
            handleEntryRequest(command, state: &state)

        case .saveCollection,
             .saveCollectionAs,
             .toggleComposer:
            handleComposerRequest(command, state: &state)

        case .goBack,
             .goForward,
             .goToEnclosingDirectory:
            handleNavigationRequest(command)

        case .toggleSidebar,
             .setViewLayout,
             .setGroupKey,
             .setSortKey,
             .setSortOrder:
            handleLayoutRequest(command, state: &state)

        case .requestUndo,
             .requestRedo:
            handleUndoRedoRequest(command)
        }
    }

    private func handleEntryRequest(_ command: Action.WindowCommand, state: inout State) -> Effect<Action> {
        let currentPath = state.content.navigation.currentPath

        if let effect = handleEntryRequestPathDependent(command, currentPath: currentPath, state: &state) {
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
        currentPath: String,
        state _: inout State,
    ) -> Effect<Action>? {
        switch command {
        case .newFolder:
            .send(.content(.entryViewLayout(.entryOperations(.createNewFolder(parentPath: currentPath)))))
        case .paste:
            .send(.content(.entryViewLayout(.delegate(.executeCommand(.clipboard(
                .pasteItems(destinationPath: currentPath),
            ))))))
        default:
            nil
        }
    }

    private func handleEntryRequestSelection(_ command: Action.WindowCommand, state: State) -> Effect<Action>? {
        switch command {
        case .openSelectedItem:
            guard state.content.hasSelectableEntriesInLayout else { return .none }
            return .send(.content(.entryViewLayout(.delegate(.executeCommand(.navigation(.openSelectedItem))))))
        case .quickLookSelectedItem:
            guard state.content.hasSelectableEntriesInLayout else { return .none }
            return .send(.content(.entryViewLayout(.delegate(.executeCommand(.navigation(.quickLookSelectedItem))))))
        case .selectAll:
            return .send(.content(.selectAllEntries))
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
            .send(.content(.toggleShowHiddenFilesAndReload))
        default:
            nil
        }
    }

    private func handleComposerRequest(_ command: Action.WindowCommand, state: inout State) -> Effect<Action> {
        switch command {
        case .saveCollection:
            .send(.content(.composer(.saveCollection)))
        case .saveCollectionAs:
            .send(.content(.composer(.saveCollectionAs)))
        case .toggleComposer:
            .send(.content(.composer(.setPresented(!state.content.composer.isPresented))))
        default:
            .none
        }
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
            .send(.sidebar(.setSidebarVisible(!state.sidebar.sidebarVisible)))
        case let .setViewLayout(layout):
            .send(.content(.changeLayout(layout)))
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
            .send(.content(.entryViewLayout(.entryOperations(.requestUndo))))
        case .requestRedo:
            .send(.content(.entryViewLayout(.entryOperations(.requestRedo))))
        default:
            .none
        }
    }
}
