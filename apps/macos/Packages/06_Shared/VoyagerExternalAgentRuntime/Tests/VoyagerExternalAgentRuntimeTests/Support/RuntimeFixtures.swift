import VoyagerExternalAgentRuntime

func makeLaunch(
    host: ExternalAgentSessionReference,
    run: RuntimeRunReference,
    adapterID: String,
) -> RuntimeLaunchRequest {
    RuntimeLaunchRequest(
        externalAgentSessionReference: host,
        runReference: run,
        adapterID: RuntimeAdapterID(adapterID),
        contextPolicy: RuntimeContextPolicy(
            branchReference: "feat/voy-696",
            authorizationGeneration: 1,
            localCorrelation: "local-a",
        ),
        input: RuntimeSensitiveInput("not persisted"),
    )
}

func runPolicyReady(
    _ plane: RuntimeControlPlane,
    _ request: RuntimeLaunchRequest,
) async throws -> RuntimeResult {
    if await plane.projection(for: request.externalAgentSessionReference) == nil {
        try await plane.projectPrelaunch(request, as: .policyReady)
    }
    return try await plane.run(request)
}

func waitForProjection(
    _ expected: RuntimeProjection,
    host: ExternalAgentSessionReference,
    on plane: RuntimeControlPlane,
) async throws {
    for _ in 0 ..< 200 {
        if await plane.projection(for: host) == expected {
            return
        }
        try await Task.sleep(for: .milliseconds(1))
    }
    throw RuntimeHostError.invalidEvent
}

extension RuntimeCapabilities {
    static var terminalOnly: RuntimeCapabilities {
        RuntimeCapabilities(
            discovery: .supported,
            eventStream: .unsupported,
            approval: .unsupported,
            cancellation: .unknown,
            queuedInput: .unsupported,
            terminalResult: .supported,
        )
    }
}
