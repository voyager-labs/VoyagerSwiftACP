import CryptoKit
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

    @Test
    func `runtime context fingerprint matches byte-exact vectors`() throws {
        let actualFingerprints = Dictionary(
            uniqueKeysWithValues: fingerprintVectors().map {
                ($0.name, characterizedFingerprint(for: $0))
            },
        )

        assertReferencePayloadLayout()

        let nilDigest = try #require(actualFingerprints["nil-values"])
        let emptyRequestDigest = try #require(actualFingerprints["nonnil-empty-request"])
        let orderedDigest = try #require(actualFingerprints["ordered-unicode-roots"])
        let reversedDigest = try #require(actualFingerprints["reversed-unicode-roots"])

        #expect(nilDigest != emptyRequestDigest)
        #expect(orderedDigest != reversedDigest)
        try assertPersistedContextEncoding()
    }

    @Test
    func `derived event copies preserve restoration claim`() {
        var stored = makeRunningSession(
            host: ExternalAgentSessionReference("host-a"),
            run: RuntimeRunReference("run-a"),
            context: makeCanonicalContext(),
        )
        let claim = RuntimeRestorationClaim(
            ownerToken: "owner-copy",
            expiresAt: Date(timeIntervalSince1970: 120),
        )
        stored.restorationClaim = claim

        let withEvidence = stored.withEvidence(.ignoredDuplicate(RuntimeIdempotencyKey("duplicate")))
        let withProviderCount = stored.withProcessedEventCount(3)
        let withHostCount = stored.withHostProcessedEventCount(4)

        #expect(withEvidence.restorationClaim == claim)
        #expect(withEvidence.eventEvidence == [.ignoredDuplicate(RuntimeIdempotencyKey("duplicate"))])
        #expect(withProviderCount.restorationClaim == claim)
        #expect(withProviderCount.processedEventCount == 3)
        #expect(withHostCount.restorationClaim == claim)
        #expect(withHostCount.hostProcessedEventCount == 4)

        for derived in [withEvidence, withProviderCount, withHostCount] {
            #expect(derived.restorationClaim?.ownerToken == claim.ownerToken)
            #expect(derived.restorationClaim?.expiresAt == claim.expiresAt)
        }

        let withoutClaim = makeRunningSession(
            host: ExternalAgentSessionReference("host-nil"),
            run: RuntimeRunReference("run-nil"),
            context: makeCanonicalContext(),
        )
        let nilEvidence = withoutClaim.withEvidence(.ignoredDuplicate(RuntimeIdempotencyKey("duplicate")))
        let nilProviderCount = withoutClaim.withProcessedEventCount(3)
        let nilHostCount = withoutClaim.withHostProcessedEventCount(4)
        #expect(nilEvidence.restorationClaim == nil)
        #expect(nilProviderCount.restorationClaim == nil)
        #expect(nilHostCount.restorationClaim == nil)
    }

    @Test
    func `stored context excludes raw runtime values`() throws {
        let context = makeCanonicalContext()
        let storedContext = RuntimeStoredContext(contextPolicy: context)
        let session = makeRunningSession(
            host: ExternalAgentSessionReference("stored-context-host"),
            run: RuntimeRunReference("stored-context-run"),
            context: context,
            storedContext: storedContext,
        )
        let encoded = try JSONEncoder().encode(session)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let encodedString = try #require(String(data: encoded, encoding: .utf8))

        #expect(object["stored_context"] != nil)
        #expect(!object.keys.contains("context" + "_" + "policy"))
        #expect(!encodedString.contains(context.workingDirectory ?? ""))
        #expect(!encodedString.contains(context.requestContext ?? ""))
    }

    @Test
    func `persisted session equality covers every stored field`() {
        let context = makeCanonicalContext()
        let storedContext = RuntimeStoredContext(contextPolicy: context)
        let baseline = makeEqualitySession(storedContext: storedContext)
        let mutations = [
            makeEqualitySession(storedContext: storedContext, externalAgentSessionReference: "other-host"),
            makeEqualitySession(
                storedContext: storedContext,
                providerInternalSessionReference: ProviderInternalSessionReference("other-provider"),
            ),
            makeEqualitySession(storedContext: storedContext, runReference: RuntimeRunReference("other-run")),
            makeEqualitySession(storedContext: storedContext, adapterID: RuntimeAdapterID("other-adapter")),
            makeEqualitySession(storedContext: storedContext, providerNamespace: "other-provider"),
            makeEqualitySession(storedContext: storedContext, adapterVersion: "2.0.0"),
            makeEqualitySession(storedContext: storedContext, providerBranch: .claudeAgentSDK),
            makeEqualitySession(storedContext: storedContext, capabilitySnapshot: .terminalOnly),
            makeEqualitySession(storedContext: RuntimeStoredContext(contextPolicy: RuntimeContextPolicy(
                branchReference: "other-branch",
                authorizationGeneration: 1,
                localCorrelation: "local-a",
            ))),
            makeEqualitySession(storedContext: storedContext, projection: .completed),
            makeEqualitySession(storedContext: storedContext, providerLaunchAttempted: true),
            makeEqualitySession(storedContext: storedContext, lastSequence: 1),
            makeEqualitySession(storedContext: storedContext, acceptedEventCount: 1),
            makeEqualitySession(storedContext: storedContext, processedEventCount: 1),
            makeEqualitySession(storedContext: storedContext, acceptedIdempotencyKeys: [RuntimeIdempotencyKey("key")]),
            makeEqualitySession(storedContext: storedContext, hostLastSequence: 1),
            makeEqualitySession(storedContext: storedContext, hostAcceptedEventCount: 1),
            makeEqualitySession(storedContext: storedContext, hostProcessedEventCount: 1),
            makeEqualitySession(
                storedContext: storedContext,
                hostAcceptedIdempotencyKeys: [RuntimeIdempotencyKey("host-key")],
            ),
            makeEqualitySession(storedContext: storedContext, eventEvidence: [.sequenceGap(expected: 1, received: 2)]),
            makeEqualitySession(
                storedContext: storedContext,
                restorationClaim: RuntimeRestorationClaim(
                    ownerToken: "owner",
                    expiresAt: Date(timeIntervalSince1970: 1),
                ),
            ),
        ]

        #expect(mutations.count == 21)
        #expect(mutations.allSatisfy { $0 != baseline })
    }

    @Test
    func `stored context rejects malformed fingerprint`() throws {
        for fingerprint in [
            String(repeating: "A", count: 64),
            "short",
            String(repeating: "0", count: 65),
            String(repeating: "g", count: 64),
        ] {
            let data = try JSONSerialization.data(withJSONObject: [
                "branch_reference": "feat/voy-745",
                "authorization_generation": 1,
                "local_correlation": "local-a",
                "execution_context_fingerprint": fingerprint,
            ])
            let context = try JSONDecoder().decode(RuntimeStoredContext.self, from: data)
            #expect(!context.isWithinRuntimeBounds)
        }
    }

    @Test
    func `restart binding retains full caller context in memory`() {
        let context = makeCanonicalContext()
        let binding = RuntimeRestartBinding(
            externalAgentSessionReference: "host-binding",
            providerInternalSessionReference: ProviderInternalSessionReference("provider-binding"),
            runReference: RuntimeRunReference("run-binding"),
            adapterID: RuntimeAdapterID("sdk"),
            providerNamespace: "provider",
            adapterVersion: "1.0.0",
            providerBranch: .claudeAgentSDK,
            capabilitySnapshot: .allSupported,
            contextPolicy: context,
        )

        #expect(binding.contextPolicy == context)
        #expect(binding.contextPolicy.workingDirectory == context.workingDirectory)
        #expect(binding.contextPolicy.allowedRoots == context.allowedRoots)
        #expect(binding.contextPolicy.requestContext == context.requestContext)
    }

    @Test
    func `restart binding defaults provider event sequence to zero`() {
        #expect(makeTechnicalRestartBinding().providerEventSequence == 0)
    }

    @Test
    func `restart binding equality distinguishes provider event sequence`() {
        let first = makeTechnicalRestartBinding()
        let second = makeTechnicalRestartBinding(providerEventSequence: 1)

        #expect(first != second)
        #expect(Set([first, second]).count == 2)
    }

    private struct FingerprintVector {
        let name: String
        let workingDirectory: String?
        let allowedRoots: [String]
        let requestContext: String?
        let expectedDigest: String
    }

    private func fingerprintVectors() -> [FingerprintVector] {
        [
            FingerprintVector(
                name: "nil-values",
                workingDirectory: nil,
                allowedRoots: [],
                requestContext: nil,
                expectedDigest: "709e80c88487a2411e1ee4dfb9f22a861492d20c4765150c0c794abd70f8147c",
            ),
            FingerprintVector(
                name: "nonnil-empty-request",
                workingDirectory: nil,
                allowedRoots: [],
                requestContext: "",
                expectedDigest: "d86a665e460d8579e6efff0602563351c46ccd820732c195c75db4820e1f6f21",
            ),
            FingerprintVector(
                name: "ordered-unicode-roots",
                workingDirectory: "é🙂",
                allowedRoots: ["alpha", "根/🙂"],
                requestContext: "요청",
                expectedDigest: "f91a61ab9558dbcfe0de207eea150b106d075e9e09ef2fc67c281eec04a95803",
            ),
            FingerprintVector(
                name: "reversed-unicode-roots",
                workingDirectory: "é🙂",
                allowedRoots: ["根/🙂", "alpha"],
                requestContext: "요청",
                expectedDigest: "8f125a1999f09eff22a23b3c3aa152fa556cce3a44e5fc9bf65270519871fde6",
            ),
        ]
    }

    private func characterizedFingerprint(for vector: FingerprintVector) -> String {
        let context = RuntimeContextPolicy(
            branchReference: "feat/voy-745",
            authorizationGeneration: 42,
            localCorrelation: "fingerprint-\(vector.name)",
            workingDirectory: vector.workingDirectory,
            allowedRoots: vector.allowedRoots,
            requestContext: vector.requestContext,
        )
        let actualDigest = context.executionContextFingerprint
        let referenceDigest = referenceFingerprint(
            workingDirectory: vector.workingDirectory,
            allowedRoots: vector.allowedRoots,
            requestContext: vector.requestContext,
        )

        print(
            "fingerprint vector \(vector.name): "
                + "production=\(actualDigest) reference=\(referenceDigest)",
        )
        #expect(referenceDigest == vector.expectedDigest)
        #expect(actualDigest == referenceDigest)
        #expect(actualDigest.utf8.count == 64)
        #expect(
            actualDigest.utf8.allSatisfy {
                (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains($0)
                    || (UInt8(ascii: "a") ... UInt8(ascii: "f")).contains($0)
            },
        )
        return actualDigest
    }

    private func assertReferencePayloadLayout() {
        let nilPayload = referenceFingerprintPayload(
            workingDirectory: nil,
            allowedRoots: [],
            requestContext: nil,
        )
        let emptyRequestPayload = referenceFingerprintPayload(
            workingDirectory: nil,
            allowedRoots: [],
            requestContext: "",
        )
        let unicodePayload = referenceFingerprintPayload(
            workingDirectory: "é🙂",
            allowedRoots: ["alpha", "根/🙂"],
            requestContext: "요청",
        )

        #expect(Array(nilPayload) == [0, 0, 0])
        #expect(Array(emptyRequestPayload) == [0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0])
        #expect("é🙂".unicodeScalars.count == 2)
        #expect("é🙂".utf8.count == 6)
        #expect(Array(unicodePayload.dropFirst().prefix(8)) == [0, 0, 0, 0, 0, 0, 0, 6])
    }

    private func assertPersistedContextEncoding() throws {
        let rawWorkingDirectory = "/raw-workdir-voy-745"
        let rawAllowedRoots = ["/raw-root-a-voy-745", "/raw-root-b-voy-745"]
        let rawRequestContext = "raw-request-voy-745"
        let persistedContext = RuntimeStoredContext(contextPolicy: RuntimeContextPolicy(
            branchReference: "feat/voy-745",
            authorizationGeneration: 42,
            localCorrelation: "persistence-characterization",
            workingDirectory: rawWorkingDirectory,
            allowedRoots: rawAllowedRoots,
            requestContext: rawRequestContext,
        ))
        let encoded = try JSONEncoder().encode(persistedContext)
        let encodedObject = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any],
        )
        let encodedString = try #require(String(data: encoded, encoding: .utf8))

        #expect(
            Set(encodedObject.keys) == [
                "authorization_generation",
                "branch_reference",
                "execution_context_fingerprint",
                "local_correlation",
            ],
        )
        #expect(
            encodedObject["execution_context_fingerprint"] as? String
                == persistedContext.executionContextFingerprint,
        )
        for rawValue in [rawWorkingDirectory] + rawAllowedRoots + [rawRequestContext] {
            #expect(!encodedString.contains(rawValue))
        }
    }

    private func referenceFingerprint(
        workingDirectory: String?,
        allowedRoots: [String],
        requestContext: String?,
    ) -> String {
        SHA256.hash(
            data: referenceFingerprintPayload(
                workingDirectory: workingDirectory,
                allowedRoots: allowedRoots,
                requestContext: requestContext,
            ),
        )
        .map { String(format: "%02x", $0) }
        .joined()
    }

    private func referenceFingerprintPayload(
        workingDirectory: String?,
        allowedRoots: [String],
        requestContext: String?,
    ) -> Data {
        var bytes: [UInt8] = []
        appendReferenceOptional(workingDirectory, to: &bytes)
        allowedRoots.forEach { appendReferenceOptional($0, to: &bytes) }
        appendReferenceOptional(nil, to: &bytes)
        appendReferenceOptional(requestContext, to: &bytes)
        return Data(bytes)
    }

    private func appendReferenceOptional(_ value: String?, to bytes: inout [UInt8]) {
        guard let value else {
            bytes.append(0)
            return
        }

        bytes.append(1)
        let encoded = Array(value.utf8)
        var byteCount = UInt64(encoded.count).bigEndian
        withUnsafeBytes(of: &byteCount) { bytes.append(contentsOf: $0) }
        bytes.append(contentsOf: encoded)
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
}

private func makeTechnicalRestartBinding(providerEventSequence: UInt64 = 0) -> RuntimeRestartBinding {
    RuntimeRestartBinding(
        externalAgentSessionReference: "host-binding-technical",
        providerInternalSessionReference: ProviderInternalSessionReference("provider-binding-technical"),
        runReference: RuntimeRunReference("run-binding-technical"),
        adapterID: RuntimeAdapterID("sdk"),
        providerNamespace: "provider",
        adapterVersion: "1.0.0",
        providerBranch: .claudeAgentSDK,
        capabilitySnapshot: .allSupported,
        contextPolicy: RuntimeContextPolicy(
            branchReference: "feat/voy-696",
            authorizationGeneration: 1,
            localCorrelation: "local-a",
        ),
        providerEventSequence: providerEventSequence,
    )
}
