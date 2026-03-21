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

            case let .content(.delegate(.openPathInNewWindow(path))):
                .send(.delegate(.openPathInNewWindow(path)))

            case let .content(.delegate(.openPathInNewTab(path))):
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

        if let effect = handleEntryRequestPathDependent(command, currentPath: currentPath) {
            return effect
        }

        if let effect = handleEntryRequestSelection(command, state: state) {
            return effect
        }

        if let effect = handleEntryRequestEditing(command, state: state) {
            return effect
        }

        if let effect = handleEntryRequestCopying(command, state: state) {
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
    ) -> Effect<Action>? {
        switch command {
        case .newFolder:
            let defaultName = "untitled folder"
            return .send(.content(.entryOperations(.createNewFolder(name: defaultName, parentPath: currentPath))))
        case .paste:
            return .send(.content(.entryOperations(.pasteItemsFromClipboard(destinationPath: currentPath))))
        default:
            return nil
        }
    }

    private func handleEntryRequestSelection(_ command: Action.WindowCommand, state: State) -> Effect<Action>? {
        let context = EntryOperationsCommandContext(
            selectedIds: state.content.entryViewLayout.selectedIds,
            displayItems: state.content.entryOperations.displayOrderItems,
            currentPath: state.content.navigation.currentPath,
        )
        switch command {
        case .openSelectedItem:
            return .send(.content(.entryOperations(.executeCommand(
                command: .navigation(.openSelectedItem),
                context: context,
            ))))
        case .quickLookSelectedItem:
            return .send(.content(.entryOperations(.executeCommand(
                command: .navigation(.quickLookSelectedItem),
                context: context,
            ))))
        case .selectAll:
            return .send(.content(.view(.selectAllEntries)))
        default:
            return nil
        }
    }

    private func handleEntryRequestEditing(_ command: Action.WindowCommand, state: State) -> Effect<Action>? {
        let context = EntryOperationsCommandContext(
            selectedIds: state.content.entryViewLayout.selectedIds,
            displayItems: state.content.entryOperations.displayOrderItems,
            currentPath: state.content.navigation.currentPath,
        )
        switch command {
        case .cut:
            return .send(.content(.entryOperations(.executeCommand(
                command: .clipboard(.cutSelectedItems),
                context: context,
            ))))
        case .copy:
            return .send(.content(.entryOperations(.executeCommand(
                command: .clipboard(.copySelectedItems),
                context: context,
            ))))
        case .duplicate:
            return .send(.content(.entryOperations(.executeCommand(
                command: .clipboard(.duplicateSelectedItems),
                context: context,
            ))))
        case .makeAlias:
            return .send(.content(.entryOperations(.executeCommand(
                command: .mutation(.createAliasForSelectedItems),
                context: context,
            ))))
        default:
            return nil
        }
    }

    private func handleEntryRequestCopying(_ command: Action.WindowCommand, state: State) -> Effect<Action>? {
        let context = EntryOperationsCommandContext(
            selectedIds: state.content.entryViewLayout.selectedIds,
            displayItems: state.content.entryOperations.displayOrderItems,
            currentPath: state.content.navigation.currentPath,
        )
        switch command {
        case .copyAbsolutePaths:
            return .send(.content(.entryOperations(.executeCommand(
                command: .clipboard(.copySelectedAbsolutePaths),
                context: context,
            ))))
        case .copyURLs:
            return .send(.content(.entryOperations(.executeCommand(
                command: .clipboard(.copySelectedURLs),
                context: context,
            ))))
        default:
            return nil
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
            .send(.sidebar(.view(.setSidebarVisible(!state.sidebar.sidebarVisible))))
        case let .setViewLayout(layout):
            .send(.content(.view(.changeLayout(layout))))
        case let .setGroupKey(key):
            .send(.content(.entryArrangements(.setGroupKey(key))))
        case let .setSortKey(key):
            .send(.content(.entryArrangements(.setSortKey(key))))
        case let .setSortOrder(order):
            .send(.content(.entryArrangements(.setSortOrder(order))))
        default:
            .none
        }
    }

    private func handleUndoRedoRequest(_ command: Action.WindowCommand) -> Effect<Action> {
        switch command {
        case .requestUndo:
            .send(.content(.entryOperations(.requestUndo)))
        case .requestRedo:
            .send(.content(.entryOperations(.requestRedo)))
        default:
            .none
        }
    }
}
