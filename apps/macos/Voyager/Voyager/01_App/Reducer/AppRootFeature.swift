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
        static let helperStateObserver = "helperStateObserver"
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.lifecycle, action: \.lifecycle) {
            AppLifecycleFeature()
        }
        Scope(state: \.appPreferences, action: \.appPreferences) {
            AppPreferencesFeature()
        }
        Reduce { state, action in
            if case .windowManager = action {
                state.windowPresenceBeforeWindowManagerAction = !state.windowManager.windows.isEmpty
            }
            return .none
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
            let effect: Effect<Action>
            switch action {
            case .lifecycle(.launch(.willFinishLaunching)):
                let helperStateClient = helperStateClient
                effect = .merge(
                    .send(.appPreferences(.load)),
                    .run { send in
                        for await helperState in helperStateClient.observe() {
                            await send(.helperStateUpdated(helperState))
                        }
                    }
                    .cancellable(id: CancelID.helperStateObserver, cancelInFlight: true),
                )

            case .startHelperExternalFileBridge:
                guard !state.isHelperExternalFileBridgeStarted else {
                    effect = .none
                    break
                }
                state.isHelperExternalFileBridgeStarted = true
                let helperExternalFileChangeClient = helperExternalFileChangeClient
                effect = .run { send in
                    for await event in helperExternalFileChangeClient.observeChangedPaths() {
                        await send(.helperExternalFileChanged(event))
                    }
                }
                .cancellable(id: CancelID.helperExternalFileBridge, cancelInFlight: true)

            case let .lifecycle(.delegate(delegateAction)):
                switch delegateAction {
                case .openInitialWindowIfNeeded:
                    effect = .send(.windowManager(.lifecycle(.openInitialWindowIfNeeded)))

                case let .reopenWindowIfNeeded(hasVisibleWindows):
                    effect =
                        .send(.windowManager(.lifecycle(.reopenWindowIfNeeded(hasVisibleWindows: hasVisibleWindows))))
                }

            case .lifecycle:
                switch action {
                case .lifecycle(.termination(.willTerminate)):
                    state.isHelperExternalFileBridgeStarted = false
                    state.lastHelperReady = false
                    state.windowPresenceBeforeWindowManagerAction = nil
                    effect = .merge(
                        .cancel(id: CancelID.helperExternalFileBridge),
                        .cancel(id: CancelID.helperStateObserver),
                    )
                default:
                    effect = .none
                }

            case let .helperStateUpdated(helperState):
                let shouldRegister = !state.lastHelperReady && helperState.helperReady
                    && !state.windowManager.windows.isEmpty
                state.lastHelperReady = helperState.helperReady
                effect = shouldRegister ? .send(.registerHelperWatchRootsIfNeeded) : .none

            case let .helperExternalFileChanged(event):
                let helperExternalFileChangeClient = helperExternalFileChangeClient
                collectionStalenessClient.invalidateRecords(event.paths)
                if event.source == .replay, state.windowManager.windows.isEmpty {
                    effect = .run { _ in
                        await PendingReplayPathsStore.shared.append(event.paths)
                    }
                } else if event.source == .replay, !state.windowManager.windows.isEmpty {
                    effect = .merge(
                        forwardExternalFileChanges(event.paths, windowIDs: state.windowManager.windows.ids),
                        .run { _ in
                            await helperExternalFileChangeClient.acknowledgeReplay()
                        },
                    )
                } else {
                    effect = forwardExternalFileChanges(event.paths, windowIDs: state.windowManager.windows.ids)
                }

            case .flushPendingReplay:
                guard !state.windowManager.windows.isEmpty else {
                    effect = .none
                    break
                }
                effect = .run { send in
                    let paths = await PendingReplayPathsStore.shared.takeAll()
                    await send(.pendingReplayLoaded(paths))
                }

            case let .pendingReplayLoaded(paths):
                guard !paths.isEmpty else {
                    effect = .none
                    break
                }
                let helperExternalFileChangeClient = helperExternalFileChangeClient
                effect = .merge(
                    forwardExternalFileChanges(paths, windowIDs: state.windowManager.windows.ids),
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
                        access = await helperFolderAccess.checkAccess()
                        let data = try? JSONEncoder().encode(access)
                        userDefaultsClient.setObject(data, SettingsKeys.helperFolderAccessSnapshot)
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
                effect = .send(.windowManager(.lifecycle(.applyAppPreferences(preferences))))

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
                    let hadWindowsBeforeAction = state.windowPresenceBeforeWindowManagerAction ?? false
                    let hasWindowsAfterAction = !state.windowManager.windows.isEmpty
                    let didOpenFirstWindow = !hadWindowsBeforeAction && hasWindowsAfterAction
                    state.windowPresenceBeforeWindowManagerAction = nil
                    effect = .merge(
                        didOpenFirstWindow ? .send(.startHelperExternalFileBridge) : .none,
                        didOpenFirstWindow ? .send(.flushPendingReplay) : .none,
                        (didOpenFirstWindow && state.lastHelperReady) ? .send(.registerHelperWatchRootsIfNeeded) :
                            .none,
                    )
                default:
                    effect = .none
                }
            }

            state.menuCommands = MenuCommandsState(state: state)
            return effect
        }
    }
}

private func forwardExternalFileChanges(
    _ paths: [String],
    windowIDs: IdentifiedArrayOf<WindowSessionFeature.State>.IDs,
) -> Effect<AppRootAction> {
    guard !paths.isEmpty else { return .none }

    return .merge(
        windowIDs.map { id in
            .send(.windowManager(.windows(.element(
                id: id,
                action: .window(.content(.externalFileSystemChanged(paths))),
            ))))
        },
    )
}

actor PendingReplayPathsStore {
    static let shared = PendingReplayPathsStore()

    private var paths: Set<String> = []

    func append(_ newPaths: [String]) {
        paths.formUnion(newPaths)
    }

    func takeAll() -> [String] {
        let snapshot = Array(paths).sorted()
        paths.removeAll()
        return snapshot
    }
}

private nonisolated func helperGrantedWatchRoots(from access: FolderAccessResult) -> [String] {
    guard access.status == .granted else { return [] }

    let fileManager = FileManager.default
    var roots: [String] = []

    let homePath = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path
    roots.append(homePath)

    let iCloudDrive = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(FileManagerSpecialRootRelativePathConfig.iCloudDrive)
        .standardizedFileURL
    if fileManager.fileExists(atPath: iCloudDrive.path) {
        roots.append(iCloudDrive.path)
    }

    let cloudStorageRoot = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(FileManagerSpecialRootRelativePathConfig.cloudStorage)
        .standardizedFileURL
    if let contents = try? fileManager.contentsOfDirectory(
        at: cloudStorageRoot,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles],
    ) {
        for itemURL in contents {
            if let isDirectory = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory,
               isDirectory == true
            {
                roots.append(itemURL.standardizedFileURL.path)
            }
        }
    }

    return Array(Set(roots)).sorted()
}

private nonisolated func persistedHelperFolderAccess(userDefaultsClient: UserDefaultsClient) -> FolderAccessResult? {
    guard let data = userDefaultsClient.object(SettingsKeys.helperFolderAccessSnapshot) as? Data else {
        return nil
    }
    return try? JSONDecoder().decode(FolderAccessResult.self, from: data)
}
