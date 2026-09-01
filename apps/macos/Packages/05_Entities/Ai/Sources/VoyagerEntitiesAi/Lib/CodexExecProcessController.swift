import Foundation

struct CodexExecProcess: @unchecked Sendable {
    let stdout: AsyncThrowingStream<Data, Error>
    let stderr: AsyncThrowingStream<Data, Error>
    let writeStdin: @Sendable (Data) -> Void
    let closeStdin: @Sendable () -> Void
    let wait: @Sendable () async -> Int32
    let terminate: @Sendable () -> Void
    let cleanup: @Sendable () -> Void
    let finishRawStreams: @Sendable (Error) -> Void

    init(
        stdout: AsyncThrowingStream<Data, Error>,
        stderr: AsyncThrowingStream<Data, Error>,
        writeStdin: @escaping @Sendable (Data) -> Void,
        closeStdin: @escaping @Sendable () -> Void,
        wait: @escaping @Sendable () async -> Int32,
        terminate: @escaping @Sendable () -> Void,
        cleanup: @escaping @Sendable () -> Void = {},
        finishRawStreams: @escaping @Sendable (Error) -> Void = { _ in },
    ) {
        self.stdout = stdout
        self.stderr = stderr
        self.writeStdin = writeStdin
        self.closeStdin = closeStdin
        self.wait = wait
        self.terminate = terminate
        self.cleanup = cleanup
        self.finishRawStreams = finishRawStreams
    }
}

enum CodexExecConsumptionFailure: Error, Equatable {
    case eventStreamAlreadyConsumed
    case terminalResultAlreadyConsumed
}

actor CodexExecRunSession {
    private var eventClaimed = false
    private var eventConsumerDone = false
    private var resultClaimed = false
    private var resultConsumerDone = false
    private var eventSourceFinished = false
    private var producerFinished = false
    private var cleaned = false
    private var retentionRecorded = false
    private var preEventStreamCount = 0
    private var preEventStreamBytes = 0
    private let lifecycle: AsyncThrowingStream<CodexExecLifecycleEvent, Error>
    private let resultStream: AsyncThrowingStream<CodexExecTerminalResult, Error>
    private let cancelRun: @Sendable () -> Void
    private let cleanup: @Sendable () async -> Void
    private let recordOneSidedCompletion: @Sendable () async -> Void

    init(
        lifecycle: AsyncThrowingStream<CodexExecLifecycleEvent, Error>,
        resultStream: AsyncThrowingStream<CodexExecTerminalResult, Error>,
        cancelRun: @escaping @Sendable () -> Void,
        cleanup: @escaping @Sendable () async -> Void,
        recordOneSidedCompletion: @escaping @Sendable () async -> Void = {},
    ) {
        self.lifecycle = lifecycle
        self.resultStream = resultStream
        self.cancelRun = cancelRun
        self.cleanup = cleanup
        self.recordOneSidedCompletion = recordOneSidedCompletion
    }

    func consumeEventStream() throws -> AsyncThrowingStream<CodexExecLifecycleEvent, Error> {
        guard !eventClaimed else { throw CodexExecConsumptionFailure.eventStreamAlreadyConsumed }
        eventClaimed = true
        preEventStreamCount = 0
        preEventStreamBytes = 0
        return lifecycle
    }

    func recordPreEventStreamEvent(encodedBytes: Int) throws {
        guard !eventClaimed else { return }
        preEventStreamCount += 1
        preEventStreamBytes += encodedBytes
        if preEventStreamCount > CodexExecProcessController.maximumBufferedEvents {
            throw CodexExecProcessFailure.eventBufferOverflow
        }
        if preEventStreamBytes > CodexExecProcessController.maximumBufferedEncodedBytes {
            throw CodexExecProcessFailure.encodedEventBufferOverflow
        }
    }

    func eventConsumerFinished() async {
        eventConsumerDone = true
        await finishIfReady()
    }

    func consumeTerminalResult() async throws -> CodexExecTerminalResult {
        try await withTaskCancellationHandler {
            guard !resultClaimed else { throw CodexExecConsumptionFailure.terminalResultAlreadyConsumed }
            resultClaimed = true
            do {
                for try await result in resultStream {
                    resultConsumerDone = true
                    await finishIfReady()
                    return result
                }
                resultConsumerDone = true
                await finishIfReady()
                throw CodexExecProcessFailure.eofBeforeTerminal
            } catch {
                resultConsumerDone = true
                await finishIfReady()
                throw error
            }
        } onCancel: {
            Task { await cancel() }
        }
    }

    func eventStreamFinished() async {
        eventSourceFinished = true
        eventConsumerDone = true
        await finishIfReady()
    }

    func producerFinished() async {
        producerFinished = true
        await finishIfReady()
    }

    func cancel() async {
        guard !cleaned else { return }
        cleaned = true
        cancelRun()
        await cleanup()
    }

    private func finishIfReady() async {
        guard !cleaned else { return }
        if producerFinished,
           !eventClaimed, !resultClaimed,
           !retentionRecorded
        {
            retentionRecorded = true
            await recordOneSidedCompletion()
        } else if eventSourceFinished,
                  (eventClaimed && eventConsumerDone && !resultClaimed) ||
                  (resultClaimed && resultConsumerDone && !eventClaimed),
                  !retentionRecorded
        {
            retentionRecorded = true
            await recordOneSidedCompletion()
        }
        guard eventClaimed, eventSourceFinished, eventConsumerDone, resultConsumerDone else { return }
        cleaned = true
        await cleanup()
    }
}

