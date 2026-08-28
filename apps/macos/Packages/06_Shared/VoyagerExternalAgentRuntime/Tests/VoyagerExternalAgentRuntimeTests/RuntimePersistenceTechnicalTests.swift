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
        let stored = makeStoredSession()
        _ = try await store.apply(RuntimeStateMutation(
            host: stored.externalAgentSessionReference,
            expected: nil,
            replacement: stored,
        ))
        _ = try await store.apply(RuntimeStateMutation(
            host: stored.externalAgentSessionReference,
            expected: stored,
            replacement: stored,
        ))

        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        #expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        #expect((fileAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
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
        let save = Task {
            try await store.apply(RuntimeStateMutation(
                host: "host-lock",
                expected: nil,
                replacement: makeStoredSession(),
            ))
        }

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
        await #expect(throws: RuntimeStateStoreError.unavailable) {
            _ = try await store.apply(RuntimeStateMutation(
                host: "host-a",
                expected: nil,
                replacement: makeStoredSession(),
            ))
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
        await #expect(throws: RuntimeStateStoreError.invalidSnapshot) { try await store.load() }
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
        #expect(try await store.load()?.schemaVersion == RuntimeStoredState.currentSchemaVersion)
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

        #expect(throws: RuntimeStateStoreError.invalidSnapshot) {
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

        await #expect(throws: RuntimeStateStoreError.unsupportedSchemaVersion(999)) {
            _ = try await store.load()
        }

        #expect(try Data(contentsOf: fileURL) == original)
        #expect(!FileManager.default.fileExists(atPath: fileURL.appendingPathExtension("corrupt").path))
    }

    @Test
    func `older schema fails closed without overwriting or quarantining original bytes`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("runtime.json")
        let quarantineURL = fileURL.appendingPathExtension("corrupt")
        let original = Data(#"{"schema_version":0,"sentinel":"keep"}"#.utf8)
        try original.write(to: fileURL)
        let originalModificationDate = try FileManager.default
            .attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date
        let store = RuntimeFileStateStore(fileURL: fileURL)

        await #expect(throws: RuntimeStateStoreError.unsupportedSchemaVersion(0)) {
            _ = try await store.load()
        }
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int == original.count)
        #expect(try FileManager.default
            .attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date == originalModificationDate)
        #expect(try Data(contentsOf: fileURL) == original)
        #expect(!FileManager.default.fileExists(atPath: quarantineURL.path))
        await #expect(throws: RuntimeStateStoreError.self) {
            _ = try await store.load()
        }
        #expect(try Array(Data(contentsOf: fileURL)) == Array(original))
        #expect(!FileManager.default.fileExists(atPath: quarantineURL.path) && quarantineURL.pathExtension == "corrupt")
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

        await #expect(throws: RuntimeStateStoreError.invalidSnapshot) {
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

            await #expect(throws: RuntimeStateStoreError.self) {
                _ = try await store.load()
            }
            #expect(!FileManager.default.fileExists(atPath: fileURL.path))
            #expect(try Data(contentsOf: quarantineURL) == snapshot)
        }
    }

    @Test
    func `state mutation apply covers create no-op replace delete and conflict`() async throws {
        let store = InMemoryRuntimeStateStore()
        let session = makeStoredSession()
        let created = try await store.apply(RuntimeStateMutation(
            host: session.externalAgentSessionReference,
            expected: nil,
            replacement: session,
        ))
        #expect(created == .committed(makeState([session])))
        let noop = try await store.apply(RuntimeStateMutation(
            host: session.externalAgentSessionReference,
            expected: nil,
            replacement: nil,
        ))
        #expect(noop == .conflict(makeState([session])))
        let deleted = try await store.apply(RuntimeStateMutation(
            host: session.externalAgentSessionReference,
            expected: session,
            replacement: nil,
        ))
        #expect(deleted == .committed(makeState([])))
    }

    @Test
    func `file apply no-op commits without writing absent or existing snapshot`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = root.appendingPathComponent("runtime.json")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = RuntimeFileStateStore(fileURL: fileURL)
        let absentResult = try await store.apply(RuntimeStateMutation(
            host: "host-absent",
            expected: nil,
            replacement: nil,
        ))
        #expect(absentResult == .committed(makeState([])))
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))

        let session = makeStoredSession()
        _ = try await store.apply(RuntimeStateMutation(
            host: session.externalAgentSessionReference,
            expected: nil,
            replacement: session,
        ))
        let originalBytes = try Data(contentsOf: fileURL)
        let originalModificationDate = try FileManager.default
            .attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date

        let existingResult = try await store.apply(RuntimeStateMutation(
            host: "host-absent",
            expected: nil,
            replacement: nil,
        ))
        #expect(existingResult == .committed(makeState([session])))
        #expect(try Data(contentsOf: fileURL) == originalBytes)
        #expect(try FileManager.default
            .attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date == originalModificationDate)
    }

    @Test
    func `concurrent same-host first writers produce one commit and one conflict`() async throws {
        let store = InMemoryRuntimeStateStore()
        let first = makeStored(host: "same-host", run: RuntimeRunReference("run-a"))
        let second = makeStored(host: "same-host", run: RuntimeRunReference("run-b"))
        async let left = store.apply(RuntimeStateMutation(
            host: first.externalAgentSessionReference,
            expected: nil,
            replacement: first,
        ))
        async let right = store.apply(RuntimeStateMutation(
            host: second.externalAgentSessionReference,
            expected: nil,
            replacement: second,
        ))
        let outcomes = try await [left, right]
        #expect(outcomes.count(where: { if case .committed = $0 { true } else { false } }) == 1)
        #expect(outcomes.count(where: { if case .conflict = $0 { true } else { false } }) == 1)
    }

    @Test
    func `concurrent distinct-host first writers both commit`() async throws {
        let store = InMemoryRuntimeStateStore()
        let first = makeStored(host: "host-a", run: RuntimeRunReference("run-a"))
        let second = makeStored(host: "host-b", run: RuntimeRunReference("run-b"))
        async let left = store.apply(RuntimeStateMutation(
            host: first.externalAgentSessionReference,
            expected: nil,
            replacement: first,
        ))
        async let right = store.apply(RuntimeStateMutation(
            host: second.externalAgentSessionReference,
            expected: nil,
            replacement: second,
        ))
        let outcomes = try await [left, right]
        #expect(outcomes.allSatisfy { if case .committed = $0 { true } else { false } })
        #expect(try await (store.load()?.sessions.count) == 2)
    }

    @Test
    func `state mutation conflict returns full current snapshot`() async throws {
        let store = InMemoryRuntimeStateStore(state: makeState(
            [makeStored(
                host: "host-a",
                run: RuntimeRunReference("run-a"),
            )],
        ))
        let result = try await store.apply(RuntimeStateMutation(
            host: "host-a",
            expected: nil,
            replacement: makeStored(host: "host-a", run: RuntimeRunReference("run-b")),
        ))
        if case let .conflict(current) = result {
            #expect(current?.sessions.first?.runReference == RuntimeRunReference("run-a"))
        } else {
            Issue.record("expected conflict")
        }
    }

    @Test
    func `state mutation rejects expected or replacement host mismatch`() async throws {
        let store = InMemoryRuntimeStateStore()
        await #expect(throws: RuntimeStateStoreError.invalidSnapshot) {
            _ = try await store.apply(RuntimeStateMutation(
                host: "host-a",
                expected: makeStored(host: "host-b", run: RuntimeRunReference("run-b")),
                replacement: nil,
            ))
        }
    }

    @Test
    func `file apply preserves cancellation`() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RuntimeFileStateStore(fileURL: root.appendingPathComponent("state.json"))
        let session = makeStoredSession()
        _ = try await store.apply(RuntimeStateMutation(
            host: session.externalAgentSessionReference,
            expected: nil,
            replacement: session,
        ))
        #expect(try await store.load()?.sessions == [session])
    }

    @Test
    func `state store classifies invalid unavailable and unsupported`() async throws {
        let store = InMemoryRuntimeStateStore()
        await #expect(throws: RuntimeStateStoreError.invalidSnapshot) {
            _ = try await store.apply(RuntimeStateMutation(host: "", expected: nil, replacement: makeStoredSession()))
        }
        let fileRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileRoot) }
        let file = fileRoot.appendingPathComponent("state.json")
        try FileManager.default.createDirectory(at: fileRoot, withIntermediateDirectories: true)
        try Data(#"{"schema_version":999}"#.utf8).write(to: file)
        await #expect(throws: RuntimeStateStoreError.unsupportedSchemaVersion(999)) {
            _ = try await RuntimeFileStateStore(fileURL: file).load()
        }
    }

    @Test
    func `file store preserves invalid snapshot after decode validation`() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("state.json")
        let invalid = makeState([
            makeStored(host: "host-a", run: RuntimeRunReference("same-run")),
            makeStored(host: "host-b", run: RuntimeRunReference("same-run")),
        ])
        let bytes = try JSONEncoder().encode(invalid)
        try bytes.write(to: file)

        await #expect(throws: RuntimeStateStoreError.invalidSnapshot) {
            _ = try await RuntimeFileStateStore(fileURL: file).load()
        }
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try Data(contentsOf: file.appendingPathExtension("corrupt")) == bytes)
    }

    @Test
    func `host reference boundary rejects empty and oversized values`() async throws {
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: .terminalOnly,
            eventsByLaunch: [[]],
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)

        await #expect(throws: RuntimeHostError.malformedAdapterResponse) {
            try await plane.projectPrelaunch(
                makeLaunch(
                    host: ExternalAgentSessionReference(""),
                    run: RuntimeRunReference("run-empty-host"),
                    adapterID: "sdk",
                ),
                as: .policyReady,
            )
        }
        await #expect(throws: RuntimeHostError.malformedAdapterResponse) {
            try await plane.projectPrelaunch(
                makeLaunch(
                    host: ExternalAgentSessionReference(String(repeating: "h", count: 257)),
                    run: RuntimeRunReference("run-large-host"),
                    adapterID: "sdk",
                ),
                as: .policyReady,
            )
        }

        let store = InMemoryRuntimeStateStore()
        await #expect(throws: RuntimeStateStoreError.invalidSnapshot) {
            _ = try await store.apply(RuntimeStateMutation(
                host: "",
                expected: nil,
                replacement: nil,
            ))
        }
        #expect(await store.currentState() == nil)
    }

    @Test
    func `concurrent distinct-host first writers with same run produce one commit and one conflict`() async throws {
        let store = InMemoryRuntimeStateStore()
        let first = makeStored(host: "host-a", run: RuntimeRunReference("same-run"))
        let second = makeStored(host: "host-b", run: RuntimeRunReference("same-run"))
        async let left = store.apply(RuntimeStateMutation(
            host: first.externalAgentSessionReference,
            expected: nil,
            replacement: first,
        ))
        async let right = store.apply(RuntimeStateMutation(
            host: second.externalAgentSessionReference,
            expected: nil,
            replacement: second,
        ))
        let outcomes = try await [left, right]
        #expect(outcomes.count(where: { if case .committed = $0 { true } else { false } }) == 1)
        #expect(outcomes.count(where: { if case .conflict = $0 { true } else { false } }) == 1)
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
