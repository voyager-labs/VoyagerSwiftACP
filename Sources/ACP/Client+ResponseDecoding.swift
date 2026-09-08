import ACPModel
import Foundation

extension Client {
    // MARK: - Response Decoding Helpers

    struct LoadSessionResponsePayload: Decodable {
        let sessionId: SessionId?
        let modes: ModesInfo?
        let models: ModelsInfo?
        let configOptions: [SessionConfigOption]?
    }

    func extractSessionId(from result: AnyCodable?) -> SessionId? {
        guard let value = result?.value else { return nil }

        if let dict = value as? [String: Any] {
            if let id = dict["sessionId"] as? String ?? dict["session_id"] as? String {
                return SessionId(id)
            }
        }

        if let dict = value as? [String: AnyCodable] {
            if let id = dict["sessionId"]?.value as? String ?? dict["session_id"]?.value as? String {
                return SessionId(id)
            }
        }

        return nil
    }

    func decodeResult<T: Decodable>(_ type: T.Type, from response: JSONRPCResponse) throws -> T {
        if let error = response.error {
            throw ClientError.agentError(error)
        }
        guard let result = response.result, !(result.value is NSNull) else {
            throw ClientError.invalidResponse
        }
        let data = try encoder.encode(result)
        return try decoder.decode(type, from: data)
    }

    func decodeEmptyTolerantResponse<T: Decodable>(
        _ type: T.Type,
        from response: JSONRPCResponse,
        emptyValue: @autoclosure () -> T,
    ) throws -> T {
        // A JSON-RPC error response has no result, so the error must win before
        // the empty-result compatibility path can report success.
        if let error = response.error {
            throw ClientError.agentError(error)
        }

        if response.result == nil || (response.result?.value is NSNull) {
            return emptyValue()
        }

        if let dict = response.result?.value as? [String: Any], dict.isEmpty {
            return emptyValue()
        }

        guard let result = response.result else {
            throw ClientError.invalidResponse
        }

        let data = try encoder.encode(result)
        return try decoder.decode(type, from: data)
    }

    func isSessionAlreadyActive(_ error: JSONRPCError) -> Bool {
        let message = error.message.lowercased()
        if message.contains("already active") || message.contains("already started") || message
            .contains("already exists")
        {
            return true
        }

        if let dataString = error.data?.value as? String {
            let lower = dataString.lowercased()
            if lower.contains("already active") || lower.contains("already started") || lower
                .contains("already exists")
            {
                return true
            }
        }

        if let data = error.data?.value as? [String: Any],
           let details = data["details"] as? String
        {
            let lower = details.lowercased()
            if lower.contains("already active") || lower.contains("already started") || lower
                .contains("already exists")
            {
                return true
            }
        }

        return false
    }
}
