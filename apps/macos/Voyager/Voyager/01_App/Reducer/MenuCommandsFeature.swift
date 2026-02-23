import ComposableArchitecture

@Reducer
struct MenuCommandsFeature {
    typealias State = MenuCommandsState
    typealias Action = MenuCommandsAction

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            case let .view(.app(command)):
                routeAppCommand(command)

            case let .view(.viewCommand(command)):
                routeViewCommand(command)

            case let .view(.edit(command)):
                routeEditCommand(command)

            case .view:
                .none

            case .delegate:
                .none
            }
        }
    }

    private func routeAppCommand(_ command: MenuCommandItem.AppCommand) -> Effect<Action> {
        switch command {
        case let .newWindow(path):
            .send(.delegate(.windowManager(.newWindow(path: path))))
        case let .newTab(path):
            .send(.delegate(.windowManager(.newTab(path: path))))
        case .newFolder:
            .send(.delegate(.windowManager(.newFolder)))
        case .open:
            .send(.delegate(.windowManager(.open)))
        case .quickLook:
            .send(.delegate(.windowManager(.quickLook)))
        case .saveCollection:
            .send(.delegate(.windowManager(.saveCollection)))
        case .saveCollectionAs:
            .send(.delegate(.windowManager(.saveCollectionAs)))
        case .closeFocusedWindow:
            .send(.delegate(.windowManager(.closeFocusedWindow)))
        case .closeAllWindows:
            .send(.delegate(.windowManager(.closeAllWindows)))
        case .goBack:
            .send(.delegate(.windowManager(.goBack)))
        case .goForward:
            .send(.delegate(.windowManager(.goForward)))
        case .goToEnclosingDirectory:
            .send(.delegate(.windowManager(.goToEnclosingDirectory)))
        case .checkForUpdates:
            .send(.delegate(.updater(.checkForUpdates)))
        case let .setAutomaticUpdate(enabled):
            .send(.delegate(.updater(.setAutomaticUpdate(enabled))))
        }
    }

    private func routeViewCommand(_ command: MenuCommandItem.ViewCommand) -> Effect<Action> {
        switch command {
        case .toggleSidebar:
            .send(.delegate(.windowManager(.toggleSidebar)))
        case .toggleShowHiddenFiles:
            .send(.delegate(.windowManager(.toggleShowHiddenFiles)))
        case let .setViewLayout(layout):
            .send(.delegate(.windowManager(.setViewLayout(layout))))
        case let .setGroupKey(key):
            .send(.delegate(.windowManager(.setGroupKey(key))))
        case let .setSortKey(key):
            .send(.delegate(.windowManager(.setSortKey(key))))
        case let .setSortOrder(order):
            .send(.delegate(.windowManager(.setSortOrder(order))))
        }
    }

    private func routeEditCommand(_ command: MenuCommandItem.EditCommand) -> Effect<Action> {
        switch command {
        case .requestUndo:
            .send(.delegate(.windowManager(.requestUndo)))
        case .requestRedo:
            .send(.delegate(.windowManager(.requestRedo)))
        case .toggleComposer:
            .send(.delegate(.windowManager(.toggleComposer)))
        case .cut:
            .send(.delegate(.windowManager(.cut)))
        case .copy:
            .send(.delegate(.windowManager(.copy)))
        case .paste:
            .send(.delegate(.windowManager(.paste)))
        case .duplicate:
            .send(.delegate(.windowManager(.duplicate)))
        case .makeAlias:
            .send(.delegate(.windowManager(.makeAlias)))
        case .selectAll:
            .send(.delegate(.windowManager(.selectAll)))
        case .copyAbsolutePaths:
            .send(.delegate(.windowManager(.copyAbsolutePaths)))
        case .copyURLs:
            .send(.delegate(.windowManager(.copyURLs)))
        }
    }
}
