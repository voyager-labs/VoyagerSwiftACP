import AppKit
import ComposableArchitecture
import Foundation
import Logging
import SwiftUI
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesComposer
import VoyagerFeaturesEntryOperations
import VoyagerPagesOnboarding
import VoyagerPagesSettings

@main
struct VoyagerApp: App {
    private let appRootStore: StoreOf<AppRootFeature>

    @NSApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate

    @MainActor
    init() {
        let fileManagerWindowClient = makeFileManagerWindowClientLive()

        appRootStore = Store(initialState: AppRootState()) {
            AppRootFeature()
        } withDependencies: {
            $0.composerMetricClient = ComposerMetricClient { name, value, tags, level in
                let appLevel: MetricLogLevel = switch level {
                case .trace: .trace
                case .debug: .debug
                case .info: .info
                case .warn: .warn
                case .error: .error
                }
                MainActor.assumeIsolated {
                    VoyagerSentryMetricLogger.logMetric(
                        name,
                        value: value,
                        tags: tags,
                        level: appLevel,
                    )
                }
            }
            $0.onboardingWindowClient = OnboardingWindowClient.makeLive(openMainWindow: { request in
                await MainActor.run {
                    let resolvedPath: String = switch request {
                    case .defaultTabPath:
                        SettingsDefaults.defaultTabPath()
                    case let .explicitPath(path):
                        path
                    }
                    requestFileManagerNewWindow(path: resolvedPath)
                }
                await Task.yield()
                return true
            })
            $0.fileManagerWindowClient = fileManagerWindowClient
            $0.undoManagerClient = .live(resolveUndoManager: { windowID in
                await MainActor.run {
                    resolveFileManagerUndoManager(windowID: windowID)
                }
            })
        }

        configureFileManagerWindowClientLive(
            requestNewWindow: { [appRootStore] path in
                appRootStore.send(.windowManager(.file(.newWindow(path: path))))
            },
            requestNewTab: { [appRootStore] path in
                appRootStore.send(.windowManager(.file(.newTab(path: path))))
            },
            resolveFileManagerStore: { [appRootStore] windowID in
                let sessionStores = Array(
                    appRootStore.scope(state: \.windowManager.windows, action: \.windowManager.windows),
                )
                return sessionStores.first(where: { $0.state.id == windowID })?
                    .scope(state: \.window, action: \.window)
            },
            onWindowBecameKey: { [appRootStore] id in
                appRootStore.send(.windowManager(.event(.windowBecameKey(id))))
            },
            onWindowResignedKey: { [appRootStore] id in
                appRootStore.send(.windowManager(.event(.windowResignedKey(id))))
            },
            onWindowClosed: { [appRootStore] id in
                appRootStore.send(.windowManager(.event(.windowClosed(id))))
            },
        )
        appDelegate.configure(appRootStore: appRootStore)
        configureLogging()
    }

    private func configureLogging() {
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
            SettingsView(store: appRootStore.scope(state: \.settings, action: \.settings))
        }
        .commands {
            AppMenuCommands(appRootStore: appRootStore)
            EditMenuCommands(appRootStore: appRootStore)
            ViewMenuCommands(appRootStore: appRootStore)
        }
    }
}
