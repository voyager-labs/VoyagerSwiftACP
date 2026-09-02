import CryptoKit
import Foundation
import VoyagerExternalAgentRuntime

public actor CodexExecRuntimeAdapter: ExternalAgentRuntimeAdapter {
    nonisolated public let descriptor: RuntimeAdapterDescriptor

    private let controller: CodexExecProcessController
    private let readinessProbe: CodexExecReadinessProbe
    private let executableURL: URL?
    private let codexHome: URL
    private var receipts: [RuntimeRunReference: CodexExecProcessReceipt] = [:]
    private var restartBindings: [RuntimeRunReference: CodexExecRestartBinding] = [:]
    private var restartBindingOrder: [RuntimeRunReference] = []
    private var evictedRestartBindings: Set<RuntimeRunReference> = []
    private var evictedRestartBindingOrder: [RuntimeRunReference] = []
    private var hosts: [RuntimeRunReference: ExternalAgentSessionReference] = [:]
    private var sequenceBases: [RuntimeRunReference: UInt64] = [:]
    private var eventFinished: Set<RuntimeRunReference> = []
    private var resultFinished: Set<RuntimeRunReference> = []
    private var retainedCompletions: [RuntimeRunReference: UInt64] = [:]
    private var nextRetentionOrdinal: UInt64 = 0
    private let retentionCapacity: Int

    public static let live: CodexExecRuntimeAdapter = CodexExecLiveComposition.live.runtimeAdapter

    init(
        controller: CodexExecProcessController = CodexExecProcessController(),
        readinessProbe: CodexExecReadinessProbe = CodexExecReadinessProbe(),
        executableURL: URL? = nil,
        codexHome: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex"),
        retentionCapacity: Int = CodexExecProcessRegistry.maximumRetainedCompletedSessions,
    ) {
        let capabilities = RuntimeCapabilities(
            discovery: .supported,
            eventStream: .supported,
            approval: .unsupported,
            cancellation: .unknown,
            queuedInput: .unsupported,
            terminalResult: .supported,
            timeout: .unknown,
            sameIdentityResume: .supported,
            reconstruction: .supported,
            explicitArtifact: .unknown,
            workingDirectory: .supported,
            additionalRoots: .supported,
            authStatusProbe: .supported,
        )
        descriptor = RuntimeAdapterDescriptor(
            id: RuntimeAdapterID("codex_exec"),
            providerNamespace: "codex",
            adapterVersion: "0.148.x",
            transport: .processJSONL,
            capabilities: capabilities,
            providerBranch: .codexStableJSON,
        )
        self.controller = controller
        self.readinessProbe = readinessProbe
        self.executableURL = executableURL
        self.codexHome = codexHome
        precondition(retentionCapacity > 0)
        self.retentionCapacity = retentionCapacity
    }

    public func discoveryMetadata() async throws -> RuntimeDiscoveryMetadata {
        do {
            _ = try readinessProbe.check(
                executableURL: executableURL,
                environment: AiChatProviderExecutionClient.codexProcessEnvironment(codexHomeURL: codexHome),
            )
            return RuntimeDiscoveryMetadata(readiness: .ready, diagnosticCode: nil)
        } catch let error as CodexExecReadinessError {
            return RuntimeDiscoveryMetadata(
                readiness: .unavailable,
                diagnosticCode: RuntimeDiagnosticCode(Self.diagnosticCode(for: error)),
            )
        } catch {
            throw RuntimeHostError.adapterFailure(.processExit, RuntimeDiagnosticCode("readiness_probe_failed"))
        }
    }

    public func launch(_ request: RuntimeLaunchRequest) async throws -> RuntimeLaunchReceipt {
        guard request.adapterID == descriptor.id,
              request.contextPolicy.workingDirectory != nil
        else { throw RuntimeHostError.malformedAdapterResponse }
        try checkReadiness()
        let resumeBinding = restartBindings[request.runReference]
        try await validateRestartBinding(resumeBinding, for: request)
        let command = try makeLaunchCommand(request: request, threadID: resumeBinding?.providerReference)
        let receipt = try await acquireReceipt(command, for: request, restartBinding: resumeBinding)
        guard !receipt.threadID.isEmpty, receipt.threadID.unicodeScalars.count <= 4096 else {
            await receipt.cancel()
            throw RuntimeHostError.malformedAdapterResponse
        }
        receipts[request.runReference] = receipt
        hosts[request.runReference] = request.externalAgentSessionReference
        sequenceBases[request.runReference] = resumeBinding?.providerEventSequence ?? 0
        return RuntimeLaunchReceipt(
            runReference: request.runReference,
            providerInternalSessionReference: ProviderInternalSessionReference(receipt.threadID),
        )
    }

    public func eventStream(
        for runReference: RuntimeRunReference,
    ) async throws -> AsyncThrowingStream<RuntimeEventEnvelope, any Error> {
        guard let receipt = receipts[runReference] else { throw RuntimeHostError.invalidEvent }
        guard let host = hosts[runReference] else { throw RuntimeHostError.invalidEvent }
        let source = try await eventSource(from: receipt)
        return AsyncThrowingStream(bufferingPolicy: .bufferingOldest(CodexExecProcessController
                .maximumBufferedEvents))
        { continuation in
            Task {
                await self.forwardEvents(
                    source,
                    host: host,
                    runReference: runReference,
                    receipt: receipt,
                    continuation: continuation,
                )
            }
            continuation.onTermination = { @Sendable termination in
                guard case .cancelled = termination else { return }
                Task {
                    await receipt.cancel()
                    await self.abandon(runReference)
                }
            }
        }
    }

    private func checkReadiness() throws {
        do {
            _ = try readinessProbe.check(
                executableURL: executableURL,
                environment: AiChatProviderExecutionClient.codexProcessEnvironment(codexHomeURL: codexHome),
            )
        } catch let error as CodexExecReadinessError {
            throw RuntimeHostError.adapterFailure(.processExit, RuntimeDiagnosticCode(Self.diagnosticCode(for: error)))
        } catch {
            throw RuntimeHostError.adapterFailure(.processExit, RuntimeDiagnosticCode("readiness_probe_failed"))
        }
    }

    private func makeLaunchCommand(
        request: RuntimeLaunchRequest,
        threadID: String?,
    ) throws -> CodexExecCommand {
        do {
            return try makeCommand(request: request, threadID: threadID)
        } catch let error as RuntimeHostError {
            throw error
        } catch {
            throw Self.map(error)
        }
    }

    private func validateRestartBinding(
        _ binding: CodexExecRestartBinding?,
        for request: RuntimeLaunchRequest,
    ) async throws {
        guard binding != nil || !evictedRestartBindings.contains(request.runReference) else {
            throw RuntimeHostError.staleRestartBinding
        }
        guard let binding else { return }
        let expected = makeRestartBinding(
            for: request,
            providerReference: binding.providerReference,
            providerEventSequence: binding.providerEventSequence,
        )
        guard binding == expected else {
            removeRestartBinding(request.runReference)
            await controller.discardStagedRestartBinding(binding)
            recordEvictedRestartBinding(request.runReference)
            throw RuntimeHostError.restartIncompatible
        }
    }

    private func acquireReceipt(
        _ command: CodexExecCommand,
        for request: RuntimeLaunchRequest,
        restartBinding: CodexExecRestartBinding?,
    ) async throws -> CodexExecProcessReceipt {
        do {
            let receipt: CodexExecProcessReceipt
            if let restartBinding {
                receipt = try await controller.acquire(
                    runID: request.runReference.rawValue,
                    command: command,
                    restartBinding: restartBinding,
                    onProducerFinished: { await self.markProducerFinished(request.runReference) },
                    onBindingEvicted: { evicted in
                        await self.removeRestartBindingIfMatching(evicted)
                    },
                    rawEventsEnabled: false,
                )
                if restartBindings[request.runReference] == restartBinding {
                    removeRestartBinding(request.runReference)
                }
                guard receipt.threadID == restartBinding.providerReference else {
                    await receipt.cancel()
                    recordEvictedRestartBinding(request.runReference)
                    throw CodexExecRestartFailure.incompatibleBinding
                }
            } else {
                receipt = try await controller.acquire(
                    runID: request.runReference.rawValue,
                    command: command,
                    onProducerFinished: { await self.markProducerFinished(request.runReference) },
                    rawEventsEnabled: false,
                )
            }
            return receipt
        } catch CodexExecProcessFailure.emptyThreadID {
            throw RuntimeHostError.malformedAdapterResponse
        } catch let error as CodexExecProcessFailure {
            throw Self.mapProcessFailure(error)
        } catch let error as CodexExecRestartFailure {
            throw Self.mapRestartFailure(error)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RuntimeHostError.adapterUnavailable
        }
    }

    private func eventSource(
        from receipt: CodexExecProcessReceipt,
    ) async throws -> AsyncThrowingStream<CodexExecLifecycleEvent, Error> {
        do { return try await receipt.eventStream() } catch { throw Self.map(error) }
    }

    private func forwardEvents(
        _ source: AsyncThrowingStream<CodexExecLifecycleEvent, Error>,
        host: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
        receipt: CodexExecProcessReceipt,
        continuation: AsyncThrowingStream<RuntimeEventEnvelope, any Error>.Continuation,
    ) async {
        do {
            var sequence = sequenceBases[runReference] ?? 0
            for try await event in source {
                let next = sequence.addingReportingOverflow(1)
                guard !next.overflow, next.partialValue != UInt64.max else {
                    let error = RuntimeHostError.adapterFailure(
                        .processExit,
                        RuntimeDiagnosticCode("event_sequence_overflow"),
                    )
                    await receipt.cancel()
                    abandon(runReference)
                    continuation.finish(throwing: error)
                    return
                }
                sequence = next.partialValue
                switch continuation.yield(Self.map(event, host: host, runReference: runReference, sequence: sequence)) {
                case .enqueued: break
                case .dropped:
                    let error = RuntimeHostError.adapterFailure(
                        .transportLoss,
                        RuntimeDiagnosticCode("event_buffer_overflow"),
                    )
                    await receipt.cancel()
                    abandon(runReference)
                    continuation.finish(throwing: error)
                    return
                case .terminated:
                    await receipt.cancel()
                    abandon(runReference)
                    return
                @unknown default:
                    await receipt.cancel()
                    abandon(runReference)
                    return
                }
            }
            if Task.isCancelled { abandon(runReference)
                return
            }
            await markEventFinished(runReference)
            continuation.finish()
        } catch {
            continuation.finish(throwing: Self.map(error))
            await receipt.cancel()
            abandon(runReference)
        }
    }

    public func respondToApproval(_ request: RuntimeApprovalRequest) async throws {
        _ = request
        throw RuntimeHostError.capabilityUnsupported(.approval)
    }

    public func requestCancellation(_ request: RuntimeCancellationRequest) async throws {
        _ = request
        throw RuntimeHostError.capabilityUnknown(.cancellation)
    }

    public func enqueueInput(_ request: RuntimeQueuedInputRequest) async throws {
        _ = request
        throw RuntimeHostError.capabilityUnsupported(.queuedInput)
    }

    public func terminalResult(for runReference: RuntimeRunReference) async throws -> RuntimeResult {
        guard let receipt = receipts[runReference] else { throw RuntimeHostError.invalidEvent }
        do {
            let result = try await receipt.terminalResult()
            resultFinished.insert(runReference)
            await retainCompletedIfOneSided(runReference)
            evictIfFinished(runReference)
            return RuntimeResult(
                runReference: runReference,
                outcome: Self.map(result.outcome),
                artifactReferences: [],
                failure: result.failure.map(Self.mapFailure),
            )
        } catch {
            await receipt.cancel()
            abandon(runReference)
            throw Self.map(error)
        }
    }

    private func markEventFinished(_ runReference: RuntimeRunReference) async {
        eventFinished.insert(runReference)
        await retainCompletedIfOneSided(runReference)
        evictIfFinished(runReference)
    }

    private func markProducerFinished(_ runReference: RuntimeRunReference) async {
        await retainCompletedIfOneSided(runReference)
    }

    private func abandon(_ runReference: RuntimeRunReference) {
        receipts[runReference] = nil
        hosts[runReference] = nil
        sequenceBases[runReference] = nil
        eventFinished.remove(runReference)
        resultFinished.remove(runReference)
        retainedCompletions[runReference] = nil
    }

    private func retainCompletedIfOneSided(_ runReference: RuntimeRunReference) async {
        guard (eventFinished.contains(runReference) != resultFinished.contains(runReference))
            || (!eventFinished.contains(runReference) && !resultFinished.contains(runReference)),
            retainedCompletions[runReference] == nil
        else { return }
        nextRetentionOrdinal += 1
        retainedCompletions[runReference] = nextRetentionOrdinal
        guard retainedCompletions.count > retentionCapacity,
              let oldest = retainedCompletions.min(by: { $0.value < $1.value })
        else { return }
        let restartBinding = restartBindings[oldest.key]
        retainedCompletions[oldest.key] = nil
        if let receipt = receipts[oldest.key] {
            await receipt.cancel()
        }
        if let restartBinding, restartBindings[oldest.key] == restartBinding {
            let result = try? await controller.restartCompatibilityAndStage(
                binding: restartBinding,
                current: restartBinding,
            )
            if let evictedBinding = result?.evictedBinding {
                removeRestartBindingIfMatching(evictedBinding)
            }
        }
        receipts[oldest.key] = nil
        hosts[oldest.key] = nil
        sequenceBases[oldest.key] = nil
        eventFinished.remove(oldest.key)
        resultFinished.remove(oldest.key)
        retainedCompletions[oldest.key] = nil
    }

    private func evictIfFinished(_ runReference: RuntimeRunReference) {
        guard eventFinished.contains(runReference), resultFinished.contains(runReference) else { return }
        receipts[runReference] = nil
        hosts[runReference] = nil
        sequenceBases[runReference] = nil
        removeRestartBinding(runReference)
        eventFinished.remove(runReference)
        resultFinished.remove(runReference)
        retainedCompletions[runReference] = nil
    }

    private func removeRestartBinding(_ runReference: RuntimeRunReference) {
        restartBindings[runReference] = nil
        restartBindingOrder.removeAll { $0 == runReference }
    }

    private func removeRestartBindingIfMatching(_ binding: CodexExecRestartBinding) {
        let runReference = RuntimeRunReference(binding.runReference)
        guard restartBindings[runReference] == binding else { return }
        removeRestartBinding(runReference)
        recordEvictedRestartBinding(runReference)
    }

    private func recordEvictedRestartBinding(_ runReference: RuntimeRunReference) {
        guard evictedRestartBindings.insert(runReference).inserted else { return }
        evictedRestartBindingOrder.append(runReference)
        guard evictedRestartBindingOrder.count > CodexExecProcessRegistry.maximumRetainedStagedBindings else { return }
        evictedRestartBindings.remove(evictedRestartBindingOrder.removeFirst())
    }

    public func restartCompatibility(
        for binding: RuntimeRestartBinding,
    ) async throws -> RuntimeRestartCompatibility {
        guard binding.adapterID == descriptor.id,
              binding.providerNamespace == descriptor.providerNamespace,
              binding.adapterVersion == descriptor.adapterVersion,
              binding.providerBranch == descriptor.providerBranch,
              binding.capabilitySnapshot == descriptor.capabilities,
              !binding.providerInternalSessionReference.rawValue.isEmpty,
              binding.providerInternalSessionReference.rawValue.unicodeScalars.count <= 4096
        else { return .incompatible }

        let candidate = CodexExecRestartBinding(
            hostReference: binding.externalAgentSessionReference.rawValue,
            runReference: binding.runReference.rawValue,
            providerReference: binding.providerInternalSessionReference.rawValue,
            adapterID: binding.adapterID.rawValue,
            providerNamespace: binding.providerNamespace,
            adapterVersion: binding.adapterVersion,
            providerBranch: binding.providerBranch.rawValue,
            capabilities: CodexExecRestartCapabilities(values: Self.capabilityValues(descriptor.capabilities)),
            context: CodexExecRestartContext(
                branchReference: binding.contextPolicy.branchReference,
                authorizationGeneration: binding.contextPolicy.authorizationGeneration,
                localCorrelation: binding.contextPolicy.localCorrelation,
                workingDirectory: binding.contextPolicy.workingDirectory,
                allowedRoots: binding.contextPolicy.allowedRoots,
                requestContext: binding.contextPolicy.requestContext,
            ),
            providerEventSequence: binding.providerEventSequence,
        )
        let result = try await controller.restartCompatibilityAndStage(binding: candidate, current: candidate)
        guard result.compatibility == .compatible else { return Self.map(result.compatibility) }
        if let evictedBinding = result.evictedBinding {
            removeRestartBindingIfMatching(evictedBinding)
        }
        guard await controller.stagedRestartBinding(for: binding.runReference.rawValue) == candidate else {
            return .stale
        }
        evictedRestartBindings.remove(binding.runReference)
        evictedRestartBindingOrder.removeAll { $0 == binding.runReference }
        restartBindings[binding.runReference] = candidate
        if !restartBindingOrder.contains(binding.runReference) {
            restartBindingOrder.append(binding.runReference)
        }
        return .compatible
    }

    func debugStorageCounts() -> CodexExecDebugStorageCounts {
        CodexExecDebugStorageCounts(
            receipts: receipts.count,
            hosts: hosts.count,
            sequenceBases: sequenceBases.count,
            restartBindings: restartBindings.count,
            tombstones: eventFinished.count + resultFinished.count,
        )
    }
}