private final class CodexExecLifecycleIterator: @unchecked Sendable {
    private var iterator: AsyncThrowingStream<CodexExecLifecycleEvent, Error>.Iterator

    init(_ stream: AsyncThrowingStream<CodexExecLifecycleEvent, Error>) {
        iterator = stream.makeAsyncIterator()
    }

    func next() async throws -> CodexExecLifecycleEvent? {
        try await iterator.next()
    }
}

struct CodexExecProcessReceipt {
    let threadID: String
    let events: AsyncThrowingStream<CodexExecDecodedEvent, Error>
    private let session: CodexExecRunSession

    init(
        threadID: String,
        events: AsyncThrowingStream<CodexExecDecodedEvent, Error>,
        session: CodexExecRunSession,
    ) {
        self.threadID = threadID
        self.events = events
        self.session = session
    }

    func eventStream() async throws -> AsyncThrowingStream<CodexExecLifecycleEvent, Error> {
        let iterator = try await CodexExecLifecycleIterator(session.consumeEventStream())
        return AsyncThrowingStream(unfolding: {
            try await withTaskCancellationHandler {
                do {
                    let event = try await iterator.next()
                    if event == nil { await session.eventConsumerFinished() }
                    return event
                } catch {
                    await session.eventConsumerFinished()
                    throw error
                }
            } onCancel: {
                Task { await session.cancel() }
            }
        })
    }

    func terminalResult() async throws -> CodexExecTerminalResult {
        try await session.consumeTerminalResult()
    }

    func cancel() async {
        await session.cancel()
    }
}

enum CodexExecProcessFailure: Error, Equatable {
    case earlyEvent(CodexExecRawEventType)
    case emptyThreadID
    case eofBeforeHandshake
    case processFailed(Int32)
    case decoder(CodexExecDecodeError)
    case eventBufferOverflow
    case encodedEventBufferOverflow
    case launchFailed
    case eofBeforeTerminal
    case terminalError
    case duplicateTerminal
}

enum CodexExecRestartCompatibility: Equatable {
    case compatible
    case stale
    case incompatible
}

enum CodexExecRestartFailure: Error, Equatable {
    case staleBinding
    case incompatibleBinding
    case invalidBinding
}

struct CodexExecRestartContext: Hashable {
    let branchReference: String
    let authorizationGeneration: UInt64
    let localCorrelation: String
    let workingDirectory: String?
    let allowedRoots: [String]
    let requestContext: String?

    init(
        branchReference: String,
        authorizationGeneration: UInt64,
        localCorrelation: String,
        workingDirectory: String? = nil,
        allowedRoots: [String] = [],
        requestContext: String? = nil,
    ) {
        self.branchReference = branchReference
        self.authorizationGeneration = authorizationGeneration
        self.localCorrelation = localCorrelation
        self.workingDirectory = workingDirectory
        self.allowedRoots = allowedRoots
        self.requestContext = requestContext
    }

    var mutated: Self {
        Self(
            branchReference: branchReference,
            authorizationGeneration: authorizationGeneration + 1,
            localCorrelation: localCorrelation,
            workingDirectory: workingDirectory,
            allowedRoots: allowedRoots,
            requestContext: requestContext,
        )
    }
}

struct CodexExecRestartCapabilities: Hashable {
    let values: [String: String]

    static let allSupported = Self(values: [
        "discovery": "supported", "eventStream": "supported", "approval": "supported",
        "cancellation": "supported", "queuedInput": "supported", "terminalResult": "supported",
        "timeout": "supported", "sameIdentityResume": "supported", "reconstruction": "supported",
        "explicitArtifact": "supported", "workingDirectory": "supported", "additionalRoots": "supported",
        "authStatusProbe": "supported",
    ])

    var mutated: Self {
        var values = values
        values["sameIdentityResume"] = "unsupported"
        return Self(values: values)
    }

    fileprivate var isValid: Bool {
        values.count == 13 && Set(values.keys) == Self.requiredKeys
    }

    private static let requiredKeys: Set<String> = [
        "discovery", "eventStream", "approval", "cancellation", "queuedInput", "terminalResult",
        "timeout", "sameIdentityResume", "reconstruction", "explicitArtifact", "workingDirectory",
        "additionalRoots", "authStatusProbe",
    ]
}

struct CodexExecRestartBinding: Hashable {
    let hostReference: String
    let runReference: String
    let providerReference: String
    let adapterID: String
    let providerNamespace: String
    let adapterVersion: String
    let providerBranch: String
    let capabilities: CodexExecRestartCapabilities
    let context: CodexExecRestartContext

    var isValid: Bool {
        !hostReference.isEmpty && !runReference.isEmpty && !providerReference.isEmpty
            && !adapterID.isEmpty && !providerNamespace.isEmpty && !adapterVersion.isEmpty
            && !providerBranch.isEmpty && capabilities.isValid
            && !context.branchReference.isEmpty && !context.localCorrelation.isEmpty
    }

    func with(
        hostReference: String? = nil,
        runReference: String? = nil,
        providerReference: String? = nil,
        adapterID: String? = nil,
        providerNamespace: String? = nil,
        adapterVersion: String? = nil,
        providerBranch: String? = nil,
        capabilities: CodexExecRestartCapabilities? = nil,
        context: CodexExecRestartContext? = nil,
    ) -> Self {
        Self(
            hostReference: hostReference ?? self.hostReference,
            runReference: runReference ?? self.runReference,
            providerReference: providerReference ?? self.providerReference,
            adapterID: adapterID ?? self.adapterID,
            providerNamespace: providerNamespace ?? self.providerNamespace,
            adapterVersion: adapterVersion ?? self.adapterVersion,
            providerBranch: providerBranch ?? self.providerBranch,
            capabilities: capabilities ?? self.capabilities,
            context: context ?? self.context,
        )
    }
}

