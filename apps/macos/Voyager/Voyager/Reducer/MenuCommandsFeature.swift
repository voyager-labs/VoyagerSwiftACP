import ComposableArchitecture
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesUpdateVersion

@Reducer
struct MenuCommandsFeature {
    typealias State = MenuCommandsState
    typealias Action = MenuCommandsAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .view(.app(.newTab)):
                guard state.canOpenNewContentTab else { return .none }
                return routeAppCommand(.newTab)

            case .view(.app(.closeTab)):
                guard state.canCloseTab else { return .none }
                return routeAppCommand(.closeTab)

            case .view(.app(.togglePinTab)):
                guard state.canPinTab else { return .none }
                return routeAppCommand(.togglePinTab)

            case .view(.app(.restoreLastClosedTab)):
                guard state.canRestoreLastClosedTab else { return .none }
                return routeAppCommand(.restoreLastClosedTab)

            case .view(.app(.duplicateTab)):
                let canDuplicate = state.selectedContentTabCount > 1
                    ? state.canDuplicateSelectedContentTabs
                    : state.canDuplicateActiveContentTab
                guard canDuplicate else { return .none }
                return routeAppCommand(.duplicateTab)

            case let .view(.app(command)):
                return routeAppCommand(command)

            case let .view(.viewCommand(command)):
                return routeViewCommand(command)

            case let .view(.edit(command)):
                return routeEditCommand(command)

            case .view:
                return .none

            case .delegate:
                return .none
            }
        }
    }

    private func routeAppCommand(_ command: MenuCommandItem.AppCommand) -> Effect<Action> {
        routeFileAppCommand(command)
            ?? routeFileOperationAppCommand(command)
            ?? routeWindowAppCommand(command)
            ?? routeUpdaterAppCommand(command)
            ?? .none
    }

    private func routeViewCommand(_ command: MenuCommandItem.ViewCommand) -> Effect<Action> {
        switch command {
        case .toggleSidebar:
            .send(.delegate(.windowManager(.window(.toggleSidebar))))
        case .toggleShowHiddenFiles:
            .send(.delegate(.windowManager(.window(.toggleShowHiddenFiles))))
        case let .setViewLayout(layout):
            .send(.delegate(.windowManager(.view(.setViewLayout(layout)))))
        case let .setGroupKey(key):
            .send(.delegate(.windowManager(.view(.setGroupKey(key)))))
        case let .setSortKey(key):
            .send(.delegate(.windowManager(.view(.setSortKey(key)))))
        case let .setSortOrder(order):
            .send(.delegate(.windowManager(.view(.setSortOrder(order)))))
        }
    }

    private func routeEditCommand(_ command: MenuCommandItem.EditCommand) -> Effect<Action> {
        routePrimaryEditCommand(command)
            ?? routeAiChatEditCommand(command)
            ?? routeClipboardEditCommand(command)
            ?? .none
    }

    private func routeFileAppCommand(_ command: MenuCommandItem.AppCommand) -> Effect<Action>? {
        switch command {
        case let .newWindow(path): .send(.delegate(.windowManager(.file(.newWindow(path: path)))))
        case .newTab: .send(.delegate(.windowManager(.file(.newTab))))
        case .closeTab: .send(.delegate(.windowManager(.file(.closeTab))))
        case .togglePinTab: .send(.delegate(.windowManager(.file(.togglePinTab))))
        case .restoreLastClosedTab: .send(.delegate(.windowManager(.file(.restoreLastClosedTab))))
        case .duplicateTab: .send(.delegate(.windowManager(.file(.duplicateTab))))
        default: nil
        }
    }

    private func routeFileOperationAppCommand(_ command: MenuCommandItem.AppCommand) -> Effect<Action>? {
        switch command {
        case .newFolder: .send(.delegate(.windowManager(.file(.newFolder))))
        case .open: .send(.delegate(.windowManager(.file(.open))))
        case .quickLook: .send(.delegate(.windowManager(.file(.quickLook))))
        case .saveCollection: .send(.delegate(.windowManager(.file(.saveCollection))))
        case .saveCollectionAs: .send(.delegate(.windowManager(.file(.saveCollectionAs))))
        default: nil
        }
    }

    private func routeWindowAppCommand(_ command: MenuCommandItem.AppCommand) -> Effect<Action>? {
        switch command {
        case .closeFocusedWindow: .send(.delegate(.windowManager(.window(.closeFocusedWindow))))
        case .closeAllWindows: .send(.delegate(.windowManager(.window(.closeAllWindows))))
        case .goBack: .send(.delegate(.windowManager(.window(.goBack))))
        case .goForward: .send(.delegate(.windowManager(.window(.goForward))))
        case .goToEnclosingDirectory: .send(.delegate(.windowManager(.window(.goToEnclosingDirectory))))
        default: nil
        }
    }

    private func routeUpdaterAppCommand(_ command: MenuCommandItem.AppCommand) -> Effect<Action>? {
        switch command {
        case .checkForUpdates: .send(.delegate(.updater(.checkForUpdates)))
        case let .setAutomaticUpdate(enabled): .send(.delegate(.updater(.setAutomaticUpdate(enabled))))
        default: nil
        }
    }

    private func routePrimaryEditCommand(_ command: MenuCommandItem.EditCommand) -> Effect<Action>? {
        switch command {
        case .requestUndo: .send(.delegate(.windowManager(.edit(.requestUndo))))
        case .requestRedo: .send(.delegate(.windowManager(.edit(.requestRedo))))
        case .toggleComposer: .send(.delegate(.windowManager(.edit(.toggleComposer))))
        case .cut: .send(.delegate(.windowManager(.edit(.cut))))
        case .copy: .send(.delegate(.windowManager(.edit(.copy))))
        case .paste: .send(.delegate(.windowManager(.edit(.paste))))
        default: nil
        }
    }

    private func routeAiChatEditCommand(_ command: MenuCommandItem.EditCommand) -> Effect<Action>? {
        switch command {
        case .newChat: .send(.delegate(.windowManager(.edit(.newChat))))
        case .showChatHistory: .send(.delegate(.windowManager(.edit(.showChatHistory))))
        default: nil
        }
    }

    private func routeClipboardEditCommand(_ command: MenuCommandItem.EditCommand) -> Effect<Action>? {
        switch command {
        case .duplicate: .send(.delegate(.windowManager(.edit(.duplicate))))
        case .makeAlias: .send(.delegate(.windowManager(.edit(.makeAlias))))
        case .selectAll: .send(.delegate(.windowManager(.edit(.selectAll))))
        case .copyAbsolutePaths: .send(.delegate(.windowManager(.edit(.copyAbsolutePaths))))
        case .copyURLs: .send(.delegate(.windowManager(.edit(.copyURLs))))
        default: nil
        }
    }
}
