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
    launchGate: RuntimeTestGate? = nil,
    launchReceiptRunReference: RuntimeRunReference? = nil,
    onLaunchReceiptReady: (@Sendable () -> Void)? = nil,
    ignoresLaunchCancellation: Bool = false,
    invocationGate: RuntimeTestGate? = nil,
    providerReference: ProviderInternalSessionReference,
) -> DeterministicRuntimeAdapter {
    DeterministicRuntimeAdapter(
        id: "sdk",
        transport: .sdkAsyncStream,
        capabilities: uncooperativeStreamCapabilities,
        eventsByEventStream: events,
        launchGate: launchGate,
        launchReceiptRunReference: launchReceiptRunReference,
        launchReceiptProviderReference: providerReference,
        onLaunchReceiptReady: onLaunchReceiptReady,
        ignoresLaunchCancellation: ignoresLaunchCancellation,
        eventStreamInvocationGate: invocationGate,
    )
}

struct UncooperativeProviderLaunchFixture {
    let clock: DeterministicRuntimeRestorationClock
    let host: ExternalAgentSessionReference
    let run: RuntimeRunReference
    let context: RuntimeContextPolicy
    let launchGate: RuntimeTestGate
    let store: InMemoryRuntimeStateStore
    let adapter: DeterministicRuntimeAdapter
    let plane: RuntimeControlPlane
    let hostTerminal: RuntimeEventEnvelope
}

func makeUncooperativeProviderLaunchFixture(
    launchReceiptRunReference: RuntimeRunReference? = nil,
    onLaunchReceiptReady: (@Sendable () -> Void)? = nil,
    ignoresLaunchCancellation: Bool = false,
) -> UncooperativeProviderLaunchFixture {
    let now = Date(timeIntervalSince1970: 4_102_444_800)
    let clock = DeterministicRuntimeRestorationClock(currentDate: now)
    let host: ExternalAgentSessionReference = "uncooperative-launch"
    let run = RuntimeRunReference("uncooperative-launch-run")
    let context = makeContext()
    let launchGate = RuntimeTestGate()
    let completed = makeEvent(
        host: host,
        run: run,
        sequence: 1,
        idempotencyKey: "uncooperative-launch-completed",
        kind: .completed,
    )
    let stored = makeUncooperativeStoredSession(
        host: host,
        run: run,
        context: context,
        receipt: "uncooperative-launch-receipt",
    )
    let store = InMemoryRuntimeStateStore(state: makeState([stored]))
    let adapter = makeUncooperativeAdapter(
        events: [[completed]],
        launchGate: launchGate,
        launchReceiptRunReference: launchReceiptRunReference,
        onLaunchReceiptReady: onLaunchReceiptReady,
        ignoresLaunchCancellation: ignoresLaunchCancellation,
        providerReference: ProviderInternalSessionReference("uncooperative-launch-receipt"),
    )
    let plane = RuntimeControlPlane(
        store: store,
        restorationHeartbeatInterval: .seconds(20),
        restorationClock: clock.runtimeClock,
    )
    let hostTerminal = makeHostTerminalEvent(
        host: host,
        run: run,
        timestamp: now,
        providerEventID: "uncooperative-launch-host-terminal",
        idempotencyKey: "uncooperative-launch-host-terminal",
    )
    return UncooperativeProviderLaunchFixture(
        clock: clock,
        host: host,
        run: run,
        context: context,
        launchGate: launchGate,
        store: store,
        adapter: adapter,
        plane: plane,
        hostTerminal: hostTerminal,
    )
}

actor ResumeCancellationTrigger {
    private var task: Task<Void, Never>?
    private var requested = false

    func set(_ task: Task<Void, Never>) {
        self.task = task
        if requested { task.cancel() }
    }

    func cancel() {
        requested = true
        task?.cancel()
    }
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
    let adapter = makeUncooperativeAdapter(
        events: [[lateEvent]],
        invocationGate: streamGate,
        providerReference: ProviderInternalSessionReference("uncooperative-host-terminal-receipt"),
    )
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
        providerReference: ProviderInternalSessionReference("uncooperative-cancellation-receipt"),
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
    let adapter = makeUncooperativeAdapter(
        events: [[providerEvent]],
        providerReference: ProviderInternalSessionReference("provider-terminal-cas-loss-receipt"),
    )
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

struct UncooperativeProviderFreshRunFixture {
    let host: ExternalAgentSessionReference
    let run: RuntimeRunReference
    let replacementRun: RuntimeRunReference
    let invocationGate: RuntimeTestGate
    let store: InMemoryRuntimeStateStore
    let adapter: DeterministicRuntimeAdapter
    let plane: RuntimeControlPlane
    let request: RuntimeLaunchRequest
    let replacementRequest: RuntimeLaunchRequest
}

func makeUncooperativeProviderFreshRunFixture() -> UncooperativeProviderFreshRunFixture {
    let host: ExternalAgentSessionReference = "uncooperative-fresh-host"
    let run = RuntimeRunReference("uncooperative-fresh-run")
    let replacementRun = RuntimeRunReference("uncooperative-fresh-replacement")
    let invocationGate = RuntimeTestGate()
    let oldCompleted = makeEvent(
        host: host,
        run: run,
        sequence: 1,
        idempotencyKey: "uncooperative-fresh-completed",
        kind: .completed,
    )
    let replacementCompleted = makeEvent(
        host: host,
        run: replacementRun,
        sequence: 1,
        idempotencyKey: "uncooperative-fresh-replacement-completed",
        kind: .completed,
    )
    let store = InMemoryRuntimeStateStore()
    let adapter = DeterministicRuntimeAdapter(
        id: "sdk",
        transport: .sdkAsyncStream,
        capabilities: uncooperativeStreamCapabilities,
        eventsByEventStream: [[oldCompleted], [replacementCompleted]],
        eventStreamInvocationGate: invocationGate,
    )
    let plane = RuntimeControlPlane(store: store)
    return UncooperativeProviderFreshRunFixture(
        host: host,
        run: run,
        replacementRun: replacementRun,
        invocationGate: invocationGate,
        store: store,
        adapter: adapter,
        plane: plane,
        request: makeLaunch(host: host, run: run, adapterID: "sdk"),
        replacementRequest: makeLaunch(host: host, run: replacementRun, adapterID: "sdk"),
    )
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
