import Foundation

extension RuntimeControlPlane {
    struct RunReservation {
        let adapter: any ExternalAgentRuntimeAdapter
        let descriptor: RuntimeAdapterDescriptor
        let host: ExternalAgentSessionReference
    }

    func reserve(_ request: RuntimeLaunchRequest) throws -> RunReservation {
        try validateBoundary(request)
        guard let adapter = adapters[request.adapterID] else {
            throw RuntimeHostError.adapterNotFound(request.adapterID)
        }
        let descriptor = adapter.descriptor
        try requireExecutionOutput(in: descriptor.capabilities)
        let host = request.externalAgentSessionReference
        guard let current = sessions[host] else { throw RuntimeHostError.invalidEvent }
        let sameRun = current.stored.runReference == request.runReference
        let mayLaunch = sameRun && [.policyReady, .launchFailed].contains(current.stored.projection)
        guard !current.active, mayLaunch else {
            if sameRun { throw RuntimeHostError.duplicateRunReference }
            throw RuntimeHostError.activeRunExists
        }
        guard current.stored.matchesLaunchSnapshot(request, descriptor: descriptor) else {
            throw RuntimeHostError.invalidEvent
        }
        sessions[host] = Session(stored: RuntimeStoredSession(
            externalAgentSessionReference: host,
            providerInternalSessionReference: nil,
            runReference: request.runReference,
            adapterID: descriptor.id,
            adapterVersion: descriptor.adapterVersion,
            capabilitySnapshot: descriptor.capabilities,
            contextPolicy: request.contextPolicy,
            projection: .launching,
            lastSequence: 0,
            acceptedEventCount: current.stored.acceptedEventCount,
            processedEventCount: current.stored.processedEventCount,
            acceptedIdempotencyKeys: [],
            providerNamespace: descriptor.providerNamespace,
            providerBranch: descriptor.providerBranch,
        ), active: true)
        return RunReservation(adapter: adapter, descriptor: descriptor, host: host)
    }

    func bind(
        _ receipt: RuntimeLaunchReceipt,
        to request: RuntimeLaunchRequest,
        descriptor: RuntimeAdapterDescriptor,
    ) throws {
        guard receipt.runReference == request.runReference else {
            throw RuntimeHostError.malformedAdapterResponse
        }
        guard !receipt.providerInternalSessionReference.rawValue.isEmpty,
              receipt.providerInternalSessionReference.rawValue.unicodeScalars.count
              <= RuntimeBoundaryLimits.opaqueProviderHandleScalars,
              var session = sessions[request.externalAgentSessionReference],
              session.active,
              session.stored.projection == .launching,
              session.stored.runReference == request.runReference
        else { throw RuntimeHostError.invalidEvent }
        session.stored = RuntimeStoredSession(
            externalAgentSessionReference: request.externalAgentSessionReference,
            providerInternalSessionReference: receipt.providerInternalSessionReference,
            runReference: request.runReference,
            adapterID: descriptor.id,
            adapterVersion: descriptor.adapterVersion,
            capabilitySnapshot: descriptor.capabilities,
            contextPolicy: request.contextPolicy,
            projection: .running,
            lastSequence: session.stored.lastSequence,
            acceptedEventCount: session.stored.acceptedEventCount,
            processedEventCount: session.stored.processedEventCount,
            acceptedIdempotencyKeys: session.stored.acceptedIdempotencyKeys,
            hostLastSequence: session.stored.hostLastSequence,
            hostAcceptedEventCount: session.stored.hostAcceptedEventCount,
            hostProcessedEventCount: session.stored.hostProcessedEventCount,
            hostAcceptedIdempotencyKeys: session.stored.hostAcceptedIdempotencyKeys,
            providerNamespace: descriptor.providerNamespace,
            providerBranch: descriptor.providerBranch,
            eventEvidence: session.stored.eventEvidence,
        )
        sessions[request.externalAgentSessionReference] = session
    }