struct CodexExecDebugStorageCounts {
    let receipts: Int
    let hosts: Int
    let sequenceBases: Int
    let restartBindings: Int
    let tombstones: Int
}

extension CodexExecRuntimeAdapter {
    func makeCommand(request: RuntimeLaunchRequest, threadID: String?) throws -> CodexExecCommand {
        guard let directory = request.contextPolicy.workingDirectory else {
            throw RuntimeHostError.malformedAdapterResponse
        }
        let roots = request.contextPolicy.allowedRoots.map { CodexPathCanonicalizer.url(URL(fileURLWithPath: $0)) }
        let primaryRoot: URL
        let additionalRoots: [URL]
        if roots.isEmpty {
            primaryRoot = CodexPathCanonicalizer.url(URL(fileURLWithPath: directory))
            additionalRoots = []
        } else {
            let workingDirectory = CodexPathCanonicalizer.url(URL(fileURLWithPath: directory))
            let authorizedAncestors = roots.filter {
                workingDirectory.path == $0.path || workingDirectory.path.hasPrefix($0.path + "/")
            }
            guard let selected = authorizedAncestors.max(by: { $0.path.count < $1.path.count }) else {
                throw Self.map(CodexExecCommandError.writableRootOutsideWorkingDirectory(workingDirectory.path))
            }
            primaryRoot = selected
            additionalRoots = roots.filter { $0 != selected }
        }
        return try CodexExecCommandBuilder.build(
            request: CodexExecCommandRequest(
                model: "gpt-5-codex",
                prompt: request.input.rawValue,
                workingDirectory: URL(fileURLWithPath: directory),
                sandbox: roots.isEmpty ? .readOnly : .workspaceWrite,
                primaryWritableRoot: primaryRoot,
                additionalWritableRoots: additionalRoots,
                codexHome: codexHome,
                threadID: threadID,
            ),
            executableURL: executableURL ?? Self.requireExecutable(),
        )
    }

