import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesAppPreferences
import VoyagerEntitiesCollection
import VoyagerFeaturesExternalFileRouter
import VoyagerFeaturesUpdateVersion
import VoyagerPagesFileManager
import VoyagerPagesOnboarding
import VoyagerPagesSettings
import VoyagerShared

private typealias HelperFolderAccessResult = VoyagerEntitiesAppPreferences.FolderAccessResult

@Reducer
struct AppRootFeature {
    typealias State = AppRootState
    typealias Action = AppRootAction

    @Dependency(\.helperExternalFileChangeClient)
    private var helperExternalFileChangeClient
    @Dependency(\.helperFolderAccessClient)
    private var helperFolderAccessClient: VoyagerEntitiesAppPreferences.HelperFolderAccessClient
    @Dependency(\.helperStateClient)
    private var helperStateClient
    @Dependency(\.collectionStalenessClient)
    private var collectionStalenessClient
    @Dependency(\.onboardingWindowClient)
    private var onboardingWindowClient
    @Dependency(\.userDefaultsClient)
    private var userDefaultsClient
    @Dependency(\.notificationCenterClient)
    private var notificationCenterClient

    private enum CancelID {
        static let helperExternalFileBridge = "helperExternalFileBridge"
        static let helperStateObserver = "helperStateObserver"
        static let appDidBecomeActiveObserver = "appDidBecomeActiveObserver"
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
        Scope(state: \.externalFileRouter, action: \.externalFileRouter) {
            ExternalFileRouterFeature()
        }

        Reduce { state, action in
            reduceAppLifecycle(into: &state, action: action)
        }
        Reduce { state, action in
            reduceHelperFileBridge(into: &state, action: action)
        }
        Reduce { state, action in
            reducePreferencesAndCommands(into: &state, action: action)
        }
        Reduce { state, action in
            reduceExternalURL(into: &state, action: action)
        }
        Reduce { state, action in
            reduceExternalFileURL(into: &state, action: action)
        }
        Reduce { state, action in
            reduceWindowPostAction(into: &state, action: action)
        }
        Reduce { state, _ in
            state.menuCommands = MenuCommandsState(state: state)
            return .none
        }
    }

    private func reduceAppLifecycle(
        into state: inout State,
        action: Action,
    ) -> Effect<Action> {
        switch action {
        case .lifecycle(.launch(.willFinishLaunching)):
            return startLaunchObservers()

        case let .lifecycle(.delegate(delegateAction)):
            switch delegateAction {
            case .openInitialWindowIfNeeded:
                return .send(.windowManager(.lifecycle(.openInitialWindowIfNeeded)))

            case let .reopenWindowIfNeeded(hasVisibleWindows):
                return .send(.windowManager(.lifecycle(.reopenWindowIfNeeded(hasVisibleWindows: hasVisibleWindows))))
            }

        case .lifecycle(.termination(.willTerminate)):
            state.isHelperExternalFileBridgeStarted = false
            state.lastHelperReady = false
            state.windowPresenceBeforeWindowManagerAction = nil
            return .merge(
                .cancel(id: CancelID.helperExternalFileBridge),
                .cancel(id: CancelID.helperStateObserver),
                .cancel(id: CancelID.appDidBecomeActiveObserver),
            )

        case .appDidBecomeActive:
            return state.lastHelperReady && !state.windowManager.windows.isEmpty
                ? .send(.registerHelperWatchRootsIfNeeded)
                : .none

        default:
            return .none
        }
    }

    private func startLaunchObservers() -> Effect<Action> {
        let helperStateClient = helperStateClient
        return .merge(
            .send(.appPreferences(.load)),
            .run { send in
                for await helperState in helperStateClient.observe() {
                    await send(.helperStateUpdated(helperState))
                }
            }
            .cancellable(id: CancelID.helperStateObserver, cancelInFlight: true),
            .run { [notificationCenterClient] send in
                for await _ in notificationCenterClient.notifications(
                    NSApplication.didBecomeActiveNotification,
                    nil,
                ) {
                    await send(.appDidBecomeActive)
                }
            }
            .cancellable(id: CancelID.appDidBecomeActiveObserver, cancelInFlight: true),
        )
    }

