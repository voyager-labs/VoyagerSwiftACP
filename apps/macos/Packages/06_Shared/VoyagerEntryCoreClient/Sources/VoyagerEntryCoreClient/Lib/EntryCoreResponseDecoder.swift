nonisolated enum EntryCoreDecodedResponse: Equatable {
    case ping(EntryCorePingResult)
    case health(EntryCoreHealthResult)
    case version(EntryCoreVersionResult)
}

nonisolated enum EntryCoreResponseDecoder {
    static func decode(
        _ raw: [UInt8],
        method: EntryCoreMethod,
        expectedRequestID: String,
    ) throws -> EntryCoreDecodedResponse {
        let root: StrictJSONValue
        do {
            root = try StrictJSONParser.parse(raw)
        } catch {
            throw EntryCoreClientError.malformedResponse
        }

        guard case .object = root else {
            throw EntryCoreClientError.protocolMismatch
        }
        guard
            let requestIDValue = root.field(named: "request_id"),
            let okValue = root.field(named: "ok"),
            case let .string(requestID) = requestIDValue,
            requestID.utf8.count <= 128,
            case let .bool(ok) = okValue
        else {
            throw EntryCoreClientError.protocolMismatch
        }

        let fields: [String: StrictJSONValue]
        if ok {
            let expectedFields = ["request_id", "ok", "result"]
            guard let successFields = root.objectFields(exactly: Set(expectedFields)) else {
                throw EntryCoreClientError.protocolMismatch
            }
            fields = successFields
        } else {
            let expectedFields = ["request_id", "ok", "error"]
            guard let errorFields = root.objectFields(exactly: Set(expectedFields)) else {
                throw EntryCoreClientError.protocolMismatch
            }
            fields = errorFields
        }

        guard
            !expectedRequestID.isEmpty,
            requestID.utf8.elementsEqual(expectedRequestID.utf8)
        else {
            throw EntryCoreClientError.requestIDMismatch
        }

        if ok {
            return try decodeResult(fields["result"], method: method)
        }
        try decodeServerError(fields["error"])
    }
}

private extension EntryCoreResponseDecoder {
    static func decodeResult(
        _ value: StrictJSONValue?,
        method: EntryCoreMethod,
    ) throws -> EntryCoreDecodedResponse {
        guard let value else {
            throw EntryCoreClientError.protocolMismatch
        }

        switch method {
        case .ping:
            guard
                let fields = value.objectFields(exactly: ["message"]),
                fields["message"] == .string("pong")
            else {
                throw EntryCoreClientError.protocolMismatch
            }
            return .ping(EntryCorePingResult())
        case .health:
            guard
                let fields = value.objectFields(exactly: ["status", "state"]),
                fields["status"] == .string("healthy"),
                fields["state"] == .string("running")
            else {
                throw EntryCoreClientError.protocolMismatch
            }
            return .health(EntryCoreHealthResult())
        case .version:
            guard
                let fields = value.objectFields(exactly: ["app_version"]),
                case let .string(appVersion)? = fields["app_version"],
                !appVersion.isEmpty
            else {
                throw EntryCoreClientError.protocolMismatch
            }
            return try .version(EntryCoreVersionResult(appVersion: appVersion))
        }
    }

    static func decodeServerError(_ value: StrictJSONValue?) throws -> Never {
        guard
            let value,
            let fields = value.objectFields(exactly: ["code", "message"]),
            case let .string(codeValue)? = fields["code"],
            case let .string(message)? = fields["message"],
            let code = EntryCoreServerErrorCode(rawValue: codeValue),
            message == code.canonicalMessage
        else {
            throw EntryCoreClientError.protocolMismatch
        }
        throw EntryCoreClientError.server(code)
    }
}
