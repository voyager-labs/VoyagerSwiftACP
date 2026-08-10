import Foundation
import Testing
@testable import VoyagerExternalAgentRuntime

@Suite("RuntimeModelTechnicalTests")
struct RuntimeModelTechnicalTests {
    @Test
    func `decoded diagnostic codes remain bounded`() throws {
        let diagnostic = try JSONDecoder().decode(
            RuntimeDiagnosticCode.self,
            from: Data(#""/Users/private/token=secret""#.utf8),
        )
        let failure = try JSONDecoder().decode(
            RuntimeAdapterFailure.self,
            from: Data(
                #"{"kind":"transportLoss","diagnosticCode":"/Users/private/token=secret"}"#.utf8,
            ),
        )

        #expect(diagnostic.rawValue == "adapter_failure")
        #expect(failure.diagnosticCode.rawValue == "adapter_failure")
    }

    @Test
    func `canonical launch snapshot and provider branches are representable`() {
        let context = makeCanonicalContext()

        #expect(context.workingDirectory == "/tmp/workspace")

        #expect(context.allowedRoots == ["/tmp/workspace"])

        #expect(context.requestContext == "content-tab")

        #expect(RuntimeProviderBranch.codexStableJSON.rawValue == "codex_stable_json")

        #expect(RuntimeProviderBranch.claudeAgentSDK.rawValue == "claude_agent_sdk")

        #expect(RuntimeProviderBranch.hermesFinalText.rawValue == "hermes_final_text")
    }

    private func makeCanonicalContext() -> RuntimeContextPolicy {
        RuntimeContextPolicy(
            branchReference: "feat/voy-696",

            authorizationGeneration: 1,

            localCorrelation: "local-a",

            workingDirectory: "/tmp/workspace",

            allowedRoots: ["/tmp/workspace"],

            requestContext: "content-tab",
        )
    }

    private func makeRunningSession(
        host: ExternalAgentSessionReference,

        run: RuntimeRunReference,

        context: RuntimeContextPolicy,

    ) -> RuntimeStoredSession {
        RuntimeStoredSession(
            externalAgentSessionReference: host,

            providerInternalSessionReference: ProviderInternalSessionReference("opaque-provider-handle"),

            runReference: run,

            adapterID: RuntimeAdapterID("sdk"),

            adapterVersion: "1.0.0",

            capabilitySnapshot: .allSupported,

            contextPolicy: context,

            projection: .running,

            lastSequence: 0,

            acceptedIdempotencyKeys: [],
        )
    }

    private func makeHostProgress(
        host: ExternalAgentSessionReference,

        run: RuntimeRunReference,

        sequence: UInt64,

    ) -> RuntimeEventEnvelope {
        RuntimeEventEnvelope(
            source: .host,

            providerEventID: ProviderEventID("host-progress-\(sequence)"),

            sequence: sequence,

            idempotencyKey: RuntimeIdempotencyKey("progress-\(sequence)"),

            timestamp: Date(timeIntervalSince1970: TimeInterval(sequence)),

            externalAgentSessionReference: host,

            runReference: run,

            kind: .progress,
        )
    }
}
