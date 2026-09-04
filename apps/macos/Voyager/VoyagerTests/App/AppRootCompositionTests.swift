import Clocks
import ComposableArchitecture
import Dependencies
@testable import Voyager
import VoyagerEntitiesCollection
import VoyagerEntryCoreClient
import VoyagerFeaturesAccountAccess
import VoyagerFeaturesAiChat
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerFeaturesExternalFileRouter
import VoyagerFeaturesUpdateVersion
import VoyagerPagesFileManager
import VoyagerPagesOnboarding
@testable import VoyagerPagesSettings
import VoyagerShared
import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class AppRootCompositionTests: XCTestCase {
    func testOnboardingProductMetricBridgeCapturesCanonicalRequestOnce() {
        let requests = LockIsolated<[ProductAnalyticsMetricRequest]>([])
        let client = ProductAnalyticsClient { request in requests.withValue { $0.append(request) } }
        let operationID = UUID()

        VoyagerApp.makeOnboardingProductMetricsClient(client: client, environment: .dev)
            .record(.completion(operationID: operationID, result: .success))

        XCTAssertEqual(requests.value.count, 1)
        XCTAssertEqual(requests.value.first?.metricKey, "voy_691_onb_001_complete_onboarding_session")
        XCTAssertEqual(requests.value.first?.eventVersion.rawValue, "1")
        XCTAssertEqual(requests.value.first?.operationID, operationID)
        XCTAssertEqual(requests.value.first?.properties["result_status"], .string("success"))
        XCTAssertEqual(requests.value.first?.properties["source_surface"], .string("onboarding"))
    }

    func testOnboardingCompletionFailureIsApprovedNoEvent() {
        let requests = LockIsolated<[ProductAnalyticsMetricRequest]>([])
        let client = ProductAnalyticsClient { request in requests.withValue { $0.append(request) } }

        VoyagerApp.makeOnboardingProductMetricsClient(client: client, environment: .dev)
            .record(.completion(operationID: UUID(), result: .failure))

        XCTAssertTrue(requests.value.isEmpty)
    }

    /// provider-independent skipped는 start가 아니라 skip canonical key로 기록된다.
    /// - 검증 내용: `.aiProvider(.skipped)`의 skip metricKey와 result_status/source_surface
    /// - 사전 조건: adapter 주입 client
    /// - 기대 결과: voy_691_onb_004_skip_ai_provider_setup_during_onboarding 1건
    func testOnboardingSkippedAIProviderUsesSkipCanonicalKey() {
        let requests = LockIsolated<[ProductAnalyticsMetricRequest]>([])
        let client = ProductAnalyticsClient { request in requests.withValue { $0.append(request) } }
        let operationID = UUID()

        VoyagerApp.makeOnboardingProductMetricsClient(client: client, environment: .dev)
            .record(.aiProvider(operationID: operationID, result: .skipped))

        XCTAssertEqual(requests.value.count, 1)
        XCTAssertEqual(
            requests.value.first?.metricKey,
            "voy_691_onb_004_skip_ai_provider_setup_during_onboarding",
        )
        XCTAssertEqual(requests.value.first?.operationID, operationID)
        XCTAssertEqual(requests.value.first?.properties["result_status"], .string("skipped"))
        XCTAssertEqual(requests.value.first?.properties["source_surface"], .string("onboarding"))
    }

    /// provider-nil skipped도 skip key로, success/failure는 start key를 유지한다.
    /// - 검증 내용: WithKind nil+skipped → skip key(provider_kind 없음), kind+success → start key,
    ///   nil+failure → 무이벤트
    /// - 사전 조건: adapter 주입 client
    /// - 기대 결과: 세 케이스의 key/property 계약 일치
    func testOnboardingAIProviderWithKindSkipsMapToSkipKeyAndSuccessKeepsStartKey() {
        let requests = LockIsolated<[ProductAnalyticsMetricRequest]>([])
        let client = ProductAnalyticsClient { request in requests.withValue { $0.append(request) } }
        let recordClient = VoyagerApp.makeOnboardingProductMetricsClient(client: client, environment: .dev)

        recordClient.record(.aiProviderWithKind(operationID: UUID(), provider: nil, result: .skipped))
        recordClient.record(.aiProviderWithKind(operationID: UUID(), provider: .openai, result: .success))
        recordClient.record(.aiProviderWithKind(operationID: UUID(), provider: nil, result: .failure))

        XCTAssertEqual(requests.value.count, 2)
        XCTAssertEqual(
            requests.value[0].metricKey,
            "voy_691_onb_004_skip_ai_provider_setup_during_onboarding",
        )
        XCTAssertNil(requests.value[0].properties["provider_kind"])
        XCTAssertEqual(requests.value[0].properties["result_status"], .string("skipped"))
        XCTAssertEqual(
            requests.value[1].metricKey,
            "voy_691_onb_004_start_ai_provider_connection_from_onboarding",
        )
        XCTAssertEqual(requests.value[1].properties["provider_kind"], .string("openai"))
        XCTAssertEqual(requests.value[1].properties["result_status"], .string("success"))
    }

    func testFileManagerProductMetricBridgeCapturesCanonicalRequestOnce() {
        let requests = LockIsolated<[ProductAnalyticsMetricRequest]>([])
        let client = ProductAnalyticsClient { request in requests.withValue { $0.append(request) } }
        let operationID = UUID()

        VoyagerApp.makeFileManagerProductMetricsClient(client: client, environment: .dev)
            .record(.contentTabAction(
                result: .success,
                identity: .openNewContentTab,
                source: .contentTabBar,
                operationID: operationID,
            ))

        XCTAssertEqual(requests.value.count, 1)
        XCTAssertEqual(requests.value.first?.metricKey, "voy_691_ctm_001_open_new_content_tab")
        XCTAssertEqual(requests.value.first?.eventVersion.rawValue, "1")
        XCTAssertEqual(requests.value.first?.operationID, operationID)
        XCTAssertEqual(requests.value.first?.properties["result_status"], .string("success"))
        XCTAssertEqual(requests.value.first?.properties["action_type"], .string("open"))
        XCTAssertEqual(requests.value.first?.properties["source_surface"], .string("content_tab_bar"))
    }

    /// Content Tab identity별 canonical key 사상이 registry의 implemented key와 1:1로 대응하는지 검증한다.
    /// action_type 단독으로는 interaction을 특정할 수 없으므로 identity가 유일한 정규 소스다.
    /// - 검증 내용: 11개 identity 전부가 서로 다른 implemented metricKey로 기록되고 registry resolve에 성공함
    /// - 사전 조건: host bundle registry와 adapter 주입 client
    /// - 기대 결과: identity→key 매트릭스 일치, 모든 요소 registry capture 통과
    func testFileManagerContentTabIdentitiesMapToDistinctCanonicalRegistryKeys() throws {
        let expectedKeys: [ContentTabInteractionIdentity: String] = [
            .openNewContentTab: "voy_691_ctm_001_open_new_content_tab",
            .closeContentTab: "voy_691_ctm_001_close_content_tab",
            .duplicateContentTab: "voy_691_ctm_001_duplicate_content_tab",
            .duplicateSelectedContentTabs: "voy_691_ctm_001_duplicate_selected_content_tabs",
            .restoreLastClosedTab: "voy_691_ctm_001_restore_last_closed_tab",
            .reorderContentTab: "voy_691_ctm_001_reorder_content_tab",
            .reorderSelectedContentTabs: "voy_691_ctm_001_reorder_selected_content_tabs",
            .moveContentTabToAnotherWindow:
                "voy_691_ctm_001_move_content_tab_to_another_file_manager_window",
            .moveSelectedContentTabsToAnotherWindow:
                "voy_691_ctm_001_move_selected_content_tabs_to_another_file_manager_window",
            .pinContentTabs: "voy_691_ctm_003_pin_content_tab_s",
            .unpinContentTabs: "voy_691_ctm_003_unpin_content_tab_s",
        ]
        let identities: [ContentTabInteractionIdentity] = [
            .openNewContentTab,
            .closeContentTab,
            .duplicateContentTab,
            .duplicateSelectedContentTabs,
            .restoreLastClosedTab,
            .reorderContentTab,
            .reorderSelectedContentTabs,
            .moveContentTabToAnotherWindow,
            .moveSelectedContentTabsToAnotherWindow,
            .pinContentTabs,
            .unpinContentTabs,
        ]
        XCTAssertEqual(identities.count, expectedKeys.count)

        let requests = LockIsolated<[ProductAnalyticsMetricRequest]>([])
        let client = ProductAnalyticsClient { request in requests.withValue { $0.append(request) } }
        let recordClient = VoyagerApp.makeFileManagerProductMetricsClient(client: client, environment: .dev)
        for (index, identity) in identities.enumerated() {
            recordClient.record(.contentTabAction(
                result: .success,
                identity: identity,
                source: .contentTabBar,
                operationID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9, UInt8(index + 1))),
            ))
        }
        let recorded = requests.value
        XCTAssertEqual(recorded.count, identities.count)
        XCTAssertEqual(Set(recorded.map(\.metricKey)).count, identities.count)

        let registry = ProductAnalyticsRegistry.load(bundle: VoyagerTestSupport.hostApplicationBundle())
        for (index, identity) in identities.enumerated() {
            let request = recorded[index]
            XCTAssertEqual(request.metricKey, try XCTUnwrap(expectedKeys[identity]))
            XCTAssertEqual(request.properties["action_type"], .string(identity.actionType))
            let result = registry.resolve(
                metricKey: request.metricKey,
                identity: .device("test-device-id"),
                context: request.context,
                properties: request.properties,
                eventVersion: request.eventVersion,
                operationID: request.operationID,
            )
            guard case .capture = result else {
                return XCTFail("identity metric did not resolve: \(request.metricKey), result: \(result)")
            }
        }
    }

    /// EOP-001-quick_look_entry: Entry terminal identity는 exact implemented registry key로 사상된다.
    /// action_type fallback이 Quick Look을 open-default interaction으로 오염시키지 않는지 검증한다.
    /// - 검증 내용: Quick Look metric request의 key, operation ID, registry resolve 결과를 비교한다.
    /// - 사전 조건: 성공 Quick Look terminal과 keyboard source가 있다.
    /// - 기대 결과: `voy_691_eop_001_quick_look_entry` 한 건이 registry capture로 resolve된다.
    func testFileManagerQuickLookMapsToExactCanonicalRegistryKey() {
        let requests = LockIsolated<[ProductAnalyticsMetricRequest]>([])
        let client = ProductAnalyticsClient { request in requests.withValue { $0.append(request) } }
        let operationID = UUID()

        VoyagerApp.makeFileManagerProductMetricsClient(client: client, environment: .dev)
            .record(.entryAction(
                result: .success,
                identity: .quickLookEntry,
                source: .keyboardShortcut,
                operationID: operationID,
                aggregate: .init(attempted: 1, succeeded: 1, failed: 0),
            ))

        XCTAssertEqual(requests.value.count, 1)
        let request = requests.value[0]
        XCTAssertEqual(request.metricKey, "voy_691_eop_001_quick_look_entry")
        XCTAssertEqual(request.operationID, operationID)
        let result = ProductAnalyticsRegistry.load(bundle: VoyagerTestSupport.hostApplicationBundle()).resolve(
            metricKey: request.metricKey,
            identity: .device("test-device-id"),
            context: request.context,
            properties: request.properties,
            eventVersion: request.eventVersion,
            operationID: request.operationID,
        )
        guard case .capture = result else {
            return XCTFail("Quick Look metric did not resolve: \(result)")
        }
    }

    /// EOP-005-compress_entries: registry에 implemented key가 없는 Entry identity는 Product event를 만들지 않는다.
    /// unsupported identity가 open-default key로 fallback하지 않는 fail-closed adapter 계약을 검증한다.
    /// - 검증 내용: compress terminal 기록 후 ProductAnalytics request 수를 확인한다.
    /// - 사전 조건: SDK-neutral compress identity와 성공 terminal이 있다.
    /// - 기대 결과: capture request가 0건이다.
    func testUnsupportedEntryIdentityDoesNotFallBackToOpenDefault() {
        let requests = LockIsolated<[ProductAnalyticsMetricRequest]>([])
        let client = ProductAnalyticsClient { request in requests.withValue { $0.append(request) } }

        VoyagerApp.makeFileManagerProductMetricsClient(client: client, environment: .dev)
            .record(.entryAction(
                result: .success,
                identity: .compressEntries,
                source: .contextMenu,
                operationID: UUID(),
                aggregate: .init(attempted: 1, succeeded: 1, failed: 0),
            ))

        XCTAssertTrue(requests.value.isEmpty)
    }

    /// EOP-001-entry_command_terminal: implemented Entry identity는 기존 canonical registry key에만 사상된다.
    /// SDK-neutral identity 전 집합의 adapter key가 registry catalog와 정확히 일치하는지 검증한다.
    /// - 검증 내용: implemented identity/key 행렬과 unsupported nil 집합을 비교한다.
    /// - 사전 조건: registry 변경 없이 현재 EOP-001/002/003/004/006/007 implemented key를 사용한다.
    /// - 기대 결과: implemented 20개는 exact key, unsupported 4개는 nil이다.
    func testFileManagerEntryIdentitiesMapOnlyToImplementedCanonicalKeys() {
        let implemented: [(EntryInteractionIdentity, String)] = [
            (.openEntryWithDefaultApp, "voy_691_eop_001_open_entry_with_default_app"),
            (.openEntryWithSelectedApp, "voy_691_eop_001_open_entry_with_selected_app"),
            (.quickLookEntry, "voy_691_eop_001_quick_look_entry"),
            (.copyEntries, "voy_691_eop_002_copy_entries"),
            (.createEntryAlias, "voy_691_eop_002_create_entry_alias"),
            (.createNewFolder, "voy_691_eop_002_create_new_folder"),
            (.cutEntries, "voy_691_eop_002_cut_entries"),
            (.duplicateEntries, "voy_691_eop_002_duplicate_entries"),
            (.moveEntries, "voy_691_eop_002_move_entries"),
            (.pasteEntries, "voy_691_eop_002_paste_entries"),
            (.deleteEntriesImmediately, "voy_691_eop_003_delete_entries_immediately"),
            (.emptyTrash, "voy_691_eop_003_empty_trash"),
            (.moveEntriesToTrash, "voy_691_eop_003_move_entries_to_trash"),
            (.putDeletedEntriesBack, "voy_691_eop_003_put_deleted_entries_back"),
            (.editEntryTags, "voy_691_eop_004_edit_entry_tags"),
            (.renameEntry, "voy_691_eop_004_rename_entry"),
            (.copyAbsolutePaths, "voy_691_eop_006_copy_absolute_paths_of_entries"),
            (.copyURLs, "voy_691_eop_006_copy_urls_of_entries"),
            (.revealEntriesInFinder, "voy_691_eop_007_reveal_entries_in_finder"),
            (.shareEntries, "voy_691_eop_007_share_entries_via_system_share_sheet"),
        ]
        for (identity, key) in implemented {
            XCTAssertEqual(VoyagerApp.entryCanonicalMetricKey(identity), key)
        }
        for identity in [
            EntryInteractionIdentity.getEntryInfo,
            .performService,
            .compressEntries,
            .extractEntries,
        ] {
            XCTAssertNil(VoyagerApp.entryCanonicalMetricKey(identity))
        }
    }

    func testAiChatProductMetricBridgeCapturesCanonicalRequestOnce() {
        let requests = LockIsolated<[ProductAnalyticsMetricRequest]>([])
        let client = ProductAnalyticsClient { request in requests.withValue { $0.append(request) } }
        let operationID = UUID()

        VoyagerApp.makeAiChatProductMetricsClient(client: client, environment: .dev)
            .record(.turnResult(
                operationID: operationID,
                interaction: .generateContextualChatResponse,
                result: .success,
                sourceSurface: .aiChatContent,
            ))

        XCTAssertEqual(requests.value.count, 1)
        XCTAssertEqual(requests.value.first?.metricKey, "voy_691_cbw_003_generate_contextual_chat_response")
        XCTAssertEqual(requests.value.first?.eventVersion.rawValue, "1")
        XCTAssertEqual(requests.value.first?.operationID, operationID)
        XCTAssertEqual(requests.value.first?.properties["result_status"], .string("success"))
        XCTAssertEqual(requests.value.first?.properties["source_surface"], .string("ai_chat_content"))
    }

    func testAiChatExplicitCancelResolvesThroughCanonicalRegistryKey() {
        let requests = LockIsolated<[ProductAnalyticsMetricRequest]>([])
        let client = ProductAnalyticsClient { request in requests.withValue { $0.append(request) } }
        let operationID = UUID()

        VoyagerApp.makeAiChatProductMetricsClient(client: client, environment: .dev)
            .record(.turnResult(
                operationID: operationID,
                interaction: .cancelActiveChatRequest,
                result: .cancelled,
                sourceSurface: .aiChatInspector,
            ))

        let request = requests.value[0]
        XCTAssertEqual(request.metricKey, "voy_691_cbw_001_cancel_active_chat_request")
        XCTAssertEqual(request.operationID, operationID)
        XCTAssertEqual(request.properties["result_status"], .string("cancelled"))
        XCTAssertEqual(request.properties["source_surface"], .string("ai_chat_inspector"))

        let result = ProductAnalyticsRegistry.load(bundle: VoyagerTestSupport.hostApplicationBundle()).resolve(
            metricKey: request.metricKey,
            identity: .device("test-device-id"),
            context: request.context,
            properties: request.properties,
            eventVersion: request.eventVersion,
            operationID: request.operationID,
        )
        guard case .capture = result else {
            return XCTFail("explicit cancel metric did not resolve: \(result)")
        }
    }

    func testComposerProductMetricBridgeCapturesCanonicalV2RequestOnce() {
        let requests = LockIsolated<[ProductAnalyticsMetricRequest]>([])
        let client = ProductAnalyticsClient { request in requests.withValue { $0.append(request) } }
        let operationID = UUID()

        VoyagerApp.makeComposerMetricClient(client: client, environment: .dev)
            .record(.queryResult(
                operationID: operationID,
                result: .success,
                durationMilliseconds: 123,
            ))

        XCTAssertEqual(requests.value.count, 1)
        XCTAssertEqual(requests.value.first?.metricKey, "voy_691_rcl_004_generate_filter_changes_from_query")
        XCTAssertEqual(requests.value.first?.eventVersion.rawValue, "2")
        XCTAssertEqual(requests.value.first?.operationID, operationID)
        XCTAssertEqual(requests.value.first?.properties["result_status"], .string("success"))
        XCTAssertEqual(requests.value.first?.properties["source_surface"], .string("composer"))
        XCTAssertEqual(requests.value.first?.properties["duration_ms"], .integer(123))
    }

    func testComposerGenericMetricInitializerDoesNotBridgeTypedProductRequest() {
        let requests = LockIsolated<[ProductAnalyticsMetricRequest]>([])
        let client = ProductAnalyticsClient { request in requests.withValue { $0.append(request) } }
        let operationID = UUID()
        let genericClient = ComposerMetricClient(logMetric: { _, _, _, _ in })

        genericClient.record(.applyResult(
            operationID: operationID,
            result: .success,
            durationMilliseconds: 45,
        ))
        XCTAssertTrue(requests.value.isEmpty)

        VoyagerApp.makeComposerMetricClient(client: client, environment: .dev)
            .record(.applyResult(
                operationID: operationID,
                result: .success,
                durationMilliseconds: 45,
            ))
        XCTAssertEqual(requests.value.count, 1)
        XCTAssertEqual(requests.value.first?.metricKey, "voy_691_rcl_004_apply_generated_filter_changes")
        XCTAssertEqual(requests.value.first?.properties["duration_ms"], .integer(45))
    }

    func testTypedAdaptersResolveThroughCanonicalRegistryKeys() {
        let requests = LockIsolated<[ProductAnalyticsMetricRequest]>([])
        let client = ProductAnalyticsClient { request in requests.withValue { $0.append(request) } }
        let operationIDs = (0 ..< 4).map { _ in UUID() }

        VoyagerApp.makeOnboardingProductMetricsClient(client: client, environment: .dev)
            .record(.completion(operationID: operationIDs[0], result: .success))
        VoyagerApp.makeFileManagerProductMetricsClient(client: client, environment: .dev)
            .record(.contentBrowsing(
                result: .success,
                content: .folder,
                identity: .direct,
                source: .fileManagerContent,
                operationID: operationIDs[1],
            ))
        VoyagerApp.makeAiChatProductMetricsClient(client: client, environment: .dev)
            .record(.turnSubmitted(operationID: operationIDs[2], sourceSurface: .aiChatContent))
        VoyagerApp.makeComposerMetricClient(client: client, environment: .dev)
            .record(.queryResult(operationID: operationIDs[3], result: .success, durationMilliseconds: 12))

        let registry = ProductAnalyticsRegistry.load(bundle: VoyagerTestSupport.hostApplicationBundle())
        let expectedEventNames = [
            "voyager_onboarding_completed",
            "voyager_content_browsing_engaged",
            "voyager_ai_chat_turn_submitted",
            "voyager_collection_filter_query_result",
        ]
        XCTAssertEqual(requests.value.count, expectedEventNames.count)

        for (request, expectedEventName) in zip(requests.value, expectedEventNames) {
            let result = registry.resolve(
                metricKey: request.metricKey,
                identity: .device("test-device-id"),
                context: request.context,
                properties: request.properties,
                eventVersion: request.eventVersion,
                operationID: request.operationID,
            )
            guard case let .capture(capture) = result else {
                return XCTFail("typed adapter request did not resolve: \(request.metricKey), result: \(result)")
            }
            XCTAssertEqual(capture.event.eventName.rawValue, expectedEventName)
            XCTAssertEqual(capture.event.operationID, request.operationID)
        }
    }

    /// EVM-001-navigate_pages: browsing identity는 exact implemented registry key로만 사상된다.
    /// TBD인 history identity는 보존하되 app product event를 만들지 않는지 검증한다.
    /// - 검증 내용: direct/back/forward/enclosing key와 history 무이벤트
    /// - 사전 조건: 동일 payload의 다섯 finite navigation identity
    /// - 기대 결과: implemented key 4건만 registry capture로 resolve
    func testContentBrowsingIdentityMapsExactImplementedRegistryKeysWithoutFallback() {
        let requests = LockIsolated<[ProductAnalyticsMetricRequest]>([])
        let client = ProductAnalyticsClient { request in requests.withValue { $0.append(request) } }
        let metrics = VoyagerApp.makeFileManagerProductMetricsClient(client: client, environment: .dev)
        let identities: [ContentPageNavigationInteractionIdentity] = [
            .direct,
            .back,
            .forward,
            .enclosingDirectory,
            .history,
        ]

        for identity in identities {
            metrics.record(.contentBrowsing(
                result: .success,
                content: .folder,
                identity: identity,
                source: .fileManagerContent,
                operationID: UUID(),
            ))
        }

        XCTAssertEqual(requests.value.map(\.metricKey), [
            "voy_691_evm_001_navigate_pages",
            "voy_691_evm_001_go_page_history_back",
            "voy_691_evm_001_forward_page_history",
            "voy_691_evm_001_go_to_enclosing_directory",
        ])

        let registry = ProductAnalyticsRegistry.load(bundle: VoyagerTestSupport.hostApplicationBundle())
        for request in requests.value {
            guard case .capture = registry.resolve(
                metricKey: request.metricKey,
                identity: .device("test-device-id"),
                context: request.context,
                properties: request.properties,
                eventVersion: request.eventVersion,
                operationID: request.operationID,
            ) else {
                return XCTFail("implemented browsing key did not resolve: \(request.metricKey)")
            }
        }
    }

    func testProductAnalyticsContextUsesResolvedAppEnvironment() {
        let occurredAtUTC = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertEqual(
            VoyagerApp.makeProductAnalyticsEventContext(
                environment: .dev,
                occurredAtUTC: occurredAtUTC,
            ).environment,
            "dev",
        )
        XCTAssertEqual(
            VoyagerApp.makeProductAnalyticsEventContext(
                environment: .prod,
                occurredAtUTC: occurredAtUTC,
            ).environment,
            "prod",
        )
        XCTAssertEqual(
            VoyagerApp.makeProductAnalyticsEventContext(
                environment: .dev,
                occurredAtUTC: occurredAtUTC,
            ).sourceProject,
            "app",
        )
    }

    func testBuiltInSeedIdentityTagsMapToSafeSourceSurfaceValues() {
        for identity in ["recents", "all_tags"] {
            XCTAssertEqual(
                VoyagerApp.productMetricProperties(
                    name: "built_in_pinned_item_seeded",
                    value: 1,
                    tags: ["identity": identity],
                )["source_surface"],
                .string(identity),
            )
        }
    }

    func testCollectionOpenMetricsReachProductionAnalyticsBridge() async {
        XCTAssertEqual(
            VoyagerApp.productMetricProperties(
                name: "collection.open",
                value: 1,
                tags: [
                    "result_status": "load_failure",
                    "error_category": "unsupportedSchema",
                    "raw_path": "/private/secret.voycoll",
                ],
            ),
            [
                "result_status": .string("load_failure"),
                "failure_reason": .string("unsupported_schema"),
            ],
        )
        let metricRequests = LockIsolated<[ProductAnalyticsMetricRequest]>([])
        let analyticsClient = ProductAnalyticsClient(captureMetric: { request in
            metricRequests.withValue { $0.append(request) }
        })
        let metricsClient = VoyagerApp.makeFileManagerMetricsClient(context: .init(
            client: analyticsClient,
            environment: .dev,
        ))
        let registry = ProductAnalyticsRegistry.load(bundle: VoyagerTestSupport.hostApplicationBundle())
        let validEmptyFile = VoyagerCollectionFile(
            id: "valid-empty",
            name: "Private Collection Name",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            query: "",
            scopes: [],
            conditions: [],
            snapshot: nil,
            snapshotMeta: nil,
            appVersion: "test",
        )
        let validEmptyResult = CollectionFileLoadResult(
            file: validEmptyFile,
            containerFormat: .package,
            compatibility: .init(
                sourceSchemaVersion: CollectionFileSchemaVersion.snapshotBearingCurrent,
                migrationPath: [.currentSchemaV2],
                warnings: [],
                usedDefinitionFallback: false,
                writeBackAllowed: true,
                writeBackReason: .allowed,
            ),
        )
        let successStore = TestStore(initialState: FileManagerWindowState()) {
            FileManagerFeature()
        } withDependencies: {
            $0.collectionFileClient.load = { _ in validEmptyResult }
            $0.collectionAlertClient = .testValue
            $0.collectionStalenessClient = .testValue
            $0.registryClient = .testValue
            $0.searchClient = .testValue
            $0.metricsClient = metricsClient
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_200))
            $0.uuid = .incrementing
            $0.continuousClock = ImmediateClock()
        }
        // store.exhaustivity = .off: production bridge 결과만 검증하고 FileManager child action은 package owner에 위임함.
        successStore.exhaustivity = .off(showSkippedAssertions: false)

        await successStore.send(.navigation(.view(.openCollectionFile(
            URL(fileURLWithPath: "/private/secret/valid-empty.voycoll"),
        ))))
        await successStore.skipReceivedActions(strict: false)
        await successStore.finish()

        let failures: [AppCollectionOpenBridgeFailure] = [
            .invalidDefinition,
            .malformed,
            .access,
            .unknown,
        ]
        for (index, failure) in failures.enumerated() {
            let store = TestStore(initialState: FileManagerWindowState()) {
                FileManagerFeature()
            } withDependencies: {
                $0.collectionFileClient.load = { _ in throw failure.error }
                $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in }
                $0.collectionStalenessClient = .testValue
                $0.registryClient = .testValue
                $0.searchClient = .testValue
                $0.metricsClient = metricsClient
                $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_200))
                $0.uuid = .constant(UUID(index + 1000))
                $0.continuousClock = ImmediateClock()
            }
            // store.exhaustivity = .off: typed failure별 production bridge 결과만 검증함.
            store.exhaustivity = .off(showSkippedAssertions: false)

            await store.send(.navigation(.view(.openCollectionFile(
                URL(fileURLWithPath: "/private/secret/failure-\(index).voycoll"),
            ))))
            await store.skipReceivedActions(strict: false)
            await store.finish()
        }

        // develop이 open 흐름에 추가한 dau.navigation 등 타 metric은 이 테스트 대상이 아니라서
        // collection.open(result_status/failure_reason properties)만 골라 검증한다.
        let requests = metricRequests.value.filter {
            let keys = Set($0.properties.keys)
            return keys == ["result_status"] || keys == ["result_status", "failure_reason"]
        }
        XCTAssertEqual(requests.count, 5)
        XCTAssertEqual(requests.count { $0.properties["result_status"] == .string("valid_empty") }, 1)
        XCTAssertEqual(requests.count { $0.properties["result_status"] == .string("load_failure") }, 4)
        XCTAssertEqual(requests.first?.properties, ["result_status": .string("valid_empty")])
        XCTAssertEqual(
            requests.dropFirst().compactMap { $0.properties["failure_reason"] },
            [
                .string("invalid_definition"),
                .string("malformed"),
                .string("access"),
                .string("unknown"),
            ],
        )

        for (index, metricRequest) in requests.enumerated() {
            XCTAssertEqual(metricRequest.metricKey, "collection.open")
            XCTAssertEqual(metricRequest.properties.count, index == 0 ? 1 : 2)
            XCTAssertTrue(Set(metricRequest.properties.keys).isSubset(of: ["result_status", "failure_reason"]))
            guard case let .capture(request) = registry.resolve(
                metricKey: metricRequest.metricKey,
                identity: .device("test-device-id"),
                context: metricRequest.context,
                properties: metricRequest.properties,
            ) else {
                return XCTFail("expected collection.open request \(index) to resolve")
            }
            XCTAssertEqual(request.event.eventName.rawValue, "voyager_collection_open")
            XCTAssertEqual(request.event.distinctID, "test-device-id")
            XCTAssertEqual(request.event.properties, metricRequest.properties)
            XCTAssertNil(request.event.identifiers)
        }
    }

    func testLiveUndoManagerClientUsesCanonicalRegistryStackForSequentialUndo() async throws {
        let windowID = UUID()
        let ownerID = UUID()
        let registry = FileOperationUndoManagerRegistry()
        let window = FileManagerWindowState.makeInitial(path: "/active")
        let activeTabID = try XCTUnwrap(window.contentTabs.activeTabID)
        let scope = UndoManagerScope(windowID: windowID, contentTabID: activeTabID.rawValue)
        let nativeUndoManager = registry.activate(scope)
        let generation = try XCTUnwrap(registry.generation(for: scope))
        let client = VoyagerApp.makeUndoManagerClient(
            fileOperationUndoManagerRegistry: registry,
            resolveScope: { requestedWindowID in
                requestedWindowID == windowID ? scope : nil
            },
        )
        let firstRecord = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/first-old", afterPath: "/first-new")],
        )
        let secondRecord = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/second-old", afterPath: "/second-new")],
        )
        var events = client.events(windowID).makeAsyncIterator()

        XCTAssertTrue(registry.registerUndo(scope, expectedGeneration: generation, record: firstRecord))
        await client.registerUndo(windowID, ownerID, firstRecord)
        XCTAssertTrue(registry.registerUndo(scope, expectedGeneration: generation, record: secondRecord))
        await client.registerUndo(windowID, ownerID, secondRecord)

        let secondIdentity = UndoManagerRecordIdentity(ownerID: ownerID, recordID: secondRecord.id)
        let firstUndo = await client.undo(windowID, expectedTarget: secondIdentity)
        let firstEvent = await events.next()
        let firstIdentity = UndoManagerRecordIdentity(ownerID: ownerID, recordID: firstRecord.id)
        let secondUndo = await client.undo(windowID, expectedTarget: firstIdentity)
        let secondEvent = await events.next()

        XCTAssertIdentical(registry.undoManager(for: scope), nativeUndoManager)
        XCTAssertTrue(firstUndo.didInvoke)
        XCTAssertTrue(secondUndo.didInvoke)
        XCTAssertEqual(firstEvent, UndoManagerEvent(ownerID: ownerID, record: secondRecord, direction: .undo))
        XCTAssertEqual(secondEvent, UndoManagerEvent(ownerID: ownerID, record: firstRecord, direction: .undo))
        XCTAssertFalse(secondUndo.availability.canUndo)
        XCTAssertTrue(secondUndo.availability.canRedo)
        XCTAssertFalse(nativeUndoManager.canUndo)
        XCTAssertTrue(nativeUndoManager.canRedo)
        XCTAssertEqual(registry.generation(for: scope), generation)
    }

    func testSignedOutLaunchDefersInitialWindowUntilRuntimeAndWindowCompletion() async {
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.onboardingWindowClient.isRequired = { false }
            $0.fileManagerWindowClient.open = { _ in }
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        store.exhaustivity = .off

        XCTAssertFalse(store.state.lifecycle.isShellReady)
        await store.send(.lifecycle(.delegate(.openInitialWindowIfNeeded)))
        await store.receive(\.windowManager.lifecycle.openInitialWindowIfNeeded)
        XCTAssertFalse(store.state.lifecycle.didCreateInitialWindow)

        await store.receive { action in
            guard case .windowManager(.file(.newWindow)) = action else { return false }
            return true
        }
        await store.receive(\.lifecycle.accountAccess.onAppear)

        XCTAssertTrue(store.state.lifecycle.didCreateInitialWindow)
        XCTAssertTrue(store.state.lifecycle.isShellReady)
        XCTAssertEqual(store.state.windowManager.windows.count, 1)
        await store.skipInFlightEffects()
    }

    func testExternalRouteStaysDeferredUntilActualInitialWindowCompletion() async throws {
        let url = try XCTUnwrap(URL(string: "voyager://open"))
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.onboardingWindowClient.isRequired = { false }
            $0.fileManagerWindowClient.open = { _ in }
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }
        store.exhaustivity = .off

        await store.send(.receiveExternalURL(url))
        XCTAssertEqual(store.state.pendingExternalURLs, [url])
        XCTAssertTrue(store.state.isExternalURLRouteInFlightWithoutWindow)
        XCTAssertFalse(store.state.lifecycle.isShellReady)

        await store.receive(\.lifecycle.delegate.openInitialWindowIfNeeded)
        await store.receive(\.windowManager.lifecycle.openInitialWindowIfNeeded)
        XCTAssertTrue(store.state.windowManager.windows.isEmpty)

        await store.receive { action in
            guard case .windowManager(.file(.newWindow)) = action else { return false }
            return true
        }
        await store.receive(\.lifecycle.accountAccess.onAppear)
        XCTAssertTrue(store.state.lifecycle.didCreateInitialWindow)
        XCTAssertTrue(store.state.lifecycle.isShellReady)
        XCTAssertTrue(store.state.pendingExternalURLs.isEmpty)
        await store.skipInFlightEffects()
    }

    // MARK: - Entry Core direct health probe

    func testEntryCoreHealthProbeRunsExactlyOnceAndPreservesHelperMonitoring() async {
        let probeStarted = expectation(description: "Entry Core health probe started")
        let helperStartCount = LockIsolated(0)
        let healthCalls = LockIsolated<[EntryCoreEndpoint]>([])
        let gate = AsyncStream<Void>.makeStream()
        let store = TestStore(initialState: AppLifecycleFeature.State()) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.entryCoreEndpointClient = .live(environment: {
                [EntryCoreEndpointClient.environmentKey: "/tmp/voyager-entry-core.sock"]
            })
            $0.entryCoreClient = makeEntryCoreClient { endpoint in
                healthCalls.withValue { $0.append(endpoint) }
                probeStarted.fulfill()
                for await _ in gate.stream {
                    break
                }
                return EntryCoreHealthResult()
            }
            $0.helperAppClient = helperAppClient(startCount: helperStartCount)
            $0.helperStateClient = readyHelperStateClient
            $0.onboardingWindowClient.isRequired = { false }
            $0.onboardingWindowClient.showIfNeeded = { false }
        }
        store.exhaustivity = .off
        await store.send(.launch(.didFinishLaunching)) {
            $0.didFinishLaunching = true
            $0.didStartHelper = true
            $0.didStartEntryCoreHealthProbe = true
        }
        await fulfillment(of: [probeStarted], timeout: 1)
        XCTAssertEqual(healthCalls.value.map(\.path), ["/tmp/voyager-entry-core.sock"])

        gate.continuation.yield(())
        gate.continuation.finish()
        await store.receive { action in
            guard case let .entryCoreHealthProbeCompleted(result) = action else { return false }
            return result.outcome == .healthy && result.phase == .response && result.duration == .zero
        }

        XCTAssertEqual(healthCalls.value.map(\.path), ["/tmp/voyager-entry-core.sock"])
        XCTAssertGreaterThanOrEqual(helperStartCount.value, 1)
        XCTAssertTrue(store.state.didFinishLaunching)
        XCTAssertTrue(store.state.didCompleteEntryCoreHealthProbe)
        await store.finish()
    }

    func testEntryCoreHealthProbeUnavailableEnvironmentDoesNotCallHealth() async {
        let environments = [
            [String: String](),
            [EntryCoreEndpointClient.environmentKey: "relative.sock"],
        ]
        let healthCallCount = LockIsolated(0)

        for environment in environments {
            var initialState = AppLifecycleFeature.State()
            initialState.didFinishLaunching = true
            initialState.didStartHelper = true
            let store = TestStore(initialState: initialState) {
                AppLifecycleFeature()
            } withDependencies: {
                $0.continuousClock = ImmediateClock()
                $0.date = .constant(Date(timeIntervalSince1970: 0))
                $0.entryCoreEndpointClient = .live(environment: { environment })
                $0.entryCoreClient = makeEntryCoreClient { _ in
                    healthCallCount.withValue { $0 += 1 }
                    return EntryCoreHealthResult()
                }
                $0.onboardingWindowClient.showIfNeeded = { false }
            }
            store.exhaustivity = .off

            await store.send(.launch(.didFinishLaunching)) {
                $0.didFinishLaunching = true
                $0.didStartHelper = true
                $0.didStartEntryCoreHealthProbe = true
            }
            await store.receive { action in
                guard case let .entryCoreHealthProbeCompleted(result) = action else { return false }
                return result.outcome == .unavailable
                    && result.phase == .endpointResolution
                    && result.duration == .zero
            }
            await store.finish()
        }

        XCTAssertEqual(healthCallCount.value, 0)
    }

    func testEntryCoreHealthProbeCancellationPreservesTerminationRouting() async {
        let probeStarted = expectation(description: "Entry Core health probe started")
        let probeCancelled = expectation(description: "Entry Core health probe cancelled")
        let helperMonitorCancelled = expectation(description: "Helper monitor cancelled")
        let helperEvents = AsyncStream<Void>.makeStream()
        helperEvents.continuation.onTermination = { @Sendable _ in
            helperMonitorCancelled.fulfill()
        }
        let store = TestStore(initialState: AppLifecycleFeature.State()) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.entryCoreEndpointClient = .live(environment: {
                [EntryCoreEndpointClient.environmentKey: "/tmp/voyager-entry-core.sock"]
            })
            $0.entryCoreClient = makeEntryCoreClient { _ in
                probeStarted.fulfill()
                return try await withTaskCancellationHandler {
                    try await Task.sleep(for: .seconds(60))
                    return EntryCoreHealthResult()
                } onCancel: {
                    probeCancelled.fulfill()
                }
            }
            $0.helperAppClient = HelperAppClient(
                start: {},
                stop: {},
                isRunning: { true },
                terminationEvents: { helperEvents.stream },
                ensureRunning: { _ in },
            )
            $0.helperStateClient = readyHelperStateClient
            $0.onboardingWindowClient.showIfNeeded = { false }
        }
        store.exhaustivity = .off

        await store.send(.launch(.didFinishLaunching)) {
            $0.didFinishLaunching = true
            $0.didStartHelper = true
            $0.didStartEntryCoreHealthProbe = true
        }
        await fulfillment(of: [probeStarted], timeout: 1)

        await store.send(.termination(.willTerminate))
        await store.receive(\.accountAccess.appWillTerminate)
        await fulfillment(of: [probeCancelled, helperMonitorCancelled], timeout: 1)
        await store.finish()
    }

    // MARK: - Helper monitoring

    func testHelperMonitorRestartsAfterTerminationEvent() async {
        let restartRequested = expectation(description: "Helper restart requested")
        let restartCount = LockIsolated(0)
        let ensureRequestCount = LockIsolated(0)
        let helperEvents = AsyncStream<Void>.makeStream()
        let monitor = HelperMonitor(
            helperClient: HelperAppClient(
                start: {},
                stop: {},
                isRunning: { false },
                terminationEvents: { helperEvents.stream },
                ensureRunning: { canLaunch in
                    guard await canLaunch() else { return }
                    let requestCount = ensureRequestCount.withValue {
                        $0 += 1
                        return $0
                    }
                    guard requestCount > 1 else { return }
                    restartCount.withValue { $0 += 1 }
                    restartRequested.fulfill()
                },
            ),
            stateClient: readyHelperStateClient,
            clock: ImmediateClock(),
            now: { Date(timeIntervalSince1970: 0) },
            canRestart: { true },
        )
        let task = Task {
            await monitor.run(mainBundleVersion: nil)
        }

        await Task.yield()
        helperEvents.continuation.yield(())
        await fulfillment(of: [restartRequested], timeout: 1)

        task.cancel()
        helperEvents.continuation.finish()
        await task.value
        XCTAssertEqual(restartCount.value, 1)
    }

    func testHelperMonitorCancellationDuringGraceWindowDoesNotRestart() async {
        let clock = TestClock()
        let restartRequested = expectation(description: "Initial helper restart requested")
        let graceSleepStarted = expectation(description: "Grace window sleep started")
        let restartCount = LockIsolated(0)
        let ensureRequestCount = LockIsolated(0)
        let nowReadCount = LockIsolated(0)
        let helperEvents = AsyncStream<Void>.makeStream()
        let monitor = HelperMonitor(
            helperClient: HelperAppClient(
                start: {},
                stop: {},
                isRunning: { false },
                terminationEvents: { helperEvents.stream },
                ensureRunning: { canLaunch in
                    guard await canLaunch() else { return }
                    let requestCount = ensureRequestCount.withValue {
                        $0 += 1
                        return $0
                    }
                    guard requestCount > 1 else { return }
                    restartCount.withValue { $0 += 1 }
                    restartRequested.fulfill()
                },
            ),
            stateClient: readyHelperStateClient,
            clock: clock,
            now: {
                let count = nowReadCount.withValue {
                    $0 += 1
                    return $0
                }
                if count == 3 {
                    graceSleepStarted.fulfill()
                }
                return Date(timeIntervalSince1970: 0)
            },
            canRestart: { true },
        )
        let task = Task {
            await monitor.run(mainBundleVersion: nil)
        }

        await Task.yield()
        helperEvents.continuation.yield(())
        await fulfillment(of: [restartRequested], timeout: 1)

        helperEvents.continuation.yield(())
        await fulfillment(of: [graceSleepStarted], timeout: 1)

        task.cancel()
        await clock.advance(by: .seconds(5))
        helperEvents.continuation.finish()
        await task.value
        XCTAssertEqual(restartCount.value, 1)
    }

    func testHelperMonitorCancellationBeforeLaunchDoesNotRestart() async {
        let restartEntered = expectation(description: "Helper restart boundary entered")
        let restartCount = LockIsolated(0)
        let ensureRequestCount = LockIsolated(0)
        let helperEvents = AsyncStream<Void>.makeStream()
        let restartGate = AsyncStream<Void>.makeStream()
        let monitor = HelperMonitor(
            helperClient: HelperAppClient(
                start: {},
                stop: {},
                isRunning: { false },
                terminationEvents: { helperEvents.stream },
                ensureRunning: { canLaunch in
                    let requestCount = ensureRequestCount.withValue {
                        $0 += 1
                        return $0
                    }
                    guard requestCount > 1 else { return }
                    restartEntered.fulfill()
                    for await _ in restartGate.stream {
                        break
                    }
                    guard await canLaunch() else { return }
                    restartCount.withValue { $0 += 1 }
                },
            ),
            stateClient: readyHelperStateClient,
            clock: ImmediateClock(),
            now: { Date(timeIntervalSince1970: 0) },
            canRestart: { true },
        )
        let task = Task {
            await monitor.run(mainBundleVersion: nil)
        }

        await Task.yield()
        helperEvents.continuation.yield(())
        await fulfillment(of: [restartEntered], timeout: 1)

        task.cancel()
        restartGate.continuation.yield(())
        restartGate.continuation.finish()
        helperEvents.continuation.finish()
        await task.value
        XCTAssertEqual(restartCount.value, 0)
    }

    func testHelperMonitorCancellationBeforeInitialLaunchDoesNotStart() async {
        let launchEntered = expectation(description: "Initial helper launch boundary entered")
        let launchCount = LockIsolated(0)
        let helperEvents = AsyncStream<Void>.makeStream()
        let launchGate = AsyncStream<Void>.makeStream()
        let monitor = HelperMonitor(
            helperClient: HelperAppClient(
                start: { launchCount.withValue { $0 += 1 } },
                stop: {},
                isRunning: { false },
                terminationEvents: { helperEvents.stream },
                ensureRunning: { canLaunch in
                    launchEntered.fulfill()
                    for await _ in launchGate.stream {
                        break
                    }
                    guard await canLaunch() else { return }
                    launchCount.withValue { $0 += 1 }
                },
            ),
            stateClient: readyHelperStateClient,
            clock: ImmediateClock(),
            now: { Date(timeIntervalSince1970: 0) },
            canRestart: { true },
        )
        let task = Task {
            await monitor.run(mainBundleVersion: nil)
        }

        await fulfillment(of: [launchEntered], timeout: 1)
        task.cancel()
        launchGate.continuation.yield(())
        launchGate.continuation.finish()
        helperEvents.continuation.finish()
        await task.value
        XCTAssertEqual(launchCount.value, 0)
    }

    func testHelperMonitorCancellationDuringInitialAlignmentDoesNotRestart() async {
        let resolveEntered = expectation(description: "Initial helper state resolution entered")
        let startCount = LockIsolated(0)
        let helperEvents = AsyncStream<Void>.makeStream()
        let resolveGate = AsyncStream<Void>.makeStream()
        let monitor = HelperMonitor(
            helperClient: HelperAppClient(
                start: { startCount.withValue { $0 += 1 } },
                stop: {},
                isRunning: { false },
                terminationEvents: { helperEvents.stream },
                ensureRunning: { canLaunch in
                    guard await canLaunch() else { return }
                    startCount.withValue { $0 += 1 }
                },
            ),
            stateClient: HelperStateClient(
                resolve: {
                    resolveEntered.fulfill()
                    for await _ in resolveGate.stream {
                        return nil
                    }
                    return nil
                },
                observe: { AsyncStream { $0.finish() } },
            ),
            clock: ImmediateClock(),
            now: { Date(timeIntervalSince1970: 0) },
            canRestart: { true },
        )
        let task = Task {
            await monitor.run(mainBundleVersion: nil)
        }

        await fulfillment(of: [resolveEntered], timeout: 1)
        XCTAssertEqual(startCount.value, 1)

        task.cancel()
        resolveGate.continuation.yield(())
        resolveGate.continuation.finish()
        helperEvents.continuation.finish()
        await task.value
        XCTAssertEqual(startCount.value, 1)
    }

    private var accessSnapshot: AccessStatusSnapshot {
        AccessStatusSnapshot(
            status: .coreLicenseActive,
            sessionExpiresAt: Date(timeIntervalSince1970: 4_102_444_800),
            deviceBindingVerifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )
    }

    private var readyHelperStateClient: HelperStateClient {
        HelperStateClient(
            resolve: { HelperState(helperReady: true, helperBundleVersion: nil) },
            observe: { AsyncStream { $0.finish() } },
        )
    }

    private func helperAppClient(startCount: LockIsolated<Int>? = nil) -> HelperAppClient {
        HelperAppClient(
            start: { startCount?.withValue { $0 += 1 } },
            stop: {},
            isRunning: { true },
            terminationEvents: { AsyncStream { $0.finish() } },
            ensureRunning: { canLaunch in
                guard await canLaunch() else { return }
                startCount?.withValue { $0 += 1 }
            },
        )
    }

    private func makeEntryCoreClient(
        health: @escaping @Sendable (EntryCoreEndpoint) async throws -> EntryCoreHealthResult,
    ) -> EntryCoreClient {
        EntryCoreClient(
            ping: { _ in EntryCorePingResult() },
            health: health,
            version: { _ in try EntryCoreVersionResult(appVersion: "test") },
        )
    }

    func testTerminationWillTerminateSendsChildAppWillTerminate() async {
        var initialState = AppLifecycleFeature.State()
        initialState.terminationAttemptID = UUID(0)

        let store = TestStore(initialState: initialState) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.notificationCenterClient.notifications = { _, _ in
                AsyncStream { $0.finish() }
            }
        }
        store.exhaustivity = .off

        await store.send(.termination(.willTerminate))

        // Task 4가 적용되면 child가 appWillTerminate를 수신한다.
        await store.receive(\.accountAccess.appWillTerminate)
        await store.finish()
    }

    // MARK: - App host lifecycle

    func testAppDelegateSuppressesAutomaticLifecycleDispatchDuringXCTestHosting() {
        let box = ActionBox<AppRootAction>()
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        let appDelegate = AppDelegate()
        appDelegate.configure(appRootStore: store)
        appDelegate.shouldSuppressAutomaticLifecycle = { true }

        appDelegate.applicationWillFinishLaunching(
            Notification(name: NSApplication.willFinishLaunchingNotification),
        )
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification),
        )
        let shouldHandleReopen = appDelegate.applicationShouldHandleReopen(
            NSApp,
            hasVisibleWindows: false,
        )
        let terminationReply = appDelegate.applicationShouldTerminate(NSApp)

        XCTAssertTrue(box.actions.isEmpty)
        XCTAssertTrue(shouldHandleReopen)
        XCTAssertEqual(terminationReply, .terminateNow)
    }

    func testAppDelegateDispatchesDidFinishLaunchingOutsideXCTestHosting() {
        let box = ActionBox<AppRootAction>()
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        let appDelegate = AppDelegate()
        appDelegate.configure(appRootStore: store)
        appDelegate.shouldSuppressAutomaticLifecycle = { false }

        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification),
        )

        XCTAssertTrue(box.actions.contains { action in
            if case .lifecycle(.launch(.didFinishLaunching)) = action {
                return true
            }
            return false
        })
    }

    func testLaunchUsesInjectedDeviceIdentityClient() async {
        let deviceIdentityCalls = LockIsolated(0)
        let analyticsIdentities = LockIsolated<[String?]>([])
        let store = TestStore(initialState: AppLifecycleFeature.State()) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.deviceIdentityClient = DeviceIdentityClient(deviceId: {
                deviceIdentityCalls.withValue { $0 += 1 }
                return "test-device-id"
            })
            $0.notificationCenterClient.notifications = { _, _ in
                AsyncStream { $0.finish() }
            }
        }
        // store.exhaustivity = .off: launch bootstrap은 장기 notification effect를 포함하고 identity 호출만 단정함.
        store.exhaustivity = .off

        await store.send(.launch(.willFinishLaunching))

        XCTAssertEqual(deviceIdentityCalls.value, 1)
        XCTAssertTrue(analyticsIdentities.value.isEmpty)
        await store.finish()
    }

    func testIdentityFailureDoesNotPreventDidFinishLaunching() async {
        let deviceIdentityCalls = LockIsolated(0)
        let sentryIdentities = LockIsolated<[String?]>([])
        let store = TestStore(initialState: AppLifecycleFeature.State()) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.deviceIdentityClient = DeviceIdentityClient(deviceId: {
                deviceIdentityCalls.withValue { $0 += 1 }
                throw DeviceIdentityError.platformUUIDUnavailable
            })
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.appTechnicalSentryClient = AppTechnicalSentryClient(
                startIfNeeded: { _, userId, _ in
                    sentryIdentities.withValue { $0.append(userId) }
                },
                updateUser: { _ in },
            )
            $0.helperAppClient = helperAppClient()
            $0.helperStateClient = readyHelperStateClient
            $0.onboardingWindowClient.showIfNeeded = { true }
            $0.notificationCenterClient.notifications = { _, _ in
                AsyncStream { $0.finish() }
            }
        }
        // store.exhaustivity = .off: identity failure는 fire-and-forget이고 이 테스트는 launch 완료만 소유함.
        store.exhaustivity = .off

        await store.send(.launch(.willFinishLaunching))
        await store.send(.launch(.didFinishLaunching)) {
            $0.didFinishLaunching = true
        }

        XCTAssertEqual(deviceIdentityCalls.value, 1)
        XCTAssertEqual(sentryIdentities.value, [nil])
        XCTAssertTrue(store.state.didFinishLaunching)
        await store.finish()
    }

    func testMalformedIdentityDoesNotUpdateSentry() async {
        let sentryUserUpdates = LockIsolated<[String]>([])
        let store = TestStore(initialState: AppLifecycleFeature.State()) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.deviceIdentityClient = DeviceIdentityClient(deviceId: { " \n\t" })
            $0.appTechnicalSentryClient.updateUser = { identity in
                sentryUserUpdates.withValue { $0.append(identity) }
            }
            $0.notificationCenterClient.notifications = { _, _ in
                AsyncStream { $0.finish() }
            }
        }
        // store.exhaustivity = .off: malformed identity normalization과 launch effect completion만 단정함.
        store.exhaustivity = .off

        await store.send(.launch(.willFinishLaunching))
        await store.finish()

        XCTAssertTrue(sentryUserUpdates.value.isEmpty)
    }

    func testLaunchCallerReturnsWhileIdentityAcquisitionIsBlocked() async {
        let deviceIdentityCalls = LockIsolated(0)
        let sentryIdentities = LockIsolated<[String?]>([])
        let sentryUserUpdates = LockIsolated<[String]>([])
        let identityStarted = expectation(description: "Identity acquisition starts")
        let sentryUserUpdated = expectation(description: "Sentry user updates independently")
        let identityRelease = DispatchSemaphore(value: 0)
        let store = Store(initialState: AppLifecycleFeature.State()) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.deviceIdentityClient = DeviceIdentityClient(deviceId: {
                deviceIdentityCalls.withValue { $0 += 1 }
                identityStarted.fulfill()
                identityRelease.wait()
                return " \n test-device-id \t"
            })
            $0.appTechnicalSentryClient = AppTechnicalSentryClient(
                startIfNeeded: { _, userId, _ in
                    sentryIdentities.withValue { $0.append(userId) }
                },
                updateUser: { userId in
                    sentryUserUpdates.withValue { $0.append(userId) }
                    sentryUserUpdated.fulfill()
                },
            )
            $0.notificationCenterClient.notifications = { _, _ in
                AsyncStream { $0.finish() }
            }
        }

        let launchStart = ContinuousClock.now
        store.send(.launch(.willFinishLaunching))
        let launchElapsed = ContinuousClock.now - launchStart

        await fulfillment(of: [identityStarted], timeout: 1)
        XCTAssertLessThan(launchElapsed, .seconds(1))
        XCTAssertEqual(deviceIdentityCalls.value, 1)
        XCTAssertEqual(sentryIdentities.value, [nil])

        identityRelease.signal()
        await fulfillment(of: [sentryUserUpdated], timeout: 1)
        XCTAssertEqual(sentryIdentities.value, [nil])
        XCTAssertEqual(sentryUserUpdates.value, ["test-device-id"])
    }

    func testLaunchCallerReturnsAfterSchedulingIdentityAcquisition() async {
        let deviceIdentityCalls = LockIsolated(0)
        let store = TestStore(initialState: AppLifecycleFeature.State()) {
            AppLifecycleFeature()
        } withDependencies: {
            $0.deviceIdentityClient = DeviceIdentityClient(deviceId: {
                deviceIdentityCalls.withValue { $0 += 1 }
                return "test-device-id"
            })
            $0.notificationCenterClient.notifications = { _, _ in
                AsyncStream { $0.finish() }
            }
        }
        // store.exhaustivity = .off: launch bootstrap의 장기 notification effect와 identity scheduling을 함께 검증함.
        store.exhaustivity = .off

        await store.send(.launch(.willFinishLaunching))
        await store.finish()
        XCTAssertEqual(deviceIdentityCalls.value, 1)
    }

    // MARK: - VOY-521 Auth callback canonical routing

    func testAppDelegateIgnoresUnsupportedURLsAndRoutesVoyagerDeepLinks() throws {
        let box = ActionBox<AppRootAction>()
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        let appDelegate = AppDelegate()
        appDelegate.configure(appRootStore: store)
        appDelegate.callbackScheme = "voyager" // Prod identity for test focus

        try appDelegate.application(NSApp, open: [XCTUnwrap(URL(string: "https://example.com"))])
        appDelegate.application(NSApp, open: [])

        XCTAssertTrue(box.actions.isEmpty)

        let deepLink = try XCTUnwrap(URL(string: "voyager://open"))
        appDelegate.application(NSApp, open: [deepLink])

        let routed = box.actions.contains { action in
            if case let .receiveExternalURL(received) = action {
                return received == deepLink
            }
            return false
        }
        XCTAssertTrue(routed)
    }

    // MARK: - Scheme acceptance (Dev/Prod)

    /// Dev callbackScheme에서 voyager-dev:// auth/callback이 routeAuthCallback으로 라우팅되는지 검증
    func testAppDelegateWithDevSchemeAcceptsVoyagerDevCallback() throws {
        let box = ActionBox<AppRootAction>()
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        let appDelegate = AppDelegate()
        appDelegate.configure(appRootStore: store)
        appDelegate.callbackScheme = "voyager-dev"

        let url = try XCTUnwrap(URL(string: "voyager-dev://auth/callback?code=abc"))
        appDelegate.application(NSApp, open: [url])

        let routed = box.actions.contains { action in
            if case let .receiveAuthCallbackURL(received) = action {
                return received == url
            }
            return false
        }
        XCTAssertTrue(routed)
    }

    /// Dev callbackScheme에서 voyager:// URL은 무시되는지 검증 (cross-scheme rejection)
    func testAppDelegateWithDevSchemeRejectsVoyagerURL() throws {
        let box = ActionBox<AppRootAction>()
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        let appDelegate = AppDelegate()
        appDelegate.configure(appRootStore: store)
        appDelegate.callbackScheme = "voyager-dev"

        let voyagerURL = try XCTUnwrap(URL(string: "voyager://auth/callback?code=abc"))
        appDelegate.application(NSApp, open: [voyagerURL])

        let anyExternalAction = box.actions.contains { action in
            if case .receiveExternalURL = action { return true }
            if case .receiveAuthCallbackURL = action { return true }
            return false
        }
        XCTAssertFalse(anyExternalAction)
    }

    /// Prod callbackScheme에서 voyager-dev:// URL은 무시되는지 검증 (cross-scheme rejection)
    func testAppDelegateWithProdSchemeRejectsVoyagerDevURL() throws {
        let box = ActionBox<AppRootAction>()
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        let appDelegate = AppDelegate()
        appDelegate.configure(appRootStore: store)
        appDelegate.callbackScheme = "voyager"

        let devURL = try XCTUnwrap(URL(string: "voyager-dev://auth/callback?code=abc"))
        appDelegate.application(NSApp, open: [devURL])

        let anyExternalAction = box.actions.contains { action in
            if case .receiveExternalURL = action { return true }
            if case .receiveAuthCallbackURL = action { return true }
            return false
        }
        XCTAssertFalse(anyExternalAction)
    }

    /// Prod callbackScheme에서 voyager:// deep link는 정상 라우팅되는지 검증
    func testAppDelegateWithProdSchemeAcceptsVoyagerDeepLink() throws {
        let box = ActionBox<AppRootAction>()
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        let appDelegate = AppDelegate()
        appDelegate.configure(appRootStore: store)
        appDelegate.callbackScheme = "voyager"

        let deepLink = try XCTUnwrap(URL(string: "voyager://open"))
        appDelegate.application(NSApp, open: [deepLink])

        let routed = box.actions.contains { action in
            if case let .receiveExternalURL(received) = action {
                return received == deepLink
            }
            return false
        }
        XCTAssertTrue(routed)
    }

    /// Dev callbackScheme에서 voyager-dev:// deep link는 정상 라우팅되는지 검증
    func testAppDelegateWithDevSchemeAcceptsVoyagerDevDeepLink() throws {
        let box = ActionBox<AppRootAction>()
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        let appDelegate = AppDelegate()
        appDelegate.configure(appRootStore: store)
        appDelegate.callbackScheme = "voyager-dev"

        let deepLink = try XCTUnwrap(URL(string: "voyager-dev://open"))
        appDelegate.application(NSApp, open: [deepLink])

        let routed = box.actions.contains { action in
            if case let .receiveExternalURL(received) = action {
                return received == deepLink
            }
            return false
        }
        XCTAssertTrue(routed)
    }

    // MARK: - System open callback batch ingress

    func testAppDelegateOpenURLsSendsOneOrderedFileBatch() throws {
        let box = ActionBox<AppRootAction>()
        let appDelegate = makeRecordingAppDelegate(box: box)
        appDelegate.callbackScheme = "voyager"
        let before = try XCTUnwrap(URL(string: "voyager://before"))
        let unsupported = try XCTUnwrap(URL(string: "https://example.com"))
        let after = try XCTUnwrap(URL(string: "voyager://after"))
        let folder = URL(fileURLWithPath: "/tmp/folder")
        let file = URL(fileURLWithPath: "/tmp/file.txt")
        let collection = URL(fileURLWithPath: "/tmp/saved.voycoll")

        appDelegate.application(NSApp, open: [before, folder, unsupported, file, collection, file, after])
        appDelegate.application(NSApp, open: [folder])

        XCTAssertEqual(box.externalFileBatches, [
            [folder, file, collection, file],
            [folder],
        ])
        XCTAssertEqual(box.externalFileBatchSources, [.systemOpenEvent, .systemOpenEvent])
        XCTAssertEqual(box.externalFileBatchModes, [.open, .open])
        XCTAssertEqual(box.actions.count, 4)
        guard case let .receiveExternalURL(receivedBefore) = box.actions[0] else {
            return XCTFail("첫 file batch 이전 deep link가 먼저 라우팅되어야 합니다.")
        }
        guard case .receiveExternalFileBatch = box.actions[1] else {
            return XCTFail("file batch는 첫 file URL 위치에서 라우팅되어야 합니다.")
        }
        guard case let .receiveExternalURL(receivedAfter) = box.actions[2] else {
            return XCTFail("file batch 이후 deep link가 뒤이어 라우팅되어야 합니다.")
        }
        guard case .receiveExternalFileBatch = box.actions[3] else {
            return XCTFail("별도 callback은 별도 batch를 생성해야 합니다.")
        }
        XCTAssertEqual(receivedBefore, before)
        XCTAssertEqual(receivedAfter, after)
    }

    func testAppDelegateOpenFileSendsSingletonBatch() {
        let box = ActionBox<AppRootAction>()
        let appDelegate = makeRecordingAppDelegate(box: box)
        let path = "/tmp/single.txt"

        XCTAssertTrue(appDelegate.application(NSApp, openFile: path))

        XCTAssertEqual(box.externalFileBatches, [[URL(fileURLWithPath: path)]])
        XCTAssertEqual(box.actions.count, 1)
    }

    func testAppDelegateOpenFilesRepliesOnceAfterBatchEnqueue() {
        let box = ActionBox<AppRootAction>()
        let appDelegate = ReplyRecordingAppDelegate()
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        appDelegate.configure(appRootStore: store)
        appDelegate.actionCount = { box.actions.count }
        let paths = ["/tmp/folder", "/tmp/file.txt", "/tmp/saved.voycoll"]

        appDelegate.application(NSApp, openFiles: paths)

        XCTAssertEqual(box.externalFileBatches, [paths.map(URL.init(fileURLWithPath:))])
        XCTAssertEqual(box.actions.count, 1)
        XCTAssertEqual(appDelegate.replies, [.success])
        XCTAssertEqual(appDelegate.actionCountsAtReply, [1])
    }

    func testAppDelegateEmptyFileCallbacksSendNoBatch() {
        let box = ActionBox<AppRootAction>()
        let appDelegate = ReplyRecordingAppDelegate()
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        appDelegate.configure(appRootStore: store)
        appDelegate.actionCount = { box.actions.count }

        appDelegate.application(NSApp, open: [])
        appDelegate.application(NSApp, openFiles: [])

        XCTAssertTrue(box.actions.isEmpty)
        XCTAssertEqual(appDelegate.replies, [.success])
        XCTAssertEqual(appDelegate.actionCountsAtReply, [0])
    }

    private func makeRecordingAppDelegate(box: ActionBox<AppRootAction>) -> AppDelegate {
        let store = Store<AppRootState, AppRootAction>(initialState: AppRootState()) {
            _ActionRecordingAppRoot(box: box)
        }
        let appDelegate = AppDelegate()
        appDelegate.configure(appRootStore: store)
        return appDelegate
    }

    // MARK: - RCL-002-save_collection_filter_changes

    /// RCL-002-save_collection_filter_changes: external open한 empty Collection의 scope를 저장하고 닫은 뒤 다시 연다.
    /// VOY-590의 bounded AppRoot composition 경로에서 scope-only 편집이 검색 없이 같은 package에 보존되는지 검증한다.
    /// - 검증 내용: normalized external receipt, WindowManager placement, FileManager open/edit/save,
    ///   Content Tab close, second receipt
    /// - 사전 조건: `fixtures/fixtures/collections/empty_definition_collection.voycoll` 복사본과 임시 search root
    /// - 기대 결과: search 요청 0회, 같은 sandbox URL, 저장한 scope definition의 clean reopened baseline
    @MainActor
    func testEmptyCollectionExternalOpenScopeSaveReopenJourney() async throws {
        let sandbox = try CollectionManagementCompositionFixtureSandbox.make()
        defer { sandbox.cleanup() }
        let searchRequests = LockIsolated<[SearchRequestPayload]>([])
        let filterRequests = LockIsolated<[FiltersOnlyRequestPayload]>([])
        let searchWarmUpCount = LockIsolated(0)
        let registeredWindowIDs = LockIsolated<Set<UUID>>([])
        let activatedWindowIDs = LockIsolated<[UUID]>([])
        let store = makeCollectionManagementCompositionStore(
            searchRequests: searchRequests,
            filterRequests: filterRequests,
            searchWarmUpCount: searchWarmUpCount,
            registeredWindowIDs: registeredWindowIDs,
            activatedWindowIDs: activatedWindowIDs,
        )

        await openCollectionExternally(sandbox.collectionURL, in: store)
        let firstWindowID = try activeCollectionWindowID(in: store)
        var window = try activeCollectionWindow(in: store)
        XCTAssertEqual(store.state.windowManager.focusedWindowID, firstWindowID)
        XCTAssertEqual(registeredWindowIDs.value, [firstWindowID])
        XCTAssertEqual(activatedWindowIDs.value, [firstWindowID])
        XCTAssertEqual(window.content.collection.collectionSession.document?.url, sandbox.collectionURL)
        XCTAssertEqual(window.content.collection.collectionContext, CollectionContext())
        XCTAssertFalse(window.content.collection.isDirty)
        await store.send(.windowManager(.windows(.element(
            id: firstWindowID,
            action: .window(.content(.composer(.scopeEditorSetPresented(true)))),
        ))))
        await store.send(.windowManager(.windows(.element(
            id: firstWindowID,
            action: .window(.content(.composer(.candidateScope(.add(path: sandbox.searchRoot.path))))),
        ))))
        await store.send(.windowManager(.windows(.element(
            id: firstWindowID,
            action: .window(.content(.composer(.scopeEditorSetIncludeSubfolders(false)))),
        ))))
        await store.send(.windowManager(.windows(.element(
            id: firstWindowID,
            action: .window(.content(.composer(.scopeEditorSetPresented(false)))),
        ))))
        await store.skipReceivedActions(strict: false)

        window = try activeCollectionWindow(in: store)
        XCTAssertTrue(window.content.collection.isDirty)
        XCTAssertEqual(window.content.collection.collectionSession.document?.url, sandbox.collectionURL)
        XCTAssertTrue(searchRequests.value.isEmpty)
        XCTAssertTrue(filterRequests.value.isEmpty)
        XCTAssertEqual(searchWarmUpCount.value, 0)

        await store.send(.windowManager(.windows(.element(
            id: firstWindowID,
            action: .window(.content(.composer(.saveCollection))),
        ))))
        await store.skipReceivedActions(strict: false)
        window = try activeCollectionWindow(in: store)
        XCTAssertFalse(window.content.collection.isDirty)
        XCTAssertEqual(window.content.collection.collectionSession.document?.url, sandbox.collectionURL)

        try await closeActiveCollectionContentTab(in: store)
        XCTAssertFalse(hasOpenCollection(at: sandbox.collectionURL, in: store))
        await openCollectionExternally(sandbox.collectionURL, in: store)
        XCTAssertEqual(try activeCollectionWindowID(in: store), firstWindowID)
        window = try activeCollectionWindow(in: store)
        let expectedContext = CollectionContext(
            query: "",
            scopes: [sandbox.searchRoot.path],
            excludedScopes: [],
            includeSubfolders: false,
            includeDirectories: false,
            conditions: [],
        )
        XCTAssertEqual(window.content.collection.collectionContext, expectedContext)
        XCTAssertEqual(window.content.collection.collectionSession.metadata.baseline?.context, expectedContext)
        XCTAssertEqual(window.content.collection.collectionSession.document?.url, sandbox.collectionURL)
        XCTAssertEqual(window.content.composer.openedCollectionURL, sandbox.collectionURL)
        XCTAssertFalse(window.content.collection.isDirty)
        XCTAssertTrue(searchRequests.value.isEmpty)
        XCTAssertTrue(filterRequests.value.isEmpty)
        XCTAssertEqual(searchWarmUpCount.value, 0)
        XCTAssertEqual(activatedWindowIDs.value, [firstWindowID, firstWindowID])
        await store.finish()
    }

    /// RCL-002-save_collection_filter_changes: external open한 empty Collection의 query를 저장하고 닫은 뒤 다시 연다.
    /// VOY-590의 bounded AppRoot composition 경로에서 query submit의 accepted response와 같은 package 복원을 검증한다.
    /// - 검증 내용: normalized external receipt, bounded query request, save, Content Tab close,
    ///   second receipt와 clean baseline
    /// - 사전 조건: canonical empty package 복사본, 임시 search root, deterministic accepted-zero search response
    /// - 기대 결과: edit/reopen query 요청 각 1회, filter 요청 0회, 같은 sandbox URL과 저장한 definition 복원
    @MainActor
    func testEmptyCollectionExternalOpenQuerySaveReopenJourney() async throws {
        let sandbox = try CollectionManagementCompositionFixtureSandbox.make()
        defer { sandbox.cleanup() }
        let searchRequests = LockIsolated<[SearchRequestPayload]>([])
        let filterRequests = LockIsolated<[FiltersOnlyRequestPayload]>([])
        let searchWarmUpCount = LockIsolated(0)
        let registeredWindowIDs = LockIsolated<Set<UUID>>([])
        let activatedWindowIDs = LockIsolated<[UUID]>([])
        let acceptedResponse = SearchResponsePayload(itemCount: 0, items: [])
        let store = makeCollectionManagementCompositionStore(
            searchRequests: searchRequests,
            filterRequests: filterRequests,
            searchWarmUpCount: searchWarmUpCount,
            registeredWindowIDs: registeredWindowIDs,
            activatedWindowIDs: activatedWindowIDs,
            searchResponse: acceptedResponse,
        )

        await openCollectionExternally(sandbox.collectionURL, in: store)
        let firstWindowID = try activeCollectionWindowID(in: store)
        var window = try activeCollectionWindow(in: store)
        XCTAssertEqual(store.state.windowManager.focusedWindowID, firstWindowID)
        XCTAssertEqual(registeredWindowIDs.value, [firstWindowID])
        XCTAssertEqual(activatedWindowIDs.value, [firstWindowID])
        XCTAssertEqual(window.content.collection.collectionSession.document?.url, sandbox.collectionURL)
        XCTAssertEqual(window.content.collection.collectionContext, CollectionContext())
        XCTAssertFalse(window.content.collection.isDirty)
        await store.send(.windowManager(.windows(.element(
            id: firstWindowID,
            action: .window(.content(.composer(.scopeEditorSetPresented(true)))),
        ))))
        await store.send(.windowManager(.windows(.element(
            id: firstWindowID,
            action: .window(.content(.composer(.candidateScope(.add(path: sandbox.searchRoot.path))))),
        ))))
        await store.send(.windowManager(.windows(.element(
            id: firstWindowID,
            action: .window(.content(.composer(.scopeEditorSetPresented(false)))),
        ))))
        await store.send(.windowManager(.windows(.element(
            id: firstWindowID,
            action: .window(.content(.composer(.setText("invoice")))),
        ))))
        await store.send(.windowManager(.windows(.element(
            id: firstWindowID,
            action: .window(.content(.composer(.submit))),
        ))))
        await store.skipReceivedActions(strict: false)

        window = try activeCollectionWindow(in: store)
        XCTAssertTrue(window.content.collection.isDirty)
        XCTAssertEqual(window.content.composer.lastSearchResponse, acceptedResponse)
        XCTAssertNotNil(window.content.composer.lastAcceptedSearchRequestID)
        XCTAssertEqual(searchRequests.value.count, 1)
        XCTAssertEqual(searchRequests.value.first?.query, "invoice")
        XCTAssertEqual(searchRequests.value.first?.filters.scopes, [sandbox.searchRoot.path])
        XCTAssertTrue(filterRequests.value.isEmpty)

        await store.send(.windowManager(.windows(.element(
            id: firstWindowID,
            action: .window(.content(.composer(.saveCollection))),
        ))))
        await store.skipReceivedActions(strict: false)
        window = try activeCollectionWindow(in: store)
        XCTAssertFalse(window.content.collection.isDirty)
        XCTAssertEqual(window.content.collection.collectionSession.document?.url, sandbox.collectionURL)
        try await closeActiveCollectionContentTab(in: store)
        XCTAssertFalse(hasOpenCollection(at: sandbox.collectionURL, in: store))
        await openCollectionExternally(sandbox.collectionURL, in: store)

        XCTAssertEqual(try activeCollectionWindowID(in: store), firstWindowID)
        window = try activeCollectionWindow(in: store)
        let expectedContext = CollectionContext(
            query: "invoice",
            scopes: [sandbox.searchRoot.path],
            excludedScopes: [],
            includeSubfolders: true,
            includeDirectories: false,
            conditions: [],
        )
        XCTAssertEqual(window.content.collection.collectionContext, expectedContext)
        XCTAssertEqual(window.content.collection.collectionSession.metadata.baseline?.context, expectedContext)
        XCTAssertEqual(window.content.collection.collectionSession.document?.url, sandbox.collectionURL)
        XCTAssertEqual(window.content.composer.openedCollectionURL, sandbox.collectionURL)
        XCTAssertFalse(window.content.collection.isDirty)
        XCTAssertEqual(searchRequests.value.count, 2)
        XCTAssertEqual(searchRequests.value.map(\.query), ["invoice", "invoice"])
        XCTAssertEqual(searchRequests.value.map(\.filters.scopes), [
            [sandbox.searchRoot.path],
            [sandbox.searchRoot.path],
        ])
        XCTAssertTrue(filterRequests.value.isEmpty)
        XCTAssertEqual(searchWarmUpCount.value, 0)
        XCTAssertEqual(activatedWindowIDs.value, [firstWindowID, firstWindowID])
        await store.finish()
    }

    // MARK: - External open batch FIFO orchestration

    /// 겹친 batch를 enqueue해도 첫 batch만 active이고 다음 batch는 FIFO queue에 남는다.
    func testExternalOpenBatchesExecuteOneAtATimeInFIFOOrder() async throws {
        let firstURL = try XCTUnwrap(URL(string: "file:///tmp/first"))
        let secondURL = try XCTUnwrap(URL(string: "file:///tmp/second"))
        let firstRequest = ExternalFileRouterBatchRequest(
            batchID: UUID(10),
            items: [
                .init(
                    itemID: UUID(11),
                    index: 0,
                    url: firstURL,
                    source: .systemOpenEvent,
                    mode: .open,
                ),
            ],
        )
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.activeExternalOpenBatch = .init(
            batch: .init(request: firstRequest, requiresInitialWindowFallback: false),
            preferredWindowIDs: [],
        )

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.onboardingWindowClient.isRequired = { false }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        // store.exhaustivity = .off: fallback window bootstrap보다 active/queued batch FIFO ownership을 검증함.
        store.exhaustivity = .off

        await store.send(.receiveExternalFileBatch(
            [secondURL],
            source: .systemOpenEvent,
            mode: .open,
        )) {
            $0.externalOpenBatchQueue = [AppRootExternalOpenBatch(
                request: .init(
                    batchID: UUID(0),
                    items: [
                        .init(
                            itemID: UUID(1),
                            index: 0,
                            url: secondURL,
                            source: .systemOpenEvent,
                            mode: .open,
                        ),
                    ],
                ),
                requiresInitialWindowFallback: true,
            )]
            $0.isInitialWindowFallbackPending = true
            $0.isExternalURLRouteInFlightWithoutWindow = true
            $0.isExternalURLFlushDelegateScheduled = true
        }

        XCTAssertEqual(store.state.activeExternalOpenBatch?.batch.request, firstRequest)
    }

    /// normalized 결과는 성공만 placement로 보내고 실패는 원래 index 순서로 보존한다.
    func testBatchNormalizedPlansSuccessesAndKeepsOrderedFailures() async throws {
        let batchID = UUID(100)
        let successID = UUID(101)
        let firstFailureID = UUID(102)
        let secondFailureID = UUID(103)
        let successURL = try XCTUnwrap(URL(string: "file:///tmp/folder"))
        let firstFailureURL = try XCTUnwrap(URL(string: "file:///tmp/missing"))
        let secondFailureURL = try XCTUnwrap(URL(string: "file:///tmp/private"))
        let request = ExternalFileRouterBatchRequest(
            batchID: batchID,
            items: [
                .init(itemID: successID, index: 0, url: successURL, source: .systemOpenEvent, mode: .open),
                .init(itemID: firstFailureID, index: 1, url: firstFailureURL, source: .systemOpenEvent, mode: .open),
                .init(itemID: secondFailureID, index: 2, url: secondFailureURL, source: .systemOpenEvent, mode: .open),
            ],
        )
        let result = ExternalFileRouterBatchResult(
            batchID: batchID,
            items: [
                .init(
                    itemID: successID,
                    index: 0,
                    url: successURL,
                    source: .systemOpenEvent,
                    mode: .open,
                    outcome: .success(.directory(path: "/tmp/folder", revealPath: nil)),
                ),
                .init(
                    itemID: firstFailureID,
                    index: 1,
                    url: firstFailureURL,
                    source: .systemOpenEvent,
                    mode: .open,
                    outcome: .failure(.invalidPath("/tmp/missing")),
                ),
                .init(
                    itemID: secondFailureID,
                    index: 2,
                    url: secondFailureURL,
                    source: .systemOpenEvent,
                    mode: .open,
                    outcome: .failure(.permissionDenied("/tmp/private")),
                ),
            ],
        )
        let events = LockIsolated<[String]>([])
        let registeredWindowIDs = LockIsolated<Set<UUID>>([])
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.activeExternalOpenBatch = .init(
            batch: .init(request: request, requiresInitialWindowFallback: false),
            preferredWindowIDs: [],
        )

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.onboardingWindowClient.isRequired = { false }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { id in
                _ = registeredWindowIDs.withValue { $0.insert(id) }
            }
            $0.fileManagerWindowClient.registeredWindowIDs = { registeredWindowIDs.value }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in
                events.withValue { $0.append("alert") }
            }
            $0.fileManagerWindowClient.activate = { _ in
                events.withValue { $0.append("activate") }
                return .becameKey
            }
        }
        // store.exhaustivity = .off: placement의 child mechanics는 WindowManager owner가 검증함.
        store.exhaustivity = .off

        await store.send(.externalFileRouter(.delegate(.batchNormalized(result)))) {
            $0.activeExternalOpenBatch?.normalizedItems = result.items
            $0.activeExternalOpenBatch?.orderedFailures = Array(result.items.dropFirst())
            $0.activeExternalOpenBatch?.phase = .planning
        }
        XCTAssertEqual(store.state.activeExternalOpenBatch?.phase, .planning)
        await store.finish()
        XCTAssertEqual(events.value, ["alert", "alert", "activate"])
    }

    /// mixed normalization의 successful anchor는 여러 window에서도 valid input subsequence와 동일하다.
    func testMixedBatchAppliesSuccessfulAnchorsAcrossWindowsInInputOrder() async {
        let batchID = UUID(150)
        let collectionURL = URL(fileURLWithPath: "/tmp/ordered.voycoll")
        var inputs: [(URL, ExternalFileRouterBatchOutcome)] = [
            (URL(fileURLWithPath: "/tmp/missing"), .failure(.invalidPath("/tmp/missing"))),
            (URL(fileURLWithPath: "/tmp/folder"), .success(.directory(path: "/tmp/folder", revealPath: nil))),
            (URL(fileURLWithPath: "/tmp/report.txt"), .success(.directory(
                path: "/tmp",
                revealPath: "/tmp/report.txt",
            ))),
            (URL(fileURLWithPath: "/tmp/private"), .failure(.permissionDenied("/tmp/private"))),
            (collectionURL, .success(.collection(path: collectionURL.path))),
        ]
        inputs.append(contentsOf: (0 ..< 18).map { index in
            let path = "/tmp/overflow/\(index)"
            return (URL(fileURLWithPath: path), .success(.directory(path: path, revealPath: nil)))
        })
        inputs.append((URL(fileURLWithPath: "/tmp/missing-last"), .failure(.invalidPath("/tmp/missing-last"))))
        let items = inputs.enumerated().map { index, input in
            ExternalFileRouterBatchRequest.Item(
                itemID: UUID(1000 + index),
                index: index,
                url: input.0,
                source: .systemOpenEvent,
                mode: .open,
            )
        }
        let request = ExternalFileRouterBatchRequest(batchID: batchID, items: items)
        let result = ExternalFileRouterBatchResult(
            batchID: batchID,
            items: zip(items, inputs).map { item, input in
                ExternalFileRouterBatchItemResult(
                    itemID: item.itemID,
                    index: item.index,
                    url: item.url,
                    source: item.source,
                    mode: item.mode,
                    outcome: input.1,
                )
            },
        )
        let expectedAnchors: [ContentTabPageAnchor] = [
            .directory(path: "/tmp/folder"),
            .directory(path: "/tmp"),
            .collectionFile(url: collectionURL),
        ] + (0 ..< 18).map { .directory(path: "/tmp/overflow/\($0)") }
        let registeredWindowIDs = LockIsolated<Set<UUID>>([])
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.activeExternalOpenBatch = .init(
            batch: .init(request: request, requiresInitialWindowFallback: false),
            preferredWindowIDs: [],
        )
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.onboardingWindowClient.isRequired = { false }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { id in
                _ = registeredWindowIDs.withValue { $0.insert(id) }
            }
            $0.fileManagerWindowClient.registeredWindowIDs = { registeredWindowIDs.value }
            $0.fileManagerWindowClient.activate = { _ in .becameKey }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in }
        }
        // store.exhaustivity = .off: layer별 mechanics 대신 AppRoot의 valid-subsequence composition만 검증함.
        store.exhaustivity = .off

        await store.send(.externalFileRouter(.delegate(.batchNormalized(result))))
        await store.receive { action in
            guard case let .windowManager(.placement(.apply(plan, reservationsByItemID))) = action else {
                return false
            }
            return plan.orderedItems.map(\.anchor) == expectedAnchors
                && reservationsByItemID.count == expectedAnchors.count
        }
        await store.finish()
    }

    /// 동일 directory route의 folder/file 요청은 AppRoot 경계에서도 기존 Content Tab 하나로 수렴한다.
    /// - 검증 내용: normalized item 순서, 기존 tab identity 재사용, 신규 reservation 미생성
    /// - 사전 조건: `/tmp/shared`를 표시하는 live window가 있고 같은 폴더와 그 안의 파일을 연속으로 요청함
    /// - 기대 결과: 두 item이 기존 tab을 공유하고 마지막 파일 reveal을 유지하며 capacity를 소비하지 않음
    func testBatchNormalizationReusesExistingTabAndConvergesDuplicateRoute() async {
        let batchID = UUID(180)
        let folderItemID = UUID(181)
        let fileItemID = UUID(182)
        let windowID = UUID(183)
        let folderURL = URL(fileURLWithPath: "/tmp/shared")
        let fileURL = URL(fileURLWithPath: "/tmp/shared/report.txt")
        let request = ExternalFileRouterBatchRequest(
            batchID: batchID,
            items: [
                .init(itemID: folderItemID, index: 0, url: folderURL, source: .systemOpenEvent, mode: .open),
                .init(itemID: fileItemID, index: 1, url: fileURL, source: .systemOpenEvent, mode: .open),
            ],
        )
        let result = ExternalFileRouterBatchResult(
            batchID: batchID,
            items: [
                .init(
                    itemID: folderItemID,
                    index: 0,
                    url: folderURL,
                    source: .systemOpenEvent,
                    mode: .open,
                    outcome: .success(.directory(path: folderURL.path, revealPath: nil)),
                ),
                .init(
                    itemID: fileItemID,
                    index: 1,
                    url: fileURL,
                    source: .systemOpenEvent,
                    mode: .open,
                    outcome: .success(.directory(path: folderURL.path, revealPath: fileURL.path)),
                ),
            ],
        )
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.windowManager.windows = [
            .init(id: windowID, window: .makeInitial(path: folderURL.path)),
        ]
        initialState.windowManager.focusedWindowID = windowID
        initialState.windowManager.lastUsedWindowIDs = [windowID]
        initialState.activeExternalOpenBatch = .init(
            batch: .init(request: request, requiresInitialWindowFallback: false),
            preferredWindowIDs: [windowID],
        )
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileManagerWindowClient.activate = { _ in .becameKey }
        }
        // store.exhaustivity = .off: WindowManager의 native activation 세부 action은 해당 owner suite가 검증함.
        store.exhaustivity = .off

        await store.send(.externalFileRouter(.delegate(.batchNormalized(result))))
        await store.receive { action in
            guard case let .windowManager(.placement(.apply(plan, reservationsByItemID))) = action else {
                return false
            }
            let items = plan.orderedItems
            return items.map(\.itemID) == [folderItemID, fileItemID]
                && Set(items.map(\.tabID)).count == 1
                && items.allSatisfy { !$0.requiresReservation }
                && items.last?.pendingSelectEntryID == fileURL.path
                && reservationsByItemID.isEmpty
        }
        await store.finish()

        XCTAssertEqual(store.state.windowManager.windows.count, 1)
        XCTAssertEqual(store.state.windowManager.windows[id: windowID]?.window.contentTabs.tabs.count, 1)
        XCTAssertEqual(
            store.state.windowManager.windows[id: windowID]?.window.content.pendingSelectEntryID,
            fileURL.path,
        )
    }

    /// termination이 시작되면 normalizing batch를 새 identity로 queue front에 되돌리고 Router batch를 취소한다.
    /// duplicate 항목의 identity와 FIFO 순서를 그대로 보존하는지 함께 검증한다.
    func testTerminationRequeuesActiveNormalizationAtFront() async throws {
        let batchID = UUID(200)
        let retryBatchID = UUID(205)
        let url = try XCTUnwrap(URL(string: "file:///tmp/retry"))
        let items = [
            ExternalFileRouterBatchRequest.Item(
                itemID: UUID(201),
                index: 0,
                url: url,
                source: .systemOpenEvent,
                mode: .open,
            ),
            ExternalFileRouterBatchRequest.Item(
                itemID: UUID(202),
                index: 1,
                url: url,
                source: .systemOpenEvent,
                mode: .open,
            ),
        ]
        let request = ExternalFileRouterBatchRequest(batchID: batchID, items: items)
        let laterRequest = ExternalFileRouterBatchRequest(
            batchID: UUID(203),
            items: [
                .init(itemID: UUID(204), index: 0, url: url, source: .deepLink, mode: .reveal),
            ],
        )
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.externalFileRouter.activeBatchID = batchID
        initialState.activeExternalOpenBatch = .init(
            batch: .init(request: request, requiresInitialWindowFallback: true),
            preferredWindowIDs: [UUID(206)],
        )
        initialState.externalOpenBatchQueue = [
            .init(request: laterRequest, requiresInitialWindowFallback: false),
        ]

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.uuid = .constant(retryBatchID)
        }
        // store.exhaustivity = .off: account-access presentation effect는 기존 lifecycle owner가 검증함.
        store.exhaustivity = .off

        await store.send(.lifecycle(.termination(.willTerminate)))
        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertEqual(store.state.externalOpenBatchQueue.map(\.request), [
            .init(batchID: retryBatchID, items: items),
            laterRequest,
        ])

        await store.receive(\.externalFileRouter.cancelBatch, batchID)
        XCTAssertNil(store.state.externalFileRouter.activeBatchID)
    }

    /// planning 중 termination이 시작되면 입력 identity를 보존한 새 batch로 재큐하고 old placement completion을 무시한다.
    func testTerminationRequeuesPlanningWithFreshIdentityAndIgnoresOldCompletion() async throws {
        let batchID = UUID(210)
        let retryBatchID = UUID(211)
        let duplicateURL = try XCTUnwrap(URL(string: "file:///tmp/planning-duplicate"))
        let items = [
            ExternalFileRouterBatchRequest.Item(
                itemID: UUID(212),
                index: 0,
                url: duplicateURL,
                source: .systemOpenEvent,
                mode: .open,
            ),
            ExternalFileRouterBatchRequest.Item(
                itemID: UUID(213),
                index: 1,
                url: duplicateURL,
                source: .systemOpenEvent,
                mode: .open,
            ),
        ]
        let request = ExternalFileRouterBatchRequest(batchID: batchID, items: items)
        let laterRequest = ExternalFileRouterBatchRequest(
            batchID: UUID(214),
            items: [
                .init(
                    itemID: UUID(215),
                    index: 0,
                    url: URL(fileURLWithPath: "/tmp/later"),
                    source: .deepLink,
                    mode: .reveal,
                ),
            ],
        )
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: request, requiresInitialWindowFallback: false),
            preferredWindowIDs: [UUID(216)],
        )
        active.normalizedItems = items.map { item in
            .init(
                itemID: item.itemID,
                index: item.index,
                url: item.url,
                source: item.source,
                mode: item.mode,
                outcome: .success(.directory(path: "/tmp", revealPath: item.url.path)),
            )
        }
        active.phase = .planning
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.activeExternalOpenBatch = active
        initialState.externalOpenBatchQueue = [
            .init(request: laterRequest, requiresInitialWindowFallback: false),
        ]

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.uuid = .constant(retryBatchID)
        }
        // store.exhaustivity = .off: account-access presentation effect는 기존 lifecycle owner가 검증함.
        store.exhaustivity = .off

        await store.send(.lifecycle(.termination(.willTerminate)))
        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertEqual(store.state.externalOpenBatchQueue.map(\.request), [
            .init(batchID: retryBatchID, items: items),
            laterRequest,
        ])

        let stalePlan = ExternalOpenPlacementPlan(batchID: batchID, windows: [])
        await store.send(.windowManager(.delegate(.externalOpenPlacementCompleted(.init(
            batchID: batchID,
            result: .success(stalePlan),
        )))))

        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertEqual(store.state.externalOpenBatchQueue.map(\.request.batchID), [retryBatchID, laterRequest.batchID])
    }

    /// placement completion 직후 termination이 시작되면 이미 예약된 apply가 window를 변경하지 않고 다음 batch를 동결한다.
    func testTerminationRevokesQueuedPlacementApplication() async throws {
        let batchID = UUID(217)
        let itemID = UUID(218)
        let windowID = UUID(219)
        let nextBatchID = UUID(220)
        let tabID = ContentTabID(rawValue: "revoked-queued-apply")
        let url = try XCTUnwrap(URL(string: "file:///tmp/revoked-queued-apply"))
        let request = ExternalFileRouterBatchRequest(
            batchID: batchID,
            items: [
                .init(itemID: itemID, index: 0, url: url, source: .systemOpenEvent, mode: .open),
            ],
        )
        let nextRequest = ExternalFileRouterBatchRequest(
            batchID: nextBatchID,
            items: [
                .init(
                    itemID: UUID(221),
                    index: 0,
                    url: URL(fileURLWithPath: "/tmp/frozen-next"),
                    source: .systemOpenEvent,
                    mode: .open,
                ),
            ],
        )
        let plan = ExternalOpenPlacementPlan(
            batchID: batchID,
            windows: [
                .init(
                    windowID: windowID,
                    isNewWindow: true,
                    items: [.init(
                        itemID: itemID,
                        tabID: tabID,
                        anchor: .directory(path: url.path),
                    )],
                ),
            ],
        )
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: request, requiresInitialWindowFallback: true),
            preferredWindowIDs: [],
        )
        active.normalizedItems = [
            .init(
                itemID: itemID,
                index: 0,
                url: url,
                source: .systemOpenEvent,
                mode: .open,
                outcome: .success(.directory(path: url.path, revealPath: nil)),
            ),
        ]
        active.placementPlan = plan
        active.phase = .applying
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.windowManager.authorizedExternalOpenBatchID = batchID
        initialState.activeExternalOpenBatch = active
        initialState.externalOpenBatchQueue = [
            .init(request: nextRequest, requiresInitialWindowFallback: true),
        ]
        initialState.isInitialWindowFallbackPending = true
        initialState.isExternalURLRouteInFlightWithoutWindow = true
        let openedWindowIDs = LockIsolated<[UUID]>([])
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.fileManagerWindowClient.open = { id in
                openedWindowIDs.withValue { $0.append(id) }
            }
        }
        // store.exhaustivity = .off: termination action을 queued apply보다 먼저 보내는 composition race만 검증함.
        store.exhaustivity = .off

        await store.send(.lifecycle(.termination(.willTerminate)))
        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertNil(store.state.windowManager.authorizedExternalOpenBatchID)

        await store.send(.windowManager(.placement(.apply(
            plan: plan,
            reservationsByItemID: [
                itemID: .init(id: tabID, anchor: .directory(path: url.path)),
            ],
        ))))
        await store.finish()

        XCTAssertTrue(store.state.windowManager.windows.isEmpty)
        XCTAssertEqual(store.state.externalOpenBatchQueue.map(\.request.batchID), [nextBatchID])
        XCTAssertTrue(openedWindowIDs.value.isEmpty)
    }

    /// apply가 commit한 새 window의 native open은 termination 시 batch cancellation으로 중단된다.
    func testTerminationCancelsDelayedPlacementNativeOpen() async {
        let batchID = UUID(222)
        let itemID = UUID(223)
        let windowID = UUID(224)
        let tabID = ContentTabID(rawValue: "cancelled-placement-open")
        let url = URL(fileURLWithPath: "/tmp/cancelled-placement-open")
        let request = ExternalFileRouterBatchRequest(
            batchID: batchID,
            items: [
                .init(itemID: itemID, index: 0, url: url, source: .systemOpenEvent, mode: .open),
            ],
        )
        let plan = ExternalOpenPlacementPlan(
            batchID: batchID,
            windows: [
                .init(
                    windowID: windowID,
                    isNewWindow: true,
                    items: [.init(
                        itemID: itemID,
                        tabID: tabID,
                        anchor: .directory(path: url.path),
                    )],
                ),
            ],
        )
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: request, requiresInitialWindowFallback: true),
            preferredWindowIDs: [],
        )
        active.normalizedItems = [
            .init(
                itemID: itemID,
                index: 0,
                url: url,
                source: .systemOpenEvent,
                mode: .open,
                outcome: .success(.directory(path: url.path, revealPath: nil)),
            ),
        ]
        active.placementPlan = plan
        active.phase = .applying
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.windowManager.authorizedExternalOpenBatchID = batchID
        initialState.activeExternalOpenBatch = active
        let openStarted = expectation(description: "placement native open started")
        let openCancelled = expectation(description: "placement native open cancelled")
        let nativeCloseCalled = expectation(description: "placement native window closed")
        let closedWindowIDs = LockIsolated<[UUID]>([])
        let openGate = AsyncStream<Void>.makeStream()
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.uuid = .incrementing
            $0.fileManagerWindowClient.open = { id in
                XCTAssertEqual(id, windowID)
                openStarted.fulfill()
                await withTaskCancellationHandler {
                    for await _ in openGate.stream {
                        break
                    }
                } onCancel: {
                    openCancelled.fulfill()
                }
            }
            $0.fileManagerWindowClient.close = { id in
                closedWindowIDs.withValue { $0.append(id) }
                nativeCloseCalled.fulfill()
            }
        }
        // store.exhaustivity = .off: child 초기화보다 batch-scoped native open cancellation 경계를 검증함.
        store.exhaustivity = .off

        await store.send(.windowManager(.placement(.apply(
            plan: plan,
            reservationsByItemID: [
                itemID: .init(id: tabID, anchor: .directory(path: url.path)),
            ],
        ))))
        await fulfillment(of: [openStarted], timeout: 1)

        await store.send(.lifecycle(.termination(.willTerminate)))
        await fulfillment(of: [openCancelled, nativeCloseCalled], timeout: 1)
        await store.skipReceivedActions()

        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertNil(store.state.windowManager.authorizedExternalOpenBatchID)
        XCTAssertNil(store.state.windowManager.externalOpenActivationAttempt)
        XCTAssertNil(store.state.windowManager.retainedExternalOpenPlacementOwnership)
        XCTAssertTrue(store.state.windowManager.windows.isEmpty)
        XCTAssertTrue(store.state.windowManager.externalWindowBatchIDs.isEmpty)
        XCTAssertEqual(closedWindowIDs.value, [windowID])
        openGate.continuation.finish()
        await store.finish()
    }

    /// applying 중 termination이 시작되면 committed batch를 재큐하지 않고 old completion을 무시하며 다음 FIFO를 동결한다.
    func testTerminationDropsApplyingBatchAndFreezesNextQueue() async throws {
        let batchID = UUID(220)
        let nextBatchID = UUID(221)
        let itemID = UUID(222)
        let nextItemID = UUID(223)
        let url = try XCTUnwrap(URL(string: "file:///tmp/applying"))
        let nextURL = try XCTUnwrap(URL(string: "file:///tmp/next-frozen"))
        let request = ExternalFileRouterBatchRequest(
            batchID: batchID,
            items: [
                .init(itemID: itemID, index: 0, url: url, source: .systemOpenEvent, mode: .open),
            ],
        )
        let nextRequest = ExternalFileRouterBatchRequest(
            batchID: nextBatchID,
            items: [
                .init(itemID: nextItemID, index: 0, url: nextURL, source: .systemOpenEvent, mode: .open),
            ],
        )
        let plan = ExternalOpenPlacementPlan(batchID: batchID, windows: [])
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: request, requiresInitialWindowFallback: true),
            preferredWindowIDs: [],
        )
        active.placementPlan = plan
        active.phase = .applying
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.activeExternalOpenBatch = active
        initialState.externalOpenBatchQueue = [
            .init(request: nextRequest, requiresInitialWindowFallback: true),
        ]
        initialState.isInitialWindowFallbackPending = true
        initialState.isExternalURLRouteInFlightWithoutWindow = true
        initialState.isExternalURLFlushDelegateScheduled = true

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        }
        // store.exhaustivity = .off: account-access presentation effect는 기존 lifecycle owner가 검증함.
        store.exhaustivity = .off

        await store.send(.lifecycle(.termination(.willTerminate)))
        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertNil(store.state.windowManager.authorizedExternalOpenBatchID)
        XCTAssertEqual(store.state.externalOpenBatchQueue.map(\.request), [nextRequest])
        XCTAssertTrue(store.state.isInitialWindowFallbackPending)
        XCTAssertTrue(store.state.isExternalURLRouteInFlightWithoutWindow)
        XCTAssertTrue(store.state.isExternalURLFlushDelegateScheduled)

        await store.send(.windowManager(.delegate(.externalOpenApplyCompleted(.init(
            batchID: batchID,
            result: .success(plan),
        )))))

        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertEqual(store.state.externalOpenBatchQueue.map(\.request.batchID), [nextBatchID])
    }

    /// terminal phase의 마지막 batch를 drop하면 no-window bookkeeping만 정리하고 종료 중 창을 열지 않는다.
    func testTerminationDropsLastApplyingBatchWithoutOpeningFallbackWindow() async throws {
        let batchID = UUID(230)
        let itemID = UUID(231)
        let url = try XCTUnwrap(URL(string: "file:///tmp/applying-last"))
        let request = ExternalFileRouterBatchRequest(
            batchID: batchID,
            items: [
                .init(itemID: itemID, index: 0, url: url, source: .systemOpenEvent, mode: .open),
            ],
        )
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: request, requiresInitialWindowFallback: true),
            preferredWindowIDs: [],
        )
        active.placementPlan = .init(batchID: batchID, windows: [])
        active.phase = .applying
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.windowManager.authorizedExternalOpenBatchID = batchID
        initialState.activeExternalOpenBatch = active
        initialState.isInitialWindowFallbackPending = true
        initialState.isExternalURLRouteInFlightWithoutWindow = true
        initialState.isExternalURLFlushDelegateScheduled = true

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.onboardingWindowClient.isRequired = { false }
            $0.onboardingWindowClient.showIfNeeded = { false }
        }
        // store.exhaustivity = .off: account-access presentation effect는 기존 lifecycle owner가 검증함.
        store.exhaustivity = .off

        await store.send(.lifecycle(.termination(.willTerminate)))

        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertNil(store.state.windowManager.authorizedExternalOpenBatchID)
        XCTAssertTrue(store.state.externalOpenBatchQueue.isEmpty)
        XCTAssertFalse(store.state.isInitialWindowFallbackPending)
        XCTAssertFalse(store.state.isExternalURLRouteInFlightWithoutWindow)
        XCTAssertFalse(store.state.isExternalURLFlushDelegateScheduled)
        XCTAssertTrue(store.state.windowManager.windows.isEmpty)

        await store.finish()
    }

    /// stale continuation과 올바른 batch의 너무 이른 advance는 active transaction을 변경하지 않는다.
    func testStaleExternalOpenContinuationsAreNoOps() async throws {
        let batchID = UUID(300)
        let staleBatchID = UUID(399)
        let url = try XCTUnwrap(URL(string: "file:///tmp/stale"))
        let request = ExternalFileRouterBatchRequest(
            batchID: batchID,
            items: [
                .init(itemID: UUID(301), index: 0, url: url, source: .systemOpenEvent, mode: .open),
            ],
        )
        let failure = ExternalFileRouterBatchItemResult(
            itemID: UUID(301),
            index: 0,
            url: url,
            source: .systemOpenEvent,
            mode: .open,
            outcome: .failure(.invalidPath("/tmp/stale")),
        )
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: request, requiresInitialWindowFallback: false),
            preferredWindowIDs: [],
        )
        active.normalizedItems = [failure]
        active.orderedFailures = [failure]
        active.phase = .alerting
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.activeExternalOpenBatch = active

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        }
        let stalePlan = ExternalOpenPlacementPlan(batchID: staleBatchID, windows: [])
        let staleResult = ExternalFileRouterBatchResult(batchID: staleBatchID, items: [])

        await store.send(.externalFileRouter(.delegate(.batchNormalized(staleResult))))
        await store.send(.windowManager(.delegate(.externalOpenPlacementCompleted(.init(
            batchID: staleBatchID,
            result: .success(stalePlan),
        )))))
        await store.send(.windowManager(.delegate(.externalOpenApplyCompleted(.init(
            batchID: staleBatchID,
            result: .success(stalePlan),
        )))))
        await store.send(.externalOpenAlertCompleted(.init(batchID: staleBatchID, failureIndex: 0)))
        await store.send(.windowManager(.delegate(.externalOpenActivationCompleted(
            batchID: staleBatchID,
        ))))
        await store.send(.externalOpenAdvanceToNextBatch(batchID: batchID))

        XCTAssertEqual(store.state.activeExternalOpenBatch, active)
    }

    /// 이전 batch의 placement failure는 현재 planning batch를 변경하지 않는다.
    func testStalePlacementFailureDoesNotMutateCurrentPlanningBatch() async throws {
        let staleBatchID = UUID(650)
        let currentBatchID = UUID(651)
        let currentItemID = UUID(652)
        let url = try XCTUnwrap(URL(string: "file:///tmp/current"))
        let request = ExternalFileRouterBatchRequest(
            batchID: currentBatchID,
            items: [
                .init(itemID: currentItemID, index: 0, url: url, source: .systemOpenEvent, mode: .open),
            ],
        )
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: request, requiresInitialWindowFallback: false),
            preferredWindowIDs: [],
        )
        active.normalizedItems = [
            .init(
                itemID: currentItemID,
                index: 0,
                url: url,
                source: .systemOpenEvent,
                mode: .open,
                outcome: .success(.directory(path: "/tmp/current", revealPath: nil)),
            ),
        ]
        active.phase = .planning
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.windowManager.authorizedExternalOpenBatchID = currentBatchID
        initialState.activeExternalOpenBatch = active
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        }

        await store.send(.windowManager(.delegate(.externalOpenPlacementCompleted(.init(
            batchID: staleBatchID,
            result: .failure(.duplicateItemID(UUID(653))),
        )))))

        XCTAssertEqual(store.state.activeExternalOpenBatch, active)
    }

    /// matching apply failure는 current batch를 종료하고 다음 FIFO batch를 시작한다.
    func testPlacementApplyFailureAdvancesToNextBatch() async throws {
        let firstBatchID = UUID(660)
        let secondBatchID = UUID(661)
        let firstItemID = UUID(662)
        let secondItemID = UUID(663)
        let firstURL = try XCTUnwrap(URL(string: "file:///tmp/apply-failed"))
        let secondURL = try XCTUnwrap(URL(string: "file:///tmp/next"))
        let firstRequest = ExternalFileRouterBatchRequest(
            batchID: firstBatchID,
            items: [
                .init(itemID: firstItemID, index: 0, url: firstURL, source: .systemOpenEvent, mode: .open),
            ],
        )
        let secondRequest = ExternalFileRouterBatchRequest(
            batchID: secondBatchID,
            items: [
                .init(itemID: secondItemID, index: 0, url: secondURL, source: .systemOpenEvent, mode: .open),
            ],
        )
        let plan = ExternalOpenPlacementPlan(batchID: firstBatchID, windows: [])
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: firstRequest, requiresInitialWindowFallback: false),
            preferredWindowIDs: [],
        )
        active.placementPlan = plan
        active.phase = .applying
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.windowManager.authorizedExternalOpenBatchID = firstBatchID
        initialState.activeExternalOpenBatch = active
        initialState.externalOpenBatchQueue = [
            .init(request: secondRequest, requiresInitialWindowFallback: false),
        ]
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.onboardingWindowClient.isRequired = { false }
            $0.pathProbeClient.probeExistence = { _ in
                PathProbeResult(exists: false, isDirectory: false)
            }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in }
        }
        store.exhaustivity = .off

        await store.send(.windowManager(.delegate(.externalOpenApplyCompleted(.init(
            batchID: firstBatchID,
            result: .failure(.validationFailed),
        )))))
        await store.receive(\.externalOpenAdvanceToNextBatch, firstBatchID)

        XCTAssertEqual(store.state.activeExternalOpenBatch?.batch.request.batchID, secondBatchID)
        await store.finish()
    }

    /// 이전 batch의 apply failure는 현재 applying batch를 변경하지 않는다.
    func testStalePlacementApplyFailureDoesNotMutateCurrentBatch() async throws {
        let staleBatchID = UUID(670)
        let currentBatchID = UUID(671)
        let itemID = UUID(672)
        let url = try XCTUnwrap(URL(string: "file:///tmp/current-apply"))
        let request = ExternalFileRouterBatchRequest(
            batchID: currentBatchID,
            items: [
                .init(itemID: itemID, index: 0, url: url, source: .systemOpenEvent, mode: .open),
            ],
        )
        let plan = ExternalOpenPlacementPlan(batchID: currentBatchID, windows: [])
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: request, requiresInitialWindowFallback: false),
            preferredWindowIDs: [],
        )
        active.placementPlan = plan
        active.phase = .applying
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.activeExternalOpenBatch = active
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        }

        await store.send(.windowManager(.delegate(.externalOpenApplyCompleted(.init(
            batchID: staleBatchID,
            result: .failure(.validationFailed),
        )))))

        XCTAssertEqual(store.state.activeExternalOpenBatch, active)
    }

    /// pending singleton terminal 전에는 다음 queued batch를 active로 만들지 않는다.
    func testPendingURLTerminalBlocksNextQueuedBatchAdmission() throws {
        let activeBatchID = UUID(680)
        let activeItemID = UUID(681)
        let queuedBatchID = UUID(682)
        let queuedItemID = UUID(683)
        let windowID = UUID(684)
        let tabID = ContentTabID(rawValue: "pending-terminal-window-tab")
        let activeURL = try XCTUnwrap(URL(string: "file:///tmp/active"))
        let pendingURL = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2Ftmp%2Fpending"))
        let queuedURL = try XCTUnwrap(URL(string: "file:///tmp/queued"))
        let activeRequest = ExternalFileRouterBatchRequest(
            batchID: activeBatchID,
            items: [
                .init(itemID: activeItemID, index: 0, url: activeURL, source: .systemOpenEvent, mode: .open),
            ],
        )
        let queuedRequest = ExternalFileRouterBatchRequest(
            batchID: queuedBatchID,
            items: [
                .init(itemID: queuedItemID, index: 0, url: queuedURL, source: .systemOpenEvent, mode: .open),
            ],
        )
        let window = try XCTUnwrap(FileManagerWindowFeature.State.makeExternalInitial(
            reservations: [
                .init(id: tabID, anchor: .directory(path: "/tmp")),
            ],
        ))
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: activeRequest, requiresInitialWindowFallback: false),
            preferredWindowIDs: [],
        )
        active.phase = .advancing
        var state = AppRootFeature.State()
        state.lifecycle.didFinishLaunching = true
        state.lifecycle.didStartHelper = true
        state.lifecycle.didCompleteEntryCoreHealthProbe = true
        state.lifecycle.didCreateInitialWindow = true
        state.windowManager.windows = [.init(id: windowID, window: window)]
        state.pendingExternalURLs = [pendingURL]
        state.externalOpenBatchQueue = [
            .init(request: queuedRequest, requiresInitialWindowFallback: false),
        ]
        state.activeExternalOpenBatch = active
        let feature = AppRootFeature()

        withDependencies {
            $0.uuid = .incrementing
            $0.onboardingWindowClient.isRequired = { false }
        } operation: {
            _ = feature.advanceExternalOpenBatch(batchID: activeBatchID, state: &state)
        }

        XCTAssertNil(state.activeExternalOpenBatch)
        XCTAssertEqual(state.activePendingExternalURL, .init(requestID: UUID(0), url: pendingURL))
        XCTAssertTrue(state.pendingExternalURLs.isEmpty)
        XCTAssertEqual(state.externalOpenBatchQueue.map(\.request.batchID), [queuedBatchID])

        withDependencies {
            $0.onboardingWindowClient.isRequired = { false }
        } operation: {
            _ = feature.consumePendingExternalURLCompletion(requestID: UUID(999), state: &state)
        }
        XCTAssertNil(state.activeExternalOpenBatch)
        XCTAssertEqual(state.externalOpenBatchQueue.map(\.request.batchID), [queuedBatchID])

        withDependencies {
            $0.onboardingWindowClient.isRequired = { false }
        } operation: {
            _ = feature.consumePendingExternalURLCompletion(requestID: UUID(0), state: &state)
        }
        XCTAssertNil(state.activePendingExternalURL)
        XCTAssertEqual(state.activeExternalOpenBatch?.batch.request.batchID, queuedBatchID)
        XCTAssertTrue(state.externalOpenBatchQueue.isEmpty)
    }

    /// 창이 없는 all-invalid batch 종료도 pending singleton을 먼저 admit하고 terminal 뒤 queued batch를 재개한다.
    func testColdAllInvalidBatchPrioritizesPendingURLBeforeQueuedBatch() throws {
        let activeBatchID = UUID(685)
        let queuedBatchID = UUID(686)
        let pendingURL = try XCTUnwrap(URL(string: "voyager://open?url=https%3A%2F%2Fexample.com"))
        let queuedURL = URL(fileURLWithPath: "/tmp/cold-queued")
        let activeRequest = ExternalFileRouterBatchRequest(batchID: activeBatchID, items: [])
        let queuedRequest = ExternalFileRouterBatchRequest(
            batchID: queuedBatchID,
            items: [
                .init(
                    itemID: UUID(687),
                    index: 0,
                    url: queuedURL,
                    source: .systemOpenEvent,
                    mode: .open,
                ),
            ],
        )
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: activeRequest, requiresInitialWindowFallback: true),
            preferredWindowIDs: [],
        )
        active.phase = .advancing
        var state = AppRootFeature.State()
        state.lifecycle.didFinishLaunching = true
        state.lifecycle.didStartHelper = true
        state.lifecycle.didCompleteEntryCoreHealthProbe = true
        state.lifecycle.didCreateInitialWindow = true
        state.activeExternalOpenBatch = active
        state.pendingExternalURLs = [pendingURL]
        state.externalOpenBatchQueue = [
            .init(request: queuedRequest, requiresInitialWindowFallback: true),
        ]
        state.isInitialWindowFallbackPending = true
        state.isExternalURLRouteInFlightWithoutWindow = true
        let feature = AppRootFeature()

        withDependencies {
            $0.uuid = .incrementing
            $0.onboardingWindowClient.isRequired = { false }
        } operation: {
            _ = feature.advanceExternalOpenBatch(batchID: activeBatchID, state: &state)
        }

        XCTAssertTrue(state.windowManager.windows.isEmpty)
        XCTAssertNil(state.activeExternalOpenBatch)
        XCTAssertEqual(state.activePendingExternalURL, .init(requestID: UUID(0), url: pendingURL))
        XCTAssertTrue(state.pendingExternalURLs.isEmpty)
        XCTAssertEqual(state.externalOpenBatchQueue.map(\.request.batchID), [queuedBatchID])
        XCTAssertTrue(state.isInitialWindowFallbackPending)

        withDependencies {
            $0.onboardingWindowClient.isRequired = { false }
        } operation: {
            _ = feature.consumePendingExternalURLCompletion(requestID: UUID(0), state: &state)
        }

        XCTAssertNil(state.activePendingExternalURL)
        XCTAssertEqual(state.activeExternalOpenBatch?.batch.request.batchID, queuedBatchID)
        XCTAssertTrue(state.externalOpenBatchQueue.isEmpty)
        XCTAssertTrue(state.isInitialWindowFallbackPending)
    }

    /// 첫 external window가 열려도 active batch terminal 전에는 pending URL을 flush하지 않는다.
    func testFirstExternalWindowDefersPendingURLFlushUntilBatchAdvance() async throws {
        let batchID = UUID(690)
        let itemID = UUID(691)
        let windowID = UUID(692)
        let tabID = ContentTabID(rawValue: "pending-url-order-tab")
        let fileURL = try XCTUnwrap(URL(string: "file:///tmp/pending-url-order"))
        let pendingURL = try XCTUnwrap(URL(string: "voyager://pending-after-batch"))
        let request = ExternalFileRouterBatchRequest(
            batchID: batchID,
            items: [
                .init(itemID: itemID, index: 0, url: fileURL, source: .systemOpenEvent, mode: .open),
            ],
        )
        let plan = ExternalOpenPlacementPlan(
            batchID: batchID,
            windows: [
                .init(
                    windowID: windowID,
                    isNewWindow: true,
                    items: [.init(
                        itemID: itemID,
                        tabID: tabID,
                        anchor: .directory(path: fileURL.path),
                    )],
                ),
            ],
        )
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: request, requiresInitialWindowFallback: true),
            preferredWindowIDs: [],
        )
        active.normalizedItems = [
            .init(
                itemID: itemID,
                index: 0,
                url: fileURL,
                source: .systemOpenEvent,
                mode: .open,
                outcome: .success(.directory(path: fileURL.path, revealPath: nil)),
            ),
        ]
        active.placementPlan = plan
        active.phase = .applying
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.pendingExternalURLs = [pendingURL]
        initialState.windowManager.authorizedExternalOpenBatchID = batchID
        initialState.activeExternalOpenBatch = active

        let activationStarted = expectation(description: "native activation started")
        let activationGate = AsyncStream<Void>.makeStream()
        let registeredWindowIDs = LockIsolated<Set<UUID>>([])
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.onboardingWindowClient.isRequired = { false }
            $0.fileManagerWindowClient.open = { id in
                _ = registeredWindowIDs.withValue { $0.insert(id) }
            }
            $0.fileManagerWindowClient.registeredWindowIDs = { registeredWindowIDs.value }
            $0.fileManagerWindowClient.activate = { _ in
                activationStarted.fulfill()
                for await _ in activationGate.stream {
                    break
                }
                return .becameKey
            }
        }
        // store.exhaustivity = .off: child window mechanics를 건너뛰고 pending route ordering만 검증함.
        store.exhaustivity = .off

        await store.send(.windowManager(.placement(.apply(
            plan: plan,
            reservationsByItemID: [
                itemID: .init(id: tabID, anchor: .directory(path: fileURL.path)),
            ],
        ))))
        await fulfillment(of: [activationStarted], timeout: 1)

        XCTAssertEqual(store.state.pendingExternalURLs, [pendingURL])

        activationGate.continuation.yield(())
        activationGate.continuation.finish()
        await store.receive(\.windowManager.delegate.externalOpenActivationCompleted, batchID)
        await store.receive(\.externalOpenAdvanceToNextBatch, batchID)
        await store.receive { action in
            guard case let .externalFileRouter(.receiveTracked(url, requestID: _)) = action else {
                return false
            }
            return url == pendingURL
        }

        XCTAssertTrue(store.state.pendingExternalURLs.isEmpty)
        await store.finish()
    }

    /// AppRoot가 matching activation failure terminal을 수락할 때 ownership을 release한 뒤 batch를 advance한다.
    /// 이후 같은 batch의 stale cancel은 성공한 window나 persistent marker를 제거하지 않는다.
    func testActivationTerminalAcceptanceReleasesPlacementOwnershipBeforeAdvance() async throws {
        let batchID = UUID()
        let itemID = UUID()
        let windowID = UUID()
        let tabID = ContentTabID(rawValue: "terminal-retained-window")
        let url = URL(fileURLWithPath: "/tmp/terminal-retained-window")
        let request = ExternalFileRouterBatchRequest(
            batchID: batchID,
            items: [
                .init(itemID: itemID, index: 0, url: url, source: .systemOpenEvent, mode: .open),
            ],
        )
        let plan = ExternalOpenPlacementPlan(
            batchID: batchID,
            windows: [
                .init(
                    windowID: windowID,
                    isNewWindow: true,
                    items: [.init(itemID: itemID, tabID: tabID)],
                ),
            ],
        )
        let window = try XCTUnwrap(FileManagerWindowFeature.State.makeExternalInitial(reservations: [
            .init(id: tabID, anchor: .directory(path: url.path)),
        ]))
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: request, requiresInitialWindowFallback: false),
            preferredWindowIDs: [],
        )
        active.placementPlan = plan
        active.phase = .activating
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.activeExternalOpenBatch = active
        initialState.windowManager.windows = [.init(id: windowID, window: window)]
        initialState.windowManager.externalWindowBatchIDs = [windowID: batchID]
        initialState.windowManager.retainedExternalOpenPlacementOwnership = .init(
            batchID: batchID,
            newWindowIDs: [windowID],
        )
        let closedWindowIDs = LockIsolated<[UUID]>([])
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.fileManagerWindowClient.close = { id in
                closedWindowIDs.withValue { $0.append(id) }
            }
        }
        // store.exhaustivity = .off: AppRoot terminal acceptance와 stale cancel 경계만 검증함.
        store.exhaustivity = .off

        await store.send(.windowManager(.delegate(.externalOpenActivationFailed(
            batchID: batchID,
            failure: .recoveryExhausted,
        )))) {
            $0.windowManager.retainedExternalOpenPlacementOwnership = nil
            $0.activeExternalOpenBatch?.phase = .advancing
        }
        await store.receive(\.externalOpenAdvanceToNextBatch, batchID)
        await store.send(.windowManager(.placement(.cancel(batchID: batchID))))
        await store.finish()

        XCTAssertEqual(store.state.windowManager.windows.map(\.id), [windowID])
        XCTAssertEqual(store.state.windowManager.externalWindowBatchIDs, [windowID: batchID])
        XCTAssertTrue(closedWindowIDs.value.isEmpty)
    }

    /// native activation이 끝나기 전에는 다음 batch를 시작하지 않는다.
    func testDelayedNativeActivationBlocksNextBatchStart() async throws {
        let firstBatchID = UUID(700)
        let secondBatchID = UUID(701)
        let firstItemID = UUID(702)
        let secondItemID = UUID(703)
        let windowID = UUID(704)
        let tabID = ContentTabID(rawValue: "activation-tab")
        let firstURL = try XCTUnwrap(URL(string: "file:///tmp/first"))
        let secondURL = try XCTUnwrap(URL(string: "file:///tmp/second"))
        let firstRequest = ExternalFileRouterBatchRequest(
            batchID: firstBatchID,
            items: [
                .init(itemID: firstItemID, index: 0, url: firstURL, source: .systemOpenEvent, mode: .open),
            ],
        )
        let secondRequest = ExternalFileRouterBatchRequest(
            batchID: secondBatchID,
            items: [
                .init(itemID: secondItemID, index: 0, url: secondURL, source: .systemOpenEvent, mode: .open),
            ],
        )
        let plan = ExternalOpenPlacementPlan(
            batchID: firstBatchID,
            windows: [
                .init(
                    windowID: windowID,
                    isNewWindow: false,
                    items: [.init(itemID: firstItemID, tabID: tabID)],
                ),
            ],
        )
        let reservation = ExternalContentTabReservation(
            id: tabID,
            anchor: .directory(path: "/tmp/first"),
        )
        let window = try XCTUnwrap(FileManagerWindowFeature.State.makeExternalInitial(
            reservations: [reservation],
        ))
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: firstRequest, requiresInitialWindowFallback: false),
            preferredWindowIDs: [],
        )
        active.normalizedItems = [
            .init(
                itemID: firstItemID,
                index: 0,
                url: firstURL,
                source: .systemOpenEvent,
                mode: .open,
                outcome: .success(.directory(path: "/tmp/first", revealPath: nil)),
            ),
        ]
        active.placementPlan = plan
        active.phase = .applying
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.windowManager.windows = [.init(id: windowID, window: window)]
        initialState.windowManager.authorizedExternalOpenBatchID = firstBatchID
        initialState.activeExternalOpenBatch = active
        initialState.externalOpenBatchQueue = [
            .init(request: secondRequest, requiresInitialWindowFallback: false),
        ]

        let activationStarted = expectation(description: "native activation started")
        let activationGate = AsyncStream<Void>.makeStream()
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.onboardingWindowClient.isRequired = { false }
            $0.fileManagerWindowClient.activate = { _ in
                activationStarted.fulfill()
                for await _ in activationGate.stream {
                    break
                }
                return .becameKey
            }
            $0.pathProbeClient.probeExistence = { _ in
                PathProbeResult(exists: false, isDirectory: false)
            }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in }
        }
        // store.exhaustivity = .off: child placement mechanics를 건너뛰고 activation terminal 순서만 검증함.
        store.exhaustivity = .off

        await store.send(.windowManager(.delegate(.externalOpenApplyCompleted(.init(
            batchID: firstBatchID,
            result: .success(plan),
        ))))) {
            $0.activeExternalOpenBatch?.phase = .activating
        }
        await store.receive(\.windowManager.placement.activate, plan)
        await fulfillment(of: [activationStarted], timeout: 1)

        XCTAssertEqual(store.state.activeExternalOpenBatch?.batch.request.batchID, firstBatchID)
        XCTAssertEqual(store.state.externalOpenBatchQueue.map(\.request.batchID), [secondBatchID])

        activationGate.continuation.yield(())
        activationGate.continuation.finish()
        await store.receive(\.windowManager.delegate.externalOpenActivationCompleted, firstBatchID)
        await store.receive(\.externalOpenAdvanceToNextBatch, firstBatchID)

        XCTAssertEqual(store.state.activeExternalOpenBatch?.batch.request.batchID, secondBatchID)
        await store.finish()
    }

    /// activating native effect가 지연된 동안 termination이 시작되면 late completion이 다음 batch를 시작하지 않는다.
    func testTerminationDuringDelayedActivationDropsBatchAndFreezesNextQueue() async throws {
        let batchID = UUID(710)
        let nextBatchID = UUID(711)
        let itemID = UUID(712)
        let nextItemID = UUID(713)
        let windowID = UUID(714)
        let tabID = ContentTabID(rawValue: "gate-closure-activation-tab")
        let url = try XCTUnwrap(URL(string: "file:///tmp/activation-gate"))
        let nextURL = try XCTUnwrap(URL(string: "file:///tmp/activation-next"))
        let request = ExternalFileRouterBatchRequest(
            batchID: batchID,
            items: [
                .init(itemID: itemID, index: 0, url: url, source: .systemOpenEvent, mode: .open),
            ],
        )
        let nextRequest = ExternalFileRouterBatchRequest(
            batchID: nextBatchID,
            items: [
                .init(itemID: nextItemID, index: 0, url: nextURL, source: .systemOpenEvent, mode: .open),
            ],
        )
        let plan = ExternalOpenPlacementPlan(
            batchID: batchID,
            windows: [
                .init(
                    windowID: windowID,
                    isNewWindow: false,
                    items: [.init(itemID: itemID, tabID: tabID)],
                ),
            ],
        )
        let reservation = ExternalContentTabReservation(
            id: tabID,
            anchor: .directory(path: "/tmp/activation-gate"),
        )
        let window = try XCTUnwrap(FileManagerWindowFeature.State.makeExternalInitial(
            reservations: [reservation],
        ))
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: request, requiresInitialWindowFallback: false),
            preferredWindowIDs: [],
        )
        active.normalizedItems = [
            .init(
                itemID: itemID,
                index: 0,
                url: url,
                source: .systemOpenEvent,
                mode: .open,
                outcome: .success(.directory(path: "/tmp/activation-gate", revealPath: nil)),
            ),
        ]
        active.placementPlan = plan
        active.phase = .applying
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.windowManager.windows = [.init(id: windowID, window: window)]
        initialState.windowManager.authorizedExternalOpenBatchID = batchID
        initialState.activeExternalOpenBatch = active
        initialState.externalOpenBatchQueue = [
            .init(request: nextRequest, requiresInitialWindowFallback: false),
        ]

        let activationStarted = expectation(description: "gate closure activation started")
        let activationCancelled = expectation(description: "gate closure activation cancelled")
        let activationGate = AsyncStream<Void>.makeStream()
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.fileManagerWindowClient.activate = { _ in
                activationStarted.fulfill()
                await withTaskCancellationHandler {
                    for await _ in activationGate.stream {
                        break
                    }
                } onCancel: {
                    activationCancelled.fulfill()
                }
                return .becameKey
            }
        }
        // store.exhaustivity = .off: child activation mechanics 대신 gate closure 이후 terminal 경계만 검증함.
        store.exhaustivity = .off

        await store.send(.windowManager(.delegate(.externalOpenApplyCompleted(.init(
            batchID: batchID,
            result: .success(plan),
        ))))) {
            $0.activeExternalOpenBatch?.phase = .activating
        }
        await store.receive(\.windowManager.placement.activate, plan)
        await fulfillment(of: [activationStarted], timeout: 1)
        XCTAssertNotNil(store.state.windowManager.externalOpenActivationAttempt)

        await store.send(.lifecycle(.termination(.willTerminate)))
        await fulfillment(of: [activationCancelled], timeout: 1)
        await store.skipReceivedActions()
        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertEqual(store.state.externalOpenBatchQueue.map(\.request.batchID), [nextBatchID])

        activationGate.continuation.finish()
        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertNil(store.state.windowManager.authorizedExternalOpenBatchID)
        XCTAssertNil(store.state.windowManager.externalOpenActivationAttempt)
        XCTAssertEqual(store.state.externalOpenBatchQueue.map(\.request.batchID), [nextBatchID])
        await store.finish()
    }

    /// final target discard 뒤 시작한 retry activation도 termination 시 같은 batch cancellation으로 중단된다.
    func testTerminationCancelsDelayedRetryActivation() async throws {
        let batchID = UUID(715)
        let firstWindowID = UUID(716)
        let finalWindowID = UUID(717)
        let firstTabID = ContentTabID(rawValue: "retry-cancel-first")
        let finalTabID = ContentTabID(rawValue: "retry-cancel-final")
        let plan = ExternalOpenPlacementPlan(
            batchID: batchID,
            windows: [
                .init(
                    windowID: firstWindowID,
                    isNewWindow: false,
                    items: [.init(itemID: UUID(718), tabID: firstTabID)],
                ),
                .init(
                    windowID: finalWindowID,
                    isNewWindow: false,
                    items: [.init(itemID: UUID(719), tabID: finalTabID)],
                ),
            ],
        )
        let firstWindow = try XCTUnwrap(FileManagerWindowFeature.State.makeExternalInitial(reservations: [
            .init(id: firstTabID, anchor: .directory(path: "/tmp/retry-cancel-first")),
        ]))
        let finalWindow = try XCTUnwrap(FileManagerWindowFeature.State.makeExternalInitial(reservations: [
            .init(id: finalTabID, anchor: .directory(path: "/tmp/retry-cancel-final")),
        ]))
        let request = ExternalFileRouterBatchRequest(
            batchID: batchID,
            items: [
                .init(
                    itemID: UUID(720),
                    index: 0,
                    url: URL(fileURLWithPath: "/tmp/retry-cancel"),
                    source: .systemOpenEvent,
                    mode: .open,
                ),
            ],
        )
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: request, requiresInitialWindowFallback: false),
            preferredWindowIDs: [],
        )
        active.placementPlan = plan
        active.phase = .activating
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.windowManager.windows = [
            .init(id: firstWindowID, window: firstWindow),
            .init(id: finalWindowID, window: finalWindow),
        ]
        initialState.windowManager.authorizedExternalOpenBatchID = batchID
        initialState.activeExternalOpenBatch = active
        let retryStarted = expectation(description: "retry activation started")
        let retryCancelled = expectation(description: "retry activation cancelled")
        let retryGate = AsyncStream<Void>.makeStream()
        let activatedWindowIDs = LockIsolated<[UUID]>([])
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.fileManagerWindowClient.activate = { windowID in
                activatedWindowIDs.withValue { $0.append(windowID) }
                if windowID == finalWindowID {
                    return .discarded
                }
                XCTAssertEqual(windowID, firstWindowID)
                retryStarted.fulfill()
                await withTaskCancellationHandler {
                    for await _ in retryGate.stream {
                        break
                    }
                } onCancel: {
                    retryCancelled.fulfill()
                }
                return .becameKey
            }
        }
        // store.exhaustivity = .off: retry attempt action보다 batch-scoped cancellation 전파를 검증함.
        store.exhaustivity = .off

        await store.send(.windowManager(.placement(.activate(plan))))
        await fulfillment(of: [retryStarted], timeout: 1)
        XCTAssertEqual(activatedWindowIDs.value, [finalWindowID, firstWindowID])

        await store.send(.lifecycle(.termination(.willTerminate)))
        await fulfillment(of: [retryCancelled], timeout: 1)
        await store.skipReceivedActions()

        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertNil(store.state.windowManager.authorizedExternalOpenBatchID)
        XCTAssertNil(store.state.windowManager.externalOpenActivationAttempt)
        retryGate.continuation.finish()
        await store.finish()
    }

    /// warm all-invalid batch는 ordered alerts를 끝낸 뒤 window mutation 없이 종료한다.
    func testWarmAllInvalidShowsOrderedAlertsAndMutatesNoWindows() async throws {
        let batchID = UUID(400)
        let firstURL = try XCTUnwrap(URL(string: "file:///tmp/missing"))
        let secondURL = try XCTUnwrap(URL(string: "file:///tmp/private"))
        let request = ExternalFileRouterBatchRequest(
            batchID: batchID,
            items: [
                .init(itemID: UUID(401), index: 0, url: firstURL, source: .systemOpenEvent, mode: .open),
                .init(itemID: UUID(402), index: 1, url: secondURL, source: .systemOpenEvent, mode: .open),
            ],
        )
        let result = ExternalFileRouterBatchResult(
            batchID: batchID,
            items: [
                .init(
                    itemID: UUID(401),
                    index: 0,
                    url: firstURL,
                    source: .systemOpenEvent,
                    mode: .open,
                    outcome: .failure(.invalidPath("/tmp/missing")),
                ),
                .init(
                    itemID: UUID(402),
                    index: 1,
                    url: secondURL,
                    source: .systemOpenEvent,
                    mode: .open,
                    outcome: .failure(.permissionDenied("/tmp/private")),
                ),
            ],
        )
        let alerts = LockIsolated<[String]>([])
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.activeExternalOpenBatch = .init(
            batch: .init(request: request, requiresInitialWindowFallback: false),
            preferredWindowIDs: [],
        )

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, message in
                alerts.withValue { $0.append(message) }
            }
        }
        // store.exhaustivity = .off: ordered terminal actions의 state 경계만 검증함.
        store.exhaustivity = .off

        await store.send(.externalFileRouter(.delegate(.batchNormalized(result))))
        await store.receive(
            \.externalOpenAlertCompleted,
            ExternalOpenAlertCompletion(batchID: batchID, failureIndex: 0),
        )
        await store.receive(
            \.externalOpenAlertCompleted,
            ExternalOpenAlertCompletion(batchID: batchID, failureIndex: 1),
        )
        await store.receive(\.externalOpenAdvanceToNextBatch, batchID)

        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertTrue(store.state.windowManager.windows.isEmpty)
        XCTAssertEqual(alerts.value.count, 2)
        XCTAssertFalse(alerts.value[0].contains("/tmp/private"))
        XCTAssertTrue(alerts.value[1].contains("/tmp/private"))
    }

    /// cold all-invalid batch는 queue drain 뒤 ordinary initial-window fallback을 정확히 한 번 재개한다.
    func testColdAllInvalidResumesInitialWindowAfterQueueDrain() async throws {
        let batchID = UUID(500)
        let url = try XCTUnwrap(URL(string: "file:///tmp/missing"))
        let request = ExternalFileRouterBatchRequest(
            batchID: batchID,
            items: [
                .init(itemID: UUID(501), index: 0, url: url, source: .systemOpenEvent, mode: .open),
            ],
        )
        let result = ExternalFileRouterBatchResult(
            batchID: batchID,
            items: [
                .init(
                    itemID: UUID(501),
                    index: 0,
                    url: url,
                    source: .systemOpenEvent,
                    mode: .open,
                    outcome: .failure(.invalidPath("/tmp/missing")),
                ),
            ],
        )
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.isInitialWindowFallbackPending = true
        initialState.isExternalURLRouteInFlightWithoutWindow = true
        initialState.activeExternalOpenBatch = .init(
            batch: .init(request: request, requiresInitialWindowFallback: true),
            preferredWindowIDs: [],
        )

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.onboardingWindowClient.isRequired = { false }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        // store.exhaustivity = .off: ordinary Home window 생성의 세부 mechanics는 WindowManager owner가 검증함.
        store.exhaustivity = .off

        await store.send(.externalFileRouter(.delegate(.batchNormalized(result))))
        await store.receive(
            \.externalOpenAlertCompleted,
            ExternalOpenAlertCompletion(batchID: batchID, failureIndex: 0),
        )
        await store.receive(\.externalOpenAdvanceToNextBatch, batchID)
        await store.receive(\.windowManager.lifecycle.openInitialWindowIfNeeded)

        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertFalse(store.state.isInitialWindowFallbackPending)
        await store.finish()
    }

    /// alert 처리 중 도착한 batch는 active를 교체하지 않고 FIFO queue에 대기한다.
    func testBatchQueuedDuringAlertDoesNotReplaceActiveBatch() async throws {
        let activeURL = try XCTUnwrap(URL(string: "file:///tmp/active"))
        let queuedURL = try XCTUnwrap(URL(string: "file:///tmp/queued"))
        let activeRequest = ExternalFileRouterBatchRequest(
            batchID: UUID(600),
            items: [
                .init(itemID: UUID(601), index: 0, url: activeURL, source: .systemOpenEvent, mode: .open),
            ],
        )
        var active = AppRootActiveExternalOpenBatch(
            batch: .init(request: activeRequest, requiresInitialWindowFallback: false),
            preferredWindowIDs: [],
        )
        active.phase = .alerting
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.activeExternalOpenBatch = active

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.onboardingWindowClient.isRequired = { false }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        // store.exhaustivity = .off: generated queue identity는 URL order로 검증함.
        store.exhaustivity = .off

        await store.send(.receiveExternalFileBatch(
            [queuedURL],
            source: .systemOpenEvent,
            mode: .open,
        ))

        XCTAssertEqual(store.state.activeExternalOpenBatch?.batch.request, activeRequest)
        XCTAssertEqual(store.state.externalOpenBatchQueue.flatMap { $0.request.items.map(\.url) }, [queuedURL])
    }

    /// tracked singleton이 active이면 새 batch는 queue에 남고 matching terminal 뒤에만 시작한다.
    func testBatchArrivingWhileTrackedSingletonActiveWaitsForMatchingTerminal() throws {
        let requestID = UUID(800)
        let staleRequestID = UUID(801)
        let pendingURL = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2Ftmp%2Fpending"))
        let batchURL = URL(fileURLWithPath: "/tmp/batch-after-singleton")
        var state = AppRootFeature.State()
        state.lifecycle.didFinishLaunching = true
        state.lifecycle.didStartHelper = true
        state.lifecycle.didCompleteEntryCoreHealthProbe = true
        state.lifecycle.didCreateInitialWindow = true
        state.activePendingExternalURL = .init(requestID: requestID, url: pendingURL)
        let feature = AppRootFeature()

        withDependencies {
            $0.uuid = .incrementing
            $0.onboardingWindowClient.isRequired = { false }
        } operation: {
            _ = feature.enqueueExternalOpenBatch(
                urls: [batchURL],
                source: .systemOpenEvent,
                mode: .open,
                state: &state,
            )
        }
        XCTAssertNil(state.activeExternalOpenBatch)
        XCTAssertEqual(state.externalOpenBatchQueue.count, 1)

        _ = feature.consumePendingExternalURLCompletion(requestID: staleRequestID, state: &state)
        XCTAssertEqual(state.activePendingExternalURL?.requestID, requestID)
        XCTAssertNil(state.activeExternalOpenBatch)

        withDependencies {
            $0.onboardingWindowClient.isRequired = { false }
        } operation: {
            _ = feature.consumePendingExternalURLCompletion(requestID: requestID, state: &state)
        }
        XCTAssertNil(state.activePendingExternalURL)
        XCTAssertNotNil(state.activeExternalOpenBatch)
        XCTAssertTrue(state.externalOpenBatchQueue.isEmpty)
    }

    /// active batch가 있으면 pending singleton은 시작되지 않는다.
    func testPendingSingletonDoesNotStartWhileBatchActive() throws {
        let pendingURL = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2Ftmp%2Fpending-during-batch"))
        let batchURL = URL(fileURLWithPath: "/tmp/active-batch")
        let batch = ExternalFileRouterBatchRequest(
            batchID: UUID(810),
            items: [.init(itemID: UUID(811), index: 0, url: batchURL, source: .systemOpenEvent, mode: .open)],
        )
        var state = AppRootFeature.State()
        state.lifecycle.didFinishLaunching = true
        state.lifecycle.didStartHelper = true
        state.lifecycle.didCompleteEntryCoreHealthProbe = true
        state.lifecycle.didCreateInitialWindow = true
        state.pendingExternalURLs = [pendingURL]
        state.activeExternalOpenBatch = .init(
            batch: .init(request: batch, requiresInitialWindowFallback: false),
            preferredWindowIDs: [],
        )

        withDependencies {
            $0.uuid = .incrementing
        } operation: {
            _ = AppRootFeature().startNextPendingExternalURLIfPossible(state: &state)
        }

        XCTAssertNil(state.activePendingExternalURL)
        XCTAssertEqual(state.pendingExternalURLs, [pendingURL])
        XCTAssertEqual(state.activeExternalOpenBatch?.batch.request.batchID, batch.batchID)
    }

    /// idle warm 첫 deep link도 tracked scheduler를 시작해 뒤이은 URL을 직렬화한다.
    func testIdleWarmDeepLinksEnterTrackedSchedulerInFIFOOrder() throws {
        let windowID = UUID(805)
        let firstURL = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2Ftmp%2Fwarm-first"))
        let secondURL = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2Ftmp%2Fwarm-second"))
        var state = AppRootFeature.State()
        state.lifecycle.didFinishLaunching = true
        state.lifecycle.didStartHelper = true
        state.lifecycle.didCompleteEntryCoreHealthProbe = true
        state.lifecycle.didCreateInitialWindow = true
        state.windowManager.windows = [.init(id: windowID, window: .makeInitial(path: "/existing"))]
        let feature = AppRootFeature()

        withDependencies {
            $0.uuid = .incrementing
            $0.onboardingWindowClient.isRequired = { false }
        } operation: {
            _ = feature.enqueueExternalURL(firstURL, state: &state)
            _ = feature.enqueueExternalURL(secondURL, state: &state)
        }

        XCTAssertEqual(state.activePendingExternalURL, .init(requestID: UUID(0), url: firstURL))
        XCTAssertEqual(state.pendingExternalURLs, [secondURL])
    }

    /// warm window의 새 deep link는 active singleton을 우회하지 않고 pending FIFO에 합류한다.
    func testWarmDeepLinkQueuesBehindActiveTrackedSingleton() async throws {
        let requestID = UUID(807)
        let windowID = UUID(808)
        let activeURL = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2Ftmp%2Factive"))
        let nextURL = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2Ftmp%2Fnext"))
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.windowManager.windows = [.init(id: windowID, window: .makeInitial(path: "/existing"))]
        initialState.activePendingExternalURL = .init(requestID: requestID, url: activeURL)
        initialState.externalFileRouter.activeTrackedRequestID = requestID
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        }
        await store.send(.receiveExternalURL(nextURL)) {
            $0.pendingExternalURLs = [nextURL]
        }
        XCTAssertEqual(store.state.activePendingExternalURL?.requestID, requestID)
        XCTAssertEqual(store.state.windowManager.windows.ids.count, 1)
        await store.finish()
    }

    /// warm window의 새 deep link는 active batch terminal 전 Router singleton으로 진입하지 않는다.
    func testWarmDeepLinkQueuesBehindActiveBatch() async throws {
        let windowID = UUID(809)
        let batchURL = URL(fileURLWithPath: "/tmp/active-batch")
        let nextURL = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2Ftmp%2Fnext-after-batch"))
        let batch = ExternalFileRouterBatchRequest(
            batchID: UUID(810),
            items: [.init(itemID: UUID(811), index: 0, url: batchURL, source: .systemOpenEvent, mode: .open)],
        )
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.windowManager.windows = [.init(id: windowID, window: .makeInitial(path: "/existing"))]
        initialState.activeExternalOpenBatch = .init(
            batch: .init(request: batch, requiresInitialWindowFallback: false),
            preferredWindowIDs: [windowID],
        )
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        }
        await store.send(.receiveExternalURL(nextURL)) {
            $0.pendingExternalURLs = [nextURL]
        }
        XCTAssertEqual(store.state.activeExternalOpenBatch?.batch.request.batchID, batch.batchID)
        XCTAssertNil(store.state.activePendingExternalURL)
        await store.finish()
    }

    /// termination은 active occurrence를 front에 보존하고 stale route를 거부하며 retry identity를 갱신한다.
    func testTerminationRequeuesTrackedSingletonWithFreshIdentityAndRejectsStaleRoute() async throws {
        let oldRequestID = UUID(812)
        let freshRequestID = UUID(813)
        let duplicateURL = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2Ftmp%2Fduplicate"))
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.activePendingExternalURL = .init(requestID: oldRequestID, url: duplicateURL)
        initialState.pendingExternalURLs = [duplicateURL]
        initialState.externalFileRouter.activeTrackedRequestID = oldRequestID
        initialState.windowManager.authorizedTrackedSingletonRequestID = oldRequestID
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.onboardingWindowClient.isRequired = { false }
            $0.onboardingWindowClient.showIfNeeded = { false }
        }
        // store.exhaustivity = .off: lifecycle presentation effect보다 singleton cancellation/requeue 경계를 검증함.
        store.exhaustivity = .off

        await store.send(.lifecycle(.termination(.willTerminate)))
        XCTAssertNil(store.state.activePendingExternalURL)
        XCTAssertEqual(store.state.pendingExternalURLs, [duplicateURL, duplicateURL])
        XCTAssertNil(store.state.windowManager.authorizedTrackedSingletonRequestID)
        await store.receive(\.externalFileRouter.cancelTrackedRequest, oldRequestID)
        XCTAssertNil(store.state.externalFileRouter.activeTrackedRequestID)

        await store.send(.externalFileRouter(.delegate(.openFolder(
            path: "/tmp/stale",
            trackedRequestID: oldRequestID,
        ))))
        XCTAssertTrue(store.state.windowManager.windows.isEmpty)
        XCTAssertNil(store.state.windowManager.authorizedTrackedSingletonRequestID)

        var retryState = store.state
        retryState.lifecycle.didFinishLaunching = true
        retryState.lifecycle.didStartHelper = true
        retryState.lifecycle.didCompleteEntryCoreHealthProbe = true
        retryState.lifecycle.didCreateInitialWindow = true
        withDependencies {
            $0.uuid = .constant(freshRequestID)
            $0.onboardingWindowClient.isRequired = { false }
        } operation: {
            _ = AppRootFeature().startNextPendingExternalURLIfPossible(state: &retryState)
        }
        XCTAssertEqual(
            retryState.activePendingExternalURL,
            .init(requestID: freshRequestID, url: duplicateURL),
        )
        XCTAssertEqual(retryState.pendingExternalURLs, [duplicateURL])
        XCTAssertNotEqual(oldRequestID, retryState.activePendingExternalURL?.requestID)
        await store.finish()
    }

    /// delayed native open 중 termination은 생성 session을 rollback하고 native window를 close한다.
    func testTerminationDuringDelayedTrackedNativeOpenRollsBackWindowAndRequeues() async throws {
        let requestID = UUID(818)
        let windowID = UUID(819)
        let url = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2Ftmp%2Fdelayed-gate"))
        let openStarted = expectation(description: "tracked native open started")
        let closeCompleted = expectation(description: "tracked native close completed")
        let openGate = AsyncStream<Void>.makeStream()
        let closedIDs = LockIsolated<[UUID]>([])
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.activePendingExternalURL = .init(requestID: requestID, url: url)
        initialState.externalFileRouter.activeTrackedRequestID = requestID
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.uuid = .constant(windowID)
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.onboardingWindowClient.isRequired = { false }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in
                openStarted.fulfill()
                for await _ in openGate.stream {
                    break
                }
            }
            $0.fileManagerWindowClient.close = { id in
                closedIDs.withValue { $0.append(id) }
                closeCompleted.fulfill()
            }
        }
        // store.exhaustivity = .off: child 초기화 action보다 gate revoke의 rollback/close 경계를 검증함.
        store.exhaustivity = .off

        await store.send(.externalFileRouter(.delegate(.openFolder(
            path: "/tmp/delayed-gate",
            trackedRequestID: requestID,
        )))) {
            $0.windowManager.authorizedTrackedSingletonRequestID = requestID
        }
        await store.receive(\.windowManager.trackedSingleton)
        await fulfillment(of: [openStarted], timeout: 1)
        XCTAssertEqual(
            store.state.windowManager.trackedSingletonWindow,
            .init(requestID: requestID, windowID: windowID),
        )
        XCTAssertEqual(store.state.windowManager.windows.ids.count, 1)

        await store.send(.lifecycle(.termination(.willTerminate)))
        await fulfillment(of: [closeCompleted], timeout: 1)
        await store.skipReceivedActions()

        XCTAssertNil(store.state.activePendingExternalURL)
        XCTAssertEqual(store.state.pendingExternalURLs, [url])
        XCTAssertNil(store.state.windowManager.authorizedTrackedSingletonRequestID)
        XCTAssertNil(store.state.windowManager.trackedSingletonWindow)
        XCTAssertTrue(store.state.windowManager.windows.isEmpty)
        XCTAssertNil(store.state.externalFileRouter.activeTrackedRequestID)
        XCTAssertEqual(closedIDs.value, [windowID])
        openGate.continuation.finish()
        await store.finish()
    }

    /// delayed fallback revoke는 native open뿐 아니라 후속 default bootstrap도 취소한다.
    func testTerminationDuringDelayedTrackedFallbackCancelsBootstrapAndRollsBack() async throws {
        let requestID = UUID(820)
        let windowID = UUID(821)
        let url = try XCTUnwrap(URL(string: "voyager://open"))
        let openStarted = expectation(description: "tracked fallback native open started")
        let closeCompleted = expectation(description: "tracked fallback native close completed")
        let openGate = AsyncStream<Void>.makeStream()
        let ensureCount = LockIsolated(0)
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.activePendingExternalURL = .init(requestID: requestID, url: url)
        initialState.externalFileRouter.activeTrackedRequestID = requestID
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.uuid = .constant(windowID)
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.onboardingWindowClient.isRequired = { false }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerBuiltInCollectionClient.ensureAll = {
                ensureCount.withValue { $0 += 1 }
                return .init(recents: .failed, allTags: .failed)
            }
            $0.fileManagerWindowClient.open = { _ in
                openStarted.fulfill()
                for await _ in openGate.stream {
                    break
                }
            }
            $0.fileManagerWindowClient.close = { _ in closeCompleted.fulfill() }
        }
        // store.exhaustivity = .off: fallback revoke가 native open 이후 bootstrap까지 취소하는 경계를 검증함.
        store.exhaustivity = .off

        await store.send(.externalFileRouter(.delegate(.openAppFallback(trackedRequestID: requestID)))) {
            $0.windowManager.authorizedTrackedSingletonRequestID = requestID
        }
        await store.receive(\.windowManager.trackedSingleton)
        await fulfillment(of: [openStarted], timeout: 1)
        await store.send(.lifecycle(.termination(.willTerminate)))
        await fulfillment(of: [closeCompleted], timeout: 1)
        await store.skipReceivedActions()

        XCTAssertEqual(ensureCount.value, 0)
        XCTAssertTrue(store.state.windowManager.windows.isEmpty)
        XCTAssertEqual(store.state.pendingExternalURLs, [url])
        openGate.continuation.finish()
        await store.finish()
    }

    /// native open completion 뒤 parent terminal 전 termination도 retained ownership으로 rollback한다.
    func testTerminationAfterNativeOpenBeforeParentTerminalRollsBackWindow() async throws {
        let requestID = UUID(822)
        let windowID = UUID(823)
        let url = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2Ftmp%2Fterminal-gap"))
        let closeCompleted = expectation(description: "terminal-gap native close completed")
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.activePendingExternalURL = .init(requestID: requestID, url: url)
        initialState.externalFileRouter.activeTrackedRequestID = requestID
        initialState.windowManager.windows = [.init(id: windowID, window: .makeInitial(path: "/tmp/terminal-gap"))]
        initialState.windowManager.trackedSingletonWindow = .init(requestID: requestID, windowID: windowID)
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.fileManagerWindowClient.close = { id in
                XCTAssertEqual(id, windowID)
                closeCompleted.fulfill()
            }
            $0.undoManagerClient.invalidateWindow = { id in
                XCTAssertEqual(id, windowID)
                return .init(succeeded: true, availability: .init())
            }
        }
        // store.exhaustivity = .off: native completion과 queued parent terminal 사이 revoke ownership만 검증함.
        store.exhaustivity = .off

        await store.send(.lifecycle(.termination(.willTerminate)))
        await fulfillment(of: [closeCompleted], timeout: 1)
        await store.skipReceivedActions()
        XCTAssertNotNil(store.state.windowManager.windows[id: windowID])

        await store.send(.windowManager(.event(.windowClosed(windowID))))
        await store.receive(\.windowManager.windowInvalidationFinished)

        XCTAssertTrue(store.state.windowManager.windows.isEmpty)
        XCTAssertNil(store.state.windowManager.trackedSingletonWindow)
        XCTAssertEqual(store.state.pendingExternalURLs, [url])
        await store.finish()
    }

    /// termination gate closure도 active singleton을 front에 되돌리고 Router request를 취소한다.
    func testTerminationRequeuesAndCancelsActiveTrackedSingleton() async throws {
        let requestID = UUID(814)
        let url = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2Ftmp%2Ftermination"))
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.activePendingExternalURL = .init(requestID: requestID, url: url)
        initialState.externalFileRouter.activeTrackedRequestID = requestID
        initialState.windowManager.authorizedTrackedSingletonRequestID = requestID
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        }
        // store.exhaustivity = .off: termination child fanout보다 singleton requeue/cancel 경계를 검증함.
        store.exhaustivity = .off

        await store.send(.lifecycle(.termination(.willTerminate)))
        XCTAssertNil(store.state.activePendingExternalURL)
        XCTAssertEqual(store.state.pendingExternalURLs, [url])
        XCTAssertNil(store.state.windowManager.authorizedTrackedSingletonRequestID)
        await store.receive(\.externalFileRouter.cancelTrackedRequest, requestID)
        XCTAssertNil(store.state.externalFileRouter.activeTrackedRequestID)
        await store.finish()
    }

    /// invalid/permission alert는 await가 끝난 뒤에만 tracked parent를 terminal 처리한다.
    func testTrackedInvalidAlertCompletionWaitsForAlertBoundary() async throws {
        try await assertTrackedAlertCompletionWaitsForBoundary(permissionDenied: false)
    }

    func testTrackedPermissionAlertCompletionWaitsForAlertBoundary() async throws {
        try await assertTrackedAlertCompletionWaitsForBoundary(permissionDenied: true)
    }

    /// tracked auth compatibility는 identity/gate를 검증한 뒤 AccountAccess handoff 수락에서 종료한다.
    func testTrackedAuthCompatibilityTerminatesAtAccountAccessHandoff() async throws {
        let requestID = UUID(815)
        let staleRequestID = UUID(816)
        let pendingURL = try XCTUnwrap(URL(string: "voyager://auth/callback?code=tracked"))
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.activePendingExternalURL = .init(requestID: requestID, url: pendingURL)
        initialState.externalFileRouter.activeTrackedRequestID = requestID
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        }
        // store.exhaustivity = .off: AccountAccess network lifecycle은 별도 owner이고 handoff terminal만 검증함.
        store.exhaustivity = .off

        await store.send(.externalFileRouter(.delegate(.routeToAuthCallback(
            pendingURL,
            trackedRequestID: staleRequestID,
        ))))
        XCTAssertEqual(store.state.activePendingExternalURL?.requestID, requestID)

        await store.send(.externalFileRouter(.delegate(.routeToAuthCallback(
            pendingURL,
            trackedRequestID: requestID,
        ))))
        await store.receive(\.receiveTrackedAuthCallbackURL)
        await store.receive(\.lifecycle.accountAccess.loginCallbackReceived)
        await store.receive(\.externalFileRouter.singletonRequestCompleted, requestID)
        XCTAssertNil(store.state.activePendingExternalURL)
        await store.finish()
    }

    private func assertTrackedAlertCompletionWaitsForBoundary(permissionDenied: Bool) async throws {
        let requestID = UUID(817)
        let pendingURL = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2Ftmp%2Falert"))
        let alertStarted = expectation(description: "tracked alert started")
        let alertGate = AsyncStream<Void>.makeStream()
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.activePendingExternalURL = .init(requestID: requestID, url: pendingURL)
        initialState.externalFileRouter.activeTrackedRequestID = requestID
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in
                alertStarted.fulfill()
                for await _ in alertGate.stream {
                    break
                }
            }
        }
        // store.exhaustivity = .off: alert UI boundary와 parent terminal 순서만 검증함.
        store.exhaustivity = .off

        let delegate: ExternalFileRouterAction.Delegate = permissionDenied
            ? .showPermissionDeniedError(path: "/tmp/alert", trackedRequestID: requestID)
            : .showInvalidPathError(path: "/tmp/alert", trackedRequestID: requestID)
        await store.send(.externalFileRouter(.delegate(delegate)))
        await fulfillment(of: [alertStarted], timeout: 1)
        XCTAssertEqual(store.state.activePendingExternalURL?.requestID, requestID)

        alertGate.continuation.yield(())
        alertGate.continuation.finish()
        await store.receive(\.externalFileRouter.singletonRequestCompleted, requestID)
        XCTAssertNil(store.state.activePendingExternalURL)
        await store.finish()
    }

    /// folder tracked route는 native open 반환 전 다음 batch를 admit하지 않는다.
    func testTrackedFolderNativeOpenBlocksNextBatchAdmission() async throws {
        try await assertTrackedSingletonNativeOpenBlocksBatch(route: .folder)
    }

    /// app fallback tracked route는 native initial-window open 반환 전 다음 batch를 admit하지 않는다.
    func testTrackedFallbackNativeOpenBlocksNextBatchAdmission() async throws {
        try await assertTrackedSingletonNativeOpenBlocksBatch(route: .fallback)
    }

    /// reveal tracked route도 parent window native open 반환 전 다음 batch를 admit하지 않는다.
    func testTrackedRevealNativeOpenBlocksNextBatchAdmission() async throws {
        try await assertTrackedSingletonNativeOpenBlocksBatch(route: .reveal)
    }

    private enum TrackedRouteScenario {
        case folder
        case fallback
        case reveal
    }

    private func assertTrackedSingletonNativeOpenBlocksBatch(route: TrackedRouteScenario) async throws {
        let requestID = UUID(820)
        let pendingURL = try XCTUnwrap(URL(string: "voyager://open?url=file%3A%2F%2F%2Ftmp%2Ftracked"))
        let batchURL = URL(fileURLWithPath: "/tmp/batch-after-native-open")
        let openStarted = expectation(description: "tracked native open started")
        let openGate = AsyncStream<Void>.makeStream()
        let registeredWindowIDs = LockIsolated<Set<UUID>>([])
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        initialState.activePendingExternalURL = .init(requestID: requestID, url: pendingURL)
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.onboardingWindowClient.isRequired = { false }
            $0.contentTabPinnedRecordClient.loadStore = { _ in ContentTabPinnedRecordStore() }
            $0.fileManagerWindowClient.open = { id in
                registeredWindowIDs.withValue { $0.insert(id) }
                openStarted.fulfill()
                for await _ in openGate.stream {
                    break
                }
            }
            $0.fileManagerWindowClient.registeredWindowIDs = { registeredWindowIDs.value }
            $0.pathProbeClient.probeExistence = { _ in PathProbeResult(exists: false, isDirectory: false) }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in }
        }
        // store.exhaustivity = .off: child window 초기화보다 native open terminal과 scheduler admission을 검증함.
        store.exhaustivity = .off

        let delegate: ExternalFileRouterAction.Delegate = switch route {
        case .folder:
            .openFolder(path: "/tmp/tracked", trackedRequestID: requestID)
        case .fallback:
            .openAppFallback(trackedRequestID: requestID)
        case .reveal:
            .openParentFolder(
                path: "/tmp",
                selectEntryPath: "/tmp/tracked.txt",
                trackedRequestID: requestID,
            )
        }
        await store.send(.externalFileRouter(.delegate(delegate))) {
            $0.windowManager.authorizedTrackedSingletonRequestID = requestID
        }
        await store.receive(\.windowManager.trackedSingleton)
        await fulfillment(of: [openStarted], timeout: 1)

        await store.send(.receiveExternalFileBatch([batchURL], source: .systemOpenEvent, mode: .open))
        XCTAssertEqual(store.state.activePendingExternalURL?.requestID, requestID)
        XCTAssertNil(store.state.activeExternalOpenBatch)
        XCTAssertEqual(store.state.externalOpenBatchQueue.count, 1)

        openGate.continuation.yield(())
        openGate.continuation.finish()
        await store.receive(\.windowManager.trackedSingletonNativeOpenCompleted, requestID)
        await store.receive(\.windowManager.delegate.trackedSingletonCompleted, requestID)
        XCTAssertNil(store.state.activePendingExternalURL)
        XCTAssertNil(store.state.externalFileRouter.activeTrackedRequestID)
        XCTAssertNil(store.state.windowManager.trackedSingletonWindow)
        XCTAssertNotNil(store.state.activeExternalOpenBatch)
        XCTAssertTrue(store.state.externalOpenBatchQueue.isEmpty)
        await store.receive(\.externalFileRouter.receiveBatch)

        XCTAssertNil(store.state.activePendingExternalURL)
        XCTAssertNotNil(store.state.activeExternalOpenBatch)
        XCTAssertTrue(store.state.externalOpenBatchQueue.isEmpty)
        await store.finish()
    }

    private func makeCollectionManagementCompositionStore(
        searchRequests: LockIsolated<[SearchRequestPayload]>,
        filterRequests: LockIsolated<[FiltersOnlyRequestPayload]>,
        searchWarmUpCount: LockIsolated<Int>,
        registeredWindowIDs: LockIsolated<Set<UUID>>,
        activatedWindowIDs: LockIsolated<[UUID]>,
        searchResponse: SearchResponsePayload = .init(itemCount: 0, items: []),
    ) -> TestStoreOf<AppRootFeature> {
        var initialState = AppRootFeature.State()
        initialState.lifecycle.didFinishLaunching = true
        initialState.lifecycle.didStartHelper = true
        initialState.lifecycle.didCompleteEntryCoreHealthProbe = true
        initialState.lifecycle.didCreateInitialWindow = true
        // develop의 external-open placement는 이미 존재하는 초기 윈도우를 재사용 대상으로 본다.
        // didCreateInitialWindow=true는 실제 윈도우 세션을 만들지 않으므로 테스트에서 직접 구성한다.
        let initialWindowID = UUID()
        let initialWindow = WindowSessionState(
            id: initialWindowID,
            window: .makeInitial(path: nil),
        )
        initialState.windowManager.windows.append(initialWindow)
        initialState.windowManager.focusedWindowID = initialWindowID
        initialState.windowManager.lastUsedWindowIDs = [initialWindowID]
        registeredWindowIDs.withValue { $0.insert(initialWindowID) }
        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        } withDependencies: {
            $0.collectionFileClient = .liveValue
            $0.collectionAlertClient = .testValue
            $0.collectionStalenessClient = .testValue
            $0.registryClient = .testValue
            $0.searchClient.search = { request in
                searchRequests.withValue { $0.append(request) }
                return searchResponse
            }
            $0.searchClient.applyFilters = { request in
                filterRequests.withValue { $0.append(request) }
                return .init(itemCount: 0, items: [])
            }
            $0.searchClient.warmUpAIModelCatalog = {
                searchWarmUpCount.withValue { $0 += 1 }
            }
            $0.userDefaultsClient = .testValue
            $0.pathProbeClient.probeExistence = { path in
                var isDirectory = ObjCBool(false)
                let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                return PathProbeResult(exists: exists, isDirectory: isDirectory.boolValue)
            }
            $0.fileManagerWindowClient.open = { id in
                _ = registeredWindowIDs.withValue { $0.insert(id) }
            }
            $0.fileManagerWindowClient.close = { id in
                _ = registeredWindowIDs.withValue { $0.remove(id) }
            }
            $0.fileManagerWindowClient.finalizeClose = { id in
                _ = registeredWindowIDs.withValue { $0.remove(id) }
            }
            $0.fileManagerWindowClient.registeredWindowIDs = { registeredWindowIDs.value }
            $0.fileManagerWindowClient.activate = { id in
                activatedWindowIDs.withValue { $0.append(id) }
                return .becameKey
            }
            $0.onboardingWindowClient.isRequired = { false }
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_200))
            $0.uuid = .incrementing
            $0.continuousClock = ImmediateClock()
        }
        // store.exhaustivity = .off: AppRoot부터 FileManager까지의 composition journey는
        // terminal state와 dependency cardinality를 검증함.
        store.exhaustivity = .off(showSkippedAssertions: false)
        return store
    }

    private func openCollectionExternally(
        _ url: URL,
        in store: TestStoreOf<AppRootFeature>,
    ) async {
        await store.send(.receiveExternalFileBatch([url], source: .systemOpenEvent, mode: .open))
        await store.skipReceivedActions(strict: false)
    }

    private func closeActiveCollectionContentTab(
        in store: TestStoreOf<AppRootFeature>,
    ) async throws {
        let windowID = try activeCollectionWindowID(in: store)
        let window = try activeCollectionWindow(in: store)
        guard let tabID = window.contentTabs.activeTabID else {
            throw CollectionManagementCompositionJourneyError.activeContentTabNotFound
        }
        await store.send(.windowManager(.windows(.element(
            id: windowID,
            action: .window(.closeContentTabRequested(tabID)),
        ))))
        await store.skipReceivedActions(strict: false)
    }

    private func activeCollectionWindowID(
        in store: TestStoreOf<AppRootFeature>,
    ) throws -> UUID {
        guard let session = store.state.windowManager.windows.first(where: {
            $0.window.content.collection.collectionSession.document != nil
        }) else {
            throw CollectionManagementCompositionJourneyError.activeCollectionWindowNotFound
        }
        return session.id
    }

    private func activeCollectionWindow(
        in store: TestStoreOf<AppRootFeature>,
    ) throws -> FileManagerWindowState {
        let windowID = try activeCollectionWindowID(in: store)
        guard let window = store.state.windowManager.windows[id: windowID]?.window else {
            throw CollectionManagementCompositionJourneyError.activeCollectionWindowNotFound
        }
        return window
    }

    private func hasOpenCollection(
        at url: URL,
        in store: TestStoreOf<AppRootFeature>,
    ) -> Bool {
        store.state.windowManager.windows.contains {
            $0.window.content.collection.collectionSession.document?.url == url
        }
    }
}

