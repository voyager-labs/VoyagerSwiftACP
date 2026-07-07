import AppKit
import ComposableArchitecture
import VoyagerEntitiesCollection
import VoyagerFeaturesAccountAccess
import VoyagerFeaturesExternalFileRouter
import VoyagerFeaturesUpdateVersion
import VoyagerPagesOnboarding

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var appRootStore: StoreOf<AppRootFeature>?

    override init() {
        super.init()
    }

    func configure(appRootStore: StoreOf<AppRootFeature>) {
        self.appRootStore = appRootStore
    }

    func applicationWillFinishLaunching(_: Notification) {
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
            $0.send(.updater(.configureAtLaunch))
        }
    }

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.servicesProvider = self
        withAppRootStore {
            $0.send(.lifecycle(.launch(.didFinishLaunching)))
        }
    }

    func application(_: NSApplication, open urls: [URL]) {
        withAppRootStore {
            for url in urls {
                routeOpenedURL(url, to: $0)
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
        sender.reply(toOpenOrPrint: .success)
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
            for url in urls {
                routeFileURL(url, source: .systemOpenEvent, mode: .open, to: $0)
            }
        }
    }

    private func routeOpenedURL(_ url: URL, to store: StoreOf<AppRootFeature>) {
        switch url.scheme?.lowercased() {
        case "voyager":
            if isAuthCallback(url) {
                routeAuthCallback(url)
            } else {
                store.send(.receiveExternalURL(url))
            }
        case "file":
            routeFileURL(url, source: .systemOpenEvent, mode: .open, to: store)
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
        withAppRootStore {
            $0.send(.lifecycle(.launch(.appReopen(hasVisibleWindows: flag))))
            return true
        } onMissing: {
            true
        }
    }

    private func routeAuthCallback(_ url: URL) {
        MainActor.assumeIsolated {
            Voyager.routeAuthCallback(
                url,
                routeToOnboarding: { VoyagerPagesOnboarding.routeAuthCallbackToOnboardingIfPresent($0) },
                routeToSessionLapseGuard: { callbackURL in
                    self.withAppRootStore {
                        _ = $0.send(.lifecycle(.sessionLapseGuard(.loginCallbackReceived(callbackURL))))
                    }
                },
            )
        }
    }

    func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        withAppRootStore {
            $0.send(.lifecycle(.termination(.requestTermination)))
            return .terminateLater
        } onMissing: {
            .terminateNow
        }
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

@MainActor
func routeAuthCallback(
    _ url: URL,
    routeToOnboarding: @escaping (URL) -> Bool,
    routeToSessionLapseGuard: ((URL) -> Void)? = nil,
) {
    // 온보딩이 콜백을 처리하면 종료. 미처리 시 sessionLapseGuard 폴백.
    if routeToOnboarding(url) { return }
    routeToSessionLapseGuard?(url)
}
