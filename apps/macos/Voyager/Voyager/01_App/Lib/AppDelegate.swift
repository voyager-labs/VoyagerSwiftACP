import AppKit
import ComposableArchitecture

class AppDelegate: NSObject, NSApplicationDelegate {
    private var appRootStore: StoreOf<AppRootFeature>?

    override init() {
        super.init()
    }

    func configure(appRootStore: StoreOf<AppRootFeature>) {
        self.appRootStore = appRootStore
    }

    func applicationWillFinishLaunching(_: Notification) {
        requireRootStore().send(.lifecycle(.willFinishLaunching))
        requireRootStore().send(.updater(.configureAtLaunch))
    }

    func applicationDidFinishLaunching(_: Notification) {
        requireRootStore().send(.lifecycle(.didFinishLaunching))
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        requireRootStore().send(.lifecycle(.appReopen(hasVisibleWindows: flag)))
        return true
    }

    func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        requireRootStore().send(.lifecycle(.requestTermination))
        return .terminateLater
    }

    private func requireRootStore() -> StoreOf<AppRootFeature> {
        guard let appRootStore else {
            fatalError("appRootStore가 설정되지 않았습니다.")
        }
        return appRootStore
    }
}
