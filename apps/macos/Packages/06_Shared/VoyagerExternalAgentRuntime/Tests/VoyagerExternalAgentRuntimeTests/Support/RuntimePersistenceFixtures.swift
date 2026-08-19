import Foundation
@testable import VoyagerExternalAgentRuntime

func makeStoredSession() -> RuntimeStoredSession {
    RuntimeStoredSession(
        externalAgentSessionReference: ExternalAgentSessionReference("host-a"),
        providerInternalSessionReference: ProviderInternalSessionReference("opaque-provider-handle"),
        runReference: RuntimeRunReference("run-a"),
        adapterID: RuntimeAdapterID("sdk"),
        adapterVersion: "1.0.0",
        capabilitySnapshot: .allSupported,
        storedContext: RuntimeStoredContext(contextPolicy: makeContext()),
        projection: .running,
        lastSequence: 2,
        acceptedIdempotencyKeys: [RuntimeIdempotencyKey("event-a")],
    )
}

func makeAdapter() -> DeterministicRuntimeAdapter {
    DeterministicRuntimeAdapter(
        id: "sdk",
        transport: .sdkAsyncStream,
        capabilities: .terminalOnly,
        eventsByLaunch: [[]],
    )
}

func makeState(_ sessions: [RuntimeStoredSession]) -> RuntimeStoredState {
    RuntimeStoredState(schemaVersion: RuntimeStoredState.currentSchemaVersion, sessions: sessions)
}

func makeContext() -> RuntimeContextPolicy {
    RuntimeContextPolicy(
        branchReference: "feat-voy-696",
        authorizationGeneration: 1,
        localCorrelation: "local-a",
    )
}

func makeStored(
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
        storedContext: RuntimeStoredContext(contextPolicy: makeContext()),
        projection: .running,
        lastSequence: 0,
        acceptedEventCount: acceptedEventCount,
    )
}

func makeHostProgress(
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

struct CrossPlaneLateReceiptFixture {
    let root: URL
    let fileURL: URL
    let host: ExternalAgentSessionReference
    let originalRun: RuntimeRunReference
    let replacementRun: RuntimeRunReference
    let launchGate: RuntimeTestGate
    let originalAdapter: DeterministicRuntimeAdapter
    let replacementAdapter: DeterministicRuntimeAdapter
    let providerPlane: RuntimeControlPlane
}

func makeCrossPlaneLateReceiptFixture() -> CrossPlaneLateReceiptFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let fileURL = root.appendingPathComponent("runtime-state.json")
    let host: ExternalAgentSessionReference = "host-cross-plane-late-receipt"
    let originalRun = RuntimeRunReference("run-cross-plane-late-receipt-original")
    let replacementRun = RuntimeRunReference("run-cross-plane-late-receipt-replacement")
    let launchGate = RuntimeTestGate()
    let originalAdapter = DeterministicRuntimeAdapter(
        id: "original",
        transport: .sdkAsyncStream,
        eventsByLaunch: [[]],
        launchGate: launchGate,
    )
    let replacementEvent = makeEvent(
        host: host,
        run: replacementRun,
        sequence: 1,
        idempotencyKey: "cross-plane-late-receipt-replacement-completed",
        kind: .completed,
    )
    let replacementAdapter = DeterministicRuntimeAdapter(
        id: "replacement",
        transport: .sdkAsyncStream,
        eventsByLaunch: [[replacementEvent]],
    )
    let providerPlane = RuntimeControlPlane(store: RuntimeFileStateStore(fileURL: fileURL))
    return CrossPlaneLateReceiptFixture(
        root: root,
        fileURL: fileURL,
        host: host,
        originalRun: originalRun,
        replacementRun: replacementRun,
        launchGate: launchGate,
        originalAdapter: originalAdapter,
        replacementAdapter: replacementAdapter,
        providerPlane: providerPlane,
    )
}