    private func reduceHelperFileBridge(
        into state: inout State,
        action: Action,
    ) -> Effect<Action> {
        switch action {
        case .startHelperExternalFileBridge:
            return startHelperExternalFileBridgeIfNeeded(state: &state)

        case let .helperStateUpdated(helperState):
            let shouldRegister = helperState.helperReady && !state.windowManager.windows.isEmpty
            state.lastHelperReady = helperState.helperReady
            return shouldRegister ? .send(.registerHelperWatchRootsIfNeeded) : .none

        case let .helperExternalFileChanged(event):
            return handleHelperExternalFileChanged(event, state: state)

        case .flushPendingReplay:
            guard !state.windowManager.windows.isEmpty else { return .none }
            return .run { send in
                let paths = await PendingReplayPathsStore.shared.takeAll()
                await send(.pendingReplayLoaded(paths))
            }

        case let .pendingReplayLoaded(paths):
            return handlePendingReplayLoaded(paths, state: state)

        case .registerHelperWatchRootsIfNeeded:
            return registerHelperWatchRootsIfNeeded()

        default:
            return .none
        }
    }

    private func startHelperExternalFileBridgeIfNeeded(state: inout State) -> Effect<Action> {
        guard !state.isHelperExternalFileBridgeStarted else { return .none }
        state.isHelperExternalFileBridgeStarted = true
        let helperExternalFileChangeClient = helperExternalFileChangeClient
        return .run { send in
            for await event in helperExternalFileChangeClient.observeChangedPaths() {
                await send(.helperExternalFileChanged(event))
            }
        }
        .cancellable(id: CancelID.helperExternalFileBridge, cancelInFlight: true)
    }

    private func handleHelperExternalFileChanged(
        _ event: HelperExternalFileChangeEvent,
        state: State,
    ) -> Effect<Action> {
        let helperExternalFileChangeClient = helperExternalFileChangeClient
        collectionStalenessClient.invalidateRecords(event.paths)

        if event.source == .replay, state.windowManager.windows.isEmpty {
            return .run { _ in
                await PendingReplayPathsStore.shared.append(event.paths)
            }
        }

        guard !state.windowManager.windows.isEmpty else { return .none }
        return .merge(
            forwardExternalFileChanges(event.paths, windowIDs: state.windowManager.windows.ids),
            .run { _ in
                await helperExternalFileChangeClient.acknowledgeDeliveredPaths(event.paths)
            },
        )
    }

    private func handlePendingReplayLoaded(
        _ paths: [String],
        state: State,
    ) -> Effect<Action> {
        guard !paths.isEmpty else { return .none }
        let helperExternalFileChangeClient = helperExternalFileChangeClient
        return .merge(
            forwardExternalFileChanges(paths, windowIDs: state.windowManager.windows.ids),
            .run { _ in
                await helperExternalFileChangeClient.acknowledgeDeliveredPaths(paths)
            },
        )
    }

    private func registerHelperWatchRootsIfNeeded() -> Effect<Action> {
        let helperExternalFileChangeClient = helperExternalFileChangeClient
        let helperStateClient = helperStateClient
        let onboardingWindowClient = onboardingWindowClient
        let helperFolderAccess = helperFolderAccessClient
        let userDefaultsClient = userDefaultsClient
        return .run { send in
            guard let helperState = await helperStateClient.resolve(), helperState.helperReady else {
                return
            }
            let access = await resolveHelperFolderAccess(
                onboardingWindowClient: onboardingWindowClient,
                helperFolderAccess: helperFolderAccess,
                userDefaultsClient: userDefaultsClient,
            )
            let watchRoots = helperGrantedWatchRoots(from: access)
            await helperExternalFileChangeClient.updateWatchRoots(watchRoots)
            await send(.registerHelperWatchRoots(watchRoots))
        }
    }

