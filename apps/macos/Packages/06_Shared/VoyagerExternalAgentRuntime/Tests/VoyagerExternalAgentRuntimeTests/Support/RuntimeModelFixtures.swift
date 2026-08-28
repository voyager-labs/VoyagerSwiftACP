import Foundation
@testable import VoyagerExternalAgentRuntime

func makeRunningSession(
    host: ExternalAgentSessionReference,
    run: RuntimeRunReference,
    context: RuntimeContextPolicy,
    storedContext: RuntimeStoredContext? = nil,
) -> RuntimeStoredSession {
    RuntimeStoredSession(
        externalAgentSessionReference: host,
        providerInternalSessionReference: ProviderInternalSessionReference("opaque-provider-handle"),
        runReference: run,
        adapterID: RuntimeAdapterID("sdk"),
        adapterVersion: "1.0.0",
        capabilitySnapshot: .allSupported,
        storedContext: storedContext ?? RuntimeStoredContext(contextPolicy: context),
        projection: .running,
        acceptedIdempotencyKeys: [],
    )
}

func makeEqualitySession(
    storedContext: RuntimeStoredContext,
    externalAgentSessionReference: ExternalAgentSessionReference = "equality-host",
    providerInternalSessionReference: ProviderInternalSessionReference? =
        ProviderInternalSessionReference("opaque-provider-handle"),
    runReference: RuntimeRunReference = RuntimeRunReference("equality-run"),
    adapterID: RuntimeAdapterID = RuntimeAdapterID("sdk"),
    providerNamespace: String = "sdk",
    adapterVersion: String = "1.0.0",
    providerBranch: RuntimeProviderBranch = .unknown,
    capabilitySnapshot: RuntimeCapabilities = .allSupported,
    projection: RuntimeProjection = .running,
    providerLaunchAttempted: Bool? = nil,
    lastSequence: UInt64 = 0,
    acceptedEventCount: Int = 0,
    processedEventCount: Int = 0,
    acceptedIdempotencyKeys: [RuntimeIdempotencyKey] = [],
    hostLastSequence: UInt64 = 0,
    hostAcceptedEventCount: Int = 0,
    hostProcessedEventCount: Int = 0,
    hostAcceptedIdempotencyKeys: [RuntimeIdempotencyKey] = [],
    eventEvidence: [RuntimeEventEvidence] = [],
    restorationClaim: RuntimeRestorationClaim? = nil,
) -> RuntimeStoredSession {
    var session = RuntimeStoredSession(
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
        eventEvidence: eventEvidence,
    )
    session.restorationClaim = restorationClaim
    return session
}
