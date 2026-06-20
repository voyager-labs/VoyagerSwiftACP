import ComposableArchitecture
import Foundation
import VoyagerFeaturesAiChat
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import VoyagerPagesFileManager
import VoyagerPagesOnboarding
import VoyagerWidgetsEntryViewLayout

typealias FileManagerWindowFeature = FileManagerFeature

@Reducer
struct WindowManagerFeature {
    typealias State = WindowManagerState
    typealias Action = WindowManagerAction

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
    private var onboardingWindowClient

    @Dependency(\.fileManagerWindowClient)
    private var fileManagerWindowClient
    @Dependency(\.attachmentPickerClient)
    private var attachmentPickerClient

    @Dependency(\.uuid)
    private var uuid

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .lifecycle(.openInitialWindowIfNeeded):
                guard state.windows.isEmpty else { return .none }
                return .send(.file(.newWindow(path: nil)))

            case let .lifecycle(.reopenWindowIfNeeded(hasVisibleWindows: flag)):
                guard !flag else { return .none }

                if state.windows.isEmpty {
                    return .send(.file(.newWindow(path: nil)))
                }

                guard let reopenWindowID = state.focusedWindowID ?? state.windows.first?.id else {
                    return .none
                }

                state.focusedWindowID = reopenWindowID
                return .run { [fileManagerWindowClient, reopenWindowID] _ in
                    await fileManagerWindowClient.open(reopenWindowID)
                }

            case let .lifecycle(.applyAppPreferences(preferences)):
                state.appPreferences = preferences
                return .merge(
                    state.windows.map { windowSession in
                        let packagePreferences = windowSession.window.appPreferencesPreservingSidebarState(
                            from: preferences.toPackageState(),
                        )
                        return .send(.windows(.element(
                            id: windowSession.id,
                            action: .window(.applyAppPreferences(packagePreferences)),
                        )))
                    },
                )

            case let .lifecycle(.aiConnectionsFileUpdated(file)):
                return .merge(
                    state.windows.ids.map { id in
                        .send(.windows(.element(id: id, action: .window(.aiConnectionsFileUpdated(file)))))
                    },
                )

            case .file(.newWindow),
                 .file(.newTab),
                 .window(.closeFocusedWindow),
                 .window(.closeAllWindows):
                return handleWindowCommand(action, state: &state)

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

            case .window(.goBack):
                return sendCommandToFocusedWindow(state, .goBack)

            case .window(.goForward):
                return sendCommandToFocusedWindow(state, .goForward)

            case .window(.goToEnclosingDirectory):
                return sendCommandToFocusedWindow(state, .goToEnclosingDirectory)

            case .window(.toggleSidebar):
                return sendCommandToFocusedWindow(state, .toggleSidebar)

            case .window(.toggleShowHiddenFiles):
                return sendCommandToFocusedWindow(state, .toggleShowHiddenFiles)

            case let .view(.setViewLayout(layout)):
                return sendCommandToFocusedWindow(state, .setViewLayout(layout))

            case let .view(.setGroupKey(key)):
                return sendCommandToFocusedWindow(state, .setGroupKey(key))

            case let .view(.setSortKey(key)):
                return sendCommandToFocusedWindow(state, .setSortKey(key))

            case let .view(.setSortOrder(order)):
                return sendCommandToFocusedWindow(state, .setSortOrder(order))

            case .edit(.requestUndo):
                return sendCommandToFocusedWindow(state, .requestUndo)

            case .edit(.requestRedo):
                return sendCommandToFocusedWindow(state, .requestRedo)

            case .edit(.toggleComposer):
                return sendCommandToFocusedWindow(state, .toggleComposer)

            case .edit(.openContextualAiChat):
                return sendCommandToFocusedWindow(state, .openContextualAiChat)

            case .edit(.cut):
                return sendCommandToFocusedWindow(state, .cut)

            case .edit(.copy):
                return sendCommandToFocusedWindow(state, .copy)

            case .edit(.paste):
                return sendCommandToFocusedWindow(state, .paste)

            case .edit(.duplicate):
                return sendCommandToFocusedWindow(state, .duplicate)

            case .edit(.makeAlias):
                return sendCommandToFocusedWindow(state, .makeAlias)

            case .edit(.selectAll):
                return sendCommandToFocusedWindow(state, .selectAll)

            case .edit(.copyAbsolutePaths):
                return sendCommandToFocusedWindow(state, .copyAbsolutePaths)

            case .edit(.copyURLs):
                return sendCommandToFocusedWindow(state, .copyURLs)

            case let .event(.windowBecameKey(id)):
                state.focusedWindowID = id
                return .none

