import Foundation

private enum ProductAnalyticsRecordCodingKeys: String, CodingKey {
    case interactionID = "interaction_id"
    case featureID = "feature_id"
    case implementationStatus = "implementation_status"
    case sentryMetricKeys = "sentry_metric_keys"
    case posthogEventName = "posthog_event_name"
    case legacyAliases = "legacy_aliases"
    case identityPolicy = "identity_policy"
    case propertyAllowlist = "property_allowlist"
    case relatedIssues = "related_issues"
}

private enum ProductAnalyticsMetadataOnlyMetricCodingKeys: String, CodingKey {
    case metricKey = "metric_key"
    case posthogEventName = "posthog_event_name"
    case identityPolicy = "identity_policy"
    case propertyAllowlist = "property_allowlist"
}

private struct ProductAnalyticsAnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

private struct ProductAnalyticsUnknownKeyError: Error {}

private func validateKnownKeys(_ decoder: Decoder, allowed: Set<String>) throws {
    let container = try decoder.container(keyedBy: ProductAnalyticsAnyCodingKey.self)
    let actualKeys = Set(container.allKeys.map(\.stringValue))
    guard actualKeys.isSubset(of: allowed) else {
        throw ProductAnalyticsUnknownKeyError()
    }
}

private struct ProductAnalyticsProvenance: Decodable, Equatable {
    let historicalSource: String
    let currentSource: String
    let historicalCanonicalDate: String
    let currentCanonicalDate: String

    private enum CodingKeys: String, CodingKey {
        case historicalSource = "historical_source"
        case currentSource = "current_source"
        case historicalCanonicalDate = "historical_canonical_date"
        case currentCanonicalDate = "current_canonical_date"
    }

    init(from decoder: Decoder) throws {
        try validateKnownKeys(decoder, allowed: [
            "historical_source", "current_source", "historical_canonical_date", "current_canonical_date",
        ])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        historicalSource = try container.decode(String.self, forKey: .historicalSource)
        currentSource = try container.decode(String.self, forKey: .currentSource)
        historicalCanonicalDate = try container.decode(String.self, forKey: .historicalCanonicalDate)
        currentCanonicalDate = try container.decode(String.self, forKey: .currentCanonicalDate)
    }
}

private struct ProductAnalyticsAggregateExpectations: Decodable, Equatable {
    let specific: Int
    let generic: Int
    let noEventRequired: Int
    let tbd: Int

    private enum CodingKeys: String, CodingKey {
        case specific
        case generic
        case noEventRequired = "no_event_required"
        case tbd = "TBD"
    }

