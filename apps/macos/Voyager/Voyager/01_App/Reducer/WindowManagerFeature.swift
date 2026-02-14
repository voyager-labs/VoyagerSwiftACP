import ComposableArchitecture
import Foundation

typealias FileManagerWindowFeature = FileManagerFeature

@Reducer
struct WindowManagerFeature {
    typealias State = WindowManagerState
    typealias Action = WindowManagerAction

    @Dependency(\.onboardingWindowClient)
    private var onboardingWindowClient

    @Dependency(\.fileManagerWindowClient)
    private var fileManagerWindowClient

    @Dependency(\.uuid)
    private var uuid

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .openInitialWindowIfNeeded:
                guard state.windows.isEmpty else { return .none }
                return .send(.newWindow(path: nil))

            case let .reopenWindowIfNeeded(hasVisibleWindows: flag):
                if !flag, state.windows.isEmpty {
                    return .send(.newWindow(path: nil))
                }
                return .none

            case .newWindow,
                 .newTab,
                 .closeFocusedWindow,
                 .closeAllWindows:
                return handleWindowCommand(action, state: &state)

            case .newFolder:
                return sendActionToFocusedWindow(state) { focused in
                    .content(.entries(.createNewFolder(currentPath: focused.window.content.navigation.currentPath)))
                }

            case .open:
                return sendActionToFocusedWindow(state, .content(.entries(.openSelectedItem)))

            case .quickLook:
                return sendActionToFocusedWindow(state, .content(.entries(.quickLookSelectedItem)))

            case .saveCollection:
                return sendActionToFocusedWindow(state, .content(.composer(.saveCollection)))

            case .saveCollectionAs:
                return sendActionToFocusedWindow(state, .content(.composer(.saveCollectionAs)))

            case .goBack:
                return sendActionToFocusedWindow(state, .navigation(.goBack))

            case .goForward:
                return sendActionToFocusedWindow(state, .navigation(.goForward))

            case .goToEnclosingDirectory:
                return sendActionToFocusedWindow(state, .navigation(.goToEnclosingDirectory))

            case .toggleSidebar:
                return sendActionToFocusedWindow(state) { focused in
                    .sidebar(.setSidebarVisible(!focused.window.sidebar.sidebarVisible))
                }

            case .toggleShowHiddenFiles:
                return sendActionToFocusedWindow(state, .content(.entries(.toggleShowHiddenFiles)))

            case let .setViewLayout(layout):
                return sendActionToFocusedWindow(state, .content(.changeLayout(layout)))

            case let .setGroupKey(key):
                return sendActionToFocusedWindow(state, .content(.entryArrangements(.setGroupKey(key))))

            case let .setSortKey(key):
                return sendActionToFocusedWindow(state, .content(.entryArrangements(.setSortKey(key))))

            case let .setSortOrder(order):
                return sendActionToFocusedWindow(state, .content(.entryArrangements(.setSortOrder(order))))

            case .requestUndo:
                return sendActionToFocusedWindow(state, .content(.entryOperations(.requestUndo)))

            case .requestRedo:
                return sendActionToFocusedWindow(state, .content(.entryOperations(.requestRedo)))

            case .toggleComposer:
                return sendActionToFocusedWindow(state) { focused in
                    .content(.composer(.setPresented(!focused.window.content.composer.isPresented)))
                }

            case .cut:
                return sendActionToFocusedWindow(state, .content(.entries(.cutSelectedItems)))

            case .copy:
                return sendActionToFocusedWindow(state, .content(.entries(.copySelectedItems)))

            case .paste:
                return sendActionToFocusedWindow(state) { focused in
                    .content(.entries(.pasteItems(destinationPath: focused.window.content.navigation.currentPath)))
                }

            case .duplicate:
                return sendActionToFocusedWindow(state, .content(.entries(.duplicateSelectedItems)))

            case .makeAlias:
                return sendActionToFocusedWindow(state, .content(.entries(.createAliasForSelectedItems)))

