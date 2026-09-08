import Foundation

// MARK: - JSON-RPC Message Types

public enum Message: Codable, Sendable {
    case request(JSONRPCRequest)
    case response(JSONRPCResponse)
    case notification(JSONRPCNotification)

    enum CodingKeys: String, CodingKey {
        case jsonrpc, method, id, params
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let version = try container.decode(String.self, forKey: .jsonrpc)
        guard version == "2.0" else {
            throw DecodingError.dataCorruptedError(
                forKey: .jsonrpc,
                in: container,
                debugDescription: "Unsupported jsonrpc version: \(version)",
            )
        }

        if container.contains(.method) {
            // A message with a method and an `id` key is a request, including `id: null`.
            // A malformed `id` value is rejected instead of being demoted to a notification.
            if container.contains(.id) {
                self = try .request(JSONRPCRequest(from: decoder))
            } else {
                self = try .notification(JSONRPCNotification(from: decoder))
            }
            return
        }

        guard container.contains(.id) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Message has neither `method` nor `id`; not a valid JSON-RPC envelope",
                ),
            )
        }
        self = try .response(JSONRPCResponse(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .request(req):
            try req.encode(to: encoder)
        case let .response(res):
            try res.encode(to: encoder)
        case let .notification(notif):
            try notif.encode(to: encoder)
        }
    }
}

public struct JSONRPCRequest: Codable, Sendable {
    public let jsonrpc: String
    public let id: RequestId
    public let method: String
    public let params: AnyCodable?

    enum CodingKeys: String, CodingKey {
        case jsonrpc, id, method, params
    }

    public init(id: RequestId, method: String, params: AnyCodable?) {
        jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(String.self, forKey: .jsonrpc)
        guard version == "2.0" else {
            throw DecodingError.dataCorruptedError(
                forKey: .jsonrpc,
                in: container,
                debugDescription: "Unsupported jsonrpc version: \(version)",
            )
        }
        jsonrpc = version
        id = try container.decode(RequestId.self, forKey: .id)
        method = try container.decode(String.self, forKey: .method)
        params = try Self.decodeParams(from: container)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("2.0", forKey: .jsonrpc)
        try container.encode(id, forKey: .id)
        try container.encode(method, forKey: .method)
        if let params {
            try Self.validateParamsShape(params, path: encoder.codingPath)
            try container.encode(params, forKey: .params)
        }
    }

    private static func decodeParams(from container: KeyedDecodingContainer<CodingKeys>) throws -> AnyCodable? {
        guard container.contains(.params) else { return nil }
        let params = try container.decode(AnyCodable.self, forKey: .params)
        guard params.value is [String: any Sendable] || params.value is [any Sendable] else {
            throw DecodingError.dataCorruptedError(
                forKey: .params,
                in: container,
                debugDescription: "Request params must be an object or an array",
            )
        }
        return params
    }

    private static func validateParamsShape(_ params: AnyCodable, path: [CodingKey]) throws {
        guard params.value is [String: any Sendable] || params.value is [any Sendable] else {
            throw EncodingError.invalidValue(
                params,
                EncodingError.Context(
                    codingPath: path,
                    debugDescription: "Request params must be an object or an array",
                ),
            )
        }
    }
}

public struct JSONRPCResponse: Codable, Sendable {
    public let jsonrpc: String
    public let id: RequestId
    /// `nil` means the `result` key is absent. A present `result: null` is stored as `AnyCodable(NSNull())`.
    public let result: AnyCodable?
    public let error: JSONRPCError?

    enum CodingKeys: String, CodingKey {
        case jsonrpc, id, result, error
    }