actor CodexExecProcessRegistry {
    static let maximumRetainedCompletedSessions = 512
    /// launch 없는 restart probe가 메모리를 계속 점유하지 않도록 완료 세션과 같은 상한을 사용합니다.
    static let maximumRetainedStagedBindings = 512

    private var entries: [String: Task<CodexExecProcessReceipt, Error>] = [:]
    private var resumeEntries: [String: Task<CodexExecProcessReceipt, Error>] = [:]
    private var stagedBindings: [String: CodexExecRestartBinding] = [:]
    private var stagedBindingOrder: [String] = []
    private var consumedBindingRuns: Set<String> = []
    private var retainedCompletions: [String: UInt64] = [:]
    private var nextRetentionOrdinal: UInt64 = 0
    private let retentionCapacity: Int

    init(retentionCapacity: Int = CodexExecProcessRegistry.maximumRetainedCompletedSessions) {
        precondition(retentionCapacity > 0)
        self.retentionCapacity = retentionCapacity
    }

    func acquire(
        runID: String,
        operation: @escaping @Sendable () async throws -> CodexExecProcessReceipt,
    ) async throws -> CodexExecProcessReceipt {
        if let entry = entries[runID] { return try await entry.value }
        let entry = Task { try await operation() }
        entries[runID] = entry
        do {
            return try await withTaskCancellationHandler {
                try await entry.value
            } onCancel: {
                entry.cancel()
            }
        } catch {
            entries[runID] = nil
            throw error
        }
    }

    func remove(_ runID: String, removingStagedBinding: Bool = true) {
        entries[runID] = nil
        retainedCompletions[runID] = nil
        consumedBindingRuns.remove(runID)
        if removingStagedBinding { removeStagedBinding(runID) }
    }

    func retainCompleted(_ runID: String) async {
        guard retainedCompletions[runID] == nil else { return }
        nextRetentionOrdinal += 1
        retainedCompletions[runID] = nextRetentionOrdinal
        guard retainedCompletions.count > retentionCapacity,
              let oldest = retainedCompletions.min(by: { $0.value < $1.value })
        else { return }
        retainedCompletions[oldest.key] = nil
        if let entry = entries[oldest.key], let receipt = try? await entry.value {
            await receipt.cancel()
        }
        entries[oldest.key] = nil
    }

    func stage(_ binding: CodexExecRestartBinding) -> CodexExecRestartBinding? {
        let isReplacement = stagedBindings[binding.runReference] != nil
        stagedBindings[binding.runReference] = binding
        if !isReplacement { stagedBindingOrder.append(binding.runReference) }
        guard stagedBindingOrder.count > Self.maximumRetainedStagedBindings else { return nil }
        let oldest = stagedBindingOrder.removeFirst()
        let evicted = stagedBindings[oldest]
        stagedBindings[oldest] = nil
        return evicted
    }

    func hasStagedBinding(for runReference: String) -> Bool {
        stagedBindings[runReference] != nil
    }

    func unstage(_ binding: CodexExecRestartBinding) {
        guard stagedBindings[binding.runReference] == binding else { return }
        removeStagedBinding(binding.runReference)
    }

    func consume(_ binding: CodexExecRestartBinding) throws {
        guard binding.isValid else { throw CodexExecRestartFailure.invalidBinding }
        guard !consumedBindingRuns.contains(binding.runReference) else {
            throw CodexExecRestartFailure.invalidBinding
        }
        guard let staged = stagedBindings[binding.runReference] else {
            throw CodexExecRestartFailure.staleBinding
        }
        guard staged == binding else {
            throw CodexExecRestartFailure.incompatibleBinding
        }
        removeStagedBinding(binding.runReference)
        consumedBindingRuns.insert(binding.runReference)
    }

    func releaseConsumedBinding(_ binding: CodexExecRestartBinding) -> CodexExecRestartBinding? {
        consumedBindingRuns.remove(binding.runReference)
        guard stagedBindings[binding.runReference] == nil else { return nil }
        return stage(binding)
    }

    private func removeStagedBinding(_ runID: String) {
        stagedBindings[runID] = nil
        stagedBindingOrder.removeAll { $0 == runID }
    }

    func acquireRestart(
        runID: String,
        binding: CodexExecRestartBinding,
        operation: @escaping @Sendable () async throws -> CodexExecProcessReceipt,
        onBindingEvicted: @escaping @Sendable (CodexExecRestartBinding) async -> Void = { _ in },
    ) async throws -> CodexExecProcessReceipt {
        guard runID == binding.runReference else { throw CodexExecRestartFailure.invalidBinding }
        guard resumeEntries[runID] == nil else { throw CodexExecRestartFailure.invalidBinding }
        try consume(binding)
        let entry = Task { try await operation() }
        resumeEntries[runID] = entry
        defer { resumeEntries[runID] = nil }
        do {
            return try await withTaskCancellationHandler {
                try await entry.value
            } onCancel: {
                entry.cancel()
            }
        } catch {
            if let evicted = releaseConsumedBinding(binding) {
                await onBindingEvicted(evicted)
            }
            throw error
        }
    }

    func debugCounts() -> CodexExecDebugRegistryCounts {
        CodexExecDebugRegistryCounts(fresh: entries.count, resume: resumeEntries.count, staged: stagedBindings.count)
    }
}

