import AppKit
import ComposableArchitecture
import Logging
import SwiftUI

@main
struct VoyagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate

    private let appRootStore: StoreOf<AppRootFeature>

    @MainActor
    init() {
        let windowContext = FileManagerWindowClientLiveContext()

        appRootStore = Store(initialState: AppRootState()) {
            AppRootFeature()
        } withDependencies: {
            $0.onboardingWindowClient = OnboardingWindowClient.makeLive(openMainWindow: { path in
                await MainActor.run {
                    windowContext.sendNewWindow(path: path)
                    return true
                }
            })
            $0.fileManagerWindowClient = windowContext.client
        }

        windowContext.bind(appStore: appRootStore)
        appDelegate.configure(appRootStore: appRootStore)

        LoggingSystem.bootstrap { label in
            let oslogHandler = VoyagerOSLogHandler(label: label)
            #if DEBUG
            let stderrHandler = StreamLogHandler.standardError(label: label)
            return MultiplexLogHandler([oslogHandler, stderrHandler])
            #else
            return oslogHandler
            #endif
        }
    }

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .commands {
            AppMenuCommands(appRootStore: appRootStore)
            EditMenuCommands(appRootStore: appRootStore)
            ViewMenuCommands(appRootStore: appRootStore)
        }
    }
}
