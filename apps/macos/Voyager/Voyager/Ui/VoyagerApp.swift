import AppKit
import ComposableArchitecture
import Foundation
import Logging
import SwiftUI
import VoyagerEntitiesCollection
import VoyagerFeaturesAiChat
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
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

nonisolated private let entryCanonicalMetricKeys: [EntryInteractionIdentity: String] = [
    .openEntryWithDefaultApp: "voy_691_eop_001_open_entry_with_default_app",
    .openEntryWithSelectedApp: "voy_691_eop_001_open_entry_with_selected_app",
    .quickLookEntry: "voy_691_eop_001_quick_look_entry",
    .copyEntries: "voy_691_eop_002_copy_entries",
    .createEntryAlias: "voy_691_eop_002_create_entry_alias",
    .createNewFolder: "voy_691_eop_002_create_new_folder",
    .cutEntries: "voy_691_eop_002_cut_entries",
    .duplicateEntries: "voy_691_eop_002_duplicate_entries",
    .moveEntries: "voy_691_eop_002_move_entries",
    .pasteEntries: "voy_691_eop_002_paste_entries",
    .deleteEntriesImmediately: "voy_691_eop_003_delete_entries_immediately",
    .emptyTrash: "voy_691_eop_003_empty_trash",
    .moveEntriesToTrash: "voy_691_eop_003_move_entries_to_trash",
    .putDeletedEntriesBack: "voy_691_eop_003_put_deleted_entries_back",
    .editEntryTags: "voy_691_eop_004_edit_entry_tags",
    .renameEntry: "voy_691_eop_004_rename_entry",
    .copyAbsolutePaths: "voy_691_eop_006_copy_absolute_paths_of_entries",
    .copyURLs: "voy_691_eop_006_copy_urls_of_entries",
    .revealEntriesInFinder: "voy_691_eop_007_reveal_entries_in_finder",
    .shareEntries: "voy_691_eop_007_share_entries_via_system_share_sheet",
]

@main
struct VoyagerApp: App {
    struct ProductAnalyticsDependencies {
        let client: ProductAnalyticsClient
        let onboarding: OnboardingProductMetricsClient
        let aiChat: AiChatProductMetricsClient
        let fileManagerProduct: FileManagerProductMetricsClient
        let composer: ComposerMetricClient
        let collection: CollectionMetricClient
        let fileManager: MetricsClient
    }

    private struct ProductAnalyticsCaptureContext {
        let client: ProductAnalyticsClient
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
            $0.composerMetricClient = analytics.composer
            $0.collectionMetricClient = analytics.collection
            $0.onboardingProductMetricsClient = analytics.onboarding
            $0.aiChatProductMetricsClient = analytics.aiChat
            $0.fileManagerProductMetricsClient = analytics.fileManagerProduct
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

    static func makeProductAnalyticsDependencies(
        environment: EnvironmentLoader.AppEnv,
    ) -> ProductAnalyticsDependencies {
        let registry = ProductAnalyticsRegistry.load()
        let client = ProductAnalyticsBootstrap.makeClient(registry: registry)
        let context = ProductAnalyticsCaptureContext(
            client: client,
            environment: environment,
        )
        return ProductAnalyticsDependencies(
            client: client,
            onboarding: makeOnboardingProductMetricsClient(client: client, environment: environment),
            aiChat: makeAiChatProductMetricsClient(client: client, environment: environment),
            fileManagerProduct: makeFileManagerProductMetricsClient(client: client, environment: environment),
            composer: makeComposerMetricClient(client: client, environment: environment),
            collection: makeCollectionMetricClient(context: context),
            fileManager: makeFileManagerMetricsClient(context: context),
        )
    }

    static func makeOnboardingProductMetricsClient(
        client: ProductAnalyticsClient,
        environment: EnvironmentLoader.AppEnv,
    ) -> OnboardingProductMetricsClient {
        OnboardingProductMetricsClient { metric in
            switch metric {
            case let .completion(operationID, .success):
                captureProductMetric(
                    "voy_691_onb_001_complete_onboarding_session",
                    properties: ["result_status": .string("success"), "source_surface": .string("onboarding")],
                    eventVersion: "1",
                    operationID: operationID,
                    client: client,
                    environment: environment,
                )
            case .completion(_, .failure):
                return
            case let .helperFolderAccess(operationID, result):
                captureProductMetric(
                    "voy_691_onb_003_request_onboarding_permission_access",
                    properties: [
                        "result_status": .string(result.rawValue),
                        "permission_kind": .string("helper_folder_access"),
                        "source_surface": .string("onboarding"),
                    ],
                    eventVersion: "1",
                    operationID: operationID,
                    client: client,
                    environment: environment,
                )
            case let .fullDiskAccess(operationID, result):
                captureProductMetric(
                    "voy_691_onb_003_request_onboarding_permission_access",
                    properties: [
                        "result_status": .string(result.rawValue),
                        "permission_kind": .string("full_disk_access"),
                        "source_surface": .string("onboarding"),
                    ],
                    eventVersion: "1",
                    operationID: operationID,
                    client: client,
                    environment: environment,
                )
            case let .aiProviderWithKind(operationID, provider, result):
                var properties: [String: ProductAnalyticsPropertyValue] = [
                    "result_status": .string(result.rawValue),
                    "source_surface": .string("onboarding"),
                ]
                if let provider {
                    properties["provider_kind"] = .string(provider.rawValue)
                }
                // provider 미확정 success/failure는 이벤트가 없고, skipped는 provider 유무와 무관하게
                // skip interaction key로 사상한다. success/failure는 start key를 유지한다.
                guard provider != nil || result == .skipped else { return }
                captureProductMetric(
                    Self.aiProviderCanonicalMetricKey(result),
                    properties: properties,
                    eventVersion: "1",
                    operationID: operationID,
                    client: client,
                    environment: environment,
                )
            case let .aiProvider(operationID, result):
                guard result == .skipped else { return }
                captureProductMetric(
                    Self.aiProviderCanonicalMetricKey(result),
                    properties: [
                        "result_status": .string(result.rawValue),
                        "source_surface": .string("onboarding"),
                    ],
                    eventVersion: "1",
                    operationID: operationID,
                    client: client,
                    environment: environment,
                )
            }
        }
    }

