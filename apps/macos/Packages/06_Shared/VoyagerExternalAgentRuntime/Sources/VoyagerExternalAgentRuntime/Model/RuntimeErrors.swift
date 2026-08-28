import Foundation

public enum RuntimeHostError: Error, Equatable, Sendable {
    case activeRunExists, duplicateRunReference, duplicateAdapterRegistration, adapterNotFound(RuntimeAdapterID)
    case capabilityUnknown(RuntimeCapability), capabilityUnsupported(RuntimeCapability)
    case unsupportedSchemaVersion(Int), persistenceFailure
    case persistenceConflict, invalidPersistedState, invalidEvent
    case malformedAdapterResponse, adapterUnavailable
    case adapterFailure(RuntimeAdapterFailureKind, RuntimeDiagnosticCode)
    case restartIncompatible, staleRestartBinding
}

public enum RuntimeAdapterFailureKind: String, Codable, Sendable {
    case malformedFrame, processExit, sdkException, transportLoss
}

public struct RuntimeDiagnosticCode: RawRepresentable, Codable, Sendable, Hashable {
    public let rawValue: String

    public init(rawValue: String) {
        self.init(rawValue)
    }

    public init(_ value: String) {
        let validScalars = value.unicodeScalars.allSatisfy { scalar in
            (97 ... 122).contains(scalar.value)
                || (48 ... 57).contains(scalar.value)
                || scalar == "_" || scalar == "." || scalar == "-"
        }
        rawValue = !value.isEmpty && value.unicodeScalars.count <= 64 && validScalars
            ? value
            : "adapter_failure"
    }
}

public struct RuntimeAdapterFailure: Error, Codable, Sendable, Equatable {
    public let kind: RuntimeAdapterFailureKind
    public let diagnosticCode: RuntimeDiagnosticCode

    public init(kind: RuntimeAdapterFailureKind, diagnosticCode: RuntimeDiagnosticCode) {
        self.kind = kind
        self.diagnosticCode = diagnosticCode
    }
}