    init(from decoder: Decoder) throws {
        try validateKnownKeys(decoder, allowed: ["specific", "generic", "no_event_required", "TBD"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        specific = try container.decode(Int.self, forKey: .specific)
        generic = try container.decode(Int.self, forKey: .generic)
        noEventRequired = try container.decode(Int.self, forKey: .noEventRequired)
        tbd = try container.decode(Int.self, forKey: .tbd)
    }
}

private struct ProductAnalyticsHistoricalSnapshot: Decodable, Equatable {
    let canonicalCommit: String
    let capturedAt: String
    let interactionCount: Int
    let interactionIDs: [String]
    let aggregateExpectations: ProductAnalyticsAggregateExpectations
    let aggregateSource: String

    private enum CodingKeys: String, CodingKey {
        case canonicalCommit = "canonical_commit"
        case capturedAt = "captured_at"
        case interactionCount = "interaction_count"
        case interactionIDs = "interaction_ids"
        case aggregateExpectations = "aggregate_expectations"
        case aggregateSource = "aggregate_source"
    }

    init(from decoder: Decoder) throws {
        try validateKnownKeys(decoder, allowed: [
            "canonical_commit", "captured_at", "interaction_count", "interaction_ids",
            "aggregate_expectations", "aggregate_source",
        ])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        canonicalCommit = try container.decode(String.self, forKey: .canonicalCommit)
        capturedAt = try container.decode(String.self, forKey: .capturedAt)
        interactionCount = try container.decode(Int.self, forKey: .interactionCount)
        interactionIDs = try container.decode([String].self, forKey: .interactionIDs)
        aggregateExpectations = try container.decode(
            ProductAnalyticsAggregateExpectations.self,
            forKey: .aggregateExpectations,
        )
        aggregateSource = try container.decode(String.self, forKey: .aggregateSource)
    }
}

private struct ProductAnalyticsCurrentSnapshot: Decodable, Equatable {
    let canonicalCommit: String
    let capturedAt: String
    let interactionCount: Int

    private enum CodingKeys: String, CodingKey {
        case canonicalCommit = "canonical_commit"
        case capturedAt = "captured_at"
        case interactionCount = "interaction_count"
    }

    init(from decoder: Decoder) throws {
        try validateKnownKeys(decoder, allowed: ["canonical_commit", "captured_at", "interaction_count"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        canonicalCommit = try container.decode(String.self, forKey: .canonicalCommit)
        capturedAt = try container.decode(String.self, forKey: .capturedAt)
        interactionCount = try container.decode(Int.self, forKey: .interactionCount)
    }
}

private struct ProductAnalyticsReconciliation: Decodable, Equatable {
    let addedInteractionIDs: [String]
    let removedInteractionIDs: [String]

    private enum CodingKeys: String, CodingKey {
        case addedInteractionIDs = "added_interaction_ids"
        case removedInteractionIDs = "removed_interaction_ids"
    }

    init(from decoder: Decoder) throws {
        try validateKnownKeys(decoder, allowed: ["added_interaction_ids", "removed_interaction_ids"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        addedInteractionIDs = try container.decode([String].self, forKey: .addedInteractionIDs)
        removedInteractionIDs = try container.decode([String].self, forKey: .removedInteractionIDs)
    }
}

private struct ProductAnalyticsMetadata: Decodable, Equatable {
    let issue: String
    let capturedAt: String
    let provenance: ProductAnalyticsProvenance
    let historicalSnapshot: ProductAnalyticsHistoricalSnapshot
    let currentSnapshot: ProductAnalyticsCurrentSnapshot
    let reconciliation: ProductAnalyticsReconciliation

    private enum CodingKeys: String, CodingKey {
        case issue
        case capturedAt = "captured_at"
        case provenance
        case historicalSnapshot = "historical_snapshot"
        case currentSnapshot = "current_snapshot"
        case reconciliation
    }

    init(from decoder: Decoder) throws {
        try validateKnownKeys(decoder, allowed: [
            "issue", "captured_at", "provenance", "historical_snapshot", "current_snapshot", "reconciliation",
        ])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        issue = try container.decode(String.self, forKey: .issue)
        capturedAt = try container.decode(String.self, forKey: .capturedAt)
        provenance = try container.decode(ProductAnalyticsProvenance.self, forKey: .provenance)
        historicalSnapshot = try container.decode(ProductAnalyticsHistoricalSnapshot.self, forKey: .historicalSnapshot)
        currentSnapshot = try container.decode(ProductAnalyticsCurrentSnapshot.self, forKey: .currentSnapshot)
        reconciliation = try container.decode(ProductAnalyticsReconciliation.self, forKey: .reconciliation)
    }
}

private struct ProductAnalyticsDocument: Decodable, Equatable {
    let metadata: ProductAnalyticsMetadata?
    let metadataOnlyMetrics: [ProductAnalyticsRegistry.MetadataOnlyMetric]
    let records: [ProductAnalyticsRegistry.Record]

    private enum CodingKeys: String, CodingKey {
        case metadata
        case metadataOnlyMetrics = "metadata_only_metrics"
        case records
    }

    init(from decoder: Decoder) throws {
        try validateKnownKeys(decoder, allowed: ["metadata", "metadata_only_metrics", "records"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metadata = try container.decodeIfPresent(ProductAnalyticsMetadata.self, forKey: .metadata)
        metadataOnlyMetrics = try container.decodeIfPresent(
            [ProductAnalyticsRegistry.MetadataOnlyMetric].self,
            forKey: .metadataOnlyMetrics,
        ) ?? []
        records = try container.decode([ProductAnalyticsRegistry.Record].self, forKey: .records)
    }
}

public enum ProductAnalyticsImplementationStatus: String, Codable, Equatable, Sendable {
    case implemented
    case deferred
    case noEventRequired = "no_event_required"
    case tbd = "TBD"
}

public enum ProductAnalyticsRegistryIdentityPolicy: String, Codable, Equatable, Sendable {
    case device
    case anonymous
    case none
}

public enum ProductAnalyticsDropReason: Equatable, Sendable {
    case legacyAlias
    case unregistered
    case deferred
    case noEventRequired
    case tbd
    case identityUnavailable
    case privacyRejected
}

public enum ProductAnalyticsMappingResult: Equatable, Sendable {
    case capture(ProductAnalyticsCaptureRequest)
    case drop(ProductAnalyticsDropReason)
}

public enum ProductAnalyticsRegistryLoadError: Equatable, Sendable {
    case missingResource
    case malformed
    case unknownKey
    case duplicateInteractionID
    case duplicateMetricKey
}

public struct ProductAnalyticsRegistry: Equatable, Sendable {
    public struct MetadataOnlyMetric: Codable, Equatable, Sendable {
        public let metricKey: String
        public let posthogEventName: String
        public let identityPolicy: ProductAnalyticsRegistryIdentityPolicy
        public let propertyAllowlist: [String]

        public init(
            metricKey: String,
            posthogEventName: String,
            identityPolicy: ProductAnalyticsRegistryIdentityPolicy,
            propertyAllowlist: [String],
        ) {
            self.metricKey = metricKey
            self.posthogEventName = posthogEventName
            self.identityPolicy = identityPolicy
            self.propertyAllowlist = propertyAllowlist
        }

        public init(from decoder: Decoder) throws {
            try validateKnownKeys(decoder, allowed: [
                "metric_key", "posthog_event_name", "identity_policy", "property_allowlist",
            ])
            let container = try decoder.container(keyedBy: ProductAnalyticsMetadataOnlyMetricCodingKeys.self)
            try self.init(
                metricKey: container.decode(String.self, forKey: .metricKey),
                posthogEventName: container.decode(String.self, forKey: .posthogEventName),
                identityPolicy: container.decode(ProductAnalyticsRegistryIdentityPolicy.self, forKey: .identityPolicy),
                propertyAllowlist: container.decode([String].self, forKey: .propertyAllowlist),
            )
        }
    }

    public struct Record: Codable, Equatable, Sendable {
        public let interactionID: String
        public let featureID: String
        public let implementationStatus: ProductAnalyticsImplementationStatus
        public let sentryMetricKeys: [String]
        public let posthogEventName: String?
        public let legacyAliases: [String]
        public let identityPolicy: ProductAnalyticsRegistryIdentityPolicy
        public let propertyAllowlist: [String]
        public let relatedIssues: [String]

        public init(
            interactionID: String,
            featureID: String,
            implementationStatus: ProductAnalyticsImplementationStatus,
            sentryMetricKeys: [String],
            posthogEventName: String?,
            legacyAliases: [String],
            identityPolicy: ProductAnalyticsRegistryIdentityPolicy,
            propertyAllowlist: [String],
            relatedIssues: [String],
        ) {
            self.interactionID = interactionID
            self.featureID = featureID
            self.implementationStatus = implementationStatus
            self.sentryMetricKeys = sentryMetricKeys
            self.posthogEventName = posthogEventName
            self.legacyAliases = legacyAliases
            self.identityPolicy = identityPolicy
            self.propertyAllowlist = propertyAllowlist
            self.relatedIssues = relatedIssues
        }

        public init(from decoder: Decoder) throws {
            try validateKnownKeys(decoder, allowed: [
                "interaction_id", "feature_id", "implementation_status", "sentry_metric_keys",
                "posthog_event_name", "legacy_aliases", "identity_policy", "property_allowlist", "related_issues",
            ])
            let container = try decoder.container(keyedBy: ProductAnalyticsRecordCodingKeys.self)
            try self.init(
                interactionID: container.decode(String.self, forKey: .interactionID),
                featureID: container.decode(String.self, forKey: .featureID),
                implementationStatus: container.decode(
                    ProductAnalyticsImplementationStatus.self,
                    forKey: .implementationStatus,
                ),
                sentryMetricKeys: container.decode([String].self, forKey: .sentryMetricKeys),
                posthogEventName: container.decodeIfPresent(String.self, forKey: .posthogEventName),
                legacyAliases: container.decode([String].self, forKey: .legacyAliases),
                identityPolicy: container.decode(ProductAnalyticsRegistryIdentityPolicy.self, forKey: .identityPolicy),
                propertyAllowlist: container.decode([String].self, forKey: .propertyAllowlist),
                relatedIssues: container.decode([String].self, forKey: .relatedIssues),
            )
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: ProductAnalyticsRecordCodingKeys.self)
            try container.encode(interactionID, forKey: .interactionID)
            try container.encode(featureID, forKey: .featureID)
            try container.encode(implementationStatus, forKey: .implementationStatus)
            try container.encode(sentryMetricKeys, forKey: .sentryMetricKeys)
            try container.encodeIfPresent(posthogEventName, forKey: .posthogEventName)
            try container.encode(legacyAliases, forKey: .legacyAliases)
            try container.encode(identityPolicy, forKey: .identityPolicy)
            try container.encode(propertyAllowlist, forKey: .propertyAllowlist)
            try container.encode(relatedIssues, forKey: .relatedIssues)
        }
    }

    public let records: [Record]
    private let byMetricKey: [String: Record]
    private let byMetadataMetricKey: [String: MetadataOnlyMetric]

    var metadataOnlyMetricCount: Int {
        byMetadataMetricKey.count
    }

    public init(records: [Record], metadataOnlyMetrics: [MetadataOnlyMetric] = []) {
        self.records = records
        byMetricKey = Self.index(records)
        byMetadataMetricKey = Dictionary(
            metadataOnlyMetrics.map { ($0.metricKey, $0) },
            uniquingKeysWith: { first, _ in first },
        )
    }

    public static func load(bundle: Bundle = .main) -> ProductAnalyticsRegistry {
        loadResult(bundle: bundle).registry ?? ProductAnalyticsRegistry(records: [])
    }

    public static func loadResult(bundle: Bundle = .main) -> LoadResult {
        guard let url = bundle.url(forResource: "ProductAnalyticsRegistry", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else {
            return .invalid(.missingResource)
        }
        return load(data: data)
    }

    public static func load(data: Data) -> LoadResult {
        let document: ProductAnalyticsDocument
        do {
            document = try JSONDecoder().decode(ProductAnalyticsDocument.self, from: data)
        } catch is ProductAnalyticsUnknownKeyError {
            return .invalid(.unknownKey)
        } catch {
            return .invalid(.malformed)
        }
        let interactionIDs = document.records.map(\.interactionID)
        guard Set(interactionIDs).count == interactionIDs.count else {
            return .invalid(.duplicateInteractionID)
        }
        let metricKeys = document.records.flatMap { $0.sentryMetricKeys + $0.legacyAliases }
            + document.metadataOnlyMetrics.map(\.metricKey)
        guard Set(metricKeys).count == metricKeys.count else {
            return .invalid(.duplicateMetricKey)
        }
        return .loaded(ProductAnalyticsRegistry(
            records: document.records,
            metadataOnlyMetrics: document.metadataOnlyMetrics,
        ))
    }

    public enum LoadResult: Equatable, Sendable {
        case loaded(ProductAnalyticsRegistry)
        case invalid(ProductAnalyticsRegistryLoadError)

        var registry: ProductAnalyticsRegistry? {
            guard case let .loaded(registry) = self else { return nil }
            return registry
        }
    }

    nonisolated public func resolve(
        metricKey: String,
        identity: ProductAnalyticsIdentity,
        context: ProductAnalyticsEventContext = .init(
            occurredAtUTC: Date(timeIntervalSince1970: 0),
            environment: "unknown",
            appVersion: "unknown",
            platform: "macOS",
            source: "unknown",
        ),
        properties: [String: ProductAnalyticsPropertyValue] = [:],
    ) -> ProductAnalyticsMappingResult {
        if let metadataOnlyMetric = byMetadataMetricKey[metricKey] {
            return resolveMetadataOnlyMetric(
                metadataOnlyMetric,
                identity: identity,
                context: context,
                properties: properties,
            )
        }
        return resolveCanonicalMetric(
            metricKey: metricKey,
            identity: identity,
            context: context,
            properties: properties,
        )
    }

    nonisolated private func resolveCanonicalMetric(
        metricKey: String,
        identity: ProductAnalyticsIdentity,
        context: ProductAnalyticsEventContext,
        properties: [String: ProductAnalyticsPropertyValue],
    ) -> ProductAnalyticsMappingResult {
        guard let record = byMetricKey[metricKey] else { return .drop(.unregistered) }
        if record.legacyAliases.contains(metricKey) { return .drop(.legacyAlias) }
        switch record.implementationStatus {
        case .deferred: return .drop(.deferred)
        case .noEventRequired: return .drop(.noEventRequired)
        case .tbd: return .drop(.tbd)
        case .implemented: break
        }
        guard let eventName = record.posthogEventName, !eventName.isEmpty else {
            return .drop(.tbd)
        }
        guard record.identityPolicy != .none else { return .drop(.noEventRequired) }
        guard identityIsAvailable(for: record.identityPolicy, identity: identity) else {
            return .drop(.identityUnavailable)
        }
        let distinctID = explicitDistinctID(for: record.identityPolicy, identity: identity)
        guard isPrivacySafe(properties, allowed: record.propertyAllowlist) else {
            return .drop(.privacyRejected)
        }
        let event = ProductAnalyticsEvent(
            eventName: .init(rawValue: eventName),
            occurredAtUTC: context.occurredAtUTC,
            environment: context.environment,
            distinctID: distinctID,
            appVersion: context.appVersion,
            platform: context.platform,
            source: context.source,
            properties: properties,
            sourceProject: context.sourceProject,
            identifiers: .init(interactionID: record.interactionID, featureID: record.featureID),
        )
        return .capture(.init(event: event))
    }

    nonisolated private func resolveMetadataOnlyMetric(
        _ metric: MetadataOnlyMetric,
        identity: ProductAnalyticsIdentity,
        context: ProductAnalyticsEventContext,
        properties: [String: ProductAnalyticsPropertyValue],
    ) -> ProductAnalyticsMappingResult {
        guard !metric.posthogEventName.isEmpty else { return .drop(.tbd) }
        guard metric.identityPolicy != .none else { return .drop(.noEventRequired) }
        guard identityIsAvailable(for: metric.identityPolicy, identity: identity) else {
            return .drop(.identityUnavailable)
        }
        guard isPrivacySafe(properties, allowed: metric.propertyAllowlist) else {
            return .drop(.privacyRejected)
        }
        let event = ProductAnalyticsEvent(
            eventName: .init(rawValue: metric.posthogEventName),
            occurredAtUTC: context.occurredAtUTC,
            environment: context.environment,
            distinctID: explicitDistinctID(for: metric.identityPolicy, identity: identity),
            appVersion: context.appVersion,
            platform: context.platform,
            source: context.source,
            properties: properties,
            sourceProject: context.sourceProject,
        )
        return .capture(.init(event: event))
    }

    private static func index(_ records: [Record]) -> [String: Record] {
        Dictionary(
            records.flatMap { record in
                record.sentryMetricKeys.map { ($0, record) } + record.legacyAliases.map { ($0, record) }
            },
            uniquingKeysWith: { first, _ in first },
        )
    }

    nonisolated private func explicitDistinctID(
        for policy: ProductAnalyticsRegistryIdentityPolicy,
        identity: ProductAnalyticsIdentity,
    ) -> String? {
        switch policy {
        case .device:
            guard case let .device(value) = identity, let value, !value.isEmpty else { return nil }
            return value
        case .anonymous:
            return nil
        case .none:
            return nil
        }
    }

    nonisolated private func identityIsAvailable(
        for policy: ProductAnalyticsRegistryIdentityPolicy,
        identity: ProductAnalyticsIdentity,
    ) -> Bool {
        switch policy {
        case .device:
            guard case let .device(value) = identity else { return false }
            return value?.isEmpty == false
        case .anonymous:
            guard case .anonymous = identity else { return false }
            return true
        case .none:
            return false
        }
    }

    nonisolated private func isPrivacySafe(
        _ properties: [String: ProductAnalyticsPropertyValue],
        allowed: [String],
    ) -> Bool {
        let allowedKeys = Set(allowed).intersection(Self.commonPropertyAllowlist)
        guard Set(properties.keys).isSubset(of: allowedKeys) else { return false }
        return properties.allSatisfy { key, value in
            isAllowedTelemetryValue(key: key, value: value)
        }
    }

    nonisolated private func isAllowedTelemetryValue(
        key: String,
        value: ProductAnalyticsPropertyValue,
    ) -> Bool {
        switch key {
        case "interaction_id", "feature_id":
            return isIdentifierValue(key: key, value: value)
        case "source_surface", "result_status", "failure_reason", "recovery_action":
            guard case let .string(value) = value else { return false }
            return isBoundedTelemetryToken(key: key, value: value)
        case "target_count", "duration_ms":
            return isBoundedInteger(key: key, value: value)
        default:
            return false
        }
    }

    nonisolated private func isIdentifierValue(
        key: String,
        value: ProductAnalyticsPropertyValue,
    ) -> Bool {
        guard case let .string(value) = value else { return false }
        return key == "interaction_id" ? isInteractionID(value) : isFeatureID(value)
    }

    nonisolated private func isBoundedInteger(
        key: String,
        value: ProductAnalyticsPropertyValue,
    ) -> Bool {
        guard case let .integer(value) = value else { return false }
        let upperBound = key == "target_count" ? 10000 : 86_400_000
        return (0 ... upperBound).contains(value)
    }

    nonisolated private func isInteractionID(_ value: String) -> Bool {
        let components = value.split(separator: "-", omittingEmptySubsequences: false)
        guard components.count == 3,
              isFeatureID("\(components[0])-\(components[1])"),
              components[2].allSatisfy({ $0.isLowercase || $0.isNumber || $0 == "_" })
        else {
            return false
        }
        return components[2].isEmpty == false
    }

    nonisolated private func isFeatureID(_ value: String) -> Bool {
        let components = value.split(separator: "-", omittingEmptySubsequences: false)
        guard components.count == 2,
              (2 ... 4).contains(components[0].count),
              components[0].allSatisfy(\.isUppercase),
              components[1].count == 3,
              components[1].allSatisfy(\.isNumber)
        else {
            return false
        }
        return true
    }

    nonisolated private func isBoundedTelemetryToken(key: String, value: String) -> Bool {
        guard (1 ... 64).contains(value.count),
              value.first?.isLetter == true,
              value.allSatisfy({ $0.isLowercase || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." })
        else {
            return false
        }
        if key == "result_status", value == "invalid_credential" {
            return true
        }
        return !Self.sensitiveValueFragments.contains { value.localizedCaseInsensitiveContains($0) }
    }

    nonisolated private static let commonPropertyAllowlist: Set<String> = [
        "interaction_id", "feature_id", "source_surface", "result_status", "failure_reason",
        "recovery_action", "target_count", "duration_ms",
    ]

    nonisolated private static let sensitiveValueFragments = [
        "/", "\\", "~/", "sk-", "pk-", "ghp_", "xoxb-", "bearer", "api_key", "token", "secret",
        "password", "credential", "response", "question", "prompt", "answer", "user_input", "model_output",
        "ignore previous instructions", "<script",
    ]
}