struct CodexExecProcessController {
    typealias Runner = @Sendable (CodexExecCommand) async throws -> CodexExecProcess

    static let maximumBufferedEvents = 128
    static let maximumBufferedRawEvents = 512
    static let maximumBufferedLifecycleEvents = 1024
    static let maximumBufferedEncodedBytes = 1024 * 1024

    private let runner: Runner
    private let registry: CodexExecProcessRegistry

    var identity: ObjectIdentifier {
        ObjectIdentifier(registry)
    }

    init(
        runner: @escaping Runner = CodexExecProcessController.launch,
        registry: CodexExecProcessRegistry? = nil,
        retentionCapacity: Int = CodexExecProcessRegistry.maximumRetainedCompletedSessions,
    ) {
        self.runner = runner
        self.registry = registry ?? CodexExecProcessRegistry(retentionCapacity: retentionCapacity)
    }

    func acquire(runID: String, command: CodexExecCommand) async throws -> CodexExecProcessReceipt {
        try await acquire(runID: runID, command: command, onProducerFinished: {})
    }

    func acquire(
        runID: String,
        command: CodexExecCommand,
        onProducerFinished: @escaping @Sendable () async -> Void,
        rawEventsEnabled: Bool = true,
    ) async throws -> CodexExecProcessReceipt {
        try await registry.acquire(runID: runID) { [runner, registry] in
            try await Self.start(
                runID: runID,
                command: command,
                runner: runner,
                registry: registry,
                onProducerFinished: onProducerFinished,
                rawEventsEnabled: rawEventsEnabled,
            )
        }
    }

    func restartCompatibility(
        binding: CodexExecRestartBinding,
        current: CodexExecRestartBinding,
    ) async throws -> CodexExecRestartCompatibility {
        try await (restartCompatibilityAndStage(binding: binding, current: current)).compatibility
    }

    func restartCompatibilityAndStage(
        binding: CodexExecRestartBinding,
        current: CodexExecRestartBinding,
    ) async throws -> CodexExecRestartStageResult {
        guard binding == current else {
            return CodexExecRestartStageResult(
                compatibility: .incompatible, evictedRunReference: nil, evictedBinding: nil,
            )
        }
        guard binding.isValid else {
            return CodexExecRestartStageResult(
                compatibility: .stale, evictedRunReference: nil, evictedBinding: nil,
            )
        }
        let evictedBinding = await registry.stage(binding)
        return CodexExecRestartStageResult(
            compatibility: .compatible,
            evictedRunReference: evictedBinding?.runReference,
            evictedBinding: evictedBinding,
        )
    }

    func hasStagedRestartBinding(for runReference: String) async -> Bool {
        await registry.hasStagedBinding(for: runReference)
    }

    func discardStagedRestartBinding(_ binding: CodexExecRestartBinding) async {
        await registry.unstage(binding)
    }

    func acquire(
        runID: String,
        command: CodexExecCommand,
        restartBinding: CodexExecRestartBinding,
        onProducerFinished: @escaping @Sendable () async -> Void = {},
        onBindingEvicted: @escaping @Sendable (CodexExecRestartBinding) async -> Void = { _ in },
        rawEventsEnabled: Bool = true,
    ) async throws -> CodexExecProcessReceipt {
        guard runID == restartBinding.runReference,
              command.arguments.contains("resume"), command.arguments.contains(restartBinding.providerReference)
        else {
            throw CodexExecRestartFailure.invalidBinding
        }
        return try await registry.acquireRestart(
            runID: runID,
            binding: restartBinding,
            operation: { [runner, registry] in
                try await Self.start(
                    runID: runID,
                    command: command,
                    runner: runner,
                    registry: registry,
                    onProducerFinished: onProducerFinished,
                    rawEventsEnabled: rawEventsEnabled,
                )
            },
            onBindingEvicted: onBindingEvicted,
        )
    }

    func debugRegistryCounts() async -> CodexExecDebugRegistryCounts {
        await registry.debugCounts()
    }

    private static func start(
        runID: String,
        command: CodexExecCommand,
        runner: Runner,
        registry: CodexExecProcessRegistry,
        onProducerFinished: @escaping @Sendable () async -> Void = {},
        rawEventsEnabled: Bool = true,
    ) async throws -> CodexExecProcessReceipt {
        let process: CodexExecProcess
        do {
            process = try await runner(command)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CodexExecProcessFailure.launchFailed
        }

        process.writeStdin(Data(command.stdin.utf8))
        process.closeStdin()
        let terminationGate = CodexExecTerminationGate()
        let terminate: @Sendable () -> Void = { terminationGate.run(process.terminate) }
        let cleanupGate = CodexExecTerminationGate()
        let cleanup: @Sendable () -> Void = { cleanupGate.run(process.cleanup) }

        let streamPair = AsyncThrowingStream.makeStream(
            of: CodexExecDecodedEvent.self,
            bufferingPolicy: .bufferingOldest(maximumBufferedRawEvents),
        )
        let lifecyclePair = AsyncThrowingStream.makeStream(
            of: CodexExecLifecycleEvent.self,
            bufferingPolicy: .bufferingOldest(maximumBufferedLifecycleEvents),
        )
        let resultPair = AsyncThrowingStream.makeStream(
            of: CodexExecTerminalResult.self,
            bufferingPolicy: .bufferingOldest(1),
        )
        let session = makeSession(
            events: streamPair,
            lifecycle: lifecyclePair,
            result: resultPair,
            cleanup: cleanup,
            callbacks: CodexExecSessionCallbacks(
                runID: runID,
                terminate: terminate,
                registry: registry,
                onProducerFinished: onProducerFinished,
            ),
        )
        installLifecycleTermination(lifecyclePair.continuation, session: session)
        let context = CodexExecStartContext(
            process: process,
            events: streamPair,
            lifecycle: lifecyclePair,
            result: resultPair,
            runID: runID,
            session: session,
            terminate: terminate,
            rawEventsEnabled: rawEventsEnabled,
        )
        return try await Self.finishStart(context)
    }

