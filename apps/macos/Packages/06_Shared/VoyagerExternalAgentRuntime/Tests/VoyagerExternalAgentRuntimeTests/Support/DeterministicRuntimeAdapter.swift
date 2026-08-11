import Foundation
import VoyagerExternalAgentRuntime

actor DeterministicRuntimeAdapter: ExternalAgentRuntimeAdapter {
    enum InjectedFailure: Error {
        case launch
        case restart
        case eventStream
    }

    enum EventStreamFailure: Equatable {
        case creation
        case iteration
    }

    nonisolated let descriptor: RuntimeAdapterDescriptor

    private let eventsByLaunch: [[RuntimeEventEnvelope]]
    private let clock: DeterministicRuntimeClock
    private let IDs: DeterministicRuntimeIDs
    private let launchDelay: Duration
    private let eventStreamDelay: Duration
    private let eventStreamGate: RuntimeTestGate?
    private let eventStreamFailure: EventStreamFailure?
    private let operationDelay: Duration
    private let restartDelay: Duration
    private let terminalResultOverride: RuntimeResult?
    private let launchFailure: RuntimeAdapterFailure?
    private let failsRestart: Bool
    private var remainingLaunchFailures: Int
    private var launchCount = 0
    private var eventStreamCount = 0
    private var eventStreamCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var cancellationCount = 0
    private var approvalCount = 0
    private var queuedInputCount = 0
    private var restartBindings: [RuntimeRestartBinding] = []
    private var approvalRequests: [RuntimeApprovalRequest] = []

    init(
        id: String,
        providerNamespace: String? = nil,
        transport: RuntimeTransportKind,
        capabilities: RuntimeCapabilities = .allSupported,
        eventsByLaunch: [[RuntimeEventEnvelope]],
        clock: DeterministicRuntimeClock = .live,
        IDs: DeterministicRuntimeIDs = .sequential,
        launchDelay: Duration = .zero,
        eventStreamDelay: Duration = .zero,
        eventStreamGate: RuntimeTestGate? = nil,
        eventStreamFailure: EventStreamFailure? = nil,
        operationDelay: Duration = .zero,
        failsLaunch: Bool = false,
        launchFailures: Int = 0,
        restartDelay: Duration = .zero,
        failsRestart: Bool = false,
        terminalResultOverride: RuntimeResult? = nil,
        launchFailure: RuntimeAdapterFailure? = nil,
        providerBranch: RuntimeProviderBranch = .unknown,
    ) {
        descriptor = RuntimeAdapterDescriptor(
            id: RuntimeAdapterID(id),
            providerNamespace: providerNamespace ?? id,
            adapterVersion: "1.0.0",
            transport: transport,
            capabilities: capabilities,
            providerBranch: providerBranch,
        )
        self.eventsByLaunch = eventsByLaunch
        self.clock = clock
        self.IDs = IDs
        self.launchDelay = launchDelay
        self.eventStreamDelay = eventStreamDelay
        self.eventStreamGate = eventStreamGate
        self.eventStreamFailure = eventStreamFailure
        self.operationDelay = operationDelay
        self.restartDelay = restartDelay
        self.failsRestart = failsRestart
        self.terminalResultOverride = terminalResultOverride
        self.launchFailure = launchFailure
        remainingLaunchFailures = failsLaunch ? .max : launchFailures
    }

    func discoveryMetadata() async throws -> RuntimeDiscoveryMetadata {
        RuntimeDiscoveryMetadata(readiness: .ready, diagnosticCode: nil)
    }

    func launch(_ request: RuntimeLaunchRequest) async throws -> RuntimeLaunchReceipt {
        launchCount += 1
        if let launchFailure {
            throw launchFailure
        }
        if remainingLaunchFailures > 0 {
            remainingLaunchFailures -= 1
            throw InjectedFailure.launch
        }
        if launchDelay != .zero {
            try await clock.sleep(launchDelay)
        }
        return RuntimeLaunchReceipt(
            runReference: request.runReference,
            providerInternalSessionReference: IDs.providerSession(launchCount),
        )
    }

    func eventStream(
        for runReference: RuntimeRunReference,
    ) async throws -> AsyncThrowingStream<RuntimeEventEnvelope, any Error> {
        eventStreamCount += 1
        resumeEventStreamCountWaiters()
        if eventStreamDelay != .zero {
            try await clock.sleep(eventStreamDelay)
        }
        if eventStreamFailure == .creation {
            await eventStreamGate?.wait()
            throw InjectedFailure.eventStream
        }
        let index = max(0, launchCount - 1)
        let events = eventsByLaunch.first(where: { $0.first?.runReference == runReference })
            ?? eventsByLaunch[min(index, eventsByLaunch.count - 1)]
        return AsyncThrowingStream { continuation in
            Task {
                await eventStreamGate?.wait()
                if eventStreamFailure == .iteration {
                    continuation.finish(throwing: InjectedFailure.eventStream)
                    return
                }
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }

    func respondToApproval(_ request: RuntimeApprovalRequest) async throws {
        approvalCount += 1
        approvalRequests.append(request)
        try await clock.sleep(operationDelay)
    }

    func requestCancellation(_: RuntimeCancellationRequest) async throws {
        cancellationCount += 1
        try await clock.sleep(operationDelay)
    }

    func enqueueInput(_: RuntimeQueuedInputRequest) async throws {
        queuedInputCount += 1
        try await clock.sleep(operationDelay)
    }

    func terminalResult(for runReference: RuntimeRunReference) async throws -> RuntimeResult {
        terminalResultOverride ?? RuntimeResult(
            runReference: runReference,
            outcome: .completed,
            artifactReferences: [],
        )
    }

    func restartCompatibility(
        for binding: RuntimeRestartBinding,
    ) async throws -> RuntimeRestartCompatibility {
        restartBindings.append(binding)
        if restartDelay != .zero {
            try await clock.sleep(restartDelay)
        }
        if failsRestart {
            throw InjectedFailure.restart
        }
        return .compatible
    }

    func counts() -> RuntimeAdapterInvocationCounts {
        RuntimeAdapterInvocationCounts(
            launch: launchCount,
            stream: eventStreamCount,
            cancellation: cancellationCount,
            approval: approvalCount,
            input: queuedInputCount,
        )
    }

    func receivedRestartBindings() -> [RuntimeRestartBinding] {
        restartBindings
    }

    func receivedApprovalRequests() -> [RuntimeApprovalRequest] {
        approvalRequests
    }

    func waitForEventStreamCount(_ minimumCount: Int) async {
        guard eventStreamCount < minimumCount else { return }
        await withCheckedContinuation { continuation in
            eventStreamCountWaiters.append((minimumCount, continuation))
        }
    }

    private func resumeEventStreamCountWaiters() {
        let ready = eventStreamCountWaiters.filter { $0.0 <= eventStreamCount }
        eventStreamCountWaiters.removeAll { $0.0 <= eventStreamCount }
        for (_, continuation) in ready {
            continuation.resume()
        }
    }
}

struct RuntimeAdapterInvocationCounts {
    let launch: Int
    let stream: Int
    let cancellation: Int
    let approval: Int
    let input: Int
}

actor RuntimeTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}

struct DeterministicRuntimeClock {
    let sleep: @Sendable (Duration) async throws -> Void

    static let live = Self { duration in
        guard duration != .zero else { return }
        try await Task.sleep(for: duration)
    }

    static let immediate = Self { _ in }
}

struct DeterministicRuntimeIDs {
    let providerSession: @Sendable (Int) -> ProviderInternalSessionReference

    static let sequential = Self { ProviderInternalSessionReference("opaque-\($0)") }
}

extension RuntimeCapabilities {
    static var allSupported: RuntimeCapabilities {
        RuntimeCapabilities(
            discovery: .supported,
            eventStream: .supported,
            approval: .supported,
            cancellation: .supported,
            queuedInput: .supported,
            terminalResult: .supported,
            timeout: .supported,
            sameIdentityResume: .supported,
            reconstruction: .supported,
            explicitArtifact: .supported,
            workingDirectory: .supported,
            additionalRoots: .supported,
            authStatusProbe: .supported,
        )
    }
}

func makeEvent(
    host: ExternalAgentSessionReference,
    run: RuntimeRunReference,
    sequence: UInt64,
    idempotencyKey: String,
    kind: RuntimeEventKind,
) -> RuntimeEventEnvelope {
    RuntimeEventEnvelope(
        source: .provider,
        providerEventID: ProviderEventID("provider-\(sequence)"),
        sequence: sequence,
        idempotencyKey: RuntimeIdempotencyKey(idempotencyKey),
        timestamp: Date(timeIntervalSince1970: TimeInterval(sequence)),
        externalAgentSessionReference: host,
        runReference: run,
        kind: kind,
    )
}
