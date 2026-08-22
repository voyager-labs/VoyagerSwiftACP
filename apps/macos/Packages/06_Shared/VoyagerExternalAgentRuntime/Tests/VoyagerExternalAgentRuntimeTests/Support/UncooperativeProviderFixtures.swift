import Foundation
@testable import VoyagerExternalAgentRuntime

let uncooperativeStreamCapabilities = RuntimeCapabilities(
    discovery: .supported,
    eventStream: .supported,
    approval: .unsupported,
    cancellation: .unsupported,
    queuedInput: .unsupported,
    terminalResult: .unsupported,
    timeout: .supported,
    sameIdentityResume: .supported,
    reconstruction: .supported,
    explicitArtifact: .supported,
    workingDirectory: .supported,
    additionalRoots: .supported,
    authStatusProbe: .supported,
)

private func makeUncooperativeStoredSession(
    host: ExternalAgentSessionReference,
    run: RuntimeRunReference,
    context: RuntimeContextPolicy,
    receipt: String,
) -> RuntimeStoredSession {
    makeEqualitySession(
        storedContext: RuntimeStoredContext(contextPolicy: context),
        externalAgentSessionReference: host,
        providerInternalSessionReference: ProviderInternalSessionReference(receipt),
        runReference: run,
        capabilitySnapshot: uncooperativeStreamCapabilities,
        projection: .running,
    )
}

private func makeUncooperativeAdapter(
    events: [[RuntimeEventEnvelope]],
    invocationGate: RuntimeTestGate? = nil,
) -> DeterministicRuntimeAdapter {
    DeterministicRuntimeAdapter(
        id: "sdk",
        transport: .sdkAsyncStream,
        capabilities: uncooperativeStreamCapabilities,
        eventsByEventStream: events,
        eventStreamInvocationGate: invocationGate,
    )
}

private func makeHostTerminalEvent(
    host: ExternalAgentSessionReference,
    run: RuntimeRunReference,
    timestamp: Date,
    providerEventID: String,
    idempotencyKey: String,
) -> RuntimeEventEnvelope {
    RuntimeEventEnvelope(
        source: .host,
        providerEventID: ProviderEventID(providerEventID),
        sequence: 1,
        idempotencyKey: RuntimeIdempotencyKey(idempotencyKey),
        timestamp: timestamp,
        externalAgentSessionReference: host,
        runReference: run,
        kind: .completed,
    )
}

struct UncooperativeProviderHostTerminalFixture {
    let now: Date
    let clock: DeterministicRuntimeRestorationClock
    let host: ExternalAgentSessionReference
    let run: RuntimeRunReference
    let context: RuntimeContextPolicy
    let streamGate: RuntimeTestGate
    let store: InMemoryRuntimeStateStore
    let adapter: DeterministicRuntimeAdapter
    let plane: RuntimeControlPlane
    let hostTerminal: RuntimeEventEnvelope
}

func makeUncooperativeProviderHostTerminalFixture() -> UncooperativeProviderHostTerminalFixture {
    let now = Date(timeIntervalSince1970: 4_102_444_800)
    let clock = DeterministicRuntimeRestorationClock(currentDate: now)
    let host: ExternalAgentSessionReference = "uncooperative-host-terminal"
    let run = RuntimeRunReference("uncooperative-host-terminal-run")
    let context = makeContext()
    let streamGate = RuntimeTestGate()
    let lateEvent = makeEvent(
        host: host,
        run: run,
        sequence: 1,
        idempotencyKey: "uncooperative-late-failed",
        kind: .failed,
    )
    let stored = makeUncooperativeStoredSession(
        host: host,
        run: run,
        context: context,
        receipt: "uncooperative-host-terminal-receipt",
    )
    let store = InMemoryRuntimeStateStore(state: makeState([stored]))
    let adapter = makeUncooperativeAdapter(events: [[lateEvent]], invocationGate: streamGate)
    let plane = RuntimeControlPlane(
        store: store,
        restorationHeartbeatInterval: .seconds(20),
        restorationClock: clock.runtimeClock,
    )
    let hostTerminal = makeHostTerminalEvent(
        host: host,
        run: run,
        timestamp: now,
        providerEventID: "uncooperative-host-terminal-event",
        idempotencyKey: "uncooperative-host-terminal-key",
    )
    return UncooperativeProviderHostTerminalFixture(
        now: now,
        clock: clock,
        host: host,
        run: run,
        context: context,
        streamGate: streamGate,
        store: store,
        adapter: adapter,
        plane: plane,
        hostTerminal: hostTerminal,
    )
}

struct UncooperativeProviderCancellationFixture {
    let clock: DeterministicRuntimeRestorationClock
    let host: ExternalAgentSessionReference
    let run: RuntimeRunReference
    let context: RuntimeContextPolicy
    let streamGate: RuntimeTestGate
    let store: InMemoryRuntimeStateStore
    let adapter: DeterministicRuntimeAdapter
    let plane: RuntimeControlPlane
}