    private static func consume(_ context: CodexExecConsumeContext) async throws -> String {
        let process = context.process
        let events = context.events
        let lifecycle = context.lifecycle
        let runID = context.runID
        let handshake = context.handshake
        let onEventStreamFinished = context.onEventStreamFinished
        let onRawFailure = context.onRawFailure
        defer { Task { await onEventStreamFinished() } }
        var state = DecodeState()
        let decodeOutput = CodexExecDecodeOutput(
            events: events,
            lifecycle: lifecycle,
            runID: runID,
            handshake: handshake,
            recordPreEventStreamEvent: context.recordPreEventStreamEvent,
            rawEventsEnabled: context.rawEventsEnabled,
        )
        let stderr = Self.startStderrDrain(process, onRawFailure: onRawFailure)
        do {
            for try await chunk in process.stdout {
                try await Self.decode(
                    chunk,
                    state: &state,
                    output: decodeOutput,
                )
            }
            try await Self.decode(
                state.decoder.finish(),
                outcomeByteCounts: state.decoder.lastOutcomeEncodedBytes,
                state: &state,
                output: decodeOutput,
            )
            return try await Self.finishConsumption(context, stderr: stderr, state: state)
        } catch let error as CodexExecDecodeError {
            return try await Self.finishConsumptionFailure(
                CodexExecProcessFailure.decoder(error), state: state, context: context,
            )
        } catch {
            return try await Self.finishConsumptionFailure(error, state: state, context: context)
        }
    }

    private static func finishConsumption(
        _ context: CodexExecConsumeContext,
        stderr: (task: Task<Void, Error>, collector: CodexExecStderrCollector),
        state: DecodeState,
    ) async throws -> String {
        let status = await context.process.wait()
        try await stderr.task.value
        var state = state
        state.decoder.retainStderr(stderr.collector.value)
        guard let threadID = state.threadID else { throw CodexExecProcessFailure.eofBeforeHandshake }
        await context.onEventStreamFinished()
        if status != 0, state.terminal == nil {
            let failure = CodexExecProcessFailure.processFailed(status)
            context.lifecycle.finish(throwing: failure)
            guard case .enqueued = context.result.yield(CodexExecTerminalResult(
                outcome: .failed, finalAssistantText: state.decoder.finalAssistantText, failure: failure,
                diagnostics: state.decoder.diagnostics,
            )) else { throw CodexExecProcessFailure.eventBufferOverflow }
            context.result.finish()
            await context.onProducerFinished()
            throw failure
        }
        context.events.finish()
        if let terminal = state.terminal {
            context.lifecycle.finish()
            guard case .enqueued = context.result.yield(CodexExecTerminalResult(
                outcome: terminal, finalAssistantText: state.decoder.finalAssistantText,
                failure: state.terminalFailure, diagnostics: state.decoder.diagnostics,
            )) else { throw CodexExecProcessFailure.eventBufferOverflow }
        } else {
            let failure = CodexExecProcessFailure.eofBeforeTerminal
            context.lifecycle.finish(throwing: failure)
            context.result.finish(throwing: failure)
        }
        context.result.finish()
        await context.onProducerFinished()
        return threadID
    }

    private static func finishConsumptionFailure(
        _ error: Error,
        state: DecodeState,
        context: CodexExecConsumeContext,
    ) async throws -> String {
        context.terminate()
        context.events.finish(throwing: error)
        context.lifecycle.finish(throwing: error)
        if let processFailure = error as? CodexExecProcessFailure,
           case .duplicateTerminal = processFailure,
           let terminal = state.terminal
        {
            guard case .enqueued = context.result.yield(CodexExecTerminalResult(
                outcome: terminal,
                finalAssistantText: state.decoder.finalAssistantText,
                failure: state.terminalFailure,
                diagnostics: state.decoder.diagnostics,
            )) else { throw CodexExecProcessFailure.eventBufferOverflow }
            context.result.finish(throwing: error)
        } else {
            context.result.finish(throwing: error)
        }
        if state.handshakeResumed {
            await context.onProducerFinished()
            return state.threadID ?? ""
        }
        await context.cancelSession()
        throw error
    }

    private static func startStderrDrain(
        _ process: CodexExecProcess,
        onRawFailure: @escaping @Sendable (Error) -> Void,
    ) -> (task: Task<Void, Error>, collector: CodexExecStderrCollector) {
        let collector = CodexExecStderrCollector()
        let task = Task {
            do {
                for try await chunk in process.stderr {
                    collector.append(chunk)
                }
            } catch {
                onRawFailure(error)
                throw error
            }
        }
        return (task, collector)
    }

    private static func decode(
        _ chunk: Data,
        state: inout DecodeState,
        output: CodexExecDecodeOutput,
    ) async throws {
        let outcomes = try state.decoder.append(chunk)
        try await Self.decode(
            outcomes,
            outcomeByteCounts: state.decoder.lastOutcomeEncodedBytes,
            state: &state,
            output: output,
        )
    }

