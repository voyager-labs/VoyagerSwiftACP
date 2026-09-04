import Foundation
@testable import Voyager
import XCTest

@MainActor
final class ProductAnalyticsRegistryTests: XCTestCase {
    func testBundledMetadataOnlyMetricsPreserveBaselinePrivacyAsRegistryGrows() throws {
        let appBundle = VoyagerTestSupport.hostApplicationBundle()
        let registryURL = try XCTUnwrap(appBundle.url(forResource: "ProductAnalyticsRegistry", withExtension: "json"))
        let document = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: registryURL)) as? [String: Any],
        )
        let metadataOnlyMetrics = try XCTUnwrap(document["metadata_only_metrics"] as? [[String: Any]])
        let registry = ProductAnalyticsRegistry.load(bundle: appBundle)

        XCTAssertEqual(metadataOnlyMetrics.count, 3)
        XCTAssertEqual(registry.metadataOnlyMetricCount, 3)
        XCTAssertEqual(registry.records.count, 378)
        XCTAssertEqual(
            registry.resolve(
                metricKey: "dau.navigation",
                identity: .device("test-device-id"),
                properties: [
                    "source_surface": .string("file_manager"),
                    "raw_path": .string("/private/secret.txt"),
                ],
            ),
            .drop(.privacyRejected),
        )
        XCTAssertEqual(
            registry.resolve(
                metricKey: "dau.navigation",
                identity: .device("test-device-id"),
                properties: ["source_surface": .string("token_value")],
            ),
            .drop(.privacyRejected),
        )
    }

    func testBundledRegistryLoadsCurrent378Records() {
        let appBundle = VoyagerTestSupport.hostApplicationBundle()
        XCTAssertEqual(ProductAnalyticsRegistry.load(bundle: appBundle).records.count, 378)

        let metadata = ProductAnalyticsRegistry.loadResult(bundle: appBundle)
        guard case let .loaded(registry) = metadata else {
            return XCTFail("expected bundled registry")
        }
        XCTAssertEqual(registry.metadataOnlyMetricCount, 3)

        XCTAssertEqual(registry.records.count(where: { $0.implementationStatus == .implemented }), 45)
        XCTAssertEqual(registry.records.count(where: { $0.implementationStatus == .noEventRequired }), 29)
        XCTAssertEqual(registry.records.count(where: { $0.implementationStatus == .tbd }), 304)
        XCTAssertTrue(registry.records.filter { $0.implementationStatus == .implemented }
            .allSatisfy { $0.relatedIssues == ["VOY-691"] })
        XCTAssertTrue(registry.records.filter { $0.implementationStatus != .implemented }
            .allSatisfy { $0.relatedIssues == ["VOY-691"] })
        XCTAssertEqual(
            Set(registry.records.filter { $0.implementationStatus == .implemented }.compactMap(\.posthogEventName)),
            Set([
                "voyager_onboarding_completed",
                "voyager_onboarding_permission_result",
                "voyager_ai_provider_setup_result",
                "voyager_content_browsing_engaged",
                "voyager_content_tab_action_result",
                "voyager_entry_action_result",
                "voyager_ai_chat_turn_submitted",
                "voyager_ai_chat_turn_result",
                "voyager_collection_filter_query_result",
                "voyager_collection_filter_apply_result",
            ]),
        )
        for interactionID in [
            "FMW-001-close_file_manager_window",
            "FMW-002-adjust_sidebar_width",
        ] {
            let record = registry.records.first { $0.interactionID == interactionID }
            XCTAssertEqual(record?.implementationStatus, .tbd)
            XCTAssertEqual(record?.featureID, interactionID.hasPrefix("FMW-001") ? "FMW-001" : "FMW-002")
            XCTAssertEqual(record?.sentryMetricKeys, [])
            XCTAssertNil(record?.posthogEventName)
            XCTAssertEqual(record?.identityPolicy, ProductAnalyticsRegistryIdentityPolicy.none)
            XCTAssertEqual(record?.propertyAllowlist, [])
        }

        for interactionID in [
            "CBW-003-show_request_resolution_failure",
            "CTM-001-close_other_content_tabs",
            "CTM-001-move_content_tab_to_new_file_manager_window",
            "EOP-004-batch_rename_entries",
            "EOP-006-copy_relative_paths_of_entries",
        ] {
            let record = registry.records.first { $0.interactionID == interactionID }
            XCTAssertEqual(record?.implementationStatus, .tbd)
            XCTAssertNil(record?.eventVersion)
            XCTAssertNil(record?.eventClass)
            XCTAssertEqual(record?.sentryMetricKeys, [])
            XCTAssertNil(record?.posthogEventName)
            XCTAssertEqual(record?.identityPolicy, ProductAnalyticsRegistryIdentityPolicy.none)
            XCTAssertEqual(record?.propertyAllowlist, [])
            XCTAssertEqual(record?.propertyValueAllowlist, [:])
        }
    }

    func testRegistrySchemaRequiresVersionClassAndFiniteAllowlist() throws {
        let appBundle = VoyagerTestSupport.hostApplicationBundle()
        let registryURL = try XCTUnwrap(appBundle.url(forResource: "ProductAnalyticsRegistry", withExtension: "json"))
        let original = try XCTUnwrap(JSONSerialization
            .jsonObject(with: Data(contentsOf: registryURL)) as? [String: Any])

        let mutations: [(String, (inout [String: Any]) -> Void)] = [
            ("missing version", { root in
                guard var records = root["records"] as? [[String: Any]] else { return }
                records[0].removeValue(forKey: "event_version")
                root["records"] = records
            }),
            ("unknown version", { root in
                guard var records = root["records"] as? [[String: Any]] else { return }
                records[0]["event_version"] = "3"
                root["records"] = records
            }),
            ("unknown class", { root in
                guard var records = root["records"] as? [[String: Any]] else { return }
                records[0]["event_class"] = "exposure"
                root["records"] = records
            }),
            ("missing value allowlist", { root in
                guard var records = root["records"] as? [[String: Any]] else { return }
                records[0].removeValue(forKey: "property_value_allowlist")
                root["records"] = records
            }),
            ("duplicate value allowlist", { root in
                guard var records = root["records"] as? [[String: Any]] else { return }
                records[0]["property_value_allowlist"] = ["result_status": ["success", "success"]]
                root["records"] = records
            }),
        ]

        for (name, mutate) in mutations {
            var mutated = original
            mutate(&mutated)
            let data = try JSONSerialization.data(withJSONObject: mutated)
            XCTAssertEqual(ProductAnalyticsRegistry.load(data: data), .invalid(.malformed), name)
        }
    }

    func testNonImplementedRowsRejectProductMappings() throws {
        let appBundle = VoyagerTestSupport.hostApplicationBundle()
        let registryURL = try XCTUnwrap(appBundle.url(forResource: "ProductAnalyticsRegistry", withExtension: "json"))
        let original = try XCTUnwrap(JSONSerialization
            .jsonObject(with: Data(contentsOf: registryURL)) as? [String: Any])
        let mutations: [(String, (inout [String: Any]) -> Void)] = [
            ("sentry metric", { root in
                guard var records = root["records"] as? [[String: Any]] else { return }
                records[0]["sentry_metric_keys"] = ["unexpected"]
                root["records"] = records
            }),
            ("PostHog event", { root in
                guard var records = root["records"] as? [[String: Any]] else { return }
                records[0]["posthog_event_name"] = "unexpected"
                root["records"] = records
            }),
            ("legacy alias", { root in
                guard var records = root["records"] as? [[String: Any]] else { return }
                records[0]["legacy_aliases"] = ["unexpected"]
                root["records"] = records
            }),
            ("identity", { root in
                guard var records = root["records"] as? [[String: Any]] else { return }
                records[0]["identity_policy"] = "anonymous"
                root["records"] = records
            }),
            ("property allowlist", { root in
                guard var records = root["records"] as? [[String: Any]] else { return }
                records[0]["property_allowlist"] = ["source_surface"]
                root["records"] = records
            }),
            ("finite value allowlist", { root in
                guard var records = root["records"] as? [[String: Any]] else { return }
                records[0]["property_value_allowlist"] = ["source_surface": ["toolbar"]]
                root["records"] = records
            }),
        ]

        for (name, mutate) in mutations {
            var mutated = original
            mutate(&mutated)
            let data = try JSONSerialization.data(withJSONObject: mutated)
            XCTAssertEqual(ProductAnalyticsRegistry.load(data: data), .invalid(.malformed), name)
        }
    }

    func testImplementedStringPropertyRequiresFiniteAllowlist() throws {
        let appBundle = VoyagerTestSupport.hostApplicationBundle()
        let registryURL = try XCTUnwrap(appBundle.url(forResource: "ProductAnalyticsRegistry", withExtension: "json"))
        var root = try XCTUnwrap(JSONSerialization
            .jsonObject(with: Data(contentsOf: registryURL)) as? [String: Any])
        var records = try XCTUnwrap(root["records"] as? [[String: Any]])
        let implementedIndex = try XCTUnwrap(records
            .firstIndex { $0["implementation_status"] as? String == "implemented" })
        records[implementedIndex]["property_allowlist"] = ["source_surface"]
        records[implementedIndex]["property_value_allowlist"] = [:]
        root["records"] = records

        let data = try JSONSerialization.data(withJSONObject: root)
        XCTAssertEqual(ProductAnalyticsRegistry.load(data: data), .invalid(.malformed))

        let directRegistry = ProductAnalyticsRegistry(records: [
            .init(
                interactionID: "RCL-001-missing_finite_values",
                featureID: "RCL-001",
                implementationStatus: .implemented,
                sentryMetricKeys: ["missing_finite_metric"],
                posthogEventName: "missing_finite_event",
                legacyAliases: [],
                identityPolicy: .anonymous,
                propertyAllowlist: ["source_surface"],
                relatedIssues: [],
            ),
        ])
        XCTAssertEqual(
            directRegistry.resolve(
                metricKey: "missing_finite_metric",
                identity: .anonymous,
                properties: ["source_surface": .string("arbitrary")],
            ),
            .drop(.privacyRejected),
        )
    }

    func testFiniteValuesAndRawPrivacyInputsFailClosed() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "records": [[
                "interaction_id": "RCL-001-finite_values",
                "feature_id": "RCL-001",
                "implementation_status": "implemented",
                "event_version": "1",
                "event_class": "action",
                "sentry_metric_keys": ["finite_metric"],
                "posthog_event_name": "finite_event",
                "legacy_aliases": [],
                "identity_policy": "anonymous",
                "property_allowlist": ["result_status", "source_surface"],
                "property_value_allowlist": [
                    "result_status": ["success", "failure"],
                    "source_surface": ["toolbar"],
                ],
                "related_issues": [],
            ]],
        ])
        guard case let .loaded(registry) = ProductAnalyticsRegistry.load(data: data) else {
            return XCTFail("expected finite-value fixture to load")
        }

        for value in ["unknown", "raw/path", "prompt", "token", "credential"] {
            XCTAssertEqual(
                registry.resolve(
                    metricKey: "finite_metric",
                    identity: .anonymous,
                    properties: ["result_status": .string(value)],
                ),
                .drop(.privacyRejected),
                value,
            )
        }
        guard case .capture = registry.resolve(
            metricKey: "finite_metric",
            identity: .anonymous,
            properties: ["source_surface": .string("toolbar")],
        ) else {
            return XCTFail("allowlisted finite value should capture")
        }
    }

    func testBundledGenericMetricsCaptureWithoutCanonicalAttribution() {
        let registry = ProductAnalyticsRegistry.load(bundle: VoyagerTestSupport.hostApplicationBundle())

        for (metricKey, eventName) in [
            ("dau.navigation", "voyager_file_manager_navigation"),
            ("dau.entry_action", "voyager_file_manager_entry_action"),
        ] {
            guard case let .capture(request) = registry.resolve(
                metricKey: metricKey,
                identity: .device("test-device-id"),
                properties: ["source_surface": .string("file_manager")],
            ) else {
                return XCTFail("expected metadata-only capture for \(metricKey)")
            }
            XCTAssertEqual(request.event.eventName.rawValue, eventName)
            XCTAssertNil(request.event.properties["interaction_id"])
            XCTAssertNil(request.event.properties["feature_id"])
        }
    }

    func testMetadataOnlyMetricRejectsExplicitVersionMismatch() {
        let registry = ProductAnalyticsRegistry(
            records: [],
            metadataOnlyMetrics: [
                .init(
                    metricKey: "metadata_metric",
                    posthogEventName: "metadata_event",
                    identityPolicy: .device,
                    propertyAllowlist: [],
                    eventVersion: "1",
                ),
            ],
        )

        XCTAssertEqual(
            registry.resolve(
                metricKey: "metadata_metric",
                identity: .device("test-device-id"),
                eventVersion: .init(rawValue: "2"),
            ),
            .drop(.privacyRejected),
        )
    }

    func testBundledGenericMetricsRejectCanonicalAttributionProperties() {
        let registry = ProductAnalyticsRegistry.load(bundle: VoyagerTestSupport.hostApplicationBundle())

        XCTAssertEqual(
            registry.resolve(
                metricKey: "dau.navigation",
                identity: .device("test-device-id"),
                properties: ["interaction_id": .string("FMW-001-close_file_manager_window")],
            ),
            .drop(.privacyRejected),
        )
    }

    func testBundledCollectionOpenMetricCapturesOnlyBoundedOutcomeProperties() {
        let registry = ProductAnalyticsRegistry.load(bundle: VoyagerTestSupport.hostApplicationBundle())
        let deviceID = "test-device-id"
        let outcomes: [[String: ProductAnalyticsPropertyValue]] = [
            ["result_status": .string("valid_empty")],
            ["result_status": .string("load_failure"), "failure_reason": .string("invalid_definition")],
            ["result_status": .string("load_failure"), "failure_reason": .string("malformed")],
            ["result_status": .string("load_failure"), "failure_reason": .string("access")],
            ["result_status": .string("load_failure"), "failure_reason": .string("unknown")],
        ]

        for properties in outcomes {
            guard case let .capture(request) = registry.resolve(
                metricKey: "collection.open",
                identity: .device(deviceID),
                properties: properties,
            ) else {
                return XCTFail("expected collection.open capture for \(properties)")
            }
            XCTAssertEqual(request.event.eventName.rawValue, "voyager_collection_open")
            XCTAssertEqual(request.event.distinctID, deviceID)
            XCTAssertEqual(request.event.properties, properties)
            XCTAssertNil(request.event.identifiers)
        }

        let privacyRejectedProperties: [[String: ProductAnalyticsPropertyValue]] = [
            ["raw_path": .string("/private/secret.voycoll")],
            ["url": .string("file:///private/secret.voycoll")],
            ["query": .string("private invoice")],
            ["filter": .string("tag_names contains secret")],
            ["error_text": .string("failed to read /private/secret.voycoll")],
            ["result_status": .string("valid_empty"), "additional": .string("safe_token")],
            ["result_status": .string("token_value")],
            ["failure_reason": .string("/private/secret.voycoll")],
        ]
        for properties in privacyRejectedProperties {
            XCTAssertEqual(
                registry.resolve(
                    metricKey: "collection.open",
                    identity: .device(deviceID),
                    properties: properties,
                ),
                .drop(.privacyRejected),
            )
        }
    }

    func testBundledQueryResultCapturesRepresentativeSnakeCaseOutcome() {
        let registry = ProductAnalyticsRegistry.load(bundle: VoyagerTestSupport.hostApplicationBundle())
        let record = registry.records.first { $0.posthogEventName == "voyager_collection_filter_query_result" }
        XCTAssertEqual(record?.eventVersion, "2")
        XCTAssertEqual(record?.eventClass, "action")
        XCTAssertEqual(record?.propertyAllowlist, ["result_status", "source_surface", "duration_ms"])
        XCTAssertEqual(record?.propertyValueAllowlist["result_status"], ["success", "empty", "failure", "cancelled"])
        XCTAssertEqual(record?.propertyValueAllowlist["source_surface"], ["composer"])
        guard let metricKey = record?.sentryMetricKeys.first else {
            return XCTFail("expected bundled query-result metric key")
        }

        let result = registry.resolve(
            metricKey: metricKey,
            identity: .device("test-device-id"),
            properties: [
                "result_status": .string("success"),
                "source_surface": .string("composer"),
            ],
        )

        guard case let .capture(request) = result else {
            return XCTFail("expected bundled query-result metric capture")
        }
        XCTAssertEqual(request.event.eventName.rawValue, "voyager_collection_filter_query_result")
        XCTAssertEqual(request.event.properties["result_status"], .string("success"))
        XCTAssertEqual(request.event.properties["source_surface"], .string("composer"))
    }

    func testBundledCutEntriesCapturesCanonicalActionEnvelope() {
        let registry = ProductAnalyticsRegistry.load(bundle: VoyagerTestSupport.hostApplicationBundle())

        let result = registry.resolve(
            metricKey: "voy_691_eop_002_cut_entries",
            identity: .device("test-device-id"),
            properties: [
                "result_status": .string("success"),
                "action_type": .string("cut"),
                "source_surface": .string("file_manager_content"),
            ],
            eventVersion: .init(rawValue: "1"),
        )

        guard case let .capture(request) = result else {
            return XCTFail("expected bundled cut-entries capture, got: \(result)")
        }
        XCTAssertEqual(request.event.eventName.rawValue, "voyager_entry_action_result")
        XCTAssertEqual(request.event.eventVersion.rawValue, "1")
        XCTAssertEqual(request.event.properties["action_type"], .string("cut"))
    }

    func testBundledQueryResultCapturesEveryCanonicalConversionOutcome() {
        let registry = ProductAnalyticsRegistry.load(bundle: VoyagerTestSupport.hostApplicationBundle())
        guard let metricKey = registry.records.first(where: {
            $0.posthogEventName == "voyager_collection_filter_query_result"
        })?.sentryMetricKeys.first else {
            return XCTFail("expected bundled query-result metric key")
        }
        let outcomes = [
            "success",
            "empty",
            "failure",
            "cancelled",
        ]

        for outcome in outcomes {
            guard case let .capture(request) = registry.resolve(
                metricKey: metricKey,
                identity: .device("test-device-id"),
                properties: [
                    "result_status": .string(outcome),
                    "source_surface": .string("composer"),
                ],
            ) else {
                return XCTFail("expected bundled capture for \(outcome)")
            }
            XCTAssertEqual(request.event.properties["result_status"], .string(outcome))
            XCTAssertEqual(request.event.properties["source_surface"], .string("composer"))
        }
    }

    func testResultStatusCredentialFragmentsRemainPrivacyRejected() {
        let registry = ProductAnalyticsRegistry(records: [
            .init(
                interactionID: "RCL-001-open_collection_scope_menu",
                featureID: "RCL-001",
                implementationStatus: .implemented,
                sentryMetricKeys: ["result_metric"],
                posthogEventName: "result_event",
                legacyAliases: [],
                identityPolicy: .anonymous,
                propertyAllowlist: ["result_status", "failure_reason"],
                relatedIssues: [],
                propertyValueAllowlist: [
                    "result_status": ["success"],
                    "failure_reason": ["network_unavailable"],
                ],
            ),
        ])

        for value in ["credential_value", "my_credential_is_invalid"] {
            XCTAssertEqual(
                registry.resolve(
                    metricKey: "result_metric",
                    identity: .anonymous,
                    properties: ["result_status": .string(value)],
                ),
                .drop(.privacyRejected),
            )
        }
        XCTAssertEqual(
            registry.resolve(
                metricKey: "result_metric",
                identity: .anonymous,
                properties: ["failure_reason": .string("invalid_credential")],
            ),
            .drop(.privacyRejected),
        )
    }

    func testComposerOpenIsUnregisteredDrop() {
        let registry = ProductAnalyticsRegistry.load(bundle: VoyagerTestSupport.hostApplicationBundle())

        let result = registry.resolve(
            metricKey: "voyager_composer_open",
            identity: .device("test-device-id"),
        )

        XCTAssertEqual(result, .drop(.unregistered))
    }

    func testRetiredCollectionSaveResultsRemainUnregisteredDrops() {
        let registry = ProductAnalyticsRegistry.load(bundle: VoyagerTestSupport.hostApplicationBundle())

        for metricKey in ["voyager_collection_filter_save_result", "voyager_composer_open"] {
            XCTAssertEqual(
                registry.resolve(metricKey: metricKey, identity: .device("test-device-id")),
                .drop(.unregistered),
            )
        }
    }

    func testCanonicalIdentifiersAreTypedAndPreserveProviderNames() {
        let registry = ProductAnalyticsRegistry(records: [
            .init(
                interactionID: "RCL-001-open_collection_scope_menu",
                featureID: "RCL-001",
                implementationStatus: .implemented,
                sentryMetricKeys: ["typed_metric"],
                posthogEventName: "typed_event",
                legacyAliases: [],
                identityPolicy: .device,
                propertyAllowlist: [],
                relatedIssues: ["VOY-527"],
            ),
        ])

        guard case let .capture(request) = registry.resolve(
            metricKey: "typed_metric",
            identity: .device("installation-id"),
        ) else {
            return XCTFail("expected typed identifier capture")
        }
        XCTAssertEqual(request.event.sourceProject, "app")
        XCTAssertEqual(request.event.identifiers?.interactionID, "RCL-001-open_collection_scope_menu")
        XCTAssertEqual(request.event.identifiers?.featureID, "RCL-001")
    }

    func testCanonicalMetricCapturesAllowlistedEnvelope() {
        let registry = ProductAnalyticsRegistry(records: [
            .init(
                interactionID: "RCL-001-open_collection_scope_menu",
                featureID: "RCL-001",
                implementationStatus: .implemented,
                sentryMetricKeys: ["legacy_scope_menu"],
                posthogEventName: "collection_scope_menu_opened",
                legacyAliases: [],
                identityPolicy: .device,
                propertyAllowlist: ["interaction_id", "target_count"],
                relatedIssues: [],
            ),
        ])

        let result = registry.resolve(
            metricKey: "legacy_scope_menu",
            identity: .device("device-123"),
            context: .init(
                occurredAtUTC: Date(timeIntervalSince1970: 1_700_000_000),
                environment: "test",
                appVersion: "0.8.2",
                platform: "macOS",
                source: "test",
            ),
            properties: [
                "interaction_id": .string("RCL-001-open_collection_scope_menu"),
                "target_count": .integer(2),
            ],
        )

        guard case let .capture(request) = result else {
            return XCTFail("expected canonical capture")
        }
        XCTAssertEqual(request.event.eventName.rawValue, "collection_scope_menu_opened")
        XCTAssertEqual(request.event.properties["target_count"], .integer(2))
        XCTAssertEqual(request.event.distinctID, "device-123")
    }

    func testAliasUnknownStatusesAndMissingIdentityDropDeterministically() {
        let registry = ProductAnalyticsRegistry(records: [
            .init(
                interactionID: "RCL-001-open_collection_scope_menu",
                featureID: "RCL-001",
                implementationStatus: .implemented,
                sentryMetricKeys: ["canonical_metric"],
                posthogEventName: "canonical_event",
                legacyAliases: ["legacy_metric"],
                identityPolicy: .device,
                propertyAllowlist: [],
                relatedIssues: [],
            ),
            .init(
                interactionID: "RCL-001-deferred",
                featureID: "RCL-001",
                implementationStatus: .deferred,
                sentryMetricKeys: ["deferred_metric"],
                posthogEventName: nil,
                legacyAliases: [],
                identityPolicy: .none,
                propertyAllowlist: [],
                relatedIssues: [],
            ),
            .init(
                interactionID: "RCL-001-tbd",
                featureID: "RCL-001",
                implementationStatus: .tbd,
                sentryMetricKeys: ["tbd_metric"],
                posthogEventName: nil,
                legacyAliases: [],
                identityPolicy: .none,
                propertyAllowlist: [],
                relatedIssues: [],
            ),
            .init(
                interactionID: "RCL-001-none",
                featureID: "RCL-001",
                implementationStatus: .implemented,
                sentryMetricKeys: ["none_metric"],
                posthogEventName: "should_not_capture",
                legacyAliases: [],
                identityPolicy: .none,
                propertyAllowlist: [],
                relatedIssues: [],
            ),
        ])

        XCTAssertEqual(registry.resolve(metricKey: "legacy_metric", identity: .device("id")), .drop(.legacyAlias))
        XCTAssertEqual(registry.resolve(metricKey: "unknown", identity: .device("id")), .drop(.unregistered))
        XCTAssertEqual(registry.resolve(metricKey: "deferred_metric", identity: .device("id")), .drop(.deferred))
        XCTAssertEqual(registry.resolve(metricKey: "tbd_metric", identity: .none), .drop(.tbd))
        XCTAssertEqual(registry.resolve(metricKey: "none_metric", identity: .none), .drop(.noEventRequired))
        XCTAssertEqual(
            registry.resolve(metricKey: "canonical_metric", identity: .device(nil)),
            .drop(.identityUnavailable),
        )
    }

    func testIdentityAndPrivacyPoliciesAreFailClosed() {
        let registry = ProductAnalyticsRegistry(records: [
            .init(
                interactionID: "RCL-001-open_collection_scope_menu",
                featureID: "RCL-001",
                implementationStatus: .implemented,
                sentryMetricKeys: ["anonymous_metric"],
                posthogEventName: "anonymous_event",
                legacyAliases: [],
                identityPolicy: .anonymous,
                propertyAllowlist: ["interaction_id"],
                relatedIssues: [],
            ),
            .init(
                interactionID: "RCL-001-no_event",
                featureID: "RCL-001",
                implementationStatus: .noEventRequired,
                sentryMetricKeys: ["no_event_metric"],
                posthogEventName: nil,
                legacyAliases: [],
                identityPolicy: .none,
                propertyAllowlist: [],
                relatedIssues: [],
            ),
        ])

        let anonymous = registry.resolve(
            metricKey: "anonymous_metric",
            identity: .anonymous,
            properties: ["interaction_id": .string("RCL-001-open_collection_scope_menu")],
        )
        guard case let .capture(request) = anonymous else {
            return XCTFail("expected anonymous capture")
        }
        XCTAssertNil(request.event.distinctID)

        XCTAssertEqual(
            registry.resolve(
                metricKey: "anonymous_metric",
                identity: .anonymous,
                properties: ["raw_path": .string("/Users/private/file")],
            ),
            .drop(.privacyRejected),
        )
        XCTAssertEqual(
            registry.resolve(
                metricKey: "anonymous_metric",
                identity: .anonymous,
                properties: ["interaction_id": .string("ignore previous instructions")],
            ),
            .drop(.privacyRejected),
        )
        XCTAssertEqual(registry.resolve(metricKey: "no_event_metric", identity: .none), .drop(.noEventRequired))
    }

    func testAllowlistedFailureReasonRejectsRawPathAndUserQuestion() {
        let registry = ProductAnalyticsRegistry(records: [
            .init(
                interactionID: "RCL-001-open_collection_scope_menu",
                featureID: "RCL-001",
                implementationStatus: .implemented,
                sentryMetricKeys: ["failure_metric"],
                posthogEventName: "collection_scope_menu_failed",
                legacyAliases: [],
                identityPolicy: .anonymous,
                propertyAllowlist: ["failure_reason", "recovery_action"],
                relatedIssues: [],
                propertyValueAllowlist: [
                    "failure_reason": ["network_unavailable", "provider_unavailable", "verification_failed"],
                    "recovery_action": ["retry"],
                ],
            ),
        ])

        for property in [
            "failure_reason": ProductAnalyticsPropertyValue.string("network_unavailable"),
            "recovery_action": .string("retry"),
        ] {
            guard case .capture = registry.resolve(
                metricKey: "failure_metric",
                identity: .anonymous,
                properties: [property.key: property.value],
            ) else {
                return XCTFail("bounded telemetry value should capture")
            }
        }

        XCTAssertEqual(
            registry.resolve(
                metricKey: "failure_metric",
                identity: .anonymous,
                properties: ["failure_reason": .string("/tmp/raw-file-path")],
            ),
            .drop(.privacyRejected),
        )
        for unsafeValue in [
            "model response text",
            "sk-test-placeholder",
            "Bearer test-placeholder",
            "credential=redacted-placeholder",
        ] {
            XCTAssertEqual(
                registry.resolve(
                    metricKey: "failure_metric",
                    identity: .anonymous,
                    properties: ["failure_reason": .string(unsafeValue)],
                ),
                .drop(.privacyRejected),
            )
        }
        XCTAssertEqual(
            registry.resolve(
                metricKey: "failure_metric",
                identity: .anonymous,
                properties: ["failure_reason": .string("arbitrary user-entered question")],
            ),
            .drop(.privacyRejected),
        )
    }

    func testMalformedDuplicateAndUnknownRegistryRecordsAreRejected() throws {
        let records = try JSONEncoder().encode([
            ProductAnalyticsRegistry.Record(
                interactionID: "RCL-001-a",
                featureID: "RCL-001",
                implementationStatus: .tbd,
                sentryMetricKeys: [],
                posthogEventName: nil,
                legacyAliases: [],
                identityPolicy: .none,
                propertyAllowlist: [],
                relatedIssues: [],
            ),
            ProductAnalyticsRegistry.Record(
                interactionID: "RCL-001-a",
                featureID: "RCL-001",
                implementationStatus: .tbd,
                sentryMetricKeys: [],
                posthogEventName: nil,
                legacyAliases: [],
                identityPolicy: .none,
                propertyAllowlist: [],
                relatedIssues: [],
            ),
        ])
        let duplicateObject = try JSONSerialization.jsonObject(with: records)
        let duplicate = try JSONSerialization.data(withJSONObject: ["records": duplicateObject])
        XCTAssertEqual(ProductAnalyticsRegistry.load(data: duplicate), .invalid(.duplicateInteractionID))

        let duplicateMetadata = try JSONSerialization.data(withJSONObject: [
            "metadata_only_metrics": [
                [
                    "metric_key": "duplicate_metric",
                    "posthog_event_name": "event_a",
                    "identity_policy": "anonymous",
                    "property_allowlist": [],
                    "event_version": "1",
                    "event_class": "exposure",
                    "kpi_eligible": false,
                ],
                [
                    "metric_key": "duplicate_metric",
                    "posthog_event_name": "event_b",
                    "identity_policy": "anonymous",
                    "property_allowlist": [],
                    "event_version": "1",
                    "event_class": "exposure",
                    "kpi_eligible": false,
                ],
            ],
            "records": [],
        ])
        XCTAssertEqual(ProductAnalyticsRegistry.load(data: duplicateMetadata), .invalid(.duplicateMetricKey))

        let duplicateCanonicalAndMetadata = try JSONSerialization.data(withJSONObject: [
            "metadata_only_metrics": [[
                "metric_key": "shared_metric",
                "posthog_event_name": "metadata_event",
                "identity_policy": "anonymous",
                "property_allowlist": [],
                "event_version": "1",
                "event_class": "exposure",
                "kpi_eligible": false,
            ]],
            "records": [[
                "interaction_id": "RCL-001-shared_metric",
                "feature_id": "RCL-001",
                "implementation_status": "implemented",
                "event_version": "1",
                "event_class": "action",
                "sentry_metric_keys": ["shared_metric"],
                "posthog_event_name": "canonical_event",
                "legacy_aliases": [],
                "identity_policy": "anonymous",
                "property_allowlist": [],
                "property_value_allowlist": [:],
                "related_issues": [],
            ]],
        ])
        XCTAssertEqual(
            ProductAnalyticsRegistry.load(data: duplicateCanonicalAndMetadata),
            .invalid(.duplicateMetricKey),
        )
        XCTAssertEqual(ProductAnalyticsRegistry.load(data: Data("not-json".utf8)), .invalid(.malformed))
    }

    func testUnknownRegistryKeysFailClosedAtEveryObjectBoundary() throws {
        let appBundle = VoyagerTestSupport.hostApplicationBundle()
        let registryURL = try XCTUnwrap(appBundle.url(forResource: "ProductAnalyticsRegistry", withExtension: "json"))
        let original = try XCTUnwrap(JSONSerialization
            .jsonObject(with: Data(contentsOf: registryURL)) as? [String: Any])

        let mutations: [(String, (inout [String: Any]) -> Void)] = [
            ("root", { $0["unexpected_root"] = true }),
            ("record", { root in
                guard var records = root["records"] as? [[String: Any]] else { return }
                records[0]["unexpected_record"] = true
                root["records"] = records
            }),
            ("metadata", { root in
                guard var metadata = root["metadata"] as? [String: Any] else { return }
                metadata["unexpected_metadata"] = true
                root["metadata"] = metadata
            }),
            ("metadata_only_metric", { root in
                guard var metrics = root["metadata_only_metrics"] as? [[String: Any]] else { return }
                metrics[0]["unexpected_metric"] = true
                root["metadata_only_metrics"] = metrics
            }),
            ("provenance", { root in
                guard var metadata = root["metadata"] as? [String: Any],
                      var provenance = metadata["provenance"] as? [String: Any]
                else { return }
                provenance["unexpected_provenance"] = true
                metadata["provenance"] = provenance
                root["metadata"] = metadata
            }),
            ("historical_snapshot", { root in
                guard var metadata = root["metadata"] as? [String: Any],
                      var snapshot = metadata["historical_snapshot"] as? [String: Any]
                else { return }
                snapshot["unexpected_snapshot"] = true
                metadata["historical_snapshot"] = snapshot
                root["metadata"] = metadata
            }),
            ("aggregate_expectations", { root in
                guard var metadata = root["metadata"] as? [String: Any],
                      var snapshot = metadata["historical_snapshot"] as? [String: Any],
                      var expectations = snapshot["aggregate_expectations"] as? [String: Any]
                else { return }
                expectations["unexpected_expectation"] = true
                snapshot["aggregate_expectations"] = expectations
                metadata["historical_snapshot"] = snapshot
                root["metadata"] = metadata
            }),
            ("current_snapshot", { root in
                guard var metadata = root["metadata"] as? [String: Any],
                      var snapshot = metadata["current_snapshot"] as? [String: Any]
                else { return }
                snapshot["unexpected_snapshot"] = true
                metadata["current_snapshot"] = snapshot
                root["metadata"] = metadata
            }),
            ("reconciliation", { root in
                guard var metadata = root["metadata"] as? [String: Any],
                      var reconciliation = metadata["reconciliation"] as? [String: Any]
                else { return }
                reconciliation["unexpected_reconciliation"] = true
                metadata["reconciliation"] = reconciliation
                root["metadata"] = metadata
            }),
        ]

        for (boundary, mutate) in mutations {
            var mutated = original
            mutate(&mutated)
            let data = try JSONSerialization.data(withJSONObject: mutated)
            XCTAssertEqual(
                ProductAnalyticsRegistry.load(data: data),
                .invalid(.unknownKey),
                "unknown key at \(boundary) must fail closed",
            )
        }
    }
}
