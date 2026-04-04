import ComposableArchitecture
import Foundation
import VoyagerEntitiesSettings
import VoyagerPagesOnboarding
import VoyagerPagesSettings
import VoyagerShared

@Reducer
struct AppRootFeature {
    typealias State = AppRootState
    typealias Action = AppRootAction

    @Dependency(\.helperExternalFileChangeClient)
    private var helperExternalFileChangeClient
    @Dependency(\.helperFolderAccessClient)
    private var helperFolderAccessClient
    @Dependency(\.helperStateClient)
    private var helperStateClient
    @Dependency(\.collectionStalenessClient)
    private var collectionStalenessClient
    @Dependency(\.onboardingWindowClient)
    private var onboardingWindowClient
    @Dependency(\.userDefaultsClient)
    private var userDefaultsClient

    private enum CancelID {
        static let helperExternalFileBridge = "helperExternalFileBridge"
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.lifecycle, action: \.lifecycle) {
            AppLifecycleFeature()
        }
        Scope(state: \.appPreferences, action: \.appPreferences) {
            AppPreferencesFeature()
        }
        Scope(state: \.windowManager, action: \.windowManager) {
            WindowManagerFeature()
        }
        Scope(state: \.updater, action: \.updater) {
            UpdaterFeature()
        }
        Scope(state: \.settings, action: \.settings) {
            SettingsFeature()
        }
        Scope(state: \.menuCommands, action: \.menuCommands) {
            MenuCommandsFeature()
        }

        Reduce { state, action in
            let hadWindowsBeforeAction = !state.windowManager.windows.isEmpty
            let effect: Effect<Action>
            switch action {
            case .lifecycle(.willFinishLaunching):
                let helperExternalFileChangeClient = helperExternalFileChangeClient
                effect = .merge(
                    .send(.appPreferences(.load)),
                    .run { send in
                        for await event in helperExternalFileChangeClient.observeChangedPaths() {
                            await send(.helperExternalFileChanged(event))
                        }
                    }
                    .cancellable(id: CancelID.helperExternalFileBridge, cancelInFlight: true),
                )

            case let .lifecycle(.delegate(delegateAction)):
                switch delegateAction {
                case .openInitialWindowIfNeeded:
                    effect = .send(.windowManager(.openInitialWindowIfNeeded))

                case let .reopenWindowIfNeeded(hasVisibleWindows):
                    effect = .send(.windowManager(.reopenWindowIfNeeded(hasVisibleWindows: hasVisibleWindows)))
                }

            case .lifecycle:
                switch action {
                case .lifecycle(.willTerminate):
                    effect = .cancel(id: CancelID.helperExternalFileBridge)
                default:
                    effect = .none
                }

            case let .helperExternalFileChanged(event):
                let helperExternalFileChangeClient = helperExternalFileChangeClient
                collectionStalenessClient.invalidateRecords(event.paths)
                if event.source == .replay, state.windowManager.windows.isEmpty {
                    state.pendingReplayPaths = Array(Set(state.pendingReplayPaths + event.paths)).sorted()
                    effect = .none
                } else if event.source == .replay, !state.windowManager.windows.isEmpty {
                    effect = .merge(
                        .send(.windowManager(.externalFileSystemChanged(event.paths))),
                        .run { _ in
                            await helperExternalFileChangeClient.acknowledgeReplay()
                        },
                    )
                } else {
                    effect = .send(.windowManager(.externalFileSystemChanged(event.paths)))
                }

            case .flushPendingReplay:
                guard !state.pendingReplayPaths.isEmpty, !state.windowManager.windows.isEmpty else {
                    effect = .none
                    break
                }

                let helperExternalFileChangeClient = helperExternalFileChangeClient
                let paths = state.pendingReplayPaths
                state.pendingReplayPaths = []
                effect = .merge(
                    .send(.windowManager(.externalFileSystemChanged(paths))),
                    .run { _ in
                        await helperExternalFileChangeClient.acknowledgeReplay()
                    },
                )

            case .registerHelperWatchRootsIfNeeded:
                let helperExternalFileChangeClient = helperExternalFileChangeClient
                let helperStateClient = helperStateClient
                let onboardingWindowClient = onboardingWindowClient
                let helperFolderAccess = helperFolderAccessClient
                let userDefaultsClient = userDefaultsClient
                effect = .run { send in
                    guard let helperState = await helperStateClient.resolve(), helperState.helperReady else {
                        return
                    }
                    let access: FolderAccessResult
                    if onboardingWindowClient.isRequired() == false,
                       let persisted = persistedHelperFolderAccess(userDefaultsClient: userDefaultsClient),
                       persisted.status == .granted
                    {
                        access = persisted
                    } else {
                        access = await helperFolderAccess.requestAccess()
                        let data = try? JSONEncoder().encode(access)
                        userDefaultsClient.setObject(data, SettingsKeys.helperFolderAccessSnapshot)
                    }
                    let watchRoots = helperGrantedWatchRoots(from: access)
                    await helperExternalFileChangeClient.updateWatchRoots(watchRoots)
                    await send(.registerHelperWatchRoots(watchRoots))
                }

            case .registerHelperWatchRoots:
                effect = .none

            case let .appPreferences(.delegate(.updated(preferences))):
                state.appPreferences = preferences
                effect = .send(.windowManager(.applyAppPreferences(preferences)))

            case .appPreferences:
                effect = .none

            case let .menuCommands(.delegate(.windowManager(action))):
                effect = .send(.windowManager(action))

            case let .menuCommands(.delegate(.updater(action))):
                effect = .send(.updater(action))

            case .menuCommands:
                effect = .none

            case .settings(.general(.checkForUpdates)):
                effect = .send(.updater(.checkForUpdates))

            case let .settings(.general(.toggleAutomaticUpdate(enabled))):
                effect = .send(.updater(.setAutomaticUpdate(enabled)))

            case .windowManager, .updater, .settings:
                switch action {
                case .windowManager:
                    let hasWindowsAfterAction = !state.windowManager.windows.isEmpty
                    effect = .merge(
                        (!hadWindowsBeforeAction && hasWindowsAfterAction) ? .send(.flushPendingReplay) : .none,
                        hasWindowsAfterAction ? .send(.registerHelperWatchRootsIfNeeded) : .none,
                    )
                default:
                    effect = .none
                }
            }

            // menuCommands는 윈도우 상태를 기반으로 한 파생 상태이므로 루트 리듀서에서 항상 동기화한다.
            state.menuCommands = MenuCommandsState(state: state)
            return effect
        }
    }
}

private nonisolated func helperGrantedWatchRoots(from access: FolderAccessResult) -> [String] {
    let fileManager = FileManager.default
    let pairs: [(FolderAccessPermission, FileManager.SearchPathDirectory)] = [
        (access.desktop, .desktopDirectory),
        (access.documents, .documentDirectory),
        (access.downloads, .downloadsDirectory),
    ]

    return pairs.compactMap { permission, directory in
        guard permission == .granted else { return nil }
        return fileManager.urls(for: directory, in: .userDomainMask).first?.standardizedFileURL.path
    }
}

private nonisolated func persistedHelperFolderAccess(userDefaultsClient: UserDefaultsClient) -> FolderAccessResult? {
    guard let data = userDefaultsClient.object(SettingsKeys.helperFolderAccessSnapshot) as? Data else {
        return nil
    }
    return try? JSONDecoder().decode(FolderAccessResult.self, from: data)
}
