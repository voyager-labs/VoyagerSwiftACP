import AppKit
import ComposableArchitecture
import Foundation
import Logging
import SwiftUI
import VoyagerEntitiesAppPreferences
import VoyagerEntitiesCollection
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

        appRootStore = Store(initialState: AppRootState()) {
            AppRootFeature()
        } withDependencies: {
            $0.composerMetricClient = Self.makeComposerMetricClient()
            $0.collectionMetricClient = Self.makeCollectionMetricClient()
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
            $0.metricsClient = Self.makeFileManagerMetricsClient()
        }

        configureFileManagerWindowCallbacks()
        appDelegate.configure(appRootStore: appRootStore)
        configureLogging()
    }

    private static func makeComposerMetricClient() -> ComposerMetricClient {
        ComposerMetricClient { name, value, tags, level in
            Task { @MainActor in
                VoyagerSentryMetricLogger.logMetric(
                    name,
                    value: value,
                    tags: tags,
                    level: metricLogLevel(for: level),
                )
            }
        }
    }

    private static func makeCollectionMetricClient() -> CollectionMetricClient {
        CollectionMetricClient { name, value, tags, level in
            Task { @MainActor in
                VoyagerSentryMetricLogger.logMetric(
                    name,
                    value: value,
                    tags: tags,
                    level: metricLogLevel(for: level),
                )
            }
        }
    }

    private static func makeFileManagerMetricsClient() -> MetricsClient {
        .init(
            logMetric: { name, value, tags in
                Task { @MainActor in
                    VoyagerSentryMetricLogger.logMetric(name, value: value, tags: tags)
                }
            },
            logDAUNavigation: { kind in
                Task { @MainActor in
                    switch kind {
                    case .folder: VoyagerSentryMetricLogger.logDAUNavigation(kind: .folder)
                    case .collection: VoyagerSentryMetricLogger.logDAUNavigation(kind: .collection)
                    }
                }
            },
            logDAUEntryAction: { actionKind, entryKind in
                let sentryActionKind = DAUEntryActionKind(rawValue: actionKind.rawValue)
                let sentryEntryKind = DAUEntryKind(rawValue: entryKind.rawValue)
                Task { @MainActor in
                    guard let sentryActionKind, let sentryEntryKind else { return }
                    VoyagerSentryMetricLogger.logDAUEntryAction(
                        actionKind: sentryActionKind,
                        entryKind: sentryEntryKind,
                    )
                }
            },
        )
    }

    private static func metricLogLevel(for level: ComposerMetricLevel) -> MetricLogLevel {
        switch level {
        case .trace: .trace
        case .debug: .debug
        case .info: .info
        case .warn: .warn
        case .error: .error
        }
    }

    private static func metricLogLevel(for level: CollectionMetricLevel) -> MetricLogLevel {
        switch level {
        case .trace: .trace
        case .debug: .debug
        case .info: .info
        case .warn: .warn
        case .error: .error
        }
    }

    private func configureFileManagerWindowCallbacks() {
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
            windowKeyCallbacks: FileManagerWindowKeyCallbacks(
                onBecameKey: { [appRootStore] id in
                    appRootStore.send(.windowManager(.event(.windowBecameKey(id))))
                },
                onResignedKey: { [appRootStore] id in
                    appRootStore.send(.windowManager(.event(.windowResignedKey(id))))
                },
                onClosed: { [appRootStore] id in
                    appRootStore.send(.windowManager(.event(.windowClosed(id))))
                },
            ),
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