            case .selectAll:
                return sendActionToFocusedWindow(state, .content(.entries(.selectAll)))

            case .copyAbsolutePaths:
                return sendActionToFocusedWindow(state, .content(.entries(.copySelectedAbsolutePaths)))

            case .copyURLs:
                return sendActionToFocusedWindow(state, .content(.entries(.copySelectedURLs)))

            case let .windowBecameKey(id):
                state.focusedWindowID = id
                return .none

            case let .windowResignedKey(id):
                if state.focusedWindowID == id {
                    state.focusedWindowID = nil
                }
                return .none

            case let .windowClosed(id):
                let wasFocused = state.focusedWindowID == id
                state.windows.remove(id: id)
                if wasFocused {
                    state.focusedWindowID = state.windows.first?.id
                }
                return .none

            case let .focusWindow(path):
                return .run { _ in
                    await fileManagerWindowClient.focusPath(path)
                }

            case .windows:
                return .none
            }
        }
        .forEach(\.windows, action: \.windows) {
            WindowSessionFeature()
        }
    }

    private func handleWindowCommand(_ action: Action, state: inout State) -> Effect<Action> {
        switch action {
        case let .newWindow(path):
            if onboardingWindowClient.showIfNeeded() {
                return .none
            }
            let id = uuid()
            var windowState = FileManagerWindowFeature.State()
            windowState.content.entryOperations.windowID = id
            if let path {
                windowState.content.navigation.navigationState =
                    FileManagerNavigationUtils.NavigationState.folder(path)
                windowState.content.navigation.titlePath = path
            }

            state.windows.append(.init(id: id, window: windowState))
            state.focusedWindowID = id

            return .run { [id] _ in
                await fileManagerWindowClient.open(id)
            }

        case let .newTab(path):
            if onboardingWindowClient.showIfNeeded() {
                return .none
            }
            let id = uuid()
            var windowState = FileManagerWindowFeature.State()
            windowState.content.entryOperations.windowID = id
            if let path {
                windowState.content.navigation.navigationState =
                    FileManagerNavigationUtils.NavigationState.folder(path)
                windowState.content.navigation.titlePath = path
            }

            state.windows.append(.init(id: id, window: windowState))
            state.focusedWindowID = id

            return .run { [id] _ in
                await fileManagerWindowClient.openTab(id)
            }

        case .closeFocusedWindow:
            guard let id = state.focusedWindowID else { return .none }
            return .run { [id] _ in
                await fileManagerWindowClient.close(id)
            }

        case .closeAllWindows:
            state.windows.removeAll()
            state.focusedWindowID = nil
            return .run { _ in
                await fileManagerWindowClient.closeAll()
            }

        default:
            return .none
        }
    }

    private func focusedWindow(_ state: State) -> WindowSessionState? {
        guard let id = state.focusedWindowID else { return nil }
        return state.windows[id: id]
    }

    private func sendActionToFocusedWindow(
        _ state: State,
        _ windowAction: FileManagerWindowAction,
    ) -> Effect<Action> {
        guard let focused = focusedWindow(state) else { return .none }
        return .send(.windows(.element(id: focused.id, action: .window(windowAction))))
    }

    private func sendActionToFocusedWindow(
        _ state: State,
        _ buildAction: (WindowSessionState) -> FileManagerWindowAction,
    ) -> Effect<Action> {
        guard let focused = focusedWindow(state) else { return .none }
        return .send(.windows(.element(id: focused.id, action: .window(buildAction(focused)))))
    }
}

@Reducer
struct WindowSessionFeature {
    @ObservableState
    struct State: Equatable, Identifiable {
        var id: UUID
        var window: FileManagerWindowFeature.State
    }

    @CasePathable
    enum Action: Sendable {
        case window(FileManagerWindowFeature.Action)
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.window, action: \.window) {
            FileManagerWindowFeature()
        }

        Reduce { _, action in
            switch action {
            case .window:
                .none
            }
        }
    }
}

typealias WindowSessionState = WindowSessionFeature.State