    /// - Note: Creating a response with both or neither of `result`/`error` is a programmer
    ///   error; encoding such a value throws instead of emitting an invalid wire message.
    public init(id: RequestId, result: AnyCodable?, error: JSONRPCError?) {
        jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(String.self, forKey: .jsonrpc)
        guard version == "2.0" else {
            throw DecodingError.dataCorruptedError(
                forKey: .jsonrpc,
                in: container,
                debugDescription: "Unsupported jsonrpc version: \(version)",
            )
        }
        jsonrpc = version
        id = try container.decode(RequestId.self, forKey: .id)

        let hasResult = container.contains(.result)
        let hasError = container.contains(.error)
        guard hasResult != hasError else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Response must contain exactly one of `result` or `error`",
                ),
            )
        }

        if hasResult {
            result = try container.decode(AnyCodable.self, forKey: .result)
            error = nil
        } else {
            result = nil
            error = try container.decode(JSONRPCError.self, forKey: .error)
        }
    }

    public func encode(to encoder: Encoder) throws {
        guard (result != nil) != (error != nil) else {
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Response must have exactly one of `result` or `error`",
                ),
            )
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("2.0", forKey: .jsonrpc)
        try container.encode(id, forKey: .id)
        if let result {
            try container.encode(result, forKey: .result)
        }
        if let error {
            try container.encode(error, forKey: .error)
        }
    }
}

public struct JSONRPCNotification: Codable, Sendable {
    public let jsonrpc: String
    public let method: String
    public let params: AnyCodable?

    enum CodingKeys: String, CodingKey {
        case jsonrpc, method, params, id
    }

    public init(method: String, params: AnyCodable?) {
        jsonrpc = "2.0"
        self.method = method
        self.params = params
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(String.self, forKey: .jsonrpc)
        guard version == "2.0" else {
            throw DecodingError.dataCorruptedError(
                forKey: .jsonrpc,
                in: container,
                debugDescription: "Unsupported jsonrpc version: \(version)",
            )
        }
        guard !container.contains(.id) else {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "Notification must not carry an `id`",
            )
        }
        jsonrpc = version
        method = try container.decode(String.self, forKey: .method)
        if container.contains(.params) {
            let params = try container.decode(AnyCodable.self, forKey: .params)
            guard params.value is [String: any Sendable] || params.value is [any Sendable] else {
                throw DecodingError.dataCorruptedError(
                    forKey: .params,
                    in: container,
                    debugDescription: "Notification params must be an object or an array",
                )
            }
            self.params = params
        } else {
            params = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("2.0", forKey: .jsonrpc)
        try container.encode(method, forKey: .method)
        if let params {
            try container.encode(params, forKey: .params)
        }
    }
}

public struct JSONRPCError: Codable, Sendable, Error {
    public let code: Int
    public let message: String
    public let data: AnyCodable?

    enum CodingKeys: String, CodingKey {
        case code, message, data
    }

    public init(code: Int, message: String, data: AnyCodable?) {
        self.code = code
        self.message = message
        self.data = data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(Int.self, forKey: .code)
        message = try container.decode(String.self, forKey: .message)
        data = try container.decodeIfPresent(AnyCodable.self, forKey: .data)
    }
}

public enum RequestId: Codable, Hashable, CustomStringConvertible, Sendable {
    case string(String)
    case number(Int)
    case null

    public var description: String {
        switch self {
        case let .string(str): str
        case let .number(num): String(num)
        case .null: "null"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let num = try? container.decode(Int.self) {
            self = .number(num)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid RequestId: must be a string, a 64-bit integer, or null",
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(str):
            try container.encode(str)
        case let .number(num):
            try container.encode(num)
        case .null:
            try container.encodeNil()
        }
    }
}

// MARK: - AnyCodable Helper

/// Type-erased JSON value. Decoding accepts any JSON value; encoding rejects values that
/// cannot be represented as JSON instead of silently writing `null`.
public struct AnyCodable: Codable, Sendable {
    public let value: any Sendable

    public init(_ value: any Sendable) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [any Sendable]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: any Sendable]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case is NSNull:
            try container.encodeNil()
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Value of type \(type(of: value)) cannot be encoded as JSON",
                ),
            )
        }
    }
}

// MARK: - Helper for encoding arbitrary keys

public struct AnyCodingKey: CodingKey, Sendable {
    public let stringValue: String
    public let intValue: Int?

    public init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    public init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}
