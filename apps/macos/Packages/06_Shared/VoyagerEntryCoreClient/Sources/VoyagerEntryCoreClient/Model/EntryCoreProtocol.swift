nonisolated public enum EntryCoreMethod: String, CaseIterable, Equatable, Sendable {
    case ping
    case health
    case version
    case propertyDefinitionList = "property.definition.list"
    case propertyDefinitionCreate = "property.definition.create"
    case propertyDefinitionUpdate = "property.definition.update"
    case propertyDefinitionDisable = "property.definition.disable"
    case propertyOptionCreate = "property.option.create"
    case propertyOptionUpdate = "property.option.update"
    case propertyOptionReorder = "property.option.reorder"
    case propertyOptionDisable = "property.option.disable"
    case propertyAssignmentList = "property.assignment.list"
    case propertyChangePrepare = "property.change.prepare"
    case propertyChangeExecute = "property.change.execute"
    case propertyConditionQuery = "property.condition.query"
}

nonisolated public struct EntryCorePingResult: Equatable, Sendable {
    public let message: String

    public init() {
        message = "pong"
    }
}

nonisolated public struct EntryCoreHealthResult: Equatable, Sendable {
    public let status: String
    public let state: String

    public init() {
        status = "healthy"
        state = "running"
    }
}

nonisolated public struct EntryCoreVersionResult: Equatable, Sendable {
    public let appVersion: String

    public init(appVersion: String) throws {
        guard !appVersion.isEmpty else {
            throw EntryCoreClientError.protocolMismatch
        }

        self.appVersion = appVersion
    }
}

nonisolated public enum EntryCoreServerErrorCode: String, CaseIterable, Equatable, Sendable {
    case requestTooLarge = "request_too_large"
    case invalidRequest = "invalid_request"
    case unknownMethod = "unknown_method"
    case invalidPath = "invalid_path"
    case mountNotFound = "mount_not_found"
    case sourceNotFound = "source_not_found"
    case invalidSelector = "invalid_selector"
    case contextMismatch = "context_mismatch"
    case scopeTooLarge = "scope_too_large"
    case invalidPageToken = "invalid_page_token"
    case permissionDenied = "permission_denied"
    case sourceUnavailable = "source_unavailable"
    case sourceRuntimeUnavailable = "source_runtime_unavailable"
    case sourceDeleted = "source_deleted"
    case entryNotFound = "entry_not_found"
    case unsupported
    case conflict
    case adapterFailure = "adapter_failure"
    case propertyNotFound = "property_not_found"
    case responseTooLarge = "response_too_large"
    case internalError = "internal_error"

    var canonicalMessage: String {
        switch self {
        case .requestTooLarge:
            "request is too large"
        case .invalidRequest:
            "request is invalid"
        case .unknownMethod:
            "method is unknown"
        case .invalidPath:
            "path is invalid"
        case .mountNotFound:
            "mount was not found"
        case .sourceNotFound:
            "source was not found"
        case .invalidSelector:
            "selector is invalid"
        case .contextMismatch:
            "context does not match"
        case .scopeTooLarge:
            "scope is too large"
        case .invalidPageToken:
            "page token is invalid"
        case .permissionDenied:
            "permission was denied"
        case .sourceUnavailable:
            "source is unavailable"
        case .sourceRuntimeUnavailable:
            "source runtime is unavailable"
        case .sourceDeleted:
            "source was deleted"
        case .entryNotFound:
            "entry was not found"
        case .unsupported:
            "operation is unsupported"
        case .conflict:
            "request conflicts with current state"
        case .adapterFailure:
            "adapter failed"
        case .propertyNotFound:
            "property was not found"
        case .responseTooLarge:
            "response is too large"
        case .internalError:
            "internal error"
        }
    }
}
