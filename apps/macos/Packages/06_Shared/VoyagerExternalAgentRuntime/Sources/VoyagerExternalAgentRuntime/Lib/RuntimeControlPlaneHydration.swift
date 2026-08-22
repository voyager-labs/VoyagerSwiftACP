import Foundation

enum HydrationWaiterOutcome {
    case delivered(Result<RuntimeStoredState?, any Error>)
    case cancelled
}

final class HydrationWaiterExit: @unchecked Sendable {
    private var continuation: CheckedContinuation<HydrationWaiterOutcome, Never>?

    init(_ continuation: CheckedContinuation<HydrationWaiterOutcome, Never>) {
        self.continuation = continuation
    }

    func resumeDelivered(_ result: Result<RuntimeStoredState?, any Error>) {
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: .delivered(result))
        }
    }

    func resumeCancelled() {
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: .cancelled)
        }
    }
}

final class HydrationWaiterExitHolder: @unchecked Sendable {
    private var exit: HydrationWaiterExit?

    func set(_ exit: HydrationWaiterExit) {
        self.exit = exit
    }

    func take() -> HydrationWaiterExit? {
        let current = exit
        exit = nil
        return current
    }
}

extension RuntimeControlPlane {
    func hydrateIfNeeded() async throws {
        guard !hydrated else { return }
        let generation: UInt64
        let task: Task<RuntimeStoredState?, Error>
        if let currentTask = hydrationTask {
            generation = hydrationGeneration
            task = currentTask
        } else {
            hydrationGeneration &+= 1
            generation = hydrationGeneration
            let store = store
            task = Task { try await store.load() }
            hydrationTask = task
        }
        hydrationWaiterCounts[generation, default: 0] += 1
        resumeHydrationWaiterAdmissionContinuations()
        let waiterExitHolder = HydrationWaiterExitHolder()
        let outcome = await withTaskCancellationHandler {
            await suspendHydrationWaiter(
                task: task,
                generation: generation,
                holder: waiterExitHolder,
            )
        } onCancel: {
            Task { await self.finishHydrationWaiterAsCancelled(waiterExitHolder, generation: generation) }
        }
        let result: Result<RuntimeStoredState?, any Error>
        switch outcome {
        case .cancelled:
            if finishHydrationWaiter(generation) {
                hydrationTask = nil
            }
            throw CancellationError()
        case let .delivered(delivered):
            result = delivered
        }
        try await processHydrationDelivery(result, generation: generation)
    }

    private func processHydrationDelivery(
        _ result: Result<RuntimeStoredState?, any Error>,
        generation: UInt64,
    ) async throws {
        hydrationDeliveryOrdinal += 1
        if hydrationDeliveryPauseOrdinal == hydrationDeliveryOrdinal
            || (hydrationDeliveryPauseBackground && Task.currentPriority == .background)
        {
            hydrationDeliveryPauseOrdinal = nil
            hydrationDeliveryPauseBackground = false
            hydrationDeliveryIsPaused = true
            let observers = hydrationPauseObservedContinuations
            hydrationPauseObservedContinuations.removeAll()
            for continuation in observers {
                continuation.resume()
            }
            await withCheckedContinuation { continuation in
                hydrationDeliveryPauseContinuation = continuation
            }
            hydrationDeliveryIsPaused = false
        }
        let isLastWaiter = finishHydrationWaiter(generation)

        if Task.isCancelled {
            if isLastWaiter {
                hydrationTask = nil
            }
            throw CancellationError()
        }

        try handleHydrationResult(result, generation: generation)
    }

    private func suspendHydrationWaiter(
        task: Task<RuntimeStoredState?, Error>,
        generation: UInt64,
        holder: HydrationWaiterExitHolder,
    ) async -> HydrationWaiterOutcome {
        await withCheckedContinuation { continuation in
            if Task.isCancelled {
                continuation.resume(returning: .cancelled)
                return
            }
            let exit = HydrationWaiterExit(continuation)
            holder.set(exit)
            hydrationWaiterExits[generation, default: []].append(exit)
            guard hydrationResultPumps[generation] == nil else { return }
            hydrationResultPumps[generation] = Task { [weak self] in
                await self?.pumpHydrationResults(task: task, generation: generation)
            }
        }
    }

    private func pumpHydrationResults(
        task: Task<RuntimeStoredState?, Error>,
        generation: UInt64,
    ) async {
        let result = await task.result
        hydrationResultPumps.removeValue(forKey: generation)
        let exits = hydrationWaiterExits.removeValue(forKey: generation) ?? []
        for exit in exits {
            exit.resumeDelivered(result)
        }
    }

    func finishHydrationWaiterAsCancelled(_ holder: HydrationWaiterExitHolder, generation: UInt64) {
        guard let exit = holder.take() else { return }
        if var exits = hydrationWaiterExits[generation],
           let index = exits.firstIndex(where: { $0 === exit })
        {
            exits.remove(at: index)
            if exits.isEmpty {
                hydrationWaiterExits.removeValue(forKey: generation)
            } else {
                hydrationWaiterExits[generation] = exits
            }
        }
        exit.resumeCancelled()
    }

