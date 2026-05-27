import AppKit
import ComposableArchitecture
import Foundation
import Logging
import SwiftUI
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesComposer
import VoyagerFeaturesEntryOperations
import VoyagerPagesFileManager
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
        appRootStore = Self.makeAppRootStore(fileManagerWindowClient: fileManagerWindowClient)

        configureFileManagerWindowClient(appRootStore: appRootStore)
        appDelegate.configure(appRootStore: appRootStore)
        configureLogging()
    }

    private static func makeAppRootStore(fileManagerWindowClient: FileManagerWindowClient) -> StoreOf<AppRootFeature> {
        Store(initialState: AppRootState()) {
            AppRootFeature()
        } withDependencies: {
            $0.composerMetricClient = makeComposerMetricClient()
            $0.onboardingWindowClient = makeOnboardingWindowClient()
            $0.fileManagerWindowClient = fileManagerWindowClient
            $0.undoManagerClient = .live(resolveUndoManager: { windowID in
                await MainActor.run {
                    resolveFileManagerUndoManager(windowID: windowID)
                }
            })
            $0.metricsClient = makeMetricsClient()
        }
    }

    private static func makeComposerMetricClient() -> ComposerMetricClient {
        ComposerMetricClient { name, value, tags, level in
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
    }

    private static func makeOnboardingWindowClient() -> OnboardingWindowClient {
        OnboardingWindowClient.makeLive(openMainWindow: { request in
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
    }

    private static func makeMetricsClient() -> MetricsClient {
        .init(
            logMetric: { name, value, tags in
                VoyagerSentryMetricLogger.logMetric(name, value: value, tags: tags)
            },
            logDAUNavigation: { kind in
                switch kind {
                case .folder: VoyagerSentryMetricLogger.logDAUNavigation(kind: .folder)
                case .collection: VoyagerSentryMetricLogger.logDAUNavigation(kind: .collection)
                }
            },
            logDAUEntryAction: resolveAndLogDAUEntryAction,
        )
    }

    private func configureFileManagerWindowClient(appRootStore: StoreOf<AppRootFeature>) {
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
    }

    private nonisolated static func resolveAndLogDAUEntryAction(
        actionKind: VoyagerPagesFileManager.DAUEntryActionKind,
        entryKind: VoyagerPagesFileManager.DAUEntryKind,
    ) {
        guard
            let resolvedActionKind = DAUEntryActionKind(
                rawValue: actionKind.rawValue,
            )
        else {
            preconditionFailure(
                "Invalid DAUEntryActionKind raw value: \(actionKind.rawValue)",
            )
        }
        guard
            let resolvedEntryKind = DAUEntryKind(
                rawValue: entryKind.rawValue,
            )
        else {
            preconditionFailure(
                "Invalid DAUEntryKind raw value: \(entryKind.rawValue)",
            )
        }
        VoyagerSentryMetricLogger.logDAUEntryAction(
            actionKind: resolvedActionKind,
            entryKind: resolvedEntryKind,
        )
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