    func consume(
        _ receipt: RuntimeLaunchReceipt,
        from adapter: any ExternalAgentRuntimeAdapter,
        host: ExternalAgentSessionReference,
    ) async throws -> RuntimeResult {
        if adapter.descriptor.capabilities.eventStream == .supported {
            do {
                let stream = try await adapter.eventStream(for: receipt.runReference)
                for try await event in stream {
                    if let terminal = try await accept(event, host: host, expectedSource: .provider) {
                        if adapter.descriptor.capabilities.terminalResult == .supported {
                            let result = try await adapter.terminalResult(for: receipt.runReference)
                            guard result.runReference == receipt.runReference else {
                                throw RuntimeHostError.malformedAdapterResponse
                            }
                            return resultRespectingStoredTerminal(result, host: host)
                        }
                        return terminal
                    }
                }
            } catch {
                if let terminal = storedTerminalResult(
                    host: host,
                    runReference: receipt.runReference,
                ) {
                    return terminal
                }
                throw error
            }
        }
        try require(.terminalResult, in: adapter.descriptor.capabilities)
        let result = try await adapter.terminalResult(for: receipt.runReference)
        guard result.runReference == receipt.runReference else {
            throw RuntimeHostError.malformedAdapterResponse
        }
        return result
    }

    func finish(_ result: RuntimeResult, host: ExternalAgentSessionReference) {
        update(host) { session in
            guard session.active, !session.stored.projection.isTerminal else { return }
            session.stored = RuntimeStoredSession(
                externalAgentSessionReference: host,
                providerInternalSessionReference: session.stored.providerInternalSessionReference,
                runReference: session.stored.runReference,
                adapterID: session.stored.adapterID,
                adapterVersion: session.stored.adapterVersion,
                capabilitySnapshot: session.stored.capabilitySnapshot,
                contextPolicy: session.stored.contextPolicy,
                projection: projection(for: result.outcome),
                lastSequence: session.stored.lastSequence,
                acceptedEventCount: session.stored.acceptedEventCount,
                processedEventCount: session.stored.processedEventCount,
                acceptedIdempotencyKeys: session.stored.acceptedIdempotencyKeys,
                hostLastSequence: session.stored.hostLastSequence,
                hostAcceptedEventCount: session.stored.hostAcceptedEventCount,
                hostProcessedEventCount: session.stored.hostProcessedEventCount,
                hostAcceptedIdempotencyKeys: session.stored.hostAcceptedIdempotencyKeys,
                providerNamespace: session.stored.providerNamespace,
                providerBranch: session.stored.providerBranch,
                eventEvidence: session.stored.eventEvidence,
            )
            session.active = false
        }
    }

    private func projection(for outcome: RuntimeOutcome) -> RuntimeProjection {
        switch outcome {
        case .completed: .completed
        case .failed: .failed
        case .interrupted: .interrupted
        }
    }

    func resultRespectingStoredTerminal(
        _ result: RuntimeResult,
        host: ExternalAgentSessionReference,
    ) -> RuntimeResult {
        guard let projection = sessions[host]?.stored.projection,
              let storedOutcome = outcome(for: projection),
              storedOutcome != result.outcome
        else { return result }
        return RuntimeResult(
            runReference: result.runReference,
            outcome: storedOutcome,
            artifactReferences: [],
        )
    }

    private func storedTerminalResult(
        host: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
    ) -> RuntimeResult? {
        guard let projection = sessions[host]?.stored.projection,
              let outcome = outcome(for: projection)
        else { return nil }
        return RuntimeResult(
            runReference: runReference,
            outcome: outcome,
            artifactReferences: [],
        )
    }

    private func outcome(for projection: RuntimeProjection) -> RuntimeOutcome? {
        switch projection {
        case .completed: .completed
        case .failed: .failed
        case .interrupted: .interrupted
        default: nil
        }
    }

    private func requireExecutionOutput(in capabilities: RuntimeCapabilities) throws {
        if capabilities.eventStream == .supported || capabilities.terminalResult == .supported {
            return
        }
        if capabilities.eventStream == .unknown || capabilities.terminalResult == .unknown {
            throw RuntimeHostError.capabilityUnknown(.eventStream)
        }
        throw RuntimeHostError.capabilityUnsupported(.eventStream)
    }
}

extension RuntimeStoredSession {
    func matchesLaunchSnapshot(
        _ request: RuntimeLaunchRequest,
        descriptor: RuntimeAdapterDescriptor,
    ) -> Bool {
        runReference == request.runReference
            && adapterID == descriptor.id
            && providerNamespace == descriptor.providerNamespace
            && adapterVersion == descriptor.adapterVersion
            && providerBranch == descriptor.providerBranch
            && capabilitySnapshot == descriptor.capabilities
            && contextPolicy.hasSameExecutionContext(as: request.contextPolicy)
    }
}
