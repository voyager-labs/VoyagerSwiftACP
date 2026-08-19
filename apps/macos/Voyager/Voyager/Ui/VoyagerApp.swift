import AppKit
import ComposableArchitecture
import Foundation
import Logging
import SwiftUI
import VoyagerEntitiesCollection
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
    private struct ProductAnalyticsDependencies {
        let client: ProductAnalyticsClient
        let composer: ComposerMetricClient
        let collection: CollectionMetricClient
        let fileManager: MetricsClient
    }

    private struct ProductAnalyticsCaptureContext {
        let client: ProductAnalyticsClient
        let registry: ProductAnalyticsRegistry
        let environment: EnvironmentLoader.AppEnv
    }

    private let appRootStore: StoreOf<AppRootFeature>

    @NSApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate

    @MainActor
    init() {
        let appRootStoreReference = AppRootStoreReference()
        let fileOperationUndoManagerRegistry = FileOperationUndoManagerRegistry()
        let workspaceClient = WorkspaceClient.liveValue
        let fileManagerWindowClient = makeFileManagerWindowClientLive(
            fileOperationUndoManagerRegistry: fileOperationUndoManagerRegistry,
            workspaceClient: workspaceClient,
        )
        try? EnvironmentLoader.loadEnvFiles()
        let analytics = Self.makeProductAnalyticsDependencies(environment: EnvironmentLoader.detectAppEnv())

        appRootStore = Store(initialState: AppRootState()) {
            AppRootFeature()
        } withDependencies: {
            $0.productAnalyticsClient = analytics.client
            $0.composerMetricClient = analytics.composer
            $0.collectionMetricClient = analytics.collection
            $0.onboardingWindowClient = OnboardingWindowClient.makeMainApp(
                openMainWindow: { _ in
                    await appRootStoreReference.openInitialWindowIfNeeded()
                    return true
                },
            )
            $0.fileManagerWindowClient = fileManagerWindowClient
            $0.fileOperationUndoManagerClient = .live(registry: fileOperationUndoManagerRegistry)
            $0.undoManagerClient = Self.makeUndoManagerClient(
                fileOperationUndoManagerRegistry: fileOperationUndoManagerRegistry,
                resolveScope: { windowID in
                    guard let store = appRootStoreReference.store else { return nil }
                    return store.withState { state in
                        guard let window = state.windowManager.windows[id: windowID]?.window,
                              let activeTabID = window.contentTabs.activeTabID
                        else { return nil }
                        return UndoManagerScope(
                            windowID: windowID,
                            contentTabID: activeTabID.rawValue,
                        )
                    }
                },
            )
            $0.metricsClient = analytics.fileManager
            $0.workspaceClient = workspaceClient
        }
        appRootStoreReference.store = appRootStore
        configureFileManagerWindowCallbacks()
        appDelegate.configure(appRootStore: appRootStore)
        configureLogging()
    }

    static func makeUndoManagerClient(
        fileOperationUndoManagerRegistry: FileOperationUndoManagerRegistry,
        resolveScope: @escaping @MainActor @Sendable (UUID) -> UndoManagerScope?,
    ) -> UndoManagerClient {
        .live(
            registry: fileOperationUndoManagerRegistry,
            resolveScope: resolveScope,
        )
    }

    private static func makeProductAnalyticsDependencies(
        environment: EnvironmentLoader.AppEnv,
    ) -> ProductAnalyticsDependencies {
        let client = ProductAnalyticsBootstrap.makeClient()
        let registry = ProductAnalyticsRegistry.load()
        let context = ProductAnalyticsCaptureContext(
            client: client,
            registry: registry,
            environment: environment,
        )
        return ProductAnalyticsDependencies(
            client: client,
            composer: makeComposerMetricClient(context: context),
            collection: makeCollectionMetricClient(context: context),
            fileManager: makeFileManagerMetricsClient(context: context),
        )
    }

    private static func makeComposerMetricClient(
        context: ProductAnalyticsCaptureContext,
    ) -> ComposerMetricClient {
        ComposerMetricClient { name, value, tags, _ in
            captureProductMetric(
                name,
                value: value,
                tags: tags,
                context: context,
            )
        }
    }

    private static func makeCollectionMetricClient(
        context: ProductAnalyticsCaptureContext,
    ) -> CollectionMetricClient {
        CollectionMetricClient { name, value, tags, _ in
            captureProductMetric(
                name,
                value: value,
                tags: tags,
                context: context,
            )
        }
    }

    private static func makeFileManagerMetricsClient(
        context: ProductAnalyticsCaptureContext,
    ) -> MetricsClient {
        .init(
            logMetric: { name, value, tags in
                captureProductMetric(
                    name,
                    value: value,
                    tags: tags,
                    context: context,
                )
            },
            logDAUNavigation: { kind in
                captureProductMetric(
                    "dau.navigation",
                    value: 1,
                    tags: ["source_surface": kind.rawValue],
                    context: context,
                )
            },
            logDAUEntryAction: { actionKind, entryKind in
                captureProductMetric(
                    "dau.entry_action",
                    value: 1,
                    tags: [
                        "source_surface": actionKind.rawValue,
                        "result_status": entryKind.rawValue,
                    ],
                    context: context,
                )
            },
        )
    }

    nonisolated private static func captureProductMetric(
        _ name: String,
        value: Double,
        tags: [String: String]?,
        context: ProductAnalyticsCaptureContext,
    ) {
        Task {
            let identity = await context.client.deviceIdentity()
            let result = await context.registry.resolve(
                metricKey: name,
                identity: .device(identity),
                context: makeProductAnalyticsEventContext(environment: context.environment),
                properties: productMetricProperties(name: name, value: value, tags: tags),
            )
            if case let .capture(request) = result {
                context.client.captureEvent(request)
            }
        }
    }

    static func makeProductAnalyticsEventContext(
        environment: EnvironmentLoader.AppEnv,
        occurredAtUTC: Date = Date(),
    ) -> ProductAnalyticsEventContext {
        ProductAnalyticsEventContext(
            occurredAtUTC: occurredAtUTC,
            environment: environment.rawValue,
            appVersion: AppVersionInfo.shortVersion,
            platform: "macOS",
            source: "app",
            sourceProject: "app",
        )
    }

    nonisolated static func productMetricProperties(
        name: String,
        value: Double,
        tags: [String: String]?,
    ) -> [String: ProductAnalyticsPropertyValue] {
        var properties: [String: ProductAnalyticsPropertyValue] = [:]
        if let identity = tags?["identity"] {
            properties["source_surface"] = .string(identity)
        }
        if name.contains("duration_ms"), value >= 0, value <= Double(Int.max) {
            properties["duration_ms"] = .integer(Int(value.rounded()))
        }
        for (key, value) in tags ?? [:] {
            guard key != "identity" else { continue }
            let mappedKey: String? = switch key {
            case "source", "source_surface": "source_surface"
            case "outcome", "result", "result_status": "result_status"
            case "reason", "failure_reason": "failure_reason"
            default: nil
            }
            if let mappedKey {
                properties[mappedKey] = .string(value)
            }
        }
        return properties
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
