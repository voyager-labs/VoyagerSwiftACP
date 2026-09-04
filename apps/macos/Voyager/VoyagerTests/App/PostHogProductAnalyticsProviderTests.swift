import Compression
import Foundation
import os
@testable import Voyager
import XCTest

@MainActor
final class PostHogProductAnalyticsProviderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        RequestInterceptor.reset()
    }

    func testMissingEmptyAndWhitespaceConfigurationIsDisabled() {
        XCTAssertNil(ProductAnalyticsBootstrap.configuration(environment: [:]))
        XCTAssertNil(ProductAnalyticsBootstrap.configuration(environment: [
            "PUBLIC_POSTHOG_PROJECT_TOKEN": "",
            "PUBLIC_POSTHOG_HOST": "https://analytics.example.test",
        ]))
        XCTAssertNil(ProductAnalyticsBootstrap.configuration(environment: [
            "PUBLIC_POSTHOG_PROJECT_TOKEN": "   ",
            "PUBLIC_POSTHOG_HOST": " https://analytics.example.test ",
        ]))
        XCTAssertNil(ProductAnalyticsBootstrap.configuration(environment: [
            "PUBLIC_POSTHOG_PROJECT_TOKEN": "project-token-placeholder",
            "PUBLIC_POSTHOG_HOST": " \n\t",
        ]))
        for host in [
            "analytics.example.test",
            "/relative/path",
            "ftp://analytics.example.test",
            "https:///missing-host",
            "https://:443",
            "https://[bad-host",
        ] {
            XCTAssertNil(ProductAnalyticsBootstrap.configuration(environment: [
                "PUBLIC_POSTHOG_PROJECT_TOKEN": "project-token-placeholder",
                "PUBLIC_POSTHOG_HOST": host,
            ]))
        }
    }

    func testDisabledClientIgnoresMetricCapture() {
        let client = ProductAnalyticsBootstrap.makeClient(environment: [
            "PUBLIC_POSTHOG_PROJECT_TOKEN": "",
            "PUBLIC_POSTHOG_HOST": "https://analytics.example.test",
        ])
        client.captureMetric(metricRequest(value: 1))
    }

    func testConfiguredClientCachesIdentityWithoutGlobalState() async throws {
        let firstDefaults =
            try XCTUnwrap(UserDefaults(suiteName: "ProductAnalyticsProviderTests.first.\(UUID().uuidString)"))
        let secondDefaults =
            try XCTUnwrap(UserDefaults(suiteName: "ProductAnalyticsProviderTests.second.\(UUID().uuidString)"))
        let first = ProductAnalyticsBootstrap.makeClient(environment: [
            "PUBLIC_POSTHOG_PROJECT_TOKEN": "runtime-project-token-placeholder",
            "PUBLIC_POSTHOG_HOST": "https://analytics.example.test",
        ], userDefaults: firstDefaults)
        let second = ProductAnalyticsBootstrap.makeClient(environment: [
            "PUBLIC_POSTHOG_PROJECT_TOKEN": "runtime-project-token-placeholder",
            "PUBLIC_POSTHOG_HOST": "https://analytics.example.test",
        ], userDefaults: secondDefaults)

        await first.setDeviceIdentity("first-runtime-device-id")

        let firstIdentity = await first.deviceIdentity()
        let secondIdentity = await second.deviceIdentity()
        XCTAssertEqual(firstIdentity, "first-runtime-device-id")
        XCTAssertNotNil(secondIdentity)
        XCTAssertNotEqual(secondIdentity, firstIdentity)
    }

    func testDisabledClientDoesNotCacheIdentity() async {
        let client = ProductAnalyticsBootstrap.makeClient(environment: [
            "PUBLIC_POSTHOG_PROJECT_TOKEN": "",
            "PUBLIC_POSTHOG_HOST": "https://analytics.example.test",
        ])

        await client.setDeviceIdentity("disabled-runtime-device-id")

        let identity = await client.deviceIdentity()
        XCTAssertNil(identity)
    }

    func testConfigurationDisablesAllAutomaticCapture() throws {
        let configuration = try XCTUnwrap(PostHogProductAnalyticsProvider.configurationForTesting(
            projectToken: "capture-project-token-placeholder",
            host: " https://analytics.example.test ",
            flushAt: 1,
        ))

        XCTAssertEqual(configuration.projectToken, "capture-project-token-placeholder")
        XCTAssertEqual(configuration.host, "https://analytics.example.test")
        XCTAssertEqual(configuration.flushAt, 1)
        XCTAssertFalse(configuration.enableSwizzling)
        XCTAssertFalse(configuration.captureApplicationLifecycleEvents)
        XCTAssertFalse(configuration.captureScreenViews)
        XCTAssertFalse(configuration.captureElementInteractions)
        XCTAssertFalse(configuration.capturePushNotificationSubscriptions)
        XCTAssertFalse(configuration.capturePushNotificationOpened)
        XCTAssertFalse(configuration.sessionReplay)
        XCTAssertFalse(configuration.preloadFeatureFlags)
        XCTAssertFalse(configuration.surveys)
        XCTAssertFalse(configuration.rageClicks)
        XCTAssertFalse(configuration.errorTrackingAutoCapture)
        XCTAssertFalse(configuration.debug)
        XCTAssertFalse(configuration.sendFeatureFlagEvent)
        XCTAssertFalse(configuration.optOut)
    }

    func testConfiguredProviderCapturesOneExplicitEventThroughSDKQueue() async throws {
        let interceptor = RequestInterceptor()
        URLProtocol.registerClass(RequestInterceptor.self)
        defer { URLProtocol.unregisterClass(RequestInterceptor.self) }

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [RequestInterceptor.self]
        let provider = try XCTUnwrap(PostHogProductAnalyticsProvider(
            projectToken: "capture-\(UUID().uuidString)",
            host: "https://analytics.example.test",
            urlSessionConfiguration: sessionConfiguration,
            flushAt: 1,
        ))

        await provider.capture(.init(event: makeEvent(distinctID: "device-test-id")))
        await provider.flush()

        let captured = await interceptor.nextRequest()
        let request = captured.request
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try gunzipped(captured.body)
        if body.isEmpty {
            XCTFail("intercepted batch body was empty; headers=\(request.allHTTPHeaderFields?.keys.sorted() ?? [])")
        }
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let batch = try XCTUnwrap(json["batch"] as? [[String: Any]])
        XCTAssertEqual(batch.count, 1)
        XCTAssertEqual(batch[0]["event"] as? String, "collection_scope_menu_opened")
        XCTAssertEqual(batch[0]["distinct_id"] as? String, "device-test-id")
        XCTAssertEqual(batch[0]["timestamp"] as? String, "2023-11-14T22:13:20.000Z")
        let properties = try XCTUnwrap(batch[0]["properties"] as? [String: Any])
        XCTAssertEqual(properties["interaction_id"] as? String, "RCL-001-open_collection_scope_menu")
        XCTAssertEqual(properties["target_count"] as? Int, 2)
        XCTAssertTrue(Set([
            "app_version", "environment", "event_version", "platform", "source", "source_project", "interaction_id",
            "feature_id", "operation_id", "target_count",
        ]).isSubset(of: properties.keys))
        XCTAssertFalse(properties.keys.contains("raw_path"))
        XCTAssertFalse(properties.keys.contains("user_prompt"))
        XCTAssertFalse(properties.keys.contains("hardware_uuid"))
        XCTAssertFalse(properties.keys.contains("account_id"))
    }

    func testProviderSerializesExactEventVersionAndLowercaseOperationID() async throws {
        let interceptor = RequestInterceptor()
        URLProtocol.registerClass(RequestInterceptor.self)
        defer { URLProtocol.unregisterClass(RequestInterceptor.self) }

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [RequestInterceptor.self]
        let provider = try XCTUnwrap(PostHogProductAnalyticsProvider(
            projectToken: "version-operation-\(UUID().uuidString)",
            host: "https://analytics.example.test",
            urlSessionConfiguration: sessionConfiguration,
            flushAt: 1,
        ))

        await provider.capture(.init(event: makeEvent(
            eventName: "voyager_collection_filter_query_result",
            eventVersion: "2",
            operationID: "ABCDEFAB-CDEF-ABCD-EFAB-CDEFABCDEFAB",
        )))
        await provider.flush()

        let captured = await interceptor.nextRequest()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: gunzipped(captured.body),
        ) as? [String: Any])
        let event = try XCTUnwrap((json["batch"] as? [[String: Any]])?.first)
        XCTAssertEqual(event["event"] as? String, "voyager_collection_filter_query_result")
        let properties = try XCTUnwrap(event["properties"] as? [String: Any])
        XCTAssertEqual(properties["event_version"] as? String, "2")
        XCTAssertEqual(properties["operation_id"] as? String, "abcdefab-cdef-abcd-efab-cdefabcdefab")
    }

    func testReservedOperationIDCannotBeOverriddenByGenericProperties() async throws {
        let interceptor = RequestInterceptor()
        URLProtocol.registerClass(RequestInterceptor.self)
        defer { URLProtocol.unregisterClass(RequestInterceptor.self) }

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [RequestInterceptor.self]
        let provider = try XCTUnwrap(PostHogProductAnalyticsProvider(
            projectToken: "reserved-operation-\(UUID().uuidString)",
            host: "https://analytics.example.test",
            urlSessionConfiguration: sessionConfiguration,
            flushAt: 1,
        ))
        await provider.capture(.init(event: makeEvent(
            eventVersion: "1",
            operationID: "ABCDEFAB-CDEF-ABCD-EFAB-CDEFABCDEFAB",
            properties: ["operation_id": .string("attacker-value")],
        )))
        await provider.flush()

        let captured = await interceptor.nextRequest()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: gunzipped(captured.body),
        ) as? [String: Any])
        let event = try XCTUnwrap((json["batch"] as? [[String: Any]])?.first)
        let properties = try XCTUnwrap(event["properties"] as? [String: Any])
        XCTAssertEqual(properties["operation_id"] as? String, "abcdefab-cdef-abcd-efab-cdefabcdefab")
    }

    func testAnonymousCaptureUsesSDKGeneratedDistinctID() async throws {
        let interceptor = RequestInterceptor()
        URLProtocol.registerClass(RequestInterceptor.self)
        defer { URLProtocol.unregisterClass(RequestInterceptor.self) }

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [RequestInterceptor.self]
        let provider = try XCTUnwrap(PostHogProductAnalyticsProvider(
            projectToken: "anonymous-\(UUID().uuidString)",
            host: "https://analytics.example.test",
            urlSessionConfiguration: sessionConfiguration,
            flushAt: 1,
        ))

        await provider.capture(.init(event: makeEvent(distinctID: nil, eventName: "anonymous_capture_probe")))
        await provider.flush()

        let captured = await interceptor.nextRequest()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: gunzipped(captured.body),
        ) as? [String: Any])
        let batch = try XCTUnwrap(json["batch"] as? [[String: Any]])
        let distinctID = try XCTUnwrap(batch.first?["distinct_id"] as? String)
        XCTAssertFalse(distinctID.isEmpty)
    }

    func testTransportFailureDoesNotThrowOrBlockCaller() async throws {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [RequestInterceptor.self]
        RequestInterceptor.setMode(.failure, gate: nil)
        defer { RequestInterceptor.setMode(.normal, gate: nil) }
        let provider = try XCTUnwrap(PostHogProductAnalyticsProvider(
            projectToken: "transport-project-token-placeholder",
            host: "https://analytics.example.test",
            urlSessionConfiguration: sessionConfiguration,
            flushAt: 1,
        ))

        await provider.capture(.init(event: .init(
            eventName: .init(rawValue: "transport_failure_probe"),
            occurredAtUTC: Date(timeIntervalSince1970: 1_700_000_000),
            environment: "test",
            distinctID: nil,
            appVersion: "0.8.2",
            platform: "macOS",
            source: "test",
            properties: [:],
        )))
        await provider.flush()
        _ = await RequestInterceptor().nextRequest()
    }

    func testMetricCaptureUsesProducerTimestampAndRegistryIdentity() async throws {
        let interceptor = RequestInterceptor()
        let suiteName = "ProductAnalyticsMetricTimestampTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        URLProtocol.registerClass(RequestInterceptor.self)
        defer { URLProtocol.unregisterClass(RequestInterceptor.self) }

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [RequestInterceptor.self]
        let producerDate = Date(timeIntervalSince1970: 1_700_000_123)
        let client = ProductAnalyticsBootstrap.makeClient(
            environment: [
                "PUBLIC_POSTHOG_PROJECT_TOKEN": "metric-timestamp-\(UUID().uuidString)",
                "PUBLIC_POSTHOG_HOST": "https://analytics.example.test",
            ],
            urlSessionConfiguration: sessionConfiguration,
            flushAt: 1,
            registry: makeMetricRegistry(),
            userDefaults: defaults,
            makeInstallationID: {
                UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE") ?? UUID()
            },
        )

        client.captureMetric(.init(
            metricKey: "metric_probe",
            properties: ["target_count": .integer(1)],
            context: .init(
                occurredAtUTC: producerDate,
                environment: "test",
                appVersion: "0.8.2",
                platform: "macOS",
                source: "app",
            ),
        ))

        let captured = await interceptor.nextRequest()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: gunzipped(captured.body),
        ) as? [String: Any])
        let event = try XCTUnwrap((json["batch"] as? [[String: Any]])?.first)
        XCTAssertEqual(event["distinct_id"] as? String, "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        XCTAssertEqual(event["timestamp"] as? String, "2023-11-14T22:15:23.000Z")
    }

    func testMetricCapturePropagatesProducerVersionAndOperationID() async throws {
        let interceptor = RequestInterceptor()
        let suiteName = "ProductAnalyticsMetricEnvelopeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        URLProtocol.registerClass(RequestInterceptor.self)
        defer { URLProtocol.unregisterClass(RequestInterceptor.self) }

        let installationID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [RequestInterceptor.self]
        let client = ProductAnalyticsBootstrap.makeClient(
            environment: [
                "PUBLIC_POSTHOG_PROJECT_TOKEN": "metric-envelope-\(UUID().uuidString)",
                "PUBLIC_POSTHOG_HOST": "https://analytics.example.test",
            ],
            urlSessionConfiguration: sessionConfiguration,
            flushAt: 1,
            registry: ProductAnalyticsRegistry(records: [
                .init(
                    interactionID: "RCL-004-generate_filter_changes_from_query",
                    featureID: "RCL-004",
                    implementationStatus: .implemented,
                    sentryMetricKeys: ["metric_probe"],
                    posthogEventName: "voyager_collection_filter_query_result",
                    legacyAliases: [],
                    identityPolicy: .device,
                    propertyAllowlist: [],
                    relatedIssues: [],
                    eventVersion: "2",
                    eventClass: "action",
                    propertyValueAllowlist: [:],
                ),
            ]),
            userDefaults: defaults,
            makeInstallationID: { installationID },
        )
        let operationID = try XCTUnwrap(UUID(uuidString: "ABCDEFAB-CDEF-ABCD-EFAB-CDEFABCDEFAB"))

        client.captureMetric(.init(
            metricKey: "metric_probe",
            properties: [:],
            context: .init(
                occurredAtUTC: Date(timeIntervalSince1970: 1_700_000_123),
                environment: "test",
                appVersion: "0.8.2",
                platform: "macOS",
                source: "app",
            ),
            eventVersion: .init(rawValue: "2"),
            operationID: operationID,
        ))

        let captured = await interceptor.nextRequest()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: gunzipped(captured.body),
        ) as? [String: Any])
        let event = try XCTUnwrap((json["batch"] as? [[String: Any]])?.first)
        let properties = try XCTUnwrap(event["properties"] as? [String: Any])
        XCTAssertEqual(properties["event_version"] as? String, "2")
        XCTAssertEqual(properties["operation_id"] as? String, operationID.uuidString.lowercased())
    }

    func testAdjacentMetricCapturesPreserveProducerOrder() async throws {
        let interceptor = RequestInterceptor()
        let gate = BlockingGate()
        URLProtocol.registerClass(RequestInterceptor.self)
        defer {
            gate.release()
            URLProtocol.unregisterClass(RequestInterceptor.self)
            RequestInterceptor.setMode(.normal, gate: nil)
        }

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [RequestInterceptor.self]
        let client = ProductAnalyticsBootstrap.makeClient(
            environment: [
                "PUBLIC_POSTHOG_PROJECT_TOKEN": "metric-order-\(UUID().uuidString)",
                "PUBLIC_POSTHOG_HOST": "https://analytics.example.test",
            ],
            urlSessionConfiguration: sessionConfiguration,
            flushAt: 1,
            registry: makeMetricRegistry(),
        )

        RequestInterceptor.setMode(.blocking, gate: gate)
        for value in 1 ... 3 {
            client.captureMetric(metricRequest(value: value))
            if value == 1 {
                XCTAssertTrue(gate.waitForStart())
            }
        }
        gate.release()

        var values: [Int] = []
        while values.count < 3 {
            let captured = await interceptor.nextRequest()
            let json = try XCTUnwrap(JSONSerialization.jsonObject(
                with: gunzipped(captured.body),
            ) as? [String: Any])
            let batch = try XCTUnwrap(json["batch"] as? [[String: Any]])
            for event in batch {
                let properties = try XCTUnwrap(event["properties"] as? [String: Any])
                try values.append(XCTUnwrap(properties["target_count"] as? Int))
            }
        }
        XCTAssertEqual(values, [1, 2, 3])
    }

    func testAwaitedIdentityUpdatePreservesMetricIdentityOrder() async throws {
        let interceptor = RequestInterceptor()
        let suiteName = "ProductAnalyticsMetricIdentityOrderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        URLProtocol.registerClass(RequestInterceptor.self)
        defer { URLProtocol.unregisterClass(RequestInterceptor.self) }

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [RequestInterceptor.self]
        let client = ProductAnalyticsBootstrap.makeClient(
            environment: [
                "PUBLIC_POSTHOG_PROJECT_TOKEN": "metric-identity-order-\(UUID().uuidString)",
                "PUBLIC_POSTHOG_HOST": "https://analytics.example.test",
            ],
            urlSessionConfiguration: sessionConfiguration,
            flushAt: 1,
            registry: makeMetricRegistry(),
            userDefaults: defaults,
            makeInstallationID: {
                UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE") ?? UUID()
            },
        )

        client.captureMetric(metricRequest(value: 1))
        await client.setDeviceIdentity("updated-device-id")
        client.captureMetric(metricRequest(value: 2))

        var identities: [String?] = []
        while identities.count < 2 {
            let captured = await interceptor.nextRequest()
            let json = try XCTUnwrap(JSONSerialization.jsonObject(
                with: gunzipped(captured.body),
            ) as? [String: Any])
            let batch = try XCTUnwrap(json["batch"] as? [[String: Any]])
            identities.append(contentsOf: batch.map { $0["distinct_id"] as? String })
        }
        XCTAssertEqual(identities, [
            "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            "updated-device-id",
        ])
    }

    func testMetricCaptureReturnsBeforeBlockingTransport() {
        let gate = BlockingGate()
        URLProtocol.registerClass(RequestInterceptor.self)
        defer {
            gate.release()
            URLProtocol.unregisterClass(RequestInterceptor.self)
            RequestInterceptor.setMode(.normal, gate: nil)
        }

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [RequestInterceptor.self]
        let client = ProductAnalyticsBootstrap.makeClient(
            environment: [
                "PUBLIC_POSTHOG_PROJECT_TOKEN": "metric-nonblocking-\(UUID().uuidString)",
                "PUBLIC_POSTHOG_HOST": "https://analytics.example.test",
            ],
            urlSessionConfiguration: sessionConfiguration,
            flushAt: 1,
            registry: makeMetricRegistry(),
        )
        RequestInterceptor.setMode(.blocking, gate: gate)

        client.captureMetric(.init(
            metricKey: "metric_probe",
            properties: ["target_count": .integer(1)],
            context: .init(
                occurredAtUTC: Date(timeIntervalSince1970: 1_700_000_000),
                environment: "test",
                appVersion: "0.8.2",
                platform: "macOS",
                source: "app",
            ),
        ))
        gate.markReturned()
        XCTAssertTrue(gate.waitForStart())
        XCTAssertTrue(gate.waitForReturn())
    }

    func testInstallationIdentityIsPersistedAndReused() throws {
        let suiteName = "ProductAnalyticsBootstrapTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let expected = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))

        let first = ProductAnalyticsBootstrap.persistedInstallationID(
            in: defaults,
            makeInstallationID: { expected },
        )
        let second = ProductAnalyticsBootstrap.persistedInstallationID(
            in: defaults,
            makeInstallationID: { XCTFail("must reuse persisted installation ID")
                return UUID()
            },
        )

        XCTAssertEqual(first, expected.uuidString)
        XCTAssertEqual(second, first)
    }

    func testConfiguredBootstrapStartsWithPersistedInstallationIdentity() async throws {
        let suiteName = "ProductAnalyticsBootstrapTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let expected = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))

        let client = ProductAnalyticsBootstrap.makeClient(
            environment: [
                "PUBLIC_POSTHOG_PROJECT_TOKEN": "identity-startup-token",
                "PUBLIC_POSTHOG_HOST": "https://analytics.example.test",
            ],
            userDefaults: defaults,
            makeInstallationID: { expected },
        )

        let identity = await client.deviceIdentity()
        XCTAssertEqual(identity, expected.uuidString)
    }

    private func makeEvent(
        distinctID: String? = "device-test-id",
        eventName: String = "collection_scope_menu_opened",
        eventVersion: String = "1",
        operationID: String = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
        properties: [String: ProductAnalyticsPropertyValue] = [
            "interaction_id": .string("RCL-001-open_collection_scope_menu"),
            "target_count": .integer(2),
        ],
    ) -> ProductAnalyticsEvent {
        ProductAnalyticsEvent(
            eventName: .init(rawValue: eventName),
            occurredAtUTC: Date(timeIntervalSince1970: 1_700_000_000),
            environment: "test",
            distinctID: distinctID,
            appVersion: "0.8.2",
            platform: "macOS",
            source: "test",
            properties: properties,
            eventVersion: .init(rawValue: eventVersion),
            operationID: UUID(uuidString: operationID) ?? UUID(),
            sourceProject: "app",
            identifiers: .init(
                interactionID: "RCL-001-open_collection_scope_menu",
                featureID: "RCL-001",
            ),
        )
    }

    private func makeMetricRegistry() -> ProductAnalyticsRegistry {
        ProductAnalyticsRegistry(records: [
            .init(
                interactionID: "metric-probe",
                featureID: "metric-probe",
                implementationStatus: .implemented,
                sentryMetricKeys: ["metric_probe"],
                posthogEventName: "metric_probe_event",
                legacyAliases: [],
                identityPolicy: .device,
                propertyAllowlist: ["target_count"],
                relatedIssues: [],
            ),
        ])
    }

    private func metricRequest(value: Int) -> ProductAnalyticsMetricRequest {
        .init(
            metricKey: "metric_probe",
            properties: ["target_count": .integer(value)],
            context: .init(
                occurredAtUTC: Date(timeIntervalSince1970: Double(value)),
                environment: "test",
                appVersion: "0.8.2",
                platform: "macOS",
                source: "app",
            ),
        )
    }
}