    private func finishHydrationWaiter(_ generation: UInt64) -> Bool {
        guard let waiters = hydrationWaiterCounts[generation] else { return false }
        if waiters == 1 {
            hydrationWaiterCounts.removeValue(forKey: generation)
        } else {
            hydrationWaiterCounts[generation] = waiters - 1
        }
        return generation == hydrationGeneration && waiters == 1
    }

    private func clearHydrationTask(ifMatching generation: UInt64) {
        guard generation == hydrationGeneration else { return }
        hydrationTask = nil
    }

    func pauseHydrationDelivery(at ordinal: Int) {
        hydrationDeliveryOrdinal = 0
        hydrationDeliveryPauseOrdinal = ordinal
    }

    func pauseBackgroundHydrationDelivery() {
        hydrationDeliveryPauseBackground = true
    }

    func waitForHydrationWaiters(_ minimum: Int) async {
        guard hydrationWaiterCount < minimum else { return }
        await withCheckedContinuation { continuation in
            hydrationWaiterAdmissionContinuations.append((minimum, continuation))
        }
    }

    func waitForHydrationDeliveryPause() async {
        guard !hydrationDeliveryIsPaused else { return }
        await withCheckedContinuation { continuation in
            hydrationPauseObservedContinuations.append(continuation)
        }
    }

    func resumeHydrationDelivery() {
        hydrationDeliveryPauseContinuation?.resume()
        hydrationDeliveryPauseContinuation = nil
    }

    private func resumeHydrationWaiterAdmissionContinuations() {
        let ready = hydrationWaiterAdmissionContinuations.filter { $0.0 <= hydrationWaiterCount }
        hydrationWaiterAdmissionContinuations.removeAll { $0.0 <= hydrationWaiterCount }
        for (_, continuation) in ready {
            continuation.resume()
        }
    }

    private func handleHydrationResult(
        _ result: Result<RuntimeStoredState?, any Error>,
        generation: UInt64,
    ) throws {
        switch result {
        case let .failure(error):
            try handleHydrationFailure(error, generation: generation)
        case let .success(state):
            try installHydrationState(state, generation: generation)
        }
    }

    private func handleHydrationFailure(_ error: any Error, generation: UInt64) throws {
        if generation == hydrationGeneration {
            hydrationTask = nil
        }
        if error is CancellationError {
            throw CancellationError()
        }
        if let error = error as? RuntimeStateStoreError {
            throw mapStoreError(error)
        }
        throw RuntimeHostError.persistenceFailure
    }

    private func installHydrationState(
        _ state: RuntimeStoredState?,
        generation: UInt64,
    ) throws {
        guard !hydrated else {
            clearHydrationTask(ifMatching: generation)
            return
        }
        do {
            let candidate = try makeHydrationCandidate(state)
            guard generation == hydrationGeneration, hydrationTask != nil else { return }
            sessions = candidate
            hydrated = true
            hydrationInstallCount += 1
            hydrationTask = nil
        } catch is CancellationError {
            clearHydrationTask(ifMatching: generation)
            throw CancellationError()
        } catch let error as RuntimeStateStoreError {
            clearHydrationTask(ifMatching: generation)
            throw mapStoreError(error)
        } catch let error as RuntimeHostError {
            clearHydrationTask(ifMatching: generation)
            throw error
        } catch {
            clearHydrationTask(ifMatching: generation)
            throw RuntimeHostError.invalidPersistedState
        }
    }

    private func makeHydrationCandidate(_ state: RuntimeStoredState?) throws -> SessionRegistry {
        let storedSessions = try state.map(validatedPersistedState)?.sessions ?? []
        return Dictionary(uniqueKeysWithValues: storedSessions.map { stored in
            (stored.externalAgentSessionReference, Session(stored: stored))
        })
    }
}

extension RuntimeStoredSession {
    func withEvidence(_ evidence: RuntimeEventEvidence) -> Self {
        var copy = Self(
            externalAgentSessionReference: externalAgentSessionReference,
            providerInternalSessionReference: providerInternalSessionReference,
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
            eventEvidence: Array(
                (eventEvidence + [evidence]).suffix(RuntimeBoundaryLimits.persistedEventEntries),
            ),
        )
        copy.restorationClaim = restorationClaim
        return copy
    }

    func withProcessedEventCount(_ count: Int) -> Self {
        var copy = Self(
            externalAgentSessionReference: externalAgentSessionReference,
            providerInternalSessionReference: providerInternalSessionReference,
            runReference: runReference,
            adapterID: adapterID,
            adapterVersion: adapterVersion,
            capabilitySnapshot: capabilitySnapshot,
            storedContext: storedContext,
            projection: projection,
            providerLaunchAttempted: providerLaunchAttempted,
            lastSequence: lastSequence,
            acceptedEventCount: acceptedEventCount,
            processedEventCount: count,
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

    func withHostProcessedEventCount(_ count: Int) -> Self {
        var copy = Self(
            externalAgentSessionReference: externalAgentSessionReference,
            providerInternalSessionReference: providerInternalSessionReference,
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
            hostProcessedEventCount: count,
            hostAcceptedIdempotencyKeys: hostAcceptedIdempotencyKeys,
            providerNamespace: providerNamespace,
            providerBranch: providerBranch,
            eventEvidence: eventEvidence,
        )
        copy.restorationClaim = restorationClaim
        return copy
    }
}
