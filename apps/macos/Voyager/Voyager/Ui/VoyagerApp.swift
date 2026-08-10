import AppKit
import ComposableArchitecture
import Foundation
import Logging
import SwiftUI
import VoyagerEntitiesCollection
import VoyagerEntryCoreClient
import VoyagerFeaturesComposer
import VoyagerFeaturesEntryOperations
import VoyagerPagesFileManager
import VoyagerPagesOnboarding
import VoyagerPagesSettings
import VoyagerShared

@MainActor
private final class AppRootStoreReference {
    var store: StoreOf<AppRootFeature>?

    func openInitialWindowIfNeeded() async {
        guard let store else {
            preconditionFailure("AppRoot store must be configured before opening the initial window.")
        }
        await store.send(.lifecycle(.delegate(.openInitialWindowIfNeeded))).finish()
    }
}

@main
struct VoyagerApp: App {
    private let appRootStore: StoreOf<AppRootFeature>

    @NSApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate

    @MainActor
    init() {
        let appHostTestMode = AppHostTestMode.current
        let appRootStoreReference = AppRootStoreReference()
        let fileOperationUndoManagerRegistry = FileOperationUndoManagerRegistry()
        let fileManagerWindowClient = makeFileManagerWindowClientLive(
            fileOperationUndoManagerRegistry: fileOperationUndoManagerRegistry,
        )

        appRootStore = Store(initialState: AppRootState()) {
            AppRootFeature()
        } withDependencies: {
            $0.composerMetricClient = Self.makeComposerMetricClient()
            $0.collectionMetricClient = Self.makeCollectionMetricClient()
            $0.onboardingWindowClient = OnboardingWindowClient.makeMainApp(
                openMainWindow: { _ in
                    await appRootStoreReference.openInitialWindowIfNeeded()
                    return true
                },
            )
            $0.fileManagerWindowClient = fileManagerWindowClient
            $0.fileOperationUndoManagerClient = .live(registry: fileOperationUndoManagerRegistry)
            $0.metricsClient = Self.makeFileManagerMetricsClient()
            if appHostTestMode == .lifecycleIntegration {
                Self.configureLifecycleIntegrationDependencies(&$0)
            }
        }
        appRootStoreReference.store = appRootStore
        configureFileManagerWindowCallbacks()
        appDelegate.configure(appRootStore: appRootStore)
        AppHostLifecycleIntegrationProbe.shared.register(appDelegate: appDelegate)
        configureLogging()
    }

    private static func configureLifecycleIntegrationDependencies(
        _ dependencies: inout DependencyValues,
    ) {
        dependencies.date = .constant(Date(timeIntervalSince1970: 0))
        dependencies.uuid = .incrementing
        dependencies.continuousClock = ContinuousClock()
        dependencies.notificationCenterClient = .testValue
        dependencies.userDefaultsClient = .testValue
        dependencies.onboardingWindowClient = OnboardingWindowClient(
            isRequired: { false },
            showIfNeeded: { false },
            showWindow: {},
            closeWindow: {},
            openMainWindow: { _ in true },
        )
        dependencies.helperAppClient = HelperAppClient(
            start: {
                await AppHostLifecycleIntegrationProbe.shared.record(.helperStarted)
            },
            stop: {},
            isRunning: { true },
            terminationEvents: { AsyncStream { $0.finish() } },
            ensureRunning: {},
        )
        dependencies.helperStateClient = HelperStateClient(
            resolve: { HelperState(helperReady: true, helperBundleVersion: nil) },
            observe: { AsyncStream { $0.finish() } },
        )
        dependencies.entryCoreEndpointClient = EntryCoreEndpointClient {
            try EntryCoreEndpoint(path: "/tmp/voyager-lifecycle-integration.sock")
        }
        dependencies.entryCoreClient = EntryCoreClient(
            ping: { _ in EntryCorePingResult() },
            health: { _ in
                await AppHostLifecycleIntegrationProbe.shared.record(.entryCoreHealthChecked)
                return EntryCoreHealthResult()
            },
            version: { _ in try EntryCoreVersionResult(appVersion: "lifecycle-integration") },
        )
        dependencies.fileManagerWindowClient = FileManagerWindowClient(
            open: { _ in
                await AppHostLifecycleIntegrationProbe.shared.record(.initialWindowOpened)
            },
            openTab: { _ in },
            activate: { _ in .becameKey },
            close: { _ in },
            closeAll: {},
            focusPath: { _ in },
        )
        dependencies.appTerminationReplyClient = AppTerminationReplyClient { shouldTerminate in
            await AppHostLifecycleIntegrationProbe.shared.record(.terminationReply(shouldTerminate))
        }
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
                let sentryActionKind = VoyagerShared.DAUEntryActionKind(rawValue: actionKind.rawValue)
                let sentryEntryKind = VoyagerShared.DAUEntryKind(rawValue: entryKind.rawValue)
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
            requestNewTab: { [appRootStore] _ in
                appRootStore.send(.windowManager(.file(.newTab)))
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
