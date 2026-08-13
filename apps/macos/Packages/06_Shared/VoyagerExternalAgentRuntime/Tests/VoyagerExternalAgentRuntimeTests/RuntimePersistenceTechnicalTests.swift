@preconcurrency import Darwin
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
    func `control planes sharing a file preserve independent hosts`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = root.appendingPathComponent("runtime-state.json")
        defer { try? FileManager.default.removeItem(at: root) }
        let firstPlane = RuntimeControlPlane(store: RuntimeFileStateStore(fileURL: fileURL))
        let secondPlane = RuntimeControlPlane(store: RuntimeFileStateStore(fileURL: fileURL))
        try await firstPlane.register(makeAdapter())
        try await secondPlane.register(makeAdapter())
        let first = makeLaunch(
            host: ExternalAgentSessionReference("host-a"),
            run: RuntimeRunReference("run-a"),
            adapterID: "sdk",
        )
        let second = makeLaunch(
            host: ExternalAgentSessionReference("host-b"),
            run: RuntimeRunReference("run-b"),
            adapterID: "sdk",
        )

        #expect(try await firstPlane.restore(
            hostReference: first.externalAgentSessionReference,
            expectedContext: first.contextPolicy,
        ) == .stale)
        #expect(try await secondPlane.restore(
            hostReference: second.externalAgentSessionReference,
            expectedContext: second.contextPolicy,
        ) == .stale)
        try await firstPlane.projectPrelaunch(first, as: .policyReady)
        try await secondPlane.projectPrelaunch(second, as: .policyReady)

        let persisted = try #require(try await RuntimeFileStateStore(fileURL: fileURL).load())
        #expect(Set(persisted.sessions.map(\.externalAgentSessionReference)) == [
            first.externalAgentSessionReference,
            second.externalAgentSessionReference,
        ])
    }

    @Test
    func `control planes sharing a file reject stale same host mutation`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = root.appendingPathComponent("runtime-state.json")
        defer { try? FileManager.default.removeItem(at: root) }
        let firstPlane = RuntimeControlPlane(store: RuntimeFileStateStore(fileURL: fileURL))
        let secondPlane = RuntimeControlPlane(store: RuntimeFileStateStore(fileURL: fileURL))
        try await firstPlane.register(makeAdapter())
        try await secondPlane.register(makeAdapter())
        let first = makeLaunch(
            host: ExternalAgentSessionReference("host-a"),
            run: RuntimeRunReference("run-a"),
            adapterID: "sdk",
        )
        let stale = makeLaunch(
            host: first.externalAgentSessionReference,
            run: RuntimeRunReference("run-stale"),
            adapterID: "sdk",
        )

        #expect(try await firstPlane.restore(
            hostReference: first.externalAgentSessionReference,
            expectedContext: first.contextPolicy,
        ) == .stale)
        #expect(try await secondPlane.restore(
            hostReference: stale.externalAgentSessionReference,
            expectedContext: stale.contextPolicy,
        ) == .stale)
        try await firstPlane.projectPrelaunch(first, as: .policyReady)
        await #expect(throws: RuntimeHostError.persistenceFailure) {
            try await secondPlane.projectPrelaunch(stale, as: .policyReady)
        }

        let persisted = try #require(try await RuntimeFileStateStore(fileURL: fileURL).load())
        #expect(persisted.sessions.count == 1)
        #expect(persisted.sessions.first?.runReference == first.runReference)
    }

    @Test
    func `control planes sharing a file resume one provider owner`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = root.appendingPathComponent("runtime-state.json")
        defer { try? FileManager.default.removeItem(at: root) }
        let host = ExternalAgentSessionReference("host-shared-restore")
        let run = RuntimeRunReference("run-shared-restore")
        let context = makeContext()
        let result = RuntimeResult(
            runReference: run,
            outcome: .completed,
            artifactReferences: ["artifact://shared-restore.json"],
        )
        let capabilities = RuntimeCapabilities(
            discovery: .unsupported,
            eventStream: .unsupported,
            approval: .unsupported,
            cancellation: .unsupported,
            queuedInput: .unsupported,
            terminalResult: .supported,
            sameIdentityResume: .supported,
        )
        let stored = RuntimeStoredSession(
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-shared-restore"),
            runReference: run,
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: capabilities,
            contextPolicy: context,
            projection: .running,
        )
        let seed = RuntimeFileStateStore(fileURL: fileURL)
        try await seed.save(makeState([stored]))
        let terminalGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: capabilities,
            eventsByLaunch: [[]],
            terminalResultOverride: result,
            terminalResultGate: terminalGate,
        )
        let firstPlane = RuntimeControlPlane(store: RuntimeFileStateStore(fileURL: fileURL))
        let secondPlane = RuntimeControlPlane(store: RuntimeFileStateStore(fileURL: fileURL))
        try await firstPlane.register(adapter)
        try await secondPlane.register(adapter)

        let firstRestore = try await firstPlane.restore(hostReference: host, expectedContext: context)
        let secondRestore = try await secondPlane.restore(hostReference: host, expectedContext: context)
        #expect(firstRestore == .restored)
        #expect(secondRestore == .stale)
        let firstResume = Task { try await firstPlane.resumeRestoredRun(hostReference: host) }
        await adapter.waitForTerminalResultCount(1)
        if secondRestore == .restored {
            let duplicateResume = Task { try await secondPlane.resumeRestoredRun(hostReference: host) }
            await adapter.waitForTerminalResultCount(2)
            await terminalGate.open()
            _ = try? await duplicateResume.value
        } else {
            await #expect(throws: RuntimeHostError.invalidEvent) {
                try await secondPlane.resumeRestoredRun(hostReference: host)
            }
            await terminalGate.open()
        }

        #expect(try await firstResume.value == result)
        #expect(await adapter.counts().stream == 0)
        let persisted = try #require(try await RuntimeFileStateStore(fileURL: fileURL).load())
        #expect(persisted.sessions.first?.projection == .completed)
    }

    @Test
    func `derived event copies preserve restoration claim`() {
        var stored = makeStoredSession()
        let claim = RuntimeRestorationClaim(
            ownerToken: "owner-copy",
            expiresAt: Date(timeIntervalSince1970: 120),
        )
        stored.restorationClaim = claim

        let withEvidence = stored.withEvidence(.ignoredDuplicate(RuntimeIdempotencyKey("duplicate")))
        let withProviderCount = stored.withProcessedEventCount(3)
        let withHostCount = stored.withHostProcessedEventCount(4)

        #expect(withEvidence.restorationClaim == claim)
        #expect(withEvidence.eventEvidence == [.ignoredDuplicate(RuntimeIdempotencyKey("duplicate"))])
        #expect(withProviderCount.restorationClaim == claim)
        #expect(withProviderCount.processedEventCount == 3)
        #expect(withHostCount.restorationClaim == claim)
        #expect(withHostCount.hostProcessedEventCount == 4)
    }

    @Test
    func `cancelled file lock waiter cannot save after lock release`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = root.appendingPathComponent("runtime-state.json")
        let lockURL = fileURL.appendingPathExtension("lock")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw RuntimeHostError.persistenceFailure }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw RuntimeHostError.persistenceFailure }
        let store = RuntimeFileStateStore(fileURL: fileURL)
        let state = RuntimeStoredState(schemaVersion: RuntimeStoredState.currentSchemaVersion, sessions: [])
        let save = Task { try await store.save(state) }

        try await Task.sleep(for: .milliseconds(20))
        save.cancel()
        flock(descriptor, LOCK_UN)

        await #expect(throws: CancellationError.self) { try await save.value }
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
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
    func `failed older schema migration quarantines original bytes`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("runtime.json")
        let quarantineURL = fileURL.appendingPathExtension("corrupt")
        let original = Data(#"{"schema_version":0,"sentinel":"keep"}"#.utf8)
        try original.write(to: fileURL)
        let store = RuntimeFileStateStore(fileURL: fileURL) { _, _ in
            throw CocoaError(.coderInvalidValue)
        }

        await #expect(throws: RuntimeHostError.migrationFailed) {
            _ = try await store.load()
        }
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        #expect(try Data(contentsOf: quarantineURL) == original)
        #expect(try await store.load() == nil)
    }

    @Test
    func `missing older schema migrator preserves original bytes`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("runtime.json")
        let quarantineURL = fileURL.appendingPathExtension("corrupt")
        let original = Data(#"{"schema_version":0,"sentinel":"keep"}"#.utf8)
        try original.write(to: fileURL)
        let store = RuntimeFileStateStore(fileURL: fileURL)

        await #expect(throws: RuntimeHostError.migrationUnavailable(0)) {
            _ = try await store.load()
        }
        #expect(try Data(contentsOf: fileURL) == original)
        #expect(!FileManager.default.fileExists(atPath: quarantineURL.path))
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
