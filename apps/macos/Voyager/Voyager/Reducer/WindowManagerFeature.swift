import ComposableArchitecture
import Foundation
import VoyagerEntitiesAppPreferences
import VoyagerEntitiesEntry
import VoyagerFeaturesAiChat
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import VoyagerPagesFileManager
import VoyagerPagesOnboarding
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

typealias FileManagerWindowFeature = FileManagerFeature

@Reducer
struct WindowManagerFeature {
    typealias State = WindowManagerState
    typealias Action = WindowManagerAction

    nonisolated private enum CancelID: Hashable {
        case defaultWindowBootstrap
    }

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

    @Dependency(\.contentTabPinnedRecordClient)
    private var contentTabPinnedRecordClient
    @Dependency(\.fileManagerClient)
    private var fileManagerClient
    @Dependency(\.fileManagerFavoritesClient)
    private var fileManagerFavoritesClient
    @Dependency(\.entryLoadingClient)
    private var entryLoadingClient
    @Dependency(\.userDefaultsClient)
    private var userDefaultsClient

    @Dependency(\.date)
    private var date

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
                 .file(.openCollectionFile),
                 .file(.newTab),
                 .window(.closeFocusedWindow),
                 .window(.closeAllWindows):
                return handleWindowCommand(action, state: &state)

            case .file(.closeTab):
                return sendCommandToFocusedWindow(state, .closeActiveContentTab)

            case .file(.togglePinTab):
                return sendCommandToFocusedWindow(state, .toggleActiveContentTabPin)

            case .file(.restoreLastClosedTab):
                return sendCommandToFocusedWindow(state, .restoreLastClosedContentTab)

            case .file(.duplicateTab):
                return sendCommandToFocusedWindow(state, .duplicateActiveContentTab)

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
                state.defaultWindowBootstrapWindowIDs.remove(id)
                if wasFocused {
                    state.focusedWindowID = state.windows.first?.id
                }
                guard state.defaultWindowBootstrapWindowIDs.isEmpty,
                      state.defaultWindowBootstrapRequestID != nil
                else { return .none }
                state.defaultWindowBootstrapRequestID = nil
                return .cancel(id: CancelID.defaultWindowBootstrap)

            case let .event(.focusWindow(path)):
                return .run { _ in
                    await fileManagerWindowClient.focusPath(path)
                }

            case let .windows(.element(id: _, action: .window(.delegate(.openPathInNewWindow(path))))):
                return .send(.file(.newWindow(path: path)))

            case let .windows(.element(
                id: sourceWindowID,
                action: .window(.delegate(.fixedLocationVisibilityChanged(hiddenIDs))),
            )):
                return .merge(
                    state.windows.ids
                        .filter { $0 != sourceWindowID }
                        .map { windowID in
                            .send(.windows(.element(
                                id: windowID,
                                action: .window(.applyHiddenFixedLocationIDs(hiddenIDs)),
                            )))
                        },
                )

            case .windows(.element(id: _, action: .window(.contentTabs(.pinnedRecordSaveSucceeded)))):
                return .send(.pinnedContentTabsStoreChanged)

            case .pinnedContentTabsStoreChanged:
                let syncEffect = syncPinnedContentTabsAcrossWindows(state: &state)
                state.defaultWindowBootstrapRequestID = nil
                state.defaultWindowBootstrapWindowIDs.removeAll()
                return .merge(
                    .cancel(id: CancelID.defaultWindowBootstrap),
                    syncEffect,
                )

            case let .defaultWindowBootstrapCompleted(requestID, restoredState):
                guard state.defaultWindowBootstrapRequestID == requestID else { return .none }
                state.defaultWindowBootstrapRequestID = nil
                let targetWindowIDs = state.windows.ids.filter {
                    state.defaultWindowBootstrapWindowIDs.contains($0)
                }
                state.defaultWindowBootstrapWindowIDs.removeAll()
                return .merge(
                    targetWindowIDs.map { id in
                        .send(.windows(.element(
                            id: id,
                            action: .window(.applyPinnedContentTabs(restoredState)),
                        )))
                    },
                )