    /// Content Tab identity를 registry의 implemented canonical key로 사상한다.
    nonisolated static func contentTabCanonicalMetricKey(_ identity: ContentTabInteractionIdentity) -> String {
        switch identity {
        case .pinContentTabs:
            "voy_691_ctm_003_pin_content_tab_s"
        case .unpinContentTabs:
            "voy_691_ctm_003_unpin_content_tab_s"
        case .closeSelectedContentTabs:
            "voy_691_ctm_001_close_selected_content_tabs"
        case .openNewContentTab, .closeContentTab, .duplicateContentTab,
             .duplicateSelectedContentTabs, .restoreLastClosedTab, .reorderContentTab,
             .reorderSelectedContentTabs, .moveContentTabToAnotherWindow,
             .moveSelectedContentTabsToAnotherWindow:
            contentTabLifecycleCanonicalMetricKey(identity)
        }
    }

    nonisolated static func entryCanonicalMetricKey(_ identity: EntryInteractionIdentity) -> String? {
        entryCanonicalMetricKeys[identity]
    }

    nonisolated static func contentBrowsingCanonicalMetricKey(
        _ identity: ContentPageNavigationInteractionIdentity,
    ) -> String? {
        switch identity {
        case .direct:
            "voy_691_evm_001_navigate_pages"
        case .back:
            "voy_691_evm_001_go_page_history_back"
        case .forward:
            "voy_691_evm_001_forward_page_history"
        case .enclosingDirectory:
            "voy_691_evm_001_go_to_enclosing_directory"
        case .history:
            nil
        }
    }

    /// CTM-001 상호작용의 canonical key 사상.
    nonisolated private static func contentTabLifecycleCanonicalMetricKey(
        _ identity: ContentTabInteractionIdentity,
    ) -> String {
        switch identity {
        case .openNewContentTab:
            "voy_691_ctm_001_open_new_content_tab"
        case .closeContentTab:
            "voy_691_ctm_001_close_content_tab"
        case .duplicateContentTab:
            "voy_691_ctm_001_duplicate_content_tab"
        case .duplicateSelectedContentTabs:
            "voy_691_ctm_001_duplicate_selected_content_tabs"
        case .restoreLastClosedTab:
            "voy_691_ctm_001_restore_last_closed_tab"
        case .reorderContentTab:
            "voy_691_ctm_001_reorder_content_tab"
        case .reorderSelectedContentTabs:
            "voy_691_ctm_001_reorder_selected_content_tabs"
        case .moveContentTabToAnotherWindow:
            "voy_691_ctm_001_move_content_tab_to_another_file_manager_window"
        case .moveSelectedContentTabsToAnotherWindow:
            "voy_691_ctm_001_move_selected_content_tabs_to_another_file_manager_window"
        case .closeSelectedContentTabs, .pinContentTabs, .unpinContentTabs:
            // CTM-003 key는 상위 함수가 소유한다.
            contentTabCanonicalMetricKey(identity)
        }
    }

    /// skipped는 skip interaction, success/failure는 start interaction이다.
    nonisolated private static func aiProviderCanonicalMetricKey(
        _ result: OnboardingProductMetric.AIProviderResult,
    ) -> String {
        result == .skipped
            ? "voy_691_onb_004_skip_ai_provider_setup_during_onboarding"
            : "voy_691_onb_004_start_ai_provider_connection_from_onboarding"
    }

