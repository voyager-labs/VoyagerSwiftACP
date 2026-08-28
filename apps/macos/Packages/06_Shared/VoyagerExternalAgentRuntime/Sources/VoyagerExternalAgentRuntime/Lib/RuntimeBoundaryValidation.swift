import Foundation

enum RuntimeBoundaryLimits {
    static let identifierScalars = 256
    static let opaqueProviderHandleScalars = 4096
    static let sensitiveInputScalars = 1_048_576
    static let contextScalars = 4096
    static let requestContextScalars = 1024
    static let allowedRoots = 32
    static let persistedEventEntries = 256
    static let acceptedEventsPerRun = 10000
    static let artifactReferences = 256
    static let artifactReferenceScalars = 4096
    static let persistedSessions = 512
    static let persistenceMutationWaiters = 512
    static let snapshotBytes = 4 * 1024 * 1024
}

extension String {
    var isRuntimeBounded: Bool {
        !isEmpty && unicodeScalars.count <= RuntimeBoundaryLimits.identifierScalars
    }
}

extension RuntimeControlPlane {
    func validatedPersistedState(_ state: RuntimeStoredState) throws -> RuntimeStoredState {
        let validated = try state.validatedForRuntime()
        for session in validated.sessions where session.projection.requiresProviderSessionReference
            && session.providerInternalSessionReference == nil
        {
            throw RuntimeHostError.invalidPersistedState
        }
        return validated
    }

    func validateBoundary(_ request: RuntimeLaunchRequest) throws {
        let context = request.contextPolicy
        guard request.externalAgentSessionReference.rawValue.isRuntimeBounded,
              request.runReference.rawValue.isRuntimeBounded,
              request.adapterID.rawValue.isRuntimeBounded,
              request.input.rawValue.unicodeScalars.count <= RuntimeBoundaryLimits.sensitiveInputScalars,
              context.branchReference.unicodeScalars.count <= RuntimeBoundaryLimits.contextScalars,
              context.localCorrelation.unicodeScalars.count <= RuntimeBoundaryLimits.identifierScalars,
              context.workingDirectory?.unicodeScalars.count ?? 0 <= RuntimeBoundaryLimits.contextScalars,
              context.allowedRoots.count <= RuntimeBoundaryLimits.allowedRoots,
              context.allowedRoots.allSatisfy({
                  $0.unicodeScalars.count <= RuntimeBoundaryLimits.contextScalars
              }),
              context.requestContext?.unicodeScalars.count ?? 0 <= RuntimeBoundaryLimits.requestContextScalars
        else { throw RuntimeHostError.malformedAdapterResponse }
    }

    func validateBoundary(
        _ result: RuntimeResult,
        runReference: RuntimeRunReference,
        outcome: RuntimeOutcome? = nil,
    ) throws {
        guard result.runReference == runReference,
              outcome.map({ result.outcome == $0 }) ?? true,
              result.artifactReferences.count <= RuntimeBoundaryLimits.artifactReferences,
              result.artifactReferences.allSatisfy({
                  $0.unicodeScalars.count <= RuntimeBoundaryLimits.artifactReferenceScalars
              })
        else { throw RuntimeHostError.malformedAdapterResponse }
    }

    func requireAvailableRunReference(
        _ runReference: RuntimeRunReference,
        excluding host: ExternalAgentSessionReference,
        in registry: SessionRegistry,
    ) throws {
        guard !registry.contains(where: { candidateHost, session in
            candidateHost != host && session.stored.runReference == runReference
        }) else { throw RuntimeHostError.duplicateRunReference }
    }
}