private class RequestInterceptor: URLProtocol {
    enum Mode: Equatable {
        case normal
        case failure
        case blocking
    }

    struct CapturedRequest {
        let request: URLRequest
        let body: Data
    }

    private struct Storage {
        var requests: [CapturedRequest] = []
        var waiters: [CheckedContinuation<CapturedRequest, Never>] = []
        var mode: Mode = .normal
        var gate: BlockingGate?
    }

    private static let storage = OSAllocatedUnfairLock(initialState: Storage())

    static func setMode(_ mode: Mode, gate: BlockingGate?) {
        storage.withLock { state in
            state.mode = mode
            state.gate = gate
        }
    }

    static func reset() {
        storage.withLock { state in
            precondition(state.waiters.isEmpty)
            state.requests.removeAll()
            state.mode = .normal
            state.gate = nil
        }
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard request.url?.path.contains("/batch") == true else {
            finish(statusCode: 200)
            return
        }
        let body = requestBody()
        let capturedRequest = CapturedRequest(request: request, body: body)
        let (mode, gate, waiter) = Self.storage.withLock { state in
            let waiter = state.waiters.first
            if waiter != nil {
                state.waiters.removeFirst()
            } else {
                state.requests.append(capturedRequest)
            }
            return (state.mode, state.gate, waiter)
        }
        waiter?.resume(returning: capturedRequest)
        if mode == .blocking {
            gate?.markStarted()
            gate?.waitForRelease()
        }
        finish(statusCode: mode == .failure ? 400 : 200)
    }

