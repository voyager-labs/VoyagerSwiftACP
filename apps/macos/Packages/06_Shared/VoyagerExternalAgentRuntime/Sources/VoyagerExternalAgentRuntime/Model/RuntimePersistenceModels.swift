import Foundation

public struct RuntimeStoredSession: Codable, Sendable, Hashable {
    public let externalAgentSessionReference: ExternalAgentSessionReference
    public let providerInternalSessionReference: ProviderInternalSessionReference?
    public let runReference: RuntimeRunReference
    public let adapterID: RuntimeAdapterID
    public let providerNamespace: String
    public let adapterVersion: String
    public let providerBranch: RuntimeProviderBranch
    public let capabilitySnapshot: RuntimeCapabilities
    public let contextPolicy: RuntimeContextPolicy
    public let projection: RuntimeProjection
    public let providerLaunchAttempted: Bool?
    public let lastSequence: UInt64
    public let acceptedEventCount: Int
    public let processedEventCount: Int
    public let acceptedIdempotencyKeys: [RuntimeIdempotencyKey]
    public let hostLastSequence: UInt64
    public let hostAcceptedEventCount: Int
    public let hostProcessedEventCount: Int
    public let hostAcceptedIdempotencyKeys: [RuntimeIdempotencyKey]
    public let eventEvidence: [RuntimeEventEvidence]
    var restorationClaim: RuntimeRestorationClaim?

    enum CodingKeys: String, CodingKey {
        case externalAgentSessionReference = "external_agent_session_reference"
        case providerInternalSessionReference = "provider_internal_session_reference"
        case runReference = "run_reference"
        case adapterID = "adapter_id"
        case providerNamespace = "provider_namespace"
        case adapterVersion = "adapter_version"
        case providerBranch = "provider_branch"
        case capabilitySnapshot = "capability_snapshot"
        case contextPolicy = "context_policy"
        case projection
        case providerLaunchAttempted = "provider_launch_attempted"
        case lastSequence = "last_sequence"
        case acceptedEventCount = "accepted_event_count"
        case processedEventCount = "processed_event_count"
        case acceptedIdempotencyKeys = "accepted_idempotency_keys"
        case hostLastSequence = "host_last_sequence"
        case hostAcceptedEventCount = "host_accepted_event_count"
        case hostProcessedEventCount = "host_processed_event_count"
        case hostAcceptedIdempotencyKeys = "host_accepted_idempotency_keys"
        case eventEvidence = "event_evidence"
        case restorationClaim = "restoration_claim"
    }

    public init(
        externalAgentSessionReference: ExternalAgentSessionReference,
        providerInternalSessionReference: ProviderInternalSessionReference?,
        runReference: RuntimeRunReference,
        adapterID: RuntimeAdapterID,
        adapterVersion: String,
        capabilitySnapshot: RuntimeCapabilities,
        contextPolicy: RuntimeContextPolicy,
        projection: RuntimeProjection,
        providerLaunchAttempted: Bool? = nil,
        lastSequence: UInt64 = 0,
        acceptedEventCount: Int = 0,
        processedEventCount: Int? = nil,
        acceptedIdempotencyKeys: [RuntimeIdempotencyKey] = [],
        hostLastSequence: UInt64 = 0,
        hostAcceptedEventCount: Int = 0,
        hostProcessedEventCount: Int? = nil,
        hostAcceptedIdempotencyKeys: [RuntimeIdempotencyKey] = [],
        providerNamespace: String? = nil,
        providerBranch: RuntimeProviderBranch = .unknown,
        eventEvidence: [RuntimeEventEvidence] = [],
    ) {
        self.externalAgentSessionReference = externalAgentSessionReference
        self.providerInternalSessionReference = providerInternalSessionReference
        self.runReference = runReference
        self.adapterID = adapterID
        self.providerNamespace = providerNamespace ?? adapterID.rawValue
        self.adapterVersion = adapterVersion
        self.providerBranch = providerBranch
        self.capabilitySnapshot = capabilitySnapshot
        self.contextPolicy = contextPolicy
        self.projection = projection
        self.providerLaunchAttempted = providerLaunchAttempted
        self.lastSequence = lastSequence
        self.acceptedEventCount = acceptedEventCount
        self.processedEventCount = processedEventCount ?? acceptedEventCount
        self.acceptedIdempotencyKeys = acceptedIdempotencyKeys
        self.hostLastSequence = hostLastSequence
        self.hostAcceptedEventCount = hostAcceptedEventCount
        self.hostProcessedEventCount = hostProcessedEventCount ?? hostAcceptedEventCount
        self.hostAcceptedIdempotencyKeys = hostAcceptedIdempotencyKeys
        self.eventEvidence = eventEvidence
        restorationClaim = nil
    }

    func hasSamePersistedState(as other: Self) -> Bool {
        externalAgentSessionReference == other.externalAgentSessionReference
            && providerInternalSessionReference == other.providerInternalSessionReference
            && runReference == other.runReference
            && adapterID == other.adapterID
            && providerNamespace == other.providerNamespace
            && adapterVersion == other.adapterVersion
            && providerBranch == other.providerBranch
            && capabilitySnapshot == other.capabilitySnapshot
            && contextPolicy.hasSameExecutionContext(as: other.contextPolicy)
            && projection == other.projection
            && providerLaunchAttempted == other.providerLaunchAttempted
            && lastSequence == other.lastSequence
            && acceptedEventCount == other.acceptedEventCount
            && processedEventCount == other.processedEventCount
            && acceptedIdempotencyKeys == other.acceptedIdempotencyKeys
            && hostLastSequence == other.hostLastSequence
            && hostAcceptedEventCount == other.hostAcceptedEventCount
            && hostProcessedEventCount == other.hostProcessedEventCount
            && hostAcceptedIdempotencyKeys == other.hostAcceptedIdempotencyKeys
            && eventEvidence == other.eventEvidence
            && restorationClaim == other.restorationClaim
    }

    static func hasSamePersistedState(_ lhs: Self?, _ rhs: Self?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            true
        case let (.some(lhs), .some(rhs)):
            lhs.hasSamePersistedState(as: rhs)
        default:
            false
        }
    }
}

struct RuntimeRestorationClaim: Codable, Hashable {
    let ownerToken: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case ownerToken = "owner_token"
        case expiresAt = "expires_at"
    }

    func isLive(at date: Date) -> Bool {
        expiresAt > date
    }
}

public struct RuntimeStoredState: Codable, Sendable, Hashable {
    public static let currentSchemaVersion = 1
    public let schemaVersion: Int
    public let sessions: [RuntimeStoredSession]

    public init(schemaVersion: Int, sessions: [RuntimeStoredSession]) {
        self.schemaVersion = schemaVersion
        self.sessions = sessions
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sessions
    }
}