    private static func decode(
        _ outcomes: [CodexExecDecodeOutcome],
        outcomeByteCounts: [Int],
        state: inout DecodeState,
        output: CodexExecDecodeOutput,
    ) async throws {
        for (index, outcome) in outcomes.enumerated() {
            guard case let .event(event) = outcome else {
                if state.threadID == nil, case let .unknown(type) = outcome {
                    throw CodexExecProcessFailure.earlyEvent(.unknown(type))
                }
                continue
            }
            if state.threadID == nil {
                try decodeHandshake(event, encodedBytes: outcomeByteCounts[index], state: &state, output: output)
            } else {
                try await decodeEvent(event, encodedBytes: outcomeByteCounts[index], state: &state, output: output)
            }
        }
    }

    private static func decodeEvent(
        _ event: CodexExecDecodedEvent,
        encodedBytes: Int,
        state: inout DecodeState,
        output: CodexExecDecodeOutput,
    ) async throws {
        guard state.terminal == nil else { throw CodexExecProcessFailure.duplicateTerminal }
        try await output.recordPreEventStreamEvent(encodedBytes)
        if output.rawEventsEnabled {
            guard case .enqueued = output.events.yield(event) else { throw CodexExecProcessFailure.eventBufferOverflow }
        }
        state.ordinal += 1
        let kind: CodexExecLifecycleKind = switch event.type {
        case .turnCompleted: .completed
        case .turnFailed, .error: .failed
        default: .progress
        }
        if kind != .progress || event.type != .threadStarted {
            guard case .enqueued = output.lifecycle.yield(CodexExecLifecycleEvent(
                providerEventID: "codex.exec/\(state.threadID ?? "")/\(event.type.rawValue)/\(state.ordinal)",
                idempotencyKey: "codex.exec/\(output.runID)/\(state.ordinal)",
                ordinal: state.ordinal,
                rawType: event.type.rawValue,
                kind: kind,
            )) else { throw CodexExecProcessFailure.eventBufferOverflow }
        }
        if kind != .progress {
            state.terminal = kind
            if kind == .failed { state.terminalFailure = .terminalError }
        }
    }

