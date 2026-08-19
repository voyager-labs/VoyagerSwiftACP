import Foundation

extension RuntimeControlPlane {
    struct RunReservation {
        let adapter: any ExternalAgentRuntimeAdapter
        let descriptor: RuntimeAdapterDescriptor
        let host: ExternalAgentSessionReference
        let lease: UInt64
    }

    enum ReceiptTransition {
        case consuming(UInt64)
        case terminal(RuntimeResult)
    }

    func retireOrphanedDirectRunIfNeeded(_ request: RuntimeLaunchRequest) async throws -> Bool {
        let host = request.externalAgentSessionReference
        guard let current = sessions[host],
              !current.lease.isActive,
              current.stored.projection == .launching,
              current.stored.providerInternalSessionReference == nil,
              current.stored.providerLaunchAttempted == false,
              current.stored.runReference == request.runReference
        else { return false }
        return try await commit(host: host) { _, registry in
            guard var candidate = registry[host],
                  !candidate.lease.isActive,
                  candidate.stored.projection == .launching,
                  candidate.stored.providerInternalSessionReference == nil,
                  candidate.stored.providerLaunchAttempted == false,
                  candidate.stored.runReference == request.runReference
            else { return false }
            candidate.stored = candidate.stored.withProjection(.interrupted)
            candidate.revision += 1
            registry[host] = candidate
            return true
        }
    }

    func reserveTransition(
        _ request: RuntimeLaunchRequest,
        in registry: inout SessionRegistry,
    ) throws -> RunReservation {
        try validateBoundary(request)
        guard let adapter = adapters[request.adapterID] else {
            throw RuntimeHostError.adapterNotFound(request.adapterID)
        }
        let descriptor = adapter.descriptor
        try requireExecutionOutput(in: descriptor.capabilities)
        try requireExecutionContext(request.contextPolicy, in: descriptor.capabilities)
        let host = request.externalAgentSessionReference
        try requireAvailableRunReference(request.runReference, excluding: host, in: registry)
        guard var current = registry[host] else { throw RuntimeHostError.invalidEvent }
        let sameRun = current.stored.runReference == request.runReference
        let mayLaunch = sameRun && [.policyReady, .launchFailed].contains(current.stored.projection)
        guard !current.lease.isActive, mayLaunch else {
            if sameRun { throw RuntimeHostError.duplicateRunReference }
            throw RuntimeHostError.activeRunExists
        }
        guard current.stored.matchesLaunchSnapshot(request, descriptor: descriptor) else {
            throw RuntimeHostError.invalidEvent
        }
        current.stored = RuntimeStoredSession(
            externalAgentSessionReference: host,
            providerInternalSessionReference: nil,
            runReference: request.runReference,
            adapterID: descriptor.id,
            adapterVersion: descriptor.adapterVersion,
            capabilitySnapshot: descriptor.capabilities,
            storedContext: RuntimeStoredContext(contextPolicy: request.contextPolicy),
            projection: .launching,
            providerLaunchAttempted: true,
            lastSequence: current.stored.lastSequence,
            acceptedEventCount: current.stored.acceptedEventCount,
            processedEventCount: current.stored.processedEventCount,
            acceptedIdempotencyKeys: current.stored.acceptedIdempotencyKeys,
            hostLastSequence: current.stored.hostLastSequence,
            hostAcceptedEventCount: current.stored.hostAcceptedEventCount,
            hostProcessedEventCount: current.stored.hostProcessedEventCount,
            hostAcceptedIdempotencyKeys: current.stored.hostAcceptedIdempotencyKeys,
            providerNamespace: descriptor.providerNamespace,
            providerBranch: descriptor.providerBranch,
            eventEvidence: current.stored.eventEvidence,
        )
        let lease = current.issueLease(RuntimeLease.launching)
        registry[host] = current
        return RunReservation(adapter: adapter, descriptor: descriptor, host: host, lease: lease)
    }

    func recordReceiptTransition(
        _ receipt: RuntimeLaunchReceipt,
        request: RuntimeLaunchRequest,
        descriptor _: RuntimeAdapterDescriptor,
        lease: UInt64,
        in registry: inout SessionRegistry,
    ) throws -> ReceiptTransition {
        try validateReceipt(receipt, request: request)
        let host = request.externalAgentSessionReference
        guard var session = registry[host], session.stored.runReference == request.runReference else {
            throw RuntimeHostError.invalidEvent
        }
        guard session.lease == .launching(lease) else { throw RuntimeHostError.invalidEvent }
        if let existing = session.stored.providerInternalSessionReference,
           existing != receipt.providerInternalSessionReference
        {
            throw RuntimeHostError.malformedAdapterResponse
        }
        session.stored = session.stored.withProviderReference(
            receipt.providerInternalSessionReference,
            projection: session.stored.projection.isTerminal ? session.stored.projection : .running,
        )
        session.revision += 1
        if let terminal = terminalResult(for: session.stored) {
            session.lease = .none
            registry[host] = session
            return .terminal(terminal)
        }
        guard session.stored.projection == .running else {
            throw RuntimeHostError.invalidEvent
        }
        session.lease = .consuming(lease)
        registry[host] = session
        return .consuming(lease)
    }

    func finishTransition(
        _ result: RuntimeResult,
        host: ExternalAgentSessionReference,
        lease: UInt64,
        in registry: inout SessionRegistry,
    ) throws -> RuntimeResult {
        guard var session = registry[host], session.stored.runReference == result.runReference else {
            throw RuntimeHostError.invalidEvent
        }
        guard session.lease == .consuming(lease) || session.lease == .resuming(lease) else {
            throw RuntimeHostError.invalidEvent
        }
        if let terminal = terminalResult(for: session.stored) {
            session.lease = .none
            session.revision += 1
            registry[host] = session
            return terminal.outcome == result.outcome ? result : terminal
        }
        session.stored = session.stored.withProjection(projection(for: result.outcome))
        session.lease = .none
        session.revision += 1
        registry[host] = session
        return result
    }