    private func resolveHelperFolderAccess(
        onboardingWindowClient: OnboardingWindowClient,
        helperFolderAccess: VoyagerEntitiesAppPreferences.HelperFolderAccessClient,
        userDefaultsClient: UserDefaultsClient,
    ) async -> HelperFolderAccessResult {
        let access: HelperFolderAccessResult = if onboardingWindowClient.isRequired() == false,
                                                  let persisted =
                                                  persistedHelperFolderAccess(userDefaultsClient: userDefaultsClient),
                                                  persisted.status == .granted
        {
            await helperFolderAccess.checkAccess()
        } else {
            await helperFolderAccess.requestAccess()
        }

        let data = try? JSONEncoder().encode(access)
        userDefaultsClient.setObject(data, SettingsKeys.helperFolderAccessSnapshot)
        return access
    }

    private func reducePreferencesAndCommands(
        into state: inout State,
        action: Action,
    ) -> Effect<Action> {
        switch action {
        case let .appPreferences(.delegate(.updated(preferences))):
            state.appPreferences = preferences
            return .send(.windowManager(.lifecycle(.applyAppPreferences(preferences))))

        case let .menuCommands(.delegate(.windowManager(action))):
            return .send(.windowManager(action))

        case let .menuCommands(.delegate(.updater(action))):
            return .send(.updater(action))

        case .windowManager(.delegate(.openAISettings)):
            return .send(.openAISettings)

        case .openAISettings:
            return .concatenate(
                .send(.settings(.selectSection(.ai))),
                .run { _ in
                    await MainActor.run {
                        openNativeSettingsScene()
                    }
                },
            )

        case let .settings(.delegate(.aiConnectionsFileUpdated(file))):
            return .send(.windowManager(.lifecycle(.aiConnectionsFileUpdated(file))))

        case .settings(.general(.checkForUpdates)):
            return .send(.updater(.checkForUpdates))

        case let .settings(.general(.toggleAutomaticUpdate(enabled))):
            return .send(.updater(.setAutomaticUpdate(enabled)))

            // MARK: - ExternalFileRouter Delegate

        case let .externalFileRouter(.delegate(.openFolder(path))):
            // ExternalFileRouter가 폴더 열기 요청 — 새 File Manager Window로 라우팅
            return .send(.windowManager(.file(.newWindow(path: path))))

        case let .externalFileRouter(.delegate(.openParentFolder(path, selectEntryPath))):
            // ExternalFileRouter가 부모 폴더 열기 요청 — 새 File Manager Window로 라우팅
            return .send(.windowManager(.file(.newWindow(path: path, selectEntryID: selectEntryPath))))

        case .externalFileRouter(.delegate(.routeToAuthCallback)):
            // ACC-001 소유의 OAuth callback — FMW-003가 가로채지 않음
            // TODO: ACC 핸드오프 seam 확인 후 실제 전달 로직 추가
            return .none

        default:
            return .none
        }
    }

    private func reduceExternalURL(
        into state: inout State,
        action: Action,
    ) -> Effect<Action> {
        switch action {
        case let .receiveExternalURL(url):
            // 창이 없으면 버퍼링, 창이 열리면 ExternalFileRouter로 URL 전달
            guard !state.windowManager.windows.isEmpty else {
                state.pendingExternalURL = url
                return .none
            }
            // 창이 열려 있는 상태에서 ExternalFileRouter로 URL 전달
            return .send(.externalFileRouter(.receive(url)))

        default:
            return .none
        }
    }

    private func reduceExternalFileURL(
        into state: inout State,
        action: Action,
    ) -> Effect<Action> {
        switch action {
        case let .receiveExternalFileURL(url, source, mode):
            guard !state.windowManager.windows.isEmpty else {
                state.pendingExternalFileURL = url
                state.pendingFileURLSource = source
                state.pendingFileURLMode = mode
                return .none
            }
            return .send(.externalFileRouter(.receiveFileURL(url, source: source, mode: mode)))

        default:
            return .none
        }
    }

