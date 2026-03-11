import ComposableArchitecture
import Foundation
import VoyagerPagesOnboarding

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
                guard !flag else { return .none }

                if state.windows.isEmpty {
                    return .send(.newWindow(path: nil))
                }

                guard let reopenWindowID = state.focusedWindowID ?? state.windows.first?.id else {
                    return .none
                }

                state.focusedWindowID = reopenWindowID
                return .run { [fileManagerWindowClient, reopenWindowID] _ in
                    await fileManagerWindowClient.open(reopenWindowID)
                }

            case let .applyAppPreferences(preferences):
                state.appPreferences = preferences
                return .merge(
                    state.windows.ids.map { id in
                        .send(.windows(.element(id: id, action: .window(.applyAppPreferences(preferences)))))
                    },
                )

            case .newWindow,
                 .newTab,
                 .closeFocusedWindow,
                 .closeAllWindows:
                return handleWindowCommand(action, state: &state)

            case .newFolder:
                return sendCommandToFocusedWindow(state, .newFolder)

            case .open:
                return sendCommandToFocusedWindow(state, .openSelectedItem)

            case .quickLook:
                return sendCommandToFocusedWindow(state, .quickLookSelectedItem)

            case .saveCollection:
                return sendCommandToFocusedWindow(state, .saveCollection)

            case .saveCollectionAs:
                return sendCommandToFocusedWindow(state, .saveCollectionAs)

            case .goBack:
                return sendCommandToFocusedWindow(state, .goBack)

            case .goForward:
                return sendCommandToFocusedWindow(state, .goForward)

            case .goToEnclosingDirectory:
                return sendCommandToFocusedWindow(state, .goToEnclosingDirectory)

            case .toggleSidebar:
                return sendCommandToFocusedWindow(state, .toggleSidebar)

            case .toggleShowHiddenFiles:
                return sendCommandToFocusedWindow(state, .toggleShowHiddenFiles)

            case let .setViewLayout(layout):
                return sendCommandToFocusedWindow(state, .setViewLayout(layout))

            case let .setGroupKey(key):
                return sendCommandToFocusedWindow(state, .setGroupKey(key))

            case let .setSortKey(key):
                return sendCommandToFocusedWindow(state, .setSortKey(key))

            case let .setSortOrder(order):
                return sendCommandToFocusedWindow(state, .setSortOrder(order))

            case .requestUndo:
                return sendCommandToFocusedWindow(state, .requestUndo)

            case .requestRedo:
                return sendCommandToFocusedWindow(state, .requestRedo)

            case .toggleComposer:
                return sendCommandToFocusedWindow(state, .toggleComposer)

            case .cut:
                return sendCommandToFocusedWindow(state, .cut)

            case .copy:
                return sendCommandToFocusedWindow(state, .copy)

            case .paste:
                return sendCommandToFocusedWindow(state, .paste)

            case .duplicate:
                return sendCommandToFocusedWindow(state, .duplicate)

            case .makeAlias:
                return sendCommandToFocusedWindow(state, .makeAlias)

            case .selectAll:
                return sendCommandToFocusedWindow(state, .selectAll)

            case .copyAbsolutePaths:
                return sendCommandToFocusedWindow(state, .copyAbsolutePaths)

            case .copyURLs:
                return sendCommandToFocusedWindow(state, .copyURLs)

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

            case let .windows(.element(id: _, action: .window(.delegate(.openPathInNewWindow(path))))):
                return .send(.newWindow(path: path))

            case let .windows(.element(id: _, action: .window(.delegate(.openPathInNewTab(path))))):
                return .send(.newTab(path: path))

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
            let windowSession = makeWindowSession(path: path)

            state.windows.append(windowSession)
            state.focusedWindowID = windowSession.id

            return .concatenate(
                .send(.windows(.element(
                    id: windowSession.id,
                    action: .window(.applyAppPreferences(state.appPreferences)),
                ))),
                .run { [id = windowSession.id] _ in
                    await fileManagerWindowClient.open(id)
                },
            )

        case let .newTab(path):
            if onboardingWindowClient.showIfNeeded() {
                return .none
            }
            let windowSession = makeWindowSession(path: path)

            state.windows.append(windowSession)
            state.focusedWindowID = windowSession.id

            return .concatenate(
                .send(.windows(.element(
                    id: windowSession.id,
                    action: .window(.applyAppPreferences(state.appPreferences)),
                ))),
                .run { [id = windowSession.id] _ in
                    await fileManagerWindowClient.openTab(id)
                },
            )

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

    private func sendCommandToFocusedWindow(
        _ state: State,
        _ command: FileManagerWindowAction.WindowCommand,
    ) -> Effect<Action> {
        guard let id = state.focusedWindowID else { return .none }
        return .send(.windows(.element(id: id, action: .window(.request(command)))))
    }

    private func makeWindowSession(path: String?) -> WindowSessionState {
        let id = uuid()
        let windowState = FileManagerWindowFeature.State.makeInitial(windowID: id, path: path)
        return .init(id: id, window: windowState)
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