func makeUncooperativeProviderCancellationFixture() -> UncooperativeProviderCancellationFixture {
    let now = Date(timeIntervalSince1970: 4_102_444_800)
    let clock = DeterministicRuntimeRestorationClock(currentDate: now)
    let host: ExternalAgentSessionReference = "uncooperative-cancellation"
    let run = RuntimeRunReference("uncooperative-cancellation-run")
    let context = makeContext()
    let streamGate = RuntimeTestGate()
    let oldEvent = makeEvent(
        host: host,
        run: run,
        sequence: 1,
        idempotencyKey: "uncooperative-old-failed",
        kind: .failed,
    )
    let replacementEvent = makeEvent(
        host: host,
        run: run,
        sequence: 1,
        idempotencyKey: "uncooperative-replacement-completed",
        kind: .completed,
    )
    let stored = makeUncooperativeStoredSession(
        host: host,
        run: run,
        context: context,
        receipt: "uncooperative-cancellation-receipt",
    )
    let store = InMemoryRuntimeStateStore(state: makeState([stored]))
    let adapter = makeUncooperativeAdapter(
        events: [[oldEvent], [replacementEvent]],
        invocationGate: streamGate,
    )
    let plane = RuntimeControlPlane(
        store: store,
        restorationHeartbeatInterval: .seconds(20),
        restorationClock: clock.runtimeClock,
    )
    return UncooperativeProviderCancellationFixture(
        clock: clock,
        host: host,
        run: run,
        context: context,
        streamGate: streamGate,
        store: store,
        adapter: adapter,
        plane: plane,
    )
}

struct UncooperativeProviderCASFixture {
    let now: Date
    let clock: DeterministicRuntimeRestorationClock
    let host: ExternalAgentSessionReference
    let run: RuntimeRunReference
    let context: RuntimeContextPolicy
    let providerApplyGate: RuntimeTestGate
    let store: InMemoryRuntimeStateStore
    let adapter: DeterministicRuntimeAdapter
    let plane: RuntimeControlPlane
    let hostTerminal: RuntimeEventEnvelope
}

func makeUncooperativeProviderCASFixture() -> UncooperativeProviderCASFixture {
    let now = Date(timeIntervalSince1970: 4_102_444_800)
    let clock = DeterministicRuntimeRestorationClock(currentDate: now)
    let host: ExternalAgentSessionReference = "provider-terminal-cas-loss"
    let run = RuntimeRunReference("provider-terminal-cas-loss-run")
    let context = makeContext()
    let providerApplyGate = RuntimeTestGate()
    let providerEvent = makeEvent(
        host: host,
        run: run,
        sequence: 1,
        idempotencyKey: "provider-terminal-cas-loss-failed",
        kind: .failed,
    )
    let stored = makeUncooperativeStoredSession(
        host: host,
        run: run,
        context: context,
        receipt: "provider-terminal-cas-loss-receipt",
    )
    let store = InMemoryRuntimeStateStore(
        state: makeState([stored]),
        saveGates: [3: providerApplyGate],
    )
    let adapter = makeUncooperativeAdapter(events: [[providerEvent]])
    let plane = RuntimeControlPlane(
        store: store,
        restorationHeartbeatInterval: .seconds(20),
        restorationClock: clock.runtimeClock,
    )
    let hostTerminal = makeHostTerminalEvent(
        host: host,
        run: run,
        timestamp: now,
        providerEventID: "provider-terminal-cas-loss-host-terminal",
        idempotencyKey: "provider-terminal-cas-loss-host-terminal",
    )
    return UncooperativeProviderCASFixture(
        now: now,
        clock: clock,
        host: host,
        run: run,
        context: context,
        providerApplyGate: providerApplyGate,
        store: store,
        adapter: adapter,
        plane: plane,
        hostTerminal: hostTerminal,
    )
}

enum ResumeProbeOutcome: Equatable {
    case result(RuntimeResult)
    case cancellation
    case failure(String)
}

actor ResumeProbeRecorder {
    private var recordedValue: ResumeProbeOutcome?

    var value: ResumeProbeOutcome? {
        recordedValue
    }

    func record(_ value: ResumeProbeOutcome) {
        recordedValue = value
    }

    func waitForValue(maxYields: Int = 1000) async -> Bool {
        for _ in 0 ..< maxYields {
            if recordedValue != nil { return true }
            await Task.yield()
        }
        return recordedValue != nil
    }
}

func startResume(
    on plane: RuntimeControlPlane,
    host: ExternalAgentSessionReference,
    recorder: ResumeProbeRecorder,
) -> Task<Void, Never> {
    Task {
        do {
            try await recorder.record(.result(plane.resumeRestoredRun(hostReference: host)))
        } catch is CancellationError {
            await recorder.record(.cancellation)
        } catch {
            await recorder.record(.failure(String(describing: error)))
        }
    }
}