            case let .event(.windowResignedKey(id)):
                if state.focusedWindowID == id {
                    state.focusedWindowID = nil
                }
                return .none

            case let .event(.windowClosed(id)):
                let wasFocused = state.focusedWindowID == id
                state.windows.remove(id: id)
                if wasFocused {
                    state.focusedWindowID = state.windows.first?.id
                }
                return .none

            case let .event(.focusWindow(path)):
                return .run { _ in
                    await fileManagerWindowClient.focusPath(path)
                }

            case let .windows(.element(id: _, action: .window(.delegate(.openPathInNewWindow(path))))):
                return .send(.file(.newWindow(path: path)))

            case let .windows(.element(id: _, action: .window(.delegate(.openPathInNewTab(path))))):
                return .send(.file(.newTab(path: path)))

            case let .windows(.element(id: _, action: .window(.inspector(.setInspectorWidth(width))))):
                state.appPreferences.inspectorWidth = max(FileManagerInspectorLayoutMetrics.minWidth, width)
                return .none

            case let .windows(.element(id: id, action: .window(.delegate(.requestAttachmentPicker)))):
                return requestAttachmentPicker(for: id)

            case .windows(.element(id: _, action: .window(.delegate(.openAISettings)))):
                return .send(.delegate(.openAISettings))

            case .delegate, .windows:
                return .none
            }
        }
        .forEach(\.windows, action: \.windows) {
            WindowSessionFeature()
        }
    }

    private func handleWindowCommand(_ action: Action, state: inout State) -> Effect<Action> {
        switch action {
        case let .file(.newWindow(path, selectEntryID)):
            return openWindowSession(path: path, selectEntryID: selectEntryID, state: &state) { id in
                await fileManagerWindowClient.open(id)
            }

        case let .file(.newTab(path)):
            return openWindowSession(path: path, selectEntryID: nil, state: &state) { id in
                await fileManagerWindowClient.openTab(id)
            }

        case .window(.closeFocusedWindow):
            guard let id = state.focusedWindowID else { return .none }
            return .run { [id] _ in
                await fileManagerWindowClient.close(id)
            }

        case .window(.closeAllWindows):
            state.windows.removeAll()
            state.focusedWindowID = nil
            return .run { _ in
                await fileManagerWindowClient.closeAll()
            }

        default:
            return .none
        }
    }

    private func openWindowSession(
        path: String?,
        selectEntryID: String?,
        state: inout State,
        open: @escaping @Sendable (UUID) async -> Void,
    ) -> Effect<Action> {
        if onboardingWindowClient.showIfNeeded() {
            return .none
        }
        let windowSession = makeWindowSession(path: path, selectEntryID: selectEntryID)

        state.windows.append(windowSession)
        state.focusedWindowID = windowSession.id

        return .concatenate(
            windowIDChangedEffect(for: windowSession.id),
            appPreferencesEffect(for: windowSession.id, preferences: state.appPreferences),
            .run { [id = windowSession.id] _ in
                await open(id)
            },
        )
    }

    private func windowIDChangedEffect(for id: UUID) -> Effect<Action> {
        .send(.windows(.element(
            id: id,
            action: .window(.content(.entryViewLayout(.entryOperations(.lifecycle(.windowIDChanged(id)))))),
        )))
    }

    private func appPreferencesEffect(
        for id: UUID,
        preferences: AppPreferencesFeature.State,
    ) -> Effect<Action> {
        .send(.windows(.element(
            id: id,
            action: .window(.applyAppPreferences(preferences.toPackageState())),
        )))
    }

    private func sendCommandToFocusedWindow(
        _ state: State,
        _ command: FileManagerWindowAction.WindowCommand,
    ) -> Effect<Action> {
        guard let id = state.focusedWindowID else { return .none }
        return .send(.windows(.element(id: id, action: .window(.request(command)))))
    }

    private func makeWindowSession(path: String?, selectEntryID: String? = nil) -> WindowSessionState {
        let id = uuid()
        let windowState = FileManagerWindowFeature.State.makeInitial(path: path, selectEntryID: selectEntryID)
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
    enum Action {
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

private extension WindowManagerFeature {
    func requestAttachmentPicker(for windowID: WindowManagerState.WindowID) -> Effect<Action> {
        .run { [attachmentPickerClient] send in
            let urls = await attachmentPickerClient.pickAttachments()
            guard !urls.isEmpty else { return }
            let action = await MainActor.run {
                Action.windows(.element(
                    id: windowID,
                    action: .window(.inspector(.aiChat(.attachmentPickerSelection(urls)))),
                ))
            }
            await send(action)
        }
    }
}