// MARK: - VOY-521 Task 1 test support

private final class ActionBox<T>: @unchecked Sendable {
    var actions: [T] = []
}

private extension ActionBox where T == AppRootAction {
    var externalFileBatches: [[URL]] {
        actions.compactMap { action in
            guard case let .receiveExternalFileBatch(urls, _, _) = action else { return nil }
            return urls
        }
    }

    var externalFileBatchSources: [RouteSource] {
        actions.compactMap { action in
            guard case let .receiveExternalFileBatch(_, source, _) = action else { return nil }
            return source
        }
    }

    var externalFileBatchModes: [DeepLinkMode] {
        actions.compactMap { action in
            guard case let .receiveExternalFileBatch(_, _, mode) = action else { return nil }
            return mode
        }
    }
}

private final class ReplyRecordingAppDelegate: AppDelegate {
    var actionCount: () -> Int = { 0 }
    var replies: [NSApplication.DelegateReply] = []
    var actionCountsAtReply: [Int] = []

    override func reply(
        toOpenOrPrint reply: NSApplication.DelegateReply,
        sender _: NSApplication,
    ) {
        replies.append(reply)
        actionCountsAtReply.append(actionCount())
    }
}

private enum AppCollectionOpenBridgeFailure {
    case invalidDefinition
    case malformed
    case access
    case unknown

    var error: any Error {
        switch self {
        case .invalidDefinition:
            CollectionFileCompatibilityError.invalidDefinitionPayload
        case .malformed:
            CollectionFileCompatibilityError.invalidPropertyListPayload
        case .access:
            CocoaError(.fileReadNoPermission)
        case .unknown:
            NSError(domain: "CollectionOpenUnknown", code: 1)
        }
    }
}

private enum CollectionManagementCompositionJourneyError: Error {
    case activeCollectionWindowNotFound
    case activeContentTabNotFound
}

private struct _ActionRecordingAppRoot: Reducer {
    typealias State = AppRootState
    typealias Action = AppRootAction

    let box: ActionBox<AppRootAction>

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            box.actions.append(action)
            return .none
        }
    }
}