    static func makeFileManagerProductMetricsClient(
        client: ProductAnalyticsClient,
        environment: EnvironmentLoader.AppEnv,
    ) -> FileManagerProductMetricsClient {
        FileManagerProductMetricsClient { metric in
            let request: (String, [String: ProductAnalyticsPropertyValue], UUID)? = switch metric {
            case let .contentBrowsing(result, content, identity, source, operationID):
                Self.contentBrowsingCanonicalMetricKey(identity).map { key in
                    (key, [
                        "result_status": .string(result.rawValue),
                        "content_kind": .string(content.rawValue),
                        "source_surface": .string(source.rawValue),
                    ], operationID)
                }
            case let .contentTabAction(result, identity, source, operationID):
                (Self.contentTabCanonicalMetricKey(identity), [
                    "result_status": .string(result.rawValue),
                    "action_type": .string(identity.actionType),
                    "source_surface": .string(source.rawValue),
                ], operationID)
            case let .entryAction(metric):
                Self.entryCanonicalMetricKey(metric.identity).map { key in
                    (key, [
                        "result_status": .string(metric.result.rawValue),
                        "action_type": .string(metric.identity.actionType),
                        "source_surface": .string(metric.source.rawValue),
                    ], metric.operationID)
                }
            }
            guard let request else { return }
            captureProductMetric(
                request.0,
                properties: request.1,
                eventVersion: "1",
                operationID: request.2,
                client: client,
                environment: environment,
            )
        }
    }

    static func makeAiChatProductMetricsClient(
        client: ProductAnalyticsClient,
        environment: EnvironmentLoader.AppEnv,
    ) -> AiChatProductMetricsClient {
        AiChatProductMetricsClient { metric in
            let request: (String, [String: ProductAnalyticsPropertyValue], UUID) = switch metric {
            case let .turnSubmitted(operationID, source):
                ("voy_691_cbw_001_submit_chat_request", [
                    "result_status": .string("accepted"),
                    "source_surface": .string(source.rawValue),
                ], operationID)
            case let .turnResult(operationID, interaction, result, source):
                (Self.aiChatResultCanonicalMetricKey(interaction), [
                    "result_status": .string(result.rawValue),
                    "source_surface": .string(source.rawValue),
                ], operationID)
            }
            captureProductMetric(
                request.0,
                properties: request.1,
                eventVersion: "1",
                operationID: request.2,
                client: client,
                environment: environment,
            )
        }
    }

    nonisolated private static func aiChatResultCanonicalMetricKey(
        _ interaction: AiChatProductMetricInteractionIdentity,
    ) -> String {
        switch interaction {
        case .generateContextualChatResponse:
            "voy_691_cbw_003_generate_contextual_chat_response"
        case .cancelActiveChatRequest:
            "voy_691_cbw_001_cancel_active_chat_request"
        }
    }

    static func makeComposerMetricClient(
        client: ProductAnalyticsClient,
        environment: EnvironmentLoader.AppEnv,
    ) -> ComposerMetricClient {
        ComposerMetricClient(recordProductMetric: { metric in
            switch metric {
            case let .queryResult(operationID, result, durationMilliseconds):
                captureComposerProductMetric(
                    metricKey: "voy_691_rcl_004_generate_filter_changes_from_query",
                    result: result,
                    durationMilliseconds: durationMilliseconds,
                    operationID: operationID,
                    client: client,
                    environment: environment,
                )
            case let .applyResult(operationID, result, durationMilliseconds):
                captureComposerProductMetric(
                    metricKey: "voy_691_rcl_004_apply_generated_filter_changes",
                    result: result,
                    durationMilliseconds: durationMilliseconds,
                    operationID: operationID,
                    client: client,
                    environment: environment,
                )
            }
        })
    }

    nonisolated private static func captureComposerProductMetric(
        metricKey: String,
        result: ComposerProductMetricResult,
        durationMilliseconds: Int?,
        operationID: UUID,
        client: ProductAnalyticsClient,
        environment: EnvironmentLoader.AppEnv,
    ) {
        var properties: [String: ProductAnalyticsPropertyValue] = [
            "result_status": .string(result.rawValue),
            "source_surface": .string("composer"),
        ]
        if let durationMilliseconds,
           (0 ... 86_400_000).contains(durationMilliseconds)
        {
            properties["duration_ms"] = .integer(durationMilliseconds)
        }
        captureProductMetric(
            metricKey,
            properties: properties,
            eventVersion: "2",
            operationID: operationID,
            client: client,
            environment: environment,
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
            logDAUNavigation: { _ in },
            logDAUEntryAction: { _, _ in },
        )
    }

    nonisolated private static func captureProductMetric(
        _ name: String,
        value: Double,
        tags: [String: String]?,
        context: ProductAnalyticsCaptureContext,
    ) {
        let eventContext = makeProductAnalyticsEventContext(environment: context.environment)
        context.client.captureMetric(.init(
            metricKey: name,
            properties: productMetricProperties(name: name, value: value, tags: tags),
            context: eventContext,
        ))
    }

    nonisolated private static func captureProductMetric(
        _ name: String,
        properties: [String: ProductAnalyticsPropertyValue],
        eventVersion: String,
        operationID: UUID,
        client: ProductAnalyticsClient,
        environment: EnvironmentLoader.AppEnv,
    ) {
        client.captureMetric(.init(
            metricKey: name,
            properties: properties,
            context: makeProductAnalyticsEventContext(environment: environment),
            eventVersion: .init(rawValue: eventVersion),
            operationID: operationID,
        ))
    }

    nonisolated static func makeProductAnalyticsEventContext(
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