    func makeRestartBinding(
        for request: RuntimeLaunchRequest,
        providerReference: String,
        providerEventSequence: UInt64 = 0,
    ) -> CodexExecRestartBinding {
        CodexExecRestartBinding(
            hostReference: request.externalAgentSessionReference.rawValue,
            runReference: request.runReference.rawValue,
            providerReference: providerReference,
            adapterID: descriptor.id.rawValue,
            providerNamespace: descriptor.providerNamespace,
            adapterVersion: descriptor.adapterVersion,
            providerBranch: descriptor.providerBranch.rawValue,
            capabilities: CodexExecRestartCapabilities(values: Self.capabilityValues(descriptor.capabilities)),
            context: CodexExecRestartContext(
                branchReference: request.contextPolicy.branchReference,
                authorizationGeneration: request.contextPolicy.authorizationGeneration,
                localCorrelation: request.contextPolicy.localCorrelation,
                workingDirectory: request.contextPolicy.workingDirectory,
                allowedRoots: request.contextPolicy.allowedRoots,
                requestContext: request.contextPolicy.requestContext,
            ),
            providerEventSequence: providerEventSequence,
        )
    }

    static func requireExecutable() throws -> URL {
        guard let executable = CodexExecReadinessProbe.discoverExecutable() else {
            throw CodexExecReadinessError.executableMissing
        }
        return executable
    }

