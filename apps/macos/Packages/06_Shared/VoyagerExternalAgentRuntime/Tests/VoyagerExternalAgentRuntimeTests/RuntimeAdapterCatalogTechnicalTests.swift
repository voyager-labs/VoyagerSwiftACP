import Foundation
import Testing
@testable import VoyagerExternalAgentRuntime

@Suite("RuntimeAdapterCatalogTechnicalTests")
struct RuntimeAdapterCatalogTechnicalTests {
    @Test
    func `deterministic adapter accepts fake clock and identifiers`() async throws {
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",

            transport: .sdkAsyncStream,

            eventsByLaunch: [[]],

            clock: .immediate,

            IDs: .init { _ in ProviderInternalSessionReference("fixed-provider-session") },

            launchDelay: .seconds(60),
        )

        let receipt = try await adapter.launch(makeLaunch(
            host: "host-a",

            run: RuntimeRunReference("run-a"),

            adapterID: "sdk",

        ))

        #expect(receipt.providerInternalSessionReference == ProviderInternalSessionReference("fixed-provider-session"))
    }

    @Test
    func `adapter failure preserves only bounded category and diagnostic code`() async throws {
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",

            transport: .sdkAsyncStream,

            eventsByLaunch: [[]],

            launchFailure: RuntimeAdapterFailure(
                kind: .transportLoss,

                diagnosticCode: RuntimeDiagnosticCode("transport_lost:/Users/private/token=secret"),

            ),
        )

        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())

        try await plane.register(adapter)

        await #expect(throws: RuntimeHostError.adapterFailure(
            .transportLoss,

            RuntimeDiagnosticCode("adapter_failure"),

        )) {
            _ = try await runPolicyReady(plane, makeLaunch(
                host: "host-a",

                run: RuntimeRunReference("run-a"),

                adapterID: "sdk",

            ))
        }
    }

    @Test
    func `runtime catalog capability slots default unknown and remain explicit`() {
        let capabilities = RuntimeCapabilities(
            discovery: .supported,

            eventStream: .supported,

            approval: .unsupported,

            cancellation: .supported,

            queuedInput: .unsupported,

            terminalResult: .supported,
        )

        let descriptor = RuntimeAdapterDescriptor(
            id: RuntimeAdapterID("sdk"),

            providerNamespace: "provider",

            adapterVersion: "1.0.0",

            transport: .sdkAsyncStream,

            capabilities: capabilities,
        )

        #expect(descriptor.providerBranch == .unknown)

        #expect(capabilities.timeout == .unknown)

        #expect(capabilities.sameIdentityResume == .unknown)

        #expect(capabilities.reconstruction == .unknown)

        #expect(capabilities.explicitArtifact == .unknown)

        #expect(capabilities.workingDirectory == .unknown)

        #expect(capabilities.additionalRoots == .unknown)

        #expect(capabilities.authStatusProbe == .unknown)
    }

    private func makeStoredState(projection: RuntimeProjection) -> RuntimeStoredState {
        RuntimeStoredState(schemaVersion: RuntimeStoredState.currentSchemaVersion, sessions: [RuntimeStoredSession(
            externalAgentSessionReference: "host-a",

            providerInternalSessionReference: ProviderInternalSessionReference("opaque-provider-handle"),

            runReference: RuntimeRunReference("run-a"),

            adapterID: RuntimeAdapterID("sdk"),

            adapterVersion: "1.0.0",

            capabilitySnapshot: .allSupported,

            contextPolicy: RuntimeContextPolicy(
                branchReference: "feat/voy-696",

                authorizationGeneration: 1,

                localCorrelation: "local-a",

            ),

            projection: projection,

            lastSequence: 0,

            acceptedIdempotencyKeys: [],

        )])
    }

    @Test
    func `raw diagnostic initializer remains bounded`() {
        let sensitive = RuntimeDiagnosticCode(rawValue: "/Users/private/token=secret")

        #expect(sensitive.rawValue == "adapter_failure")
    }

    @Test
    func `oversized unknown adapter identifier fails as malformed input`() async throws {
        let oversizedID = String(repeating: "x", count: RuntimeBoundaryLimits.identifierScalars + 1)

        let request = makeLaunch(
            host: "host-oversized-adapter",

            run: RuntimeRunReference("run-oversized-adapter"),

            adapterID: oversizedID,
        )

        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())

        await #expect(throws: RuntimeHostError.malformedAdapterResponse) {
            try await plane.projectPrelaunch(request, as: .policyReady)
        }
    }

    @Test
    func `runtime catalog represents version gated Hermes ACP`() {
        #expect(RuntimeProviderBranch.hermesACPVersionGated.rawValue == "hermes_acp_version_gated")
    }

    @Test
    func `persisted mutations cannot complete out of order`() async throws {
        let store = InMemoryRuntimeStateStore(saveDelays: [1: .milliseconds(100)])

        let plane = RuntimeControlPlane(store: store)

        try await plane.register(makeAdapter())

        let first = Task {
            try await plane.projectPrelaunch(
                makeLaunch(host: "host-a", run: RuntimeRunReference("run-a"), adapterID: "sdk"),

                as: .launchBlocked,
            )
        }

        try await Task.sleep(for: .milliseconds(10))

        let second = Task {
            try await plane.projectPrelaunch(
                makeLaunch(host: "host-b", run: RuntimeRunReference("run-b"), adapterID: "sdk"),

                as: .launchCancelled,
            )
        }

        try await first.value

        try await second.value

        let hosts = try Set(#require(await store.currentState()).sessions.map(\.externalAgentSessionReference))

        #expect(hosts == ["host-a", "host-b"])
    }

    @Test
    func `failed mutation cannot leak through a later snapshot`() async throws {
        let store = InMemoryRuntimeStateStore(
            failingSaveNumbers: [1],

            saveDelays: [1: .milliseconds(100)],
        )

        let plane = RuntimeControlPlane(store: store)

        try await plane.register(makeAdapter())

        let failing = Task {
            try await plane.projectPrelaunch(
                makeLaunch(host: "host-a", run: RuntimeRunReference("run-a"), adapterID: "sdk"),

                as: .launchBlocked,
            )
        }

        try await Task.sleep(for: .milliseconds(10))

        let succeeding = Task {
            try await plane.projectPrelaunch(
                makeLaunch(host: "host-b", run: RuntimeRunReference("run-b"), adapterID: "sdk"),

                as: .launchCancelled,
            )
        }

        await #expect(throws: RuntimeHostError.persistenceFailure) { try await failing.value }

        try await succeeding.value

        let hosts = try #require(await store.currentState()).sessions.map(\.externalAgentSessionReference)

        #expect(hosts == ["host-b"])
    }

    @Test
    func `discovery diagnostic is bounded at construction`() {
        let metadata = RuntimeDiscoveryMetadata(
            readiness: .unavailable,

            diagnosticCode: RuntimeDiagnosticCode("token=/Users/private/secret"),
        )

        #expect(metadata.diagnosticCode == RuntimeDiagnosticCode("adapter_failure"))
    }

    private func makeAdapter() -> DeterministicRuntimeAdapter {
        DeterministicRuntimeAdapter(id: "sdk", transport: .sdkAsyncStream, eventsByLaunch: [[]])
    }

    private func makeHostEvent(
        host: ExternalAgentSessionReference,

        run: RuntimeRunReference,

        sequence: UInt64,

        key: String,

    ) -> RuntimeEventEnvelope {
        RuntimeEventEnvelope(
            source: .host,

            providerEventID: ProviderEventID("host-\(sequence)"),

            sequence: sequence,

            idempotencyKey: RuntimeIdempotencyKey(key),

            timestamp: Date(timeIntervalSince1970: TimeInterval(sequence)),

            externalAgentSessionReference: host,

            runReference: run,

            kind: .progress,
        )
    }

    private func makeStoredSession(providerBranch: RuntimeProviderBranch) -> RuntimeStoredSession {
        RuntimeStoredSession(
            externalAgentSessionReference: "host-a",

            providerInternalSessionReference: ProviderInternalSessionReference("opaque-provider-handle"),

            runReference: RuntimeRunReference("run-a"),

            adapterID: RuntimeAdapterID("sdk"),

            adapterVersion: "1.0.0",

            capabilitySnapshot: .allSupported,

            contextPolicy: makeContext(),

            projection: .running,

            lastSequence: 0,

            acceptedIdempotencyKeys: [],

            providerBranch: providerBranch,
        )
    }

    private func makeContext() -> RuntimeContextPolicy {
        RuntimeContextPolicy(
            branchReference: "feat/voy-696",

            authorizationGeneration: 1,

            localCorrelation: "local-a",
        )
    }
}