            case let .defaultWindowBootstrapFailed(requestID):
                guard state.defaultWindowBootstrapRequestID == requestID else { return .none }
                state.defaultWindowBootstrapRequestID = nil
                state.defaultWindowBootstrapWindowIDs.removeAll()
                return .none

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

        case let .file(.openCollectionFile(url)):
            return openCollectionWindowSession(url: url, state: &state)

        case .file(.newTab):
            return sendCommandToFocusedWindow(state, .openNewContentTab)

        case .window(.closeFocusedWindow):
            guard let id = state.focusedWindowID else { return .none }
            return .run { [id] _ in
                await fileManagerWindowClient.close(id)
            }

        case .window(.closeAllWindows):
            state.windows.removeAll()
            state.focusedWindowID = nil
            state.defaultWindowBootstrapRequestID = nil
            state.defaultWindowBootstrapWindowIDs.removeAll()
            return .merge(
                .cancel(id: CancelID.defaultWindowBootstrap),
                .run { _ in
                    await fileManagerWindowClient.closeAll()
                },
            )

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

        let bootstrapEffect: Effect<Action> = if path == nil {
            defaultWindowBootstrapEffectIfNeeded(for: windowSession.id, state: &state)
        } else {
            .none
        }

        return .concatenate(
            windowIDChangedEffect(for: windowSession.id),
            appPreferencesEffect(for: windowSession.id, preferences: state.appPreferences),
            .run { [id = windowSession.id] _ in
                await open(id)
            },
            bootstrapEffect,
        )
    }

    private func openCollectionWindowSession(url: URL, state: inout State) -> Effect<Action> {
        if onboardingWindowClient.showIfNeeded() {
            return .none
        }
        let windowSession = makeWindowSession(path: nil)

        state.windows.append(windowSession)
        state.focusedWindowID = windowSession.id
        let bootstrapEffect = defaultWindowBootstrapEffectIfNeeded(for: windowSession.id, state: &state)

        return .concatenate(
            windowIDChangedEffect(for: windowSession.id),
            .send(.windows(.element(
                id: windowSession.id,
                action: .window(.navigation(.view(.openCollectionFile(url)))),
            ))),
            appPreferencesEffect(for: windowSession.id, preferences: state.appPreferences),
            .run { [fileManagerWindowClient, id = windowSession.id] _ in
                await fileManagerWindowClient.open(id)
            },
            bootstrapEffect,
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

    private func syncPinnedContentTabsAcrossWindows(state: inout State) -> Effect<Action> {
        guard !state.windows.isEmpty else { return .none }
        do {
            let store = try contentTabPinnedRecordClient.loadStore(userDefaultsClient)
            let restoreResult = ContentTabState.restoringPinnedRecords(
                from: store,
                isRestorableAnchor: { _ in true },
            )
            return .merge(
                state.windows.ids.map { id in
                    .send(.windows(.element(
                        id: id,
                        action: .window(.applyPinnedContentTabs(restoreResult.state)),
                    )))
                },
            )
        } catch {
            return .none
        }
    }

    private func defaultWindowBootstrapEffectIfNeeded(
        for windowID: State.WindowID,
        state: inout State,
    ) -> Effect<Action> {
        state.defaultWindowBootstrapWindowIDs.insert(windowID)
        guard state.defaultWindowBootstrapRequestID == nil else { return .none }
        let requestID = uuid()
        state.defaultWindowBootstrapRequestID = requestID
        return runDefaultWindowBootstrapEffect(requestID: requestID)
            .cancellable(id: CancelID.defaultWindowBootstrap, cancelInFlight: true)
    }

    /// Default window's asynchronous pinned-store bootstrap.
    /// Concurrent default and Collection windows share one in-flight load.
    /// Completion applies pinned tabs only to windows that requested this bootstrap.
    private func runDefaultWindowBootstrapEffect(requestID: UUID) -> Effect<Action> {
        let pinnedRecordClient = contentTabPinnedRecordClient
        let favoritesClient = fileManagerFavoritesClient
        let managerClient = fileManagerClient
        let loadingClient = entryLoadingClient
        let defaultsClient = userDefaultsClient
        let now = date

        return .run { send in
            do {
                var store = try pinnedRecordClient.loadStore(defaultsClient)

                // 1. Legacy seed flag
                if !defaultsClient.bool(SettingsKeys.defaultPinnedTabsSeedCompleted) {
                    defaultsClient.setBool(true, SettingsKeys.defaultPinnedTabsSeedCompleted)
                }

                // 2. Finder Favorites seed (if needed)
                if !defaultsClient.bool(SettingsKeys.finderFavoritesPinnedSeedCompleted) {
                    if store.records.isEmpty {
                        let favorites = favoritesClient.loadFavorites(
                            loadingClient,
                            defaultsClient,
                        )
                        let favoriteRecords = FileManagerFavoritesPinnedRecordMapper.pinnedRecords(
                            from: favorites,
                            pinnedAt: now(),
                            fileExistsWithIsDirectory: { path, isDirectory in
                                managerClient.fileExistsWithIsDirectory(path, isDirectory)
                            },
                        )
                        if !favoriteRecords.isEmpty {
                            let seededStore = ContentTabPinnedRecordStore(
                                schemaVersion: store.schemaVersion,
                                records: favoriteRecords,
                            )
                            do {
                                try pinnedRecordClient.saveStore(seededStore, defaultsClient)
                                store = seededStore
                                defaultsClient.setBool(
                                    true,
                                    SettingsKeys.finderFavoritesPinnedSeedCompleted,
                                )
                            } catch {
                                // Save failure: flag stays false for retry
                            }
                        } else {
                            defaultsClient.setBool(true, SettingsKeys.finderFavoritesPinnedSeedCompleted)
                        }
                    } else {
                        defaultsClient.setBool(true, SettingsKeys.finderFavoritesPinnedSeedCompleted)
                    }
                }

                // 3. Restore pinned records with filesystem validation
                let restoreResult = ContentTabState.restoringPinnedRecords(
                    from: store,
                    isRestorableAnchor: { anchor in
                        switch anchor {
                        case let .directory(path):
                            var isDirectory = ObjCBool(false)
                            return managerClient.fileExistsWithIsDirectory(path, &isDirectory)
                                && isDirectory.boolValue
                        case let .collectionFile(url):
                            return managerClient.fileExistsWithIsDirectory(url.path, nil)
                        case .homeDefault, .virtualCollection, .aiChat:
                            return true
                        }
                    },
                )

                // 4. Compact if needed
                if restoreResult.didCompact {
                    let compactedStore = ContentTabPinnedRecordStore(
                        schemaVersion: store.schemaVersion,
                        records: restoreResult.state.tabs.compactMap { tab in
                            restoreResult.state.pinnedRecords[tab.id]
                        },
                    )
                    try? pinnedRecordClient.saveStore(compactedStore, defaultsClient)
                }

                await send(.defaultWindowBootstrapCompleted(requestID: requestID, contentTabs: restoreResult.state))
            } catch {
                await send(.defaultWindowBootstrapFailed(requestID: requestID))
            }
        }
    }

    private func makeWindowSession(path: String?, selectEntryID: String? = nil) -> WindowSessionState {
        let id = uuid()

        if let path {
            let windowState = FileManagerWindowFeature.State.makeInitial(
                path: path,
                selectEntryID: selectEntryID,
            )
            return .init(id: id, window: windowState)
        }

        // Default window: Home shell immediately, no synchronous IO.
        // Pinned store restore/seed/validation runs asynchronously via
        // runDefaultWindowBootstrapEffect() attached in openWindowSession.
        let windowState = FileManagerWindowFeature.State.makeInitial(
            path: nil,
            selectEntryID: selectEntryID,
        )
        return .init(id: id, window: windowState)
    }
}

@Reducer
struct WindowSessionFeature {
    typealias State = WindowSessionState
    typealias Action = WindowSessionAction

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