    static func capabilityValues(_ capabilities: RuntimeCapabilities) -> [String: String] {
        [
            RuntimeCapability.discovery, .eventStream, .approval, .cancellation, .queuedInput, .terminalResult,
            .timeout, .sameIdentityResume, .reconstruction, .explicitArtifact, .workingDirectory,
            .additionalRoots, .authStatusProbe,
        ].reduce(into: [String: String]()) { result, capability in
            result[capability.rawValue] = capabilities[capability].rawValue
        }
    }

    static func diagnosticCode(for error: CodexExecReadinessError) -> String {
        switch error {
        case .executableMissing: "executable_missing"
        case .versionUnreadable: "version_unreadable"
        case .unsupportedVersion: "unsupported_version"
        case .loginRequired: "login_required"
        case .loginProbeFailed: "login_probe_failed"
        }
    }

    static func map(
        _ event: CodexExecLifecycleEvent,
        host: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
        sequence: UInt64,
    ) -> RuntimeEventEnvelope {
        RuntimeEventEnvelope(
            source: .provider,
            providerEventID: ProviderEventID(
                digestIdentifier(prefix: "codex.pe.", domain: "provider-event", values: [
                    event.providerEventID, runReference.rawValue, String(sequence),
                ]),
            ),
            sequence: sequence,
            idempotencyKey: RuntimeIdempotencyKey(
                digestIdentifier(prefix: "codex.ik.", domain: "runtime-idempotency", values: [
                    runReference.rawValue, String(sequence),
                ]),
            ),
            timestamp: Date(),
            externalAgentSessionReference: host,
            runReference: runReference,
            kind: event.kind == .completed ? .completed : event.kind == .failed ? .failed : .progress,
        )
    }

