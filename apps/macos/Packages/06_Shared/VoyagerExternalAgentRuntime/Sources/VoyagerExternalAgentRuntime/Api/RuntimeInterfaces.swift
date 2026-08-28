import Foundation

public protocol ExternalAgentRuntimeAdapter: Actor {
    nonisolated var descriptor: RuntimeAdapterDescriptor { get }
    func discoveryMetadata() async throws -> RuntimeDiscoveryMetadata
    func launch(_ request: RuntimeLaunchRequest) async throws -> RuntimeLaunchReceipt
    func eventStream(for runReference: RuntimeRunReference) async throws
        -> AsyncThrowingStream<RuntimeEventEnvelope, any Error>
    func respondToApproval(_ request: RuntimeApprovalRequest) async throws
    func requestCancellation(_ request: RuntimeCancellationRequest) async throws
    func enqueueInput(_ request: RuntimeQueuedInputRequest) async throws
    func terminalResult(for runReference: RuntimeRunReference) async throws -> RuntimeResult
    func restartCompatibility(for binding: RuntimeRestartBinding) async throws -> RuntimeRestartCompatibility
}

public protocol RuntimeStateStore: Sendable {
    func load() async throws -> RuntimeStoredState?
    func apply(_ mutation: RuntimeStateMutation) async throws -> RuntimeStateMutationResult
}

public struct RuntimeStateMutation: Sendable {
    public let host: ExternalAgentSessionReference
    public let expected: RuntimeStoredSession?
    public let replacement: RuntimeStoredSession?

    public init(
        host: ExternalAgentSessionReference,
        expected: RuntimeStoredSession?,
        replacement: RuntimeStoredSession?,
    ) {
        self.host = host
        self.expected = expected
        self.replacement = replacement
    }
}

public enum RuntimeStateMutationResult: Sendable, Equatable {
    case committed(RuntimeStoredState)
    case conflict(RuntimeStoredState?)
}

public enum RuntimeStateStoreError: Error, Sendable, Equatable {
    case invalidSnapshot
    case unavailable
    case unsupportedSchemaVersion(Int)
}

public struct RuntimeSerializationKey: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let externalAgentSessionReference =
        RuntimeSerializationKey(rawValue: "external_agent_session_reference")
    public static let providerInternalSessionReference =
        RuntimeSerializationKey(rawValue: "provider_internal_session_reference")
    public static let hostRun = RuntimeSerializationKey(rawValue: "host_run")
    public static let providerRun = RuntimeSerializationKey(rawValue: "provider_run")
}
