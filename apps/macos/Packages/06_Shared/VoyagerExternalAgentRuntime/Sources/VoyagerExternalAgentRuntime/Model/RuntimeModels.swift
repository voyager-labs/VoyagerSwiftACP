import Foundation

public struct RuntimeLaunchRequest: Sendable { public let externalAgentSessionReference: ExternalAgentSessionReference
    public let runReference: RuntimeRunReference
    public let adapterID: RuntimeAdapterID
    public let contextPolicy: RuntimeContextPolicy
    public let input: RuntimeSensitiveInput
    public init(
        externalAgentSessionReference: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
        adapterID: RuntimeAdapterID,
        contextPolicy: RuntimeContextPolicy,
        input: RuntimeSensitiveInput,
    ) {
        self.externalAgentSessionReference = externalAgentSessionReference
        self.runReference = runReference
        self.adapterID = adapterID
        self.contextPolicy = contextPolicy
        self.input = input
    }
}

public struct RuntimeLaunchReceipt: Codable, Sendable { public let runReference: RuntimeRunReference
    public let providerInternalSessionReference: ProviderInternalSessionReference
    public init(runReference: RuntimeRunReference, providerInternalSessionReference: ProviderInternalSessionReference) {
        self.runReference = runReference
        self.providerInternalSessionReference = providerInternalSessionReference
    }
}

public enum RuntimeEventSource: String, Codable, Sendable { case provider, host }
public enum RuntimeEventKind: String, Codable,
    Sendable { case policyReady, completed, failed, interrupted, approvalRequested, inputRequested, progress }
public struct RuntimeEventEnvelope: Codable, Sendable, Hashable { public let source: RuntimeEventSource
    public let providerEventID: ProviderEventID
    public let sequence: UInt64
    public let idempotencyKey: RuntimeIdempotencyKey
    public let timestamp: Date
    public let externalAgentSessionReference: ExternalAgentSessionReference
    public let runReference: RuntimeRunReference
    public let kind: RuntimeEventKind
    public init(
        source: RuntimeEventSource,
        providerEventID: ProviderEventID,
        sequence: UInt64,
        idempotencyKey: RuntimeIdempotencyKey,
        timestamp: Date,
        externalAgentSessionReference: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
        kind: RuntimeEventKind,
    ) {
        self.source = source
        self.providerEventID = providerEventID
        self.sequence = sequence
        self.idempotencyKey = idempotencyKey
        self.timestamp = timestamp
        self.externalAgentSessionReference = externalAgentSessionReference
        self.runReference = runReference
        self.kind = kind
    }
}

public enum RuntimeProjection: String, Codable, Sendable {
    case policyPending, policyReady, launchBlocked, launching, launchCancelled, launchFailed
    case running, eventProjected, eventDuplicateIgnored, eventOutOfOrder
    case completed, failed, interrupted
}

public enum RuntimePrelaunchProjection: String, Codable, Sendable {
    case policyPending, policyReady, launchBlocked, launchCancelled

    var projection: RuntimeProjection {
        switch self {
        case .policyPending: .policyPending
        case .policyReady: .policyReady
        case .launchBlocked: .launchBlocked
        case .launchCancelled: .launchCancelled
        }
    }
}

public enum RuntimeOutcome: String, Codable, Sendable { case completed, failed, interrupted }
public struct RuntimeResult: Codable, Sendable, Equatable { public let runReference: RuntimeRunReference
    public let outcome: RuntimeOutcome
    public let artifactReferences: [String]
    public let failure: RuntimeAdapterFailure?
    public init(
        runReference: RuntimeRunReference,
        outcome: RuntimeOutcome,
        artifactReferences: [String],
        failure: RuntimeAdapterFailure? = nil,
    ) {
        self.runReference = runReference
        self.outcome = outcome
        self.artifactReferences = artifactReferences
        self.failure = failure
    }
}

public enum RuntimeEventEvidence: Codable, Sendable, Hashable { case ignoredDuplicate(RuntimeIdempotencyKey)
    case sequenceGap(expected: UInt64, received: UInt64)
    case staleSequence(lastAccepted: UInt64, received: UInt64)
}

public struct RuntimeApprovalRequest: Codable, Sendable {
    public let externalAgentSessionReference: ExternalAgentSessionReference
    public let providerInternalSessionReference: ProviderInternalSessionReference
    public let requestID: RuntimeApprovalRequestID
    public let operationID: RuntimeOperationID
    public let runReference: RuntimeRunReference
    public let authorizationGeneration: UInt64
    public init(
        externalAgentSessionReference: ExternalAgentSessionReference,
        providerInternalSessionReference: ProviderInternalSessionReference,
        requestID: RuntimeApprovalRequestID,
        operationID: RuntimeOperationID,
        runReference: RuntimeRunReference,
        authorizationGeneration: UInt64,
    ) {
        self.externalAgentSessionReference = externalAgentSessionReference
        self.providerInternalSessionReference = providerInternalSessionReference
        self.requestID = requestID
        self.operationID = operationID
        self.runReference = runReference
        self.authorizationGeneration = authorizationGeneration
    }
}

public struct RuntimeCancellationRequest: Codable, Sendable { public let operationID: RuntimeOperationID
    public let runReference: RuntimeRunReference
    public init(operationID: RuntimeOperationID, runReference: RuntimeRunReference) {
        self.operationID = operationID
        self.runReference = runReference
    }
}

public struct RuntimeQueuedInputRequest: Sendable {
    public let operationID: RuntimeOperationID
    public let runReference: RuntimeRunReference
    public let input: RuntimeSensitiveInput
    public init(operationID: RuntimeOperationID, runReference: RuntimeRunReference, input: RuntimeSensitiveInput) {
        self.operationID = operationID
        self.runReference = runReference
        self.input = input
    }
}

public struct RuntimeRestartBinding: Sendable,
    Hashable
{ public let externalAgentSessionReference: ExternalAgentSessionReference
    public let providerInternalSessionReference: ProviderInternalSessionReference
    public let runReference: RuntimeRunReference
    public let adapterID: RuntimeAdapterID
    public let providerNamespace: String
    public let adapterVersion: String
    public let providerBranch: RuntimeProviderBranch
    public let capabilitySnapshot: RuntimeCapabilities
    public let contextPolicy: RuntimeContextPolicy
    public let providerEventSequence: UInt64
    public init(
        externalAgentSessionReference: ExternalAgentSessionReference,
        providerInternalSessionReference: ProviderInternalSessionReference,
        runReference: RuntimeRunReference,
        adapterID: RuntimeAdapterID,
        providerNamespace: String,
        adapterVersion: String,
        providerBranch: RuntimeProviderBranch,
        capabilitySnapshot: RuntimeCapabilities,
        contextPolicy: RuntimeContextPolicy,
        providerEventSequence: UInt64 = 0,
    ) {
        self.externalAgentSessionReference = externalAgentSessionReference
        self.providerInternalSessionReference = providerInternalSessionReference
        self.runReference = runReference
        self.adapterID = adapterID
        self.providerNamespace = providerNamespace
        self.adapterVersion = adapterVersion
        self.providerBranch = providerBranch
        self.capabilitySnapshot = capabilitySnapshot
        self.contextPolicy = contextPolicy
        self.providerEventSequence = providerEventSequence
    }
}

public enum RuntimeRestartCompatibility: String, Codable, Sendable { case compatible, stale, incompatible }
public enum RuntimeRestoreResult: String, Codable, Sendable { case restored, stale }