    private static func digestIdentifier(prefix: String, domain: String, values: [String]) -> String {
        let canonical = ([domain] + values).joined(separator: "\u{0}")
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return prefix + digest.map { String(format: "%02x", $0) }.joined()
    }

    static func map(_ outcome: CodexExecLifecycleKind) -> RuntimeOutcome {
        switch outcome {
        case .completed: .completed
        case .failed: .failed
        case .progress: .interrupted
        }
    }

    static func map(_ compatibility: CodexExecRestartCompatibility) -> RuntimeRestartCompatibility {
        switch compatibility {
        case .compatible: .compatible
        case .stale: .stale
        case .incompatible: .incompatible
        }
    }

    static func mapFailure(_ failure: CodexExecProcessFailure) -> RuntimeAdapterFailure {
        let mapped: (RuntimeAdapterFailureKind, String) = switch failure {
        case let .earlyEvent(type): (.malformedFrame, "early_\(type.rawValue)")
        case .emptyThreadID: (.malformedFrame, "empty_thread_id")
        case .eofBeforeHandshake: (.processExit, "eof_before_handshake")
        case .processFailed: (.processExit, "process_exit")
        case let .decoder(error): (.malformedFrame, decodeDiagnosticCode(error))
        case .eventBufferOverflow: (.processExit, "event_buffer_overflow")
        case .encodedEventBufferOverflow: (.processExit, "encoded_event_buffer_overflow")
        case .launchFailed: (.processExit, "launch_failed")
        case .eofBeforeTerminal: (.processExit, "eof_before_terminal")
        case .terminalError: (.processExit, "terminal_error")
        case .duplicateTerminal: (.malformedFrame, "duplicate_terminal")
        }
        return RuntimeAdapterFailure(
            kind: mapped.0,
            diagnosticCode: RuntimeDiagnosticCode(mapped.1),
        )
    }