extension RuntimeStoredSession {
    var isWithinRuntimeBounds: Bool {
        externalAgentSessionReference.rawValue.isRuntimeBounded
            && runReference.rawValue.isRuntimeBounded
            && adapterID.rawValue.isRuntimeBounded
            && providerNamespace.isRuntimeBounded
            && adapterVersion.unicodeScalars.count <= RuntimeBoundaryLimits.identifierScalars
            && providerInternalSessionReference.map {
                !$0.rawValue.isEmpty
                    && $0.rawValue.unicodeScalars.count <= RuntimeBoundaryLimits.opaqueProviderHandleScalars
            } ?? true
            && acceptedIdempotencyKeys.count <= RuntimeBoundaryLimits.persistedEventEntries
            && acceptedIdempotencyKeys.allSatisfy(\.rawValue.isRuntimeBounded)
            && hostAcceptedIdempotencyKeys.count <= RuntimeBoundaryLimits.persistedEventEntries
            && hostAcceptedIdempotencyKeys.allSatisfy(\.rawValue.isRuntimeBounded)
            && eventEvidence.count <= RuntimeBoundaryLimits.persistedEventEntries
            && eventEvidence.allSatisfy(\.isWithinRuntimeBounds)
            && restorationClaim.map {
                $0.ownerToken.isRuntimeBounded && $0.expiresAt.timeIntervalSince1970.isFinite
            } ?? true
            && acceptedEventCount >= 0
            && acceptedEventCount <= RuntimeBoundaryLimits.acceptedEventsPerRun
            && processedEventCount >= acceptedEventCount
            && processedEventCount <= RuntimeBoundaryLimits.acceptedEventsPerRun
            && hostAcceptedEventCount >= 0
            && hostAcceptedEventCount <= RuntimeBoundaryLimits.acceptedEventsPerRun
            && hostProcessedEventCount >= hostAcceptedEventCount
            && hostProcessedEventCount <= RuntimeBoundaryLimits.acceptedEventsPerRun
            && storedContext.isWithinRuntimeBounds
    }
}

extension RuntimeProjection {
    var requiresProviderSessionReference: Bool {
        switch self {
        case .running, .eventProjected, .eventDuplicateIgnored, .eventOutOfOrder:
            true
        case .policyPending, .policyReady, .launching, .launchBlocked, .launchCancelled,
             .launchFailed, .completed, .failed, .interrupted:
            false
        }
    }
}

extension RuntimeEventEvidence {
    var isWithinRuntimeBounds: Bool {
        switch self {
        case let .ignoredDuplicate(key):
            key.rawValue.isRuntimeBounded
        case .sequenceGap, .staleSequence:
            true
        }
    }
}

extension RuntimeStoredState {
    func validatedForRuntime() throws -> Self {
        if schemaVersion > Self.currentSchemaVersion {
            throw RuntimeStateStoreError.unsupportedSchemaVersion(schemaVersion)
        }
        if schemaVersion < Self.currentSchemaVersion {
            throw RuntimeStateStoreError.unsupportedSchemaVersion(schemaVersion)
        }
        let hosts = Set(sessions.map(\.externalAgentSessionReference))
        let runs = Set(sessions.map(\.runReference))
        guard sessions.count <= RuntimeBoundaryLimits.persistedSessions,
              hosts.count == sessions.count,
              runs.count == sessions.count,
              sessions.allSatisfy(\.isWithinRuntimeBounds)
        else { throw RuntimeStateStoreError.invalidSnapshot }
        return self
    }
}

extension RuntimeOperationID {
    var isWithinRuntimeBounds: Bool {
        rawValue.isRuntimeBounded
    }
}

extension RuntimeApprovalRequestID {
    var isWithinRuntimeBounds: Bool {
        rawValue.isRuntimeBounded
    }
}

extension RuntimeContextPolicy {
    var isWithinRuntimeBounds: Bool {
        branchReference.unicodeScalars.count <= RuntimeBoundaryLimits.contextScalars
            && localCorrelation.unicodeScalars.count <= RuntimeBoundaryLimits.identifierScalars
            && workingDirectory?.unicodeScalars.count ?? 0 <= RuntimeBoundaryLimits.contextScalars
            && allowedRoots.count <= RuntimeBoundaryLimits.allowedRoots
            && allowedRoots.allSatisfy {
                $0.unicodeScalars.count <= RuntimeBoundaryLimits.contextScalars
            }
            && requestContext?.unicodeScalars.count ?? 0 <= RuntimeBoundaryLimits.requestContextScalars
    }
}

extension RuntimeStoredContext {
    var isWithinRuntimeBounds: Bool {
        branchReference.unicodeScalars.count <= RuntimeBoundaryLimits.contextScalars
            && localCorrelation.unicodeScalars.count <= RuntimeBoundaryLimits.identifierScalars
            && executionContextFingerprint.count == 64
            && executionContextFingerprint.allSatisfy {
                switch $0 {
                case "0" ... "9", "a" ... "f": true
                default: false
                }
            }
    }
}