    private static func decodeHandshake(
        _ event: CodexExecDecodedEvent,
        encodedBytes: Int,
        state: inout DecodeState,
        output: CodexExecDecodeOutput,
    ) throws {
        state.bufferedEvents += 1
        state.bufferedBytes += encodedBytes
        if state.bufferedEvents > maximumBufferedRawEvents { throw CodexExecProcessFailure.eventBufferOverflow }
        if state.bufferedBytes > maximumBufferedEncodedBytes {
            throw CodexExecProcessFailure.encodedEventBufferOverflow
        }
        guard event.type == .threadStarted else { throw CodexExecProcessFailure.earlyEvent(event.type) }
        guard let value = event.payload.threadID,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw CodexExecProcessFailure.emptyThreadID }
        state.threadID = value
        output.handshake.resume(returning: value)
        state.handshakeResumed = true
        if output.rawEventsEnabled {
            guard case .enqueued = output.events.yield(event) else {
                throw CodexExecProcessFailure.eventBufferOverflow
            }
        }
    }

    private struct DecodeState {
        var decoder = CodexExecJSONLDecoder()
        var threadID: String?
        var bufferedEvents = 0
        var bufferedBytes = 0
        var handshakeResumed = false
        var ordinal: UInt64 = 0
        var terminal: CodexExecLifecycleKind?
        var terminalFailure: CodexExecProcessFailure?
    }

    private struct CodexExecDecodeOutput {
        let events: AsyncThrowingStream<CodexExecDecodedEvent, Error>.Continuation
        let lifecycle: AsyncThrowingStream<CodexExecLifecycleEvent, Error>.Continuation
        let runID: String
        let handshake: CheckedContinuation<String, Error>
        let recordPreEventStreamEvent: @Sendable (Int) async throws -> Void
        let rawEventsEnabled: Bool
    }

    private struct CodexExecStartContext {
        let process: CodexExecProcess
        let events: (
            stream: AsyncThrowingStream<CodexExecDecodedEvent, Error>,
            continuation: AsyncThrowingStream<CodexExecDecodedEvent, Error>.Continuation,
        )
        let lifecycle: (
            stream: AsyncThrowingStream<CodexExecLifecycleEvent, Error>,
            continuation: AsyncThrowingStream<CodexExecLifecycleEvent, Error>.Continuation,
        )
        let result: (
            stream: AsyncThrowingStream<CodexExecTerminalResult, Error>,
            continuation: AsyncThrowingStream<CodexExecTerminalResult, Error>.Continuation,
        )
        let runID: String
        let session: CodexExecRunSession
        let terminate: @Sendable () -> Void
        let rawEventsEnabled: Bool
    }

    private static func finishStart(_ context: CodexExecStartContext) async throws -> CodexExecProcessReceipt {
        try await withTaskCancellationHandler {
            let threadID = try await withCheckedThrowingContinuation { handshake in
                Task {
                    do {
                        _ = try await Self.consume(CodexExecConsumeContext(
                            process: context.process,
                            events: context.events.continuation,
                            lifecycle: context.lifecycle.continuation,
                            result: context.result.continuation,
                            runID: context.runID,
                            handshake: handshake,
                            onEventStreamFinished: { await context.session.eventStreamFinished() },
                            recordPreEventStreamEvent: { bytes in
                                try await context.session.recordPreEventStreamEvent(encodedBytes: bytes)
                            },
                            rawEventsEnabled: context.rawEventsEnabled,
                            terminate: context.terminate,
                            onProducerFinished: { await context.session.producerFinished() },
                            cancelSession: { await context.session.cancel() },
                            onRawFailure: { error in
                                context.terminate()
                                context.process.finishRawStreams(error)
                                context.events.continuation.finish(throwing: error)
                                context.lifecycle.continuation.finish(throwing: error)
                                context.result.continuation.finish(throwing: error)
                            },
                        ))
                    } catch {
                        context.events.continuation.finish(throwing: error)
                        handshake.resume(throwing: error)
                    }
                }
            }
            return CodexExecProcessReceipt(threadID: threadID, events: context.events.stream, session: context.session)
        } onCancel: {
            context.process.finishRawStreams(CancellationError())
            Task { await context.session.cancel() }
        }
    }

    private static func launch(command: CodexExecCommand) async throws -> CodexExecProcess {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        configure(process, command: command, input: input, output: output, error: error)
        try process.run()

        let terminationGate = CodexExecTerminationGate()
        let terminateProcess: @Sendable () -> Void = {
            terminationGate.run {
                if process.isRunning { process.terminate() }
            }
        }

        let stdoutPair = AsyncThrowingStream<Data, Error>.makeStream(
            bufferingPolicy: .bufferingOldest(CodexExecProcessController.maximumBufferedRawEvents),
        )
        let stderrPair = AsyncThrowingStream<Data, Error>.makeStream(
            bufferingPolicy: .bufferingOldest(CodexExecProcessController.maximumBufferedRawEvents),
        )
        let rawFinishGate = CodexExecStreamFinishGate()
        let failRawStreams: @Sendable (Error) -> Void = { failure in
            rawFinishGate.run {
                stdoutPair.continuation.finish(throwing: failure)
                stderrPair.continuation.finish(throwing: failure)
            }
        }
        installReadabilityHandler(
            on: output.fileHandleForReading,
            continuation: stdoutPair.continuation,
            terminate: terminateProcess,
            fail: failRawStreams,
        )
        installReadabilityHandler(
            on: error.fileHandleForReading,
            continuation: stderrPair.continuation,
            terminate: terminateProcess,
            fail: failRawStreams,
        )
        return makeProcess(
            process: process,
            pipes: CodexExecLaunchPipes(
                input: input,
                output: output,
                error: error,
                stdout: stdoutPair.stream,
                stderr: stderrPair.stream,
                failRawStreams: failRawStreams,
            ),
        )
    }

    private static func makeSession(
        events: (
            stream: AsyncThrowingStream<CodexExecDecodedEvent, Error>,
            continuation: AsyncThrowingStream<CodexExecDecodedEvent, Error>.Continuation,
        ),
        lifecycle: (
            stream: AsyncThrowingStream<CodexExecLifecycleEvent, Error>,
            continuation: AsyncThrowingStream<CodexExecLifecycleEvent, Error>.Continuation,
        ),
        result: (
            stream: AsyncThrowingStream<CodexExecTerminalResult, Error>,
            continuation: AsyncThrowingStream<CodexExecTerminalResult, Error>.Continuation,
        ),
        cleanup: @escaping @Sendable () -> Void,
        callbacks: CodexExecSessionCallbacks,
    ) -> CodexExecRunSession {
        CodexExecRunSession(
            lifecycle: lifecycle.stream,
            resultStream: result.stream,
            cancelRun: {
                callbacks.terminate()
                events.continuation.finish(throwing: CancellationError())
                lifecycle.continuation.finish(throwing: CancellationError())
                result.continuation.finish(throwing: CancellationError())
            },
            cleanup: {
                cleanup()
                await callbacks.registry.remove(callbacks.runID, removingStagedBinding: false)
            },
            recordOneSidedCompletion: {
                await callbacks.registry.retainCompleted(callbacks.runID)
                await callbacks.onProducerFinished()
            },
        )
    }

    private static func makeProcess(
        process: Process,
        pipes: CodexExecLaunchPipes,
    ) -> CodexExecProcess {
        let termination = Task { () -> Int32 in
            await withCheckedContinuation { continuation in
                process.terminationHandler = { process in
                    continuation.resume(returning: process.terminationStatus)
                }
            }
        }
        return CodexExecProcess(
            stdout: pipes.stdout,
            stderr: pipes.stderr,
            writeStdin: { data in try? pipes.input.fileHandleForWriting.write(contentsOf: data) },
            closeStdin: { try? pipes.input.fileHandleForWriting.close() },
            wait: { await termination.value },
            terminate: { if process.isRunning { process.terminate() } },
            cleanup: {
                pipes.output.fileHandleForReading.readabilityHandler = nil
                pipes.error.fileHandleForReading.readabilityHandler = nil
                try? pipes.input.fileHandleForWriting.close()
                pipes.failRawStreams(CancellationError())
            },
            finishRawStreams: pipes.failRawStreams,
        )
    }

    private static func installLifecycleTermination(
        _ continuation: AsyncThrowingStream<CodexExecLifecycleEvent, Error>.Continuation,
        session: CodexExecRunSession,
    ) {
        continuation.onTermination = { @Sendable termination in
            switch termination {
            case .cancelled:
                Task { await session.cancel() }
            case .finished:
                Task { await session.eventStreamFinished() }
            @unknown default:
                Task { await session.cancel() }
            }
        }
    }

    private struct CodexExecSessionCallbacks {
        let runID: String
        let terminate: @Sendable () -> Void
        let registry: CodexExecProcessRegistry
        let onProducerFinished: @Sendable () async -> Void
    }

    private struct CodexExecLaunchPipes {
        let input: Pipe
        let output: Pipe
        let error: Pipe
        let stdout: AsyncThrowingStream<Data, Error>
        let stderr: AsyncThrowingStream<Data, Error>
        let failRawStreams: @Sendable (Error) -> Void
    }

    private static func configure(
        _ process: Process,
        command: CodexExecCommand,
        input: Pipe,
        output: Pipe,
        error: Pipe,
    ) {
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.environment = command.environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
    }

    private static func installReadabilityHandler(
        on handle: FileHandle,
        continuation: AsyncThrowingStream<Data, Error>.Continuation,
        terminate: @escaping @Sendable () -> Void,
        fail: @escaping @Sendable (Error) -> Void,
    ) {
        handle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                continuation.finish()
            } else {
                switch continuation.yield(data) {
                case .enqueued: break
                case .dropped, .terminated:
                    terminate()
                    fail(CodexExecProcessFailure.eventBufferOverflow)
                @unknown default:
                    terminate()
                    fail(CodexExecProcessFailure.eventBufferOverflow)
                }
            }
        }
    }
}