    func failLaunchTransition(
        host: ExternalAgentSessionReference,
        lease: UInt64,
        in registry: inout SessionRegistry,
    ) -> RuntimeResult? {
        guard var session = registry[host], session.lease == .launching(lease) else { return nil }
        let terminal = terminalResult(for: session.stored)
        if !session.stored.projection.isTerminal {
            session.stored = session.stored.withProjection(.interrupted)
        }
        session.lease = .none
        session.revision += 1
        registry[host] = session
        return terminal
    }

    func detachLaunchOwnerTransition(
        host: ExternalAgentSessionReference,
        lease: UInt64,
    ) {
        guard var session = sessions[host], session.lease == .launching(lease) else { return }
        session.lease = session.stored.projection.isTerminal ? .none : .detachedLaunching(lease)
        session.revision += 1
        sessions[host] = session
    }

    func interruptTransition(
        host: ExternalAgentSessionReference,
        lease: UInt64?,
        in registry: inout SessionRegistry,
        receipt: RuntimeLaunchReceipt? = nil,
    ) throws -> RuntimeResult? {
        guard var session = registry[host] else { return nil }
        if let lease {
            guard session.lease == .launching(lease)
                || session.lease == .consuming(lease)
                || session.lease == .resuming(lease)
            else { return nil }
        }
        if let receipt {
            guard receipt.runReference == session.stored.runReference else {
                throw RuntimeHostError.invalidEvent
            }
            if let existing = session.stored.providerInternalSessionReference,
               existing != receipt.providerInternalSessionReference
            {
                throw RuntimeHostError.malformedAdapterResponse
            }
            session.stored = session.stored.withProviderReference(
                receipt.providerInternalSessionReference,
                projection: session.stored.projection,
            )
        }
        if session.stored.projection.isTerminal {
            let terminal = terminalResult(for: session.stored)
            session.lease = .none
            session.revision += 1
            registry[host] = session
            return terminal
        }
        session.stored = session.stored.withProjection(.interrupted)
        session.lease = .none
        session.revision += 1
        registry[host] = session
        return nil
    }

    func detachConsumerOwnerTransition(
        host: ExternalAgentSessionReference,
        lease: UInt64,
        in registry: inout SessionRegistry,
    ) {
        guard var session = registry[host],
              session.lease == .consuming(lease)
        else { return }
        session.lease = session.stored.projection.isTerminal ? .none : .detachedConsuming(lease)
        session.revision += 1
        registry[host] = session
    }

    func recoverTerminalPersistenceClaimTransition(
        host: ExternalAgentSessionReference,
        lease: UInt64,
    ) {
        guard var session = sessions[host] else { return }
        switch session.lease {
        case .consuming(lease):
            session.lease = .none
        case .resuming(lease):
            session.lease = .restored(lease)
        default:
            return
        }
        session.revision += 1
        sessions[host] = session
    }

    func outcome(for projection: RuntimeProjection) -> RuntimeOutcome? {
        switch projection {
        case .completed: .completed
        case .failed: .failed
        case .interrupted: .interrupted
        default: nil
        }
    }

    private func projection(for outcome: RuntimeOutcome) -> RuntimeProjection {
        switch outcome {
        case .completed: .completed
        case .failed: .failed
        case .interrupted: .interrupted
        }
    }

    private func validateReceipt(
        _ receipt: RuntimeLaunchReceipt,
        request: RuntimeLaunchRequest,
    ) throws {
        guard receipt.runReference == request.runReference,
              !receipt.providerInternalSessionReference.rawValue.isEmpty,
              receipt.providerInternalSessionReference.rawValue.unicodeScalars.count
              <= RuntimeBoundaryLimits.opaqueProviderHandleScalars
        else { throw RuntimeHostError.malformedAdapterResponse }
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

    private func requireExecutionContext(
        _ contextPolicy: RuntimeContextPolicy,
        in capabilities: RuntimeCapabilities,
    ) throws {
        if contextPolicy.workingDirectory != nil {
            try require(.workingDirectory, in: capabilities)
        }
        if !contextPolicy.allowedRoots.isEmpty {
            try require(.additionalRoots, in: capabilities)
        }
    }
}

extension RuntimeStoredSession {
    func withProviderReference(
        _ providerReference: ProviderInternalSessionReference,
        projection: RuntimeProjection,
    ) -> Self {
        var copy = Self(
            externalAgentSessionReference: externalAgentSessionReference,
            providerInternalSessionReference: providerReference,
            runReference: runReference,
            adapterID: adapterID,
            adapterVersion: adapterVersion,
            capabilitySnapshot: capabilitySnapshot,
            storedContext: storedContext,
            projection: projection,
            providerLaunchAttempted: providerLaunchAttempted,
            lastSequence: lastSequence,
            acceptedEventCount: acceptedEventCount,
            processedEventCount: processedEventCount,
            acceptedIdempotencyKeys: acceptedIdempotencyKeys,
            hostLastSequence: hostLastSequence,
            hostAcceptedEventCount: hostAcceptedEventCount,
            hostProcessedEventCount: hostProcessedEventCount,
            hostAcceptedIdempotencyKeys: hostAcceptedIdempotencyKeys,
            providerNamespace: providerNamespace,
            providerBranch: providerBranch,
            eventEvidence: eventEvidence,
        )
        copy.restorationClaim = restorationClaim
        return copy
    }
}