    override func stopLoading() {}

    func nextRequest() async -> CapturedRequest {
        await withCheckedContinuation { continuation in
            let request: CapturedRequest? = Self.storage.withLock { state in
                if let request = state.requests.first {
                    state.requests.removeFirst()
                    return request
                }
                state.waiters.append(continuation)
                return nil
            }
            if let request {
                continuation.resume(returning: request)
            }
        }
    }

    private func requestBody() -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            body.append(buffer, count: count)
        }
        return body
    }

    private func finish(statusCode: Int) {
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: statusCode,
                  httpVersion: nil,
                  headerFields: nil,
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

private struct BlockingGate {
    private let started = DispatchSemaphore(value: 0)
    private let returned = DispatchSemaphore(value: 0)
    private let releaseSignal = DispatchSemaphore(value: 0)

    func markStarted() {
        started.signal()
    }

    func markReturned() {
        returned.signal()
    }

    func waitForStart() -> Bool {
        started.wait(timeout: .now() + 2) == .success
    }

    func waitForReturn() -> Bool {
        returned.wait(timeout: .now() + 2) == .success
    }

    func waitForRelease() {
        _ = releaseSignal.wait(timeout: .now() + 5)
    }

    func release() {
        releaseSignal.signal()
    }
}

private func gunzipped(_ data: Data) throws -> Data {
    guard data.starts(with: [0x1F, 0x8B]), data.count > 18 else { return data }
    let compressed = data.dropFirst(10).dropLast(8)
    var decompressed = [UInt8](repeating: 0, count: max(compressed.count * 32, 4096))
    let count = decompressed.withUnsafeMutableBytes { output in
        compressed.withUnsafeBytes { input in
            guard let outputBase = output.bindMemory(to: UInt8.self).baseAddress,
                  let inputBase = input.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(
                outputBase,
                output.count,
                inputBase,
                input.count,
                nil,
                COMPRESSION_ZLIB,
            )
        }
    }
    guard count > 0 else { throw NSError(domain: "PostHogTest", code: 1) }
    return Data(decompressed.prefix(count))
}
