import Foundation

extension RuntimeControlPlane {
    enum ReservationTransition {
        case reserved(RunReservation)
        case rejectedDuplicate
    }

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

    func reserveTransition(
        _ request: RuntimeLaunchRequest,
        in registry: inout SessionRegistry,
    ) throws -> ReservationTransition {
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
        guard current.stored.runReference == request.runReference else {
            throw RuntimeHostError.activeRunExists
        }
        let snapshot = current.freshRunSnapshot()
        if try applyOrphanReservationIfNeeded(snapshot, to: &current, in: &registry, host: host) {
            return .rejectedDuplicate
        }
        try requireReservationAllowed(snapshot)
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
        return .reserved(RunReservation(adapter: adapter, descriptor: descriptor, host: host, lease: lease))
    }

    private func applyOrphanReservationIfNeeded(
        _ snapshot: RuntimeFreshRunSnapshot,
        to session: inout Session,
        in registry: inout SessionRegistry,
        host: ExternalAgentSessionReference,
    ) throws -> Bool {
        switch RuntimeFreshRunDecisionTable.decide(.orphanLaunching, on: snapshot) {
        case let .persist(projection, attachReceipt, lease):
            try applyFreshRunDecision(
                .persist(projection: projection, attachReceipt: attachReceipt, lease: lease),
                to: &session,
            )
            registry[host] = session
            return true
        case .ignore, .recordCleanupFailure, .throwHost(.activeRunExists):
            return false
        case let .throwHost(error):
            throw error
        case .throwCancellation:
            throw CancellationError()
        case .adoptPersisted:
            throw RuntimeHostError.persistenceConflict
        }
    }

    private func requireReservationAllowed(_ snapshot: RuntimeFreshRunSnapshot) throws {
        guard !RuntimeFreshRunDecisionTable.allowsRelaunch(snapshot) else { return }
        switch RuntimeFreshRunDecisionTable.decide(.reserve, on: snapshot) {
        case let .throwHost(error):
            throw error
        case .throwCancellation:
            throw CancellationError()
        case .ignore, .recordCleanupFailure:
            throw RuntimeHostError.duplicateRunReference
        case .persist, .adoptPersisted:
            throw RuntimeHostError.invalidEvent
        }
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
        let decision = RuntimeFreshRunDecisionTable.decide(
            .receipt(token: receipt.providerInternalSessionReference.rawValue),
            on: session.freshRunSnapshot(),
        )
        try applyFreshRunDecision(decision, to: &session)
        if let terminal = terminalResult(for: session.stored) {
            registry[host] = session
            return .terminal(terminal)
        }
        guard session.stored.projection == .running,
              case let .consuming(consumingLease) = session.lease
        else {
            throw RuntimeHostError.invalidEvent
        }
        registry[host] = session
        return .consuming(consumingLease)
    }

    func finishTransition(
        _ result: RuntimeResult,
        host: ExternalAgentSessionReference,
        lease: UInt64,
        in registry: inout SessionRegistry,
        restoredContext: RuntimeRestoredResumeContext? = nil,
    ) throws -> RuntimeResult {
        if let restoredContext {
            try requireRestoredResumeContext(
                restoredContext,
                host: host,
                runReference: result.runReference,
                in: registry,
            )
        }
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
        switch session.lease {
        case .consuming:
            let decision = RuntimeFreshRunDecisionTable.decide(
                .providerResult(result.outcome),
                on: session.freshRunSnapshot(),
            )
            guard case .persist = decision else { throw RuntimeHostError.invalidEvent }
            try applyFreshRunDecision(decision, to: &session)
        case .resuming:
            session.stored = session.stored.withProjection(projection(for: result.outcome))
            session.lease = .none
            session.revision += 1
        case .none, .launching, .detachedLaunching, .detachedConsuming, .restored:
            throw RuntimeHostError.invalidEvent
        }
        registry[host] = session
        return result
    }

    func persistLaunchFailureTransition(
        host: ExternalAgentSessionReference,
        lease: UInt64,
        in registry: inout SessionRegistry,
    ) throws -> RuntimeResult? {
        guard var session = registry[host], session.lease == .launching(lease) else { return nil }
        let decision = RuntimeFreshRunDecisionTable.decide(
            .adapterLaunchFailed,
            on: session.freshRunSnapshot(),
        )
        try applyFreshRunDecision(decision, to: &session)
        if session.stored.projection.isTerminal, session.lease == .launching(lease) {
            session.lease = .none
            session.revision += 1
        }
        registry[host] = session
        return terminalResult(for: session.stored)
    }

    func persistReceiptFailureTransition(
        host: ExternalAgentSessionReference,
        lease: UInt64,
        receipt: RuntimeLaunchReceipt,
        in registry: inout SessionRegistry,
    ) throws -> RuntimeResult? {
        guard var session = registry[host],
              session.stored.runReference == receipt.runReference,
              session.lease == .launching(lease)
        else { return nil }
        let decision = RuntimeFreshRunDecisionTable.decide(
            .receiptPersistFailed,
            on: session.freshRunSnapshot(
                receiptToken: receipt.providerInternalSessionReference.rawValue,
            ),
        )
        try applyFreshRunDecision(decision, to: &session)
        registry[host] = session
        return terminalResult(for: session.stored)
    }

    func persistCallerCancellationTransition(
        host: ExternalAgentSessionReference,
        originatingRunReference: RuntimeRunReference,
        in registry: inout SessionRegistry,
        receipt: RuntimeLaunchReceipt? = nil,
    ) throws {
        guard var session = registry[host],
              session.stored.runReference == originatingRunReference
        else { return }
        let decision = RuntimeFreshRunDecisionTable.decide(
            .callerCancel,
            on: session.freshRunSnapshot(
                receiptToken: receipt?.providerInternalSessionReference.rawValue,
            ),
        )
        try applyFreshRunDecision(decision, to: &session)
        registry[host] = session
    }

    func applyFreshRunDecision(
        _ decision: RuntimeFreshRunDecision,
        to session: inout Session,
    ) throws {
        switch decision {
        case let .persist(projection, attachReceipt, lease):
            if let attachReceipt {
                let providerReference = ProviderInternalSessionReference(attachReceipt)
                if let existing = session.stored.providerInternalSessionReference,
                   existing != providerReference
                {
                    throw RuntimeHostError.malformedAdapterResponse
                }
                session.stored = session.stored.withProviderReference(
                    providerReference,
                    projection: projection,
                )
            } else {
                session.stored = session.stored.withProjection(projection)
            }
            session.lease = lease
            session.revision += 1
        case .adoptPersisted:
            throw RuntimeHostError.persistenceConflict
        case .recordCleanupFailure:
            return
        case .ignore:
            return
        case .throwCancellation:
            throw CancellationError()
        case let .throwHost(error):
            throw error
        }
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
        restoredContext: RuntimeRestoredResumeContext? = nil,
    ) throws -> RuntimeResult? {
        guard var session = registry[host] else { return nil }
        if let restoredContext {
            try requireRestoredResumeContext(
                restoredContext,
                host: host,
                runReference: session.stored.runReference,
                in: registry,
            )
        }
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
