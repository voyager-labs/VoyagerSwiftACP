import Foundation
import Testing
@testable import VoyagerExternalAgentRuntime

@Suite("RuntimePersistenceTechnicalTests")
struct RuntimePersistenceTechnicalTests {
    @Test
    func `file store rejects oversized snapshot before decoding`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let file = directory.appending(path: "state.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(repeating: 0x20, count: RuntimeBoundaryLimits.snapshotBytes + 1).write(to: file)

        let store = RuntimeFileStateStore(fileURL: file)
        await #expect(throws: RuntimeHostError.persistenceFailure) { try await store.load() }
    }

    @Test
    func `file store rejects future schema before overwriting current bytes`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let file = directory.appending(path: "state.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = Data(#"{"schema_version":1,"sessions":[]}"#.utf8)
        try original.write(to: file)
        let store = RuntimeFileStateStore(fileURL: file)
        let future = RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion + 1,
            sessions: [],
        )

        await #expect(throws: RuntimeHostError.unsupportedSchemaVersion(future.schemaVersion)) {
            try await store.save(future)
        }
        #expect(try Data(contentsOf: file) == original)
    }

    @Test
    func `unreleased runtime starts with schema version one`() {
        #expect(RuntimeStoredState.currentSchemaVersion == 1)
    }

    @Test
    func `host and provider references use distinct serialized fields`() throws {
        let session = makeStoredSession()

        let data = try JSONEncoder().encode(session)

        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("external_agent_session_reference"))

        #expect(json.contains("provider_internal_session_reference"))

        #expect(!json.contains("\"session_reference\""))
    }

    @Test
    func `future schema fails closed without overwriting original bytes`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        defer { try? FileManager.default.removeItem(at: root) }

        let fileURL = root.appendingPathComponent("runtime.json")

        let original = Data(#"{"schema_version":999,"sentinel":"keep"}"#.utf8)

        try original.write(to: fileURL)

        let store = RuntimeFileStateStore(fileURL: fileURL)

        await #expect(throws: RuntimeHostError.unsupportedSchemaVersion(999)) {
            _ = try await store.load()
        }

        #expect(try Data(contentsOf: fileURL) == original)
    }

    @Test
    func `older schema uses explicit migration hook`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        defer { try? FileManager.default.removeItem(at: root) }

        let fileURL = root.appendingPathComponent("runtime.json")

        try Data(#"{"schema_version":0}"#.utf8).write(to: fileURL)

        let expected = RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,

            sessions: [makeStoredSession()],
        )

        let store = RuntimeFileStateStore(fileURL: fileURL) { _, version in
            #expect(version == 0)

            return expected
        }

        #expect(try await store.load() == expected)
    }

    @Test
    func `persistence failures expose only bounded host error`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        defer { try? FileManager.default.removeItem(at: root) }

        let fileURL = root.appendingPathComponent("runtime.json")

        try Data("not-json".utf8).write(to: fileURL)

        let store = RuntimeFileStateStore(fileURL: fileURL)

        await #expect(throws: RuntimeHostError.persistenceFailure) {
            _ = try await store.load()
        }
    }

    @Test(arguments: [
        RuntimeTransportKind.processJSONL,

        RuntimeTransportKind.sdkAsyncStream,

    ])
    func `process and SDK transports satisfy the same host contract`(transport: RuntimeTransportKind) async throws {
        let host = ExternalAgentSessionReference("host-\(transport.rawValue)")

        let run = RuntimeRunReference("run-\(transport.rawValue)")

        let adapter = DeterministicRuntimeAdapter(
            id: transport.rawValue,

            transport: transport,

            eventsByLaunch: [[makeEvent(
                host: host,

                run: run,

                sequence: 1,

                idempotencyKey: "done",

                kind: .completed,

            )]],
        )

        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())

        try await plane.register(adapter)

        let result = try await runPolicyReady(plane, RuntimeLaunchRequest(
            externalAgentSessionReference: host,

            runReference: run,

            adapterID: RuntimeAdapterID(transport.rawValue),

            contextPolicy: RuntimeContextPolicy(
                branchReference: "feat/voy-696",

                authorizationGeneration: 1,

                localCorrelation: "local",

            ),

            input: RuntimeSensitiveInput("secret payload"),

        ))

        #expect(result.outcome == .completed)
    }

    private func makeStoredSession() -> RuntimeStoredSession {
        RuntimeStoredSession(
            externalAgentSessionReference: ExternalAgentSessionReference("host-a"),

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

            projection: .running,

            lastSequence: 2,

            acceptedIdempotencyKeys: [RuntimeIdempotencyKey("event-a")],
        )
    }

    private func makeAdapter() -> DeterministicRuntimeAdapter {
        DeterministicRuntimeAdapter(
            id: "sdk",

            transport: .sdkAsyncStream,

            capabilities: .terminalOnly,

            eventsByLaunch: [[]],
        )
    }

    private func makeState(_ sessions: [RuntimeStoredSession]) -> RuntimeStoredState {
        RuntimeStoredState(schemaVersion: RuntimeStoredState.currentSchemaVersion, sessions: sessions)
    }

    private func makeContext() -> RuntimeContextPolicy {
        RuntimeContextPolicy(
            branchReference: "feat/voy-696",

            authorizationGeneration: 1,

            localCorrelation: "local-a",
        )
    }

    private func makeStored(
        host: ExternalAgentSessionReference,

        run: RuntimeRunReference,

        acceptedEventCount: Int = 0,

    ) -> RuntimeStoredSession {
        RuntimeStoredSession(
            externalAgentSessionReference: host,

            providerInternalSessionReference: ProviderInternalSessionReference("opaque-1"),

            runReference: run,

            adapterID: RuntimeAdapterID("sdk"),

            adapterVersion: "1.0.0",

            capabilitySnapshot: .terminalOnly,

            contextPolicy: makeContext(),

            projection: .running,

            lastSequence: 0,

            acceptedEventCount: acceptedEventCount,
        )
    }

    private func makeHostProgress(
        host: ExternalAgentSessionReference,

        run: RuntimeRunReference,

    ) -> RuntimeEventEnvelope {
        RuntimeEventEnvelope(
            source: .host,

            providerEventID: ProviderEventID("host-progress"),

            sequence: 1,

            idempotencyKey: RuntimeIdempotencyKey("host-progress"),

            timestamp: Date(timeIntervalSince1970: 1),

            externalAgentSessionReference: host,

            runReference: run,

            kind: .progress,
        )
    }
}
