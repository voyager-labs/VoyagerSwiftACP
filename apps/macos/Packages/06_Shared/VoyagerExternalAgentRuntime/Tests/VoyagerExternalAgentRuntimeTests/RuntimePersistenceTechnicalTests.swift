import Foundation
import Testing
@testable import VoyagerExternalAgentRuntime

@Suite("RuntimePersistenceTechnicalTests")
struct RuntimePersistenceTechnicalTests {
    @Test
    func `runtime state storage remains owner only across writes`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let directory = root.appendingPathComponent("runtime", isDirectory: true)
        let fileURL = directory.appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RuntimeFileStateStore(fileURL: fileURL)
        let state = RuntimeStoredState(schemaVersion: RuntimeStoredState.currentSchemaVersion, sessions: [])

        try await store.save(state)
        try await store.save(state)

        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        #expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        #expect((fileAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test
    func `runtime state save preserves a nonempty directory target`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let target = root.appendingPathComponent("runtime.json", isDirectory: true)
        let sentinel = target.appendingPathComponent("sentinel.txt")
        let sentinelBytes = Data("preserve-directory".utf8)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try sentinelBytes.write(to: sentinel)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RuntimeFileStateStore(fileURL: target)
        let state = RuntimeStoredState(schemaVersion: RuntimeStoredState.currentSchemaVersion, sessions: [])

        await #expect(throws: RuntimeHostError.persistenceFailure) {
            try await store.save(state)
        }

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(try Data(contentsOf: sentinel) == sentinelBytes)
    }

    @Test
    func `file store rejects oversized snapshot before decoding`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let file = directory.appending(path: "state.json")
        let quarantine = file.appendingPathExtension("corrupt")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = Data(repeating: 0x20, count: RuntimeBoundaryLimits.snapshotBytes + 1)
        try snapshot.write(to: file)

        let store = RuntimeFileStateStore(fileURL: file)
        await #expect(throws: RuntimeHostError.persistenceFailure) { try await store.load() }
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try Data(contentsOf: quarantine) == snapshot)
        #expect(try await store.load() == nil)
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
    func `persisted sessions reject duplicate run references across hosts`() {
        let run = RuntimeRunReference("run-shared")
        let state = makeState([
            makeStored(host: "host-a", run: run),
            makeStored(host: "host-b", run: run),
        ])

        #expect(throws: RuntimeHostError.malformedAdapterResponse) {
            try state.validatedForRuntime()
        }
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

    @Test
    func `corrupted snapshots are quarantined with original bytes`() async throws {
        let snapshots = [
            Data("not-json".utf8),
            Data(#"{"schema_version":1,"sessions":"invalid"}"#.utf8),
        ]
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("runtime.json")
        let quarantineURL = fileURL.appendingPathExtension("corrupt")

        for snapshot in snapshots {
            try snapshot.write(to: fileURL)
            let store = RuntimeFileStateStore(fileURL: fileURL)

            await #expect(throws: RuntimeHostError.persistenceFailure) {
                _ = try await store.load()
            }
            #expect(!FileManager.default.fileExists(atPath: fileURL.path))
            #expect(try Data(contentsOf: quarantineURL) == snapshot)
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
