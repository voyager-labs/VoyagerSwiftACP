import Foundation

public struct ExternalAgentSessionReference: Hashable, Codable, Sendable,
    ExpressibleByStringLiteral
{ public let rawValue: String
    public init(_ value: String) {
        rawValue = value
    }

    public init(stringLiteral value: String) {
        rawValue = value
    }
}

public struct ProviderInternalSessionReference: Hashable, Codable, Sendable { public let rawValue: String
    public init(_ value: String) {
        rawValue = value
    }
}

public struct RuntimeRunReference: Hashable, Codable, Sendable { public let rawValue: String
    public init(_ value: String) {
        rawValue = value
    }
}

public struct RuntimeAdapterID: Hashable, Codable, Sendable { public let rawValue: String
    public init(_ value: String) {
        rawValue = value
    }
}

public struct RuntimeIdempotencyKey: Hashable, Codable, Sendable { public let rawValue: String
    public init(_ value: String) {
        rawValue = value
    }
}

public struct ProviderEventID: Hashable, Codable, Sendable { public let rawValue: String
    public init(_ value: String) {
        rawValue = value
    }
}

public struct RuntimeOperationID: Hashable, Codable, Sendable { public let rawValue: String
    public init(_ value: String) {
        rawValue = value
    }
}

public struct RuntimeApprovalRequestID: Hashable, Codable, Sendable { public let rawValue: String
    public init(_ value: String) {
        rawValue = value
    }
}

public struct RuntimeSensitiveInput: Hashable, Sendable { public let rawValue: String
    public init(_ value: String) {
        rawValue = value
    }
}

public struct RuntimeContextPolicy: Hashable, Sendable {
    public let branchReference: String
    public let authorizationGeneration: UInt64
    public let localCorrelation: String
    public let workingDirectory: String?
    public let allowedRoots: [String]
    public let requestContext: String?
    let executionContextFingerprint: String
    public init(
        branchReference: String,
        authorizationGeneration: UInt64,
        localCorrelation: String,
        workingDirectory: String? = nil,
        allowedRoots: [String] = [],
        requestContext: String? = nil,
    ) {
        self.branchReference = branchReference
        self.authorizationGeneration = authorizationGeneration
        self.localCorrelation = localCorrelation
        self.workingDirectory = workingDirectory
        self.allowedRoots = allowedRoots
        self.requestContext = requestContext
        executionContextFingerprint = RuntimeStoredContext.makeExecutionContextFingerprint(
            workingDirectory: workingDirectory,
            allowedRoots: allowedRoots,
            requestContext: requestContext,
        )
    }

    func hasSameRestartIdentity(as other: Self) -> Bool {
        branchReference == other.branchReference
            && authorizationGeneration == other.authorizationGeneration
            && localCorrelation == other.localCorrelation
    }
}

public enum RuntimeTransportKind: String, Codable, Sendable { case processJSONL, sdkAsyncStream }
public enum RuntimeCapability: String, Codable,
    Sendable
{
    case discovery, eventStream, approval, cancellation, queuedInput, terminalResult
    case timeout, sameIdentityResume, reconstruction, explicitArtifact
    case workingDirectory, additionalRoots, authStatusProbe
}

public enum RuntimeCapabilityStatus: String, Codable, Sendable { case supported, unsupported, unknown }
public struct RuntimeCapabilities: Codable, Hashable, Sendable {
    public let discovery, eventStream, approval, cancellation, queuedInput, terminalResult: RuntimeCapabilityStatus
    public let timeout, sameIdentityResume, reconstruction, explicitArtifact: RuntimeCapabilityStatus
    public let workingDirectory, additionalRoots, authStatusProbe: RuntimeCapabilityStatus
    public init(
        discovery: RuntimeCapabilityStatus,
        eventStream: RuntimeCapabilityStatus,
        approval: RuntimeCapabilityStatus,
        cancellation: RuntimeCapabilityStatus,
        queuedInput: RuntimeCapabilityStatus,
        terminalResult: RuntimeCapabilityStatus,
        timeout: RuntimeCapabilityStatus = .unknown,
        sameIdentityResume: RuntimeCapabilityStatus = .unknown,
        reconstruction: RuntimeCapabilityStatus = .unknown,
        explicitArtifact: RuntimeCapabilityStatus = .unknown,
        workingDirectory: RuntimeCapabilityStatus = .unknown,
        additionalRoots: RuntimeCapabilityStatus = .unknown,
        authStatusProbe: RuntimeCapabilityStatus = .unknown,
    ) {
        self.discovery = discovery
        self.eventStream = eventStream
        self.approval = approval
        self.cancellation = cancellation
        self.queuedInput = queuedInput
        self.terminalResult = terminalResult
        self.timeout = timeout
        self.sameIdentityResume = sameIdentityResume
        self.reconstruction = reconstruction
        self.explicitArtifact = explicitArtifact
        self.workingDirectory = workingDirectory
        self.additionalRoots = additionalRoots
        self.authStatusProbe = authStatusProbe
    }

    public subscript(_ capability: RuntimeCapability) -> RuntimeCapabilityStatus {
        switch capability {
        case .discovery:
            discovery
        case .eventStream:
            eventStream
        case .approval:
            approval
        case .cancellation:
            cancellation
        case .queuedInput:
            queuedInput
        case .terminalResult:
            terminalResult
        case .timeout:
            timeout
        case .sameIdentityResume:
            sameIdentityResume
        case .reconstruction:
            reconstruction
        case .explicitArtifact:
            explicitArtifact
        case .workingDirectory:
            workingDirectory
        case .additionalRoots:
            additionalRoots
        case .authStatusProbe:
            authStatusProbe
        }
    }
}

public enum RuntimeProviderBranch: String, Codable, Sendable {
    case codexStableJSON = "codex_stable_json"
    case claudeAgentSDK = "claude_agent_sdk"
    case hermesFinalText = "hermes_final_text"
    case hermesACPVersionGated = "hermes_acp_version_gated"
    case stable, preview, nightly, unknown
}

public struct RuntimeAdapterDescriptor: Codable, Hashable, Sendable {
    public let id: RuntimeAdapterID
    public let providerNamespace: String
    public let adapterVersion: String
    public let transport: RuntimeTransportKind
    public let capabilities: RuntimeCapabilities
    public let providerBranch: RuntimeProviderBranch
    public init(
        id: RuntimeAdapterID,
        providerNamespace: String,
        adapterVersion: String,
        transport: RuntimeTransportKind,
        capabilities: RuntimeCapabilities,
        providerBranch: RuntimeProviderBranch = .unknown,
    ) {
        self.id = id
        self.providerNamespace = providerNamespace
        self.adapterVersion = adapterVersion
        self.transport = transport
        self.capabilities = capabilities
        self.providerBranch = providerBranch
    }
}

public enum RuntimeDiscoveryReadiness: String, Codable, Sendable { case ready, unavailable, unknown }
public struct RuntimeDiscoveryMetadata: Codable, Sendable, Hashable { public let readiness: RuntimeDiscoveryReadiness
    public let diagnosticCode: RuntimeDiagnosticCode?
    public init(readiness: RuntimeDiscoveryReadiness, diagnosticCode: RuntimeDiagnosticCode?) {
        self.readiness = readiness
        self.diagnosticCode = diagnosticCode
    }
}