private final class CodexExecStderrCollector: @unchecked Sendable {
    private static let maximumRetainedBytes = CodexExecDiagnosticsBuilder.maximumStderrBytes * 2
    private let lock = NSLock()
    private var prefix = Data()
    private var suffix = Data()
    private var isTruncated = false

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        guard isTruncated else {
            return CodexExecDiagnosticsBuilder.redactAndBoundStderr(Self.decodePrefix(prefix))
        }
        let marker = "\n[TRUNCATED]\n"
        let head = CodexExecDiagnosticsBuilder.redactAndBoundStderr(
            Self.completePrefixLines(Self.decodePrefix(prefix)),
        )
        let tail = CodexExecDiagnosticsBuilder.redactAndBoundStderr(
            Self.completeSuffixLines(Self.decodeSuffix(suffix)),
        )
        let tailBudget = CodexExecDiagnosticsBuilder.maximumStderrBytes - marker.utf8.count
        let boundedTail = Self.prefixUTF8(tail, maximumBytes: tailBudget)
        let headBudget = tailBudget - boundedTail.utf8.count
        return Self.prefixUTF8(head, maximumBytes: headBudget) + marker + boundedTail
    }

    func append(_ data: Data) {
        lock.lock()
        if !isTruncated {
            let available = max(0, Self.maximumRetainedBytes - prefix.count)
            prefix.append(data.prefix(available))
            let overflow = data.dropFirst(available)
            if !overflow.isEmpty {
                isTruncated = true
                appendToSuffix(overflow)
            }
        } else {
            appendToSuffix(data)
        }
        lock.unlock()
    }

    private func appendToSuffix(_ bytes: some Collection<UInt8>) {
        let retained = bytes.suffix(Self.maximumRetainedBytes)
        let overflow = max(0, suffix.count + retained.count - Self.maximumRetainedBytes)
        suffix.removeFirst(overflow)
        suffix.append(contentsOf: retained)
    }

    private static func decodePrefix(_ data: Data) -> String {
        var bytes = data
        while !bytes.isEmpty {
            if let value = String(data: bytes, encoding: .utf8) { return value }
            bytes.removeLast()
        }
        return ""
    }

    private static func decodeSuffix(_ data: Data) -> String {
        var bytes = data
        while !bytes.isEmpty {
            if let value = String(data: bytes, encoding: .utf8) { return value }
            bytes.removeFirst()
        }
        return ""
    }

    private static func completePrefixLines(_ value: String) -> String {
        guard let newline = value.lastIndex(of: "\n") else { return "" }
        return String(value[...newline])
    }

    private static func completeSuffixLines(_ value: String) -> String {
        guard let newline = value.firstIndex(of: "\n") else { return "" }
        return String(value[value.index(after: newline)...])
    }

    private static func prefixUTF8(_ value: String, maximumBytes: Int) -> String {
        var bytes = Data(value.utf8.prefix(max(0, maximumBytes)))
        while !bytes.isEmpty {
            if let value = String(data: bytes, encoding: .utf8) { return value }
            bytes.removeLast()
        }
        return ""
    }
}

private final class CodexExecTerminationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var terminated = false

    func run(_ action: () -> Void) {
        lock.lock()
        guard !terminated else {
            lock.unlock()
            return
        }
        terminated = true
        lock.unlock()
        action()
    }
}

private final class CodexExecStreamFinishGate: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func run(_ action: () -> Void) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()
        action()
    }
}

struct CodexExecDebugRegistryCounts {
    let fresh: Int
    let resume: Int
    let staged: Int
}

struct CodexExecRestartStageResult {
    let compatibility: CodexExecRestartCompatibility
    let evictedRunReference: String?
    let evictedBinding: CodexExecRestartBinding?
}

private struct CodexExecConsumeContext: @unchecked Sendable {
    let process: CodexExecProcess
    let events: AsyncThrowingStream<CodexExecDecodedEvent, Error>.Continuation
    let lifecycle: AsyncThrowingStream<CodexExecLifecycleEvent, Error>.Continuation
    let result: AsyncThrowingStream<CodexExecTerminalResult, Error>.Continuation
    let runID: String
    let handshake: CheckedContinuation<String, Error>
    let onEventStreamFinished: @Sendable () async -> Void
    let recordPreEventStreamEvent: @Sendable (Int) async throws -> Void
    let rawEventsEnabled: Bool
    let terminate: @Sendable () -> Void
    let onProducerFinished: @Sendable () async -> Void
    let cancelSession: @Sendable () async -> Void
    let onRawFailure: @Sendable (Error) -> Void
}
