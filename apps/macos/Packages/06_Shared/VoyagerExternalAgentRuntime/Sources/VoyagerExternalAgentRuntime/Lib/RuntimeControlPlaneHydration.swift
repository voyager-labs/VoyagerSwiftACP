import Foundation

extension RuntimeControlPlane {
    func hydrateIfNeeded() async throws {
        guard !hydrated else { return }
        let task: Task<RuntimeStoredState?, Error>
        if let hydrationTask {
            task = hydrationTask
        } else {
            let store = store
            task = Task { try await store.load() }
            hydrationTask = task
        }
        let state: RuntimeStoredState?
        do {
            state = try await task.value
        } catch let error as RuntimeHostError {
            hydrationTask = nil
            throw error
        } catch {
            hydrationTask = nil
            throw RuntimeHostError.persistenceFailure
        }
        do {
            try await mutateAfterPersistedTransitions { plane in
                guard !plane.hydrated else { return }
                let storedSessions = try state?.validatedForRuntime().sessions ?? []
                for stored in storedSessions {
                    guard plane.sessions[stored.externalAgentSessionReference] == nil else { continue }
                    plane.sessions[stored.externalAgentSessionReference] = Session(stored: stored)
                }
                plane.hydrated = true
                plane.hydrationTask = nil
            }
        } catch {
            hydrationTask = nil
            throw error
        }
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
            contextPolicy: contextPolicy,
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
            contextPolicy: contextPolicy,
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
            contextPolicy: contextPolicy,
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