    static func mapProcessFailure(_ failure: CodexExecProcessFailure) -> RuntimeHostError {
        .adapterFailure(mapFailure(failure).kind, mapFailure(failure).diagnosticCode)
    }

    static func mapRestartFailure(_ failure: CodexExecRestartFailure) -> RuntimeHostError {
        switch failure {
        case .staleBinding: .staleRestartBinding
        case .incompatibleBinding: .restartIncompatible
        case .invalidBinding: .invalidEvent
        }
    }

    static func map(_ error: Error) -> RuntimeHostError {
        if let error = error as? RuntimeHostError { return error }
        if let error = error as? CodexExecProcessFailure { return mapProcessFailure(error) }
        if let error = error as? CodexExecRestartFailure { return mapRestartFailure(error) }
        if error is CodexExecConsumptionFailure { return .invalidEvent }
        if let error = error as? CodexExecCommandError {
            return .adapterFailure(.sdkException, RuntimeDiagnosticCode(Self.commandDiagnosticCode(error)))
        }
        if let error = error as? CodexExecReadinessError {
            return .adapterFailure(.processExit, RuntimeDiagnosticCode(Self.diagnosticCode(for: error)))
        }
        if let error = error as? CodexExecDecodeError {
            return .adapterFailure(.malformedFrame, RuntimeDiagnosticCode(Self.decodeDiagnosticCode(error)))
        }
        return .adapterFailure(.transportLoss, RuntimeDiagnosticCode("stream_failure"))
    }

    static func commandDiagnosticCode(_ error: CodexExecCommandError) -> String {
        switch error {
        case .invalidWorkingDirectory: "invalid_working_directory"
        case .invalidWritableRoot: "invalid_writable_root"
        case .writableRootOutsideWorkingDirectory: "writable_root_outside_working_directory"
        case .emptyModel: "empty_model"
        case .emptyThreadID: "empty_thread_id"
        }
    }

    static func decodeDiagnosticCode(_ error: CodexExecDecodeError) -> String {
        switch error {
        case .malformedFrame: "malformed_frame"
        case .incompleteFrame: "incomplete_frame"
        case .rawLineTooLarge: "raw_line_too_large"
        case .finalAssistantItemLimit: "final_assistant_item_limit"
        }
    }
}
