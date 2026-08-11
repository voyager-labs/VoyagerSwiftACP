import AppKit
import ComposableArchitecture
import VoyagerEntitiesCollection
import VoyagerFeaturesAccountAccess
import VoyagerFeaturesExternalFileRouter
import VoyagerFeaturesUpdateVersion

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var appRootStore: StoreOf<AppRootFeature>?
    private lazy var keyboardShortcutMonitor = AppKeyboardShortcutMonitor()

    /// 현재 앱 신원에 맞는 callback scheme. 테스트에서 override하여 Dev/Prod 동작 검증.
    /// AppHandoffTarget으로 런타임 bundle ID 기반 결정.
    var callbackScheme: String = AppHandoffTarget.liveValue.callbackScheme
    /// Application-hosted XCTest boots the real app delegate before test cases run.
    /// Keep automatic app lifecycle dispatch at this boundary so reducer tests can
    /// still exercise lifecycle actions explicitly.
    var shouldSuppressAutomaticLifecycle: () -> Bool = {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    override init() {
        super.init()
    }

    func configure(appRootStore: StoreOf<AppRootFeature>) {
        self.appRootStore = appRootStore
    }

    func applicationWillFinishLaunching(_: Notification) {
        guard !shouldSuppressAutomaticLifecycle() else { return }

        // 현재 앱 신원에 맞는 scheme으로 ExternalFileRouter 초기화
        let scheme = AppHandoffTarget.liveValue.callbackScheme
        withAppRootStore {
            $0.send(.externalFileRouter(.setExpectedScheme(scheme)))
        }
        UpdaterClient.registerRelaunchHandlers(
            prepareForRelaunch: {
                await VoyagerTerminationCoordinator.shared.begin(.sparkleRelaunch)
            },
            stopHelperApp: {
                await HelperAppClient.liveValue.stop()
            },
        )
        withAppRootStore {
            $0.send(.lifecycle(.launch(.willFinishLaunching)))
        }
    }

    func applicationDidFinishLaunching(_: Notification) {
        guard !shouldSuppressAutomaticLifecycle() else { return }

        NSApp.servicesProvider = self
        withAppRootStore {
            $0.send(.lifecycle(.launch(.didFinishLaunching)))
            keyboardShortcutMonitor.start(
                context: { [weak self] in
                    self?.contentTabShortcutContext() ?? .unavailable
                },
                onSelectContentTab: { [weak self] position in
                    self?.withAppRootStore {
                        $0.send(.menuCommands(.view(.app(.selectContentTab(position: position)))))
                    }
                },
            )
        }
    }

    func applicationWillTerminate(_: Notification) {
        keyboardShortcutMonitor.stop()
    }

    func application(_: NSApplication, open urls: [URL]) {
        withAppRootStore { store in
            let fileURLs = urls.filter(\.isFileURL)
            var didRouteFileBatch = false
            for url in urls {
                if url.isFileURL {
                    guard !didRouteFileBatch else { continue }
                    didRouteFileBatch = true
                    routeSystemOpenFileURLs(fileURLs, to: store)
                } else {
                    routeOpenedURL(url, to: store)
                }
            }
        }
    }

    func application(_: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        routeSystemOpenFileURLs([url])
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        routeSystemOpenFileURLs(filenames.map(URL.init(fileURLWithPath:)))
        reply(toOpenOrPrint: .success, sender: sender)
    }

    func reply(toOpenOrPrint reply: NSApplication.DelegateReply, sender: NSApplication) {
        sender.reply(toOpenOrPrint: reply)
    }

    /// NSServices "Voyager로 열기" 핸들러
    @objc
    func openInVoyagerService(
        _ pboard: NSPasteboard,
        userData _: String,
        error _: NSErrorPointer,
    ) {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] else { return }
        withAppRootStore {
            for url in urls {
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let mode: DeepLinkMode = isDirectory ? .open : .reveal
                routeFileURL(url, source: .nsservices, mode: mode, to: $0)
            }
        }
    }

    private func routeSystemOpenFileURLs(_ urls: [URL]) {
        withAppRootStore {
            routeSystemOpenFileURLs(urls, to: $0)
        }
    }

    private func routeSystemOpenFileURLs(_ urls: [URL], to store: StoreOf<AppRootFeature>) {
        guard !urls.isEmpty else { return }
        store.send(.receiveExternalFileBatch(
            urls,
            source: .systemOpenEvent,
            mode: .open,
        ))
    }

    private func routeOpenedURL(_ url: URL, to store: StoreOf<AppRootFeature>) {
        switch url.scheme?.lowercased() {
        case callbackScheme.lowercased():
            if isAuthCallback(url) {
                routeAuthCallback(url)
            } else {
                store.send(.receiveExternalURL(url))
            }
        default:
            break
        }
    }

    private func routeFileURL(
        _ url: URL,
        source: RouteSource,
        mode: DeepLinkMode,
        to store: StoreOf<AppRootFeature>,
    ) {
        if CollectionFileUtils.isCollectionFile(url) {
            store.send(.receiveCollectionFileURL(url))
            return
        }

        store.send(.receiveExternalFileURL(url, source: source, mode: mode))
    }

    private func isAuthCallback(_ url: URL) -> Bool {
        url.host?.lowercased() == "auth" && url.path.lowercased() == "/callback"
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !shouldSuppressAutomaticLifecycle() else { return true }

        return withAppRootStore {
            $0.send(.lifecycle(.launch(.appReopen(hasVisibleWindows: flag))))
            return true
        } onMissing: {
            true
        }
    }

    private func routeAuthCallback(_ url: URL) {
        withAppRootStore {
            $0.send(.receiveAuthCallbackURL(url))
        }
    }

    func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        guard !shouldSuppressAutomaticLifecycle() else { return .terminateNow }

        return withAppRootStore {
            $0.send(.lifecycle(.termination(.requestTermination)))
            return .terminateLater
        } onMissing: {
            .terminateNow
        }
    }

    private func contentTabShortcutContext() -> AppKeyboardShortcutMonitor.ContentTabShortcutContext {
        withAppRootStore({ store in
            store.withState { state in
                let menuCommands = MenuCommandsState(state: state)
                return .init(
                    hasFocusedWindow: menuCommands.hasFocusedWindow,
                    isComposerPresented: menuCommands.isComposerPresented,
                )
            }
        }, onMissing: {
            .unavailable
        })
    }

    @discardableResult
    private func withAppRootStore<T>(
        _ operation: (StoreOf<AppRootFeature>) -> T,
        onMissing: (() -> T)? = nil,
    ) -> T {
        guard let appRootStore else {
            assertionFailure("appRootStore가 설정되지 않았습니다.")
            if let onMissing {
                return onMissing()
            }

            if let voidValue = () as? T {
                return voidValue
            }

            preconditionFailure("onMissing 콜백이 필요한 반환 타입입니다.")
        }
        return operation(appRootStore)
    }
}