    /// didOpenFirstWindow 분기에서 버퍼링된 외부 URL을 소비하고 nil로 리셋
    private func flushPendingExternalURL(state: inout State) -> Effect<Action> {
        guard let url = state.pendingExternalURL else { return .none }
        state.pendingExternalURL = nil
        // 버퍼링된 URL을 ExternalFileRouter로 전달
        return .send(.externalFileRouter(.receive(url)))
    }

    /// Cold state에서 버퍼링된 file:// URL을 flush
    private func flushPendingExternalFileURL(state: inout State) -> Effect<Action> {
        guard let url = state.pendingExternalFileURL,
              let source = state.pendingFileURLSource,
              let mode = state.pendingFileURLMode
        else { return .none }
        state.pendingExternalFileURL = nil
        state.pendingFileURLSource = nil
        state.pendingFileURLMode = nil
        return .send(.externalFileRouter(.receiveFileURL(url, source: source, mode: mode)))
    }

    private func reduceWindowPostAction(
        into state: inout State,
        action: Action,
    ) -> Effect<Action> {
        guard case .windowManager = action else { return .none }

        let hadWindowsBeforeAction = state.windowPresenceBeforeWindowManagerAction ?? false
        let hasWindowsAfterAction = !state.windowManager.windows.isEmpty
        let didOpenFirstWindow = !hadWindowsBeforeAction && hasWindowsAfterAction
        state.windowPresenceBeforeWindowManagerAction = nil
        return .merge(
            didOpenFirstWindow ? .send(.startHelperExternalFileBridge) : .none,
            didOpenFirstWindow ? .send(.flushPendingReplay) : .none,
            (didOpenFirstWindow && state.lastHelperReady) ? .send(.registerHelperWatchRootsIfNeeded) : .none,
            didOpenFirstWindow ? flushPendingExternalURL(state: &state) : .none,
            didOpenFirstWindow ? flushPendingExternalFileURL(state: &state) : .none,
        )
    }
}

@MainActor
private func openNativeSettingsScene() {
    NSApp.activate(ignoringOtherApps: true)

    if performSettingsMenuItem() {
        return
    }

    let settingsSelector = Selector(("showSettingsWindow:"))
    if NSApp.sendAction(settingsSelector, to: nil, from: nil) {
        return
    }

    let preferencesSelector = Selector(("showPreferencesWindow:"))
    _ = NSApp.sendAction(preferencesSelector, to: nil, from: nil)
}

@MainActor
private func performSettingsMenuItem() -> Bool {
    guard let mainMenu = NSApp.mainMenu else { return false }

    for item in mainMenu.items {
        guard let submenu = item.submenu else { continue }
        if performSettingsMenuItem(in: submenu) {
            return true
        }
    }

    return false
}

@MainActor
private func performSettingsMenuItem(in menu: NSMenu) -> Bool {
    for index in 0 ..< menu.numberOfItems {
        guard let item = menu.item(at: index) else { continue }
        if isSettingsMenuItem(item) {
            if let action = item.action,
               NSApp.sendAction(action, to: item.target, from: item)
            {
                return true
            }

            menu.performActionForItem(at: index)
            return true
        }

        if let submenu = item.submenu,
           performSettingsMenuItem(in: submenu)
        {
            return true
        }
    }

    return false
}

private func isSettingsMenuItem(_ item: NSMenuItem) -> Bool {
    let normalizedTitle = item.title
        .replacingOccurrences(of: "…", with: "")
        .replacingOccurrences(of: "...", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()

    return normalizedTitle == "settings"
        || normalizedTitle == "preferences"
        || item.action == Selector(("showSettingsWindow:"))
        || item.action == Selector(("showPreferencesWindow:"))
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

nonisolated private func helperGrantedWatchRoots(from access: HelperFolderAccessResult) -> [String] {
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

nonisolated private func persistedHelperFolderAccess(userDefaultsClient: UserDefaultsClient)
    -> HelperFolderAccessResult?
{
    guard let data = userDefaultsClient.object(SettingsKeys.helperFolderAccessSnapshot) as? Data else {
        return nil
    }
    return try? JSONDecoder().decode(HelperFolderAccessResult.self, from: data)
}
