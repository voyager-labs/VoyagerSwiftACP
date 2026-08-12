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
    func save(_ state: RuntimeStoredState) async throws
}

protocol RuntimeStateStoreHostMutation: RuntimeStateStore {
    func updateHost(
        _ host: ExternalAgentSessionReference,
        expected: RuntimeStoredSession?,
        replacement: RuntimeStoredSession?,
    ) async throws -> RuntimeStoredState
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
