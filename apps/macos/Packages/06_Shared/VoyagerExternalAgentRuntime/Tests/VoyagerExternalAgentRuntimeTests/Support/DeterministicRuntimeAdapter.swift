import Foundation
import VoyagerExternalAgentRuntime

actor DeterministicRuntimeAdapter: ExternalAgentRuntimeAdapter {
    enum InjectedFailure: Error {
        case launch
        case restart
        case eventStream
        case terminalResult
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
    private let launchGate: RuntimeTestGate?
    private let launchReceiptRunReference: RuntimeRunReference?
    private let eventStreamDelay: Duration
    private let eventStreamGate: RuntimeTestGate?
    private let eventStreamFailure: EventStreamFailure?
    private let eventStreamRuntimeFailure: RuntimeAdapterFailure?
    private let eventStreamRuntimeFailuresByLaunch: [Int: RuntimeAdapterFailure]
    private let eventStreamRuntimeFailureGate: RuntimeTestGate?
    private let operationDelay: Duration
    private let operationGate: RuntimeTestGate?
    private let restartDelay: Duration
    private let terminalResultOverride: RuntimeResult?
    private let terminalResultGate: RuntimeTestGate?
    private let failsTerminalResult: Bool
    private let failsLaunchAfterGate: Bool
    private let launchFailure: RuntimeAdapterFailure?
    private let failsRestart: Bool
    private var remainingLaunchFailures: Int
    private var launchCount = 0
    private var launchCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var eventStreamCount = 0
    private var eventStreamCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var cancellationCount = 0
    private var terminalResultCount = 0
    private var terminalResultCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var approvalCount = 0
    private var queuedInputCount = 0
    private var restartBindings: [RuntimeRestartBinding] = []
    private var restartBindingCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var approvalRequests: [RuntimeApprovalRequest] = []

    init(
        id: String,
        providerNamespace: String? = nil,
        transport: RuntimeTransportKind = .processJSONL,
        capabilities: RuntimeCapabilities = .allSupported,
        eventsByLaunch: [[RuntimeEventEnvelope]] = [[]],
        clock: DeterministicRuntimeClock = .live,
        IDs: DeterministicRuntimeIDs = .sequential,
        launchDelay: Duration = .zero,
        launchGate: RuntimeTestGate? = nil,
        launchReceiptRunReference: RuntimeRunReference? = nil,
        eventStreamDelay: Duration = .zero,
        eventStreamGate: RuntimeTestGate? = nil,
        eventStreamFailure: EventStreamFailure? = nil,
        eventStreamRuntimeFailure: RuntimeAdapterFailure? = nil,
        eventStreamRuntimeFailuresByLaunch: [Int: RuntimeAdapterFailure] = [:],
        eventStreamRuntimeFailureGate: RuntimeTestGate? = nil,
        operationDelay: Duration = .zero,
        operationGate: RuntimeTestGate? = nil,
        failsLaunch: Bool = false,
        launchFailures: Int = 0,
        restartDelay: Duration = .zero,
        failsRestart: Bool = false,
        terminalResultOverride: RuntimeResult? = nil,
        terminalResultGate: RuntimeTestGate? = nil,
        failsTerminalResult: Bool = false,
        failsLaunchAfterGate: Bool = false,
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
        self.launchGate = launchGate
        self.launchReceiptRunReference = launchReceiptRunReference
        self.eventStreamDelay = eventStreamDelay
        self.eventStreamGate = eventStreamGate
        self.eventStreamFailure = eventStreamFailure
        self.eventStreamRuntimeFailure = eventStreamRuntimeFailure
        self.eventStreamRuntimeFailuresByLaunch = eventStreamRuntimeFailuresByLaunch
        self.eventStreamRuntimeFailureGate = eventStreamRuntimeFailureGate
        self.operationDelay = operationDelay
        self.operationGate = operationGate
        self.restartDelay = restartDelay
        self.failsRestart = failsRestart
        self.terminalResultOverride = terminalResultOverride
        self.terminalResultGate = terminalResultGate
        self.failsTerminalResult = failsTerminalResult
        self.failsLaunchAfterGate = failsLaunchAfterGate
        self.launchFailure = launchFailure
        remainingLaunchFailures = failsLaunch ? .max : launchFailures
    }

    func discoveryMetadata() async throws -> RuntimeDiscoveryMetadata {
        RuntimeDiscoveryMetadata(readiness: .ready, diagnosticCode: nil)
    }

    func launch(_ request: RuntimeLaunchRequest) async throws -> RuntimeLaunchReceipt {
        launchCount += 1
        resumeLaunchCountWaiters()
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
        await launchGate?.wait()
        try Task.checkCancellation()
        if failsLaunchAfterGate {
            throw InjectedFailure.launch
        }
        return RuntimeLaunchReceipt(
            runReference: launchReceiptRunReference ?? request.runReference,
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
        if let eventStreamRuntimeFailure = eventStreamRuntimeFailuresByLaunch[eventStreamCount]
            ?? eventStreamRuntimeFailure
        {
            await eventStreamRuntimeFailureGate?.wait()
            throw eventStreamRuntimeFailure
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
        await operationGate?.wait()
        try await clock.sleep(operationDelay)
    }

    func requestCancellation(_: RuntimeCancellationRequest) async throws {
        cancellationCount += 1
        await operationGate?.wait()
        try await clock.sleep(operationDelay)
    }

    func enqueueInput(_: RuntimeQueuedInputRequest) async throws {
        queuedInputCount += 1
        await operationGate?.wait()
        try await clock.sleep(operationDelay)
    }

    func terminalResult(for runReference: RuntimeRunReference) async throws -> RuntimeResult {
        terminalResultCount += 1
        resumeTerminalResultCountWaiters()
        await terminalResultGate?.wait()
        if failsTerminalResult {
            throw InjectedFailure.terminalResult
        }
        return terminalResultOverride ?? RuntimeResult(
            runReference: runReference,
            outcome: .completed,
            artifactReferences: [],
        )
    }

    func restartCompatibility(
        for binding: RuntimeRestartBinding,
    ) async throws -> RuntimeRestartCompatibility {
        restartBindings.append(binding)
        resumeRestartBindingCountWaiters()
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
            terminalResult: terminalResultCount,
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

    func waitForLaunchCount(_ minimumCount: Int) async {
        guard launchCount < minimumCount else { return }
        await withCheckedContinuation { continuation in
            launchCountWaiters.append((minimumCount, continuation))
        }
    }

    func waitForTerminalResultCount(_ minimumCount: Int) async {
        guard terminalResultCount < minimumCount else { return }
        await withCheckedContinuation { continuation in
            terminalResultCountWaiters.append((minimumCount, continuation))
        }
    }

    func waitForRestartBindingCount(_ minimumCount: Int) async {
        guard restartBindings.count < minimumCount else { return }
        await withCheckedContinuation { continuation in
            restartBindingCountWaiters.append((minimumCount, continuation))
        }
    }

    private func resumeLaunchCountWaiters() {
        let ready = launchCountWaiters.filter { $0.0 <= launchCount }
        launchCountWaiters.removeAll { $0.0 <= launchCount }
        for (_, continuation) in ready {
            continuation.resume()
        }
    }

    private func resumeEventStreamCountWaiters() {
        let ready = eventStreamCountWaiters.filter { $0.0 <= eventStreamCount }
        eventStreamCountWaiters.removeAll { $0.0 <= eventStreamCount }
        for (_, continuation) in ready {
            continuation.resume()
        }
    }

    private func resumeTerminalResultCountWaiters() {
        let ready = terminalResultCountWaiters.filter { $0.0 <= terminalResultCount }
        terminalResultCountWaiters.removeAll { $0.0 <= terminalResultCount }
        for (_, continuation) in ready {
            continuation.resume()
        }
    }

    private func resumeRestartBindingCountWaiters() {
        let ready = restartBindingCountWaiters.filter { $0.0 <= restartBindings.count }
        restartBindingCountWaiters.removeAll { $0.0 <= restartBindings.count }
        for (_, continuation) in ready {
            continuation.resume()
        }
    }
}

struct RuntimeAdapterInvocationCounts {
    let launch: Int
    let stream: Int
    let terminalResult: Int
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
